#ifndef DMA_CAPTURE_H
#define DMA_CAPTURE_H

#include "xstatus.h"
#include "xil_types.h"

int dma_capture_init(void);
int dma_capture_start(void);
int dma_capture_frame_ready(void);
int dma_capture_take_error(void);
volatile u16 *dma_capture_get_rx_buffer(void);
void dma_capture_shutdown(void);

#endif
