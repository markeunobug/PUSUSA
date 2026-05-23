#include "phase_noise_engine.h"

#include <math.h>
#include <string.h>

#include "amplitude_correction.h"
#include "dma_capture.h"
#include "lo_control.h"
#include "profile_timer.h"
#include "signal_processing.h"
#include "xstatus.h"
#include "xtime_l.h"

#define PN_LOCK_TIMEOUT_LOOPS   500000U
#define PN_FRAME_TIMEOUT_LOOPS  500000U
#define PN_RF_MIN_HZ            1ULL
#define PN_RF_MAX_HZ            1500000000ULL
#define PN_DEFAULT_CARRIER_SEARCH_SPAN_HZ 100000UL
#define PN_CARRIER_COARSE_DEFAULT_STEP_HZ 10000UL
#define PN_CARRIER_FINE_STEP_HZ           1000UL
#define PN_CARRIER_COARSE_RBW_MODE        RBW_MODE_100K
#define PN_CARRIER_FINE_RBW_MODE          RBW_MODE_10K
#define PN_DEFAULT_MIN_CARRIER_DBM        (-50)
#define PN_MIN_REASONABLE_CARRIER_DBM     (-120)
#define PN_MAX_REASONABLE_CARRIER_DBM     30

static uint16_t g_next_trace_id = 1U;

static int validate_config(const phase_noise_config_t *config);
static uint32_t effective_search_span_hz(const phase_noise_config_t *config);
static int8_t effective_min_carrier_dbm(const phase_noise_config_t *config);
static uint64_t round_to_step_hz(uint64_t value_hz, uint64_t step_hz);
static void begin_carrier_search(phase_noise_engine_t *engine);
static void start_carrier_search_stage(phase_noise_engine_t *engine,
                                       uint64_t center_hz,
                                       uint64_t span_hz,
                                       uint64_t step_hz,
                                       uint8_t stage);
static int advance_carrier_search(phase_noise_engine_t *engine);
static void set_error(phase_noise_engine_t *engine, phase_noise_error_t error);
static void emit_status(phase_noise_engine_t *engine);
static int emit_data_point(phase_noise_engine_t *engine, uint8_t done);
static int prepare_measurement(phase_noise_engine_t *engine);
static int start_current_point(phase_noise_engine_t *engine);
static int finish_current_measurement(phase_noise_engine_t *engine);
static uint64_t current_target_rf_hz(const phase_noise_engine_t *engine);
static uint64_t carrier_search_target_hz(const phase_noise_engine_t *engine);
static rbw_mode_t carrier_search_rbw_mode(const phase_noise_engine_t *engine);
static uint32_t carrier_search_rbw_hz(const phase_noise_engine_t *engine);
static int rf_in_range(uint64_t rf_hz);
static uint16_t status_flags(const phase_noise_engine_t *engine);
static uint16_t active_warning_code(const phase_noise_engine_t *engine);
static uint32_t elapsed_ms(const phase_noise_engine_t *engine);

int phase_noise_engine_init(phase_noise_engine_t *engine)
{
    if (engine == 0) {
        return -1;
    }

    memset(engine, 0, sizeof(*engine));
    engine->state = PN_STATE_IDLE;
    engine->step = PN_STEP_IDLE;
    engine->last_error = PN_ERR_OK;
    return 0;
}

int phase_noise_engine_configure(phase_noise_engine_t *engine,
                                 const phase_noise_config_t *config)
{
    phase_noise_config_t sanitized_config;

    if ((engine == 0) || (config == 0)) {
        return -1;
    }

    if (phase_noise_engine_is_active(engine) != 0) {
        engine->last_error = PN_ERR_BUSY;
        return -1;
    }

    sanitized_config = *config;
    sanitized_config.carrier_search_span_hz = effective_search_span_hz(config);
    sanitized_config.minimum_carrier_level_dbm = effective_min_carrier_dbm(config);

    if (validate_config(&sanitized_config) != 0) {
        engine->last_error = PN_ERR_BAD_CONFIG;
        engine->state = PN_STATE_ERROR;
        return -1;
    }

    if (phase_noise_plan_build(sanitized_config.start_offset_hz,
                               sanitized_config.stop_offset_hz,
                               sanitized_config.points_per_decade,
                               &engine->plan) != 0) {
        engine->last_error = PN_ERR_BAD_CONFIG;
        engine->state = PN_STATE_ERROR;
        return -1;
    }

    engine->config = sanitized_config;
    engine->configured = 1U;
    engine->carrier_valid = 0U;
    engine->data_valid = 0U;
    engine->stop_requested = 0U;
    engine->current_index = 0U;
    engine->average_index = 0U;
    engine->plan_warning = (engine->plan.truncated != 0U) ?
        PHASE_NOISE_WARN_PLAN_TRUNCATED : PHASE_NOISE_WARN_NONE;
    engine->last_warning = PHASE_NOISE_WARN_NONE;
    engine->last_error = PN_ERR_OK;
    engine->state = PN_STATE_CONFIGURED;
    engine->step = PN_STEP_IDLE;
    memset(engine->average_noise_mw, 0, sizeof(engine->average_noise_mw));
    return 0;
}

