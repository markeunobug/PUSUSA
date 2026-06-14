# PL/PS 有限 Burst + SG DMA 改造计划

日期：2026-06-08

工程：`C:\learning\pusu_V2\code\pusu_20260608`

目标：把低 RBW 需要的大量连续原始样本，改成由 PL 明确输出有限数量的 AXI4-Stream packet，PS 用 AXI DMA SG 一次接收完整 burst。核心原则是：DMA 有多少个 BD，PL 就只吐多少个 TLAST packet，不能让 PL 无限连续输出后撞上 SG BD 链表尾部。

## 1. 当前结论

已经验证正常的部分：

- `main 4096` 单帧 DMA 正常。
- `sgring 4096x8 target64` 和 `sgring 8192x4 target128` 正常。
- AXI DMA 的 SG 硬件通路已经接通：`axi_dma_0/M_AXI_SG -> axi_mem_intercon/S01_AXI -> processing_system7_0/S_AXI_HP0`。

现在不合理的部分：

- sweep 里的临时 SG batch 仍然调用 `pl_capture_start_stream()`。
- `pl_capture_start_stream()` 对应 PL 的无限 continuous stream。
- PS 只提交有限个 BD，例如 8 个；PL 却可能继续输出第 9 个 packet。
- 在低 RBW 下，100K/30K/10K/1K 需要跨多个 batch 或大量 packet，容易触发 AXI DMA S2MM internal error，典型表现是 `last_irq=0x00005000`。

因此下一步不能直接把 sweep 切到现在的 SG ring 正式模式。先要加一个有限 burst 模式，让 PL 输出 packet 数和 PS 的 BD 数严格一致。

## 2. Agent 分工

本轮已分配两个子 agent：

| Agent | 职责 | 工作边界 | 输出 |
| --- | --- | --- | --- |
| PL agent `Maxwell` | 调查并拆解 PL RTL 与 Vivado BD 改动 | `adc_capture_axis.v`、`adc_capture_control_axi.v`、`LTC2208.v`、`system.bd` | 端口、寄存器、FSM、BD 连接、验证点 |
| PS agent `Raman` | 调查并拆解 PS/Vitis 与测试脚本改动 | `pl_capture_control.*`、`dma_capture.*`、`sweep_engine.c`、`signal_processing.*`、`device_protocol.c`、`tools/*.py` | API、DMA SG burst、sweep 接入、测试命令 |

两个 agent 只负责调查和任务拆解，不直接改文件。主线程负责最终合并方案和后续代码落地。

## 3. 总体步骤

### Step 0：恢复安全基线

先禁用当前 sweep 中不安全的 SG batch 路径，但保留所有 SG smoke 测试命令。

PS 侧建议：

- 在 `app_config.h` 增加 `DMA_SWEEP_SG_BATCH_ENABLE 0U`。
- 在 `sweep_engine_try_sg_batch_capture()` 开头用该宏直接返回 0。
- `dma_capture_sg_ring_smoke_test()` 继续保留，用来验证硬件 SG ring。

预期结果：

- 低 RBW 回到旧的受控单帧反复 rearm 路径。
- 速度不一定快，但不应该再因为临时 SG batch 触发 `last_irq=0x5000`。

### Step 1：PL 增加有限 burst 模式

在 `adc_capture_axis.v` 中新增模式：

```text
PS 写 frame_len = 4096
PS 写 frame_count = N
PS 触发 start
PL 连续输出 N 个 AXIS packet
每个 packet 长度 frame_len
每个 packet 最后一拍拉高 TLAST
第 N 个 packet 完成后自动停止
```

建议新增端口：

```verilog
input  wire [31:0] ctrl_frame_count;

output reg         status_burst_active;
output reg         status_burst_done;
output reg [31:0]  status_burst_packet_count;
output reg [31:0]  status_burst_remaining;      // 可选，便于调试
```

模式语义：

```text
ctrl_frame_count == 0：保留现有无限 stream smoke 模式
ctrl_frame_count  > 0：ctrl_start 触发有限 burst，输出 N 个 packet 后自动停
```

建议 FSM：

