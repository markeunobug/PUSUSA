# RBW Scheme B Current Parameters

Updated: 2026-06-01

## Decision

Use Scheme B as the current implementation target for the first ENBW-accurate
RBW firmware replacement.

Scheme B accepts:

```text
1 kHz RBW: R=1300, Fs_out=100 kHz, 768-tap Kaiser FIR
1 MHz RBW: 96-tap Kaiser FIR
10 kHz, 30 kHz, 100 kHz, 300 kHz: selected PASS candidates from MATLAB search
```

For the first implementation pass, the 1 kHz passband-flatness target is
relaxed from `<= 0.20 dB` to `<= 0.25 dB`. The selected 1 kHz candidate has
`0.206 dB` flatness, which is close to the original target and avoids the much
larger 1024-tap/buffer-1408 option.

## Selected Parameters

| RBW | Status | CIC R/N | Fs out | FIR method | FIR options | Taps | Observe | Skip | Accum target | Required buffer |
| ---: | --- | ---: | ---: | --- | --- | ---: | ---: | ---: | ---: | ---: |
| 1 kHz | Scheme B accepted | 1300 / 5 | 100 kHz | Kaiser | cutoff=520 Hz, beta=3 | 768 | 256 | 128 | 1152 | 1152 |
| 10 kHz | PASS | 1300 / 5 | 100 kHz | Kaiser | cutoff=5200 Hz, beta=5 | 256 | 256 | 128 | 640 | 768 |
| 30 kHz | PASS | 433 / 5 | 300.23 kHz | Kaiser | cutoff=15600 Hz, beta=5 | 256 | 256 | 128 | 640 | 768 |
| 100 kHz | PASS | 130 / 5 | 1 MHz | Hamming-sinc | cutoff=54000 Hz | 128 | 384 | 64 | 576 | 768 |
| 300 kHz | PASS | 43 / 4 | 3.023 MHz | Hamming-sinc | cutoff=162000 Hz | 128 | 384 | 64 | 576 | 768 |
| 1 MHz | PASS | 13 / 4 | 10 MHz | Kaiser | cutoff=540000 Hz, beta=4 | 96 | 384 | 32 | 512 | 768 |

Global firmware implication:

```text
ACCUM_BUFFER_SIZE must increase from 768 to at least 1152.
Maximum FIR taps must increase from 256 to at least 768.
```

## Selected Metrics

| RBW | ENBW | ENBW/RBW | Correction | Flatness | 2x RBW | 5x RBW | 10 kHz alias note |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 1 kHz | 983.29 Hz | 0.9833 | -0.07 dB | 0.206 dB | -67.33 dB | -92.47 dB | 10 kHz: -91.64 dB; 10.2 kHz: -107.05 dB |
| 10 kHz | 9949.76 Hz | 0.9950 | -0.02 dB | 0.115 dB | -84.24 dB | -321.38 dB | 10 kHz: -70.23 dB; 10.2 kHz: -78.82 dB |
| 30 kHz | 29848.61 Hz | 0.9950 | -0.02 dB | 0.115 dB | -85.74 dB | -112.78 dB | 10 kHz is inside this RBW passband |
| 100 kHz | 100020.77 Hz | 1.0002 | +0.00 dB | 0.133 dB | -75.47 dB | -103.18 dB | 10 kHz is inside this RBW passband |
| 300 kHz | 300911.26 Hz | 1.0030 | +0.01 dB | 0.110 dB | -74.44 dB | -90.77 dB | 10 kHz is inside this RBW passband |
| 1 MHz | 990877.50 Hz | 0.9909 | -0.04 dB | 0.140 dB | -69.62 dB | -320.65 dB | 10 kHz is inside this RBW passband |

## 1 kHz Engineering Tradeoff

The stricter 1 kHz PASS candidate was:

```text
1024 taps, Kaiser cutoff=540 Hz, beta=5
ENBW/RBW = 1.0030
flatness = 0.105 dB
required buffer = 1408
```

Scheme B chooses the lighter 768-tap candidate:

```text
768 taps, Kaiser cutoff=520 Hz, beta=3
ENBW/RBW = 0.9833
flatness = 0.206 dB
required buffer = 1152
```

This keeps ENBW within the +/-5% target, meets 2x and 5x rejection targets, and
removes the old 10 kHz / 10.2 kHz alias geometry by changing 1 kHz RBW from
`R=13000` to `R=1300`.

## Firmware Changes Implied Next

1. Change `RBW_1K_CIC_R` from `13000U` to `1300U`.
2. Change `RBW_1K_FIR_TAPS` from `256U` to `768U`.
3. Change `RBW_1M_FIR_TAPS` from `64U` to `96U`.
4. Increase `ACCUM_BUFFER_SIZE` from `768U` to at least `1152U`.
5. Replace runtime Hamming-sinc coefficient generation with fixed coefficient
   lookup tables generated from this Scheme B parameter set.
6. Carry actual ENBW values into any density math:

```text
density = measured_power_dbm - 10*log10(actual_enbw_hz)
```

## Source Outputs

The selected values are derived from:

```text
docs/rbw_filter_analysis/matlab/rbw_candidate_selection.md
docs/rbw_filter_analysis/matlab/rbw_candidate_tap_sweep.md
docs/rbw_filter_analysis/matlab/rbw_candidate_metrics.csv
docs/rbw_filter_analysis/matlab/rbw_candidate_tap_sweep.csv
```

