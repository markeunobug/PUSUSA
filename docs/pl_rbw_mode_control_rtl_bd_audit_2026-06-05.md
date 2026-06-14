# PL RBW Mode Control RTL/BD Audit

更新日期：2026-06-05

## 结论

`pusu_pl_dsp_core.v` 与 `pusu_pl_dsp_axi_regs.v` 的端口、寄存器 offset、RBW mode 编号、sample-rate/decimation readback 与任务书总体一致。

本次审计只修了一个 PL RTL 状态语义小问题：`STATUS.configured` 在 `mode_switch_busy=1` 期间现在读为 0，避免 PS 在 mode switch hold window 内误判配置完成。

当前 Block Design 仍有必须人工处理的 CDC/复位风险，不能仅靠 RTL 修正解决。

## RTL 接口核对

### AXI-Lite 寄存器

寄存器表与任务书一致：

| Offset | RTL register | 语义 |
| ---: | --- | --- |
| `0x00` | `CONTROL` | bit0 `enable` 保持；bit1 `soft_reset`、bit2 `clear_status`、bit3 `mode_update`、bit4 `abort` 为 1-cycle pulse |
| `0x04` | `STATUS` | 来自 `status_word` |
| `0x08` | `RBW_MODE` | `pl_rbw_mode[2:0]` |
| `0x0C` | `OUTPUT_SELECT` | `pl_output_select[1:0]` |
| `0x10` | `SAMPLE_RATE_HZ` | PL readback |
| `0x14` | `DECIMATION_RATIO` | PL readback |
| `0x18` | `FRAME_WORDS` | `pl_frame_words[31:0]`，默认 4096 |
| `0x1C` | `DATA_FORMAT` | `0x00010401`: version 1, 4 bytes/word, packed IQ16 |
| `0x20` | `INPUT_SAMPLE_COUNT` | input counter |
| `0x24` | `OUTPUT_SAMPLE_COUNT` | output counter |
| `0x28` | `OUTPUT_DROP_COUNT` | backpressure/drop counter |
| `0x2C` | `ERROR_CODE` | invalid mode 等错误 |
| `0x30` | `VERSION` | `0x20260605` |

### Mode decode

RTL decode 与任务书一致：

| Mode | RBW | Fs | Decimation |
| ---: | --- | ---: | ---: |
| 0 | 1M | 10000000 | 13 |
| 1 | 300K | 3250000 | 40 |
| 2 | 100K | 1000000 | 130 |
| 3 | 30K | 325000 | 400 |
| 4 | 10K | 100000 | 1300 |
| 5 | 1K | 100000 | 1300 |

`OUTPUT_SELECT=0/2/3` 当前不会输出 AXIS 数据；第一版只启用 `OUTPUT_SELECT=1` decimated IQ，保留其余枚举。

### AXIS 语义

- `m_axis_tdata[31:16]=I16`、`m_axis_tdata[15:0]=Q16` 与任务书一致。
- `m_axis_tlast` 按 `cfg_frame_words` 产生 frame boundary；`cfg_frame_words=0` 时回退默认 4096。
- 当 `m_axis_tvalid && !m_axis_tready` 且下一点即将输出时，RTL 通过拉低 `s_axis_tready` 保持输出点；`OUTPUT_DROP_COUNT` 实际更接近 backpressure cycle counter。
- `clear_status` 清计数器、drop/overflow/error，不改 mode。
- `soft_reset`/`abort` 清数据通道状态，不改 mode 配置。

## 已发现并修正的问题

### STATUS.configured 在 busy 期间提前为 1

原 RTL 在 `mode_update` 后立即让 `configured=1`，同时 `mode_switch_busy=1` 维持 16 个周期。虽然输出路径有 `!mode_switch_busy` 保护，但 PS 如果只看 `STATUS.configured` 可能提前启动 DMA。

已修改：

```verilog
// bit 1 configured
(configured && !mode_switch_busy)
```

## BD 审计结果

当前 BD 已包含：

