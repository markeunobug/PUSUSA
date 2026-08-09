#ifndef LMX2572_PFD_PROFILE_H
#define LMX2572_PFD_PROFILE_H

#include <stdint.h>

#include "lmx2572.h"

typedef enum {
    LMX2572_PFD_PROFILE_P100 = 0,
    LMX2572_PFD_PROFILE_P75 = 1,
    LMX2572_PFD_PROFILE_COUNT
} LMX2572_PfdProfileId;

typedef struct {
    LMX2572_PfdProfileId id;
    uint32_t ref_hz;
    uint8_t osc_2x;
    uint8_t pll_r_pre;
    uint8_t mult;
    uint8_t pll_r;
    uint64_t fpd_num_hz;
    uint64_t fpd_den;
    uint8_t cpg_code;
    uint8_t mash_order;
    uint8_t qualified;
    uint32_t lock_timeout_loops;
    uint32_t analog_settle_us;
    uint32_t discard_frames;
    int32_t gain_correction_mdB;
    uint64_t spur_grid_num_hz;
    uint64_t spur_grid_den;
    int64_t spur_grid_origin_hz;
    uint8_t spur_model_valid;
} LMX2572_PfdProfile;

const LMX2572_PfdProfile *lmx2572_pfd_profile_get(uint8_t profile_id);
LMX2572_Status lmx2572_pfd_profile_validate(
    const LMX2572_PfdProfile *profile,
    uint64_t output_hz);
LMX2572_Status lmx2572_pfd_profile_apply(
    LMX2572_Device *dev,
    const LMX2572_PfdProfile *profile,
    uint64_t output_hz);

#endif
