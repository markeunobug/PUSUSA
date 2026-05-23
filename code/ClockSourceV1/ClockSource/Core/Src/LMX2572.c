/*
 * LMX2572.c
 *
 *  Created on: Jun 15, 2025
 *      Author: 10663
 */

#include "LMX2572.h"
#include "stm32f1xx_hal.h"
#include <math.h>
#include <string.h>

static const uint16_t lmx2572_reg_default[126] = {
    0x2288, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
    0x0000, 0x0000, 0x0000, 0x7802, 0x0000, 0x0000, 0x0000, 0x0000,
    0x0000, 0x0000, 0x0000, 0x0007, 0x4440, 0x2580, 0x0000, 0x0000,
    0x0000, 0x2580, 0x8E38, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
    0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x5325,
    0xEBD5, 0x0001, 0xACD7, 0x3F2A, 0x0000, 0x0000, 0x0050, 0x0001,
    0x0000, 0x000C, 0x08C0, 0x0000, 0x003F, 0x0001, 0x0081, 0xC350,
    0x0000, 0x03E8, 0x0000, 0x01F4, 0x0000, 0x1388, 0x0000, 0x00AF,
    0x00A8, 0x03E8, 0x0001, 0x9001, 0x0020, 0x0000, 0x0000, 0x0000,
    0x0000, 0x0421, 0x0080, 0x0080, 0x4180, 0x03E0, 0x0300, 0x07F0,
    0xC61E, 0x1E63, 0x0000, 0x0000, 0x0000, 0x0000, 0x03E8, 0x0000,
    0x0205, 0x0028, 0x0004, 0x0010, 0x1E01, 0x05BF, 0xC3E6, 0x18A6,
    0x0000, 0x0488, 0x0002, 0x0808, 0x0624, 0x071A, 0x007C, 0x0001,
    0x0409, 0x4848, 0x27B7, 0x0064, 0x0096, 0x0080, 0x060E, 0x1820,
    0x4000, 0x5001, 0xB018, 0x1278, 0x0004, 0x2000, 0x00B2, 0xC802,
    0x20C8, 0x0A43, 0x0782, 0x0500, 0x0808, 0x2318
};

static void LMX2572_CE_Write(LMX2572_Device *dev, GPIO_PinState state)
{
	HAL_GPIO_WritePin(dev->ce_port, dev->ce_pin, state);
}

static void LMX2572_CSB_Write(LMX2572_Device *dev, GPIO_PinState state)
{
	HAL_GPIO_WritePin(dev->csb_port, dev->csb_pin, state);
}

static void LMX2572_SCLK_Write(LMX2572_Device *dev, GPIO_PinState state)
{
	HAL_GPIO_WritePin(dev->sck_port, dev->sck_pin, state);
}

static void LMX2572_SDIO_Write(LMX2572_Device *dev, GPIO_PinState state)
{
	HAL_GPIO_WritePin(dev->sdi_port, dev->sdi_pin, state);
}

static GPIO_PinState LMX2572_MUX_Read(LMX2572_Device *dev)
{
	return HAL_GPIO_ReadPin(dev->mux_port, dev->mux_pin);
}

void LMX2572_Device_Init(LMX2572_Device *dev,
		GPIO_TypeDef *ce_port, uint16_t ce_pin,
		GPIO_TypeDef *csb_port, uint16_t csb_pin,
		GPIO_TypeDef *sck_port, uint16_t sck_pin,
		GPIO_TypeDef *sdi_port, uint16_t sdi_pin,
		GPIO_TypeDef *mux_port, uint16_t mux_pin)
{
	dev->ce_port = ce_port;
	dev->ce_pin = ce_pin;
	dev->csb_port = csb_port;
	dev->csb_pin = csb_pin;
	dev->sck_port = sck_port;
	dev->sck_pin = sck_pin;
	dev->sdi_port = sdi_port;
	dev->sdi_pin = sdi_pin;
	dev->mux_port = mux_port;
	dev->mux_pin = mux_pin;
	dev->fpd_hz = 0.0;
	memcpy(dev->reg_config, lmx2572_reg_default, sizeof(dev->reg_config));
}

