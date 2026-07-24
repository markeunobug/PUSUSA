#include "signal_processing.h"
#include "cic_decimator.h"
#include "rbw_filter_coeffs.h"

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
static float32_t current_decimated_sample_rate_hz = ADC_SAMPLE_RATE_HZ;
static signal_processing_peak_debug_t peak_debug = {1U};
static signal_processing_peak_debug_t last_peak_debug = {1U};
static u8 peak_debug_valid = 0U;

typedef struct {
    float32_t freq_hz;
    float32_t acc_re;
    float32_t acc_im;
    float32_t osc_re;
    float32_t osc_im;
    float32_t step_re;
    float32_t step_im;
} ddc_debug_tone_t;

static ddc_debug_tone_t ddc_debug_tones[5];
static float32_t ddc_debug_power_sum;
static u32       ddc_debug_sample_count;
#if RBW_10K_SYNTH_DDC_MODE != RBW_10K_SYNTH_DDC_MODE_REAL_ADC
static float32_t rbw10k_synth_ddc_main_phase;
static float32_t rbw10k_synth_ddc_image_phase;
#endif

static const float32_t *comp_fir_coeffs;
static float32_t comp_fir_state[ACCUM_BUFFER_SIZE + RBW_1K_FIR_TAPS];
static arm_fir_instance_f32 comp_fir_instance;
static int       comp_fir_taps;
static int       comp_fir_skip;

#if RBW_10K_USE_FIR_DECIMATOR
static float32_t rbw10k_fir_decim_coeffs[RBW_10K_FIR_DECIMATOR_TAPS];
static float32_t rbw10k_fir_decim_hist_i[RBW_10K_FIR_DECIMATOR_TAPS];
static float32_t rbw10k_fir_decim_hist_q[RBW_10K_FIR_DECIMATOR_TAPS];
static int       rbw10k_fir_decim_write;
static int       rbw10k_fir_decim_phase;
static int       rbw10k_fir_decim_coeffs_ready;
#endif

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
static void direct_if_fft_postprocess(void);
static void report_time_domain_power(void);
static void fft_report_peak(void);

/* Sweep-path internals */
static void nco_table_build(float32_t if_hz);
static void ddc_mix_to_time_domain(volatile u16 *rx_buffer);
static void ddc_mix_to_time_domain_sweep(volatile u16 *rx_buffer);
#if RBW_10K_SYNTH_DDC_MODE != RBW_10K_SYNTH_DDC_MODE_REAL_ADC
static void ddc_generate_synthetic_10k_block(void);
#endif
static void sweep_configure_for_rbw(rbw_mode_t mode);
static void apply_compensating_fir(void);
static float32_t measure_power_dbfs_accumulated(void);
static float32_t measure_complex_power_dbfs(const float32_t *i_data,
                                            const float32_t *q_data,
                                            int len);
static float32_t measure_complex_tone_dbfs(const float32_t *i_data,
                                           const float32_t *q_data,
                                           int len,
                                           float32_t freq_hz,
                                           float32_t sample_rate_hz);
static void measure_complex_peak_dbfs(const float32_t *i_data,
                                      const float32_t *q_data,
                                      int len,
                                      float32_t sample_rate_hz,
                                      float32_t *out_peak_freq_hz,
                                      float32_t *out_peak_dbfs);
static void ddc_debug_reset(void);
#if SIGNAL_PROCESSING_DDC_DEBUG_ENABLE
static void ddc_debug_accumulate_current_block(void);
static void ddc_debug_finalize(signal_processing_peak_debug_t *out_debug);
static float32_t ddc_debug_tone_dbfs(const ddc_debug_tone_t *tone,
                                     u32 sample_count);
#endif
#if RBW_10K_USE_FIR_DECIMATOR
static float32_t rbw10k_fir_decimator_i0(float32_t x);
static void rbw10k_fir_decimator_build_coeffs(void);
static void rbw10k_fir_decimator_reset(void);
static int rbw10k_fir_decimator_process(const float32_t *i_in,
                                         const float32_t *q_in,
                                         int in_len,
                                         float32_t *i_out,
                                         float32_t *q_out,
                                         int out_capacity);
