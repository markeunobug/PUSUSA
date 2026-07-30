#include "ad8370.h"
#include "device_protocol.h"
#include "dma_capture.h"
#include "lock_indicator.h"
#include "lo_control.h"
#include "platform.h"
#include "phase_noise_engine.h"
#include "realtime_if_fft_engine.h"
#include "rf_frontend.h"
#include "signal_processing.h"
#include "sweep_engine.h"

static int protocol_spectrum_provider(const device_control_config_t *config,
                                      spectrum_point_t *points,
                                      unsigned short max_points,
                                      unsigned short *out_point_count);
static int protocol_direct_if_fft_provider(spectrum_point_t *points,
                                           unsigned short max_points,
                                           unsigned short *out_point_count);
static int protocol_status_provider(device_status_t *status);
static int start_background_capture(void);
static int reset_background_capture(void);
static void release_background_capture(void);
static void resume_background_capture_if_idle(void);
static void reset_and_resume_background_capture_if_idle(void);
static void poll_background_capture(void);
static int foreground_capture_is_idle(void);
static int arm_background_capture_once(void);
static void enter_background_backoff(void);
static int protocol_sweep_point_callback(uint32_t freq_hz,
                                         float power_dbm,
                                         uint32_t total_points,
                                         uint32_t current_index,
                                         int done,
                                         void *context);
static int protocol_sweep_control_handler(unsigned char action, const device_control_config_t *config);
static int protocol_rf_frontend_handler(const device_rf_frontend_config_t *config);
static int protocol_realtime_if_fft_handler(realtime_if_fft_engine_action_t action, const realtime_if_fft_engine_config_t *config);
static int protocol_realtime_if_fft_trace_callback(const realtime_if_fft_trace_t *trace, const realtime_if_fft_engine_status_t *status, void *context);
static int protocol_realtime_if_fft_status_callback(const realtime_if_fft_engine_status_t *status, void *context);
static int protocol_phase_noise_handler(phase_noise_engine_action_t action,
                                        const phase_noise_config_t *config);
static int protocol_capture_stream_smoke_handler(
    u32 sample_count,
    dma_capture_stream_smoke_result_t *result);
static int protocol_capture_main_smoke_handler(
    u32 sample_count,
    dma_capture_stream_smoke_result_t *result);
static int protocol_capture_sg_smoke_handler(
    u32 samples_per_bd,
    u32 bd_count,
    dma_capture_sg_smoke_result_t *result);
static int protocol_capture_sg_ring_smoke_handler(
    u32 samples_per_bd,
    u32 bd_count,
    u32 target_bd_count,
    dma_capture_sg_smoke_result_t *result);

static int protocol_phase_noise_data_callback(const phase_noise_data_t *point,
                                              void *context);
static int protocol_phase_noise_status_callback(const phase_noise_status_t *status,
                                                void *context);

typedef struct {
    spectrum_point_t *points;
    unsigned short max_points;
    unsigned short point_count;
} protocol_sweep_stream_context_t;

typedef enum {
    BACKGROUND_CAPTURE_IDLE = 0,
    BACKGROUND_CAPTURE_ARMED,
    BACKGROUND_CAPTURE_BACKOFF,
    BACKGROUND_CAPTURE_SUSPENDED
} background_capture_state_t;

static unsigned int g_dma_start_count = 0U;
static unsigned int g_dma_error_count = 0U;
static unsigned int g_dma_error_bg_irq_count = 0U;
static unsigned int g_dma_error_bg_start_count = 0U;
static unsigned int g_dma_error_bg_reset_count = 0U;
static unsigned int g_dma_error_sweep_reset_count = 0U;
static unsigned int g_dma_error_direct_if_count = 0U;
static unsigned int g_dma_error_phase_noise_count = 0U;
static unsigned int g_dma_error_realtime_if_fft_count = 0U;
static unsigned int g_dma_error_capture_test_count = 0U;
static unsigned int g_frame_ready_count = 0U;
static unsigned int g_process_frame_count = 0U;
static background_capture_state_t g_background_capture_state =
    BACKGROUND_CAPTURE_IDLE;
static unsigned int g_background_capture_backoff_loops = 0U;
static sweep_engine_t g_sweep_engine;//扫描相关参数，包括扫描计划、扫频后结果
static phase_noise_engine_t g_phase_noise_engine;
static realtime_if_fft_engine_t g_realtime_if_fft_engine;
static protocol_sweep_stream_context_t g_sweep_stream_context;
static int g_last_sweep_error = 0;
static unsigned char g_background_dma_error_code = 0U;

#define NOTE_DMA_ERROR(counter) \
    do { \
        g_dma_error_count++; \
        (counter)++; \
    } while (0)

static unsigned int g_dma_error_bg_start_invalid_arg_count = 0U;
static unsigned int g_dma_error_bg_start_invalid_samples_count = 0U;
static unsigned int g_dma_error_bg_start_pl_abort_fail_count = 0U;
static unsigned int g_dma_error_bg_start_pl_clear_fail_count = 0U;
static unsigned int g_dma_error_bg_start_pl_config_fail_count = 0U;
static unsigned int g_dma_error_bg_start_submit_sg_fail_count = 0U;
static unsigned int g_dma_error_bg_start_simple_fail_count = 0U;
static unsigned int g_dma_error_bg_start_pl_start_fail_count = 0U;

