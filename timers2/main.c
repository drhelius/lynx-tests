#include <lynx.h>
#include <tgi.h>
#include <6502.h>
#include <stdint.h>
#include "util.h"

#define TEST_COUNT 10

extern void run_tests(void);
extern volatile uint8_t g_results[TEST_COUNT];
extern volatile uint8_t g_debug_results[TEST_COUNT];

static const char* k_test_names[TEST_COUNT] =
{
    "T3>T6 ORDER",
    "T6>T3 ORDER",
    "ENABLE PHASE",
    "COUNT PHASE",
    "PRESCALER",
    "T4 PHASE",
    "TIMER READS",
    "TIMER WRITES",
    "MIKEY ACCESS",
    "LINK CASCADE"
};

static void paint_results(void);

void main(void)
{
    run_tests();

    tgi_install(tgi_static_stddrv);
    tgi_init();

    CLI();

    while (tgi_busy()) { }
    tgi_clear();

    paint_results();
    tgi_updatedisplay();

    for (;;) { }
}

static void paint_results(void)
{
    char buf[4];
    int test;

    for (test = 0; test < TEST_COUNT; test++)
    {
        int y = 2 + test * 8;
        const char* result;

        tgi_setcolor(COLOR_YELLOW);
        tgi_outtextxy(9, y, k_test_names[test]);

        if (g_results[test] == 0)
        {
            tgi_setcolor(COLOR_LIGHTGREEN);
            result = "PASS";
        }
        else
        {
            tgi_setcolor(COLOR_RED);
            hex2(buf, g_results[test]);
            result = buf;
        }

        tgi_outtextxy(9 + 9 * 12, y, result);
    }

    tgi_setcolor(COLOR_WHITE);
    for (test = 0; test < TEST_COUNT; test++)
    {
        hex2(buf, g_debug_results[test]);
        tgi_outtextxy(test * 16, 92, buf);
    }
}
