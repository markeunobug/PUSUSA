# 频谱仪硬件变更记录

本文档记录当前频谱仪硬件相对原设计的变更点，用于后续 FPGA 约束、固件驱动、寄存器映射和上位机控制逻辑开发。

## 项目平台

| 项目 | 内容 |
|---|---|
| FPGA/SoC | Zynq-7000 `XC7Z010` |
| FPGA 开发工具 | Vivado |
| PS 软件开发工具 | Vitis |
| ADC | `LTC2208` |
| ADC 采样率 | 130 Msps |

## 变更概览

| 模块 | 变更内容 | 开发影响 |
|---|---|---|
| LMX2572_0 | 作为 ADC 时钟源 PLL，提供 ADC 130 MHz 时钟 | 复用现有 LMX2572 驱动，新增一颗 ADC 时钟 PLL 的实例/配置 |
| LMX2572_1 | 作为第一级混频器本振控制 PLL | 沿用现有 LMX2572 驱动和第一级本振控制流程 |
| LMX2572_2 | 作为第二级混频器本振控制 PLL | 沿用现有 LMX2572 驱动和第二级本振控制流程 |
| AD8370 | 中频 VGA 控制管脚修改 | 需要更新 FPGA 约束、顶层端口和 VGA 增益控制逻辑 |
| 射频前端开关 | 新增/调整 HMC849、HMC544AETR 等前端路径选择控制 | 需要新增射频路径状态机或寄存器控制位 |
| PE43711B-Z | 射频前端数字衰减器 | 需要新增衰减值配置接口和串行控制时序 |

## FPGA Bank 分配

| Bank | 电压 | 连接设备/信号 | 约束影响 |
|---|---|---|---|
| Bank 35 | 2.5 V | LTC2208 ADC 的 LVDS 数据、数据时钟、溢出指示及部分控制信号 | ADC LVDS 输入应使用匹配 2.5 V Bank 的 LVDS IO 标准，控制脚使用匹配 2.5 V Bank 的单端 IO 标准 |
| Bank 34 | 3.3 V | LMX2572 PLL、开关、衰减器、VGA 等控制信号 | 普通控制 GPIO/SPI 信号应使用 3.3 V IO 标准 |

说明：

- LTC2208 的 LVDS 接口挂在 Bank 35，Bank 35 电压为 2.5 V。
- 除 ADC LVDS 外，其他控制类外设挂在 Bank 34，Bank 34 电压为 3.3 V。
- Bank 34 当前包含 PLL、射频前端开关、衰减器、VGA 等控制信号。

## LTC2208：ADC 接口

`LTC2208` 的并行 LVDS 数据、`CLK_OUT` 数据时钟和 `OF` 溢出指示连接到 FPGA Bank 35。Bank 35 电压为 2.5 V。

说明：

- `D0~D15` 为 `LTC2208` 输出到 FPGA 的 16 bit LVDS 数据。
- `CLK_OUT` 为 `LTC2208` 输出到 FPGA 的 LVDS 数据时钟。
- `OF` 为 `LTC2208` 输出到 FPGA 的 LVDS over-range/overflow 指示。
- `PGA_PIN`、`SHDN_PIN`、`DITH_PIN`、`RAND_PIN` 为 `LTC2208` 单端控制脚，同样接在 Bank 35。
- `LTC2208` 的 `ENC` 差分采样时钟由 `LMX2572_0` 差分输出直接提供，不经过 FPGA。

### LTC2208 原理图连接

| 信号名 | 原理图网络 | 方向 | 建议 IO 标准 | 备注 |
|---|---|---|---|---|
| D0- | L2 / B35_N | ADC 到 FPGA | LVDS_25 | 数据 bit 0 负端 |
| D0+ | L2 / B35_P | ADC 到 FPGA | LVDS_25 | 数据 bit 0 正端 |
| D1- | L1 / B35_N | ADC 到 FPGA | LVDS_25 | 数据 bit 1 负端 |
| D1+ | L1 / B35_P | ADC 到 FPGA | LVDS_25 | 数据 bit 1 正端 |
| D2- | L3 / B35_N | ADC 到 FPGA | LVDS_25 | 数据 bit 2 负端 |
| D2+ | L3 / B35_P | ADC 到 FPGA | LVDS_25 | 数据 bit 2 正端 |
| D3- | L4 / B35_N | ADC 到 FPGA | LVDS_25 | 数据 bit 3 负端 |
| D3+ | L4 / B35_P | ADC 到 FPGA | LVDS_25 | 数据 bit 3 正端 |
| D4- | L5 / B35_N | ADC 到 FPGA | LVDS_25 | 数据 bit 4 负端 |
| D4+ | L5 / B35_P | ADC 到 FPGA | LVDS_25 | 数据 bit 4 正端 |
| D5- | L16 / B35_N | ADC 到 FPGA | LVDS_25 | 数据 bit 5 负端 |
| D5+ | L16 / B35_P | ADC 到 FPGA | LVDS_25 | 数据 bit 5 正端 |
| D6- | L19 / B35_N | ADC 到 FPGA | LVDS_25 | 数据 bit 6 负端 |
| D6+ | L19 / B35_P | ADC 到 FPGA | LVDS_25 | 数据 bit 6 正端 |
| D7- | L10 / B35_N | ADC 到 FPGA | LVDS_25 | 数据 bit 7 负端 |
| D7+ | L10 / B35_P | ADC 到 FPGA | LVDS_25 | 数据 bit 7 正端 |
| D8- | L17 / B35_N | ADC 到 FPGA | LVDS_25 | 数据 bit 8 负端 |
| D8+ | L17 / B35_P | ADC 到 FPGA | LVDS_25 | 数据 bit 8 正端 |
| D9- | L20 / B35_N | ADC 到 FPGA | LVDS_25 | 数据 bit 9 负端 |
| D9+ | L20 / B35_P | ADC 到 FPGA | LVDS_25 | 数据 bit 9 正端 |
| D10- | L14 / B35_N | ADC 到 FPGA | LVDS_25 | 数据 bit 10 负端 |
| D10+ | L14 / B35_P | ADC 到 FPGA | LVDS_25 | 数据 bit 10 正端 |
| D11- | L7 / B35_N | ADC 到 FPGA | LVDS_25 | 数据 bit 11 负端 |
| D11+ | L7 / B35_P | ADC 到 FPGA | LVDS_25 | 数据 bit 11 正端 |
| D12- | L11 / B35_N | ADC 到 FPGA | LVDS_25 | 数据 bit 12 负端 |
| D12+ | L11 / B35_P | ADC 到 FPGA | LVDS_25 | 数据 bit 12 正端 |
| D13- | L8 / B35_N | ADC 到 FPGA | LVDS_25 | 数据 bit 13 负端 |
| D13+ | L8 / B35_P | ADC 到 FPGA | LVDS_25 | 数据 bit 13 正端 |
| D14- | L22 / B35_N | ADC 到 FPGA | LVDS_25 | 数据 bit 14 负端 |
| D14+ | L22 / B35_P | ADC 到 FPGA | LVDS_25 | 数据 bit 14 正端 |
| D15- | L21 / B35_N | ADC 到 FPGA | LVDS_25 | 数据 bit 15 负端 |
| D15+ | L21 / B35_P | ADC 到 FPGA | LVDS_25 | 数据 bit 15 正端 |
| CLK_OUT- | L13 / B35_N | ADC 到 FPGA | LVDS_25 | ADC 数据时钟负端 |
| CLK_OUT+ | L13 / B35_P | ADC 到 FPGA | LVDS_25 | ADC 数据时钟正端 |
| OF- | L6 / B35_N | ADC 到 FPGA | LVDS_25 | ADC 溢出指示负端 |
| OF+ | L6 / B35_P | ADC 到 FPGA | LVDS_25 | ADC 溢出指示正端 |
| PGA_PIN | L24 / B35_N | FPGA 到 ADC | LVCMOS25 | ADC PGA 控制 |
| SHDN_PIN | L23 / B35_N | FPGA 到 ADC | LVCMOS25 | ADC shutdown 控制 |
| DITH_PIN | L23 / B35_P | FPGA 到 ADC | LVCMOS25 | ADC dither 控制 |
| RAND_PIN | L24 / B35_P | FPGA 到 ADC | LVCMOS25 | ADC randomizer 控制 |

