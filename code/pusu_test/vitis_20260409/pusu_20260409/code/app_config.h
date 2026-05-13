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
#define AD8370_DEFAULT_GAIN_CODE 0x19U//  dB
#define AD8370_VERBOSE 0

#define LMX2572_GPIO_DEVICE_ID   XPAR_AXI_GPIO_1_DEVICE_ID
#define LMX2572_GPIO_OUT_CHANNEL 1U
#define LMX2572_GPIO_MUX_CHANNEL 2U
#define LMX2572_1_CE_MASK        (1U << 0)
#define LMX2572_1_CSB_MASK       (1U << 1)
#define LMX2572_1_SCK_MASK       (1U << 2)
#define LMX2572_1_SDI_MASK       (1U << 3)
#define LMX2572_2_CE_MASK        (1U << 4)
#define LMX2572_2_CSB_MASK       (1U << 5)
#define LMX2572_2_SCK_MASK       (1U << 6)
#define LMX2572_2_SDI_MASK       (1U << 7)
#define LMX2572_1_MUX_MASK       (1U << 0)
#define LMX2572_2_MUX_MASK       (1U << 1)
#define LMX2572_GPIO_DELAY_LOOPS 20U
#define LMX2572_DEFAULT_REF_HZ   50000000U
#define LMX2572_DEFAULT_REF_DOUBLER 1U
#define LMX2572_DEFAULT_REF_PRE_R 1U
#define LMX2572_DEFAULT_REF_MULTIPLIER 1U
#define LMX2572_DEFAULT_REF_R    1U
#define LMX2572_DEFAULT_OUTPUT_HZ 1000000000ULL
#define LMX2572_DEFAULT_OUTPUT_POWER_DBM 0

#define SIGNAL_PROCESSING_VERBOSE 0

/* ADC full-scale reference: LTC2208 2.25 Vpp diff → 1:2 balun → 50Ω */
#define ADC_INPUT_FULL_SCALE_DBM  8.02f

#define RBW_10K_HZ          10000.0f
#define RBW_30K_HZ          30000.0f
#define RBW_100K_HZ         100000.0f
#define RBW_300K_HZ         300000.0f
#define RBW_1M_HZ           1000000.0f
#define RBW_LPF_TAP_NUM     129U

/* CIC decimation ratio per RBW mode */
#define RBW_1M_CIC_R          13U
#define RBW_1M_CIC_N          4U
#define RBW_300K_CIC_R        43U
#define RBW_300K_CIC_N        4U
#define RBW_100K_CIC_R        130U
#define RBW_100K_CIC_N        5U
#define RBW_30K_CIC_R         433U
#define RBW_30K_CIC_N         5U
#define RBW_10K_CIC_R         1300U
#define RBW_10K_CIC_N         5U

/* Compensating FIR filter taps per RBW mode */
#define RBW_1M_FIR_TAPS       64U
#define RBW_300K_FIR_TAPS     128U
#define RBW_100K_FIR_TAPS     128U
#define RBW_30K_FIR_TAPS      256U
#define RBW_10K_FIR_TAPS      256U

/* Decimated output target per sweep point (post-CIC, post-FIR-transient).
 * Chosen for ~0.6-1.0 dB power measurement accuracy (σ ≈ 4.34/√N_indep).
 * Effective independent samples ≈ T_measure × RBW ≈ observe_pts × RBW/fs_out. */
#define RBW_1M_OBSERVE_POINTS   384U
#define RBW_300K_OBSERVE_POINTS 384U
#define RBW_100K_OBSERVE_POINTS 384U
#define RBW_30K_OBSERVE_POINTS  256U
#define RBW_10K_OBSERVE_POINTS  256U

/* FIR transient skip: ceil(fir_taps/2) per mode */
#define RBW_1M_SKIP_POINTS      32U
#define RBW_300K_SKIP_POINTS    64U
#define RBW_100K_SKIP_POINTS    64U
#define RBW_30K_SKIP_POINTS     128U
#define RBW_10K_SKIP_POINTS     128U

/* Accumulation buffer: holds decimated CIC output across DMA transfers.
 * Max needed = observe + skip + fir_taps:
 *   RBW_10K: 256 + 128 + 256 = 640 → 768 for margin */
#define ACCUM_BUFFER_SIZE     768U

typedef enum {
    RBW_MODE_10K = 0,
    RBW_MODE_30K = 1,
    RBW_MODE_100K = 2,
    RBW_MODE_300K = 3,
    RBW_MODE_1M = 4
} rbw_mode_t;

#endif
