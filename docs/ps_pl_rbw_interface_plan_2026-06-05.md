# PuSuSA PS/PL RBW Interface Plan

更新日期：2026-06-05

## 1. 目标和边界

本文只定义 PS/PL 接口和软件职责边界，不修改固件代码，不替代 FIR 参数离线设计和 PL 多级抽取树设计。

当前已经验证的 PL 路径是 bring-up/debug path：

```text
ADC 130 MSPS real AXIS
  -> pusu_pl_dsp_core 固定 40 MHz DDC
  -> 简单 /130 accumulator decimation
  -> 1 MSPS complex IQ
  -> AXI Stream FIFO
  -> AXI DMA S2MM
  -> PS unpack IQ + residual NCO + RBW FIR + power
```

最终可信 RBW 路径应按最终采样率表推进：

| RBW mode | 名义 RBW | PL 输出采样率 | 总抽取率 |
| --- | ---: | ---: | ---: |
| `RBW_MODE_1M` | 1 MHz | 10 MSPS | 13 |
| `RBW_MODE_300K` | 300 kHz | 3.25 MSPS | 40 |
| `RBW_MODE_100K` | 100 kHz | 1 MSPS | 130 |
| `RBW_MODE_30K` | 30 kHz | 325 kSPS | 400 |
| `RBW_MODE_10K` | 10 kHz | 100 kSPS | 1300 |
| `RBW_MODE_1K` | 1 kHz | 100 kSPS | 1300 |

## 2. 第一版 PS/PL 分工

第一版目标是尽快让多 RBW 在 PL IQ 架构下逻辑自洽，同时保留 PS 端可观察性。

PL 负责：

- 40 MHz IF complex DDC。
- 按 RBW mode 输出对应采样率的 decimated IQ。
- 保持 decimator 状态连续，避免 PS 侧 DMA block discontinuity 再进入 FIR 状态。
- 通过 AXI DMA 输出 debug/measurement IQ。
- 暴露 mode、sample rate、decimation、输出计数、drop 计数、当前状态等寄存器。

PS 负责：

- 根据 RBW mode 配置 PL。
- 等待 PL mode switch 完成。
- 按 PL 返回的 `sample_rate_hz` 解释 DMA IQ。
- 在 PS 端完成 RBW ENBW FIR、skip/observe、power accumulation、ENBW correction、amplitude correction。
- 继续通过现有 UART spectrum point 协议向上位机输出频谱点。

第一版不要让上位机直接看到“PL debug IQ”这个内部形态。上位机仍只接收点功率，debug IQ 只服务诊断脚本和 ILA/Vivado bring-up。

## 3. 最终版 PS/PL 分工

最终版目标是 PL 输出可信点功率，PS 只做控制、标定和通信。

PL 负责：

- DDC。
- 多级连续 FIR/polyphase decimation。
- RBW ENBW FIR。
- skip/observe 窗口控制。
- power accumulation。
- ENBW correction 可选：建议先在 PS 中做，最终可固化到 PL。
- 点完成标志、点功率寄存器或结果 FIFO。

PS 负责：

- 配置 RBW mode、目标频点、LO/residual frequency、检测模式和测量窗口。
- 启动/停止每个点的 PL 测量。
- 读取点功率、状态和错误码。
- 应用幅度校准、RF path 校准、温度/前端状态标记。
- 通过现有 UART 协议输出 spectrum point。

最终版可以完全绕开大块 IQ DMA，只在 debug 模式下打开 IQ DMA。

## 4. 模式配置字段

建议新增独立的 PL RBW mode 配置结构。第一版可先在 PS 内部使用，后续映射到 AXI-Lite 寄存器。

```c
typedef enum {
    PL_RBW_OUTPUT_IQ_AFTER_DECIM = 0,
    PL_RBW_OUTPUT_IQ_AFTER_RBW_FIR = 1,
    PL_RBW_OUTPUT_POWER_POINT = 2,
    PL_RBW_OUTPUT_DISABLED = 3
} pl_rbw_output_select_t;

typedef struct {
    rbw_mode_t rbw_mode;
    uint32_t nominal_rbw_hz;
    uint32_t output_sample_rate_hz;
    uint16_t total_decimation;
    uint16_t decim_chain_id;
    uint16_t rbw_fir_taps;
    uint16_t observe_points;
    uint16_t skip_points;
    uint16_t accum_target;
    float actual_enbw_hz;
    float enbw_correction_db;
    pl_rbw_output_select_t debug_output_select;
    uint8_t pl_decim_enabled;
    uint8_t pl_rbw_fir_enabled;
    uint8_t pl_power_enabled;
} pl_rbw_mode_config_t;
```

建议第一版固定：

