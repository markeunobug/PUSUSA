# 相位噪声专用串口协议契约

本文定义上位机 `host_computer/flutter_pusu` 与下位机
`code/pusu_20260516/vitis/pusu_20260516/src` 之间的相位噪声专用协议。
当前第一版已落地固件 `phase_noise_engine`、`1 kHz RBW`、Host 模式入口/算法/图表壳。
Host 已准备真实 `0x86/0x87` 数据流 parser/stream，UI 绑定仍待后续接入。

## 1. 版本和边界

- 协议版本：`version = 1`。
- 第一版数据流：`PHASE_NOISE_DATA` 每帧只承载一个 offset 点。
- 相位噪声数据使用专用响应帧，不复用 `SPECTRUM_DATA(0x82)`。
- 固件已接入相噪命令和专用响应帧；Host 联调前仍需补齐真实 UI 绑定。
- 所有 `reserved` 字段发送端必须填 `0`，接收端必须忽略。

## 2. 外层帧格式

沿用当前二进制 UART 帧：

```text
0xAA | Len(2B BE) | Cmd(1B) | Data(NB) | CRC16 Modbus(2B BE) | 0x55
```

| 字段 | 大小 | 端序 | 说明 |
| --- | --- | --- | --- |
| Start | 1B | - | 固定 `0xAA` |
| Len | 2B | Big-endian | `Data` 字节数，不包含 `Cmd` |
| Cmd | 1B | - | 命令字 |
| Data | NB | 见各 payload | 负载 |
| CRC | 2B | Big-endian | CRC16 Modbus，覆盖 `Len + Cmd + Data` |
| End | 1B | - | 固定 `0x55` |

payload 端序规则：

- 配置 payload 中的 `float64/uint16` 参数使用 little-endian，延续现有上位机参数命令写法。
- 流式响应头里的 `trace_id/total_points/current_index/average_index` 使用 big-endian，延续现有 `SPECTRUM_DATA` 分段头写法。
- 测量数值 `float64/float32/uint32` 使用 little-endian。

## 3. 命令分配

当前固件命令已占用请求 `0x01` 到 `0x0E`、响应 `0x81` 到 `0x85`。相噪协议使用以下命令：

| 方向 | Cmd | 名称 | payload 长度 | 说明 |
| --- | --- | --- | --- | --- |
| 上位机 -> 下位机 | `0x0F` | `SET_PHASE_NOISE_CONFIG` | 36B | 写入下一次相噪测量配置 |
| 上位机 -> 下位机 | `0x10` | `START_PHASE_NOISE` | 0B | 使用最近一次有效配置启动测量 |
| 上位机 -> 下位机 | `0x11` | `STOP_PHASE_NOISE` | 0B | 请求停止当前相噪测量 |
| 上位机 -> 下位机 | `0x12` | `GET_PHASE_NOISE_STATUS` | 0B | 请求当前相噪状态 |
| 下位机 -> 上位机 | `0x86` | `PHASE_NOISE_DATA` | 42B | 流式返回一个 offset 点 |
| 下位机 -> 上位机 | `0x87` | `PHASE_NOISE_STATUS` | 64B | 返回配置、进度、状态和错误 |

请求命令仍通过 `ACK(0x81)` 表示协议层是否接受。相噪测量语义错误通过
`PHASE_NOISE_STATUS.error_code` 和 `PHASE_NOISE_DATA.error_code` 返回。

## 4. 请求 payload

### 4.1 SET_PHASE_NOISE_CONFIG(0x0F)

总长度固定 `36B`。

| Offset | 字段 | 类型 | 端序 | 单位/取值 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 0 | `version` | `uint8` | - | `1` | 协议版本 |
| 1 | `flags` | `uint8` | - | bit field | 见下表 |
| 2 | `carrier_mode` | `uint8` | - | `0/1` | `0=manual`，`1=auto` |
| 3 | `sideband_mode` | `uint8` | - | `0/1/2` | 协议预留 `0=upper`，`1=lower`，`2=dual_average`；当前固件只接受 `0=upper` |
| 4 | `nominal_carrier_hz` | `float64` | LE | Hz | 手动载波频率；auto 模式下作为搜索中心，当前固件也要求大于 `0` |
| 12 | `start_offset_hz` | `float64` | LE | Hz | 起始 offset，必须大于 `0` |
| 20 | `stop_offset_hz` | `float64` | LE | Hz | 终止 offset，必须大于起始 offset |
| 28 | `points_per_decade` | `uint16` | LE | 点/decade | Host 默认 `60`，建议可选 `30/60/90`；`0` 非法 |
| 30 | `average_count` | `uint16` | LE | 次 | 推荐 `10`；`0` 非法 |
| 32 | `carrier_search_span_khz` | `uint16` | LE | kHz | 载波搜索总 span；`0` 表示使用固件默认值，Host 默认写 `100` |
| 34 | `minimum_carrier_level_dbm_i8` | `int8` | - | dBm | 载波有效判定阈值，Host 默认写 `-50` |
| 35 | `reserved` | `uint8` | - | `0` | 预留，必须为 `0` |

