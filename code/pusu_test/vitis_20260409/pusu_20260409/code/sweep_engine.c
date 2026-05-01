#include "../code/sweep_engine.h"

#include <string.h>

#include "../code/dma_capture.h"
#include "../code/lo_control.h"
#include "../code/signal_processing.h"

#define SWEEP_ENGINE_LOCK_TIMEOUT_LOOPS   500000U
#define SWEEP_ENGINE_FRAME_TIMEOUT_LOOPS  500000U

static void sweep_engine_set_error(sweep_engine_t *engine, int error);
static int g_last_error = SWEEP_ENGINE_OK;

int sweep_engine_init(sweep_engine_t *engine)
{
    if (engine == 0) {
        g_last_error = SWEEP_ENGINE_ERR_BAD_ARG;
        return SWEEP_ENGINE_ERR_BAD_ARG;
    }

    memset(engine, 0, sizeof(*engine));
    engine->state = SWEEP_ENGINE_STATE_IDLE;
    engine->last_error = SWEEP_ENGINE_OK;
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
    engine->current_point = 0U;
    engine->current_rf_hz = 0ULL;
    engine->wait_counter = 0U;
    engine->current_power_dbm = 0.0f;
    engine->stop_requested = 0;
    engine->last_error = SWEEP_ENGINE_OK;
    g_last_error = SWEEP_ENGINE_OK;
    return SWEEP_ENGINE_OK;
}

int sweep_engine_start(sweep_engine_t *engine, const device_control_config_t *config)
{
    int status;

    if (engine == 0) {
        g_last_error = SWEEP_ENGINE_ERR_BAD_ARG;
        return SWEEP_ENGINE_ERR_BAD_ARG;
    }

    if (sweep_engine_is_active(engine) != 0) {
        sweep_engine_stop(engine);
    }

    status = sweep_engine_prepare(engine, config);
    if (status != SWEEP_ENGINE_OK) {
        return status;
    }

    engine->state = SWEEP_ENGINE_STATE_PREPARE;
    return SWEEP_ENGINE_OK;
}

void sweep_engine_stop(sweep_engine_t *engine)
{
    if (engine == 0) {
        return;
    }

    if (sweep_engine_is_active(engine) != 0) {
        engine->stop_requested = 1;
    }
}

int sweep_engine_poll(sweep_engine_t *engine)
{
    if (engine == 0) {
        g_last_error = SWEEP_ENGINE_ERR_BAD_ARG;
        return SWEEP_ENGINE_ERR_BAD_ARG;
    }

    if ((engine->stop_requested != 0) &&
        (engine->state != SWEEP_ENGINE_STATE_IDLE) &&
        (engine->state != SWEEP_ENGINE_STATE_DONE) &&
        (engine->state != SWEEP_ENGINE_STATE_ABORTED) &&
        (engine->state != SWEEP_ENGINE_STATE_ERROR)) {
        engine->state = SWEEP_ENGINE_STATE_ABORTED;
        engine->stop_requested = 0;
        return SWEEP_ENGINE_OK;
    }

    switch (engine->state) {
    case SWEEP_ENGINE_STATE_IDLE:
    case SWEEP_ENGINE_STATE_DONE:
    case SWEEP_ENGINE_STATE_ABORTED:
        return SWEEP_ENGINE_OK;

    case SWEEP_ENGINE_STATE_PREPARE:
        signal_processing_set_if_hz((float)LO_CONTROL_IF2_HZ);
        signal_processing_apply_rbw_mode(engine->plan.rbw_mode);
        engine->current_point = 0U;
        engine->state = SWEEP_ENGINE_STATE_SET_LO1;
        return SWEEP_ENGINE_OK;

    case SWEEP_ENGINE_STATE_SET_LO1:
        if (engine->current_point >= engine->point_count) {
            engine->state = SWEEP_ENGINE_STATE_DONE;
            g_last_error = SWEEP_ENGINE_OK;
            engine->last_error = SWEEP_ENGINE_OK;
            return SWEEP_ENGINE_OK;
        }

        engine->current_rf_hz = sweep_plan_get_rf_hz(&engine->plan, engine->current_point);
        if (lo_control_set_lo1_for_rf_hz(engine->current_rf_hz) != XST_SUCCESS) {
            sweep_engine_set_error(engine, SWEEP_ENGINE_ERR_LO1_SET);
            return SWEEP_ENGINE_ERR_LO1_SET;
        }

        engine->wait_counter = 0U;
        engine->state = SWEEP_ENGINE_STATE_WAIT_LO1_LOCK;
        return SWEEP_ENGINE_OK;

    case SWEEP_ENGINE_STATE_WAIT_LO1_LOCK:
        if (lo_control_is_locked(LO_CONTROL_DEVICE_LO1) == XST_SUCCESS) {
            engine->state = SWEEP_ENGINE_STATE_ARM_DMA;
            return SWEEP_ENGINE_OK;
        }

        engine->wait_counter++;
        if (engine->wait_counter >= SWEEP_ENGINE_LOCK_TIMEOUT_LOOPS) {
            sweep_engine_set_error(engine, SWEEP_ENGINE_ERR_LO1_LOCK_TIMEOUT);
            return SWEEP_ENGINE_ERR_LO1_LOCK_TIMEOUT;
        }
        return SWEEP_ENGINE_OK;

    case SWEEP_ENGINE_STATE_ARM_DMA:
        if (dma_capture_start() != XST_SUCCESS) {
            sweep_engine_set_error(engine, SWEEP_ENGINE_ERR_FRAME_TIMEOUT);
            return SWEEP_ENGINE_ERR_FRAME_TIMEOUT;
        }

        engine->wait_counter = 0U;
        engine->state = SWEEP_ENGINE_STATE_WAIT_FRAME;
        return SWEEP_ENGINE_OK;

    case SWEEP_ENGINE_STATE_WAIT_FRAME:
        if (dma_capture_take_error() != 0) {
            sweep_engine_set_error(engine, SWEEP_ENGINE_ERR_FRAME_TIMEOUT);
            return SWEEP_ENGINE_ERR_FRAME_TIMEOUT;
        }

        if (dma_capture_frame_ready() != 0) {
            engine->state = SWEEP_ENGINE_STATE_MEASURE;
            return SWEEP_ENGINE_OK;
        }

        engine->wait_counter++;
        if (engine->wait_counter >= SWEEP_ENGINE_FRAME_TIMEOUT_LOOPS) {
            sweep_engine_set_error(engine, SWEEP_ENGINE_ERR_FRAME_TIMEOUT);
            return SWEEP_ENGINE_ERR_FRAME_TIMEOUT;
        }
        return SWEEP_ENGINE_OK;

    case SWEEP_ENGINE_STATE_MEASURE:
        if (signal_processing_measure_power_dbm(dma_capture_get_rx_buffer(),
                                                &engine->current_power_dbm) != 0) {
            sweep_engine_set_error(engine, SWEEP_ENGINE_ERR_POWER_MEASURE);
            return SWEEP_ENGINE_ERR_POWER_MEASURE;
        }

        engine->points[engine->current_point].freq_hz = (double)engine->current_rf_hz;
        engine->points[engine->current_point].power_dbm = engine->current_power_dbm;
        engine->state = SWEEP_ENGINE_STATE_EMIT_POINT;
        return SWEEP_ENGINE_OK;

    case SWEEP_ENGINE_STATE_EMIT_POINT:
        if (engine->point_callback != 0) {
            if (engine->point_callback((uint32_t)engine->current_rf_hz,
                                       engine->current_power_dbm,
                                       engine->point_callback_context) != 0) {
                sweep_engine_set_error(engine, SWEEP_ENGINE_ERR_STREAM_CALLBACK);
                return SWEEP_ENGINE_ERR_STREAM_CALLBACK;
            }
        }

        engine->state = SWEEP_ENGINE_STATE_NEXT_POINT;
        return SWEEP_ENGINE_OK;

    case SWEEP_ENGINE_STATE_NEXT_POINT:
        engine->current_point++;
        if (engine->current_point >= engine->point_count) {
            engine->state = SWEEP_ENGINE_STATE_DONE;
            g_last_error = SWEEP_ENGINE_OK;
            engine->last_error = SWEEP_ENGINE_OK;
        } else {
            engine->state = SWEEP_ENGINE_STATE_SET_LO1;
        }
        return SWEEP_ENGINE_OK;

    case SWEEP_ENGINE_STATE_ERROR:
    default:
        return engine->last_error;
    }
}

