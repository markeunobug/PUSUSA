# 第一版 PL Decimated IQ 实施计划

更新日期：2026-06-05

## 目标

第一版目标不是一次性把完整 RBW 测量全部搬入 PL，而是先完成一个可验证、可逐步扩展的中间形态：

```text
PL: ADC real -> 40 MHz DDC -> per-RBW continuous decimation -> packed IQ DMA
PS: unpack IQ -> residual correction -> RBW ENBW FIR -> power -> ENBW/amplitude correction
```

这样可以先验证最终采样率层级、PL 连续抽取、DMA 数据解释和 PS 端 RBW 逻辑，再逐步把 RBW FIR 与 power accumulation 下沉到 PL。

## 已冻结输入

### RBW 采样率和 FIR 参数

| RBW | PL 输出 IQ 采样率 | 总抽取率 | RBW FIR taps | 实际 ENBW | PS observe/skip/accum |
| ---: | ---: | ---: | ---: | ---: | --- |
| 1M | 10 MSPS | 13 | 96 | 1.002220 MHz | 384 / 32 / 512 |
| 300K | 3.25 MSPS | 40 | 128 | 313.368 kHz | 384 / 64 / 576 |
| 100K | 1 MSPS | 130 | 128 | 101.478 kHz | 384 / 64 / 576 |
| 30K | 325 kSPS | 400 | 192 | 30.643 kHz | 256 / 128 / 576 |
| 10K | 100 kSPS | 1300 | 256 | 10.090 kHz | 2560 / 128 / 2944 |
| 1K | 100 kSPS | 1300 | 768 | 983.42 Hz | 256 / 128 / 1152 |

离线来源：

```text
docs/rbw_filter_analysis/pl_final_recalc_2026_06_05/pl_final_rbw_selected_parameters.csv
docs/rbw_filter_analysis/pl_final_recalc_2026_06_05/pl_final_rbw_final_coefficients_float.csv
```

### PL 抽取树

采用两主干混合共享树：

```text
Chain A: /13 -> /130 -> /1300
  1M    : /13      -> 10 MSPS
  100K  : /13 /10  -> 1 MSPS
  10K   : /13 /10 /10 -> 100 kSPS
  1K    : /13 /10 /10 -> 100 kSPS

Chain B: /40 -> /400
  300K  : /40      -> 3.25 MSPS
  30K   : /40 /10  -> 325 kSPS
```

`/10` 子级推荐实现为：

```text
/5 FIR/polyphase decimator -> /2 halfband decimator
```

## 第一版 RTL 边界

建议把当前 `pusu_pl_dsp_core.v` 从单一 debug core 演进为以下内部模块，但第一版可以先用同一个源文件或少量子模块实现，等功能稳定后再拆 IP：

| 模块 | 职责 | 第一版要求 |
| --- | --- | --- |
| `pusu_pl_ddc` | 40 MHz NCO/DDC，real ADC 到 complex IQ | 保持连续相位；输出比当前 debug core 更宽的 I/Q 内部位宽。 |
| `pusu_decim_chain_a` | `/13 -> /10 -> /10` 主干 | 支持输出 10 MSPS、1 MSPS、100 kSPS。 |
| `pusu_decim_chain_b` | `/40 -> /10` 主干 | 支持输出 3.25 MSPS、325 kSPS。 |
| `pusu_rbw_mode_router` | 根据 RBW mode 选择输出分支 | 模式切换时禁止输出旧数据。 |
| `pusu_iq_packetizer` | 把内部 IQ 缩放/饱和到 packed I16/Q16 AXIS | 继续使用 `tdata[31:16]=I16`、`tdata[15:0]=Q16`。 |
| `pusu_pl_status` | sample counters、drop counters、mode status | 第一版可先用离散 debug/status 线，后续升级 AXI-Lite。 |

第一版 AXIS 输出仍走：

```text
pusu_pl_dsp_core/M_AXIS -> axis_data_fifo_0/S_AXIS -> axi_dma_0/S_AXIS_S2MM
```

## 模式配置

第一版 PS 需要有一张 PL IQ 路径模式表：

```c
typedef struct {
    rbw_mode_t mode;
    uint32_t pl_sample_rate_hz;
    uint16_t total_decimation;
    uint16_t rbw_fir_taps;
    float actual_enbw_hz;
    float enbw_correction_db;
    uint16_t observe_points;
    uint16_t skip_points;
    uint16_t accum_target;
    uint8_t decim_chain_id;
} pl_iq_rbw_mode_config_t;
```

