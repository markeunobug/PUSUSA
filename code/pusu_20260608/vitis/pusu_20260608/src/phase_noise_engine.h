#ifndef PHASE_NOISE_ENGINE_H
#define PHASE_NOISE_ENGINE_H

#include <stdint.h>

#include "phase_noise_plan.h"

#define PHASE_NOISE_VERSION      1U
#define PHASE_NOISE_DATA_VERSION 2U

#define PHASE_NOISE_FLAG_CONTINUOUS                 0x01U
#define PHASE_NOISE_FLAG_ALLOW_ESTIMATED_ENBW       0x02U
#define PHASE_NOISE_FLAG_EMIT_INTERMEDIATE_AVERAGES 0x04U

#define PHASE_NOISE_DATA_FLAG_DONE              0x01U
#define PHASE_NOISE_DATA_FLAG_CARRIER_VALID     0x02U
#define PHASE_NOISE_DATA_FLAG_WARNING           0x04U
#define PHASE_NOISE_DATA_FLAG_LOWER_SIDEBAND    0x08U
#define PHASE_NOISE_DATA_FLAG_DUAL_AVERAGE      0x10U
#define PHASE_NOISE_DATA_FLAG_PHASE_NOISE_VALID 0x20U

#define PHASE_NOISE_STATUS_FLAG_CONFIGURED    0x01U
#define PHASE_NOISE_STATUS_FLAG_RUNNING       0x02U
#define PHASE_NOISE_STATUS_FLAG_CARRIER_VALID 0x04U
#define PHASE_NOISE_STATUS_FLAG_DATA_VALID    0x08U
#define PHASE_NOISE_STATUS_FLAG_WARNING       0x10U
#define PHASE_NOISE_STATUS_FLAG_STOP_REQUEST  0x20U
#define PHASE_NOISE_STATUS_FLAG_COMPLETE      0x40U

#define PHASE_NOISE_CARRIER_MANUAL 0U
#define PHASE_NOISE_CARRIER_AUTO   1U

#define PHASE_NOISE_SIDEBAND_UPPER 0U
#define PHASE_NOISE_SIDEBAND_LOWER 1U
#define PHASE_NOISE_SIDEBAND_DUAL  2U

#define PHASE_NOISE_WARN_NONE                  0U
#define PHASE_NOISE_WARN_OFFSET_BELOW_RBW      1U
#define PHASE_NOISE_WARN_ENBW_ESTIMATED        2U
#define PHASE_NOISE_WARN_CARRIER_LEVEL_LOW     3U
#define PHASE_NOISE_WARN_RF_RANGE_CLIPPED      4U
#define PHASE_NOISE_WARN_PARTIAL_DUAL_SIDEBAND 5U
#define PHASE_NOISE_WARN_PLAN_TRUNCATED        6U

typedef enum {
    PN_STATE_IDLE = 0,
    PN_STATE_CONFIGURED = 1,
    PN_STATE_SEARCHING_CARRIER = 2,
    PN_STATE_MEASURING = 3,
    PN_STATE_STOPPING = 4,
    PN_STATE_COMPLETE = 5,
    PN_STATE_ERROR = 6
} phase_noise_state_t;

typedef enum {
    PN_ERR_OK = 0,
    PN_ERR_BAD_CONFIG = 1,
    PN_ERR_CARRIER_NOT_FOUND = 2,
    PN_ERR_OFFSET_OUT_OF_RANGE = 3,
    PN_ERR_RBW_UNSUPPORTED = 4,
    PN_ERR_LO_LOCK_TIMEOUT = 5,
    PN_ERR_DMA_TIMEOUT = 6,
    PN_ERR_MEASURE_FAILED = 7,
    PN_ERR_BUSY = 8,
    PN_ERR_NOT_CONFIGURED = 9,
    PN_ERR_STOPPED_BY_HOST = 10,
    PN_ERR_UNSUPPORTED_VERSION = 11,
    PN_ERR_INTERNAL = 12
} phase_noise_error_t;

typedef enum {
    PHASE_NOISE_ENGINE_ACTION_CONFIGURE = 1,
    PHASE_NOISE_ENGINE_ACTION_START,
    PHASE_NOISE_ENGINE_ACTION_STOP,
    PHASE_NOISE_ENGINE_ACTION_GET_STATUS
} phase_noise_engine_action_t;