int phase_noise_engine_start(phase_noise_engine_t *engine)
{
    XTime now;

    if (engine == 0) {
        return -1;
    }
    if (phase_noise_engine_is_active(engine) != 0) {
        engine->last_error = PN_ERR_BUSY;
        return -1;
    }
    if (engine->configured == 0U) {
        engine->last_error = PN_ERR_NOT_CONFIGURED;
        engine->state = PN_STATE_ERROR;
        return -1;
    }

    XTime_GetTime(&now);
    engine->start_ticks = (uint64_t)now;
    engine->trace_id = g_next_trace_id++;
    if (g_next_trace_id == 0U) {
        g_next_trace_id = 1U;
    }

    engine->current_index = 0U;
    engine->average_index = 1U;
    engine->current_offset_hz = 0U;
    engine->current_rbw_hz = 0U;
    engine->current_rf_hz = 0ULL;
    engine->measured_carrier_hz =
        (engine->config.nominal_carrier_hz > 0.0) ?
        (uint64_t)(engine->config.nominal_carrier_hz + 0.5) : 0ULL;
    engine->carrier_candidate_hz = engine->measured_carrier_hz;
    engine->carrier_search_center_hz = engine->measured_carrier_hz;
    engine->carrier_search_start_hz = engine->measured_carrier_hz;
    engine->carrier_search_step_hz = PN_CARRIER_FINE_STEP_HZ;
    engine->carrier_coarse_best_hz = engine->measured_carrier_hz;
    engine->carrier_level_dbm = 0.0f;
    engine->best_carrier_level_dbm = -200.0f;
    engine->carrier_valid = 0U;
    engine->data_valid = 0U;
    engine->stop_requested = 0U;
    engine->wait_counter = 0U;
    engine->last_warning = engine->plan_warning;
    engine->last_error = PN_ERR_OK;
    memset(engine->average_noise_mw, 0, sizeof(engine->average_noise_mw));

    engine->state = PN_STATE_SEARCHING_CARRIER;
    engine->step = PN_STEP_PREPARE_CARRIER;
    begin_carrier_search(engine);

    return 0;
}

void phase_noise_engine_stop(phase_noise_engine_t *engine)
{
    if (engine == 0) {
        return;
    }

    if (phase_noise_engine_is_active(engine) != 0) {
        engine->stop_requested = 1U;
        engine->state = PN_STATE_STOPPING;
    }
}