建议枚举：

```text
decim_chain_id = 0: Chain A /13 output, 10 MSPS
decim_chain_id = 1: Chain A /130 output, 1 MSPS
decim_chain_id = 2: Chain A /1300 output, 100 kSPS
decim_chain_id = 3: Chain B /40 output, 3.25 MSPS
decim_chain_id = 4: Chain B /400 output, 325 kSPS
```

## PS 端第一版修改点

| 文件/模块 | 修改目的 |
| --- | --- |
| `app_config.h` | 用最终 RBW 表替代 PL IQ 路径下的固定 `PL_DSP_DEBUG_IQ_SAMPLE_RATE_HZ=1 MHz`。 |
| `rbw_filter_coeffs.c/h` | 同步最终 30K/300K/10K 系数和 ENBW；10K 必须使用 Scheme B 100 kSPS 系数。 |
| `signal_processing.c/h` | 根据 RBW mode 获取 `pl_sample_rate_hz`，PS RBW FIR 使用对应采样率语义。 |
| `sweep_engine.c` | 每次 RBW/mode 切换时配置 PL 输出采样率和 DMA 采样点需求。 |
| `dma_capture.c/h` | DMA 每样点仍为 4 bytes，但点测量需要的 frame 数随采样率和 accum target 变化。 |
| `device_protocol.c/h` | profile/status 增加 PL RBW mode、sample rate、decimation、data format/version 字段。 |
| `tools/serial_300k_rbw_diagnose.py` | 诊断脚本读取并打印 PL sample rate，不再假设 1 MSPS。 |

## 模式切换流程

第一版必须避免 PS 用新模式解释 PL 旧数据：

```text
PS stop sweep
PS stop/abort DMA
PS disable PL output
PS write or drive rbw_mode / decim_chain_select
PL reset selected chain state and packetizer
PL reports configured/sample_rate/decimation stable
PS configures RBW FIR/observe/skip/accum
PS clear status and discard first debug frame
PS enable PL output
PS start DMA and measurement
```

如果第一版还没有 AXI-Lite 控制面，可以先用 RTL 参数/外部端口和 Vitis 常量做单模式 bring-up；但从多 RBW 开始，建议尽快增加最小 mode/status 寄存器或 GPIO/AXI-Lite 控制，避免每个 RBW 都重新综合。

## 验证顺序

### 1. Chain A bring-up

先做 Chain A，因为它覆盖四个模式，也是当前 `/130 -> 1 MSPS` debug path 的自然延伸：

1. `100K @ 1 MSPS`：与当前已跑通路径对齐，先验证 DMA 和 PS power。
2. `10K @ 100 kSPS`：验证最终 10K Scheme B 系数，重点看 40.100 MHz offset。
3. `1K @ 100 kSPS`：验证窄 RBW 稳定性和 observe 时间。
4. `1M @ 10 MSPS`：验证高吞吐 DMA、FIFO 和 PS 处理负载。

### 2. Chain B bring-up

1. `300K @ 3.25 MSPS`：验证 `/40` 输出、300K 新 FIR。
2. `30K @ 325 kSPS`：验证 `/400` 输出、30K 新 FIR。

### 3. 每个模式的最小实测项

| 测试 | 目的 |
| --- | --- |
| 无输入噪声底 | 检查饱和、NaN、EPSILON floor、DMA 空帧。 |
| 中心频点输入 | 检查峰值幅度和 marker 对齐。 |
| +RBW、+2RBW、+5RBW offset | 检查实际带宽和泄漏。 |
| RBW 切换连续测试 | 检查 mode switch 后是否仍读到旧模式数据。 |
| 长时间连续 sweep | 检查 drop counter、DMA error、输出计数一致性。 |

## 进入代码实现前的冻结条件

可以开始写第一版 RTL/PS 代码的条件：

1. 最终 RBW 配置表已同步 MATLAB 结果。
2. `rbw_filter_coeffs.c` 的目标系数来源已确定。
3. 第一版只承诺输出 decimated IQ，不承诺 PL 端 RBW FIR/power。
4. Mode switch 和 sample rate metadata 必须纳入 PS/PL 接口。
5. 每个 RBW 的测试命令和预期采样率已经写入诊断脚本计划。