#endif

static void ddc_debug_reset(void)
{
    static const float32_t freqs_hz[5] = {
        0.0f, 10000.0f, -10000.0f, 100000.0f, -100000.0f
    };
    int i;

    ddc_debug_power_sum = 0.0f;
    ddc_debug_sample_count = 0U;
    for (i = 0; i < 5; i++) {
        float32_t step = 2.0f * PI * freqs_hz[i] / ADC_SAMPLE_RATE_HZ;

        ddc_debug_tones[i].freq_hz = freqs_hz[i];
        ddc_debug_tones[i].acc_re = 0.0f;
        ddc_debug_tones[i].acc_im = 0.0f;
        ddc_debug_tones[i].osc_re = 1.0f;
        ddc_debug_tones[i].osc_im = 0.0f;
        ddc_debug_tones[i].step_re = arm_cos_f32(step);
        ddc_debug_tones[i].step_im = arm_sin_f32(step);
    }

    peak_debug.ddc_sample_count = 0U;
    peak_debug.ddc_power_dbfs = 0.0f;
    peak_debug.ddc_dc_dbfs = 0.0f;
    peak_debug.ddc_pos10k_dbfs = 0.0f;
    peak_debug.ddc_neg10k_dbfs = 0.0f;
    peak_debug.ddc_pos100k_dbfs = 0.0f;
    peak_debug.ddc_neg100k_dbfs = 0.0f;
}

#if SIGNAL_PROCESSING_DDC_DEBUG_ENABLE
static void ddc_debug_accumulate_current_block(void)
{
    uint32_t i;
    int tone_idx;

    for (i = 0U; i < FFT_SIZE; i++) {
        float32_t sample_i = time_domain_real[i];
        float32_t sample_q = time_domain_imag[i];

        ddc_debug_power_sum += (sample_i * sample_i) + (sample_q * sample_q);
        for (tone_idx = 0; tone_idx < 5; tone_idx++) {
            ddc_debug_tone_t *tone = &ddc_debug_tones[tone_idx];
            float32_t osc_re = tone->osc_re;
            float32_t osc_im = tone->osc_im;
            float32_t next_re;
            float32_t next_im;

            tone->acc_re += (sample_i * osc_re) + (sample_q * osc_im);
            tone->acc_im += (sample_q * osc_re) - (sample_i * osc_im);

            next_re = (osc_re * tone->step_re) - (osc_im * tone->step_im);
            next_im = (osc_im * tone->step_re) + (osc_re * tone->step_im);
            tone->osc_re = next_re;
            tone->osc_im = next_im;
        }
    }

    ddc_debug_sample_count += FFT_SIZE;
    for (tone_idx = 0; tone_idx < 5; tone_idx++) {
        float32_t mag_sq = (ddc_debug_tones[tone_idx].osc_re *
                            ddc_debug_tones[tone_idx].osc_re) +
                           (ddc_debug_tones[tone_idx].osc_im *
                            ddc_debug_tones[tone_idx].osc_im);
        if (mag_sq > EPSILON) {
            float32_t inv_mag = 1.0f / sqrtf(mag_sq);
            ddc_debug_tones[tone_idx].osc_re *= inv_mag;
            ddc_debug_tones[tone_idx].osc_im *= inv_mag;
        }
    }
}

static float32_t ddc_debug_tone_dbfs(const ddc_debug_tone_t *tone,
                                     u32 sample_count)
{
    float32_t acc_re;
    float32_t acc_im;
    float32_t tone_power;

    if ((tone == 0) || (sample_count == 0U)) {
        return -120.0f;
    }

    acc_re = tone->acc_re / (float32_t)sample_count;
    acc_im = tone->acc_im / (float32_t)sample_count;
    tone_power = (acc_re * acc_re) + (acc_im * acc_im);
    if (tone_power < EPSILON) {
        tone_power = EPSILON;
    }

    return 10.0f * log10f(tone_power / FULL_SCALE_COMPLEX_POWER);
}

