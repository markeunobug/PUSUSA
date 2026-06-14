#include "pl_capture_control.h"

#include "xil_io.h"

static int pl_capture_write_reg(u32 offset, u32 value);
static int pl_capture_read_reg(u32 offset, u32 *value);
static int pl_capture_write_control(u32 pulse_mask);
static void pl_capture_reset_delay(void);
static u8 pl_capture_bit_is_set(u32 value, u32 mask);

static u32 control_hold_mask;

int pl_capture_is_available(void)
{
    return PL_CAPTURE_CONTROL_AVAILABLE;
}

int pl_capture_init(void)
{
    if (pl_capture_is_available() == 0) {
        return XST_FAILURE;
    }

    control_hold_mask = 0U;
    if (pl_capture_stop_stream() != XST_SUCCESS) {
        return XST_FAILURE;
    }

    return pl_capture_clear_status();
}

int pl_capture_abort(void)
{
    control_hold_mask &= ~(PL_CAPTURE_CONTROL_CONTINUOUS_MODE_MASK |
                           PL_CAPTURE_CONTROL_STREAM_ENABLE_MASK);

    return pl_capture_write_control(PL_CAPTURE_CONTROL_ABORT_MASK);
}

int pl_capture_clear_status(void)
{
    return pl_capture_write_control(PL_CAPTURE_CONTROL_CLEAR_STATUS_MASK);
}

int pl_capture_clear_counters(void)
{
    return pl_capture_write_control(PL_CAPTURE_CONTROL_CLEAR_COUNTERS_MASK);
}

int pl_capture_reset_fifo(void)
{
    int status;

    control_hold_mask &= ~(PL_CAPTURE_CONTROL_CONTINUOUS_MODE_MASK |
                           PL_CAPTURE_CONTROL_STREAM_ENABLE_MASK);

    status = pl_capture_write_control(PL_CAPTURE_CONTROL_FIFO_RESET_MASK);
    if (status != XST_SUCCESS) {
        return status;
    }

    pl_capture_reset_delay();

    status = pl_capture_write_control(0U);
    if (status != XST_SUCCESS) {
        return status;
    }

    pl_capture_reset_delay();
    return XST_SUCCESS;
}

int pl_capture_configure(u32 frame_len, u32 frame_id)
{
    int status;

    if (pl_capture_is_available() == 0) {
        return XST_FAILURE;
    }

    if ((frame_len == 0U) || (frame_len > PL_CAPTURE_MAX_FRAME_LEN)) {
        return XST_FAILURE;
    }

    status = pl_capture_write_reg(PL_CAPTURE_REG_FRAME_LEN_OFFSET, frame_len);
    if (status != XST_SUCCESS) {
        return status;
    }

    status = pl_capture_write_reg(PL_CAPTURE_REG_FRAME_ID_OFFSET, frame_id);
    if (status != XST_SUCCESS) {
        return status;
    }

    return pl_capture_write_reg(PL_CAPTURE_REG_FRAME_COUNT_OFFSET, 0U);
}

int pl_capture_configure_burst(u32 frame_len, u32 frame_count, u32 frame_id)
{
    int status;

    if (pl_capture_is_available() == 0) {
        return XST_FAILURE;
    }

    if ((frame_len == 0U) ||
        (frame_len > PL_CAPTURE_MAX_FRAME_LEN) ||
        (frame_count == 0U)) {
        return XST_FAILURE;
    }

    status = pl_capture_write_reg(PL_CAPTURE_REG_FRAME_LEN_OFFSET, frame_len);
    if (status != XST_SUCCESS) {
        return status;
    }

    status = pl_capture_write_reg(PL_CAPTURE_REG_FRAME_COUNT_OFFSET, frame_count);
    if (status != XST_SUCCESS) {
        return status;
    }

    return pl_capture_write_reg(PL_CAPTURE_REG_FRAME_ID_OFFSET, frame_id);
}

int pl_capture_start(void)
{
    control_hold_mask = 0U;
    return pl_capture_write_control(PL_CAPTURE_CONTROL_START_MASK);
}