static unsigned int g_dma_error_bg_start_fail_invalid_arg_count = 0U;
static unsigned int g_dma_error_bg_start_fail_invalid_samples_count = 0U;
static unsigned int g_dma_error_bg_start_fail_pl_abort_count = 0U;
static unsigned int g_dma_error_bg_start_fail_pl_clear_count = 0U;
static unsigned int g_dma_error_bg_start_fail_pl_config_count = 0U;
static unsigned int g_dma_error_bg_start_fail_submit_sg_count = 0U;
static unsigned int g_dma_error_bg_start_fail_simple_transfer_count = 0U;
static unsigned int g_dma_error_bg_start_fail_pl_start_count = 0U;
static void record_background_start_failure(unsigned int result_code)
{
    switch (result_code) {
    case DMA_CAPTURE_START_INVALID_ARG:
        g_dma_error_bg_start_fail_invalid_arg_count++;
        break;
    case DMA_CAPTURE_START_INVALID_SAMPLES:
        g_dma_error_bg_start_fail_invalid_samples_count++;
        break;
    case DMA_CAPTURE_START_PL_ABORT_FAIL:
        g_dma_error_bg_start_fail_pl_abort_count++;
        break;
    case DMA_CAPTURE_START_PL_CLEAR_FAIL:
        g_dma_error_bg_start_fail_pl_clear_count++;
        break;
    case DMA_CAPTURE_START_PL_CONFIG_FAIL:
        g_dma_error_bg_start_fail_pl_config_count++;
        break;
    case DMA_CAPTURE_START_SUBMIT_SG_FAIL:
        g_dma_error_bg_start_fail_submit_sg_count++;
        break;
    case DMA_CAPTURE_START_SIMPLE_TRANSFER_FAIL:
        g_dma_error_bg_start_fail_simple_transfer_count++;
        break;
    case DMA_CAPTURE_START_PL_START_FAIL:
        g_dma_error_bg_start_fail_pl_start_count++;
        break;
    default:
        break;
    }
}
static float g_direct_if_spectrum_dbfs[SPECTRUM_BINS];

#define BACKGROUND_DMA_ERR_RESET 0xD1U
#define BACKGROUND_DMA_ERR_START 0xD2U
#define BACKGROUND_DMA_ERR_RT_FFT_RESET 0xD3U
#define DIRECT_IF_FRAME_TIMEOUT_LOOPS 500000U
#define BACKGROUND_CAPTURE_BACKOFF_LOOPS 50000U

