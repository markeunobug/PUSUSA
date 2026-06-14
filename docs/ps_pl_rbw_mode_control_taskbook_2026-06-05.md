# PS/PL RBW 模式控制任务书

更新日期：2026-06-05

## 0. 前提说明

用户建议的模式编号为：

```text
0 = 1M
1 = 30K
2 = 100K
3 = 30K
4 = 10K
5 = 1K
```

其中 `1` 和 `3` 都写成了 `30K`。本文先按以下修正理解：

```text
0 = 1M
1 = 300K
2 = 100K
3 = 30K
4 = 10K
5 = 1K
```

如果后续确认 `300K` 暂时不做，则需要重新定义枚举并同步 PS/PL/上位机/诊断脚本。

## 1. 总体契约

PS 是模式控制主机，PL 是测量数据面。

PS 负责告诉 PL 当前 RBW mode；PL 负责根据 mode 选择对应 decimation chain，并回报实际输出采样率、总抽取率和状态。

第一版数据路径：

```text
PL: ADC -> DDC -> per-RBW decimated IQ -> AXI DMA
PS: unpack IQ -> RBW FIR -> power -> ENBW/amplitude correction -> UART spectrum point
```

最终数据路径：

```text
PL: ADC -> DDC -> decimation -> RBW FIR -> power accumulation
PS: configure -> read point result -> calibration -> UART spectrum point
```

## 2. RBW Mode 枚举冻结

建议在 PS 和 PL 两侧都使用同一套编号：

| RBW mode value | 名称 | 名义 RBW | PL 输出采样率 | 总抽取率 | Decim chain |
| ---: | --- | ---: | ---: | ---: | --- |
| 0 | `PL_RBW_MODE_1M` | 1 MHz | 10 MSPS | 13 | Chain A `/13` |
| 1 | `PL_RBW_MODE_300K` | 300 kHz | 3.25 MSPS | 40 | Chain B `/40` |
| 2 | `PL_RBW_MODE_100K` | 100 kHz | 1 MSPS | 130 | Chain A `/13 -> /10` |
| 3 | `PL_RBW_MODE_30K` | 30 kHz | 325 kSPS | 400 | Chain B `/40 -> /10` |
| 4 | `PL_RBW_MODE_10K` | 10 kHz | 100 kSPS | 1300 | Chain A `/13 -> /10 -> /10` |
| 5 | `PL_RBW_MODE_1K` | 1 kHz | 100 kSPS | 1300 | Chain A `/13 -> /10 -> /10` |

注意：

- 10K 和 1K 共享同一个 `100 kSPS` decimated IQ 输出，只是 PS/PL 后级 RBW FIR taps、observe、skip、accum 不同。
- 第一版 PL 只按 mode 输出 decimated IQ；RBW FIR 仍在 PS。
- 这套 mode value 应作为接口 ABI，后续不要随意改顺序。

## 3. 最小 AXI-Lite 寄存器表

第一版建议给 `pusu_pl_dsp_core` 增加 AXI-Lite slave，最小寄存器如下：

| Offset | Register | R/W | 位定义 / 说明 |
| ---: | --- | --- | --- |
| `0x00` | `CONTROL` | R/W | bit0 `enable`；bit1 `soft_reset`；bit2 `clear_status`；bit3 `mode_update`；bit4 `abort` |
| `0x04` | `STATUS` | R | bit0 `idle`；bit1 `configured`；bit2 `mode_switch_busy`；bit3 `output_valid_enabled`；bit4 `overflow`；bit5 `drop_seen`；bit6 `error` |
| `0x08` | `RBW_MODE` | R/W | 当前目标 RBW mode，取值 0..5 |
| `0x0C` | `OUTPUT_SELECT` | R/W | 0 disabled；1 decimated IQ；2 post-RBW IQ；3 point power |
| `0x10` | `SAMPLE_RATE_HZ` | R | 当前输出 IQ 或测量通道采样率 |
| `0x14` | `DECIMATION_RATIO` | R | 当前总抽取率 |
| `0x18` | `FRAME_WORDS` | R/W | Debug IQ DMA 每帧 word 数，默认 4096 |
| `0x1C` | `DATA_FORMAT` | R | bit[7:0] version；bit[15:8] word bytes；bit[23:16] IQ packing |
| `0x20` | `INPUT_SAMPLE_COUNT` | R | ADC 输入样点计数 |
| `0x24` | `OUTPUT_SAMPLE_COUNT` | R | PL 输出 IQ 样点计数 |
| `0x28` | `OUTPUT_DROP_COUNT` | R | AXIS backpressure/drop 计数 |
| `0x2C` | `ERROR_CODE` | R | 最近错误码 |
| `0x30` | `VERSION` | R | PL DSP IP version |

第一版可以不实现点功率寄存器；但 `OUTPUT_SELECT=3` 应保留枚举，便于后续扩展。

## 4. Mode Switching 握手

PS 每次切换 RBW 必须按以下顺序：

