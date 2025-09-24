#include <lynx.h>
#include <tgi.h>
#include <6502.h>
#include <stdint.h>

/* ASM entry point (no args) */
extern void run_tests(void);

/* Results buffer defined in ASM */
extern volatile uint8_t g_results[20];

static void hex2(char* out, uint8_t v)
{
    static const char* H = "0123456789ABCDEF";
    out[0] = H[(v >> 4) & 0x0F];
    out[1] = H[v & 0x0F];
    out[2] = 0;
}

static const char* kTestNames[] = {
    "CTLB", "FF", "00", "DONE", "IRQS",
    "#IRQ", "DONE", "CONT", "#IRQ", "DONE",
    "WAIT" , "STOP", "RUN", "??", "??",
    "??" , "??", "??", "??", "??"
};

void main(void)
{
    /* Run tests first, sin interferencias del driver gráfico */
    SEI();              /* Disable IRQs while the ASM pokes hardware, if needed */
    run_tests();
    CLI();              /* Enable IRQs again */

    tgi_install(tgi_static_stddrv);
    tgi_init();
    CLI();
    while (tgi_busy()) { }
    tgi_clear();
    

    /* Paint results */
    {
        char buf[3];
        int i;
        int y = 0;
        int x = 0;
        for (i = 0; i < 20; ++i)
        {
            hex2(buf, g_results[i]);
            tgi_setcolor(COLOR_YELLOW);
            tgi_outtextxy(x, y, kTestNames[i]);

            tgi_setcolor(COLOR_LIGHTGREEN);
            tgi_outtextxy(x + 45, y, buf);
            y += 9;

            if (i == 9)
            {
                x = 81;
                y = 0;
            }
        }
    }

    tgi_updatedisplay();

    for (;;)
        ;
}