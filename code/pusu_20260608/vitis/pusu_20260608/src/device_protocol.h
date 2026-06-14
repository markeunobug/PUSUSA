#ifndef DEVICE_PROTOCOL_H
#define DEVICE_PROTOCOL_H

#include <stdint.h>

#include "xstatus.h"

#include "dma_capture.h"
#include "phase_noise_engine.h"

typedef struct {
    double start_hz;
    double stop_hz;
    double center_hz;
    double span_hz;
} device_frequency_config_t;

typedef struct {
    double ref_level_dbm;
    unsigned char attenuator_mode;
    unsigned char preamp_mode;
} device_amplitude_config_t;

typedef struct {
    unsigned char rbw_mode;
    double rbw_hz;
    unsigned char vbw_mode;
    double vbw_hz;
} device_bandwidth_config_t;

typedef struct {
    double speed_hz;
    unsigned char mode;
    unsigned short point_count;
} device_sweep_config_t;

typedef struct {
    unsigned char detect_mode;
} device_detect_config_t;

typedef struct {
    unsigned char lna_mode;
    unsigned char path_mode;
    unsigned char atten_code;
    unsigned char flags;
} device_rf_frontend_config_t;

typedef struct {
    device_frequency_config_t frequency;
    device_amplitude_config_t amplitude;
    device_bandwidth_config_t bandwidth;
    device_sweep_config_t sweep;
    device_detect_config_t detect;
    device_rf_frontend_config_t rf_frontend;
} device_control_config_t;

typedef struct {
    uint32_t freq_hz;
    float amp_dbm;
} spectrum_point_t;

typedef struct {
    double temperature_c;
    unsigned char battery_percent;
    unsigned char error_code;
    unsigned int dma_start_count;
    unsigned int dma_error_count;
    unsigned int dma_error_bg_irq_count;
    unsigned int dma_error_bg_start_count;
    unsigned int dma_error_bg_reset_count;
    unsigned int dma_error_sweep_reset_count;
    unsigned int dma_error_direct_if_count;
    unsigned int dma_error_phase_noise_count;
    unsigned int dma_error_capture_test_count;
    unsigned int dma_start_last_result_code;
    unsigned int dma_start_last_transfer_bytes;
    unsigned int dma_start_last_capture_samples;
    unsigned int dma_start_last_s2mm_dmasr;
    unsigned int dma_start_last_sg_ring_ready;
    unsigned int dma_start_last_sg_active_bd_count;
    unsigned int dma_start_last_sg_free_bd_count;
    unsigned int dma_start_fail_invalid_arg_count;
    unsigned int dma_start_fail_invalid_samples_count;
    unsigned int dma_start_fail_pl_abort_count;
    unsigned int dma_start_fail_pl_clear_count;
    unsigned int dma_start_fail_pl_config_count;
    unsigned int dma_start_fail_submit_sg_count;
    unsigned int dma_start_fail_simple_transfer_count;
    unsigned int dma_start_fail_pl_start_count;
    unsigned int frame_ready_count;
    unsigned int process_frame_count;
    unsigned char spectrum_valid;
    unsigned int s2mm_dmacr;
    unsigned int s2mm_dmasr;
    unsigned int dma_irq_count;
    unsigned int dma_last_irq_status;
    unsigned int uart_rx_bad_frame_count;
    unsigned int uart_rx_crc_error_count;
    unsigned int uart_rx_overrun_count;
    unsigned int uart_rx_resync_count;
} device_status_t;

typedef int (*device_protocol_spectrum_provider_t)(
    const device_control_config_t *config,
    spectrum_point_t *points,
    unsigned short max_points,
    unsigned short *out_point_count);

typedef int (*device_protocol_status_provider_t)(device_status_t *status);
typedef int (*device_protocol_sweep_control_t)(
    unsigned char action,
    const device_control_config_t *config);
typedef int (*device_protocol_rf_frontend_control_t)(
    const device_rf_frontend_config_t *config);
typedef int (*device_protocol_phase_noise_control_t)(
    phase_noise_engine_action_t action,
    const phase_noise_config_t *config);
typedef int (*device_protocol_capture_stream_smoke_control_t)(
    u32 sample_count,
    dma_capture_stream_smoke_result_t *result);
typedef int (*device_protocol_capture_main_smoke_control_t)(
    u32 sample_count,
    dma_capture_stream_smoke_result_t *result);
typedef int (*device_protocol_capture_sg_smoke_control_t)(
    u32 samples_per_bd,
    u32 bd_count,
    dma_capture_sg_smoke_result_t *result);
typedef int (*device_protocol_capture_sg_ring_smoke_control_t)(
    u32 samples_per_bd,
    u32 bd_count,
    u32 target_bd_count,
    dma_capture_sg_smoke_result_t *result);

#define DEVICE_PROTOCOL_SWEEP_START 1U
#define DEVICE_PROTOCOL_SWEEP_STOP  2U

int device_protocol_init(void);
void device_protocol_poll(void);
void device_protocol_recover_uart_rx(void);

const device_control_config_t *device_protocol_get_config(void);
void device_protocol_set_spectrum_provider(device_protocol_spectrum_provider_t provider);
void device_protocol_set_status_provider(device_protocol_status_provider_t provider);
void device_protocol_set_sweep_control_handler(device_protocol_sweep_control_t handler);
void device_protocol_set_rf_frontend_handler(device_protocol_rf_frontend_control_t handler);
void device_protocol_set_phase_noise_handler(device_protocol_phase_noise_control_t handler);
void device_protocol_set_capture_stream_smoke_handler(
    device_protocol_capture_stream_smoke_control_t handler);
void device_protocol_set_capture_main_smoke_handler(
    device_protocol_capture_main_smoke_control_t handler);
void device_protocol_set_capture_sg_smoke_handler(
    device_protocol_capture_sg_smoke_control_t handler);
void device_protocol_set_capture_sg_ring_smoke_handler(
    device_protocol_capture_sg_ring_smoke_control_t handler);
int device_protocol_stream_spectrum_point(uint32_t freq_hz,
                                          float amp_dbm,
                                          uint16_t total_points,
                                          uint16_t current_index,
                                          uint8_t done);
int device_protocol_stream_phase_noise_point(const phase_noise_data_t *point);
int device_protocol_send_phase_noise_status(const phase_noise_status_t *status);
void device_protocol_send_rf_frontend_status(void);

#endif
