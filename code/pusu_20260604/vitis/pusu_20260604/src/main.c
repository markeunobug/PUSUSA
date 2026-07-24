#include "ad8370.h"
#include "device_protocol.h"
#include "dma_capture.h"
#include "lock_indicator.h"
#include "lo_control.h"
#include "platform.h"
#include "phase_noise_engine.h"
#include "pusu_pl_dsp_control.h"
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
static int protocol_sweep_point_callback(uint32_t freq_hz,
                                         float power_dbm,
                                         uint32_t total_points,
                                         uint32_t current_index,
                                         int done,
                                         void *context);
static int protocol_sweep_control_handler(unsigned char action, const device_control_config_t *config);
static int protocol_rf_frontend_handler(const device_rf_frontend_config_t *config);
static int protocol_phase_noise_handler(phase_noise_engine_action_t action,
                                        const phase_noise_config_t *config);
static int protocol_phase_noise_data_callback(const phase_noise_data_t *point,
                                              void *context);
static int protocol_phase_noise_status_callback(const phase_noise_status_t *status,
                                                void *context);

typedef struct {
    spectrum_point_t *points;
    unsigned short max_points;
    unsigned short point_count;
} protocol_sweep_stream_context_t;

static unsigned int g_dma_start_count = 0U;
static unsigned int g_dma_error_count = 0U;
static unsigned int g_frame_ready_count = 0U;
static unsigned int g_process_frame_count = 0U;
static int g_background_dma_armed = 0;
static sweep_engine_t g_sweep_engine;//扫描相关参数，包括扫描计划、扫频后结果
static phase_noise_engine_t g_phase_noise_engine;
static protocol_sweep_stream_context_t g_sweep_stream_context;
static int g_last_sweep_error = 0;
static unsigned char g_background_dma_error_code = 0U;
static float g_direct_if_spectrum_dbfs[SPECTRUM_BINS];

#define BACKGROUND_DMA_ERR_RESET 0xD1U
#define BACKGROUND_DMA_ERR_START 0xD2U
#define DIRECT_IF_FRAME_TIMEOUT_LOOPS 500000U

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
    status = pusu_pl_dsp_init();
    if (status != XST_SUCCESS) {
        cleanup_platform();
        return -1;
    }

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

    (void)start_background_capture();

    while (1) {
        device_protocol_poll();

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

        resume_background_capture_if_idle();

        if (dma_capture_take_error() != 0) {
            g_dma_error_count++;
            (void)reset_background_capture();
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
                release_background_capture();
                if (dma_capture_reset() != XST_SUCCESS) {
                    g_dma_error_count++;
                    g_background_dma_error_code = BACKGROUND_DMA_ERR_RESET;
                    continue;
                }
                if (pusu_pl_dsp_configure_rbw(requested_mode) != XST_SUCCESS) {
                    g_background_dma_error_code = (unsigned char)(-SWEEP_ENGINE_ERR_PL_DSP_CONFIG);
                    continue;
                }
                signal_processing_apply_rbw_mode(requested_mode);
                applied_rbw_mode = requested_mode;
            }
        }

        if (dma_capture_frame_ready() != 0) {
            g_background_dma_armed = 0;
            g_frame_ready_count++;
            signal_processing_process_frame(dma_capture_get_rx_buffer());
            g_process_frame_count++;
            (void)start_background_capture();
        }
    }

    dma_capture_shutdown();
    cleanup_platform();
    return 0;
}

static int start_background_capture(void)
{
    if (g_background_dma_armed != 0) {
        return XST_SUCCESS;
    }

    if (dma_capture_start(TRANSFER_LENGTH) != XST_SUCCESS) {
        g_dma_error_count++;
        g_background_dma_armed = 0;
        g_background_dma_error_code = BACKGROUND_DMA_ERR_START;
        return XST_FAILURE;
    }

    g_dma_start_count++;
    g_background_dma_armed = 1;
    g_background_dma_error_code = 0U;
    return XST_SUCCESS;
}

static int reset_background_capture(void)
{
    release_background_capture();

    if (dma_capture_reset() != XST_SUCCESS) {
        g_dma_error_count++;
        g_background_dma_error_code = BACKGROUND_DMA_ERR_RESET;
        return XST_FAILURE;
    }

    return start_background_capture();
}

static void release_background_capture(void)
{
    g_background_dma_armed = 0;
}

static void resume_background_capture_if_idle(void)
{
    if (sweep_engine_is_active(&g_sweep_engine) == 0) {
        (void)start_background_capture();
    }
}

static void reset_and_resume_background_capture_if_idle(void)
{
    if (sweep_engine_is_active(&g_sweep_engine) == 0) {
        (void)reset_background_capture();
    }
}