### LTC2208 Vivado 管脚绑定

| 信号名 | 原理图网络 | Vivado `PACKAGE_PIN` | 建议 IO 标准 | 方向 |
|---|---|---|---|---|
| D0- | L2 / B35_N | A20 | LVDS_25 | 输入 |
| D0+ | L2 / B35_P | B19 | LVDS_25 | 输入 |
| D1- | L1 / B35_N | B20 | LVDS_25 | 输入 |
| D1+ | L1 / B35_P | C20 | LVDS_25 | 输入 |
| D2- | L3 / B35_N | D18 | LVDS_25 | 输入 |
| D2+ | L3 / B35_P | E17 | LVDS_25 | 输入 |
| D3- | L4 / B35_N | D20 | LVDS_25 | 输入 |
| D3+ | L4 / B35_P | D19 | LVDS_25 | 输入 |
| D4- | L5 / B35_N | E19 | LVDS_25 | 输入 |
| D4+ | L5 / B35_P | E18 | LVDS_25 | 输入 |
| D5- | L16 / B35_N | G18 | LVDS_25 | 输入 |
| D5+ | L16 / B35_P | G17 | LVDS_25 | 输入 |
| D6- | L19 / B35_N | G15 | LVDS_25 | 输入 |
| D6+ | L19 / B35_P | H15 | LVDS_25 | 输入 |
| D7- | L10 / B35_N | J19 | LVDS_25 | 输入 |
| D7+ | L10 / B35_P | K19 | LVDS_25 | 输入 |
| D8- | L17 / B35_N | H20 | LVDS_25 | 输入 |
| D8+ | L17 / B35_P | J20 | LVDS_25 | 输入 |
| D9- | L20 / B35_N | J14 | LVDS_25 | 输入 |
| D9+ | L20 / B35_P | K14 | LVDS_25 | 输入 |
| D10- | L14 / B35_N | H18 | LVDS_25 | 输入 |
| D10+ | L14 / B35_P | J18 | LVDS_25 | 输入 |
| D11- | L7 / B35_N | M20 | LVDS_25 | 输入 |
| D11+ | L7 / B35_P | M19 | LVDS_25 | 输入 |
| D12- | L11 / B35_N | L17 | LVDS_25 | 输入 |
| D12+ | L11 / B35_P | L16 | LVDS_25 | 输入 |
| D13- | L8 / B35_N | M18 | LVDS_25 | 输入 |
| D13+ | L8 / B35_P | M17 | LVDS_25 | 输入 |
| D14- | L22 / B35_N | L15 | LVDS_25 | 输入 |
| D14+ | L22 / B35_P | L14 | LVDS_25 | 输入 |
| D15- | L21 / B35_N | N16 | LVDS_25 | 输入 |
| D15+ | L21 / B35_P | N15 | LVDS_25 | 输入 |
| CLK_OUT- | L13 / B35_N | H17 | LVDS_25 | 输入 |
| CLK_OUT+ | L13 / B35_P | H16 | LVDS_25 | 输入 |
| OF- | L6 / B35_N | F17 | LVDS_25 | 输入 |
| OF+ | L6 / B35_P | F16 | LVDS_25 | 输入 |
| PGA_PIN | L24 / B35_N | J16 | LVCMOS25 | 输出 |
| SHDN_PIN | L23 / B35_N | M15 | LVCMOS25 | 输出 |
| DITH_PIN | L23 / B35_P | M14 | LVCMOS25 | 输出 |
| RAND_PIN | L24 / B35_P | K16 | LVCMOS25 | 输出 |

若顶层端口命名按 ADC 位号展开，可参考以下 XDC 片段：

