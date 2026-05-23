# 子任务 06：下位机相位噪声专用测量引擎

## 目标

新增下位机相位噪声专用测量引擎，支持 `1 kHz` 到 `1 MHz` offset 测量。该引擎应复用现有 LO、DMA、DDC/RBW 功率测量链路，但不要直接把普通 `sweep_engine` 改成相噪专用逻辑。

本任务依赖：

- 子任务 04 的协议契约。
- 子任务 05 的 `1 kHz RBW` 能力。

## 建议新增文件

- `code/pusu_20260516/vitis/pusu_20260516/src/phase_noise_engine.c`
- `code/pusu_20260516/vitis/pusu_20260516/src/phase_noise_engine.h`
- `code/pusu_20260516/vitis/pusu_20260516/src/phase_noise_plan.c`
- `code/pusu_20260516/vitis/pusu_20260516/src/phase_noise_plan.h`

需要修改：

- `device_protocol.c/.h`
- `main.c`
- 可能需要 `signal_processing.h`

## 设计原则

1. 不破坏普通扫频
   - `sweep_engine` 保持普通频谱模式。
   - 相噪引擎单独维护状态机。

2. offset 点表
   - 使用对数 offset 规划，不使用普通线性 `start/stop + RBW/2`。
   - 默认范围：

```text
1 kHz to 1 MHz
```

   - 每 decade 默认 20 或 30 个点。

3. 分段 RBW
   - 建议初始策略：

```text
1 kHz - 10 kHz       RBW 1 kHz
10 kHz - 100 kHz     RBW 10 kHz
100 kHz - 1 MHz      RBW 30 kHz 或 100 kHz
```

   - 实际映射要结合子任务 05 的稳定性。

4. 载波测量
   - 支持 manual carrier。
   - 支持 auto carrier：在 nominal 附近做小范围搜索。
   - 记录：
     - nominal carrier
     - measured carrier
     - carrier level
     - initial delta
     - drift

5. 功率换算
   - 固件可以只返回 `noise_power_dbm` 和 `rbw_hz`，让上位机算 `dBc/Hz`。
   - 或固件同时返回 `phase_noise_dbc_hz`。
   - 推荐两者都返回，便于调试。

6. 状态机
   - 类似 `sweep_engine`：
     - prepare
     - set LO
     - wait lock
     - arm DMA
     - accumulate
     - measure
     - emit point
     - next offset
     - done/error

7. 双边测量预留
   - 第一版可以只测 upper sideband。
   - 结构上预留 lower/dual average。

## 验收标准

- 新增引擎不影响普通 `GET_SPECTRUM`。
- 能根据配置生成 `1 kHz` 到 `1 MHz` offset 点表。
- 能按 offset 设置 RF：

```text
RF = carrierHz + offsetHz
```

- 能流式返回每个 offset 点。
- 停止命令能中断相噪测量。
- 错误能通过状态或数据帧返回。

## 非目标

- 不做完整 IQ 相位 PSD 算法。
- 不做交叉相关。
- 不保证商用相噪仪级别底噪。