typedef enum {
    PN_STEP_IDLE = 0,
    PN_STEP_PREPARE_CARRIER,
    PN_STEP_SET_LO,
    PN_STEP_WAIT_LO_LOCK,
    PN_STEP_ARM_DMA,
    PN_STEP_REARM_DMA,
    PN_STEP_WAIT_FRAME,
    PN_STEP_MEASURE,
    PN_STEP_EMIT_POINT,
    PN_STEP_NEXT_POINT,
    PN_STEP_STOPPING
} phase_noise_step_t;

typedef struct {
    uint8_t version;
    uint8_t flags;
    uint8_t carrier_mode;
    uint8_t sideband_mode;
    double nominal_carrier_hz;
    double start_offset_hz;
    double stop_offset_hz;
    uint16_t points_per_decade;
    uint16_t average_count;
    uint32_t carrier_search_span_hz;
    int8_t minimum_carrier_level_dbm;
} phase_noise_config_t;

typedef struct {
    uint8_t version;
    uint8_t flags;
    uint16_t trace_id;
    uint16_t total_points;
    uint16_t current_index;
    uint16_t average_index;
    double carrier_hz;
    float carrier_level_dbm;
    uint32_t offset_hz;
    float noise_power_dbm;
    float phase_noise_dbc_hz;
    uint32_t rbw_hz;
    uint8_t error_code;
} phase_noise_data_t;

typedef struct {
    uint8_t version;
    uint8_t state;
    uint8_t flags;
    uint8_t error_code;
    uint16_t trace_id;
    uint16_t total_points;
    uint16_t current_index;
    uint16_t average_index;
    double nominal_carrier_hz;
    double measured_carrier_hz;
    float carrier_level_dbm;
    double start_offset_hz;
    double stop_offset_hz;
    uint32_t current_offset_hz;
    uint32_t current_rbw_hz;
    uint32_t elapsed_ms;
    uint16_t warning_code;
} phase_noise_status_t;

typedef int (*phase_noise_data_callback_t)(const phase_noise_data_t *point,
                                           void *context);
typedef int (*phase_noise_status_callback_t)(const phase_noise_status_t *status,
                                             void *context);

typedef struct {
    phase_noise_config_t config;
    phase_noise_plan_t plan;
    phase_noise_state_t state;
    phase_noise_step_t step;
    uint8_t configured;
    uint8_t carrier_valid;
    uint8_t data_valid;
    uint8_t stop_requested;
    uint16_t trace_id;
    uint16_t current_index;
    uint16_t average_index;
    uint16_t plan_warning;
    uint16_t last_warning;
    phase_noise_error_t last_error;
    uint32_t wait_counter;
    uint32_t current_offset_hz;
    uint32_t current_rbw_hz;
    uint64_t current_rf_hz;
    uint64_t measured_carrier_hz;
    uint64_t carrier_candidate_hz;
    uint64_t carrier_search_center_hz;
    uint64_t carrier_search_start_hz;
    uint64_t carrier_search_step_hz;
    uint64_t carrier_coarse_best_hz;
    float carrier_level_dbm;
    float best_carrier_level_dbm;
    uint16_t carrier_search_index;
    uint16_t carrier_search_count;
    uint8_t carrier_search_stage;
    float current_raw_power_dbm;
    float current_power_dbm;
    float current_correction_db;
    uint64_t start_ticks;
    phase_noise_data_callback_t data_callback;
    void *data_callback_context;
    phase_noise_status_callback_t status_callback;
    void *status_callback_context;
} phase_noise_engine_t;

int phase_noise_engine_init(phase_noise_engine_t *engine);
int phase_noise_engine_configure(phase_noise_engine_t *engine,
                                 const phase_noise_config_t *config);
int phase_noise_engine_start(phase_noise_engine_t *engine);
void phase_noise_engine_stop(phase_noise_engine_t *engine);
int phase_noise_engine_poll(phase_noise_engine_t *engine);
int phase_noise_engine_is_active(const phase_noise_engine_t *engine);
void phase_noise_engine_get_status(const phase_noise_engine_t *engine,
                                   phase_noise_status_t *status);
void phase_noise_engine_set_callbacks(phase_noise_engine_t *engine,
                                      phase_noise_data_callback_t data_callback,
                                      void *data_context,
                                      phase_noise_status_callback_t status_callback,
                                      void *status_context);

#endif
