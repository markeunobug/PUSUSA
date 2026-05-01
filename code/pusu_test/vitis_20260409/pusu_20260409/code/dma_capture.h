#ifndef DMA_CAPTURE_H
#define DMA_CAPTURE_H

#include "xstatus.h"
#include "xil_types.h"

typedef struct {
    u32 s2mm_dmacr;
    u32 s2mm_dmasr;
    u32 irq_count;
    u32 last_irq_status;
} dma_capture_diag_t;

int dma_capture_init(void);
int dma_capture_start(void);
int dma_capture_frame_ready(void);
int dma_capture_take_error(void);
volatile u16 *dma_capture_get_rx_buffer(void);
void dma_capture_get_diag(dma_capture_diag_t *diag);
void dma_capture_shutdown(void);

#endif
