#ifndef PL_CAPTURE_CONTROL_H
#define PL_CAPTURE_CONTROL_H

#include "xil_types.h"
#include "xparameters.h"
#include "xstatus.h"

/* Register map for the ADC capture-control AXI-Lite block. */
#define PL_CAPTURE_REG_CONTROL_OFFSET       0x00U
#define PL_CAPTURE_REG_STATUS_OFFSET        0x04U
#define PL_CAPTURE_REG_FRAME_LEN_OFFSET     0x08U
#define PL_CAPTURE_REG_FRAME_ID_OFFSET      0x0CU
#define PL_CAPTURE_REG_SAMPLE_COUNT_OFFSET  0x10U
#define PL_CAPTURE_REG_DONE_FRAME_ID_OFFSET 0x14U
#define PL_CAPTURE_REG_ERROR_CODE_OFFSET    0x18U
#define PL_CAPTURE_REG_VERSION_OFFSET       0x1CU
#define PL_CAPTURE_REG_TOTAL_SAMPLE_LO_OFFSET 0x20U
#define PL_CAPTURE_REG_TOTAL_SAMPLE_HI_OFFSET 0x24U
#define PL_CAPTURE_REG_PACKET_COUNT_OFFSET    0x28U
#define PL_CAPTURE_REG_OVERFLOW_COUNT_OFFSET  0x2CU
#define PL_CAPTURE_REG_BACKPRESSURE_COUNT_OFFSET 0x30U

#define PL_CAPTURE_CONTROL_START_MASK        (1U << 0)
#define PL_CAPTURE_CONTROL_ABORT_MASK        (1U << 1)
#define PL_CAPTURE_CONTROL_CLEAR_STATUS_MASK (1U << 2)
#define PL_CAPTURE_CONTROL_SOFT_RESET_MASK   (1U << 3)
#define PL_CAPTURE_CONTROL_CONTINUOUS_MODE_MASK (1U << 4)
#define PL_CAPTURE_CONTROL_STREAM_ENABLE_MASK   (1U << 5)
#define PL_CAPTURE_CONTROL_CLEAR_COUNTERS_MASK  (1U << 6)
#define PL_CAPTURE_CONTROL_FIFO_RESET_MASK      (1U << 7)

#define PL_CAPTURE_STATUS_IDLE_MASK              (1U << 0)
#define PL_CAPTURE_STATUS_BUSY_MASK              (1U << 1)
#define PL_CAPTURE_STATUS_DONE_MASK              (1U << 2)
#define PL_CAPTURE_STATUS_ERROR_MASK             (1U << 3)
#define PL_CAPTURE_STATUS_OVERFLOW_SEEN_MASK     (1U << 4)
#define PL_CAPTURE_STATUS_BACKPRESSURE_SEEN_MASK (1U << 5)
#define PL_CAPTURE_STATUS_TLAST_SEEN_MASK        (1U << 6)
#define PL_CAPTURE_STATUS_STREAMING_MASK         (1U << 7)

#define PL_CAPTURE_MAX_FRAME_LEN 16384U

typedef enum {
    PL_CAPTURE_ERROR_NONE = 0U,
    PL_CAPTURE_ERROR_INVALID_FRAME_LEN = 1U,
    PL_CAPTURE_ERROR_START_WHILE_BUSY = 2U,
    PL_CAPTURE_ERROR_ADC_OVERFLOW = 3U,
    PL_CAPTURE_ERROR_AXIS_BACKPRESSURE = 4U,
    PL_CAPTURE_ERROR_ABORT_REQUESTED = 5U,
    PL_CAPTURE_ERROR_UNAVAILABLE = 0xFFFFFFFEU
} pl_capture_error_code_t;

typedef struct {
    u8 available;
    u8 idle;
    u8 busy;
    u8 done;
    u8 error;
    u8 overflow_seen;
    u8 backpressure_seen;
    u8 tlast_seen;
    u8 streaming;
    u32 raw_status;
    u32 frame_len;
    u32 frame_id;
    u32 sample_count;
    u32 done_frame_id;
    u32 error_code;
    u32 version;
} pl_capture_status_t;

typedef struct {
    u32 total_sample_count_lo;
    u32 total_sample_count_hi;
    u32 packet_count;
    u32 overflow_count;
    u32 backpressure_count;
} pl_capture_counters_t;

