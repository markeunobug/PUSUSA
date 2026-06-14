#ifndef APP_CONFIG_H
#define APP_CONFIG_H

#include "xparameters.h"

#define DMA_DEV_ID          XPAR_AXIDMA_0_DEVICE_ID
#define INTC_DEVICE_ID      XPAR_SCUGIC_SINGLE_DEVICE_ID

/* The 2026-05-16 hardware fixes the DMA IRQ route by connecting
 * axi_dma_0/s2mm_introut to xlconcat_0/In0, which maps to IRQ_F2P[0].
 * Trust the BSP-exported interrupt ID for this platform.
 */
#define RX_INTR_ID          XPAR_FABRIC_AXI_DMA_0_S2MM_INTROUT_INTR

#define DDR_BASE_ADDR       XPAR_PS7_DDR_0_S_AXI_BASEADDR
#define MEM_BASE_ADDR       (DDR_BASE_ADDR + 0x1000000)
#define RX_BUFFER_BASE      (MEM_BASE_ADDR + 0x00300000)

#define FFT_SIZE            4096U
#define TRANSFER_LENGTH     (FFT_SIZE * 2U)
#define DMA_MAX_SAMPLES     (1024U * FFT_SIZE)
#define DMA_MAX_BYTES       (DMA_MAX_SAMPLES * 2U)
/* Stage-1 PL capture control accepts up to 16384 samples per frame. Keep sweep
 * simple transfers block-aligned and inside that controlled-frame limit:
 * 4 * 4096 samples * 2 bytes = 32768 bytes. */
#define DMA_SWEEP_MAX_BLOCKS_PER_TRANSFER   4U
#define DMA_SWEEP_MAX_SAMPLES_PER_TRANSFER  (DMA_SWEEP_MAX_BLOCKS_PER_TRANSFER * FFT_SIZE)
#define DMA_SWEEP_SG_BATCH_ENABLE 0U
#define DMA_SWEEP_SG_BURST_ENABLE 1U
#define DMA_SWEEP_SG_MAX_BLOCKS_PER_TRANSFER 1024U
#define DMA_SWEEP_SG_MAX_SAMPLES_PER_TRANSFER \
    (DMA_SWEEP_SG_MAX_BLOCKS_PER_TRANSFER * FFT_SIZE)
#define DMA_CAPTURE_BURST_DIAG_ENABLE 1U
#define DMA_SIMPLE_MAX_BYTES                65535U
#define SPECTRUM_BINS       (FFT_SIZE / 2U)

#ifndef PI
#define PI                  3.14159265358979323846f
#endif
#define EPSILON             1e-12f
#define FULL_SCALE_COMPLEX_POWER 0.25f

#define DDC_BYPASS          0
#define ADC_SAMPLE_RATE_HZ  130000000.0f
#define DDC_IF_HZ           40000000.0f
#define UART_BASEADDR       XPAR_XUARTPS_0_BASEADDR

#define AD8370_GPIO_DEVICE_ID   XPAR_AXI_GPIO_0_DEVICE_ID
#define AD8370_GPIO_CHANNEL     1U
#define AD8370_GPIO_LTC_MASK    (1U << 0)
#define AD8370_GPIO_CLK_MASK    (1U << 1)
#define AD8370_GPIO_DATA_MASK   (1U << 2)
#define LTC2208_PGA_MASK        (1U << 3)
#define LTC2208_SHDN_MASK       (1U << 4)
#define LTC2208_DITH_MASK       (1U << 5)
#define LTC2208_RAND_MASK       (1U << 6)
#define AD8370_ENABLE_STARTUP_TEST 0
#define AD8370_STARTUP_TEST_DELAY_US 500000U
#define AD8370_DEFAULT_GAIN_CODE 0x19U//  dB
#define AD8370_VERBOSE 0

