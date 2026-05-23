# 子任务 09：Host 相噪协议 points/decade 与进度接入准备

## 目标

为真实相噪串口接入准备 Host 侧协议模型，使 `SET_PHASE_NOISE_CONFIG` 能携带用户选择的
`points_per_decade`，并让 Host 能解析真实 `total_points/current_index` 进度。

本任务可以先完成协议模型和测试，不要求一次把 UI 完全切到实机数据。

## 先读

1. `docs/phase_noise_dense_points_plan.md`
2. `docs/phase_noise_protocol.md`
3. `tools/phase_noise_protocol_smoke_test.py`
4. `host_computer/flutter_pusu/lib/serial_protocol.dart`
5. `host_computer/flutter_pusu/lib/phase_noise_models.dart`

## 修改范围

优先修改：

- `host_computer/flutter_pusu/lib/serial_protocol.dart`
- `host_computer/flutter_pusu/lib/phase_noise_models.dart`
- `host_computer/flutter_pusu/test/` 下新增相噪协议 parser 测试，若项目结构允许
- `tools/phase_noise_protocol_smoke_test.py`
- `docs/phase_noise_protocol.md`，仅同步字段说明

不要修改：

- 固件状态机
- 图表视觉样式
- 旧工程和生成产物

## 实现要求

1. Host 侧增加相噪 config payload 构造能力：
   - `version = 1`
   - `flags` 至少包含 `allow_estimated_enbw`
   - `carrier_mode`
   - `sideband_mode = upper`
   - `nominal_carrier_hz`
   - `start_offset_hz`
   - `stop_offset_hz`
   - `points_per_decade`
   - `average_count`
2. `points_per_decade` 来自 `PhaseNoiseConfig.pointsPerDecade`，不要写死 `20`。
3. Host 侧为 `PHASE_NOISE_DATA(0x86)` 和 `PHASE_NOISE_STATUS(0x87)` 建独立模型/stream。
   - 不复用 `SpectrumSegment`。
   - 解析 `total_points/current_index/average_index`。
4. 进度字段设计：
   - `plannedTotalPoints`
   - `receivedPoints`
   - `currentIndex`
   - `averageIndex`
5. 若暂不接 UI，至少暴露 stream 和 parser，让下一轮 UI agent 可直接绑定。
6. `tools/phase_noise_protocol_smoke_test.py` 默认 `points_per_decade` 更新为 `60`，并保留 CLI 或函数参数覆盖能力。

## 验收

运行：

```powershell
python tools\phase_noise_protocol_smoke_test.py --dump-hex
python -m py_compile tools\phase_noise_protocol_smoke_test.py
C:\learning\tools\flutter\bin\cache\dart-sdk\bin\dart.exe analyze host_computer\flutter_pusu\lib
```

如新增 Dart 测试，运行对应测试。

验收点：

- config payload offset `28..29` 正确写入 `points_per_decade` 小端。
- status/data parser 能读出 `total_points/current_index/average_index`。
- 收到 `0x86/0x87` 不再走 unknown frame。

## 完成汇报

汇报：

- 新增/修改的模型和 stream。
- `points_per_decade` 的来源。
- 已运行命令和结果。
- UI 绑定还剩哪些工作。
