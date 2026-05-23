#include "signal_processing.h"
#include "cic_decimator.h"

#include <math.h>
#include <string.h>
#include "arm_const_structs.h"
#include "arm_math.h"
#include "profile_timer.h"
#include "xil_printf.h"

/* ── FFT-path static buffers (unchanged) ─────────────────────────── */
static float32_t time_domain_real[FFT_SIZE];
static float32_t time_domain_imag[FFT_SIZE];
static float32_t stage_real[FFT_SIZE];
static float32_t stage_imag[FFT_SIZE];
static float32_t fft_input[2 * FFT_SIZE];
static float32_t fft_mag[FFT_SIZE];
static float32_t hann_window[FFT_SIZE];
static float32_t rbw_lpf_coeffs[RBW_LPF_TAP_NUM];
static float32_t latest_spectrum_dbfs[SPECTRUM_BINS];
static float32_t fir_state[FFT_SIZE + RBW_LPF_TAP_NUM - 1];
static arm_fir_instance_f32 fir_instance;

/* ── Sweep-path accumulation state ───────────────────────────────── */
static float32_t accum_i[ACCUM_BUFFER_SIZE];
static float32_t accum_q[ACCUM_BUFFER_SIZE];
static int       accum_count;
static int       accum_target;
static u32       current_dma_samples = FFT_SIZE;

static float32_t comp_fir_coeffs[RBW_1K_FIR_TAPS];
static float32_t comp_fir_state[ACCUM_BUFFER_SIZE + RBW_1K_FIR_TAPS];
static arm_fir_instance_f32 comp_fir_instance;
static int       comp_fir_taps;
static int       comp_fir_skip;

/* ── NCO precomputed lookup table ─────────────────────────────────── */
static float32_t nco_cos_table[FFT_SIZE];
static float32_t nco_sin_table[FFT_SIZE];
static float32_t nco_if_hz;
static float32_t nco_block_phase_step;
static float32_t sweep_nco_phase;

static rbw_mode_t current_rbw_mode = RBW_MODE_100K;
static int latest_spectrum_valid = 0;
static float32_t current_if_hz = DDC_IF_HZ;

/* ── Static forward declarations ─────────────────────────────────── */
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

/* Sweep-path internals */
static void nco_table_build(float32_t if_hz);
static void ddc_mix_to_time_domain(volatile u16 *rx_buffer);
static void ddc_mix_to_time_domain_sweep(volatile u16 *rx_buffer);
static void sweep_configure_for_rbw(rbw_mode_t mode);
static void compensating_fir_init(float32_t cutoff_hz, int taps);
static void apply_compensating_fir(void);
static float32_t measure_power_dbfs_accumulated(void);

/* ── Public API ──────────────────────────────────────────────────── */

void signal_processing_init(void)
{
    hann_init();
    nco_table_build(DDC_IF_HZ);
    signal_processing_apply_rbw_mode(RBW_MODE_100K);
}

void signal_processing_apply_rbw_mode(rbw_mode_t mode)
{
    current_rbw_mode = mode;

    /* FFT-path legacy LPF for signal_processing_process_frame() */
    rbw_lpf_init(rbw_mode_cutoff_hz(mode));

    /* Sweep-path CIC + compensating FIR */
    sweep_configure_for_rbw(mode);

#if SIGNAL_PROCESSING_VERBOSE
    xil_printf("RBW,%s\r\n", rbw_mode_name(current_rbw_mode));
#endif
}

void signal_processing_set_if_hz(float if_hz)
{
    if (if_hz > 0.0f && if_hz != current_if_hz) {
        current_if_hz = if_hz;
        nco_table_build(if_hz);
    }
}

float signal_processing_get_if_hz(void)
{
    return current_if_hz;
}

/* ── FFT-path: full-spectrum processing (kept, not in sweep use) ─── */

void signal_processing_process_frame(volatile u16 *rx_buffer)
{
    spectral_prepare_input(rx_buffer);
    report_time_domain_power();
    fft_run();
    fft_postprocess();
    fft_report_peak();
}

