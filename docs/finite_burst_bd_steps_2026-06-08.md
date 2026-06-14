# 有限 Burst 端口 BD 连接步骤

日期：2026-06-08

工程：`C:\learning\pusu_V2\code\pusu_20260608`

目的：把新增的 `FRAME_COUNT` 有限 burst 控制信号接入现有 `adc_capture_axis_0` 和 `adc_capture_control_0`。本次不改 DMA/HP0/AXI-Lite 主链路，只刷新两个 module reference 并连接新增普通端口。

## 1. 刷新 RTL 模块

1. 打开 Vivado 工程。
2. 打开 `system.bd`。
3. 确认 Design Sources 中已有：

```text
pusu_test.srcs/sources_1/new/adc_capture_axis.v
pusu_test.srcs/sources_1/new/adc_capture_control_axi.v
```

4. 如果 Vivado 提示 module reference 变化，选择更新。
5. 如果没有提示但端口没出现，右键：

```text
adc_capture_axis_0
adc_capture_control_0
```

执行 `Refresh Module Reference` / `Update Module Reference`。

6. 如果仍然不刷新，删除这两个 module reference 后重新 `Add Module`，然后按现有连接重新接回。

## 2. 新增端口连接

只新增以下 5 组普通信号连接：

| 源 | 目标 |
| --- | --- |
| `adc_capture_control_0/capture_frame_count[31:0]` | `adc_capture_axis_0/ctrl_frame_count[31:0]` |
| `adc_capture_axis_0/status_burst_active` | `adc_capture_control_0/status_burst_active` |
| `adc_capture_axis_0/status_burst_done` | `adc_capture_control_0/status_burst_done` |
| `adc_capture_axis_0/status_burst_packet_count[31:0]` | `adc_capture_control_0/status_burst_packet_count[31:0]` |
| `adc_capture_axis_0/status_burst_remaining[31:0]` | `adc_capture_control_0/status_burst_remaining[31:0]` |

不要新增 `burst_mode` 线。本版语义是：

```text
FRAME_COUNT = 0：旧无限 stream smoke
FRAME_COUNT > 0：start 脉冲触发有限 burst
```

## 3. 保持现有连接不变

数据通路保持：

```text
LTC2208_0/adc_data        -> adc_capture_axis_0/adc_sample
LTC2208_0/adc_of          -> adc_capture_axis_0/adc_overflow
adc_capture_axis_0/M_AXIS -> axis_data_fifo_0/S_AXIS
axis_data_fifo_0/M_AXIS   -> axi_dma_0/S_AXIS_S2MM
axi_dma_0/M_AXI_S2MM      -> axi_mem_intercon/S00_AXI
axi_dma_0/M_AXI_SG        -> axi_mem_intercon/S01_AXI
axi_mem_intercon/M00_AXI  -> processing_system7_0/S_AXI_HP0
```

控制通路保持：

```text
processing_system7_0/M_AXI_GP0
  -> ps7_0_axi_periph/S00_AXI
  -> ps7_0_axi_periph/M05_AXI
  -> adc_capture_control_0/S_AXI
```

FIFO reset 保持：

```text
adc_capture_control_0/fifo_resetn -> util_vector_logic_1/Op2
util_vector_logic_1/Res           -> axis_data_fifo_0/s_axis_aresetn
```

时钟保持：

```text
LTC2208_0/adc_clk -> adc_capture_axis_0/adc_clk
LTC2208_0/adc_clk -> adc_capture_control_0/adc_clk
LTC2208_0/adc_clk -> axis_data_fifo_0/s_axis_aclk

processing_system7_0/FCLK_CLK0 -> adc_capture_control_0/s_axi_aclk
processing_system7_0/FCLK_CLK0 -> axis_data_fifo_0/m_axis_aclk
processing_system7_0/FCLK_CLK0 -> axi_dma_0/s_axis_s2mm_aclk
processing_system7_0/FCLK_CLK0 -> axi_dma_0/m_axi_s2mm_aclk
processing_system7_0/FCLK_CLK0 -> axi_dma_0/m_axi_sg_aclk
```

## 4. Validate 和导出

1. 运行 `Validate Design`。
2. 修复所有 unconnected port 或 clock domain warning。
3. `Generate Output Products`。
4. 重新综合、实现、生成 bitstream。
5. `File -> Export -> Export Hardware`，勾选 `Include bitstream`。
6. 回到 Vitis 更新 platform/BSP。
7. 重新 build/burn 当前 ELF。

PS 端已经按新寄存器编译。烧入后先不要测 sweep SG，先测：

```powershell
python C:\learning\pusu_V2\tools\capture_stream_smoke_test.py --port COM7 --baud 921600 --mode sgburst --samples-per-bd 4096 --bd-count 1 --timeout 5
python C:\learning\pusu_V2\tools\capture_stream_smoke_test.py --port COM7 --baud 921600 --mode sgburst --samples-per-bd 4096 --bd-count 8 --timeout 5
```

