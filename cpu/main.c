#include <lynx.h>
#include <tgi.h>
#include <6502.h>
#include <stdint.h>
#include "util.h"

#define RESULT_COUNT 18
#define TEST_COUNT 7

extern void run_tests(void);
static void init(void);
static void paint_results(void);
static void paint_debug_results(void);
static void loop_forever(void);

extern volatile uint8_t g_results[RESULT_COUNT];

static const expected_result_t k_expected_results[RESULT_COUNT] =
{
    /* Test 1: SEI/CLI IRQ latency */
    EXPECT(0x01),                       /* CLI: INC ran before IRQ (value = 1) */
    EXPECT(0x01),                       /* IRQ was actually taken */
    
    /* Test 2: D flag cleared on interrupt */
    EXPECT(0x00),                       /* D flag should be cleared in IRQ handler */
    EXPECT(0x08),                       /* D flag should be restored after RTI */
    
    /* Test 3: BCD arithmetic and flags */
    EXPECT(0x52),                       /* 0x29 + 0x23 = 0x52 in BCD */
    EXPECT(0x06),                       /* 0x29 - 0x23 = 0x06 in BCD */
    EXPECT(0x01),                       /* Carry flag set after $85+$25 */
    EXPECT(0x02),                       /* Z flag set after $99+$01=$00 */
    EXPECT(0x80),                       /* N flag set after $40+$41=$81 */
    
    /* Test 4: BRK is 2 bytes */
    EXPECT(0x02),                       /* PC incremented by 2 (skips signature) */
    EXPECT(0x30),                       /* (hardcoded) B+unused bits always set in P */
    
    /* Test 5: JMP (indirect) page-boundary - 65C02 fix */
    EXPECT(0xBB),                       /* 65C02 correct: 0xBB, NMOS bug: 0x66 */
    
    /* Test 6: Illegal/reserved opcodes behave as NOP (1,2,3-byte) */
    EXPECT(0x03),                       /* Progress: 3 = all tests passed */
    EXPECT(0x00),                       /* Error code: 0 = no error */
    
    /* Test 7: 65SC02 RMB/SMB/BBR/BBS - required on Lynx  */
    EXPECT(0xFE),                       /* RMB0: bit 0 cleared */
    EXPECT(0x01),                       /* SMB0: bit 0 set */
    EXPECT(0x01),                       /* BBR0: branch taken */
    EXPECT(0x01),                       /* BBS0: branch taken */
};

static const uint8_t k_test_offsets[TEST_COUNT] = { 0, 2, 4, 9, 11, 12, 14 };
static const uint8_t k_test_counts[TEST_COUNT]  = { 2, 2, 5, 2, 1, 2, 4 };

static const char* k_test_names[TEST_COUNT] =
{
    "SEI/CLI",
    "D FLAG IRQ",
    "BCD",
    "BRK 2 BYTES",
    "JMP IND FIX",
    "ILLEGAL OPS",
    "RMB/SMB/BBx",
};

void main(void)
{
    run_tests();
    init();
    paint_results();
    paint_debug_results();
    loop_forever();
}

static void init(void)
{
    tgi_install(tgi_static_stddrv);
    tgi_init();

    CLI();

    while (tgi_busy()) { }
    tgi_clear();
}

static void paint_results(void)
{
    char buf[4];
    int t;
    int y = 9;
    int x = 9;
    int x_result = 9 * 12;

    for (t = 0; t < TEST_COUNT; ++t)
    {
        uint8_t off = k_test_offsets[t];
        uint8_t cnt = k_test_counts[t];
        int pass = 1;
        int fail_index = -1;
        int i;

        for (i = 0; i < cnt; ++i)
        {
            if (!is_valid_result(g_results[off + i], &k_expected_results[off + i]))
            {
                pass = 0;
                fail_index = i;
                break;
            }
        }

        tgi_setcolor(COLOR_YELLOW);
        tgi_outtextxy(x, y, k_test_names[t]);

        if (pass)
        {
            tgi_setcolor(COLOR_LIGHTGREEN);
            tgi_outtextxy(x + x_result, y, "PASS");
        }
        else
        {

            tgi_setcolor(COLOR_RED);

            if (fail_index + 1 >= 10)
            {
                buf[0] = '0' + ((fail_index + 1) / 10);
                buf[1] = '0' + ((fail_index + 1) % 10);
                buf[2] = 0;
            }
            else
            {
                buf[0] = '0' + (fail_index + 1);
                buf[1] = 0;
            }

            tgi_outtextxy(x + x_result, y, buf);
        }

        y += 9;
    }
}

static void paint_debug_results(void)
{
    char buf[4];
    int i;
    int y = 9 * 9;
    int x = 0;

    tgi_setcolor(COLOR_WHITE);

    for (i = 0; i < RESULT_COUNT; ++i)
    {
        hex2(buf, g_results[i]);
        tgi_outtextxy(x, y, buf);
        x += 18;

        if ((i + 1) % 9 == 0)
        {
            y += 9;
            x = 0;
        }
    }
}

static void loop_forever(void)
{
    tgi_updatedisplay();
    for (;;) ;
}
