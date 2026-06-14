# Vivado ILA ADC Data Analysis

- Input directory: `C:\learning\pusu_V2\docs\ila_data`
- Output directory: `C:\learning\pusu_V2\docs\ila_data_analysis\20260604_104101`
- Generated: 2026-06-04T10:41:01
- Assumed sample rate: Fs = 130.000 MHz
- FFT bin spacing for 1024 samples: 126953.125 Hz
- 100 kHz offset vs bin spacing: 100000 Hz / 126953.125 Hz = 0.788 bin
- Processing: selected signed/numeric ADC sample column, removed mean, applied Hann window, computed real FFT.
- Amplitudes are relative dB values from FFT magnitude; they are not calibrated dBm.

## File Inventory and Column Detection

### iladata_1.0000G.csv

- Detected type: CSV / Vivado ILA-style table
- Size: 18886 bytes
- Columns: `Sample in Buffer, Sample in Window, TRIGGER, system_i/LTC2208_0_adc_data[15:0], system_i/LTC2208_0_m_axis_aclk, system_i/LTC2208_0_adc_of`
- Radix row: `UNSIGNED, UNSIGNED, UNSIGNED, SIGNED, HEX, HEX`
- Parsed sample rows: 1024
- Filename condition inference: filename suggests 1.0000 GHz input / expected IF around 40.000 MHz

| Column | Radix | Numeric | Unique | Min | Max | Mean | Std | Candidate score |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `Sample in Buffer` | UNSIGNED | 1024 | 1024 | 0 | 1023 | 511.5 | 295.603 | 9 |
| `Sample in Window` | UNSIGNED | 1024 | 1024 | 0 | 1023 | 511.5 | 295.603 | 9 |
| `TRIGGER` | UNSIGNED | 1024 | 2 | 0 | 1 | 0.000976562 | 0.0312347 | -3 |
| `system_i/LTC2208_0_adc_data[15:0]` | SIGNED | 1024 | 188 | -65 | 148 | 44.9854 | 56.2354 | 17 |
| `system_i/LTC2208_0_m_axis_aclk` | HEX | 1024 | 1 | 0 | 0 | 0 | 0 | -3 |
| `system_i/LTC2208_0_adc_of` | HEX | 1024 | 1 | 0 | 0 | 0 | 0 | -1 |

- Suspected data columns: `system_i/LTC2208_0_adc_data[15:0]` (score 17), `Sample in Buffer` (score 9), `Sample in Window` (score 9)
- Selected ADC column: `system_i/LTC2208_0_adc_data[15:0]`

### iladata_1.0001G.csv

- Detected type: CSV / Vivado ILA-style table
- Size: 18912 bytes
- Columns: `Sample in Buffer, Sample in Window, TRIGGER, system_i/LTC2208_0_adc_data[15:0], system_i/LTC2208_0_m_axis_aclk, system_i/LTC2208_0_adc_of`
- Radix row: `UNSIGNED, UNSIGNED, UNSIGNED, SIGNED, HEX, HEX`
- Parsed sample rows: 1024
- Filename condition inference: filename suggests 1.0001 GHz input / expected IF around 40.100 MHz

| Column | Radix | Numeric | Unique | Min | Max | Mean | Std | Candidate score |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `Sample in Buffer` | UNSIGNED | 1024 | 1024 | 0 | 1023 | 511.5 | 295.603 | 9 |
| `Sample in Window` | UNSIGNED | 1024 | 1024 | 0 | 1023 | 511.5 | 295.603 | 9 |
| `TRIGGER` | UNSIGNED | 1024 | 2 | 0 | 1 | 0.000976562 | 0.0312347 | -3 |
| `system_i/LTC2208_0_adc_data[15:0]` | SIGNED | 1024 | 188 | -57 | 144 | 45.9609 | 55.8486 | 17 |
| `system_i/LTC2208_0_m_axis_aclk` | HEX | 1024 | 1 | 0 | 0 | 0 | 0 | -3 |
| `system_i/LTC2208_0_adc_of` | HEX | 1024 | 1 | 0 | 0 | 0 | 0 | -1 |

- Suspected data columns: `system_i/LTC2208_0_adc_data[15:0]` (score 17), `Sample in Buffer` (score 9), `Sample in Window` (score 9)
- Selected ADC column: `system_i/LTC2208_0_adc_data[15:0]`

## FFT Results

| File | Samples | Selected column | Peak frequency (Hz) | Peak bin (Hz) | Peak relative dB | Top peaks Hz:dB |
|---|---:|---|---:|---:|---:|---|
| iladata_1.0000G.csv | 1024 | `system_i/LTC2208_0_adc_data[15:0]` | 40000643.860 | 39990234.375 | 37.876 | 39990234.375:37.88<br>62333984.375:7.02<br>55732421.875:6.10<br>45576171.875:4.78<br>60937500.000:4.72 |
| iladata_1.0001G.csv | 1024 | `system_i/LTC2208_0_adc_data[15:0]` | 40099003.673 | 40117187.500 | 37.722 | 40117187.500:37.72<br>59414062.500:8.55<br>42529296.875:6.31<br>50019531.250:6.19<br>64492187.500:5.63 |

## 40.000 MHz vs 40.100 MHz Check

- `iladata_1.0000G.csv`: interpolated peak 40.000644 MHz; error vs 40.000 MHz = +0.644 kHz, vs 40.100 MHz = -99.356 kHz. Nearest reference: 40.000 MHz.
- `iladata_1.0001G.csv`: interpolated peak 40.099004 MHz; error vs 40.000 MHz = +99.004 kHz, vs 40.100 MHz = -0.996 kHz. Nearest reference: 40.100 MHz.

Interpretation: each capture contains only 1024 samples, so the bin spacing is 126.953 kHz. A +100 kHz offset is smaller than one FFT bin. The two files do show peaks nearest to different adjacent bins/references, and Hann-window sub-bin interpolation estimates approximately a 100 kHz separation. However, this should be treated as indicative rather than a robust frequency-resolution proof unless longer captures or repeated captures confirm it.

## Spectrum Plots

- `iladata_1.0000G.csv`: `iladata_1.0000G_spectrum.png`
- `iladata_1.0001G.csv`: `iladata_1.0001G_spectrum.png`

## Limitations / Unable to Determine

- The report infers input conditions only from filenames; no embedded metadata was found proving which RF condition produced each capture.
- The ILA exports contain one real ADC sample column, not complex I/Q samples, so the FFT is a real-input spectrum from 0 to Fs/2.
- Absolute amplitude calibration is unavailable in the ILA data; dB values are relative FFT magnitudes.
- With 1024 samples at 130 MHz, the record length is only 7.877 us, so the native FFT resolution is coarse for a 100 kHz question.