| 状态 | 作用 |
| --- | --- |
| `ST_IDLE` | 等待 `ctrl_start` |
| `ST_CAPTURE` | 保留现有单帧模式 |
| `ST_STREAM` | 保留现有无限 stream smoke 模式 |
| `ST_BURST` | 新增有限 burst 模式，输出 N 个 packet 后自动停 |
| `ST_DONE` | 保持完成状态供 PS 读回 |

`ST_BURST` 的硬规则：

- 只在 `m_axis_tvalid && m_axis_tready` 时递增 sample 计数。
- `m_axis_tlast` 只在每个 packet 的最后一个 accepted beat 为 1。
- 每完成一个 TLAST，`status_packet_count` 和 `status_burst_packet_count` 加 1。
- 当 `status_burst_packet_count + 1 == ctrl_frame_count` 时，完成最后一个 packet 后关闭 `tvalid` 并进入 `ST_DONE`。
- 如果 `ctrl_frame_len == 0` 或 `ctrl_frame_len > MAX_FRAME_LEN`，置 `status_error`。
- 如果处在有限 burst 请求里但 `ctrl_frame_count` 非法，置 `ERR_INVALID_FRAME_COUNT`。
- 如果 capture 过程中出现 backpressure 或 ADC overflow，置 sticky 状态，PS 丢弃本次数据。

### Step 2：AXI-Lite 控制寄存器增加 burst 字段

在 `adc_capture_control_axi.v` 中增加 AXI-Lite 寄存器和 CDC。

建议寄存器：

| Offset | 名称 | 方向 | 含义 |
| ---: | --- | --- | --- |
| `0x00` | `CONTROL` | W/R | bit0 start，bit1 abort，bit2 clear_status，bit3 soft_reset，bit4 continuous_mode，bit5 stream_enable，bit6 clear_counters，bit7 fifo_reset |
| `0x04` | `STATUS` | R | bit0 idle，bit1 busy，bit2 done，bit3 error，bit4 overflow，bit5 backpressure，bit6 tlast，bit7 streaming，bit8 burst_active，bit9 burst_done |
| `0x08` | `FRAME_LEN` | W/R | 每个 packet 的样本数，先用 4096 |
| `0x0C` | `FRAME_ID` | W/R | PS 写入的事务 ID |
| `0x28` | `PACKET_COUNT` | R | 已输出 packet 总数 |
| `0x34` | `FRAME_COUNT` | W/R | 本次有限 burst 需要输出的 packet 数；0 表示保留无限 stream |
| `0x38` | `BURST_PACKET_COUNT` | R | 本次有限 burst 已完成的 packet 数 |
| `0x3C` | `BURST_REMAINING` | R | 可选，剩余 packet 数 |

`C_S_AXI_ADDR_WIDTH = 6` 可以覆盖到 `0x3C`，所以新增 `0x34/0x38` 不需要扩大地址宽度。

### Step 3：PS 增加有限 burst API 和 smoke test

`pl_capture_control.h/.c` 增加：

```c
int pl_capture_configure_burst(u32 frame_len,
                               u32 frame_count,
                               u32 frame_id);
int pl_capture_start_burst(u32 frame_len,
                           u32 frame_count,
                           u32 frame_id);
int pl_capture_validate_burst(const pl_capture_status_t *status,
                              const pl_capture_counters_t *counters,
                              u32 frame_len,
                              u32 frame_count,
                              u32 frame_id);
```

同时增加寄存器宏：

```c
#define PL_CAPTURE_REG_FRAME_COUNT_OFFSET          0x34U
#define PL_CAPTURE_REG_BURST_PACKET_COUNT_OFFSET   0x38U
#define PL_CAPTURE_REG_BURST_REMAINING_OFFSET      0x3CU
```

`dma_capture.h/.c` 增加：

```c
int dma_capture_sg_burst_smoke_test(u32 samples_per_bd,
                                    u32 bd_count,
                                    dma_capture_sg_smoke_result_t *result);

int dma_capture_sg_burst_capture(u32 samples_per_bd,
                                 u32 bd_count,
                                 u32 *out_total_samples,
                                 dma_capture_sg_batch_diag_t *diag);
```

关键时序：