int phase_noise_engine_poll(phase_noise_engine_t *engine)
{
    if (engine == 0) {
        return -1;
    }

    if (engine->stop_requested != 0U) {
        engine->stop_requested = 0U;
        engine->step = PN_STEP_IDLE;
        engine->state = PN_STATE_IDLE;
        engine->last_error = PN_ERR_STOPPED_BY_HOST;
        emit_status(engine);
        return 0;
    }

    switch (engine->step) {
    case PN_STEP_IDLE:
        return 0;

    case PN_STEP_PREPARE_CARRIER:
    {
        rbw_mode_t search_rbw_mode = carrier_search_rbw_mode(engine);

        signal_processing_set_if_hz((float)LO_CONTROL_IF2_HZ);
        signal_processing_apply_rbw_mode(search_rbw_mode);
        sweep_profile_reset((uint8_t)search_rbw_mode);
        engine->current_rbw_hz = carrier_search_rbw_hz(engine);
        engine->current_offset_hz = 0U;
        engine->current_rf_hz = carrier_search_target_hz(engine);
        engine->step = PN_STEP_SET_LO;
        return 0;
    }

    case PN_STEP_SET_LO:
        return start_current_point(engine);

    case PN_STEP_WAIT_LO_LOCK:
        if (lo_control_is_locked(LO_CONTROL_DEVICE_LO1) == XST_SUCCESS) {
            sweep_profile_end(SWEEP_PROFILE_SECTION_WAIT_LOCK);
            engine->step = PN_STEP_ARM_DMA;
            return 0;
        }
        engine->wait_counter++;
        if (engine->wait_counter >= PN_LOCK_TIMEOUT_LOOPS) {
            sweep_profile_end(SWEEP_PROFILE_SECTION_WAIT_LOCK);
            sweep_profile_end(SWEEP_PROFILE_SECTION_POINT_TOTAL);
            set_error(engine, PN_ERR_LO_LOCK_TIMEOUT);
            return -1;
        }
        return 0;

    case PN_STEP_ARM_DMA:
        sweep_profile_begin(SWEEP_PROFILE_SECTION_DMA_RESET);
        if (dma_capture_reset() != XST_SUCCESS) {
            sweep_profile_end(SWEEP_PROFILE_SECTION_DMA_RESET);
            sweep_profile_end(SWEEP_PROFILE_SECTION_POINT_TOTAL);
            set_error(engine, PN_ERR_DMA_TIMEOUT);
            return -1;
        }
        sweep_profile_end(SWEEP_PROFILE_SECTION_DMA_RESET);
        /* fall through */

    case PN_STEP_REARM_DMA:
        if (engine->step == PN_STEP_REARM_DMA) {
            sweep_profile_note_dma_rearm();
        }
        sweep_profile_begin(SWEEP_PROFILE_SECTION_DMA_START);
        if (dma_capture_start((u32)(signal_processing_get_dma_samples() * 2U)) != XST_SUCCESS) {
            sweep_profile_end(SWEEP_PROFILE_SECTION_DMA_START);
            sweep_profile_end(SWEEP_PROFILE_SECTION_POINT_TOTAL);
            set_error(engine, PN_ERR_DMA_TIMEOUT);
            return -1;
        }
        sweep_profile_end(SWEEP_PROFILE_SECTION_DMA_START);

        engine->wait_counter = 0U;
        engine->step = PN_STEP_WAIT_FRAME;
        sweep_profile_begin(SWEEP_PROFILE_SECTION_DMA_WAIT);
        return 0;

    case PN_STEP_WAIT_FRAME:
        if (dma_capture_take_error() != 0) {
            sweep_profile_end(SWEEP_PROFILE_SECTION_DMA_WAIT);
            sweep_profile_end(SWEEP_PROFILE_SECTION_POINT_TOTAL);
            set_error(engine, PN_ERR_DMA_TIMEOUT);
            return -1;
        }

        if (dma_capture_frame_ready() != 0) {
            sweep_profile_end(SWEEP_PROFILE_SECTION_DMA_WAIT);
            sweep_profile_begin(SWEEP_PROFILE_SECTION_ACCUMULATE);
            signal_processing_accumulate_dma(dma_capture_get_rx_buffer(),
                                             signal_processing_get_dma_samples());
            sweep_profile_end(SWEEP_PROFILE_SECTION_ACCUMULATE);

            engine->step = (signal_processing_accumulation_ready() != 0) ?
                PN_STEP_MEASURE : PN_STEP_REARM_DMA;
            return 0;
        }

        engine->wait_counter++;
        if (engine->wait_counter >= PN_FRAME_TIMEOUT_LOOPS) {
            sweep_profile_end(SWEEP_PROFILE_SECTION_DMA_WAIT);
            sweep_profile_end(SWEEP_PROFILE_SECTION_POINT_TOTAL);
            set_error(engine, PN_ERR_DMA_TIMEOUT);
            return -1;
        }
        return 0;

    case PN_STEP_MEASURE:
        return finish_current_measurement(engine);

    case PN_STEP_EMIT_POINT:
    {
        uint8_t done = ((engine->config.flags & PHASE_NOISE_FLAG_CONTINUOUS) == 0U) &&
            (engine->average_index >= engine->config.average_count) &&
            ((uint32_t)engine->current_index + 1U >= engine->plan.point_count);
        return emit_data_point(engine, done);
    }

    case PN_STEP_NEXT_POINT:
        return prepare_measurement(engine);

    case PN_STEP_STOPPING:
    default:
        set_error(engine, PN_ERR_INTERNAL);
        return -1;
    }
}

int phase_noise_engine_is_active(const phase_noise_engine_t *engine)
{
    if (engine == 0) {
        return 0;
    }

    return (engine->state == PN_STATE_SEARCHING_CARRIER) ||
           (engine->state == PN_STATE_MEASURING) ||
           (engine->state == PN_STATE_STOPPING);
}

