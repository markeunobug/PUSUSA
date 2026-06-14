# PuSuSA PL 多级抽取树设计预研

更新日期：2026-06-05

## 1. 目标和边界

本文只预研 PL 侧多级抽取树，不修改固件代码，不替代 FIR 系数离线重算和 PS/PL 接口方案。

已对齐的目标采样率如下：

| RBW mode | 名义 RBW | PL 最终 IQ 采样率 | 总抽取率 |
| --- | ---: | ---: | ---: |
| `RBW_MODE_1M` | 1 MHz | 10 MSPS | 13 |
| `RBW_MODE_300K` | 300 kHz | 3.25 MSPS | 40 |
| `RBW_MODE_100K` | 100 kHz | 1 MSPS | 130 |
| `RBW_MODE_30K` | 30 kHz | 325 kSPS | 400 |
| `RBW_MODE_10K` | 10 kHz | 100 kSPS | 1300 |
| `RBW_MODE_1K` | 1 kHz | 100 kSPS | 1300 |

当前 `pusu_pl_dsp_core.v` 是 bring-up/debug core：

```text
ADC 130 MSPS real
  -> 固定 40 MHz DDC
  -> 简单 /130 accumulator decimation
  -> 1 MSPS packed IQ
  -> AXI DMA
```

它证明了 PL 连续 DDC / DMA IQ 方向，但不能作为最终 RBW 抽取树。最终版本应使用连续 FIR/polyphase decimator，并为 RBW FIR 和 power accumulation 下沉 PL 预留结构。

## 2. 总体推荐：两主干混合共享树

不建议做单一万能抽取链，因为目标倍率包含两组互不整除的主干：

- `/13` 主干：天然得到 10 MSPS，可继续向下得到 `/130` 和 `/1300`。
- `/40` 主干：天然得到 3.25 MSPS，可继续向下得到 `/400`。

推荐第一版采用 DDC 后两条主干，低速子级复用同类模块实例：

```text
ADC 130 MSPS real
  -> PL DDC 40 MHz, complex
      |
      +-- Chain A: /13 -> 10 MSPS
      |       +-- output: 1 MHz RBW
      |       +-- /10 -> 1 MSPS
      |       |       +-- output: 100 kHz RBW
      |       |       +-- /10 -> 100 kSPS
      |       |               +-- output: 10 kHz RBW
      |       |               +-- output: 1 kHz RBW
      |
      +-- Chain B: /40 -> 3.25 MSPS
              +-- output: 300 kHz RBW
              +-- /10 -> 325 kSPS
                      +-- output: 30 kHz RBW
```

这里的“共享”分两层：

1. **流共享**：10 kHz 和 1 kHz 共享 `/1300` 后的 100 kSPS IQ；区别只在后级 RBW ENBW FIR 和 observe/skip/power 参数。
2. **模块共享**：`/10` 子级、halfband 子级、低速 packetizer 可以复用同一 RTL 模板，但在不同主干中各自实例化，避免跨分支状态互相污染。

第一版建议任一时刻只使能当前 RBW 所需主干。未选中的主干保持 reset 或 idle，节省动态功耗，也避免 debug 计数混乱。

## 3. 共享链路 vs 独立分支

| 方案 | 优点 | 缺点 | 结论 |
| --- | --- | --- | --- |
| 五条完全独立分支 | 模式隔离最清楚；每个倍率可单独优化；debug 简单 | DDC 后高码率 fanout 和 FIR 资源最高；重复实现 `/10`、packetizer、状态机；7010 资源风险大 | 不建议作为第一版，仅适合资源充足后的性能版本 |
| 单一 `/1300` 低速链 | 资源最低；10 kHz/1 kHz 直接可用 | 1 MHz、300 kHz、100 kHz、30 kHz 的目标采样率不满足；高 RBW 会被低采样率破坏 | 不可作为最终多 RBW 架构 |
| 单一 `/13` 主干再继续抽取 | 1 MHz、100 kHz、10 kHz、1 kHz 很自然 | 无法整数得到 `/40` 和 `/400`，不能覆盖 300 kHz/30 kHz | 只能覆盖四个模式，不完整 |
| 两主干混合共享树 | 覆盖全部目标倍率；高码率处只有两条主干；低速处复用 `/10` 模板；状态边界清楚 | 需要一个 mode router 和两套主干 reset/计数；比单一链多一些控制逻辑 | 推荐第一版 |