```text
1. pl_capture_abort()
2. pl_capture_stop_stream()
3. pl_capture_reset_fifo()
4. dma_capture_reset()
5. submit_sg_rx_bds(rx_buffer, bytes_per_bd, bd_count)
6. pl_capture_start_burst(samples_per_bd, bd_count, frame_id)
7. 等待 DMA 回收 bd_count 个 BD
8. 停止/清状态
9. 读 PL status/counters
10. 校验 completed_bd_count == bd_count
11. 校验 completed_bytes == samples_per_bd * bd_count * 2
12. 校验 burst_packet_count == bd_count
13. 校验 overflow/backpressure/error 均为 0
14. 如果能读到 BD SOF/EOF 位，每个 BD 都应同时有 SOF 和 EOF，且 actual length 必须等于 bytes_per_bd
```

`device_protocol.c` 和 `tools/capture_stream_smoke_test.py` 增加一个新命令，例如：

```text
CMD_CAPTURE_SG_BURST_SMOKE = 0x17
```

测试顺序：

```powershell
python C:\learning\pusu_V2\tools\capture_stream_smoke_test.py --port COM7 --baud 921600 --mode main --samples 4096 --timeout 5
python C:\learning\pusu_V2\tools\capture_stream_smoke_test.py --port COM7 --baud 921600 --mode sgring --samples-per-bd 4096 --bd-count 8 --target-bd-count 64 --timeout 5
python C:\learning\pusu_V2\tools\capture_stream_smoke_test.py --port COM7 --baud 921600 --mode sgburst --samples-per-bd 4096 --bd-count 1 --timeout 5
python C:\learning\pusu_V2\tools\capture_stream_smoke_test.py --port COM7 --baud 921600 --mode sgburst --samples-per-bd 4096 --bd-count 7 --timeout 5
python C:\learning\pusu_V2\tools\capture_stream_smoke_test.py --port COM7 --baud 921600 --mode sgburst --samples-per-bd 4096 --bd-count 19 --timeout 10
python C:\learning\pusu_V2\tools\capture_stream_smoke_test.py --port COM7 --baud 921600 --mode sgburst --samples-per-bd 4096 --bd-count 72 --timeout 20
```

后续扩大 ring 后再测：

```powershell
python C:\learning\pusu_V2\tools\capture_stream_smoke_test.py --port COM7 --baud 921600 --mode sgburst --samples-per-bd 4096 --bd-count 384 --timeout 60
python C:\learning\pusu_V2\tools\capture_stream_smoke_test.py --port COM7 --baud 921600 --mode sgburst --samples-per-bd 4096 --bd-count 982 --timeout 120
```

### Step 4：扩大 PS SG ring 和 DDR buffer

当前 `dma_capture.c` 里：

```c
#define DMA_SG_RX_BD_COUNT 8U
#define DMA_SG_RX_BD_SPACE_BYTES 2048U
```

低 RBW 需要更大 burst，建议分两级推进：

| 阶段 | BD 数 | 覆盖能力 | 目的 |
| ---: | ---: | --- | --- |
| A | 128 | 覆盖 30K 级别 | 先验证中等规模 burst |
| B | 1024 | 覆盖 10K 约 982 blocks | 覆盖低 RBW 主需求 |

同时 RX buffer 需要按最大 burst 规划：

```text
4096 samples/block * 2 bytes/sample * 1024 blocks = 8 MB
```

PS 侧要检查：

- `RX_BUFFER_BASE` 后面至少预留 8 MB 连续 DDR。
- BD ring 空间不要和 RX buffer 重叠。
- DCache flush/invalidate 范围按实际 burst bytes 做，不再沿用 64K 级假设。

### Step 5：sweep 接入有限 burst

接入原则：

- 不再使用 `dma_capture_sg_batch_capture()` 的无限 stream 版本。
- `signal_processing_get_sg_dma_samples()` 返回本点仍需的样本块数。
- sweep 对一个点调用 `dma_capture_sg_burst_capture(4096, bd_count, ...)`。
- burst 成功后，直接 `signal_processing_accumulate_dma(rx_buffer, captured_samples)`。
- 如果 `bd_count` 超过当前 ring 能力，先 fallback 到旧的单帧 rearm，不硬跑。
- 当前 `DMA_SG_RX_BD_COUNT=8` 时，低 RBW 仍会用多轮有限 burst 累积一个点；这一步先解决 packet 边界和 DMA 错误，不承诺立刻把 10K/1K 速度提到最终状态。
- 扩大到 `128` 或 `1024` BD 后，再逐步把更多低 RBW 数据合并成一次大 burst，减少 rearm 次数。

