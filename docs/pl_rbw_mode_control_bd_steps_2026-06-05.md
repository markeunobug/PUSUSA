# PL RBW Mode Control BD 接线步骤

更新日期：2026-06-05

## 1. 本次 RTL 修改

已修改：

```text
code/pusu_20260604/pusu_test.srcs/sources_1/new/pusu_pl_dsp_core.v
```

已新增：

```text
code/pusu_20260604/pusu_test.srcs/sources_1/new/pusu_pl_dsp_axi_regs.v
```

当前实现范围：

- PS 可通过 AXI-Lite 写 RBW mode。
- PL 根据 mode 输出不同抽取率的 debug IQ。
- PL 可读回 `sample_rate_hz`、`decimation_ratio`、`status_word`、计数器和版本。
- 当前 decimator 仍是 accumulator bring-up 实现，不是最终 FIR/polyphase decimator。

RBW mode 编号：

| value | mode | sample rate | decimation |
| ---: | --- | ---: | ---: |
| 0 | 1M | 10 MSPS | 13 |
| 1 | 300K | 3.25 MSPS | 40 |
| 2 | 100K | 1 MSPS | 130 |
| 3 | 30K | 325 kSPS | 400 |
| 4 | 10K | 100 kSPS | 1300 |
| 5 | 1K | 100 kSPS | 1300 |

## 2. Vivado 工程源文件操作

1. 在 Vivado 中执行 `Add Sources`。
2. 加入：

```text
C:\learning\pusu_V2\code\pusu_20260604\pusu_test.srcs\sources_1\new\pusu_pl_dsp_axi_regs.v
```

3. 右键 block design，执行 `Refresh Changed Modules` 或重新打开 BD，让 `pusu_pl_dsp_core_0` 识别新端口。

## 3. BD 中新增模块

在 Block Design 中添加 RTL module：

```text
pusu_pl_dsp_axi_regs
```

建议实例名：

```text
pusu_pl_dsp_axi_regs_0
```

## 4. 时钟和复位

### 4.1 关键原则

`pusu_pl_dsp_axi_regs_0` 和 `pusu_pl_dsp_core_0` 的控制/status 信号直接相连，因此必须处在同一个时钟域。

推荐：

```text
pusu_pl_dsp_axi_regs_0/s_axi_aclk  -> pusu_pl_dsp_core_0/aclk
pusu_pl_dsp_axi_regs_0/s_axi_aresetn -> 与 pusu_pl_dsp_core_0/aresetn 同源
```

如果 PS `M_AXI_GP0` / AXI interconnect 使用的是 `FCLK_CLK0`，而 `pusu_pl_dsp_core_0/aclk` 是 ADC/AXIS clock，则必须加：

```text
AXI Clock Converter
```

连接方式：

```text
PS M_AXI_GP0 / interconnect clock domain
  -> AXI Clock Converter
  -> pusu_pl_dsp_axi_regs_0/S_AXI, clock = pusu_pl_dsp_core_0/aclk
```

不要把 `pusu_pl_dsp_axi_regs_0` 放在 FCLK 域、再直接把寄存器输出接到 ADC clock 域的 DSP core；这会造成 CDC 风险。

### 4.2 ADC/AXIS 时钟域复位

如果 `pusu_pl_dsp_core_0/aclk`、`axis_data_fifo_0/s_axis_aclk` 使用的是
`LTC2208_0/m_axis_aclk`，则这些端口的复位也必须同步到
`LTC2208_0/m_axis_aclk`。不要直接使用同步到 `processing_system7_0/FCLK_CLK0`
的 `proc_sys_reset_0/peripheral_aresetn`。

建议新增一个专用复位模块，例如：

```text
proc_sys_reset_adc
```

连接方式：

```text
proc_sys_reset_adc/slowest_sync_clk -> LTC2208_0/m_axis_aclk
proc_sys_reset_adc/ext_reset_in     -> processing_system7_0/FCLK_RESET0_N 或系统复位源
proc_sys_reset_adc/aux_reset_in     -> 1'b1
proc_sys_reset_adc/mb_debug_sys_rst -> 1'b0
proc_sys_reset_adc/dcm_locked       -> 1'b1
```

然后使用：

```text
proc_sys_reset_adc/peripheral_aresetn -> pusu_pl_dsp_core_0/aresetn
proc_sys_reset_adc/peripheral_aresetn -> axis_data_fifo_0/s_axis_aresetn
proc_sys_reset_adc/peripheral_aresetn -> pusu_pl_dsp_axi_regs_0/s_axi_aresetn
```

