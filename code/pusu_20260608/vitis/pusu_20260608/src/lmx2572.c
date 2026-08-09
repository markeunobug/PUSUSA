#include "lmx2572.h"

#include <string.h>

#include "sleep.h"
#include "app_config.h"
#include "lmx2572_bus.h"
#include "lmx2572_frequency.h"
#include "lmx2572_pfd_profile.h"
#include "lmx2572_registers.h"

/*
 * Authoritative current-machine P100 TICS Pro export. The array is ordered
 * R125..R0. Runtime frequency, output and MUX settings intentionally update a
 * subset of this image after it is copied into each device shadow.
 */
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

static LMX2572_Device lmx2572_dev0;
static LMX2572_Device lmx2572_dev1;
static LMX2572_Device lmx2572_dev2;

static void lmx2572_delay_ms(uint32_t delay_ms)
{
    usleep(delay_ms * 1000U);
}

int LMX2572_GpioInit(void)
{
    return lmx2572_bus_gpio_init();
}

void LMX2572_Device_Init(LMX2572_Device *dev,
                         uint32_t ce_mask,
                         uint32_t csb_mask,
                         uint32_t sck_mask,
                         uint32_t sdi_mask,
                         uint32_t mux_mask)
{
    if (dev == 0) {
        return;
    }

    dev->ce_mask = ce_mask;
    dev->csb_mask = csb_mask;
    dev->sck_mask = sck_mask;
    dev->sdi_mask = sdi_mask;
    dev->mux_mask = mux_mask;
    dev->fpd_hz = 0.0;
    memcpy(dev->reg_config, lmx2572_reg_default, sizeof(dev->reg_config));
    dev->fpd_num_hz = 0U;
    dev->fpd_den = 1U;
    dev->last_requested_frequency_hz = 0U;
    dev->last_fvco_hz = 0U;
    dev->last_pll_n = 0U;
    dev->last_pll_num = 0U;
    dev->last_pll_den = 0U;
    dev->last_chdiv = 0U;
    dev->last_pfd_dly_sel = 0U;
    dev->mash_order = (uint8_t)(lmx2572_shadow_get(dev->reg_config,
                                                   LMX2572_R44) &
                                LMX2572_R44_MASH_ORDER_MASK);
    dev->pfd_profile_id = 0xFFU;
    dev->last_status = (int)LMX2572_STATUS_OK;

    lmx2572_bus_set_device_idle(dev);
}

void LMX2572_WriteRegister(LMX2572_Device *dev, uint8_t reg_addr, uint16_t data)
{
    if ((dev == 0) || (reg_addr >= LMX2572_REGISTER_COUNT)) {
        if (dev != 0) {
            dev->last_status = (int)LMX2572_STATUS_INVALID_ARGUMENT;
        }
        return;
    }

    lmx2572_bus_write_register(dev, reg_addr, data);

    if (reg_addr == LMX2572_R0) {
        if ((data & LMX2572_R0_RESET_MASK) != 0U) {
            lmx2572_shadow_set(dev->reg_config,
                               LMX2572_R0,
                               data & (uint16_t)~LMX2572_R0_RESET_MASK);
        } else {
            lmx2572_shadow_set(dev->reg_config, LMX2572_R0, data);
        }
    } else {
        lmx2572_shadow_set(dev->reg_config, reg_addr, data);
    }

    if (reg_addr == LMX2572_R44) {
        dev->mash_order = (uint8_t)(data & LMX2572_R44_MASH_ORDER_MASK);
    }
    dev->last_status = (int)LMX2572_STATUS_OK;
}

