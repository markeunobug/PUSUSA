#include "../code/lock_indicator.h"

#include "sleep.h"
#include "xgpiops.h"
#include "xparameters.h"

static XGpioPs g_lock_indicator_gpio;
static int g_lock_indicator_ready = 0;

int lock_indicator_init(void)
{
    int status;
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

    XGpioPs_SetDirectionPin(&g_lock_indicator_gpio, LOCK_INDICATOR_PS_PIN, 1U);
    XGpioPs_SetOutputEnablePin(&g_lock_indicator_gpio, LOCK_INDICATOR_PS_PIN, 1U);
    XGpioPs_WritePin(&g_lock_indicator_gpio, LOCK_INDICATOR_PS_PIN, 0U);
    g_lock_indicator_ready = 1;
    return XST_SUCCESS;
}

void lock_indicator_set(int on)
{
    if (g_lock_indicator_ready == 0) {
        return;
    }

    XGpioPs_WritePin(&g_lock_indicator_gpio,
                     LOCK_INDICATOR_PS_PIN,
                     (on != 0) ? 1U : 0U);
}

void lock_indicator_self_test(void)
{
    if (g_lock_indicator_ready == 0) {
        return;
    }

    XGpioPs_WritePin(&g_lock_indicator_gpio, LOCK_INDICATOR_PS_PIN, 1U);
    usleep(100000U);
    XGpioPs_WritePin(&g_lock_indicator_gpio, LOCK_INDICATOR_PS_PIN, 0U);
}