void LMX2572_WriteRegister(LMX2572_Device *dev, uint8_t reg_addr, uint16_t data)
{
    uint32_t tx_data = ((uint32_t)reg_addr << 16) | data;

	LMX2572_SCLK_Write(dev, GPIO_PIN_RESET);
	__NOP();
	__NOP();
	__NOP();
	LMX2572_SDIO_Write(dev, GPIO_PIN_RESET);

    LMX2572_CSB_Write(dev, GPIO_PIN_RESET);
    __NOP();
    __NOP();
    __NOP();
	__NOP();

	for (int i = 0; i < 24; i++) {
		LMX2572_SDIO_Write(dev, (tx_data & ((uint32_t)1 << (23 - i))) ? GPIO_PIN_SET : GPIO_PIN_RESET);
		__NOP();
	    __NOP();
		__NOP();

		LMX2572_SCLK_Write(dev, GPIO_PIN_SET);
		__NOP();
	    __NOP();
		__NOP();

		LMX2572_SCLK_Write(dev, GPIO_PIN_RESET);
		__NOP();
	    __NOP();
		__NOP();
	}

    LMX2572_CSB_Write(dev, GPIO_PIN_SET);
	__NOP();
	__NOP();

    if (reg_addr == 0) {
    	if (data & 0x02) {
    		dev->reg_config[125] = data & 0xFFFD;
    	} else {
    		dev->reg_config[125] = data;
    	}
    } else {
    	dev->reg_config[125 - reg_addr] = data;
    }
}

uint16_t LMX2572_ReadRegister(LMX2572_Device *dev, uint8_t reg_addr)
{
    uint16_t rx_data = 0;
    uint32_t tx_data = (1UL << 23) | ((uint32_t)reg_addr << 16);

    LMX2572_CSB_Write(dev, GPIO_PIN_RESET);

    for (int i = 0; i < 8; i++) {
        LMX2572_SCLK_Write(dev, GPIO_PIN_RESET);
        __NOP();
        LMX2572_SDIO_Write(dev, (tx_data & ((uint32_t)1 << (23 - i))) ? GPIO_PIN_SET : GPIO_PIN_RESET);
        __NOP();
        LMX2572_SCLK_Write(dev, GPIO_PIN_SET);
        __NOP();
    }

    for (int i = 0; i < 16; i++) {
        LMX2572_SCLK_Write(dev, GPIO_PIN_RESET);
        __NOP();
        __NOP();
        rx_data |= ((uint16_t)LMX2572_MUX_Read(dev) << (15 - i));
        LMX2572_SCLK_Write(dev, GPIO_PIN_SET);
        __NOP();
        __NOP();
    }

    LMX2572_CSB_Write(dev, GPIO_PIN_SET);
    return rx_data;
}

void LMX2572_Reset(LMX2572_Device *dev)
{
    LMX2572_WriteRegister(dev, 0x00, dev->reg_config[125] | 0x02);
    HAL_Delay(10);
}

void LMX2572_SetEnabled(LMX2572_Device *dev, bool enabled)
{
    LMX2572_CE_Write(dev, enabled ? GPIO_PIN_SET : GPIO_PIN_RESET);
}

