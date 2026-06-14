# 当前数字信号处理流程说明

更新日期：2026-06-10

## 0. 结论

项目中已经有数字信号处理流程相关说明，但目前分散在多个文档和两条工程线里：

- `code/pusu_20260608`：当前最新的采集可靠性/SG burst 扫频工程线。主链路仍是 **原始 ADC 采样进 PS，PS 做 DDC、CIC/RBW、功率计算**，但采集侧已经加入有限 burst 和 SG DMA 方向。
- `code/pusu_20260604`：PL DSP 迁移工程线。已经有 **PL 40 MHz DDC + per-RBW 抽取控制 + 32-bit packed IQ 输出** 的 bring-up/debug core，PS 侧继续做 RBW FIR 和 power；它是最终 PL 化 RBW 的过渡形态。
- 最终推荐方向：把 `20260608` 的有限 burst/SG DMA 可靠性经验和 `20260604` 的 PL 连续 DSP 思路合并，逐步走向 **PL 连续 DDC/抽取/RBW FIR/功率累加，PS 只做控制、标定、协议和显示**。

因此，本说明不是替代原有文档，而是把“现在能跑什么、参数怎么理解、怎么验证、哪里还能优化、有哪些替代方案”集中到一处。

## 1. 已有资料索引

建议查阅顺序如下：

| 文档 | 作用 |
| --- | --- |
| `CLAUDE.md` | 项目总览、硬件链路、固件模块和主扫频流程概览。 |
| `docs/digital_chain_checkpoint_2026-03-26.md` | 早期可运行数字链路检查点：ADC DMA、40 MHz DDC、RBW FIR、POWER_DBFS、FFT peak debug。 |
| `docs/digital_signal_chain.drawio` | 数字信号处理链路图，适合汇报/展示。 |
| `docs/pl_ddc_decimation_architecture_plan_2026-06-04.md` | 为什么要把 DDC/抽取/RBW 从 PS 迁到 PL，以及分阶段 PL 架构。 |
| `docs/pl_iq_rbw_config_table_2026-06-05.md` | 最终 PL 侧 RBW 模式表、采样率、抽取率、FIR taps、ENBW 校正。 |
| `docs/pl_ps_interface_plan_2026-06-05.md` | PL RBW 模式控制、AXI-Lite 寄存器、PS/PL 边界建议。 |
| `docs/rbw_system_consistency_and_calibration_2026-06-05.md` | 多 RBW 实测一致性、单频校正表、ENBW 与实测幅度误差的分层说明。 |
| `docs/pl_ps_dma_capture_consistency_plan_2026-06-07.md` | 原始 ADC 采集可靠性、受控单帧、PL capture status 校验。 |
| `docs/pl_ps_bounded_sg_burst_plan_2026-06-08.md` | 有限 burst + SG DMA 方案、测试命令、低 RBW 大批量采集策略。 |
| `docs/direct_if_fft_0_65m_task.md` | direct IF 0-65 MHz FFT 分支方案，属于替代显示路径。 |

## 2. 当前主要实现线 A：`code/pusu_20260608`

这条线是目前最新的“原始 ADC 采集 + PS DSP + 有限 burst/SG DMA”实现。

### 2.1 链路构成

```text
RF frontend
  -> 40 MHz IF
  -> LTC2208, 130 MSPS, signed 16-bit real ADC samples
  -> adc_capture_axis.v, controlled frame / finite burst packet source
  -> axis_data_fifo_0
  -> AXI DMA S2MM, simple or SG burst
  -> PS DDR RX buffer
  -> PS signal_processing_accumulate_dma()
       -> DDC around 40 MHz / sweep residual NCO
       -> CIC decimation by RBW mode
       -> accumulated complex I/Q buffer
       -> compensating RBW FIR
       -> transient skip
       -> mean(I^2 + Q^2)
       -> dBFS -> approximate dBm
  -> amplitude_correction_apply()
  -> UART SPECTRUM_DATA
  -> Flutter host spectrum display
```

这里的 DMA 数据仍是 **raw ADC 16-bit sample**，不是 packed IQ。`TRANSFER_LENGTH = FFT_SIZE * 2`，`FFT_SIZE = 4096`。

### 2.2 扫频状态机

`sweep_engine.c` 当前按点工作：

