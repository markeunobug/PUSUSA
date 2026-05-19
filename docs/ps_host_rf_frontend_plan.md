# PS 端与上位机射频前端控制开发计划

本文档用于规划在已完成 PL 底层修改后，继续开发 PS 端驱动和上位机控制能力。目标是让上位机能够可靠控制射频前端关键状态，包括是否经过 LNA、PE43711B-Z 衰减值、走两级混频路径还是直通路径，并为后续本振、VGA、ADC 控制统一留出接口。

## 1. 开发目标

### 1.1 必须实现

- 上位机可以设置 LNA 选择：直通或经过 LNA。
- 上位机可以设置 PE43711B-Z 射频衰减值，范围 `0 dB` 到 `31.75 dB`，步进 `0.25 dB`。
- 上位机可以选择信号路径：前端直通到中频，或进入衰减器和两级混频链路。
- PS 端负责校验开关组合，禁止无效或危险组合直接写入硬件。
- PS 端保留当前射频前端状态，并能通过状态查询返回给上位机。
- 上位机 UI 中显示当前 RF 前端配置，并在用户修改后发送到 PS 端。

### 1.2 后续扩展

- 将 `LMX2572_1`、`LMX2572_2` 的本振配置与混频路径选择联动。
- 将 `LMX2572_0` ADC 时钟 PLL 初始化纳入上电流程。
- 将 AD8370 中频 VGA 增益与前端衰减、参考电平联动。
- 将 LTC2208 的 `PGA/SHDN/DITH/RAND` 控制纳入状态页或调试页。
- 增加自动衰减、自动前放和过载保护策略。

## 2. 当前硬件控制面

依据 [hardware_changes.md](/C:/learning/pusu_V2/docs/hardware_changes.md)，RF 前端建议由 `axi_gpio_2` 暴露为 8 bit 输出：

| bit | 信号 | 用途 |
|---:|---|---|
| 0 | `SW1_CTL` | 第一处 HMC849，输入直通或 LNA 输入选择 |
| 1 | `SW2_CTL` | 第二处 HMC849，直通或 LNA 输出选择 |
| 2 | `SW3_CTL` | 第三处 HMC849，直通中频或混频链路入口选择 |
| 3 | `SW4_A` | HMC544AETR 控制 A |
| 4 | `SW4_B` | HMC544AETR 控制 B |
| 5 | `DSA_CLK` | PE43711B-Z 串行时钟 |
| 6 | `DSA_SI` | PE43711B-Z 串行数据 |
| 7 | `DSA_LE` | PE43711B-Z 锁存 |

开关组合建议由 PS 端抽象为两个独立维度：

| 控制维度 | 用户语义 | 硬件组合 |
|---|---|---|
| 输入前端 | `bypass_lna` | `SW1_CTL=1, SW2_CTL=0` |
| 输入前端 | `use_lna` | `SW1_CTL=0, SW2_CTL=1` |
| 后级路径 | `direct_if` | `SW3_CTL=1, SW4_A=1, SW4_B=0` |
| 后级路径 | `mixer_chain` | `SW3_CTL=0, SW4_A=0, SW4_B=1` |

PE43711B-Z 衰减器控制字：

| 项目 | 计划值 |
|---|---|
| 控制字长度 | `8 bit` |
| 位序 | `LSB first` |
| 步进 | `0.25 dB/code` |
| 可设置范围 | `0 dB` 到 `31.75 dB` |
| 有效控制位 | `D6:D0` |
| 保留位 | `D7=0` |
| 上电默认 | 建议先写入 `31.75 dB`，再按用户配置切换 |

## 3. PS 端开发计划

### 3.1 第一步：导入新硬件平台并校验 BSP

1. 从已修改完成的 Vivado 工程重新导出 XSA。
2. 在 Vitis 中更新 platform/BSP。
3. 检查 `xparameters.h` 是否存在新的 GPIO 设备：
   - `XPAR_AXI_GPIO_2_DEVICE_ID` 或对应 `GPIO_RF_FRONTEND` 设备 ID。
   - 若 PL 中已新增 `axi_gpio_3`，确认 `GPIO_LTC2208_CTRL` 设备 ID。
4. 更新 [app_config.h](/C:/learning/pusu_V2/code/pusu_20260516/vitis/pusu_20260516/src/app_config.h)，让软件宏与实际 XSA 保持一致。

注意：当前 PS 代码中的 `app_config.h` 仍可见旧式 LTC2208 控制 mask 挂在 `AD8370_GPIO_DEVICE_ID` 后面。后续实现前必须以新导出的 BSP 为准重新核对 GPIO 分配。

### 3.2 第二步：新增 RF 前端驱动模块

建议新增：

- `rf_frontend.h`
- `rf_frontend.c`

模块职责：

- 初始化 `axi_gpio_2`，设置方向为输出。
- 维护 RF 前端 GPIO 输出影子寄存器，避免 DSA 串行时序改变开关位。
- 提供 LNA 选择 API。
- 提供直通/混频路径选择 API。
- 提供 PE43711B-Z 衰减值写入 API。
- 提供当前状态查询 API。

