# RBW system consistency and calibration start note

Date: 2026-06-05

Active workspace:

- `C:\learning\pusu_V2\code\pusu_20260604`
- PL IQ DMA path: 32-bit packed complex IQ, `I=tdata[31:16]`, `Q=tdata[15:0]`
- Clean DMA packet-boundary fix is active: stream reset + FIFO reset before each S2MM arm

## Test setup

- RF input: fixed 1 GHz tone
- Nominal reference input power: -10 dBm
- RF frontend: LNA bypass, mixer path, attenuator code 0, VGA 0 dB
- Serial port: COM7 @ 921600
- Test tool: `C:\learning\pusu_V2\tools\rbw_system_consistency_matrix.py`

## Generated test artifacts

- First 1-repeat matrix:
  - `C:\learning\pusu_V2\docs\rbw_system_consistency_20260605_195230\rbw_system_consistency_summary.md`
  - `C:\learning\pusu_V2\docs\rbw_system_consistency_20260605_195230\rbw_system_consistency_results.csv`
- Main 3-repeat matrix:
  - `C:\learning\pusu_V2\docs\rbw_system_consistency_20260605_195411\rbw_system_consistency_summary.md`
  - `C:\learning\pusu_V2\docs\rbw_system_consistency_20260605_195411\rbw_system_consistency_results.csv`
- 100K/1M switch stress:
  - `C:\learning\pusu_V2\docs\rbw_system_consistency_20260605_195804\rbw_system_consistency_results.csv`
- 100K steady repeat:
  - `C:\learning\pusu_V2\docs\rbw_system_consistency_20260605_200011\rbw_system_consistency_results.csv`

## Current consistency result

All RBW runs completed with:

- `SWEEP err=0`
- `frame_ready=1`
- `dma_err=0`
- `last_irq=0x00001000`

This means the previous low-RBW DMA/TLAST packet-boundary failure was not reproduced in the 1K/10K/multi-RBW tests.

Main 3-repeat amplitude result, using -10 dBm as the reference plane:

| RBW | OK/Total | Mean peak dBm | Mean error dB | Suggested RBW correction |
|---|---:|---:|---:|---:|
| 1M | 3/3 | -14.46 | -4.46 | +4.46 dB |
| 300K | 3/3 | -11.03 | -1.03 | +1.03 dB |
| 100K | 3/3 | -12.09 | -2.09 | +2.09 dB |
| 30K | 3/3 | -15.15 | -5.15 | +5.15 dB |
| 10K | 3/3 | -10.97 | -0.97 | +0.97 dB |
| 1K | 3/3 | -10.93 | -0.93 | +0.93 dB |

100K follow-up:

- Alternating 100K/1M test showed occasional 100K first-frame-like jumps.
- 100K-only repeated test was stable: -12.84 to -12.85 dBm across five runs.
- Interpretation: 100K itself is stable, but RBW switching may still need a discard/settle frame policy before calibration sampling.

## ENBW observation

The selected offline FIR parameters have small ENBW correction values:

| RBW | ENBW/RBW | Theoretical correction |
|---|---:|---:|
| 1M | 1.0022 | +0.0096 dB |
| 300K | 1.0446 | +0.1893 dB |
| 100K | 1.0148 | +0.0637 dB |
| 30K | 1.0214 | +0.0921 dB |
| 10K | 1.0090 | +0.0389 dB |
| 1K | 0.9834 | -0.0726 dB |

These ENBW corrections are much smaller than the observed 1M/30K/100K amplitude spread, so ENBW alone cannot explain the present inter-RBW amplitude error.

## Calibration strategy

Separate the calibration into two layers:

1. ENBW/RBW-filter theory correction
   - Use the offline FIR `actual_enbw_hz` and `correction_db`.
   - This is a small deterministic correction for noise density and RBW definition.
   - It should not be used to hide multi-dB signal-amplitude mismatches.

2. Measured RBW-mode amplitude correction
   - Use a known tone and record per-RBW measured peak.
   - Correction formula:

```text
rbw_mode_correction_db = reference_power_dbm - measured_peak_dbm
display_power_dbm = measured_power_dbm + rbw_mode_correction_db
```

For the current 1 GHz / -10 dBm setup, a provisional correction table is:

| RBW | Provisional measured correction |
|---|---:|
| 1M | +4.46 dB |
| 300K | +1.03 dB |
| 100K | use steady-repeat value, about +2.84 dB |
| 30K | +5.15 dB |
| 10K | +0.97 dB |
| 1K | +0.93 dB |

This table is only a single-frequency, single-power, single-front-end-state provisional table. It should not be treated as final RF calibration.

## Next implementation recommendation

Before writing permanent calibration constants:

1. Add a discard-frame policy after RBW mode changes.
   - When RBW changes, arm and discard one clean DMA frame, then use the next frame for measurement.
   - This is especially important for calibration acquisition.

2. Repeat the matrix at multiple input powers.
   - Suggested: -40, -30, -20, -10 dBm.
   - Purpose: confirm linearity and see whether correction is power-independent.

3. Repeat at multiple frequencies.
   - Suggested first pass: 100 MHz, 500 MHz, 1 GHz, 1.5 GHz if the source/front-end setup supports it.
   - Purpose: separate RBW-mode correction from RF frequency-response correction.

4. Store calibration as structured data, not hard-coded first.
   - Per record: frequency, reference power, RBW, measured peak, correction, RF frontend state, timestamp.
   - Later decide whether to apply in firmware, host, or both.

