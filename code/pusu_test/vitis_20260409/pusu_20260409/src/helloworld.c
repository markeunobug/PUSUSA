#include "platform.h"
#include "ad8370.h"
#include "device_protocol.h"
#include "dma_capture.h"
#include "signal_processing.h"

/*
 * First-pass amplitude conversion for host display:
 * latest_bins[] is dBFS from the FFT chain.
 * Assuming LTC2208 full-scale is 2.5 Vpp differential across 100 ohm,
 * a full-scale sine corresponds to about +8.93 dBm at the ADC input.
 *
 * This is ADC-input dBm only. Front-end gain/attenuation calibration
 * will be added later as a separate correction term.
 */
#define ADC_INPUT_FULL_SCALE_DBM   (8.93)

static int protocol_spectrum_provider(const device_control_config_t *config,
                                      spectrum_point_t *points,
                                      unsigned short max_points,
                                      unsigned short *out_point_count);
static int protocol_status_provider(device_status_t *status);

static unsigned int g_dma_start_count = 0U;
static unsigned int g_dma_error_count = 0U;
static unsigned int g_frame_ready_count = 0U;
static unsigned int g_process_frame_count = 0U;

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

    status = device_protocol_init();
    if (status != XST_SUCCESS) {
        cleanup_platform();
        return -1;
    }

    signal_processing_init();

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

    device_protocol_set_spectrum_provider(protocol_spectrum_provider);
    device_protocol_set_status_provider(protocol_status_provider);

    while (1) {
        device_protocol_poll();

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
    float latest_bins[SPECTRUM_BINS];
    unsigned short latest_count = 0U;
    unsigned short requested_count;
    unsigned short i;

    (void)config;

    if ((points == 0) || (out_point_count == 0)) {
        return -1;
    }

    if (signal_processing_get_latest_spectrum(latest_bins, SPECTRUM_BINS, &latest_count) != 0) {
        return -1;
    }

    requested_count = config->sweep.point_count;
    if (requested_count < 8U) {
        requested_count = 8U;
    }
    if (requested_count > max_points) {
        requested_count = max_points;
    }
    if (requested_count > latest_count) {
        requested_count = latest_count;
    }

    for (i = 0U; i < requested_count; i++) {
        unsigned int src_index;

        if (requested_count <= 1U) {
            src_index = 0U;
        } else {
            src_index = ((unsigned int)i * (unsigned int)(latest_count - 1U)) /
                        (unsigned int)(requested_count - 1U);
        }

        points[i].freq_hz = (double)signal_processing_get_bin_frequency_hz((unsigned short)src_index);
        points[i].amp_dbm = (double)latest_bins[src_index] + ADC_INPUT_FULL_SCALE_DBM;
    }

    *out_point_count = requested_count;
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
    status->error_code = 0U;
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
