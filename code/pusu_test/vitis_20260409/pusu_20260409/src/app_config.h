#ifndef APP_CONFIG_H
#define APP_CONFIG_H

#include "xparameters.h"

#define DMA_DEV_ID          XPAR_AXIDMA_0_DEVICE_ID
#define INTC_DEVICE_ID      XPAR_SCUGIC_SINGLE_DEVICE_ID

/* Temporary validation override:
 * The BD connects axi_dma_0/s2mm_introut to xlconcat_0/In1, which should map
 * to IRQ_F2P[1] = 62 on Zynq-7000. Force 62 here to verify whether the BSP
 * exported interrupt ID is mismatched.
 */
#define RX_INTR_ID          62U

#define DDR_BASE_ADDR       XPAR_PS7_DDR_0_S_AXI_BASEADDR
#define MEM_BASE_ADDR       (DDR_BASE_ADDR + 0x1000000)
#define RX_BUFFER_BASE      (MEM_BASE_ADDR + 0x00300000)

#define FFT_SIZE            4096U
#define TRANSFER_LENGTH     (FFT_SIZE * 2U)
#define SPECTRUM_BINS       (FFT_SIZE / 2U)

#ifndef PI
#define PI                  3.14159265358979323846f
#endif
#define EPSILON             1e-12f
#define FULL_SCALE_COMPLEX_POWER 0.25f

#define DDC_BYPASS          0
#define ADC_SAMPLE_RATE_HZ  130000000.0f
#define DDC_IF_HZ           50000000.0f
#define UART_BASEADDR       XPAR_XUARTPS_0_BASEADDR

#define AD8370_GPIO_DEVICE_ID   XPAR_AXI_GPIO_0_DEVICE_ID
#define AD8370_GPIO_CHANNEL     1U
#define AD8370_GPIO_LTC_MASK    (1U << 0)
#define AD8370_GPIO_CLK_MASK    (1U << 1)
#define AD8370_GPIO_DATA_MASK   (1U << 2)
#define AD8370_ENABLE_STARTUP_TEST 0
#define AD8370_STARTUP_TEST_DELAY_US 500000U
#define AD8370_DEFAULT_GAIN_CODE 0x80U
#define AD8370_VERBOSE 0
#define SIGNAL_PROCESSING_VERBOSE 0

#define RBW_10K_HZ          10000.0f
#define RBW_30K_HZ          30000.0f
#define RBW_100K_HZ         100000.0f
#define RBW_300K_HZ         300000.0f
#define RBW_1M_HZ           1000000.0f
#define RBW_LPF_TAP_NUM     129U

typedef enum {
    RBW_MODE_10K = 0,
    RBW_MODE_30K = 1,
    RBW_MODE_100K = 2,
    RBW_MODE_300K = 3,
    RBW_MODE_1M = 4
} rbw_mode_t;

#endif
