#include <lynx.h>
#include <tgi.h>
#include <6502.h>
#include <stdint.h>
#include "util.h"

#define RESULT_COUNT 20
#define TEST_COUNT 10

extern void run_tests(void);
static void init(void);
static void paint_results(void);
static void paint_debug_results(void);
static void loop_forever(void);

extern volatile uint8_t g_results[RESULT_COUNT];

static const expected_result_t k_expected_results[RESULT_COUNT] =
{
    EXPECT(0x01), EXPECT(0x00),
    EXPECT(0x01), EXPECT(0x00),
    EXPECT(0x01), EXPECT(0x00),
    EXPECT(0x07), EXPECT(0x00),
    EXPECT(0x01), EXPECT(0x00),
    EXPECT(0x01), EXPECT(0x01),
    EXPECT(0x01), EXPECT(0x00),
    EXPECT(0x00), EXPECT(0x00),
    EXPECT(0x01), EXPECT(0x00),
    EXPECT(0x01), EXPECT(0x00),
};

static const char* k_test_names[TEST_COUNT] =
{
    "ACK BEFORE",
    "ACK AFTER",
    "REARM ONCE",
    "REARM STICKY",
    "ACK VALUE",
    "IRQ RESLEEP",
    "IRQ PENDING",
    "IDLE SLEEP",
    "BUS OFF GO",
    "BUS OFF SLEEP"
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
    int test;
    int y = 0;
    int x = 9;
    int result_right = tgi_getxres() - x;

    for (test = 0; test < TEST_COUNT; ++test)
    {
        int result = test * 2;
        int pass = is_valid_result(g_results[result], &k_expected_results[result]) &&
                   is_valid_result(g_results[result + 1], &k_expected_results[result + 1]);

        tgi_setcolor(COLOR_YELLOW);
        tgi_outtextxy(x, y, k_test_names[test]);
        tgi_setcolor(pass ? COLOR_LIGHTGREEN : COLOR_RED);
        tgi_outtextxy(result_right - (int)tgi_gettextwidth("PASS"), y, pass ? "PASS" : "FAIL");
        y += 8;
    }
}

static void paint_debug_results(void)
{
    char buf[5];
    int test;

    tgi_setcolor(COLOR_WHITE);

    for (test = 0; test < TEST_COUNT; ++test)
    {
        int result = test * 2;
        int x = 2 + (test % 5) * 31;
        int y = 84 + (test / 5) * 9;

        hex2(buf, g_results[result]);
        hex2(buf + 2, g_results[result + 1]);
        tgi_outtextxy(x, y, buf);
    }
}

static void loop_forever(void)
{
    tgi_updatedisplay();
    for (;;) ;
}