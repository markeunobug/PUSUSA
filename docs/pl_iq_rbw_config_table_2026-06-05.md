# PL 侧最终 RBW 配置表

更新日期：2026-06-05

## 定位

这份表是最终目标表，不是当前 `1 MSPS complex IQ` 调试路径的兼容表。

最终 RBW 设计应从指标反推架构：

1. 每个 RBW 模式先确定最终测量采样率。
2. 每个 RBW 模式使用与该采样率匹配的 ENBW FIR。
3. 抽取链必须在 PL 中保持连续状态，避免 PS DMA 分段造成滤波状态断裂。
4. 旧 CIC 只作为历史方案参考，最终可信 RBW 路径不依赖 CIC。
5. 后续逐步把 RBW FIR 和 power accumulation 也下沉到 PL。

## 总体链路

```text
ADC 130 MSPS real
  -> PL DDC 40 MHz, complex
  -> PL continuous FIR/polyphase decimation, per RBW mode
  -> RBW ENBW FIR, first in PS for validation, final in PL
  -> power accumulation / ENBW correction
  -> PS reads point power / status / debug IQ
```

## 最终 RBW 指标表

最终采样率层级已采用：

```text
1 MHz RBW   -> 10 MSPS
300 kHz RBW -> 3.25 MSPS
100 kHz RBW -> 1 MSPS
30 kHz RBW  -> 325 kSPS
10 kHz RBW  -> 100 kSPS
1 kHz RBW   -> 100 kSPS
```

MATLAB 离线重算输出：

```text
docs/rbw_filter_analysis/pl_final_recalc_2026_06_05/pl_final_rbw_selected_parameters.csv
docs/rbw_filter_analysis/pl_final_recalc_2026_06_05/pl_final_rbw_final_coefficients_float.csv
```

| RBW 模式 | 名义 RBW | 最终测量采样率 | 总抽取率 | 抽取实现目标 | RBW FIR taps | 实际 ENBW | ENBW/RBW | ENBW 校正 | Observe | Skip | Accum target | FIR 来源 | 最终状态 |
| --- | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| `RBW_MODE_1K` | 1 kHz | 100 kSPS | 1300 | PL 连续 FIR/polyphase decimator | 768 | 983.42 Hz | 0.9834 | -0.073 dB | 256 | 128 | 1152 | 当前固件系数复核 | PASS_ACCEPTABLE |
| `RBW_MODE_10K` | 10 kHz | 100 kSPS | 1300 | PL 连续 FIR/polyphase decimator | 256 | 10.090 kHz | 1.0090 | +0.039 dB | 2560 | 128 | 2944 | Scheme B 100 kSPS 系数 | PASS_STRICT |
| `RBW_MODE_30K` | 30 kHz | 325 kSPS | 400 | PL 连续 FIR/polyphase decimator | 192 | 30.643 kHz | 1.0214 | +0.092 dB | 256 | 128 | 576 | MATLAB 重算，cutoff=16.05 kHz, beta=6 | PASS_ACCEPTABLE |
| `RBW_MODE_100K` | 100 kHz | 1 MSPS | 130 | PL 连续 FIR/polyphase decimator | 128 | 101.478 kHz | 1.0148 | +0.064 dB | 384 | 64 | 576 | 当前固件系数复核 | PASS_ACCEPTABLE |
| `RBW_MODE_300K` | 300 kHz | 3.25 MSPS | 40 | PL 连续 FIR/polyphase decimator | 128 | 313.368 kHz | 1.0446 | +0.189 dB | 384 | 64 | 576 | MATLAB 重算，cutoff=165 kHz, beta=4 | PASS_ACCEPTABLE |
| `RBW_MODE_1M` | 1 MHz | 10 MSPS | 13 | PL 连续 FIR/polyphase decimator | 96 | 1.002220 MHz | 1.0022 | +0.010 dB | 384 | 32 | 512 | 当前固件系数复核 | PASS_ACCEPTABLE |

说明：

- 1 MHz、100 kHz、1 kHz 已完成无 CIC 条件复核，可作为第一版最终候选。
- 10 kHz 最终采用 Scheme B 的 `100 kSPS` 系数；当前固件 `r130_validation` 10 kHz 系数只属于 `1 MSPS` 验证路径，不能作为最终 `100 kSPS` 10 kHz RBW FIR。
- 300 kHz 和 30 kHz 已按新采样率完成 MATLAB 重算，分别冻结为 `128 taps` 和 `192 taps` 候选。
- “总抽取率”是 PL 连续抽取链的目标倍率，最终实现方式不再使用 CIC。
- 1 kHz 和 10 kHz 共用 `100 kSPS` 最终测量采样率。
- 1 MHz 不应在 `1 MSPS IQ` 调试路径里定义为可信 RBW；最终应使用 `10 MSPS` 测量采样率。

## MATLAB 复核风险备注

