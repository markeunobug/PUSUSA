#ifndef SIGNAL_PROCESSING_H
#define SIGNAL_PROCESSING_H

#include "xil_types.h"
#include "app_config.h"

typedef struct {
    u8 version;
    u8 current_rbw_mode;
    u8 reserved0;
    u8 reserved1;
    u32 point_index;
    u32 pre_rbw_count;
    u32 post_rbw_count;
    float pre_rbw_power_dbfs;
    float post_rbw_power_dbfs;
    float pre_rbw_peak_freq_hz;
    float pre_rbw_peak_dbfs;
    float post_rbw_peak_freq_hz;
    float post_rbw_peak_dbfs;
    u32 ddc_sample_count;
    float ddc_power_dbfs;
    float ddc_dc_dbfs;
    float ddc_pos10k_dbfs;
    float ddc_neg10k_dbfs;
    float ddc_pos100k_dbfs;
    float ddc_neg100k_dbfs;
} signal_processing_peak_debug_t;

void signal_processing_init(void);
void signal_processing_apply_rbw_mode(rbw_mode_t mode);
void signal_processing_set_if_hz(float if_hz);
float signal_processing_get_if_hz(void);
void signal_processing_process_frame(volatile u16 *rx_buffer);
void signal_processing_process_direct_if_fft_frame(volatile u16 *rx_buffer);
int signal_processing_measure_power_dbfs(volatile u16 *rx_buffer, float *out_power_dbfs);
int signal_processing_measure_power_dbm(volatile u16 *rx_buffer, float *out_power_dbm);
void signal_processing_accumulate_dma(volatile u16 *rx_buffer, u32 dma_samples);
int  signal_processing_accumulation_ready(void);
int  signal_processing_measure_accumulated_power_dbm(float *out_power_dbm);
void signal_processing_reset_accumulation(void);
u32  signal_processing_get_dma_samples(void);
void signal_processing_set_debug_point_index(u32 point_index);
void signal_processing_get_peak_debug(signal_processing_peak_debug_t *out_debug);
int signal_processing_get_latest_spectrum(float *out_mag_dbfs,
                                          unsigned short max_bins,
                                          unsigned short *out_bin_count);
float signal_processing_get_bin_frequency_hz(unsigned short bin_index);
int signal_processing_has_latest_spectrum(void);

#endif