int signal_processing_measure_power_dbfs(volatile u16 *rx_buffer, float *out_power_dbfs)
{
    /* Legacy single-buffer power measurement through old DDC+LPF path.
     * Sweep engine now uses accumulate_dma + measure_accumulated_power_dbm
     * instead.  Kept for standalone use / smoke tests. */
    uint32_t i;
    float32_t power_sum = 0.0f;
    float32_t mean_power;

    if ((rx_buffer == 0) || (out_power_dbfs == 0)) {
        return -1;
    }

    ddc_process_block(rx_buffer);

    for (i = 0; i < FFT_SIZE; i++) {
        power_sum += time_domain_real[i] * time_domain_real[i];
        power_sum += time_domain_imag[i] * time_domain_imag[i];
    }

    mean_power = power_sum / (float32_t)FFT_SIZE;
    if (mean_power < EPSILON) {
        mean_power = EPSILON;
    }

    *out_power_dbfs = 10.0f * log10f(mean_power / FULL_SCALE_COMPLEX_POWER);
    return 0;
}

int signal_processing_measure_power_dbm(volatile u16 *rx_buffer, float *out_power_dbm)
{
    float power_dbfs = 0.0f;

    if ((rx_buffer == 0) || (out_power_dbm == 0)) {
        return -1;
    }

    if (signal_processing_measure_power_dbfs(rx_buffer, &power_dbfs) != 0) {
        return -1;
    }

    *out_power_dbm = power_dbfs + ADC_INPUT_FULL_SCALE_DBM;
    return 0;
}

/* ── Sweep-path: multi-DMA accumulation ──────────────────────────── */

void signal_processing_accumulate_dma(volatile u16 *rx_buffer, u32 dma_samples)
{
    u32 offset;
    int produced;

    for (offset = 0; offset < dma_samples; offset += FFT_SIZE) {
        sweep_profile_begin(SWEEP_PROFILE_SECTION_ACC_DDC);
        ddc_mix_to_time_domain_sweep(rx_buffer + offset);
        sweep_profile_end(SWEEP_PROFILE_SECTION_ACC_DDC);

        sweep_profile_begin(SWEEP_PROFILE_SECTION_ACC_CIC);
        produced = cic_decimator_process(time_domain_real, time_domain_imag,
                                         (int)FFT_SIZE,
                                         accum_i + accum_count,
                                         accum_q + accum_count,
                                         (int)ACCUM_BUFFER_SIZE - accum_count);
        sweep_profile_end(SWEEP_PROFILE_SECTION_ACC_CIC);
        accum_count += produced;
    }
}

int signal_processing_accumulation_ready(void)
{
    return (accum_count >= accum_target) ? 1 : 0;
}

int signal_processing_measure_accumulated_power_dbm(float *out_power_dbm)
{
    float power_dbfs;

    if ((out_power_dbm == 0) || (accum_count < 1)) {
        return -1;
    }

    apply_compensating_fir();
    power_dbfs = measure_power_dbfs_accumulated();
    *out_power_dbm = power_dbfs + ADC_INPUT_FULL_SCALE_DBM;
    return 0;
}

void signal_processing_reset_accumulation(void)
{
    accum_count = 0;
    sweep_nco_phase = 0.0f;
    cic_decimator_reset();
}

u32 signal_processing_get_dma_samples(void)
{
    return current_dma_samples;
}

/* ── Spectrum read-back (FFT path) ───────────────────────────────── */

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

/* ── Static: configuration ───────────────────────────────────────── */

typedef struct {
    int cic_r;
    int cic_n;
    int fir_taps;
    float accum_target_obs;
} rbw_mode_config_t;

