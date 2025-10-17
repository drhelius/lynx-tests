#include <lynx.h>
#include <tgi.h>
#include <6502.h>
#include <stdint.h>
#include "util.h"

#define RESULT_COUNT 27
#define TEST_COUNT 6

extern void run_tests(void);
static void init(void);
static void paint_results(void);
static void paint_debug_results(void);
static void loop_forever(void);

extern volatile uint8_t g_results[RESULT_COUNT];

static const expected_result_t k_expected_results[RESULT_COUNT] =
{
    EXPECT(0x14, 0x15), EXPECT(0x53, 0x54), EXPECT(0xA9, 0xAA), EXPECT(0x03, 0x04),
    EXPECT(0x02, 0x03, 0x04), EXPECT(0x0D, 0x0E), EXPECT(0x1A, 0x1B), EXPECT(0x01, 0x02),
    EXPECT(0x24, 0x25), EXPECT(0x8F, 0x90), EXPECT(0x1E, 0x1F), EXPECT(0x06, 0x07),
    EXPECT(0x12, 0x13), EXPECT(0x48), EXPECT(0x8F, 0x90), EXPECT(0x03, 0x04),
    EXPECT(0x12, 0x13), EXPECT(0x48), EXPECT(0x8F, 0x90), EXPECT(0x03, 0x04),
    EXPECT(0x07, 0x08), EXPECT(0x46, 0x47), EXPECT(0x08F, 0x90), EXPECT(0x03, 0x04),
    EXPECT(0x00),
    EXPECT(0x00),
    EXPECT(0x00),
};

static const uint8_t k_test_offsets[TEST_COUNT] = { 0, 4, 8, 12, 16, 20 };
static const uint8_t k_test_counts[TEST_COUNT]  = { 4, 4, 4, 4, 4, 4 };

static const char* k_test_names[TEST_COUNT] =
{
    "TXEMPTY IDLE",
    "TXRDY IDLE",
    "TXEMPTY FULL",
    "TXRDY FULL",
    "TIME TO IRQ",
    "TXBRK->TXRDY"
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
    int y = 9 * 8;
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
