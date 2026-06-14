#include "dma_capture.h"

#include "app_config.h"
#include "pl_capture_control.h"
#include "xaxidma.h"
#include "xaxidma_bd.h"
#include "xaxidma_hw.h"
#include "xil_cache.h"
#include "xil_exception.h"
#include "xscugic.h"
#include "xtime_l.h"

static XAxiDma axidma;
static XScuGic intc;

static volatile u16 rx_buffer[DMA_MAX_SAMPLES] __attribute__((aligned(32)));
static volatile int rx_done = 0;
static volatile int error = 0;
static volatile u32 irq_count = 0U;
static volatile u32 last_irq_status = 0U;
static u32 current_transfer_bytes = TRANSFER_LENGTH;
static int pl_capture_enabled = 0;
static u32 next_capture_frame_id = 1U;
static u32 active_capture_frame_id = 0U;
static u32 active_capture_samples = 0U;
static int active_capture_stream_mode = 0;
static dma_capture_start_diag_t last_start_diag;

#define DMA_STREAM_SMOKE_WAIT_LIMIT 1000000U
#define DMA_SG_SMOKE_WAIT_LIMIT 1000000U
#define DMA_SG_RX_BD_COUNT 1024U
#define DMA_SG_RX_BD_SPACE_BYTES (DMA_SG_RX_BD_COUNT * 256U)
#define DMA_SG_SAMPLES_PER_BD FFT_SIZE

static u8 rx_bd_space[DMA_SG_RX_BD_SPACE_BYTES]
    __attribute__((aligned(XAXIDMA_BD_MINIMUM_ALIGNMENT)));
static int sg_rx_ring_ready = 0;
static u32 sg_rx_active_bd_count = 0U;
static u32 sg_rx_active_bytes_per_bd = 0U;
static int sg_smoke_burst_mode = 0;
#if DMA_CAPTURE_BURST_DIAG_ENABLE
static dma_capture_burst_diag_t last_burst_diag;
static dma_capture_burst_diag_t slowest_burst_diag;
static u32 burst_diag_sequence = 0U;
#endif

static void rx_intr_handler(void *callback);
static int setup_intr_system(XScuGic *int_ins_ptr, XAxiDma *axidma_ptr, u16 rx_intr_id);
static int dma_has_sg(void);
static void stop_active_capture_stream(void);
static void capture_start_diag_record(u32 result_code,
                                      u32 transfer_bytes,
                                      u32 capture_samples);
static void choose_sg_frame_layout(u32 transfer_bytes,
                                   u32 *bytes_per_bd,
                                   u32 *bd_count);
#if DMA_CAPTURE_BURST_DIAG_ENABLE
static u64 burst_diag_now_ticks(void);
static u32 burst_diag_elapsed_us(u64 start_ticks, u64 end_ticks);
static void burst_diag_commit(dma_capture_burst_diag_t *diag,
                              u32 result_code,
                              u64 total_start_ticks);
#endif
static int reset_dma_core(void);
static int setup_sg_rx_ring(void);
static int submit_sg_rx_bds(UINTPTR buffer_addr, u32 bytes_per_bd, u32 bd_count);
static int submit_sg_rx_bds_start(UINTPTR buffer_addr,
                                  u32 bytes_per_bd,
                                  u32 bd_count,
                                  int start_ring);
static int reclaim_sg_rx_bds(u32 expected_bd_count,
                             u32 expected_bytes_per_bd,
                             u32 *completed_bd_count,
                             u32 *completed_bytes,
                             u32 *first_bd_status,
                             u32 *last_bd_status);
static int reclaim_sg_rx_bds_any(u32 expected_bytes_per_bd,
                                 u32 *completed_bd_count,
                                 u32 *completed_bytes,
                                 u32 *first_bd_status,
                                 u32 *last_bd_status,
                                 UINTPTR *buffer_addrs,
                                 u32 max_buffer_addrs);
static u32 allocate_capture_frame_id(void);
static int wait_for_pl_capture_done(u32 expected_samples, u32 expected_frame_id);
static void init_stream_smoke_result(u32 sample_count,
                                     dma_capture_stream_smoke_result_t *result);
static void finalize_stream_smoke_result(dma_capture_stream_smoke_result_t *result);
static void init_sg_smoke_result(u32 samples_per_bd,
                                 u32 bd_count,
                                 dma_capture_sg_smoke_result_t *result);
static void finalize_sg_smoke_result(dma_capture_sg_smoke_result_t *result);

int dma_capture_init(void)
{
    int status;
    XAxiDma_Config *config;

    config = XAxiDma_LookupConfig(DMA_DEV_ID);
    if (config == NULL) {
        return XST_FAILURE;
    }

    status = XAxiDma_CfgInitialize(&axidma, config);
    if (status != XST_SUCCESS) {
        return status;
    }

    if (dma_has_sg() != 0) {
        status = setup_sg_rx_ring();
        if (status != XST_SUCCESS) {
            return status;
        }
    }

    status = setup_intr_system(&intc, &axidma, RX_INTR_ID);
    if (status != XST_SUCCESS) {
        return status;
    }

    if (pl_capture_is_available() != 0) {
        status = pl_capture_init();
        if (status != XST_SUCCESS) {
            return status;
        }
        pl_capture_enabled = 1;
    }

    return XST_SUCCESS;
}

#define DMA_RESET_TIMEOUT 10000U

int dma_capture_reset(void)
{
    rx_done = 0;
    error = 0;
    active_capture_frame_id = 0U;
    active_capture_samples = 0U;
    active_capture_stream_mode = 0;

    if (pl_capture_enabled != 0) {
        if (pl_capture_abort() != XST_SUCCESS) {
            return XST_FAILURE;
        }
        if (pl_capture_clear_status() != XST_SUCCESS) {
            return XST_FAILURE;
        }
    }

    if (reset_dma_core() != XST_SUCCESS) {
        return XST_FAILURE;
    }

    rx_done = 0;
    error = 0;

    if (pl_capture_enabled != 0) {
        if (pl_capture_reset_fifo() != XST_SUCCESS) {
            return XST_FAILURE;
        }
        if (pl_capture_clear_status() != XST_SUCCESS) {
            return XST_FAILURE;
        }
    }

    return XST_SUCCESS;
}

int dma_capture_start(u32 transfer_bytes)
{
    int status;
    u32 capture_samples;
    u32 capture_frame_id = 0U;

    if (transfer_bytes > DMA_MAX_BYTES ||
        transfer_bytes > DMA_SIMPLE_MAX_BYTES ||
        (transfer_bytes & 0x3U) != 0U) {
        capture_start_diag_record(DMA_CAPTURE_START_INVALID_ARG,
                                  transfer_bytes,
                                  0U);
        return XST_FAILURE;
    }

    capture_samples = transfer_bytes / (u32)sizeof(u16);
    if ((capture_samples == 0U) ||
        ((pl_capture_enabled != 0) &&
         (capture_samples > PL_CAPTURE_MAX_FRAME_LEN))) {
        capture_start_diag_record(DMA_CAPTURE_START_INVALID_SAMPLES,
                                  transfer_bytes,
                                  capture_samples);
        return XST_FAILURE;
    }

    if (pl_capture_enabled != 0) {
        if (pl_capture_abort() != XST_SUCCESS) {
            capture_start_diag_record(DMA_CAPTURE_START_PL_ABORT_FAIL,
                                      transfer_bytes,
                                      capture_samples);
            return XST_FAILURE;
        }
        if (pl_capture_clear_status() != XST_SUCCESS) {
            capture_start_diag_record(DMA_CAPTURE_START_PL_CLEAR_FAIL,
                                      transfer_bytes,
                                      capture_samples);
            return XST_FAILURE;
        }

        capture_frame_id = allocate_capture_frame_id();
        status = pl_capture_configure(capture_samples, capture_frame_id);
        if (status != XST_SUCCESS) {
            capture_start_diag_record(DMA_CAPTURE_START_PL_CONFIG_FAIL,
                                      transfer_bytes,
                                      capture_samples);
            return status;
        }
    }

    rx_done = 0;
    error = 0;
    current_transfer_bytes = transfer_bytes;
    active_capture_samples = capture_samples;
    active_capture_frame_id = capture_frame_id;
    active_capture_stream_mode = 0;

    Xil_DCacheFlushRange((UINTPTR)rx_buffer, (u32)transfer_bytes);

    if (dma_has_sg() != 0) {
        status = submit_sg_rx_bds((UINTPTR)rx_buffer, transfer_bytes, 1U);
    } else {
        sg_rx_active_bd_count = 0U;
        sg_rx_active_bytes_per_bd = 0U;
        status = XAxiDma_SimpleTransfer(&axidma,
                                        (UINTPTR)rx_buffer,
                                        (int)transfer_bytes,
                                        XAXIDMA_DEVICE_TO_DMA);
    }
    if (status != XST_SUCCESS) {
        capture_start_diag_record((dma_has_sg() != 0)
                                      ? DMA_CAPTURE_START_SUBMIT_SG_FAIL
                                      : DMA_CAPTURE_START_SIMPLE_TRANSFER_FAIL,
                                  transfer_bytes,
                                  capture_samples);
        active_capture_samples = 0U;
        active_capture_frame_id = 0U;
        active_capture_stream_mode = 0;
        return status;
    }

    if (pl_capture_enabled != 0) {
        status = pl_capture_start();
        if (status != XST_SUCCESS) {
            capture_start_diag_record(DMA_CAPTURE_START_PL_START_FAIL,
                                      transfer_bytes,
                                      capture_samples);
            active_capture_samples = 0U;
            active_capture_frame_id = 0U;
            active_capture_stream_mode = 0;
            XAxiDma_Reset(&axidma);
            return status;
        }
    }

    capture_start_diag_record(DMA_CAPTURE_START_OK,
                              transfer_bytes,
                              capture_samples);
    return XST_SUCCESS;
}