int main(void)
{
    int status;
    int pn_status;
    rbw_mode_t applied_rbw_mode = RBW_MODE_100K;

    init_platform();
    device_protocol_recover_uart_rx();

    status = ad8370_init();
    if (status != XST_SUCCESS) {
        cleanup_platform();
        return -1;
    }

    status = lock_indicator_init();
    if (status != XST_SUCCESS) {
        cleanup_platform();
        return -1;
    }
    lock_indicator_self_test();

    status = lo_control_init();
    if (status != XST_SUCCESS) {
        cleanup_platform();
        return -1;
    }


    status = rf_frontend_init();
    if (status != XST_SUCCESS) {
        cleanup_platform();
        return -1;
    }

    status = device_protocol_init();
    if (status != XST_SUCCESS) {
        cleanup_platform();
        return -1;
    }
    device_protocol_recover_uart_rx();

    signal_processing_init();
    signal_processing_set_if_hz((float)LO_CONTROL_IF2_HZ);

    status = sweep_engine_init(&g_sweep_engine);
    if (status != 0) {
        cleanup_platform();
        return -1;
    }

    status = phase_noise_engine_init(&g_phase_noise_engine);
    if (status != 0) {
        cleanup_platform();
        return -1;
    }
    phase_noise_engine_set_callbacks(&g_phase_noise_engine,
                                     protocol_phase_noise_data_callback,
                                     0,
                                     protocol_phase_noise_status_callback,
                                     0);

    status = realtime_if_fft_engine_init(&g_realtime_if_fft_engine);
    if (status != 0) { cleanup_platform(); return -1; }
    realtime_if_fft_engine_set_callbacks(&g_realtime_if_fft_engine,
                                         protocol_realtime_if_fft_trace_callback, 0,
                                         protocol_realtime_if_fft_status_callback, 0);

    status = dma_capture_init();
    if (status != XST_SUCCESS) {
        cleanup_platform();
        return -1;
    }

    device_protocol_set_spectrum_provider(protocol_spectrum_provider);//把这个函数指针注册给协议层
    device_protocol_set_status_provider(protocol_status_provider);//频谱状态配置
    device_protocol_set_sweep_control_handler(protocol_sweep_control_handler);
    device_protocol_set_rf_frontend_handler(protocol_rf_frontend_handler);
    device_protocol_set_phase_noise_handler(protocol_phase_noise_handler);
    device_protocol_set_realtime_if_fft_handler(protocol_realtime_if_fft_handler);
    device_protocol_set_capture_stream_smoke_handler(
        protocol_capture_stream_smoke_handler);
    device_protocol_set_capture_main_smoke_handler(
        protocol_capture_main_smoke_handler);
    device_protocol_set_capture_sg_smoke_handler(
        protocol_capture_sg_smoke_handler);
    device_protocol_set_capture_sg_ring_smoke_handler(
        protocol_capture_sg_ring_smoke_handler);

    (void)start_background_capture();

    while (1) {
        device_protocol_poll();

        if (realtime_if_fft_engine_is_active(&g_realtime_if_fft_engine) != 0) {
            (void)realtime_if_fft_engine_poll(&g_realtime_if_fft_engine);
            if (realtime_if_fft_engine_is_active(&g_realtime_if_fft_engine) == 0) {
                lock_indicator_toggle_activity();
                reset_and_resume_background_capture_if_idle();
            }
            continue;
        }

        if (phase_noise_engine_is_active(&g_phase_noise_engine) != 0) {
            pn_status = phase_noise_engine_poll(&g_phase_noise_engine);
            if ((pn_status != 0) ||
                (phase_noise_engine_is_active(&g_phase_noise_engine) == 0)) {
                lock_indicator_toggle_activity();
                reset_and_resume_background_capture_if_idle();
                applied_rbw_mode = (rbw_mode_t)0xFFU;
            }
            continue;
        }

        if (sweep_engine_is_active(&g_sweep_engine) != 0) {
            g_last_sweep_error = sweep_engine_poll(&g_sweep_engine);
            if (g_last_sweep_error != 0) {
                sweep_engine_set_point_callback(&g_sweep_engine, 0, 0);
                reset_and_resume_background_capture_if_idle();
            } else if (sweep_engine_is_active(&g_sweep_engine) == 0) {
                sweep_engine_set_point_callback(&g_sweep_engine, 0, 0);
                lock_indicator_toggle_activity();
                reset_and_resume_background_capture_if_idle();
                applied_rbw_mode = (rbw_mode_t)0xFFU;
            }
            continue;
        }

        {
            const device_control_config_t *config = device_protocol_get_config();
            rbw_mode_t requested_mode = (rbw_mode_t)config->bandwidth.rbw_mode;

            switch (requested_mode) {
            case RBW_MODE_10K:
            case RBW_MODE_30K:
            case RBW_MODE_100K:
            case RBW_MODE_300K:
            case RBW_MODE_1M:
            case RBW_MODE_1K:
                break;
            default:
                requested_mode = RBW_MODE_100K;
                break;
            }

            if (requested_mode != applied_rbw_mode) {
                signal_processing_apply_rbw_mode(requested_mode);
                applied_rbw_mode = requested_mode;
            }
        }

        poll_background_capture();
    }

    dma_capture_shutdown();
    cleanup_platform();
    return 0;
}

static int start_background_capture(void)
{
    dma_capture_start_diag_t start_diag;

    if (g_background_capture_state == BACKGROUND_CAPTURE_ARMED) {
        return XST_SUCCESS;
    }

    if (g_background_capture_state == BACKGROUND_CAPTURE_SUSPENDED) {
        return XST_SUCCESS;
    }

    if (g_background_capture_state == BACKGROUND_CAPTURE_BACKOFF) {
        return XST_FAILURE;
    }

    if (arm_background_capture_once() == XST_SUCCESS) {
        return XST_SUCCESS;
    }

    dma_capture_get_start_diag(&start_diag);
    if (start_diag.result_code == DMA_CAPTURE_START_SUBMIT_SG_FAIL) {
        if (dma_capture_reset() != XST_SUCCESS) {
            NOTE_DMA_ERROR(g_dma_error_bg_reset_count);
            g_background_dma_error_code = BACKGROUND_DMA_ERR_RESET;
            enter_background_backoff();
            return XST_FAILURE;
        }

        if (arm_background_capture_once() == XST_SUCCESS) {
            return XST_SUCCESS;
        }
    }

    enter_background_backoff();
    return XST_FAILURE;
}

static int arm_background_capture_once(void)
{
    dma_capture_start_diag_t start_diag;

    if (dma_capture_start(TRANSFER_LENGTH) != XST_SUCCESS) {
        dma_capture_get_start_diag(&start_diag);
        record_background_start_failure(start_diag.result_code);
        NOTE_DMA_ERROR(g_dma_error_bg_start_count);
        g_background_capture_state = BACKGROUND_CAPTURE_IDLE;
        g_background_dma_error_code = BACKGROUND_DMA_ERR_START;
        return XST_FAILURE;
    }

    g_dma_start_count++;
    g_background_capture_state = BACKGROUND_CAPTURE_ARMED;
    g_background_capture_backoff_loops = 0U;
    g_background_dma_error_code = 0U;
    return XST_SUCCESS;
}