static const rbw_mode_config_t *get_rbw_config(rbw_mode_t mode)
{
    static const rbw_mode_config_t cfg_1k =
        { RBW_1K_CIC_R,   RBW_1K_CIC_N,   RBW_1K_FIR_TAPS,   RBW_1K_OBSERVE_POINTS   };
    static const rbw_mode_config_t cfg_10k =
        { RBW_10K_CIC_R,  RBW_10K_CIC_N,  RBW_10K_FIR_TAPS,  RBW_10K_OBSERVE_POINTS  };
    static const rbw_mode_config_t cfg_30k =
        { RBW_30K_CIC_R,  RBW_30K_CIC_N,  RBW_30K_FIR_TAPS,  RBW_30K_OBSERVE_POINTS  };
    static const rbw_mode_config_t cfg_100k =
        { RBW_100K_CIC_R, RBW_100K_CIC_N, RBW_100K_FIR_TAPS, RBW_100K_OBSERVE_POINTS };
    static const rbw_mode_config_t cfg_300k =
        { RBW_300K_CIC_R, RBW_300K_CIC_N, RBW_300K_FIR_TAPS, RBW_300K_OBSERVE_POINTS };
    static const rbw_mode_config_t cfg_1m =
        { RBW_1M_CIC_R,   RBW_1M_CIC_N,   RBW_1M_FIR_TAPS,   RBW_1M_OBSERVE_POINTS   };

    switch (mode) {
    case RBW_MODE_1K:
        return &cfg_1k;
    case RBW_MODE_10K:
        return &cfg_10k;
    case RBW_MODE_30K:
        return &cfg_30k;
    case RBW_MODE_100K:
        return &cfg_100k;
    case RBW_MODE_300K:
        return &cfg_300k;
    case RBW_MODE_1M:
        return &cfg_1m;
    default:
        return &cfg_100k;
    }
}

static int get_rbw_skip_points(rbw_mode_t mode)
{
    switch (mode) {
    case RBW_MODE_1K:
        return RBW_1K_SKIP_POINTS;
    case RBW_MODE_10K:
        return RBW_10K_SKIP_POINTS;
    case RBW_MODE_30K:
        return RBW_30K_SKIP_POINTS;
    case RBW_MODE_100K:
        return RBW_100K_SKIP_POINTS;
    case RBW_MODE_300K:
        return RBW_300K_SKIP_POINTS;
    case RBW_MODE_1M:
        return RBW_1M_SKIP_POINTS;
    default:
        return RBW_100K_SKIP_POINTS;
    }
}

/* ── Static: sweep-path configuration ────────────────────────────── */

static void sweep_configure_for_rbw(rbw_mode_t mode)
{
    const rbw_mode_config_t *cfg = get_rbw_config(mode);

    cic_decimator_init(cfg->cic_n, cfg->cic_r);
    accum_count = 0;
    sweep_nco_phase = 0.0f;

    /* Compensating FIR: RBW lowpass at the decimated rate.
     * fs_out = ADC_SAMPLE_RATE_HZ / cfg->cic_r */
    compensating_fir_init(rbw_mode_cutoff_hz(mode), cfg->fir_taps);

    comp_fir_skip = get_rbw_skip_points(mode);

    /* Accumulation target: observe_points + skip + fir_taps margin */
    accum_target = (int)cfg->accum_target_obs + comp_fir_skip + cfg->fir_taps;
    if (accum_target > (int)ACCUM_BUFFER_SIZE) {
        accum_target = (int)ACCUM_BUFFER_SIZE;
    }

    /* Optimal DMA transfer size: minimize frames without exceeding the AXI DMA
     * simple-transfer length limit. Narrow RBW modes will accumulate several
     * DMA frames in SWEEP_ENGINE_STATE_REARM_DMA.
     * Compute in FFT_SIZE blocks since DDC+CIC operate on 4096-sample chunks.
     * total outputs from B blocks = floor(B * FFT_SIZE / cic_r).
     * Find minimum B where total_outputs >= accum_target, then clamp to the
     * largest safe block-aligned transfer. */
    {
        u32 blocks_needed = 1U;
        while ((u32)(blocks_needed * FFT_SIZE) / (u32)cfg->cic_r < (u32)accum_target) {
            blocks_needed++;
        }

        if (blocks_needed > DMA_SWEEP_MAX_BLOCKS_PER_TRANSFER) {
            blocks_needed = DMA_SWEEP_MAX_BLOCKS_PER_TRANSFER;
        }

        current_dma_samples = blocks_needed * FFT_SIZE;
    }
}

/* ── Static: compensating FIR design ─────────────────────────────── */

