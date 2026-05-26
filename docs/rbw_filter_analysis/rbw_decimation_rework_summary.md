# RBW Decimation Rework Alias Check

This report constructs temporary 1 kHz RBW modes for the decimation rework, independent of the current `app_config.h` values.

| Configuration | Fs out | 3 dB BW | ENBW | ENBW/RBW | Accum count |
| --- | ---: | ---: | ---: | ---: | ---: |
| old 1K, R=13000 | 10000.0 Hz | 979.3 Hz | 1870.0 Hz | 1.870 | 640 |
| new 1K, R=1300 | 100000.0 Hz | 842.6 Hz | 1688.6 Hz | 1.689 | 640 |

## Key Alias Points

`FIR at alias` is the post-decimation FIR response at the folded frequency. `Fixed window` is the full CIC + FIR finite-window response after skipping the FIR transient.

| Configuration | Offset | Alias | In RBW passband | FIR at alias | CIC | Steady total | Current window | Fixed window |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| old 1K, R=13000 | 1 kHz | 1 kHz | yes | -6.02 dB | -0.72 dB | -6.73 dB | -6.48 dB | -6.73 dB |
| old 1K, R=13000 | 3 kHz | 3 kHz | no | -75.67 dB | -6.63 dB | -82.30 dB | -37.19 dB | -82.30 dB |
| old 1K, R=13000 | 10 kHz | 0 Hz | yes | -0.00 dB | -1598.98 dB | -1598.98 dB | -48.03 dB | -304.29 dB |
| old 1K, R=13000 | 10.2 kHz | 200 Hz | yes | 0.00 dB | -170.79 dB | -170.78 dB | -48.21 dB | -170.78 dB |
| old 1K, R=13000 | 14 kHz | 4 kHz | no | -74.46 dB | -66.51 dB | -140.97 dB | -50.97 dB | -140.97 dB |
| old 1K, R=13000 | 100 kHz | 0 Hz | yes | -0.00 dB | -1640.91 dB | -1640.91 dB | -68.07 dB | -322.56 dB |
| new 1K, R=1300 | 1 kHz | 1 kHz | yes | -6.01 dB | -0.01 dB | -6.02 dB | -5.91 dB | -6.02 dB |
| new 1K, R=1300 | 3 kHz | 3 kHz | no | -55.40 dB | -0.06 dB | -55.46 dB | -29.53 dB | -55.46 dB |
| new 1K, R=1300 | 10 kHz | 10 kHz | no | -64.35 dB | -0.72 dB | -65.07 dB | -40.38 dB | -65.07 dB |
| new 1K, R=1300 | 10.2 kHz | 10.2 kHz | no | -74.07 dB | -0.75 dB | -74.81 dB | -40.56 dB | -74.81 dB |
| new 1K, R=1300 | 14 kHz | 14 kHz | no | -72.82 dB | -1.41 dB | -74.23 dB | -43.33 dB | -74.23 dB |
| new 1K, R=1300 | 100 kHz | 0 Hz | yes | -0.00 dB | -1574.39 dB | -1574.39 dB | -60.42 dB | -316.72 dB |

## Conclusion

- Old 1 kHz RBW (`R=13000`, `Fs_out=10 kHz`) folds 10 kHz to DC and 10.2 kHz to 200 Hz; both land inside the 1 kHz RBW passband. The FIR-only alias response is -0.00 dB at 10 kHz and 0.00 dB at 10.2 kHz.
- New 1 kHz RBW (`R=1300`, `Fs_out=100 kHz`) leaves those offsets at 10 kHz and 10.2 kHz, outside the 1 kHz FIR passband. The full fixed-window carrier rejection is -65.07 dB at 10 kHz and -74.81 dB at 10.2 kHz.
- Exact 10 kHz is a CIC comb-null special case in the old mode, so the ideal steady-state total response is very low. The alias risk is still visible in the folded frequency and FIR-only columns, and the old current-window model leaks -48.21 dB at 10.2 kHz before the FIR transient is skipped.

## If More Rejection Is Needed

The proposed 256-tap Hamming FIR solves the 10 kHz alias geometry, but it gives only about -65.1 dB to -74.8 dB of full fixed-window carrier rejection around 10 kHz. Tap sweep for the new `R=1300` mode:

| FIR taps | Accum count | Fits 768 buffer | 3 dB BW | ENBW | 10 kHz | 10.2 kHz | 14 kHz |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 256 | 640 | yes | 842.6 Hz | 1688.6 Hz | -65.07 dB | -74.81 dB | -74.23 dB |
| 384 | 768 | yes | 896.6 Hz | 1804.2 Hz | -75.32 dB | -83.59 dB | -80.04 dB |
| 512 | 896 | no | 920.6 Hz | 1838.4 Hz | -81.31 dB | -81.03 dB | -85.11 dB |

A 384-tap Hamming FIR is the largest option that still fits `256 + 128 + taps <= 768`; larger rejection should use a different window or a larger/rebalanced accumulation buffer.
