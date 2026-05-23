#ifndef SWEEP_PLAN_H
#define SWEEP_PLAN_H

#include <stdint.h>

#include "../code/app_config.h"
#include "../code/device_protocol.h"

#define SWEEP_PLAN_MAX_POINTS 4096U

typedef struct {
    uint64_t start_hz;
    uint64_t stop_hz;
    uint64_t step_hz;
    uint32_t point_count;
    rbw_mode_t rbw_mode;
    float rbw_hz;
} sweep_plan_t;

int sweep_plan_build(const device_control_config_t *config, sweep_plan_t *plan);
uint64_t sweep_plan_get_rf_hz(const sweep_plan_t *plan, uint32_t point_index);

#endif