void phase_noise_engine_get_status(const phase_noise_engine_t *engine,
                                   phase_noise_status_t *status)
{
    if (status == 0) {
        return;
    }

    memset(status, 0, sizeof(*status));
    status->version = PHASE_NOISE_VERSION;

    if (engine == 0) {
        status->state = (uint8_t)PN_STATE_ERROR;
        status->error_code = (uint8_t)PN_ERR_INTERNAL;
        return;
    }

    status->state = (uint8_t)engine->state;
    status->flags = (uint8_t)status_flags(engine);
    status->error_code = (uint8_t)engine->last_error;
    status->trace_id = engine->trace_id;
    status->total_points = (uint16_t)engine->plan.point_count;
    status->current_index = engine->current_index;
    status->average_index = engine->average_index;
    status->nominal_carrier_hz = engine->config.nominal_carrier_hz;
    status->measured_carrier_hz = (double)engine->measured_carrier_hz;
    status->carrier_level_dbm = engine->carrier_level_dbm;
    status->start_offset_hz = engine->config.start_offset_hz;
    status->stop_offset_hz = engine->config.stop_offset_hz;
    status->current_offset_hz = engine->current_offset_hz;
    status->current_rbw_hz = engine->current_rbw_hz;
    status->elapsed_ms = elapsed_ms(engine);
    status->warning_code = active_warning_code(engine);
}

void phase_noise_engine_set_callbacks(phase_noise_engine_t *engine,
                                      phase_noise_data_callback_t data_callback,
                                      void *data_context,
                                      phase_noise_status_callback_t status_callback,
                                      void *status_context)
{
    if (engine == 0) {
        return;
    }

    engine->data_callback = data_callback;
    engine->data_callback_context = data_context;
    engine->status_callback = status_callback;
    engine->status_callback_context = status_context;
}

static int validate_config(const phase_noise_config_t *config)
{
    if (config == 0) {
        return -1;
    }
    if (config->version != PHASE_NOISE_VERSION) {
        return -1;
    }
    if ((config->flags & ~(PHASE_NOISE_FLAG_CONTINUOUS |
                           PHASE_NOISE_FLAG_ALLOW_ESTIMATED_ENBW |
                           PHASE_NOISE_FLAG_EMIT_INTERMEDIATE_AVERAGES)) != 0U) {
        return -1;
    }
    if ((config->flags & PHASE_NOISE_FLAG_ALLOW_ESTIMATED_ENBW) == 0U) {
        return -1;
    }
    if ((config->carrier_mode != PHASE_NOISE_CARRIER_MANUAL) &&
        (config->carrier_mode != PHASE_NOISE_CARRIER_AUTO)) {
        return -1;
    }
    if (config->sideband_mode != PHASE_NOISE_SIDEBAND_UPPER) {
        return -1;
    }
    if ((config->start_offset_hz <= 0.0) ||
        (config->stop_offset_hz <= config->start_offset_hz) ||
        (config->points_per_decade == 0U) ||
        (config->points_per_decade > 100U) ||
        (config->average_count == 0U)) {
        return -1;
    }
    if ((config->carrier_mode == PHASE_NOISE_CARRIER_MANUAL) &&
        ((config->nominal_carrier_hz < (double)PN_RF_MIN_HZ) ||
         (config->nominal_carrier_hz > (double)PN_RF_MAX_HZ))) {
        return -1;
    }
    if ((config->carrier_mode == PHASE_NOISE_CARRIER_AUTO) &&
        (config->nominal_carrier_hz <= 0.0)) {
        return -1;
    }

    return 0;
}

static uint32_t effective_search_span_hz(const phase_noise_config_t *config)
{
    if ((config == 0) || (config->carrier_search_span_hz == 0U)) {
        return PN_DEFAULT_CARRIER_SEARCH_SPAN_HZ;
    }
    return config->carrier_search_span_hz;
}

static int8_t effective_min_carrier_dbm(const phase_noise_config_t *config)
{
    if (config == 0) {
        return (int8_t)PN_DEFAULT_MIN_CARRIER_DBM;
    }
    if ((config->carrier_search_span_hz == 0U) &&
        (config->minimum_carrier_level_dbm == 0)) {
        return (int8_t)PN_DEFAULT_MIN_CARRIER_DBM;
    }
    if ((config->minimum_carrier_level_dbm < PN_MIN_REASONABLE_CARRIER_DBM) ||
        (config->minimum_carrier_level_dbm > PN_MAX_REASONABLE_CARRIER_DBM)) {
        return (int8_t)PN_DEFAULT_MIN_CARRIER_DBM;
    }
    return config->minimum_carrier_level_dbm;
}

static uint64_t round_to_step_hz(uint64_t value_hz, uint64_t step_hz)
{
    if (step_hz == 0ULL) {
        return value_hz;
    }
    return ((value_hz + (step_hz / 2ULL)) / step_hz) * step_hz;
}