static void compensating_fir_init(float32_t cutoff_hz, int taps)
{
    int n;
    const rbw_mode_config_t *cfg = get_rbw_config(current_rbw_mode);
    const float32_t fs_out = ADC_SAMPLE_RATE_HZ / (float32_t)cfg->cic_r;
    const float32_t fc_norm = cutoff_hz / fs_out;
    const int mid = taps / 2;
    float32_t coeff_sum = 0.0f;

    for (n = 0; n < taps; n++) {
        int k = n - mid;
        float32_t sinc_val;
        float32_t window;

        if (k == 0) {
            sinc_val = 2.0f * fc_norm;
        } else {
            float32_t x = 2.0f * PI * fc_norm * (float32_t)k;
            sinc_val = arm_sin_f32(x) / (PI * (float32_t)k);
        }

        window = 0.54f - 0.46f * arm_cos_f32(2.0f * PI * (float32_t)n
                                              / (float32_t)(taps - 1));
        comp_fir_coeffs[n] = sinc_val * window;
        coeff_sum += comp_fir_coeffs[n];
    }

    if (fabsf(coeff_sum) > EPSILON) {
        for (n = 0; n < taps; n++) {
            comp_fir_coeffs[n] /= coeff_sum;
        }
    }

    comp_fir_taps = taps;
}

/* ── Static: apply compensating FIR to accumulated data ──────────── */

static void apply_compensating_fir(void)
{
    int first_valid;
    int out_len;
    int i;

    if (accum_count <= 0 || comp_fir_taps <= 0) {
        return;
    }

    /* arm_fir_f32() emits one output per input sample with zero initial
     * history.  stage[0..taps-2] are startup transient; apply the configured
     * skip after the first complete FIR window. */
    first_valid = (comp_fir_taps - 1) + comp_fir_skip;
    if (first_valid >= accum_count) {
        accum_count = 0;
        return;
    }
    out_len = accum_count - first_valid;

    /* Process I channel */
    {
        arm_fir_instance_f32 inst;
        memset(comp_fir_state, 0,
               (size_t)(comp_fir_taps + accum_count - 1) * sizeof(float32_t));
        arm_fir_init_f32(&inst, comp_fir_taps, comp_fir_coeffs,
                         comp_fir_state, (uint32_t)accum_count);
        arm_fir_f32(&inst, accum_i, stage_real, (uint32_t)accum_count);

        for (i = 0; i < out_len; i++) {
            accum_i[i] = stage_real[first_valid + i];
        }
    }

    /* Process Q channel (fresh state to avoid I-channel residue) */
    {
        arm_fir_instance_f32 inst;
        memset(comp_fir_state, 0,
               (size_t)(comp_fir_taps + accum_count - 1) * sizeof(float32_t));
        arm_fir_init_f32(&inst, comp_fir_taps, comp_fir_coeffs,
                         comp_fir_state, (uint32_t)accum_count);
        arm_fir_f32(&inst, accum_q, stage_imag, (uint32_t)accum_count);

        for (i = 0; i < out_len; i++) {
            accum_q[i] = stage_imag[first_valid + i];
        }
    }

    accum_count = out_len;
}

/* ── Static: power measurement on accumulated (FIR-filtered) data ── */

static float32_t measure_power_dbfs_accumulated(void)
{
    uint32_t i;
    float32_t power_sum = 0.0f;
    float32_t mean_power;

    if (accum_count < 1) {
        return -120.0f;
    }

    for (i = 0; i < (uint32_t)accum_count; i++) {
        power_sum += accum_i[i] * accum_i[i];
        power_sum += accum_q[i] * accum_q[i];
    }

    mean_power = power_sum / (float32_t)accum_count;
    if (mean_power < EPSILON) {
        mean_power = EPSILON;
    }

    return 10.0f * log10f(mean_power / FULL_SCALE_COMPLEX_POWER);
}

/* ── Static: NCO lookup table (precomputed, ~32 KB) ───────────────── */