建议公开接口：

```c
typedef enum {
    RF_LNA_BYPASS = 0,
    RF_LNA_ENABLE = 1
} rf_lna_mode_t;

typedef enum {
    RF_PATH_DIRECT_IF = 0,
    RF_PATH_MIXER_CHAIN = 1
} rf_path_mode_t;

typedef struct {
    rf_lna_mode_t lna_mode;
    rf_path_mode_t path_mode;
    uint8_t atten_code;      /* 0..127, 0.25 dB/step */
    float atten_db;          /* cached display value */
} rf_frontend_state_t;

int rf_frontend_init(void);
int rf_frontend_set_lna_mode(rf_lna_mode_t mode);
int rf_frontend_set_path_mode(rf_path_mode_t mode);
int rf_frontend_set_atten_db(float atten_db);
int rf_frontend_apply(const rf_frontend_state_t *state);
const rf_frontend_state_t *rf_frontend_get_state(void);
```

### 3.3 第三步：定义安全默认状态

上电和复位后的建议顺序：

1. 初始化 GPIO，先保持全部输出为可控状态。
2. 设置 RF 前端为高保护状态：
   - `LNA bypass`
   - `mixer_chain` 或按调试阶段选择 `direct_if`
   - `atten=31.75 dB`
3. 初始化 `LMX2572_0`，等待 ADC 时钟 PLL 锁定。
4. 初始化 `LMX2572_1/2`，仅在需要混频路径时使能并配置。
5. 初始化 AD8370 VGA 到保守增益。
6. 启动采集、扫频和上位机协议服务。

调试早期可以固定 `direct_if + 31.75 dB`，确认开关和衰减器可控后再打开混频链路。

### 3.4 第四步：协议层接入

当前 [device_protocol.c](/C:/learning/pusu_V2/code/pusu_20260516/vitis/pusu_20260516/src/device_protocol.c) 已有：

- `CMD_SET_AMPLITUDE = 0x02`
- `CMD_GET_STATUS = 0x07`
- `CMD_SET_VGA_GAIN = 0x0B`

建议新增专用命令，避免把“仪表参考电平”和“硬件 RF 路径”揉在一起：

| 命令 | 方向 | 名称 | Payload | 说明 |
|---:|---|---|---|---|
| `0x0C` | Host -> PS | `SET_RF_FRONTEND` | `lna_mode(1B) + path_mode(1B) + atten_code(1B) + flags(1B)` | 设置 RF 前端 |
| `0x0D` | Host -> PS | `GET_RF_FRONTEND` | 无 | 查询 RF 前端当前状态 |
| `0x84` | PS -> Host | `RF_FRONTEND_STATUS` | `lna_mode(1B) + path_mode(1B) + atten_code(1B) + applied_gpio(1B) + error(1B)` | 返回当前状态 |

字段建议：

| 字段 | 编码 |
|---|---|
| `lna_mode` | `0=bypass`, `1=enable`, `2=auto-reserved` |
| `path_mode` | `0=direct_if`, `1=mixer_chain`, `2=auto-reserved` |
| `atten_code` | `0..127`，实际衰减 `code * 0.25 dB` |
| `flags.bit0` | `1=apply_immediately`，先保留，默认置 1 |
| `applied_gpio` | 当前 `axi_gpio_2` 输出影子值 |
| `error` | `0=OK`，非 0 表示参数或硬件错误 |

后续可以让现有 `CMD_SET_AMPLITUDE(0x02)` 继续表示仪表级幅度设置；当上位机选择“自动衰减/自动前放”时，由 PS 端策略层把它转换为 `rf_frontend` 状态。

### 3.5 第五步：状态查询扩展

短期可以通过新增 `RF_FRONTEND_STATUS(0x84)` 返回 RF 状态。长期可以扩展 `STATUS_DATA(0x83)`，但需要同步修改上位机解析和文档，避免旧上位机误解析。

建议先采用独立状态帧，风险更低。

## 4. 上位机开发计划

### 4.1 数据模型

在 Flutter 上位机中新增 RF 前端配置模型：

```dart
enum RfLnaMode { bypass, enable, auto }
enum RfPathMode { directIf, mixerChain, auto }

class RfFrontendConfig {
  final RfLnaMode lnaMode;
  final RfPathMode pathMode;
  final int attenCode; // 0..127
}
```

显示值转换：

| UI 显示 | 协议值 |
|---|---|
| LNA 关闭/直通 | `lna_mode=0` |
| LNA 打开 | `lna_mode=1` |
| 直通路径 | `path_mode=0` |
| 混频路径 | `path_mode=1` |
| `x.xx dB` | `atten_code = round(x.xx / 0.25)` |

### 4.2 UI 控件

建议在现有幅度/前端控制区域增加：