int dma_capture_frame_ready(void)
{
    u32 completed_bd_count = 0U;
    u32 completed_bytes = 0U;
    u32 first_bd_status = 0U;
    u32 last_bd_status = 0U;

    if (rx_done == 0) {
        return 0;
    }

    rx_done = 0;

    if ((dma_has_sg() != 0) && (sg_rx_active_bd_count != 0U)) {
        if (reclaim_sg_rx_bds(sg_rx_active_bd_count,
                              sg_rx_active_bytes_per_bd,
                              &completed_bd_count,
                              &completed_bytes,
                              &first_bd_status,
                              &last_bd_status) != XST_SUCCESS) {
            error = 1;
            stop_active_capture_stream();
            return 0;
        }

        if (completed_bytes < current_transfer_bytes) {
            error = 1;
            stop_active_capture_stream();
            return 0;
        }
    }

    Xil_DCacheInvalidateRange((UINTPTR)rx_buffer, current_transfer_bytes);

    if (pl_capture_enabled != 0) {
        stop_active_capture_stream();
        if (wait_for_pl_capture_done(active_capture_samples,
                                     active_capture_frame_id) != XST_SUCCESS) {
            error = 1;
            return 0;
        }

        (void)pl_capture_clear_status();
    }

    active_capture_stream_mode = 0;
    return 1;
}

int dma_capture_take_error(void)
{
    int had_error = error;
    error = 0;
    return had_error;
}

volatile u16 *dma_capture_get_rx_buffer(void)
{
    return rx_buffer;
}

void dma_capture_get_diag(dma_capture_diag_t *diag)
{
    if (diag == 0) {
        return;
    }

    diag->s2mm_dmacr =
        XAxiDma_ReadReg(axidma.RegBase, XAXIDMA_RX_OFFSET + XAXIDMA_CR_OFFSET);
    diag->s2mm_dmasr =
        XAxiDma_ReadReg(axidma.RegBase, XAXIDMA_RX_OFFSET + XAXIDMA_SR_OFFSET);
    diag->irq_count = irq_count;
    diag->last_irq_status = last_irq_status;
}

void dma_capture_get_start_diag(dma_capture_start_diag_t *diag)
{
    if (diag == 0) {
        return;
    }

    *diag = last_start_diag;
}

#if DMA_CAPTURE_BURST_DIAG_ENABLE
void dma_capture_get_burst_diag(dma_capture_burst_diag_t *diag)
{
    if (diag == 0) {
        return;
    }

    *diag = (slowest_burst_diag.valid != 0U)
        ? slowest_burst_diag
        : last_burst_diag;
}

void dma_capture_reset_burst_diag(void)
{
    memset(&last_burst_diag, 0, sizeof(last_burst_diag));
    memset(&slowest_burst_diag, 0, sizeof(slowest_burst_diag));
}
#endif

int dma_capture_continuous_smoke_test(u32 sample_count,
                                      dma_capture_stream_smoke_result_t *result)
{
    int status;
    u32 transfer_bytes;
    u32 wait_loops = 0U;
    u32 completed_bd_count = 0U;
    u32 completed_bytes = 0U;
    u32 first_bd_status = 0U;
    u32 last_bd_status = 0U;
    pl_capture_status_t capture_status;
    pl_capture_counters_t counters;

    if ((result == 0) || (sample_count == 0U) ||
        (sample_count > PL_CAPTURE_MAX_FRAME_LEN)) {
        if (result != 0) {
            init_stream_smoke_result(sample_count, result);
            result->result_code = DMA_CAPTURE_STREAM_SMOKE_INVALID_ARG;
        }
        return XST_FAILURE;
    }

    init_stream_smoke_result(sample_count, result);
    transfer_bytes = sample_count * (u32)sizeof(u16);
    result->transfer_bytes = transfer_bytes;

    if (pl_capture_enabled == 0) {
        result->result_code = DMA_CAPTURE_STREAM_SMOKE_PL_UNAVAILABLE;
        finalize_stream_smoke_result(result);
        return XST_FAILURE;
    }

    status = dma_capture_reset();
    if (status != XST_SUCCESS) {
        result->result_code = DMA_CAPTURE_STREAM_SMOKE_DMA_RESET_FAIL;
        finalize_stream_smoke_result(result);
        return XST_FAILURE;
    }

    rx_done = 0;
    error = 0;
    current_transfer_bytes = transfer_bytes;
    active_capture_samples = 0U;
    active_capture_frame_id = 0U;
    Xil_DCacheFlushRange((UINTPTR)rx_buffer, transfer_bytes);

    if (dma_has_sg() != 0) {
        status = submit_sg_rx_bds((UINTPTR)rx_buffer, transfer_bytes, 1U);
    } else {
        status = XAxiDma_SimpleTransfer(&axidma,
                                        (UINTPTR)rx_buffer,
                                        (int)transfer_bytes,
                                        XAXIDMA_DEVICE_TO_DMA);
    }
    if (status != XST_SUCCESS) {
        result->result_code = DMA_CAPTURE_STREAM_SMOKE_DMA_START_FAIL;
        finalize_stream_smoke_result(result);
        return XST_FAILURE;
    }

    status = pl_capture_start_stream(sample_count, allocate_capture_frame_id());
    if (status != XST_SUCCESS) {
        (void)pl_capture_stop_stream();
        XAxiDma_Reset(&axidma);
        result->result_code = DMA_CAPTURE_STREAM_SMOKE_STREAM_START_FAIL;
        finalize_stream_smoke_result(result);
        return XST_FAILURE;
    }

    while ((rx_done == 0) && (error == 0) &&
           (wait_loops < DMA_STREAM_SMOKE_WAIT_LIMIT)) {
        wait_loops++;
    }
    result->wait_loops = wait_loops;

    (void)pl_capture_stop_stream();

    if ((dma_has_sg() != 0) && (rx_done != 0)) {
        if (reclaim_sg_rx_bds(1U,
                              transfer_bytes,
                              &completed_bd_count,
                              &completed_bytes,
                              &first_bd_status,
                              &last_bd_status) != XST_SUCCESS) {
            error = 1;
        }
    }

    Xil_DCacheInvalidateRange((UINTPTR)rx_buffer, transfer_bytes);

    result->dma_completed = (rx_done != 0) ? 1U : 0U;
    result->dma_error = (error != 0) ? 1U : 0U;
    result->timed_out = (wait_loops >= DMA_STREAM_SMOKE_WAIT_LIMIT) ? 1U : 0U;

    if (pl_capture_get_status(&capture_status) == XST_SUCCESS) {
        result->raw_status = capture_status.raw_status;
        result->status_error_code = capture_status.error_code;
    }

    if (pl_capture_get_counters(&counters) == XST_SUCCESS) {
        result->total_sample_count_lo = counters.total_sample_count_lo;
        result->total_sample_count_hi = counters.total_sample_count_hi;
        result->packet_count = counters.packet_count;
        result->overflow_count = counters.overflow_count;
        result->backpressure_count = counters.backpressure_count;
    }

    finalize_stream_smoke_result(result);

    if (result->dma_error != 0U) {
        result->result_code = DMA_CAPTURE_STREAM_SMOKE_DMA_ERROR;
    } else if (result->timed_out != 0U) {
        result->result_code = DMA_CAPTURE_STREAM_SMOKE_DMA_TIMEOUT;
    } else if ((result->raw_status & PL_CAPTURE_STATUS_ERROR_MASK) != 0U) {
        result->result_code = DMA_CAPTURE_STREAM_SMOKE_PL_STATUS_ERROR;
    } else if (result->overflow_count != 0U) {
        result->result_code = DMA_CAPTURE_STREAM_SMOKE_OVERFLOW;
    } else if (result->backpressure_count != 0U) {
        result->result_code = DMA_CAPTURE_STREAM_SMOKE_BACKPRESSURE;
    } else if ((result->total_sample_count_lo < sample_count) ||
               (result->packet_count == 0U)) {
        result->result_code = DMA_CAPTURE_STREAM_SMOKE_COUNTER_MISMATCH;
    } else {
        result->result_code = DMA_CAPTURE_STREAM_SMOKE_OK;
    }

    rx_done = 0;
    error = 0;
    active_capture_samples = 0U;
    active_capture_frame_id = 0U;
    active_capture_stream_mode = 0;

    return (result->result_code == DMA_CAPTURE_STREAM_SMOKE_OK)
        ? XST_SUCCESS
        : XST_FAILURE;
}

int dma_capture_main_path_smoke_test(u32 sample_count,
                                     dma_capture_stream_smoke_result_t *result)
{
    int status;
    u32 transfer_bytes;
    u32 wait_loops = 0U;
    pl_capture_status_t capture_status;
    pl_capture_counters_t counters;

    if ((result == 0) || (sample_count == 0U) ||
        (sample_count > PL_CAPTURE_MAX_FRAME_LEN)) {
        if (result != 0) {
            init_stream_smoke_result(sample_count, result);
            result->result_code = DMA_CAPTURE_STREAM_SMOKE_INVALID_ARG;
        }
        return XST_FAILURE;
    }

    init_stream_smoke_result(sample_count, result);
    transfer_bytes = sample_count * (u32)sizeof(u16);
    result->transfer_bytes = transfer_bytes;

    if (pl_capture_enabled == 0) {
        result->result_code = DMA_CAPTURE_STREAM_SMOKE_PL_UNAVAILABLE;
        finalize_stream_smoke_result(result);
        return XST_FAILURE;
    }

    status = dma_capture_reset();
    if (status != XST_SUCCESS) {
        result->result_code = DMA_CAPTURE_STREAM_SMOKE_DMA_RESET_FAIL;
        finalize_stream_smoke_result(result);
        return XST_FAILURE;
    }

    status = dma_capture_start(transfer_bytes);
    if (status != XST_SUCCESS) {
        result->result_code = DMA_CAPTURE_STREAM_SMOKE_DMA_START_FAIL;
        finalize_stream_smoke_result(result);
        return XST_FAILURE;
    }

    while ((wait_loops < DMA_STREAM_SMOKE_WAIT_LIMIT) &&
           (dma_capture_frame_ready() == 0)) {
        if (dma_capture_take_error() != 0) {
            error = 1;
            break;
        }
        wait_loops++;
    }
    result->wait_loops = wait_loops;

    result->dma_completed = (wait_loops < DMA_STREAM_SMOKE_WAIT_LIMIT) ? 1U : 0U;
    result->dma_error = (error != 0) ? 1U : 0U;
    result->timed_out =
        ((result->dma_completed == 0U) && (result->dma_error == 0U)) ? 1U : 0U;

    Xil_DCacheInvalidateRange((UINTPTR)rx_buffer, transfer_bytes);

    if (pl_capture_get_status(&capture_status) == XST_SUCCESS) {
        result->raw_status = capture_status.raw_status;
        result->status_error_code = capture_status.error_code;
        result->total_sample_count_lo = capture_status.sample_count;
    }

    if (pl_capture_get_counters(&counters) == XST_SUCCESS) {
        result->total_sample_count_lo = counters.total_sample_count_lo;
        result->total_sample_count_hi = counters.total_sample_count_hi;
        result->packet_count = counters.packet_count;
        result->overflow_count = counters.overflow_count;
        result->backpressure_count = counters.backpressure_count;
    }

    finalize_stream_smoke_result(result);

    if (result->dma_error != 0U) {
        result->result_code = DMA_CAPTURE_STREAM_SMOKE_DMA_ERROR;
    } else if (result->timed_out != 0U) {
        result->result_code = DMA_CAPTURE_STREAM_SMOKE_DMA_TIMEOUT;
    } else if ((result->raw_status & PL_CAPTURE_STATUS_ERROR_MASK) != 0U) {
        result->result_code = DMA_CAPTURE_STREAM_SMOKE_PL_STATUS_ERROR;
    } else if (result->overflow_count != 0U) {
        result->result_code = DMA_CAPTURE_STREAM_SMOKE_OVERFLOW;
    } else if (result->backpressure_count != 0U) {
        result->result_code = DMA_CAPTURE_STREAM_SMOKE_BACKPRESSURE;
    } else if ((result->total_sample_count_lo < sample_count) ||
               (result->packet_count == 0U)) {
        result->result_code = DMA_CAPTURE_STREAM_SMOKE_COUNTER_MISMATCH;
    } else {
        result->result_code = DMA_CAPTURE_STREAM_SMOKE_OK;
    }

    rx_done = 0;
    error = 0;
    active_capture_samples = 0U;
    active_capture_frame_id = 0U;
    active_capture_stream_mode = 0;

    return (result->result_code == DMA_CAPTURE_STREAM_SMOKE_OK)
        ? XST_SUCCESS
        : XST_FAILURE;
}