如果 `axis_data_fifo_0/m_axis_aclk` 是 DMA/FCLK 时钟域，则 FIFO 的 M_AXIS 侧
复位应使用该时钟域对应的 reset，不要和 S_AXIS 侧混接。

## 5. AXI-Lite 接线

将 PS 的 AXI master 接到：

```text
pusu_pl_dsp_axi_regs_0/S_AXI
```

如果 BD 没有自动识别成一个 AXI-Lite 总线，可以手动连接这些端口：

```text
s_axi_awaddr
s_axi_awvalid
s_axi_awready
s_axi_wdata
s_axi_wstrb
s_axi_wvalid
s_axi_wready
s_axi_bresp
s_axi_bvalid
s_axi_bready
s_axi_araddr
s_axi_arvalid
s_axi_arready
s_axi_rdata
s_axi_rresp
s_axi_rvalid
s_axi_rready
```

地址宽度为 6 bit，数据宽度为 32 bit。

在 Address Editor 中给 `pusu_pl_dsp_axi_regs_0` 分配一个地址段。建议先用 4 KB 或 64 KB 均可，PS 端后续通过 BSP 宏读取 base address。

## 6. AXI regs 到 DSP core 的控制接线

断开 `pusu_pl_dsp_core_0` 原来的 `enable`、`clear_status` 常量或手动控制线，改为：

```text
pusu_pl_dsp_axi_regs_0/pl_enable        -> pusu_pl_dsp_core_0/enable
pusu_pl_dsp_axi_regs_0/pl_clear_status  -> pusu_pl_dsp_core_0/clear_status
pusu_pl_dsp_axi_regs_0/pl_soft_reset    -> pusu_pl_dsp_core_0/soft_reset
pusu_pl_dsp_axi_regs_0/pl_mode_update   -> pusu_pl_dsp_core_0/mode_update
pusu_pl_dsp_axi_regs_0/pl_abort         -> pusu_pl_dsp_core_0/abort
pusu_pl_dsp_axi_regs_0/pl_rbw_mode[2:0] -> pusu_pl_dsp_core_0/rbw_mode[2:0]
pusu_pl_dsp_axi_regs_0/pl_output_select[1:0] -> pusu_pl_dsp_core_0/output_select[1:0]
pusu_pl_dsp_axi_regs_0/pl_frame_words[31:0]  -> pusu_pl_dsp_core_0/cfg_frame_words[31:0]
```

## 7. DSP core 到 AXI regs 的状态接线

```text
pusu_pl_dsp_core_0/status_word[31:0]       -> pusu_pl_dsp_axi_regs_0/pl_status_word[31:0]
pusu_pl_dsp_core_0/sample_rate_hz[31:0]    -> pusu_pl_dsp_axi_regs_0/pl_sample_rate_hz[31:0]
pusu_pl_dsp_core_0/decimation_ratio[31:0]  -> pusu_pl_dsp_axi_regs_0/pl_decimation_ratio[31:0]
pusu_pl_dsp_core_0/data_format[31:0]       -> pusu_pl_dsp_axi_regs_0/pl_data_format[31:0]
pusu_pl_dsp_core_0/dbg_input_sample_count[31:0]  -> pusu_pl_dsp_axi_regs_0/pl_input_sample_count[31:0]
pusu_pl_dsp_core_0/dbg_output_sample_count[31:0] -> pusu_pl_dsp_axi_regs_0/pl_output_sample_count[31:0]
pusu_pl_dsp_core_0/dbg_output_drop_count[31:0]   -> pusu_pl_dsp_axi_regs_0/pl_output_drop_count[31:0]
pusu_pl_dsp_core_0/error_code[31:0]        -> pusu_pl_dsp_axi_regs_0/pl_error_code[31:0]
pusu_pl_dsp_core_0/version[31:0]           -> pusu_pl_dsp_axi_regs_0/pl_version[31:0]
```

可选 ILA 观察：

```text
current_rbw_mode
current_output_select
status_word
sample_rate_hz
decimation_ratio
dbg_decim_count
```

## 8. AXIS 数据路径保持不变

保持现有数据路径：

```text
LTC2208_0/M_AXIS -> pusu_pl_dsp_core_0/S_AXIS
pusu_pl_dsp_core_0/M_AXIS -> axis_data_fifo_0/S_AXIS
axis_data_fifo_0/M_AXIS -> axi_dma_0/S_AXIS_S2MM
```

确保：

```text
pusu_pl_dsp_core_0/aclk
axis_data_fifo_0/s_axis_aclk
axis_data_fifo_0/m_axis_aclk
axi_dma_0/m_axi_s2mm_aclk
```

仍按当前已验证方案连接。若 FIFO 用 independent clocks，则 `s_axis_aclk` 接 DSP core 输出时钟，`m_axis_aclk` 接 DMA S2MM 时钟。