## 4. 各倍率级联方案

### 4.1 `/13`：1 MHz RBW，10 MSPS

推荐：

```text
130 MSPS -> polyphase FIR decimator /13 -> 10 MSPS
```

理由：

- `/13` 不能通过先 `/2` 或 `/5` 共享早期 halfband 得到，否则后级倍率变成非整数。
- 当前 40 MHz NCO LUT 已利用 `40 / 130 = 4 / 13` 的整周期关系；正式版仍应保留确定性的 NCO phase / decimator phase 对齐。
- `/13` 是 Chain A 的根输出，必须优先保证 1 MHz RBW 的抗混叠余量和定点缩放。

工程建议：

- 使用 FIR Compiler 或手写 polyphase FIR decimator。
- 输出位宽建议保持 24 到 32 bit complex，再由后级按模式缩放到 debug I16 或 power accumulator 输入。
- 先不要把 `/13` 做成简单 moving average；它只适合 debug，不适合作为最终抗混叠滤波。

### 4.2 `/40`：300 kHz RBW，3.25 MSPS

推荐第一版：

```text
130 MSPS -> /5 FIR/polyphase -> 26 MSPS
         -> /2 halfband      -> 13 MSPS
         -> /2 halfband      -> 6.5 MSPS
         -> /2 halfband      -> 3.25 MSPS
```

等价倍率为 `5 * 2 * 2 * 2 = 40`。

理由：

- `/5` 先降到 26 MSPS，后续 halfband 都在较低速率运行。
- halfband 适合连续 `/2` 抽取，约一半系数为零，资源效率好。
- 最后一级 6.5 MSPS 到 3.25 MSPS 时，300 kHz RBW 的 5x 检查点接近 Nyquist，需要 FIR agent 给出明确通带/阻带指标，不能由 RBW FIR 临时补救。

备选：

```text
130 MSPS -> /2 -> /2 -> /2 -> /5 -> 3.25 MSPS
```

这个方案高码率部分更依赖 halfband，但最后 `/5` 在 16.25 MSPS 下要完成更窄的抗混叠过渡。它可作为资源/timing 对比备选，不作为第一推荐。

### 4.3 `/130`：100 kHz RBW，1 MSPS

推荐：

```text
130 MSPS -> /13 -> 10 MSPS
         -> /5  -> 2 MSPS
         -> /2  -> 1 MSPS
```

等价倍率为 `13 * 5 * 2 = 130`。

理由：

- 复用 Chain A 的 `/13` 输出。
- 低速 `/5` 和 `/2` 可以做成可复用 `decim10` 子级。
- 现有 1 MSPS debug path 可用于早期对比，但最终 `/130` 子级必须替换简单 accumulator，保证抗混叠和状态连续。

### 4.4 `/400`：30 kHz RBW，325 kSPS

推荐：

```text
130 MSPS -> /40 -> 3.25 MSPS
         -> /5  -> 650 kSPS
         -> /2  -> 325 kSPS
```

等价倍率为 `40 * 5 * 2 = 400`。

理由：

- 复用 Chain B 的 `/40` 输出。
- 30 kHz at 325 kSPS 的 5x RBW 也接近 Nyquist，抽取 FIR 和 RBW FIR 的职责必须分清：抽取 FIR 先保证 alias 不进目标带内，RBW FIR 再定义 ENBW。
- `/40` 后再 `/10` 的低速资源压力较小，适合第一版验证。

### 4.5 `/1300`：10 kHz / 1 kHz RBW，100 kSPS

推荐：

```text
130 MSPS -> /13 -> 10 MSPS
         -> /5  -> 2 MSPS
         -> /2  -> 1 MSPS
         -> /5  -> 200 kSPS
         -> /2  -> 100 kSPS
```

等价倍率为 `13 * 5 * 2 * 5 * 2 = 1300`。

