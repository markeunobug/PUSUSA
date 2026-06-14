# PL DSP Block Design 接入步骤

日期：2026-06-04

工程路径：

`C:\learning\pusu_V2\code\pusu_20260604`

新增 RTL 文件：

`C:\learning\pusu_V2\code\pusu_20260604\pusu_test.srcs\sources_1\new\pusu_pl_dsp_core.v`

## 1. 目标

把第一版 PL DSP 调试核插入到 `LTC2208_0` 和 `axi_dma_0` 之间。

当前版本的 `pusu_pl_dsp_core` 用于验证 PL 端连续 DDC / 抽取链路：

```text
LTC2208 ADC 16-bit @ 130 MSPS
-> 固定 40 MHz DDC
-> 连续 /130 抽取
-> 1 MSPS packed IQ 输出
-> AXI DMA
-> PS DDR
```

输出数据格式为 32-bit packed IQ：

```text
m_axis_tdata[31:16] = signed I16
m_axis_tdata[15:0]  = signed Q16
```

默认每包为 `4096` 个 complex sample，与 Vitis 侧现有 `FFT_SIZE=4096` 对齐。因此一帧 DMA 数据长度为：

```text
4096 complex samples * 4 bytes = 16384 bytes
```

注意：这版只是 DDC / 连续性验证核，不是最终可信 RBW 实现。后续还需要把简单抽取替换为正式多级 FIR，并加入 PL 端 RBW FIR / power accumulator。

## 2. 打开 Vivado 工程

打开：

```text
C:\learning\pusu_V2\code\pusu_20260604\pusu_test.xpr
```

然后打开 Block Design：

```text
pusu_test.srcs/sources_1/bd/system/system.bd
```

## 3. 确认 RTL 文件已加入工程

确认 `pusu_pl_dsp_core.v` 已经出现在 Sources 中。

如果 Vivado 没有自动刷新，手动添加：

```text
Add Sources
-> Add or create design sources
-> Add Files
-> C:\learning\pusu_V2\code\pusu_20260604\pusu_test.srcs\sources_1\new\pusu_pl_dsp_core.v
```

## 4. 添加 `pusu_pl_dsp_core` 模块

在 Block Design 空白处右键：

```text
Add Module
-> pusu_pl_dsp_core
```

建议实例名：

```text
pusu_pl_dsp_core_0
```

如果 Vivado 没有自动识别 AXI-Stream 接口，也没关系；按普通信号逐个连接即可。

## 5. 时钟和复位连接

`pusu_pl_dsp_core_0` 必须和 ADC stream 处在同一个时钟域。

连接：

```text
pusu_pl_dsp_core_0/aclk
    <- LTC2208_0/m_axis_aclk
```

复位连接：

```text
pusu_pl_dsp_core_0/aresetn
    <- 与 axis_data_fifo_0/s_axis_aresetn 相同的 active-low reset
```

如果 BD 中使用 `proc_sys_reset_0`，优先使用同一时钟域下的 active-low peripheral reset。

## 6. 断开旧 ADC 到 DMA 的直连路径

当前旧路径大致是：

```text
LTC2208_0/m_axis
-> axis_data_fifo_0/S_AXIS
-> axis_data_fifo_0/M_AXIS
-> axi_dma_0/S_AXIS_S2MM
```

需要把 `LTC2208_0/m_axis` 到 `axis_data_fifo_0/S_AXIS` 的原连接断开。

新路径改为：

```text
LTC2208_0/m_axis
-> pusu_pl_dsp_core_0/s_axis
-> axis_data_fifo_0/S_AXIS
-> axis_data_fifo_0/M_AXIS
-> axi_dma_0/S_AXIS_S2MM
```

## 7. AXI-Stream 输入连接

把 `LTC2208_0` 的 ADC stream 接到 `pusu_pl_dsp_core_0` 输入。

逐个连接：

```text
LTC2208_0/m_axis_tdata
    -> pusu_pl_dsp_core_0/s_axis_tdata

LTC2208_0/m_axis_tvalid
    -> pusu_pl_dsp_core_0/s_axis_tvalid

pusu_pl_dsp_core_0/s_axis_tready
    -> LTC2208_0/m_axis_tready

LTC2208_0/m_axis_tlast
    -> pusu_pl_dsp_core_0/s_axis_tlast

LTC2208_0/m_axis_tuser
    -> pusu_pl_dsp_core_0/s_axis_tuser
```

## 8. AXI-Stream 输出连接

把 `pusu_pl_dsp_core_0` 输出接到 FIFO，再接到 DMA。

推荐第一版连接：

```text
pusu_pl_dsp_core_0/m_axis_tdata
    -> axis_data_fifo_0/s_axis_tdata

pusu_pl_dsp_core_0/m_axis_tvalid
    -> axis_data_fifo_0/s_axis_tvalid

axis_data_fifo_0/s_axis_tready
    -> pusu_pl_dsp_core_0/m_axis_tready

pusu_pl_dsp_core_0/m_axis_tlast
    -> axis_data_fifo_0/s_axis_tlast

pusu_pl_dsp_core_0/m_axis_tuser
    -> axis_data_fifo_0/s_axis_tuser
```

