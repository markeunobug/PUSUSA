# 子任务 07：相位噪声验证、校准和验收

## 目标

制定并实现相位噪声功能的验证流程，确保 UI、数学换算、协议、固件测量链路可以被重复验证。输出实验记录格式和边界提示策略。

## 相关文件

建议新增：

- `docs/phase_noise_validation.md`
- `tools/phase_noise_protocol_smoke_test.py`
- `tools/phase_noise_result_check.py`

可能修改：

- `docs/phase_noise_measurement_plan.md`
- `docs/uart_protocol_summary.md`

## 验证范围

1. 上位机纯算法验证
   - 输入模拟 carrier/noise/RBW。
   - 验证 `dBc/Hz` 计算。
   - 验证线性域平均。

2. 图表验证
   - 模拟 `1 kHz` 到 `1 MHz` offset 数据。
   - 验证 log 轴、marker、raw/avg trace。

3. 协议验证
   - 构造 `PHASE_NOISE_DATA` 测试帧。
   - 验证 Dart parser。
   - Python smoke test 可以发送配置命令并解析返回。

4. 固件验证
   - 验证 `1 kHz RBW` 不崩溃、不越界。
   - 验证普通频谱 RBW 不被破坏。
   - 验证相噪引擎可 stop、error recover。

5. 实机测量验证
   - 使用稳定单音信号源。
   - 记录：
     - 信号源型号
     - carrier frequency
     - carrier level
     - reference clock
     - RBW strategy
     - average count
     - measured trace

## 校准和提示

必须在 UI 或结果中标记：

- `UNCAL`：未完成幅度/RBW ENBW 校准。
- `Estimated ENBW`：第一版使用 `ENBW ~= RBW`。
- `Offset < RBW`：offset 小于当前 RBW 时结果近似。
- `Instrument noise limited`：当被测源可能低于本机 LO 噪声时提示。

## 建议结果文件格式

CSV：

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

## 验收标准

- 有一份可执行的验证文档。
- 有至少一个无需硬件的算法/协议测试。
- 实机验证步骤清楚，失败时能定位到 UI、协议、RBW 或测量链路。
- 明确哪些结果是未校准估算，哪些结果可以用于对比展示。

## 非目标

- 不实现主功能。
- 不调参替代子任务 05/06。