理由：

- 10 kHz 和 1 kHz 共享同一个 100 kSPS decimated IQ。
- 10 kHz/1 kHz 的区别应放在后级 RBW FIR taps、skip、observe、accum target，而不是抽取树重复实现。
- 这是修复 PS DMA block discontinuity 风险的关键路径，必须保证跨 DMA frame 的抽取器内部状态由 PL 连续维护。

## 5. 抽取 FIR 职责边界

抽取 FIR 与 RBW ENBW FIR 不应混为一谈：

| 模块 | 主要职责 | 不能依赖它做什么 |
| --- | --- | --- |
| 多级抽取 FIR/polyphase | 抗混叠、降采样、连续状态维护 | 定义最终 RBW ENBW |
| RBW ENBW FIR | 定义分辨率带宽、输出可校正 ENBW | 替代前级抗混叠 |
| power accumulation | skip/observe、线性功率累加、饱和统计 | 修复前级 alias 或状态断裂 |

因此，FIR agent 冻结 RBW 系数时，应同时拿到本文给出的实际输入采样率；抽取树 agent 则需要为每一级给出 anti-alias 频响、定点量化和群延迟。

## 6. 工程约束

### 6.1 PL 资源

主要资源压力来自两个高码率 decimator：

- Chain A 的 `/13` complex polyphase FIR。
- Chain B 的 `/5 + halfband * 3`。

建议：

1. 第一版只综合当前需要的主干，或用 mode enable 让未选主干保持 idle。
2. complex I/Q 两路滤波可以共享系数，但乘法器通常仍按 I/Q 两路计资源。
3. halfband stage 优先用对称系数和零系数优化。
4. 系数存储、状态 RAM、debug ILA 都要算入资源；ILA 不应成为最终 bitstream 的常驻负担。
5. 如果仍以 7z010 为约束，先做 `/13 -> /130 -> /1300` 四模式链路更稳；如果切到 7z020，再并行加入完整 `/40 -> /400` 主干会更舒服。

### 6.2 时钟域

推荐第一版全部 DSP stage 使用 ADC AXIS 同一 `aclk`，用 `valid` / `ce` 脉冲表示低速采样，不新建派生低速时钟。

理由：

- 避免每一级 decimator 之间的 CDC。
- 便于 ILA 同时观察输入、DDC、decimator valid 和 DMA ready/valid。
- AXI DMA 仍可以看到同一时钟下的稀疏 `m_axis_tvalid`。

AXI-Lite 控制面如果来自 PS FCLK，需要单独做寄存器 CDC：

- mode、output_select、frame_words 等配置在 `mode_update` 握手后同步到 DSP 时钟域。
- status、counter、overflow flags 通过灰码计数器或稳定快照返回 PS 域。
- 第一版如果暂时没有 AXI-Lite，可用常量/AXI GPIO，但模块端口应按最终寄存器方案预留。

### 6.3 AXIS backpressure

ADC 输入不能被下游 DMA 反压破坏。原则是：

```text
ADC -> DDC -> decimator 必须连续消费；
DMA/FIFO 只能影响 debug 输出，不能让前级抽取状态停走。
```

建议：

- `s_axis_tready` 对 ADC 侧保持 ready，或在 RTL 里明确不允许用 DMA ready 停住 ADC 样本。
- decimated IQ 输出前加 skid buffer / small async-safe FIFO。
- debug DMA 满时允许丢 debug IQ，但必须递增 `output_drop_count` 并置 `underflow/drop` flag。
- 最终点功率路径不应依赖大块 IQ DMA ready；PL 内部完成 power accumulation 后通过 AXI-Lite 或小型 result FIFO 给 PS。

### 6.4 Debug DMA 输出点

建议 `OUTPUT_SELECT` 支持以下点位：