void LMX2572_Init(LMX2572_Device *dev)
{
    LMX2572_CE_Write(dev, GPIO_PIN_SET);
    HAL_Delay(10);
    LMX2572_Reset(dev);
    HAL_Delay(10);

    LMX2572_WriteRegister(dev, 0, 0x231c);
    LMX2572_WriteRegister(dev, 29, 0x0000);
    LMX2572_WriteRegister(dev, 30, 0x18A6);
    LMX2572_WriteRegister(dev, 34, 0x0010);
    LMX2572_WriteRegister(dev, 36, 0x0029);
    LMX2572_WriteRegister(dev, 37, 0x0205);
    LMX2572_WriteRegister(dev, 38, 0x0000);
    LMX2572_WriteRegister(dev, 39, 0x03E8);
    LMX2572_WriteRegister(dev, 52, 0x0421);
    LMX2572_WriteRegister(dev, 57, 0x0020);
    LMX2572_WriteRegister(dev, 71, 0x0081);
    LMX2572_WriteRegister(dev, 78, 0x0001);
}

void LMX2572_Init_Block(LMX2572_Device *dev)
{
    LMX2572_CE_Write(dev, GPIO_PIN_SET);
    HAL_Delay(50);
    LMX2572_Reset(dev);
    HAL_Delay(50);

    for (int reg_idx = 0; reg_idx < 126; reg_idx++) {
    	LMX2572_WriteRegister(dev, reg_idx, dev->reg_config[125 - reg_idx]);
    }
}

uint32_t LMX2572_SetReferenceFrequency(LMX2572_Device *dev, uint32_t ref_freq_Hz, uint8_t doubler, uint8_t pre_R, uint8_t multiplier, uint8_t R)
{
	if (pre_R < 1 || pre_R > 255) {
		pre_R = 1;
	}
	if (R < 1 || R > 255) {
		R = 1;
	}
	if (doubler != 0 && doubler != 1) {
		doubler = 0;
	}
	if (doubler == 1) {
		if (multiplier != 1) {
			multiplier = 1;
		}
	} else {
		if (multiplier != 1 && (multiplier < 3 || multiplier > 7)) {
			multiplier = 1;
		}
	}

	uint32_t ref_freq_kHz = ref_freq_Hz / 1000;
	uint32_t f_osc2x_kHz = ref_freq_kHz * (doubler ? 2U : 1U);
	uint32_t f_mult_in_kHz = f_osc2x_kHz / pre_R;
	uint32_t f_mult_out_kHz = f_mult_in_kHz * multiplier;

	if (multiplier != 1) {
		if (f_mult_in_kHz < 10000U || f_mult_in_kHz > 40000U) {
			return 0;
		}
		if (f_mult_out_kHz < 60000U || f_mult_out_kHz > 150000U) {
			return 0;
		}
	}

	uint8_t mult_hi = (f_mult_out_kHz > 100000U) ? 1U : 0U;
	uint16_t reg_data = 0;

	reg_data = 0x0004;
	reg_data &= (uint16_t)~((1U << 14) | (1U << 12));
	reg_data |= (uint16_t)((mult_hi << 14) | (doubler << 12));
	LMX2572_WriteRegister(dev, 0x09, reg_data);

	reg_data = 0x10F8;
	reg_data &= (uint16_t)~0x0F80;
	reg_data |= (uint16_t)((multiplier & 0x1F) << 7);
	LMX2572_WriteRegister(dev, 0x0A, reg_data);

	reg_data = 0x5001;
	reg_data &= (uint16_t)~0x0FFF;
	reg_data |= (uint16_t)(pre_R & 0x0FFF);
	LMX2572_WriteRegister(dev, 0x0C, reg_data);

	reg_data = 0xB018;
	reg_data &= (uint16_t)~0x0FF0;
	reg_data |= (uint16_t)((R & 0xFF) << 4);
	LMX2572_WriteRegister(dev, 0x0B, reg_data);

	dev->fpd_hz = 1000.0 * f_mult_out_kHz / R;
	return (uint32_t)dev->fpd_hz;
}