static int reset_background_capture(void)
{
    release_background_capture();

    if (dma_capture_reset() != XST_SUCCESS) {
        NOTE_DMA_ERROR(g_dma_error_bg_reset_count);
        g_background_dma_error_code = BACKGROUND_DMA_ERR_RESET;
        enter_background_backoff();
        return XST_FAILURE;
    }

    g_background_capture_state = BACKGROUND_CAPTURE_IDLE;
    g_background_capture_backoff_loops = 0U;
    return start_background_capture();
}

static void release_background_capture(void)
{
    g_background_capture_state = BACKGROUND_CAPTURE_SUSPENDED;
    g_background_capture_backoff_loops = 0U;
}

static void resume_background_capture_if_idle(void)
{
    if (foreground_capture_is_idle() != 0) {
        if (g_background_capture_state == BACKGROUND_CAPTURE_SUSPENDED) {
            g_background_capture_state = BACKGROUND_CAPTURE_IDLE;
        }
        (void)start_background_capture();
    }
}

static void reset_and_resume_background_capture_if_idle(void)
{
    if (foreground_capture_is_idle() != 0) {
        (void)reset_background_capture();
    }
}

static void poll_background_capture(void)
{
    if (foreground_capture_is_idle() == 0) {
        return;
    }

    if (g_background_capture_state == BACKGROUND_CAPTURE_SUSPENDED) {
        g_background_capture_state = BACKGROUND_CAPTURE_IDLE;
    }

    if (dma_capture_take_error() != 0) {
        NOTE_DMA_ERROR(g_dma_error_bg_irq_count);
        (void)reset_background_capture();
        return;
    }

    if (dma_capture_frame_ready() != 0) {
        g_background_capture_state = BACKGROUND_CAPTURE_IDLE;
        g_frame_ready_count++;
        signal_processing_process_frame(dma_capture_get_rx_buffer());
        g_process_frame_count++;
        (void)reset_background_capture();
        return;
    }

    if (g_background_capture_state == BACKGROUND_CAPTURE_BACKOFF) {
        if (g_background_capture_backoff_loops > 0U) {
            g_background_capture_backoff_loops--;
            return;
        }
        g_background_capture_state = BACKGROUND_CAPTURE_IDLE;
    }

    if (g_background_capture_state == BACKGROUND_CAPTURE_IDLE) {
        (void)start_background_capture();
    }
}

static int foreground_capture_is_idle(void)
{
    if (sweep_engine_is_active(&g_sweep_engine) != 0) {
        return 0;
    }

    if (phase_noise_engine_is_active(&g_phase_noise_engine) != 0) { return 0; }
    if (realtime_if_fft_engine_is_active(&g_realtime_if_fft_engine) != 0) { return 0; }
    return 1;
}

static void enter_background_backoff(void)
{
    g_background_capture_state = BACKGROUND_CAPTURE_BACKOFF;
    g_background_capture_backoff_loops = BACKGROUND_CAPTURE_BACKOFF_LOOPS;
}

static int protocol_spectrum_provider(const device_control_config_t *config,
                                      spectrum_point_t *points,
                                      unsigned short max_points,
                                      unsigned short *out_point_count)
{
    if ((config == 0) || (points == 0) || (out_point_count == 0)) {
        return -1;
    }

    if ((phase_noise_engine_is_active(&g_phase_noise_engine) != 0) ||
        (realtime_if_fft_engine_is_active(&g_realtime_if_fft_engine) != 0)) { return -1; }

    {
        const rf_frontend_state_t *rf_state = rf_frontend_get_state();
        if ((rf_state != 0) && (rf_state->path_mode == RF_PATH_DIRECT_IF)) {
            return protocol_direct_if_fft_provider(points, max_points, out_point_count);
        }
    }

    if (config->rf_frontend.path_mode == (unsigned char)RF_PATH_DIRECT_IF) {
        return protocol_direct_if_fft_provider(points, max_points, out_point_count);
    }

    protocol_sweep_stream_context_t stream_context;

    stream_context.points = points;
    stream_context.max_points = max_points;
    stream_context.point_count = 0U;

    release_background_capture();
    if (dma_capture_reset() != XST_SUCCESS) {
        NOTE_DMA_ERROR(g_dma_error_sweep_reset_count);
        g_background_dma_error_code = BACKGROUND_DMA_ERR_RESET;
        reset_and_resume_background_capture_if_idle();
        return -1;
    }

    g_last_sweep_error = sweep_engine_prepare(&g_sweep_engine, config);	//扫频准备，根据扫频的起始与终止频率计算出中间需要扫描点
    if (g_last_sweep_error != 0) {
        reset_and_resume_background_capture_if_idle();
        return -1;
    }

    sweep_engine_set_point_callback(&g_sweep_engine,
                                    protocol_sweep_point_callback,
                                    &stream_context);

    g_last_sweep_error = sweep_engine_run_blocking(&g_sweep_engine);	//开始扫频，并计算各个频点功率
    sweep_engine_set_point_callback(&g_sweep_engine, 0, 0);
    if (g_last_sweep_error != 0) {
        reset_and_resume_background_capture_if_idle();
        return -1;
    }

    *out_point_count = stream_context.point_count;
    g_last_sweep_error = 0;
    lock_indicator_toggle_activity();
    reset_and_resume_background_capture_if_idle();
    return 0;
}