static void ddc_debug_finalize(signal_processing_peak_debug_t *out_debug)
{
    float32_t mean_power;

    if (out_debug == 0) {
        return;
    }

    out_debug->ddc_sample_count = ddc_debug_sample_count;
    if (ddc_debug_sample_count == 0U) {
        out_debug->ddc_power_dbfs = -120.0f;
        out_debug->ddc_dc_dbfs = -120.0f;
        out_debug->ddc_pos10k_dbfs = -120.0f;
        out_debug->ddc_neg10k_dbfs = -120.0f;
        out_debug->ddc_pos100k_dbfs = -120.0f;
        out_debug->ddc_neg100k_dbfs = -120.0f;
        return;
    }

    mean_power = ddc_debug_power_sum / (float32_t)ddc_debug_sample_count;
    if (mean_power < EPSILON) {
        mean_power = EPSILON;
    }

    out_debug->ddc_power_dbfs =
        10.0f * log10f(mean_power / FULL_SCALE_COMPLEX_POWER);
    out_debug->ddc_dc_dbfs = ddc_debug_tone_dbfs(&ddc_debug_tones[0],
                                                 ddc_debug_sample_count);
    out_debug->ddc_pos10k_dbfs = ddc_debug_tone_dbfs(&ddc_debug_tones[1],
                                                     ddc_debug_sample_count);
    out_debug->ddc_neg10k_dbfs = ddc_debug_tone_dbfs(&ddc_debug_tones[2],
                                                     ddc_debug_sample_count);
    out_debug->ddc_pos100k_dbfs = ddc_debug_tone_dbfs(&ddc_debug_tones[3],
                                                      ddc_debug_sample_count);
    out_debug->ddc_neg100k_dbfs = ddc_debug_tone_dbfs(&ddc_debug_tones[4],
                                                      ddc_debug_sample_count);
}
#endif

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
    peak_debug.current_rbw_mode = (u8)mode;

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

