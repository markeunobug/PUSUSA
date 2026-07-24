#ifndef DMA_CAPTURE_H
#define DMA_CAPTURE_H

#include "xstatus.h"
#include "xil_types.h"

typedef struct {
    u32 s2mm_dmacr;
    u32 s2mm_dmasr;
    u32 irq_count;
    u32 last_irq_status;
} dma_capture_diag_t;

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
} dma_capture_sg_smoke_result_t;

int dma_capture_init(void);
int dma_capture_reset(void);
int dma_capture_start(u32 transfer_bytes);
int dma_capture_frame_ready(void);
int dma_capture_take_error(void);
volatile u16 *dma_capture_get_rx_buffer(void);
void dma_capture_get_diag(dma_capture_diag_t *diag);
int dma_capture_continuous_smoke_test(u32 sample_count,
                                      dma_capture_stream_smoke_result_t *result);
int dma_capture_sg_is_supported(void);
int dma_capture_sg_smoke_test(u32 samples_per_bd,
                              u32 bd_count,
                              dma_capture_sg_smoke_result_t *result);
void dma_capture_shutdown(void);

#endif
