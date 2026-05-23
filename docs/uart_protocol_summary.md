# 串口协议总览

当前项目存在两套协议并存：上位机定义了完整二进制帧协议；下位机当前确认稳定工作的 RBW 控制与调试输出仍是文本 UART 协议。

依据代码与记录：
- [serial_protocol.dart](/C:/learning/pusu_V2/上位机/flutter_hello/lib/serial_protocol.dart)
- [serial_port_manager.dart](/C:/learning/pusu_V2/上位机/flutter_hello/lib/serial_port_manager.dart)
- [digital_chain_checkpoint_2026-03-26.md](/C:/learning/pusu_V2/docs/digital_chain_checkpoint_2026-03-26.md)

## 1. 串口物理层参数

| 项目 | 值 | 说明 |
| --- | --- | --- |
| 波特率 | `115200` | 上位机串口配置固定值 |
| 数据位 | `8` | `bits = 8` |
| 停止位 | `1` | `stopBits = 1` |
| 校验 | `None` | `parity = none` |

## 2. 设计中的统一二进制协议

### 2.1 帧格式

| 字段 | 大小 | 内容 | 说明 |
| --- | --- | --- | --- |
| Start | 1B | `0xAA` | 帧头 |
| Len | 2B | 数据区长度 | 代码中按 `Uint16` 写入 |
| Cmd | 1B | 命令字 | 请求或响应命令 |
| Data | NB | 负载 | 长度由 `Len` 指定 |
| CRC | 2B | `CRC16 Modbus` | 对 `Len + Cmd + Data` 计算 |
| End | 1B | `0x55` | 帧尾 |

帧结构可写为：

```text
0xAA | Len(2B) | Cmd(1B) | Data(NB) | CRC16(2B) | 0x55
```

### 2.2 上位机发送命令

| 方向 | 命令字 | 名称 | 数据区格式 | 字节序 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 上位机 -> 下位机 | `0x01` | `setFreq` | `startHz(8B) + stopHz(8B) + centerHz(8B) + spanHz(8B)` | 4 个 `float64 little-endian` | 设置起始、终止、中心频率和 Span，共 `32B` |
| 上位机 -> 下位机 | `0x02` | `setAmplitude` | `refLevel(8B) + attenuator(1B) + preamp(1B)` | `refLevel` 为 `float64 little-endian`，其余为 `uint8` | 设置参考电平、衰减器、前放，共 `10B` |
| 上位机 -> 下位机 | `0x03` | `setBw` | `rbwMode(1B) + rbwHz(8B) + vbwMode(1B) + vbwHz(8B)` | `rbwHz/vbwHz` 为 `float64 little-endian`，模式值为 `uint8` | 设置 RBW/VBW，共 `18B` |
| 上位机 -> 下位机 | `0x04` | `setDetect` | `mode(1B)` | `uint8` | 设置检波方式，共 `1B` |
| 上位机 -> 下位机 | `0x05` | `setSweep` | `speed(8B) + mode(1B)` | `speed` 为 `float64 little-endian`，`mode` 为 `uint8` | 设置扫描速度和模式，共 `9B` |
| 上位机 -> 下位机 | `0x06` | `getSpectrum` | 无 | 无 | 请求一次频谱数据，`0B` |
| 上位机 -> 下位机 | `0x07` | `getStatus` | 无 | 无 | 请求状态数据，`0B` |
| 上位机 -> 下位机 | `0x08` | `reset` | 无 | 无 | 请求复位，`0B` |

### 2.3 参数编码补充

| 类别 | UI/含义 | 编码值 | 说明 |
| --- | --- | --- | --- |
| 衰减器 | 自动 | `0` | `setAmplitude` 参数 |
| 衰减器 | `0dB / 0.25dB / 0.5dB / 1dB / 2dB / 4dB / 8dB / 16dB / 31.75dB` | `1 / 2 / 3 / 4 / 5 / 6 / 7 / 8 / 9` | 上位机当前映射值 |
| 前放 | 自动 / 使能 / 关闭 | `0 / 1 / 2` | `setAmplitude` 参数 |
| RBW 模式 | 自动 / 手动 / `0.001*Span` / `0.01*Span` | `0 / 1 / 2 / 3` | `setBw` 参数 |
| VBW 模式 | `VBW=RBW` / 手动 / `VBW=0.1*RBW` / `VBW=0.01*RBW` / `VBW=10*RBW` | `0 / 1 / 2 / 3 / 4` | `setBw` 参数 |
| Detect | 平均 / 取样 / 正峰值 / 负峰值 / 最大功率 / 均方根值 | `0 / 1 / 2 / 3 / 4 / 5` | `setDetect` 参数 |

