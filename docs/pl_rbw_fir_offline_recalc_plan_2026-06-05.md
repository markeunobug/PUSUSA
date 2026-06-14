# PL RBW FIR 离线重算/复核预研

日期：2026-06-05

## 1. 目标和边界

本文只负责 PuSuSA 最终 PL RBW 方案中的 **RBW ENBW FIR 参数离线重算/复核**，不修改固件代码、不修改 PL 抽取树、不定义 PS/PL 寄存器接口。PL 抽取树和接口字段由其他预研文档继续负责。

本轮固定采用以下最终测量采样率：

| RBW 模式 | 最终 Fs | 总抽取率 |
| ---: | ---: | ---: |
| 1 MHz | 10 MSPS | /13 |
| 300 kHz | 3.25 MSPS | /40 |
| 100 kHz | 1 MSPS | /130 |
| 30 kHz | 325 kSPS | /400 |
| 10 kHz | 100 kSPS | /1300 |
| 1 kHz | 100 kSPS | /1300 |

RBW FIR 的离线设计以实际 ENBW 为准：

```text
ENBW = Fs * sum(h.^2) / (sum(h)^2)
correction_dB = 10 * log10(ENBW / nominal_RBW)
```

注意：这里讨论的 RBW FIR 是最终分辨率带宽定义滤波器，不替代 PL 多级抽取中的抗混叠滤波器。MATLAB 报告需要明确区分“抽取抗混叠滤波器”和“RBW ENBW FIR”。

## 2. 已对齐资料

已阅读并对齐：

- `docs/pl_iq_rbw_config_table_2026-06-05.md`
- `docs/pl_ddc_decimation_architecture_plan_2026-06-04.md`
- `docs/rbw_filter_analysis/rbw_scheme_b_current_parameters.md`
- `code/pusu_20260604/vitis/pusu_20260604/src/rbw_filter_coeffs.c`
- `code/pusu_20260604/vitis/pusu_20260604/src/app_config.h`

关键背景：

- 最终可信路径应是 PL 连续流：ADC -> DDC -> per-mode decimation -> RBW FIR -> power accumulation。
- 现有 `app_config.h` 仍包含历史 CIC/PS 侧验证参数和 1 MSPS debug IQ 路径，不能直接当作最终 PL 多 RBW 冻结表。
- `rbw_filter_coeffs.c` 中 30K/300K 系数来自旧 Scheme B 采样率；10K 系数来自 `r130_validation`，不是 Scheme B 原始 10K 版本。

## 3. 旧 Scheme B 沿用判断

| RBW | Scheme B Fs | 最终 Fs | 旧系数处理 | 结论 |
| ---: | ---: | ---: | --- | --- |
| 1 kHz | 100 kSPS | 100 kSPS | 可复核沿用 | 768-tap Kaiser 可作为候选；需复核 float/fixed 指标。 |
| 10 kHz | 100 kSPS | 100 kSPS | 可沿用采样率，但需统一版本 | Scheme B 文档值为 9949.76 Hz；当前固件 10K 系数为 10001.51 Hz，需要 MATLAB 并排复核后冻结一个版本。 |
| 30 kHz | 300.23 kSPS | 325 kSPS | 必须重算 | Fs 改为 /400 后 ENBW、droop、2x/5x 指标不能直接继承。 |
| 100 kHz | 1 MSPS | 1 MSPS | 可复核沿用 | 128-tap Hamming-sinc 可作为候选；需复核无 CIC 最终链路条件。 |
| 300 kHz | 3.023 MSPS | 3.25 MSPS | 必须重算 | Fs 改为 /40 后旧 128-tap 形状只能作初值参考。 |
| 1 MHz | 10 MSPS | 10 MSPS | 可复核沿用 | 96-tap Kaiser 可作为候选；需复核无 CIC 最终链路条件。 |

本轮重点重算项是 **300K@3.25MSPS** 和 **30K@325kSPS**。

## 4. 每个 RBW 的 FIR 设计输入