void signal_processing_process_direct_if_fft_frame(volatile u16 *rx_buffer)
{
    uint32_t i;

    if (rx_buffer == 0) {
        latest_spectrum_valid = 0;
        return;
    }

    for (i = 0; i < FFT_SIZE; i++) {
        float32_t norm = (float32_t)(int16_t)rx_buffer[i] / 32768.0f;

        fft_input[2U * i] = norm * hann_window[i];
        fft_input[2U * i + 1U] = 0.0f;
    }

    fft_run();
    direct_if_fft_postprocess();
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
#if RBW_10K_SYNTH_DDC_MODE != RBW_10K_SYNTH_DDC_MODE_REAL_ADC
        if (current_rbw_mode == RBW_MODE_10K) {
            ddc_generate_synthetic_10k_block();
        } else
#endif
        {
            ddc_mix_to_time_domain_sweep(rx_buffer + offset);
        }
        sweep_profile_end(SWEEP_PROFILE_SECTION_ACC_DDC);

#if SIGNAL_PROCESSING_DDC_DEBUG_ENABLE
        ddc_debug_accumulate_current_block();
#endif

        sweep_profile_begin(SWEEP_PROFILE_SECTION_ACC_CIC);
#if RBW_10K_USE_FIR_DECIMATOR
        if (current_rbw_mode == RBW_MODE_10K) {
            produced = rbw10k_fir_decimator_process(time_domain_real,
                                                    time_domain_imag,
                                                    (int)FFT_SIZE,
                                                    accum_i + accum_count,
                                                    accum_q + accum_count,
                                                    (int)ACCUM_BUFFER_SIZE - accum_count);
        } else
#endif
        {
            produced = cic_decimator_process(time_domain_real, time_domain_imag,
                                             (int)FFT_SIZE,
                                             accum_i + accum_count,
                                             accum_q + accum_count,
                                             (int)ACCUM_BUFFER_SIZE - accum_count);
        }
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

#if SIGNAL_PROCESSING_DDC_DEBUG_ENABLE
    ddc_debug_finalize(&peak_debug);
#else
    peak_debug.ddc_sample_count = 0U;
    peak_debug.ddc_power_dbfs = 0.0f;
    peak_debug.ddc_dc_dbfs = 0.0f;
    peak_debug.ddc_pos10k_dbfs = 0.0f;
    peak_debug.ddc_neg10k_dbfs = 0.0f;
    peak_debug.ddc_pos100k_dbfs = 0.0f;
    peak_debug.ddc_neg100k_dbfs = 0.0f;
#endif
    peak_debug.pre_rbw_count = (u32)accum_count;
    peak_debug.pre_rbw_power_dbfs = measure_complex_power_dbfs(accum_i, accum_q, accum_count);
#if SIGNAL_PROCESSING_PEAK_SEARCH_ENABLE
    measure_complex_peak_dbfs(accum_i, accum_q, accum_count,
                              current_decimated_sample_rate_hz,
                              &peak_debug.pre_rbw_peak_freq_hz,
                              &peak_debug.pre_rbw_peak_dbfs);
#else
    peak_debug.pre_rbw_peak_freq_hz = 0.0f;
    peak_debug.pre_rbw_peak_dbfs = peak_debug.pre_rbw_power_dbfs;
#endif

    apply_compensating_fir();
    power_dbfs = measure_power_dbfs_accumulated();
    *out_power_dbm = power_dbfs + ADC_INPUT_FULL_SCALE_DBM;

    peak_debug.post_rbw_count = (u32)accum_count;
    peak_debug.post_rbw_power_dbfs = power_dbfs;
#if SIGNAL_PROCESSING_PEAK_SEARCH_ENABLE
    measure_complex_peak_dbfs(accum_i, accum_q, accum_count,
                              current_decimated_sample_rate_hz,
                              &peak_debug.post_rbw_peak_freq_hz,
                              &peak_debug.post_rbw_peak_dbfs);
#else
    peak_debug.post_rbw_peak_freq_hz = 0.0f;
    peak_debug.post_rbw_peak_dbfs = power_dbfs;
#endif
    last_peak_debug = peak_debug;
    peak_debug_valid = 1U;
    return 0;
}

void signal_processing_reset_accumulation(void)
{
    accum_count = 0;
    peak_debug.pre_rbw_count = 0U;
    peak_debug.post_rbw_count = 0U;
    ddc_debug_reset();
    sweep_nco_phase = 0.0f;
#if RBW_10K_SYNTH_DDC_MODE != RBW_10K_SYNTH_DDC_MODE_REAL_ADC
    rbw10k_synth_ddc_main_phase = 0.0f;
    rbw10k_synth_ddc_image_phase = 0.0f;
#endif
    cic_decimator_reset();
#if RBW_10K_USE_FIR_DECIMATOR
    rbw10k_fir_decimator_reset();
#endif
}

u32 signal_processing_get_dma_samples(void)
{
    return current_dma_samples;
}

void signal_processing_set_debug_point_index(u32 point_index)
{
    peak_debug.point_index = point_index;
}