uint16_t LMX2572_ReadRegister(LMX2572_Device *dev, uint8_t reg_addr)
{
    uint16_t rx_data;

    if ((dev == 0) || (reg_addr >= LMX2572_REGISTER_COUNT)) {
        if (dev != 0) {
            dev->last_status = (int)LMX2572_STATUS_INVALID_ARGUMENT;
        }
        return 0U;
    }
    if ((lmx2572_shadow_get(dev->reg_config, LMX2572_R0) &
         LMX2572_R0_MUXOUT_LD_SEL_MASK) != 0U) {
        dev->last_status = (int)LMX2572_STATUS_MUX_MODE_CONFLICT;
        return 0U;
    }

    rx_data = lmx2572_bus_read_register(dev, reg_addr);
    dev->last_status = (int)LMX2572_STATUS_OK;
    return rx_data;
}

void LMX2572_Reset(LMX2572_Device *dev)
{
    if (dev == 0) {
        return;
    }
    LMX2572_WriteRegister(
        dev,
        LMX2572_R0,
        lmx2572_shadow_get(dev->reg_config, LMX2572_R0) |
            LMX2572_R0_RESET_MASK);
    lmx2572_delay_ms(10U);
}

void LMX2572_SetEnabled(LMX2572_Device *dev, bool enabled)
{
    if (dev == 0) {
        return;
    }
    lmx2572_bus_set_enabled(dev, enabled);
    dev->last_status = (int)LMX2572_STATUS_OK;
}

void LMX2572_Init(LMX2572_Device *dev)
{
    if (dev == 0) {
        return;
    }
    LMX2572_Init_Block(dev);
}

void LMX2572_Init_Block(LMX2572_Device *dev)
{
    unsigned int image_idx;

    if (dev == 0) {
        return;
    }
    lmx2572_bus_set_enabled(dev, true);
    lmx2572_delay_ms(50U);
    LMX2572_Reset(dev);
    lmx2572_delay_ms(50U);

    /* TICS Pro exports the image R125..R0; write R0 last so FCAL starts only
     * after the complete configuration is present in the device. */
    for (image_idx = 0U; image_idx < LMX2572_REGISTER_COUNT; image_idx++) {
        uint8_t reg = (uint8_t)((LMX2572_REGISTER_COUNT - 1U) - image_idx);
        LMX2572_WriteRegister(dev, reg, dev->reg_config[image_idx]);
    }
}

static uint64_t lmx2572_gcd_u64(uint64_t a, uint64_t b)
{
    while (b != 0U) {
        uint64_t remainder = a % b;
        a = b;
        b = remainder;
    }
    return a;
}

static int lmx2572_ratio_in_range(uint64_t num,
                                  uint64_t den,
                                  uint64_t min_hz,
                                  uint64_t max_hz)
{
    if (den == 0U) {
        return 0;
    }
    return (num >= min_hz * den) && (num <= max_hz * den);
}

static uint8_t lmx2572_fcal_hpfd_adj(uint64_t fpd_num, uint64_t fpd_den)
{
    if ((fpd_num * 2U) <= (75000000ULL * fpd_den)) {
        return 0U;
    }
    if (fpd_num <= (75000000ULL * fpd_den)) {
        return 1U;
    }
    if (fpd_num <= (100000000ULL * fpd_den)) {
        return 2U;
    }
    return 3U;
}

static uint8_t lmx2572_fcal_lpfd_adj(uint64_t fpd_num, uint64_t fpd_den)
{
    if (fpd_num >= (10000000ULL * fpd_den)) {
        return 0U;
    }
    if (fpd_num >= (5000000ULL * fpd_den)) {
        return 1U;
    }
    if ((fpd_num * 2U) >= (5000000ULL * fpd_den)) {
        return 2U;
    }
    return 3U;
}