```tcl
# LTC2208 LVDS data
set_property PACKAGE_PIN B19 [get_ports ltc2208_d_p[0]]
set_property PACKAGE_PIN A20 [get_ports ltc2208_d_n[0]]
set_property PACKAGE_PIN C20 [get_ports ltc2208_d_p[1]]
set_property PACKAGE_PIN B20 [get_ports ltc2208_d_n[1]]
set_property PACKAGE_PIN E17 [get_ports ltc2208_d_p[2]]
set_property PACKAGE_PIN D18 [get_ports ltc2208_d_n[2]]
set_property PACKAGE_PIN D19 [get_ports ltc2208_d_p[3]]
set_property PACKAGE_PIN D20 [get_ports ltc2208_d_n[3]]
set_property PACKAGE_PIN E18 [get_ports ltc2208_d_p[4]]
set_property PACKAGE_PIN E19 [get_ports ltc2208_d_n[4]]
set_property PACKAGE_PIN G17 [get_ports ltc2208_d_p[5]]
set_property PACKAGE_PIN G18 [get_ports ltc2208_d_n[5]]
set_property PACKAGE_PIN H15 [get_ports ltc2208_d_p[6]]
set_property PACKAGE_PIN G15 [get_ports ltc2208_d_n[6]]
set_property PACKAGE_PIN K19 [get_ports ltc2208_d_p[7]]
set_property PACKAGE_PIN J19 [get_ports ltc2208_d_n[7]]
set_property PACKAGE_PIN J20 [get_ports ltc2208_d_p[8]]
set_property PACKAGE_PIN H20 [get_ports ltc2208_d_n[8]]
set_property PACKAGE_PIN K14 [get_ports ltc2208_d_p[9]]
set_property PACKAGE_PIN J14 [get_ports ltc2208_d_n[9]]
set_property PACKAGE_PIN J18 [get_ports ltc2208_d_p[10]]
set_property PACKAGE_PIN H18 [get_ports ltc2208_d_n[10]]
set_property PACKAGE_PIN M19 [get_ports ltc2208_d_p[11]]
set_property PACKAGE_PIN M20 [get_ports ltc2208_d_n[11]]
set_property PACKAGE_PIN L16 [get_ports ltc2208_d_p[12]]
set_property PACKAGE_PIN L17 [get_ports ltc2208_d_n[12]]
set_property PACKAGE_PIN M17 [get_ports ltc2208_d_p[13]]
set_property PACKAGE_PIN M18 [get_ports ltc2208_d_n[13]]
set_property PACKAGE_PIN L14 [get_ports ltc2208_d_p[14]]
set_property PACKAGE_PIN L15 [get_ports ltc2208_d_n[14]]
set_property PACKAGE_PIN N15 [get_ports ltc2208_d_p[15]]
set_property PACKAGE_PIN N16 [get_ports ltc2208_d_n[15]]
set_property IOSTANDARD LVDS_25 [get_ports {ltc2208_d_p[*] ltc2208_d_n[*]}]

# LTC2208 LVDS clock and overflow
set_property PACKAGE_PIN H16 [get_ports ltc2208_clkout_p]
set_property PACKAGE_PIN H17 [get_ports ltc2208_clkout_n]
set_property PACKAGE_PIN F16 [get_ports ltc2208_of_p]
set_property PACKAGE_PIN F17 [get_ports ltc2208_of_n]
set_property IOSTANDARD LVDS_25 [get_ports {ltc2208_clkout_p ltc2208_clkout_n ltc2208_of_p ltc2208_of_n}]

# LTC2208 single-ended controls
set_property PACKAGE_PIN J16 [get_ports ltc2208_pga]
set_property PACKAGE_PIN M15 [get_ports ltc2208_shdn]
set_property PACKAGE_PIN M14 [get_ports ltc2208_dith]
set_property PACKAGE_PIN K16 [get_ports ltc2208_rand]
set_property IOSTANDARD LVCMOS25 [get_ports {ltc2208_pga ltc2208_shdn ltc2208_dith ltc2208_rand}]
```

## LMX2572_0：ADC 时钟源 PLL

用途：提供 ADC 130 MHz 时钟。`LMX2572_0` 的差分时钟输出直接进入 `LTC2208` 的 `ENC` 差分输入，不进入 FPGA 作为采样时钟源。

| 信号名 | FPGA 管脚/Bank | 方向 | 备注 |
|---|---|---|---|
| LMX2572_0_PLL_CE | L9 / B34_N | FPGA 输出 | PLL 使能控制 |
| LMX2572_0_PLL_SCK | L9 / B34_P | FPGA 输出 | SPI 时钟 |
| LMX2572_0_PLL_SDI | L24 / B34_P | FPGA 输出 | SPI 数据输入到 PLL |
| LMX2572_0_PLL_MUXOUT | L6 / B34_N | FPGA 输入 | PLL MUXOUT，配置为锁定状态检测 |
| LMX2572_0_PLL_CSB | L6 / B34_P | FPGA 输出 | SPI 片选 |

说明：

- 该 PLL 用于新增 ADC 时钟源。
- 现有工程之前已经使用过 `LMX2572` 驱动，`LMX2572_0` 的底层驱动应复用现有 `LMX2572` SPI/寄存器配置代码。
- 上电初始化时，`CE` 需要先明确拉到安全状态，再按初始化流程使能和配置。

## LMX2572_1：第一级混频器本振 PLL

用途：第一级混频器本振。

| 信号名 | FPGA 管脚/Bank | 方向 | 备注 |
|---|---|---|---|
| LMX2572_1_PLL_CE | L1 / B34_N | FPGA 输出 | PLL 使能控制 |
| LMX2572_1_PLL_SCK | L8 / B34_N | FPGA 输出 | SPI 时钟 |
| LMX2572_1_PLL_SDI | L3 / B34_P | FPGA 输出 | SPI 数据输入到 PLL |
| LMX2572_1_PLL_MUXOUT | L2 / B34_P | FPGA 输入 | PLL MUXOUT，配置为锁定状态检测 |
| LMX2572_1_PLL_CSB | L1 / B34_P | FPGA 输出 | SPI 片选 |

说明：

- 该 PLL 对应已有第一级本振控制。
- 底层驱动沿用现有 `LMX2572` 驱动。
- 上电初始化时，`CE` 需要先明确拉到安全状态，再按初始化流程使能和配置。

## LMX2572_2：第二级混频器本振 PLL

用途：第二级混频器本振。

| 信号名 | FPGA 管脚/Bank | 方向 | 备注 |
|---|---|---|---|
| LMX2572_2_PLL_CE | L10 / B34_P | FPGA 输出 | PLL 使能控制 |
| LMX2572_2_PLL_SCK | L10 / B34_N | FPGA 输出 | SPI 时钟 |
| LMX2572_2_PLL_SDI | L18 / B34_N | FPGA 输出 | SPI 数据输入到 PLL |
| LMX2572_2_PLL_MUXOUT | L18 / B34_P | FPGA 输入 | PLL MUXOUT，配置为锁定状态检测 |
| LMX2572_2_PLL_CSB | L21 / B34_P | FPGA 输出 | SPI 片选 |

说明：

- 该 PLL 对应已有第二级本振控制。
- 底层驱动沿用现有 `LMX2572` 驱动。
- 上电初始化时，`CE` 需要先明确拉到安全状态，再按初始化流程使能和配置。

