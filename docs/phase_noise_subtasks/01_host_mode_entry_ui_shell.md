# 子任务 01：上位机相位噪声模式入口和 UI 骨架

## 目标

在 Flutter 上位机中新增 `Phase Noise` 测量模式入口，并把它放到现有“模式”菜单中，替换当前测试/实时模式入口位置。先完成页面骨架和状态布局，不负责最终测量算法。

用户明确要求：

- 相位噪声模式放在“模式”菜单中。
- 替换“试试模式”那个位置。如果当前代码中没有“试试模式”，则按现有代码理解为替换 `_showModeFlyout()` 中第二个模式入口，即当前 `实时模式` 的位置。

## 相关文件

主要文件：

- `host_computer/flutter_pusu/lib/main.dart`
- `host_computer/flutter_pusu/lib/device_models.dart`

建议新增：

- `host_computer/flutter_pusu/lib/phase_noise_models.dart`

不要修改：

- `host_computer/flutter_hello`
- 下位机固件
- `spectrum_chart.dart` 的绘图细节，除非只是传参适配

## 当前代码入口

当前模式入口在 `main.dart` 的 `_showModeFlyout()`，已有：

- `标准模式`
- `实时模式`

当前扫频方式枚举为：

```dart
enum SweepMode { standard, realTime }
```

注意：`SweepMode` 更像下位机扫频方式。相位噪声应作为上位机应用模式，建议新增：

```dart
enum MeasurementMode {
  spectrum,
  phaseNoise,
}
```

如果为了降低改动量，也可以先用布尔状态 `_isPhaseNoiseMode`，但最终应整理为明确的测量模式枚举。

## 实现要求

1. 新增测量模式状态
   - 默认进入普通频谱模式。
   - 切换到相位噪声模式时停止当前连续扫频，清理普通频谱的 pending 数据。
   - 切回普通频谱模式时停止相噪测量流程，恢复频谱图。

2. 修改 `_showModeFlyout()`
   - 第一项保留 `标准模式` 或改名为 `频谱模式`。
   - 第二项替换为 `相位噪声`。
   - `相位噪声` subtitle 建议为：`1 kHz - 1 MHz offset，显示 dBc/Hz 曲线`。
   - 选中态需要显示 check mark。

3. 新增相位噪声页面骨架
   - 中央图表区域先可以显示占位组件或空数据提示。
   - 顶部状态条预留：
     - `Nominal Frequency`
     - `Measured Frequency`
     - `Measured Level`
     - `Measurement`
     - `Initial Delta`
     - `Drift`
   - 控制区预留：
     - Carrier Auto/Manual
     - Offset Start
     - Offset Stop
     - Average Count
     - Single
     - Continuous
     - Stop

4. 视觉方向
   - 参考 Rohde 截图，但不要硬编码图片资源。
   - 使用现有 Fluent UI 深色风格。
   - 页面应是工具界面，不要做营销式 hero 或大卡片布局。

## 验收标准

- Dart analyze 不出现新增 error。
- 点击“模式”菜单可以看到 `相位噪声`。
- 选择 `相位噪声` 后，主界面切到相噪页面骨架。
- 相噪模式不会继续显示普通频谱 marker 自动峰值行为。
- 切回频谱模式后，普通扫频功能仍能启动。

## 非目标

- 不实现 `dBc/Hz` 换算。
- 不实现真实相噪数据流。
- 不新增下位机协议。
- 不新增 `1 kHz RBW`。

