# 子任务 03：相噪图表、marker、结果展示和导出

## 目标

新增相位噪声专用图表组件，显示类似 Rohde & Schwarz 相噪页面的曲线：

- 横轴：Frequency Offset，对数轴，默认 `1 kHz` 到 `1 MHz`。
- 纵轴：`dBc/Hz`。
- 支持 raw trace 和 average trace。
- 支持 marker 读数。
- 支持 CSV 导出。

本任务依赖子任务 01 的页面骨架和子任务 02 的数据模型。

## 相关文件

建议新增：

- `host_computer/flutter_pusu/lib/phase_noise_chart.dart`
- `host_computer/flutter_pusu/lib/phase_noise_results.dart`，可选

可能修改：

- `host_computer/flutter_pusu/lib/main.dart`
- `host_computer/flutter_pusu/lib/phase_noise_models.dart`

尽量不要修改：

- `host_computer/flutter_pusu/lib/spectrum_chart.dart`

## 图表实现要求

1. 独立图表组件
   - 不要把相噪逻辑塞进 `SpectrumChart`。
   - x 输入仍使用真实 `offsetHz`。
   - 组件内部转换为 `log10(offsetHz)` 绘图。

2. 坐标轴
   - x 轴主刻度：
     - `1 kHz`
     - `10 kHz`
     - `100 kHz`
     - `1 MHz`
   - x 轴次网格可显示每 decade 内的 2/3/5 等辅助线。
   - y 轴单位固定 `dBc/Hz`。
   - 默认 y 范围可先用 `-140` 到 `-80 dBc/Hz`，后续允许自适应。

3. 曲线
   - raw trace：浅蓝或青色细线。
   - average trace：黄色或白色平滑线。
   - trace 切换：
     - Raw
     - Avg
     - Both

4. marker
   - marker 显示：
     - offset
     - dBc/Hz
   - marker 应吸附到最近点。
   - 初版可以只支持点击/拖动一个 marker。

5. 结果展示
   - 顶部或侧边显示：
     - `Nominal Frequency`
     - `Measured Frequency`
     - `Measured Level`
     - `Measurement: 1 kHz to 1 MHz`
     - `Average: n/N`
     - warning，例如 `UNCAL` 或 `Offset < RBW`

6. CSV 导出
   - 格式建议：

```text
carrier_hz,carrier_dbm,rbw_hz,enbw_hz,average_count
offset_hz,raw_dbc_hz,avg_dbc_hz,noise_power_dbm,valid
```

## 验收标准

- 无真实设备时能用模拟点显示完整相噪曲线。
- `1 kHz` 到 `1 MHz` 对数轴刻度正确。
- raw/avg 两条线可以同时显示。
- marker 读数显示 offset 和 dBc/Hz。
- CSV 导出文件内容可读，包含元数据和点数据。
- Dart analyze 不出现新增 error。

## 非目标

- 不实现相噪数学换算。
- 不实现下位机协议。
- 不新增 RBW 档位。