预计每点原始块数：

| RBW | 约需 4096-sample block | 原始数据量 |
| --- | ---: | ---: |
| 1M | 1 | 8 KB |
| 300K | 7 | 56 KB |
| 100K | 19 | 152 KB |
| 30K | 72 | 576 KB |
| 10K | 982 | 7.7 MB |
| 1K | 384 | 3.0 MB |

## 4. Vivado BD 操作步骤

以下操作在 PL RTL 修改后进行。

### 4.1 刷新模块端口

1. 打开 Vivado 工程：`C:\learning\pusu_V2\code\pusu_20260608`。
2. 打开 Block Design：`system.bd`。
3. 确认 `adc_capture_axis.v` 和 `adc_capture_control_axi.v` 已在 Design Sources。
4. 如果 Vivado 提示 module reference 已变化，选择更新。
5. 如果没有提示但 BD 里看不到新端口，右键 `adc_capture_axis_0` 和 `adc_capture_control_0`，执行类似 `Refresh Module Reference` / `Update Module Reference` 的操作。
6. 如果仍不出现新端口，删除这两个 module reference 后用 `Add Module` 重新加入，但保留原连接作为参考重新接线。

### 4.2 保持现有数据通路不变

保留：

```text
LTC2208_0/adc_data       -> adc_capture_axis_0/adc_sample
LTC2208_0/adc_of         -> adc_capture_axis_0/adc_overflow
adc_capture_axis_0/M_AXIS -> axis_data_fifo_0/S_AXIS
axis_data_fifo_0/M_AXIS   -> axi_dma_0/S_AXIS_S2MM
axi_dma_0/M_AXI_S2MM      -> axi_mem_intercon/S00_AXI
axi_dma_0/M_AXI_SG        -> axi_mem_intercon/S01_AXI
axi_mem_intercon/M00_AXI  -> processing_system7_0/S_AXI_HP0
```

这部分现在已经正确，不要重连成普通 pin，也不要把 SG 接到 GP0。

### 4.3 连接新增 burst 控制端口

新增连接：

| 源 | 目标 |
| --- | --- |
| `adc_capture_control_0/capture_frame_count[31:0]` | `adc_capture_axis_0/ctrl_frame_count[31:0]` |

新增状态回读：

| 源 | 目标 |
| --- | --- |
| `adc_capture_axis_0/status_burst_active` | `adc_capture_control_0/status_burst_active` |
| `adc_capture_axis_0/status_burst_done` | `adc_capture_control_0/status_burst_done` |
| `adc_capture_axis_0/status_burst_packet_count[31:0]` | `adc_capture_control_0/status_burst_packet_count[31:0]` |
| `adc_capture_axis_0/status_burst_remaining[31:0]` | `adc_capture_control_0/status_burst_remaining[31:0]` |

### 4.4 保持 AXI-Lite 控制连接

保留：

```text
processing_system7_0/M_AXI_GP0
  -> ps7_0_axi_periph/S00_AXI
  -> ps7_0_axi_periph/M05_AXI
  -> adc_capture_control_0/S_AXI
```

`ps7_0_axi_periph` 分多个 M_AXI 端口是正常的。它只是把 PS 的 GP0 控制总线分发给 DMA、GPIO、capture control 等多个 AXI-Lite 从设备，不会影响 DMA 数据搬运。真正的数据搬运走 HP0，不走 GP0。

### 4.5 保持 FIFO reset 连接

当前 BD 已经把：

```text
adc_capture_control_0/fifo_resetn -> util_vector_logic_1/Op2
util_vector_logic_1/Res           -> axis_data_fifo_0/s_axis_aresetn
```

这条线保留。它用于 PS 可控清 FIFO。若重新加模块时断开，需要重新接回。

