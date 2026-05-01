#include "../code/sweep_plan.h"

static float sweep_plan_rbw_hz(rbw_mode_t mode, double requested_hz)
{
    switch (mode) {
    case RBW_MODE_10K:
        return RBW_10K_HZ;
    case RBW_MODE_30K:
        return RBW_30K_HZ;
    case RBW_MODE_100K:
        return RBW_100K_HZ;
    case RBW_MODE_300K:
        return RBW_300K_HZ;
    case RBW_MODE_1M:
        return RBW_1M_HZ;
    default:
        if (requested_hz > 0.0) {
            return (float)requested_hz;
        }
        return RBW_100K_HZ;
    }
}

//设置扫频参数，输入配置扫频的配置 config ，输出计划扫描的方案 plan
int sweep_plan_build(const device_control_config_t *config, sweep_plan_t *plan)
{
    uint64_t start_hz;
    uint64_t stop_hz;
    uint64_t span_hz;
    uint64_t step_hz;
    uint64_t raw_point_count;
    rbw_mode_t rbw_mode;
    float rbw_hz;

    if ((config == 0) || (plan == 0)) {
        return -1;
    }

    start_hz = (config->frequency.start_hz > 0.0) ? (uint64_t)config->frequency.start_hz : 0ULL;
    stop_hz = (config->frequency.stop_hz > 0.0) ? (uint64_t)config->frequency.stop_hz : 0ULL;
    if (stop_hz <= start_hz) {
        return -1;
    }

    rbw_mode = (rbw_mode_t)config->bandwidth.rbw_mode;
    rbw_hz = sweep_plan_rbw_hz(rbw_mode, config->bandwidth.rbw_hz);

    /* Internal sweep density rule:
     * 步长 step = RBW / 2
     * This keeps the internal sweep spacing tied to RBW so narrow peaks
     * are less likely to be skipped by an overly sparse fixed point count.
     */
    step_hz = (uint64_t)(rbw_hz * 0.5f);
    if (step_hz == 0ULL) {
        step_hz = 1ULL;
    }

    span_hz = stop_hz - start_hz;
    raw_point_count = (span_hz / step_hz) + 1ULL;
    if (raw_point_count > SWEEP_PLAN_MAX_POINTS) {
        raw_point_count = SWEEP_PLAN_MAX_POINTS;
    }

    if (raw_point_count < 2ULL) {
        raw_point_count = 2ULL;
    }

    plan->start_hz = start_hz;
    plan->stop_hz = stop_hz;
    plan->step_hz = step_hz;
    plan->point_count = (uint32_t)raw_point_count;
    plan->rbw_mode = rbw_mode;
    plan->rbw_hz = rbw_hz;
    return 0;
}

uint64_t sweep_plan_get_rf_hz(const sweep_plan_t *plan, uint32_t point_index)
{
    if (plan == 0) {
        return 0ULL;
    }

    if (point_index >= plan->point_count) {
        point_index = plan->point_count - 1U;
    }

    return plan->start_hz + (uint64_t)point_index * plan->step_hz;
}
