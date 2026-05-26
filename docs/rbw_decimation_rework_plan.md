# 窄 RBW 抽取架构重做计划

更新时间: 2026-05-23

## 1. 背景和最新结论

当前 1 kHz RBW 模式的数字链路为:

```text
ADC 130 MHz
-> DDC 到 40 MHz 基带
-> CIC R=13000, N=5
-> Fs_out = 10 kHz
-> FIR cutoff = 1 kHz
-> 功率统计
```

用户用外部仪器测 RF 混频器输出的 40 MHz IF 后发现:

1. LO 对准 1 GHz 时，载波在 40 MHz 附近正常出现。
2. LO 对准 1 GHz + 10 kHz 时，原 1 GHz 载波在 IF 上移动到约 39.9898 MHz，也就是相对 40 MHz 约 -10.2 kHz。
3. 外部仪器在 40.000 MHz 目标点没有看到明显干扰。

这说明模拟 IF 在目标频点是干净的，但本机数字测量仍可能把 -10 kHz 附近的大载波混叠进 1 kHz RBW 通带。

根因判断:

```text
1 kHz RBW 当前 Fs_out = 10 kHz
主载波相对目标频点约 -10 kHz
经过 10 kHz 采样后 alias 到接近 DC
alias 后落入 1 kHz RBW FIR 通带
```

因此问题不是单纯 FIR transient，也不是 RF 混频器输出 40 MHz 处真的有干扰，而是窄 RBW 模式在大倍率 CIC 前缺少足够抗混叠保护。

## 2. 修改目标

第一阶段目标是避免 1 kHz RBW 在 10 kHz 偏移点把主载波 alias 回通带。

核心原则:

```text
窄 RBW 的 CIC 输出采样率必须明显高于相噪 offset。
RBW 滤波主要由后级 FIR 实现，而不是直接把 CIC 输出采样率降到接近 RBW。
```

建议第一版配置:

| RBW | 当前 CIC R | 当前 Fs_out | 建议 CIC R | 建议 Fs_out | 说明 |
|---:|---:|---:|---:|---:|---|
| 1 kHz | 13000 | 10 kHz | 1300 | 100 kHz | 先解决 10 kHz offset alias |
| 10 kHz | 1300 | 100 kHz | 433 或 650 | 300 kHz 或 200 kHz | 避免 100 kHz 附近 alias |
| 30 kHz | 433 | 300 kHz | 260 或 325 | 500 kHz 或 400 kHz | 作为第二优先级检查 |
| 100 kHz+ | 保持 | 保持 | 暂不改 | 暂不改 | 先不扩大改动面 |

第一阶段可以只改 1 kHz RBW；10 kHz 和 30 kHz 由仿真结果决定是否同步改。

## 3. 风险点

1. **FIR 过渡带**

当前 FIR 是 Hamming-window sinc，1 kHz RBW、Fs_out=100 kHz、256 taps 时，滤波器相对较短。10 kHz 偏移应能压住，但 ENBW、通带形状、远端旁瓣需要仿真确认。

2. **计算量**

R 从 13000 降到 1300 后，同样采集时间内 CIC 输出点数增加 10 倍。若仍用当前 `observe + skip + taps` 目标点数，采集时间会缩短，但每点 FIR 输入长度仍受 `ACCUM_BUFFER_SIZE` 限制。

3. **频率响应校准**

改 R 后 CIC droop、FIR cutoff、ENBW 都会变化，必须重新生成 RBW 响应图和 ENBW 修正数据。

4. **点数和 DMA**

`ACCUM_BUFFER_SIZE=768`。当前修复后的 FIR 窗口要求:

```text
accum_target = observe + skip + taps
out_len = accum_target - (taps - 1 + skip)
```

所以如果 `observe=256`，最终输出点数约 257。改 R 不应破坏这个几何关系。

## 4. 子任务分工

### Agent A: 固件 RBW 参数和安全性修改

目标: 调整窄 RBW 的 CIC decimation ratio，让 1 kHz RBW 的 `Fs_out` 从 10 kHz 提高到 100 kHz。

写入范围:

- `code/pusu_20260516/vitis/pusu_20260516/src/app_config.h`
- 如有必要，少量调整 `signal_processing.c` 中与 buffer、tap 上限相关的代码

建议第一版改动:

```c
#define RBW_1K_CIC_R          1300U
#define RBW_1K_CIC_N          5U
#define RBW_1K_FIR_TAPS       256U
#define RBW_1K_OBSERVE_POINTS 256U
#define RBW_1K_SKIP_POINTS    128U
```

注意:

- 不要修改相噪规划。
- 不要修改 carrier search。
- 不要回退 FIR transient 窗口修复。
- 检查 `comp_fir_coeffs` 和 `comp_fir_state` 的最大 taps 是否仍足够。
- 检查 `DMA_SWEEP_MAX_BLOCKS_PER_TRANSFER` 下 1 kHz 模式是否还能一次或多次采够 `accum_target`。

验收:

- 1 kHz RBW `Fs_out=100 kHz`。
- `accum_target <= ACCUM_BUFFER_SIZE`。
- `out_len > 0`。
- `git diff --check` 通过。
- 如本机工具链可用，至少做目标文件级语法/编译检查。

### Agent B: 离线仿真和图表更新

目标: 用当前分析脚本验证新 RBW 配置能消除 10 kHz offset alias。

写入范围:

- `tools/rbw_filter_analysis.py`
- `docs/rbw_filter_analysis/`

要求:

1. 增加或更新 alias 风险图，重点比较:
   - 旧 1K: R=13000, Fs_out=10 kHz
   - 新 1K: R=1300, Fs_out=100 kHz
2. 输出 1 kHz RBW 在以下偏移点的有限窗口响应:
   - 1 kHz
   - 3 kHz
   - 10 kHz
   - 10.2 kHz
   - 14 kHz
   - 100 kHz
3. 生成新的 summary，包含:
   - 3 dB bandwidth
   - ENBW
   - 10 kHz offset carrier rejection
   - 10.2 kHz offset carrier rejection
4. 如果只改 1 kHz RBW 后 10 kHz offset 抑制仍不够，提出 FIR taps 或窗口结构建议。

建议输出:

- `docs/rbw_filter_analysis/rbw_decimation_rework_summary.md`
- `docs/rbw_filter_analysis/rbw_decimation_alias_comparison.png`
- `docs/rbw_filter_analysis/rbw_decimation_alias_comparison.csv`

验收:

- 新 1 kHz RBW 在 10 kHz 和 10.2 kHz 偏移不再 alias 回通带。
- 图中能清楚看到旧配置的 alias 失败和新配置的改善。

### Agent C: 相噪 RBW 规划审计和后续改动建议

目标: 审计相噪 offset 到 RBW 的选择逻辑，提出与新抽取架构匹配的规划。

读取范围:

- `code/pusu_20260516/vitis/pusu_20260516/src/phase_noise_plan.c`
- `code/pusu_20260516/vitis/pusu_20260516/src/phase_noise_engine.c`
- 上位机 phase noise 相关显示和 CSV 文件

要求:

1. 只读审计，不直接改代码。
2. 明确当前 `offset=10 kHz` 是否会选择 10 kHz RBW，还是用户实际界面强制成了 1 kHz RBW。
3. 给出新规划建议，例如 `RBW <= offset / 10`。
4. 给出哪些 offset 点应标记为不可靠，例如 `offset < 10 * RBW`。
5. 明确 carrier search 是否也应使用新 1 kHz RBW 的高 Fs_out 路径。

验收:

- 输出后续相噪规划修改建议。
- 不修改任何文件。

## 5. 主线集成顺序

1. Agent B 先用“临时参数”仿真新 1 kHz RBW，确认方案有效。
2. Agent A 修改固件参数。
3. 主线运行 `tools/rbw_filter_analysis.py`，生成新图和 CSV。
4. 烧录固件后复测:
   - 1 GHz 输入
   - 相噪 10 kHz offset
   - 标准扫频 100 kHz RBW
   - 1 kHz RBW 下测 1 GHz + 10 kHz 点
5. 根据 Agent C 的建议，再改相噪 RBW 规划。

## 6. 硬件复测清单