uint32_t LMX2572_SetReferenceFrequency(LMX2572_Device *dev,
                                       uint32_t ref_freq_hz,
                                       uint8_t doubler,
                                       uint8_t pre_r,
                                       uint8_t multiplier,
                                       uint8_t r)
{
    uint64_t osc_num;
    uint64_t pre_num;
    uint64_t pre_den;
    uint64_t mult_num;
    uint64_t mult_den;
    uint64_t fpd_num;
    uint64_t fpd_den;
    uint64_t common;
    uint8_t mult_hi;
    uint16_t reg_data;

    if (dev == 0) {
        return 0U;
    }
    if ((ref_freq_hz < 5000000U) || (ref_freq_hz > 250000000U) ||
        (pre_r == 0U) || (r == 0U) ||
        ((doubler != 0U) && (doubler != 1U)) ||
        ((multiplier != 1U) &&
         ((multiplier < 3U) || (multiplier > 7U))) ||
        ((doubler != 0U) && (multiplier != 1U)) ||
        ((doubler != 0U) && (ref_freq_hz > 125000000U))) {
        dev->last_status = (int)LMX2572_STATUS_INVALID_ARGUMENT;
        return 0U;
    }

    osc_num = (uint64_t)ref_freq_hz * ((doubler != 0U) ? 2U : 1U);
    if (!lmx2572_ratio_in_range(osc_num, 1U, 5000000U, 200000000U)) {
        dev->last_status = (int)LMX2572_STATUS_REFERENCE_OUT_OF_RANGE;
        return 0U;
    }

    pre_num = osc_num;
    pre_den = pre_r;
    if (!lmx2572_ratio_in_range(pre_num, pre_den, 250000U, 200000000U)) {
        dev->last_status = (int)LMX2572_STATUS_REFERENCE_OUT_OF_RANGE;
        return 0U;
    }
    if ((multiplier != 1U) &&
        !lmx2572_ratio_in_range(pre_num, pre_den, 10000000U, 40000000U)) {
        dev->last_status = (int)LMX2572_STATUS_REFERENCE_OUT_OF_RANGE;
        return 0U;
    }

    mult_num = pre_num * multiplier;
    mult_den = pre_den;
    if ((multiplier != 1U) &&
        !lmx2572_ratio_in_range(mult_num, mult_den, 60000000U, 150000000U)) {
        dev->last_status = (int)LMX2572_STATUS_REFERENCE_OUT_OF_RANGE;
        return 0U;
    }
    if (!lmx2572_ratio_in_range(mult_num, mult_den, 5000000U, 200000000U)) {
        dev->last_status = (int)LMX2572_STATUS_REFERENCE_OUT_OF_RANGE;
        return 0U;
    }

    fpd_num = mult_num;
    fpd_den = mult_den * r;
    if (!lmx2572_ratio_in_range(fpd_num, fpd_den, 250000U, 200000000U)) {
        dev->last_status = (int)LMX2572_STATUS_REFERENCE_OUT_OF_RANGE;
        return 0U;
    }
    common = lmx2572_gcd_u64(fpd_num, fpd_den);
    fpd_num /= common;
    fpd_den /= common;
    mult_hi = (mult_num > 100000000ULL * mult_den) ? 1U : 0U;

    reg_data = lmx2572_shadow_get(dev->reg_config, LMX2572_R9);
    reg_data = lmx2572_field_replace(reg_data,
                                     LMX2572_R9_MULT_HI_MASK,
                                     14U,
                                     mult_hi);
    reg_data = lmx2572_field_replace(reg_data,
                                     LMX2572_R9_OSC_2X_MASK,
                                     12U,
                                     doubler);
    LMX2572_WriteRegister(dev, LMX2572_R9, reg_data);

    reg_data = lmx2572_shadow_get(dev->reg_config, LMX2572_R10);
    reg_data = lmx2572_field_replace(reg_data,
                                     LMX2572_R10_MULT_MASK,
                                     LMX2572_R10_MULT_SHIFT,
                                     multiplier);
    LMX2572_WriteRegister(dev, LMX2572_R10, reg_data);

    reg_data = lmx2572_shadow_get(dev->reg_config, LMX2572_R12);
    reg_data = lmx2572_field_replace(reg_data,
                                     LMX2572_R12_PLL_R_PRE_MASK,
                                     0U,
                                     pre_r);
    LMX2572_WriteRegister(dev, LMX2572_R12, reg_data);

    reg_data = lmx2572_shadow_get(dev->reg_config, LMX2572_R11);
    reg_data = lmx2572_field_replace(reg_data,
                                     LMX2572_R11_PLL_R_MASK,
                                     LMX2572_R11_PLL_R_SHIFT,
                                     r);
    LMX2572_WriteRegister(dev, LMX2572_R11, reg_data);

    reg_data = lmx2572_shadow_get(dev->reg_config, LMX2572_R0);
    reg_data = lmx2572_field_replace(
        reg_data,
        LMX2572_R0_FCAL_HPFD_ADJ_MASK,
        LMX2572_R0_FCAL_HPFD_ADJ_SHIFT,
        lmx2572_fcal_hpfd_adj(fpd_num, fpd_den));
    reg_data = lmx2572_field_replace(
        reg_data,
        LMX2572_R0_FCAL_LPFD_ADJ_MASK,
        LMX2572_R0_FCAL_LPFD_ADJ_SHIFT,
        lmx2572_fcal_lpfd_adj(fpd_num, fpd_den));
    lmx2572_shadow_set(dev->reg_config, LMX2572_R0, reg_data);

    dev->fpd_num_hz = fpd_num;
    dev->fpd_den = fpd_den;
    dev->fpd_hz = (double)fpd_num / (double)fpd_den;
    dev->last_status = (int)LMX2572_STATUS_OK;
    return (uint32_t)(fpd_num / fpd_den);
}

