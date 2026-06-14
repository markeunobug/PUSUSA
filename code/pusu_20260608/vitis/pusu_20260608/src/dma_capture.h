#ifndef DMA_CAPTURE_H
#define DMA_CAPTURE_H

#include "app_config.h"
#include "xstatus.h"
#include "xil_types.h"

typedef struct {
    u32 s2mm_dmacr;
    u32 s2mm_dmasr;
    u32 irq_count;
    u32 last_irq_status;
} dma_capture_diag_t;

enum {
    DMA_CAPTURE_START_OK = 0U,
    DMA_CAPTURE_START_INVALID_ARG = 1U,
    DMA_CAPTURE_START_INVALID_SAMPLES = 2U,
    DMA_CAPTURE_START_PL_ABORT_FAIL = 3U,
    DMA_CAPTURE_START_PL_CLEAR_FAIL = 4U,
    DMA_CAPTURE_START_PL_CONFIG_FAIL = 5U,
    DMA_CAPTURE_START_SUBMIT_SG_FAIL = 6U,
    DMA_CAPTURE_START_SIMPLE_TRANSFER_FAIL = 7U,
    DMA_CAPTURE_START_PL_START_FAIL = 8U
};

typedef struct {
    u32 result_code;
    u32 transfer_bytes;
    u32 capture_samples;
    u32 s2mm_dmacr;
    u32 s2mm_dmasr;
    u32 sg_ring_ready;
    u32 sg_active_bd_count;
    u32 sg_free_bd_count;
} dma_capture_start_diag_t;

#define DMA_CAPTURE_STREAM_SMOKE_RESULT_VERSION 1U

enum {
    DMA_CAPTURE_STREAM_SMOKE_OK = 0U,
    DMA_CAPTURE_STREAM_SMOKE_INVALID_ARG = 1U,
    DMA_CAPTURE_STREAM_SMOKE_PL_UNAVAILABLE = 2U,
    DMA_CAPTURE_STREAM_SMOKE_DMA_RESET_FAIL = 3U,
    DMA_CAPTURE_STREAM_SMOKE_DMA_START_FAIL = 4U,
    DMA_CAPTURE_STREAM_SMOKE_STREAM_START_FAIL = 5U,
    DMA_CAPTURE_STREAM_SMOKE_DMA_TIMEOUT = 6U,
    DMA_CAPTURE_STREAM_SMOKE_DMA_ERROR = 7U,
    DMA_CAPTURE_STREAM_SMOKE_PL_STATUS_ERROR = 8U,
    DMA_CAPTURE_STREAM_SMOKE_COUNTER_MISMATCH = 9U,
    DMA_CAPTURE_STREAM_SMOKE_BACKPRESSURE = 10U,
    DMA_CAPTURE_STREAM_SMOKE_OVERFLOW = 11U,
    DMA_CAPTURE_STREAM_SMOKE_BUSY = 12U
};

typedef struct {
    u32 version;
    u32 result_code;
    u32 requested_samples;
    u32 transfer_bytes;
    u32 dma_completed;
    u32 dma_error;
    u32 timed_out;
    u32 wait_loops;
    u32 raw_status;
    u32 status_error_code;
    u32 total_sample_count_lo;
    u32 total_sample_count_hi;
    u32 packet_count;
    u32 overflow_count;
    u32 backpressure_count;
    u32 s2mm_dmacr;
    u32 s2mm_dmasr;
    u32 irq_count;
    u32 last_irq_status;
} dma_capture_stream_smoke_result_t;

#define DMA_CAPTURE_SG_SMOKE_RESULT_VERSION 1U

enum {
    DMA_CAPTURE_SG_SMOKE_OK = 0U,
    DMA_CAPTURE_SG_SMOKE_INVALID_ARG = 1U,
    DMA_CAPTURE_SG_SMOKE_UNSUPPORTED = 2U,
    DMA_CAPTURE_SG_SMOKE_PL_UNAVAILABLE = 3U,
    DMA_CAPTURE_SG_SMOKE_DMA_RESET_FAIL = 4U,
    DMA_CAPTURE_SG_SMOKE_RING_SETUP_FAIL = 5U,
    DMA_CAPTURE_SG_SMOKE_BD_ALLOC_FAIL = 6U,
    DMA_CAPTURE_SG_SMOKE_BD_SETUP_FAIL = 7U,
    DMA_CAPTURE_SG_SMOKE_DMA_START_FAIL = 8U,
    DMA_CAPTURE_SG_SMOKE_STREAM_START_FAIL = 9U,
    DMA_CAPTURE_SG_SMOKE_TIMEOUT = 10U,
    DMA_CAPTURE_SG_SMOKE_DMA_ERROR = 11U,
    DMA_CAPTURE_SG_SMOKE_PL_STATUS_ERROR = 12U,
    DMA_CAPTURE_SG_SMOKE_COUNTER_MISMATCH = 13U,
    DMA_CAPTURE_SG_SMOKE_BACKPRESSURE = 14U,
    DMA_CAPTURE_SG_SMOKE_OVERFLOW = 15U,
    DMA_CAPTURE_SG_SMOKE_BUSY = 16U
};

