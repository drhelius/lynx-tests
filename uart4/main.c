#include <lynx.h>
#include <tgi.h>
#include <6502.h>
#include <stdint.h>
#include "util.h"

#define RESULT_COUNT 18
#define TEST_COUNT 5

extern uint8_t wait_for_peer(void);
extern void run_tests(void);

static void init(void);
static void paint_waiting(void);
static void paint_role(uint8_t role);
static void paint_results(void);
static void paint_debug_results(void);
static void loop_forever(void);

extern volatile uint8_t g_results[RESULT_COUNT];

static const expected_result_t k_expected_results[RESULT_COUNT] =
{
    EXPECT(0x00),                   /*  0 peer burst bytes (raw)        */
    EXPECT(0x00),                   /*  1 peer burst mismatches         */
    EXPECT(0x00),                   /*  2 peer burst error flags        */
    EXPECT(0x00),                   /*  3 own echo lost with peer       */
    EXPECT(0x00),                   /*  4 own echo count (raw)          */
    EXPECT(0x00),                   /*  5 collision recovery            */
    EXPECT(0x00),                   /*  6 collision flags (raw)         */
    EXPECT(0x00),                   /*  7 peer latched during our frame */
    EXPECT(0x00),                   /*  8 bus frames in window (raw)    */
    EXPECT(0x01),                   /*  9 parity mismatch detected      */
    EXPECT(0x00),                   /* 10 parity match clean            */
    EXPECT(0x00),                   /* 11 role (raw)                    */
    EXPECT(0x00),
    EXPECT(0x00),
    EXPECT(0x00),
    EXPECT(0x00),
    EXPECT(0x00),
    EXPECT(0x00),
};

static const uint8_t k_test_offsets[TEST_COUNT] = { 1, 3, 5, 7, 9 };
static const uint8_t k_test_counts[TEST_COUNT]  = { 2, 1, 1, 1, 2 };

static const char* k_test_names[TEST_COUNT] =
{
    "PEER BURST",
    "OWN ECHO",
    "COLLISION",
    "HALF DUPLEX",
    "PARITY LINK"
};

void main(void)
{
    uint8_t role;

    init();
    paint_waiting();

    role = wait_for_peer();

    tgi_clear();
    paint_role(role);
    tgi_updatedisplay();

    run_tests();

    tgi_clear();
    paint_role(role);
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

static void paint_waiting(void)
{
    tgi_setcolor(COLOR_YELLOW);
    tgi_outtextxy(9, 36, "CONNECT 2ND LYNX");
    tgi_setcolor(COLOR_WHITE);
    tgi_outtextxy(9, 45, "RUN ROM ON BOTH");
    tgi_outtextxy(9, 63, "WAITING...");
    tgi_updatedisplay();
}

static void paint_role(uint8_t role)
{
    tgi_setcolor(COLOR_LIGHTBLUE);
    tgi_outtextxy(9, 0, role ? "MASTER" : "SLAVE");
}

static void paint_results(void)
{
    char buf[4];
    int t;
    int y = 18;
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
