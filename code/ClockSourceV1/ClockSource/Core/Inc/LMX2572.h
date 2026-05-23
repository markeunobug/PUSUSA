/*
 * LMX2572.h
 *
 *  Created on: Jun 15, 2025
 *      Author: 10663
 */

#ifndef INC_LMX2572_H_
#define INC_LMX2572_H_

#ifndef LMX2572DRIVER_H
#define LMX2572DRIVER_H

#include "stdint.h"
#include "stdbool.h"
#include "stm32f1xx_hal.h"
#include "main.h"

typedef struct
{
	GPIO_TypeDef *ce_port;
	uint16_t ce_pin;
	GPIO_TypeDef *csb_port;
	uint16_t csb_pin;
	GPIO_TypeDef *sck_port;
	uint16_t sck_pin;
	GPIO_TypeDef *sdi_port;
	uint16_t sdi_pin;
	GPIO_TypeDef *mux_port;
	uint16_t mux_pin;
	double fpd_hz;
	uint16_t reg_config[126];
} LMX2572_Device;

// Frequency pre-define
#define FREQ_100MHz 100000000U
#define FREQ_50MHz  50000000U
#define FREQ_20MHz  20000000U
#define FREQ_10MHz  10000000U
#define FREQ_1MHz   1000000U

void LMX2572_Device_Init(LMX2572_Device *dev,
		GPIO_TypeDef *ce_port, uint16_t ce_pin,
		GPIO_TypeDef *csb_port, uint16_t csb_pin,
		GPIO_TypeDef *sck_port, uint16_t sck_pin,
		GPIO_TypeDef *sdi_port, uint16_t sdi_pin,
		GPIO_TypeDef *mux_port, uint16_t mux_pin);

// Write a byte to the LMX2572 via SPI
void LMX2572_WriteRegister(LMX2572_Device *dev, uint8_t reg_addr, uint16_t data);

// Read a byte from the LMX2572 via SPI
uint16_t LMX2572_ReadRegister(LMX2572_Device *dev, uint8_t reg_addr);

// Reset the LMX2572
void LMX2572_Reset(LMX2572_Device *dev);

// Function to enable or disable the LMX2572
void LMX2572_SetEnabled(LMX2572_Device *dev, bool enabled);

// Function to initialize the LMX2572 driver
void LMX2572_Init(LMX2572_Device *dev);

// Function to initialize the LMX2572 driver with block initialization
void LMX2572_Init_Block(LMX2572_Device *dev);

// Function to set the reference frequency of the LMX2572
uint32_t LMX2572_SetReferenceFrequency(LMX2572_Device *dev, uint32_t ref_freq_Hz, uint8_t doubler, uint8_t pre_R, uint8_t multiplier, uint8_t R);

// Function to set the frequency of the LMX2572
int8_t LMX2572_SetFrequency(LMX2572_Device *dev, uint64_t frequencyHz);

// Function to set the output power of the LMX2572
void LMX2572_SetOutputPower(LMX2572_Device *dev, uint8_t ch, int8_t powerDbm);

// Function to enable output channel of the LMX2572
void LMX2572_SetOutputChannel(LMX2572_Device *dev, uint8_t channel_en);

// Function to set output source
void LMX2572_SetOutputMux(LMX2572_Device *dev, uint8_t channel, uint8_t source);

// Function to read the current lock status of the LMX2572
bool LMX2572_IsLocked(LMX2572_Device *dev);

// Configure the MUX pin function
void LMX2572_SetMuxFunction(LMX2572_Device *dev, uint8_t mux);


#endif // LMX2572DRIVER_H


#endif /* INC_LMX2572_H_ */
