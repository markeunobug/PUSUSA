# 相位噪声测量功能实现计划

## 1. 目标

在当前 PuSuSA 频谱仪项目中增加一个类似 Rohde & Schwarz 相噪应用的测量页面：

- 横轴显示相对载波的 Frequency Offset，优先使用对数坐标，例如 1 kHz 到 1 MHz。
- 纵轴显示单边带相位噪声，单位 dBc/Hz。
- 自动寻找或手动指定载波频率，显示载波频率、载波电平、起止 offset、RBW、平均次数、测量进度。
- 支持平滑/平均曲线、marker 读数、结果导出，后续可扩展 limits 和 numerical results。

第一阶段目标是做成可联调、可演示、可持续改进的测量应用，不追求一次达到商用相噪分析仪的底噪和算法完整度。

## 2. 当前项目结构判断

当前活跃路径如下：

- 上位机：`host_computer/flutter_pusu`
- 上位机关键文件：
  - `lib/main.dart`：主界面、扫频控制、连续/单次测量流程、marker、零扫宽处理。
  - `lib/serial_protocol.dart`：二进制串口协议，解析 `SPECTRUM_DATA(0x82)`，发送 `SET_FREQ/SET_BW/GET_SPECTRUM` 等命令。
  - `lib/device_models.dart`：频率、带宽、扫频、检波等配置模型。
  - `lib/spectrum_chart.dart`：当前频谱图显示和 marker 绘制。
- 下位机：`code/pusu_20260516/vitis/pusu_20260516/src`
- 下位机关键文件：
  - `device_protocol.c/.h`：当前 UART 二进制协议。
  - `sweep_engine.c/.h`：非阻塞扫频状态机，逐点设置 LO1、采样、测功率、回传。
  - `sweep_plan.c/.h`：按 `step = RBW / 2` 生成内部扫频点。
  - `signal_processing.c/.h`：DDC 到 40 MHz IF，CIC/RBW 滤波，计算 `mean(I^2 + Q^2)` 并输出 dBm。
  - `app_config.h`：RBW 档位、CIC/FIR、观测点数、profile 配置。

当前数据通路是：

```text
Flutter UI -> SET_FREQ/SET_BW/GET_SPECTRUM
下位机 sweep_engine -> LO1 点频扫描 -> DDC/RBW 功率测量
device_protocol_stream_spectrum_point -> Flutter SpectrumSegment
```

这意味着现阶段上位机拿到的是频率点功率 `dBm`，不是 IQ 时间序列，也不是直接的相位误差序列。

## 3. 功能实现策略

### 3.1 第一阶段：基于现有扫频功率数据实现相噪视图

先不改下位机协议，复用当前扫频数据，把载波两侧 offset 处的噪声功率换算为 dBc/Hz：

```text
L(offset) = P_noise_at_offset(dBm) - P_carrier(dBm) - 10*log10(ENBW_Hz)
```

第一版可先用当前 RBW 标称值近似 ENBW：

```text
ENBW_Hz ~= RBW_Hz
```

后续校准时再把 RBW 滤波器的等效噪声带宽作为每档 RBW 的校准参数。

优点：

- 能最快接入现有 Flutter 和下位机扫频链路。
- 不需要新增 UART 命令，不影响普通频谱模式。
- 可以先完成 Rohde 风格页面、offset 曲线、平均、marker、结果表等用户体验。

限制：

- 这是“频谱仪扫频法”的近似相噪测量，不是完整的交叉相关/相位检波相噪分析仪。
- 载波附近会受 RBW、LO 相噪、动态范围、泄漏、幅度校准影响。
- 如果被测源和仪器本振同源或未隔离，结果可能被系统自身噪声主导。

### 3.2 第二阶段：增加下位机相噪专用测量模式

当第一阶段 UI 和流程跑通后，再考虑新增下位机功能：

