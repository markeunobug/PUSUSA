#ifndef DEVICE_PROTOCOL_H
#define DEVICE_PROTOCOL_H

#include <stdint.h>

#include "xstatus.h"

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
    device_frequency_config_t frequency;
    device_amplitude_config_t amplitude;
    device_bandwidth_config_t bandwidth;
    device_sweep_config_t sweep;
    device_detect_config_t detect;
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
    unsigned int frame_ready_count;
    unsigned int process_frame_count;
    unsigned char spectrum_valid;
    unsigned int s2mm_dmacr;
    unsigned int s2mm_dmasr;
    unsigned int dma_irq_count;
    unsigned int dma_last_irq_status;
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

#define DEVICE_PROTOCOL_SWEEP_START 1U
#define DEVICE_PROTOCOL_SWEEP_STOP  2U

int device_protocol_init(void);
void device_protocol_poll(void);

const device_control_config_t *device_protocol_get_config(void);
void device_protocol_set_spectrum_provider(device_protocol_spectrum_provider_t provider);
void device_protocol_set_status_provider(device_protocol_status_provider_t provider);
void device_protocol_set_sweep_control_handler(device_protocol_sweep_control_t handler);
int device_protocol_stream_spectrum_point(uint32_t freq_hz, float amp_dbm);

#endif
