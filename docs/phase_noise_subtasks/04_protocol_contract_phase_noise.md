# 子任务 04：相位噪声专用协议契约设计

## 目标

设计上位机与下位机之间的相位噪声专用协议，为后续 `phase_noise_engine` 落地提供稳定接口。此任务优先产出文档和模型，不要求立即实现完整固件。

## 相关文件

必须更新：

- `docs/uart_protocol_summary.md` 或新增 `docs/phase_noise_protocol.md`

可能修改：

- `host_computer/flutter_pusu/lib/serial_protocol.dart`
- `host_computer/flutter_pusu/lib/device_models.dart`

下位机涉及但本任务不强制实现：

- `code/pusu_20260516/vitis/pusu_20260516/src/device_protocol.c`
- `code/pusu_20260516/vitis/pusu_20260516/src/device_protocol.h`

## 当前协议背景

当前二进制帧格式：

```text
0xAA | Len(2B BE) | Cmd(1B) | Data | CRC16 Modbus | 0x55
```

当前响应：

- `ACK(0x81)`
- `SPECTRUM_DATA(0x82)`
- `STATUS_DATA(0x83)`
- `RF_FRONTEND_STATUS(0x84)`
- `PROFILE_DATA(0x85)`

建议为相噪新增命令，不复用 `SPECTRUM_DATA` 承载所有字段。

## 建议命令

可选命令号，最终以未占用为准：

```text
0x0F SET_PHASE_NOISE_CONFIG
0x10 START_PHASE_NOISE
0x11 STOP_PHASE_NOISE
0x12 GET_PHASE_NOISE_STATUS
0x86 PHASE_NOISE_DATA
0x87 PHASE_NOISE_STATUS
```

## 建议配置 payload

`SET_PHASE_NOISE_CONFIG(0x0F)`：

```text
version(1B)
flags(1B)
carrier_mode(1B)       0=manual, 1=auto
sideband_mode(1B)      0=upper, 1=lower, 2=dual_average
nominal_carrier_hz(8B float64 LE)
start_offset_hz(8B float64 LE)
stop_offset_hz(8B float64 LE)
points_per_decade(2B uint16 LE)
average_count(2B uint16 LE)
reserved(4B)
```

## 建议数据 payload

`PHASE_NOISE_DATA(0x86)`：

```text
version(1B)
flags(1B)              bit0=done, bit1=carrier_valid, bit2=warning
trace_id(2B uint16 BE)
total_points(2B uint16 BE)
current_index(2B uint16 BE)
average_index(2B uint16 BE)
carrier_hz(8B float64 LE)
carrier_level_dbm(4B float32 LE)
offset_hz(4B uint32 LE)
noise_power_dbm(4B float32 LE)
phase_noise_dbc_hz(4B float32 LE)
rbw_hz(4B uint32 LE)
error_code(1B)
reserved(3B)
```

如果每帧发送多个点，可扩展为：

```text
header + point_count + N * point_record
```

但第一版建议每帧一个点，和当前 `device_protocol_stream_spectrum_point()` 的流式习惯一致。

## 错误码建议

```text
0 = OK
1 = BAD_CONFIG
2 = CARRIER_NOT_FOUND
3 = OFFSET_OUT_OF_RANGE
4 = RBW_UNSUPPORTED
5 = LO_LOCK_TIMEOUT
6 = DMA_TIMEOUT
7 = MEASURE_FAILED
```

## 上位机要求

- 在 `serial_protocol.dart` 中预留 parser 和 stream：
  - `Stream<PhaseNoiseSegment>`
  - `parsePhaseNoiseData()`
- 不要破坏现有 `SpectrumSegment`。
- 未实现固件时 parser 可以只放模型和 TODO，不发送真实命令。

## 验收标准

- 产出协议文档，字段端序和单位清楚。
- 命令号不与现有协议冲突。
- 上位机/下位机子任务可以按文档独立实现。
- 明确第一版是否每帧一个点。

## 非目标

- 不实现完整 `phase_noise_engine`。
- 不实现 `1 kHz RBW`。
- 不做 UI。

