# PuSuSA PL/PS RBW Interface Plan

更新日期：2026-06-05

## 1. 目标和边界

本文定义 PL RBW 最终方案第一版 PS/PL 控制接口和 PS 端迁移边界，不修改固件代码，不替代 FIR agent 和 PL 抽取树 agent 的详细设计。

已知最终采样率固定为：

| RBW mode | 当前 `rbw_mode_t` 值 | 名义 RBW | PL 输出测量采样率 | 总抽取率 |
| --- | ---: | ---: | ---: | ---: |
| `RBW_MODE_1M` | 4 | 1 MHz | 10 MSPS | 13 |
| `RBW_MODE_300K` | 3 | 300 kHz | 3.25 MSPS | 40 |
| `RBW_MODE_100K` | 2 | 100 kHz | 1 MSPS | 130 |
| `RBW_MODE_30K` | 1 | 30 kHz | 325 kSPS | 400 |
| `RBW_MODE_10K` | 0 | 10 kHz | 100 kSPS | 1300 |
| `RBW_MODE_1K` | 5 | 1 kHz | 100 kSPS | 1300 |

当前 `pusu_pl_dsp_core.v` 仍是 bring-up/debug core：固定 40 MHz DDC、固定 `/130`、输出 `1 MSPS` packed IQ。它证明 PL 连续链路方向，但不能作为最终多 RBW 接口的固定假设。

## 2. 第一版接口定义

第一版接口建议按“PL decimated IQ + PS RBW FIR/power”落地，同时为后续“PL RBW FIR/power”预留字段。

### 2.1 模式和输出选择

PS 内部先冻结一张模式表：

```c
typedef enum {
    PL_RBW_OUTPUT_DECIM_IQ      = 0,
    PL_RBW_OUTPUT_POST_RBW_IQ   = 1,
    PL_RBW_OUTPUT_POINT_POWER   = 2,
    PL_RBW_OUTPUT_DISABLED      = 3
} pl_rbw_output_select_t;

typedef struct {
    rbw_mode_t rbw_mode;
    uint32_t nominal_rbw_hz;
    uint32_t pl_sample_rate_hz;
    uint16_t total_decimation;
    uint16_t decim_chain_id;
    uint16_t rbw_fir_taps;
    uint16_t skip_points;
    uint16_t observe_points;
    uint16_t accum_target;
    float actual_enbw_hz;
    float enbw_correction_db;
    pl_rbw_output_select_t output_select;
    uint8_t pl_decim_enabled;
    uint8_t pl_rbw_fir_enabled;
    uint8_t pl_power_enabled;
} pl_rbw_mode_config_t;
```

第一版固定策略：

- `pl_decim_enabled = 1`
- `pl_rbw_fir_enabled = 0`
- `pl_power_enabled = 0`
- `output_select = PL_RBW_OUTPUT_DECIM_IQ`

后续逐模式打开 `PL_RBW_OUTPUT_POST_RBW_IQ` 和 `PL_RBW_OUTPUT_POINT_POWER`。

### 2.2 最小控制/状态字段

建议第一版至少具备以下控制和状态语义：

