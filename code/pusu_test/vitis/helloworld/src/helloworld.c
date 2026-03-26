#include <stdio.h>
#include <math.h>
#include "platform.h"
#include "xil_printf.h"
#include "xaxidma.h"
#include "xscugic.h"
#include "xparameters.h"
#include "xil_exception.h"
#include "xil_cache.h"
#include "xuartps_hw.h"
#include "arm_math.h"
#include "arm_const_structs.h"

/************************** Constant Definitions *****************************/

#define DMA_DEV_ID          XPAR_AXIDMA_0_DEVICE_ID
#define RX_INTR_ID          XPAR_FABRIC_AXIDMA_0_S2MM_INTROUT_VEC_ID
#define INTC_DEVICE_ID      XPAR_SCUGIC_SINGLE_DEVICE_ID

#define DDR_BASE_ADDR       XPAR_PS7_DDR_0_S_AXI_BASEADDR
#define MEM_BASE_ADDR       (DDR_BASE_ADDR + 0x1000000)
#define RX_BUFFER_BASE      (MEM_BASE_ADDR + 0x00300000)

#define FFT_SIZE            4096U
#define TRANSFER_LENGTH     (FFT_SIZE * 2U)
#define SPECTRUM_BINS       (FFT_SIZE / 2U)

#define PI                  3.14159265358979323846f
#define EPSILON             1e-12f
#define FULL_SCALE_COMPLEX_POWER 0.25f

#define DDC_BYPASS          0
#define ADC_SAMPLE_RATE_HZ  130000000.0f
#define DDC_IF_HZ           50000000.0f
#define UART_BASEADDR       XPAR_XUARTPS_0_BASEADDR
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

/************************** Function Prototypes ******************************/

static void rx_intr_handler(void *callback);
static int setup_intr_system(XScuGic *int_ins_ptr, XAxiDma *axidma_ptr, u16 rx_intr_id);
static void disable_intr_system(XScuGic *int_ins_ptr, u16 rx_intr_id);

static void hann_init(void);
static int start_dma_capture(void);
static void process_capture_frame(void);
static void spectral_prepare_input(void);
static void ddc_process_block(void);
static void ddc_bypass_copy(void);
static void ddc_mix_to_baseband(void);
static void remove_dc_offset(void);
static void rbw_lpf_init(float32_t cutoff_hz);
static void rbw_apply_mode(rbw_mode_t mode);
static void poll_uart_command(void);
static void rbw_lpf_apply_complex(void);
static void fft_run(void);
static void fft_postprocess(void);
static void report_time_domain_power(void);
static void fft_report_peak(void);
static void fft_print_spectrum(void);

/************************** Variable Definitions *****************************/

static XAxiDma axidma;
static XScuGic intc;

static volatile u16 *const rx_buffer = (u16 *)RX_BUFFER_BASE;
static volatile int rx_done = 0;
static volatile int error = 0;

static float32_t time_domain_real[FFT_SIZE];
static float32_t time_domain_imag[FFT_SIZE];
static float32_t stage_real[FFT_SIZE];
static float32_t stage_imag[FFT_SIZE];
static float32_t fft_input[2 * FFT_SIZE];
static float32_t fft_mag[FFT_SIZE];
static float32_t hann_window[FFT_SIZE];
static float32_t rbw_lpf_coeffs[RBW_LPF_TAP_NUM];

static rbw_mode_t current_rbw_mode = RBW_MODE_100K;

/************************** Signal Processing Helpers ************************/

static void hann_init(void)
{
    uint32_t i;

    for (i = 0; i < FFT_SIZE; i++) {
        hann_window[i] = 0.5f * (1.0f - cosf(2.0f * PI * i / (FFT_SIZE - 1U)));
    }
}

static void rbw_lpf_init(float32_t cutoff_hz)
{
    uint32_t n;
    const float32_t fc = cutoff_hz / ADC_SAMPLE_RATE_HZ;
    const int32_t mid = (int32_t)(RBW_LPF_TAP_NUM / 2U);
    float32_t coeff_sum = 0.0f;

    for (n = 0; n < RBW_LPF_TAP_NUM; n++) {
        int32_t k = (int32_t)n - mid;
        float32_t sinc_val;
        float32_t window;

        if (k == 0) {
            sinc_val = 2.0f * fc;
        } else {
            float32_t x = 2.0f * PI * fc * (float32_t)k;
            sinc_val = arm_sin_f32(x) / (PI * (float32_t)k);
        }

        window = 0.54f - 0.46f * arm_cos_f32(2.0f * PI * (float32_t)n / (float32_t)(RBW_LPF_TAP_NUM - 1U));
        rbw_lpf_coeffs[n] = sinc_val * window;
        coeff_sum += rbw_lpf_coeffs[n];
    }

    if (fabsf(coeff_sum) > EPSILON) {
        for (n = 0; n < RBW_LPF_TAP_NUM; n++) {
            rbw_lpf_coeffs[n] /= coeff_sum;
        }
    }
}