static void begin_carrier_search(phase_noise_engine_t *engine)
{
    uint64_t span_hz;
    uint64_t coarse_step_hz;

    if (engine == 0) {
        return;
    }

    span_hz = (uint64_t)effective_search_span_hz(&engine->config);
    coarse_step_hz = span_hz / 20ULL;
    if (coarse_step_hz < PN_CARRIER_FINE_STEP_HZ) {
        coarse_step_hz = PN_CARRIER_FINE_STEP_HZ;
    }
    if (coarse_step_hz > PN_CARRIER_COARSE_DEFAULT_STEP_HZ) {
        coarse_step_hz = PN_CARRIER_COARSE_DEFAULT_STEP_HZ;
    }
    coarse_step_hz = round_to_step_hz(coarse_step_hz, PN_CARRIER_FINE_STEP_HZ);
    if (coarse_step_hz == 0ULL) {
        coarse_step_hz = PN_CARRIER_FINE_STEP_HZ;
    }

    engine->carrier_coarse_best_hz = engine->measured_carrier_hz;
    engine->best_carrier_level_dbm = -200.0f;
    engine->carrier_level_dbm = 0.0f;
    engine->carrier_valid = 0U;
    start_carrier_search_stage(engine,
                               engine->measured_carrier_hz,
                               span_hz,
                               coarse_step_hz,
                               0U);
    engine->step = PN_STEP_PREPARE_CARRIER;
}

static void start_carrier_search_stage(phase_noise_engine_t *engine,
                                       uint64_t center_hz,
                                       uint64_t span_hz,
                                       uint64_t step_hz,
                                       uint8_t stage)
{
    uint64_t half_span_hz;
    uint64_t start_hz;
    uint64_t end_hz;

    if (engine == 0) {
        return;
    }
    if (step_hz == 0ULL) {
        step_hz = PN_CARRIER_FINE_STEP_HZ;
    }

    half_span_hz = span_hz / 2ULL;
    start_hz = (center_hz > half_span_hz) ? (center_hz - half_span_hz) : 0ULL;
    end_hz = center_hz + half_span_hz;
    if (end_hz < center_hz) {
        end_hz = UINT64_MAX;
    }

    start_hz = (start_hz / step_hz) * step_hz;
    if (start_hz == 0ULL) {
        start_hz = PN_RF_MIN_HZ;
    }

    engine->carrier_search_center_hz = center_hz;
    engine->carrier_search_start_hz = start_hz;
    engine->carrier_search_step_hz = step_hz;
    engine->carrier_search_count =
        (uint16_t)(((end_hz - start_hz) / step_hz) + 1ULL);
    if (engine->carrier_search_count == 0U) {
        engine->carrier_search_count = 1U;
    }
    engine->carrier_search_index = 0U;
    engine->carrier_search_stage = stage;
    engine->carrier_candidate_hz = carrier_search_target_hz(engine);
    engine->step = PN_STEP_SET_LO;
}

static int advance_carrier_search(phase_noise_engine_t *engine)
{
    uint64_t fine_span_hz;

    if (engine == 0) {
        return -1;
    }

    engine->carrier_search_index++;
    while (engine->carrier_search_index < engine->carrier_search_count) {
        engine->carrier_candidate_hz = carrier_search_target_hz(engine);
        if (rf_in_range(engine->carrier_candidate_hz) != 0) {
            engine->step = PN_STEP_SET_LO;
            return 0;
        }
        engine->carrier_search_index++;
    }

    if (engine->carrier_search_stage == 0U) {
        if (engine->best_carrier_level_dbm <= -199.0f) {
            engine->last_warning = PHASE_NOISE_WARN_RF_RANGE_CLIPPED;
            set_error(engine, PN_ERR_CARRIER_NOT_FOUND);
            return -1;
        }

        engine->carrier_coarse_best_hz = engine->measured_carrier_hz;
        fine_span_hz = engine->carrier_search_step_hz * 2ULL;
        engine->best_carrier_level_dbm = -200.0f;
        start_carrier_search_stage(engine,
                                   engine->carrier_coarse_best_hz,
                                   fine_span_hz,
                                   PN_CARRIER_FINE_STEP_HZ,
                                   1U);
        return 0;
    }

    if (engine->best_carrier_level_dbm < (float)engine->config.minimum_carrier_level_dbm) {
        engine->carrier_valid = 0U;
        engine->last_warning = PHASE_NOISE_WARN_CARRIER_LEVEL_LOW;
        set_error(engine, PN_ERR_CARRIER_NOT_FOUND);
        return -1;
    }

    engine->carrier_valid = 1U;
    engine->carrier_level_dbm = engine->best_carrier_level_dbm;
    engine->last_warning = engine->plan_warning;
    engine->state = PN_STATE_MEASURING;
    engine->current_index = 0U;
    engine->average_index = 1U;
    engine->step = PN_STEP_SET_LO;
    emit_status(engine);
    return 0;
}