static int protocol_direct_if_fft_provider(spectrum_point_t *points,
                                           unsigned short max_points,
                                           unsigned short *out_point_count)
{
    unsigned short bin_count = 0U;
    unsigned short i;
    unsigned int wait_count = 0U;
    int status = -1;

    if ((points == 0) || (out_point_count == 0) || (max_points == 0U)) {
        return -1;
    }

    *out_point_count = 0U;

    release_background_capture();
    if (dma_capture_reset() != XST_SUCCESS) {
        NOTE_DMA_ERROR(g_dma_error_direct_if_count);
        g_background_dma_error_code = BACKGROUND_DMA_ERR_RESET;
        reset_and_resume_background_capture_if_idle();
        return -1;
    }

    if (dma_capture_start(TRANSFER_LENGTH) != XST_SUCCESS) {
        NOTE_DMA_ERROR(g_dma_error_direct_if_count);
        g_background_dma_error_code = BACKGROUND_DMA_ERR_START;
        reset_and_resume_background_capture_if_idle();
        return -1;
    }
    g_dma_start_count++;
    g_background_dma_error_code = 0U;

    while (wait_count < DIRECT_IF_FRAME_TIMEOUT_LOOPS) {
        if (dma_capture_take_error() != 0) {
            NOTE_DMA_ERROR(g_dma_error_direct_if_count);
            break;
        }

        if (dma_capture_frame_ready() != 0) {
            g_frame_ready_count++;
            signal_processing_process_direct_if_fft_frame(dma_capture_get_rx_buffer());
            g_process_frame_count++;

            if (signal_processing_get_latest_spectrum(g_direct_if_spectrum_dbfs,
                                                      SPECTRUM_BINS,
                                                      &bin_count) != 0) {
                break;
            }

            if (bin_count > max_points) {
                bin_count = max_points;
            }

            status = 0;
            for (i = 0U; i < bin_count; i++) {
                uint32_t freq_hz =
                    (uint32_t)signal_processing_get_bin_frequency_hz(i);
                uint8_t done = (uint8_t)((i + 1U >= bin_count) ? 1U : 0U);

                points[i].freq_hz = freq_hz;
                points[i].amp_dbm = g_direct_if_spectrum_dbfs[i];

                if (device_protocol_stream_spectrum_point(freq_hz,
                                                          g_direct_if_spectrum_dbfs[i],
                                                          bin_count,
                                                          i,
                                                          done) != 0) {
                    status = -1;
                    break;
                }
            }

            *out_point_count = (status == 0) ? bin_count : i;
            break;
        }

        wait_count++;
    }

    if (status == 0) {
        lock_indicator_toggle_activity();
    } else if (wait_count >= DIRECT_IF_FRAME_TIMEOUT_LOOPS) {
        NOTE_DMA_ERROR(g_dma_error_direct_if_count);
    }

    reset_and_resume_background_capture_if_idle();
    return status;
}

static int protocol_sweep_point_callback(uint32_t freq_hz,
                                         float power_dbm,
                                         uint32_t total_points,
                                         uint32_t current_index,
                                         int done,
                                         void *context)
{
    protocol_sweep_stream_context_t *stream_context =
        (protocol_sweep_stream_context_t *)context;

    if ((stream_context != 0) && (stream_context->points != 0) && (stream_context->max_points > 0U)) {
        if (stream_context->point_count >= stream_context->max_points) {
            return -1;
        }

        stream_context->points[stream_context->point_count].freq_hz = freq_hz;
        stream_context->points[stream_context->point_count].amp_dbm = power_dbm;
        stream_context->point_count++;
    }

    return device_protocol_stream_spectrum_point(
        freq_hz,
        power_dbm,
        (uint16_t)total_points,
        (uint16_t)current_index,
        (uint8_t)done);
}

static int protocol_sweep_control_handler(unsigned char action, const device_control_config_t *config)
{
    if (action == DEVICE_PROTOCOL_SWEEP_STOP) {
        int was_active;

        if (phase_noise_engine_is_active(&g_phase_noise_engine) != 0) {
            return -1;
        }

        was_active = sweep_engine_is_active(&g_sweep_engine);
        sweep_engine_stop(&g_sweep_engine);
        if (was_active == 0) {
            resume_background_capture_if_idle();
        }
        return 0;
    }

    if (action != DEVICE_PROTOCOL_SWEEP_START) {
        return -1;
    }

    if ((phase_noise_engine_is_active(&g_phase_noise_engine) != 0) ||
        (realtime_if_fft_engine_is_active(&g_realtime_if_fft_engine) != 0)) { return -1; }

    g_sweep_stream_context.points = 0;
    g_sweep_stream_context.max_points = 0U;
    g_sweep_stream_context.point_count = 0U;

    release_background_capture();
    if (dma_capture_reset() != XST_SUCCESS) {
        NOTE_DMA_ERROR(g_dma_error_sweep_reset_count);
        g_background_dma_error_code = BACKGROUND_DMA_ERR_RESET;
        return -1;
    }

    sweep_engine_set_point_callback(&g_sweep_engine,
                                    protocol_sweep_point_callback,
                                    &g_sweep_stream_context);

    g_last_sweep_error = sweep_engine_start(&g_sweep_engine, config);
    if (g_last_sweep_error != 0) {
        sweep_engine_set_point_callback(&g_sweep_engine, 0, 0);
        reset_and_resume_background_capture_if_idle();
        return -1;
    }

    return 0;
}