int8_t LMX2572_SetFrequency(LMX2572_Device *dev, uint64_t frequency_hz)
{
    LMX2572_FrequencyPlan plan;
    LMX2572_Status status;
    uint16_t reg_data;
    uint8_t chdiv_code;

    if (dev == 0) {
        return 0;
    }
    if ((dev->fpd_num_hz == 0U) || (dev->fpd_den == 0U)) {
        dev->last_status = (int)LMX2572_STATUS_INVALID_ARGUMENT;
        return 0;
    }

#if LMX2572_FRACTIONAL_OPT_ENABLE
    {
        const uint32_t fractional_denominator =
            (uint32_t)LMX2572_FRACTIONAL_DENOMINATOR;
#else
    {
        const uint32_t fractional_denominator = 1000000U;
#endif
    status = lmx2572_frequency_plan(
        frequency_hz,
        dev->fpd_num_hz,
        dev->fpd_den,
        dev->mash_order,
        fractional_denominator,
        &plan);
    }
    if (status != LMX2572_STATUS_OK) {
        dev->last_status = (int)status;
        return 0;
    }

    reg_data = lmx2572_shadow_get(dev->reg_config, LMX2572_R34);
    reg_data = lmx2572_field_replace(
        reg_data,
        LMX2572_R34_PLL_N_HIGH_MASK,
        0U,
        (uint16_t)(plan.pll_n >> 16));
    LMX2572_WriteRegister(dev, LMX2572_R34, reg_data);

    LMX2572_WriteRegister(dev, LMX2572_R36,
                          (uint16_t)(plan.pll_n & 0xFFFFU));
    LMX2572_WriteRegister(dev, LMX2572_R38,
                          (uint16_t)(plan.pll_den >> 16));
    LMX2572_WriteRegister(dev, LMX2572_R39,
                          (uint16_t)(plan.pll_den & 0xFFFFU));
    LMX2572_WriteRegister(dev, LMX2572_R42,
                          (uint16_t)(plan.pll_num >> 16));
    LMX2572_WriteRegister(dev, LMX2572_R43,
                          (uint16_t)(plan.pll_num & 0xFFFFU));

    {
        uint16_t reg_r46 = lmx2572_shadow_get(dev->reg_config, LMX2572_R46);
        uint16_t reg_r45 = lmx2572_shadow_get(dev->reg_config, LMX2572_R45);

        if (plan.chdiv == 1U) {
            reg_r45 = lmx2572_field_replace(
                reg_r45,
                LMX2572_R45_OUTA_MUX_MASK,
                LMX2572_R45_OUTA_MUX_SHIFT,
                1U);
            LMX2572_WriteRegister(dev, LMX2572_R45, reg_r45);

            reg_r46 = lmx2572_field_replace(
                reg_r46,
                LMX2572_R46_OUTB_MUX_MASK,
                0U,
                1U);
            LMX2572_WriteRegister(dev, LMX2572_R46, reg_r46);
        } else {
            reg_r45 = lmx2572_field_replace(
                reg_r45,
                LMX2572_R45_OUTA_MUX_MASK,
                LMX2572_R45_OUTA_MUX_SHIFT,
                0U);
            LMX2572_WriteRegister(dev, LMX2572_R45, reg_r45);

            reg_r46 = lmx2572_field_replace(
                reg_r46,
                LMX2572_R46_OUTB_MUX_MASK,
                0U,
                0U);
            LMX2572_WriteRegister(dev, LMX2572_R46, reg_r46);

            if (lmx2572_chdiv_register_code(plan.chdiv, &chdiv_code) == 0U) {
                dev->last_status = (int)LMX2572_STATUS_NO_VALID_DIVIDER;
                return 0;
            }

            /*
             * Preserve the current-machine runtime value outside CHDIV. The
             * 0xF800 base is part of the legacy P100 behavior baseline.
             */
            reg_data = 0xF800U;
            reg_data = lmx2572_field_replace(
                reg_data,
                LMX2572_R75_CHDIV_MASK,
                LMX2572_R75_CHDIV_SHIFT,
                chdiv_code);
            LMX2572_WriteRegister(dev, LMX2572_R75, reg_data);
        }
    }

    reg_data = lmx2572_shadow_get(dev->reg_config, LMX2572_R37);
    reg_data = lmx2572_field_replace(
        reg_data,
        LMX2572_R37_PFD_DLY_SEL_MASK,
        LMX2572_R37_PFD_DLY_SEL_SHIFT,
        plan.pfd_dly_sel);
    LMX2572_WriteRegister(dev, LMX2572_R37, reg_data);

    reg_data = lmx2572_shadow_get(dev->reg_config, LMX2572_R0);
    reg_data |= LMX2572_R0_FCAL_EN_MASK;
    LMX2572_WriteRegister(dev, LMX2572_R0, reg_data);

    dev->last_requested_frequency_hz = frequency_hz;
    dev->last_fvco_hz = plan.fvco_hz;
    dev->last_pll_n = plan.pll_n;
    dev->last_pll_num = plan.pll_num;
    dev->last_pll_den = plan.pll_den;
    dev->last_chdiv = plan.chdiv;
    dev->last_pfd_dly_sel = plan.pfd_dly_sel;
    dev->last_status = (int)LMX2572_STATUS_OK;
    return 1;
}

void LMX2572_SetOutputPower(LMX2572_Device *dev, uint8_t ch, int8_t power_dbm)
{
    uint8_t power_code;

    if (dev == 0) {
        return;
    }
    if (ch > 1U) {
        dev->last_status = (int)LMX2572_STATUS_INVALID_ARGUMENT;
        return;
    }

    if (power_dbm <= -8) {
        power_code = 0U;
    } else if (power_dbm >= 4) {
        power_code = 63U;
    } else {
        power_code = (uint8_t)((power_dbm + 8) * 4);
    }

    if (ch == 0U) {
        uint16_t r44 = lmx2572_shadow_get(dev->reg_config, LMX2572_R44);
        r44 = lmx2572_field_replace(r44,
                                    LMX2572_R44_OUTA_PWR_MASK,
                                    LMX2572_R44_OUTA_PWR_SHIFT,
                                    power_code);
        LMX2572_WriteRegister(dev, LMX2572_R44, r44);
    } else if (ch == 1U) {
        uint16_t r45 = lmx2572_shadow_get(dev->reg_config, LMX2572_R45);
        r45 = lmx2572_field_replace(r45,
                                    LMX2572_R45_OUTB_PWR_MASK,
                                    0U,
                                    power_code);
        LMX2572_WriteRegister(dev, LMX2572_R45, r45);
    }
    dev->last_status = (int)LMX2572_STATUS_OK;
}

void LMX2572_SetOutputChannel(LMX2572_Device *dev, uint8_t channel_en)
{
    uint16_t reg_r44;

    if (dev == 0) {
        return;
    }
    if (channel_en > 2U) {
        dev->last_status = (int)LMX2572_STATUS_INVALID_ARGUMENT;
        return;
    }

    reg_r44 = lmx2572_shadow_get(dev->reg_config, LMX2572_R44);

    reg_r44 |= LMX2572_R44_OUTA_PD_MASK | LMX2572_R44_OUTB_PD_MASK;

    switch (channel_en) {
    case 0:
        reg_r44 &= (uint16_t)~LMX2572_R44_OUTA_PD_MASK;
        break;
    case 1:
        reg_r44 &= (uint16_t)~LMX2572_R44_OUTB_PD_MASK;
        break;
    case 2:
        reg_r44 &= (uint16_t)~(LMX2572_R44_OUTA_PD_MASK |
                               LMX2572_R44_OUTB_PD_MASK);
        break;
    default:
        return;
    }

    LMX2572_WriteRegister(dev, LMX2572_R44, reg_r44);
    dev->last_status = (int)LMX2572_STATUS_OK;
}

void LMX2572_SetOutputMux(LMX2572_Device *dev, uint8_t channel, uint8_t source)
{
    uint16_t reg_val;
    uint8_t is_param_valid = 1U;

    if (dev == 0) {
        return;
    }

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
        dev->last_status = (int)LMX2572_STATUS_INVALID_ARGUMENT;
        return;
    }

    if (channel == 0U) {
        reg_val = lmx2572_shadow_get(dev->reg_config, LMX2572_R45);
        reg_val = lmx2572_field_replace(reg_val,
                                        LMX2572_R45_OUTA_MUX_MASK,
                                        LMX2572_R45_OUTA_MUX_SHIFT,
                                        source);
        LMX2572_WriteRegister(dev, LMX2572_R45, reg_val);
    } else {
        reg_val = lmx2572_shadow_get(dev->reg_config, LMX2572_R46);
        reg_val = lmx2572_field_replace(reg_val,
                                        LMX2572_R46_OUTB_MUX_MASK,
                                        0U,
                                        source);
        LMX2572_WriteRegister(dev, LMX2572_R46, reg_val);
    }
    dev->last_status = (int)LMX2572_STATUS_OK;
}