int dma_capture_sg_is_supported(void)
{
    return (dma_has_sg() != 0) ? 1 : 0;
}

void dma_capture_set_sg_smoke_burst_mode(int enable)
{
    sg_smoke_burst_mode = (enable != 0) ? 1 : 0;
}

int dma_capture_sg_smoke_test(u32 samples_per_bd,
                              u32 bd_count,
                              dma_capture_sg_smoke_result_t *result)
{
    int status;
    u32 total_samples;
    u32 total_bytes;
    u32 bytes_per_bd;
    u32 wait_loops = 0U;
    u32 completed_bd_count = 0U;
    u32 completed_bytes = 0U;
    u32 first_bd_status = 0U;
    u32 last_bd_status = 0U;
    pl_capture_status_t capture_status;
    pl_capture_counters_t counters;

    if (sg_smoke_burst_mode != 0) {
        return dma_capture_sg_burst_smoke_test(samples_per_bd,
                                               bd_count,
                                               result);
    }

    if ((result == 0) || (samples_per_bd == 0U) ||
        (bd_count == 0U) || (bd_count > DMA_SG_RX_BD_COUNT)) {
        if (result != 0) {
            init_sg_smoke_result(samples_per_bd, bd_count, result);
            result->result_code = DMA_CAPTURE_SG_SMOKE_INVALID_ARG;
        }
        return XST_FAILURE;
    }

    init_sg_smoke_result(samples_per_bd, bd_count, result);

    if (samples_per_bd > (DMA_MAX_SAMPLES / bd_count)) {
        result->result_code = DMA_CAPTURE_SG_SMOKE_INVALID_ARG;
        finalize_sg_smoke_result(result);
        return XST_FAILURE;
    }

    total_samples = samples_per_bd * bd_count;
    bytes_per_bd = samples_per_bd * (u32)sizeof(u16);
    total_bytes = total_samples * (u32)sizeof(u16);

    result->requested_samples = total_samples;
    result->requested_bytes = total_bytes;

    if (((bytes_per_bd & 0x3U) != 0U) ||
        (total_samples > PL_CAPTURE_MAX_FRAME_LEN)) {
        result->result_code = DMA_CAPTURE_SG_SMOKE_INVALID_ARG;
        finalize_sg_smoke_result(result);
        return XST_FAILURE;
    }

    if (pl_capture_enabled == 0) {
        result->result_code = DMA_CAPTURE_SG_SMOKE_PL_UNAVAILABLE;
        finalize_sg_smoke_result(result);
        return XST_FAILURE;
    }

    if (dma_has_sg() == 0) {
        result->result_code = DMA_CAPTURE_SG_SMOKE_UNSUPPORTED;
        finalize_sg_smoke_result(result);
        return XST_FAILURE;
    }

    status = dma_capture_reset();
    if (status != XST_SUCCESS) {
        result->result_code = DMA_CAPTURE_SG_SMOKE_DMA_RESET_FAIL;
        finalize_sg_smoke_result(result);
        return XST_FAILURE;
    }

    rx_done = 0;
    error = 0;
    current_transfer_bytes = total_bytes;
    active_capture_samples = 0U;
    active_capture_frame_id = 0U;
    Xil_DCacheFlushRange((UINTPTR)rx_buffer, total_bytes);

    status = submit_sg_rx_bds((UINTPTR)rx_buffer, bytes_per_bd, bd_count);
    if (status != XST_SUCCESS) {
        result->result_code = DMA_CAPTURE_SG_SMOKE_DMA_START_FAIL;
        finalize_sg_smoke_result(result);
        return XST_FAILURE;
    }

    status = pl_capture_start_stream(total_samples, allocate_capture_frame_id());
    if (status != XST_SUCCESS) {
        (void)pl_capture_stop_stream();
        XAxiDma_Reset(&axidma);
        result->result_code = DMA_CAPTURE_SG_SMOKE_STREAM_START_FAIL;
        finalize_sg_smoke_result(result);
        return XST_FAILURE;
    }

    while ((rx_done == 0) && (error == 0) &&
           (wait_loops < DMA_SG_SMOKE_WAIT_LIMIT)) {
        wait_loops++;
    }
    result->wait_loops = wait_loops;

    (void)pl_capture_stop_stream();

    if (rx_done != 0) {
        if (reclaim_sg_rx_bds(bd_count,
                              bytes_per_bd,
                              &completed_bd_count,
                              &completed_bytes,
                              &first_bd_status,
                              &last_bd_status) != XST_SUCCESS) {
            error = 1;
        }
    }

    Xil_DCacheInvalidateRange((UINTPTR)rx_buffer, total_bytes);

    result->completed_bd_count = completed_bd_count;
    result->completed_bytes = completed_bytes;
    result->first_bd_status = first_bd_status;
    result->last_bd_status = last_bd_status;
    result->dma_completed = (rx_done != 0) ? 1U : 0U;
    result->dma_error = (error != 0) ? 1U : 0U;
    result->timed_out = (wait_loops >= DMA_SG_SMOKE_WAIT_LIMIT) ? 1U : 0U;

    if (pl_capture_get_status(&capture_status) == XST_SUCCESS) {
        result->raw_status = capture_status.raw_status;
        result->status_error_code = capture_status.error_code;
    }

    if (pl_capture_get_counters(&counters) == XST_SUCCESS) {
        result->total_sample_count_lo = counters.total_sample_count_lo;
        result->total_sample_count_hi = counters.total_sample_count_hi;
        result->packet_count = counters.packet_count;
        result->overflow_count = counters.overflow_count;
        result->backpressure_count = counters.backpressure_count;
    }

    finalize_sg_smoke_result(result);

    if (result->dma_error != 0U) {
        result->result_code = DMA_CAPTURE_SG_SMOKE_DMA_ERROR;
    } else if (result->timed_out != 0U) {
        result->result_code = DMA_CAPTURE_SG_SMOKE_TIMEOUT;
    } else if ((result->raw_status & PL_CAPTURE_STATUS_ERROR_MASK) != 0U) {
        result->result_code = DMA_CAPTURE_SG_SMOKE_PL_STATUS_ERROR;
    } else if (result->overflow_count != 0U) {
        result->result_code = DMA_CAPTURE_SG_SMOKE_OVERFLOW;
    } else if (result->backpressure_count != 0U) {
        result->result_code = DMA_CAPTURE_SG_SMOKE_BACKPRESSURE;
    } else if ((result->completed_bd_count != bd_count) ||
               (result->completed_bytes < total_bytes) ||
               (result->total_sample_count_lo < total_samples) ||
               (result->packet_count == 0U)) {
        result->result_code = DMA_CAPTURE_SG_SMOKE_COUNTER_MISMATCH;
    } else {
        result->result_code = DMA_CAPTURE_SG_SMOKE_OK;
    }

    rx_done = 0;
    error = 0;
    active_capture_samples = 0U;
    active_capture_frame_id = 0U;
    active_capture_stream_mode = 0;

    return (result->result_code == DMA_CAPTURE_SG_SMOKE_OK)
        ? XST_SUCCESS
        : XST_FAILURE;
}