void signal_processing_get_peak_debug(signal_processing_peak_debug_t *out_debug)
{
    if (out_debug != 0) {
        *out_debug = (peak_debug_valid != 0U)
            ? last_peak_debug
            : peak_debug;
    }
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
    const rbw_filter_config_t *filter_cfg = rbw_filter_get_config(mode);

    cic_decimator_init(cfg->cic_n, cfg->cic_r);
    accum_count = 0;
    peak_debug.pre_rbw_count = 0U;
    peak_debug.post_rbw_count = 0U;
    ddc_debug_reset();
    sweep_nco_phase = 0.0f;
#if RBW_10K_SYNTH_DDC_MODE != RBW_10K_SYNTH_DDC_MODE_REAL_ADC
    rbw10k_synth_ddc_main_phase = 0.0f;
    rbw10k_synth_ddc_image_phase = 0.0f;
#endif
#if RBW_10K_USE_FIR_DECIMATOR
    rbw10k_fir_decimator_reset();
    if (mode == RBW_MODE_10K) {
        rbw10k_fir_decimator_build_coeffs();
    }
#endif

    comp_fir_coeffs = filter_cfg->coeffs;
    comp_fir_taps = (int)filter_cfg->tap_count;

    comp_fir_skip = get_rbw_skip_points(mode);

    /* Accumulation target: observe_points + skip + fir_taps margin */
    accum_target = (int)cfg->accum_target_obs + comp_fir_skip + comp_fir_taps;
    if (accum_target > (int)ACCUM_BUFFER_SIZE) {
        accum_target = (int)ACCUM_BUFFER_SIZE;
    }
#if RBW_10K_USE_FIR_DECIMATOR
    if (mode == RBW_MODE_10K) {
        current_decimated_sample_rate_hz = ADC_SAMPLE_RATE_HZ /
            (float32_t)RBW_10K_FIR_DECIMATOR_R;
    } else
#endif
    {
        current_decimated_sample_rate_hz = ADC_SAMPLE_RATE_HZ / (float32_t)cfg->cic_r;
    }

    /* Choose the largest useful controlled frame while staying inside the PL
     * Stage-1 max frame length. This reduces PS rearm overhead without moving
     * to continuous/cyclic DMA yet.
     */
    {
        u32 blocks_per_transfer = 1U;
        u32 decimated_per_block;

#if RBW_10K_USE_FIR_DECIMATOR
        if (mode == RBW_MODE_10K) {
            decimated_per_block = FFT_SIZE / RBW_10K_FIR_DECIMATOR_R;
        } else
#endif
        {
            decimated_per_block = FFT_SIZE / (u32)cfg->cic_r;
        }

        if (decimated_per_block > 0U) {
            blocks_per_transfer =
                ((u32)accum_target + decimated_per_block - 1U) /
                decimated_per_block;
        }
        if (blocks_per_transfer < 1U) {
            blocks_per_transfer = 1U;
        }
        if (blocks_per_transfer > DMA_SWEEP_MAX_BLOCKS_PER_TRANSFER) {
            blocks_per_transfer = DMA_SWEEP_MAX_BLOCKS_PER_TRANSFER;
        }

        current_dma_samples = blocks_per_transfer * FFT_SIZE;
    }

#if SIGNAL_PROCESSING_VERBOSE && RBW_10K_USE_FIR_DECIMATOR
    if (mode == RBW_MODE_10K) {
        xil_printf("RBW_10K_DECIMATOR,FIR,R=%d,TAPS=%d,CUTOFF_HZ=%d\r\n",
                   (int)RBW_10K_FIR_DECIMATOR_R,
                   (int)RBW_10K_FIR_DECIMATOR_TAPS,
                   (int)RBW_10K_FIR_DECIMATOR_CUTOFF_HZ);
    }
#endif
}

/* ── Static: compensating FIR design ─────────────────────────────── */

/* ── Static: apply compensating FIR to accumulated data ──────────── */

#if RBW_10K_USE_FIR_DECIMATOR
static float32_t rbw10k_fir_decimator_i0(float32_t x)
{
    float32_t ax = fabsf(x);
    float32_t y;

    if (ax < 3.75f) {
        y = x / 3.75f;
        y *= y;
        return 1.0f + y * (3.5156229f + y * (3.0899424f +
               y * (1.2067492f + y * (0.2659732f +
               y * (0.0360768f + y * 0.0045813f)))));
    }

    y = 3.75f / ax;
    return (expf(ax) / sqrtf(ax)) *
           (0.39894228f + y * (0.01328592f + y * (0.00225319f +
           y * (-0.00157565f + y * (0.00916281f + y * (-0.02057706f +
           y * (0.02635537f + y * (-0.01647633f + y * 0.00392377f))))))));
}