`flags` 定义：

| bit | 名称 | 含义 |
| --- | --- | --- |
| 0 | `continuous` | `0=完成 average_count 后结束`，`1=持续重复直到 STOP` |
| 1 | `allow_estimated_enbw` | `1=允许固件用 ENBW ~= RBW 估算 dBc/Hz`；当前固件尚无 ENBW 校准表，必须置 `1` |
| 2 | `emit_intermediate_averages` | `1=每次 average pass 都可流式返回点`，`0=优先返回最终平均点` |
| 3..7 | reserved | 必须为 `0` |

第一版配置不直接指定 RBW。相噪引擎由 offset 策略选择实际 RBW，并在数据帧中回传
`rbw_hz`。当前固件已包含 `1 kHz RBW`，但仍应通过实机校准确认实际 ENBW。

载波捕获使用 `nominal_carrier_hz` 作为搜索中心；auto 模式通常由当前中心频率填入，
manual 模式由用户输入的载波频率填入，但两种模式都允许在配置 span 内搜索。固件应先做
coarse search，再围绕最强 coarse candidate 做 fine search，并把最强有效点作为
`measured_carrier_hz` 和 `carrier_level_dbm`。默认搜索 span 为 `100 kHz`，默认
trigger/min carrier level 为 `-50 dBm`。若最强点低于
`minimum_carrier_level_dbm_i8`，应返回 `PN_ERR_CARRIER_NOT_FOUND` 或
`PN_WARN_CARRIER_LEVEL_LOW`，并清除 `carrier_valid` 和
`PHASE_NOISE_DATA` 的 `phase_noise_valid`，不能把曲线作为有效相噪结果显示。

### 4.2 START_PHASE_NOISE(0x10)

payload 长度固定 `0B`。语义：

- 使用最近一次成功接受的 `SET_PHASE_NOISE_CONFIG`。
- 固件为本次测量分配 `trace_id`，后续数据和状态帧使用同一个 `trace_id`。
- 若尚未配置，返回 ACK 失败或发送 `PHASE_NOISE_STATUS`，错误码为 `PN_ERR_NOT_CONFIGURED`。

### 4.3 STOP_PHASE_NOISE(0x11)

payload 长度固定 `0B`。语义：

- 请求中断当前测量。
- 固件应尽快停止发出该 `trace_id` 的新数据点。
- 停止完成后建议发送一次 `PHASE_NOISE_STATUS`，状态为 `stopped` 或 `idle`，错误码为 `PN_ERR_STOPPED_BY_HOST`。

### 4.4 GET_PHASE_NOISE_STATUS(0x12)

payload 长度固定 `0B`。语义：

- 固件先返回 `ACK(0x81)`。
- 随后返回一个 `PHASE_NOISE_STATUS(0x87)` 帧。

## 5. 响应 payload

### 5.1 PHASE_NOISE_DATA(0x86)

总长度固定 `42B`。第一版每帧一个点。

| Offset | 字段 | 类型 | 端序 | 单位/取值 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 0 | `version` | `uint8` | - | `1` | 协议版本 |
| 1 | `flags` | `uint8` | - | bit field | 见下表 |
| 2 | `trace_id` | `uint16` | BE | - | 每次 START 分配，回绕允许 |
| 4 | `total_points` | `uint16` | BE | 点 | 单次 average pass 的 planned offset 点数 |
| 6 | `current_index` | `uint16` | BE | 点索引 | `0` 起始，范围 `0..total_points-1` |
| 8 | `average_index` | `uint16` | BE | 次 | 产生该点的 average pass，`1` 起始 |
| 10 | `carrier_hz` | `float64` | LE | Hz | 实测载波；无效时填 nominal 值并清 `carrier_valid` |
| 18 | `carrier_level_dbm` | `float32` | LE | dBm | 载波功率；无效时填 `0.0` 并清 `carrier_valid` |
| 22 | `offset_hz` | `uint32` | LE | Hz | 当前 offset，按整数 Hz 回传 |
| 26 | `noise_power_dbm` | `float32` | LE | dBm | 当前 RBW 内积分噪声功率 |
| 30 | `phase_noise_dbc_hz` | `float32` | LE | dBc/Hz | 固件计算值；无效时填 `0.0` 并清 `phase_noise_valid` |
| 34 | `rbw_hz` | `uint32` | LE | Hz | 本点实际使用的标称 RBW |
| 38 | `error_code` | `uint8` | - | `PN_ERR_*` | 本点错误码 |
| 39 | `reserved` | `uint8[3]` | - | `0` | 预留 |