int sweep_engine_is_active(const sweep_engine_t *engine)
{
    if (engine == 0) {
        return 0;
    }

    return (engine->state == SWEEP_ENGINE_STATE_PREPARE) ||
           (engine->state == SWEEP_ENGINE_STATE_SET_LO1) ||
           (engine->state == SWEEP_ENGINE_STATE_WAIT_LO1_LOCK) ||
           (engine->state == SWEEP_ENGINE_STATE_ARM_DMA) ||
           (engine->state == SWEEP_ENGINE_STATE_WAIT_FRAME) ||
           (engine->state == SWEEP_ENGINE_STATE_MEASURE) ||
           (engine->state == SWEEP_ENGINE_STATE_EMIT_POINT) ||
           (engine->state == SWEEP_ENGINE_STATE_NEXT_POINT);
}

sweep_engine_state_t sweep_engine_get_state(const sweep_engine_t *engine)
{
    return (engine == 0) ? SWEEP_ENGINE_STATE_ERROR : engine->state;
}

uint32_t sweep_engine_get_current_point(const sweep_engine_t *engine)
{
    return (engine == 0) ? 0U : engine->current_point;
}

uint32_t sweep_engine_get_total_points(const sweep_engine_t *engine)
{
    return (engine == 0) ? 0U : engine->point_count;
}

int sweep_engine_run_blocking(sweep_engine_t *engine)
{
    if (engine == 0) {
        g_last_error = SWEEP_ENGINE_ERR_BAD_ARG;
        return SWEEP_ENGINE_ERR_BAD_ARG;
    }

    signal_processing_set_if_hz((float)LO_CONTROL_IF2_HZ);
    signal_processing_apply_rbw_mode(engine->plan.rbw_mode);
    engine->state = SWEEP_ENGINE_STATE_PREPARE;

    while (sweep_engine_is_active(engine) != 0) {
        int status = sweep_engine_poll(engine);
        if (status != SWEEP_ENGINE_OK) {
            return status;
        }
    }

    return (engine->state == SWEEP_ENGINE_STATE_ERROR) ? engine->last_error : SWEEP_ENGINE_OK;
}

int sweep_engine_get_last_error(void)
{
    return g_last_error;
}

static void sweep_engine_set_error(sweep_engine_t *engine, int error)
{
    if (engine != 0) {
        engine->last_error = error;
        engine->state = SWEEP_ENGINE_STATE_ERROR;
    }
    g_last_error = error;
}