```text
PREPARE
  -> set IF = 40 MHz
  -> signal_processing_apply_rbw_mode()
SET_LO1
  -> lo_control_set_lo1_for_rf_hz(current_rf_hz)
WAIT_LO1_LOCK
ARM_DMA / REARM_DMA
  -> first try finite SG burst
  -> fallback to controlled simple DMA
WAIT_FRAME
  -> signal_processing_accumulate_dma()
MEASURE
  -> signal_processing_measure_accumulated_power_dbm()
  -> amplitude_correction_apply()
EMIT_POINT
  -> stream one spectrum point
NEXT_POINT
```

`DMA_SWEEP_SG_BURST_ENABLE = 1`，旧的无限 stream SG batch 被关掉：`DMA_SWEEP_SG_BATCH_ENABLE = 0`。

这样做的原因是：PS 提交有限个 BD 时，PL 不能无限吐 AXIS packet，否则容易在 BD 链表尾部触发 DMA S2MM internal error。有限 burst 模式让 PL 输出 packet 数和 PS 的 BD 数严格匹配。

### 2.3 采集/DMA 使用细节

关键参数：

| 项 | 当前值 |
| --- | ---: |
| ADC sample rate | 130 MSPS |
| IF / DDC center | 40 MHz |
| ADC sample width | 16 bit |
| `FFT_SIZE` | 4096 samples |
| simple DMA 基本帧 | 4096 samples = 8192 bytes |
| controlled capture 单帧上限 | 16384 samples |
| simple sweep transfer 上限 | 4 * 4096 samples = 32768 bytes |
| SG burst 最大块数 | 1024 blocks |
| SG burst 最大样本数 | 1024 * 4096 samples |
| SG burst 最大原始数据量 | 8 MB |

调试命令入口：

```powershell
python C:\learning\pusu_V2\tools\capture_stream_smoke_test.py --port COM7 --baud 921600 --mode main --samples 4096 --timeout 5
python C:\learning\pusu_V2\tools\capture_stream_smoke_test.py --port COM7 --baud 921600 --mode sgring --samples-per-bd 4096 --bd-count 8 --target-bd-count 64 --timeout 5
python C:\learning\pusu_V2\tools\capture_stream_smoke_test.py --port COM7 --baud 921600 --mode sgburst --samples-per-bd 4096 --bd-count 7 --timeout 5
```

下载当前 `20260608` ELF 的脚本入口：

```powershell
xsct C:\learning\pusu_V2\tools\download_pusu_20260608_elf.tcl
```

### 2.4 当前 RBW 参数

`code/pusu_20260608/vitis/pusu_20260608/src/app_config.h` 当前采用的是快速测试口径，observe 点数比最终稳态测量更少。

| RBW | enum | CIC R/N | Fs after decim | FIR taps | Observe | Skip | Accum target | 4096-sample blocks, approx. |
| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1M | 4 | R=13, N=4 | 10.000 MSPS | 96 | 100 | 32 | 228 | 1 |
| 300K | 3 | R=43, N=4 | 3.023 MSPS | 128 | 101 | 64 | 293 | 4 |
| 100K | 2 | R=130, N=5 | 1.000 MSPS | 128 | 100 | 64 | 292 | 10 |
| 30K | 1 | R=433, N=5 | 300.2 kSPS | 256 | 101 | 128 | 485 | 54 |
| 10K | 0 | R=1300, N=5 | 100.0 kSPS | 256 | 100 | 128 | 484 | 162 |
| 1K | 5 | R=1300, N=5 | 100.0 kSPS | 768 | 500 | 128 | 1396 | 466 |

说明：

- `Accum target = observe + skip + FIR taps`，超过 `ACCUM_BUFFER_SIZE = 2944` 时会截断。
- 表中 block 数按整数 decimated samples per `4096` raw block 估算，用于理解 DMA rearm/SG burst 压力。
- `300K` 和 `30K` 当前仍用 `R=43/433` 的旧 PS CIC 路径；最终 PL 表中它们应改为 `R=40/400`，对应 `3.25 MSPS/325 kSPS`。
- `RBW_10K_USE_FIR_DECIMATOR = 0`，也就是当前 10K 默认仍走 CIC 低速路径，不启用 8192 taps 的 130x FIR decimator 诊断分支。
- `SIGNAL_PROCESSING_DDC_DEBUG_ENABLE = 0` 和 `SIGNAL_PROCESSING_PEAK_SEARCH_ENABLE = 0`，正常扫频时关闭昂贵 debug 计算以提升速度。

## 3. 当前主要实现线 B：`code/pusu_20260604`

