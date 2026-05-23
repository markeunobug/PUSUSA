# 相噪 RBW 误差根因排查与修复计划

更新时间: 2026-05-23

范围: 当前计划聚焦 1 GHz 输入信号在相噪与宽扫模式下出现的异常宽裙边、10 kHz 偏移相噪读数偏高、以及 RBW 滤波器实际抑制不符合预期的问题。

## 1. 现象归纳

1. 外部频谱仪测同一 1 GHz 信号，10 kHz 偏移相噪约为 -90 dBc/Hz 量级。
2. 本系统相噪界面在 10 kHz 偏移读到约 -33.8 dBc/Hz，指标与实际相差很大。
3. 标准扫频界面在 100 kHz RBW 下，1 GHz 单音周围出现很宽的裙边，约到 14 MHz 偏移才接近底噪。
4. 用户确认 10 kHz 偏移点当前使用的是 1 kHz RBW，因此仅把 offset < 100 kHz 全部规划成 1 kHz RBW 不能从根本上解决问题。

## 2. 当前核心判断

### H1: FIR 输出窗口取错，导致载波泄漏进入测量窗口

这是当前优先级最高的根因假设。

固件中 `apply_compensating_fir()` 对 CIC 后的 I/Q 数据做补偿 FIR。当前逻辑先对整段 `accum_i/accum_q` 做 FIR，然后从 `stage[comp_fir_skip]` 开始拷贝输出。对 CMSIS FIR 来说，FIR 输出前 `taps - 1` 个样点仍处于启动过渡过程。如果只跳过 `comp_fir_skip`，实际上把大量 FIR transient 数据放进功率统计窗口。

以 1 kHz RBW 为例:

- CIC 后累计点数约 640。
- FIR taps 约 256。
- skip 约 128。
- 当前窗口从 `stage[128]` 开始。
- 更合理的稳态窗口应从 `stage[255 + 128]` 附近开始，也就是 `comp_fir_taps - 1 + comp_fir_skip`。

这个错误会让一个强载波在偏移频点的滤波测量中留下很高的伪泄漏，表现为单音两侧宽裙边、相噪读数被大幅抬高。

### H2: 载波搜索可能没有锁在真实峰值中心

相噪界面中曾看到:

- `Measured Level: -17.14 dBm`
- 标准扫频中同一载波峰值约 `-3.54 dBm`
- `Initial Delta: 7.00 kHz`

如果载波搜索锁到滤波肩部或频率存在几 kHz 偏差，carrier level 会被低估。相噪公式使用 `noise_power - 10log10(RBW) - carrier_level`，carrier level 低估会直接把 dBc/Hz 抬高。

这不是唯一主因，但可能叠加 10 dB 以上误差。

### H3: 点 RBW、标记 RBW、UI 显示需要更清楚

相噪数据帧和 CSV 已包含每点 `rbw_hz`。但界面顶部的 `Point RBW` 更像是当前正在测量点的 RBW，不一定是 marker 所在点的 RBW。排查时必须以 CSV 每点 `rbw_hz` 为准。

另外，`Initial Delta` 目前显示绝对值，会丢失偏差方向，不利于判断载波搜索是偏高还是偏低。

### H4: ENBW 校准会带来小误差，但不是主因

当前离线仿真显示各 RBW 滤波器 ENBW 大约比名义 RBW 高 2.6 到 2.8 dB。这个会影响 dBc/Hz 的绝对值，但不足以解释 50 dB 以上偏差。

### H5: 模拟链路、LO 相噪、压缩或混频杂散需要在数字修复后复测

如果 H1 修复后仍存在大偏差，再系统性验证模拟链路和 LO。但从 100 kHz RBW 下宽裙边延伸到 14 MHz 的形态看，数字 FIR 窗口问题优先级更高。

## 3. 关键证据

### 3.1 固件疑点

文件:

- `code/pusu_20260516/vitis/pusu_20260516/src/signal_processing.c`

重点函数:

- `signal_processing_accumulate_dma()`
- `signal_processing_measure_accumulated_power_dbm()`
- `sweep_configure_for_rbw()`
- `apply_compensating_fir()`

疑点逻辑:

```c
int fir_out_len = accum_count - comp_fir_taps + 1;
arm_fir_f32(&inst, accum_i, stage_real, (uint32_t)accum_count);

for (i = comp_fir_skip; i < fir_out_len && (i - comp_fir_skip) < accum_count; i++) {
    accum_i[i - comp_fir_skip] = stage_real[i];
}
```

这里 `fir_out_len` 是有效卷积长度，但 `stage_real[i]` 的前 `comp_fir_taps - 1` 个输出仍受前置零状态影响。当前从 `comp_fir_skip` 开始取，窗口明显过早。

### 3.2 离线有限窗口仿真结论

对当前窗口与修正窗口进行有限长度仿真，初步结果如下:

| RBW 模式 | 偏移 | 当前窗口载波抑制 | 修正窗口载波抑制 |
|---|---:|---:|---:|
| 1 kHz | 10 kHz | 约 -48 dB | 约 -151 dB |
| 1 kHz | 14 kHz | 约 -51 dB | 约 -141 dB |
| 100 kHz | 1 MHz | 约 -50 dB | 约 -173 dB |
| 100 kHz | 10 MHz | 约 -70 dB | 约 -196 dB |
| 100 kHz | 14 MHz | 约 -73 dB | 约 -199 dB |

100 kHz RBW 下当前窗口在 14 MHz 附近只剩约 -73 dB 抑制，这和截图中 1 GHz 载波附近到 1.014 GHz 约 -71 dBm 的现象高度一致。

## 4. 子任务分工

### Agent A: 固件 FIR 窗口修复

目标: 修复 `apply_compensating_fir()` 的 FIR 输出取窗位置，避免 transient 样点进入功率统计。

写入范围:

- `code/pusu_20260516/vitis/pusu_20260516/src/signal_processing.c`

允许只在必要时读取相关头文件或配置文件，不做无关重构。

实施要求:

1. 确认 CMSIS `arm_fir_f32()` 输出时序。
2. 将 FIR 有效统计窗口起点改为 `comp_fir_taps - 1 + comp_fir_skip` 附近。
3. I/Q 使用完全相同的窗口。
4. 输出点数应由实际可用窗口计算，避免越界。
5. 保留当前 RBW 配置、CIC、幅度校准和串口协议不变。
6. 如果发现 off-by-one，写清楚选择理由。

建议伪代码:

```c
int first_valid = comp_fir_taps - 1 + comp_fir_skip;
if (first_valid >= accum_count) {
    accum_count = 0;
    return;
}

int out_len = accum_count - first_valid;
for (int i = 0; i < out_len; ++i) {
    accum_i[i] = stage_real[first_valid + i];
}
accum_count = out_len;
```

验收标准:

- 不发生数组越界。
- 1 kHz、10 kHz、100 kHz、1 MHz 等 RBW 模式均有正的输出点数。
- 修复范围尽量局限在 FIR 取窗，不混入 RBW 规划改动。

### Agent B: 离线滤波器有限窗口仿真

目标: 把“当前窗口”和“修正窗口”的传递/泄漏差异固化成脚本、CSV 和图。

写入范围:

- `tools/rbw_filter_analysis.py`
- `docs/rbw_filter_analysis/`

实施要求:

1. 在现有 RBW 分析脚本中加入有限窗口仿真。
2. 覆盖至少 1 kHz、10 kHz、100 kHz、1 MHz RBW。
3. 输出当前窗口与修正窗口的载波泄漏曲线。
4. 输出重点偏移点 CSV，例如 1 kHz、3 kHz、10 kHz、14 kHz、100 kHz、1 MHz、10 MHz、14 MHz。
5. 图名建议:
   - `rbw_finite_window_current_vs_fixed.png`
   - `rbw_finite_window_leakage_summary.csv`
   - `rbw_finite_window_summary.md`

验收标准:

- 脚本可以在当前 PC 上直接运行。
- 结果能清楚复现当前窗口在远偏移处抑制不足的问题。
- 图和 CSV 便于后续跟硬件截图对应。

### Agent C: 上位机相噪调试可视化

目标: 让界面和导出数据更容易判断相噪测量到底用了哪个 RBW、载波偏差方向是什么。

写入范围:

- `host_computer/flutter_pusu/lib/main.dart`
- 必要时读取或修改相噪 chart/model/export 相关文件。

实施要求:

1. `Initial Delta` 显示保留正负号，不再只显示绝对值。
2. Marker 信息优先显示 marker 对应点的 RBW，而不是仅显示当前扫描点 RBW。
3. 确认 CSV 中每点 `rbw_hz` 已导出；若已有则不要重复实现。
4. 不改变相噪计算公式，不改变串口协议。

验收标准:

- UI 能区分载波搜索偏高还是偏低。
- 用户在 10 kHz marker 上能看到该点真实使用的 RBW。
- 不影响现有相噪曲线绘制和 CSV 导出。

### Agent D: 载波搜索与 LO 频率审计

目标: 只读审计相噪载波搜索、LO 设频、频率量化与偏移测量路径，判断是否需要第二阶段改动。

读取范围:

- `code/pusu_20260516/vitis/pusu_20260516/src/phase_noise_engine.c`
- `code/pusu_20260516/vitis/pusu_20260516/src/phase_noise_plan.c`
- `code/pusu_20260516/vitis/pusu_20260516/src/lmx2572.c`
- `code/pusu_20260516/vitis/pusu_20260516/src/sweep.c`
- 上位机 phase noise 相关解析与显示文件

实施要求:

1. 确认 carrier coarse/fine search 使用的 RBW、步进和搜索 span。
2. 分析 `Initial Delta: 7 kHz` 是否可能来自搜索分辨率、滤波肩部、LO 量化或 UI 显示。
3. 检查相噪测量当前是否只测上边带 `carrier + offset`。
4. 检查 1 GHz 到 40 MHz IF 的 LO 计算路径中是否存在 kHz 级误差风险。
5. 输出建议，不直接修改代码。

验收标准:

- 给出是否需要把 fine search 改为 1 kHz RBW、100 Hz 步进或插值寻峰的判断。
- 给出是否需要支持 manual carrier lock 或跳过搜索的判断。
- 给出是否需要显示 carrier measured/nominal 差值和载波功率一致性检查的判断。

## 5. 集成顺序

1. 先完成 Agent B 的离线有限窗口仿真，作为修复前后的定量证据。
2. 完成 Agent A 的固件 FIR 窗口修复。
3. 运行离线脚本，确认修正窗口模型与预期一致。
4. 完成 Agent C 的上位机调试显示增强。
5. 根据 Agent D 的审计结论，决定是否进入第二阶段载波搜索优化。
6. 上板测试，比较修复前后的标准扫频宽裙边和相噪 10 kHz 读数。

## 6. 硬件验证清单

### 6.1 标准扫频验证

配置:

- 输入: 1 GHz 单音
- RBW: 100 kHz
- Span: 至少 100 MHz

观察:

- 1 GHz 附近宽裙边是否明显收窄。
- 1.014 GHz 附近是否不再出现约 -70 dBm 量级的载波泄漏平台。
- 改变输入衰减 10 dB 后，远端裙边是否跟随载波等比例变化。若跟随，说明仍是泄漏或压缩相关；若不跟随，接近底噪。

### 6.2 相噪验证

配置:

- 输入: 1 GHz 单音
- Offset: 1 kHz 到 1 MHz
- 确认导出 CSV 中 10 kHz 点的 `rbw_hz`

观察:

- 10 kHz 点 dBc/Hz 是否从 -30 dBc/Hz 量级显著下降。
- Marker RBW 是否与 CSV 每点 RBW 一致。
- `Measured Level` 是否接近标准扫频载波峰值，差异不应再有十几 dB。
- `Initial Delta` 是否稳定且方向明确。

### 6.3 链路隔离验证

建议步骤:

1. 50 欧输入或无信号，测底噪曲线。
2. 同一 40 MHz IF 直接注入 ADC 链路，与混频路径对比。
3. 固定输入功率，改变 RF 衰减、LNA、VGA，观察 dBc/Hz 是否随链路增益异常变化。
4. 用外部频谱仪同时看 40 MHz IF，确认模拟 IF 本身是否已有宽裙边。

## 7. 通过标准

