#include <lynx.h>
#include <tgi.h>
#include <6502.h>
#include <stdint.h>

#define RESULT_COUNT 16
#define TEST_COUNT 7

extern void run_tests(void);
static void init(void);
static void paint_results(void);
static void hex2(char* out, uint8_t v);

extern volatile uint8_t g_results[RESULT_COUNT];
static const uint8_t k_expected_results[RESULT_COUNT] =
{
    0x00, 0xE9, 0x00, 0x08,
    0x00, 0x01, 0x08, 0x00,
    0x04, 0x08, 0x00, 0x36,
    0x00, 0x01, 0x0D, 0x08,
};

static const uint8_t k_test_offsets[TEST_COUNT] = { 0, 3, 5, 8, 12, 14, 15 };
static const uint8_t k_test_counts[TEST_COUNT]  = { 3, 2, 3, 4, 2, 1, 1 };

static const char* k_test_names[TEST_COUNT] =
{
    "CTLB RD/WR",
    "ONESHOT",
    "ONESHOT+IRQ",
    "RESET-DONE",
    "TDONE BIT",
    "ONESHOT+LNK",
    "TDONE RELOAD"
};

void main(void)
{
    run_tests();
    init();
    paint_results();
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
            if (g_results[off + i] != k_expected_results[off + i])
            {
                pass = 0;
                fail_index = i; // 0-based index within the test
                break; // first failing result
            }
        }

        // Print test name
        tgi_setcolor(COLOR_YELLOW);
        tgi_outtextxy(x, y, k_test_names[t]);

        // Print PASS or failing index
        if (pass)
        {
            tgi_setcolor(COLOR_LIGHTGREEN);
            tgi_outtextxy(x + x_result, y, "PASS");
        }
        else
        {
            // show 1-based failing result number (e.g. "2")
            tgi_setcolor(COLOR_RED);
            // format small number into buf
            if (fail_index + 1 >= 10)
            {
                // unlikely with current counts, but keep generic
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

    tgi_updatedisplay();

    for (;;) ;
}

static void hex2(char* out, uint8_t v)
{
    static const char* H = "0123456789ABCDEF";
    out[0] = H[(v >> 4) & 0x0F];
    out[1] = H[v & 0x0F];
    out[2] = 0;
}