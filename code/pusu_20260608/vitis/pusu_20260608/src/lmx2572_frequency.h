#ifndef LMX2572_FREQUENCY_H
#define LMX2572_FREQUENCY_H

#include <stdint.h>

#include "lmx2572.h"

typedef struct {
    uint64_t requested_output_hz;
    uint64_t fvco_hz;
    uint16_t chdiv;
    uint32_t pll_n;
    uint32_t pll_num;
    uint32_t pll_den;
    uint8_t pfd_dly_sel;
    uint8_t is_integer_n;
} LMX2572_FrequencyPlan;

LMX2572_Status lmx2572_frequency_plan(uint64_t output_hz,
                                      uint64_t fpd_num_hz,
                                      uint64_t fpd_den,
                                      uint8_t mash_order,
                                      uint32_t fractional_denominator,
                                      LMX2572_FrequencyPlan *out_plan);

uint8_t lmx2572_chdiv_register_code(uint16_t chdiv, uint8_t *out_code);

#endif