int dma_capture_sg_burst_smoke_test(u32 samples_per_bd,
                                    u32 bd_count,
                                    dma_capture_sg_smoke_result_t *result)
{
    int status;
    u32 total_samples;
    u32 total_bytes;
    u32 bytes_per_bd;
    u32 wait_loops = 0U;
    u32 completed_bd_count = 0U;
    u32 completed_bytes = 0U;
    u32 total_completed_bd_count = 0U;
    u32 total_completed_bytes = 0U;
    u32 first_bd_status = 0U;
    u32 last_bd_status = 0U;
    u32 capture_frame_id = 0U;
    u32 burst_status_ok = 0U;
    u32 burst_state_ok = 0U;
    u32 burst_packet_ok = 0U;
    UINTPTR completed_buffer_addrs[DMA_SG_RX_BD_COUNT];
    pl_capture_status_t capture_status;
    pl_capture_counters_t counters;
#if DMA_CAPTURE_BURST_DIAG_ENABLE
    dma_capture_burst_diag_t burst_diag;
    u64 burst_diag_total_start = 0U;
    u64 burst_diag_step_start = 0U;
    u64 burst_diag_step_end = 0U;
#endif

    if ((result == 0) || (samples_per_bd == 0U) ||
        (bd_count == 0U) || (bd_count > DMA_SG_RX_BD_COUNT)) {
        if (result != 0) {
            init_sg_smoke_result(samples_per_bd, bd_count, result);
            result->result_code = DMA_CAPTURE_SG_SMOKE_INVALID_ARG;
        }
        return XST_FAILURE;
    }

    init_sg_smoke_result(samples_per_bd, bd_count, result);

    if (samples_per_bd > (DMA_MAX_SAMPLES / bd_count)) {
        result->result_code = DMA_CAPTURE_SG_SMOKE_INVALID_ARG;
        finalize_sg_smoke_result(result);
        return XST_FAILURE;
    }

    total_samples = samples_per_bd * bd_count;
    bytes_per_bd = samples_per_bd * (u32)sizeof(u16);
    total_bytes = total_samples * (u32)sizeof(u16);

    result->requested_samples = total_samples;
    result->requested_bytes = total_bytes;

    if (((bytes_per_bd & 0x3U) != 0U) ||
        (samples_per_bd > PL_CAPTURE_MAX_FRAME_LEN)) {
        result->result_code = DMA_CAPTURE_SG_SMOKE_INVALID_ARG;
        finalize_sg_smoke_result(result);
        return XST_FAILURE;
    }

    if (pl_capture_enabled == 0) {
        result->result_code = DMA_CAPTURE_SG_SMOKE_PL_UNAVAILABLE;
        finalize_sg_smoke_result(result);
        return XST_FAILURE;
    }

    if (dma_has_sg() == 0) {
        result->result_code = DMA_CAPTURE_SG_SMOKE_UNSUPPORTED;
        finalize_sg_smoke_result(result);
        return XST_FAILURE;
    }

#if DMA_CAPTURE_BURST_DIAG_ENABLE
    memset(&burst_diag, 0, sizeof(burst_diag));
    burst_diag.version = DMA_CAPTURE_BURST_DIAG_VERSION;
    burst_diag.valid = 1U;
    burst_diag.sequence = ++burst_diag_sequence;
    burst_diag.samples_per_bd = samples_per_bd;
    burst_diag.bd_count = bd_count;
    burst_diag.requested_samples = total_samples;
    burst_diag.requested_bytes = total_bytes;
    burst_diag_total_start = burst_diag_now_ticks();
#endif

#if DMA_CAPTURE_BURST_DIAG_ENABLE
    burst_diag_step_start = burst_diag_now_ticks();
#endif
    status = dma_capture_reset();
#if DMA_CAPTURE_BURST_DIAG_ENABLE
    burst_diag_step_end = burst_diag_now_ticks();
    burst_diag.reset_us =
        burst_diag_elapsed_us(burst_diag_step_start, burst_diag_step_end);
#endif
    if (status != XST_SUCCESS) {
        result->result_code = DMA_CAPTURE_SG_SMOKE_DMA_RESET_FAIL;
        finalize_sg_smoke_result(result);
#if DMA_CAPTURE_BURST_DIAG_ENABLE
        burst_diag_commit(&burst_diag,
                          DMA_CAPTURE_SG_SMOKE_DMA_RESET_FAIL,
                          burst_diag_total_start);
#endif
        return XST_FAILURE;
    }

    rx_done = 0;
    error = 0;
    current_transfer_bytes = total_bytes;
    active_capture_samples = 0U;
    active_capture_frame_id = 0U;
    active_capture_stream_mode = 1;
#if DMA_CAPTURE_BURST_DIAG_ENABLE
    burst_diag_step_start = burst_diag_now_ticks();
#endif
    Xil_DCacheFlushRange((UINTPTR)rx_buffer, total_bytes);
#if DMA_CAPTURE_BURST_DIAG_ENABLE
    burst_diag_step_end = burst_diag_now_ticks();
    burst_diag.cache_flush_us =
        burst_diag_elapsed_us(burst_diag_step_start, burst_diag_step_end);
#endif

#if DMA_CAPTURE_BURST_DIAG_ENABLE
    burst_diag_step_start = burst_diag_now_ticks();
#endif
    status = submit_sg_rx_bds((UINTPTR)rx_buffer, bytes_per_bd, bd_count);
#if DMA_CAPTURE_BURST_DIAG_ENABLE
    burst_diag_step_end = burst_diag_now_ticks();
    burst_diag.bd_submit_us =
        burst_diag_elapsed_us(burst_diag_step_start, burst_diag_step_end);
#endif
    if (status != XST_SUCCESS) {
        result->result_code = DMA_CAPTURE_SG_SMOKE_DMA_START_FAIL;
        finalize_sg_smoke_result(result);
#if DMA_CAPTURE_BURST_DIAG_ENABLE
        burst_diag_commit(&burst_diag,
                          DMA_CAPTURE_SG_SMOKE_DMA_START_FAIL,
                          burst_diag_total_start);
#endif
        return XST_FAILURE;
    }

    capture_frame_id = allocate_capture_frame_id();
#if DMA_CAPTURE_BURST_DIAG_ENABLE
    burst_diag_step_start = burst_diag_now_ticks();
#endif
    status = pl_capture_start_burst(samples_per_bd, bd_count, capture_frame_id);
#if DMA_CAPTURE_BURST_DIAG_ENABLE
    burst_diag_step_end = burst_diag_now_ticks();
    burst_diag.pl_start_us =
        burst_diag_elapsed_us(burst_diag_step_start, burst_diag_step_end);
#endif
    if (status != XST_SUCCESS) {
        (void)pl_capture_stop_stream();
        XAxiDma_Reset(&axidma);
        result->result_code = DMA_CAPTURE_SG_SMOKE_STREAM_START_FAIL;
        finalize_sg_smoke_result(result);
#if DMA_CAPTURE_BURST_DIAG_ENABLE
        burst_diag_commit(&burst_diag,
                          DMA_CAPTURE_SG_SMOKE_STREAM_START_FAIL,
                          burst_diag_total_start);
#endif
        return XST_FAILURE;
    }

#if DMA_CAPTURE_BURST_DIAG_ENABLE
    burst_diag_step_start = burst_diag_now_ticks();
#endif
    while ((error == 0) &&
           (total_completed_bd_count < bd_count) &&
           (wait_loops < DMA_SG_SMOKE_WAIT_LIMIT)) {
        completed_bd_count = 0U;
        completed_bytes = 0U;

        if (reclaim_sg_rx_bds_any(bytes_per_bd,
                                  &completed_bd_count,
                                  &completed_bytes,
                                  &first_bd_status,
                                  &last_bd_status,
                                  completed_buffer_addrs,
                                  DMA_SG_RX_BD_COUNT) != XST_SUCCESS) {
            error = 1;
            break;
        }

        if (completed_bd_count != 0U) {
            total_completed_bd_count += completed_bd_count;
            total_completed_bytes += completed_bytes;
            rx_done = 0;
        } else {
            wait_loops++;
        }
    }
#if DMA_CAPTURE_BURST_DIAG_ENABLE
    burst_diag_step_end = burst_diag_now_ticks();
    burst_diag.wait_reclaim_us =
        burst_diag_elapsed_us(burst_diag_step_start, burst_diag_step_end);
#endif

    result->wait_loops = wait_loops;

#if DMA_CAPTURE_BURST_DIAG_ENABLE
    burst_diag_step_start = burst_diag_now_ticks();
#endif
    (void)pl_capture_stop_stream();
#if DMA_CAPTURE_BURST_DIAG_ENABLE
    burst_diag_step_end = burst_diag_now_ticks();
    burst_diag.stop_us =
        burst_diag_elapsed_us(burst_diag_step_start, burst_diag_step_end);
#endif
#if DMA_CAPTURE_BURST_DIAG_ENABLE
    burst_diag_step_start = burst_diag_now_ticks();
#endif
    Xil_DCacheInvalidateRange((UINTPTR)rx_buffer, total_bytes);
#if DMA_CAPTURE_BURST_DIAG_ENABLE
    burst_diag_step_end = burst_diag_now_ticks();
    burst_diag.cache_invalidate_us =
        burst_diag_elapsed_us(burst_diag_step_start, burst_diag_step_end);
#endif

    result->completed_bd_count = total_completed_bd_count;
    result->completed_bytes = total_completed_bytes;
    result->first_bd_status = first_bd_status;
    result->last_bd_status = last_bd_status;
    result->dma_completed =
        (total_completed_bd_count == bd_count) ? 1U : 0U;
    result->timed_out =
        (wait_loops >= DMA_SG_SMOKE_WAIT_LIMIT) ? 1U : 0U;

#if DMA_CAPTURE_BURST_DIAG_ENABLE
    burst_diag_step_start = burst_diag_now_ticks();
#endif
    if (pl_capture_get_status(&capture_status) == XST_SUCCESS) {
        result->raw_status = capture_status.raw_status;
        result->status_error_code = capture_status.error_code;

        if (pl_capture_validate_burst(&capture_status,
                                      samples_per_bd,
                                      bd_count,
                                      capture_frame_id) == XST_SUCCESS) {
            burst_state_ok = 1U;
            burst_packet_ok = 1U;
        } else if ((capture_status.available != 0U) &&
                   (capture_status.error == 0U) &&
                   (capture_status.overflow_seen == 0U) &&
                   (capture_status.backpressure_seen == 0U) &&
                   (capture_status.tlast_seen != 0U) &&
                   (capture_status.burst_done != 0U) &&
                   (capture_status.burst_active == 0U) &&
                   (capture_status.burst_remaining == 0U) &&
                   (capture_status.frame_len == samples_per_bd) &&
                   (capture_status.frame_count == bd_count) &&
                   (capture_status.frame_id == capture_frame_id) &&
                   (capture_status.done_frame_id == capture_frame_id)) {
            burst_state_ok = 1U;
        }
    } else {
        memset(&capture_status, 0, sizeof(capture_status));
        error = 1;
    }

    if (pl_capture_get_counters(&counters) == XST_SUCCESS) {
        result->total_sample_count_lo = counters.total_sample_count_lo;
        result->total_sample_count_hi = counters.total_sample_count_hi;
        result->packet_count = counters.packet_count;
        result->overflow_count = counters.overflow_count;
        result->backpressure_count = counters.backpressure_count;
    } else {
        memset(&counters, 0, sizeof(counters));
        error = 1;
    }
#if DMA_CAPTURE_BURST_DIAG_ENABLE
    burst_diag_step_end = burst_diag_now_ticks();
    burst_diag.status_us =
        burst_diag_elapsed_us(burst_diag_step_start, burst_diag_step_end);
    burst_diag.completed_bd_count = total_completed_bd_count;
    burst_diag.completed_bytes = total_completed_bytes;
    burst_diag.wait_loops = wait_loops;
    burst_diag.packet_count = result->packet_count;
    burst_diag.burst_packet_count = capture_status.burst_packet_count;
    burst_diag.burst_remaining = capture_status.burst_remaining;
    burst_diag.overflow_count = result->overflow_count;
    burst_diag.backpressure_count = result->backpressure_count;
    burst_diag.raw_status = result->raw_status;
#endif

    if ((capture_status.burst_packet_count == bd_count) ||
        (result->packet_count >= bd_count)) {
        burst_packet_ok = 1U;
    }

    burst_status_ok =
        ((burst_state_ok != 0U) && (burst_packet_ok != 0U)) ? 1U : 0U;

    result->dma_error = (error != 0) ? 1U : 0U;

    finalize_sg_smoke_result(result);
#if DMA_CAPTURE_BURST_DIAG_ENABLE
    burst_diag.s2mm_dmasr = result->s2mm_dmasr;
#endif

    if (result->dma_error != 0U) {
        result->result_code = DMA_CAPTURE_SG_SMOKE_DMA_ERROR;
    } else if (result->timed_out != 0U) {
        result->result_code = DMA_CAPTURE_SG_SMOKE_TIMEOUT;
    } else if ((result->raw_status & PL_CAPTURE_STATUS_ERROR_MASK) != 0U) {
        result->result_code = DMA_CAPTURE_SG_SMOKE_PL_STATUS_ERROR;
    } else if (result->overflow_count != 0U) {
        result->result_code = DMA_CAPTURE_SG_SMOKE_OVERFLOW;
    } else if (result->backpressure_count != 0U) {
        result->result_code = DMA_CAPTURE_SG_SMOKE_BACKPRESSURE;
    } else if ((result->completed_bd_count != bd_count) ||
               (result->completed_bytes != total_bytes) ||
               (result->total_sample_count_lo < total_samples) ||
               (burst_status_ok == 0U)) {
        result->result_code = DMA_CAPTURE_SG_SMOKE_COUNTER_MISMATCH;
    } else {
        result->result_code = DMA_CAPTURE_SG_SMOKE_OK;
    }

    rx_done = 0;
    error = 0;
    active_capture_samples = 0U;
    active_capture_frame_id = 0U;
    active_capture_stream_mode = 0;
    sg_rx_active_bd_count = 0U;
    sg_rx_active_bytes_per_bd = 0U;
#if DMA_CAPTURE_BURST_DIAG_ENABLE
    burst_diag_step_start = burst_diag_now_ticks();
#endif
    (void)dma_capture_reset();
#if DMA_CAPTURE_BURST_DIAG_ENABLE
    burst_diag_step_end = burst_diag_now_ticks();
    burst_diag.final_reset_us =
        burst_diag_elapsed_us(burst_diag_step_start, burst_diag_step_end);
    burst_diag_commit(&burst_diag, result->result_code, burst_diag_total_start);
#endif

    return (result->result_code == DMA_CAPTURE_SG_SMOKE_OK)
        ? XST_SUCCESS
        : XST_FAILURE;
}