## 射频前端结构

射频前端路径按当前描述整理如下：

1. 输入信号先进入第一个开关 `HMC849`。
2. `RF1` 为直通路径。
3. `RF2` 经过 LNA，型号为 `SGL0622Z`。
4. 后面依次经过第二个开关和第三个开关。
5. 第二个开关和第三个开关型号同样为 `HMC849`。
6. 第三处路径选择中，`RF1` 可直通中频，即不经过两级混频器。
7. `RF2` 接入 `PE43711B-Z` 数字衰减器，然后进入混频器链路。
8. 两级混频之后有一个开关 `HMC544AETR`，用于选择直通路径或两级混频路径。
9. 第四个开关 `HMC544AETR` 中，混频器链路输出接到 `RF1`，前端直通接到 `RF2`。
10. 当前射频链路中共有 2 个混频器，构成两级混频核心链路。

### 两级混频频率规划

两级混频链路是本系统的核心工作链路，频谱搬移关系如下：

1. `50 MHz` 到 `1.5 GHz` 的输入信号进入第一级混频器。
2. 第一级本振频率为 `2.18 GHz + RFin`，将输入信号混频到 `2.18 GHz`。
3. 第一级混频后经过 SAW 滤波器，用于滤除镜频。
4. SAW 滤波后进入第二级混频器。
5. 第二级本振为 `2.22 GHz` 定频，将信号混频到 `40 MHz` 中频。
6. `40 MHz` 中频经过后级带通滤波器，再经过中频 VGA `AD8370`，最后进入 `LTC2208` ADC。

## 射频前端开关控制

用途：控制射频前端直通、LNA、衰减、两级混频和最终路径选择。

| 信号名 | FPGA 管脚/Bank | 方向 | 备注 |
|---|---|---|---|
| SW1_CTL | L16 / B34_N | FPGA 输出 | 第一个前端开关控制，关联 HMC849 输入路径选择 |
| SW2_CTL | L17 / B34_N | FPGA 输出 | 第二个前端开关控制 |
| SW3_CTL | L17 / B34_P | FPGA 输出 | 第三个前端开关控制 |
| SW4_A | L21 / B34_N | FPGA 输出 | 第四个开关控制 A，关联 HMC544AETR |
| SW4_B | L16 / B34_P | FPGA 输出 | 第四个开关控制 B，关联 HMC544AETR |

### 射频前端开关控制逻辑

以下控制逻辑基于器件数据手册和当前原理图描述整理：

- `SW1`、`SW2`、`SW3` 均为 `HMC849`。
- `HMC849` 的 `EN` 为低有效使能，硬件默认拉低，因此默认处于使能状态；在 `EN=0` 时，`CTL=1` 选择 `RF1`，`CTL=0` 选择 `RF2`。若 `EN=1`，器件进入 all-off 状态。
- `SW4` 为 `HMC544AETR`，`SW4_A=0` 且 `SW4_B=1` 时选择 `RF1`，`SW4_A=1` 且 `SW4_B=0` 时选择 `RF2`。
- `SW4` 的 `RF1` 接两级混频后的输出，`RF2` 接前端直通输出。

| 控制对象 | 器件 | 选择 RF1 | 选择 RF2 | 当前 RF1 连接 | 当前 RF2 连接 |
|---|---|---|---|---|---|
| SW1 | HMC849 | `SW1_CTL=1` | `SW1_CTL=0` | 输入直通路径 | LNA `SGL0622Z` 路径 |
| SW2 | HMC849 | `SW2_CTL=1` | `SW2_CTL=0` | LNA `SGL0622Z` 输出 | 直通路径 |
| SW3 | HMC849 | `SW3_CTL=1` | `SW3_CTL=0` | 直通中频，不经过两级混频器 | 经 `PE43711B-Z` 衰减器后进入混频器链路 |
| SW4 | HMC544AETR | `SW4_A=0, SW4_B=1` | `SW4_A=1, SW4_B=0` | 两级混频输出 | 前端直通输出 |

由当前连接关系可推导出以下基础开关组合：

| 控制目标 | SW1_CTL | SW2_CTL | 说明 |
|---|---:|---:|---|
| 选择前端直通 | 1 | 0 | SW1 选输入直通，SW2 选直通路径 |
| 选择 LNA 路径 | 0 | 1 | SW1 选 LNA 输入，SW2 选 LNA 输出 |
| 其他组合 | 0/1 | 0/1 | 由 PS 端管理并禁止配置到无效组合 |

| 控制目标 | SW3_CTL | SW4_A | SW4_B | 说明 |
|---|---:|---:|---:|---|
| 前端直通到中频 | 1 | 1 | 0 | SW3 选直通中频，SW4 选前端直通输出 |
| 两级混频输出到中频 | 0 | 0 | 1 | SW3 选衰减器/混频链路，SW4 选两级混频输出 |
| 其他组合 | 0/1 | 0/1 | 0/1 | 由 PS 端管理并禁止配置到无效组合 |

### 射频前端控制抽象

射频前端不应在软件中固化为少数几个固定模式。直通、LNA、衰减器和两级混频链路之间没有固定绑定关系，应作为独立控制维度暴露。

建议软件/固件按以下维度建模：

| 控制维度 | 相关信号 | 控制含义 |
|---|---|---|
| 输入前端选择 | `SW1_CTL`、`SW2_CTL` | 选择是否经过 LNA，或选择直通/LNA 输出进入后级 |
| 直通/混频链路选择 | `SW3_CTL`、`SW4_A`、`SW4_B` | 选择前端信号直通到中频，或进入衰减器和两级混频核心链路 |
| 射频衰减 | `DSA_CLK`、`DSA_SI`、`DSA_LE` | 独立设置 `PE43711B-Z` 衰减值 |
| 两级混频 | `LMX2572_1`、`LMX2572_2` 及混频路径开关 | 本系统核心链路，负责两次变频 |

说明：

- 直通路径主要用于补偿低频情况下的频谱图。
- 两次混频链路是本系统的核心工作链路。
- LNA 是否接入、衰减器衰减值、是否走两级混频，应允许独立设置。
- 开关组合由 PS 端统一管理，无效组合不会被配置。
- 上位机或固件可以在更高层提供快捷模式，但底层寄存器/控制接口不要只保留固定三种模式。

## PE43711B-Z：射频前端衰减器

用途：RF2 路径进入混频器前的数字衰减控制。

