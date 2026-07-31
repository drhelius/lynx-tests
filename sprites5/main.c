#include <lynx.h>
#include <tgi.h>
#include <6502.h>
#include <stdint.h>
#define UTIL_ENABLE_16BIT
#include "util.h"

#define RESULT_COUNT 32
#define TEST_COUNT 8

extern void run_tests(void);
static void init(void);
static void paint_results(void);
static void paint_debug_results(void);
static void loop_forever(void);

extern volatile uint8_t g_results[RESULT_COUNT];

static const expected_range16_t k_expected_timings[TEST_COUNT] =
{
    EXPECT_RANGE16(0x0048, 0x0068),
    EXPECT_RANGE16(0x003B, 0x005B),
    EXPECT_RANGE16(0x0039, 0x0059),
    EXPECT_RANGE16(0x003B, 0x005B),
    EXPECT_RANGE16(0x0043, 0x0063),
    EXPECT_RANGE16(0x0042, 0x0062),
    EXPECT_RANGE16(0x0042, 0x0062),
    EXPECT_RANGE16(0x0044, 0x0064)
};

static const expected_result_t k_expected_crcs[TEST_COUNT * 2] =
{
    EXPECT(0x50), EXPECT(0x4B),
    EXPECT(0x99), EXPECT(0x4B),
    EXPECT(0x69), EXPECT(0x4B),
    EXPECT(0x36), EXPECT(0x4B),
    EXPECT(0x21), EXPECT(0x4B),
    EXPECT(0x4D), EXPECT(0x4B),
    EXPECT(0x14), EXPECT(0x4B),
    EXPECT(0x55), EXPECT(0x4B)
};

static const char* k_test_names[TEST_COUNT] =
{
    "ZOOM OUT .5",
    "ZOOM 16X8",
    "STRETCH +.5",
    "STRETCH -1",
    "TILT +.5",
    "TILT +1",
    "TILT -1",
    "BOTH +1"
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
        uint8_t off = t * 4;
        uint8_t crc_off = t * 2;
        uint16_t timing = g_results[off] | ((uint16_t)g_results[off + 1] << 8);
        int pass = 1;
        int fail_index = -1;

        if (!is_valid_result(g_results[off + 2], &k_expected_crcs[crc_off]))
        {
            pass = 0;
            fail_index = 0;
        }
        else if (!is_valid_result(g_results[off + 3], &k_expected_crcs[crc_off + 1]))
        {
            pass = 0;
            fail_index = 1;
        }
        else if (!is_valid_range16(timing, &k_expected_timings[t]))
        {
            pass = 0;
            fail_index = 2;
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
            buf[0] = '0' + fail_index + 1;
            buf[1] = 0;
            tgi_outtextxy(x + x_result, y, buf);
        }

        y += 9;
    }
}

static void paint_debug_results(void)
{
    char buf[5];
    int i;

    tgi_setcolor(COLOR_WHITE);
    for (i = 0; i < TEST_COUNT; ++i)
    {
        uint8_t off = i * 4;
        uint16_t timing = g_results[off] | ((uint16_t)g_results[off + 1] << 8);
        int x = 4 + (i & 3) * 39;
        int y = 9 * (9 + (i >> 2));

        hex4(buf, timing);
        tgi_outtextxy(x, y, buf);
    }
}

static void loop_forever(void)
{
    tgi_updatedisplay();
    for (;;) ;
}