| 输出点 | 数据率 | 用途 | 第一版优先级 |
| --- | ---: | --- | --- |
| raw ADC | 130 MSPS real | 只用于短抓取或旧路径对比 | 低 |
| post-DDC IQ | 130 MSPS complex | ILA 优先，DMA 不适合长抓 | 中 |
| post-decimator IQ | 10 MSPS / 3.25 MSPS / 1 MSPS / 325 kSPS / 100 kSPS | 第一版 PS RBW FIR/power 输入，也是主要 debug DMA | 高 |
| post-RBW FIR IQ | 与对应 RBW 输出采样率相同 | 验证 ENBW FIR 和 skip | 中 |
| point power result | 每 sweep point 一个结果 | 最终产品路径 | 第二阶段 |

第一版建议固定输出 post-decimator IQ，继续使用 32-bit packed IQ：

```text
tdata[31:16] = signed I16
tdata[15:0]  = signed Q16
```

但 PS 必须按当前 RBW mode 读取 `sample_rate_hz` 和 `decimation_ratio`，不能继续假设全局 1 MSPS。

### 6.5 跨模式切换清状态

RBW mode switch 必须是显式状态机，不应让 PS 一边按新采样率解释 DMA，一边收旧模式残留。

推荐流程：

```text
PS stop point/sweep
PS disable PL output
PS abort DMA and clear pending IRQ
PS write RBW_MODE / OUTPUT_SELECT / FRAME_WORDS
PS pulse mode_update or soft_reset
PL asserts mode_switch_busy
PL clears selected branch decimator state, RBW FIR state, packetizer, counters as needed
PL loads mode table and selects output tap
PL waits pipeline_flush samples or marks first frame invalid
PL deasserts mode_switch_busy and asserts configured
PS reads SAMPLE_RATE_HZ / DECIMATION_RATIO / VERSION
PS clear_status
PS enable output and start DMA or point measurement
```

清状态建议拆成三类：

| reset 类型 | 清除内容 | 不应清除 |
| --- | --- | --- |
| `clear_status` | debug counter、drop counter、sticky flags | mode、FIR 状态、NCO phase |
| `point_reset` | power accumulator、skip/observe counter、point_done | decimator 长期状态，除非 LO/输入已不连续 |
| `mode_reset` | NCO phase、所有 decimator state、RBW FIR state、packetizer、accumulator | version、只读能力表 |

如果 sweep point 之间 LO 重新锁定或 ADC 流不连续，建议使用 `point_reset` 后丢弃一段 `valid_after_settle`，不要让旧点滤波状态进入新点。

## 7. 推荐第一版 RTL 模块拆分

建议不要直接把当前 `pusu_pl_dsp_core` 扩成一个巨型模块，而是拆成可独立仿真和替换的层级：

```text
pusu_pl_rbw_top
  +-- pusu_pl_rbw_regs_or_ctrl_sync
  +-- pusu_pl_ddc_mixer
  +-- pusu_decim_chain_a_13_130_1300
  |     +-- pusu_decim_fir_p13
  |     +-- pusu_decim_by10_a
  |     +-- pusu_decim_by10_b
  +-- pusu_decim_chain_b_40_400
  |     +-- pusu_decim_fir_p5
  |     +-- pusu_halfband_decim2_x3
  |     +-- pusu_decim_by10_c
  +-- pusu_rbw_output_mux
  +-- pusu_debug_iq_packetizer
  +-- pusu_rbw_fir_bank          (第二阶段)
  +-- pusu_power_accumulator     (第二阶段)
```

各模块职责：

| 模块 | 职责 |
| --- | --- |
| `pusu_pl_rbw_top` | 顶层 AXIS、控制、状态、mode switch，连接两条主干 |
| `pusu_pl_ddc_mixer` | 40 MHz NCO、real-to-complex mixer、定点缩放、DDC debug probe |
| `pusu_decim_chain_a_13_130_1300` | 输出 10 MSPS、1 MSPS、100 kSPS taps |
| `pusu_decim_chain_b_40_400` | 输出 3.25 MSPS、325 kSPS taps |
| `pusu_rbw_output_mux` | 按 RBW mode 选择 decimated IQ、post-RBW IQ 或 point power |
| `pusu_debug_iq_packetizer` | 32-bit packed IQ、frame_words、tlast、drop counter |
| `pusu_rbw_fir_bank` | 每个 RBW 的 ENBW FIR，系数由 FIR agent 冻结 |
| `pusu_power_accumulator` | skip/observe、线性功率累加、overflow、point_done |