int dma_capture_sg_burst_capture(u32 samples_per_bd,
                                 u32 bd_count,
                                 u32 *out_total_samples,
                                 dma_capture_sg_batch_diag_t *diag)
{
    int status;
    dma_capture_sg_smoke_result_t result;

    if (diag != 0) {
        memset(diag, 0, sizeof(*diag));
    }
    if (out_total_samples != 0) {
        *out_total_samples = 0U;
    }

    status = dma_capture_sg_burst_smoke_test(samples_per_bd,
                                             bd_count,
                                             &result);

    if (diag != 0) {
        diag->completed_bd_count = result.completed_bd_count;
        diag->completed_bytes = result.completed_bytes;
        diag->first_bd_status = result.first_bd_status;
        diag->last_bd_status = result.last_bd_status;
        diag->raw_status = result.raw_status;
        diag->status_error_code = result.status_error_code;
        diag->total_sample_count_lo = result.total_sample_count_lo;
        diag->total_sample_count_hi = result.total_sample_count_hi;
        diag->packet_count = result.packet_count;
        diag->overflow_count = result.overflow_count;
        diag->backpressure_count = result.backpressure_count;
    }

    if ((status == XST_SUCCESS) && (out_total_samples != 0)) {
        *out_total_samples = result.requested_samples;
    }

    return status;
}

int dma_capture_sg_batch_capture(u32 samples_per_bd,
                                 u32 bd_count,
                                 u32 *out_total_samples,
                                 dma_capture_sg_batch_diag_t *diag)
{
    int status;
    u32 total_samples;
    u32 total_bytes;
    u32 bytes_per_bd;
    u32 wait_loops = 0U;
    u32 completed_bd_count = 0U;
    u32 completed_bytes = 0U;
    u32 total_completed_bd_count = 0U;
    u32 total_completed_bytes = 0U;
    u32 first_bd_status = 0U;
    u32 last_bd_status = 0U;
    UINTPTR completed_buffer_addrs[DMA_SG_RX_BD_COUNT];
    pl_capture_status_t capture_status;
    pl_capture_counters_t counters;

    if (diag != 0) {
        memset(diag, 0, sizeof(*diag));
    }
    if (out_total_samples != 0) {
        *out_total_samples = 0U;
    }

    if ((samples_per_bd == 0U) ||
        (bd_count == 0U) ||
        (bd_count > DMA_SG_RX_BD_COUNT) ||
        (samples_per_bd > (DMA_MAX_SAMPLES / bd_count))) {
        return XST_FAILURE;
    }

    total_samples = samples_per_bd * bd_count;
    bytes_per_bd = samples_per_bd * (u32)sizeof(u16);
    total_bytes = total_samples * (u32)sizeof(u16);

    if (((bytes_per_bd & 0x3U) != 0U) ||
        (samples_per_bd > PL_CAPTURE_MAX_FRAME_LEN) ||
        (pl_capture_enabled == 0) ||
        (dma_has_sg() == 0)) {
        return XST_FAILURE;
    }

    status = dma_capture_reset();
    if (status != XST_SUCCESS) {
        return XST_FAILURE;
    }

    rx_done = 0;
    error = 0;
    current_transfer_bytes = total_bytes;
    active_capture_samples = 0U;
    active_capture_frame_id = 0U;
    active_capture_stream_mode = 0;
    Xil_DCacheFlushRange((UINTPTR)rx_buffer, total_bytes);

    status = submit_sg_rx_bds((UINTPTR)rx_buffer, bytes_per_bd, bd_count);
    if (status != XST_SUCCESS) {
        return XST_FAILURE;
    }

    status = pl_capture_start_stream(samples_per_bd, allocate_capture_frame_id());
    if (status != XST_SUCCESS) {
        (void)pl_capture_stop_stream();
        XAxiDma_Reset(&axidma);
        return XST_FAILURE;
    }

    while ((error == 0) &&
           (total_completed_bd_count < bd_count) &&
           (wait_loops < DMA_SG_SMOKE_WAIT_LIMIT)) {
        completed_bd_count = 0U;
        completed_bytes = 0U;

        if (reclaim_sg_rx_bds_any(bytes_per_bd,
                                  &completed_bd_count,
                                  &completed_bytes,
                                  &first_bd_status,
                                  &last_bd_status,
                                  completed_buffer_addrs,
                                  DMA_SG_RX_BD_COUNT) != XST_SUCCESS) {
            error = 1;
            break;
        }

        if (completed_bd_count != 0U) {
            total_completed_bd_count += completed_bd_count;
            total_completed_bytes += completed_bytes;
            rx_done = 0;
        } else {
            wait_loops++;
        }
    }

    (void)pl_capture_stop_stream();

    Xil_DCacheInvalidateRange((UINTPTR)rx_buffer, total_bytes);

    if (pl_capture_get_status(&capture_status) != XST_SUCCESS) {
        memset(&capture_status, 0, sizeof(capture_status));
        error = 1;
    }
    if (pl_capture_get_counters(&counters) != XST_SUCCESS) {
        memset(&counters, 0, sizeof(counters));
        error = 1;
    }

    if (diag != 0) {
        diag->completed_bd_count = total_completed_bd_count;
        diag->completed_bytes = total_completed_bytes;
        diag->first_bd_status = first_bd_status;
        diag->last_bd_status = last_bd_status;
        diag->raw_status = capture_status.raw_status;
        diag->status_error_code = capture_status.error_code;
        diag->total_sample_count_lo = counters.total_sample_count_lo;
        diag->total_sample_count_hi = counters.total_sample_count_hi;
        diag->packet_count = counters.packet_count;
        diag->overflow_count = counters.overflow_count;
        diag->backpressure_count = counters.backpressure_count;
    }

    rx_done = 0;
    active_capture_samples = 0U;
    active_capture_frame_id = 0U;
    active_capture_stream_mode = 0;
    sg_rx_active_bd_count = 0U;
    sg_rx_active_bytes_per_bd = 0U;

    if ((error != 0) ||
        (wait_loops >= DMA_SG_SMOKE_WAIT_LIMIT) ||
        ((capture_status.raw_status & PL_CAPTURE_STATUS_ERROR_MASK) != 0U) ||
        (counters.overflow_count != 0U) ||
        (counters.backpressure_count != 0U) ||
        (total_completed_bd_count != bd_count) ||
        (total_completed_bytes < total_bytes) ||
        (counters.total_sample_count_lo < total_samples) ||
        (counters.packet_count == 0U)) {
        error = 0;
        return XST_FAILURE;
    }

    error = 0;
    if (out_total_samples != 0) {
        *out_total_samples = total_samples;
    }
    return XST_SUCCESS;
}