#define LMX2572_GPIO_DEVICE_ID   XPAR_AXI_GPIO_1_DEVICE_ID
#define LMX2572_GPIO_OUT_CHANNEL 1U
#define LMX2572_GPIO_MUX_CHANNEL 2U
#define LMX2572_0_CE_MASK        (1U << 0)
#define LMX2572_0_CSB_MASK       (1U << 1)
#define LMX2572_0_SCK_MASK       (1U << 2)
#define LMX2572_0_SDI_MASK       (1U << 3)
#define LMX2572_1_CE_MASK        (1U << 4)
#define LMX2572_1_CSB_MASK       (1U << 5)
#define LMX2572_1_SCK_MASK       (1U << 6)
#define LMX2572_1_SDI_MASK       (1U << 7)
#define LMX2572_2_CE_MASK        (1U << 8)
#define LMX2572_2_CSB_MASK       (1U << 9)
#define LMX2572_2_SCK_MASK       (1U << 10)
#define LMX2572_2_SDI_MASK       (1U << 11)
#define LMX2572_0_MUX_MASK       (1U << 0)
#define LMX2572_1_MUX_MASK       (1U << 1)
#define LMX2572_2_MUX_MASK       (1U << 2)
#define LMX2572_GPIO_DELAY_LOOPS 20U
#define LMX2572_DEFAULT_REF_HZ   50000000U
#define LMX2572_DEFAULT_REF_DOUBLER 1U
#define LMX2572_DEFAULT_REF_PRE_R 1U
#define LMX2572_DEFAULT_REF_MULTIPLIER 1U
#define LMX2572_DEFAULT_REF_R    1U
#define LMX2572_DEFAULT_OUTPUT_HZ 1000000000ULL
#define LMX2572_ADC_CLK_OUTPUT_HZ 130000000ULL
#define LMX2572_ADC_CLK_OUTPUT_POWER_DBM 0
#define LMX2572_LO1_OUTPUT_POWER_DBM 0
#define LMX2572_LO2_OUTPUT_POWER_DBM 0
#define LMX2572_DEFAULT_OUTPUT_POWER_DBM LMX2572_LO1_OUTPUT_POWER_DBM

#if defined(XPAR_AXI_GPIO_2_DEVICE_ID)
#define RF_FRONTEND_GPIO_AVAILABLE 1
#define RF_FRONTEND_GPIO_DEVICE_ID XPAR_AXI_GPIO_2_DEVICE_ID
#else
#define RF_FRONTEND_GPIO_AVAILABLE 0
#define RF_FRONTEND_GPIO_DEVICE_ID 0U
#endif
#define RF_FRONTEND_GPIO_CHANNEL   1U
#define RF_SW1_CTL_MASK            (1U << 0)
#define RF_SW2_CTL_MASK            (1U << 1)
#define RF_SW3_CTL_MASK            (1U << 2)
#define RF_SW4_A_MASK              (1U << 3)
#define RF_SW4_B_MASK              (1U << 4)
#define RF_DSA_CLK_MASK            (1U << 5)
#define RF_DSA_SI_MASK             (1U << 6)
#define RF_DSA_LE_MASK             (1U << 7)
#define RF_FRONTEND_DEFAULT_ATTEN_CODE 127U

#define AMPLITUDE_LNA_GAIN_DB         30.0f
#define AMPLITUDE_DIRECT_IF_CAL_DB    0.0f
#define AMPLITUDE_MIXER_CHAIN_CAL_DB  0.0f
#define AMPLITUDE_FREQ_CAL_DB_0       0.0f
#define AMPLITUDE_FREQ_CAL_DB_1       0.0f
#define AMPLITUDE_FREQ_CAL_DB_2       0.0f
#define AMPLITUDE_FREQ_CAL_DB_3       0.0f

#define SIGNAL_PROCESSING_VERBOSE 0
/* DDC tone diagnostics for leakage bring-up. Disable for normal sweep speed. */
#define SIGNAL_PROCESSING_DDC_DEBUG_ENABLE 0
/* Expensive diagnostic peak search for RBW bring-up. Keep disabled for normal
 * sweep speed; it scans -200 kHz..+200 kHz with per-sample sin/cos work. */
#define SIGNAL_PROCESSING_PEAK_SEARCH_ENABLE 0
#define SWEEP_PROFILE_ENABLE 1

/* ADC full-scale reference: LTC2208 2.25 Vpp diff 閳拷 1:2 balun 閳拷 50鎯� */
#define ADC_INPUT_FULL_SCALE_DBM  8.02f

