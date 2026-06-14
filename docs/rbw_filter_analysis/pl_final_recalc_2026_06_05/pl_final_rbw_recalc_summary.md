# PL RBW FIR final offline recalculation

Date: 2026-06-05

## Execution

- MATLAB used: yes
- MATLAB version: `24.2.0.2773142 (R2024b) Update 2`
- Script path: `C:\learning\pusu_V2\docs\rbw_filter_analysis\pl_final_recalc_2026_06_05\run_pl_final_rbw_recalc_2026_06_05`
- Output directory: `C:\learning\pusu_V2\docs\rbw_filter_analysis\pl_final_recalc_2026_06_05`
- Scope: final RBW FIR at final per-mode Fs; legacy CIC response is not included in these FIR-only ENBW numbers.

## Required inputs read

| Input | Bytes read |
| --- | ---: |
| `C:\learning\pusu_V2\docs\pl_iq_rbw_config_table_2026-06-05.md` | 4131 |
| `C:\learning\pusu_V2\docs\pl_rbw_fir_offline_recalc_plan_2026-06-05.md` | 8045 |
| `C:\learning\pusu_V2\docs\rbw_filter_analysis\rbw_scheme_b_current_parameters.md` | 3864 |
| `C:\learning\pusu_V2\code\pusu_20260604\vitis\pusu_20260604\src\rbw_filter_coeffs.c` | 35242 |

## Selected parameters

| Mode | Fs | RBW | Source | Taps | Method/window | Cutoff | Beta | ENBW | ENBW/RBW | Correction | Flatness 0.4RBW | Flatness 0.45RBW | 2x | 5x | Observe | Skip | Accum | Status |
| ---: | ---: | ---: | --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 1M | 10000000 | 1000000 | firmware_current_coeffs | 96 | kaiser/kaiser | 540000.0 | 4.0 | 1002220.35 | 1.00222 | +0.0096 dB | 0.0658 dB | 0.7834 dB | -67.31 dB | -305.45 dB | 384 | 32 | 512 | PASS_ACCEPTABLE |
| 300K | 3250000 | 300000 | recalc_scan | 128 | windowed_sinc/kaiser | 165000.0 | 4.0 | 313367.84 | 1.04456 | +0.1893 dB | 0.0521 dB | 0.1573 dB | -62.16 dB | -80.27 dB | 384 | 64 | 576 | PASS_ACCEPTABLE |
| 100K | 1000000 | 100000 | firmware_current_coeffs | 128 | c_table/legacy_hamming_sinc | 54000.0 | n/a | 101477.63 | 1.01478 | +0.0637 dB | 0.0342 dB | 0.4529 dB | -72.57 dB | -83.57 dB | 384 | 64 | 576 | PASS_ACCEPTABLE |
| 30K | 325000 | 30000 | recalc_scan | 192 | windowed_sinc/kaiser | 16050.0 | 6.0 | 30642.72 | 1.02142 | +0.0921 dB | 0.0070 dB | 0.1658 dB | -81.69 dB | -87.39 dB | 256 | 128 | 576 | PASS_ACCEPTABLE |
| 10K | 100000 | 10000 | scheme_b_coeffs_csv | 256 | csv_table/scheme_b_kaiser | 5200.0 | 5.0 | 10089.86 | 1.00899 | +0.0389 dB | 0.0119 dB | 0.0171 dB | -81.34 dB | -302.89 dB | 2560 | 128 | 2944 | PASS_STRICT |
| 1K | 100000 | 1000 | firmware_current_coeffs | 768 | kaiser/kaiser | 520.0 | 3.0 | 983.42 | 0.98342 | -0.0726 dB | 0.2068 dB | 1.5166 dB | -67.30 dB | -92.29 dB | 256 | 128 | 1152 | PASS_ACCEPTABLE |

## 10K conflict conclusion

- `scheme_b_coeffs_csv`: ENBW 10089.86 Hz, ENBW/RBW 1.00899, correction +0.0389 dB, flatness 0.0119 dB, 2x -81.34 dB, 5x -302.89 dB. SELECTED
- `firmware_current_coeffs`: ENBW 1000.38 Hz, ENBW/RBW 0.10004, correction -9.9984 dB, flatness 130.0083 dB, 2x -92.03 dB, 5x -307.95 dB.

Recommendation: use the Scheme B 100 kSPS 10K coefficient set for the final PL RBW table. The current firmware `r130_validation` coefficients should stay only as a 1 MSPS validation-path artifact, not as the final 100 kSPS 10K RBW FIR.

Important Fs note: the current firmware `r130_validation` 10K ENBW near 10001.51 Hz belongs to its 1 MSPS validation context. At the final 100 kSPS RBW FIR rate, the same coefficients evaluate to about 1000 Hz ENBW, so they must not be frozen as the final 10K coefficients.

## Recalculation notes

- 30K and 300K old Scheme B coefficients were re-evaluated at the final Fs only as invalid reference rows; they are not selected.
- 30K scan tested taps 192/256/320/384 at Fs=325 kSPS.
- 300K scan tested taps 96/128/160/192 at Fs=3.25 MSPS.
- Selection rule: smallest taps among candidates meeting acceptance targets, then ENBW closeness/flatness/stopband score.
- Selection flatness uses the historical Scheme B `0~0.4*RBW` passband window for comparability; `0~0.45*RBW` is also reported as a stricter risk observation.
- For newly recalculated 30K/300K modes, final selection additionally prefers candidates with `0~0.45*RBW` flatness <= 0.20 dB when available.
- `accum_target = observe + skip + taps`.

## Output files

- `pl_final_rbw_recalc_summary.md`
- `pl_final_rbw_recalc_metrics.csv`
- `pl_final_rbw_selected_parameters.csv`
- `pl_final_rbw_final_coefficients_float.csv`
- `pl_final_rbw_response_<mode>_<source>.csv`
- `pl_final_rbw_response_<mode>_<source>.png` when MATLAB graphics export succeeds
