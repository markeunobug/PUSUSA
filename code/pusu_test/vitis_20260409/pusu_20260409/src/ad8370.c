#include "ad8370.h"

#include "app_config.h"
#include <math.h>
#include "sleep.h"
#include "xgpio.h"
#include "xil_printf.h"

static XGpio ad8370_gpio;
static uint32_t ad8370_gpio_state = 0U;
static uint8_t ad8370_current_code = AD8370_DEFAULT_GAIN_CODE;

static void ad8370_gpio_commit(void)
{
    XGpio_DiscreteWrite(&ad8370_gpio, AD8370_GPIO_CHANNEL, ad8370_gpio_state);
}

static void ad8370_set_mask(uint32_t mask, int level)
{
    if (level != 0) {
        ad8370_gpio_state |= mask;
    } else {
        ad8370_gpio_state &= ~mask;
    }

    ad8370_gpio_commit();
}

static void ad8370_short_delay(void)
{
    usleep(1U);
}

float32_t ad8370_get_theoretical_gain_db(uint8_t code)
{
    uint32_t msb = ((uint32_t)code >> 7) & 0x1U;
    uint32_t gain_code = (uint32_t)code & 0x7FU;
    float32_t av;

    if (gain_code == 0U) {
        return -120.0f;
    }

    av = (float32_t)gain_code * 0.055744f * (1.0f + (7.079458f - 1.0f) * (float32_t)msb);
    if (av < 1.0e-12f) {
        av = 1.0e-12f;
    }

    return 20.0f * log10f(av);
}

int ad8370_init(void)
{
    int status;

    status = XGpio_Initialize(&ad8370_gpio, AD8370_GPIO_DEVICE_ID);
    if (status != XST_SUCCESS) {
        return status;
    }

    XGpio_SetDataDirection(&ad8370_gpio, AD8370_GPIO_CHANNEL, 0x0U);

    ad8370_gpio_state = 0U;
    ad8370_gpio_commit();

    ad8370_set_mask(AD8370_GPIO_LTC_MASK, 0);
    ad8370_set_mask(AD8370_GPIO_CLK_MASK, 0);
    ad8370_set_mask(AD8370_GPIO_DATA_MASK, 0);
    ad8370_set_gain_code(AD8370_DEFAULT_GAIN_CODE);

    return XST_SUCCESS;
}

void ad8370_write_code(uint8_t code)
{
    int bit_idx;

    ad8370_set_mask(AD8370_GPIO_LTC_MASK, 0);
    ad8370_set_mask(AD8370_GPIO_CLK_MASK, 0);

    for (bit_idx = 7; bit_idx >= 0; bit_idx--) {
        ad8370_set_mask(AD8370_GPIO_DATA_MASK, (code >> bit_idx) & 0x01U);
        ad8370_short_delay();

        ad8370_set_mask(AD8370_GPIO_CLK_MASK, 1);
        ad8370_short_delay();

        ad8370_set_mask(AD8370_GPIO_CLK_MASK, 0);
        ad8370_short_delay();
    }

    ad8370_set_mask(AD8370_GPIO_LTC_MASK, 1);
    ad8370_short_delay();
    ad8370_set_mask(AD8370_GPIO_LTC_MASK, 0);
    ad8370_short_delay();
}

void ad8370_set_gain_code(uint8_t code)
{
    float32_t gain_db = ad8370_get_theoretical_gain_db(code);

    ad8370_write_code(code);
    ad8370_current_code = code;
#if AD8370_VERBOSE
    xil_printf("AD8370_GAIN,0x%02X,%d,%d dB\r\n",
               (unsigned int)code,
               (int)code,
               (int)gain_db);
#else
    (void)gain_db;
#endif
}

uint8_t ad8370_get_gain_code(void)
{
    return ad8370_current_code;
}

void ad8370_run_startup_test(void)
{
#if AD8370_ENABLE_STARTUP_TEST
    static const uint8_t test_codes[] = {0x00U, 0x20U, 0x80U, 0xFFU};
    uint32_t i;

    xil_printf("AD8370 startup test begin\r\n");

    for (i = 0; i < (sizeof(test_codes) / sizeof(test_codes[0])); i++) {
        ad8370_set_gain_code(test_codes[i]);
        usleep(AD8370_STARTUP_TEST_DELAY_US);
    }

    xil_printf("AD8370 startup test end\r\n");
#endif
}
