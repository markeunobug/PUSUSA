#ifndef SWEEP_ENGINE_H
#define SWEEP_ENGINE_H

#include <stdint.h>

#include "../code/sweep_plan.h"

#define SWEEP_ENGINE_MAX_POINTS SWEEP_PLAN_MAX_POINTS

#define SWEEP_ENGINE_OK                     (0)
#define SWEEP_ENGINE_ERR_BAD_ARG           (-1)
#define SWEEP_ENGINE_ERR_PLAN              (-10)
#define SWEEP_ENGINE_ERR_LO1_SET           (-11)
#define SWEEP_ENGINE_ERR_LO1_LOCK_TIMEOUT  (-12)
#define SWEEP_ENGINE_ERR_FRAME_TIMEOUT     (-13)
#define SWEEP_ENGINE_ERR_POWER_MEASURE     (-14)
#define SWEEP_ENGINE_ERR_STREAM_CALLBACK   (-15)

typedef int (*sweep_engine_point_callback_t)(uint32_t freq_hz, float power_dbm, void *context);

typedef struct {
    double freq_hz;
    float power_dbm;
} sweep_trace_point_t;

typedef struct {
    sweep_plan_t plan;
    sweep_trace_point_t points[SWEEP_ENGINE_MAX_POINTS];
    uint32_t point_count;
    sweep_engine_point_callback_t point_callback;
    void *point_callback_context;
} sweep_engine_t;

int sweep_engine_init(sweep_engine_t *engine);
int sweep_engine_prepare(sweep_engine_t *engine, const device_control_config_t *config);
int sweep_engine_run_blocking(sweep_engine_t *engine);
int sweep_engine_get_last_error(void);
void sweep_engine_set_point_callback(sweep_engine_t *engine,
                                     sweep_engine_point_callback_t callback,
                                     void *context);

#endif
