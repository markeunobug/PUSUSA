// LMX2592.c
#include "lmx2592.h"
#include <math.h>

// -------------------------- 常量与静态变量定义 --------------------------
#define LMX2592_MAX_REG_ADDR     70
#define LMX2592_SPI_W_BIT        0x00    // 写操作：R/W位=0
#define LMX2592_SPI_R_BIT        0x01    // 读操作：R/W位=1
#define LMX2592_PLL_N_PRE_DIV2   0       // 寄存器值：预分频2
#define LMX2592_PLL_N_PRE_DIV4   1       // 寄存器值：预分频4

// 芯片配置静态变量
static double lmx2592_ref_freq_MHz = 50.0;
static double lmx2592_fpd_MHz = 100.0;
static uint16_t lmx2592_shadow[LMX2592_MAX_REG_ADDR + 1] = {0};

// 初始化寄存器列表（匹配数据手册上电推荐配置，保留位严格按默认值）
static const struct {
    uint8_t addr;
    uint16_t value;
} lmx2592_init_regs[] = {
    {70, 0x0000}, {69, 0x0000}, {68, 0x0089}, {64, 0x0077}, {62, 0x0000}, {61, 0x0001}, {59, 0x0000},
    {48, 0x03FC}, {47, 0x00CF}, {46, 0x0AA3}, {45, 0x0000}, {44, 0x0000}, {43, 0x0000}, {42, 0x0000},
    {41, 0x03E8}, {40, 0x0000}, {39, 0x8204}, {38, 0x0028}, {37, 0x4000}, {36, 0x0421}, {35, 0x029B},
    {34, 0xC3EA}, {33, 0x2A0A}, {32, 0x210A}, {31, 0x0601}, {30, 0x0034}, {29, 0x0084}, {28, 0x2924},
    {25, 0x0000}, {24, 0x0509}, {23, 0x8842}, {22, 0x2300}, {20, 0x012C}, {19, 0x0965}, {14, 0x018C},
    {13, 0x4000}, {12, 0x7001}, {11, 0x0018}, {10, 0x10D8}, {9, 0x0B02}, {8, 0x1084}, {7, 0x28B2},
    {4, 0x1943},  {2, 0x0500},  {1, 0x0808},  {0, 0x221C}
};
static const uint8_t lmx2592_num_init_regs = sizeof(lmx2592_init_regs) / sizeof(lmx2592_init_regs[0]);

// MASH阶数对应最小N值（匹配数据手册表7-2）
static const uint32_t min_n_by_mash[] = {9, 11, 16, 18, 30};
// 通道分频器SEG2/SEG3 实际分频→寄存器值映射表（匹配数据手册表7-30/7-31）
static const uint8_t chdiv_seg_map[9] = {0, 0, 1, 0, 2, 0, 4, 0, 8};

// -------------------------- 底层辅助函数 --------------------------
// 微秒级延时
static void lmx2592_delay_us(uint32_t us) {
    uint32_t clk_cycle = us * (SystemCoreClock / 1000000U) / 3;
    for (uint32_t i = 0; i < clk_cycle; i++) {
        __NOP();
    }
}

// 最大公约数计算
static uint32_t lmx2592_gcd(uint32_t a, uint32_t b) {
    while (b != 0) {
        uint32_t temp = b;
        b = a % b;
        a = temp;
    }
    return a;
}

// SDIO引脚方向切换（解决读操作电平冲突）
static void lmx2592_sdio_set_output(void) {
    GPIO_InitTypeDef GPIO_InitStruct = {0};
    GPIO_InitStruct.Pin = PLL_SDI_Pin;
    GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_PP;
    GPIO_InitStruct.Pull = GPIO_NOPULL;
    GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;
    HAL_GPIO_Init(PLL_SDI_GPIO_Port, &GPIO_InitStruct);
}

