# Vivado ILA ADC Data Analysis

- Input directory: `C:\learning\pusu_V2\docs\ila_data`
- Output directory: `C:\learning\pusu_V2\docs\ila_data_analysis_2026_06_04`
- Assumed ADC sample rate: Fs = 130.000 MHz
- Clock note: no embedded sample-rate metadata was found in the parsed CSV files; `m_axis_aclk` is a captured logic probe, not a frequency annotation.
- Processing: selected the most likely raw ADC numeric column, removed its mean, applied a Hann window, then computed a real-input FFT.
- Amplitudes are relative FFT magnitudes in dB; the data do not contain amplitude-calibration metadata.

## File Inventory

### iladata_1.0000G.csv

- Detected type: CSV / Vivado ILA-style table
- Size: 18886 bytes
- Columns: `Sample in Buffer, Sample in Window, TRIGGER, system_i/LTC2208_0_adc_data[15:0], system_i/LTC2208_0_m_axis_aclk, system_i/LTC2208_0_adc_of`
- Radix row: `UNSIGNED, UNSIGNED, UNSIGNED, SIGNED, HEX, HEX`
- Parsed sample rows: 1024
- Filename condition inference: filename suggests 1.0000 GHz input / expected IF near 40.000 MHz
- Contains tdata/tvalid/tlast: False/False/False
- Contains ADC raw-looking field: True
- Selected sample column: `system_i/LTC2208_0_adc_data[15:0]`
- Selected column radix/format: `SIGNED`; bit width from name: 16; signed: True
- tvalid continuity: no tvalid/valid field present
- ADC overflow: system_i/LTC2208_0_adc_of never asserted
- Mean before de-mean: 44.9854 ADC codes

| Column | Radix | Numeric | Unique | Min | Max | Mean | Std | Score |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `Sample in Buffer` | UNSIGNED | 1024 | 1024 | 0 | 1023 | 511.5 | 295.603 | -6 |
| `Sample in Window` | UNSIGNED | 1024 | 1024 | 0 | 1023 | 511.5 | 295.603 | -6 |
| `TRIGGER` | UNSIGNED | 1024 | 2 | 0 | 1 | 0.000976562 | 0.0312347 | -5 |
| `system_i/LTC2208_0_adc_data[15:0]` | SIGNED | 1024 | 188 | -65 | 148 | 44.9854 | 56.2354 | 20 |
| `system_i/LTC2208_0_m_axis_aclk` | HEX | 1024 | 1 | 0 | 0 | 0 | 0 | -5 |
| `system_i/LTC2208_0_adc_of` | HEX | 1024 | 1 | 0 | 0 | 0 | 0 | 1 |

### iladata_1.0001G.csv

- Detected type: CSV / Vivado ILA-style table
- Size: 18912 bytes
- Columns: `Sample in Buffer, Sample in Window, TRIGGER, system_i/LTC2208_0_adc_data[15:0], system_i/LTC2208_0_m_axis_aclk, system_i/LTC2208_0_adc_of`
- Radix row: `UNSIGNED, UNSIGNED, UNSIGNED, SIGNED, HEX, HEX`
- Parsed sample rows: 1024
- Filename condition inference: filename suggests 1.0001 GHz input / expected IF near 40.100 MHz
- Contains tdata/tvalid/tlast: False/False/False
- Contains ADC raw-looking field: True
- Selected sample column: `system_i/LTC2208_0_adc_data[15:0]`
- Selected column radix/format: `SIGNED`; bit width from name: 16; signed: True
- tvalid continuity: no tvalid/valid field present
- ADC overflow: system_i/LTC2208_0_adc_of never asserted
- Mean before de-mean: 45.9609 ADC codes

