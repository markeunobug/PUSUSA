# 子任务 11：密集点数视觉与验收检查

## 目标

为相位噪声密集点优化提供可重复验收，确保曲线更密、marker 稳定、CSV/协议/固件点数一致。

## 先读

1. `docs/phase_noise_dense_points_plan.md`
2. `docs/phase_noise_validation.md`
3. `host_computer/flutter_pusu/lib/phase_noise_chart.dart`
4. `host_computer/flutter_pusu/lib/main.dart`
5. `tools/phase_noise_result_check.py`
6. `tools/phase_noise_protocol_smoke_test.py`

## 修改范围

优先修改：

- `docs/phase_noise_validation.md`
- `tools/phase_noise_result_check.py`
- `tools/phase_noise_protocol_smoke_test.py`
- `host_computer/flutter_pusu/test/phase_noise_chart_test.dart`
- 必要时新增视觉检查说明文档

不要修改：

- 固件热路径
- 大块 UI 实现
- 生成产物

## 实现要求

1. 在验证文档中增加密集点验收项：
   - Fast/Normal/Fine 的 points/decade。
   - 1 kHz 到 1 MHz 的 expected point count。
   - received/total 一致性。
2. `phase_noise_result_check.py` 增加对 CSV metadata 的检查：
   - `points_per_decade`
   - `planned_points`
   - `received_points`
   - 若没有这些字段，给出 warning 或失败策略，按当前 CSV 格式决定。
3. `phase_noise_protocol_smoke_test.py` 覆盖默认 `points_per_decade=60`。
4. Chart 测试覆盖：
   - 高点数 trace 不丢点。
   - marker 仍吸附真实点。
   - CSV 导出包含密度字段，若子任务 08 已实现。
5. 如果能跑 Flutter app，截一张 Normal 档和 Fine 档对比图；不能截图则说明原因。

## 验收命令

```powershell
python tools\phase_noise_protocol_smoke_test.py --dump-hex
python tools\phase_noise_result_check.py --self-test
python -m py_compile tools\phase_noise_protocol_smoke_test.py tools\phase_noise_result_check.py
C:\learning\tools\flutter\bin\flutter.bat test test\phase_noise_processor_test.dart test\phase_noise_chart_test.dart
C:\learning\tools\flutter\bin\cache\dart-sdk\bin\dart.exe analyze host_computer\flutter_pusu\lib
```

## 人工验收清单

- Normal 档 `1 kHz..1 MHz` 曲线点数明显比当前更密。
- Fine 档若可用，曲线更细但 UI 不明显卡顿。
- Marker 读数仍落在真实采样点。
- CSV 中点数与页面进度一致。
- 若固件截断点数，页面或结果检查能明确提示。

## 完成汇报

汇报：

- 新增验收规则。
- 已运行命令和结果。
- 是否完成截图/视觉检查。
- 剩余风险。