| 信号名 | FPGA 管脚/Bank | 方向 | 备注 |
|---|---|---|---|
| DSA_CLK | L7 / B34_N | FPGA 输出 | 衰减器串行时钟 |
| DSA_SI | L7 / B34_P | FPGA 输出 | 衰减器串行数据输入 |
| DSA_LE | L8 / B34_P | FPGA 输出 | 衰减器锁存使能 |

### PE43711B-Z 底层控制说明

`PE43711B-Z` 的串行控制参数用于编写底层驱动：

| 参数 | 含义 | 当前记录 |
|---|---|---|
| 串行位宽 | 每次写入衰减器的控制字长度 | 8 bit |
| 位序 | 串行移位时先发送最高位还是最低位 | LSB first |
| 衰减步进 | 每增加 1 个控制码对应的衰减变化 | 0.25 dB/step |
| 可设置范围 | 衰减器支持的衰减范围 | 0 dB 到 31.75 dB |
| 保留位 | 控制字中不表示衰减值的位 | `D7` 必须写 0 |
| 默认衰减值 | 上电后串行模式默认状态 | 31.75 dB |

这些参数只影响底层串行写入方式。具体运行时要设置多少 dB 衰减，后续可由校准、频段策略或上位机控制逻辑决定。

## FPGA 约束影响

- 以上三个 LMX2572 均连接到 FPGA Bank 34。
- AD8370 中频 VGA 控制信号连接到 FPGA Bank 34。
- 射频前端开关和 PE43711B-Z 衰减器控制信号连接到 FPGA Bank 34。
- 需要在约束文件中更新/新增对应端口的管脚绑定。
- Bank 34 为 3.3 V，控制信号应设置为匹配 3.3 V Bank 的 IO 标准。
- Bank 35 为 2.5 V，LTC2208 ADC LVDS 信号应设置为匹配 2.5 V Bank 的 LVDS IO 标准。
- `MUXOUT` 作为输入信号处理，用于三颗 PLL 的锁定状态检测。
- `CE`、`SCK`、`SDI`、`CSB` 建议作为 FPGA 输出信号处理。
- AD8370 的 `DATA`、`CLCK`、`LTCH` 建议作为 FPGA 输出信号处理。
- 射频前端开关的 `SW*_CTL`、`SW4_A`、`SW4_B` 建议作为 FPGA 输出信号处理。
- PE43711B-Z 的 `DSA_CLK`、`DSA_SI`、`DSA_LE` 建议作为 FPGA 输出信号处理。

## 固件/逻辑影响

- 需要支持 3 颗 LMX2572 的独立配置。
- 现有版本已经使用 `LMX2572` 驱动，第一级/第二级本振 PLL 继续沿用原驱动，新增 `LMX2572_0` ADC 时钟源 PLL 时复用该代码。
- 三颗 `LMX2572` 的 `CE` 上电需要明确拉到安全状态，避免 PLL 在未完成配置前进入不确定输出状态。
- 若三颗 LMX2572 共用同一 SPI 控制器，需要确认是否共享 `SCK/SDI`，当前截图显示三颗 PLL 的 `SCK/SDI/CSB` 均为独立 FPGA 信号。
- `LMX2572_0` 初始化应先于 ADC 采样链路启动，确保 ADC 130 MHz 时钟稳定。
- `LMX2572_1` 和 `LMX2572_2` 的配置应跟随扫频/本振设置流程更新。
- 需要支持 AD8370 中频 VGA 的三线串行控制或兼容现有 VGA 控制模块。
- 需要新增射频前端路径控制逻辑，将 `SW1_CTL`、`SW2_CTL`、`SW3_CTL`、`SW4_A`、`SW4_B` 组合成清晰的工作模式。
- `HMC849` 开关可在软件中抽象为 `select_rf1` 布尔控制：`1` 选 RF1，`0` 选 RF2。
- `HMC544AETR` 开关可在软件中抽象为 `select_rf1` 布尔控制：选 RF1 时 `A=0/B=1`，选 RF2 时 `A=1/B=0`。
- 直通、LNA、衰减器和两级混频链路应作为独立控制维度暴露，不应只固化为少数固定路径模式。
- 开关组合由 PS 端管理，PL/底层驱动只需要提供可控寄存器或接口。
- 需要支持 PE43711B-Z 衰减器串行配置，并将衰减值纳入本机控制或上位机控制参数。

## AD8370：中频 VGA 控制

用途：中频 VGA 增益控制。

| 信号名 | FPGA 管脚/Bank | 方向 | 备注 |
|---|---|---|---|
| AD8370_DATA | L15 / B34_P | FPGA 输出 | VGA 串行数据 |
| AD8370_CLCK | L15 / B34_N | FPGA 输出 | VGA 串行时钟，原理图信号名为 `CLCK` |
| AD8370_LTCH | L12 / B34_N | FPGA 输出 | VGA 锁存控制 |

## Vivado 管脚绑定速查

本节根据原理图中 `Lx_B34_P/N` 到 Zynq `XC7Z010` Bank 34 封装管脚的对应关系整理，用于 Vivado XDC 约束。

说明：

- Bank 34 电压为 3.3 V，本节控制信号建议使用 `LVCMOS33`。
- `PACKAGE_PIN` 为 Vivado 约束中需要填写的封装管脚名。
- 若顶层端口继续使用 AXI GPIO 向量名，应优先参考下方“Vivado GPIO/端口分配表”；若改为独立端口，可直接使用下表信号名作为端口名参考。

### Vivado GPIO/端口分配表

当前工程已有：

- `axi_gpio_0`：现用于 `AD8370_GPIO_0`，单通道输出，当前宽度 3 bit。
- `axi_gpio_1`：现用于 `GPIO_LMX2572` 和 `GPIO_LMX2572_MUX`，双通道；通道 1 为输出，当前宽度 8 bit；通道 2 为输入，当前宽度 2 bit。

建议：

- 保留 `axi_gpio_0` 给 `AD8370`，继续使用原软件 bit 定义，只更新管脚约束。
- 调整并扩展 `axi_gpio_1`：输出通道扩展到 12 bit，输入通道扩展到 3 bit；三颗 `LMX2572` 按 `0/1/2` 顺序排列。
- 新增 `axi_gpio_2`，命名建议为 `GPIO_RF_FRONTEND`，单通道输出 8 bit，用于射频开关和 PE43711B-Z 衰减器。
- 新增 `axi_gpio_3`，命名建议为 `GPIO_LTC2208_CTRL`，单通道输出 4 bit，用于 `LTC2208` 单端控制脚。