#define RBW_1K_HZ           1000.0f
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
#define RBW_1K_CIC_R          1300U
#define RBW_1K_CIC_N          5U

/* Validation switch: bypass CIC only for RBW_MODE_10K and use a direct
 * low-pass FIR decimator from 130 MHz to 1 MHz instead. */
#define RBW_10K_USE_FIR_DECIMATOR       0
#define RBW_10K_FIR_DECIMATOR_R         130U
#define RBW_10K_FIR_DECIMATOR_TAPS      8192U
#define RBW_10K_FIR_DECIMATOR_CUTOFF_HZ 50000.0f
#define RBW_10K_FIR_DECIMATOR_BETA      6.0f

/* Temporary 10 kHz RBW DDC synthesis mode for decimator diagnosis.
 * 0 = real ADC/DDC data
 * 1 = pure complex +100 kHz tone
 * 2 = ideal real-signal DDC model: +100 kHz plus -80.100 MHz image
 * 3 = mode 2, but reset synthetic phase at each DMA/FFT block boundary
 * Return this to 0 after the alias/image diagnostic is complete. */
#define RBW_10K_SYNTH_DDC_MODE_REAL_ADC         0
#define RBW_10K_SYNTH_DDC_MODE_COMPLEX_100K     1
#define RBW_10K_SYNTH_DDC_MODE_REAL_IMAGE       2
#define RBW_10K_SYNTH_DDC_MODE_REAL_IMAGE_BLOCK_RESET 3
#define RBW_10K_SYNTH_DDC_MODE                  RBW_10K_SYNTH_DDC_MODE_REAL_ADC
#define RBW_10K_SYNTH_DDC_MAIN_FREQ_HZ          100000.0f
#define RBW_10K_SYNTH_DDC_IMAGE_FREQ_HZ         (-80100000.0f)
#define RBW_10K_SYNTH_DDC_MAIN_AMPLITUDE        0.5f
#define RBW_10K_SYNTH_DDC_IMAGE_AMPLITUDE       0.5f

/* Compensating FIR filter taps per RBW mode */
#define RBW_1M_FIR_TAPS       96U
#define RBW_300K_FIR_TAPS     128U
#define RBW_100K_FIR_TAPS     128U
#define RBW_30K_FIR_TAPS      256U
#define RBW_10K_FIR_TAPS      256U
#define RBW_1K_FIR_TAPS       768U

/* Decimated output target per sweep point after CIC and FIR transient.
 * Fast-test profile:
 *   K ~= observe_points * RBW / fs_out
 *   1M/300K/100K/30K/10K target K ~= 10 for faster sweep testing.
 *   1K target K ~= 5 for a faster but less noisy low-RBW test.
 *   Raise 1K observe to 1000/2000 for K ~= 10/20 later. */
#define RBW_1M_OBSERVE_POINTS   100U
#define RBW_300K_OBSERVE_POINTS 101U
#define RBW_100K_OBSERVE_POINTS 100U
#define RBW_30K_OBSERVE_POINTS  101U
#define RBW_10K_OBSERVE_POINTS  100U
#define RBW_1K_OBSERVE_POINTS   500U

/* FIR transient skip: ceil(fir_taps/2) per mode */
#define RBW_1M_SKIP_POINTS      32U
#define RBW_300K_SKIP_POINTS    64U
#define RBW_100K_SKIP_POINTS    64U
#define RBW_30K_SKIP_POINTS     128U
#define RBW_10K_SKIP_POINTS     128U
#define RBW_1K_SKIP_POINTS      128U

/* Accumulation buffer: holds decimated CIC output across DMA transfers.
 * Keep enough headroom for the later 1K K~=20 profile:
 *   RBW_1K: 2000 + 128 + 768 = 2896 */
#define ACCUM_BUFFER_SIZE     2944U

typedef enum {
    RBW_MODE_10K = 0,
    RBW_MODE_30K = 1,
    RBW_MODE_100K = 2,
    RBW_MODE_300K = 3,
    RBW_MODE_1M = 4,
    RBW_MODE_1K = 5
} rbw_mode_t;

#endif