static int protocol_status_provider(device_status_t *status)
{
    dma_capture_diag_t dma_diag;
    dma_capture_start_diag_t start_diag;

    if (status == 0) {
        return -1;
    }

    dma_capture_get_diag(&dma_diag);
    dma_capture_get_start_diag(&start_diag);

    status->temperature_c = 32.5;
    status->battery_percent = signal_processing_has_latest_spectrum() ? 90U : 80U;
    /* Sweep errors are exported through the 1-byte status code so the host
     * can quickly tell whether the failure happened in LO control, frame wait,
     * or power measurement without opening a debugger.
     */
    if (g_last_sweep_error != 0) {
        status->error_code =
            (unsigned char)((g_last_sweep_error < 0) ?
                            (-g_last_sweep_error) : g_last_sweep_error);
    } else if ((g_background_dma_error_code != 0U) &&
               (signal_processing_has_latest_spectrum() == 0)) {
        status->error_code = g_background_dma_error_code;
    } else {
        status->error_code = 0U;
    }
    status->dma_start_count = g_dma_start_count;
    status->dma_error_count = g_dma_error_count;
    status->dma_error_bg_irq_count = g_dma_error_bg_irq_count;
    status->dma_error_bg_start_count = g_dma_error_bg_start_count;
    status->dma_error_bg_reset_count = g_dma_error_bg_reset_count;
    status->dma_error_sweep_reset_count = g_dma_error_sweep_reset_count;
    status->dma_error_direct_if_count = g_dma_error_direct_if_count;
    status->dma_error_phase_noise_count = g_dma_error_phase_noise_count;
    status->dma_error_capture_test_count = g_dma_error_capture_test_count;
    status->dma_start_last_result_code = start_diag.result_code;
    status->dma_start_last_transfer_bytes = start_diag.transfer_bytes;
    status->dma_start_last_capture_samples = start_diag.capture_samples;
    status->dma_start_last_s2mm_dmasr = start_diag.s2mm_dmasr;
    status->dma_start_last_sg_ring_ready = start_diag.sg_ring_ready;
    status->dma_start_last_sg_active_bd_count = start_diag.sg_active_bd_count;
    status->dma_start_last_sg_free_bd_count = start_diag.sg_free_bd_count;
    status->dma_start_fail_invalid_arg_count = g_dma_error_bg_start_fail_invalid_arg_count;
    status->dma_start_fail_invalid_samples_count = g_dma_error_bg_start_fail_invalid_samples_count;
    status->dma_start_fail_pl_abort_count = g_dma_error_bg_start_fail_pl_abort_count;
    status->dma_start_fail_pl_clear_count = g_dma_error_bg_start_fail_pl_clear_count;
    status->dma_start_fail_pl_config_count = g_dma_error_bg_start_fail_pl_config_count;
    status->dma_start_fail_submit_sg_count = g_dma_error_bg_start_fail_submit_sg_count;
    status->dma_start_fail_simple_transfer_count = g_dma_error_bg_start_fail_simple_transfer_count;
    status->dma_start_fail_pl_start_count = g_dma_error_bg_start_fail_pl_start_count;
    status->frame_ready_count = g_frame_ready_count;
    status->process_frame_count = g_process_frame_count;
    status->spectrum_valid = (unsigned char)(signal_processing_has_latest_spectrum() ? 1U : 0U);
    status->s2mm_dmacr = dma_diag.s2mm_dmacr;
    status->s2mm_dmasr = dma_diag.s2mm_dmasr;
    status->dma_irq_count = dma_diag.irq_count;
    status->dma_last_irq_status = dma_diag.last_irq_status;
    status->uart_rx_bad_frame_count = 0U;
    status->uart_rx_crc_error_count = 0U;
    status->uart_rx_overrun_count = 0U;
    status->uart_rx_resync_count = 0U;
    return 0;
}
static int protocol_phase_noise_handler(phase_noise_engine_action_t action, const phase_noise_config_t *config)
{
    phase_noise_status_t status;
    switch (action) {
    case PHASE_NOISE_ENGINE_ACTION_CONFIGURE: return phase_noise_engine_configure(&g_phase_noise_engine, config);
    case PHASE_NOISE_ENGINE_ACTION_START:
        if (realtime_if_fft_engine_is_active(&g_realtime_if_fft_engine) != 0) return -1;
        if (sweep_engine_is_active(&g_sweep_engine) != 0) { sweep_engine_stop(&g_sweep_engine); g_last_sweep_error=sweep_engine_poll(&g_sweep_engine); sweep_engine_set_point_callback(&g_sweep_engine,0,0); if(g_last_sweep_error!=0 || sweep_engine_is_active(&g_sweep_engine)!=0) return -1; }
        release_background_capture();
        if (dma_capture_reset()!=XST_SUCCESS) { NOTE_DMA_ERROR(g_dma_error_phase_noise_count); g_background_dma_error_code=BACKGROUND_DMA_ERR_RESET; reset_and_resume_background_capture_if_idle(); return -1; }
        if (phase_noise_engine_start(&g_phase_noise_engine)!=0) { reset_and_resume_background_capture_if_idle(); return -1; }
        return 0;
    case PHASE_NOISE_ENGINE_ACTION_STOP: phase_noise_engine_stop(&g_phase_noise_engine); if(phase_noise_engine_is_active(&g_phase_noise_engine)==0){phase_noise_engine_get_status(&g_phase_noise_engine,&status);(void)device_protocol_send_phase_noise_status(&status);reset_and_resume_background_capture_if_idle();} return 0;
    case PHASE_NOISE_ENGINE_ACTION_GET_STATUS: phase_noise_engine_get_status(&g_phase_noise_engine,&status); return device_protocol_send_phase_noise_status(&status);
    default: return -1;
    }
}

