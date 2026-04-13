#ifndef SIGNAL_PROCESSING_H
#define SIGNAL_PROCESSING_H

#include "app_config.h"
#include "xil_types.h"

void signal_processing_init(void);
void signal_processing_apply_rbw_mode(rbw_mode_t mode);
void signal_processing_process_frame(volatile u16 *rx_buffer);
int signal_processing_get_latest_spectrum(float *out_mag_dbfs,
                                          unsigned short max_bins,
                                          unsigned short *out_bin_count);
float signal_processing_get_bin_frequency_hz(unsigned short bin_index);
int signal_processing_has_latest_spectrum(void);

#endif