## 8. 顶层端口草案

第一版可以先不用完整 AXI-Lite，但顶层端口建议按最终控制面预留：

```verilog
module pusu_pl_rbw_top #(
    parameter integer ADC_WIDTH = 16,
    parameter integer IQ_WIDTH = 24,
    parameter integer DEBUG_AXIS_WIDTH = 32
)(
    input  wire                  aclk,
    input  wire                  aresetn,

    input  wire signed [15:0]    s_axis_adc_tdata,
    input  wire                  s_axis_adc_tvalid,
    output wire                  s_axis_adc_tready,
    input  wire                  s_axis_adc_tlast,
    input  wire                  s_axis_adc_tuser,

    output wire [31:0]           m_axis_debug_tdata,
    output wire                  m_axis_debug_tvalid,
    input  wire                  m_axis_debug_tready,
    output wire                  m_axis_debug_tlast,
    output wire [3:0]            m_axis_debug_tuser,

    input  wire                  cfg_enable,
    input  wire                  cfg_mode_update,
    input  wire                  cfg_soft_reset,
    input  wire                  cfg_clear_status,
    input  wire [2:0]            cfg_rbw_mode,
    input  wire [1:0]            cfg_output_select,
    input  wire [31:0]           cfg_nco_phase_inc,
    input  wire [15:0]           cfg_frame_words,
    input  wire [15:0]           cfg_skip_points,
    input  wire [15:0]           cfg_observe_points,
    input  wire [31:0]           cfg_accum_target,
    input  wire [15:0]           cfg_point_id,
    input  wire                  cfg_start_point,
    input  wire                  cfg_abort_point,

    output wire                  sts_configured,
    output wire                  sts_mode_switch_busy,
    output wire                  sts_point_busy,
    output wire                  sts_point_done,
    output wire                  sts_overflow,
    output wire                  sts_output_drop,
    output wire [31:0]           sts_sample_rate_hz,
    output wire [15:0]           sts_decimation_ratio,
    output wire [31:0]           sts_input_sample_count,
    output wire [31:0]           sts_output_sample_count,
    output wire [31:0]           sts_output_drop_count,
    output wire [31:0]           sts_version
);
```

后续 AXI-Lite wrapper 只需要把寄存器映射到 `cfg_*` 和 `sts_*`，DSP 主体不用关心 PS 总线细节。

## 9. 每个 RBW 的推荐 decim_chain_id

| RBW mode | 输出 tap | decim_chain_id | 总抽取率 | 备注 |
| --- | --- | ---: | ---: | --- |
| `RBW_MODE_1M` | Chain A `/13` | 0 | 13 | 10 MSPS 给 1 MHz RBW FIR |
| `RBW_MODE_300K` | Chain B `/40` | 1 | 40 | 3.25 MSPS，FIR 需重算 |
| `RBW_MODE_100K` | Chain A `/130` | 2 | 130 | 1 MSPS，可对比现有 debug path |
| `RBW_MODE_30K` | Chain B `/400` | 3 | 400 | 325 kSPS，FIR 需重算 |
| `RBW_MODE_10K` | Chain A `/1300` | 4 | 1300 | 100 kSPS，与 1K 共享抽取 IQ |
| `RBW_MODE_1K` | Chain A `/1300` | 4 | 1300 | 100 kSPS，后级 RBW FIR 不同 |

## 10. 第一版实施建议

推荐第一版不要一次把所有功能做满，按下面顺序降低风险：

1. 把当前 `/130` accumulator debug core 替换为 `pusu_pl_rbw_top` 壳，先保留 `/130` 输出行为和 32-bit packed IQ。
2. 加入 mode/status/configured/mode_switch_busy/drop counter，不急着加入所有 FIR。
3. 实现 Chain A：`/13 -> /130 -> /1300`，覆盖 1 MHz、100 kHz、10 kHz、1 kHz。
4. 用 10 kHz zero-span 的 40.000 MHz / 40.100 MHz 场景确认 100 kSPS IQ 连续性和 PS RBW FIR 响应。
5. 再实现 Chain B：`/40 -> /400`，接入 300 kHz 和 30 kHz 的重算 FIR。
6. 最后把 RBW FIR 和 power accumulation 分模式下沉到 PL，debug DMA 退化为诊断路径。