static int protocol_realtime_if_fft_trace_callback(const realtime_if_fft_trace_t *trace, const realtime_if_fft_engine_status_t *status, void *context)
{ (void)context; return device_protocol_stream_realtime_if_fft_trace(trace, status); }
static int protocol_realtime_if_fft_status_callback(const realtime_if_fft_engine_status_t *status, void *context)
{ (void)context; return device_protocol_send_realtime_if_fft_status(status); }
static int protocol_realtime_if_fft_handler(realtime_if_fft_engine_action_t action, const realtime_if_fft_engine_config_t *config)
{
    realtime_if_fft_engine_status_t status;
    int start_status;
    const rf_frontend_state_t *rf_state;

    switch (action) {
    case REALTIME_IF_FFT_ENGINE_ACTION_CONFIGURE:
        return realtime_if_fft_engine_configure(&g_realtime_if_fft_engine, config);

    case REALTIME_IF_FFT_ENGINE_ACTION_START:
        /* RT FFT is defined only for the RF mixer chain; do not silently
         * retarget the RF switch when a Direct-IF user session is active. */
        rf_state = rf_frontend_get_state();
        if ((rf_state == 0) || (rf_state->path_mode != RF_PATH_MIXER_CHAIN)) {
            return -1;
        }
        if (phase_noise_engine_is_active(&g_phase_noise_engine) != 0) return -1;
        if (sweep_engine_is_active(&g_sweep_engine) != 0) {
            sweep_engine_stop(&g_sweep_engine);
            g_last_sweep_error = sweep_engine_poll(&g_sweep_engine);
            sweep_engine_set_point_callback(&g_sweep_engine, 0, 0);
            if ((g_last_sweep_error != 0) ||
                (sweep_engine_is_active(&g_sweep_engine) != 0)) return -1;
        }
        release_background_capture();
        if (dma_capture_reset() != XST_SUCCESS) {
            NOTE_DMA_ERROR(g_dma_error_realtime_if_fft_count);
            g_background_dma_error_code = BACKGROUND_DMA_ERR_RT_FFT_RESET;
            reset_and_resume_background_capture_if_idle();
            return -1;
        }
        start_status = realtime_if_fft_engine_start(&g_realtime_if_fft_engine);
        if (start_status != 0) {
            /* No RT FFT owner was acquired; give the background producer back
             * its DMA path even for e.g. an unconfigured START command. */
            reset_and_resume_background_capture_if_idle();
        }
        return start_status;

    case REALTIME_IF_FFT_ENGINE_ACTION_STOP:
        /* Non-blocking: the main loop polls the state machine, releases DMA,
         * emits final idle status, then restores the background capture. */
        realtime_if_fft_engine_stop(&g_realtime_if_fft_engine);
        return 0;

    case REALTIME_IF_FFT_ENGINE_ACTION_GET_STATUS:
        realtime_if_fft_engine_get_status(&g_realtime_if_fft_engine, &status);
        return device_protocol_send_realtime_if_fft_status(&status);

    default:
        return -1;
    }
}
static int protocol_capture_stream_smoke_handler(
    u32 sample_count,
    dma_capture_stream_smoke_result_t *result)
{
    int status;

    if ((phase_noise_engine_is_active(&g_phase_noise_engine) != 0) ||
        (realtime_if_fft_engine_is_active(&g_realtime_if_fft_engine) != 0) ||
        (sweep_engine_is_active(&g_sweep_engine) != 0)) {
        if (result != 0) {
            result->version = DMA_CAPTURE_STREAM_SMOKE_RESULT_VERSION;
            result->result_code = DMA_CAPTURE_STREAM_SMOKE_BUSY;
            result->requested_samples = sample_count;
            result->transfer_bytes = sample_count * (u32)sizeof(u16);
        }
        return XST_FAILURE;
    }

    release_background_capture();
    status = dma_capture_continuous_smoke_test(sample_count, result);
    reset_and_resume_background_capture_if_idle();

    if (status != XST_SUCCESS) {
        NOTE_DMA_ERROR(g_dma_error_capture_test_count);
    }

    return status;
}