1. 离线仿真能明确显示当前窗口和修正窗口在远偏移处的泄漏差异。
2. 固件 FIR 取窗修复后，100 kHz RBW 下 14 MHz 偏移处不再出现由数字滤波 transient 造成的约 -70 dBc 级泄漏。
3. 相噪 10 kHz 点读数不再被载波泄漏主导。
4. UI 和 CSV 能让用户直接确认 marker 点使用的 RBW、载波频偏方向和 carrier level。
5. 若修复后仍有偏差，剩余偏差可以被拆分到载波搜索、ENBW、模拟链路或 LO 相噪，而不是混在一起。

## 8. 暂不做的改动

1. 暂不修改 RBW 自动规划阈值，因为用户已确认 10 kHz 处当前用 1 kHz RBW，规划不是根因。
2. 暂不改变相噪公式，ENBW 修正作为后续小误差校准项处理。
3. 暂不改串口协议，除非后续需要上报更多诊断字段。
4. 暂不大改载波搜索流程，先等 FIR 窗口修复和复测结果。

## 9. 子 agent 分派记录

| 子任务 | Agent | 状态 | 备注 |
|---|---|---|---|
| Agent A: 固件 FIR 窗口修复 | Carson `019e53e2-4284-7b62-ba72-a8925225b680` | 已完成 | 写入范围限定在 `signal_processing.c` |
| Agent B: 离线有限窗口仿真 | Gibbs `019e53e2-56dd-7032-ae1e-178150d06f22` | 主线接管完成 | 原 agent 超时关闭，主线补齐仿真输出 |
| Agent C: 上位机相噪调试显示 | McClintock `019e53e2-6d63-7bd0-ab9e-42b9d71321e9` | 已完成 | 写入范围限定在 Flutter 相噪显示相关文件 |
| Agent D: 载波搜索与 LO 审计 | Schrodinger `019e53e2-81bb-7ef2-a91d-bb6f5e9c8c2a` | 已完成 | 只读审计，不直接改代码 |

## 10. Agent D 审计结论摘要

载波搜索和 LO 审计没有发现能单独解释 50 dB 级误差的 LO 量化问题，但确认了载波搜索会带来额外不确定性。

### 10.1 Carrier search 现状

固件默认载波搜索总 span 为 100 kHz:

- coarse RBW: 100 kHz
- 默认 coarse step: 5 kHz
- fine RBW: 10 kHz
- fine step: 1 kHz
- fine span: 围绕 coarse best 约 ±5 kHz
- 当前只选离散网格最大功率点，没有插值寻峰

因此 `Initial Delta: 7 kHz` 可能来自 1 kHz 网格点选择、真实频偏、滤波肩部最大点偏移，或者这些因素叠加。上位机此前用绝对值显示 Initial Delta，会丢失方向。

### 10.2 Sideband 现状

当前相噪测量路径只测上边带，也就是:

```text
target_frequency = measured_carrier + offset
```

这可能造成和外部频谱仪设置比较时的解释混淆，但不太像 50 dB 级异常的主因。

### 10.3 LO 量化风险

1 GHz 输入时:

- LO1 目标约 3.180 GHz
- LO2 固定约 2.220 GHz
- IF2 为 40 MHz
- LMX2572 使用约 100 MHz PFD 和 1,000,000 小数分母
- 计算得到的输出频率 LSB 约 50 Hz 级

`pll_num` 当前偏 floor 处理，可能有几十 Hz 级误差，但不是 kHz 级误差来源。

### 10.4 第二阶段建议

FIR 窗口修复和复测之后，再决定是否进入载波搜索优化:

1. 对 carrier search 增加三点抛物线插值寻峰。
2. 可选增加局部窄窗口 refinement，例如 1 kHz RBW + 100 Hz step，但不要默认扫完整 ±5 kHz，避免启动时间过长。
3. 增加 manual carrier lock 或 skip search 模式，让已知频率的测试不依赖自动寻峰。
4. UI/CSV 显示 signed Initial Delta、搜索 RBW、搜索 span/step、upper sideband only。
5. 低优先级清理 LO: `pll_num` 从 floor 改为 round，并记录实际 programmed LO。

## 11. Agent C 实施结论摘要

上位机相噪调试显示已完成，核心目标是让后续硬件复测更容易判断“测量点 RBW”和“载波偏差方向”。

