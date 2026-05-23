#include "dma_capture.h"

#include "app_config.h"
#include "xaxidma.h"
#include "xil_cache.h"
#include "xil_exception.h"
#include "xscugic.h"

static XAxiDma axidma;
static XScuGic intc;

static volatile u16 *const rx_buffer = (u16 *)RX_BUFFER_BASE;
static volatile int rx_done = 0;
static volatile int error = 0;

static void rx_intr_handler(void *callback);
static int setup_intr_system(XScuGic *int_ins_ptr, XAxiDma *axidma_ptr, u16 rx_intr_id);

int dma_capture_init(void)
{
    int status;
    XAxiDma_Config *config;

    config = XAxiDma_LookupConfig(DMA_DEV_ID);
    if (config == NULL) {
        return XST_FAILURE;
    }

    status = XAxiDma_CfgInitialize(&axidma, config);
    if (status != XST_SUCCESS) {
        return status;
    }

    status = setup_intr_system(&intc, &axidma, RX_INTR_ID);
    if (status != XST_SUCCESS) {
        return status;
    }

    return XST_SUCCESS;
}

int dma_capture_start(void)
{
    Xil_DCacheFlushRange((UINTPTR)rx_buffer, TRANSFER_LENGTH);
    return XAxiDma_SimpleTransfer(&axidma,
                                  (UINTPTR)rx_buffer,
                                  TRANSFER_LENGTH,
                                  XAXIDMA_DEVICE_TO_DMA);
}

int dma_capture_frame_ready(void)
{
    if (rx_done == 0) {
        return 0;
    }

    rx_done = 0;
    Xil_DCacheInvalidateRange((UINTPTR)rx_buffer, TRANSFER_LENGTH);
    return 1;
}

int dma_capture_take_error(void)
{
    int had_error = error;
    error = 0;
    return had_error;
}

volatile u16 *dma_capture_get_rx_buffer(void)
{
    return rx_buffer;
}

void dma_capture_shutdown(void)
{
    XScuGic_Disconnect(&intc, RX_INTR_ID);
}

static void rx_intr_handler(void *callback)
{
    XAxiDma *axidma_inst = (XAxiDma *)callback;
    u32 irq_status;

    XAxiDma_IntrDisable(axidma_inst, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);

    irq_status = XAxiDma_IntrGetIrq(axidma_inst, XAXIDMA_DEVICE_TO_DMA);
    XAxiDma_IntrAckIrq(axidma_inst, irq_status, XAXIDMA_DEVICE_TO_DMA);

    if ((irq_status & XAXIDMA_IRQ_ERROR_MASK) != 0U) {
        error = 1;
    }

    if ((irq_status & XAXIDMA_IRQ_IOC_MASK) != 0U) {
        rx_done = 1;
    }

    XAxiDma_IntrEnable(axidma_inst, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);
}

static int setup_intr_system(XScuGic *int_ins_ptr, XAxiDma *axidma_ptr, u16 rx_intr_id)
{
    int status;
    XScuGic_Config *intc_config;

    intc_config = XScuGic_LookupConfig(INTC_DEVICE_ID);
    if (intc_config == NULL) {
        return XST_FAILURE;
    }

    status = XScuGic_CfgInitialize(int_ins_ptr,
                                   intc_config,
                                   intc_config->CpuBaseAddress);
    if (status != XST_SUCCESS) {
        return XST_FAILURE;
    }

    XScuGic_SetPriorityTriggerType(int_ins_ptr, rx_intr_id, 0xA0, 0x3);

    status = XScuGic_Connect(int_ins_ptr,
                             rx_intr_id,
                             (Xil_InterruptHandler)rx_intr_handler,
                             axidma_ptr);
    if (status != XST_SUCCESS) {
        return status;
    }

    XScuGic_Enable(int_ins_ptr, rx_intr_id);

    Xil_ExceptionInit();
    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_INT,
                                 (Xil_ExceptionHandler)XScuGic_InterruptHandler,
                                 (void *)int_ins_ptr);
    Xil_ExceptionEnable();

    XAxiDma_IntrEnable(axidma_ptr, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);

    return XST_SUCCESS;
}
