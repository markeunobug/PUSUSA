#ifndef SIGNAL_PROCESSING_H
#define SIGNAL_PROCESSING_H

#include "app_config.h"
#include "xil_types.h"

void signal_processing_init(void);
void signal_processing_apply_rbw_mode(rbw_mode_t mode);
void signal_processing_process_frame(volatile u16 *rx_buffer);

#endif