- 增加专用 `PHASE_NOISE` 命令或扩展 `SET_SWEEP` mode。
- 固件按 offset 列表测量，而不是线性扫完整 span。
- 支持每个 offset 点独立 RBW、平均次数、驻留时间。
- 返回专用 `PHASE_NOISE_DATA`，字段包含 carrier、offset、noise、rbw、平均计数、done。

只有在第一阶段实测发现普通扫频链路速度或近载波动态范围不足时，再进入这一阶段。

### 3.3 第三阶段：IQ/相位序列算法评估

如果后续要做更接近专业相噪仪的能力，需要评估从下位机输出或内部处理 IQ 序列：

- 载波锁定到固定频点，采集基带 I/Q。
- `phase[n] = atan2(Q, I)` 得到相位时间序列。
- 去除线性频偏和 DC，相位序列做 PSD。
- 换算为 `dBc/Hz`。

这一方案对采样稳定度、参考时钟、本振噪声、数据吞吐和 DSP 资源要求更高，不建议作为第一版。

## 4. 第一阶段详细设计

### 4.1 新增测量模式

在上位机增加测量模式枚举，例如：

```dart
enum MeasurementMode {
  spectrum,
  zeroSpan,
  phaseNoise,
}
```

当前代码已有 `SweepMode { standard, realTime }`，它更像下位机扫频方式；相噪应该作为上位机测量应用层模式，不建议直接混进 `SweepMode`。

需要新增状态：

- `bool _phaseNoiseMode`
- `double _phaseNoiseCarrierHz`
- `double _phaseNoiseCarrierLevelDbm`
- `double _phaseNoiseStartOffsetHz`
- `double _phaseNoiseStopOffsetHz`
- `int _phaseNoiseAverageCount`
- `List<FlSpot> _phaseNoiseTrace`
- `List<FlSpot> _phaseNoiseRawTrace`
- `int _phaseNoiseCompletedAverages`

### 4.2 载波频率获取

支持两种方式：

1. 自动载波：
   - 先执行一次窄 span 或当前 span 的普通扫频。
   - 取最大功率点作为 carrier。
   - 记录 `carrierHz` 和 `carrierLevelDbm`。

2. 手动载波：
   - 用户直接输入 nominal frequency。
   - 在 carrier 附近执行小 span 扫描，找实际峰值并修正 measured carrier。

建议第一版默认自动载波，保留手动输入框。

### 4.3 Offset 扫描频率规划

相噪图横轴是 offset，不是 RF 绝对频率。第一版可用单边测量：

```text
RF = carrierHz + offsetHz
```

后续再支持双边平均：

```text
RF_upper = carrierHz + offsetHz
RF_lower = carrierHz - offsetHz
P_noise = average_power_linear(P_upper, P_lower)
```

由于当前下位机 `sweep_plan` 是线性频率步进，且步长等于 `RBW / 2`，第一版最简单的做法是：

- 让上位机设置：
  - `startHz = carrierHz + startOffsetHz`
  - `stopHz = carrierHz + stopOffsetHz`
  - `rbwMode = 10 kHz / 30 kHz / 100 kHz`
- 下位机按当前机制扫频。
- 上位机把返回的绝对频率 `freqHz` 转换为：
  - `offsetHz = freqHz - carrierHz`

如果要模仿图中 1 kHz 到 1 MHz 的对数横轴，第一版在显示层做对数坐标映射；采样点仍来自线性扫频。第二阶段再改成对数 offset 列表，减少远端冗余点。

### 4.4 dBc/Hz 换算

输入：

- `carrierLevelDbm`
- `rbwHz`
- 每个 offset 点的 `noisePowerDbm`

计算：

```text
noiseDensityDbmPerHz = noisePowerDbm - 10*log10(enbwHz)
phaseNoiseDbcPerHz = noiseDensityDbmPerHz - carrierLevelDbm
```

第一版：

```text
enbwHz = rbwHz
```

第二版：

```text
enbwHz = rbwHz * rbwEnbwFactor[rbwMode]
```

其中 `rbwEnbwFactor` 通过滤波器仿真或实测校准得到。

### 4.5 平均和平滑

