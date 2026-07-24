#include "lock_indicator.h"

#include "sleep.h"
#include "xgpiops.h"
#include "xparameters.h"

static XGpioPs g_lock_indicator_gpio;
static int g_lock_indicator_ready = 0;
static int g_activity_indicator_state = 0;

static uint32_t lock_indicator_pin_from_index(uint8_t index)
{
    return LOCK_INDICATOR_FIRST_PS_PIN + (uint32_t)index;
}

static void lock_indicator_write_pin(uint32_t pin, int on)
{
    if (g_lock_indicator_ready == 0) {
        return;
    }

    XGpioPs_WritePin(&g_lock_indicator_gpio, pin, (on != 0) ? 1U : 0U);
}

int lock_indicator_init(void)
{
    int status;
    uint8_t i;
    XGpioPs_Config *config;

    config = XGpioPs_LookupConfig(XPAR_XGPIOPS_0_DEVICE_ID);
    if (config == 0) {
        g_lock_indicator_ready = 0;
        return XST_FAILURE;
    }

    status = XGpioPs_CfgInitialize(&g_lock_indicator_gpio, config, config->BaseAddr);
    if (status != XST_SUCCESS) {
        g_lock_indicator_ready = 0;
        return status;
    }

    for (i = 0U; i < LOCK_INDICATOR_COUNT; i++) {
        uint32_t pin = lock_indicator_pin_from_index(i);

        XGpioPs_SetDirectionPin(&g_lock_indicator_gpio, pin, 1U);
        XGpioPs_SetOutputEnablePin(&g_lock_indicator_gpio, pin, 1U);
        XGpioPs_WritePin(&g_lock_indicator_gpio, pin, 0U);
    }

    g_lock_indicator_ready = 1;
    return XST_SUCCESS;
}

void lock_indicator_set(int on)
{
    g_activity_indicator_state = (on != 0) ? 1 : 0;
    lock_indicator_write_pin(LOCK_INDICATOR_FIRST_PS_PIN, on);
}

void lock_indicator_set_lmx(uint8_t device_index, int on)
{
    uint32_t pin;

    if (device_index >= 3U) {
        return;
    }

    pin = LOCK_INDICATOR_LO0_PS_PIN + (uint32_t)device_index;
    lock_indicator_write_pin(pin, on);
}

void lock_indicator_toggle_activity(void)
{
    g_activity_indicator_state = (g_activity_indicator_state == 0) ? 1 : 0;
    lock_indicator_write_pin(LOCK_INDICATOR_FIRST_PS_PIN, g_activity_indicator_state);
}

void lock_indicator_self_test(void)
{
    uint8_t i;

    if (g_lock_indicator_ready == 0) {
        return;
    }

    for (i = 0U; i < LOCK_INDICATOR_COUNT; i++) {
        lock_indicator_write_pin(lock_indicator_pin_from_index(i), 1);
    }
    usleep(100000U);
    for (i = 0U; i < LOCK_INDICATOR_COUNT; i++) {
        lock_indicator_write_pin(lock_indicator_pin_from_index(i), 0);
    }
    g_activity_indicator_state = 0;
}