static int protocol_spectrum_provider(const device_control_config_t *config,
                                      spectrum_point_t *points,
                                      unsigned short max_points,
                                      unsigned short *out_point_count)
{
    if ((config == 0) || (points == 0) || (out_point_count == 0)) {
        return -1;
    }

    if (phase_noise_engine_is_active(&g_phase_noise_engine) != 0) {
        return -1;
    }

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
        g_dma_error_count++;
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
        g_dma_error_count++;
        g_background_dma_error_code = BACKGROUND_DMA_ERR_RESET;
        reset_and_resume_background_capture_if_idle();
        return -1;
    }

    if (dma_capture_start(TRANSFER_LENGTH) != XST_SUCCESS) {
        g_dma_error_count++;
        g_background_dma_error_code = BACKGROUND_DMA_ERR_START;
        reset_and_resume_background_capture_if_idle();
        return -1;
    }
    g_dma_start_count++;
    g_background_dma_error_code = 0U;

    while (wait_count < DIRECT_IF_FRAME_TIMEOUT_LOOPS) {
        if (dma_capture_take_error() != 0) {
            g_dma_error_count++;
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
        g_dma_error_count++;
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

    if (phase_noise_engine_is_active(&g_phase_noise_engine) != 0) {
        return -1;
    }

    g_sweep_stream_context.points = 0;
    g_sweep_stream_context.max_points = 0U;
    g_sweep_stream_context.point_count = 0U;

    release_background_capture();
    if (dma_capture_reset() != XST_SUCCESS) {
        g_dma_error_count++;
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
    pusu_pl_dsp_status_t pl_status;

    if (status == 0) {
        return -1;
    }

    dma_capture_get_diag(&dma_diag);
    (void)pusu_pl_dsp_read_status(&pl_status);

    status->temperature_c = 32.5;
    status->battery_percent = signal_processing_has_latest_spectrum() ? 90U : 80U;
    /* Sweep errors are exported through the 1-byte status code so the host
     * can quickly tell whether the failure happened in LO control, frame wait,
     * or power measurement without opening a debugger.
     */
    status->error_code = (g_last_sweep_error != 0)
        ? (unsigned char)((g_last_sweep_error < 0) ? (-g_last_sweep_error) : g_last_sweep_error)
        : g_background_dma_error_code;
    status->dma_start_count = g_dma_start_count;
    status->dma_error_count = g_dma_error_count;
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
    status->pl_available = pl_status.available;
    status->pl_mode_value = pl_status.pl_mode_value;
    status->pl_output_select = pl_status.output_select;
    status->pl_reserved = 0U;
    status->pl_status = pl_status.status;
    status->pl_sample_rate_hz = pl_status.sample_rate_hz;
    status->pl_decimation = pl_status.decimation_ratio;
    status->pl_frame_words = pl_status.frame_words;
    status->pl_data_format = pl_status.data_format;
    status->pl_version = pl_status.version;
    status->pl_input_sample_count = pl_status.input_sample_count;
    status->pl_output_sample_count = pl_status.output_sample_count;
    status->pl_output_drop_count = pl_status.output_drop_count;
    status->pl_error_code = pl_status.error_code;
    return 0;
}
static int protocol_phase_noise_handler(phase_noise_engine_action_t action,
                                        const phase_noise_config_t *config)
{
    phase_noise_status_t status;

    switch (action) {
    case PHASE_NOISE_ENGINE_ACTION_CONFIGURE:
        return phase_noise_engine_configure(&g_phase_noise_engine, config);

    case PHASE_NOISE_ENGINE_ACTION_START:
        if (sweep_engine_is_active(&g_sweep_engine) != 0) {
            return -1;
        }
        release_background_capture();
        if (dma_capture_reset() != XST_SUCCESS) {
            g_dma_error_count++;
            g_background_dma_error_code = BACKGROUND_DMA_ERR_RESET;
            reset_and_resume_background_capture_if_idle();
            return -1;
        }
        if (phase_noise_engine_start(&g_phase_noise_engine) != 0) {
            reset_and_resume_background_capture_if_idle();
            return -1;
        }
        return 0;

    case PHASE_NOISE_ENGINE_ACTION_STOP:
        phase_noise_engine_stop(&g_phase_noise_engine);
        if (phase_noise_engine_is_active(&g_phase_noise_engine) == 0) {
            phase_noise_engine_get_status(&g_phase_noise_engine, &status);
            (void)device_protocol_send_phase_noise_status(&status);
            reset_and_resume_background_capture_if_idle();
        }
        return 0;

    case PHASE_NOISE_ENGINE_ACTION_GET_STATUS:
        phase_noise_engine_get_status(&g_phase_noise_engine, &status);
        return device_protocol_send_phase_noise_status(&status);

    default:
        return -1;
    }
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

    state.lna_mode = (rf_lna_mode_t)config->lna_mode;
    state.path_mode = (rf_path_mode_t)config->path_mode;
    state.atten_code = config->atten_code;
    state.atten_db = (float)config->atten_code * 0.25f;
    state.applied_gpio = 0U;
    state.last_error = RF_FRONTEND_ERR_NONE;

    return rf_frontend_apply(&state);
}