typedef struct {
    u32 version;
    u32 result_code;
    u32 samples_per_bd;
    u32 bd_count;
    u32 requested_samples;
    u32 requested_bytes;
    u32 completed_bd_count;
    u32 completed_bytes;
    u32 dma_completed;
    u32 dma_error;
    u32 timed_out;
    u32 wait_loops;
    u32 first_bd_status;
    u32 last_bd_status;
    u32 raw_status;
    u32 status_error_code;
    u32 total_sample_count_lo;
    u32 total_sample_count_hi;
    u32 packet_count;
    u32 overflow_count;
    u32 backpressure_count;
    u32 s2mm_dmacr;
    u32 s2mm_dmasr;
    u32 irq_count;
    u32 last_irq_status;
    u32 debug_config_has_sg;
    u32 debug_instance_has_sg;
    u32 debug_ring_ready;
    u32 debug_dma_device_id;
    u32 debug_dma_baseaddr;
} dma_capture_sg_smoke_result_t;

typedef struct {
    u32 completed_bd_count;
    u32 completed_bytes;
    u32 first_bd_status;
    u32 last_bd_status;
    u32 raw_status;
    u32 status_error_code;
    u32 total_sample_count_lo;
    u32 total_sample_count_hi;
    u32 packet_count;
    u32 overflow_count;
    u32 backpressure_count;
} dma_capture_sg_batch_diag_t;

#if DMA_CAPTURE_BURST_DIAG_ENABLE
#define DMA_CAPTURE_BURST_DIAG_VERSION 1U

typedef struct {
    u32 version;
    u32 valid;
    u32 sequence;
    u32 samples_per_bd;
    u32 bd_count;
    u32 requested_samples;
    u32 requested_bytes;
    u32 completed_bd_count;
    u32 completed_bytes;
    u32 wait_loops;
    u32 result_code;
    u32 reset_us;
    u32 cache_flush_us;
    u32 bd_submit_us;
    u32 pl_start_us;
    u32 wait_reclaim_us;
    u32 stop_us;
    u32 cache_invalidate_us;
    u32 status_us;
    u32 final_reset_us;
    u32 total_us;
    u32 packet_count;
    u32 burst_packet_count;
    u32 burst_remaining;
    u32 overflow_count;
    u32 backpressure_count;
    u32 raw_status;
    u32 s2mm_dmasr;
    u32 irq_count;
    u32 last_irq_status;
} dma_capture_burst_diag_t;
#endif

int dma_capture_init(void);
int dma_capture_reset(void);
int dma_capture_start(u32 transfer_bytes);
int dma_capture_frame_ready(void);
int dma_capture_take_error(void);
volatile u16 *dma_capture_get_rx_buffer(void);
void dma_capture_get_diag(dma_capture_diag_t *diag);
void dma_capture_get_start_diag(dma_capture_start_diag_t *diag);
#if DMA_CAPTURE_BURST_DIAG_ENABLE
void dma_capture_get_burst_diag(dma_capture_burst_diag_t *diag);
void dma_capture_reset_burst_diag(void);
#endif
int dma_capture_continuous_smoke_test(u32 sample_count,
                                      dma_capture_stream_smoke_result_t *result);
int dma_capture_main_path_smoke_test(u32 sample_count,
                                     dma_capture_stream_smoke_result_t *result);
int dma_capture_sg_is_supported(void);
int dma_capture_sg_smoke_test(u32 samples_per_bd,
                              u32 bd_count,
                              dma_capture_sg_smoke_result_t *result);
void dma_capture_set_sg_smoke_burst_mode(int enable);
int dma_capture_sg_burst_smoke_test(u32 samples_per_bd,
                                    u32 bd_count,
                                    dma_capture_sg_smoke_result_t *result);
int dma_capture_sg_batch_capture(u32 samples_per_bd,
                                 u32 bd_count,
                                 u32 *out_total_samples,
                                 dma_capture_sg_batch_diag_t *diag);
int dma_capture_sg_burst_capture(u32 samples_per_bd,
                                 u32 bd_count,
                                 u32 *out_total_samples,
                                 dma_capture_sg_batch_diag_t *diag);
int dma_capture_sg_ring_smoke_test(u32 samples_per_bd,
                                   u32 bd_count,
                                   u32 target_bd_count,
                                   dma_capture_sg_smoke_result_t *result);
void dma_capture_shutdown(void);

#endif