- `pl_decim_enabled = 1`
- `pl_rbw_fir_enabled = 0`
- `pl_power_enabled = 0`
- `debug_output_select = PL_RBW_OUTPUT_IQ_AFTER_DECIM`

最终版逐模式打开：

- `pl_rbw_fir_enabled = 1`
- `pl_power_enabled = 1`
- `debug_output_select = PL_RBW_OUTPUT_POWER_POINT`

## 5. AXI-Lite 寄存器建议

当前 `pusu_pl_dsp_core` 只有 `enable`、`clear_status` 和若干 debug 输出线。最终需要把它升级为带 AXI-Lite 控制面的 DSP IP，或外接一个轻量寄存器模块。

建议寄存器表：

| Offset | 名称 | 方向 | 说明 |
| ---: | --- | --- | --- |
| `0x00` | `CONTROL` | W/R | bit0 `enable`，bit1 `soft_reset`，bit2 `clear_status`，bit3 `start_point`，bit4 `abort_point` |
| `0x04` | `STATUS` | R | bit0 `idle`，bit1 `configured`，bit2 `mode_switch_busy`，bit3 `point_busy`，bit4 `point_done`，bit5 `overflow`，bit6 `underflow`，bit7 `error` |
| `0x08` | `RBW_MODE` | W/R | 与 PS `rbw_mode_t` 对齐 |
| `0x0C` | `OUTPUT_SELECT` | W/R | decimated IQ、post-RBW IQ、point power、disabled |
| `0x10` | `SAMPLE_RATE_HZ` | R | 当前 PL 输出 IQ 或内部测量采样率 |
| `0x14` | `DECIMATION_RATIO` | R | 当前总抽取率 |
| `0x18` | `FRAME_WORDS` | W/R | debug IQ DMA 每帧 word 数，默认 4096 |
| `0x1C` | `POINT_ID` | W/R | PS 写入当前 sweep point index，PL 回读用于对账 |
| `0x20` | `RESIDUAL_FREQ_HZ_Q16` | W/R | 可选，最终 residual NCO 下沉 PL 时使用 |
| `0x24` | `OBSERVE_POINTS` | W/R | 当前测量窗口 |
| `0x28` | `SKIP_POINTS` | W/R | 当前跳过点数 |
| `0x2C` | `ACCUM_TARGET` | W/R | 当前累计目标 |
| `0x30` | `INPUT_SAMPLE_COUNT` | R | ADC 输入样本计数 |
| `0x34` | `OUTPUT_SAMPLE_COUNT` | R | debug IQ 或内部输出计数 |
| `0x38` | `OUTPUT_DROP_COUNT` | R | AXIS backpressure/drop 计数 |
| `0x3C` | `POINT_DONE_COUNT` | R | 点功率完成计数 |
| `0x40` | `ERROR_CODE` | R | 最近错误码 |
| `0x44` | `POWER_DBFS_Q8_24` | R | 最终点功率，定点 dBFS |
| `0x48` | `POWER_LINEAR_HI` | R | 可选，线性功率累加高 32 bit |
| `0x4C` | `POWER_LINEAR_LO` | R | 可选，线性功率累加低 32 bit |
| `0x50` | `VERSION` | R | IP version、data format version |

第一版可以先实现 `CONTROL/STATUS/RBW_MODE/OUTPUT_SELECT/SAMPLE_RATE_HZ/DECIMATION_RATIO/FRAME_WORDS/*COUNT/VERSION`。点功率相关寄存器留到第二阶段。

## 6. Mode switching handshake

PS 切换 RBW 时应使用明确握手，避免 DMA 正在收旧模式数据时 PS 已经按新模式解释。

推荐流程：

```text
PS stop sweep / stop point
PS disable PL output
PS abort DMA and clear pending IRQ
PS write RBW_MODE and OUTPUT_SELECT
PS pulse soft_reset or mode_update
PL asserts mode_switch_busy
PL resets decimator/FIR/power state
PL loads mode config
PL deasserts mode_switch_busy and sets configured
PS reads SAMPLE_RATE_HZ / DECIMATION_RATIO / VERSION
PS configures dma_sample_count and PS FIR config
PS clear_status
PS enable PL output
PS start DMA / start point
```

要求：

- `mode_switch_busy=1` 时，PL 不应输出 `m_axis_tvalid`。
- `configured=1` 后，`sample_rate_hz`、`decimation_ratio`、`output_select` 必须稳定。
- `clear_status` 只清计数器，不改变 mode 和 FIR 状态。
- `soft_reset/mode_update` 清 decimator/FIR/power 状态。
- PS 端每次 mode switch 后必须丢弃至少一个 debug frame 或等待 `valid_after_mode_switch`，用于规避管线残留。

## 7. DMA 数据格式

### 7.1 第一版 debug IQ DMA