int pl_capture_set_continuous_mode(int enable)
{
    if (enable != 0) {
        control_hold_mask |= PL_CAPTURE_CONTROL_CONTINUOUS_MODE_MASK;
    } else {
        control_hold_mask &= ~PL_CAPTURE_CONTROL_CONTINUOUS_MODE_MASK;
    }

    return pl_capture_write_control(0U);
}

int pl_capture_set_stream_enable(int enable)
{
    if (enable != 0) {
        control_hold_mask |= PL_CAPTURE_CONTROL_STREAM_ENABLE_MASK;
    } else {
        control_hold_mask &= ~PL_CAPTURE_CONTROL_STREAM_ENABLE_MASK;
    }

    return pl_capture_write_control(0U);
}

int pl_capture_start_stream(u32 frame_len, u32 frame_id)
{
    int status;

    status = pl_capture_stop_stream();
    if (status != XST_SUCCESS) {
        return status;
    }

    status = pl_capture_configure(frame_len, frame_id);
    if (status != XST_SUCCESS) {
        return status;
    }

    status = pl_capture_clear_status();
    if (status != XST_SUCCESS) {
        return status;
    }

    status = pl_capture_clear_counters();
    if (status != XST_SUCCESS) {
        return status;
    }

    control_hold_mask = PL_CAPTURE_CONTROL_CONTINUOUS_MODE_MASK |
                        PL_CAPTURE_CONTROL_STREAM_ENABLE_MASK;

    return pl_capture_write_control(0U);
}

int pl_capture_start_burst(u32 frame_len, u32 frame_count, u32 frame_id)
{
    int status;

    status = pl_capture_stop_stream();
    if (status != XST_SUCCESS) {
        return status;
    }

    status = pl_capture_configure_burst(frame_len, frame_count, frame_id);
    if (status != XST_SUCCESS) {
        return status;
    }

    status = pl_capture_clear_status();
    if (status != XST_SUCCESS) {
        return status;
    }

    status = pl_capture_clear_counters();
    if (status != XST_SUCCESS) {
        return status;
    }

    control_hold_mask = PL_CAPTURE_CONTROL_CONTINUOUS_MODE_MASK |
                        PL_CAPTURE_CONTROL_STREAM_ENABLE_MASK;

    status = pl_capture_write_control(0U);
    if (status != XST_SUCCESS) {
        return status;
    }
    pl_capture_reset_delay();

    status = pl_capture_write_control(PL_CAPTURE_CONTROL_START_MASK);
    if (status != XST_SUCCESS) {
        return status;
    }

    return pl_capture_write_control(0U);
}

int pl_capture_stop_stream(void)
{
    control_hold_mask &= ~(PL_CAPTURE_CONTROL_CONTINUOUS_MODE_MASK |
                           PL_CAPTURE_CONTROL_STREAM_ENABLE_MASK);

    return pl_capture_write_control(0U);
}