参考图中黄色平滑曲线和蓝色实时曲线，第一版实现两条 trace：

- Raw trace：最近一次 sweep 的相噪曲线。
- Average trace：N 次平均后的曲线。

建议用线性功率域平均，避免 dB 直接平均造成偏差：

```text
linear = 10^(dbcHz / 10)
avgLinear = (oldAvgLinear * n + newLinear) / (n + 1)
avgDb = 10*log10(avgLinear)
```

平滑可先做显示层移动平均，例如 3 点或 5 点窗口；不要影响导出的原始数据。

### 4.6 图表组件

当前 `SpectrumChart` 是线性频率轴、单位 dBm。相噪图建议新增独立组件：

```text
host_computer/flutter_pusu/lib/phase_noise_chart.dart
```

原因：

- 横轴需要 log offset。
- 左轴单位是 dBc/Hz。
- 顶部信息栏和底部标签与频谱模式不同。
- 需要显示 raw/avg 两条线、offset marker、测量带宽段。

组件输入建议：

- `rawData: List<FlSpot>`，x 为 offset Hz，y 为 dBc/Hz。
- `averageData: List<FlSpot>`
- `minOffsetHz/maxOffsetHz`
- `minDbcHz/maxDbcHz`
- `carrierHz/carrierLevelDbm`
- `rbwHz/averageProgress`
- `markers`

绘制方式：

- 如果 `fl_chart` 对 log x 轴不方便，组件内部把 x 转换为 `log10(offsetHz)` 绘图。
- tooltip 和底部标签再把 log x 转回 Hz/kHz/MHz。

### 4.7 UI 布局

新增入口可以放在现有顶部/侧边控制区：

- `Spectrum`
- `Zero Span`
- `Phase Noise`

相噪模式下主要控件：

- Carrier：Auto / Manual，频率输入。
- Offset Start：默认 `1 kHz`。
- Offset Stop：默认 `1 MHz`。
- RBW：默认 `10 kHz` 或 `30 kHz`。
- Average：默认 `10`。
- Trace：Raw / Avg / Both。
- Single / Continuous / Stop。
- Export CSV。

顶部状态条显示：

- Nominal Frequency
- Measured Frequency
- Carrier Level
- Measurement Offset Range
- RBW / VBW
- Average Progress

### 4.8 与现有扫频流程的集成

第一版优先复用 `_requestSpectrumIfIdle()` 和 `_handleSpectrumData()` 的机制，但要把普通频谱和相噪的数据装配逻辑分开：

- 普通频谱：写入 `_displaySweepPoints` 和 `_spectrumData`。
- 相噪：写入 `_phaseNoiseRawTrace` 和 `_phaseNoiseAverageTrace`。

建议新增函数：

- `_startPhaseNoiseMeasurement()`
- `_stopPhaseNoiseMeasurement()`
- `_configurePhaseNoiseSweep()`
- `_handlePhaseNoiseSpectrumData(SpectrumSegment segment)`
- `_completePhaseNoiseSweep()`
- `_convertSpectrumToPhaseNoise(List<FlSpot> spots)`

这样不污染当前频谱模式的 marker、zero-span、自动峰值逻辑。

## 5. 是否需要修改下位机

第一阶段不强制修改下位机。

但有两个固件点需要注意：

1. 当前 `sweep_plan` 对任意 span 都使用 `step = RBW / 2`，1 kHz 起始 offset 如果 RBW 选 10 kHz，近端分辨率本身就不足。第一版可以把最小 offset 限制到 `>= RBW`，避免给出看似很细但不可信的数据。
2. 当前协议每点频率是 `uint32_t freq_hz`，最大可到 4.29 GHz，当前 0 到 1.5 GHz RF 范围够用。

第二阶段建议新增固件能力：

- 支持 offset 点列表或对数扫点。
- 支持每点不同 RBW/驻留时间。
- 支持一次命令返回相噪专用数据，减少上位机多次改配置的同步风险。

## 6. 推荐实施步骤

### Step 1：文档和 UI 骨架

