# 子任务 05：下位机增加 1 kHz RBW 能力

## 目标

在当前固件 DSP 链路中增加 `1 kHz RBW` 档位，为相位噪声 `1 kHz offset` 测量提供基本分辨率。此任务只负责 RBW 能力扩展，不实现完整相噪测量引擎。

## 相关文件

主要文件：

- `code/pusu_20260516/vitis/pusu_20260516/src/app_config.h`
- `code/pusu_20260516/vitis/pusu_20260516/src/signal_processing.c`
- `code/pusu_20260516/vitis/pusu_20260516/src/sweep_plan.c`
- `code/pusu_20260516/vitis/pusu_20260516/src/device_protocol.c`
- `code/pusu_20260516/vitis/pusu_20260516/src/main.c`

可能需要同步：

- `host_computer/flutter_pusu/lib/main.dart`
- `host_computer/flutter_pusu/lib/serial_protocol.dart`

## 当前背景

当前 RBW 档位：

```text
10 kHz
30 kHz
100 kHz
300 kHz
1 MHz
```

当前普通扫频步进：

```text
step = RBW / 2
```

因此当前最小步进为 `5 kHz`，无法可信覆盖 `1 kHz offset`。

## 实现要求

1. 新增枚举

建议将 `RBW_MODE_1K` 加到 `rbw_mode_t` 中。注意这会影响现有模式编码，必须谨慎：

方案 A：在最前面插入：

```c
RBW_MODE_1K = 0,
RBW_MODE_10K = 1,
...
```

缺点：会改变现有 host 编码。

方案 B：追加到最后：

```c
RBW_MODE_1K = 5
```

优点：不破坏现有 host 编码。推荐方案 B。

2. 新增参数

在 `app_config.h` 增加：

```c
#define RBW_1K_HZ ...
#define RBW_1K_CIC_R ...
#define RBW_1K_CIC_N ...
#define RBW_1K_FIR_TAPS ...
#define RBW_1K_OBSERVE_POINTS ...
#define RBW_1K_SKIP_POINTS ...
```

参数需要根据 ADC rate、CIC 输出采样率、FIR 成本和 buffer 限制设计。不能随便照抄 10K。

3. 更新 DSP 配置表

更新 `signal_processing.c`：

- `get_rbw_config()`
- `get_rbw_skip_points()`
- `rbw_mode_name()`
- `rbw_mode_cutoff_hz()`

注意如果 `RBW_MODE_1K = 5`，不能继续用 `table[(int)mode]` 假设连续 0..N。需要改成 switch 或保证表索引安全。

4. 更新协议 sanitize

更新 `device_protocol.c`：

- `sanitize_rbw_mode()`
- `rbw_mode_to_hz()`

5. 更新主循环 RBW 检查

当前 `main.c` 有类似：

```c
if (requested_mode > RBW_MODE_1M) ...
```

如果追加 `RBW_MODE_1K = 5`，这个判断会错误拒绝 1K，需要改成显式合法性检查。

6. 上位机可见

上位机 RBW 下拉可以先不开放给普通频谱模式，但相噪模式需要能请求 `1 kHz RBW`。

## 验收标准

- 固件编译不因枚举和表索引出错。
- `RBW_MODE_1K` 不破坏现有 10K/30K/100K/300K/1M 编码。
- 普通频谱模式原有 RBW 仍可正常映射。
- 代码中没有危险的 `table[(int)mode]` 越界。
- 如无法完成实机测试，必须给出参数计算依据和风险。

## 非目标

- 不实现相噪专用 offset 扫描。
- 不新增 `PHASE_NOISE_DATA`。
- 不做 UI。