| 字段 | 方向 | 必选 | 语义 |
| --- | --- | --- | --- |
| `enable` | PS -> PL | 是 | 允许 PL DSP 输出；为 0 时 PL 不产生新的 AXIS output。 |
| `soft_reset` / `mode_update` | PS -> PL | 是 | 重置 NCO、decimator、RBW FIR、power accumulator 状态，并装载新 mode。 |
| `clear_status` | PS -> PL | 是 | 只清 debug counter、sticky error、done flag；不改变 mode，也不重置滤波器状态。 |
| `rbw_mode` | PS -> PL | 是 | 与当前 `rbw_mode_t` 数值对齐，避免 `SET_BW` 再做一层重映射。 |
| `output_select` | PS -> PL | 是 | 选择 decimated IQ、post-RBW IQ、point power 或 disabled。 |
| `frame_words` | PS -> PL | 建议 | debug IQ DMA 每帧 complex word 数，默认 4096。 |
| `point_id` | PS -> PL | 建议 | 当前 sweep point index，用于 profile/debug 对账。 |
| `observe_points` / `skip_points` / `accum_target` | PS -> PL | 预留 | PL power 阶段使用；第一版可只写入并回读。 |
| `residual_freq_hz_q16` | PS -> PL | 可选 | residual NCO 下沉 PL 时使用；第一版 residual 可继续在 PS。 |
| `sample_rate_hz` | PL -> PS | 是 | 当前输出 IQ 或内部测量采样率，必须与 mode 表一致。 |
| `decimation_ratio` | PL -> PS | 是 | 当前总抽取率，必须与 mode 表一致。 |
| `status` | PL -> PS | 是 | `configured`、`mode_switch_busy`、`point_busy`、`point_done`、`overflow`、`error` 等。 |
| `debug counters` | PL -> PS | 是 | input/output/drop/count、last I/Q、decim count、point done count。 |
| `version` | PL -> PS | 是 | IP version 和 data format version。 |

### 2.3 建议 AXI-Lite 寄存器图

| Offset | 名称 | 方向 | 第一版说明 |
| ---: | --- | --- | --- |
| `0x00` | `CONTROL` | W/R | bit0 `enable`，bit1 `soft_reset`，bit2 `clear_status`，bit3 `start_point`，bit4 `abort_point`。 |
| `0x04` | `STATUS` | R | bit0 `idle`，bit1 `configured`，bit2 `mode_switch_busy`，bit3 `point_busy`，bit4 `point_done`，bit5 `overflow`，bit6 `drop_seen`，bit7 `error`。 |
| `0x08` | `RBW_MODE` | W/R | 直接写当前 `rbw_mode_t` 值。 |
| `0x0C` | `OUTPUT_SELECT` | W/R | `PL_RBW_OUTPUT_*`。 |
| `0x10` | `SAMPLE_RATE_HZ` | R | 10M / 3.25M / 1M / 325k / 100k。 |
| `0x14` | `DECIMATION_RATIO` | R | 13 / 40 / 130 / 400 / 1300。 |
| `0x18` | `FRAME_WORDS` | W/R | debug IQ DMA 帧长，默认 4096。 |
| `0x1C` | `POINT_ID` | W/R | 当前 sweep point index。 |
| `0x20` | `RESIDUAL_FREQ_HZ_Q16` | W/R | 可选 residual NCO 控制。 |
| `0x24` | `OBSERVE_POINTS` | W/R | PL power 阶段测量窗口。 |
| `0x28` | `SKIP_POINTS` | W/R | PL power 阶段 transient skip。 |
| `0x2C` | `ACCUM_TARGET` | W/R | PL power 阶段累计目标。 |
| `0x30` | `INPUT_SAMPLE_COUNT` | R | ADC 输入样本计数。 |
| `0x34` | `OUTPUT_SAMPLE_COUNT` | R | 当前输出 IQ 或内部输出计数。 |
| `0x38` | `OUTPUT_DROP_COUNT` | R | AXIS backpressure/drop 计数。 |
| `0x3C` | `POINT_DONE_COUNT` | R | 点测量完成计数。 |
| `0x40` | `ERROR_CODE` | R | 最近错误码。 |
| `0x44` | `POWER_DBFS_Q8_24` | R | PL point power 阶段使用。 |
| `0x48` | `POWER_LINEAR_HI` | R | 可选线性功率累加高 32 bit。 |
| `0x4C` | `POWER_LINEAR_LO` | R | 可选线性功率累加低 32 bit。 |
| `0x50` | `VERSION` | R | IP/data format version。 |

第一版必须实现到 `VERSION` 之前的 mode/status/counter/status readback；点功率寄存器可以先保留为 0 或未实现。

## 3. AXI-Lite vs GPIO/固定参数

### 3.1 简单 GPIO/固定参数

优点：

- 适合当前 bring-up：`enable=1`、`clear_status=0`、`DECIM_FACTOR=130`、`PACKET_LENGTH=4096`。
- BD 代价低，不需要先写 AXI-Lite slave。
- 对 DDC 方向、AXIS 32-bit packed IQ、DMA 是否丢样的验证足够。