#### `axi_gpio_0`：AD8370 控制输出

| AXI GPIO | 通道 | bit | 顶层端口建议 | 信号名 | PACKAGE_PIN | IO 标准 | 方向 | 备注 |
|---|---:|---:|---|---|---|---|---|---|
| axi_gpio_0 | 1 | 0 | `AD8370_GPIO_0_tri_o[0]` | AD8370_LTCH | U19 | LVCMOS33 | 输出 | 保留现有 `AD8370_GPIO_LTC_MASK` |
| axi_gpio_0 | 1 | 1 | `AD8370_GPIO_0_tri_o[1]` | AD8370_CLCK | U20 | LVCMOS33 | 输出 | 保留现有 `AD8370_GPIO_CLK_MASK` |
| axi_gpio_0 | 1 | 2 | `AD8370_GPIO_0_tri_o[2]` | AD8370_DATA | T20 | LVCMOS33 | 输出 | 保留现有 `AD8370_GPIO_DATA_MASK` |

#### `axi_gpio_1`：LMX2572 控制输出

| AXI GPIO | 通道 | bit | 顶层端口建议 | 信号名 | PACKAGE_PIN | IO 标准 | 方向 | 备注 |
|---|---:|---:|---|---|---|---|---|---|
| axi_gpio_1 | 1 | 0 | `GPIO_LMX2572_tri_o[0]` | LMX2572_0_PLL_CE | U17 | LVCMOS33 | 输出 | ADC 时钟源 PLL |
| axi_gpio_1 | 1 | 1 | `GPIO_LMX2572_tri_o[1]` | LMX2572_0_PLL_CSB | P14 | LVCMOS33 | 输出 | ADC 时钟源 PLL |
| axi_gpio_1 | 1 | 2 | `GPIO_LMX2572_tri_o[2]` | LMX2572_0_PLL_SCK | T16 | LVCMOS33 | 输出 | ADC 时钟源 PLL |
| axi_gpio_1 | 1 | 3 | `GPIO_LMX2572_tri_o[3]` | LMX2572_0_PLL_SDI | P15 | LVCMOS33 | 输出 | ADC 时钟源 PLL |
| axi_gpio_1 | 1 | 4 | `GPIO_LMX2572_tri_o[4]` | LMX2572_1_PLL_CE | T10 | LVCMOS33 | 输出 | 第一级本振 PLL |
| axi_gpio_1 | 1 | 5 | `GPIO_LMX2572_tri_o[5]` | LMX2572_1_PLL_CSB | T11 | LVCMOS33 | 输出 | 第一级本振 PLL |
| axi_gpio_1 | 1 | 6 | `GPIO_LMX2572_tri_o[6]` | LMX2572_1_PLL_SCK | Y14 | LVCMOS33 | 输出 | 第一级本振 PLL |
| axi_gpio_1 | 1 | 7 | `GPIO_LMX2572_tri_o[7]` | LMX2572_1_PLL_SDI | U13 | LVCMOS33 | 输出 | 第一级本振 PLL |
| axi_gpio_1 | 1 | 8 | `GPIO_LMX2572_tri_o[8]` | LMX2572_2_PLL_CE | V15 | LVCMOS33 | 输出 | 第二级本振 PLL |
| axi_gpio_1 | 1 | 9 | `GPIO_LMX2572_tri_o[9]` | LMX2572_2_PLL_CSB | V17 | LVCMOS33 | 输出 | 第二级本振 PLL |
| axi_gpio_1 | 1 | 10 | `GPIO_LMX2572_tri_o[10]` | LMX2572_2_PLL_SCK | W15 | LVCMOS33 | 输出 | 第二级本振 PLL |
| axi_gpio_1 | 1 | 11 | `GPIO_LMX2572_tri_o[11]` | LMX2572_2_PLL_SDI | W16 | LVCMOS33 | 输出 | 第二级本振 PLL |

#### `axi_gpio_1`：LMX2572 锁定状态输入

| AXI GPIO | 通道 | bit | 顶层端口建议 | 信号名 | PACKAGE_PIN | IO 标准 | 方向 | 备注 |
|---|---:|---:|---|---|---|---|---|---|
| axi_gpio_1 | 2 | 0 | `GPIO_LMX2572_MUX_tri_i[0]` | LMX2572_0_PLL_MUXOUT | R14 | LVCMOS33 | 输入 | ADC 时钟源 PLL lock detect |
| axi_gpio_1 | 2 | 1 | `GPIO_LMX2572_MUX_tri_i[1]` | LMX2572_1_PLL_MUXOUT | T12 | LVCMOS33 | 输入 | 第一级本振 PLL lock detect |
| axi_gpio_1 | 2 | 2 | `GPIO_LMX2572_MUX_tri_i[2]` | LMX2572_2_PLL_MUXOUT | V16 | LVCMOS33 | 输入 | 第二级本振 PLL lock detect |

#### `axi_gpio_2`：射频前端和衰减器控制输出

| AXI GPIO | 通道 | bit | 顶层端口建议 | 信号名 | PACKAGE_PIN | IO 标准 | 方向 | 备注 |
|---|---:|---:|---|---|---|---|---|---|
| axi_gpio_2 | 1 | 0 | `GPIO_RF_FRONTEND_tri_o[0]` | SW1_CTL | W20 | LVCMOS33 | 输出 | HMC849 开关 1 |
| axi_gpio_2 | 1 | 1 | `GPIO_RF_FRONTEND_tri_o[1]` | SW2_CTL | Y19 | LVCMOS33 | 输出 | HMC849 开关 2 |
| axi_gpio_2 | 1 | 2 | `GPIO_RF_FRONTEND_tri_o[2]` | SW3_CTL | Y18 | LVCMOS33 | 输出 | HMC849 开关 3 |
| axi_gpio_2 | 1 | 3 | `GPIO_RF_FRONTEND_tri_o[3]` | SW4_A | V18 | LVCMOS33 | 输出 | HMC544AETR A |
| axi_gpio_2 | 1 | 4 | `GPIO_RF_FRONTEND_tri_o[4]` | SW4_B | V20 | LVCMOS33 | 输出 | HMC544AETR B |
| axi_gpio_2 | 1 | 5 | `GPIO_RF_FRONTEND_tri_o[5]` | DSA_CLK | Y17 | LVCMOS33 | 输出 | PE43711B-Z 时钟 |
| axi_gpio_2 | 1 | 6 | `GPIO_RF_FRONTEND_tri_o[6]` | DSA_SI | Y16 | LVCMOS33 | 输出 | PE43711B-Z 数据 |
| axi_gpio_2 | 1 | 7 | `GPIO_RF_FRONTEND_tri_o[7]` | DSA_LE | W14 | LVCMOS33 | 输出 | PE43711B-Z 锁存 |

