#include "realtime_if_fft.h"

#include <signal_processing.h>

#include <string.h>

#define REALTIME_IF_FFT_SOURCE_BINS (REALTIME_IF_FFT_SIZE / 2U)

double realtime_if_fft_bin_rf_hz(uint64_t center_frequency_hz, uint16_t bin)
{
    return (double)center_frequency_hz +
           ((double)bin * (double)REALTIME_IF_FFT_ADC_SAMPLE_RATE_HZ /
            (double)REALTIME_IF_FFT_SIZE) -
           (double)REALTIME_IF_FFT_IF_CENTER_HZ;
}

int realtime_if_fft_build_trace(const realtime_if_fft_config_t *config,
                                uint32_t trace_id,
                                const float *spectrum_dbfs,
                                uint16_t spectrum_bin_count,
                                realtime_if_fft_trace_t *out_trace)
{
    if ((config == 0) || (spectrum_dbfs == 0) || (out_trace == 0) ||
        (config->center_frequency_hz < REALTIME_IF_FFT_CENTER_MIN_HZ) ||
        (config->center_frequency_hz > REALTIME_IF_FFT_CENTER_MAX_HZ) ||
        (spectrum_bin_count <
         (REALTIME_IF_FFT_FIRST_BIN + REALTIME_IF_FFT_BIN_COUNT))) {
        return -1;
    }

    memset(out_trace, 0, sizeof(*out_trace));
    out_trace->contract_version = REALTIME_IF_FFT_CONTRACT_VERSION;
    out_trace->window_id = REALTIME_IF_FFT_WINDOW_HANN;
    out_trace->amplitude_unit = REALTIME_IF_FFT_AMPLITUDE_RAW_DBFS;
    out_trace->trace_id = trace_id;
    out_trace->center_frequency_hz = config->center_frequency_hz;
    out_trace->adc_sample_rate_hz = REALTIME_IF_FFT_ADC_SAMPLE_RATE_HZ;
    out_trace->fft_size = REALTIME_IF_FFT_SIZE;
    out_trace->first_bin = REALTIME_IF_FFT_FIRST_BIN;
    out_trace->bin_count = REALTIME_IF_FFT_BIN_COUNT;
    memcpy(out_trace->amplitude_dbfs,
           &spectrum_dbfs[REALTIME_IF_FFT_FIRST_BIN],
           sizeof(out_trace->amplitude_dbfs));
    return 0;
}

int realtime_if_fft_process_raw_adc_frame(volatile uint16_t *raw_adc_samples,
                                          const realtime_if_fft_config_t *config,
                                          uint32_t trace_id,
                                          realtime_if_fft_trace_t *out_trace)
{
    static float spectrum_dbfs[REALTIME_IF_FFT_SOURCE_BINS];
    unsigned short copied_bins = 0U;

    if ((raw_adc_samples == 0) || (config == 0) || (out_trace == 0) ||
        (config->center_frequency_hz < REALTIME_IF_FFT_CENTER_MIN_HZ) ||
        (config->center_frequency_hz > REALTIME_IF_FFT_CENTER_MAX_HZ)) {
        return -1;
    }

    signal_processing_process_direct_if_fft_frame((volatile u16 *)raw_adc_samples);
    if (signal_processing_get_latest_spectrum(spectrum_dbfs,
                                              REALTIME_IF_FFT_SOURCE_BINS,
                                              &copied_bins) != 0) {
        return -1;
    }

    return realtime_if_fft_build_trace(config, trace_id, spectrum_dbfs,
                                       (uint16_t)copied_bins, out_trace);
}