通带 droop 建议统一在 `0 ~ 0.45 * RBW` 统计；阻带观察点至少包含 `2x RBW`、`5x RBW`，并输出到 Nyquist 的全响应曲线。对于 30K 和 300K，`5x RBW` 靠近 Nyquist，需要在报告中单独标注其余量。

| RBW | Fs | 目标 ENBW | taps 搜索/复核范围 | 通带观察点 | 阻带观察点 | 备注 |
| ---: | ---: | ---: | --- | --- | --- | --- |
| 1 kHz | 100 kSPS | 1 kHz | 768 复核；1024 备选 | 0, 0.25K, 0.45K | 2K, 5K, 10K, 10.2K | 10K/10.2K 用于确认窄 RBW alias 风险已解除。 |
| 10 kHz | 100 kSPS | 10 kHz | 256 复核；320 备选 | 0, 2.5K, 4.5K | 20K, 50K, Nyquist 附近 | 并排比较 Scheme B 10K 与当前 `r130_validation` 10K。 |
| 30 kHz | 325 kSPS | 30 kHz | 192, 256, 320, 384 | 0, 7.5K, 13.5K | 60K, 150K, 162.5K | 必须重算；优先争取 256 taps 通过。 |
| 100 kHz | 1 MSPS | 100 kHz | 128 复核；160 备选 | 0, 25K, 45K | 200K, 500K, Nyquist | 旧 Fs 一致，可复核沿用。 |
| 300 kHz | 3.25 MSPS | 300 kHz | 96, 128, 160, 192 | 0, 75K, 135K | 600K, 1.5M, 1.625M | 必须重算；优先争取 128 taps 通过。 |
| 1 MHz | 10 MSPS | 1 MHz | 96 复核；128 备选 | 0, 250K, 450K | 2M, 5M, Nyquist | 旧 Fs 一致，可复核沿用。 |

## 5. MATLAB 离线计算任务清单

### 5.1 输入扫描

对每个 RBW 模式生成候选集合：

- 固定 `Fs` 和 nominal RBW。
- 扫描 taps、window、beta、cutoff。
- windowed-sinc 作为基础方法；Kaiser 用于需要调 beta 的模式；Hamming-sinc 用于 100K/300K 这类旧方案已表现稳定的宽 RBW 候选。
- 对每个候选用 cutoff 网格或二分搜索，使 ENBW 接近 nominal RBW。

建议初始扫描：

| RBW | 初始方法 | cutoff 扫描 | beta 扫描 |
| ---: | --- | --- | --- |
| 1 kHz | Kaiser | 0.50:0.005:0.56 * RBW | 3, 4, 5 |
| 10 kHz | Kaiser | 0.50:0.005:0.56 * RBW | 4, 5, 6 |
| 30 kHz | Kaiser + Hamming-sinc | 0.50:0.005:0.56 * RBW | 4, 5, 6 |
| 100 kHz | Hamming-sinc + Kaiser | 0.50:0.01:0.58 * RBW | 4, 5 |
| 300 kHz | Hamming-sinc + Kaiser | 0.50:0.01:0.58 * RBW | 3, 4, 5, 6 |
| 1 MHz | Kaiser | 0.50:0.01:0.58 * RBW | 4, 5 |

### 5.2 判据

| 指标 | 推荐冻结目标 | 最低可接受线 |
| --- | ---: | ---: |
| ENBW/RBW | 0.99 到 1.01 | 0.95 到 1.05 |
| ENBW correction | abs <= 0.05 dB | abs <= 0.22 dB |
| passband droop | <= 0.15 dB | <= 0.20 dB；1K 可放宽到 <= 0.25 dB |
| 2x RBW 抑制 | <= -70 dB | <= -60 dB |
| 5x RBW 抑制 | <= -90 dB | <= -80 dB；靠近 Nyquist 时可作为工程目标上报 |
| DC gain | 0 dB 归一 | 必须统一归一 |
| float/fixed ENBW delta | <= 0.02 dB | <= 0.05 dB |

