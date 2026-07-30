#ifndef REALTIME_IF_FFT_H
#define REALTIME_IF_FFT_H

#include <stdint.h>

/*
 * Stage-1 realtime IF FFT contract.
 *
 * This module deliberately has no DMA, LO, UART, protocol, or calibration
 * ownership.  Its amplitudes are the existing Hann FFT's raw dBFS values;
 * they are not dBm and must not be presented as calibrated power.
 */
#define REALTIME_IF_FFT_CONTRACT_VERSION       1U
#define REALTIME_IF_FFT_SIZE                   4096U
#define REALTIME_IF_FFT_ADC_SAMPLE_RATE_HZ     130000000U
#define REALTIME_IF_FFT_IF_CENTER_HZ           40000000U
#define REALTIME_IF_FFT_FIRST_BIN              1103U
#define REALTIME_IF_FFT_BIN_COUNT              315U
#define REALTIME_IF_FFT_CENTER_MIN_HZ          50000000ULL
#define REALTIME_IF_FFT_CENTER_MAX_HZ          1500000000ULL

typedef enum {
    REALTIME_IF_FFT_WINDOW_HANN = 1U
} realtime_if_fft_window_t;

typedef enum {
    REALTIME_IF_FFT_AMPLITUDE_RAW_DBFS = 1U
} realtime_if_fft_amplitude_unit_t;

typedef struct {
    /* Fixed RF centre selected by a future engine; no LO is set here. */
    uint64_t center_frequency_hz;
} realtime_if_fft_config_t;

typedef struct {
    uint8_t contract_version;
    uint8_t window_id;
    uint8_t amplitude_unit;
    uint8_t reserved0;
    uint32_t trace_id;
    uint64_t center_frequency_hz;
    uint32_t adc_sample_rate_hz;
    uint32_t fft_size;
    uint16_t first_bin;
    uint16_t bin_count;
    float amplitude_dbfs[REALTIME_IF_FFT_BIN_COUNT];
} realtime_if_fft_trace_t;

/* RF frequency for FFT bin k: Fc + k * 130 MHz / 4096 - 40 MHz. */
double realtime_if_fft_bin_rf_hz(uint64_t center_frequency_hz, uint16_t bin);

/* Populate metadata and copy bins 1103..1417 from a 2048-bin dBFS spectrum. */
int realtime_if_fft_build_trace(const realtime_if_fft_config_t *config,
                                uint32_t trace_id,
                                const float *spectrum_dbfs,
                                uint16_t spectrum_bin_count,
                                realtime_if_fft_trace_t *out_trace);

/*
 * DSP-only adapter for a raw 4096-sample ADC frame. It reuses the existing
 * Direct-IF Hann/4096-point FFT and then applies the fixed trace contract.
 * The caller is responsible for signal_processing_init() and all hardware
 * ownership; Stage 1 does not call this from main or any DMA callback.
 */
int realtime_if_fft_process_raw_adc_frame(volatile uint16_t *raw_adc_samples,
                                          const realtime_if_fft_config_t *config,
                                          uint32_t trace_id,
                                          realtime_if_fft_trace_t *out_trace);

#endif
