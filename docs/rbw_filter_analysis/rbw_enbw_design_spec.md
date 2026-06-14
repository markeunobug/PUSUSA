# RBW ENBW-Accurate Design Specification

Updated: 2026-06-01

## 1. Goal

The PuSuSA sweep measurement path shall define each nominal RBW by its
equivalent noise bandwidth (ENBW), not by its -3 dB bandwidth.

```text
Nominal RBW = measured ENBW of the complete DDC -> CIC -> FIR response
```

This matters because the firmware computes power from filtered baseband I/Q.
For noise density, phase-noise density, and any dBm/Hz style result, the
normalization bandwidth must be the actual ENBW. A filter whose -3 dB width is
close to the nominal RBW can still have an ENBW error of several dB.

## 2. Current Digital RBW Chain

The active sweep path is:

```text
ADC samples at 130 MHz
-> DDC to complex baseband I/Q
-> CIC decimator, mode-dependent R and N
-> post-decimation FIR low-pass
-> discard startup transient
-> mean(I^2 + Q^2)
-> dBFS to dBm conversion
```

The response to be specified and verified is the complete complex baseband
response after DDC, CIC, and FIR. FIR-only plots are useful diagnostics, but
they are not sufficient for RBW certification because CIC droop, CIC comb
zeros, and post-decimation aliasing are part of the actual measurement path.

## 3. Required Metrics

Each RBW mode shall report the following metrics from the complete CIC + FIR
response:

| Metric | Definition | First target |
| --- | --- | ---: |
| ENBW | Integral of normalized power response, in Hz | Nominal RBW +/- 5% |
| ENBW correction | `10*log10(actual_enbw / nominal_rbw)` | Must be recorded |
| -3 dB bandwidth | Frequency where magnitude first crosses -3.0103 dB | Report only |
| -6 dB bandwidth | Frequency where magnitude first crosses -6 dB | Report only |
| Passband flatness | Worst deviation in `0 .. 0.4*RBW` | <= +/- 0.2 dB |
| Response at 0.5*RBW | Magnitude response | Report only |
| Response at 1*RBW | Magnitude response | Report only |
| Response at 2*RBW | Magnitude response | <= -60 dB |
| Response at 5*RBW | Magnitude response | <= -80 dB |
| Response at 10*RBW | Magnitude response | Report, check alias risk |
| Shape factor | 60 dB bandwidth / 3 dB bandwidth | Report once available |
| CIC output rate | `ADC_FS / CIC_R` | Narrow RBW should be >= 20*RBW |
| Finite-window response | Response after actual CIC reset, FIR transient skip, and measurement window | Must match steady-state risk conclusions |

The first implementation target is intentionally moderate. Once the design and
validation workflow is stable, ENBW error can be tightened from +/- 5% to
+/- 2%.

## 4. Current Firmware Baseline

The following baseline was generated from the current
`code/pusu_20260516/vitis/pusu_20260516/src/app_config.h` using:

```text
python tools/rbw_filter_analysis.py --no-plots --out-dir docs/rbw_filter_analysis_current_check
```

| RBW | CIC R/N | Fs out | FIR taps | -3 dB BW | -6 dB BW | ENBW | ENBW/RBW | ENBW error | Correction |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 kHz | 13000 / 5 | 10 kHz | 256 | 979 Hz | 997 Hz | 1870 Hz | 1.870 | +87.0% | +2.72 dB |
| 10 kHz | 1300 / 5 | 100 kHz | 256 | 9.79 kHz | 9.97 kHz | 18.70 kHz | 1.870 | +87.0% | +2.72 dB |
| 30 kHz | 433 / 5 | 300.23 kHz | 256 | 29.38 kHz | 29.90 kHz | 56.10 kHz | 1.870 | +87.0% | +2.72 dB |
| 100 kHz | 130 / 5 | 1 MHz | 128 | 95.88 kHz | 99.36 kHz | 183.92 kHz | 1.839 | +83.9% | +2.65 dB |
| 300 kHz | 43 / 4 | 3.02 MHz | 128 | 288.22 kHz | 298.47 kHz | 557.80 kHz | 1.859 | +85.9% | +2.69 dB |
| 1 MHz | 13 / 4 | 10 MHz | 64 | 922.79 kHz | 990.14 kHz | 1.807 MHz | 1.807 | +80.7% | +2.57 dB |