这条线是 PL DSP 迁移路线，目标是消除 PS 分块处理导致的滤波状态风险。

### 3.1 链路构成

```text
LTC2208 raw ADC, 130 MSPS real
  -> pusu_pl_dsp_core.v
       -> fixed 40 MHz NCO / mixer
       -> per-RBW debug decimation
       -> 32-bit packed IQ AXIS output
          tdata[31:16] = signed I
          tdata[15:0]  = signed Q
  -> AXI DMA S2MM
  -> PS signal_processing_accumulate_dma()
       -> unpack packed IQ
       -> optional residual NCO
       -> accumulate decimated IQ
       -> PS RBW ENBW FIR
       -> power dBFS/dBm
  -> amplitude correction / UART / host
```

`app_config.h` 中 `PL_DSP_DEBUG_IQ_PATH = 1`，所以 PS 按 4 bytes/sample 解释 DMA 数据。这个路径已经不是 raw ADC，而是 PL 输出的 complex IQ。

### 3.2 PL 控制接口

`pusu_pl_dsp_axi_regs.v` / `pusu_pl_dsp_control.*` 使用 AXI-Lite 控制和回读：

| Offset | 名称 | 用途 |
| ---: | --- | --- |
| `0x00` | `CONTROL` | enable、soft_reset、clear_status、mode_update、abort、stream_reset |
| `0x04` | `STATUS` | idle、configured、mode_busy、output_enabled、overflow、drop、error、stream_reset_active |
| `0x08` | `RBW_MODE` | PL RBW mode |
| `0x0C` | `OUTPUT_SELECT` | 当前第一版使用 decimated IQ |
| `0x10` | `SAMPLE_RATE_HZ` | PL 当前输出采样率 |
| `0x14` | `DECIMATION_RATIO` | PL 当前总抽取率 |
| `0x18` | `FRAME_WORDS` | debug IQ DMA 帧长，默认 4096 |
| `0x1C` | `DATA_FORMAT` | `0x00010401`, packed IQ16 |
| `0x20..0x30` | counters/version | input/output/drop/error/version 等诊断字段 |

扫频开始或 RBW 切换时，PS 调用 `pusu_pl_dsp_configure_rbw()`，读回 sample rate 和 decimation ratio，再配置 PS 侧 residual NCO 与 RBW FIR 解释。

### 3.3 PL debug core 的限制

`pusu_pl_dsp_core.v` 明确标注当前仍是 bring-up/debug core：

- DDC 固定 40 MHz，利用 `40/130 = 4/13` 的 13-phase NCO LUT。
- 目前 decimator 是 accumulator decimator，不是最终可信的 FIR/polyphase anti-alias decimator。
- 输出 shift 是按 mode 近似归一化，仅适合 debug IQ，不应直接当最终幅度标定依据。
- RBW FIR 和 power accumulation 仍在 PS，尚未完全下沉 PL。

所以 `20260604` 的价值是验证 **PL 连续 DDC + per-RBW decimated IQ + PS 读回状态**，不是最终产品形态。

## 4. 最终目标 RBW 表

最终目标来自 `docs/pl_iq_rbw_config_table_2026-06-05.md` 和 `pusu_pl_dsp_control.c` 的模式表。

| RBW | 最终 Fs | 总抽取率 | FIR taps | actual ENBW | ENBW correction | Observe | Skip | Accum target |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1M | 10 MSPS | 13 | 96 | 1.002220 MHz | +0.010 dB | 384 | 32 | 512 |
| 300K | 3.25 MSPS | 40 | 128 | 313.368 kHz | +0.189 dB | 384 | 64 | 576 |
| 100K | 1 MSPS | 130 | 128 | 101.478 kHz | +0.064 dB | 384 | 64 | 576 |
| 30K | 325 kSPS | 400 | 192 | 30.643 kHz | +0.092 dB | 256 | 128 | 576 |
| 10K | 100 kSPS | 1300 | 256 | 10.090 kHz | +0.039 dB | 2560 | 128 | 2944 |
| 1K | 100 kSPS | 1300 | 768 | 983.42 Hz | -0.073 dB | 256 | 128 | 1152 |

注意点：

- 这张表是最终目标，不等于 `20260608` 当前 raw ADC + PS CIC 快速测试参数。
- `10K` 最终应使用 Scheme B 的 `100 kSPS` 系数；`1 MSPS` 验证路径中的 10K 系数不能冻结为最终 10K FIR。
- `300K/30K` 最终抽取率是 `40/400`，不是旧 PS CIC 的 `43/433`。
- ENBW correction 很小，不能用来掩盖多 dB 的实测幅度差；实测幅度差需要单独的 RBW-mode measured correction。

