#ifndef SIGNAL_PROCESSING_H
#define SIGNAL_PROCESSING_H

#include "xil_types.h"
#include "app_config.h"

void signal_processing_init(void);
void signal_processing_apply_rbw_mode(rbw_mode_t mode);
void signal_processing_set_if_hz(float if_hz);
float signal_processing_get_if_hz(void);
void signal_processing_process_frame(volatile u16 *rx_buffer);
int signal_processing_measure_power_dbfs(volatile u16 *rx_buffer, float *out_power_dbfs);
int signal_processing_measure_power_dbm(volatile u16 *rx_buffer, float *out_power_dbm);
void signal_processing_accumulate_dma(volatile u16 *rx_buffer, u32 dma_samples);
int  signal_processing_accumulation_ready(void);
int  signal_processing_measure_accumulated_power_dbm(float *out_power_dbm);
void signal_processing_reset_accumulation(void);
u32  signal_processing_get_dma_samples(void);
int signal_processing_get_latest_spectrum(float *out_mag_dbfs,
                                          unsigned short max_bins,
                                          unsigned short *out_bin_count);
float signal_processing_get_bin_frequency_hz(unsigned short bin_index);
int signal_processing_has_latest_spectrum(void);

#endif
