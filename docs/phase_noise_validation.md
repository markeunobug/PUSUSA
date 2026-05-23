# 相位噪声验证、校准和验收

本文面向 `host_computer/flutter_pusu` 和
`code/pusu_20260516/vitis/pusu_20260516/src` 的相位噪声功能联调。目标是让算法、协议、
CSV 结果和实机测试都有可重复的验收路径，并明确哪些结果只能标记为 `UNCAL` 或估算。

## 1. 验证边界

当前阶段只验收相位噪声功能的可联调性和结果一致性，不声明商业级相噪仪精度。

范围内：

- 上位机纯算法：载波搜索、offset 转换、`dBc/Hz` 换算、线性域平均、边界 warning。
- 协议契约：`SET_PHASE_NOISE_CONFIG(0x0F)`、`START/STOP/STATUS` 请求帧、
  `PHASE_NOISE_DATA(0x86)` 和 `PHASE_NOISE_STATUS(0x87)` 响应帧的长度、端序、CRC。
- 结果文件：CSV metadata、每点 offset/RBW/噪声功率/`dBc/Hz`/valid/warning 的一致性。
- 实机流程：信号源、参考时钟、RBW 策略、平均次数、失败定位和实验记录格式。
- 校准标注：`UNCAL`、`Estimated ENBW`、`Offset < RBW`、`Instrument noise limited`。

范围外：

- 不声明商业级相噪仪精度或已完成 ENBW/幅度校准。
- 不覆盖 Host 真实 `0x86/0x87` parser/UI 绑定；该项属于下一轮串口联调任务。
- 不修改 `host_computer/flutter_hello`、`code/pusu_test` 或 Vivado/Vitis 生成产物。

## 2. 快速离线验收

无硬件时先跑以下检查：

```powershell
python tools\phase_noise_protocol_smoke_test.py
python tools\phase_noise_result_check.py --self-test
C:\learning\tools\flutter\bin\cache\dart-sdk\bin\dart.exe test host_computer\flutter_pusu\test\phase_noise_processor_test.dart
```

期望结果：

- 协议 smoke test 能构造并解析固定长度相噪帧，校验 CRC、payload 长度、保留字段和
  `dBc/Hz` 公式。
- CSV result check 的 self-test 能通过一份合格样例，并确认一份故意错误样例会失败。
- Dart processor tests 全部通过，覆盖算法和 warning 的主路径。

## 3. 算法验收

算法层以 `host_computer/flutter_pusu/test/phase_noise_processor_test.dart` 为主验收入口。
验收点如下：

| 验收项 | 方法 | 通过标准 |
| --- | --- | --- |
| `dBc/Hz` 换算 | 输入 carrier、noise power、ENBW/RBW | `noise_power_dbm - carrier_dbm - 10*log10(enbw_hz)` |
| 自动载波 | 从 sweep 点中选最大功率点 | 返回 measured carrier 和 carrier level |
| 手动载波 | nominal 附近搜索或取最近点 | 保留 nominal，记录 measured 与初始频偏 |
| 单边带 offset | 只取 upper 或 lower 侧 | offset 落在配置范围内并按 RBW 判定 valid |
| 双边带平均 | paired upper/lower 功率点 | 先转线性功率平均，再转 dB |
| Trace 平均 | 多次 sweep 的 `dBc/Hz` | 在线性域平均，不能直接平均 dB |
| 边界 warning | offset、carrier level、点数不足 | 输出对应 warning code，结果不被误标为已校准 |

验收失败定位：

- 公式偏差：先确认 `enbwHz` 是校准值还是 `rbwHz` 估算值。
- 平均结果偏差：检查是否误用 dB 算术平均。
- offset 丢点：检查载波 measured frequency、sideband 模式和 start/stop offset。
- 近端结果异常：检查 `startOffsetHz < rbwHz` 是否被标记为 invalid 或 warning。

## 4. 协议验收

相噪专用协议以 `docs/phase_noise_protocol.md` 为唯一契约。离线协议检查脚本：

```powershell
python tools\phase_noise_protocol_smoke_test.py --dump-hex
```

脚本验证内容：

- 构造 `SET_PHASE_NOISE_CONFIG(0x0F)` 固定 `36B` payload。
- 构造 `START_PHASE_NOISE(0x10)`、`STOP_PHASE_NOISE(0x11)`、
  `GET_PHASE_NOISE_STATUS(0x12)` 空 payload 请求。
- 构造并解析 `PHASE_NOISE_DATA(0x86)` 固定 `42B` payload。
- 构造并解析 `PHASE_NOISE_STATUS(0x87)` 固定 `64B` payload。
- 校验外层帧头尾、payload length、CRC16 Modbus、version 和 reserved 字段。
- 对样例点按 `ENBW ~= RBW` 重新计算 `phase_noise_dbc_hz`。

实机协议联调顺序：

1. 只发 `GET_PHASE_NOISE_STATUS(0x12)`，确认固件能返回 ACK 和 `PHASE_NOISE_STATUS(0x87)`，
   不应卡死串口。
