#include "../code/lmx2572.h"

#include <math.h>
#include <string.h>

#include "sleep.h"
#include "xgpio.h"
#include "../code/app_config.h"

static const uint16_t lmx2572_reg_default[126] = {
    0x2288, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
    0x0000, 0x0000, 0x0000, 0x7802, 0x0000, 0x0000, 0x0000, 0x0000,
    0x0000, 0x0000, 0x0000, 0x0007, 0x4440, 0x2580, 0x0000, 0x0000,
    0x0000, 0x2580, 0x8E38, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
    0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x5325,
    0xEBD5, 0x0001, 0xACD7, 0x3F2A, 0x0000, 0x0000, 0x0050, 0x0001,
    0x0000, 0x000C, 0x08C0, 0x0000, 0x003F, 0x0001, 0x0081, 0xC350,
    0x0000, 0x03E8, 0x0000, 0x01F4, 0x0000, 0x1388, 0x0000, 0x00AF,
    0x00A8, 0x03E8, 0x0001, 0x9001, 0x0020, 0x0000, 0x0000, 0x0000,
    0x0000, 0x0421, 0x0080, 0x0080, 0x4180, 0x03E0, 0x0300, 0x07F0,
    0xC61E, 0x1E63, 0x0000, 0x0000, 0x0000, 0x0000, 0x03E8, 0x0000,
    0x0205, 0x0028, 0x0004, 0x0010, 0x1E01, 0x05BF, 0xC3E6, 0x18A6,
    0x0000, 0x0488, 0x0002, 0x0808, 0x0624, 0x071A, 0x007C, 0x0001,
    0x0409, 0x4848, 0x27B7, 0x0064, 0x0096, 0x0080, 0x060E, 0x1820,
    0x4000, 0x5001, 0xB018, 0x1278, 0x0004, 0x2000, 0x00B2, 0xC802,
    0x20C8, 0x0A43, 0x0782, 0x0500, 0x0808, 0x2318
};

static XGpio lmx2572_gpio;
static uint32_t lmx2572_gpio_state;
static int lmx2572_gpio_ready;
static LMX2572_Device lmx2572_dev1;
static LMX2572_Device lmx2572_dev2;

