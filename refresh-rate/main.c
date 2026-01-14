#include <lynx.h>
#include <6502.h>
#include <stdint.h>
#include <string.h>

#define FRAMEBUFFER_ADDR    ((uint8_t*)0xA000)
#define SCREEN_WIDTH        160
#define SCREEN_HEIGHT       102
#define BYTES_PER_LINE      80

#define DEFAULT_T0_BACKUP   158  /* 60Hz default */
#define MIN_T0_BACKUP       0
#define MAX_T0_BACKUP       255

#define DEFAULT_PBKUP       41   /* 60Hz default */
#define MIN_PBKUP           0
#define MAX_PBKUP           255

#define DEFAULT_T2_BACKUP   104  /* 102 + 3 lines total */
#define MIN_T2_BACKUP       0
#define MAX_T2_BACKUP       255

#define JOYSTICK_REG        (*(volatile uint8_t*)0xFCB0)
#define TIM0_BKUP           (*(volatile uint8_t*)0xFD00)
#define TIM2_BKUP           (*(volatile uint8_t*)0xFD08)
#define PBKUP_REG           (*(volatile uint8_t*)0xFD93)
#define GREEN_PALETTE       ((volatile uint8_t*)0xFDA0)
#define BLUERED_PALETTE     ((volatile uint8_t*)0xFDB0)

#define BTN_UP              0x80
#define BTN_DOWN            0x40
#define BTN_LEFT            0x20
#define BTN_RIGHT           0x10

static uint8_t prev_buttons = 0xFF;
static uint8_t current_t0_backup = DEFAULT_T0_BACKUP;
static uint8_t current_pbkup = DEFAULT_PBKUP;
static uint8_t current_t2_backup = DEFAULT_T2_BACKUP;

extern void install_isrs(void);
extern void remove_isrs(void);
extern void init_display(void);

static const uint8_t digit_font[10][5] = {
    { 0x6, 0x9, 0x9, 0x9, 0x6 },  /* 0 */
    { 0x2, 0x6, 0x2, 0x2, 0x7 },  /* 1 */
    { 0x6, 0x9, 0x2, 0x4, 0xF },  /* 2 */
    { 0xE, 0x1, 0x6, 0x1, 0xE },  /* 3 */
    { 0x9, 0x9, 0xF, 0x1, 0x1 },  /* 4 */
    { 0xF, 0x8, 0xE, 0x1, 0xE },  /* 5 */
    { 0x6, 0x8, 0xE, 0x9, 0x6 },  /* 6 */
    { 0xF, 0x1, 0x2, 0x4, 0x4 },  /* 7 */
    { 0x6, 0x9, 0x6, 0x9, 0x6 },  /* 8 */
    { 0x6, 0x9, 0x7, 0x1, 0x6 },  /* 9 */
};

static void draw_digit(uint8_t digit, uint8_t x, uint8_t y)
{
    uint8_t row;
    uint8_t *fb = FRAMEBUFFER_ADDR;

    if (digit > 9) digit = 0;

    for (row = 0; row < 5; ++row)
    {
        uint8_t *line_ptr = fb + ((y + row) * BYTES_PER_LINE) + (x / 2);
        uint8_t pattern = digit_font[digit][row];
        
        /* Draw 4 pixels (2 bytes) using color 2 (yellow) */
        /* Pixel order in byte: high nibble = left pixel, low nibble = right pixel */
        line_ptr[0] = ((pattern & 0x8) ? 0x20 : 0x00) | ((pattern & 0x4) ? 0x02 : 0x00);
        line_ptr[1] = ((pattern & 0x2) ? 0x20 : 0x00) | ((pattern & 0x1) ? 0x02 : 0x00);
    }
}

static void draw_number_3(uint8_t value, uint8_t x, uint8_t y)
{
    draw_digit(value / 100, x, y);
    draw_digit((value / 10) % 10, x + 6, y);
    draw_digit(value % 10, x + 12, y);
}

static void draw_number_2(uint8_t value, uint8_t x, uint8_t y)
{
    draw_digit(value / 10, x, y);
    draw_digit(value % 10, x + 6, y);
}

static void clear_area(uint8_t x, uint8_t y, uint8_t width, uint8_t height)
{
    uint8_t row, col;
    uint8_t *fb = FRAMEBUFFER_ADDR;
    uint8_t byte_width = width / 2;

    for (row = 0; row < height; ++row)
    {
        uint8_t *line_ptr = fb + ((y + row) * BYTES_PER_LINE) + (x / 2);
        for (col = 0; col < byte_width; ++col)
        {
            line_ptr[col] = 0x00;
        }
    }
}

static void update_display(void)
{
    clear_area(50, 42, 60, 16);

    draw_number_3(current_t0_backup, 56, 44);
    draw_number_3(current_pbkup, 84, 44);

    draw_number_3(current_t2_backup, 70, 51);
}

