#ifndef LMX2572_REGISTERS_H
#define LMX2572_REGISTERS_H

#include <stdint.h>

#define LMX2572_REGISTER_COUNT 126U

#define LMX2572_R0             0U
#define LMX2572_R9             9U
#define LMX2572_R10            10U
#define LMX2572_R11            11U
#define LMX2572_R12            12U
#define LMX2572_R14            14U
#define LMX2572_R34            34U
#define LMX2572_R36            36U
#define LMX2572_R37            37U
#define LMX2572_R38            38U
#define LMX2572_R39            39U
#define LMX2572_R42            42U
#define LMX2572_R43            43U
#define LMX2572_R44            44U
#define LMX2572_R45            45U
#define LMX2572_R46            46U
#define LMX2572_R75            75U

#define LMX2572_R0_RESET_MASK          0x0002U
#define LMX2572_R0_MUXOUT_LD_SEL_MASK  0x0004U
#define LMX2572_R0_FCAL_EN_MASK        0x0008U
#define LMX2572_R0_FCAL_LPFD_ADJ_MASK  0x0060U
#define LMX2572_R0_FCAL_LPFD_ADJ_SHIFT 5U
#define LMX2572_R0_FCAL_HPFD_ADJ_MASK  0x0180U
#define LMX2572_R0_FCAL_HPFD_ADJ_SHIFT 7U

#define LMX2572_R9_OSC_2X_MASK         0x1000U
#define LMX2572_R9_MULT_HI_MASK        0x4000U

#define LMX2572_R10_MULT_MASK          0x0F80U
#define LMX2572_R10_MULT_SHIFT         7U
#define LMX2572_R11_PLL_R_MASK         0x0FF0U
#define LMX2572_R11_PLL_R_SHIFT        4U
#define LMX2572_R12_PLL_R_PRE_MASK     0x0FFFU

#define LMX2572_R14_CPG_MASK           0x0078U
#define LMX2572_R14_CPG_SHIFT          3U

#define LMX2572_R34_PLL_N_HIGH_MASK    0x0007U
#define LMX2572_R37_PFD_DLY_SEL_MASK   0x3F00U
#define LMX2572_R37_PFD_DLY_SEL_SHIFT  8U

#define LMX2572_R44_MASH_ORDER_MASK    0x0007U
#define LMX2572_R44_OUTA_PD_MASK       0x0040U
#define LMX2572_R44_OUTB_PD_MASK       0x0080U
#define LMX2572_R44_OUTA_PWR_MASK      0x3F00U
#define LMX2572_R44_OUTA_PWR_SHIFT     8U

#define LMX2572_R45_OUTB_PWR_MASK      0x003FU
#define LMX2572_R45_OUTA_MUX_MASK      0x1800U
#define LMX2572_R45_OUTA_MUX_SHIFT     11U
#define LMX2572_R46_OUTB_MUX_MASK      0x0003U

#define LMX2572_R75_CHDIV_MASK         0x07C0U
#define LMX2572_R75_CHDIV_SHIFT        6U

/*
 * The authoritative P100 image is stored in descending register order
 * (R125 first, R0 last), matching the original TICS Pro export.
 */
static inline uint16_t lmx2572_shadow_get(const uint16_t *shadow, uint8_t reg)
{
    return shadow[(LMX2572_REGISTER_COUNT - 1U) - reg];
}

static inline void lmx2572_shadow_set(uint16_t *shadow,
                                     uint8_t reg,
                                     uint16_t value)
{
    shadow[(LMX2572_REGISTER_COUNT - 1U) - reg] = value;
}

static inline uint16_t lmx2572_field_replace(uint16_t reg_value,
                                             uint16_t mask,
                                             uint8_t shift,
                                             uint16_t field_value)
{
    reg_value &= (uint16_t)~mask;
    reg_value |= (uint16_t)((uint16_t)(field_value << shift) & mask);
    return reg_value;
}

#endif