int pl_capture_get_status(pl_capture_status_t *status)
{
    u32 raw_status = 0U;
    int read_status;

    if (status == 0) {
        return XST_FAILURE;
    }

    status->available = (u8)pl_capture_is_available();
    status->idle = 0U;
    status->busy = 0U;
    status->done = 0U;
    status->error = 0U;
    status->overflow_seen = 0U;
    status->backpressure_seen = 0U;
    status->tlast_seen = 0U;
    status->streaming = 0U;
    status->burst_active = 0U;
    status->burst_done = 0U;
    status->raw_status = 0U;
    status->frame_len = 0U;
    status->frame_id = 0U;
    status->frame_count = 0U;
    status->sample_count = 0U;
    status->done_frame_id = 0U;
    status->error_code = PL_CAPTURE_ERROR_UNAVAILABLE;
    status->version = 0U;
    status->burst_packet_count = 0U;
    status->burst_remaining = 0U;

    if (pl_capture_is_available() == 0) {
        return XST_FAILURE;
    }

    read_status = pl_capture_read_reg(PL_CAPTURE_REG_STATUS_OFFSET, &raw_status);
    if (read_status != XST_SUCCESS) {
        return read_status;
    }

    status->raw_status = raw_status;
    status->idle = pl_capture_bit_is_set(raw_status, PL_CAPTURE_STATUS_IDLE_MASK);
    status->busy = pl_capture_bit_is_set(raw_status, PL_CAPTURE_STATUS_BUSY_MASK);
    status->done = pl_capture_bit_is_set(raw_status, PL_CAPTURE_STATUS_DONE_MASK);
    status->error = pl_capture_bit_is_set(raw_status, PL_CAPTURE_STATUS_ERROR_MASK);
    status->overflow_seen =
        pl_capture_bit_is_set(raw_status, PL_CAPTURE_STATUS_OVERFLOW_SEEN_MASK);
    status->backpressure_seen =
        pl_capture_bit_is_set(raw_status, PL_CAPTURE_STATUS_BACKPRESSURE_SEEN_MASK);
    status->tlast_seen =
        pl_capture_bit_is_set(raw_status, PL_CAPTURE_STATUS_TLAST_SEEN_MASK);
    status->streaming =
        pl_capture_bit_is_set(raw_status, PL_CAPTURE_STATUS_STREAMING_MASK);
    status->burst_active =
        pl_capture_bit_is_set(raw_status, PL_CAPTURE_STATUS_BURST_ACTIVE_MASK);
    status->burst_done =
        pl_capture_bit_is_set(raw_status, PL_CAPTURE_STATUS_BURST_DONE_MASK);

    if (pl_capture_read_reg(PL_CAPTURE_REG_FRAME_LEN_OFFSET,
                            &status->frame_len) != XST_SUCCESS) {
        return XST_FAILURE;
    }

    if (pl_capture_read_reg(PL_CAPTURE_REG_FRAME_ID_OFFSET,
                            &status->frame_id) != XST_SUCCESS) {
        return XST_FAILURE;
    }

    if (pl_capture_read_reg(PL_CAPTURE_REG_FRAME_COUNT_OFFSET,
                            &status->frame_count) != XST_SUCCESS) {
        return XST_FAILURE;
    }

    if (pl_capture_read_reg(PL_CAPTURE_REG_SAMPLE_COUNT_OFFSET,
                            &status->sample_count) != XST_SUCCESS) {
        return XST_FAILURE;
    }

    if (pl_capture_read_reg(PL_CAPTURE_REG_DONE_FRAME_ID_OFFSET,
                            &status->done_frame_id) != XST_SUCCESS) {
        return XST_FAILURE;
    }

    if (pl_capture_read_reg(PL_CAPTURE_REG_ERROR_CODE_OFFSET,
                            &status->error_code) != XST_SUCCESS) {
        return XST_FAILURE;
    }

    if (pl_capture_read_reg(PL_CAPTURE_REG_VERSION_OFFSET,
                            &status->version) != XST_SUCCESS) {
        return XST_FAILURE;
    }

    if (pl_capture_read_reg(PL_CAPTURE_REG_BURST_PACKET_COUNT_OFFSET,
                            &status->burst_packet_count) != XST_SUCCESS) {
        return XST_FAILURE;
    }

    if (pl_capture_read_reg(PL_CAPTURE_REG_BURST_REMAINING_OFFSET,
                            &status->burst_remaining) != XST_SUCCESS) {
        return XST_FAILURE;
    }

    return XST_SUCCESS;
}

