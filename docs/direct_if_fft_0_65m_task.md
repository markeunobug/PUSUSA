# Direct IF 0-65 MHz FFT Task

Updated: 2026-05-25

## 1. Goal

When the RF frontend path is set to `direct_if`, add an FFT display path for the current LF-65 MHz ADC signal:

- capture one ADC frame from LTC2208
- run a 4096-point FFT
- return a fixed 0-65 MHz spectrum trace to the host
- keep the existing mixer-chain sweep path unchanged

This feature is intended for the low-frequency direct IF path. The normal mixer-chain path should continue to use the current sweep engine:

```text
Mixer chain:
LO sweep -> 40 MHz IF -> DDC/RBW -> time-domain power -> streamed sweep points

Direct IF:
ADC raw 0-65 MHz -> 4096-point FFT -> streamed fixed-frequency FFT bins
```

## 2. Feasibility

The task is feasible and relatively low risk if implemented as a separate direct-IF branch.

Evidence from current code:

- `app_config.h` already defines `FFT_SIZE = 4096`, `ADC_SAMPLE_RATE_HZ = 130000000.0f`, and `SPECTRUM_BINS = FFT_SIZE / 2`.
- `signal_processing.c` already keeps the legacy FFT buffers and CMSIS-DSP call:
  - `fft_input[2 * FFT_SIZE]`
  - `fft_mag[FFT_SIZE]`
  - `hann_window[FFT_SIZE]`
  - `arm_cfft_f32(&arm_cfft_sR_f32_len4096, ...)`
- `signal_processing_get_latest_spectrum()` and `signal_processing_get_bin_frequency_hz()` already expose FFT bin magnitudes and frequencies.
- `rf_frontend.h/.c` already has `RF_PATH_DIRECT_IF` and `RF_PATH_MIXER_CHAIN`.
- The host already supports segmented `SPECTRUM_DATA(0x82)` frames, so the firmware can stream one FFT bin per frame without needing a huge UART frame.

Important detail: with `Fs = 130 MSPS` and a 4096-point real-input FFT, the usable one-sided spectrum is:

```text
0 Hz to Fs / 2 = 65 MHz
bin spacing = 130 MHz / 4096 = 31.73828125 kHz
one-sided bins = 2048 bins for current SPECTRUM_BINS
```

If the UI must include the exact Nyquist endpoint at 65.000 MHz, extend output to 2049 bins by including bin `FFT_SIZE / 2`. If this is not visually required, the existing 2048-bin convention reaches about `64.968 MHz`, which is usually acceptable for a fixed 0-65 MHz chart.

## 3. Key Design Choice

Do not reuse the current DDC/RBW FFT path for direct IF as-is.

Current `signal_processing_process_frame()` does:

```text
raw ADC -> DDC around current IF -> RBW LPF -> complex FFT
```

That is correct for the 40 MHz IF debug path, but wrong for LF-65 MHz direct IF because it shifts/filter-limits the raw ADC spectrum. The direct-IF FFT needs a raw real-input path:

```text
raw ADC samples -> normalize -> Hann window -> 4096-point FFT -> one-sided magnitude
```

The implementation can still reuse the existing static FFT buffers and `fft_run()`/postprocess logic, but it needs a new entry point that bypasses DDC and RBW filtering at runtime.

## 4. Firmware Implementation Plan

### 4.1 Add a raw direct-IF FFT entry point

Files:

- `code/pusu_20260516/vitis/pusu_20260516/src/signal_processing.c`
- `code/pusu_20260516/vitis/pusu_20260516/src/signal_processing.h`

Add:

```c
void signal_processing_process_direct_if_fft_frame(volatile u16 *rx_buffer);
```

Behavior:

1. Validate `rx_buffer`.
2. For `i = 0..4095`:
   - cast sample to signed ADC value
   - normalize by `32768.0f`
   - apply `hann_window[i]`
   - write `fft_input[2*i] = normalized * hann`
   - write `fft_input[2*i + 1] = 0.0f`
3. Run `arm_cfft_f32`.
4. Convert the first `SPECTRUM_BINS` bins to dBFS using the existing style.
5. Set `latest_spectrum_valid = 1`.

Recommended magnitude scaling for first version:

```text
DC bin:        mag / FFT_SIZE
non-DC bins:  2 * mag / FFT_SIZE
```

Avoid the extra second `* 2.0f` currently present in `fft_postprocess()` unless measurement confirms it is compensating for a known analog/digital gain term. For first bring-up, consistency and trace shape matter more than absolute amplitude; absolute calibration can follow.

### 4.2 Add a direct-IF FFT provider branch

File:

- `code/pusu_20260516/vitis/pusu_20260516/src/main.c`

Modify `protocol_spectrum_provider()`:

```text
if config->rf_frontend.path_mode == RF_PATH_DIRECT_IF:
    run direct-IF FFT capture/provider
else:
    run existing sweep_engine path
```

Add a helper, for example:

```c
static int protocol_direct_if_fft_provider(
    spectrum_point_t *points,
    unsigned short max_points,
    unsigned short *out_point_count);
```

Provider flow:

1. Reject if phase-noise engine is active.
2. Stop/release background DMA capture.
3. `dma_capture_reset()`.
4. `dma_capture_start(TRANSFER_LENGTH)`.
5. Wait for `dma_capture_frame_ready()` with a timeout.
6. Call `signal_processing_process_direct_if_fft_frame(dma_capture_get_rx_buffer())`.
7. Call `signal_processing_get_latest_spectrum(...)`.
8. Stream bins as `SPECTRUM_DATA(0x82)` using `device_protocol_stream_spectrum_point()`.
9. Frequency for bin `i`:

```c
freq_hz = (uint32_t)((float)i * ADC_SAMPLE_RATE_HZ / (float)FFT_SIZE);
```

10. Total points should be the FFT bin count, not the requested sweep point count.
11. Resume background capture when done or on error.

The direct-IF branch should ignore `start_hz`, `stop_hz`, RBW, and sweep point count for the actual returned x-axis. It always returns fixed 0-65 MHz bins.

### 4.3 Keep the existing sweep path unchanged

Do not change:

- `sweep_engine.c`
- `sweep_plan.c`
- mixer-chain LO set/wait behavior
- RBW accumulation path
- phase-noise engine

The only branch condition should be the RF frontend path mode.

## 5. Protocol Plan

Short-term, reuse `GET_SPECTRUM(0x06)` and `SPECTRUM_DATA(0x82)`:

- Host requests `GET_SPECTRUM`.
- Firmware checks `path_mode`.
- In `direct_if`, firmware returns FFT bins as normal spectrum points.
- In `mixer_chain`, firmware returns existing sweep points.

This avoids adding a new command in the first version.

Recommended documentation update:

- Update `docs/uart_protocol_summary.md` to state that `GET_SPECTRUM` returns either:
  - sweep trace in mixer-chain mode
  - fixed 0-65 MHz FFT trace in direct-IF mode

Optional later protocol cleanup:

- Add `GET_FFT_SPECTRUM` and `FFT_SPECTRUM_DATA` if the host needs to display FFT metadata such as FFT size, sample rate, window type, and calibration flags.

## 6. Host Implementation Plan

Files:

- `host_computer/flutter_pusu/lib/main.dart`
- `host_computer/flutter_pusu/lib/serial_protocol.dart`

Minimum host changes:

1. When `_rfFrontendConfig.pathMode == RfPathMode.directIf`, treat the chart as fixed FFT mode.
2. On spectrum request, do not rely on user start/stop fields for direct-IF x-axis.
3. Display returned points directly; the firmware will send `freq_hz` from 0 to 65 MHz.
4. Request timeout can be much shorter in direct IF, for example 3-10 seconds, because no LO sweep is needed.
5. Disable or visually de-emphasize RBW/sweep point controls while in direct IF if they do not affect the FFT result.

Suggested UI behavior:

```text
Direct IF selected:
    x-axis = 0-65 MHz
    request = single 4096-point FFT capture
    displayed points = firmware FFT bins, usually 2048

Mixer chain selected:
    x-axis = configured start/stop
    request = existing sweep
```

The existing segmented parser in `serial_protocol.dart` can parse the data without changes if firmware streams the FFT bins through `SPECTRUM_DATA(0x82)`.

## 7. Testing Plan

### 7.1 Firmware smoke tests

1. Boot firmware and confirm `GET_STATUS` still responds.
2. Set RF frontend to direct IF:

```text
SET_RF_FRONTEND(lna=bypass, path=direct_if, atten_code=safe value)
```

3. Request spectrum.
4. Confirm:
   - no LO sweep occurs
   - one DMA frame is captured
   - returned frequencies are fixed from 0 toward 65 MHz
   - `done=1` appears on the final streamed point

### 7.2 Signal tests

Inject known LF signals into the direct IF path:

| Input | Expected FFT result |
|---:|---|
| 1 MHz | peak near 1 MHz |
| 10 MHz | peak near 10 MHz |
| 40 MHz | peak near 40 MHz |
| 60 MHz | peak near 60 MHz |

Acceptance:

- Peak bin frequency error should be within one bin, about `31.74 kHz`.
- Amplitude can be marked provisional until calibration is done.
- Noise floor should be stable across repeated captures.

### 7.3 Regression tests

After direct-IF FFT works, switch back to mixer-chain mode and confirm:

- existing sweep still runs
- RBW modes still work
- phase-noise mode still rejects/pauses normal spectrum requests as before
- status counters still update

## 8. Risks And Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Direct-IF FFT accidentally uses DDC/RBW path | Wrong 0-65 MHz spectrum | Add a separate raw FFT entry point and name it explicitly |
| UART throughput for 2048 bins is slow | Slower refresh | Stream segmented points as today; later batch multiple bins per frame if needed |
| Existing `spectrum_point_t.freq_hz` is `uint32_t` | Fine for 0-65 MHz | No change needed |
| Amplitude scaling may not be calibrated | dBFS/dBm may be approximate | Label first version as FFT amplitude provisional; calibrate later |
| Background DMA conflicts with one-shot capture | Intermittent DMA failures | Release/reset DMA before one-shot FFT and resume background capture after |
| Host controls imply sweep behavior in direct IF | User confusion | Fixed x-axis and shorter timeout when direct IF is selected |

## 9. Acceptance Criteria

- Selecting `direct_if` and requesting spectrum returns an FFT trace without LO sweeping.
- FFT uses 4096 ADC samples.
- Chart x-axis is fixed 0-65 MHz.
- Returned trace has approximately 2048 one-sided bins, or 2049 if Nyquist bin support is added.
- A known input tone appears at the correct frequency bin.
- Switching back to mixer-chain mode preserves the existing sweep behavior.
- `docs/uart_protocol_summary.md` documents the mode-dependent `GET_SPECTRUM` behavior.

## 10. Suggested Task Breakdown

1. Firmware DSP: add raw direct-IF FFT entry point.
2. Firmware provider: branch `GET_SPECTRUM` by `RF_PATH_DIRECT_IF`.
3. Host behavior: fixed direct-IF x-axis and shorter timeout.
4. Protocol docs: document mode-dependent spectrum behavior.
5. Serial test tool: add a direct-IF FFT capture smoke test.
6. Hardware validation: inject 1/10/40/60 MHz tones and record results.