int8_t LMX2572_SetFrequency(LMX2572_Device *dev, uint64_t frequencyHz)
{
    if (frequencyHz < 12500000UL || frequencyHz > 6400000000ULL) {
        return 0;
    }

    if (dev->fpd_hz == 0.0) {
        return 0;
    }

    const uint16_t chdiv_list[] = {1, 2, 4, 8, 16, 32, 64, 128, 256};
    uint16_t selected_chdiv = 0;
    uint64_t f_vco_target = 0;
    uint32_t pll_n = 0;
    const uint32_t pll_den = 1000000UL;
    uint32_t pll_num = 0;
    uint8_t pfd_dly_sel = 0;
    uint8_t chdiv_found = 0;

    for (uint8_t i = 0; i < 9; i++) {
        uint16_t chdiv = chdiv_list[i];
        f_vco_target = frequencyHz * chdiv;

        if (f_vco_target < 3200000000ULL || f_vco_target > 6400000000ULL) {
            continue;
        }

        double n_total = (double)f_vco_target / dev->fpd_hz;
        pll_n = (uint32_t)floor(n_total);
        double frac = n_total - pll_n;
        pll_num = (uint32_t)(frac * pll_den);

        if (pll_num >= pll_den) {
            pll_num -= pll_den;
            pll_n += 1;
        }

        uint32_t min_pll_n = 0;
        if (f_vco_target < 4000000000ULL) {
            min_pll_n = 26;
            pfd_dly_sel = 1;
        } else if (f_vco_target < 4900000000ULL) {
            min_pll_n = 30;
            pfd_dly_sel = 2;
        } else {
            min_pll_n = 30;
            pfd_dly_sel = 2;
        }

        if (pll_n >= min_pll_n) {
            selected_chdiv = chdiv;
            chdiv_found = 1;
            break;
        }
    }

    if (!chdiv_found) {
        return 0;
    }

    uint16_t reg_data = 0;

    reg_data = 0x0010;
    reg_data &= (uint16_t)~0x0007;
    reg_data |= (uint16_t)((pll_n >> 16) & 0x0007);
    LMX2572_WriteRegister(dev, 0x22, reg_data);

    reg_data = pll_n & 0xFFFF;
    LMX2572_WriteRegister(dev, 0x24, reg_data);

    reg_data = (pll_den >> 16) & 0xFFFF;
    LMX2572_WriteRegister(dev, 0x26, reg_data);

    reg_data = pll_den & 0xFFFF;
    LMX2572_WriteRegister(dev, 0x27, reg_data);

    reg_data = (pll_num >> 16) & 0xFFFF;
    LMX2572_WriteRegister(dev, 0x2A, reg_data);

    reg_data = pll_num & 0xFFFF;
    LMX2572_WriteRegister(dev, 0x2B, reg_data);

    uint16_t reg_r46 = dev->reg_config[125 - 46];
    uint16_t reg_r45 = dev->reg_config[125 - 45];

    if (selected_chdiv == 1) {
    	reg_r45 &= (uint16_t)~(0x03 << 11);
    	reg_r45 |= (uint16_t)(0x01 << 11);
    	LMX2572_WriteRegister(dev, 0x2D, reg_r45);

    	reg_r46 &= (uint16_t)~0x0003;
    	reg_r46 |= 0x0001;
    	LMX2572_WriteRegister(dev, 0x2E, reg_r46);
    } else {
    	reg_r45 &= (uint16_t)~(0x03 << 11);
    	LMX2572_WriteRegister(dev, 0x2D, reg_r45);

    	reg_r46 &= (uint16_t)~0x0003;
    	LMX2572_WriteRegister(dev, 0x2E, reg_r46);

        uint8_t chdiv_code = 0;
        switch (selected_chdiv) {
            case 2:   chdiv_code = 0;  break;
            case 4:   chdiv_code = 1;  break;
            case 8:   chdiv_code = 3;  break;
            case 16:  chdiv_code = 5;  break;
            case 32:  chdiv_code = 7;  break;
            case 64:  chdiv_code = 9;  break;
            case 128: chdiv_code = 12; break;
            case 256: chdiv_code = 14; break;
            default:  chdiv_code = 0;  break;
        }

        reg_data = 0xF800;
        reg_data &= (uint16_t)~0x07C0;
        reg_data |= (uint16_t)((chdiv_code & 0x1F) << 6);
        LMX2572_WriteRegister(dev, 0x4B, reg_data);
    }

    reg_data = 0x0205;
    reg_data &= (uint16_t)~0x3F00;
    reg_data |= (uint16_t)((pfd_dly_sel & 0x3F) << 8);
    LMX2572_WriteRegister(dev, 0x25, reg_data);

    reg_data = dev->reg_config[125];
    reg_data |= 0x0008;
    LMX2572_WriteRegister(dev, 0x00, reg_data);

    return 1;
}

