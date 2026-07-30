#ifndef SIGNAL_PROCESSING_H
#define SIGNAL_PROCESSING_H

#include <stdint.h>

typedef uint16_t u16;

void signal_processing_process_direct_if_fft_frame(volatile u16 *rx_buffer);
int signal_processing_get_latest_spectrum(float *out_mag_dbfs,
                                          unsigned short max_bins,
                                          unsigned short *out_bin_count);

#endif