int dma_capture_sg_ring_smoke_test(u32 samples_per_bd,
                                   u32 bd_count,
                                   u32 target_bd_count,
                                   dma_capture_sg_smoke_result_t *result)
{
    int status;
    u32 bytes_per_bd;
    u32 initial_bytes;
    u32 wait_loops = 0U;
    u32 completed_bd_count = 0U;
    u32 completed_bytes = 0U;
    u32 total_completed_bd_count = 0U;
    u32 total_completed_bytes = 0U;
    u32 first_bd_status = 0U;
    u32 last_bd_status = 0U;
    UINTPTR completed_buffer_addrs[DMA_SG_RX_BD_COUNT];
    pl_capture_status_t capture_status;
    pl_capture_counters_t counters;

    if ((result == 0) || (samples_per_bd == 0U) ||
        (bd_count == 0U) || (bd_count > DMA_SG_RX_BD_COUNT) ||
        (target_bd_count == 0U)) {
        if (result != 0) {
            init_sg_smoke_result(samples_per_bd, bd_count, result);
            result->result_code = DMA_CAPTURE_SG_SMOKE_INVALID_ARG;
        }
        return XST_FAILURE;
    }

    init_sg_smoke_result(samples_per_bd, bd_count, result);

    bytes_per_bd = samples_per_bd * (u32)sizeof(u16);
    initial_bytes = bytes_per_bd * bd_count;

    if (((bytes_per_bd & 0x3U) != 0U) ||
        (samples_per_bd > PL_CAPTURE_MAX_FRAME_LEN) ||
        (samples_per_bd > (DMA_MAX_SAMPLES / bd_count))) {
        result->result_code = DMA_CAPTURE_SG_SMOKE_INVALID_ARG;
        finalize_sg_smoke_result(result);
        return XST_FAILURE;
    }

    result->requested_samples = samples_per_bd * target_bd_count;
    result->requested_bytes = bytes_per_bd * target_bd_count;

    if (pl_capture_enabled == 0) {
        result->result_code = DMA_CAPTURE_SG_SMOKE_PL_UNAVAILABLE;
        finalize_sg_smoke_result(result);
        return XST_FAILURE;
    }

    if (dma_has_sg() == 0) {
        result->result_code = DMA_CAPTURE_SG_SMOKE_UNSUPPORTED;
        finalize_sg_smoke_result(result);
        return XST_FAILURE;
    }

    status = dma_capture_reset();
    if (status != XST_SUCCESS) {
        result->result_code = DMA_CAPTURE_SG_SMOKE_DMA_RESET_FAIL;
        finalize_sg_smoke_result(result);
        return XST_FAILURE;
    }

    rx_done = 0;
    error = 0;
    current_transfer_bytes = initial_bytes;
    active_capture_samples = 0U;
    active_capture_frame_id = 0U;
    active_capture_stream_mode = 1;
    Xil_DCacheFlushRange((UINTPTR)rx_buffer, initial_bytes);

    status = submit_sg_rx_bds((UINTPTR)rx_buffer, bytes_per_bd, bd_count);
    if (status != XST_SUCCESS) {
        result->result_code = DMA_CAPTURE_SG_SMOKE_DMA_START_FAIL;
        finalize_sg_smoke_result(result);
        return XST_FAILURE;
    }

    status = pl_capture_start_stream(samples_per_bd, allocate_capture_frame_id());
    if (status != XST_SUCCESS) {
        (void)pl_capture_stop_stream();
        XAxiDma_Reset(&axidma);
        result->result_code = DMA_CAPTURE_SG_SMOKE_STREAM_START_FAIL;
        finalize_sg_smoke_result(result);
        return XST_FAILURE;
    }

    while ((error == 0) &&
           (total_completed_bd_count < target_bd_count) &&
           (wait_loops < DMA_SG_SMOKE_WAIT_LIMIT)) {
        completed_bd_count = 0U;
        completed_bytes = 0U;

        if (reclaim_sg_rx_bds_any(bytes_per_bd,
                                  &completed_bd_count,
                                  &completed_bytes,
                                  &first_bd_status,
                                  &last_bd_status,
                                  completed_buffer_addrs,
                                  DMA_SG_RX_BD_COUNT) != XST_SUCCESS) {
            error = 1;
            break;
        }

        if (completed_bd_count != 0U) {
            u32 i;

            total_completed_bd_count += completed_bd_count;
            total_completed_bytes += completed_bytes;

            for (i = 0U; i < completed_bd_count; i++) {
                if (completed_buffer_addrs[i] == 0U) {
                    error = 1;
                    break;
                }

                Xil_DCacheInvalidateRange(completed_buffer_addrs[i],
                                          bytes_per_bd);
                Xil_DCacheFlushRange(completed_buffer_addrs[i],
                                     bytes_per_bd);

                status = submit_sg_rx_bds_start(completed_buffer_addrs[i],
                                                bytes_per_bd,
                                                1U,
                                                0);
                if (status != XST_SUCCESS) {
                    error = 1;
                    break;
                }
            }

            if (error != 0) {
                break;
            }

            rx_done = 0;
        } else {
            wait_loops++;
        }
    }

    result->wait_loops = wait_loops;

    (void)pl_capture_stop_stream();

    result->completed_bd_count = total_completed_bd_count;
    result->completed_bytes = total_completed_bytes;
    result->first_bd_status = first_bd_status;
    result->last_bd_status = last_bd_status;
    result->dma_completed =
        (total_completed_bd_count >= target_bd_count) ? 1U : 0U;
    result->dma_error = (error != 0) ? 1U : 0U;
    result->timed_out =
        (wait_loops >= DMA_SG_SMOKE_WAIT_LIMIT) ? 1U : 0U;

    if (pl_capture_get_status(&capture_status) == XST_SUCCESS) {
        result->raw_status = capture_status.raw_status;
        result->status_error_code = capture_status.error_code;
    }

    if (pl_capture_get_counters(&counters) == XST_SUCCESS) {
        result->total_sample_count_lo = counters.total_sample_count_lo;
        result->total_sample_count_hi = counters.total_sample_count_hi;
        result->packet_count = counters.packet_count;
        result->overflow_count = counters.overflow_count;
        result->backpressure_count = counters.backpressure_count;
    }

    finalize_sg_smoke_result(result);

    if (result->dma_error != 0U) {
        result->result_code = DMA_CAPTURE_SG_SMOKE_DMA_ERROR;
    } else if (result->timed_out != 0U) {
        result->result_code = DMA_CAPTURE_SG_SMOKE_TIMEOUT;
    } else if ((result->raw_status & PL_CAPTURE_STATUS_ERROR_MASK) != 0U) {
        result->result_code = DMA_CAPTURE_SG_SMOKE_PL_STATUS_ERROR;
    } else if (result->overflow_count != 0U) {
        result->result_code = DMA_CAPTURE_SG_SMOKE_OVERFLOW;
    } else if (result->backpressure_count != 0U) {
        result->result_code = DMA_CAPTURE_SG_SMOKE_BACKPRESSURE;
    } else if ((result->completed_bd_count < target_bd_count) ||
               (result->completed_bytes < result->requested_bytes) ||
               (result->total_sample_count_lo < result->requested_samples) ||
               (result->packet_count == 0U)) {
        result->result_code = DMA_CAPTURE_SG_SMOKE_COUNTER_MISMATCH;
    } else {
        result->result_code = DMA_CAPTURE_SG_SMOKE_OK;
    }

    rx_done = 0;
    error = 0;
    active_capture_samples = 0U;
    active_capture_frame_id = 0U;
    active_capture_stream_mode = 0;
    (void)dma_capture_reset();

    return (result->result_code == DMA_CAPTURE_SG_SMOKE_OK)
        ? XST_SUCCESS
        : XST_FAILURE;
}

void dma_capture_shutdown(void)
{
    if (pl_capture_enabled != 0) {
        (void)pl_capture_abort();
    }

    XScuGic_Disconnect(&intc, RX_INTR_ID);
}

static int dma_has_sg(void)
{
    return (axidma.HasSg != 0) ? 1 : 0;
}

static void stop_active_capture_stream(void)
{
    if (active_capture_stream_mode != 0) {
        (void)pl_capture_stop_stream();
        active_capture_stream_mode = 0;
    }
}

static void choose_sg_frame_layout(u32 transfer_bytes,
                                   u32 *bytes_per_bd,
                                   u32 *bd_count)
{
    u32 preferred_bytes_per_bd = DMA_SG_SAMPLES_PER_BD * (u32)sizeof(u16);

    *bytes_per_bd = transfer_bytes;
    *bd_count = 1U;

    if ((preferred_bytes_per_bd == 0U) ||
        ((preferred_bytes_per_bd & 0x3U) != 0U) ||
        (transfer_bytes < preferred_bytes_per_bd) ||
        ((transfer_bytes % preferred_bytes_per_bd) != 0U)) {
        return;
    }

    *bd_count = transfer_bytes / preferred_bytes_per_bd;
    if ((*bd_count == 0U) || (*bd_count > DMA_SG_RX_BD_COUNT)) {
        *bytes_per_bd = transfer_bytes;
        *bd_count = 1U;
        return;
    }

    *bytes_per_bd = preferred_bytes_per_bd;
}

static int reset_dma_core(void)
{
    int timeout;

    XAxiDma_Reset(&axidma);
    sg_rx_ring_ready = 0;
    sg_rx_active_bd_count = 0U;
    sg_rx_active_bytes_per_bd = 0U;

    timeout = (int)DMA_RESET_TIMEOUT;
    while (timeout > 0) {
        if (XAxiDma_ResetIsDone(&axidma) != 0) {
            break;
        }
        timeout--;
    }

    if (timeout == 0) {
        return XST_FAILURE;
    }

    if (dma_has_sg() != 0) {
        if (setup_sg_rx_ring() != XST_SUCCESS) {
            return XST_FAILURE;
        }
    } else {
        XAxiDma_IntrEnable(&axidma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);
    }

    return XST_SUCCESS;
}