2. 发送 `SET_PHASE_NOISE_CONFIG(0x0F)`，确认 ACK 成功或给出可解释错误码。
3. 发送 `START_PHASE_NOISE(0x10)`，确认进入 searching/measuring 或返回
   `PN_ERR_NOT_CONFIGURED`、`PN_ERR_RBW_UNSUPPORTED` 等语义错误。
4. 接收 `PHASE_NOISE_DATA(0x86)`，检查 `trace_id`、`current_index`、`average_index`、
   `offset_hz` 单调性和 `done` 标志。
5. 发送 `STOP_PHASE_NOISE(0x11)`，确认能停止并返回 stopped/idle 状态。

协议失败定位：

| 现象 | 优先检查 |
| --- | --- |
| 无响应 | 当前固件是否仍在文本协议或未注册相噪命令 |
| ACK `ERR_BAD_FRAME` | payload 长度、Len 字段、帧尾 |
| ACK `ERR_BAD_CRC` | CRC 覆盖范围和大端发送 |
| parser 拒收 `0x86` | payload 是否正好 `42B`，version 是否为 `1` |
| `dBc/Hz` 不一致 | 固件是否使用校准 ENBW，上位机是否按 RBW 估算复算 |

## 5. CSV 结果验收

建议导出格式：

```text
metadata_key,metadata_value
carrier_hz,2219997671
carrier_dbm,1.25
start_offset_hz,1000
stop_offset_hz,1000000
average_count,10
enbw_mode,estimated

offset_hz,raw_dbc_hz,avg_dbc_hz,noise_power_dbm,rbw_hz,valid,warning
1000,-92.1,-93.0,-62.1,1000,1,
```

离线结果检查：

```powershell
python tools\phase_noise_result_check.py path\to\phase_noise_result.csv
```

脚本检查内容：

- metadata 必须包含 `carrier_hz`、`carrier_dbm`、`start_offset_hz`、`stop_offset_hz`、
  `average_count`、`enbw_mode`。
- data header 必须包含 `offset_hz`、`raw_dbc_hz`、`avg_dbc_hz`、`noise_power_dbm`、
  `rbw_hz`、`valid`、`warning`。
- offset 必须为正、单调递增，并落在 metadata 的 start/stop 范围内。
- `rbw_hz` 必须为正。
- 当 `enbw_mode=estimated` 时，按 `rbw_hz` 复算 `raw_dbc_hz`。
- 当存在 `enbw_hz` 列或 metadata 时，优先按 `enbw_hz` 复算。
- `offset_hz < rbw_hz` 时，必须满足 `valid=0` 或 warning 包含 `Offset < RBW` /
  `PN_WARN_OFFSET_BELOW_RBW` / `offset_below_rbw`。

推荐判定：

- 展示用：允许 `enbw_mode=estimated`，但结果必须标 `UNCAL` 或 `Estimated ENBW`。
- 对比用：同一仪器、同一配置、同一温度范围内可比较趋势。
- 验收用：必须保存原始 CSV、设备配置、信号源配置和脚本输出。
- 精度声明用：只有完成幅度校准和 RBW ENBW 校准后才允许移除 `UNCAL`。

## 6. 实机测量流程

### 6.1 仪器连接

1. 预热 PuSuSA、信号源和外部参考至少 20 分钟。
2. 信号源输出单音，例如 `100 MHz`、`-10 dBm`，关闭调制。
3. 优先让信号源和被测仪器使用同一 `10 MHz` 参考；若不能同源，记录参考方式。
4. 连接链路中记录衰减器、线缆、转接头和前端增益设置。
5. 先在普通频谱模式确认 carrier 峰值稳定、无明显过载和无错误状态。

### 6.2 基线测量

建议第一轮参数：

| 参数 | 建议值 |
| --- | --- |
| Carrier mode | Auto |
| Offset start | `1 kHz`，但若 RBW 仍为 `10 kHz` 必须标记 approximate |
| Offset stop | `1 MHz` |
| RBW strategy | 近端优先 `1 kHz`，否则 `10 kHz` 并标 `Offset < RBW` |
| Average count | `10` |
| Sideband | Upper only；lower/dual 为协议预留，当前固件未实现 |
| Carrier search span | `100 kHz` |
| Carrier threshold | `-50 dBm`，或按实机链路提高到不低于当前处理器默认 `minimumCarrierLevelDbm` |

步骤：

1. 普通频谱模式执行窄 span sweep，使用 marker 记录 carrier frequency 和 level。
2. 相噪模式设置 offset 范围、RBW 策略、平均次数、`100 kHz` carrier search span 和
   `-50 dBm` carrier threshold。
3. 单次测量，记录 `PHASE_NOISE_STATUS.measured_carrier_hz` 和 `carrier_level_dbm`，
   确认 raw trace 点数、offset 顺序和 warning。
4. 对比普通频谱 marker carrier level 与相噪 measured carrier level；正常验收中二者不应
   相差 `19 dB`。若差异接近或超过该量级，应判为 carrier acquisition/幅度链路问题，
   不进入有效相噪曲线验收。
5. 若相噪 measured carrier level 低于 configured trigger/min carrier level，应返回
   `PN_ERR_CARRIER_NOT_FOUND` 或 `PN_WARN_CARRIER_LEVEL_LOW`，且曲线不得被标为有效结果。