static void lmx2592_sdio_set_input(void) {
    GPIO_InitTypeDef GPIO_InitStruct = {0};
    GPIO_InitStruct.Pin = PLL_SDI_Pin;
    GPIO_InitStruct.Mode = GPIO_MODE_INPUT;
    GPIO_InitStruct.Pull = GPIO_NOPULL;
    HAL_GPIO_Init(PLL_SDI_GPIO_Port, &GPIO_InitStruct);
}

// SPI写操作（24位帧：R/W(1bit)+ADDR(7bit)+DATA(16bit)）
static void lmx2592_spi_write(uint32_t word) {
    lmx2592_sdio_set_output();
    LMX2592_CSB(0);
    lmx2592_delay_us(1);

    for (int i = 23; i >= 0; i--) {
        LMX2592_SCLK(0);
        LMX2592_SDIO((word & (1UL << i)) ? 1 : 0);
        lmx2592_delay_us(1);
        LMX2592_SCLK(1);
        lmx2592_delay_us(1);
    }

    LMX2592_CSB(1);
    lmx2592_delay_us(1);
}

// SPI读操作（修复时序与引脚方向冲突，匹配数据手册图7-4）
static uint16_t lmx2592_spi_read(uint8_t addr) {
    uint32_t cmd = ((uint32_t)LMX2592_SPI_R_BIT << 23) | ((uint32_t)addr << 16);
    uint16_t data = 0;

    lmx2592_sdio_set_output();
    LMX2592_CSB(0);
    lmx2592_delay_us(1);

    // 发送前8位：R/W位 + 7位地址
    for (int i = 23; i >= 16; i--) {
        LMX2592_SCLK(0);
        LMX2592_SDIO((cmd & (1UL << i)) ? 1 : 0);
        lmx2592_delay_us(1);
        LMX2592_SCLK(1);
        lmx2592_delay_us(1);
    }

    // 地址发送完成，切换SDIO为输入，避免电平冲突
    lmx2592_sdio_set_input();
    lmx2592_delay_us(1);

    // 接收后16位数据（第9-24个时钟）
    for (int i = 15; i >= 0; i--) {
        LMX2592_SCLK(0);
        lmx2592_delay_us(1);
        LMX2592_SCLK(1);
        lmx2592_delay_us(1);
        data = (data << 1) | LMX2592_MUX_READ();
    }

    LMX2592_CSB(1);
    lmx2592_sdio_set_output(); // 恢复输出模式
    lmx2592_delay_us(1);

    return data;
}

// -------------------------- 寄存器读写API --------------------------
void LMX2592_WriteRegister(uint8_t addr, uint16_t data) {
    if (addr > LMX2592_MAX_REG_ADDR) return;
    uint32_t word = ((uint32_t)LMX2592_SPI_W_BIT << 23) | ((uint32_t)addr << 16) | data;
    lmx2592_spi_write(word);
    lmx2592_shadow[addr] = data;
}

uint16_t LMX2592_ReadRegister(uint8_t addr) {
    if (addr > LMX2592_MAX_REG_ADDR) return 0;
    uint8_t prev_mux_mode = (lmx2592_shadow[0] >> 2) & 0x01;
    // 读操作必须先设置MUX为回读模式
    if (prev_mux_mode != LMX2592_MUX_READBACK) {
        LMX2592_SetMuxPin(LMX2592_MUX_READBACK);
    }
    uint16_t data = lmx2592_spi_read(addr);
    // 恢复之前的MUX模式
    if (prev_mux_mode != LMX2592_MUX_READBACK) {
        LMX2592_SetMuxPin(prev_mux_mode);
    }
    return data;
}