static void capture_start_diag_record(u32 result_code,
                                      u32 transfer_bytes,
                                      u32 capture_samples)
{
    XAxiDma_BdRing *rx_ring;

    memset(&last_start_diag, 0, sizeof(last_start_diag));
    last_start_diag.result_code = result_code;
    last_start_diag.transfer_bytes = transfer_bytes;
    last_start_diag.capture_samples = capture_samples;
    last_start_diag.s2mm_dmacr =
        XAxiDma_ReadReg(axidma.RegBase,
                        XAXIDMA_RX_OFFSET + XAXIDMA_CR_OFFSET);
    last_start_diag.s2mm_dmasr =
        XAxiDma_ReadReg(axidma.RegBase,
                        XAXIDMA_RX_OFFSET + XAXIDMA_SR_OFFSET);
    last_start_diag.sg_ring_ready = (u32)sg_rx_ring_ready;
    last_start_diag.sg_active_bd_count = sg_rx_active_bd_count;

    if (dma_has_sg() != 0) {
        rx_ring = XAxiDma_GetRxRing(&axidma);
        last_start_diag.sg_free_bd_count =
            (u32)XAxiDma_BdRingGetFreeCnt(rx_ring);
    }
}

static int setup_sg_rx_ring(void)
{
    int status;
    XAxiDma_BdRing *rx_ring;
    XAxiDma_Bd bd_template;
    u32 bd_space_bytes;

    if (dma_has_sg() == 0) {
        return XST_SUCCESS;
    }

    rx_ring = XAxiDma_GetRxRing(&axidma);
    bd_space_bytes =
        (u32)XAxiDma_BdRingMemCalc(XAXIDMA_BD_MINIMUM_ALIGNMENT,
                                   DMA_SG_RX_BD_COUNT);
    if (bd_space_bytes > DMA_SG_RX_BD_SPACE_BYTES) {
        return XST_FAILURE;
    }

    memset(rx_bd_space, 0, sizeof(rx_bd_space));
    Xil_DCacheFlushRange((UINTPTR)rx_bd_space, sizeof(rx_bd_space));

    status = (int)XAxiDma_BdRingCreate(rx_ring,
                                       (UINTPTR)rx_bd_space,
                                       (UINTPTR)rx_bd_space,
                                       XAXIDMA_BD_MINIMUM_ALIGNMENT,
                                       (int)DMA_SG_RX_BD_COUNT);
    if (status != XST_SUCCESS) {
        return status;
    }

    XAxiDma_BdClear(&bd_template);
    status = XAxiDma_BdRingClone(rx_ring, &bd_template);
    if (status != XST_SUCCESS) {
        return status;
    }

    status = XAxiDma_BdRingSetCoalesce(rx_ring, 1U, 0U);
    if (status != XST_SUCCESS) {
        return status;
    }

    XAxiDma_BdRingIntEnable(rx_ring, XAXIDMA_IRQ_ALL_MASK);

    sg_rx_ring_ready = 1;
    return XST_SUCCESS;
}

static int submit_sg_rx_bds(UINTPTR buffer_addr, u32 bytes_per_bd, u32 bd_count)
{
    return submit_sg_rx_bds_start(buffer_addr, bytes_per_bd, bd_count, 1);
}

static int submit_sg_rx_bds_start(UINTPTR buffer_addr,
                                  u32 bytes_per_bd,
                                  u32 bd_count,
                                  int start_ring)
{
    int status;
    u32 i;
    XAxiDma_BdRing *rx_ring;
    XAxiDma_Bd *bd_set;
    XAxiDma_Bd *cur_bd;

    if ((dma_has_sg() == 0) ||
        (bd_count == 0U) || (bd_count > DMA_SG_RX_BD_COUNT) ||
        (bytes_per_bd == 0U)) {
        return XST_FAILURE;
    }

    if (sg_rx_ring_ready == 0) {
        status = setup_sg_rx_ring();
        if (status != XST_SUCCESS) {
            return status;
        }
    }

    rx_ring = XAxiDma_GetRxRing(&axidma);
    if (XAxiDma_BdRingGetFreeCnt(rx_ring) < (int)bd_count) {
        return XST_FAILURE;
    }

    status = XAxiDma_BdRingAlloc(rx_ring, (int)bd_count, &bd_set);
    if (status != XST_SUCCESS) {
        return status;
    }

    cur_bd = bd_set;
    for (i = 0U; i < bd_count; i++) {
        XAxiDma_BdClear(cur_bd);
        status = (int)XAxiDma_BdSetBufAddr(
            cur_bd,
            buffer_addr + ((UINTPTR)i * (UINTPTR)bytes_per_bd));
        if (status != XST_SUCCESS) {
            (void)XAxiDma_BdRingUnAlloc(rx_ring, (int)bd_count, bd_set);
            return status;
        }

        status = XAxiDma_BdSetLength(cur_bd,
                                     bytes_per_bd,
                                     rx_ring->MaxTransferLen);
        if (status != XST_SUCCESS) {
            (void)XAxiDma_BdRingUnAlloc(rx_ring, (int)bd_count, bd_set);
            return status;
        }

        XAxiDma_BdSetCtrl(cur_bd, 0U);
        XAxiDma_BdSetId(cur_bd,
                        buffer_addr + ((UINTPTR)i * (UINTPTR)bytes_per_bd));
        cur_bd = (XAxiDma_Bd *)(void *)XAxiDma_BdRingNext(rx_ring, cur_bd);
    }

    status = XAxiDma_BdRingToHw(rx_ring, (int)bd_count, bd_set);
    if (status != XST_SUCCESS) {
        return status;
    }

    if ((start_ring != 0) || (XAxiDma_BdRingHwIsStarted(rx_ring) == 0)) {
        status = XAxiDma_BdRingStart(rx_ring);
        if (status != XST_SUCCESS) {
            return status;
        }
    }

    sg_rx_active_bd_count = bd_count;
    sg_rx_active_bytes_per_bd = bytes_per_bd;
    return XST_SUCCESS;
}

static int reclaim_sg_rx_bds(u32 expected_bd_count,
                             u32 expected_bytes_per_bd,
                             u32 *completed_bd_count,
                             u32 *completed_bytes,
                             u32 *first_bd_status,
                             u32 *last_bd_status)
{
    int bd_count;
    int status;
    int i;
    u32 total_bytes = 0U;
    XAxiDma_BdRing *rx_ring;
    XAxiDma_Bd *bd_set;
    XAxiDma_Bd *cur_bd;

    if (dma_has_sg() == 0) {
        return XST_FAILURE;
    }

    rx_ring = XAxiDma_GetRxRing(&axidma);
    bd_count = XAxiDma_BdRingFromHw(rx_ring, XAXIDMA_ALL_BDS, &bd_set);
    if ((bd_count <= 0) || (bd_set == 0)) {
        return XST_FAILURE;
    }

    cur_bd = bd_set;
    for (i = 0; i < bd_count; i++) {
        u32 bd_status = XAxiDma_BdGetSts(cur_bd);
        u32 actual_len =
            XAxiDma_BdGetActualLength(cur_bd, rx_ring->MaxTransferLen);

        if (i == 0) {
            if (first_bd_status != 0) {
                *first_bd_status = bd_status;
            }
        }

        if (i == (bd_count - 1)) {
            if (last_bd_status != 0) {
                *last_bd_status = bd_status;
            }
        }

        if ((bd_status & XAXIDMA_BD_STS_ALL_ERR_MASK) != 0U) {
            status = XAxiDma_BdRingFree(rx_ring, bd_count, bd_set);
            (void)status;
            return XST_FAILURE;
        }

        if ((actual_len == 0U) || (actual_len > expected_bytes_per_bd)) {
            status = XAxiDma_BdRingFree(rx_ring, bd_count, bd_set);
            (void)status;
            return XST_FAILURE;
        }

        total_bytes += actual_len;
        cur_bd = (XAxiDma_Bd *)(void *)XAxiDma_BdRingNext(rx_ring, cur_bd);
    }

    status = XAxiDma_BdRingFree(rx_ring, bd_count, bd_set);
    if (status != XST_SUCCESS) {
        return status;
    }

    if (completed_bd_count != 0) {
        *completed_bd_count = (u32)bd_count;
    }
    if (completed_bytes != 0) {
        *completed_bytes = total_bytes;
    }

    sg_rx_active_bd_count = 0U;
    sg_rx_active_bytes_per_bd = 0U;

    if ((u32)bd_count != expected_bd_count) {
        return XST_FAILURE;
    }

    return XST_SUCCESS;
}

static int reclaim_sg_rx_bds_any(u32 expected_bytes_per_bd,
                                 u32 *completed_bd_count,
                                 u32 *completed_bytes,
                                 u32 *first_bd_status,
                                 u32 *last_bd_status,
                                 UINTPTR *buffer_addrs,
                                 u32 max_buffer_addrs)
{
    int bd_count;
    int status;
    int i;
    u32 total_bytes = 0U;
    UINTPTR buffer_base = (UINTPTR)rx_buffer;
    UINTPTR buffer_limit = (UINTPTR)rx_buffer + (UINTPTR)sizeof(rx_buffer);
    XAxiDma_BdRing *rx_ring;
    XAxiDma_Bd *bd_set;
    XAxiDma_Bd *cur_bd;

    if (dma_has_sg() == 0) {
        return XST_FAILURE;
    }

    if (completed_bd_count != 0) {
        *completed_bd_count = 0U;
    }
    if (completed_bytes != 0) {
        *completed_bytes = 0U;
    }

    rx_ring = XAxiDma_GetRxRing(&axidma);
    bd_count = XAxiDma_BdRingFromHw(rx_ring, XAXIDMA_ALL_BDS, &bd_set);
    if ((bd_count <= 0) || (bd_set == 0)) {
        return XST_SUCCESS;
    }

    if ((buffer_addrs == 0) || ((u32)bd_count > max_buffer_addrs)) {
        status = XAxiDma_BdRingFree(rx_ring, bd_count, bd_set);
        (void)status;
        return XST_FAILURE;
    }

    cur_bd = bd_set;
    for (i = 0; i < bd_count; i++) {
        u32 bd_status = XAxiDma_BdGetSts(cur_bd);
        u32 actual_len =
            XAxiDma_BdGetActualLength(cur_bd, rx_ring->MaxTransferLen);
        UINTPTR buffer_addr = (UINTPTR)XAxiDma_BdGetId(cur_bd);

        if (i == 0) {
            if (first_bd_status != 0) {
                *first_bd_status = bd_status;
            }
        }

        if (i == (bd_count - 1)) {
            if (last_bd_status != 0) {
                *last_bd_status = bd_status;
            }
        }

        if ((bd_status & XAXIDMA_BD_STS_ALL_ERR_MASK) != 0U) {
            status = XAxiDma_BdRingFree(rx_ring, bd_count, bd_set);
            (void)status;
            return XST_FAILURE;
        }

        if ((actual_len == 0U) || (actual_len > expected_bytes_per_bd)) {
            status = XAxiDma_BdRingFree(rx_ring, bd_count, bd_set);
            (void)status;
            return XST_FAILURE;
        }

        if ((buffer_addr < buffer_base) ||
            ((buffer_addr + (UINTPTR)expected_bytes_per_bd) > buffer_limit)) {
            status = XAxiDma_BdRingFree(rx_ring, bd_count, bd_set);
            (void)status;
            return XST_FAILURE;
        }

        buffer_addrs[i] = buffer_addr;
        total_bytes += actual_len;
        cur_bd = (XAxiDma_Bd *)(void *)XAxiDma_BdRingNext(rx_ring, cur_bd);
    }

    status = XAxiDma_BdRingFree(rx_ring, bd_count, bd_set);
    if (status != XST_SUCCESS) {
        return status;
    }

    if (completed_bd_count != 0) {
        *completed_bd_count = (u32)bd_count;
    }
    if (completed_bytes != 0) {
        *completed_bytes = total_bytes;
    }

    return XST_SUCCESS;
}

