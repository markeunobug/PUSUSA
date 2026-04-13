#include "signal_processing.h"

#include <math.h>
#include "arm_const_structs.h"
#include "arm_math.h"
#include "xil_printf.h"

static float32_t time_domain_real[FFT_SIZE];
static float32_t time_domain_imag[FFT_SIZE];
static float32_t stage_real[FFT_SIZE];
static float32_t stage_imag[FFT_SIZE];
static float32_t fft_input[2 * FFT_SIZE];
static float32_t fft_mag[FFT_SIZE];
static float32_t hann_window[FFT_SIZE];
static float32_t rbw_lpf_coeffs[RBW_LPF_TAP_NUM];
static float32_t latest_spectrum_dbfs[SPECTRUM_BINS];

static rbw_mode_t current_rbw_mode = RBW_MODE_100K;
static int latest_spectrum_valid = 0;

static void hann_init(void);
static void spectral_prepare_input(volatile u16 *rx_buffer);
static void ddc_process_block(volatile u16 *rx_buffer);
static void ddc_bypass_copy(volatile u16 *rx_buffer);
static void ddc_mix_to_baseband(volatile u16 *rx_buffer);
static void remove_dc_offset(void);
static void rbw_lpf_init(float32_t cutoff_hz);
static void rbw_lpf_apply_complex(void);
static const char *rbw_mode_name(rbw_mode_t mode);
static float32_t rbw_mode_cutoff_hz(rbw_mode_t mode);
static void fft_run(void);
static void fft_postprocess(void);
static void report_time_domain_power(void);
static void fft_report_peak(void);

void signal_processing_init(void)
{
    hann_init();
    signal_processing_apply_rbw_mode(RBW_MODE_100K);
}

void signal_processing_apply_rbw_mode(rbw_mode_t mode)
{
    current_rbw_mode = mode;
    rbw_lpf_init(rbw_mode_cutoff_hz(mode));
#if SIGNAL_PROCESSING_VERBOSE
    xil_printf("RBW,%s\r\n", rbw_mode_name(current_rbw_mode));
#endif
}

void signal_processing_process_frame(volatile u16 *rx_buffer)
{
    spectral_prepare_input(rx_buffer);
    report_time_domain_power();
    fft_run();
    fft_postprocess();
    fft_report_peak();
}

int signal_processing_get_latest_spectrum(float *out_mag_dbfs,
                                          unsigned short max_bins,
                                          unsigned short *out_bin_count)
{
    unsigned short copy_count;
    unsigned short i;

    if ((out_mag_dbfs == 0) || (out_bin_count == 0) || !latest_spectrum_valid) {
        return -1;
    }

    copy_count = (unsigned short)SPECTRUM_BINS;
    if (max_bins < copy_count) {
        copy_count = max_bins;
    }

    for (i = 0U; i < copy_count; i++) {
        out_mag_dbfs[i] = latest_spectrum_dbfs[i];
    }

    *out_bin_count = copy_count;
    return 0;
}

float signal_processing_get_bin_frequency_hz(unsigned short bin_index)
{
    return ((float)bin_index * ADC_SAMPLE_RATE_HZ) / (float)FFT_SIZE;
}

int signal_processing_has_latest_spectrum(void)
{
    return latest_spectrum_valid;
}

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

static void ddc_bypass_copy(volatile u16 *rx_buffer)
{
    uint32_t i;

    for (i = 0; i < FFT_SIZE; i++) {
        int16_t adc_value = (int16_t)rx_buffer[i];
        float32_t norm = (float32_t)adc_value / 32768.0f;

        time_domain_real[i] = norm;
        time_domain_imag[i] = 0.0f;
    }
}

static void ddc_mix_to_baseband(volatile u16 *rx_buffer)
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

static void ddc_process_block(volatile u16 *rx_buffer)
{
#if DDC_BYPASS
    ddc_bypass_copy(rx_buffer);
#else
    ddc_mix_to_baseband(rx_buffer);
    rbw_lpf_apply_complex();
    remove_dc_offset();
#endif
}

static void spectral_prepare_input(volatile u16 *rx_buffer)
{
    uint32_t i;

    ddc_process_block(rx_buffer);

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
        latest_spectrum_dbfs[i] = fft_mag[i];
    }

    latest_spectrum_valid = 1;
}

static void report_time_domain_power(void)
{
#if SIGNAL_PROCESSING_VERBOSE
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
#endif
}

static void fft_report_peak(void)
{
#if SIGNAL_PROCESSING_VERBOSE
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

    xil_printf("PEAK,%s,%d,%d,%03d,%d",
               rbw_mode_name(current_rbw_mode),
               peak_bin,
               peak_freq_khz,
               peak_freq_hz_rem,
               (int)peak_db);
#endif
}