#### `axi_gpio_3`：LTC2208 单端控制输出

| AXI GPIO | 通道 | bit | 顶层端口建议 | 信号名 | PACKAGE_PIN | IO 标准 | 方向 | 备注 |
|---|---:|---:|---|---|---|---|---|---|
| axi_gpio_3 | 1 | 0 | `GPIO_LTC2208_CTRL_tri_o[0]` | LTC2208_PGA | J16 | LVCMOS25 | 输出 | ADC PGA 控制 |
| axi_gpio_3 | 1 | 1 | `GPIO_LTC2208_CTRL_tri_o[1]` | LTC2208_SHDN | M15 | LVCMOS25 | 输出 | ADC shutdown 控制 |
| axi_gpio_3 | 1 | 2 | `GPIO_LTC2208_CTRL_tri_o[2]` | LTC2208_DITH | M14 | LVCMOS25 | 输出 | ADC dither 控制 |
| axi_gpio_3 | 1 | 3 | `GPIO_LTC2208_CTRL_tri_o[3]` | LTC2208_RAND | K16 | LVCMOS25 | 输出 | ADC randomizer 控制 |

#### 对应软件宏建议

```c
/* AD8370: axi_gpio_0 channel 1, unchanged */
#define AD8370_GPIO_LTC_MASK       (1U << 0)
#define AD8370_GPIO_CLK_MASK       (1U << 1)
#define AD8370_GPIO_DATA_MASK      (1U << 2)

/* LMX2572: axi_gpio_1 channel 1 outputs, ordered 0/1/2 */
#define LMX2572_0_CE_MASK          (1U << 0)
#define LMX2572_0_CSB_MASK         (1U << 1)
#define LMX2572_0_SCK_MASK         (1U << 2)
#define LMX2572_0_SDI_MASK         (1U << 3)
#define LMX2572_1_CE_MASK          (1U << 4)
#define LMX2572_1_CSB_MASK         (1U << 5)
#define LMX2572_1_SCK_MASK         (1U << 6)
#define LMX2572_1_SDI_MASK         (1U << 7)
#define LMX2572_2_CE_MASK          (1U << 8)
#define LMX2572_2_CSB_MASK         (1U << 9)
#define LMX2572_2_SCK_MASK         (1U << 10)
#define LMX2572_2_SDI_MASK         (1U << 11)

/* LMX2572: axi_gpio_1 channel 2 inputs, ordered 0/1/2 */
#define LMX2572_0_MUX_MASK         (1U << 0)
#define LMX2572_1_MUX_MASK         (1U << 1)
#define LMX2572_2_MUX_MASK         (1U << 2)

/* RF frontend: axi_gpio_2 channel 1 outputs */
#define RF_SW1_CTL_MASK            (1U << 0)
#define RF_SW2_CTL_MASK            (1U << 1)
#define RF_SW3_CTL_MASK            (1U << 2)
#define RF_SW4_A_MASK              (1U << 3)
#define RF_SW4_B_MASK              (1U << 4)
#define DSA_CLK_MASK               (1U << 5)
#define DSA_SI_MASK                (1U << 6)
#define DSA_LE_MASK                (1U << 7)

/* LTC2208 controls: axi_gpio_3 channel 1 outputs */
#define LTC2208_PGA_MASK           (1U << 0)
#define LTC2208_SHDN_MASK          (1U << 1)
#define LTC2208_DITH_MASK          (1U << 2)
#define LTC2208_RAND_MASK          (1U << 3)
```

### 本次新增/修改控制信号

| 信号名 | 原理图网络 | Vivado `PACKAGE_PIN` | IO 标准 | 方向 | 备注 |
|---|---|---|---|---|---|
| LMX2572_0_PLL_CE | L9 / B34_N | U17 | LVCMOS33 | 输出 | ADC 时钟源 PLL 使能 |
| LMX2572_0_PLL_SCK | L9 / B34_P | T16 | LVCMOS33 | 输出 | ADC 时钟源 PLL SPI 时钟 |
| LMX2572_0_PLL_SDI | L24 / B34_P | P15 | LVCMOS33 | 输出 | ADC 时钟源 PLL SPI 数据 |
| LMX2572_0_PLL_MUXOUT | L6 / B34_N | R14 | LVCMOS33 | 输入 | ADC 时钟源 PLL 锁定状态 |
| LMX2572_0_PLL_CSB | L6 / B34_P | P14 | LVCMOS33 | 输出 | ADC 时钟源 PLL SPI 片选 |
| LMX2572_1_PLL_CE | L1 / B34_N | T10 | LVCMOS33 | 输出 | 第一级本振 PLL 使能 |
| LMX2572_1_PLL_SCK | L8 / B34_N | Y14 | LVCMOS33 | 输出 | 第一级本振 PLL SPI 时钟 |
| LMX2572_1_PLL_SDI | L3 / B34_P | U13 | LVCMOS33 | 输出 | 第一级本振 PLL SPI 数据 |
| LMX2572_1_PLL_MUXOUT | L2 / B34_P | T12 | LVCMOS33 | 输入 | 第一级本振 PLL 锁定状态 |
| LMX2572_1_PLL_CSB | L1 / B34_P | T11 | LVCMOS33 | 输出 | 第一级本振 PLL SPI 片选 |
| LMX2572_2_PLL_CE | L10 / B34_P | V15 | LVCMOS33 | 输出 | 第二级本振 PLL 使能 |
| LMX2572_2_PLL_SCK | L10 / B34_N | W15 | LVCMOS33 | 输出 | 第二级本振 PLL SPI 时钟 |
| LMX2572_2_PLL_SDI | L18 / B34_N | W16 | LVCMOS33 | 输出 | 第二级本振 PLL SPI 数据 |
| LMX2572_2_PLL_MUXOUT | L18 / B34_P | V16 | LVCMOS33 | 输入 | 第二级本振 PLL 锁定状态 |
| LMX2572_2_PLL_CSB | L21 / B34_P | V17 | LVCMOS33 | 输出 | 第二级本振 PLL SPI 片选 |
| SW1_CTL | L16 / B34_N | W20 | LVCMOS33 | 输出 | HMC849 开关 1 控制 |
| SW2_CTL | L17 / B34_N | Y19 | LVCMOS33 | 输出 | HMC849 开关 2 控制 |
| SW3_CTL | L17 / B34_P | Y18 | LVCMOS33 | 输出 | HMC849 开关 3 控制 |
| SW4_A | L21 / B34_N | V18 | LVCMOS33 | 输出 | HMC544AETR 控制 A |
| SW4_B | L16 / B34_P | V20 | LVCMOS33 | 输出 | HMC544AETR 控制 B |
| DSA_CLK | L7 / B34_N | Y17 | LVCMOS33 | 输出 | PE43711B-Z 串行时钟 |
| DSA_SI | L7 / B34_P | Y16 | LVCMOS33 | 输出 | PE43711B-Z 串行数据 |
| DSA_LE | L8 / B34_P | W14 | LVCMOS33 | 输出 | PE43711B-Z 锁存使能 |
| AD8370_DATA | L15 / B34_P | T20 | LVCMOS33 | 输出 | AD8370 串行数据 |
| AD8370_CLCK | L15 / B34_N | U20 | LVCMOS33 | 输出 | AD8370 串行时钟 |
| AD8370_LTCH | L12 / B34_N | U19 | LVCMOS33 | 输出 | AD8370 锁存控制 |

