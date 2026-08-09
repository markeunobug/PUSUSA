#include "lmx2572_bus.h"

#include "app_config.h"
#include "xgpio.h"

static XGpio lmx2572_gpio;
static uint32_t lmx2572_gpio_state;
static int lmx2572_gpio_ready;

static void lmx2572_gpio_commit(void)
{
    XGpio_DiscreteWrite(&lmx2572_gpio,
                        LMX2572_GPIO_OUT_CHANNEL,
                        lmx2572_gpio_state);
}

static void lmx2572_gpio_write_mask(uint32_t mask, int level)
{
    if (level != 0) {
        lmx2572_gpio_state |= mask;
    } else {
        lmx2572_gpio_state &= ~mask;
    }
    lmx2572_gpio_commit();
}

static void lmx2572_short_delay(void)
{
    volatile uint32_t i;

    for (i = 0U; i < LMX2572_GPIO_DELAY_LOOPS; i++) {
    }
}

static void lmx2572_bus_ce_write(LMX2572_Device *dev, int level)
{
    lmx2572_gpio_write_mask(dev->ce_mask, level);
}

static void lmx2572_bus_csb_write(LMX2572_Device *dev, int level)
{
    lmx2572_gpio_write_mask(dev->csb_mask, level);
}

static void lmx2572_bus_sclk_write(LMX2572_Device *dev, int level)
{
    lmx2572_gpio_write_mask(dev->sck_mask, level);
}

static void lmx2572_bus_sdio_write(LMX2572_Device *dev, int level)
{
    lmx2572_gpio_write_mask(dev->sdi_mask, level);
}

int lmx2572_bus_read_mux(LMX2572_Device *dev)
{
    uint32_t mux_state =
        XGpio_DiscreteRead(&lmx2572_gpio, LMX2572_GPIO_MUX_CHANNEL);
    return ((mux_state & dev->mux_mask) != 0U) ? 1 : 0;
}

int lmx2572_bus_gpio_init(void)
{
    int status;

    if (lmx2572_gpio_ready != 0) {
        return XST_SUCCESS;
    }

    status = XGpio_Initialize(&lmx2572_gpio, LMX2572_GPIO_DEVICE_ID);
    if (status != XST_SUCCESS) {
        return status;
    }

    XGpio_SetDataDirection(&lmx2572_gpio,
                           LMX2572_GPIO_OUT_CHANNEL,
                           0x00U);
    XGpio_SetDataDirection(&lmx2572_gpio,
                           LMX2572_GPIO_MUX_CHANNEL,
                           0xFFFFFFFFU);

    lmx2572_gpio_state = 0U;
    lmx2572_gpio_commit();
    lmx2572_gpio_ready = 1;
    return XST_SUCCESS;
}

void lmx2572_bus_set_device_idle(LMX2572_Device *dev)
{
    lmx2572_bus_ce_write(dev, 0);
    lmx2572_bus_sclk_write(dev, 0);
    lmx2572_bus_sdio_write(dev, 0);
    lmx2572_bus_csb_write(dev, 1);
}

void lmx2572_bus_set_enabled(LMX2572_Device *dev, bool enabled)
{
    lmx2572_bus_ce_write(dev, enabled ? 1 : 0);
}

void lmx2572_bus_write_register(LMX2572_Device *dev,
                                uint8_t reg_addr,
                                uint16_t data)
{
    uint32_t tx_data = ((uint32_t)reg_addr << 16) | (uint32_t)data;
    int i;

    lmx2572_bus_sclk_write(dev, 0);
    lmx2572_short_delay();
    lmx2572_bus_sdio_write(dev, 0);
    lmx2572_bus_csb_write(dev, 0);
    lmx2572_short_delay();

    for (i = 0; i < 24; i++) {
        lmx2572_bus_sdio_write(
            dev,
            ((tx_data & ((uint32_t)1 << (23 - i))) != 0U) ? 1 : 0);
        lmx2572_short_delay();
        lmx2572_bus_sclk_write(dev, 1);
        lmx2572_short_delay();
        lmx2572_bus_sclk_write(dev, 0);
        lmx2572_short_delay();
    }

    lmx2572_bus_csb_write(dev, 1);
    lmx2572_short_delay();
}

uint16_t lmx2572_bus_read_register(LMX2572_Device *dev, uint8_t reg_addr)
{
    uint16_t rx_data = 0U;
    uint32_t tx_data = (1UL << 23) | ((uint32_t)reg_addr << 16);
    int i;

    lmx2572_bus_csb_write(dev, 0);
    for (i = 0; i < 8; i++) {
        lmx2572_bus_sclk_write(dev, 0);
        lmx2572_short_delay();
        lmx2572_bus_sdio_write(
            dev,
            ((tx_data & ((uint32_t)1 << (23 - i))) != 0U) ? 1 : 0);
        lmx2572_short_delay();
        lmx2572_bus_sclk_write(dev, 1);
        lmx2572_short_delay();
    }

    for (i = 0; i < 16; i++) {
        lmx2572_bus_sclk_write(dev, 0);
        lmx2572_short_delay();
        rx_data |=
            (uint16_t)((uint16_t)lmx2572_bus_read_mux(dev) << (15 - i));
        lmx2572_bus_sclk_write(dev, 1);
        lmx2572_short_delay();
    }

    lmx2572_bus_csb_write(dev, 1);
    return rx_data;
}