已修改:

- `host_computer/flutter_pusu/lib/main.dart`
- `host_computer/flutter_pusu/lib/phase_noise_chart.dart`

改动摘要:

1. `Initial Delta` 改成带正负号显示，例如 `+7.00 kHz` 或 `-7.00 kHz`，不再只显示绝对值。
2. `PhaseNoiseMarker` 增加 marker 点对应的 `rbwHz`。
3. 有 marker 时，状态栏显示 `Marker RBW`；没有 marker 时回退显示当前测量点 `Point RBW`。
4. 图表内 marker 信息行和右侧控制面板 marker 文案也显示 marker 点 RBW。
5. 确认 CSV 已有每点 `rbw_hz` 导出，未重复新增字段。

验证状态:

- 已通过 `rg` 检查关键字段。
- 已通过 `git diff --check`。
- 当前 PC 的 PATH 找不到 `flutter`、`dart`、`fvm`，因此未运行 Flutter analyzer。

## 12. Agent A 实施结论摘要

固件 FIR 取窗修复已完成，关键位置:

- `code/pusu_20260516/vitis/pusu_20260516/src/signal_processing.c`

核心修复:

```c
first_valid = (comp_fir_taps - 1) + comp_fir_skip;
out_len = accum_count - first_valid;
```

然后 I/Q 都从 `stage[first_valid + i]` 回填，最后 `accum_count = out_len`。

off-by-one 选择理由:

CMSIS `arm_fir_f32()` 每输入一个样点输出一个样点，初始历史为 0；因此 `stage[0..taps-2]` 都包含前置零启动 transient，第一个完整 FIR 窗口输出是 `stage[taps - 1]`。配置的 `comp_fir_skip` 应叠加在 `taps - 1` 后，而不是从 `stage[comp_fir_skip]` 开始。

静态点数验算:

- 1K/10K/30K: 修正后 `out_len = 257`
- 100K/300K/1M: 修正后 `out_len = 385`

验证状态:

- 已通过 `git diff --check`。
- 目标文件级 `arm-none-eabi-gcc` 编译通过。
- 完整 `make all` 被当前 Vitis/GnuWin32 make 的自动生成依赖路径问题挡住: `No rule to make target C\\:\\learning\\...\\mylib/arm_math.h`。

## 13. Agent B 离线仿真实施结论摘要

原 Agent B 长时间未返回，已关闭并由主线接管完成。

已修改:

- `tools/rbw_filter_analysis.py`

已生成:

- `docs/rbw_filter_analysis/rbw_finite_window_current_vs_fixed.png`
- `docs/rbw_filter_analysis/rbw_finite_window_current_vs_fixed.csv`
- `docs/rbw_filter_analysis/rbw_finite_window_leakage_summary.csv`
- `docs/rbw_filter_analysis/rbw_finite_window_summary.md`

模型说明:

有限窗口仿真不再只使用 CIC 稳态幅频响应，而是模拟 CIC reset 后的零状态有限输出序列，再送入 FIR。这样可以正确复现 comb 零点附近的启动 transient 泄漏。

关键结果:

| 模式 | 偏移 | 当前窗口抑制 | 修复窗口抑制 | 当前等效读数 |
|---|---:|---:|---:|---:|
| 1K | 10 kHz | -48.03 dB | -304.29 dB | -78.03 dBc/Hz |
| 1K | 14 kHz | -50.97 dB | -140.97 dB | -80.97 dBc/Hz |
| 100K | 1 MHz | -49.85 dB | -325.28 dB | -99.85 dBc/Hz |
| 100K | 10 MHz | -69.80 dB | -322.49 dB | -119.80 dBc/Hz |
| 100K | 14 MHz | -72.64 dB | -308.71 dB | -122.64 dBc/Hz |

其中 100K RBW、14 MHz 偏移的当前窗口抑制约 -72.64 dB，和用户截图中 1 GHz 载波旁 1.014 GHz 附近约 -71 dBm 的宽裙边非常接近。

验证状态:

- `python tools\\rbw_filter_analysis.py` 运行通过。
- `git diff --check -- tools/rbw_filter_analysis.py` 通过。