// -------------------------- 初始化API --------------------------
void LMX2592_Init(void) {
    // 初始化SPI引脚默认状态
    LMX2592_CSB(1);
    LMX2592_SCLK(0);
    LMX2592_SDIO(0);
    lmx2592_sdio_set_output();
    lmx2592_delay_us(100);

    // 芯片使能
    LMX2592_CE(1);
    lmx2592_delay_us(1000); // 等待电源稳定

    // 软复位（匹配数据手册推荐流程）
    LMX2592_WriteRegister(0, 0x0002);
    lmx2592_delay_us(100); // 等待复位完成，必须延时

    // 写入所有初始化寄存器（跳过R0，最后单独配置）
    for (int i = 0; i < lmx2592_num_init_regs; i++) {
        if (lmx2592_init_regs[i].addr != 0) {
            LMX2592_WriteRegister(lmx2592_init_regs[i].addr, lmx2592_init_regs[i].value);
        }
    }

    // 写入R0最终值，触发频率与幅度校准
    LMX2592_WriteRegister(0, lmx2592_init_regs[lmx2592_num_init_regs - 1].value);
    lmx2592_delay_us(1000); // 等待校准完成
}

// -------------------------- 参考频率配置API --------------------------
double LMX2592_SetReferenceFrequency(double ref_freq_MHz, uint16_t doubler, uint16_t pre_R, uint16_t multiplier, uint16_t R) {
    // 输入参数边界检查（与手册一致）
    if (ref_freq_MHz < 5.0 || ref_freq_MHz > 1400.0) return lmx2592_fpd_MHz;
    if (multiplier < 1 || multiplier > 6) multiplier = 1;
    if (pre_R < 1 || pre_R > 4095) pre_R = 1;
    if (R < 1 || R > 255) R = 1;

    lmx2592_ref_freq_MHz = ref_freq_MHz;

    // 1. OSC_2X（R9 bit11）
    uint16_t r9 = lmx2592_shadow[9];
    r9 = (r9 & ~(1U << 11)) | ((doubler ? 1U : 0U) << 11);
    LMX2592_WriteRegister(9, r9);

    // 2. PLL_R_PRE（R12 bits11:0）——关键修复：保留 bits15:12 默认值
    uint16_t r12 = lmx2592_shadow[12];
    r12 = (r12 & ~0x0FFFU) | (pre_R & 0x0FFFU);
    LMX2592_WriteRegister(12, r12);

    // 3. MULT（R10 bits11:7）
    uint16_t r10 = lmx2592_shadow[10];
    r10 = (r10 & ~(0x1FU << 7)) | ((multiplier & 0x1FU) << 7);
    LMX2592_WriteRegister(10, r10);

    // 4. PLL_R（R11 bits11:4）
    uint16_t r11 = lmx2592_shadow[11];
    r11 = (r11 & ~(0xFFU << 4)) | ((R & 0xFFU) << 4);
    LMX2592_WriteRegister(11, r11);

    // 计算 PFD（手册公式完全一致）
    lmx2592_fpd_MHz = ref_freq_MHz * (doubler ? 2.0 : 1.0) /
                      (double)pre_R * (double)multiplier / (double)R;

    // 5. PFD 自适应校准位（严格按手册 Table 7-5）
    uint16_t r0 = lmx2592_shadow[0];
    r0 &= ~((0x0FU << 9) | (0x03U << 5));  // 清除 bits 12:9 + 6:5

    uint8_t hpfd_adj = 0;
    if (lmx2592_fpd_MHz > 200.0)      hpfd_adj = 3;
    else if (lmx2592_fpd_MHz > 150.0) hpfd_adj = 2;
    else if (lmx2592_fpd_MHz > 100.0) hpfd_adj = 1;
    // else 0: PFD ≤ 100 MHz

    uint8_t lpfd_adj = 0;
    if (lmx2592_fpd_MHz < 2.5)       lpfd_adj = 3;
    else if (lmx2592_fpd_MHz < 5.0)  lpfd_adj = 2;
    else if (lmx2592_fpd_MHz < 10.0) lpfd_adj = 1;
    // else 0: PFD ≥ 10 MHz

    r0 |= ((uint16_t)hpfd_adj << 9) | ((uint16_t)lpfd_adj << 5);
    LMX2592_WriteRegister(0, r0);

    return lmx2592_fpd_MHz;
}