static const char *rbw_mode_name(rbw_mode_t mode)
{
    if (mode == RBW_MODE_10K) {
        return "10K";
    }
    if (mode == RBW_MODE_30K) {
        return "30K";
    }
    if (mode == RBW_MODE_100K) {
        return "100K";
    }
    if (mode == RBW_MODE_300K) {
        return "300K";
    }
    if (mode == RBW_MODE_1M) {
        return "1M";
    }

    return "UNKNOWN";
}

static float32_t rbw_mode_cutoff_hz(rbw_mode_t mode)
{
    if (mode == RBW_MODE_10K) {
        return RBW_10K_HZ;
    }
    if (mode == RBW_MODE_30K) {
        return RBW_30K_HZ;
    }
    if (mode == RBW_MODE_100K) {
        return RBW_100K_HZ;
    }
    if (mode == RBW_MODE_300K) {
        return RBW_300K_HZ;
    }
    if (mode == RBW_MODE_1M) {
        return RBW_1M_HZ;
    }

    return RBW_100K_HZ;
}

static void rbw_apply_mode(rbw_mode_t mode)
{
    current_rbw_mode = mode;
    rbw_lpf_init(rbw_mode_cutoff_hz(mode));
    xil_printf("RBW,%s\r\n", rbw_mode_name(current_rbw_mode));
}

static void poll_uart_command(void)
{
    if (XUartPs_IsReceiveData(UART_BASEADDR) != 0U) {
        u32 rx_data = XUartPs_ReadReg(UART_BASEADDR, XUARTPS_FIFO_OFFSET);
        char cmd = (char)(rx_data & 0xFFU);

        switch (cmd) {
        case '0':
            rbw_apply_mode(RBW_MODE_10K);
            break;
        case '1':
            rbw_apply_mode(RBW_MODE_30K);
            break;
        case '2':
            rbw_apply_mode(RBW_MODE_100K);
            break;
        case '3':
            rbw_apply_mode(RBW_MODE_300K);
            break;
        case '4':
            rbw_apply_mode(RBW_MODE_1M);
            break;
        default:
            xil_printf("RBW_CMD_ERR,%c\r\n", cmd);
            break;
        }
    }
}

static int start_dma_capture(void)
{
    int status;

    Xil_DCacheFlushRange((UINTPTR)rx_buffer, TRANSFER_LENGTH);
    status = XAxiDma_SimpleTransfer(&axidma,
                                    (UINTPTR)rx_buffer,
                                    TRANSFER_LENGTH,
                                    XAXIDMA_DEVICE_TO_DMA);
    return status;
}

static void ddc_bypass_copy(void)
{
    uint32_t i;

    for (i = 0; i < FFT_SIZE; i++) {
        int16_t adc_value = (int16_t)rx_buffer[i];
        float32_t norm = (float32_t)adc_value / 32768.0f;

        time_domain_real[i] = norm;
        time_domain_imag[i] = 0.0f;
    }
}

static void ddc_mix_to_baseband(void)
{
    uint32_t i;
    const float32_t phase_step = 2.0f * PI * DDC_IF_HZ / ADC_SAMPLE_RATE_HZ;

    for (i = 0; i < FFT_SIZE; i++) {
        int16_t adc_value = (int16_t)rx_buffer[i];
        float32_t norm = (float32_t)adc_value / 32768.0f;
        float32_t phase = phase_step * (float32_t)i;
        float32_t lo_i = arm_cos_f32(phase);
        float32_t lo_q = -arm_sin_f32(phase);

        time_domain_real[i] = norm * lo_i;
        time_domain_imag[i] = norm * lo_q;
    }
}

static void rbw_lpf_apply_complex(void)
{
    uint32_t i;
    uint32_t k;
    const uint32_t half = RBW_LPF_TAP_NUM / 2U;

    for (i = 0; i < FFT_SIZE; i++) {
        float32_t acc_real = 0.0f;
        float32_t acc_imag = 0.0f;

        for (k = 0; k < RBW_LPF_TAP_NUM; k++) {
            int32_t idx = (int32_t)i + (int32_t)k - (int32_t)half;

            if (idx >= 0 && idx < (int32_t)FFT_SIZE) {
                acc_real += time_domain_real[idx] * rbw_lpf_coeffs[k];
                acc_imag += time_domain_imag[idx] * rbw_lpf_coeffs[k];
            }
        }

        stage_real[i] = acc_real;
        stage_imag[i] = acc_imag;
    }

    for (i = 0; i < FFT_SIZE; i++) {
        time_domain_real[i] = stage_real[i];
        time_domain_imag[i] = stage_imag[i];
    }
}

static void remove_dc_offset(void)
{
    /* Keep the hook in place, but do not modify the spectrum while
     * we inspect the true low-frequency content.
     */
}

static void ddc_process_block(void)
{
#if DDC_BYPASS
    ddc_bypass_copy();
#else
    ddc_mix_to_baseband();
    rbw_lpf_apply_complex();
    remove_dc_offset();
#endif
}

static void spectral_prepare_input(void)
{
    uint32_t i;

    ddc_process_block();

    for (i = 0; i < FFT_SIZE; i++) {
        fft_input[2U * i] = time_domain_real[i] * hann_window[i];
        fft_input[2U * i + 1U] = time_domain_imag[i] * hann_window[i];
    }
}