Current conclusion: the existing filters roughly make the -3 dB bandwidth close
to the nominal RBW, but they do not make ENBW close to nominal RBW. Under the
new definition, every current mode fails the ENBW accuracy target unless an
explicit ENBW correction is applied.

## 5. Current Rejection Baseline

| RBW | 0.5*RBW | 1*RBW | 2*RBW | 5*RBW | 10*RBW |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 1 kHz | -0.17 dB | -6.73 dB | -77.51 dB | -113.26 dB | CIC zero |
| 10 kHz | -0.17 dB | -6.73 dB | -77.51 dB | -113.26 dB | CIC zero |
| 30 kHz | -0.17 dB | -6.73 dB | -79.16 dB | -103.89 dB | very low |
| 100 kHz | -0.19 dB | -6.75 dB | -67.88 dB | -99.07 dB | CIC zero |
| 300 kHz | -0.15 dB | -6.59 dB | -67.13 dB | -85.29 dB | -168.83 dB |
| 1 MHz | -0.13 dB | -6.57 dB | -65.66 dB | -98.96 dB | very low |

The rejection values are acceptable as a starting point for many modes, but
they must be rechecked after any ENBW-centered redesign. Narrow modes also need
special alias checks because strong tones can fold into the post-decimation
passband if `Fs_out` is too low.

## 6. Alias and Decimation Requirements

For ENBW-accurate RBW, decimation must not only reduce compute load. It must
also preserve enough post-decimation bandwidth that important nearby offsets do
not alias back into the RBW passband.

Initial rule:

```text
For narrow RBW modes, Fs_out >= 20 * nominal_RBW
```

This is a minimum geometry rule, not a complete anti-aliasing proof. The final
check shall include explicit finite-window response at important offsets,
especially:

```text
1 kHz, 3 kHz, 10 kHz, 10.2 kHz, 14 kHz, 100 kHz
```

The current 1 kHz mode uses `R=13000`, so `Fs_out=10 kHz`. This is risky around
10 kHz offset because frequencies near 10 kHz can fold into or near DC after
decimation. A previous analysis showed that changing 1 kHz mode to
`R=1300`, `Fs_out=100 kHz` avoids this specific alias geometry, but the FIR
still needs ENBW-centered redesign.

## 7. Offline Design Workflow

The design workflow for each RBW mode is:

1. Choose CIC decimation ratio `R` and stages `N`.
2. Compute `Fs_out = 130 MHz / R`.
3. Design a post-decimation FIR in MATLAB.
4. Evaluate the combined CIC + FIR response, including alias behavior.
5. Scale or redesign FIR so combined ENBW equals nominal RBW.
6. Check passband flatness, 2x/5x rejection, and finite-window response.
7. Export fixed FIR coefficient tables and a machine-readable metric summary.
8. Re-run the same analysis after coefficient quantization or firmware-format conversion.

Recommended MATLAB outputs:

```text
docs/rbw_filter_analysis/matlab/rbw_enbw_metrics.csv
docs/rbw_filter_analysis/matlab/rbw_enbw_metrics.md
docs/rbw_filter_analysis/matlab/rbw_coefficients_float.csv
docs/rbw_filter_analysis/matlab/rbw_response_<mode>.csv
docs/rbw_filter_analysis/matlab/rbw_response_<mode>.png
```

The first MATLAB pass should compare at least these design methods:

```text
Kaiser-window FIR
Parks-McClellan / equiripple FIR
CIC-compensation FIR followed by RBW low-pass, if feasible
```

## 8. Open Decisions

The following decisions remain open and should be resolved after the first
MATLAB sweep:

1. Whether to keep the current CIC ratios for all modes except 1 kHz.
2. Whether 1 kHz should move from `R=13000` to `R=1300` as the default.
3. Whether to enforce ENBW by FIR design alone or by applying an explicit ENBW
   correction factor in firmware/host math.
4. Whether to store one fixed FIR table per RBW mode instead of generating
   Hamming-window sinc coefficients at runtime.
5. Whether the first production target should be `+/- 5% ENBW` or a tighter
   `+/- 2% ENBW`.