### 4.6 检查时钟和复位

保持 ADC 输入侧：

```text
LTC2208_0/adc_clk -> adc_capture_axis_0/adc_clk
LTC2208_0/adc_clk -> axis_data_fifo_0/s_axis_aclk
LTC2208_0/adc_clk -> adc_capture_control_0/adc_clk
```

保持 PS/DMA 侧：

```text
processing_system7_0/FCLK_CLK0 -> axis_data_fifo_0/m_axis_aclk
processing_system7_0/FCLK_CLK0 -> axi_dma_0/s_axis_s2mm_aclk
processing_system7_0/FCLK_CLK0 -> axi_dma_0/m_axi_s2mm_aclk
processing_system7_0/FCLK_CLK0 -> axi_dma_0/m_axi_sg_aclk
processing_system7_0/FCLK_CLK0 -> adc_capture_control_0/s_axi_aclk
```

注意：`axis_data_fifo_0/S_AXIS` 和 `adc_capture_axis_0/M_AXIS` 必须同属 ADC clock domain；`axis_data_fifo_0/M_AXIS` 和 DMA 必须同属 PS FCLK domain。

### 4.7 检查 FIFO 和 DMA 参数

`axis_data_fifo_0`：

- FIFO depth 保持或提升到 `16384 words`。
- TDATA 宽度保持 16 bit。
- TLAST 必须启用。
- 如当前工程启用了 TUSER，则保持 1 bit TUSER。

`axi_dma_0`：

- Scatter Gather 必须启用。
- S2MM channel 必须启用。
- `M_AXI_SG` 接到 `axi_mem_intercon/S01_AXI`。
- `M_AXI_S2MM` 接到 `axi_mem_intercon/S00_AXI`。
- `s2mm_introut` 接到 `xlconcat_0/In0`。

### 4.8 Address Editor 和导出

1. 运行 `Validate Design`。
2. 打开 `Address Editor`。
3. 确认 `adc_capture_control_0/S_AXI` 有地址段，例如 `SEG_adc_capture_control_0_reg0`。
4. 确认 `axi_dma_0/M_AXI_S2MM` 和 `axi_dma_0/M_AXI_SG` 都映射到 `processing_system7_0/S_AXI_HP0` 的 DDR 地址空间。
5. `Generate Output Products`。
6. 重新综合、实现、生成 bitstream。
7. `File -> Export -> Export Hardware`，勾选 `Include bitstream`。
8. 回到 Vitis 更新 platform/BSP。
9. 检查 `xparameters.h` 中有 capture control baseaddr 宏。

## 5. 验收标准

PL/PS 单独验收：

- `main 4096` 正常。
- 旧 `sgring` smoke 仍正常。
- 新 `sgburst 1/7/19/72` 正常。
- 扩大 ring 后 `sgburst 384/982` 正常。

健康签名：

```text
result_code = 0
dma_error = 0
timed_out = 0
completed_bd_count == bd_count
completed_bytes == samples_per_bd * bd_count * 2
packet_count >= bd_count
burst_packet_count == bd_count
overflow_count = 0
backpressure_count = 0
last_irq_status 包含 IOC，不包含 error
```

进入 sweep 前必须满足：

- 新 burst smoke 在 72 blocks 以内稳定。
- 扩大 BD ring 后 384/982 blocks 至少各跑 3 次稳定。
- 失败时能区分是 PL status error、DMA error、timeout 还是 counter mismatch。

## 6. 主要风险

- `ST_BURST` 的 TLAST 计数如果按 clock 而不是按 `tvalid && tready` 计，会再次破坏 packet 边界。
- BD ring 和 RX buffer 如果还按 8 BD / 128 KB 设计，10K 这种低 RBW 无法一次 burst。
- 如果 PS 在 DMA 未完全 armed 前启动 PL，仍可能丢第一个 packet。
- 如果 AXI FIFO 复位和 PL burst start 间隔太短，可能读到旧 FIFO 残留，PS 需要保留 `pl_capture_reset_fifo()`。
- 这套方案解决的是原始数据连续性和 DMA packet 一致性，不直接解决幅度校准，也不解决宽 span 低 RBW 的扫频策略问题。
