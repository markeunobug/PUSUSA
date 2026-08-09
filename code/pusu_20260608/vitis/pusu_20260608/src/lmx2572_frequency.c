#include "lmx2572_frequency.h"

#include <limits.h>
#include <stddef.h>

#define LMX2572_OUTPUT_MIN_HZ 12500000ULL
#define LMX2572_OUTPUT_MAX_HZ 6400000000ULL
#define LMX2572_VCO_MIN_HZ    3200000000ULL
#define LMX2572_VCO_MAX_HZ    6400000000ULL

typedef struct {
    uint32_t min_n;
    uint8_t pfd_dly_sel;
} lmx2572_n_rule_t;

static LMX2572_Status lmx2572_get_n_rule(uint8_t mash_order,
                                         uint64_t fvco_hz,
                                         lmx2572_n_rule_t *out_rule)
{
    static const lmx2572_n_rule_t rules[5][3] = {
        { {20U, 0U}, {24U, 1U}, {24U, 1U} },
        { {25U, 1U}, {29U, 2U}, {29U, 2U} },
        { {26U, 1U}, {30U, 2U}, {30U, 2U} },
        { {32U, 2U}, {32U, 2U}, {36U, 3U} },
        { {44U, 4U}, {44U, 4U}, {48U, 5U} }
    };
    uint8_t band;

    if ((out_rule == NULL) || (mash_order > 4U)) {
        return LMX2572_STATUS_INVALID_ARGUMENT;
    }

    if (fvco_hz < 4000000000ULL) {
        band = 0U;
    } else if (fvco_hz < 4900000000ULL) {
        band = 1U;
    } else {
        band = 2U;
    }

    *out_rule = rules[mash_order][band];
    return LMX2572_STATUS_OK;
}

static uint8_t lmx2572_u64_mul_overflow(uint64_t a,
                                        uint64_t b,
                                        uint64_t *out)
{
    if ((out == NULL) || ((a != 0U) && (b > UINT64_MAX / a))) {
        return 1U;
    }
    *out = a * b;
    return 0U;
}

LMX2572_Status lmx2572_frequency_plan(uint64_t output_hz,
                                      uint64_t fpd_num_hz,
                                      uint64_t fpd_den,
                                      uint8_t mash_order,
                                      uint32_t fractional_denominator,
                                      LMX2572_FrequencyPlan *out_plan)
{
    static const uint16_t chdiv_list[] = {1U, 2U, 4U, 8U, 16U,
                                         32U, 64U, 128U, 256U};
    LMX2572_FrequencyPlan best = {0};
    uint8_t found = 0U;
    uint8_t best_is_integer = 0U;
    unsigned int i;

    if ((out_plan == NULL) || (fpd_num_hz == 0U) || (fpd_den == 0U) ||
        (fractional_denominator == 0U) || (mash_order > 4U)) {
        return LMX2572_STATUS_INVALID_ARGUMENT;
    }
    if ((output_hz < LMX2572_OUTPUT_MIN_HZ) ||
        (output_hz > LMX2572_OUTPUT_MAX_HZ)) {
        return LMX2572_STATUS_OUTPUT_OUT_OF_RANGE;
    }

    for (i = 0U; i < sizeof(chdiv_list) / sizeof(chdiv_list[0]); i++) {
        LMX2572_FrequencyPlan candidate = {0};
        lmx2572_n_rule_t rule;
        uint64_t scaled_vco;
        uint64_t quotient;
        uint64_t remainder;
        uint64_t rounded_num;

        if (output_hz > UINT64_MAX / chdiv_list[i]) {
            continue;
        }
        candidate.requested_output_hz = output_hz;
        candidate.chdiv = chdiv_list[i];
        candidate.fvco_hz = output_hz * (uint64_t)candidate.chdiv;
        if ((candidate.fvco_hz < LMX2572_VCO_MIN_HZ) ||
            (candidate.fvco_hz > LMX2572_VCO_MAX_HZ)) {
            continue;
        }
        if (lmx2572_u64_mul_overflow(candidate.fvco_hz,
                                     fpd_den,
                                     &scaled_vco) != 0U) {
            return LMX2572_STATUS_ARITHMETIC_OVERFLOW;
        }

        quotient = scaled_vco / fpd_num_hz;
        remainder = scaled_vco % fpd_num_hz;
        if (lmx2572_u64_mul_overflow(remainder,
                                     fractional_denominator,
                                     &rounded_num) != 0U) {
            return LMX2572_STATUS_ARITHMETIC_OVERFLOW;
        }
        if (rounded_num > UINT64_MAX - (fpd_num_hz / 2U)) {
            return LMX2572_STATUS_ARITHMETIC_OVERFLOW;
        }
        rounded_num = (rounded_num + (fpd_num_hz / 2U)) / fpd_num_hz;
        if (rounded_num >= fractional_denominator) {
            rounded_num = 0U;
            quotient++;
        }

        if ((quotient > 0x7FFFFU) || (rounded_num > UINT32_MAX)) {
            continue;
        }
        if (lmx2572_get_n_rule(mash_order, candidate.fvco_hz, &rule) !=
            LMX2572_STATUS_OK) {
            return LMX2572_STATUS_INVALID_ARGUMENT;
        }
        if (quotient < rule.min_n) {
            continue;
        }

        candidate.pll_n = (uint32_t)quotient;
        candidate.pll_num = (uint32_t)rounded_num;
        candidate.pll_den = fractional_denominator;
        candidate.pfd_dly_sel = rule.pfd_dly_sel;
        candidate.is_integer_n = (rounded_num == 0U) ? 1U : 0U;

        if ((found == 0U) ||
            ((candidate.is_integer_n != 0U) && (best_is_integer == 0U))) {
            best = candidate;
            best_is_integer = candidate.is_integer_n;
            found = 1U;
        }
    }

    if (found == 0U) {
        return LMX2572_STATUS_NO_VALID_DIVIDER;
    }

    *out_plan = best;
    return LMX2572_STATUS_OK;
}

uint8_t lmx2572_chdiv_register_code(uint16_t chdiv, uint8_t *out_code)
{
    uint8_t code;

    if (out_code == NULL) {
        return 0U;
    }

    switch (chdiv) {
    case 2U:   code = 0U;  break;
    case 4U:   code = 1U;  break;
    case 8U:   code = 3U;  break;
    case 16U:  code = 5U;  break;
    case 32U:  code = 7U;  break;
    case 64U:  code = 9U;  break;
    case 128U: code = 12U; break;
    case 256U: code = 14U; break;
    default:
        return 0U;
    }

    *out_code = code;
    return 1U;
}