static void rbw10k_fir_decimator_build_coeffs(void)
{
    uint32_t n;
    float32_t coeff_sum = 0.0f;
    const float32_t cutoff_norm =
        RBW_10K_FIR_DECIMATOR_CUTOFF_HZ / ADC_SAMPLE_RATE_HZ;
    const float32_t center =
        0.5f * (float32_t)(RBW_10K_FIR_DECIMATOR_TAPS - 1U);
    const float32_t i0_beta =
        rbw10k_fir_decimator_i0(RBW_10K_FIR_DECIMATOR_BETA);

    if (rbw10k_fir_decim_coeffs_ready) {
        return;
    }

    for (n = 0U; n < RBW_10K_FIR_DECIMATOR_TAPS; n++) {
        float32_t k = (float32_t)n - center;
        float32_t sinc_val;
        float32_t rel = k / center;
        float32_t window_arg = 1.0f - rel * rel;
        float32_t window;

        if (fabsf(k) < 1.0e-6f) {
            sinc_val = 2.0f * cutoff_norm;
        } else {
            float32_t x = 2.0f * PI * cutoff_norm * k;
            sinc_val = arm_sin_f32(x) / (PI * k);
        }

        if (window_arg < 0.0f) {
            window_arg = 0.0f;
        }
        window = rbw10k_fir_decimator_i0(
                     RBW_10K_FIR_DECIMATOR_BETA * sqrtf(window_arg)) /
                 i0_beta;

        rbw10k_fir_decim_coeffs[n] = sinc_val * window;
        coeff_sum += rbw10k_fir_decim_coeffs[n];
    }

    if (fabsf(coeff_sum) > EPSILON) {
        for (n = 0U; n < RBW_10K_FIR_DECIMATOR_TAPS; n++) {
            rbw10k_fir_decim_coeffs[n] /= coeff_sum;
        }
    }

    rbw10k_fir_decim_coeffs_ready = 1;
}

static void rbw10k_fir_decimator_reset(void)
{
    memset(rbw10k_fir_decim_hist_i, 0, sizeof(rbw10k_fir_decim_hist_i));
    memset(rbw10k_fir_decim_hist_q, 0, sizeof(rbw10k_fir_decim_hist_q));
    rbw10k_fir_decim_write = 0;
    rbw10k_fir_decim_phase = 0;
}

static int rbw10k_fir_decimator_process(const float32_t *i_in,
                                         const float32_t *q_in,
                                         int in_len,
                                         float32_t *i_out,
                                         float32_t *q_out,
                                         int out_capacity)
{
    int i;
    int produced = 0;

    rbw10k_fir_decimator_build_coeffs();

    for (i = 0; i < in_len; i++) {
        rbw10k_fir_decim_hist_i[rbw10k_fir_decim_write] = i_in[i];
        rbw10k_fir_decim_hist_q[rbw10k_fir_decim_write] = q_in[i];

        rbw10k_fir_decim_write++;
        if (rbw10k_fir_decim_write >= (int)RBW_10K_FIR_DECIMATOR_TAPS) {
            rbw10k_fir_decim_write = 0;
        }

        rbw10k_fir_decim_phase++;
        if (rbw10k_fir_decim_phase >= (int)RBW_10K_FIR_DECIMATOR_R) {
            rbw10k_fir_decim_phase = 0;

            if (produced < out_capacity) {
                uint32_t tap;
                int hist_index = rbw10k_fir_decim_write - 1;
                float32_t acc_i_val = 0.0f;
                float32_t acc_q_val = 0.0f;

                if (hist_index < 0) {
                    hist_index = (int)RBW_10K_FIR_DECIMATOR_TAPS - 1;
                }

                for (tap = 0U; tap < RBW_10K_FIR_DECIMATOR_TAPS; tap++) {
                    float32_t coeff = rbw10k_fir_decim_coeffs[tap];

                    acc_i_val += coeff * rbw10k_fir_decim_hist_i[hist_index];
                    acc_q_val += coeff * rbw10k_fir_decim_hist_q[hist_index];

                    hist_index--;
                    if (hist_index < 0) {
                        hist_index = (int)RBW_10K_FIR_DECIMATOR_TAPS - 1;
                    }
                }

                i_out[produced] = acc_i_val;
                q_out[produced] = acc_q_val;
                produced++;
            }
        }
    }

    return produced;
}
#endif

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