bool LMX2572_IsLocked(LMX2572_Device *dev)
{
    if (dev == 0) {
        return false;
    }
    if ((lmx2572_shadow_get(dev->reg_config, LMX2572_R0) &
         LMX2572_R0_MUXOUT_LD_SEL_MASK) == 0U) {
        dev->last_status = (int)LMX2572_STATUS_MUX_MODE_CONFLICT;
        return false;
    }
    dev->last_status = (int)LMX2572_STATUS_OK;
    return (lmx2572_bus_read_mux(dev) != 0);
}

void LMX2572_SetMuxFunction(LMX2572_Device *dev, uint8_t mux)
{
    uint16_t r0;

    if (dev == 0) {
        return;
    }
    if (mux > 1U) {
        dev->last_status = (int)LMX2572_STATUS_INVALID_ARGUMENT;
        return;
    }

    r0 = lmx2572_shadow_get(dev->reg_config, LMX2572_R0);

    r0 &= (uint16_t)~LMX2572_R0_MUXOUT_LD_SEL_MASK;
    if (mux == 1U) {
        r0 |= LMX2572_R0_MUXOUT_LD_SEL_MASK;
    }

    LMX2572_WriteRegister(dev, LMX2572_R0, r0);
    dev->last_status = (int)LMX2572_STATUS_OK;
}