static uint8_t calculate_pbkup(uint8_t backup)
{
    /* line_time = backup + 1 (in us)
     * pbkup = ((line_time - 0.5) / 15) * 4 - 1
     * Multiply by 2 to avoid floating point:
     * pbkup = ((2*line_time - 1) / 30) * 4 - 1
     * = ((2*(backup+1) - 1) * 4 / 30) - 1
     * = ((2*backup + 1) * 4 / 30) - 1
     * = ((2*backup + 1) * 2 / 15) - 1
     */
    uint16_t numerator = ((uint16_t)(backup + 1) * 2 - 1) * 4;
    uint8_t pbkup = (uint8_t)(numerator / 30) - 1;
    return pbkup;
}

static void init_palette(void)
{
    uint8_t i;

    for (i = 0; i < 16; ++i)
    {
        GREEN_PALETTE[i] = 0x00;
        BLUERED_PALETTE[i] = 0x00;
    }

    /* Color 1 red */
    GREEN_PALETTE[1] = 0x00;
    BLUERED_PALETTE[1] = 0x0F;

    /* Color 2 yellow */
    GREEN_PALETTE[2] = 0x0F;
    BLUERED_PALETTE[2] = 0x0F;
}

static void create_checkerboard(void)
{
    uint8_t *fb = FRAMEBUFFER_ADDR;
    uint16_t line;
    uint8_t col;

    for (line = 0; line < SCREEN_HEIGHT; ++line)
    {
        uint8_t *line_ptr = fb + (line * BYTES_PER_LINE);
        uint8_t pattern1, pattern2;
        
        if ((line / 2) & 1)
        {
            pattern1 = 0x00;
            pattern2 = 0x11;
        }
        else
        {
            pattern1 = 0x11;
            pattern2 = 0x00;
        }

        for (col = 0; col < BYTES_PER_LINE; col += 2)
        {
            line_ptr[col] = pattern1;
            line_ptr[col + 1] = pattern2;
        }
    }
}

static uint8_t button_pressed(uint8_t button_mask, uint8_t current, uint8_t previous)
{
    /* Button is active low */
    uint8_t was_released = (previous & button_mask);
    uint8_t is_pressed = !(current & button_mask);

    return was_released && is_pressed;
}

void main(void)
{

    SEI();

    init_palette();
    create_checkerboard();
    init_display();

    current_pbkup = calculate_pbkup(current_t0_backup);

    update_display();

    install_isrs();

    CLI();

    for (;;)
    {
        uint8_t buttons = JOYSTICK_REG;
        uint8_t new_t0_backup = current_t0_backup;
        uint8_t new_pbkup = current_pbkup;
        uint8_t changed = 0;

        if (button_pressed(BUTTON_INNER, buttons, prev_buttons))
        {
            if (current_t0_backup > MIN_T0_BACKUP)
            {
                new_t0_backup = current_t0_backup - 1;
                new_pbkup = calculate_pbkup(new_t0_backup);
                changed = 1;
            }
        }

        if (button_pressed(BUTTON_OUTER, buttons, prev_buttons))
        {
            if (current_t0_backup < MAX_T0_BACKUP)
            {
                new_t0_backup = current_t0_backup + 1;
                new_pbkup = calculate_pbkup(new_t0_backup);
                changed = 1;
            }
        }

        if (button_pressed(BTN_UP, buttons, prev_buttons))
        {
            if (current_pbkup < MAX_PBKUP)
            {
                new_pbkup = current_pbkup + 1;
                changed = 1;
            }
        }

        if (button_pressed(BTN_DOWN, buttons, prev_buttons))
        {
            if (current_pbkup > MIN_PBKUP)
            {
                new_pbkup = current_pbkup - 1;
                changed = 1;
            }
        }

        if (button_pressed(BTN_RIGHT, buttons, prev_buttons))
        {
            if (current_t2_backup < MAX_T2_BACKUP)
            {
                current_t2_backup++;
                TIM2_BKUP = current_t2_backup;
                changed = 1;
            }
        }

        if (button_pressed(BTN_LEFT, buttons, prev_buttons))
        {
            if (current_t2_backup > MIN_T2_BACKUP)
            {
                current_t2_backup--;
                TIM2_BKUP = current_t2_backup;
                changed = 1;
            }
        }

        if (changed)
        {
            SEI();
            
            if (new_t0_backup != current_t0_backup)
            {
                current_t0_backup = new_t0_backup;
                TIM0_BKUP = current_t0_backup;
            }
            
            if (new_pbkup != current_pbkup)
            {
                current_pbkup = new_pbkup;
                PBKUP_REG = current_pbkup;
            }

            CLI();

            update_display();
        }

        prev_buttons = buttons;
    }
}