#if DMA_CAPTURE_BURST_DIAG_ENABLE
static u64 burst_diag_now_ticks(void)
{
    XTime now;

    XTime_GetTime(&now);
    return (u64)now;
}

static u32 burst_diag_elapsed_us(u64 start_ticks, u64 end_ticks)
{
    u64 ticks;
    u64 usec;

    if (end_ticks < start_ticks) {
        return 0U;
    }

    ticks = end_ticks - start_ticks;
    usec = (ticks * 1000000ULL) / (u64)COUNTS_PER_SECOND;
    if (usec > 0xFFFFFFFFULL) {
        return 0xFFFFFFFFU;
    }
    return (u32)usec;
}

static void burst_diag_commit(dma_capture_burst_diag_t *diag,
                              u32 result_code,
                              u64 total_start_ticks)
{
    if (diag == 0) {
        return;
    }

    diag->result_code = result_code;
    diag->total_us =
        burst_diag_elapsed_us(total_start_ticks, burst_diag_now_ticks());
    if (diag->s2mm_dmasr == 0U) {
        diag->s2mm_dmasr =
            XAxiDma_ReadReg(axidma.RegBase,
                            XAXIDMA_RX_OFFSET + XAXIDMA_SR_OFFSET);
    }
    diag->irq_count = irq_count;
    diag->last_irq_status = last_irq_status;
    last_burst_diag = *diag;
    if ((slowest_burst_diag.valid == 0U) ||
        (diag->total_us >= slowest_burst_diag.total_us)) {
        slowest_burst_diag = *diag;
    }
}
#endif

static u32 allocate_capture_frame_id(void)
{
    u32 frame_id = next_capture_frame_id;

    next_capture_frame_id++;
    if (next_capture_frame_id == 0U) {
        next_capture_frame_id = 1U;
    }

    return frame_id;
}

#define PL_CAPTURE_STATUS_POLL_LIMIT 1000U

static int wait_for_pl_capture_done(u32 expected_samples, u32 expected_frame_id)
{
    u32 timeout = PL_CAPTURE_STATUS_POLL_LIMIT;
    pl_capture_status_t capture_status;

    while (timeout > 0U) {
        if (pl_capture_get_status(&capture_status) != XST_SUCCESS) {
            return XST_FAILURE;
        }

        if (pl_capture_validate(&capture_status,
                                expected_samples,
                                expected_frame_id) == XST_SUCCESS) {
            return XST_SUCCESS;
        }

        if ((capture_status.error != 0U) ||
            (capture_status.overflow_seen != 0U) ||
            (capture_status.backpressure_seen != 0U)) {
            return XST_FAILURE;
        }

        timeout--;
    }

    return XST_FAILURE;
}

static void init_stream_smoke_result(u32 sample_count,
                                     dma_capture_stream_smoke_result_t *result)
{
    result->version = DMA_CAPTURE_STREAM_SMOKE_RESULT_VERSION;
    result->result_code = DMA_CAPTURE_STREAM_SMOKE_OK;
    result->requested_samples = sample_count;
    result->transfer_bytes = 0U;
    result->dma_completed = 0U;
    result->dma_error = 0U;
    result->timed_out = 0U;
    result->wait_loops = 0U;
    result->raw_status = 0U;
    result->status_error_code = 0U;
    result->total_sample_count_lo = 0U;
    result->total_sample_count_hi = 0U;
    result->packet_count = 0U;
    result->overflow_count = 0U;
    result->backpressure_count = 0U;
    result->s2mm_dmacr = 0U;
    result->s2mm_dmasr = 0U;
    result->irq_count = 0U;
    result->last_irq_status = 0U;
}

static void finalize_stream_smoke_result(dma_capture_stream_smoke_result_t *result)
{
    result->s2mm_dmacr =
        XAxiDma_ReadReg(axidma.RegBase, XAXIDMA_RX_OFFSET + XAXIDMA_CR_OFFSET);
    result->s2mm_dmasr =
        XAxiDma_ReadReg(axidma.RegBase, XAXIDMA_RX_OFFSET + XAXIDMA_SR_OFFSET);
    result->irq_count = irq_count;
    result->last_irq_status = last_irq_status;
}

static void init_sg_smoke_result(u32 samples_per_bd,
                                 u32 bd_count,
                                 dma_capture_sg_smoke_result_t *result)
{
    XAxiDma_Config *config;

    result->version = DMA_CAPTURE_SG_SMOKE_RESULT_VERSION;
    result->result_code = DMA_CAPTURE_SG_SMOKE_OK;
    result->samples_per_bd = samples_per_bd;
    result->bd_count = bd_count;
    result->requested_samples = samples_per_bd * bd_count;
    result->requested_bytes =
        result->requested_samples * (u32)sizeof(u16);
    result->completed_bd_count = 0U;
    result->completed_bytes = 0U;
    result->dma_completed = 0U;
    result->dma_error = 0U;
    result->timed_out = 0U;
    result->wait_loops = 0U;
    result->first_bd_status = 0U;
    result->last_bd_status = 0U;
    result->raw_status = 0U;
    result->status_error_code = 0U;
    result->total_sample_count_lo = 0U;
    result->total_sample_count_hi = 0U;
    result->packet_count = 0U;
    result->overflow_count = 0U;
    result->backpressure_count = 0U;
    result->s2mm_dmacr = 0U;
    result->s2mm_dmasr = 0U;
    result->irq_count = 0U;
    result->last_irq_status = 0U;

    config = XAxiDma_LookupConfig(DMA_DEV_ID);
    if (config != 0) {
        result->debug_config_has_sg = (u32)config->HasSg;
        result->debug_dma_device_id = config->DeviceId;
        result->debug_dma_baseaddr = (u32)config->BaseAddr;
    }
    result->debug_instance_has_sg = (u32)dma_has_sg();
    result->debug_ring_ready = (u32)sg_rx_ring_ready;
}

static void finalize_sg_smoke_result(dma_capture_sg_smoke_result_t *result)
{
    result->s2mm_dmacr =
        XAxiDma_ReadReg(axidma.RegBase, XAXIDMA_RX_OFFSET + XAXIDMA_CR_OFFSET);
    result->s2mm_dmasr =
        XAxiDma_ReadReg(axidma.RegBase, XAXIDMA_RX_OFFSET + XAXIDMA_SR_OFFSET);
    result->irq_count = irq_count;
    result->last_irq_status = last_irq_status;
    result->debug_instance_has_sg = (u32)dma_has_sg();
    result->debug_ring_ready = (u32)sg_rx_ring_ready;
}

static void rx_intr_handler(void *callback)
{
    XAxiDma *axidma_inst = (XAxiDma *)callback;
    u32 irq_status;

    XAxiDma_IntrDisable(axidma_inst, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);

    irq_status = XAxiDma_IntrGetIrq(axidma_inst, XAXIDMA_DEVICE_TO_DMA);
    irq_count++;
    last_irq_status = irq_status;
    XAxiDma_IntrAckIrq(axidma_inst, irq_status, XAXIDMA_DEVICE_TO_DMA);

    if ((irq_status & XAXIDMA_IRQ_ERROR_MASK) != 0U) {
        error = 1;
    }

    if ((irq_status & XAXIDMA_IRQ_IOC_MASK) != 0U) {
        rx_done = 1;
    }

    XAxiDma_IntrEnable(axidma_inst, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);
}

static int setup_intr_system(XScuGic *int_ins_ptr, XAxiDma *axidma_ptr, u16 rx_intr_id)
{
    int status;
    XScuGic_Config *intc_config;

    intc_config = XScuGic_LookupConfig(INTC_DEVICE_ID);
    if (intc_config == NULL) {
        return XST_FAILURE;
    }

    status = XScuGic_CfgInitialize(int_ins_ptr,
                                   intc_config,
                                   intc_config->CpuBaseAddress);
    if (status != XST_SUCCESS) {
        return XST_FAILURE;
    }

    XScuGic_SetPriorityTriggerType(int_ins_ptr, rx_intr_id, 0xA0, 0x3);

    status = XScuGic_Connect(int_ins_ptr,
                             rx_intr_id,
                             (Xil_InterruptHandler)rx_intr_handler,
                             axidma_ptr);
    if (status != XST_SUCCESS) {
        return status;
    }

    XScuGic_Enable(int_ins_ptr, rx_intr_id);

    Xil_ExceptionInit();
    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_INT,
                                 (Xil_ExceptionHandler)XScuGic_InterruptHandler,
                                 (void *)int_ins_ptr);
    Xil_ExceptionEnable();

    XAxiDma_IntrEnable(axidma_ptr, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);

    return XST_SUCCESS;
}