`flags` 定义：

| bit | 名称 | 含义 |
| --- | --- | --- |
| 0 | `done` | 本 trace 的最后一个数据点 |
| 1 | `carrier_valid` | `carrier_hz/carrier_level_dbm` 有效 |
| 2 | `warning` | 本点存在非致命警告，查看 status 或 warning code |
| 3 | `lower_sideband` | 本点来自 lower sideband；upper 时为 `0` |
| 4 | `dual_average` | 本点为 upper/lower 线性平均后的结果 |
| 5 | `phase_noise_valid` | `phase_noise_dbc_hz` 有效 |
| 6..7 | reserved | 必须为 `0` |

`phase_noise_dbc_hz` 的推荐换算：

```text
noise_density_dbm_per_hz = noise_power_dbm - 10 * log10(enbw_hz)
phase_noise_dbc_hz = noise_density_dbm_per_hz - carrier_level_dbm
```

第一版不在数据帧里传 `enbw_hz`。若尚无校准表，可在
`allow_estimated_enbw=1` 时使用 `enbw_hz ~= rbw_hz`，并通过 warning 标注估算。
若上位机要自行计算，使用 `noise_power_dbm/carrier_level_dbm/rbw_hz` 作为输入。

### 5.2 PHASE_NOISE_STATUS(0x87)

总长度固定 `64B`。

| Offset | 字段 | 类型 | 端序 | 单位/取值 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 0 | `version` | `uint8` | - | `1` | 协议版本 |
| 1 | `state` | `uint8` | - | `PN_STATE_*` | 状态机状态 |
| 2 | `flags` | `uint8` | - | bit field | 见下表 |
| 3 | `error_code` | `uint8` | - | `PN_ERR_*` | 最近一次错误 |
| 4 | `trace_id` | `uint16` | BE | - | 当前或最近 trace |
| 6 | `total_points` | `uint16` | BE | 点 | 当前配置的单次 pass 点数 |
| 8 | `current_index` | `uint16` | BE | 点索引 | 当前或最近处理的点 |
| 10 | `average_index` | `uint16` | BE | 次 | 当前或最近 average pass |
| 12 | `nominal_carrier_hz` | `float64` | LE | Hz | 配置中的 nominal carrier |
| 20 | `measured_carrier_hz` | `float64` | LE | Hz | auto/manual 修正后的载波 |
| 28 | `carrier_level_dbm` | `float32` | LE | dBm | 最近载波电平 |
| 32 | `start_offset_hz` | `float64` | LE | Hz | 配置起始 offset |
| 40 | `stop_offset_hz` | `float64` | LE | Hz | 配置终止 offset |
| 48 | `current_offset_hz` | `uint32` | LE | Hz | 当前或最近 offset |
| 52 | `current_rbw_hz` | `uint32` | LE | Hz | 当前或最近 RBW |
| 56 | `elapsed_ms` | `uint32` | LE | ms | 本 trace 已耗时 |
| 60 | `warning_code` | `uint16` | LE | `PN_WARN_*` | 最近一次非致命警告 |
| 62 | `reserved` | `uint8[2]` | - | `0` | 预留 |

`state` 定义：

| 值 | 名称 | 含义 |
| --- | --- | --- |
| 0 | `PN_STATE_IDLE` | 空闲，未运行 |
| 1 | `PN_STATE_CONFIGURED` | 已接受配置，尚未启动 |
| 2 | `PN_STATE_SEARCHING_CARRIER` | auto carrier 搜索中 |
| 3 | `PN_STATE_MEASURING` | offset 点测量中 |
| 4 | `PN_STATE_STOPPING` | 收到 STOP，正在停止 |
| 5 | `PN_STATE_COMPLETE` | 本 trace 正常完成 |
| 6 | `PN_STATE_ERROR` | 错误结束 |

`flags` 定义：