继续复用当前 AXI DMA S2MM：

```text
AXIS word width: 32 bit
tdata[31:16] = signed I16
tdata[15:0]  = signed Q16
tlast        = frame boundary
tuser[3:0]   = data_path_id / flags
```

建议定义 `tuser`：

| bit | 含义 |
| ---: | --- |
| `0` | ADC sideband 原始标志，当前可保留 |
| `1` | `mode_first_frame`，模式切换后的第一帧 |
| `2` | `sample_saturated`，I/Q 饱和 |
| `3` | `debug_path`，1 表示不是最终点功率路径 |

不同采样率仍复用同一个 DMA 格式。区别只在 PS 读取的 metadata：

| RBW | IQ sample rate | 建议 DMA frame words | 每帧时间 |
| --- | ---: | ---: | ---: |
| 1 MHz | 10 MSPS | 4096 | 409.6 us |
| 300 kHz | 3.25 MSPS | 4096 | 1.260 ms |
| 100 kHz | 1 MSPS | 4096 | 4.096 ms |
| 30 kHz | 325 kSPS | 4096 | 12.603 ms |
| 10 kHz | 100 kSPS | 4096 | 40.960 ms |
| 1 kHz | 100 kSPS | 4096 | 40.960 ms |

注意：PS 的 `DMA_STREAM_BYTES_PER_SAMPLE` 仍为 4，但 `PL_DSP_DEBUG_IQ_SAMPLE_RATE_HZ` 不能再是全局固定 1 MHz，必须来自 RBW mode config 或 PL status。

### 7.2 最终点功率输出

最终点功率不建议走大块 AXI DMA IQ 流。推荐两种方式：

方案 A：AXI-Lite status/result registers。

- 适合单点 sweep 逐点读取。
- PS 写 `start_point`，轮询或中断等待 `point_done`，读 `POWER_DBFS_Q8_24`。
- 简单、确定、方便调试。

方案 B：小型 AXIS result FIFO。

```text
tdata[63:0] = {point_id[15:0], flags[7:0], rbw_mode[7:0], power_dbfs_q8_24[31:0]}
```

- 适合连续 sweep 自动吐点。
- 仍需保留 AXI-Lite status。
- 后续如果 sweep 全下沉到 PL，这个更自然。

第一版建议先采用方案 A，等 PL power accumulation 稳定后再决定是否增加 result FIFO。

## 8. 避免上位机误解 bring-up/debug path

当前 UART 上位机只看到 spectrum point，不知道底层是 legacy、PL debug IQ 还是最终 PL power。为了防止误判，应加一层明确标识。

建议增加内部状态字段：

```c
typedef enum {
    DSP_PATH_LEGACY_PS_DDC_CIC = 0,
    DSP_PATH_PL_DEBUG_IQ_PS_RBW = 1,
    DSP_PATH_PL_FINAL_POWER = 2
} dsp_data_path_t;
```

建议在 `GET_PROFILE` 扩展中增加：

- `dsp_data_path`
- `pl_output_select`
- `pl_sample_rate_hz`
- `pl_decimation_ratio`
- `pl_status`
- `pl_error_code`
- `pl_version`

上位机显示策略：

- `DSP_PATH_PL_DEBUG_IQ_PS_RBW`：可显示为调试链路，RBW 结果用于验证，不标记为最终可信版本。
- `DSP_PATH_PL_FINAL_POWER`：才显示为最终 PL RBW。
- debug IQ DMA 永远不直接被 Flutter 解释为频谱 trace；Flutter 仍只消费 UART spectrum points。

## 9. PS 端需要修改的模块

这里只列职责，不改代码。

### `app_config.h`

- 移除 PL IQ 路径对全局固定 `PL_DSP_DEBUG_IQ_SAMPLE_RATE_HZ=1MHz` 的依赖。
- 新增最终 RBW mode table 的采样率、总抽取率、FIR taps、ENBW、skip、observe。
- 将 legacy CIC 参数标记为 legacy path，不再作为 PL RBW 路径依据。
- 增加 `DSP_PATH_*`、`PL_RBW_OUTPUT_*`、PL 寄存器地址或 device id。

### `pusu_pl_dsp_control.c/h`（建议新增）

- 封装 PL AXI-Lite 访问。
- 提供 `pl_rbw_configure_mode()`、`pl_rbw_enable()`、`pl_rbw_disable()`、`pl_rbw_clear_status()`、`pl_rbw_get_status()`。
- 隐藏 mode switching handshake 的细节。
- 提供 PL 返回 metadata：sample rate、decimation、version、status、counter。

### `dma_capture.c/h`