```text
1. PS stop sweep / stop point
2. PS abort DMA, clear DMA pending irq
3. PS write CONTROL.enable = 0
4. PS write RBW_MODE = target mode
5. PS write OUTPUT_SELECT = decimated IQ
6. PS pulse CONTROL.mode_update = 1
7. PL asserts STATUS.mode_switch_busy = 1
8. PL clears selected chain/router/packetizer state
9. PL loads sample_rate_hz and decimation_ratio for target mode
10. PL deasserts mode_switch_busy, sets configured = 1
11. PS reads back RBW_MODE/SAMPLE_RATE_HZ/DECIMATION_RATIO/DATA_FORMAT
12. PS configures RBW FIR/observe/skip/accum using readback metadata
13. PS clear_status
14. PS enable PL output
15. PS starts DMA
16. PS discards first frame after mode switch or waits valid_after_switch
17. PS starts measurement
```

硬性要求：

- `mode_switch_busy=1` 时，PL 不允许输出 `m_axis_tvalid`。
- `configured=0` 时，PS 不允许启动 DMA 测量。
- PS 必须以 PL readback 的 `SAMPLE_RATE_HZ` 为准，不能用固定 `1 MHz` 假设。
- `clear_status` 只清计数器和错误标志，不改变 mode。
- `soft_reset` 清数据通道状态，但不一定改变配置寄存器。

## 5. 给 PS 的任务书

### 5.1 新增 PL RBW 控制模块

建议新增：

```text
code/pusu_20260604/vitis/pusu_20260604/src/pusu_pl_dsp_control.c
code/pusu_20260604/vitis/pusu_20260604/src/pusu_pl_dsp_control.h
```

职责：

- 封装 AXI-Lite 寄存器读写。
- 提供 `pusu_pl_dsp_set_rbw_mode(rbw_mode_t mode)`。
- 提供 `pusu_pl_dsp_get_status()`。
- 提供 `pusu_pl_dsp_get_sample_rate_hz()`。
- 提供 `pusu_pl_dsp_clear_status()`。
- 提供 `pusu_pl_dsp_enable(bool enable)`。

### 5.2 建立 PS 侧 RBW 配置表

在 PS 侧建立和 PL mode value 一致的配置表：

```c
typedef struct {
    rbw_mode_t fw_mode;
    uint32_t pl_mode_value;
    uint32_t nominal_rbw_hz;
    uint32_t expected_sample_rate_hz;
    uint16_t total_decimation;
    uint16_t rbw_fir_taps;
    float actual_enbw_hz;
    float enbw_correction_db;
    uint16_t observe_points;
    uint16_t skip_points;
    uint16_t accum_target;
} ps_pl_rbw_config_t;
```

最终表：

| Firmware mode | PL mode value | Fs | Decim | taps | ENBW | correction | observe/skip/accum |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `RBW_MODE_1M` | 0 | 10 MSPS | 13 | 96 | 1.002220 MHz | +0.010 dB | 384/32/512 |
| `RBW_MODE_300K` | 1 | 3.25 MSPS | 40 | 128 | 313.368 kHz | +0.189 dB | 384/64/576 |
| `RBW_MODE_100K` | 2 | 1 MSPS | 130 | 128 | 101.478 kHz | +0.064 dB | 384/64/576 |
| `RBW_MODE_30K` | 3 | 325 kSPS | 400 | 192 | 30.643 kHz | +0.092 dB | 256/128/576 |
| `RBW_MODE_10K` | 4 | 100 kSPS | 1300 | 256 | 10.090 kHz | +0.039 dB | 2560/128/2944 |
| `RBW_MODE_1K` | 5 | 100 kSPS | 1300 | 768 | 983.42 Hz | -0.073 dB | 256/128/1152 |

### 5.3 修改现有 PS 测量链

PS 需要修改：

| 模块 | 任务 |
| --- | --- |
| `app_config.h` | 保留 legacy 配置，但 PL IQ 路径改用 PS/PL RBW 配置表，不再固定 `PL_DSP_DEBUG_IQ_SAMPLE_RATE_HZ=1MHz`。 |
| `rbw_filter_coeffs.c/h` | 同步最终系数 CSV；10K 必须使用 Scheme B 100 kSPS 系数；30K/300K 使用 MATLAB 重算系数。 |
| `signal_processing.c/h` | `current_decimated_sample_rate_hz` 从 RBW config / PL readback 设置。 |
| `sweep_engine.c` | RBW 变化时调用 `pusu_pl_dsp_set_rbw_mode()`，并等待 configured。 |
| `dma_capture.c/h` | 保持 32-bit IQ sample；根据 `accum_target` 和 PL 输出采样率决定需要多少 DMA frame。 |
| `device_protocol.c/h` | profile/status 增加 `pl_mode_value`、`pl_sample_rate_hz`、`pl_decimation`、`pl_data_format`。 |
| `tools/serial_300k_rbw_diagnose.py` | 打印 PL readback mode/sample_rate/decimation，诊断 RBW 切换是否正确。 |

