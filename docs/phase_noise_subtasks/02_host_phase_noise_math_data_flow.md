# 子任务 02：上位机相噪数学模型和数据流

## 目标

实现上位机相位噪声测量的核心数据模型和计算链路：

- 载波自动搜索或手动指定。
- 普通扫频功率点转换为 offset 点。
- `dBm` 转换为 `dBc/Hz`。
- raw trace 与 average trace。
- 处理当前 `10 kHz RBW` 的可信边界提示。

本任务优先做纯 Dart 逻辑，尽量少碰 UI。

## 相关文件

建议新增：

- `host_computer/flutter_pusu/lib/phase_noise_models.dart`
- `host_computer/flutter_pusu/lib/phase_noise_processor.dart`

可能需要修改：

- `host_computer/flutter_pusu/lib/main.dart`
- `host_computer/flutter_pusu/lib/device_models.dart`

不要修改：

- 下位机固件
- `serial_protocol.dart` 的协议命令，除非只是复用现有 `SpectrumSegment`

## 基本公式

频谱仪扫频法近似：

```text
L(offset) = Pnoise(offset) - Pcarrier - 10*log10(ENBW)
```

第一阶段：

```text
ENBW ~= RBW
```

输入输出：

```text
输入：carrierLevelDbm, rbwHz, freqHz, powerDbm
offsetHz = abs(freqHz - carrierHz)
phaseNoiseDbcHz = powerDbm - carrierLevelDbm - 10*log10(enbwHz)
```

平均必须在线性功率域做：

```text
linear = 10^(dbcHz / 10)
avgLinear = (oldAvgLinear * n + newLinear) / (n + 1)
avgDb = 10*log10(avgLinear)
```

## 实现要求

1. 数据模型
   - `PhaseNoiseConfig`
     - `carrierMode`
     - `manualCarrierHz`
     - `startOffsetHz`
     - `stopOffsetHz`
     - `rbwHz`
     - `enbwHz`
     - `averageTarget`
     - `sidebandMode`
   - `PhaseNoiseCarrier`
     - `nominalHz`
     - `measuredHz`
     - `levelDbm`
     - `initialDeltaHz`
     - `driftHz`
   - `PhaseNoisePoint`
     - `offsetHz`
     - `noisePowerDbm`
     - `dbcHz`
     - `rbwHz`
     - `valid`
   - `PhaseNoiseTrace`
     - `rawPoints`
     - `averagePoints`
     - `completedAverages`

2. 载波搜索
   - 从一组 `FlSpot(freqHz, powerDbm)` 中找到最大点作为载波。
   - 保留手动 carrier 的入口，手动时仍可用近邻峰值修正 measured carrier。
   - 输出 measured carrier 和 carrier level。

3. offset 转换
   - 支持单边 upper：
     - `offset = freqHz - carrierHz`
     - 只保留 `offset > 0`
   - 预留 lower / both-side 平均接口，但第一版可以不接 UI。

4. 可信边界
   - 如果 `startOffsetHz < rbwHz`，输出 warning：
     - `Offset < RBW, result is approximate`
   - 如果 `carrierLevelDbm` 低于可配置阈值，例如 `-50 dBm`，输出 warning。
   - 如果有效点数少于 3 个，输出 warning。

5. 与现有数据流集成
   - 在 `main.dart` 中新增 `_handlePhaseNoiseSpectrumData(SpectrumSegment segment)` 或等价函数。
   - 普通频谱模式仍走 `_handleSpectrumData()` 原有逻辑。
   - 相噪模式下不要触发普通 marker 自动峰值更新。

## 验收标准

- 有纯 Dart 可调用的 processor，不依赖 Flutter widget。
- 给定模拟数据能得到正确的 `dBc/Hz`：

```text
carrier = 0 dBm
noise = -80 dBm
RBW = 10 kHz
结果 = -120 dBc/Hz
```

- 平均逻辑使用线性域，不直接平均 dB。
- 相噪模式接收 `SpectrumSegment` 后可以生成 raw/avg trace。
- Dart analyze 不出现新增 error。

## 非目标

- 不做最终图表。
- 不设计新 UART 协议。
- 不实现 `1 kHz RBW`。