缺点：

- 无法可靠表达 6 个 RBW mode 的采样率和总抽取率。
- PS 无法读回 `sample_rate_hz`、`decimation_ratio`、`version`，只能相信编译期宏。
- `clear_status`、`soft_reset`、`mode_update` 很容易混在一起，切模式时风险大。
- 不能给串口诊断脚本提供当前 PL path/status，容易把 debug path 误判为最终 RBW。

### 3.2 AXI-Lite 寄存器

优点：

- mode、output select、frame words、residual、observe/skip/accum 可以统一配置。
- PS 可以读回采样率、抽取率、版本、drop/overflow 计数，诊断脚本有真实依据。
- 支持明确 mode switching handshake，避免 DMA 旧模式数据被新模式解释。
- 自然支持后续 PL point power 和低速 result path。

缺点：

- 第一版 RTL/BD 工作量更高。
- 需要定义寄存器复位值、写脉冲语义、跨时钟域处理和 profile/status 编码。

### 3.3 阶段性推荐

当前固定 `/130` DDC debug core 可以继续用常量脚完成 DDC/AXIS bring-up；但一旦要进入“最终采样率表”的多 RBW 验证，就应切到最小 AXI-Lite wrapper。

不建议用纯 AXI GPIO 承载多 RBW 控制。GPIO 可作为过渡方案驱动 `enable/clear_status/rbw_mode[2:0]`，但它不适合承载可读状态、版本、计数器、采样率和点功率。阶段性推荐是：

1. DDC 方向验证：固定参数或 GPIO。
2. 多 RBW decimated IQ 验证：最小 AXI-Lite。
3. PL RBW FIR/power：AXI-Lite result registers，必要时再加小型 AXIS result FIFO。

## 4. PS 端同步修改逻辑

### 4.1 `app_config.h`

- `PL_DSP_DEBUG_IQ_SAMPLE_RATE_HZ` 不能继续作为全局固定 `1 MHz`。第一版可保留默认值，但实际测量必须来自 `pl_rbw_mode_config_t` 或 PL `SAMPLE_RATE_HZ`。
- `DMA_STREAM_BYTES_PER_SAMPLE` 应按 data path 定义：legacy raw ADC 为 2 bytes，PL debug IQ 为 4 bytes，PL point power 不走大块 IQ DMA。
- 旧 `RBW_*_CIC_R` 不再作为最终 PL RBW 依据；最终表应使用 13、40、130、400、1300、1300。特别是 300K 不再是 43，30K 不再是 433，10K 最终不再是 130。
- 300K 和 30K 的 FIR/ENBW/observe/skip 在最终表中仍是待冻结项，PS 表应允许 TBD 或 compile-time guard，不要沿用旧 Scheme B 参数冒充最终结果。

### 4.2 `dma_capture.c/h`

- 第一版 PL debug IQ 仍用 S2MM simple transfer，`transfer_bytes = frame_words * 4`。
- `dma_capture_bytes_for_samples()` 需要避免把“sample_count”理解成 raw ADC sample；在 PL debug IQ 下它是 complex IQ word 数。
- 继续遵守 `DMA_SIMPLE_MAX_BYTES = 65535`，4096 words * 4 = 16384 bytes 是安全帧长。
- 多帧 simple transfer 仍不建议作为默认测量方式；保留当前单帧 rearm，更容易观察 drop、first frame 和 settle 问题。

### 4.3 `signal_processing.c/h`

- 第一版输入已经是 PL decimated complex IQ，PS 应跳过 legacy DDC/CIC，只做 residual NCO、RBW ENBW FIR、skip/observe、power。
- `current_decimated_sample_rate_hz` 必须由当前 PL mode/status 驱动，用于 residual NCO phase step、`measure_complex_peak_dbfs()`、FIR/ENBW 解释。
- `pl_debug_apply_residual_nco()` 不能继续使用固定 `PL_DSP_DEBUG_IQ_SAMPLE_RATE_HZ`。
- `get_rbw_config()` 需要拆成 legacy PS config 和 PL RBW config，避免 CIC 参数污染最终 PL 路径。
- 最终 PL power 阶段新增“直接接受 PL `POWER_DBFS_Q8_24` 或 linear accumulator”的路径，绕过 PS FIR/power，只保留 dBFS/dBm 和 amplitude correction 的统一转换点。