然后保持：

```text
axis_data_fifo_0/M_AXIS
-> axi_dma_0/S_AXIS_S2MM
```

## 9. 必须修改 AXIS 数据宽度

这是最容易漏掉的一步。

旧路径是 16-bit ADC 原始数据：

```text
TDATA width = 16 bit
```

新 PL DSP 输出是 32-bit packed IQ：

```text
TDATA width = 32 bit
```

所以需要把以下模块的 AXI-Stream 数据宽度改成 32-bit：

```text
axis_data_fifo_0 S_AXIS / M_AXIS
axi_dma_0 S_AXIS_S2MM
```

如果原 `axis_data_fifo_0` 不方便直接改，可以新增一个 32-bit AXIS Data FIFO，专门放在：

```text
pusu_pl_dsp_core_0
-> 新 32-bit axis_data_fifo
-> axi_dma_0
```

固件端如果启用：

```c
#define PL_DSP_DEBUG_IQ_PATH 1
```

则 BD 中 DMA S2MM 输入必须是 32-bit packed IQ。否则 PS 会按错误格式解析数据。

## 10. 控制脚连接

第一版先不做 AXI-Lite 配置寄存器，控制脚直接用常量绑定。

添加两个 `xlconstant`：

```text
enable       = 1'b1
clear_status = 1'b0
```

连接：

```text
xlconstant_1bit_1/dout
    -> pusu_pl_dsp_core_0/enable

xlconstant_1bit_0/dout
    -> pusu_pl_dsp_core_0/clear_status
```

后续如果要做可切换模式，再把这些控制信号接到 AXI GPIO 或自定义 AXI-Lite 寄存器。

## 11. ILA 观测点

建议第一版至少抓这些信号：

```text
dbg_input_sample_count
dbg_output_sample_count
dbg_output_drop_count
dbg_last_i
dbg_last_q
dbg_nco_phase
dbg_decim_count
m_axis_tdata
m_axis_tvalid
m_axis_tready
m_axis_tlast
```

这些观测点用于确认：

- ADC 输入样本是否持续进入 PL DSP。
- `/130` 抽取是否正常。
- 输出速率是否约为 1 MSPS。
- DMA / FIFO 是否造成输出丢样。
- 40 MHz DDC 后的 I/Q 是否正常。

## 12. 预期硬件行为

ADC 采样率为 130 MHz 时：

```text
每输入 130 个 ADC 样本，输出 1 个 complex IQ 样本
```

因此：

```text
dbg_output_sample_count ~= dbg_input_sample_count / 130
```

如果 FIFO / DMA 能正常接收数据：

```text
dbg_output_drop_count 应保持为 0
```

输出速率：

```text
130 MSPS / 130 = 1 MSPS
```

## 13. 频率验证预期

输入 1 GHz RF，改变 sweep center，使二中频 IF2 落在不同位置。

| IF2 频率 | PL DDC 后预期 |
|---:|---|
| 40.000 MHz | 接近 DC |
| 40.100 MHz | 接近 +100 kHz |
| 39.900 MHz | 接近 -100 kHz |

第一轮验证重点不是幅度绝对值，而是频率映射和连续性。

## 14. Vivado 生成步骤

完成连接后依次执行：

```text
Validate Design
Generate Output Products
Run Synthesis
Run Implementation
Generate Bitstream
Export Hardware, include bitstream
```

然后在 Vitis 中更新 platform / hardware specification，再重新编译应用。

## 15. Vitis 配合

Vitis 端已经预留开关，默认关闭：

```c
#define PL_DSP_DEBUG_IQ_PATH 0
```

当 Vivado 侧已经改成 32-bit packed IQ 输出，并成功生成 bitstream 后，再改成：

```c
#define PL_DSP_DEBUG_IQ_PATH 1
```

此时固件会把 DMA buffer 解释为：

```text
word[31:16] = I
word[15:0]  = Q
```

并跳过旧 PS DDC，把 PL 输出的 1 MSPS IQ 送入现有后级 RBW / power 诊断路径。

## 16. 注意事项

1. 不要把这版当作最终 RBW 滤波器。

   当前 `pusu_pl_dsp_core` 使用简单连续累加抽取，目的是快速验证 PL 端连续链路和 40 MHz DDC。正式版本还需要多级 FIR 抽取和 ENBW 校准。

2. 必须确认 AXI DMA S2MM 是 32-bit stream。

   如果 DMA 仍是 16-bit，Vitis 打开 `PL_DSP_DEBUG_IQ_PATH=1` 后一定会解析错误。

3. 先用 ILA 看计数器。

   `dbg_input_sample_count`、`dbg_output_sample_count`、`dbg_output_drop_count` 比一上来追幅度更重要。

4. 如果输出丢样，先查 FIFO / DMA backpressure。

   `dbg_output_drop_count` 非 0 说明 PL DSP 产生了输出，但下游没有及时接收。

5. 第一轮只验证 10 kHz RBW 问题相关场景。

   重点测试 40.000 MHz 和 40.100 MHz IF2，不要一开始扩展到所有 RBW。

