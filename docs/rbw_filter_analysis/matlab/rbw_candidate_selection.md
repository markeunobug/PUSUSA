# RBW Candidate Selection

Step 1 selects one first-version candidate per profile and mode. Status meanings: `PASS`, `NEEDS_TAPS`, `NEEDS_DECIMATION_REWORK`, or `FAIL`.

| Profile | Mode | Status | Method/options | Fs out | Taps | ENBW | ENBW/RBW | Correction | Flatness | 2x | 5x | Alias check | Recommendation |
| --- | ---: | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| firmware_current | 1K | NEEDS_DECIMATION_REWORK | kaiser `cutoff_hz=520;kaiser_beta=5` | 10000.0 | 256 | 994.98 | 0.9950 | -0.02 dB | 0.115 dB | -84.24 dB | -321.38 dB | 10k->0.0 Hz -1599.0 dB; 10.2k->200.0 Hz -170.8 dB | Revise CIC decimation geometry before freezing coefficients; 1 kHz offset aliases into the passband-risk region. |
| firmware_current | 10K | PASS | kaiser `cutoff_hz=5200;kaiser_beta=5` | 100000.0 | 256 | 9949.76 | 0.9950 | -0.02 dB | 0.115 dB | -84.24 dB | -321.38 dB | 10k->10000.0 Hz -70.2 dB; 10.2k->10200.0 Hz -78.8 dB | Use this candidate for Step 2 freeze after coefficient quantization check. |
| firmware_current | 30K | PASS | kaiser `cutoff_hz=15600;kaiser_beta=5` | 300230.9 | 256 | 29848.61 | 0.9950 | -0.02 dB | 0.115 dB | -85.74 dB | -112.78 dB | 10k->10000.0 Hz -0.1 dB; 10.2k->10200.0 Hz -0.1 dB | Use this candidate for Step 2 freeze after coefficient quantization check. |
| firmware_current | 100K | PASS | hamming_sinc `cutoff_hz=54000` | 1000000.0 | 128 | 100020.77 | 1.0002 | +0.00 dB | 0.133 dB | -75.47 dB | -103.18 dB | 10k->10000.0 Hz -0.0 dB; 10.2k->10200.0 Hz -0.0 dB | Use this candidate for Step 2 freeze after coefficient quantization check. |
| firmware_current | 300K | PASS | hamming_sinc `cutoff_hz=162000` | 3023255.8 | 128 | 300911.26 | 1.0030 | +0.01 dB | 0.110 dB | -74.44 dB | -90.77 dB | 10k->10000.0 Hz -0.0 dB; 10.2k->10200.0 Hz -0.0 dB | Use this candidate for Step 2 freeze after coefficient quantization check. |
| firmware_current | 1M | NEEDS_TAPS | kaiser `cutoff_hz=560000;kaiser_beta=4` | 10000000.0 | 64 | 995263.81 | 0.9953 | -0.02 dB | 0.533 dB | -61.64 dB | -321.81 dB | 10k->10000.0 Hz -0.0 dB; 10.2k->10200.0 Hz -0.0 dB | Increase FIR taps or broaden method sweep; current tap budget is close but misses rejection/flatness targets. |
| alias_rework_1k | 1K | NEEDS_TAPS | kaiser `cutoff_hz=640;kaiser_beta=8` | 100000.0 | 256 | 1005.83 | 1.0058 | +0.03 dB | 1.982 dB | -98.24 dB | -90.51 dB | 10k->10000.0 Hz -96.9 dB; 10.2k->10200.0 Hz -117.0 dB | Increase FIR taps or broaden method sweep; current tap budget is close but misses rejection/flatness targets. |
| alias_rework_1k | 10K | PASS | kaiser `cutoff_hz=5200;kaiser_beta=5` | 100000.0 | 256 | 9949.76 | 0.9950 | -0.02 dB | 0.115 dB | -84.24 dB | -321.38 dB | 10k->10000.0 Hz -70.2 dB; 10.2k->10200.0 Hz -78.8 dB | Use this candidate for Step 2 freeze after coefficient quantization check. |
| alias_rework_1k | 30K | PASS | kaiser `cutoff_hz=15600;kaiser_beta=5` | 300230.9 | 256 | 29848.61 | 0.9950 | -0.02 dB | 0.115 dB | -85.74 dB | -112.78 dB | 10k->10000.0 Hz -0.1 dB; 10.2k->10200.0 Hz -0.1 dB | Use this candidate for Step 2 freeze after coefficient quantization check. |
| alias_rework_1k | 100K | PASS | hamming_sinc `cutoff_hz=54000` | 1000000.0 | 128 | 100020.77 | 1.0002 | +0.00 dB | 0.133 dB | -75.47 dB | -103.18 dB | 10k->10000.0 Hz -0.0 dB; 10.2k->10200.0 Hz -0.0 dB | Use this candidate for Step 2 freeze after coefficient quantization check. |
| alias_rework_1k | 300K | PASS | hamming_sinc `cutoff_hz=162000` | 3023255.8 | 128 | 300911.26 | 1.0030 | +0.01 dB | 0.110 dB | -74.44 dB | -90.77 dB | 10k->10000.0 Hz -0.0 dB; 10.2k->10200.0 Hz -0.0 dB | Use this candidate for Step 2 freeze after coefficient quantization check. |
| alias_rework_1k | 1M | NEEDS_TAPS | kaiser `cutoff_hz=560000;kaiser_beta=4` | 10000000.0 | 64 | 995263.81 | 0.9953 | -0.02 dB | 0.533 dB | -61.64 dB | -321.81 dB | 10k->10000.0 Hz -0.0 dB; 10.2k->10200.0 Hz -0.0 dB | Increase FIR taps or broaden method sweep; current tap budget is close but misses rejection/flatness targets. |

## Notes

- `firmware_current` keeps the current CIC decimation ratios.
- `alias_rework_1k` changes only 1 kHz RBW to `R=1300`, giving `Fs_out=100 kHz`.
- Equiripple was skipped because this MATLAB install exposes `firpm.m` as a non-callable script; Hamming-sinc and Kaiser sweeps were evaluated.
- `NEEDS_DECIMATION_REWORK` is assigned before filter quality when the 1 kHz 10 kHz/10.2 kHz alias geometry folds into the passband-risk region.