### 4.4 `sweep_engine.c`

第一版继续沿用当前状态机外壳：

```text
configure PL RBW mode
-> set LO
-> wait LO lock / settle
-> arm DMA
-> discard first frame if needed
-> accumulate PL IQ frames
-> PS FIR/power
-> amplitude correction
-> emit spectrum point
```

需要新增的行为：

- `SWEEP_ENGINE_STATE_PREPARE` 或 RBW 变化时先配置 PL mode，读回 sample rate/decim/version。
- mode switch 后清 DMA pending IRQ，并丢弃至少一帧 debug IQ，或等待 PL 给出 `valid_after_mode_switch`。
- `clear_status` 用于清计数器，不替代 mode switch reset。
- 最终 PL point power 阶段状态机改为 `start_point -> wait point_done -> read power -> emit point`，DMA 只作为 debug IQ capture。

### 4.5 `device_protocol.c/h`

- `SET_BW` 继续承载 RBW mode，不建议改变已有命令含义。
- `SPECTRUM_DATA` 点格式保持不变，Flutter 仍只消费频率和点功率。
- `GET_PROFILE` 增加 PL metadata extension，建议 magic 为 `PLRB`，至少包含：
  - `dsp_data_path`
  - `pl_output_select`
  - `pl_rbw_mode`
  - `pl_sample_rate_hz`
  - `pl_decimation_ratio`
  - `pl_status`
  - `pl_error_code`
  - `pl_input_sample_count`
  - `pl_output_sample_count`
  - `pl_output_drop_count`
  - `pl_version`
- `GET_STATUS` 可以追加或另设 PL status 命令，但不建议破坏现有 59-byte status payload 的解析兼容；更稳妥是先走 `GET_PROFILE` 扩展。

### 4.6 `pusu_pl_dsp_core.v`

- 从参数固定 `DECIM_FACTOR/PACKET_LENGTH` 演进为 mode table 或寄存器驱动。
- 保留当前 debug counter：`dbg_input_sample_count`、`dbg_output_sample_count`、`dbg_output_drop_count`、`dbg_last_i/q`、`dbg_nco_phase`、`dbg_decim_count`。
- 增加 `mode_switch_busy/configured/error/version`。
- 输出 `m_axis_tuser` 建议至少标注 `debug_path`、`mode_first_frame`、`sample_saturated`，帮助 PS 丢弃首帧和定位饱和。

## 5. 模式切换握手

推荐 PS 端流程：

```text
stop sweep / stop point
disable PL output
abort or reset DMA, clear pending IRQ
write RBW_MODE, OUTPUT_SELECT, FRAME_WORDS, POINT_ID
pulse soft_reset or mode_update
wait mode_switch_busy = 0 and configured = 1
read SAMPLE_RATE_HZ, DECIMATION_RATIO, VERSION
check against PS mode table
configure PS DMA bytes/sample, FIR, residual NCO sample rate
clear_status
enable PL output
discard first debug frame or wait valid_after_mode_switch
start point measurement
```

约束：

- `mode_switch_busy=1` 时 PL 不应产生新的 `m_axis_tvalid`。
- `configured=1` 后 `SAMPLE_RATE_HZ`、`DECIMATION_RATIO`、`OUTPUT_SELECT` 必须稳定。
- `clear_status` 不改变 mode，不清 FIR/decimator 状态。
- `soft_reset/mode_update` 才清 NCO、decimator、FIR、power accumulator 状态。
- LO 切换后的 settle 仍保留；PL 连续抽取解决 DMA block discontinuity，不自动解决 LO 切换带来的瞬态。

## 6. 串口诊断脚本和上位机兼容迁移

### 6.1 兼容原则

