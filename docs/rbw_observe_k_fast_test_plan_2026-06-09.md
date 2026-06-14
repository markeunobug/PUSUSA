# RBW Observe/K Fast-Test Plan - 2026-06-09

## Goal

This step changes the PS-side observation budget for each RBW mode so the
finite-burst SG DMA path can be tested with lower latency, especially at 30 kHz,
10 kHz, and 1 kHz RBW.

The change does not redesign the DDC, CIC, FIR coefficients, or power formula.
It changes how many post-decimation samples are accumulated for one measurement
point.

## Quality Metric

Use:

```text
K = observe_points * RBW / Fs_out
Fs_out = ADC_SAMPLE_RATE_HZ / CIC_R
accum_target = observe_points + skip_points + fir_taps
blocks = ceil(accum_target / floor(FFT_SIZE / CIC_R))
```

Approximate single-point power jitter:

```text
sigma_dB ~= 4.34 / sqrt(K)
```

This is a rough measurement-stability indicator. It does not change the RBW
filter ENBW by itself.

## Fast-Test Profile To Implement Now

This profile is intentionally biased toward link bring-up and stutter
diagnosis, while using 1 kHz K=5 as a faster but less noisy low-RBW test point.

| RBW | Target K | Observe points | Accum target | DMA blocks | Raw data | Approx sigma |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 MHz | 10 | 100 | 228 | 1 | 8 KiB | 1.37 dB |
| 300 kHz | 10 | 101 | 293 | 4 | 32 KiB | 1.37 dB |
| 100 kHz | 10 | 100 | 292 | 10 | 80 KiB | 1.37 dB |
| 30 kHz | 10 | 101 | 485 | 54 | 432 KiB | 1.37 dB |
| 10 kHz | 10 | 100 | 484 | 162 | 1.27 MiB | 1.37 dB |
| 1 kHz | 5 | 500 | 1396 | 466 | 3.64 MiB | 1.94 dB |

## Important 1 kHz Caveat

`1 kHz / K=5` is a faster low-RBW test setting with better stability than K=1/K=2,
but it is still lighter than K=10/K=20.

For more stable 1 kHz measurements, use one of these later:

| 1 kHz mode | Observe points | Accum target | DMA blocks | Raw data | Approx sigma |
| --- | ---: | ---: | ---: | ---: | ---: |
| K=10 | 1000 | 1896 | 632 | 4.94 MiB | 1.37 dB |
| K=20 | 2000 | 2896 | 966 | 7.55 MiB | 0.97 dB |

The current `ACCUM_BUFFER_SIZE=2944` still covers up to 1 kHz K=20. If 1 kHz is
raised beyond K=20, the accumulation buffers must be expanded.

## Code Changes

1. Update `code/pusu_20260608/vitis/pusu_20260608/src/app_config.h`.
   - Set the new `RBW_*_OBSERVE_POINTS` values from the fast-test table.
   - Expand `DMA_MAX_SAMPLES` from `128 * FFT_SIZE` to `1024 * FFT_SIZE`.
   - Expand `DMA_SWEEP_SG_MAX_BLOCKS_PER_TRANSFER` from `128` to `1024`.
   - Update comments so the file no longer claims all modes target 0.6-1.0 dB.

2. Update `code/pusu_20260608/vitis/pusu_20260608/src/dma_capture.c`.
   - Expand `DMA_SG_RX_BD_COUNT` from `128` to `1024`.
   - `DMA_SG_RX_BD_SPACE_BYTES` follows from that macro.

3. Update `code/pusu_20260608/vitis/pusu_20260608/src/phase_noise_plan.c`.
   - Route exactly `10 kHz` offset to `RBW_MODE_1K` by changing the first
     threshold from `< 10000U` to `<= 10000U`.
   - This prepares the phase-noise planner for the later true-1 kHz mode.

## Verification After User Builds And Burns

1. Run SG burst smoke tests:
   - `sgburst 162` for 10 kHz fast profile.
   - `sgburst 466` for 1 kHz K=5 profile.
   - Optional future tests: `sgburst 632` for K=10 and `sgburst 966` for K=20.

2. Sweep each RBW mode and record:
   - Point completion count.
   - `dma_error` and SG submit failures.
   - `completed_bd / requested_bd`.
   - DMA/profile time.
   - Visible stutter in the host UI.

3. Treat 1 kHz K=5 results as preliminary low-RBW evidence. Use K=10/K=20 or averaging for final
   phase-noise accuracy evidence.

## Follow-Up

After the fast-test profile is stable, split the measurement policy:

- Sweep/UI fast mode: lower K for responsiveness.
- Phase-noise mode: 1 kHz K=10/K=20 or multiple-window linear averaging.

This avoids forcing the whole spectrum UI to carry the full phase-noise
observation cost.
