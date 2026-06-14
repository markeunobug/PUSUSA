# adc_capture_axis 与 AXI-Lite 控制 wrapper 的 BD 操作说明

日期：2026-06-07

范围：`code/pusu_20260516` 的第一阶段受控 ADC 采集逻辑。

本说明用于在 Vivado Block Design 中插入两个 RTL 模块：

- `adc_capture_axis.v`：放在 `LTC2208_0` 和 `axis_data_fifo_0` 之间，负责按帧输出 ADC 数据。
- `adc_capture_control_axi.v`：AXI-Lite 控制寄存器 wrapper，负责 PS 端配置、启动、停止和状态回读。

不要手动编辑 Vivado 自动生成的 `.bd` 文件。

## 0. 为什么不是直接拖一个 AXI 控制器 IP

这里的控制器不是 Xilinx 现成的 `AXI GPIO` 或普通寄存器 IP，而是我们自己写的 AXI4-Lite slave：

```text
PS M_AXI_GP0
  -> AXI interconnect
    -> adc_capture_control_0/S_AXI
      -> adc_capture_axis_0 控制/状态信号
```

也就是说，它仍然是在 BD 中连接 AXI 总线，只是这个 AXI-Lite 从设备由
`adc_capture_control_axi.v` 实现，而不是从 IP Catalog 里拖一个现成 IP。

这样做的原因是：

1. `start/abort/clear_status` 需要变成 ADC 时钟域下的单周期控制脉冲。
2. `frame_len/frame_id` 需要在启动采集时锁存，避免采集中途被 PS 改写影响当前帧。
3. `busy/done/error/sample_count/frame_id/error_code` 需要从 ADC 时钟域回读到 PS 时钟域。
4. 这些 CDC 和状态语义用 `AXI GPIO` 能绕出来，但逻辑分散，后面更难确认数据一致性。

推荐当前阶段用 **Add Module** 加入 RTL。Vivado 会根据 `adc_capture_control_axi.v`
里的 `X_INTERFACE_INFO` 属性识别出 `S_AXI` 接口，然后可以像普通 AXI 从设备一样
用 Connection Automation 连接。

如果 Vivado 没有自动识别 `S_AXI`，再走 **Package IP** 方式，把
`adc_capture_control_axi.v` 打包成一个 AXI4-Lite peripheral，然后从 IP Catalog
拖进 BD。两种方式的功能相同，区别只是 BD 操作入口不同。

## 1. 目标数据路径

插入后，数据路径应该变成：

```text
LTC2208_0
  adc_data[15:0] / adc_of / adc_clk
    -> adc_capture_axis_0
       M_AXIS
         -> axis_data_fifo_0/S_AXIS
            -> axis_data_fifo_0/M_AXIS
               -> axi_dma_0/S_AXIS_S2MM
```

控制路径应该变成：

```text
processing_system7_0/M_AXI_GP0
  -> ps7_0_axi_periph
    -> adc_capture_control_0/S_AXI
       capture_start / capture_abort / capture_clear_status
       capture_frame_len / capture_frame_id
         -> adc_capture_axis_0
```

## 2. 加入 RTL 源文件

在 Vivado 工程中确认以下文件已经在 Design Sources 里：

```text
pusu_test.srcs/sources_1/new/adc_capture_axis.v
pusu_test.srcs/sources_1/new/adc_capture_control_axi.v
```

如果还没有：

1. 打开 Vivado 工程。
2. 点击 **Add Sources**。
3. 选择 **Add or create design sources**。
4. 添加上面两个 `.v` 文件。
5. 勾选 **Copy sources into project** 可以不勾，保持使用当前工程目录下的文件即可。

## 3. 在 BD 中加入两个模块

打开 Block Design：

1. 右键空白处，选择 **Add Module**。
2. 选择 `adc_capture_axis`。
3. 将实例命名为 `adc_capture_axis_0`。
4. 参数 `MAX_FRAME_LEN` 保持 `16384`。
5. 再次右键空白处，选择 **Add Module**。
6. 选择 `adc_capture_control_axi`。
7. 将实例命名为 `adc_capture_control_0`。

如果 `adc_capture_control_axi` 没有出现在 Add Module 列表里，先确认该文件已经
在 Design Sources 中，并且没有 Verilog 语法错误。

## 4. 断开原来的自由流 ADC 数据路径

断开原先的直接 AXI4-Stream 连接：

```text
LTC2208_0/M_AXIS -> axis_data_fifo_0/S_AXIS
```

保留 `LTC2208_0` 的原始调试输出：

```text
LTC2208_0/adc_data
LTC2208_0/adc_of
LTC2208_0/adc_clk
```