## 11. 关键风险和待冻结项

| 项目 | 风险 | 需要谁继续冻结 |
| --- | --- | --- |
| `/13` polyphase FIR | 高码率 complex FIR 资源和定点缩放风险 | PL 抽取树 + FIR agent |
| `/40` 最后几级过渡带 | 300 kHz 的 5x RBW 接近 Nyquist，30 kHz 类似 | FIR agent 给指标，PL agent 给实现余量 |
| AXIS backpressure | DMA ready 反压会破坏连续 DSP 状态 | PL + PS/PL interface agent |
| mode switch | 旧模式残留被 PS 当成新采样率解释 | PS/PL interface agent |
| 10K/1K 共享 100 kSPS | 抽取 IQ 可共享，但 RBW FIR 和状态不能共享错 | FIR + PL agent |
| debug ILA | 资源、时序和观测点过多 | PL bring-up 阶段逐步裁剪 |

## 12. 预研结论

推荐采用“两主干混合共享树”：

```text
Chain A: /13 -> /130 -> /1300
Chain B: /40 -> /400
```

它是当前目标倍率下最自然的共享结构：既避免五条独立链的资源浪费，又不把 300 kHz/30 kHz 硬塞进无法整数覆盖的 `/13` 主干。第一版应优先让 Chain A 跑通 10 kHz/1 kHz 相关连续性问题，再扩展 Chain B，并始终保持抽取 FIR、RBW ENBW FIR、power accumulation 三者职责清晰。

## 13. 本轮复核后的冻结建议

本轮复核依据：

- `pl_iq_rbw_config_table_2026-06-05.md` 已冻结最终采样率和总抽取率。
- `pl_ddc_decimation_architecture_plan_2026-06-04.md` 已明确生产方向是 PL 连续 DDC / decimation / RBW / power。
- `pl_dsp_bd_integration_steps_2026-06-04.md` 已验证第一版 32-bit packed IQ DMA debug 路径。
- `pusu_pl_dsp_core.v` 当前只是固定 40 MHz DDC + `/130` accumulator debug core，不能作为最终可信 RBW decimator。

最终 PL 抽取树建议冻结为：

```text
ADC 130 MSPS real
  -> DDC 40 MHz complex, same ADC aclk
      |
      +-- Chain A
      |     /13   -> 10 MSPS   -> RBW 1M
      |     /10   -> 1 MSPS    -> RBW 100K
      |     /10   -> 100 kSPS  -> RBW 10K / 1K
      |
      +-- Chain B
            /40   -> 3.25 MSPS -> RBW 300K
            /10   -> 325 kSPS  -> RBW 30K
```

其中 `/10` 建议实现为 `/5 FIR decimator + /2 halfband`，而不是简单平均或 CIC。这样 Chain A 的 `/130`、`/1300` 和 Chain B 的 `/400` 可以复用同一类低速 RTL 模板，但不要共享同一个运行状态实例。

冻结后的级联表：

| 总倍率 | 目标模式 | 推荐级联 | 冻结理由 |
| ---: | --- | --- | --- |
| `/13` | 1 MHz | `/13 polyphase FIR` | 直接得到 10 MSPS；不能从 `/2`、`/5` 主干自然派生；是 Chain A 根节点。 |
| `/40` | 300 kHz | `/5 FIR -> /2 HB -> /2 HB -> /2 HB` | 先把 130 MSPS 降到 26 MSPS，再用 halfband 降速，资源和时序更容易控制。 |
| `/130` | 100 kHz | `/13 -> /5 -> /2` | 复用 Chain A；输出 1 MSPS 可与当前 debug path 对照。 |
| `/400` | 30 kHz | `/40 -> /5 -> /2` | 复用 Chain B；输出 325 kSPS，匹配最终 30 kHz RBW 表。 |
| `/1300` | 10 kHz / 1 kHz | `/13 -> /5 -> /2 -> /5 -> /2` | 10K/1K 共享 100 kSPS IQ，后级 RBW FIR 和 power 参数分开。 |