// -------------------------- 频率设置API --------------------------
void LMX2592_SetFrequency(enum LMX2592_Channel ch, double freq_MHz) {
    if (freq_MHz < 20.0 || freq_MHz > 9800.0) return;

    double vco_freq = freq_MHz;
    uint8_t use_doubler = 0;          // VCO_2X_EN (R30[0])
    uint8_t use_chdiv   = 0;
    uint16_t chdiv_total = 1;

    uint8_t seg1 = 2, seg1_en = 0;    // 手册表 7-4 中的“SEG1”标签（2=÷2, 3=÷3）
    uint8_t seg2 = 1, seg2_en = 0;    // 手册表 7-4 中的“SEG2”标签（1=禁用,2/4/6/8=分频比）
    uint8_t seg3 = 1, seg3_en = 0;

    // 1. VCO 倍频器处理（手册 7.3.7：fOUT > 7100 MHz 时启用，VCO 必须在 3550~4900 MHz）
    if (freq_MHz > 7100.0) {
        use_doubler = 1;
        vco_freq /= 2.0;
    }
    // 2. 通道分频器处理（手册 7.3.8 + 表 7-4）
    else if (freq_MHz < 3550.0) {
        use_chdiv = 1;
        if (freq_MHz >= 1775.0) {          // total=2
            chdiv_total = 2; seg1 = 2; seg1_en = 1;
        } else if (freq_MHz >= 1184.0) {   // total=3
            chdiv_total = 3; seg1 = 3; seg1_en = 1;
        } else if (freq_MHz >= 888.0) {    // total=4
            chdiv_total = 4; seg1 = 2; seg2 = 2; seg1_en = 1; seg2_en = 1;
        } else if (freq_MHz >= 592.0) {    // total=6
            chdiv_total = 6; seg1 = 3; seg2 = 2; seg1_en = 1; seg2_en = 1;
        } else if (freq_MHz >= 444.0) {    // total=8
            chdiv_total = 8; seg1 = 2; seg2 = 4; seg1_en = 1; seg2_en = 1;
        } else if (freq_MHz >= 296.0) {    // total=12
            chdiv_total = 12; seg1 = 2; seg2 = 6; seg1_en = 1; seg2_en = 1;
        } else if (freq_MHz >= 222.0) {    // total=16
            chdiv_total = 16; seg1 = 2; seg2 = 8; seg1_en = 1; seg2_en = 1;
        } else if (freq_MHz >= 148.0) {    // total=24
            chdiv_total = 24; seg1 = 3; seg2 = 8; seg1_en = 1; seg2_en = 1;
        } else if (freq_MHz >= 111.0) {    // total=32
            chdiv_total = 32; seg1 = 2; seg2 = 8; seg3 = 2; seg1_en = 1; seg2_en = 1; seg3_en = 1;
        } else if (freq_MHz >= 99.0) {     // total=36
            chdiv_total = 36; seg1 = 3; seg2 = 6; seg3 = 2; seg1_en = 1; seg2_en = 1; seg3_en = 1;
        } else if (freq_MHz >= 74.0) {     // total=48
            chdiv_total = 48; seg1 = 3; seg2 = 8; seg3 = 2; seg1_en = 1; seg2_en = 1; seg3_en = 1;
        } else if (freq_MHz >= 56.0) {     // total=64
            chdiv_total = 64; seg1 = 2; seg2 = 8; seg3 = 4; seg1_en = 1; seg2_en = 1; seg3_en = 1;
        } else if (freq_MHz >= 37.0) {     // total=96
            chdiv_total = 96; seg1 = 2; seg2 = 8; seg3 = 6; seg1_en = 1; seg2_en = 1; seg3_en = 1;
        } else if (freq_MHz >= 28.0) {     // total=128
            chdiv_total = 128; seg1 = 2; seg2 = 8; seg3 = 8; seg1_en = 1; seg2_en = 1; seg3_en = 1;
        } else if (freq_MHz >= 20.0) {     // total=192
            chdiv_total = 192; seg1 = 3; seg2 = 8; seg3 = 8; seg1_en = 1; seg2_en = 1; seg3_en = 1;
        }
        vco_freq *= (double)chdiv_total;
    }

    // VCO 范围检查（手册 7.3.5：3550~7100 MHz）
    if (vco_freq < 3550.0 || vco_freq > 7100.0) return;

    // 3. 计算 PLL N 分频参数（手册 7.3.4 + 表 7-2）
    uint8_t mash_order = lmx2592_shadow[46] & 0x07;
    uint32_t min_n = (mash_order <= 4) ? min_n_by_mash[mash_order] : 18;

    double total_mult = vco_freq / lmx2592_fpd_MHz;

    // 预分频选择（手册 7.3.7：VCO 倍频器强制 ÷4；其余默认 ÷2 以获得最佳性能）
    uint8_t pll_n_pre_reg = use_doubler ? LMX2592_PLL_N_PRE_DIV4 : LMX2592_PLL_N_PRE_DIV2;
    double pre_div = use_doubler ? 4.0 : 2.0;
    double main_n = total_mult / pre_div;

    if (main_n < (double)min_n) return;   // 无法满足最小 N（需降低 fPD 或 MASH 阶数）

    uint32_t pll_n = (uint32_t)floor(main_n);
    double frac = main_n - (double)pll_n;

    uint32_t pll_den = 0xFFFFFFFFU;
    uint32_t pll_num = 0;
    if (frac < 1e-9) {                    // 整数模式
        pll_num = 0;
        pll_den = 1;
    } else {
        pll_num = (uint32_t)(frac * (double)pll_den + 0.5);
        uint32_t gcd_val = lmx2592_gcd(pll_num, pll_den);
        pll_num /= gcd_val;
        pll_den /= gcd_val;
    }

    // 4. 写入寄存器（严格按手册位字段）
    // 4.1 N 预分频（R37[12]）
    uint16_t r37 = lmx2592_shadow[37];
    r37 = (r37 & ~(1U << 12)) | ((uint16_t)pll_n_pre_reg << 12);
    LMX2592_WriteRegister(37, r37);

    // 4.2 N 整数部分（仅 12 位，R38[12:1]）← 原代码重大错误点
    uint16_t r38 = lmx2592_shadow[38];
    r38 = (r38 & ~0x1FFEU) | ((pll_n & 0x0FFFU) << 1);
    LMX2592_WriteRegister(38, r38);
    // R39 不用于 N（原代码错误）

    // 4.3 分数部分（32 位）
    LMX2592_WriteRegister(40, (pll_den >> 16) & 0xFFFF);
    LMX2592_WriteRegister(41, pll_den & 0xFFFF);
    LMX2592_WriteRegister(44, (pll_num >> 16) & 0xFFFF);
    LMX2592_WriteRegister(45, pll_num & 0xFFFF);

    // 4.4 VCO 倍频器 + VTUNE_ADJ（R30[0] + [7:6]，手册表 7-25）
    uint16_t r30 = lmx2592_shadow[30];
    r30 = (r30 & ~0x0001U) | (use_doubler ? 1U : 0U);
    uint8_t vtune_adj = (vco_freq >= 6500.0) ? 3 : 0;
    r30 = (r30 & ~(0x03U << 6)) | ((uint16_t)vtune_adj << 6);
    LMX2592_WriteRegister(30, r30);

    // 4.5 通道分频器配置（仅当 use_chdiv 时，严格匹配手册 R34~R36）
    if (use_chdiv) {
        // R34[5] CHDIV_EN
        uint16_t r34 = lmx2592_shadow[34];
        r34 = (r34 & ~(1U << 5)) | (1U << 5);
        LMX2592_WriteRegister(34, r34);

        // R35（SEG2[12:9]、SEG3_EN[8]、SEG2_EN[7]、SEG1[2]、SEG1_EN[1]）
        uint8_t seg1_reg = (seg1 == 3 ? 1 : 0);
        uint8_t seg2_reg = seg2_en ? chdiv_seg_map[seg2] : 0;
        uint8_t seg3_reg = seg3_en ? chdiv_seg_map[seg3] : 0;
        uint16_t r35 = lmx2592_shadow[35];
        r35 &= ~((0xFU << 9) | (1U << 8) | (1U << 7) | (1U << 2) | (1U << 1));
        r35 |= ((uint16_t)seg2_reg << 9) |
               ((uint16_t)seg3_en << 8) |
               ((uint16_t)seg2_en << 7) |
               ((uint16_t)seg1_reg << 2) |
               ((uint16_t)seg1_en << 1);
        LMX2592_WriteRegister(35, r35);

        // R36（SEG_SEL[6:4]、SEG3[3:0]）
        uint8_t seg_sel = seg3_en ? 4 : (seg2_en ? 2 : (seg1_en ? 1 : 0));
        uint16_t r36 = lmx2592_shadow[36];
        r36 &= ~((7U << 4) | 0xFU);
        r36 |= ((uint16_t)seg_sel << 4) | seg3_reg;
        LMX2592_WriteRegister(36, r36);
    } else {
        // 未使用通道分频器 → 省电（手册推荐）
        uint16_t r34 = lmx2592_shadow[34];
        r34 &= ~(1U << 5);
        LMX2592_WriteRegister(34, r34);

        uint16_t r36 = lmx2592_shadow[36];
        r36 &= ~(7U << 4);                 // SEG_SEL=0
        LMX2592_WriteRegister(36, r36);
    }

    // 4.6 输出 MUX（R47[12:11] + R48[1:0]，手册表 7-42）
    uint8_t out_mux = use_chdiv ? 0 : 1;   // 0=通道分频器，1=VCO（含倍频器）
    uint16_t r47 = lmx2592_shadow[47];
    r47 = (r47 & ~(3U << 11)) | ((uint16_t)out_mux << 11);
    LMX2592_WriteRegister(47, r47);

    uint16_t r48 = lmx2592_shadow[48];
    r48 = (r48 & ~0x0003U) | out_mux;
    LMX2592_WriteRegister(48, r48);

    // 5. 触发 VCO 校准（手册 7.3.6：写 R0[3]=FCAL_EN=1）
    uint16_t r0 = lmx2592_shadow[0];
    r0 |= (1U << 3);
    LMX2592_WriteRegister(0, r0);

    // 6. 设置输出通道并等待锁定
    LMX2592_SetOutputChannel(ch);
//    lmx2592_delay_us(10);               // 安全延时（手册典型 <25 µs）

    // 7.（可选）检查锁定状态
    // enum LMX2592_LockStatus status = LMX2592_GetLockStatus();
}