| bit | 名称 | 含义 |
| --- | --- | --- |
| 0 | `configured` | 已有有效配置 |
| 1 | `running` | 状态机正在运行 |
| 2 | `carrier_valid` | 载波频率和电平有效 |
| 3 | `data_valid` | 至少已产生一个有效数据点 |
| 4 | `warning` | 存在非致命警告 |
| 5 | `stop_requested` | 已收到 STOP 请求 |
| 6 | `complete` | 本 trace 已完成 |
| 7 | reserved | 必须为 `0` |

## 6. 错误码和警告码

### 6.1 ACK 错误字节

`ACK(0x81)` 的 `error` 字节继续表示协议层接收结果，例如当前固件已有的：

| 值 | 名称 | 含义 |
| --- | --- | --- |
| `0x00` | `ERR_NONE` | 成功 |
| `0x01` | `ERR_BAD_CRC` | CRC 错误 |
| `0x02` | `ERR_BAD_FRAME` | 帧格式或 payload 长度错误 |
| `0x03` | `ERR_BAD_CMD` | 未知命令 |
| `0x04` | `ERR_INTERNAL` | 内部错误 |

相噪配置的范围、载波、RBW、DMA 等测量语义错误不要只依赖 ACK 表达，应通过
`PHASE_NOISE_STATUS.error_code` 或 `PHASE_NOISE_DATA.error_code` 表达。

### 6.2 相噪 error_code

| 值 | 名称 | 含义 |
| --- | --- | --- |
| `0` | `PN_ERR_OK` | 正常 |
| `1` | `PN_ERR_BAD_CONFIG` | 配置字段非法，例如 offset 范围或 average 为 0 |
| `2` | `PN_ERR_CARRIER_NOT_FOUND` | auto carrier 搜索失败 |
| `3` | `PN_ERR_OFFSET_OUT_OF_RANGE` | offset 对应 RF 超出设备范围 |
| `4` | `PN_ERR_RBW_UNSUPPORTED` | 当前 RBW 能力不支持该 offset 或策略 |
| `5` | `PN_ERR_LO_LOCK_TIMEOUT` | LO 锁定超时 |
| `6` | `PN_ERR_DMA_TIMEOUT` | DMA 等待超时 |
| `7` | `PN_ERR_MEASURE_FAILED` | 功率测量失败 |
| `8` | `PN_ERR_BUSY` | 已有相噪任务运行，不能接受新 START |
| `9` | `PN_ERR_NOT_CONFIGURED` | 未设置有效配置就 START |
| `10` | `PN_ERR_STOPPED_BY_HOST` | 被 STOP 命令中断 |
| `11` | `PN_ERR_UNSUPPORTED_VERSION` | `version` 不支持 |
| `12` | `PN_ERR_INTERNAL` | 其他内部错误 |

### 6.3 warning_code

| 值 | 名称 | 含义 |
| --- | --- | --- |
| `0` | `PN_WARN_NONE` | 无警告 |
| `1` | `PN_WARN_OFFSET_BELOW_RBW` | offset 小于当前 RBW，结果可信度低 |
| `2` | `PN_WARN_ENBW_ESTIMATED` | 使用 `ENBW ~= RBW` 估算 |
| `3` | `PN_WARN_CARRIER_LEVEL_LOW` | 载波电平过低，动态范围可能不足 |
| `4` | `PN_WARN_RF_RANGE_CLIPPED` | offset 计划被 RF 范围裁剪 |
| `5` | `PN_WARN_PARTIAL_DUAL_SIDEBAND` | dual 模式下只有一侧有效 |
| `6` | `PN_WARN_PLAN_TRUNCATED` | offset 点表超过固件上限，`total_points` 为实际测量点数 |

## 7. 推荐交互流程

```text
Host -> Device: SET_PHASE_NOISE_CONFIG(0x0F)
Device -> Host: ACK(0x81)

Host -> Device: START_PHASE_NOISE(0x10)
Device -> Host: ACK(0x81)
Device -> Host: PHASE_NOISE_STATUS(0x87)  state=SEARCHING_CARRIER/MEASURING
Device -> Host: PHASE_NOISE_DATA(0x86)    one offset point per frame
Device -> Host: PHASE_NOISE_DATA(0x86)    flags.done=1 on final point
Device -> Host: PHASE_NOISE_STATUS(0x87)  state=COMPLETE or ERROR
```

停止流程：

```text
Host -> Device: STOP_PHASE_NOISE(0x11)
Device -> Host: ACK(0x81)
Device -> Host: PHASE_NOISE_STATUS(0x87) state=STOPPING/IDLE, error=PN_ERR_STOPPED_BY_HOST
```

## 8. 配置校验规则