这些信号后面要接入 `adc_capture_axis_0`。

## 5. 连接 ADC 输入到采集控制层

连接如下信号：

| 源信号 | 目标信号 |
| --- | --- |
| `LTC2208_0/adc_clk` | `adc_capture_axis_0/adc_clk` |
| ADC 时钟域低有效复位 | `adc_capture_axis_0/rst_n` |
| `LTC2208_0/adc_data[15:0]` | `adc_capture_axis_0/adc_sample[15:0]` |
| `LTC2208_0/adc_of` | `adc_capture_axis_0/adc_overflow` |

`adc_capture_axis_0/rst_n` 使用和 `LTC2208_0/rst_n` 同源的低有效复位。
如果复位来自其他时钟域，至少要保证释放复位时对 `adc_clk` 安全。

## 6. 连接新的 AXI4-Stream 数据路径

将 `adc_capture_axis_0` 接到 FIFO 的输入侧：

| 源信号 | 目标信号 |
| --- | --- |
| `adc_capture_axis_0/m_axis_tdata[15:0]` | `axis_data_fifo_0/s_axis_tdata[15:0]` |
| `adc_capture_axis_0/m_axis_tvalid` | `axis_data_fifo_0/s_axis_tvalid` |
| `axis_data_fifo_0/s_axis_tready` | `adc_capture_axis_0/m_axis_tready` |
| `adc_capture_axis_0/m_axis_tlast` | `axis_data_fifo_0/s_axis_tlast` |
| `adc_capture_axis_0/m_axis_tuser` | `axis_data_fifo_0/s_axis_tuser` |

如果 `axis_data_fifo_0` 当前没有启用 `TUSER`，在 FIFO 配置里打开 1 bit TUSER。
这里用 `TUSER` 携带 ADC overflow 标记。

下游连接保持不变：

```text
axis_data_fifo_0/M_AXIS -> axi_dma_0/S_AXIS_S2MM
```

## 7. FIFO 深度设置

打开 `axis_data_fifo_0` 的配置，将 FIFO depth 从 `1024` 改为：

```text
16384 words
```

当前 stream 是 16 bit，因此 `16384 words` 对应 `32768 bytes`，刚好覆盖一帧
`16384 samples` 的第一阶段测试窗口。

如果后续要做更大帧长，可以继续增大 FIFO；第一阶段先用 `16384`，便于定位。

## 8. 保持异步 FIFO 时钟分界

不要把 DMA 的 S2MM 时钟改到 ADC 时钟域。

保持如下连接：

| 源信号 | 目标信号 |
| --- | --- |
| `LTC2208_0/adc_clk` | `axis_data_fifo_0/s_axis_aclk` |
| `processing_system7_0/FCLK_CLK0` | `axis_data_fifo_0/m_axis_aclk` |
| `processing_system7_0/FCLK_CLK0` | `axi_dma_0/s_axis_s2mm_aclk` |
| `processing_system7_0/FCLK_CLK0` | `axi_dma_0/m_axi_s2mm_aclk` |

也就是：

```text
ADC clock domain -> FIFO S_AXIS
PS FCLK domain   -> FIFO M_AXIS -> DMA S2MM
```

这个分界不要改。

同时为 ADC 时钟域单独使用一个 reset 同步器：

```text
proc_sys_reset_adc_0/slowest_sync_clk  <- LTC2208_0/adc_clk
proc_sys_reset_adc_0/ext_reset_in      <- processing_system7_0/FCLK_RESET0_N
proc_sys_reset_adc_0/peripheral_aresetn
  -> LTC2208_0/rst_n
  -> adc_capture_axis_0/rst_n
  -> adc_capture_control_0/adc_rst_n
  -> axis_data_fifo_0/s_axis_aresetn
```

`proc_sys_reset_0/peripheral_aresetn` 仍然只用于 PS FCLK 域的 AXI-Lite、
DMA、AXI interconnect 和 GPIO 等模块。

## 9. 连接 AXI-Lite 控制 wrapper

先连接 wrapper 的时钟和复位：

| 源信号 | 目标信号 |
| --- | --- |
| `processing_system7_0/FCLK_CLK0` | `adc_capture_control_0/s_axi_aclk` |
| `proc_sys_reset_0/peripheral_aresetn` | `adc_capture_control_0/s_axi_aresetn` |
| `LTC2208_0/adc_clk` | `adc_capture_control_0/adc_clk` |
| `proc_sys_reset_adc_0/peripheral_aresetn` | `adc_capture_control_0/adc_rst_n` |

再连接 AXI-Lite：

