#ifndef PHASE_NOISE_PLAN_H
#define PHASE_NOISE_PLAN_H

#include <stdint.h>

#include "app_config.h"

#define PHASE_NOISE_PLAN_MAX_POINTS 384U

#define PHASE_NOISE_PLAN_WARN_NONE             0U
#define PHASE_NOISE_PLAN_WARN_OFFSET_BELOW_RBW 1U
#define PHASE_NOISE_PLAN_WARN_TRUNCATED        6U

typedef struct {
    uint32_t offset_hz;
    rbw_mode_t rbw_mode;
    float rbw_hz;
    float enbw_hz;
    uint16_t warning_code;
} phase_noise_plan_point_t;

typedef struct {
    uint32_t point_count;
    uint32_t requested_point_count;
    uint16_t warning_code;
    uint8_t truncated;
    uint8_t reserved;
    phase_noise_plan_point_t points[PHASE_NOISE_PLAN_MAX_POINTS];
} phase_noise_plan_t;

int phase_noise_plan_build(double start_offset_hz,
                           double stop_offset_hz,
                           uint16_t points_per_decade,
                           phase_noise_plan_t *plan);
const phase_noise_plan_point_t *phase_noise_plan_get_point(
    const phase_noise_plan_t *plan,
    uint32_t point_index);
float phase_noise_plan_rbw_hz(rbw_mode_t mode);
float phase_noise_plan_enbw_hz(rbw_mode_t mode);

#endif
