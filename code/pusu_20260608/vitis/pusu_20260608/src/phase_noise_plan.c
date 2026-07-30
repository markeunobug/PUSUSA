#include "phase_noise_plan.h"

#include <math.h>
#include <string.h>

static rbw_mode_t rbw_mode_for_offset(uint32_t offset_hz);

int phase_noise_plan_build(double start_offset_hz,
                           double stop_offset_hz,
                           uint16_t points_per_decade,
                           phase_noise_plan_t *plan)
{
    double log_start;
    double log_stop;
    double log_step;
    uint32_t requested_count;
    uint32_t build_count;
    uint32_t i;
    uint32_t last_offset_hz = 0U;

    if ((plan == 0) ||
        (start_offset_hz <= 0.0) ||
        (stop_offset_hz <= start_offset_hz) ||
        (points_per_decade == 0U)) {
        return -1;
    }

    memset(plan, 0, sizeof(*plan));

    log_start = log10(start_offset_hz);
    log_stop = log10(stop_offset_hz);
    requested_count =
        (uint32_t)(((log_stop - log_start) * (double)points_per_decade) + 0.5) + 1U;

    if (requested_count < 2U) {
        requested_count = 2U;
    }

    plan->requested_point_count = requested_count;
    build_count = requested_count;
    if (build_count > PHASE_NOISE_PLAN_MAX_POINTS) {
        build_count = PHASE_NOISE_PLAN_MAX_POINTS;
        plan->truncated = 1U;
        plan->warning_code = PHASE_NOISE_PLAN_WARN_TRUNCATED;
    }

    log_step = (build_count > 1U) ?
        ((log_stop - log_start) / (double)(build_count - 1U)) : 0.0;

    for (i = 0U; i < build_count; i++) {
        double value = pow(10.0, log_start + log_step * (double)i);
        uint32_t offset_hz = (uint32_t)(value + 0.5);
        rbw_mode_t rbw_mode;
        float rbw_hz;
        phase_noise_plan_point_t *point;

        if (offset_hz == 0U) {
            offset_hz = 1U;
        }
        if ((i > 0U) && (offset_hz <= last_offset_hz)) {
            offset_hz = last_offset_hz + 1U;
        }

        rbw_mode = rbw_mode_for_offset(offset_hz);
        rbw_hz = phase_noise_plan_rbw_hz(rbw_mode);

        point = &plan->points[plan->point_count];
        point->offset_hz = offset_hz;
        point->rbw_mode = rbw_mode;
        point->rbw_hz = rbw_hz;
        point->enbw_hz = phase_noise_plan_enbw_hz(rbw_mode);
        point->warning_code = ((float)offset_hz < rbw_hz) ?
            PHASE_NOISE_PLAN_WARN_OFFSET_BELOW_RBW : PHASE_NOISE_PLAN_WARN_NONE;

        plan->point_count++;
        last_offset_hz = offset_hz;
    }

    return (plan->point_count > 0U) ? 0 : -1;
}

const phase_noise_plan_point_t *phase_noise_plan_get_point(
    const phase_noise_plan_t *plan,
    uint32_t point_index)
{
    if ((plan == 0) || (point_index >= plan->point_count)) {
        return 0;
    }

    return &plan->points[point_index];
}

float phase_noise_plan_rbw_hz(rbw_mode_t mode)
{
    switch (mode) {
    case RBW_MODE_1K:
        return RBW_1K_HZ;
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
        return RBW_100K_HZ;
    }
}

float phase_noise_plan_enbw_hz(rbw_mode_t mode)
{
    switch (mode) {
    case RBW_MODE_1K:
        return RBW_1K_ENBW_HZ;
    case RBW_MODE_10K:
        return RBW_10K_ENBW_HZ;
    case RBW_MODE_30K:
        return RBW_30K_ENBW_HZ;
    case RBW_MODE_100K:
        return RBW_100K_ENBW_HZ;
    case RBW_MODE_300K:
        return RBW_300K_ENBW_HZ;
    case RBW_MODE_1M:
        return RBW_1M_ENBW_HZ;
    default:
        return RBW_100K_ENBW_HZ;
    }
}

static rbw_mode_t rbw_mode_for_offset(uint32_t offset_hz)
{
    /* Keep the close-in trace on one calibrated filter path through 300 kHz.
     * The 10 kHz mode is intentionally skipped to avoid a discontinuity at
     * 100 kHz; switch directly from 1 kHz to 30 kHz at 300 kHz. */
    if (offset_hz >= 10000000U) {
        return RBW_MODE_1M;
    }
    if (offset_hz >= 3000000U) {
        return RBW_MODE_300K;
    }
    if (offset_hz >= 1000000U) {
        return RBW_MODE_100K;
    }
    if (offset_hz >= 300000U) {
        return RBW_MODE_30K;
    }
    return RBW_MODE_1K;
}