- 保留现有 S2MM DMA。
- 第一版继续按 `sample_count * 4` 请求 IQ debug 数据。
- 支持按当前 PL mode 选择 `frame_words`，默认仍 4096。
- 最终点功率路径下，DMA 可以不参与 sweep measurement，只服务 debug IQ capture。

### `signal_processing.c/h`

- 第一版：输入已经是 PL decimated IQ，只做 PS RBW FIR/power。
- `current_decimated_sample_rate_hz` 改为来自 RBW mode config 或 PL status，而不是固定宏。
- residual NCO 如果保留在 PS，需要以当前 PL sample rate 计算 phase step。
- 将 legacy PS DDC/CIC、当前 PL debug IQ、最终 PL power 三条路径拆清楚。
- 最终版：增加从 PL 点功率直接返回 dBm/dBFS 的路径，绕过 PS FIR/power。

### `sweep_engine.c`

- RBW 切换时先配置 PL mode，再启动 DMA 或 PL point measurement。
- 第一版状态机仍可使用 DMA accumulate/measure 流程。
- 最终版状态机改为：配置 LO -> 等 lock/settle -> start PL point -> wait point_done -> read power -> amplitude correction -> emit point。
- 保留 LO settle/discard frame 作为测试注意项。

### `device_protocol.c/h`

- 现有 `SET_BW` 可以继续承载 RBW mode。
- `GET_STATUS` 可扩展或新增 PL status 命令。
- `GET_PROFILE` 应增加 DSP path 和 PL metadata，方便诊断脚本判断当前数据来自哪条路径。
- 不建议改变现有 `SPECTRUM_DATA` 点格式，避免 Flutter 大改。

### `tools/serial_300k_rbw_diagnose.py`

- 解析新增 PL status/profile 字段。
- 输出 `dsp_data_path`、`pl_output_select`、`pl_sample_rate_hz`、`pl_decimation_ratio`。
- 当路径是 debug IQ 时，在 SUMMARY 中明确提示“不是最终 PL point power path”。
- 支持按目标 RBW 自动检查期望 sample rate。

### `pusu_pl_dsp_core.v`

- 从固定 `/130` debug core 演进为可配置 mode core。
- 增加 AXI-Lite 控制面或配套寄存器 wrapper。
- `DECIM_FACTOR` 由 parameter 固定值改为 mode table 或可切换分支。
- `PACKET_LENGTH` 由固定参数改为寄存器或统一 4096。
- 增加 output select：decimated IQ、post-RBW IQ、point power。
- 增加 mode switching busy、configured、error、counter。

## 10. 第一版 bring-up 验证清单

1. `SET_BW` 选择 RBW 后，PS 配置 PL mode。
2. `GET_PROFILE` 显示 `DSP_PATH_PL_DEBUG_IQ_PS_RBW`。
3. `GET_PROFILE` 中 sample rate 与表一致。
4. ILA 确认 `m_axis_tvalid/tready/tlast` 正常。
5. DMA status 计数正常增长，无 `output_drop_count`。
6. PS residual NCO 使用当前 sample rate。
7. 单点 zero span 下，DC/offset 行为与外部频谱仪观测一致。
8. 多点 sweep 下，频率位置正确。
9. 每个 RBW 的 ENBW/FIR 离线参数与 PS 实际使用一致。
10. Flutter 只显示 spectrum point，不直接理解 debug IQ。

## 11. 风险和决策点

- 当前 `1 MSPS complex IQ` 已经证明方向，但不能代表所有 RBW 的最终路径。
- `300 kHz @ 3.25 MSPS` 和 `30 kHz @ 325 kSPS` 需要新的 FIR 参数和 PL 抽取树配合。
- 如果第一版继续用 PS FIR/power，PS 计算压力会随 10 MSPS debug IQ 明显上升；1 MHz RBW 可能需要缩短 observe 或尽快下沉 PL power。
- AXI DMA 简单模式长度仍受 16-bit length 限制，debug IQ frame words 需要保持可控。
- LO settle/第一帧残留风险先作为测试注意项保留，mode switch 后建议丢弃至少一帧。
- 上位机协议可以暂时不改 spectrum point，但 profile/status 必须能说明当前 DSP path。

## 12. 建议实施顺序

1. 冻结 `pl_rbw_mode_config_t` 表字段。
2. 让 FIR agent 输出每个 RBW 的 taps、ENBW、correction、observe、skip。
3. 让 PL 抽取树 agent 输出每个 RBW 的 decim_chain_id 和资源预估。
4. 设计 `pusu_pl_dsp_control.c/h`，先只读写 mode/status。
5. 将 PS 端 `current_decimated_sample_rate_hz` 改为 mode table/status 驱动。
6. 第一版跑通 `PL decimated IQ -> PS RBW FIR/power`。
7. 再逐步把 RBW FIR 和 power accumulation 下沉到 PL。