static void fft_run(void)
{
    arm_cfft_f32(&arm_cfft_sR_f32_len4096, fft_input, 0, 1);
    arm_cmplx_mag_f32(fft_input, fft_mag, FFT_SIZE);
}

static void fft_postprocess(void)
{
    uint32_t i;

    for (i = 0; i < SPECTRUM_BINS; i++) {
        float32_t val;

        if (i == 0U) {
            val = fft_mag[i] / FFT_SIZE;
        } else {
            val = fft_mag[i] * 2.0f / FFT_SIZE;
            val *= 2.0f;
        }

        if (val < EPSILON) {
            val = EPSILON;
        }

        fft_mag[i] = 20.0f * log10f(val);
    }
}

static void report_time_domain_power(void)
{
    uint32_t i;
    float32_t power_sum = 0.0f;
    float32_t mean_power;
    float32_t power_dbfs;

    for (i = 0; i < FFT_SIZE; i++) {
        power_sum += time_domain_real[i] * time_domain_real[i];
        power_sum += time_domain_imag[i] * time_domain_imag[i];
    }

    mean_power = power_sum / (float32_t)FFT_SIZE;
    if (mean_power < EPSILON) {
        mean_power = EPSILON;
    }

    power_dbfs = 10.0f * log10f(mean_power / FULL_SCALE_COMPLEX_POWER);

    xil_printf("POWER_DBFS,%s,%d\r\n", rbw_mode_name(current_rbw_mode), (int)power_dbfs);
}

static void fft_print_spectrum(void)
{
    uint32_t i;

    for (i = 0; i < SPECTRUM_BINS; i++) {
        xil_printf("%d,%d\n", i, (int)fft_mag[i]);
    }
}

static void fft_report_peak(void)
{
    uint32_t i;
    uint32_t peak_bin = 0U;
    float32_t peak_db = fft_mag[0];
    const float32_t freq_res_hz = ADC_SAMPLE_RATE_HZ / (float32_t)FFT_SIZE;
    uint32_t peak_freq_hz;
    uint32_t peak_freq_khz;
    uint32_t peak_freq_hz_rem;

    for (i = 1; i < SPECTRUM_BINS; i++) {
        if (fft_mag[i] > peak_db) {
            peak_db = fft_mag[i];
            peak_bin = i;
        }
    }

    peak_freq_hz = (uint32_t)((float32_t)peak_bin * freq_res_hz);
    peak_freq_khz = peak_freq_hz / 1000U;
    peak_freq_hz_rem = peak_freq_hz % 1000U;

    xil_printf("PEAK,%s,%d,%d,%03d,%d",//\r\n
               rbw_mode_name(current_rbw_mode),
               peak_bin,
               peak_freq_khz,
               peak_freq_hz_rem,
               (int)peak_db);
}

static void process_capture_frame(void)
{
    Xil_DCacheInvalidateRange((UINTPTR)rx_buffer, TRANSFER_LENGTH);

    spectral_prepare_input();
    report_time_domain_power();
    fft_run();
    fft_postprocess();
    fft_report_peak();
//    fft_print_spectrum();
}

/************************** Main *****************************/

int main(void)
{
    int status;
    XAxiDma_Config *config;

    init_platform();
    xil_printf("Hello World\r\n");

    hann_init();
    rbw_apply_mode(RBW_MODE_100K);

    config = XAxiDma_LookupConfig(DMA_DEV_ID);
    if (config == NULL) {
        xil_printf("No DMA config found\r\n");
        cleanup_platform();
        return -1;
    }

    status = XAxiDma_CfgInitialize(&axidma, config);
    if (status != XST_SUCCESS) {
        xil_printf("DMA init failed: %d\r\n", status);
        cleanup_platform();
        return -1;
    }

    status = setup_intr_system(&intc, &axidma, RX_INTR_ID);
    if (status != XST_SUCCESS) {
        xil_printf("Interrupt setup failed: %d\r\n", status);
        cleanup_platform();
        return -1;
    }

    status = start_dma_capture();
    if (status != XST_SUCCESS) {
        xil_printf("DMA start failed: %d\r\n", status);
        disable_intr_system(&intc, RX_INTR_ID);
        cleanup_platform();
        return -1;
    }

    while (1) {
        poll_uart_command();

        if (rx_done) {
            rx_done = 0;
            process_capture_frame();

            status = start_dma_capture();
            if (status != XST_SUCCESS) {
                xil_printf("DMA restart failed: %d\r\n", status);
                break;
            }
        }

        if (error) {
            error = 0;
            xil_printf("DMA error\r\n");
        }
    }

    disable_intr_system(&intc, RX_INTR_ID);
    cleanup_platform();
    return 0;
}

/************************** DMA / Interrupt *****************************/

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

static void disable_intr_system(XScuGic *int_ins_ptr, u16 rx_intr_id)
{
    XScuGic_Disconnect(int_ins_ptr, rx_intr_id);
}