### 2.4 下位机返回命令

| 方向 | 命令字 | 名称 | 数据区格式 | 字节序 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 下位机 -> 上位机 | `0x81` | `ACK` | `originalCmd(1B) + success(1B) + error(1B)` | `uint8` | 原命令、成功标志、错误码；错误码语义当前未在代码外定义 |
| 下位机 -> 上位机 | `0x82` | `SPECTRUM_DATA` | `pointCount(2B) + timestamp(4B) + N * [freq(8B) + amp(8B)]` | `pointCount/timestamp` 为 big-endian，`freq/amp` 为 `float64 little-endian` | 前 6B 为头信息，后续每个点占 `16B` |
| 下位机 -> 上位机 | `0x83` | `STATUS_DATA` | `temp(8B) + battery(1B) + error(1B)` | `temp` 端序代码中未显式指定，`battery/error` 为 `uint8` | 温度字段需与下位机实机再确认字节序 |

### 2.5 相位噪声专用协议

相位噪声专用测量不复用 `SPECTRUM_DATA(0x82)` 承载全部字段，协议契约见
[phase_noise_protocol.md](/C:/learning/pusu_V2/docs/phase_noise_protocol.md)。

当前第一版命令号如下；固件侧已接入命令和响应帧，Host 真实 parser/UI 绑定仍待接入：

| 方向 | 命令字 | 名称 | 数据区格式 | 字节序 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 上位机 -> 下位机 | `0x0F` | `SET_PHASE_NOISE_CONFIG` | 固定 `36B` 配置 | payload 内数值以 little-endian 为主 | 设置相噪版本、flags、carrier/sideband 模式、nominal carrier、offset 范围、points/decade、average count |
| 上位机 -> 下位机 | `0x10` | `START_PHASE_NOISE` | 无 | 无 | 使用最近一次有效配置启动相噪测量 |
| 上位机 -> 下位机 | `0x11` | `STOP_PHASE_NOISE` | 无 | 无 | 请求停止当前相噪测量 |
| 上位机 -> 下位机 | `0x12` | `GET_PHASE_NOISE_STATUS` | 无 | 无 | 请求 `PHASE_NOISE_STATUS` |
| 下位机 -> 上位机 | `0x86` | `PHASE_NOISE_DATA` | 固定 `42B`，第一版每帧一个 offset 点 | 流式头字段 big-endian，测量数值 little-endian | 返回 trace_id、进度、carrier、offset、noise power、dBc/Hz、RBW 和点错误码 |
| 下位机 -> 上位机 | `0x87` | `PHASE_NOISE_STATUS` | 固定 `64B` 状态 | 流式头字段 big-endian，测量数值 little-endian | 返回状态机状态、配置摘要、进度、当前 offset/RBW、错误码和警告码 |

## 3. 当前下位机已验证文本协议

| 方向 | 命令字/文本 | 名称 | 数据区格式 | 字节序 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 上位机 -> 下位机 | `'0'` | RBW 切换 | 单字符 | 文本 | 切到 `10 kHz` |
| 上位机 -> 下位机 | `'1'` | RBW 切换 | 单字符 | 文本 | 切到 `30 kHz` |
| 上位机 -> 下位机 | `'2'` | RBW 切换 | 单字符 | 文本 | 切到 `100 kHz` |
| 上位机 -> 下位机 | `'3'` | RBW 切换 | 单字符 | 文本 | 切到 `300 kHz` |
| 上位机 -> 下位机 | `'4'` | RBW 切换 | 单字符 | 文本 | 切到 `1 MHz` |
| 下位机 -> 上位机 | `POWER_DBFS,<RBW>,<value>` | 功率输出 | 逗号分隔文本 | 文本 | 输出当前 RBW 下的时域功率结果 |
| 下位机 -> 上位机 | `PEAK,<RBW>,<bin>,<kHz>,<Hz_rem>,<dB>` | FFT 峰值调试 | 逗号分隔文本 | 文本 | 输出峰值 bin、频率和幅度调试信息 |

## 4. 当前状态与风险

1. 上下位机可能尚未完全统一到二进制协议。
2. 若联调失败，先确认下位机当前分支到底接收的是二进制帧还是文本字符。
3. `STATUS_DATA` 中温度字段的字节序需要实机确认。