- `pusu_pl_dsp_axi_regs_0`
- AXI-Lite segment: `0x43C00000`, range `64K`
- `pusu_pl_dsp_axi_regs_0/s_axi` 接到 `ps7_0_axi_periph/M05_AXI`
- `pusu_pl_dsp_axi_regs_0` 到 `pusu_pl_dsp_core_0` 的 enable/reset/mode/output/frame_words 控制线
- `pusu_pl_dsp_core_0` 到 `pusu_pl_dsp_axi_regs_0` 的 status/sample_rate/decimation/data_format/counters/error/version 状态线
- `LTC2208_0/M_AXIS -> pusu_pl_dsp_core_0/S_AXIS`
- `pusu_pl_dsp_core_0/M_AXIS -> axis_data_fifo_0/S_AXIS`
- `axis_data_fifo_0/M_AXIS -> axi_dma_0/S_AXIS_S2MM`
- `axis_data_fifo_0/s_axis_tready -> pusu_pl_dsp_core_0/m_axis_tready`
- `axi_dma_0/s_axis_s2mm_tready -> axis_data_fifo_0/m_axis_tready`

### 必须处理的 BD 风险

当前 BD 里：

- `pusu_pl_dsp_core_0/aclk` 接 `LTC2208_0/m_axis_aclk`
- `pusu_pl_dsp_axi_regs_0/s_axi_aclk` 接 `processing_system7_0/FCLK_CLK0`
- 两者之间的 control/status 信号直接相连

这会形成跨时钟域直连风险。下一步必须二选一：

1. 让 `pusu_pl_dsp_axi_regs_0/s_axi_aclk` 与 `pusu_pl_dsp_core_0/aclk` 同域，并用 AXI Clock Converter 从 PS AXI 域跨到 ADC/DSP 域。
2. 保持 AXI regs 在 FCLK 域，但在 regs 与 DSP core 之间增加明确的 CDC synchronizer/handshake，不允许直接连多 bit mode/status bus。

当前 BD 还把 `proc_sys_reset_0/peripheral_aresetn` 同时接到 FCLK 域 AXI、ADC/DSP 域 core、FIFO S_AXIS 侧和 regs reset。若 core/FIFO S_AXIS 运行在 `LTC2208_0/m_axis_aclk`，应新增 ADC clock domain reset，例如 `proc_sys_reset_adc`，并将 core、FIFO S_AXIS 和同域 regs reset 同步到 ADC/DSP 时钟。

## BD 最终检查清单

1. Address Editor 确认 `pusu_pl_dsp_axi_regs_0` base address 为 `0x43C00000`，range `64K`，并同步到 XSA/BSP 宏。
2. `pusu_pl_dsp_axi_regs_0` 与 `pusu_pl_dsp_core_0` 的 control/status 直连信号必须同一时钟域，或加明确 CDC。
3. `pusu_pl_dsp_core_0/aresetn`、`axis_data_fifo_0/s_axis_aresetn`、同域 regs reset 必须同步到对应 clock。
4. `pusu_pl_dsp_core_0/M_AXIS -> axis_data_fifo_0/S_AXIS` 用完整 AXI4-Stream interface 连接，Validate Design 不应出现子信号 override warning。
5. `axis_data_fifo_0/M_AXIS -> axi_dma_0/S_AXIS_S2MM` 用完整 AXI4-Stream interface 连接。
6. `m_axis_tready` 链路必须真实回连：DMA `tready` 到 FIFO M_AXIS，FIFO S_AXIS `tready` 到 DSP core。
7. ILA 建议探针：`current_rbw_mode`、`current_output_select`、`status_word`、`sample_rate_hz`、`decimation_ratio`、`dbg_decim_count`、`dbg_output_drop_count`、`m_axis_tdata/tvalid/tready/tlast`、FIFO M_AXIS `tdata/tvalid/tready/tlast`、DMA irq/status。

## 静态检查说明

当前环境 PATH 中没有可用的 `xvlog`、`iverilog`、`verilator`、`yosys` 或 verible 工具，因此未能做真正 Verilog 编译/综合级检查。已做文本级静态核对：端口、offset、mode decode、AXIS 信号、BD 连接、地址和时钟复位字段。
