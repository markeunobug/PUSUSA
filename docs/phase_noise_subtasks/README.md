# 相位噪声功能子任务总览

本目录用于把相位噪声测量功能拆分给多个子 agent 并行落地。所有子 agent 开始前必须先读：

1. `docs/phase_noise_measurement_plan.md`
2. 本文件
3. 自己对应的子任务文件

## 当前活跃工程路径

- 上位机：`host_computer/flutter_pusu`
- 下位机：`code/pusu_20260516/vitis/pusu_20260516/src`
- 不要修改旧工程：
  - `host_computer/flutter_hello`
  - `code/pusu_test`
  - 任何 Vivado/Vitis 生成输出、缓存、bitstream、xsa、archive、build 产物

## 用户目标

参考 Rohde & Schwarz 频谱仪的 Phase Noise Analyzer 页面，增加相位噪声测量功能：

- 模式入口放在现有“模式”菜单中，替换当前测试/实时模式入口位置。
- 测量范围目标为 `1 kHz` 到 `1 MHz` frequency offset。
- 图表横轴为对数 offset，纵轴为 `dBc/Hz`。
- 显示载波频率、载波电平、测量频率、初始偏差、漂移、平均进度等关键状态。
- 第一阶段允许先做上位机 UI 和现有扫频链路验证。
- 后续必须支持相位噪声专用下位机测量代码，因为当前最小 `10 kHz RBW` 不足以可信测量 `1 kHz offset`。

## 子任务拆分

建议按以下顺序分配：

1. `01_host_mode_entry_ui_shell.md`
   - 负责相位噪声模式入口、页面骨架、状态布局。
2. `02_host_phase_noise_math_data_flow.md`
   - 负责上位机相噪数据模型、载波搜索、dBc/Hz 换算、平均。
3. `03_host_phase_noise_chart_results.md`
   - 负责相噪图表、对数 offset 轴、marker、结果区和导出。
4. `04_protocol_contract_phase_noise.md`
   - 负责设计上位机/下位机相噪专用协议契约，不一定立即实现固件。
5. `05_firmware_1khz_rbw_extension.md`
   - 负责在固件 DSP 链路中增加 `1 kHz RBW` 能力。
6. `06_firmware_phase_noise_engine.md`
   - 负责相噪专用下位机测量引擎：offset 列表、分段 RBW、专用回传。
7. `07_validation_calibration.md`
   - 负责联调、校准、边界提示、验收脚本和实验记录格式。

## 第二轮：密集点数优化

当前相噪页面已能运行，但 1 kHz 到 1 MHz offset 图表点数偏少。新一轮目标是让点数密度接近
Rohde & Schwarz 相噪测量页面，同时避免用显示插值伪造真实测量点。

本轮开始前必须先读：

1. `docs/phase_noise_dense_points_plan.md`
2. 本 README
3. 自己对应的子任务文件

建议拆分：

8. `08_host_phase_noise_density_controls.md`
   - Host 配置模型、密度控件、demo 曲线按 points/decade 生成。
9. `09_host_phase_noise_protocol_density.md`
   - Host 串口协议 config/parser 为真实 points/decade 和 progress 做准备。
10. `10_firmware_phase_noise_dense_plan.md`
    - 固件点表上限、截断 warning、性能预算。
11. `11_dense_points_validation_visual.md`
    - 测试、视觉检查、CSV/文档验收。

## 并行边界

- 子任务 01/02/03 都会涉及 `host_computer/flutter_pusu/lib/main.dart`，不能无协调同时提交大块改动。
- 子任务 02 可以先做纯 Dart 计算类和单元测试，减少对 `main.dart` 的占用。
- 子任务 03 应优先新增独立 `phase_noise_chart.dart`，避免改动 `spectrum_chart.dart`。
- 子任务 04 只设计协议文档和 host parser/模型草案，不直接改固件热路径。
- 子任务 05 只扩展 RBW 档位和 DSP 配置，不新增相噪引擎。
- 子任务 06 依赖子任务 04 和 05 的接口结论。

## 通用验收要求

每个子 agent 完成后必须提供：

- 修改文件列表。
- 关键实现说明。
- 已运行的检查命令和结果。
- 未完成项和风险。
- 不得回退或重写其他 agent 的改动。

## 推荐检查命令

上位机：

```powershell
C:\learning\tools\flutter\bin\cache\dart-sdk\bin\dart.exe analyze host_computer\flutter_pusu\lib
```

固件：

```powershell
rg -n "RBW_MODE|phase_noise|PHASE_NOISE|CMD_" code\pusu_20260516\vitis\pusu_20260516\src
```

Git 状态：

```powershell
git -c safe.directory=C:/learning/pusu_V2 status --short -- docs host_computer/flutter_pusu/lib code/pusu_20260516/vitis/pusu_20260516/src
```
