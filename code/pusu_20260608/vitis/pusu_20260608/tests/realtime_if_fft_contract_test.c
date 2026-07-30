#include "realtime_if_fft.h"

#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

static float mocked_spectrum[REALTIME_IF_FFT_SIZE / 2U];
static int process_call_count;

/* Host-test mocks for the narrow signal_processing dependency. */
void signal_processing_process_direct_if_fft_frame(volatile uint16_t *samples)
{
    assert(samples != 0);
    ++process_call_count;
}

int signal_processing_get_latest_spectrum(float *out, unsigned short max_bins,
                                          unsigned short *out_count)
{
    assert(max_bins >= (REALTIME_IF_FFT_SIZE / 2U));
    memcpy(out, mocked_spectrum, sizeof(mocked_spectrum));
    *out_count = REALTIME_IF_FFT_SIZE / 2U;
    return 0;
}

static void assert_near(double actual, double expected, double tolerance)
{
    assert(fabs(actual - expected) <= tolerance);
}

static void test_bin_selection_and_metadata(void)
{
    realtime_if_fft_config_t config = { .center_frequency_hz = 1000000000ULL };
    realtime_if_fft_trace_t trace;
    float spectrum[REALTIME_IF_FFT_SIZE / 2U];
    uint16_t i;

    for (i = 0U; i < REALTIME_IF_FFT_SIZE / 2U; ++i) {
        spectrum[i] = (float)i - 2000.0f;
    }

    assert(realtime_if_fft_build_trace(&config, 42U, spectrum,
                                       REALTIME_IF_FFT_SIZE / 2U, &trace) == 0);
    assert(trace.contract_version == REALTIME_IF_FFT_CONTRACT_VERSION);
    assert(trace.window_id == REALTIME_IF_FFT_WINDOW_HANN);
    assert(trace.amplitude_unit == REALTIME_IF_FFT_AMPLITUDE_RAW_DBFS);
    assert(trace.trace_id == 42U);
    assert(trace.center_frequency_hz == 1000000000ULL);
    assert(trace.adc_sample_rate_hz == REALTIME_IF_FFT_ADC_SAMPLE_RATE_HZ);
    assert(trace.fft_size == REALTIME_IF_FFT_SIZE);
    assert(trace.first_bin == 1103U);
    assert(trace.bin_count == 315U);
    assert(trace.amplitude_dbfs[0] == spectrum[1103U]);
    assert(trace.amplitude_dbfs[314U] == spectrum[1417U]);
}

static void test_frequency_mapping_is_ascending(void)
{
    const uint64_t fc = 1000000000ULL;
    const double spacing = 130000000.0 / 4096.0;
    const double first = realtime_if_fft_bin_rf_hz(fc, 1103U);
    const double last = realtime_if_fft_bin_rf_hz(fc, 1417U);

    assert_near(first, (double)fc + 1103.0 * spacing - 40000000.0, 1e-6);
    assert_near(last, (double)fc + 1417.0 * spacing - 40000000.0, 1e-6);
    assert_near(realtime_if_fft_bin_rf_hz(fc, 1104U) - first, spacing, 1e-6);
    assert(last > first);
    /* The selected FFT-bin centres lie inside, rather than exactly at, Fc +/-5 MHz. */
    assert(first > (double)fc - 5000000.0);
    assert(last < (double)fc + 5000000.0);
}

static void test_rejects_short_input_and_processes_raw_adapter(void)
{
    realtime_if_fft_config_t config = { .center_frequency_hz = 50000000ULL };
    realtime_if_fft_trace_t trace;
    uint16_t samples[REALTIME_IF_FFT_SIZE] = {0};
    uint16_t i;

    assert(realtime_if_fft_build_trace(&config, 1U, mocked_spectrum, 1417U,
                                       &trace) == -1);
    for (i = 0U; i < REALTIME_IF_FFT_SIZE / 2U; ++i) {
        mocked_spectrum[i] = (float)i;
    }
    assert(realtime_if_fft_process_raw_adc_frame(samples, &config, 7U, &trace) == 0);
    assert(process_call_count == 1);
    assert(trace.amplitude_dbfs[0] == 1103.0f);
    assert(trace.amplitude_dbfs[314U] == 1417.0f);
}

static void test_rf_center_range(void)
{
    realtime_if_fft_config_t config = {
        .center_frequency_hz = REALTIME_IF_FFT_CENTER_MIN_HZ
    };
    realtime_if_fft_trace_t trace;
    float spectrum[REALTIME_IF_FFT_SIZE / 2U] = {0};
    uint16_t samples[REALTIME_IF_FFT_SIZE] = {0};
    int calls_before;

    assert(realtime_if_fft_build_trace(&config, 1U, spectrum,
                                       REALTIME_IF_FFT_SIZE / 2U, &trace) == 0);
    config.center_frequency_hz = REALTIME_IF_FFT_CENTER_MAX_HZ;
    assert(realtime_if_fft_build_trace(&config, 2U, spectrum,
                                       REALTIME_IF_FFT_SIZE / 2U, &trace) == 0);

    config.center_frequency_hz = REALTIME_IF_FFT_CENTER_MIN_HZ - 1U;
    assert(realtime_if_fft_build_trace(&config, 3U, spectrum,
                                       REALTIME_IF_FFT_SIZE / 2U, &trace) == -1);
    calls_before = process_call_count;
    assert(realtime_if_fft_process_raw_adc_frame(samples, &config, 3U, &trace) == -1);
    assert(process_call_count == calls_before);

    config.center_frequency_hz = REALTIME_IF_FFT_CENTER_MAX_HZ + 1U;
    assert(realtime_if_fft_build_trace(&config, 4U, spectrum,
                                       REALTIME_IF_FFT_SIZE / 2U, &trace) == -1);
}

int main(void)
{
    test_bin_selection_and_metadata();
    test_frequency_mapping_is_ascending();
    test_rejects_short_input_and_processes_raw_adapter();
    test_rf_center_range();
    puts("realtime_if_fft_contract_test: PASS");
    return 0;
}