static float32_t measure_complex_power_dbfs(const float32_t *i_data,
                                            const float32_t *q_data,
                                            int len)
{
    int i;
    float32_t power_sum = 0.0f;
    float32_t mean_power;

    if ((i_data == 0) || (q_data == 0) || (len < 1)) {
        return -120.0f;
    }

    for (i = 0; i < len; i++) {
        power_sum += i_data[i] * i_data[i];
        power_sum += q_data[i] * q_data[i];
    }

    mean_power = power_sum / (float32_t)len;
    if (mean_power < EPSILON) {
        mean_power = EPSILON;
    }

    return 10.0f * log10f(mean_power / FULL_SCALE_COMPLEX_POWER);
}

static float32_t measure_complex_tone_dbfs(const float32_t *i_data,
                                           const float32_t *q_data,
                                           int len,
                                           float32_t freq_hz,
                                           float32_t sample_rate_hz)
{
    int i;
    float32_t acc_re = 0.0f;
    float32_t acc_im = 0.0f;
    float32_t phase = 0.0f;
    float32_t phase_step;
    float32_t tone_power;

    if ((i_data == 0) || (q_data == 0) || (len < 1) || (sample_rate_hz <= 0.0f)) {
        return -120.0f;
    }

    phase_step = 2.0f * PI * freq_hz / sample_rate_hz;
    for (i = 0; i < len; i++) {
        float32_t c = arm_cos_f32(phase);
        float32_t sn = arm_sin_f32(phase);

        acc_re += (i_data[i] * c) + (q_data[i] * sn);
        acc_im += (q_data[i] * c) - (i_data[i] * sn);

        phase += phase_step;
        if (phase >= 2.0f * PI) {
            phase -= 2.0f * PI;
        } else if (phase <= -2.0f * PI) {
            phase += 2.0f * PI;
        }
    }

    acc_re /= (float32_t)len;
    acc_im /= (float32_t)len;
    tone_power = (acc_re * acc_re) + (acc_im * acc_im);
    if (tone_power < EPSILON) {
        tone_power = EPSILON;
    }

    return 10.0f * log10f(tone_power / FULL_SCALE_COMPLEX_POWER);
}