// -------------------------- 输出功率配置API（修复保留位写入错误） --------------------------
void LMX2592_SetOutputPower(enum LMX2592_Channel ch, int8_t powerDbm) {
    // 功率范围限制（匹配芯片实际能力，单端最大8dBm，差分最大14dBm）
    if (powerDbm < -20) powerDbm = -20;
    if (powerDbm > 14) powerDbm = 14;

    // 功率映射：-20~14dBm → 0~31 + 48~63，避开32-47保留位
    uint8_t pow_code;
    if (powerDbm <= 7) {
        pow_code = (uint8_t)((powerDbm + 20) * 31 / 27); // -20~7dBm → 0~31
    } else {
        pow_code = 48 + (uint8_t)((powerDbm - 7) * 15 / 7); // 7~14dBm → 48~63
    }

    // 配置对应通道功率
    if (ch == LMX2592_CHANNEL_A || ch == LMX2592_CHANNEL_A_AND_B) {
        uint16_t r46 = lmx2592_shadow[46];
        r46 = (r46 & ~(0x3F << 8)) | ((pow_code & 0x3F) << 8);
        LMX2592_WriteRegister(46, r46);
    }
    if (ch == LMX2592_CHANNEL_B || ch == LMX2592_CHANNEL_A_AND_B) {
        uint16_t r47 = lmx2592_shadow[47];
        r47 = (r47 & ~0x003F) | (pow_code & 0x3F);
        LMX2592_WriteRegister(47, r47);
    }
}