LMX2572_Status LMX2572_GetLastStatus(const LMX2572_Device *dev)
{
    if (dev == 0) {
        return LMX2572_STATUS_NULL_DEVICE;
    }
    return (LMX2572_Status)dev->last_status;
}

int lmx2572_board_init(void)
{
    int status;

    status = LMX2572_GpioInit();
    if (status != XST_SUCCESS) {
        return status;
    }

    LMX2572_Device_Init(&lmx2572_dev0,
                        LMX2572_0_CE_MASK,
                        LMX2572_0_CSB_MASK,
                        LMX2572_0_SCK_MASK,
                        LMX2572_0_SDI_MASK,
                        LMX2572_0_MUX_MASK);
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

    LMX2572_Init_Block(&lmx2572_dev0);
    LMX2572_Init_Block(&lmx2572_dev1);
    LMX2572_Init_Block(&lmx2572_dev2);

    if (LMX2572_SetReferenceFrequency(&lmx2572_dev0,
                                      LMX2572_DEFAULT_REF_HZ,
                                      LMX2572_DEFAULT_REF_DOUBLER,
                                      LMX2572_DEFAULT_REF_PRE_R,
                                      LMX2572_DEFAULT_REF_MULTIPLIER,
                                      LMX2572_DEFAULT_REF_R) == 0U) {
        return XST_FAILURE;
    }
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

    if (LMX2572_SetFrequency(&lmx2572_dev0, LMX2572_ADC_CLK_OUTPUT_HZ) == 0) {
        return XST_FAILURE;
    }
    if (LMX2572_SetFrequency(&lmx2572_dev1, LMX2572_DEFAULT_OUTPUT_HZ) == 0) {
        return XST_FAILURE;
    }
    if (LMX2572_SetFrequency(&lmx2572_dev2, LMX2572_DEFAULT_OUTPUT_HZ) == 0) {
        return XST_FAILURE;
    }

    lmx2572_dev0.pfd_profile_id = (uint8_t)LMX2572_PFD_PROFILE_P100;
    lmx2572_dev1.pfd_profile_id = (uint8_t)LMX2572_PFD_PROFILE_P100;
    lmx2572_dev2.pfd_profile_id = (uint8_t)LMX2572_PFD_PROFILE_P100;

    LMX2572_SetOutputPower(&lmx2572_dev0, 0U, LMX2572_ADC_CLK_OUTPUT_POWER_DBM);
    LMX2572_SetOutputPower(&lmx2572_dev0, 1U, LMX2572_ADC_CLK_OUTPUT_POWER_DBM);
    LMX2572_SetOutputPower(&lmx2572_dev1, 0U, LMX2572_LO1_OUTPUT_POWER_DBM);
    LMX2572_SetOutputPower(&lmx2572_dev2, 0U, LMX2572_LO2_OUTPUT_POWER_DBM);
    LMX2572_SetMuxFunction(&lmx2572_dev0, 1U);
    LMX2572_SetMuxFunction(&lmx2572_dev1, 1U);
    LMX2572_SetMuxFunction(&lmx2572_dev2, 1U);
    LMX2572_SetOutputChannel(&lmx2572_dev0, 0U);
    LMX2572_SetOutputChannel(&lmx2572_dev1, 0U);
    LMX2572_SetOutputChannel(&lmx2572_dev2, 2U);

//    LMX2572_SetEnabled(&lmx2572_dev1, false);//!!!!!

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

int lmx2572_board_apply_pfd_profile(uint8_t device_index,
                                    uint8_t profile_id,
                                    uint64_t frequency_hz)
{
    LMX2572_Device *dev = lmx2572_board_get_device(device_index);
    const LMX2572_PfdProfile *profile =
        lmx2572_pfd_profile_get(profile_id);

    if ((dev == 0) || (profile == 0)) {
        return XST_FAILURE;
    }
    return (lmx2572_pfd_profile_apply(dev, profile, frequency_hz) ==
            LMX2572_STATUS_OK)
        ? XST_SUCCESS
        : XST_FAILURE;
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
        return &lmx2572_dev0;
    }
    if (device_index == 1U) {
        return &lmx2572_dev1;
    }
    if (device_index == 2U) {
        return &lmx2572_dev2;
    }
    return 0;
}