### 8.1 AXIS 接口必须整组连接

`pusu_pl_dsp_core_0/M_AXIS -> axis_data_fifo_0/S_AXIS` 和
`axis_data_fifo_0/M_AXIS -> axi_dma_0/S_AXIS_S2MM` 都建议用 Vivado 的 AXIS
interface 总线连接，不要单独手动覆盖 `tdata/tvalid/tready/tlast` 子信号。

如果出现类似：

```text
[BD 41-1271] ... m_axis_tdata has been overridden by the user
```

处理方法：

```text
1. 删除该 AXIS 接口上的所有散线。
2. 断开旧的 interface connection。
3. 重新用接口总线连接 M_AXIS -> S_AXIS。
4. 确认 tdata/tvalid/tready/tlast 都属于同一个 interface connection。
```

### 8.2 tready 连接检查

必须确认：

```text
axis_data_fifo_0/s_axis_tready -> pusu_pl_dsp_core_0/m_axis_tready
axi_dma_0/s_axis_s2mm_tready   -> axis_data_fifo_0/m_axis_tready
```

`pusu_pl_dsp_core_0/m_axis_tready` 不能悬空，也不要 tie-off。当前 RTL 会在
`m_axis_tvalid && !m_axis_tready` 时保持输出样点，背压链路必须真实接通。

### 8.3 可选 debug 输出

以下输出不影响主数据链路，可以不接；推荐接 ILA：

```text
pusu_pl_dsp_core_0/current_rbw_mode
pusu_pl_dsp_core_0/current_output_select
pusu_pl_dsp_core_0/dbg_nco_phase
pusu_pl_dsp_core_0/dbg_decim_count
```

以下状态回读建议接到 AXI regs，否则 PS 端无法通过寄存器验证抽取率：

```text
pusu_pl_dsp_core_0/dbg_input_sample_count[31:0]
    -> pusu_pl_dsp_axi_regs_0/pl_input_sample_count[31:0]
pusu_pl_dsp_core_0/dbg_output_sample_count[31:0]
    -> pusu_pl_dsp_axi_regs_0/pl_output_sample_count[31:0]
pusu_pl_dsp_core_0/dbg_output_drop_count[31:0]
    -> pusu_pl_dsp_axi_regs_0/pl_output_drop_count[31:0]
```

## 9. 寄存器读写测试

烧录后，PS 侧最小读写流程：

```text
write RBW_MODE = 2
write OUTPUT_SELECT = 1
write CONTROL = enable=0, mode_update=1
read SAMPLE_RATE_HZ      -> 1000000
read DECIMATION_RATIO    -> 130
write CONTROL = enable=1
```

再测试：

```text
RBW_MODE=4 -> SAMPLE_RATE_HZ=100000, DECIMATION_RATIO=1300
RBW_MODE=5 -> SAMPLE_RATE_HZ=100000, DECIMATION_RATIO=1300
RBW_MODE=0 -> SAMPLE_RATE_HZ=10000000, DECIMATION_RATIO=13
RBW_MODE=1 -> SAMPLE_RATE_HZ=3250000, DECIMATION_RATIO=40
RBW_MODE=3 -> SAMPLE_RATE_HZ=325000, DECIMATION_RATIO=400
```

## 9.1 Validate Design 重点关注

`Validate Design` 通过后仍建议人工确认：

```text
1. pusu_pl_dsp_axi_regs_0/S_AXI 已在 Address Editor 中分配地址。
2. AXI Clock Converter 存在，且 regs 的 s_axi_aclk 与 DSP core aclk 同域。
3. pusu_pl_dsp_core_0/aresetn 和 FIFO S_AXIS reset 同步到 LTC2208_0/m_axis_aclk。
4. FIFO M_AXIS 侧 reset 同步到 DMA/FCLK 域。
5. pusu_pl_dsp_core_0/m_axis_tready 真实来自 FIFO S_AXIS，不是悬空或常量。
6. axis_data_fifo_0/M_AXIS 到 axi_dma_0/S_AXIS_S2MM 没有子信号 override warning。
7. current_rbw_mode/current_output_select 未连接 warning 可接受；输入端口未连接不可接受。
```

## 10. 当前限制

本次 RTL 只是控制面和多抽取率 bring-up 框架：

- 仍是 accumulator decimator，不是最终可信 FIR/polyphase decimator。
- 幅度归一化是近似 power-of-two shift，仅用于 debug IQ。
- 不能用本次 PL 输出直接宣称最终 RBW 指标达标。
- 下一步应在 Chain A 上先替换正式 `/13` 与 `/10` FIR/polyphase decimator。
