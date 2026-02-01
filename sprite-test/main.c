/*
 * Alpine Games Copy Protection Test
 * 
 * Minimal C entry point - all tests are in assembly.
 * This replicates the exact conditions from Alpine Games:
 * - COLLBAS = $0000, VIDBAS = $0210 (overlapping buffers)
 * - Off-screen sprite with HFLIP
 * - Check what value ends up at specific addresses
 * 
 * Results are displayed as numbers on screen.
 */

#include <lynx.h>
#include <6502.h>
#include <stdint.h>
#include <string.h>

/* Display buffer for showing results */
#define DISPLAY_ADDR        ((uint8_t*)0xC000)
#define SCREEN_WIDTH        160
#define SCREEN_HEIGHT       102
#define BYTES_PER_LINE      80

/* Results from assembly tests stored here */
#define RESULTS_ADDR        ((uint8_t*)0xB000)

/* Mikey registers */
#define MIKEY_DISPCTL       (*(volatile uint8_t*)0xFD92)
#define MIKEY_PBKUP         (*(volatile uint8_t*)0xFD93)
#define MIKEY_DISPADRL      (*(volatile uint8_t*)0xFD94)
#define MIKEY_DISPADRH      (*(volatile uint8_t*)0xFD95)
#define GREEN_PALETTE       ((volatile uint8_t*)0xFDA0)
#define BLUERED_PALETTE     ((volatile uint8_t*)0xFDB0)
#define TIM0_BKUP           (*(volatile uint8_t*)0xFD00)
#define TIM0_CTLA           (*(volatile uint8_t*)0xFD01)
#define TIM2_BKUP           (*(volatile uint8_t*)0xFD08)
#define TIM2_CTLA           (*(volatile uint8_t*)0xFD09)

/* Assembly test function */
extern void run_sprite_tests(void);

/* Simple 4x5 digit font */
static const uint8_t digit_font[16][5] = {
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
    { 0x6, 0x9, 0xF, 0x9, 0x9 },  /* A */
    { 0xE, 0x9, 0xE, 0x9, 0xE },  /* B */
    { 0x7, 0x8, 0x8, 0x8, 0x7 },  /* C */
    { 0xE, 0x9, 0x9, 0x9, 0xE },  /* D */
    { 0xF, 0x8, 0xE, 0x8, 0xF },  /* E */
    { 0xF, 0x8, 0xE, 0x8, 0x8 },  /* F */
};

static void init_display(void)
{
    /* Timer 0 - horizontal line timer */
    TIM0_BKUP = 158;
    TIM0_CTLA = 0x18;  /* reload + count, no interrupt */
    
    /* Timer 2 - vertical line counter */
    TIM2_BKUP = 104;
    TIM2_CTLA = 0x1F;  /* reload + count + link to T0 */
    
    /* Display control: color, 4-bit, enable video DMA */
    MIKEY_DISPCTL = 0x09;
    
    /* Magic P value for 60Hz */
    MIKEY_PBKUP = 41;
    
    /* Set display address */
    MIKEY_DISPADRL = (uint8_t)((uint16_t)DISPLAY_ADDR & 0xFF);
    MIKEY_DISPADRH = (uint8_t)((uint16_t)DISPLAY_ADDR >> 8);
}

static void init_palette(void)
{
    uint8_t i;
    
    for (i = 0; i < 16; ++i) {
        GREEN_PALETTE[i] = 0x00;
        BLUERED_PALETTE[i] = 0x00;
    }
    
    /* Color 1 = Red (fail) */
    BLUERED_PALETTE[1] = 0x0F;
    
    /* Color 2 = Green (pass) */
    GREEN_PALETTE[2] = 0x0F;
    
    /* Color 3 = Yellow (info) */
    GREEN_PALETTE[3] = 0x0F;
    BLUERED_PALETTE[3] = 0x0F;
    
    /* Color 7 = White (text) */
    GREEN_PALETTE[7] = 0x0F;
    BLUERED_PALETTE[7] = 0xFF;
}

static void draw_digit(uint8_t digit, uint8_t x, uint8_t y, uint8_t color)
{
    uint8_t row;
    uint8_t *fb = DISPLAY_ADDR;

    if (digit > 15) digit = 0;

    for (row = 0; row < 5; ++row) {
        uint8_t *line_ptr = fb + ((y + row) * BYTES_PER_LINE) + (x / 2);
        uint8_t pattern = digit_font[digit][row];
        
        line_ptr[0] = ((pattern & 0x8) ? (color << 4) : 0x00) | ((pattern & 0x4) ? color : 0x00);
        line_ptr[1] = ((pattern & 0x2) ? (color << 4) : 0x00) | ((pattern & 0x1) ? color : 0x00);
    }
}

static void draw_hex_byte(uint8_t val, uint8_t x, uint8_t y, uint8_t color)
{
    draw_digit(val >> 4, x, y, color);
    draw_digit(val & 0x0F, x + 6, y, color);
}

static void display_results(void)
{
    uint8_t *results = (uint8_t*)RESULTS_ADDR;
    uint8_t i;
    uint8_t y = 2;
    
    /* Clear display buffer */
    memset(DISPLAY_ADDR, 0x00, SCREEN_WIDTH * SCREEN_HEIGHT / 2);
    
    /* 
     * Results format from assembly (16 bytes per test):
     * 0: test_id
     * 1: target_addr_lo
     * 2: target_addr_hi  
     * 3: value_at_target (the important result!)
     * 4: collision_dep
     * 5: sprctl0
     * 6: hpos_lo
     * 7: hpos_hi
     * 8: hsiz_lo
     * 9: hsiz_hi
     * 10-15: reserved
     */
    
    for (i = 0; i < 16; i++) {
        uint8_t *r = results + (i * 16);
        uint8_t test_id = r[0];
        uint8_t value = r[3];
        uint8_t expected = 5;  /* We expect pen 5 to be written */
        uint8_t color;
        uint8_t x;
        
        if (test_id == 0) break;  /* End of tests */
        
        x = (i % 4) * 40;
        if (i > 0 && (i % 4) == 0)
            y += 8;
        
        /* Test number */
        draw_hex_byte(test_id, x, y+20, 7);
        
        /* Result value - green if matches expected, red otherwise */
        color = (value == expected || (value >> 4) == expected || (value & 0x0F) == expected) ? 2 : 1;
        draw_hex_byte(value, x + 14, y+20, color);
    }
}

void main(void)
{
    SEI();
    
    init_palette();
    init_display();
    
    /* Run all sprite tests (in assembly) */
    run_sprite_tests();
    
    /* Display results */
    display_results();
    
    /* Infinite loop */
    for (;;);
}