// -------------------------- 输出通道开关API（优化低功耗配置） --------------------------
void LMX2592_SetOutputChannel(enum LMX2592_Channel channel) {
    uint16_t r46 = lmx2592_shadow[46];
    uint16_t r47 = lmx2592_shadow[47];
    uint16_t r31 = lmx2592_shadow[31];
    uint16_t r36 = lmx2592_shadow[36];

    switch (channel) {
        case LMX2592_CHANNEL_A:
            // 开启A通道，关闭B通道
            r46 &= ~(1 << 6);  // OUTA_PD=0
            r47 |= (1 << 7);   // OUTB_PD=1
            r31 &= ~(1 << 9);  // VCO_DISTA_PD=0
            r31 |= (1 << 10);  // VCO_DISTB_PD=1
            r36 |= (1 << 10);  // CHDIV_DISTA_EN=1
            r36 &= ~(1 << 11); // CHDIV_DISTB_EN=0
            LED_OUTA(1);
            LED_OUTB(0);
            break;
        case LMX2592_CHANNEL_B:
            // 开启B通道，关闭A通道
            r46 |= (1 << 6);   // OUTA_PD=1
            r47 &= ~(1 << 7);  // OUTB_PD=0
            r31 |= (1 << 9);   // VCO_DISTA_PD=1
            r31 &= ~(1 << 10); // VCO_DISTB_PD=0
            r36 &= ~(1 << 10); // CHDIV_DISTA_EN=0
            r36 |= (1 << 11);  // CHDIV_DISTB_EN=1
            LED_OUTA(0);
            LED_OUTB(1);
            break;
        case LMX2592_CHANNEL_A_AND_B:
            // 同时开启A、B通道
            r46 &= ~(1 << 6);  // OUTA_PD=0
            r47 &= ~(1 << 7);  // OUTB_PD=0
            r31 &= ~((1 << 9) | (1 << 10)); // 两个VCO分布buffer都开启
            r36 |= ((1 << 10) | (1 << 11));  // 两个分频分布buffer都开启
            LED_OUTA(1);
            LED_OUTB(1);
            break;
    }

    // 写入修改后的寄存器
    LMX2592_WriteRegister(46, r46);
    LMX2592_WriteRegister(47, r47);
    LMX2592_WriteRegister(31, r31);
    LMX2592_WriteRegister(36, r36);
}

// -------------------------- MUX引脚配置API --------------------------
void LMX2592_SetMuxPin(uint8_t mode) {
    uint16_t r0 = lmx2592_shadow[0];
    r0 = (r0 & ~(1 << 2)) | ((mode & 0x01) << 2);
    LMX2592_WriteRegister(0, r0);
}

// -------------------------- 锁相状态读取API（新增，匹配数据手册） --------------------------
enum LMX2592_LockStatus LMX2592_GetLockStatus(void) {
    uint16_t r68 = LMX2592_ReadRegister(68);
    uint8_t ld_status = (r68 >> 9) & 0x03;
    if (ld_status == 2) {
    	LED_LD(1);
    	return LMX2592_LOCKED;
    }
    if (ld_status == 1) {
    	LED_LD(0);
    	return LMX2592_INVALID;
    }
    return LMX2592_UNLOCKED;
}
