#include "../code/ad8370.h"
#include "../code/device_protocol.h"
#include "../code/dma_capture.h"
#include "../code/lock_indicator.h"
#include "../code/lo_control.h"
#include "../code/platform.h"
#include "../code/signal_processing.h"
#include "../code/sweep_engine.h"

static int protocol_spectrum_provider(const device_control_config_t *config,
                                      spectrum_point_t *points,
                                      unsigned short max_points,
                                      unsigned short *out_point_count);
static int protocol_status_provider(device_status_t *status);
static int protocol_sweep_point_callback(uint32_t freq_hz, float power_dbm, void *context);
static int protocol_sweep_control_handler(unsigned char action, const device_control_config_t *config);

typedef struct {
    spectrum_point_t *points;
    unsigned short max_points;
    unsigned short point_count;
} protocol_sweep_stream_context_t;

static unsigned int g_dma_start_count = 0U;
static unsigned int g_dma_error_count = 0U;
static unsigned int g_frame_ready_count = 0U;
static unsigned int g_process_frame_count = 0U;
static sweep_engine_t g_sweep_engine;//扫描相关参数，包括扫描计划、扫频后结果
static protocol_sweep_stream_context_t g_sweep_stream_context;
static int g_last_sweep_error = 0;

int main(void)
{
    int status;
    rbw_mode_t applied_rbw_mode = RBW_MODE_100K;

    init_platform();

    status = ad8370_init();
    if (status != XST_SUCCESS) {
        cleanup_platform();
        return -1;
    }
//    ad8370_set_gain_code(0x19U);//3dB
//    ad8370_set_gain_code(0x39U);//10dB
//    ad8370_set_gain_code(0x99U);//20dB

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

    status = device_protocol_init();
    if (status != XST_SUCCESS) {
        cleanup_platform();
        return -1;
    }

    signal_processing_init();
    signal_processing_set_if_hz((float)LO_CONTROL_IF2_HZ);

    status = sweep_engine_init(&g_sweep_engine);
    if (status != 0) {
        cleanup_platform();
        return -1;
    }

    status = dma_capture_init();
    if (status != XST_SUCCESS) {
        cleanup_platform();
        return -1;
    }

    status = dma_capture_start();
    if (status != XST_SUCCESS) {
        cleanup_platform();
        return -1;
    }
    g_dma_start_count++;

    device_protocol_set_spectrum_provider(protocol_spectrum_provider);//把这个函数指针注册给协议层
    device_protocol_set_status_provider(protocol_status_provider);//频谱状态配置
    device_protocol_set_sweep_control_handler(protocol_sweep_control_handler);

    while (1) {
        device_protocol_poll();

//            ad8370_set_gain_code(0x39U);//10dB

        if (sweep_engine_is_active(&g_sweep_engine) != 0) {
            g_last_sweep_error = sweep_engine_poll(&g_sweep_engine);
            if (g_last_sweep_error != 0) {
                sweep_engine_set_point_callback(&g_sweep_engine, 0, 0);
            }
            continue;
        }

        if (dma_capture_take_error() != 0) {
            g_dma_error_count++;
            (void)dma_capture_start();
            g_dma_start_count++;
            continue;
        }

        {
            const device_control_config_t *config = device_protocol_get_config();
            rbw_mode_t requested_mode = (rbw_mode_t)config->bandwidth.rbw_mode;

            if (requested_mode > RBW_MODE_1M) {
                requested_mode = RBW_MODE_100K;
            }

            if (requested_mode != applied_rbw_mode) {
                signal_processing_apply_rbw_mode(requested_mode);
                applied_rbw_mode = requested_mode;
            }
        }

        if (dma_capture_frame_ready() != 0) {
            g_frame_ready_count++;
            signal_processing_process_frame(dma_capture_get_rx_buffer());
            g_process_frame_count++;
            (void)dma_capture_start();
            g_dma_start_count++;
        }
    }

    dma_capture_shutdown();
    cleanup_platform();
    return 0;
}

static int protocol_spectrum_provider(const device_control_config_t *config,
                                      spectrum_point_t *points,
                                      unsigned short max_points,
                                      unsigned short *out_point_count)
{
    protocol_sweep_stream_context_t stream_context;

    if ((points == 0) || (out_point_count == 0)) {
        return -1;
    }

    stream_context.points = points;
    stream_context.max_points = max_points;
    stream_context.point_count = 0U;

    g_last_sweep_error = sweep_engine_prepare(&g_sweep_engine, config);	//扫频准备，根据扫频的起始与终止频率计算出中间需要扫描点
    if (g_last_sweep_error != 0) {
        return -1;
    }

    sweep_engine_set_point_callback(&g_sweep_engine,
                                    protocol_sweep_point_callback,
                                    &stream_context);

    g_last_sweep_error = sweep_engine_run_blocking(&g_sweep_engine);	//开始扫频，并计算各个频点功率
    sweep_engine_set_point_callback(&g_sweep_engine, 0, 0);
    if (g_last_sweep_error != 0) {
        return -1;
    }

    *out_point_count = stream_context.point_count;
    g_last_sweep_error = 0;
    return 0;
}

static int protocol_sweep_point_callback(uint32_t freq_hz, float power_dbm, void *context)
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

    return device_protocol_stream_spectrum_point(freq_hz, power_dbm);
}

static int protocol_sweep_control_handler(unsigned char action, const device_control_config_t *config)
{
    if (action == DEVICE_PROTOCOL_SWEEP_STOP) {
        sweep_engine_stop(&g_sweep_engine);
        return 0;
    }

    if (action != DEVICE_PROTOCOL_SWEEP_START) {
        return -1;
    }

    g_sweep_stream_context.points = 0;
    g_sweep_stream_context.max_points = 0U;
    g_sweep_stream_context.point_count = 0U;

    sweep_engine_set_point_callback(&g_sweep_engine,
                                    protocol_sweep_point_callback,
                                    &g_sweep_stream_context);

    g_last_sweep_error = sweep_engine_start(&g_sweep_engine, config);
    if (g_last_sweep_error != 0) {
        sweep_engine_set_point_callback(&g_sweep_engine, 0, 0);
        return -1;
    }

    return 0;
}

static int protocol_status_provider(device_status_t *status)
{
    dma_capture_diag_t dma_diag;

    if (status == 0) {
        return -1;
    }

    dma_capture_get_diag(&dma_diag);

    status->temperature_c = 32.5;
    status->battery_percent = signal_processing_has_latest_spectrum() ? 90U : 80U;
    /* Sweep errors are exported through the 1-byte status code so the host
     * can quickly tell whether the failure happened in LO control, frame wait,
     * or power measurement without opening a debugger.
     */
    status->error_code = (unsigned char)((g_last_sweep_error < 0) ? (-g_last_sweep_error) : g_last_sweep_error);
    status->dma_start_count = g_dma_start_count;
    status->dma_error_count = g_dma_error_count;
    status->frame_ready_count = g_frame_ready_count;
    status->process_frame_count = g_process_frame_count;
    status->spectrum_valid = (unsigned char)(signal_processing_has_latest_spectrum() ? 1U : 0U);
    status->s2mm_dmacr = dma_diag.s2mm_dmacr;
    status->s2mm_dmasr = dma_diag.s2mm_dmasr;
    status->dma_irq_count = dma_diag.irq_count;
    status->dma_last_irq_status = dma_diag.last_irq_status;
    return 0;
}

