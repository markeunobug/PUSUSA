#include "../code/sweep_engine.h"

#include <string.h>

#include "../code/dma_capture.h"
#include "../code/lo_control.h"
#include "../code/signal_processing.h"

#define SWEEP_ENGINE_LOCK_TIMEOUT_LOOPS   500000U
#define SWEEP_ENGINE_FRAME_TIMEOUT_LOOPS  500000U

static int sweep_engine_wait_frame(void);
static int g_last_error = SWEEP_ENGINE_OK;

int sweep_engine_init(sweep_engine_t *engine)
{
    if (engine == 0) {
        g_last_error = SWEEP_ENGINE_ERR_BAD_ARG;
        return SWEEP_ENGINE_ERR_BAD_ARG;
    }

    memset(engine, 0, sizeof(*engine));
    g_last_error = SWEEP_ENGINE_OK;
    return SWEEP_ENGINE_OK;
}

void sweep_engine_set_point_callback(sweep_engine_t *engine,
                                     sweep_engine_point_callback_t callback,
                                     void *context)
{
    if (engine == 0) {
        return;
    }

    engine->point_callback = callback;
    engine->point_callback_context = context;
}

int sweep_engine_prepare(sweep_engine_t *engine, const device_control_config_t *config)
{
    if ((engine == 0) || (config == 0)) {
        g_last_error = SWEEP_ENGINE_ERR_BAD_ARG;
        return SWEEP_ENGINE_ERR_BAD_ARG;
    }

    if (sweep_plan_build(config, &engine->plan) != 0) {
        g_last_error = SWEEP_ENGINE_ERR_PLAN;
        return SWEEP_ENGINE_ERR_PLAN;
    }

    engine->point_count = engine->plan.point_count;
    g_last_error = SWEEP_ENGINE_OK;
    return SWEEP_ENGINE_OK;
}

int sweep_engine_run_blocking(sweep_engine_t *engine)
{
    uint32_t i;

    if (engine == 0) {
        g_last_error = SWEEP_ENGINE_ERR_BAD_ARG;
        return SWEEP_ENGINE_ERR_BAD_ARG;
    }

    signal_processing_set_if_hz((float)LO_CONTROL_IF2_HZ);
    signal_processing_apply_rbw_mode(engine->plan.rbw_mode);

    for (i = 0U; i < engine->point_count; i++) {
        uint64_t rf_hz = sweep_plan_get_rf_hz(&engine->plan, i);
        float power_dbm = 0.0f;

        if (lo_control_set_lo1_for_rf_hz(rf_hz) != XST_SUCCESS) {
            g_last_error = SWEEP_ENGINE_ERR_LO1_SET;
            return SWEEP_ENGINE_ERR_LO1_SET;
        }

        if (lo_control_wait_lock(LO_CONTROL_DEVICE_LO1, SWEEP_ENGINE_LOCK_TIMEOUT_LOOPS) != XST_SUCCESS) {
            g_last_error = SWEEP_ENGINE_ERR_LO1_LOCK_TIMEOUT;
            return SWEEP_ENGINE_ERR_LO1_LOCK_TIMEOUT;
        }

        if (dma_capture_start() != XST_SUCCESS) {
            g_last_error = SWEEP_ENGINE_ERR_FRAME_TIMEOUT;
            return SWEEP_ENGINE_ERR_FRAME_TIMEOUT;
        }

        if (sweep_engine_wait_frame() != XST_SUCCESS) {
            g_last_error = SWEEP_ENGINE_ERR_FRAME_TIMEOUT;
            return SWEEP_ENGINE_ERR_FRAME_TIMEOUT;
        }

        if (signal_processing_measure_power_dbm(dma_capture_get_rx_buffer(), &power_dbm) != 0) {
            g_last_error = SWEEP_ENGINE_ERR_POWER_MEASURE;
            return SWEEP_ENGINE_ERR_POWER_MEASURE;
        }

        engine->points[i].freq_hz = (double)rf_hz;
        engine->points[i].power_dbm = power_dbm;

        if (engine->point_callback != 0) {
            if (engine->point_callback((uint32_t)rf_hz,
                                       power_dbm,
                                       engine->point_callback_context) != 0) {
                g_last_error = SWEEP_ENGINE_ERR_STREAM_CALLBACK;
                return SWEEP_ENGINE_ERR_STREAM_CALLBACK;
            }
        }
    }

    g_last_error = SWEEP_ENGINE_OK;
    return SWEEP_ENGINE_OK;
}

int sweep_engine_get_last_error(void)
{
    return g_last_error;
}

static int sweep_engine_wait_frame(void)
{
    uint32_t i;

    for (i = 0U; i < SWEEP_ENGINE_FRAME_TIMEOUT_LOOPS; i++) {
        if (dma_capture_take_error() != 0) {
            return XST_FAILURE;
        }

        if (dma_capture_frame_ready() != 0) {
            return XST_SUCCESS;
        }
    }

    return XST_FAILURE;
}