6. 连续测量到 average count 完成，导出 CSV。
7. 运行 `phase_noise_result_check.py`，保存脚本输出。
8. 调整信号源电平 10 dB，复测一次，确认相对趋势合理且无过载。
9. 若有低相噪参考源，用它测系统底噪；若测得曲线不再下降，标记
   `Instrument noise limited`。

### 6.3 重复性验收

同一配置连续导出三次 CSV：

- carrier measured frequency 漂移应记录在实验表。
- 每个关键 offset 的 avg trace 差异建议小于 `3 dB`；超过时记录为稳定性风险。
- warning 集合必须可解释，不能出现未记录的 error code。
- 若任一 CSV 无法通过离线结果检查，不进入展示验收。

## 7. 校准策略

### 7.1 幅度校准

相噪换算依赖 carrier level 和 noise power 的相对准确度。幅度校准未完成前：

- 所有结果文件 metadata 写入 `calibration_state,UNCAL`。
- UI 或报告中显示 `UNCAL`。
- 结果只能用于开发对比和趋势展示，不用于绝对指标声明。

幅度校准建议记录：

| 字段 | 示例 |
| --- | --- |
| calibration_date | `2026-05-22` |
| source_model | `...` |
| power_meter_model | `...` |
| frequency_points_hz | `100e6;500e6;1000e6` |
| input_levels_dbm | `-30;-20;-10;0` |
| frontend_state | attenuator/preamp/VGA 设置 |

### 7.2 RBW ENBW 校准

第一版允许 `ENBW ~= RBW`，但必须标记：

- metadata: `enbw_mode,estimated`
- warning: `Estimated ENBW` 或 `PN_WARN_ENBW_ESTIMATED`

完成 ENBW 校准后，推荐在 CSV 中新增：

```text
enbw_mode,calibrated
rbw_enbw_table,1000:1230;10000:11200;30000:33500
```

或在 data 表中新增每点 `enbw_hz` 列。`phase_noise_result_check.py` 会优先使用
`enbw_hz` 复算。

### 7.3 UNCAL 标注规则

必须显示或导出的标注：

| 条件 | 标注 |
| --- | --- |
| 幅度校准未完成 | `UNCAL` |
| `enbw_mode=estimated` | `Estimated ENBW` |
| `offset_hz < rbw_hz` | `Offset < RBW` |
| carrier 电平低于阈值 | `Carrier level low` |
| 被测源低于系统本底 | `Instrument noise limited` |
| 只完成单边带测量 | `Upper sideband only` |

验收结论中不能把带 `UNCAL` 的曲线描述为绝对准确，只能描述为“估算相噪曲线”或“开发验证曲线”。

## 8. 实验记录模板

```text
test_id:
date:
operator:
firmware_commit:
host_commit:
device_serial:
signal_source_model:
signal_source_serial:
reference_clock:
carrier_hz:
carrier_level_dbm:
frontend_state:
rbw_strategy:
enbw_mode:
average_count:
sideband_mode:
offset_start_hz:
offset_stop_hz:
csv_file:
protocol_log:
result_check_output:
warnings:
pass_fail:
notes:
```

## 9. 最低验收标准

进入下一阶段前至少满足：

- Dart processor tests 通过。
- `phase_noise_protocol_smoke_test.py` 离线通过。
- `phase_noise_result_check.py --self-test` 离线通过。
- 至少一份实机 CSV 通过 `phase_noise_result_check.py`。
- 实机记录明确写出 `UNCAL`、`Estimated ENBW` 或已完成的校准状态。
- 若 Host 仍使用 demo 数据，文档和报告必须说明当前尚未完成真实串口数据接入。

## Dense point acceptance addendum

For dense-point validation, exported CSV metadata must include:

```text
points_per_decade,60
planned_points,181
received_points,181
```

Acceptance rules:
- Fast = `30 points/decade`; expected `1 kHz..1 MHz` planned point count is `91`.
- Normal = `60 points/decade`; expected `1 kHz..1 MHz` planned point count is `181`.
- Fine = `90 points/decade`; expected `1 kHz..1 MHz` planned point count is `271`.
- `planned_points` must equal `round(log10(stop_offset_hz / start_offset_hz) * points_per_decade) + 1`.
- `received_points` must equal the exported data row count and must be `<= planned_points`.
- `received_points == planned_points` is required for an untruncated final acceptance run. If firmware caps or truncates the plan, the CSV/check output must make the mismatch visible and the run is not a dense-point pass.
- Legacy CSV files missing all three dense fields may be accepted by `phase_noise_result_check.py` with a warning for backward compatibility, but they are not sufficient as dense-point acceptance evidence.
- If any dense field is present, all three are required and mismatches are treated as failures.

Visual acceptance:
- Normal and Fine traces must render all real sampled points; display smoothing must not create fake export or marker points.
- Marker readout must snap to an existing raw/average point, not an interpolated point.
- Page status, protocol progress, and CSV metadata must agree on `received/total` whenever real `0x86/0x87` data is available.