| RBW | 风险备注 |
| --- | --- |
| 1 MHz | `0~0.45*RBW` flatness 为 0.783 dB，最终是否接受取决于产品口径；`0~0.4*RBW` 为 0.066 dB。 |
| 300 kHz | ENBW/RBW 为 1.0446，接近 +5% 上限但仍在接受范围内。 |
| 100 kHz | `0~0.45*RBW` flatness 为 0.453 dB，最终是否接受取决于产品口径；`0~0.4*RBW` 为 0.034 dB。 |
| 30 kHz | 5x RBW 抑制为 -87.39 dB，未到 -90 dB，但 5x 检查点接近 Nyquist，当前标记为 PASS_ACCEPTABLE。 |
| 10 kHz | 已解决系数冲突，必须使用 Scheme B 100 kSPS 版本。 |
| 1 kHz | `0~0.45*RBW` flatness 为 1.517 dB，沿用早期对 1 kHz 放宽的口径；若后续要求更严，需要重新提高 taps。 |

## 抽取链设计原则

最终 PL 侧抽取器不是旧 CIC 的替代名字，而是新的连续多速率滤波链。

必须满足：

1. 抽取前有足够抗混叠滤波。
2. 跨 DMA、跨扫频点的内部状态连续可控。
3. 对 RBW 通带内平坦度影响可标定或可忽略。
4. 输出给 RBW FIR 的采样率与离线系数完全一致。
5. 允许每个 RBW 模式使用不同输出采样率，而不是强行统一到 1 MSPS。

建议的 PL 实现路线：

| 阶段 | 内容 | 目的 |
| --- | --- | --- |
| Stage 0 | 40 MHz NCO/DDC | 将 40 MHz IF 搬移到 complex baseband。 |
| Stage 1 | per-mode continuous decimator | 根据 RBW 输出 10 MSPS / 3.25 MSPS / 1 MSPS / 325 kSPS / 100 kSPS。 |
| Stage 2 | RBW ENBW FIR | 实现最终 RBW 带宽定义。第一版可留在 PS 验证，最终下沉 PL。 |
| Stage 3 | power accumulation | 对 FIR 输出做功率累加、平均和 ENBW 校正。 |
| Stage 4 | AXI-lite/status/DMA debug | PS 读取点功率，必要时导出低速 debug IQ。 |

## 与当前 1 MSPS 调试路径的区别

当前已经跑通的 `1 MSPS complex IQ` 路径只适合验证：

- PL DDC 方向是否正确。
- DMA AXIS 链路是否连续。
- PS 是否能正确解释 packed IQ。
- 100 kHz RBW 附近的初步测量链。

它不适合作为最终多 RBW 架构，因为：

- 1 MHz RBW 需要约 10 MSPS 测量采样率。
- 300 kHz RBW 的最终目标采样率是 3.25 MSPS，需要重新冻结 FIR。
- 30 kHz RBW 的最终目标采样率是 325 kSPS，需要重新冻结 FIR。
- 把所有模式硬塞到 1 MSPS 会导致部分旧 ENBW 系数失效。

所以当前 `1 MSPS IQ` 应定位为 bring-up/debug path，最终产品路径应按上表做 per-RBW PL 输出。

## PS 端配置结构建议

最终建议新增一张 PL RBW 模式表：

```c
typedef struct {
    rbw_mode_t mode;
    float nominal_rbw_hz;
    float pl_output_sample_rate_hz;
    uint16_t total_decimation;
    uint16_t rbw_fir_taps;
    float actual_enbw_hz;
    float enbw_correction_db;
    uint16_t observe_points;
    uint16_t skip_points;
    uint16_t accum_target;
    uint8_t pl_rbw_fir_enabled;
    uint8_t pl_power_accum_enabled;
} pl_rbw_mode_config_t;
```

第一阶段可以这样落地：

1. PL 只做 DDC + per-mode decimation，RBW FIR 和 power 仍在 PS。
2. PS 按 `pl_output_sample_rate_hz` 选择对应 FIR 系数。
3. 验证每个 RBW 模式的单点功率、offset 响应、ENBW 校正。
4. 验证通过后，再把 `pl_rbw_fir_enabled` 和 `pl_power_accum_enabled` 分模式打开。

## 下一步冻结项

1. 为每个总抽取率设计 PL 抗混叠 decimator。
2. 第一版实现 PL 输出 per-RBW decimated IQ，PS 继续做 RBW FIR/power。
3. 决定 debug DMA 输出位置：第一版固定为抽取后 IQ，后续支持 RBW FIR 后 IQ 和最终点功率。
4. 在 PS 协议里增加 PL RBW mode/status 字段，避免上位机把 bring-up 模式误认为最终 RBW 模式。
5. 完成实测后再决定是否收紧 1 MHz、100 kHz、1 kHz 的更严格 flatness 口径。