## 14. 第一版 RTL 落地边界

第一版不建议同时下沉 RBW FIR 和 power accumulation。更稳的边界是：

```text
PL: ADC -> DDC -> per-RBW decimated IQ -> debug DMA
PS: RBW ENBW FIR -> skip/observe -> power -> correction -> UART
```

这样可以先验证两个关键问题：

1. 每个 RBW mode 的 PL 输出采样率是否正确。
2. PS 端按不同 `sample_rate_hz` 解释 IQ 后，RBW FIR / ENBW / power 是否自洽。

第一版 RTL 最小模块集合建议：

| 模块 | 第一版是否需要 | 说明 |
| --- | --- | --- |
| `pusu_pl_rbw_top` | 需要 | 替代当前 debug core 顶层，提供 mode、status、output mux。 |
| `pusu_pl_ddc_mixer` | 需要 | 保留 40 MHz DDC，后续可从 LUT NCO 升级到 programmable phase inc。 |
| `pusu_decim_chain_a` | 优先需要 | 先覆盖 1M / 100K / 10K / 1K。 |
| `pusu_decim_chain_b` | 第二步需要 | 覆盖 300K / 30K，等待 FIR 离线参数确认。 |
| `pusu_debug_iq_packetizer` | 需要 | 输出 32-bit packed IQ 到现有 FIFO/DMA。 |
| `pusu_rbw_fir_bank` | 暂缓 | 第二阶段下沉。 |
| `pusu_power_accumulator` | 暂缓 | 第二阶段下沉，最终替代大块 IQ DMA。 |

## 15. 实施前必须确认的工程规则

1. ADC 输入侧不允许被 DMA backpressure 停住。`s_axis_adc_tready` 不应直接依赖 debug DMA 的 `m_axis_tready`。
2. 下游来不及接收时，允许丢 debug IQ，但必须置位 `output_drop` 并计数；最终 power path 不应丢样。
3. DSP 主体第一版全部跑在 ADC AXIS `aclk`，用 clock-enable/valid pulse 表示低速输出，不新建多个低速时钟。
4. mode switch 必须清 decimator / packetizer / counter 状态，并让 PS 在 `configured=1` 后再启动 DMA。
5. `clear_status` 只清计数和 sticky flag，不应误清正在工作的 FIR state；`mode_reset` 和 `point_reset` 要分开。
6. debug DMA 输出的 `sample_rate_hz`、`decimation_ratio`、`rbw_mode` 必须能被 PS 读取或由 PS 配置表严格推导，不能继续写死 1 MSPS。
7. ILA 只保留 bring-up 必需观测点：DDC I/Q、selected decimator valid、selected IQ、output ready/valid/drop、mode状态。最终 bitstream 应裁剪 ILA。

## 16. 和其他两份预研文档的接口点

与 FIR 离线重算文档的接口：

- 本文只定义抽取输出采样率和级联结构。
- `/13`、`/40`、`/5`、halfband 各级 anti-alias FIR 的通带/阻带指标仍需离线冻结。
- RBW ENBW FIR 只使用本文输出采样率，不承担前级抗混叠职责。

与 PS/PL 接口文档的接口：

- 第一版 DMA 数据仍为 `tdata[31:16]=I16`、`tdata[15:0]=Q16`。
- PS 必须支持 per-RBW DMA sample rate 和 frame length。
- 最终版可切到 AXI-Lite result/status 或小型 result FIFO，debug IQ DMA 退为诊断接口。

## 17. 下一步建议

实际写 RTL 前建议先完成三个冻结动作：

1. FIR 离线任务给出 `/13`、`/40`、`/5`、halfband decimator 的可实现指标和定点量化建议。
2. PS/PL 接口任务冻结 mode switch register、sample rate status、DMA frame words 的字段。
3. RTL 第一轮只实现 `pusu_pl_rbw_top + Chain A + debug packetizer`，先在 10 kHz / 1 kHz 路径上证明连续抽取和多采样率解释正确。