- 不改 `SPECTRUM_DATA` 主格式，避免 Flutter 频谱显示大改。
- 不让 Flutter 直接理解 debug IQ；debug IQ 只用于固件、ILA、串口诊断脚本。
- 用 `GET_PROFILE` 扩展声明当前 DSP path，让脚本和上位机知道数据来源。

建议 DSP path 枚举：

```c
typedef enum {
    DSP_PATH_LEGACY_PS_DDC_CIC = 0,
    DSP_PATH_PL_DEBUG_IQ_PS_RBW = 1,
    DSP_PATH_PL_FINAL_POWER = 2
} dsp_data_path_t;
```

### 6.2 `serial_300k_rbw_diagnose.py`

脚本迁移建议：

- 保持 `SET_BW`、`GET_STATUS`、`GET_PROFILE`、`GET_SPECTRUM` 命令顺序。
- 在 `PROFILE` 解析中追加 `PLRB` extension，打印 `dsp_data_path`、`pl_output_select`、`pl_sample_rate_hz`、`pl_decimation_ratio`、`pl_status`、`pl_drop_count`。
- 按 RBW 自动检查期望采样率：
  - 1M -> 10,000,000
  - 300K -> 3,250,000
  - 100K -> 1,000,000
  - 30K -> 325,000
  - 10K/1K -> 100,000
- 当 `dsp_data_path=PL_DEBUG_IQ_PS_RBW` 时，在 summary 中明确标记“PL debug IQ + PS RBW，不是最终 PL point power”。
- 继续保留现有 `DSP_PEAK`/DDC debug 解析，因为它对确认 pre/post RBW 问题位置仍然有价值。

### 6.3 Flutter/上位机显示

- 第一阶段只显示普通 spectrum point，不新增 UI 依赖。
- 若读取到 `dsp_data_path=PL_DEBUG_IQ_PS_RBW`，可在隐藏诊断区或状态栏标注“PL debug path”。
- 只有 `DSP_PATH_PL_FINAL_POWER` 且 `pl_status.error=0` 时，才标注为最终 PL RBW。

## 7. 关键风险和检查点

| 风险 | 检查点 |
| --- | --- |
| PS 把旧模式 DMA 数据按新模式解释 | 必须有 mode switch handshake，并丢弃首帧或等待 `valid_after_mode_switch`。 |
| 采样率仍固定 1 MHz | `GET_PROFILE` 必须能读回 `pl_sample_rate_hz`，PS residual NCO 和 peak debug 使用该值。 |
| 300K/30K 沿用旧 FIR | mode table 标注 TBD，等 FIR agent 冻结后再放开最终可信标志。 |
| AXIS backpressure 破坏连续性 | `OUTPUT_DROP_COUNT` 必须进入 profile，非 0 时该点无效。 |
| debug path 被误认为最终 RBW | 增加 `dsp_data_path`，Flutter 只消费 spectrum point，诊断脚本打印路径。 |
| clear/reset 语义混用 | 文档和接口中区分 `clear_status` 与 `soft_reset/mode_update`。 |

## 8. 推荐实施顺序

1. 保留当前固定 `/130` core 完成 1 MSPS DDC bring-up。
2. 新增最小 AXI-Lite wrapper，实现 `CONTROL/STATUS/RBW_MODE/OUTPUT_SELECT/SAMPLE_RATE_HZ/DECIMATION_RATIO/*COUNT/VERSION`。
3. PS 新增 `pl_rbw_mode_config_t`，先只配置并读回 PL mode/status。
4. 把 `current_decimated_sample_rate_hz`、DMA bytes/sample、residual NCO sample rate 改为 mode/status 驱动。
5. 按最终采样率表验证 `PL decimated IQ -> PS RBW FIR/power`。
6. 串口 `GET_PROFILE` 增加 `PLRB` extension，诊断脚本解析并校验 sample rate。
7. FIR 和 PL 抽取树冻结后，逐模式下沉 RBW FIR。
8. PL power accumulation 稳定后，切到 AXI-Lite point result；如连续扫频吞吐需要，再评估小型 AXIS result FIFO。