static void lmx2572_gpio_commit(void)
{
    XGpio_DiscreteWrite(&lmx2572_gpio, LMX2572_GPIO_OUT_CHANNEL, lmx2572_gpio_state);
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

static void lmx2572_delay_ms(uint32_t delay_ms)
{
    usleep(delay_ms * 1000U);
}

static void LMX2572_CE_Write(LMX2572_Device *dev, int level)
{
    lmx2572_gpio_write_mask(dev->ce_mask, level);
}

static void LMX2572_CSB_Write(LMX2572_Device *dev, int level)
{
    lmx2572_gpio_write_mask(dev->csb_mask, level);
}

static void LMX2572_SCLK_Write(LMX2572_Device *dev, int level)
{
    lmx2572_gpio_write_mask(dev->sck_mask, level);
}

static void LMX2572_SDIO_Write(LMX2572_Device *dev, int level)
{
    lmx2572_gpio_write_mask(dev->sdi_mask, level);
}

static int LMX2572_MUX_Read(LMX2572_Device *dev)
{
    uint32_t mux_state = XGpio_DiscreteRead(&lmx2572_gpio, LMX2572_GPIO_MUX_CHANNEL);

    return ((mux_state & dev->mux_mask) != 0U) ? 1 : 0;
}

int LMX2572_GpioInit(void)
{
    int status;

    if (lmx2572_gpio_ready != 0) {
        return XST_SUCCESS;
    }

    status = XGpio_Initialize(&lmx2572_gpio, LMX2572_GPIO_DEVICE_ID);
    if (status != XST_SUCCESS) {
        return status;
    }

    XGpio_SetDataDirection(&lmx2572_gpio, LMX2572_GPIO_OUT_CHANNEL, 0x00U);
    XGpio_SetDataDirection(&lmx2572_gpio, LMX2572_GPIO_MUX_CHANNEL, 0xFFFFFFFFU);

    lmx2572_gpio_state = 0U;
    lmx2572_gpio_commit();
    lmx2572_gpio_ready = 1;
    return XST_SUCCESS;
}

void LMX2572_Device_Init(LMX2572_Device *dev,
                         uint32_t ce_mask,
                         uint32_t csb_mask,
                         uint32_t sck_mask,
                         uint32_t sdi_mask,
                         uint32_t mux_mask)
{
    dev->ce_mask = ce_mask;
    dev->csb_mask = csb_mask;
    dev->sck_mask = sck_mask;
    dev->sdi_mask = sdi_mask;
    dev->mux_mask = mux_mask;
    dev->fpd_hz = 0.0;
    memcpy(dev->reg_config, lmx2572_reg_default, sizeof(dev->reg_config));

    LMX2572_CE_Write(dev, 0);
    LMX2572_SCLK_Write(dev, 0);
    LMX2572_SDIO_Write(dev, 0);
    LMX2572_CSB_Write(dev, 1);
}

void LMX2572_WriteRegister(LMX2572_Device *dev, uint8_t reg_addr, uint16_t data)
{
    uint32_t tx_data = ((uint32_t)reg_addr << 16) | (uint32_t)data;
    int i;

    LMX2572_SCLK_Write(dev, 0);
    lmx2572_short_delay();
    LMX2572_SDIO_Write(dev, 0);

    LMX2572_CSB_Write(dev, 0);
    lmx2572_short_delay();

    for (i = 0; i < 24; i++) {
        LMX2572_SDIO_Write(dev, ((tx_data & ((uint32_t)1 << (23 - i))) != 0U) ? 1 : 0);
        lmx2572_short_delay();

        LMX2572_SCLK_Write(dev, 1);
        lmx2572_short_delay();

        LMX2572_SCLK_Write(dev, 0);
        lmx2572_short_delay();
    }

    LMX2572_CSB_Write(dev, 1);
    lmx2572_short_delay();

    if (reg_addr < 126U) {
        if (reg_addr == 0U) {
            if ((data & 0x0002U) != 0U) {
                dev->reg_config[125] = data & 0xFFFDU;
            } else {
                dev->reg_config[125] = data;
            }
        } else {
            dev->reg_config[125U - reg_addr] = data;
        }
    }
}

uint16_t LMX2572_ReadRegister(LMX2572_Device *dev, uint8_t reg_addr)
{
    uint16_t rx_data = 0U;
    uint32_t tx_data = (1UL << 23) | ((uint32_t)reg_addr << 16);
    int i;

    LMX2572_CSB_Write(dev, 0);

    for (i = 0; i < 8; i++) {
        LMX2572_SCLK_Write(dev, 0);
        lmx2572_short_delay();
        LMX2572_SDIO_Write(dev, ((tx_data & ((uint32_t)1 << (23 - i))) != 0U) ? 1 : 0);
        lmx2572_short_delay();
        LMX2572_SCLK_Write(dev, 1);
        lmx2572_short_delay();
    }

    for (i = 0; i < 16; i++) {
        LMX2572_SCLK_Write(dev, 0);
        lmx2572_short_delay();
        rx_data |= (uint16_t)((uint16_t)LMX2572_MUX_Read(dev) << (15 - i));
        LMX2572_SCLK_Write(dev, 1);
        lmx2572_short_delay();
    }

    LMX2572_CSB_Write(dev, 1);
    return rx_data;
}

void LMX2572_Reset(LMX2572_Device *dev)
{
    LMX2572_WriteRegister(dev, 0x00U, dev->reg_config[125] | 0x0002U);
    lmx2572_delay_ms(10U);
}

void LMX2572_SetEnabled(LMX2572_Device *dev, bool enabled)
{
    LMX2572_CE_Write(dev, enabled ? 1 : 0);
}

void LMX2572_Init(LMX2572_Device *dev)
{
    LMX2572_CE_Write(dev, 1);
    lmx2572_delay_ms(10U);
    LMX2572_Reset(dev);
    lmx2572_delay_ms(10U);

    LMX2572_WriteRegister(dev, 0, 0x231c);
    LMX2572_WriteRegister(dev, 29, 0x0000);
    LMX2572_WriteRegister(dev, 30, 0x18A6);
    LMX2572_WriteRegister(dev, 34, 0x0010);
    LMX2572_WriteRegister(dev, 36, 0x0029);
    LMX2572_WriteRegister(dev, 37, 0x0205);
    LMX2572_WriteRegister(dev, 38, 0x0000);
    LMX2572_WriteRegister(dev, 39, 0x03E8);
    LMX2572_WriteRegister(dev, 52, 0x0421);
    LMX2572_WriteRegister(dev, 57, 0x0020);
    LMX2572_WriteRegister(dev, 71, 0x0081);
    LMX2572_WriteRegister(dev, 78, 0x0001);
}

void LMX2572_Init_Block(LMX2572_Device *dev)
{
    int reg_idx;

    LMX2572_CE_Write(dev, 1);
    lmx2572_delay_ms(50U);
    LMX2572_Reset(dev);
    lmx2572_delay_ms(50U);

    for (reg_idx = 0; reg_idx < 126; reg_idx++) {
        LMX2572_WriteRegister(dev, (uint8_t)reg_idx, dev->reg_config[125 - reg_idx]);
    }
}

uint32_t LMX2572_SetReferenceFrequency(LMX2572_Device *dev,
                                       uint32_t ref_freq_hz,
                                       uint8_t doubler,
                                       uint8_t pre_r,
                                       uint8_t multiplier,
                                       uint8_t r)
{
    uint32_t ref_freq_khz;
    uint32_t f_osc2x_khz;
    uint32_t f_mult_in_khz;
    uint32_t f_mult_out_khz;
    uint8_t mult_hi;
    uint16_t reg_data;

    if ((pre_r < 1U) || (pre_r > 255U)) {
        pre_r = 1U;
    }
    if ((r < 1U) || (r > 255U)) {
        r = 1U;
    }
    if ((doubler != 0U) && (doubler != 1U)) {
        doubler = 0U;
    }
    if (doubler == 1U) {
        if (multiplier != 1U) {
            multiplier = 1U;
        }
    } else {
        if ((multiplier != 1U) && ((multiplier < 3U) || (multiplier > 7U))) {
            multiplier = 1U;
        }
    }

    ref_freq_khz = ref_freq_hz / 1000U;
    f_osc2x_khz = ref_freq_khz * (doubler ? 2U : 1U);
    f_mult_in_khz = f_osc2x_khz / pre_r;
    f_mult_out_khz = f_mult_in_khz * multiplier;

    if (multiplier != 1U) {
        if ((f_mult_in_khz < 10000U) || (f_mult_in_khz > 40000U)) {
            return 0U;
        }
        if ((f_mult_out_khz < 60000U) || (f_mult_out_khz > 150000U)) {
            return 0U;
        }
    }

    mult_hi = (f_mult_out_khz > 100000U) ? 1U : 0U;

    reg_data = 0x0004U;
    reg_data &= (uint16_t)~((1U << 14) | (1U << 12));
    reg_data |= (uint16_t)((mult_hi << 14) | (doubler << 12));
    LMX2572_WriteRegister(dev, 0x09U, reg_data);

    reg_data = 0x10F8U;
    reg_data &= (uint16_t)~0x0F80U;
    reg_data |= (uint16_t)((multiplier & 0x1FU) << 7);
    LMX2572_WriteRegister(dev, 0x0AU, reg_data);

    reg_data = 0x5001U;
    reg_data &= (uint16_t)~0x0FFFU;
    reg_data |= (uint16_t)(pre_r & 0x0FFFU);
    LMX2572_WriteRegister(dev, 0x0CU, reg_data);

    reg_data = 0xB018U;
    reg_data &= (uint16_t)~0x0FF0U;
    reg_data |= (uint16_t)((r & 0xFFU) << 4);
    LMX2572_WriteRegister(dev, 0x0BU, reg_data);

    dev->fpd_hz = 1000.0 * (double)f_mult_out_khz / (double)r;
    return (uint32_t)dev->fpd_hz;
}

int8_t LMX2572_SetFrequency(LMX2572_Device *dev, uint64_t frequency_hz)
{
    const uint16_t chdiv_list[] = {1, 2, 4, 8, 16, 32, 64, 128, 256};
    uint16_t selected_chdiv = 0U;
    uint64_t f_vco_target = 0U;
    uint32_t pll_n = 0U;
    const uint32_t pll_den = 1000000UL;
    uint32_t pll_num = 0U;
    uint8_t pfd_dly_sel = 0U;
    uint8_t chdiv_found = 0U;
    uint16_t reg_data;
    uint8_t i;

    if ((frequency_hz < 12500000UL) || (frequency_hz > 6400000000ULL)) {
        return 0;
    }
    if (dev->fpd_hz == 0.0) {
        return 0;
    }

    for (i = 0U; i < 9U; i++) {
        uint16_t chdiv = chdiv_list[i];
        double n_total;
        double frac;
        uint32_t min_pll_n;

        f_vco_target = frequency_hz * (uint64_t)chdiv;
        if ((f_vco_target < 3200000000ULL) || (f_vco_target > 6400000000ULL)) {
            continue;
        }

        n_total = (double)f_vco_target / dev->fpd_hz;
        pll_n = (uint32_t)floor(n_total);
        frac = n_total - (double)pll_n;
        pll_num = (uint32_t)(frac * (double)pll_den);

        if (pll_num >= pll_den) {
            pll_num -= pll_den;
            pll_n += 1U;
        }

        if (f_vco_target < 4000000000ULL) {
            min_pll_n = 26U;
            pfd_dly_sel = 1U;
        } else if (f_vco_target < 4900000000ULL) {
            min_pll_n = 30U;
            pfd_dly_sel = 2U;
        } else {
            min_pll_n = 30U;
            pfd_dly_sel = 2U;
        }

        if (pll_n >= min_pll_n) {
            selected_chdiv = chdiv;
            chdiv_found = 1U;
            break;
        }
    }

    if (chdiv_found == 0U) {
        return 0;
    }

    reg_data = 0x0010U;
    reg_data &= (uint16_t)~0x0007U;
    reg_data |= (uint16_t)((pll_n >> 16) & 0x0007U);
    LMX2572_WriteRegister(dev, 0x22U, reg_data);

    LMX2572_WriteRegister(dev, 0x24U, (uint16_t)(pll_n & 0xFFFFU));
    LMX2572_WriteRegister(dev, 0x26U, (uint16_t)((pll_den >> 16) & 0xFFFFU));
    LMX2572_WriteRegister(dev, 0x27U, (uint16_t)(pll_den & 0xFFFFU));
    LMX2572_WriteRegister(dev, 0x2AU, (uint16_t)((pll_num >> 16) & 0xFFFFU));
    LMX2572_WriteRegister(dev, 0x2BU, (uint16_t)(pll_num & 0xFFFFU));

    {
        uint16_t reg_r46 = dev->reg_config[125 - 46];
        uint16_t reg_r45 = dev->reg_config[125 - 45];

        if (selected_chdiv == 1U) {
            reg_r45 &= (uint16_t)~(0x03U << 11);
            reg_r45 |= (uint16_t)(0x01U << 11);
            LMX2572_WriteRegister(dev, 0x2DU, reg_r45);

            reg_r46 &= (uint16_t)~0x0003U;
            reg_r46 |= 0x0001U;
            LMX2572_WriteRegister(dev, 0x2EU, reg_r46);
        } else {
            uint8_t chdiv_code;

            reg_r45 &= (uint16_t)~(0x03U << 11);
            LMX2572_WriteRegister(dev, 0x2DU, reg_r45);

            reg_r46 &= (uint16_t)~0x0003U;
            LMX2572_WriteRegister(dev, 0x2EU, reg_r46);

            switch (selected_chdiv) {
            case 2:   chdiv_code = 0U;  break;
            case 4:   chdiv_code = 1U;  break;
            case 8:   chdiv_code = 3U;  break;
            case 16:  chdiv_code = 5U;  break;
            case 32:  chdiv_code = 7U;  break;
            case 64:  chdiv_code = 9U;  break;
            case 128: chdiv_code = 12U; break;
            case 256: chdiv_code = 14U; break;
            default:  chdiv_code = 0U;  break;
            }

            reg_data = 0xF800U;
            reg_data &= (uint16_t)~0x07C0U;
            reg_data |= (uint16_t)((chdiv_code & 0x1FU) << 6);
            LMX2572_WriteRegister(dev, 0x4BU, reg_data);
        }
    }

    reg_data = 0x0205U;
    reg_data &= (uint16_t)~0x3F00U;
    reg_data |= (uint16_t)((pfd_dly_sel & 0x3FU) << 8);
    LMX2572_WriteRegister(dev, 0x25U, reg_data);

    reg_data = dev->reg_config[125];
    reg_data |= 0x0008U;
    LMX2572_WriteRegister(dev, 0x00U, reg_data);
    return 1;
}

void LMX2572_SetOutputPower(LMX2572_Device *dev, uint8_t ch, int8_t power_dbm)
{
    uint8_t power_code;

    if (power_dbm <= -8) {
        power_code = 0U;
    } else if (power_dbm >= 4) {
        power_code = 63U;
    } else {
        power_code = (uint8_t)((power_dbm + 8) * 4);
    }

    if (ch == 0U) {
        uint16_t r44 = dev->reg_config[125 - 44];
        r44 &= (uint16_t)~0x3F00U;
        r44 |= (uint16_t)((power_code & 0x3FU) << 8);
        LMX2572_WriteRegister(dev, 0x2CU, r44);
    } else if (ch == 1U) {
        uint16_t r45 = dev->reg_config[125 - 45];
        r45 &= (uint16_t)~0x003FU;
        r45 |= (uint16_t)(power_code & 0x3FU);
        LMX2572_WriteRegister(dev, 0x2DU, r45);
    }
}

void LMX2572_SetOutputChannel(LMX2572_Device *dev, uint8_t channel_en)
{
    uint16_t reg_r44 = dev->reg_config[125 - 44];

    reg_r44 |= (1U << 6) | (1U << 7);

    switch (channel_en) {
    case 0:
        reg_r44 &= (uint16_t)~(1U << 6);
        break;
    case 1:
        reg_r44 &= (uint16_t)~(1U << 7);
        break;
    case 2:
        reg_r44 &= (uint16_t)~((1U << 6) | (1U << 7));
        break;
    default:
        break;
    }

    LMX2572_WriteRegister(dev, 0x2CU, reg_r44);
}

void LMX2572_SetOutputMux(LMX2572_Device *dev, uint8_t channel, uint8_t source)
{
    uint16_t reg_val;
    uint8_t is_param_valid = 1U;

    switch (channel) {
    case 0:
        if (!((source == 0U) || (source == 1U) || (source == 3U))) {
            is_param_valid = 0U;
        }
        break;
    case 1:
        if (!((source == 0U) || (source == 1U) || (source == 2U) || (source == 3U))) {
            is_param_valid = 0U;
        }
        break;
    default:
        is_param_valid = 0U;
        break;
    }

    if (is_param_valid == 0U) {
        return;
    }

    if (channel == 0U) {
        reg_val = dev->reg_config[125 - 45];
        reg_val &= (uint16_t)~(0x03U << 11);
        reg_val |= (uint16_t)(source << 11);
        LMX2572_WriteRegister(dev, 0x2DU, reg_val);
    } else {
        reg_val = dev->reg_config[125 - 46];
        reg_val &= (uint16_t)~0x0003U;
        reg_val |= (uint16_t)source;
        LMX2572_WriteRegister(dev, 0x2EU, reg_val);
    }
}

bool LMX2572_IsLocked(LMX2572_Device *dev)
{
    return (LMX2572_MUX_Read(dev) != 0);
}

void LMX2572_SetMuxFunction(LMX2572_Device *dev, uint8_t mux)
{
    uint16_t r0 = dev->reg_config[125];

    r0 &= (uint16_t)~(1U << 2);
    if (mux == 1U) {
        r0 |= (1U << 2);
    }

    LMX2572_WriteRegister(dev, 0U, r0);
}

int lmx2572_board_init(void)
{
    int status;

    status = LMX2572_GpioInit();
    if (status != XST_SUCCESS) {
        return status;
    }

    LMX2572_Device_Init(&lmx2572_dev1,
                        LMX2572_1_CE_MASK,
                        LMX2572_1_CSB_MASK,
                        LMX2572_1_SCK_MASK,
                        LMX2572_1_SDI_MASK,
                        LMX2572_1_MUX_MASK);
    LMX2572_Device_Init(&lmx2572_dev2,
                        LMX2572_2_CE_MASK,
                        LMX2572_2_CSB_MASK,
                        LMX2572_2_SCK_MASK,
                        LMX2572_2_SDI_MASK,
                        LMX2572_2_MUX_MASK);

    LMX2572_Init_Block(&lmx2572_dev1);
    LMX2572_Init_Block(&lmx2572_dev2);

    if (LMX2572_SetReferenceFrequency(&lmx2572_dev1,
                                      LMX2572_DEFAULT_REF_HZ,
                                      LMX2572_DEFAULT_REF_DOUBLER,
                                      LMX2572_DEFAULT_REF_PRE_R,
                                      LMX2572_DEFAULT_REF_MULTIPLIER,
                                      LMX2572_DEFAULT_REF_R) == 0U) {
        return XST_FAILURE;
    }
    if (LMX2572_SetReferenceFrequency(&lmx2572_dev2,
                                      LMX2572_DEFAULT_REF_HZ,
                                      LMX2572_DEFAULT_REF_DOUBLER,
                                      LMX2572_DEFAULT_REF_PRE_R,
                                      LMX2572_DEFAULT_REF_MULTIPLIER,
                                      LMX2572_DEFAULT_REF_R) == 0U) {
        return XST_FAILURE;
    }

    if (LMX2572_SetFrequency(&lmx2572_dev1, LMX2572_DEFAULT_OUTPUT_HZ) == 0) {
        return XST_FAILURE;
    }
    if (LMX2572_SetFrequency(&lmx2572_dev2, LMX2572_DEFAULT_OUTPUT_HZ) == 0) {
        return XST_FAILURE;
    }

    LMX2572_SetOutputPower(&lmx2572_dev1, 0U, LMX2572_DEFAULT_OUTPUT_POWER_DBM);
    LMX2572_SetOutputPower(&lmx2572_dev2, 0U, LMX2572_DEFAULT_OUTPUT_POWER_DBM);
    LMX2572_SetMuxFunction(&lmx2572_dev1, 1U);
    LMX2572_SetMuxFunction(&lmx2572_dev2, 1U);
    LMX2572_SetOutputChannel(&lmx2572_dev1, 0U);
    LMX2572_SetOutputChannel(&lmx2572_dev2, 0U);
    return XST_SUCCESS;
}

int lmx2572_board_set_frequency(uint8_t device_index, uint64_t frequency_hz)
{
    LMX2572_Device *dev = lmx2572_board_get_device(device_index);

    if (dev == 0) {
        return XST_FAILURE;
    }
    return (LMX2572_SetFrequency(dev, frequency_hz) != 0) ? XST_SUCCESS : XST_FAILURE;
}

bool lmx2572_board_is_locked(uint8_t device_index)
{
    LMX2572_Device *dev = lmx2572_board_get_device(device_index);

    if (dev == 0) {
        return false;
    }
    return LMX2572_IsLocked(dev);
}

LMX2572_Device *lmx2572_board_get_device(uint8_t device_index)
{
    if (device_index == 0U) {
        return &lmx2572_dev1;
    }
    if (device_index == 1U) {
        return &lmx2572_dev2;
    }
    return 0;
}
