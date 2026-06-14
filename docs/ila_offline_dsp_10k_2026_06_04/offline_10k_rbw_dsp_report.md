# 10K RBW ILA Raw ADC Offline DSP Validation

## Verdict

- 原始 ILA 每个文件只有 1024 点，小于当前固件 10K A 方案 FIR decimator 的 8192 taps，不能直接产生稳态 decimated output。
- 1024 点最多只能触发 7 个 /130 decimator 输出；后级 10K FIR 还需要 first_valid=383，所以直接 raw capture 无法给出最终功率。
- 用 ILA 估计幅度合成 400000 点长记录后，40.100 MHz 相对 40.000 MHz 的最终输出功率降低 -61.53 dB；该数值受固件 EPSILON 地板限制。
- 理论频响在 100 kHz offset 处：decimator=-76.85 dB，后级 10K FIR=-80.18 dB，合计=-157.03 dB。

## Firmware Parameters Used

- Source: `code\pusu_20260516\vitis\pusu_20260516\src\app_config.h` and `code\pusu_20260516\vitis\pusu_20260516\src\rbw_filter_coeffs.c`
- ADC Fs: 130.000000 MHz
- DDC NCO: 40.000000 MHz, real=x*cos, imag=x*(-sin)
- FIR decimator: R=130, taps=8192, cutoff=50000 Hz, Kaiser beta=6.0
- Decimated Fs: 1.000000 MHz
- Post 10K FIR: taps=256, observe=2560, skip=128, first_valid=383
- Accumulation target: 2944 decimated samples

## ILA Short Record Results

| File | Samples | Selected column | Mean code | RMS code | Hann peak MHz | Model freq MHz | Fit amp code | Decim outputs | Final valid outputs | Direct power dBFS |
|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|
| iladata_1.0000G.csv | 1024 | `system_i/LTC2208_0_adc_data[15:0]` | 44.985 | 72.015 | 40.000644 | 40.000000 | 78.418 | 7 | 0 | n/a |
| iladata_1.0001G.csv | 1024 | `system_i/LTC2208_0_adc_data[15:0]` | 45.961 | 72.329 | 40.099004 | 40.100000 | 77.933 | 7 | 0 | n/a |

- `iladata_1.0000G.csv`: Only 1024 raw samples are present; this is shorter than the 8192-tap FIR decimator, so all direct decimator outputs are startup transient.
- `iladata_1.0000G.csv`: Post-RBW FIR needs first_valid=383 decimated samples; short record produced only 7.
- `iladata_1.0001G.csv`: Only 1024 raw samples are present; this is shorter than the 8192-tap FIR decimator, so all direct decimator outputs are startup transient.
- `iladata_1.0001G.csv`: Post-RBW FIR needs first_valid=383 decimated samples; short record produced only 7.

## Synthetic Long-Record Test

| Input freq MHz | Samples | ILA-derived amp code | Final valid outputs | Power dBFS | Unclamped dBFS | Power dBm | Relative to 40.000 MHz dB |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 40.000000 | 400000 | 78.176 | 2693 | -52.45 | -52.45 | -44.43 | 0.00 |
| 40.100000 | 400000 | 78.176 | 2693 | -113.98 | -209.48 | -105.96 | -61.53 |

Interpretation: 40.100 MHz mixes to a +100 kHz complex baseband tone. The current 10K chain should heavily reject that offset in offline math; the reported firmware-style power is clipped at the EPSILON floor when the residual falls below it.

## If Hardware Still Does Not Improve

如果理论/离线压制很好但板上仍不改善，下一步最像运行时问题，而不是这个滤波器的离线频响问题。优先查：

- 每个 sweep 点是否真的累积到 `accum_target=2944` 个 decimated samples；不足会导致后级 FIR 后没有有效功率。
- 8192-tap complex FIR decimator 是否过重，导致 sweep 状态机超时、丢帧或提前读功率。
- DMA 是否仍是一帧一帧 rearm，且总 rearm 次数足够；10K 需要大量 4096-sample frame 才能填满目标。
- DDC NCO 相位连续性和符号是否与 `ddc_mix_to_time_domain_sweep()` 一致；符号错通常会把 offset 放到相反频率，但功率滤波仍应按绝对 offset 受抑。
- 测量状态机是否在 `signal_processing_accumulation_ready()` 之前调用了功率计算，或 RBW mode/coeffs 是否没有真正切到 10K。
- 如果看到固定约 -105.99 dBm 一类地板值，要优先怀疑 `EPSILON` clamp 前没有有效能量到达功率计算。

## Generated Files

- `offline_10k_rbw_dsp.py`: reproducible script
- `ila_short_record_summary.csv`: direct ILA short-record checks
- `synthetic_power_summary.csv`: long synthetic record power comparison
- `theoretical_response.csv`: decimator/post-FIR/combined response
- `theoretical_10k_response.png`: frequency-response plot
- `synthetic_power_comparison.png`: synthetic output-power plot

## Reproduce

```powershell
python docs\ila_offline_dsp_10k_2026_06_04\offline_10k_rbw_dsp.py
```