int pl_capture_get_counters(pl_capture_counters_t *counters)
{
    if (counters == 0) {
        return XST_FAILURE;
    }

    counters->total_sample_count_lo = 0U;
    counters->total_sample_count_hi = 0U;
    counters->packet_count = 0U;
    counters->overflow_count = 0U;
    counters->backpressure_count = 0U;

    if (pl_capture_is_available() == 0) {
        return XST_FAILURE;
    }

    if (pl_capture_read_reg(PL_CAPTURE_REG_TOTAL_SAMPLE_LO_OFFSET,
                            &counters->total_sample_count_lo) != XST_SUCCESS) {
        return XST_FAILURE;
    }

    if (pl_capture_read_reg(PL_CAPTURE_REG_TOTAL_SAMPLE_HI_OFFSET,
                            &counters->total_sample_count_hi) != XST_SUCCESS) {
        return XST_FAILURE;
    }

    if (pl_capture_read_reg(PL_CAPTURE_REG_PACKET_COUNT_OFFSET,
                            &counters->packet_count) != XST_SUCCESS) {
        return XST_FAILURE;
    }

    if (pl_capture_read_reg(PL_CAPTURE_REG_OVERFLOW_COUNT_OFFSET,
                            &counters->overflow_count) != XST_SUCCESS) {
        return XST_FAILURE;
    }

    if (pl_capture_read_reg(PL_CAPTURE_REG_BACKPRESSURE_COUNT_OFFSET,
                            &counters->backpressure_count) != XST_SUCCESS) {
        return XST_FAILURE;
    }

    return XST_SUCCESS;
}

int pl_capture_validate(const pl_capture_status_t *status,
                        u32 expected_len,
                        u32 expected_frame_id)
{
    if (pl_capture_status_ok_for_frame(status,
                                       expected_len,
                                       expected_frame_id) != 0) {
        return XST_SUCCESS;
    }

    return XST_FAILURE;
}

int pl_capture_validate_burst(const pl_capture_status_t *status,
                              u32 expected_frame_len,
                              u32 expected_frame_count,
                              u32 expected_frame_id)
{
    if (status == 0) {
        return XST_FAILURE;
    }

    if ((status->available == 0U) ||
        (status->error != 0U) ||
        (status->overflow_seen != 0U) ||
        (status->backpressure_seen != 0U) ||
        (status->tlast_seen == 0U) ||
        (status->burst_done == 0U) ||
        (status->burst_active != 0U)) {
        return XST_FAILURE;
    }

    if ((status->frame_len != expected_frame_len) ||
        (status->frame_count != expected_frame_count) ||
        (status->frame_id != expected_frame_id) ||
        (status->done_frame_id != expected_frame_id) ||
        (status->burst_packet_count != expected_frame_count) ||
        (status->burst_remaining != 0U)) {
        return XST_FAILURE;
    }

    return XST_SUCCESS;
}

int pl_capture_status_ok_for_frame(const pl_capture_status_t *status,
                                   u32 expected_len,
                                   u32 expected_frame_id)
{
    if (status == 0) {
        return 0;
    }

    if (status->available == 0U) {
        return 0;
    }

    if ((status->done == 0U) ||
        (status->error != 0U) ||
        (status->overflow_seen != 0U) ||
        (status->backpressure_seen != 0U) ||
        (status->tlast_seen == 0U)) {
        return 0;
    }

    if ((status->sample_count != expected_len) ||
        (status->done_frame_id != expected_frame_id)) {
        return 0;
    }

    return 1;
}

static int pl_capture_write_reg(u32 offset, u32 value)
{
#if PL_CAPTURE_CONTROL_AVAILABLE
    Xil_Out32((UINTPTR)PL_CAPTURE_CONTROL_BASEADDR + offset, value);
    return XST_SUCCESS;
#else
    (void)offset;
    (void)value;
    return XST_FAILURE;
#endif
}

static int pl_capture_write_control(u32 pulse_mask)
{
    return pl_capture_write_reg(PL_CAPTURE_REG_CONTROL_OFFSET,
                                control_hold_mask | pulse_mask);
}

static void pl_capture_reset_delay(void)
{
    volatile u32 i;

    for (i = 0U; i < 1000U; i++) {
    }
}

static int pl_capture_read_reg(u32 offset, u32 *value)
{
    if (value == 0) {
        return XST_FAILURE;
    }

#if PL_CAPTURE_CONTROL_AVAILABLE
    *value = Xil_In32((UINTPTR)PL_CAPTURE_CONTROL_BASEADDR + offset);
    return XST_SUCCESS;
#else
    (void)offset;
    *value = 0U;
    return XST_FAILURE;
#endif
}

static u8 pl_capture_bit_is_set(u32 value, u32 mask)
{
    return ((value & mask) != 0U) ? 1U : 0U;
}
