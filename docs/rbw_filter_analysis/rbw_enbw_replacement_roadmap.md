# RBW ENBW Replacement Roadmap

Updated: 2026-06-01

## Objective

Replace the current runtime-generated Hamming-sinc RBW FIR path with an
offline-designed, ENBW-accurate RBW implementation.

Primary definition:

```text
Nominal RBW = actual ENBW of the complete DDC -> CIC -> FIR measurement path
```

## Step 1: MATLAB Final Candidate Parameters

Owner: MATLAB offline design task.

Write scope:

```text
docs/rbw_filter_analysis/matlab/
tools/matlab/
```

No firmware `.c` or `.h` files should be changed in this step.

Tasks:

1. Keep the current Hamming-sinc design as the regression baseline.
2. Add cutoff/design sweeps for each RBW mode.
3. Evaluate at least these candidate methods:
   - Hamming-sinc with tuned cutoff
   - Kaiser-window FIR
   - Parks-McClellan / equiripple FIR, if MATLAB toolbox support is available
4. Evaluate both relevant profiles:
   - `firmware_current`
   - `alias_rework_1k`, where 1 kHz RBW uses `R=1300`
5. For every mode and method, compute complete-chain metrics:
   - ENBW
   - ENBW/RBW
   - ENBW correction dB
   - -3 dB bandwidth
   - -6 dB bandwidth
   - passband flatness over `0 .. 0.4*RBW`
   - response at `0.5x`, `1x`, `2x`, `5x`, and `10x RBW`
   - finite-window alias risk at important offsets
6. Select the best candidate per RBW mode using the acceptance targets in
   `rbw_enbw_design_spec.md`.

Acceptance target for this step:

```text
0.95 <= ENBW/RBW <= 1.05
passband flatness <= +/- 0.2 dB over 0 .. 0.4*RBW
response at 2*RBW <= -60 dB
response at 5*RBW <= -80 dB
1 kHz RBW candidate must not fold 10 kHz / 10.2 kHz offsets into the passband
```

Expected outputs:

```text
docs/rbw_filter_analysis/matlab/rbw_candidate_metrics.csv
docs/rbw_filter_analysis/matlab/rbw_candidate_metrics.md
docs/rbw_filter_analysis/matlab/rbw_candidate_coefficients_float.csv
docs/rbw_filter_analysis/matlab/rbw_candidate_selection.md
docs/rbw_filter_analysis/matlab/rbw_candidate_response_<mode>.csv
docs/rbw_filter_analysis/matlab/rbw_candidate_response_<mode>.png
```

The selection report should clearly mark each mode as `PASS`, `NEEDS_TAPS`,
`NEEDS_DECIMATION_REWORK`, or `FAIL`.

## Step 2: Freeze the Design Result

Once Step 1 produces candidates, choose one coefficient set per RBW mode and
freeze the exact metrics and coefficient files.

Required frozen artifacts:

```text
rbw_enbw_metrics.csv
rbw_enbw_metrics.md
rbw_coefficients_float.csv
response plots and CSVs for every RBW mode
```

The frozen artifacts become the source of truth for firmware conversion.

## Step 3: Convert MATLAB Coefficients to Firmware Tables

Add fixed coefficient tables, for example:

```text
code/pusu_20260516/vitis/pusu_20260516/src/rbw_filter_coeffs.h
code/pusu_20260516/vitis/pusu_20260516/src/rbw_filter_coeffs.c
```

Each mode should expose:

```text
FIR coefficient pointer
FIR tap count
actual ENBW Hz
ENBW correction dB
CIC R/N
observe points
skip points
```

## Step 4: Replace Runtime FIR Generation

Update the sweep RBW path in `signal_processing.c` so it no longer generates
Hamming-window sinc coefficients at runtime.

Target direction:

```text
old: compensating_fir_init(cutoff_hz, taps)
new: rbw_filter_get_coeffs(mode, &coeffs, &tap_count, &enbw_hz)
```

The FIR application path may still use `arm_fir_f32`; only the coefficient
source should change.

## Step 5: Update Buffer and Timing Limits

If the selected MATLAB design requires larger tap counts, update:

```text
RBW_*_FIR_TAPS
ACCUM_BUFFER_SIZE
comp_fir_state sizing
accum_target = observe + skip + taps
```

Keep:

```text
first_valid = taps - 1 + skip
out_len > 0
accum_target <= ACCUM_BUFFER_SIZE
```

## Step 6: Use Actual ENBW in Density Math

Any dBm/Hz or dBc/Hz path must use actual ENBW, not nominal RBW.

```text
density = measured_power_dbm - 10*log10(actual_enbw_hz)
```

If a legacy display still uses nominal RBW, apply:

```text
correction_db = 10*log10(actual_enbw_hz / nominal_rbw_hz)
```

## Step 7: Reverse Verification from Firmware Coefficients

After C tables are generated, re-import the firmware coefficient tables into
MATLAB or Python and recompute all metrics.

This catches:

```text
coefficient copy errors
float formatting errors
wrong tap count
wrong mode mapping
quantization drift
```

## Step 8: Hardware Validation

Required bench checks:

1. Single-tone sweep amplitude sanity across all RBW modes.
2. Noise floor change versus RBW, checked against `10*log10(actual ENBW)`.
3. 1 kHz RBW with 10 kHz and 10.2 kHz offset tones.
4. Phase-noise mode RBW selection near mode boundaries.
5. Marker/host display consistency after ENBW correction.