### 5.4 PS 验收标准

PS 侧完成后应满足：

- 切换 RBW 后 profile 能显示 PL mode、sample rate、decimation。
- `100K` 读回 `1,000,000 Hz / 130`。
- `10K` 和 `1K` 都读回 `100,000 Hz / 1300`，但 FIR taps/ENBW 不同。
- 如果 PL readback 与 PS 预期不一致，测量应失败并返回错误，不允许继续输出误解释的频谱点。

## 6. 给 PL 的任务书

### 6.1 增加 AXI-Lite 控制面

PL 需要在 `pusu_pl_dsp_core` 中加入 AXI-Lite slave，或先外接轻量寄存器模块。

第一版必须支持：

- `CONTROL`
- `STATUS`
- `RBW_MODE`
- `OUTPUT_SELECT`
- `SAMPLE_RATE_HZ`
- `DECIMATION_RATIO`
- `FRAME_WORDS`
- `DATA_FORMAT`
- counters
- `VERSION`

### 6.2 实现 mode decode

PL mode decode 固定如下：

```verilog
localparam PL_RBW_MODE_1M   = 3'd0;
localparam PL_RBW_MODE_300K = 3'd1;
localparam PL_RBW_MODE_100K = 3'd2;
localparam PL_RBW_MODE_30K  = 3'd3;
localparam PL_RBW_MODE_10K  = 3'd4;
localparam PL_RBW_MODE_1K   = 3'd5;
```

Decode 输出：

| Mode | sample_rate_hz | decimation_ratio | output select |
| ---: | ---: | ---: | --- |
| 0 | 10000000 | 13 | Chain A `/13` |
| 1 | 3250000 | 40 | Chain B `/40` |
| 2 | 1000000 | 130 | Chain A `/130` |
| 3 | 325000 | 400 | Chain B `/400` |
| 4 | 100000 | 1300 | Chain A `/1300` |
| 5 | 100000 | 1300 | Chain A `/1300` |

### 6.3 实现两主干输出选择

第一版数据面：

```text
DDC complex output
  -> Chain A outputs: /13, /130, /1300
  -> Chain B outputs: /40, /400
  -> mode router
  -> packetizer
  -> M_AXIS
```

第一版可分阶段实现：

1. 先用当前已验证 `/130 -> 1MSPS` 替换为 Chain A 的正式 router 框架。
2. 增加 `/13` 输出，验证 1M 高速 DMA。
3. 增加第二级 `/10`，验证 10K/1K 的 100 kSPS 输出。
4. 再做 Chain B `/40` 和 `/400`。

### 6.4 Mode switch 行为

PL 收到 `mode_update` 后必须：

```text
1. stop m_axis_tvalid
2. set mode_switch_busy
3. reset selected decimator/router/packetizer state
4. load mode metadata
5. clear first-frame marker state
6. deassert mode_switch_busy
7. set configured
```

PL 不应在 busy 期间输出旧模式数据。

### 6.5 AXIS 输出格式

第一版沿用当前格式：

```text
m_axis_tdata[31:16] = signed I16
m_axis_tdata[15:0]  = signed Q16
m_axis_tlast        = frame boundary
m_axis_tvalid       = output sample valid
m_axis_tready       = DMA/FIFO ready
```

建议：

- 内部 DDC/decimator 保留更高位宽。
- packetizer 处统一做 rounding/saturation。
- 如果 `m_axis_tvalid && !m_axis_tready`，要么背压保持数据，要么记录 drop；不能默默跳样。
- `OUTPUT_DROP_COUNT` 必须能反映异常。

### 6.6 PL 验收标准

PL 侧完成后应满足：

- 写 `RBW_MODE=2` 后读回 `SAMPLE_RATE_HZ=1000000`、`DECIMATION_RATIO=130`。
- 写 `RBW_MODE=4/5` 后读回 `SAMPLE_RATE_HZ=100000`、`DECIMATION_RATIO=1300`。
- mode switch busy 期间无 AXIS 输出。
- 每个 mode 的 `OUTPUT_SAMPLE_COUNT / INPUT_SAMPLE_COUNT` 比例接近对应抽取率。
- 长时间运行 `OUTPUT_DROP_COUNT=0`。

## 7. 联调顺序

推荐联调顺序：

1. `RBW_MODE_100K = 2`：复现当前 1 MSPS 已验证路径。
2. `RBW_MODE_10K = 4`：验证 100 kSPS 输出和最终 10K Scheme B FIR。
3. `RBW_MODE_1K = 5`：验证 100 kSPS 共享路径和 1K FIR。
4. `RBW_MODE_1M = 0`：验证 10 MSPS 高吞吐。
5. `RBW_MODE_300K = 1`：验证 Chain B `/40`。
6. `RBW_MODE_30K = 3`：验证 Chain B `/400`。

每一步都需要：

- 读回 mode/sample_rate/decimation。
- ILA 看输出 valid 频率。
- DMA profile 看 frame_ready/process_frame。
- 频谱点看中心和 offset 响应。

