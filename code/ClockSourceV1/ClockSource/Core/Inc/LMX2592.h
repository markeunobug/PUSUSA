/*
 * LMX2592.h
 * 修正版：严格匹配TI LMX2592数据手册
 *  Created on: Feb 3, 2026
 *      Author: 修正版
 */
#ifndef INC_LMX2592_H_
#define INC_LMX2592_H_

#include "stdint.h"
#include "stdbool.h"
#include "stm32f1xx_hal.h"
#include "main.h"

// -------------------------- GPIO引脚宏定义--------------------------
#define LMX2592_CE(x)        HAL_GPIO_WritePin(LMX2592_CE_GPIO_Port, LMX2592_CE_Pin, (x) ? GPIO_PIN_SET : GPIO_PIN_RESET)
#define LMX2592_CSB(x)       HAL_GPIO_WritePin(LMX2592_CSB_GPIO_Port, LMX2592_CSB_Pin, (x) ? GPIO_PIN_SET : GPIO_PIN_RESET)
#define LMX2592_SCLK(x)      HAL_GPIO_WritePin(LMX2592_SCK_GPIO_Port, LMX2592_SCK_Pin, (x) ? GPIO_PIN_SET : GPIO_PIN_RESET)
#define LMX2592_SDIO(x)      HAL_GPIO_WritePin(LMX2592_SDI_GPIO_Port, LMX2592_SDI_Pin, (x) ? GPIO_PIN_SET : GPIO_PIN_RESET)
#define LMX2592_MUX_READ()   HAL_GPIO_ReadPin(LMX2592_MUX_GPIO_Port, LMX2592_MUX_Pin)

// 状态指示灯宏
#define LED_LMX2592_LD(x)            HAL_GPIO_WritePin(LED_LMX2592_GPIO_Port, LED_LMX2592_Pin, (x) ? GPIO_PIN_SET : GPIO_PIN_RESET)
//#define LED_OUTA(x)          HAL_GPIO_WritePin(LED_OUTA_GPIO_Port, LED_OUTA_Pin, (x) ? GPIO_PIN_SET : GPIO_PIN_RESET)
//#define LED_OUTB(x)          HAL_GPIO_WritePin(LED_OUTB_GPIO_Port, LED_OUTB_Pin, (x) ? GPIO_PIN_SET : GPIO_PIN_RESET)

// MUX引脚模式定义
#define LMX2592_MUX_READBACK  0
#define LMX2592_MUX_LOCK_DET  1

// 输出通道枚举
enum LMX2592_Channel {
    LMX2592_CHANNEL_A,
    LMX2592_CHANNEL_B,
    LMX2592_CHANNEL_A_AND_B
};

// 锁相检测状态返回
enum LMX2592_LockStatus {
    LMX2592_UNLOCKED = 0,
    LMX2592_LOCKED = 1,
    LMX2592_INVALID = 2
};

// 核心API声明
void LMX2592_WriteRegister(uint8_t addr, uint16_t data);
uint16_t LMX2592_ReadRegister(uint8_t addr);
void LMX2592_Init(void);
void LMX2592_SetFrequency(enum LMX2592_Channel ch, double freq_MHz);
double LMX2592_SetReferenceFrequency(double ref_freq_MHz, uint16_t doubler, uint16_t pre_R, uint16_t multiplier, uint16_t R);
void LMX2592_SetOutputPower(enum LMX2592_Channel ch, int8_t powerDbm);
void LMX2592_SetOutputChannel(enum LMX2592_Channel channel);
void LMX2592_SetMuxPin(uint8_t mode);
enum LMX2592_LockStatus LMX2592_GetLockStatus(void);

#endif /* INC_LMX2592_H_ */