static void measure_complex_peak_dbfs(const float32_t *i_data,
                                      const float32_t *q_data,
                                      int len,
                                      float32_t sample_rate_hz,
                                      float32_t *out_peak_freq_hz,
                                      float32_t *out_peak_dbfs)
{
    float32_t freq_hz;
    float32_t best_freq_hz = 0.0f;
    float32_t best_dbfs = -120.0f;

    if (out_peak_freq_hz != 0) {
        *out_peak_freq_hz = 0.0f;
    }
    if (out_peak_dbfs != 0) {
        *out_peak_dbfs = -120.0f;
    }
    if ((i_data == 0) || (q_data == 0) || (len < 1) || (sample_rate_hz <= 0.0f)) {
        return;
    }

    for (freq_hz = -200000.0f; freq_hz <= 200000.0f; freq_hz += 2000.0f) {
        float32_t tone_dbfs = measure_complex_tone_dbfs(i_data, q_data, len,
                                                        freq_hz, sample_rate_hz);
        if (tone_dbfs > best_dbfs) {
            best_dbfs = tone_dbfs;
            best_freq_hz = freq_hz;
        }
    }

    if (out_peak_freq_hz != 0) {
        *out_peak_freq_hz = best_freq_hz;
    }
    if (out_peak_dbfs != 0) {
        *out_peak_dbfs = best_dbfs;
    }
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

#if RBW_10K_SYNTH_DDC_MODE != RBW_10K_SYNTH_DDC_MODE_REAL_ADC
/* Temporary diagnostic synthesis before the 10 kHz FIR decimator.
 * Mode 2 models a real 40.100 MHz ADC tone mixed by a 40 MHz complex NCO:
 * +100 kHz desired term plus the -80.100 MHz image term.
 * Mode 3 resets synthetic phase at every DMA/FFT block boundary to simulate
 * DMA rearm / block-to-block phase discontinuity; FIR decimator state is not
 * reset here, so this tests discontinuous input with continuous filter
 * history. */
static void ddc_generate_synthetic_10k_block(void)
{
    uint32_t i;
    float32_t main_phase = rbw10k_synth_ddc_main_phase;
    float32_t image_phase = rbw10k_synth_ddc_image_phase;
    const float32_t main_step =
        2.0f * PI * RBW_10K_SYNTH_DDC_MAIN_FREQ_HZ / ADC_SAMPLE_RATE_HZ;
    const float32_t image_step =
        2.0f * PI * RBW_10K_SYNTH_DDC_IMAGE_FREQ_HZ / ADC_SAMPLE_RATE_HZ;
    const uint8_t include_image =
        (RBW_10K_SYNTH_DDC_MODE == RBW_10K_SYNTH_DDC_MODE_REAL_IMAGE) ||
        (RBW_10K_SYNTH_DDC_MODE == RBW_10K_SYNTH_DDC_MODE_REAL_IMAGE_BLOCK_RESET);

    if (RBW_10K_SYNTH_DDC_MODE ==
        RBW_10K_SYNTH_DDC_MODE_REAL_IMAGE_BLOCK_RESET) {
        main_phase = 0.0f;
        image_phase = 0.0f;
    }

    for (i = 0; i < FFT_SIZE; i++) {
        float32_t sample_i =
            RBW_10K_SYNTH_DDC_MAIN_AMPLITUDE * arm_cos_f32(main_phase);
        float32_t sample_q =
            RBW_10K_SYNTH_DDC_MAIN_AMPLITUDE * arm_sin_f32(main_phase);

        if (include_image) {
            sample_i += RBW_10K_SYNTH_DDC_IMAGE_AMPLITUDE *
                        arm_cos_f32(image_phase);
            sample_q += RBW_10K_SYNTH_DDC_IMAGE_AMPLITUDE *
                        arm_sin_f32(image_phase);
        }

        time_domain_real[i] = sample_i;
        time_domain_imag[i] = sample_q;

        main_phase += main_step;
        image_phase += image_step;
        if (main_phase >= 2.0f * PI) {
            main_phase -= 2.0f * PI;
        } else if (main_phase < 0.0f) {
            main_phase += 2.0f * PI;
        }
        if (image_phase >= 2.0f * PI) {
            image_phase -= 2.0f * PI;
        } else if (image_phase < 0.0f) {
            image_phase += 2.0f * PI;
        }
    }

    rbw10k_synth_ddc_main_phase = main_phase;
    rbw10k_synth_ddc_image_phase = image_phase;
}
#endif

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

static void direct_if_fft_postprocess(void)
{
    uint32_t i;

    for (i = 0; i < SPECTRUM_BINS; i++) {
        float32_t val;

        if (i == 0U) {
            val = fft_mag[i] / (float32_t)FFT_SIZE;
        } else {
            val = (2.0f * fft_mag[i]) / (float32_t)FFT_SIZE;
        }

        if (val < EPSILON) {
            val = EPSILON;
        }

        latest_spectrum_dbfs[i] = 20.0f * log10f(val);
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
