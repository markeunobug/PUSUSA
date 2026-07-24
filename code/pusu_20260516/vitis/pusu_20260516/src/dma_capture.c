#include "dma_capture.h"

#include "app_config.h"
#include "pl_capture_control.h"
#include "xaxidma.h"
#include "xaxidma_bd.h"
#include "xaxidma_hw.h"
#include "xil_cache.h"
#include "xil_exception.h"
#include "xscugic.h"

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

#define DMA_STREAM_SMOKE_WAIT_LIMIT 1000000U
#define DMA_SG_SMOKE_WAIT_LIMIT 1000000U
#define DMA_SG_RX_BD_COUNT 8U
#define DMA_SG_RX_BD_SPACE_BYTES 2048U

static u8 rx_bd_space[DMA_SG_RX_BD_SPACE_BYTES]
    __attribute__((aligned(XAXIDMA_BD_MINIMUM_ALIGNMENT)));
static int sg_rx_ring_ready = 0;
static u32 sg_rx_active_bd_count = 0U;
static u32 sg_rx_active_bytes_per_bd = 0U;

static void rx_intr_handler(void *callback);
static int setup_intr_system(XScuGic *int_ins_ptr, XAxiDma *axidma_ptr, u16 rx_intr_id);
static int reset_dma_core(void);
static int setup_sg_rx_ring(void);
static int submit_sg_rx_bds(UINTPTR buffer_addr, u32 bytes_per_bd, u32 bd_count);
static int reclaim_sg_rx_bds(u32 expected_bd_count,
                             u32 expected_bytes_per_bd,
                             u32 *completed_bd_count,
                             u32 *completed_bytes,
                             u32 *first_bd_status,
                             u32 *last_bd_status);
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

    if (XAxiDma_HasSg(&axidma) != 0) {
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
        return XST_FAILURE;
    }

    capture_samples = transfer_bytes / (u32)sizeof(u16);
    if ((capture_samples == 0U) ||
        ((pl_capture_enabled != 0) &&
         (capture_samples > PL_CAPTURE_MAX_FRAME_LEN))) {
        return XST_FAILURE;
    }

    if (pl_capture_enabled != 0) {
        if (pl_capture_abort() != XST_SUCCESS) {
            return XST_FAILURE;
        }
        if (pl_capture_clear_status() != XST_SUCCESS) {
            return XST_FAILURE;
        }

        capture_frame_id = allocate_capture_frame_id();
        status = pl_capture_configure(capture_samples, capture_frame_id);
        if (status != XST_SUCCESS) {
            return status;
        }
    }

    rx_done = 0;
    error = 0;
    current_transfer_bytes = transfer_bytes;
    active_capture_samples = capture_samples;
    active_capture_frame_id = capture_frame_id;

    Xil_DCacheFlushRange((UINTPTR)rx_buffer, (u32)transfer_bytes);

    if (XAxiDma_HasSg(&axidma) != 0) {
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
        active_capture_samples = 0U;
        active_capture_frame_id = 0U;
        return status;
    }

    if (pl_capture_enabled != 0) {
        status = pl_capture_start();
        if (status != XST_SUCCESS) {
            active_capture_samples = 0U;
            active_capture_frame_id = 0U;
            XAxiDma_Reset(&axidma);
            return status;
        }
    }

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

    if ((XAxiDma_HasSg(&axidma) != 0) && (sg_rx_active_bd_count != 0U)) {
        if (reclaim_sg_rx_bds(sg_rx_active_bd_count,
                              sg_rx_active_bytes_per_bd,
                              &completed_bd_count,
                              &completed_bytes,
                              &first_bd_status,
                              &last_bd_status) != XST_SUCCESS) {
            error = 1;
            return 0;
        }

        if (completed_bytes < current_transfer_bytes) {
            error = 1;
            return 0;
        }
    }

    Xil_DCacheInvalidateRange((UINTPTR)rx_buffer, current_transfer_bytes);

    if (pl_capture_enabled != 0) {
        if (wait_for_pl_capture_done(active_capture_samples,
                                     active_capture_frame_id) != XST_SUCCESS) {
            error = 1;
            return 0;
        }

        (void)pl_capture_clear_status();
    }

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

    if (XAxiDma_HasSg(&axidma) != 0) {
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

    if ((XAxiDma_HasSg(&axidma) != 0) && (rx_done != 0)) {
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

    return (result->result_code == DMA_CAPTURE_STREAM_SMOKE_OK)
        ? XST_SUCCESS
        : XST_FAILURE;
}

int dma_capture_sg_is_supported(void)
{
    return (XAxiDma_HasSg(&axidma) != 0) ? 1 : 0;
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

    if (XAxiDma_HasSg(&axidma) == 0) {
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

    if (XAxiDma_HasSg(&axidma) != 0) {
        if (setup_sg_rx_ring() != XST_SUCCESS) {
            return XST_FAILURE;
        }
    } else {
        XAxiDma_IntrEnable(&axidma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);
    }

    return XST_SUCCESS;
}

static int setup_sg_rx_ring(void)
{
    int status;
    XAxiDma_BdRing *rx_ring;
    XAxiDma_Bd bd_template;
    u32 bd_space_bytes;

    if (XAxiDma_HasSg(&axidma) == 0) {
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
    int status;
    u32 i;
    XAxiDma_BdRing *rx_ring;
    XAxiDma_Bd *bd_set;
    XAxiDma_Bd *cur_bd;

    if ((XAxiDma_HasSg(&axidma) == 0) ||
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
        XAxiDma_BdSetId(cur_bd, buffer_addr);
        cur_bd = (XAxiDma_Bd *)(void *)XAxiDma_BdRingNext(rx_ring, cur_bd);
    }

    status = XAxiDma_BdRingToHw(rx_ring, (int)bd_count, bd_set);
    if (status != XST_SUCCESS) {
        return status;
    }

    status = XAxiDma_BdRingStart(rx_ring);
    if (status != XST_SUCCESS) {
        return status;
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

    if (XAxiDma_HasSg(&axidma) == 0) {
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
}

static void finalize_sg_smoke_result(dma_capture_sg_smoke_result_t *result)
{
    result->s2mm_dmacr =
        XAxiDma_ReadReg(axidma.RegBase, XAXIDMA_RX_OFFSET + XAXIDMA_CR_OFFSET);
    result->s2mm_dmasr =
        XAxiDma_ReadReg(axidma.RegBase, XAXIDMA_RX_OFFSET + XAXIDMA_SR_OFFSET);
    result->irq_count = irq_count;
    result->last_irq_status = last_irq_status;
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
