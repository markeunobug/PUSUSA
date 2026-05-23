# 子任务 08：Host 相噪点数密度配置与 UI

## 目标

让相位噪声页面支持更密集的 offset 点数配置，默认曲线密度接近 Rohde & Schwarz 相噪页面观感。

本任务只负责 Host 配置、控件和 demo 数据密度，不做真实串口 parser。

## 先读

1. `docs/phase_noise_dense_points_plan.md`
2. `docs/phase_noise_measurement_plan.md`
3. `host_computer/flutter_pusu/lib/main.dart`
4. `host_computer/flutter_pusu/lib/phase_noise_models.dart`
5. `host_computer/flutter_pusu/lib/phase_noise_processor.dart`
6. `host_computer/flutter_pusu/lib/phase_noise_chart.dart`

## 修改范围

优先修改：

- `host_computer/flutter_pusu/lib/phase_noise_models.dart`
- `host_computer/flutter_pusu/lib/main.dart`
- 必要时新增/更新 `host_computer/flutter_pusu/test/phase_noise_processor_test.dart`

不要修改：

- `host_computer/flutter_hello`
- 固件代码
- Vivado/Vitis 生成产物

## 实现要求

1. 在 `PhaseNoiseConfig` 中增加 `pointsPerDecade`，默认建议 `60`。
2. 增加密度档位模型，建议：
   - Fast = 30 points/decade
   - Normal = 60 points/decade
   - Fine = 90 points/decade
3. 右侧相噪控制面板增加密度控件：
   - 推荐放在 `Offset` 面板中。
   - 使用 segmented/button group 或 ComboBox，不要只放自由文本。
   - 显示估算总点数，例如 `Points: 181`。
4. `_buildDemoPhaseNoiseSweep()` 不再写死 `pointCount = 121`。
   - 根据 `startOffsetHz/stopOffsetHz/pointsPerDecade` 计算点数。
   - `1 kHz..1 MHz`、`60 pts/dec` 应生成 `181` 个 offset 点。
5. 状态栏或 Trace 面板中显示当前密度，例如 `Density: 60 pts/dec`。
6. marker、CSV 和平均逻辑必须仍基于真实生成点，不要生成插值点混入数据模型。

## 验收

运行：

```powershell
C:\learning\tools\flutter\bin\cache\dart-sdk\bin\dart.exe analyze host_computer\flutter_pusu\lib
```

如测试可加，运行：

```powershell
C:\learning\tools\flutter\bin\flutter.bat test test\phase_noise_processor_test.dart test\phase_noise_chart_test.dart
```

人工验收：

- 切换 Fast/Normal/Fine，图表点数密度明显变化。
- `1 kHz..1 MHz`、Normal 档估算点数为 `181`。
- UI 文本不溢出，按钮不挤压。

## 完成汇报

汇报：

- 修改文件列表。
- 新增配置字段和默认值。
- 点数计算公式。
- 已运行命令和结果。
- 未处理风险。