- 新增相噪计划文档。
- 新增 `PhaseNoiseConfig` / `PhaseNoiseTracePoint` 上位机模型。
- 新增 `PhaseNoiseChart`，先用模拟数据验证 log 坐标和双 trace 显示。
- 在主界面加 `Phase Noise` 模式入口。

验收：

- 不连接仪器时也能看到相噪页面和模拟曲线。
- 页面横轴为 offset，纵轴为 dBc/Hz。

### Step 2：复用扫频链路跑通真实数据

- 自动找到 carrier。
- 设置 offset 扫描范围。
- 接收现有 `SPECTRUM_DATA`。
- 转换为 offset 和 dBc/Hz。
- 显示 raw trace。

验收：

- 输入一个稳定单音信号后，页面能显示随 offset 变化的相噪曲线。
- 顶部显示 measured carrier 和 carrier level。

### Step 3：平均、平滑、marker、导出

- 增加 N 次平均。
- 增加 raw/avg 两条线显示。
- 支持 marker 读取某个 offset 的 dBc/Hz。
- 导出 CSV：

```text
carrier_hz,carrier_dbm,rbw_hz,enbw_hz,average_count
offset_hz,raw_dbc_hz,avg_dbc_hz,noise_power_dbm
```

验收：

- 可复现实验记录。
- 平均次数增加时曲线波动明显下降。

### Step 4：误差提示和测量边界

- 当 `startOffsetHz < rbwHz` 时提示测量不可信。
- 当 carrier 电平太低时提示动态范围不足。
- 当 offset 扫描超出设备 RF 范围时自动裁剪或禁止启动。
- 在 UI 上标记 `UNCAL` 或 `Estimated ENBW`。

验收：

- 用户不会把第一版近似结果误认为已校准商用相噪结果。

### Step 5：下位机专用模式评估

基于第一阶段实测数据决定是否进入下位机扩展：

- 如果速度慢：优先做 offset 列表扫频。
- 如果近端不准：优先做更小 RBW/更长驻留时间。
- 如果底噪不够：评估 LO/参考源/前端动态范围，不先盲目改 UI。
- 如果需要真正相位 PSD：再做 IQ 相位序列方案。

## 7. 风险和待确认问题

- 相噪结果会被仪器自身 LO 相噪限制；需要用已知低相噪信号源做基线测试。
- 当前幅度校准还不完整，`carrierLevelDbm` 和 `noisePowerDbm` 的绝对准确度会影响 dBc/Hz。
- 当前 RBW 的 ENBW 未校准，第一版只能标注为估算。
- 1 kHz offset 对当前最小 10 kHz RBW 并不理想；若必须显示 1 kHz，需要新增更窄 RBW 或专用算法。
- 当前串口和逐点 LO 扫描速度可能限制平均次数和刷新率。

## 8. 第一版建议默认参数

| 参数 | 默认值 | 原因 |
| --- | --- | --- |
| Carrier | Auto | 降低使用门槛 |
| Offset Start | 10 kHz | 匹配当前最小 RBW 能力 |
| Offset Stop | 1 MHz | 与参考图类似，且扫点数量可控 |
| RBW | 10 kHz | 当前最窄 RBW，适合噪声密度换算 |
| Average | 10 | 与参考图中的 AVG 10 一致 |
| Trace | Raw + Avg | 同时观察实时波动和平滑结果 |
| Sideband | Upper only | 第一版最少改动 |

如果用户坚持从 1 kHz 开始，UI 可以允许设置，但必须显示 `Offset < RBW, result is approximate`。

## 9. 结论

最稳妥的实现路线是：

1. 先在 Flutter 上位机做一个独立 `Phase Noise` 测量应用。
2. 复用现有扫频功率数据，把 `dBm` 换算为 `dBc/Hz`。
3. 把第一版明确标注为基于 RBW 的扫频估算相噪。
4. 用真实信号源验证速度、底噪和近端 offset 后，再决定是否扩展下位机协议或做 IQ 相位算法。