static void nco_table_build(float32_t if_hz)
{
    uint32_t i;
    const float32_t phase_step = 2.0f * PI * if_hz / ADC_SAMPLE_RATE_HZ;

    for (i = 0; i < FFT_SIZE; i++) {
        float32_t phase = phase_step * (float32_t)i;
        nco_cos_table[i] =  arm_cos_f32(phase);
        nco_sin_table[i] = -arm_sin_f32(phase);
    }
    nco_if_hz = if_hz;
    nco_block_phase_step = fmodf(phase_step * (float32_t)FFT_SIZE,
                                 2.0f * PI);
    sweep_nco_phase = 0.0f;
}

/* ── Static: DDC mix (no LPF) �?used by sweep accumulation path ──── */

static void ddc_mix_to_time_domain(volatile u16 *rx_buffer)
{
    uint32_t i;

    for (i = 0; i < FFT_SIZE; i++) {
        float32_t norm = (float32_t)(int16_t)rx_buffer[i] / 32768.0f;

        time_domain_real[i] = norm * nco_cos_table[i];
        time_domain_imag[i] = norm * nco_sin_table[i];
    }
}

static void ddc_mix_to_time_domain_sweep(volatile u16 *rx_buffer)
{
    uint32_t i;
    float32_t phase = sweep_nco_phase;
    float32_t phase_cos = arm_cos_f32(phase);
    float32_t phase_sin = arm_sin_f32(phase);

    for (i = 0; i < FFT_SIZE; i++) {
        float32_t norm = (float32_t)(int16_t)rx_buffer[i] / 32768.0f;
        float32_t cos_base = nco_cos_table[i];
        float32_t neg_sin_base = nco_sin_table[i];

        time_domain_real[i] = norm * ((phase_cos * cos_base) +
                                      (phase_sin * neg_sin_base));
        time_domain_imag[i] = norm * ((phase_cos * neg_sin_base) -
                                      (phase_sin * cos_base));
    }

    sweep_nco_phase += nco_block_phase_step;
    if (sweep_nco_phase >= 2.0f * PI) {
        sweep_nco_phase -= 2.0f * PI;
    }
}

/* ══════════════════════════════════════════════════════════════════�? * Below: FFT-path static implementations (unchanged from original)
 * ══════════════════════════════════════════════════════════════════�?*/

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
    if (mode == RBW_MODE_1K)   return "1K";
    if (mode == RBW_MODE_10K)  return "10K";
    if (mode == RBW_MODE_30K)  return "30K";
    if (mode == RBW_MODE_100K) return "100K";
    if (mode == RBW_MODE_300K) return "300K";
    if (mode == RBW_MODE_1M)   return "1M";
    return "UNKNOWN";
}

static float32_t rbw_mode_cutoff_hz(rbw_mode_t mode)
{
    if (mode == RBW_MODE_1K)   return RBW_1K_HZ;
    if (mode == RBW_MODE_10K)  return RBW_10K_HZ;
    if (mode == RBW_MODE_30K)  return RBW_30K_HZ;
    if (mode == RBW_MODE_100K) return RBW_100K_HZ;
    if (mode == RBW_MODE_300K) return RBW_300K_HZ;
    if (mode == RBW_MODE_1M)   return RBW_1M_HZ;
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
    ddc_mix_to_time_domain(rx_buffer);
}

static void rbw_lpf_apply_complex(void)
{
    uint32_t i;

    arm_fir_init_f32(&fir_instance, RBW_LPF_TAP_NUM,
                     rbw_lpf_coeffs, fir_state, FFT_SIZE);
    arm_fir_f32(&fir_instance, time_domain_real, stage_real, FFT_SIZE);

    arm_fir_init_f32(&fir_instance, RBW_LPF_TAP_NUM,
                     rbw_lpf_coeffs, fir_state, FFT_SIZE);
    arm_fir_f32(&fir_instance, time_domain_imag, stage_imag, FFT_SIZE);

    for (i = 0; i < FFT_SIZE; i++) {
        time_domain_real[i] = stage_real[i];
        time_domain_imag[i] = stage_imag[i];
    }
}

static void remove_dc_offset(void)
{
    /* Keep the hook; no modification while inspecting low-frequency content. */
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
        fft_input[2U * i]     = time_domain_real[i] * hann_window[i];
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