## 5. 标定与幅度解释

当前功率换算层次：

```text
linear mean power
  -> dBFS
  -> + ADC_INPUT_FULL_SCALE_DBM
  -> raw dBm
  -> amplitude_correction_apply()
  -> displayed dBm
```

`docs/rbw_system_consistency_and_calibration_2026-06-05.md` 的 1 GHz / -10 dBm 单频测试说明：

| RBW | mean peak dBm | provisional correction |
| --- | ---: | ---: |
| 1M | -14.46 | +4.46 dB |
| 300K | -11.03 | +1.03 dB |
| 100K | 100K-only steady value约 -12.84 到 -12.85 | 约 +2.84 dB |
| 30K | -15.15 | +5.15 dB |
| 10K | -10.97 | +0.97 dB |
| 1K | -10.93 | +0.93 dB |

这只是单频、单功率、单前端状态的临时表，不能直接当最终 RF 校准。

推荐分两层处理：

1. **ENBW/RBW 理论校正**：用于 RBW 定义和噪声密度口径，量级通常小于 0.2 dB。
2. **实测 RBW-mode 幅度校正**：用已知信号源测每个 RBW 模式的峰值误差，后续按频率、功率、前端状态扩展成结构化校准数据。

## 6. 使用建议

### 6.1 普通扫频

普通上位机扫频仍走现有 `GET_SPECTRUM` / `SPECTRUM_DATA` 协议。用户侧主要配置：

- RF path：mixer chain 或 direct IF。
- start / stop / points。
- RBW mode：`1K/10K/30K/100K/300K/1M`。
- 前端状态：LNA、attenuator、VGA 等。

当前 mixer-chain 正常扫频使用 LO per-point tuning。不要把固定 LO residual sweep 当默认低 RBW 方案；在低采样率下做宽 span residual sweep 会折叠频率。

### 6.2 采集链路 smoke test

先测最小主链路，再测 SG ring，再测有限 burst：

```powershell
python C:\learning\pusu_V2\tools\capture_stream_smoke_test.py --port COM7 --baud 921600 --mode main --samples 4096 --timeout 5
python C:\learning\pusu_V2\tools\capture_stream_smoke_test.py --port COM7 --baud 921600 --mode sgring --samples-per-bd 4096 --bd-count 8 --target-bd-count 64 --timeout 5
python C:\learning\pusu_V2\tools\capture_stream_smoke_test.py --port COM7 --baud 921600 --mode sgburst --samples-per-bd 4096 --bd-count 1 --timeout 5
python C:\learning\pusu_V2\tools\capture_stream_smoke_test.py --port COM7 --baud 921600 --mode sgburst --samples-per-bd 4096 --bd-count 7 --timeout 5
```

健康结果应关注：

- `result_code = OK`
- `dma_completed = 1`
- `dma_error = 0`
- `completed_bd_count == bd_count`
- `completed_bytes == samples_per_bd * bd_count * 2`
- `overflow_count = 0`
- `backpressure_count = 0`
- `burst_packet_count == bd_count`

### 6.3 RBW 一致性测试

已有工具：

```powershell
python C:\learning\pusu_V2\tools\rbw_system_consistency_matrix.py --help
```

建议测试顺序：

1. 单 RBW 重复测，确认该 RBW 自身稳定。
2. 多 RBW 轮询测，观察 mode switch 后第一帧污染。
3. 每次 RBW 切换后丢弃至少一帧，再做校准采样。
4. 多功率、多频点重复，区分 RBW-mode 校正和 RF 频响校正。

## 7. 优化空间

### 7.1 采集和 DMA

当前 `20260608` 已经把不安全的无限 stream SG batch 关掉，有限 burst 是正确方向。下一步优化：

- 把 SG ring 从小规模扩大到 128 / 1024 BD，覆盖 30K / 10K 等低 RBW 大采样需求。
- 保证 DDR RX buffer 和 BD ring 不重叠，8 MB raw burst 要有连续可用空间。
- 在 sweep 中优先使用有限 burst，一次采够一个点需要的 raw blocks，减少 simple DMA rearm 次数。
- 对每次采集严格检查 PL status、BD completion、overflow/backpressure、TLAST/packet count。

### 7.2 DSP 连续性