static int protocol_capture_main_smoke_handler(
    u32 sample_count,
    dma_capture_stream_smoke_result_t *result)
{
    int status;

    if ((phase_noise_engine_is_active(&g_phase_noise_engine) != 0) ||
        (realtime_if_fft_engine_is_active(&g_realtime_if_fft_engine) != 0) ||
        (sweep_engine_is_active(&g_sweep_engine) != 0)) {
        if (result != 0) {
            result->version = DMA_CAPTURE_STREAM_SMOKE_RESULT_VERSION;
            result->result_code = DMA_CAPTURE_STREAM_SMOKE_BUSY;
            result->requested_samples = sample_count;
            result->transfer_bytes = sample_count * (u32)sizeof(u16);
        }
        return XST_FAILURE;
    }

    release_background_capture();
    status = dma_capture_main_path_smoke_test(sample_count, result);
    reset_and_resume_background_capture_if_idle();

    if (status != XST_SUCCESS) {
        NOTE_DMA_ERROR(g_dma_error_capture_test_count);
    }

    return status;
}

static int protocol_capture_sg_smoke_handler(
    u32 samples_per_bd,
    u32 bd_count,
    dma_capture_sg_smoke_result_t *result)
{
    int status;

    if ((phase_noise_engine_is_active(&g_phase_noise_engine) != 0) ||
        (realtime_if_fft_engine_is_active(&g_realtime_if_fft_engine) != 0) ||
        (sweep_engine_is_active(&g_sweep_engine) != 0)) {
        if (result != 0) {
            result->version = DMA_CAPTURE_SG_SMOKE_RESULT_VERSION;
            result->result_code = DMA_CAPTURE_SG_SMOKE_BUSY;
            result->samples_per_bd = samples_per_bd;
            result->bd_count = bd_count;
            result->requested_samples = samples_per_bd * bd_count;
            result->requested_bytes = result->requested_samples * (u32)sizeof(u16);
        }
        return XST_FAILURE;
    }

    release_background_capture();
    status = dma_capture_sg_smoke_test(samples_per_bd, bd_count, result);
    reset_and_resume_background_capture_if_idle();

    if (status != XST_SUCCESS) {
        NOTE_DMA_ERROR(g_dma_error_capture_test_count);
    }

    return status;
}

static int protocol_capture_sg_ring_smoke_handler(
    u32 samples_per_bd,
    u32 bd_count,
    u32 target_bd_count,
    dma_capture_sg_smoke_result_t *result)
{
    int status;

    if ((phase_noise_engine_is_active(&g_phase_noise_engine) != 0) ||
        (realtime_if_fft_engine_is_active(&g_realtime_if_fft_engine) != 0) ||
        (sweep_engine_is_active(&g_sweep_engine) != 0)) {
        if (result != 0) {
            result->version = DMA_CAPTURE_SG_SMOKE_RESULT_VERSION;
            result->result_code = DMA_CAPTURE_SG_SMOKE_BUSY;
            result->samples_per_bd = samples_per_bd;
            result->bd_count = bd_count;
            result->requested_samples = samples_per_bd * target_bd_count;
            result->requested_bytes = result->requested_samples * (u32)sizeof(u16);
        }
        return XST_FAILURE;
    }

    release_background_capture();
    status = dma_capture_sg_ring_smoke_test(samples_per_bd,
                                            bd_count,
                                            target_bd_count,
                                            result);
    reset_and_resume_background_capture_if_idle();

    if (status != XST_SUCCESS) {
        NOTE_DMA_ERROR(g_dma_error_capture_test_count);
    }

    return status;
}

static int protocol_phase_noise_data_callback(const phase_noise_data_t *point,
                                              void *context)
{
    (void)context;
    return device_protocol_stream_phase_noise_point(point);
}

static int protocol_phase_noise_status_callback(const phase_noise_status_t *status,
                                                void *context)
{
    (void)context;
    return device_protocol_send_phase_noise_status(status);
}
static int protocol_rf_frontend_handler(const device_rf_frontend_config_t *config)
{
    rf_frontend_state_t state;

    if (config == 0) {
        return XST_FAILURE;
    }

    /* The RT engine fixes LO1 and interprets all bins through the mixer
     * chain.  Do not permit a UART RF-path/attenuator/LNA update to mutate
     * that context while it owns DMA. */
    if (realtime_if_fft_engine_is_active(&g_realtime_if_fft_engine) != 0) {
        return XST_FAILURE;
    }

    state.lna_mode = (rf_lna_mode_t)config->lna_mode;
    state.path_mode = (rf_path_mode_t)config->path_mode;
    state.atten_code = config->atten_code;
    state.atten_db = (float)config->atten_code * 0.25f;
    state.applied_gpio = 0U;
    state.last_error = RF_FRONTEND_ERR_NONE;

    return rf_frontend_apply(&state);
}