工程 taps 上限建议：

| RBW | 首选上限 | 硬上限 | 说明 |
| ---: | ---: | ---: | --- |
| 1 kHz | 768 | 1024 | 1024 仅在 768 指标不足时启用。 |
| 10 kHz | 256 | 320 | 优先解决版本统一，不主动增大。 |
| 30 kHz | 256 | 384 | 325 kSPS 下 5x 靠近 Nyquist，可能需要 320。 |
| 100 kHz | 128 | 160 | 旧 128 taps 应优先保留。 |
| 300 kHz | 128 | 192 | 3.25 MSPS 下优先保留 128 taps。 |
| 1 MHz | 96 | 128 | 旧 96 taps 应优先保留。 |

### 5.3 必须输出

建议输出到新的离线结果目录，例如：

```text
docs/rbw_filter_analysis/pl_final_2026-06-05/
```

必须产物：

| 文件 | 内容 |
| --- | --- |
| `pl_final_rbw_tap_sweep.csv` | 全部 taps/window/beta/cutoff 扫描记录。 |
| `pl_final_rbw_metrics.csv` | 每个候选的 ENBW、correction、droop、2x/5x 抑制、Nyquist 余量。 |
| `pl_final_rbw_selected.md` | 最终推荐候选表和淘汰理由。 |
| `pl_final_rbw_coefficients_float.csv` | 最终 float 系数。 |
| `pl_final_rbw_coefficients_fixed.csv` | 固定 Q 格式的量化系数及缩放说明。 |
| `pl_final_rbw_response_<mode>.csv` | 每个模式的频响曲线数据。 |
| `pl_final_rbw_response_<mode>.png` | 标注 RBW、2x、5x、Nyquist 的响应图。 |
| `pl_final_rbw_summary_for_firmware.md` | 给固件/PL 接入使用的冻结参数摘要。 |

建议额外输出：

- `pl_final_rbw_quantization_delta.csv`：float 与 fixed 指标差异。
- `pl_final_rbw_group_delay.csv`：group delay、skip 建议、minimum accum target。
- `pl_final_rbw_power_window_noise.csv`：不同 observe 长度下的功率抖动估计，用于决定 10K 是否保留 2560 observe。

## 6. 候选参数表草案

未知处用 `TBD`，等待 MATLAB 重算/复核冻结。

| RBW | Fs | 总抽取率 | FIR taps | method / 初值 | actual ENBW | correction dB | observe | skip | accum target | 状态 |
| ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | --- |
| 1 kHz | 100 kSPS | 1300 | 768 | Kaiser, cutoff=520 Hz, beta=3 | 983.29 Hz | -0.07 | 256 | 128 | 1152 | 复核沿用候选；1024 taps 作为备选。 |
| 10 kHz | 100 kSPS | 1300 | 256 | TBD：Scheme B 或 `r130_validation` 二选一 | TBD | TBD | 256 或 2560 | 128 | 640 或 2944 | 采样率可沿用，但需统一系数来源。 |
| 30 kHz | 325 kSPS | 400 | TBD，首选 256 | Kaiser/Hamming-sinc 扫描 | TBD | TBD | 256 | 128 | TBD | 必须重算；若 taps=256，则 accum=640。 |
| 100 kHz | 1 MSPS | 130 | 128 | Hamming-sinc, cutoff=54 kHz | 100.02 kHz | +0.00 | 384 | 64 | 576 | 复核沿用候选。 |
| 300 kHz | 3.25 MSPS | 40 | TBD，首选 128 | Hamming-sinc/Kaiser 扫描 | TBD | TBD | 384 | 64 | TBD | 必须重算；若 taps=128，则 accum=576。 |
| 1 MHz | 10 MSPS | 13 | 96 | Kaiser, cutoff=540 kHz, beta=4 | 990.88 kHz | -0.04 | 384 | 32 | 512 | 复核沿用候选。 |