### 6.1 关键复测

配置:

- 输入: 1 GHz 单音
- 相噪 offset: 1 kHz 到 1 MHz
- 重点 marker: 10 kHz

期待:

- `10 kHz offset` 不再被 1 GHz 主载波 alias 主导。
- `Measured Level` 与标准扫频 carrier level 差距缩小。
- `Initial Delta` 仍需单独观察，但不应再导致 10 kHz 点被大载波 alias。

### 6.2 IF 对照

继续用外部仪器观察 40 MHz IF:

- LO 对准 1 GHz，确认 carrier 在 40 MHz。
- LO 对准 1 GHz + 10 kHz，确认 carrier 在 39.99 MHz 附近。
- 本机新固件此时测 1 GHz + 10 kHz，应不再把 39.99 MHz 强载波当成 40 MHz 通带信号。

## 7. 暂不做

1. 暂不重写整个多级 DDC 架构。
2. 暂不引入复杂 polyphase/halfband filter。
3. 暂不改 carrier search，除非新 1 kHz RBW 验证后仍有大偏差。
4. 暂不改 ENBW 绝对校准，先解决 alias。

## 8. 子 agent 分派记录

| 子任务 | Agent | 状态 | 备注 |
|---|---|---|---|
| Agent A: 固件 RBW 参数和安全性修改 | Harvey `019e556e-f31b-7e10-be11-f572b0072aba` | 已完成 | `RBW_1K_CIC_R` 改为 `1300U` |
| Agent B: 离线仿真和图表更新 | Chandrasekhar `019e556f-074e-7a71-ab15-2351d40df38f` | 进行中 | 输出 old/new alias 对比 |
| Agent C: 相噪 RBW 规划审计 | Cicero `019e556f-155e-79f1-b8a7-76181759a57b` | 已完成 | 只读审计 |

## 9. Agent A 实施摘要

已修改:

- `code/pusu_20260516/vitis/pusu_20260516/src/app_config.h`

变更:

```c
#define RBW_1K_CIC_R          1300U
```

因此:

```text
1 kHz RBW Fs_out = 130 MHz / 1300 = 100 kHz
```

保持不变:

- `RBW_1K_CIC_N = 5`
- `RBW_1K_FIR_TAPS = 256`
- `RBW_1K_OBSERVE_POINTS = 256`
- `RBW_1K_SKIP_POINTS = 128`

安全性结论:

- `accum_target = 256 + 128 + 256 = 640 <= ACCUM_BUFFER_SIZE 768`
- `first_valid = 255 + 128 = 383`
- `out_len >= 257 > 0`
- 最大 taps 仍为 256，现有 FIR buffer 足够
- `signal_processing.c` 无需改动

验证:

- `git diff --check` 通过
- `signal_processing.c` ARM GCC `-fsyntax-only` 通过
- 完整 make 被旧 `.d` 文件的 Windows 绝对路径依赖解析问题挡住

## 10. Agent C 审计摘要

当前 `phase_noise_plan.c` 的映射是:

- `offset < 10 kHz` -> `RBW_MODE_1K`
- `10 kHz <= offset < 100 kHz` -> `RBW_MODE_10K`
- `100 kHz <= offset <= 1 MHz` -> `RBW_MODE_30K`
- `offset > 1 MHz` -> `RBW_MODE_100K`

所以精确 `10 kHz` 现在会选 `10 kHz RBW`，而不是 `1 kHz RBW`。这正是后续要修的规划问题之一。

推荐后续 RBW 规划:

```text
RBW <= offset / 10
且
carrier alias distance after CIC >= 约 10 * RBW
```

应标记不可靠的组合:

- `offset < 10 * RBW`
- `offset` 接近所选 RBW 模式 `Fs_out` 的整数倍，可能 alias 回 DC 或 RBW 通带
- 当前 `10 kHz <= offset < 100 kHz` 用 10K RBW 时，10 kHz 精确点尤其不可靠

carrier search 当前不受 1K RBW 改动影响，因为它固定使用 coarse 100K、fine 10K、step 1 kHz。后续如果复测仍偏低，再考虑局部 1K refinement 或插值寻峰。