1. 选中 `adc_capture_control_0/S_AXI`。
2. 点击 **Run Connection Automation**。
3. Master 选择 `processing_system7_0/M_AXI_GP0`。
4. Interconnect 选择现有 `ps7_0_axi_periph`，没有的话让 Vivado 自动添加。
5. 完成后检查 `S_AXI` 是否已经接入 AXI interconnect。
6. 打开 **Address Editor**。
7. 给 `adc_capture_control_0/S_AXI` 分配一个地址段。

如果 `adc_capture_control_0` 没有显示整体的 `S_AXI` 接口，而是散开的
`s_axi_awaddr/s_axi_wdata/...` 引脚，说明 Vivado 没有成功识别接口。此时有两个选择：

1. 检查 RTL 文件是否包含 `X_INTERFACE_INFO` 属性并重新打开 BD。
2. 将 `adc_capture_control_axi.v` package 成自定义 AXI4-Lite IP，再从 IP Catalog 拖入 BD。

## 10. 连接 wrapper 与采集模块

控制信号从 wrapper 接到 capture：

| 源信号 | 目标信号 |
| --- | --- |
| `adc_capture_control_0/capture_start` | `adc_capture_axis_0/ctrl_start` |
| `adc_capture_control_0/capture_abort` | `adc_capture_axis_0/ctrl_abort` |
| `adc_capture_control_0/capture_clear_status` | `adc_capture_axis_0/ctrl_clear_status` |
| `adc_capture_control_0/capture_frame_len[15:0]` | `adc_capture_axis_0/ctrl_frame_len[15:0]` |
| `adc_capture_control_0/capture_frame_id[31:0]` | `adc_capture_axis_0/ctrl_frame_id[31:0]` |

状态信号从 capture 接回 wrapper：

| 源信号 | 目标信号 |
| --- | --- |
| `adc_capture_axis_0/status_busy` | `adc_capture_control_0/status_busy` |
| `adc_capture_axis_0/status_done` | `adc_capture_control_0/status_done` |
| `adc_capture_axis_0/status_error` | `adc_capture_control_0/status_error` |
| `adc_capture_axis_0/status_overflow_seen` | `adc_capture_control_0/status_overflow_seen` |
| `adc_capture_axis_0/status_backpressure_seen` | `adc_capture_control_0/status_backpressure_seen` |
| `adc_capture_axis_0/status_tlast_seen` | `adc_capture_control_0/status_tlast_seen` |
| `adc_capture_axis_0/status_sample_count[15:0]` | `adc_capture_control_0/status_sample_count[15:0]` |
| `adc_capture_axis_0/status_frame_id[31:0]` | `adc_capture_control_0/status_frame_id[31:0]` |
| `adc_capture_axis_0/status_error_code[7:0]` | `adc_capture_control_0/status_error_code[7:0]` |

## 11. 生成硬件并同步到 Vitis

BD 连接完成后：

1. 点击 **Validate Design**。
2. 修复所有连接错误。
3. 右键 BD，选择 **Generate Output Products**。
4. 运行综合、实现、生成 bitstream。
5. 选择 **File -> Export -> Export Hardware**。
6. 勾选 **Include bitstream**。
7. 回到 Vitis，刷新 platform / BSP。

导出后，Vitis 的 `xparameters.h` 里应该出现类似宏：

```c
XPAR_ADC_CAPTURE_CONTROL_0_S_AXI_BASEADDR
```

PS 端的 `pl_capture_control.c/.h` 已经按这个寄存器表写好，并且会尝试识别几种常见
base address 宏名。如果 Vivado 生成的宏名不同，可以在包含 `pl_capture_control.h`
之前手动定义：

```c
#define PL_CAPTURE_CONTROL_BASEADDR <你的AXI-Lite基地址>
```

## 12. 第一阶段联调顺序

PS 端建议按下面顺序操作：

```text
1. pl_capture_abort()
2. pl_capture_clear_status()
3. pl_capture_configure(frame_len, frame_id)
4. 先启动 AXI DMA S2MM，长度为 frame_len * 2 bytes
5. pl_capture_start()
6. 等 DMA IOC
7. 读取 adc_capture_control_0 状态寄存器
8. 只有全部满足时才接受这一帧：
   error == 0
   overflow_seen == 0
   backpressure_seen == 0
   tlast_seen == 1
   sample_count == frame_len
   done_frame_id == frame_id
```

第一轮先测：

```text
frame_len = 4096
```

稳定后再测：

```text
frame_len = 16384
```

如果 `backpressure_seen == 1`，说明 FIFO/DMA 侧没有持续接住数据，该帧丢弃。
如果 `sample_count != frame_len`，说明帧不完整，该帧也丢弃。
