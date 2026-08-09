#include "lmx2572_pfd_profile.h"

#include <stddef.h>

#include "app_config.h"
#include "lmx2572_frequency.h"
#include "lmx2572_registers.h"

#define LMX2572_P100_CPG_CODE   4U
#define LMX2572_P100_MASH_ORDER 3U

static const LMX2572_PfdProfile lmx2572_pfd_profiles[] = {
    {
        LMX2572_PFD_PROFILE_P100,
        50000000U, 1U, 1U, 1U, 1U,
        100000000ULL, 1ULL,
        LMX2572_P100_CPG_CODE, LMX2572_P100_MASH_ORDER, 1U,
        LMX2572_PROFILE_LOCK_TIMEOUT_LOOPS, 0U, 0U, 0,
        0U, 1U, 0, 0U
    },
    {
        LMX2572_PFD_PROFILE_P75,
        50000000U, 0U, 2U, 3U, 1U,
        75000000ULL, 1ULL,
        LMX2572_P75_CPG_CODE, LMX2572_P75_MASH_ORDER,
        LMX2572_P75_PROFILE_QUALIFIED,
        LMX2572_PROFILE_LOCK_TIMEOUT_LOOPS, 0U, 0U, 0,
        0U, 1U, 0, 0U
    }
};

static uint32_t lmx2572_profile_fractional_denominator(void)
{
#if LMX2572_FRACTIONAL_OPT_ENABLE
    return (uint32_t)LMX2572_FRACTIONAL_DENOMINATOR;
#else
    return 1000000U;
#endif
}

static uint64_t lmx2572_profile_gcd_u64(uint64_t a, uint64_t b)
{
    while (b != 0U) {
        uint64_t remainder = a % b;
        a = b;
        b = remainder;
    }
    return a;
}

static uint8_t lmx2572_profile_reference_matches(
    const LMX2572_PfdProfile *profile)
{
    uint64_t numerator;
    uint64_t denominator;
    uint64_t common;

    if ((profile->pll_r_pre == 0U) || (profile->pll_r == 0U) ||
        (profile->osc_2x > 1U) ||
        ((profile->mult != 1U) &&
         ((profile->mult < 3U) || (profile->mult > 7U))) ||
        ((profile->osc_2x != 0U) && (profile->mult != 1U))) {
        return 0U;
    }

    numerator = (uint64_t)profile->ref_hz *
                ((profile->osc_2x != 0U) ? 2U : 1U) *
                profile->mult;
    denominator = (uint64_t)profile->pll_r_pre * profile->pll_r;
    common = lmx2572_profile_gcd_u64(numerator, denominator);
    numerator /= common;
    denominator /= common;

    return ((numerator == profile->fpd_num_hz) &&
            (denominator == profile->fpd_den))
        ? 1U
        : 0U;
}

const LMX2572_PfdProfile *lmx2572_pfd_profile_get(uint8_t profile_id)
{
    if (profile_id >= (uint8_t)LMX2572_PFD_PROFILE_COUNT) {
        return NULL;
    }
    return &lmx2572_pfd_profiles[profile_id];
}

LMX2572_Status lmx2572_pfd_profile_validate(
    const LMX2572_PfdProfile *profile,
    uint64_t output_hz)
{
    LMX2572_FrequencyPlan plan;

    if (profile == NULL) {
        return LMX2572_STATUS_INVALID_ARGUMENT;
    }
    if (profile->qualified == 0U) {
        return LMX2572_STATUS_PROFILE_NOT_QUALIFIED;
    }
    if ((profile->id >= LMX2572_PFD_PROFILE_COUNT) ||
        (profile->cpg_code > 15U) || (profile->mash_order > 4U) ||
        (profile->fpd_num_hz == 0U) || (profile->fpd_den == 0U) ||
        (lmx2572_profile_reference_matches(profile) == 0U)) {
        return LMX2572_STATUS_INVALID_ARGUMENT;
    }

    return lmx2572_frequency_plan(
        output_hz,
        profile->fpd_num_hz,
        profile->fpd_den,
        profile->mash_order,
        lmx2572_profile_fractional_denominator(),
        &plan);
}

LMX2572_Status lmx2572_pfd_profile_apply(
    LMX2572_Device *dev,
    const LMX2572_PfdProfile *profile,
    uint64_t output_hz)
{
    LMX2572_Status status;
    uint16_t reg_data;

    if (dev == NULL) {
        return LMX2572_STATUS_NULL_DEVICE;
    }

    status = lmx2572_pfd_profile_validate(profile, output_hz);
    if (status != LMX2572_STATUS_OK) {
        dev->last_status = status;
        return status;
    }

    if (LMX2572_SetReferenceFrequency(dev,
                                      profile->ref_hz,
                                      profile->osc_2x,
                                      profile->pll_r_pre,
                                      profile->mult,
                                      profile->pll_r) == 0U) {
        return LMX2572_GetLastStatus(dev);
    }
    if ((dev->fpd_num_hz != profile->fpd_num_hz) ||
        (dev->fpd_den != profile->fpd_den)) {
        dev->last_status = LMX2572_STATUS_INVALID_ARGUMENT;
        return dev->last_status;
    }

    reg_data = lmx2572_shadow_get(dev->reg_config, LMX2572_R14);
    reg_data = lmx2572_field_replace(reg_data,
                                     LMX2572_R14_CPG_MASK,
                                     LMX2572_R14_CPG_SHIFT,
                                     profile->cpg_code);
    LMX2572_WriteRegister(dev, LMX2572_R14, reg_data);

    reg_data = lmx2572_shadow_get(dev->reg_config, LMX2572_R44);
    reg_data = lmx2572_field_replace(reg_data,
                                     LMX2572_R44_MASH_ORDER_MASK,
                                     0U,
                                     profile->mash_order);
    LMX2572_WriteRegister(dev, LMX2572_R44, reg_data);

    if (LMX2572_SetFrequency(dev, output_hz) == 0) {
        return LMX2572_GetLastStatus(dev);
    }

    dev->pfd_profile_id = (uint8_t)profile->id;
    dev->last_status = LMX2572_STATUS_OK;
    return LMX2572_STATUS_OK;
}
