/***************************** Include Files *********************************/

#include "xaxidma.h"
#include "xil_cache.h"
#include "xil_exception.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "xscugic.h"
#include <stdint.h>

/************************** Constant Definitions *****************************/

#define DMA_DEV_ID              XPAR_AXIDMA_0_DEVICE_ID
#define RX_INTR_ID              XPAR_FABRIC_AXIDMA_0_S2MM_INTROUT_VEC_ID
#define INTC_DEVICE_ID          XPAR_SCUGIC_SINGLE_DEVICE_ID

#define DDR_BASE_ADDR           XPAR_PS7_DDR_0_S_AXI_BASEADDR
#define MEM_BASE_ADDR           (DDR_BASE_ADDR + 0x1000000)
#define RX_BUFFER_BASE          (MEM_BASE_ADDR + 0x00300000)

#define RESET_TIMEOUT_COUNTER   10000
#define SAMPLE_COUNT            4096
#define SAMPLE_BYTES            (SAMPLE_COUNT * sizeof(uint16_t))
#define PRINT_SAMPLE_COUNT      32

/************************** Function Prototypes ******************************/

static void rx_intr_handler(void *callback);
static int setup_intr_system(XScuGic *intc_ptr, XAxiDma *axidma_ptr, u16 rx_intr_id);
static void disable_intr_system(XScuGic *intc_ptr, u16 rx_intr_id);
static int start_adc_capture(uint16_t *rx_buffer_ptr);
static void dump_samples(const uint16_t *samples, int count);
static void print_sample_stats(const uint16_t *samples, int count);

/************************** Variable Definitions *****************************/

static XAxiDma axidma;
static XScuGic intc;
static volatile int rx_done;
static volatile int error;

/************************** Function Definitions *****************************/

int main(void)
{
    int status;
    uint16_t *rx_buffer_ptr;
    XAxiDma_Config *config;

    rx_buffer_ptr = (uint16_t *)RX_BUFFER_BASE;

    xil_printf("\r\n--- ADC Capture Start ---\r\n");
    xil_printf("Capture samples: %d\r\n", SAMPLE_COUNT);

    config = XAxiDma_LookupConfig(DMA_DEV_ID);
    if (config == NULL) {
        xil_printf("No DMA config found for device %d\r\n", DMA_DEV_ID);
        return XST_FAILURE;
    }

    status = XAxiDma_CfgInitialize(&axidma, config);
    if (status != XST_SUCCESS) {
        xil_printf("DMA initialization failed: %d\r\n", status);
        return XST_FAILURE;
    }

    if (XAxiDma_HasSg(&axidma)) {
        xil_printf("Scatter-gather mode is not supported in this app\r\n");
        return XST_FAILURE;
    }

    status = setup_intr_system(&intc, &axidma, RX_INTR_ID);
    if (status != XST_SUCCESS) {
        xil_printf("Interrupt setup failed\r\n");
        return XST_FAILURE;
    }

    status = start_adc_capture(rx_buffer_ptr);
    if (status != XST_SUCCESS) {
        xil_printf("ADC capture failed\r\n");
        disable_intr_system(&intc, RX_INTR_ID);
        return XST_FAILURE;
    }

    dump_samples(rx_buffer_ptr, PRINT_SAMPLE_COUNT);
    print_sample_stats(rx_buffer_ptr, SAMPLE_COUNT);

    disable_intr_system(&intc, RX_INTR_ID);
    xil_printf("--- ADC Capture Done ---\r\n");
    return XST_SUCCESS;
}