- `version` 必须为 `1`。
- 当前固件要求 `allow_estimated_enbw=1`，否则配置失败；完成 ENBW 校准表后可放宽。
- `carrier_mode` 只能为 `0` 或 `1`。
- v1 协议预留 `sideband_mode=0/1/2`；当前固件实现只接受 `0=upper`，其他值返回配置失败。
- `start_offset_hz > 0` 且 `stop_offset_hz > start_offset_hz`。
- `points_per_decade` 推荐范围为 `1..100`；当前固件 offset 点表上限为 `384`，超出时返回 `PN_WARN_PLAN_TRUNCATED`，并让 `total_points` 表示实际测量点数。
- `average_count` 推荐范围为 `1..65535`。
- manual carrier 模式下 `nominal_carrier_hz` 必须落在设备 RF 范围内。
- auto carrier 模式下当前固件要求 `nominal_carrier_hz > 0` 作为 coarse/fine 搜索中心；
  manual carrier 模式也应允许围绕 nominal 进行同样 span 的搜索。
- `carrier_search_span_khz` 为 `uint16 LE`，`0` 表示固件默认值；Host 默认发送 `100`，
  即 `100 kHz`。固件可根据状态机能力裁剪搜索点数，但必须保持可观测的 warning/error。
- `minimum_carrier_level_dbm_i8` 为有符号 `int8`，Host 默认发送 `-50 dBm`；低于该阈值的
  carrier 不得置 `carrier_valid`，对应相噪点不得置 `phase_noise_valid`。
- 当前固件 upper sideband 生成的 RF 测量点必须落在设备 RF 范围内，否则返回
  `PN_ERR_OFFSET_OUT_OF_RANGE`；lower/dual 后续实现时也必须遵守同一范围约束，
  可设置 `PN_WARN_RF_RANGE_CLIPPED` 或 `PN_WARN_PARTIAL_DUAL_SIDEBAND`。
- 目标 `1 kHz` offset 由协议允许；若后续硬件/校准策略判定某个 RBW 不可用，可返回
  `PN_ERR_RBW_UNSUPPORTED`。

## 9. 上位机 parser/model

Host 真实串口接入使用以下独立模型，不复用 `SpectrumSegment`：

```dart
class PhaseNoiseConfigDraft {
  final int version;
  final int flags;
  final int carrierMode;
  final int sidebandMode;
  final double nominalCarrierHz;
  final double startOffsetHz;
  final double stopOffsetHz;
  final int pointsPerDecade;
  final int averageCount;
  final int carrierSearchSpanKhz;
  final int minimumCarrierLevelDbm;
}

class PhaseNoiseDataFrame {
  final int traceId;
  final int plannedTotalPoints;
  final int receivedPoints;
  final int currentIndex;
  final int averageIndex;
  final double carrierHz;
  final double carrierLevelDbm;
  final int offsetHz;
  final double noisePowerDbm;
  final double phaseNoiseDbcHz;
  final int rbwHz;
  final int errorCode;
  final int flags;
}

class PhaseNoiseStatusFrame {
  final int traceId;
  final int state;
  final int flags;
  final int errorCode;
  final int plannedTotalPoints;
  final int receivedPoints;
  final int currentIndex;
  final int averageIndex;
  final int warningCode;
}
```

parser 入口建议：

```dart
Stream<PhaseNoiseDataFrame> get phaseNoiseStream;
Stream<PhaseNoiseStatusFrame> get phaseNoiseStatusStream;
PhaseNoiseDataFrame? parsePhaseNoiseData(Uint8List data);
PhaseNoiseStatusFrame? parsePhaseNoiseStatus(Uint8List data);
```

parser 只应接受固定长度 `42B/64B` 的 v1 payload；长度或 version 不匹配时计入坏帧，
不得影响现有 `SpectrumSegment` 解析。
Host 进度字段统一命名为 `plannedTotalPoints`、`receivedPoints`、`currentIndex` 和
`averageIndex`；`plannedTotalPoints` 来自协议 `total_points`，`receivedPoints` 可由
`currentIndex + 1` 限幅到 `plannedTotalPoints` 得到。

## 10. 固件实现提示

- 当前 `device_protocol.c/.h` 已增加 `CMD_SET_PHASE_NOISE_CONFIG` 等宏和 handler。
- 相噪引擎应独立于普通 `sweep_engine`，不要把普通频谱热路径改成相噪专用逻辑。
- 固件应按 offset 点表流式调用专用发送函数，保持“一帧一点”的第一版行为。
- 如果后续需要多点合帧，应定义 `version = 2` 或新增 payload 格式，不要改变 v1
  `PHASE_NOISE_DATA` 的 `42B` 固定长度。