`accum target = observe + skip + taps`。30K 和 300K 在 taps 未冻结前保留 TBD；表中给出首选 taps 对应的参考值，方便后续系统预算。

## 7. 重点重算项

### 7.1 300 kHz at 3.25 MSPS

最终 Fs 为 `130 MSPS / 40 = 3.25 MSPS`，旧 Scheme B 使用 `130 MSPS / 43 = 3.0232558 MSPS`。旧 300K 系数只能作为形状参考，不能继承 ENBW 和 correction。

MATLAB 任务：

- 扫描 taps = 96, 128, 160, 192。
- 扫描 Hamming-sinc 与 Kaiser。
- cutoff 从 `0.50 * RBW` 到 `0.58 * RBW`。
- 输出 600 kHz、1.5 MHz、Nyquist 1.625 MHz 的抑制。
- 优先选择满足指标的最小 taps；预计先尝试冻结 128 taps。

特别风险：

- `5x RBW = 1.5 MHz`，距离 Nyquist `1.625 MHz` 较近，频响图必须高分辨率输出。
- 如果 5x 抑制难以达到 -90 dB，但 2x、ENBW、droop 均达标，需要把 5x 标为工程目标而不是隐含失败。

### 7.2 30 kHz at 325 kSPS

最终 Fs 为 `130 MSPS / 400 = 325 kSPS`，旧 Scheme B 使用约 `300.23 kSPS`。旧 30K 的 `cutoff=15600 Hz, beta=5` 可以作为初值，但不能直接沿用指标。

MATLAB 任务：

- 扫描 taps = 192, 256, 320, 384。
- 扫描 Kaiser beta = 4, 5, 6；并保留 Hamming-sinc 对照。
- cutoff 从 `0.50 * RBW` 到 `0.56 * RBW`。
- 输出 60 kHz、150 kHz、Nyquist 162.5 kHz 的抑制。
- 优先冻结 256 taps；若 flatness 或 2x 抑制不足，再上探 320 taps。

特别风险：

- `5x RBW = 150 kHz`，接近 Nyquist `162.5 kHz`，5x 指标可能比 2x 指标更受采样率几何限制。
- 若 5x 与 droop 无法同时满足，优先保证 ENBW、correction、passband droop 和 2x 抑制，把 5x 作为工程风险上报。

## 8. 冻结前待确认

1. 10K 最终采用 Scheme B 的 `ENBW=9949.76 Hz`，还是当前固件 `r130_validation` 的 `ENBW=10001.51 Hz`。
2. 10K 的最终 observe 是回到 256，还是保留当前 2560 作为低方差测量窗口。
3. 30K/300K 的 5x RBW 抑制在接近 Nyquist 时是否作为硬门槛。
4. PL 固定点 Q 格式由 FIR Compiler/乘法器位宽决定；MATLAB 至少应给出一版 `Q1.15` 或 `Q1.17` 的量化复核。
5. 若 RBW FIR 和 power accumulation 下沉到 PL，同一冻结包还需要包含系数量化、累加位宽、溢出/饱和策略和标定缩放说明。

## 9. 预研结论

- 可复核沿用：1K、100K、1M。它们的最终 Fs 与 Scheme B 一致，旧系数可作为第一版最终候选，但仍需 float/fixed 指标复核。
- 10K：最终 Fs 与 Scheme B 一致，但当前固件系数来源不同，必须先并排复核并冻结一个版本。
- 必须重算：30K@325kSPS、300K@3.25MSPS。旧 Scheme B 的 ENBW、correction、droop、2x/5x 抑制不能直接沿用。
- 推荐首选目标：300K 尝试 128 taps 通过，30K 尝试 256 taps 通过；若 5x RBW 因靠近 Nyquist 余量不足，再分别上探到 160/320 taps。
- 固件/PL 接入前置条件：每个最终候选必须同时给出 `Fs、actual_enbw_hz、correction_dB、taps、observe、skip、accum_target`，并提供 float 与 fixed 两套指标。