static int start_adc_capture(uint16_t *rx_buffer_ptr)
{
    int timeout;
    int status;

    rx_done = 0;
    error = 0;

    Xil_DCacheInvalidateRange((UINTPTR)rx_buffer_ptr, SAMPLE_BYTES);

    status = XAxiDma_SimpleTransfer(&axidma,
                                    (UINTPTR)rx_buffer_ptr,
                                    SAMPLE_BYTES,
                                    XAXIDMA_DEVICE_TO_DMA);
    if (status != XST_SUCCESS) {
        xil_printf("S2MM transfer start failed: %d\r\n", status);
        return XST_FAILURE;
    }

    timeout = RESET_TIMEOUT_COUNTER * 1000;
    while ((!rx_done) && (!error) && timeout) {
        timeout--;
    }

    if (timeout == 0) {
        xil_printf("Capture timeout\r\n");
        return XST_FAILURE;
    }

    if (error) {
        xil_printf("DMA receive error\r\n");
        return XST_FAILURE;
    }

    Xil_DCacheInvalidateRange((UINTPTR)rx_buffer_ptr, SAMPLE_BYTES);
    return XST_SUCCESS;
}

static void dump_samples(const uint16_t *samples, int count)
{
    int i;

    xil_printf("First %d ADC samples:\r\n", count);
    for (i = 0; i < count; ++i) {
        xil_printf("[%04d] 0x%04x\r\n", i, samples[i]);
    }
}

static void print_sample_stats(const uint16_t *samples, int count)
{
    int i;
    uint16_t min_value;
    uint16_t max_value;
    uint64_t sum;

    min_value = 0xffff;
    max_value = 0x0000;
    sum = 0;

    for (i = 0; i < count; ++i) {
        if (samples[i] < min_value) {
            min_value = samples[i];
        }
        if (samples[i] > max_value) {
            max_value = samples[i];
        }
        sum += samples[i];
    }

    xil_printf("Sample stats: min=0x%04x max=0x%04x avg=%u\r\n",
               min_value,
               max_value,
               (unsigned int)(sum / (uint64_t)count));
}

static void rx_intr_handler(void *callback)
{
    int timeout;
    u32 irq_status;
    XAxiDma *axidma_inst;

    axidma_inst = (XAxiDma *)callback;

    irq_status = XAxiDma_IntrGetIrq(axidma_inst, XAXIDMA_DEVICE_TO_DMA);
    XAxiDma_IntrAckIrq(axidma_inst, irq_status, XAXIDMA_DEVICE_TO_DMA);

    if ((irq_status & XAXIDMA_IRQ_ERROR_MASK) != 0U) {
        error = 1;
        XAxiDma_Reset(axidma_inst);

        timeout = RESET_TIMEOUT_COUNTER;
        while (timeout != 0) {
            if (XAxiDma_ResetIsDone(axidma_inst)) {
                break;
            }
            timeout--;
        }
        return;
    }

    if ((irq_status & XAXIDMA_IRQ_IOC_MASK) != 0U) {
        rx_done = 1;
    }
}

static int setup_intr_system(XScuGic *intc_ptr, XAxiDma *axidma_ptr, u16 rx_intr_id)
{
    int status;
    XScuGic_Config *intc_config;

    intc_config = XScuGic_LookupConfig(INTC_DEVICE_ID);
    if (intc_config == NULL) {
        return XST_FAILURE;
    }

    status = XScuGic_CfgInitialize(intc_ptr,
                                   intc_config,
                                   intc_config->CpuBaseAddress);
    if (status != XST_SUCCESS) {
        return XST_FAILURE;
    }

    XScuGic_SetPriorityTriggerType(intc_ptr, rx_intr_id, 0xA0, 0x3);

    status = XScuGic_Connect(intc_ptr,
                             rx_intr_id,
                             (Xil_InterruptHandler)rx_intr_handler,
                             axidma_ptr);
    if (status != XST_SUCCESS) {
        return status;
    }

    XScuGic_Enable(intc_ptr, rx_intr_id);

    Xil_ExceptionInit();
    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_INT,
                                 (Xil_ExceptionHandler)XScuGic_InterruptHandler,
                                 (void *)intc_ptr);
    Xil_ExceptionEnable();

    XAxiDma_IntrDisable(axidma_ptr, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DMA_TO_DEVICE);
    XAxiDma_IntrEnable(axidma_ptr, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);

    return XST_SUCCESS;
}

static void disable_intr_system(XScuGic *intc_ptr, u16 rx_intr_id)
{
    XScuGic_Disconnect(intc_ptr, rx_intr_id);
}