static void set_error(phase_noise_engine_t *engine, phase_noise_error_t error)
{
    if (engine == 0) {
        return;
    }

    engine->last_error = error;
    engine->state = PN_STATE_ERROR;
    engine->step = PN_STEP_IDLE;
    emit_status(engine);
}

static void emit_status(phase_noise_engine_t *engine)
{
    phase_noise_status_t status;

    if ((engine == 0) || (engine->status_callback == 0)) {
        return;
    }

    phase_noise_engine_get_status(engine, &status);
    (void)engine->status_callback(&status, engine->status_callback_context);
}

static int emit_data_point(phase_noise_engine_t *engine, uint8_t done)
{
    phase_noise_data_t data;
    const phase_noise_plan_point_t *plan_point;
    float averaged_noise_dbm;
    float enbw_hz;

    if (engine == 0) {
        return -1;
    }

    plan_point = phase_noise_plan_get_point(&engine->plan, engine->current_index);
    if (plan_point == 0) {
        set_error(engine, PN_ERR_INTERNAL);
        return -1;
    }

    averaged_noise_dbm = 10.0f * log10f(engine->average_noise_mw[engine->current_index]);
    enbw_hz = (float)plan_point->rbw_hz;

    memset(&data, 0, sizeof(data));
    data.version = PHASE_NOISE_VERSION;
    data.flags = 0U;
    if (done != 0U) {
        data.flags |= PHASE_NOISE_DATA_FLAG_DONE;
    }
    if (active_warning_code(engine) != PHASE_NOISE_WARN_NONE) {
        data.flags |= PHASE_NOISE_DATA_FLAG_WARNING;
    }

    data.trace_id = engine->trace_id;
    data.total_points = (uint16_t)engine->plan.point_count;
    data.current_index = engine->current_index;
    data.average_index = engine->average_index;
    data.carrier_hz = (engine->carrier_valid != 0U) ?
        (double)engine->measured_carrier_hz : engine->config.nominal_carrier_hz;
    data.carrier_level_dbm = (engine->carrier_valid != 0U) ?
        engine->carrier_level_dbm : 0.0f;
    data.offset_hz = plan_point->offset_hz;
    data.noise_power_dbm = averaged_noise_dbm;
    data.rbw_hz = (uint32_t)(plan_point->rbw_hz + 0.5f);
    data.error_code = (uint8_t)engine->last_error;

    if (engine->carrier_valid != 0U) {
        data.flags |= PHASE_NOISE_DATA_FLAG_CARRIER_VALID;
        data.phase_noise_dbc_hz =
            averaged_noise_dbm - (10.0f * log10f(enbw_hz)) - engine->carrier_level_dbm;
        data.flags |= PHASE_NOISE_DATA_FLAG_PHASE_NOISE_VALID;
    } else {
        data.phase_noise_dbc_hz = 0.0f;
    }

    if (engine->data_callback != 0) {
        sweep_profile_begin(SWEEP_PROFILE_SECTION_EMIT_UART);
        if (engine->data_callback(&data, engine->data_callback_context) != 0) {
            sweep_profile_end(SWEEP_PROFILE_SECTION_EMIT_UART);
            sweep_profile_end(SWEEP_PROFILE_SECTION_POINT_TOTAL);
            set_error(engine, PN_ERR_INTERNAL);
            return -1;
        }
        sweep_profile_end(SWEEP_PROFILE_SECTION_EMIT_UART);
    }

    sweep_profile_note_point();
    sweep_profile_end(SWEEP_PROFILE_SECTION_POINT_TOTAL);
    engine->data_valid = 1U;
    engine->step = PN_STEP_NEXT_POINT;
    return 0;
}

static int prepare_measurement(phase_noise_engine_t *engine)
{
    if (engine == 0) {
        return -1;
    }

    engine->current_index++;
    if (engine->current_index >= (uint16_t)engine->plan.point_count) {
        if ((engine->config.flags & PHASE_NOISE_FLAG_CONTINUOUS) != 0U) {
            engine->current_index = 0U;
            engine->average_index++;
            if (engine->average_index == 0U) {
                engine->average_index = 1U;
            }
        } else if (engine->average_index < engine->config.average_count) {
            engine->current_index = 0U;
            engine->average_index++;
        } else {
            engine->state = PN_STATE_COMPLETE;
            engine->step = PN_STEP_IDLE;
            engine->last_error = PN_ERR_OK;
            emit_status(engine);
            return 0;
        }
    }

    return start_current_point(engine);
}