/*
 * Optional manual override:
 *   #define PL_CAPTURE_CONTROL_BASEADDR <axi-lite base address>
 *
 * Otherwise this wrapper accepts the common BSP macro names expected from an
 * adc_capture_axis / capture-control IP. If none exist, the driver remains
 * compiled but unavailable and does not access any PL address.
 */
#ifndef PL_CAPTURE_CONTROL_BASEADDR
#if defined(XPAR_ADC_CAPTURE_AXIS_0_S_AXI_BASEADDR)
#define PL_CAPTURE_CONTROL_BASEADDR XPAR_ADC_CAPTURE_AXIS_0_S_AXI_BASEADDR
#elif defined(XPAR_ADC_CAPTURE_AXIS_0_S00_AXI_BASEADDR)
#define PL_CAPTURE_CONTROL_BASEADDR XPAR_ADC_CAPTURE_AXIS_0_S00_AXI_BASEADDR
#elif defined(XPAR_ADC_CAPTURE_AXIS_0_BASEADDR)
#define PL_CAPTURE_CONTROL_BASEADDR XPAR_ADC_CAPTURE_AXIS_0_BASEADDR
#elif defined(XPAR_ADC_CAPTURE_CONTROL_0_S_AXI_BASEADDR)
#define PL_CAPTURE_CONTROL_BASEADDR XPAR_ADC_CAPTURE_CONTROL_0_S_AXI_BASEADDR
#elif defined(XPAR_ADC_CAPTURE_CONTROL_0_S00_AXI_BASEADDR)
#define PL_CAPTURE_CONTROL_BASEADDR XPAR_ADC_CAPTURE_CONTROL_0_S00_AXI_BASEADDR
#elif defined(XPAR_ADC_CAPTURE_CONTROL_0_BASEADDR)
#define PL_CAPTURE_CONTROL_BASEADDR XPAR_ADC_CAPTURE_CONTROL_0_BASEADDR
#elif defined(XPAR_PL_CAPTURE_CONTROL_0_S_AXI_BASEADDR)
#define PL_CAPTURE_CONTROL_BASEADDR XPAR_PL_CAPTURE_CONTROL_0_S_AXI_BASEADDR
#elif defined(XPAR_PL_CAPTURE_CONTROL_0_S00_AXI_BASEADDR)
#define PL_CAPTURE_CONTROL_BASEADDR XPAR_PL_CAPTURE_CONTROL_0_S00_AXI_BASEADDR
#elif defined(XPAR_PL_CAPTURE_CONTROL_0_BASEADDR)
#define PL_CAPTURE_CONTROL_BASEADDR XPAR_PL_CAPTURE_CONTROL_0_BASEADDR
#elif defined(XPAR_CAPTURE_CONTROL_0_S_AXI_BASEADDR)
#define PL_CAPTURE_CONTROL_BASEADDR XPAR_CAPTURE_CONTROL_0_S_AXI_BASEADDR
#elif defined(XPAR_CAPTURE_CONTROL_0_S00_AXI_BASEADDR)
#define PL_CAPTURE_CONTROL_BASEADDR XPAR_CAPTURE_CONTROL_0_S00_AXI_BASEADDR
#elif defined(XPAR_CAPTURE_CONTROL_0_BASEADDR)
#define PL_CAPTURE_CONTROL_BASEADDR XPAR_CAPTURE_CONTROL_0_BASEADDR
#endif
#endif

#if defined(PL_CAPTURE_CONTROL_BASEADDR)
#define PL_CAPTURE_CONTROL_AVAILABLE 1
#else
#define PL_CAPTURE_CONTROL_AVAILABLE 0
#endif

int pl_capture_is_available(void);
int pl_capture_init(void);
int pl_capture_abort(void);
int pl_capture_clear_status(void);
int pl_capture_clear_counters(void);
int pl_capture_reset_fifo(void);
int pl_capture_configure(u32 frame_len, u32 frame_id);
int pl_capture_start(void);
int pl_capture_set_continuous_mode(int enable);
int pl_capture_set_stream_enable(int enable);
int pl_capture_start_stream(u32 frame_len, u32 frame_id);
int pl_capture_stop_stream(void);
int pl_capture_get_status(pl_capture_status_t *status);
int pl_capture_get_counters(pl_capture_counters_t *counters);
int pl_capture_validate(const pl_capture_status_t *status,
                        u32 expected_len,
                        u32 expected_frame_id);
int pl_capture_status_ok_for_frame(const pl_capture_status_t *status,
                                   u32 expected_len,
                                   u32 expected_frame_id);

#endif
