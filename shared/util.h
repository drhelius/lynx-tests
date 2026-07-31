#ifndef UTIL_H
#define UTIL_H

#include <stdint.h>

#define MAX_VALID_VALUES 8

typedef struct {
    uint8_t count;                          // Number of valid values (1-MAX_VALID_VALUES)
    uint8_t values[MAX_VALID_VALUES];       // Valid values
} expected_result_t;

typedef struct {
    uint16_t minimum;
    uint16_t maximum;
} expected_range16_t;

#define VA_ARGS_COUNT(...) VA_ARGS_COUNT_IMPL(__VA_ARGS__, 8, 7, 6, 5, 4, 3, 2, 1)
#define VA_ARGS_COUNT_IMPL(_1, _2, _3, _4, _5, _6, _7, _8, N, ...) N
#define EXPECT(...) {VA_ARGS_COUNT(__VA_ARGS__), {__VA_ARGS__}}
#define EXPECT_RANGE16(min_value, max_value) {min_value, max_value}

static int is_valid_result(uint8_t actual, const expected_result_t* expected)
{
    int i;
    for (i = 0; i < expected->count; ++i)
    {
        if (actual == expected->values[i])
            return 1;
    }
    return 0;
}

#ifdef UTIL_ENABLE_16BIT
static int is_valid_range16(uint16_t actual, const expected_range16_t* expected)
{
    return actual >= expected->minimum && actual <= expected->maximum;
}
#endif

static void hex2(char* out, uint8_t v)
{
    static const char* H = "0123456789ABCDEF";
    out[0] = H[(v >> 4) & 0x0F];
    out[1] = H[v & 0x0F];
    out[2] = 0;
}

#ifdef UTIL_ENABLE_16BIT
static void hex4(char* out, uint16_t v)
{
    hex2(out, (uint8_t)(v >> 8));
    hex2(out + 2, (uint8_t)v);
}
#endif

#endif /* UTIL_H */