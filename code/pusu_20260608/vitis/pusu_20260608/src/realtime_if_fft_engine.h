#ifndef REALTIME_IF_FFT_ENGINE_H
#define REALTIME_IF_FFT_ENGINE_H

#include <stdint.h>
#include "realtime_if_fft.h"

#define REALTIME_IF_FFT_ENGINE_VERSION 1U

typedef enum { RTFFT_STATE_IDLE=0, RTFFT_STATE_CONFIGURED, RTFFT_STATE_SET_LO, RTFFT_STATE_WAIT_LOCK, RTFFT_STATE_ARM_DMA, RTFFT_STATE_WAIT_FRAME, RTFFT_STATE_ERROR } realtime_if_fft_engine_state_t;
typedef enum { RTFFT_ERR_NONE=0, RTFFT_ERR_BAD_CONFIG=1, RTFFT_ERR_NOT_CONFIGURED=2, RTFFT_ERR_BUSY=3, RTFFT_ERR_LO_SET=4, RTFFT_ERR_LO_LOCK=5, RTFFT_ERR_DMA=6, RTFFT_ERR_FRAME_TIMEOUT=7, RTFFT_ERR_PROCESS=8, RTFFT_ERR_STREAM=9, RTFFT_ERR_STOPPED=10, RTFFT_ERR_DMA_RESET=11 } realtime_if_fft_engine_error_t;
typedef enum { REALTIME_IF_FFT_ENGINE_ACTION_CONFIGURE=1, REALTIME_IF_FFT_ENGINE_ACTION_START, REALTIME_IF_FFT_ENGINE_ACTION_STOP, REALTIME_IF_FFT_ENGINE_ACTION_GET_STATUS } realtime_if_fft_engine_action_t;

typedef struct { uint8_t version; uint8_t flags; uint16_t reserved; uint64_t center_frequency_hz; } realtime_if_fft_engine_config_t;
typedef struct { uint8_t version, state, flags, error_code; /* V1 frame-by-frame DMA never discards a completed frame; this remains zero
 * until a deliberate latest-frame/drop policy has a reliable source counter. */
    uint32_t next_trace_id, frames_sent, dropped_frames, dma_error_count; uint64_t center_frequency_hz; } realtime_if_fft_engine_status_t;
typedef int (*realtime_if_fft_engine_trace_callback_t)(const realtime_if_fft_trace_t *, const realtime_if_fft_engine_status_t *, void *);
typedef int (*realtime_if_fft_engine_status_callback_t)(const realtime_if_fft_engine_status_t *, void *);
typedef struct { realtime_if_fft_engine_config_t config; realtime_if_fft_engine_state_t state; realtime_if_fft_engine_error_t last_error; uint8_t configured, stop_requested; uint32_t next_trace_id, wait_counter, frames_sent, dropped_frames, dma_error_count; realtime_if_fft_engine_trace_callback_t trace_callback; void *trace_context; realtime_if_fft_engine_status_callback_t status_callback; void *status_context; } realtime_if_fft_engine_t;

int realtime_if_fft_engine_init(realtime_if_fft_engine_t *engine);
int realtime_if_fft_engine_configure(realtime_if_fft_engine_t *engine, const realtime_if_fft_engine_config_t *config);
int realtime_if_fft_engine_start(realtime_if_fft_engine_t *engine);
void realtime_if_fft_engine_stop(realtime_if_fft_engine_t *engine);
int realtime_if_fft_engine_poll(realtime_if_fft_engine_t *engine);
int realtime_if_fft_engine_is_active(const realtime_if_fft_engine_t *engine);
void realtime_if_fft_engine_get_status(const realtime_if_fft_engine_t *engine, realtime_if_fft_engine_status_t *status);
void realtime_if_fft_engine_set_callbacks(realtime_if_fft_engine_t *engine, realtime_if_fft_engine_trace_callback_t trace_callback, void *trace_context, realtime_if_fft_engine_status_callback_t status_callback, void *status_context);
#endif