static int start_current_point(phase_noise_engine_t *engine)
{
    const phase_noise_plan_point_t *point;

    if (engine == 0) {
        return -1;
    }

    if (engine->state == PN_STATE_SEARCHING_CARRIER) {
        rbw_mode_t search_rbw_mode;

        if (engine->carrier_search_count == 0U) {
            set_error(engine, PN_ERR_CARRIER_NOT_FOUND);
            return -1;
        }
        engine->current_rf_hz = carrier_search_target_hz(engine);
        search_rbw_mode = carrier_search_rbw_mode(engine);
        engine->current_rbw_hz = carrier_search_rbw_hz(engine);
        signal_processing_apply_rbw_mode(search_rbw_mode);
        sweep_profile_set_rbw_mode((uint8_t)search_rbw_mode);
    } else {
        point = phase_noise_plan_get_point(&engine->plan, engine->current_index);
        if (point == 0) {
            set_error(engine, PN_ERR_INTERNAL);
            return -1;
        }

        engine->current_offset_hz = point->offset_hz;
        engine->current_rbw_hz = (uint32_t)(point->rbw_hz + 0.5f);
        engine->last_warning = point->warning_code;
        if ((engine->last_warning == PHASE_NOISE_WARN_NONE) &&
            ((engine->config.flags & PHASE_NOISE_FLAG_ALLOW_ESTIMATED_ENBW) != 0U)) {
            engine->last_warning = PHASE_NOISE_WARN_ENBW_ESTIMATED;
        }

        signal_processing_apply_rbw_mode(point->rbw_mode);
        sweep_profile_set_rbw_mode((uint8_t)point->rbw_mode);
        engine->current_rf_hz = current_target_rf_hz(engine);
    }

    if (rf_in_range(engine->current_rf_hz) == 0) {
        if (engine->state == PN_STATE_SEARCHING_CARRIER) {
            if (advance_carrier_search(engine) == 0) {
                engine->step = PN_STEP_SET_LO;
                return 0;
            }
            return -1;
        }
        set_error(engine, PN_ERR_OFFSET_OUT_OF_RANGE);
        return -1;
    }

    signal_processing_reset_accumulation();
    sweep_profile_begin(SWEEP_PROFILE_SECTION_POINT_TOTAL);
    sweep_profile_begin(SWEEP_PROFILE_SECTION_SET_LO1);
    if (lo_control_set_lo1_for_rf_hz(engine->current_rf_hz) != XST_SUCCESS) {
        sweep_profile_end(SWEEP_PROFILE_SECTION_SET_LO1);
        sweep_profile_end(SWEEP_PROFILE_SECTION_POINT_TOTAL);
        set_error(engine, PN_ERR_LO_LOCK_TIMEOUT);
        return -1;
    }
    sweep_profile_end(SWEEP_PROFILE_SECTION_SET_LO1);

    engine->wait_counter = 0U;
    engine->step = PN_STEP_WAIT_LO_LOCK;
    sweep_profile_begin(SWEEP_PROFILE_SECTION_WAIT_LOCK);
    return 0;
}

static int finish_current_measurement(phase_noise_engine_t *engine)
{
    float raw_power_dbm = 0.0f;
    float corrected_power_dbm = 0.0f;
    float correction_db = 0.0f;

    if (engine == 0) {
        return -1;
    }

    sweep_profile_begin(SWEEP_PROFILE_SECTION_MEASURE);
    if (signal_processing_measure_accumulated_power_dbm(&raw_power_dbm) != 0) {
        sweep_profile_end(SWEEP_PROFILE_SECTION_MEASURE);
        sweep_profile_end(SWEEP_PROFILE_SECTION_POINT_TOTAL);
        set_error(engine, PN_ERR_MEASURE_FAILED);
        return -1;
    }

    if (amplitude_correction_apply(engine->current_rf_hz,
                                   raw_power_dbm,
                                   &corrected_power_dbm,
                                   &correction_db) != 0) {
        sweep_profile_end(SWEEP_PROFILE_SECTION_MEASURE);
        sweep_profile_end(SWEEP_PROFILE_SECTION_POINT_TOTAL);
        set_error(engine, PN_ERR_MEASURE_FAILED);
        return -1;
    }
    sweep_profile_end(SWEEP_PROFILE_SECTION_MEASURE);

    engine->current_raw_power_dbm = raw_power_dbm;
    engine->current_power_dbm = corrected_power_dbm;
    engine->current_correction_db = correction_db;

    if (engine->state == PN_STATE_SEARCHING_CARRIER) {
        if ((engine->carrier_search_index == 0U) ||
            (corrected_power_dbm > engine->best_carrier_level_dbm)) {
            engine->best_carrier_level_dbm = corrected_power_dbm;
            engine->measured_carrier_hz = engine->current_rf_hz;
            engine->carrier_level_dbm = corrected_power_dbm;
        }

        sweep_profile_note_point();
        sweep_profile_end(SWEEP_PROFILE_SECTION_POINT_TOTAL);

        if (advance_carrier_search(engine) == 0) {
            return 0;
        }
        return -1;
    }

    {
        float sample_mw = powf(10.0f, corrected_power_dbm / 10.0f);
        uint16_t n = engine->average_index;

        if (n <= 1U) {
            engine->average_noise_mw[engine->current_index] = sample_mw;
        } else {
            float old = engine->average_noise_mw[engine->current_index];
            engine->average_noise_mw[engine->current_index] =
                ((old * (float)(n - 1U)) + sample_mw) / (float)n;
        }
    }

    engine->step = PN_STEP_EMIT_POINT;
    return 0;
}