| Column | Radix | Numeric | Unique | Min | Max | Mean | Std | Score |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `Sample in Buffer` | UNSIGNED | 1024 | 1024 | 0 | 1023 | 511.5 | 295.603 | -6 |
| `Sample in Window` | UNSIGNED | 1024 | 1024 | 0 | 1023 | 511.5 | 295.603 | -6 |
| `TRIGGER` | UNSIGNED | 1024 | 2 | 0 | 1 | 0.000976562 | 0.0312347 | -5 |
| `system_i/LTC2208_0_adc_data[15:0]` | SIGNED | 1024 | 188 | -57 | 144 | 45.9609 | 55.8486 | 20 |
| `system_i/LTC2208_0_m_axis_aclk` | HEX | 1024 | 1 | 0 | 0 | 0 | 0 | -5 |
| `system_i/LTC2208_0_adc_of` | HEX | 1024 | 1 | 0 | 0 | 0 | 0 | 1 |

## FFT Results

| File | Samples | Bin spacing (Hz) | Peak bin (Hz) | Interpolated peak (Hz) | Peak relative dB | Top peaks Hz:dB |
|---|---:|---:|---:|---:|---:|---|
| iladata_1.0000G.csv | 1024 | 126953.125 | 39990234.4 | 40000643.9 | 37.8764 | 39990234.375:37.88<br>62333984.375:7.02<br>55732421.875:6.10<br>45576171.875:4.78<br>60937500.000:4.72 |
| iladata_1.0001G.csv | 1024 | 126953.125 | 40117187.5 | 40099003.7 | 37.7218 | 40117187.500:37.72<br>59414062.500:8.55<br>42529296.875:6.31<br>50019531.250:6.19<br>64492187.500:5.63 |

With 1024 samples at 130 MHz, the FFT bin spacing is 126953.125 Hz (126.953 kHz), so a 100 kHz shift is about 0.788 bin.

## 40.000 MHz vs 40.100 MHz Check

- `iladata_1.0000G.csv`: interpolated peak 40.000644 MHz; error vs 40.000 MHz = +0.644 kHz, vs 40.100 MHz = -99.356 kHz. Nearest reference: 40.000 MHz.
- `iladata_1.0001G.csv`: interpolated peak 40.099004 MHz; error vs 40.000 MHz = +99.004 kHz, vs 40.100 MHz = -0.996 kHz. Nearest reference: 40.100 MHz.
- Filename-paired delta: `iladata_1.0001G.csv` - `iladata_1.0000G.csv` = 98.360 kHz.
- This is consistent with a +100 kHz offset after sub-bin interpolation, but the native FFT bin spacing is coarser than 100 kHz.

## Generated Plots

- `iladata_1.0000G.csv` spectrum: `iladata_1.0000G_spectrum.png`
- `iladata_1.0000G.csv` time series: `iladata_1.0000G_time.png`
- `iladata_1.0001G.csv` spectrum: `iladata_1.0001G_spectrum.png`
- `iladata_1.0001G.csv` time series: `iladata_1.0001G_time.png`

## Data Quality and Uncertainties

- The captures are short: 1024 samples at 130 MHz is about 7.877 us, so native FFT resolution is coarse for proving a 100 kHz separation.
- The two current CSV files expose `system_i/LTC2208_0_adc_data[15:0]` as a signed 16-bit ADC-looking probe; they do not expose AXI `tdata/tvalid/tlast` handshake probes.
- The `system_i/LTC2208_0_m_axis_aclk` column is constant in the export and cannot be used to derive sample rate.
- `system_i/LTC2208_0_adc_of` remains 0 in the parsed files, so no ADC overflow is visible in these captures.
- The RF condition is inferred from filenames only. If a future export includes ILA metadata, clock constraints, or experiment labels, add it to the report instead of relying on filenames.
- Sub-bin peak interpolation is useful here, but longer captures or repeated captures would make the 40.000/40.100 MHz confirmation much stronger.

## Reproduce

```powershell
python docs\ila_data_analysis_2026_06_04\analyze_ila_data.py
```