### XDC 独立端口参考

如果顶层端口命名与信号名一致，可参考以下 XDC 片段；实际工程中若使用 AXI GPIO 向量端口，应将端口名替换为对应的 `*_tri_o[n]` 或 `*_tri_i[n]`。

```tcl
# LMX2572_0: ADC clock PLL
set_property PACKAGE_PIN U17 [get_ports LMX2572_0_PLL_CE]
set_property PACKAGE_PIN T16 [get_ports LMX2572_0_PLL_SCK]
set_property PACKAGE_PIN P15 [get_ports LMX2572_0_PLL_SDI]
set_property PACKAGE_PIN R14 [get_ports LMX2572_0_PLL_MUXOUT]
set_property PACKAGE_PIN P14 [get_ports LMX2572_0_PLL_CSB]
set_property IOSTANDARD LVCMOS33 [get_ports {LMX2572_0_PLL_CE LMX2572_0_PLL_SCK LMX2572_0_PLL_SDI LMX2572_0_PLL_MUXOUT LMX2572_0_PLL_CSB}]

# LMX2572_1: first LO PLL
set_property PACKAGE_PIN T10 [get_ports LMX2572_1_PLL_CE]
set_property PACKAGE_PIN Y14 [get_ports LMX2572_1_PLL_SCK]
set_property PACKAGE_PIN U13 [get_ports LMX2572_1_PLL_SDI]
set_property PACKAGE_PIN T12 [get_ports LMX2572_1_PLL_MUXOUT]
set_property PACKAGE_PIN T11 [get_ports LMX2572_1_PLL_CSB]
set_property IOSTANDARD LVCMOS33 [get_ports {LMX2572_1_PLL_CE LMX2572_1_PLL_SCK LMX2572_1_PLL_SDI LMX2572_1_PLL_MUXOUT LMX2572_1_PLL_CSB}]

# LMX2572_2: second LO PLL
set_property PACKAGE_PIN V15 [get_ports LMX2572_2_PLL_CE]
set_property PACKAGE_PIN W15 [get_ports LMX2572_2_PLL_SCK]
set_property PACKAGE_PIN W16 [get_ports LMX2572_2_PLL_SDI]
set_property PACKAGE_PIN V16 [get_ports LMX2572_2_PLL_MUXOUT]
set_property PACKAGE_PIN V17 [get_ports LMX2572_2_PLL_CSB]
set_property IOSTANDARD LVCMOS33 [get_ports {LMX2572_2_PLL_CE LMX2572_2_PLL_SCK LMX2572_2_PLL_SDI LMX2572_2_PLL_MUXOUT LMX2572_2_PLL_CSB}]

# RF switches
set_property PACKAGE_PIN W20 [get_ports SW1_CTL]
set_property PACKAGE_PIN Y19 [get_ports SW2_CTL]
set_property PACKAGE_PIN Y18 [get_ports SW3_CTL]
set_property PACKAGE_PIN V18 [get_ports SW4_A]
set_property PACKAGE_PIN V20 [get_ports SW4_B]
set_property IOSTANDARD LVCMOS33 [get_ports {SW1_CTL SW2_CTL SW3_CTL SW4_A SW4_B}]

# PE43711B-Z DSA
set_property PACKAGE_PIN Y17 [get_ports DSA_CLK]
set_property PACKAGE_PIN Y16 [get_ports DSA_SI]
set_property PACKAGE_PIN W14 [get_ports DSA_LE]
set_property IOSTANDARD LVCMOS33 [get_ports {DSA_CLK DSA_SI DSA_LE}]

# AD8370 IF VGA
set_property PACKAGE_PIN T20 [get_ports AD8370_DATA]
set_property PACKAGE_PIN U20 [get_ports AD8370_CLCK]
set_property PACKAGE_PIN U19 [get_ports AD8370_LTCH]
set_property IOSTANDARD LVCMOS33 [get_ports {AD8370_DATA AD8370_CLCK AD8370_LTCH}]
```

## 待确认问题

| 问题 | 说明 |
|---|---|
| LMX2572_0 寄存器表 | 复用现有 LMX2572 驱动，但需要新增/确认 ADC 时钟源 PLL 输出 130 MHz 的寄存器配置 |
| AD8370 底层控制时序 | 当前阶段先实现底层驱动；具体增益/衰减设置策略后续再定 |
| PE43711B-Z 锁存时序 | 串行位宽、位序、步进和默认值已记录；仍可在实现驱动时按 datasheet 细化 `CLK` 与 `LE` 的时序裕量 |
| PLL CE 安全状态 | 三颗 `LMX2572` 的 `CE` 上电需要由初始化流程明确拉到安全状态；具体安全电平应结合板级设计和现有驱动实现确认 |

## 参考资料

- HMC849A 数据手册：`https://www.analog.com/en/products/hmc849a.html`
- HMC544A/HMC544AE 数据手册：`https://www.analog.com/media/en/technical-documentation/data-sheets/hmc544ae.pdf`
- PE43711 数据手册：`https://www.psemi.com/pdf/datasheets/pe43711ds.pdf`