static uint64_t current_target_rf_hz(const phase_noise_engine_t *engine)
{
    if (engine == 0) {
        return 0ULL;
    }

    return engine->measured_carrier_hz + (uint64_t)engine->current_offset_hz;
}

static uint64_t carrier_search_target_hz(const phase_noise_engine_t *engine)
{
    if (engine == 0) {
        return 0ULL;
    }

    return engine->carrier_search_start_hz +
        ((uint64_t)engine->carrier_search_index * engine->carrier_search_step_hz);
}

static rbw_mode_t carrier_search_rbw_mode(const phase_noise_engine_t *engine)
{
    if ((engine != 0) && (engine->carrier_search_stage == 0U)) {
        return PN_CARRIER_COARSE_RBW_MODE;
    }

    return PN_CARRIER_FINE_RBW_MODE;
}

static uint32_t carrier_search_rbw_hz(const phase_noise_engine_t *engine)
{
    return (uint32_t)(phase_noise_plan_rbw_hz(
        carrier_search_rbw_mode(engine)) + 0.5f);
}

static int rf_in_range(uint64_t rf_hz)
{
    return ((rf_hz >= PN_RF_MIN_HZ) && (rf_hz <= PN_RF_MAX_HZ)) ? 1 : 0;
}

static uint16_t status_flags(const phase_noise_engine_t *engine)
{
    uint16_t flags = 0U;

    if (engine == 0) {
        return 0U;
    }
    if (engine->configured != 0U) {
        flags |= PHASE_NOISE_STATUS_FLAG_CONFIGURED;
    }
    if (phase_noise_engine_is_active(engine) != 0) {
        flags |= PHASE_NOISE_STATUS_FLAG_RUNNING;
    }
    if (engine->carrier_valid != 0U) {
        flags |= PHASE_NOISE_STATUS_FLAG_CARRIER_VALID;
    }
    if (engine->data_valid != 0U) {
        flags |= PHASE_NOISE_STATUS_FLAG_DATA_VALID;
    }
    if (active_warning_code(engine) != PHASE_NOISE_WARN_NONE) {
        flags |= PHASE_NOISE_STATUS_FLAG_WARNING;
    }
    if (engine->stop_requested != 0U) {
        flags |= PHASE_NOISE_STATUS_FLAG_STOP_REQUEST;
    }
    if (engine->state == PN_STATE_COMPLETE) {
        flags |= PHASE_NOISE_STATUS_FLAG_COMPLETE;
    }

    return flags;
}

static uint16_t active_warning_code(const phase_noise_engine_t *engine)
{
    if (engine == 0) {
        return PHASE_NOISE_WARN_NONE;
    }
    if ((engine->last_warning == PHASE_NOISE_WARN_CARRIER_LEVEL_LOW) ||
        (engine->last_warning == PHASE_NOISE_WARN_RF_RANGE_CLIPPED)) {
        return engine->last_warning;
    }
    if (engine->plan_warning != PHASE_NOISE_WARN_NONE) {
        return engine->plan_warning;
    }
    return engine->last_warning;
}

static uint32_t elapsed_ms(const phase_noise_engine_t *engine)
{
    XTime now;
    uint64_t elapsed_ticks;

    if ((engine == 0) || (engine->start_ticks == 0ULL)) {
        return 0U;
    }

    XTime_GetTime(&now);
    elapsed_ticks = (uint64_t)now - engine->start_ticks;
    return (uint32_t)((elapsed_ticks * 1000ULL) / (uint64_t)COUNTS_PER_SECOND);
}