- LNA：分段按钮或开关，`直通 / LNA`。
- 路径：分段按钮，`直通 IF / 两级混频`。
- 衰减：下拉或步进输入，范围 `0..31.75 dB`，步进 `0.25 dB`。
- 状态显示：显示最近一次 ACK、实际应用值和错误状态。

UI 上可以保留“自动”选项，但第一阶段先禁用或标记为后续策略，底层先实现手动可控。

### 4.3 串口协议实现

在 [serial_protocol.dart](/C:/learning/pusu_V2/host_computer/flutter_pusu/lib/serial_protocol.dart) 中新增：

- `setRfFrontend(RfFrontendConfig config)`
- `getRfFrontendStatus()`
- `parseRfFrontendStatus(...)`

在 [serial_port_manager.dart](/C:/learning/pusu_V2/host_computer/flutter_pusu/lib/serial_port_manager.dart) 或状态管理处新增：

- RF 配置发送节流，避免滑动衰减器时连续轰炸串口。
- ACK 和状态帧回显处理。
- 连接后主动查询 RF 前端状态，并同步 UI。

## 5. 联调步骤

### 5.1 GPIO 静态验证

1. 烧录新 bitstream 和 PS 程序。
2. 用示波器或逻辑分析仪检查 `SW1_CTL/SW2_CTL/SW3_CTL/SW4_A/SW4_B`。
3. 逐个调用 PS 测试命令，确认 GPIO 电平与表格一致。
4. 检查无效组合不会被 PS 写入。

### 5.2 衰减器验证

1. 默认写 `31.75 dB`，确认 DSA 时钟、数据和 LE 有动作。
2. 依次写 `0 dB`、`10 dB`、`20 dB`、`31.75 dB`。
3. 用信号源和功率测量链路确认输出幅度变化。
4. 若衰减方向反了，优先检查 PE43711B-Z 位序和保留位。

### 5.3 路径验证

1. 直通路径：设置 `LNA bypass + direct_if`，输入已知 IF 或可直通测试信号，确认 ADC 端可观测。
2. LNA 路径：设置 `LNA enable + direct_if`，确认前放路径幅度变化。
3. 混频路径：设置 `mixer_chain`，同步配置 `LMX2572_1/2`，确认 40 MHz 中频输出。
4. 扫频路径：在上位机触发 sweep，确认 RF 设置不会被扫频流程覆盖。

### 5.4 上位机闭环验证

1. 上位机连接设备后查询 RF 状态。
2. 修改 LNA、路径和衰减，确认每次收到 ACK。
3. 查询状态，确认 `RF_FRONTEND_STATUS` 与 UI 一致。
4. 断开重连后再次查询，确认 UI 能同步设备真实状态。

## 6. 里程碑

| 阶段 | 产出 | 验收标准 |
|---|---|---|
| M1 | BSP 和 `app_config.h` 更新 | PS 能编译，新 GPIO ID 和 bit mask 与 PL 一致 |
| M2 | `rf_frontend` 驱动 | 裸机测试可切换 LNA、路径、衰减 |
| M3 | PS 协议扩展 | 上位机或测试脚本可发送 `SET_RF_FRONTEND` 并收到 ACK |
| M4 | 上位机 UI 和协议 | UI 可控制并显示 RF 前端实际状态 |
| M5 | 射频链路联调 | 直通、LNA、混频、衰减均有可测量结果 |

## 7. 风险与待确认问题

| 问题 | 影响 | 处理建议 |
|---|---|---|
| 新 XSA 中 GPIO 设备 ID 与文档命名不同 | PS 宏可能写错设备 | 以 `xparameters.h` 为准，不手写猜测 ID |
| HMC849/HMC544AETR 实际 RF1/RF2 与文档相反 | 路径选择反向 | GPIO 验证后修正 `rf_frontend` 映射层，不让上位机感知 |
| PE43711B-Z 位序或 LE 时序不匹配 | 衰减设置无效或反向 | 先用逻辑分析仪看串行帧，再用实测幅度校验 |
| `CMD_SET_AMPLITUDE` 旧语义与新 RF 控制重叠 | 上下位机状态混乱 | 第一阶段新增 `SET_RF_FRONTEND` 专用命令，旧命令保持兼容 |
| 扫频流程自动改本振或路径 | 用户设置被覆盖 | RF 状态由 `rf_frontend` 统一持有，扫频代码只能通过公开 API 修改 |
| 上电默认衰减过低 | 可能过载 ADC 或后级 | 默认 `31.75 dB`，确认链路安全后再按配置降低 |

## 8. 后续开发顺序建议

1. 先更新硬件平台和 `app_config.h`，保证软件看到正确 GPIO。
2. 独立实现并测试 `rf_frontend`，不用先接上位机。
3. 用串口测试脚本打通 `SET_RF_FRONTEND/GET_RF_FRONTEND`。
4. 再接 Flutter UI，做状态同步。
5. 最后把混频路径与 `lo_control`、扫频流程联动。

这样推进的好处是每一层都能单独验证：GPIO 对不对、硬件动作对不对、协议通不通、UI 是否真实反映设备状态。