void LMX2572_SetOutputPower(LMX2572_Device *dev, uint8_t ch, int8_t powerDbm)
{
    uint8_t power_code = 0;

    if (powerDbm <= -8) {
    	power_code = 0;
    } else if (powerDbm >= 4) {
    	power_code = 63;
    } else {
    	power_code = (uint8_t)((powerDbm + 8) * 4);
    }

    if (ch == 0) {
		uint16_t r44 = dev->reg_config[125 - 44];
		r44 &= (uint16_t)~0x3F00;
		r44 |= (uint16_t)((power_code & 0x3F) << 8);
		LMX2572_WriteRegister(dev, 0x2C, r44);
    } else if (ch == 1) {
		uint16_t r45 = dev->reg_config[125 - 45];
		r45 &= (uint16_t)~0x003F;
		r45 |= (uint16_t)(power_code & 0x3F);
		LMX2572_WriteRegister(dev, 0x2D, r45);
    }
}

void LMX2572_SetOutputChannel(LMX2572_Device *dev, uint8_t channel_en)
{
    uint16_t regR44 = dev->reg_config[125 - 44];

    regR44 |= (1U << 6) | (1U << 7);

    switch (channel_en) {
        case 0:
            regR44 &= (uint16_t)~(1U << 6);
            break;
        case 1:
            regR44 &= (uint16_t)~(1U << 7);
            break;
        case 2:
            regR44 &= (uint16_t)~((1U << 6) | (1U << 7));
            break;
        default:
            break;
    }

    LMX2572_WriteRegister(dev, 0x2C, regR44);
}

void LMX2572_SetOutputMux(LMX2572_Device *dev, uint8_t channel, uint8_t source)
{
    uint16_t regVal = 0;
    uint8_t isParamValid = 1;

    switch (channel) {
        case 0:
            if (!(source == 0 || source == 1 || source == 3)) {
                isParamValid = 0;
            }
            break;
        case 1:
            if (!(source == 0 || source == 1 || source == 2 || source == 3)) {
                isParamValid = 0;
            }
            break;
        default:
            isParamValid = 0;
            break;
    }

    if (!isParamValid) {
        return;
    }

    if (channel == 0) {
        regVal = dev->reg_config[125 - 45];
        regVal &= (uint16_t)~(0x03 << 11);
        regVal |= (uint16_t)(source << 11);
        LMX2572_WriteRegister(dev, 0x2D, regVal);
    } else {
        regVal = dev->reg_config[125 - 46];
        regVal &= (uint16_t)~0x0003;
        regVal |= (uint16_t)source;
        LMX2572_WriteRegister(dev, 0x2E, regVal);
    }
}

bool LMX2572_IsLocked(LMX2572_Device *dev)
{
    return (LMX2572_MUX_Read(dev) == GPIO_PIN_SET);
}

void LMX2572_SetMuxFunction(LMX2572_Device *dev, uint8_t mux)
{
	uint16_t r0 = dev->reg_config[125];

	r0 &= (uint16_t)~(1U << 2);

    if (mux == 1) {
    	r0 |= (1U << 2);
    }

    LMX2572_WriteRegister(dev, 0, r0);
}