PS 端跨 DMA block 保持长 FIR/decimator 状态时，最怕 block 之间不是连续样本。优化方向：

- 短期：受控 frame / finite burst，保证一个 burst 内 packet 数和 BD 数一致。
- 中期：PL 输出连续 decimated IQ，PS 只做 RBW FIR/power，降低 raw 数据吞吐。
- 长期：RBW FIR 和 power accumulation 全部下沉 PL，PS 只读点结果。

### 7.3 RBW 设计

需要把“当前能跑”和“最终可信”分开：

- `20260608` 当前快测 observe 点数较少，适合速度/链路验证。
- 最终 RBW 表应按 ENBW 复核后的采样率、taps、observe/skip/accum target 冻结。
- `300K/30K` 不应长期停在旧 `43/433` CIC 口径。
- `1K` flatness 已标记为放宽口径，若产品指标变严，需要增加 taps 或重新设计 FIR。

### 7.4 标定

ENBW 校正和实测幅度校正要分层：

- ENBW 校正只修 RBW 定义，不负责修 RF/数字链路增益。
- 实测校正需要记录频率、功率、RBW、前端状态、时间戳。
- RBW 切换后的第一帧建议丢弃，避免 mode-transition state 污染校准表。

### 7.5 扫频策略

默认应保持 per-point LO tuning。固定 LO + residual NCO 只适合明确受限的 fast sweep：

- span 必须安全落在当前 IQ sample rate 的可表示带宽内。
- 低 RBW 不能用过宽 span，否则会出现周期性折叠峰。
- 对 `10K/1K` 这类 100 kSPS 输出，250 kHz 级 span 不适合作 fixed-LO residual sweep。

## 8. 替代方案对比

| 方案 | 位置 | 优点 | 风险/缺点 | 适合阶段 |
| --- | --- | --- | --- | --- |
| Legacy simple DMA + PS DDC/CIC/RBW | `20260516` / `20260608` fallback | 最容易理解，改动少 | rearm 多，低 RBW 慢，跨 block 连续性风险 | 基线回归、故障隔离 |
| Controlled frame + finite SG burst + PS DSP | `20260608` | 采集边界明确，可一次抓更多 raw blocks | PS 计算量仍大，raw 数据量大，仍需处理跨 burst 状态 | 当前推荐短期主线 |
| PL DDC/decimated IQ + PS RBW FIR/power | `20260604` | 降低数据率，改善连续性，可读回 PL mode/status | 当前 decimator 仍是 debug accumulator，幅度不可最终信任 | 中期迁移验证 |
| Full PL RBW FIR + PL power accumulator | 目标方案 | 吞吐最高，最接近仪器产品架构，PS 只读点功率 | RTL/定点/标定复杂，验证成本高 | 最终产品路径 |
| Direct IF 0-65 MHz FFT | `direct_if_fft_0_65m_task.md` | 适合 LF/direct IF 一帧 FFT 显示，不扫 LO | 不是 mixer-chain RBW 扫频，不替代窄 RBW power path | direct IF 显示分支 |

## 9. 建议下一步

1. 把 `20260608` 有限 burst smoke test 跑通并记录健康签名。
2. 用当前快测 RBW 参数跑一轮 sweep，确认 `100K/30K/10K/1K` 不再触发 `last_irq=0x00005000`。
3. 对 `20260608` 低 RBW sweep 增加“每点实际 raw blocks / SG burst 次数 / captured samples / accum_count”的 profile 输出，便于判断速度瓶颈。
4. 保持 `20260604` PL IQ 迁移线继续推进，但文档和协议里明确标记 `DSP_PATH_PL_DEBUG_IQ_PS_RBW`，避免把 debug IQ 当成最终 RBW。
5. 冻结最终 per-RBW FIR/ENBW 表后，再把 `300K/30K` 从旧 PS CIC 参数迁到最终 `40/400` 口径。
6. 逐步把 RBW FIR 和 power accumulation 下沉 PL；下沉前保留 PS 路径作为 A/B 对照。

## 10. 一句话版本

目前项目不是没有说明，而是说明比较分散。当前最新可运行方向是 `20260608` 的 **有限 burst/SG DMA + PS DDC/CIC/RBW**；中期迁移方向是 `20260604` 的 **PL DDC/decimated IQ + PS RBW**；最终目标是 **PL 连续完成 DDC、抽取、RBW FIR 和功率累加，PS 只负责控制、标定和协议**。
