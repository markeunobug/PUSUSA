# 相位噪声点数密度优化计划

## 1. 背景

当前相位噪声页面已经能运行，图表整体观感正常，但曲线点数偏少。对比 Rohde & Schwarz
频谱仪的 Phase Noise 测量页面，1 kHz 到 1 MHz offset 范围内应有更密集的 offset 采样点，
尤其是对数横轴上每个 decade 内不应只出现少量折线段。

这次优化的目标不是用视觉插值伪造测量结果，而是把真实测量点密度、图表显示能力和性能预算一起设计清楚。

## 2. 当前实现判断

活跃路径：

- Host：`host_computer/flutter_pusu`
- Firmware：`code/pusu_20260516/vitis/pusu_20260516/src`

关键现状：

- Demo 曲线在 `host_computer/flutter_pusu/lib/main.dart` 的 `_buildDemoPhaseNoiseSweep()` 中固定
  `pointCount = 121`，对应 1 kHz 到 1 MHz 约 `40 points/decade`。
- 固件相噪 offset 点表在 `phase_noise_plan.c` 中按 `points_per_decade` 生成：
  `raw_count = decades * points_per_decade + 1`。
- `phase_noise_engine.c` 当前限制 `points_per_decade <= 100`，`PHASE_NOISE_PLAN_MAX_POINTS = 256`。
- 协议工具 `tools/phase_noise_protocol_smoke_test.py` 默认 `points_per_decade = 20`，即 1 kHz 到
  1 MHz 只有约 61 个真实测量点。
- 当前 Host 相噪 UI 还没有暴露 `points_per_decade` 控件，也还没有真实 `0x86/0x87` parser/UI
  绑定；页面主要显示 demo 数据。
- `phase_noise_chart.dart` 使用 `fl_chart` 对已有点绘制折线，未发现明显图表抽稀逻辑。

## 3. 优化原则

1. **真实测量点优先**：密度提升应主要通过增加 offset 计划点数实现。
2. **显示平滑只作辅助**：可增加抗锯齿、曲线渲染或可选平滑线，但必须保留真实点数和 marker 对真实点吸附。
3. **默认值保守**：默认密度应让页面接近商用仪器观感，同时不让固件一次测量过慢。
4. **可配置**：给用户至少提供低/中/高密度档，必要时提供高级 points/decade 数值输入。
5. **性能可观测**：点数、估算测量耗时、串口包数、完成进度必须能看见或能在日志/CSV 中验证。

## 4. 建议目标

### 4.1 密度档位

建议 Host 使用三个显示给用户的密度档：

| 档位 | points/decade | 1 kHz 到 1 MHz 点数 | 用途 |
| --- | ---: | ---: | --- |
| Fast | 30 | 91 | 快速验证、低串口负载 |
| Normal | 60 | 181 | 默认，接近较密集仪器曲线 |
| Fine | 90 | 271 | 更细曲线，可能需要提高固件上限 |

说明：

- 如果固件保持 `PHASE_NOISE_PLAN_MAX_POINTS = 256`，Fine 在 3 decade 范围会被截断为 256 点。
- 若要完整支持 90 points/decade，应把固件最大点数提高到至少 `320` 或 `384`，并评估内存。
- 当前固件每点单独测量和回传，点数翻倍会近似线性增加测量时间。

### 4.2 默认策略

第一版建议：

- 默认 `points_per_decade = 60`。
- UI 默认显示 `Normal`。
- 允许用户选择 `Fast / Normal / Fine`。
- 若用户选择 Fine 但固件上限不足，Host 应显示“点数被固件限制”的 warning，而不是静默截断。

### 4.3 图表策略

- Chart 继续使用真实 offset 点绘制。
- Marker 继续吸附真实点，不吸附插值点。
- 可增加一个只影响显示的 `renderSmoothing` 开关，但 CSV、marker、状态栏必须使用真实点。
- 图表上建议显示：`Points: received/total` 或 `Density: 60 pts/dec`。

## 5. 技术拆分

### 5.1 Host 配置与 UI

新增/扩展模型：

- `PhaseNoiseConfig.pointsPerDecade`
- `PhaseNoiseDensityPreset { fast, normal, fine, custom }`

UI 控件建议放在 Offset 或 Average 面板中：

- Segmented/Button group：`Fast / Normal / Fine`
- 高级输入：`Pts/dec`，范围建议 `10..100`
- 状态显示：`Points: estimatedTotal` 或真实接入后显示 `received/total`

Demo 曲线：

- 不再写死 `pointCount = 121`。
- 根据 `pointsPerDecade` 和 offset decade 数计算 demo 点数。
- demo 曲线应能体现 Normal/Fine 的点数差异。

### 5.2 Host 协议接入

真实串口接入时：

- `SET_PHASE_NOISE_CONFIG` payload 的 `points_per_decade` 必须来自 Host 配置。
- parser 解析 `PHASE_NOISE_STATUS.total_points` 和 `PHASE_NOISE_DATA.total_points/current_index`。
- UI 用真实 `total_points/current_index` 更新进度。
- CSV metadata 写入 `points_per_decade`、`planned_points`、`received_points`。

### 5.3 固件点表与性能

固件需要评估：

- `PHASE_NOISE_PLAN_MAX_POINTS` 从 `256` 提升到 `384` 是否可接受。
- `average_noise_mw[PHASE_NOISE_PLAN_MAX_POINTS]` 的内存增加是否可接受。
- `points_per_decade` 上限是否保持 `100`，或按 `PHASE_NOISE_PLAN_MAX_POINTS` 动态限制。
- `phase_noise_plan_build()` 若点数被截断，应给 status 或 warning 留出可观测信号。

如果不想立即提高上限：

- Host 的 Fine 档应限制为不超过固件当前最大点数。
- 文档明确 `1 kHz..1 MHz` 在 256 点上限下最多约 `85 points/decade`。

### 5.4 验收

离线验收：

- Dart 单元测试覆盖 points/decade 到 planned point count 的计算。
- Demo trace 在 `1 kHz..1 MHz`、`60 pts/dec` 下应生成 `181` 个 offset 点。
- Protocol smoke test 覆盖 `points_per_decade=60` 的 config payload。
- 固件语法检查通过。

视觉验收：

- 1 kHz 到 1 MHz 图表在 Normal 档下曲线明显比当前更密。
- Marker 拖动仍稳定，读数来自真实点。
- 右侧控制面板文本不溢出。

实机验收：

- 固件返回的 `total_points` 与 Host 估算一致，或明确返回截断 warning。
- `PHASE_NOISE_DATA` 点数与 `total_points` 匹配。
- 相同平均次数下，Fast/Normal/Fine 的测量耗时大致按点数比例增加。

## 6. 子任务分配

本轮建议分成四个子任务：

1. `08_host_phase_noise_density_controls.md`
   - Host 配置模型、密度控件、demo 曲线按 points/decade 生成。
2. `09_host_phase_noise_protocol_density.md`
   - Host 串口协议 config/parser 为真实 points/decade 和 progress 做准备。
3. `10_firmware_phase_noise_dense_plan.md`
   - 固件点表上限、截断 warning、性能预算。
4. `11_dense_points_validation_visual.md`
   - 测试、视觉检查、CSV/文档验收。

## 7. 风险

- 点数提升会线性增加测量时间，尤其 average count 较大时更明显。
- 1 kHz RBW 近端点本身采样时间更长，点数密度不能无限提高。
- 若 Host 只做显示插值，会让用户误以为有更多真实测量点，必须避免。
- 若固件静默截断点表，Host 图表会仍然稀疏，需要显式暴露 total/planned 差异。
