/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    gpio.c
  * @brief   This file provides code for the configuration
  *          of all used GPIO pins.
  ******************************************************************************
  * @attention
  *
  * Copyright (c) 2026 STMicroelectronics.
  * All rights reserved.
  *
  * This software is licensed under terms that can be found in the LICENSE file
  * in the root directory of this software component.
  * If no LICENSE file comes with this software, it is provided AS-IS.
  *
  ******************************************************************************
  */
/* USER CODE END Header */

/* Includes ------------------------------------------------------------------*/
#include "gpio.h"

/* USER CODE BEGIN 0 */

/* USER CODE END 0 */

/*----------------------------------------------------------------------------*/
/* Configure GPIO                                                             */
/*----------------------------------------------------------------------------*/
/* USER CODE BEGIN 1 */

/* USER CODE END 1 */

/** Configure pins as
        * Analog
        * Input
        * Output
        * EVENT_OUT
        * EXTI
*/
void MX_GPIO_Init(void)
{

  GPIO_InitTypeDef GPIO_InitStruct = {0};

  /* GPIO Ports Clock Enable */
  __HAL_RCC_GPIOD_CLK_ENABLE();
  __HAL_RCC_GPIOC_CLK_ENABLE();
  __HAL_RCC_GPIOA_CLK_ENABLE();
  __HAL_RCC_GPIOB_CLK_ENABLE();

  /*Configure GPIO pin Output Level */
  HAL_GPIO_WritePin(GPIOC, LED_LMX2592_Pin|LED_LMX2572_1_Pin|LED_LMX2572_2_Pin|LMX2592_CSB_Pin
                          |LMX2572_1_CE_Pin|LMX2572_2_CSB_Pin|LMX2572_2_SDI_Pin|LMX2572_2_SCK_Pin, GPIO_PIN_RESET);

  /*Configure GPIO pin Output Level */
  HAL_GPIO_WritePin(GPIOA, LMX2592_CE_Pin|LMX2592_SCK_Pin|LMX2592_SDI_Pin, GPIO_PIN_RESET);

  /*Configure GPIO pin Output Level */
  HAL_GPIO_WritePin(GPIOB, LMX2572_1_SCK_Pin|LMX2572_1_SDI_Pin|LMX2572_1_CSB_Pin|TEMP_SDA_Pin
                          |TEMP_SCL_Pin|CLKBUFFER_SEL_Pin|LMX2572_2_CE_Pin, GPIO_PIN_RESET);

  /*Configure GPIO pins : LED_LMX2592_Pin LED_LMX2572_1_Pin LED_LMX2572_2_Pin */
  GPIO_InitStruct.Pin = LED_LMX2592_Pin|LED_LMX2572_1_Pin|LED_LMX2572_2_Pin;
  GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_PP;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;
  HAL_GPIO_Init(GPIOC, &GPIO_InitStruct);

  /*Configure GPIO pins : LMX2592_CE_Pin LMX2592_SCK_Pin LMX2592_SDI_Pin */
  GPIO_InitStruct.Pin = LMX2592_CE_Pin|LMX2592_SCK_Pin|LMX2592_SDI_Pin;
  GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_PP;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;
  HAL_GPIO_Init(GPIOA, &GPIO_InitStruct);

  /*Configure GPIO pin : LMX2592_MUX_Pin */
  GPIO_InitStruct.Pin = LMX2592_MUX_Pin;
  GPIO_InitStruct.Mode = GPIO_MODE_INPUT;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  HAL_GPIO_Init(LMX2592_MUX_GPIO_Port, &GPIO_InitStruct);

  /*Configure GPIO pins : LMX2592_CSB_Pin LMX2572_1_CE_Pin LMX2572_2_CSB_Pin LMX2572_2_SDI_Pin
                           LMX2572_2_SCK_Pin */
  GPIO_InitStruct.Pin = LMX2592_CSB_Pin|LMX2572_1_CE_Pin|LMX2572_2_CSB_Pin|LMX2572_2_SDI_Pin
                          |LMX2572_2_SCK_Pin;
  GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_PP;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_HIGH;
  HAL_GPIO_Init(GPIOC, &GPIO_InitStruct);

  /*Configure GPIO pins : LMX2572_1_SCK_Pin LMX2572_1_SDI_Pin LMX2572_1_CSB_Pin LMX2572_2_CE_Pin */
  GPIO_InitStruct.Pin = LMX2572_1_SCK_Pin|LMX2572_1_SDI_Pin|LMX2572_1_CSB_Pin|LMX2572_2_CE_Pin;
  GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_PP;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_HIGH;
  HAL_GPIO_Init(GPIOB, &GPIO_InitStruct);

  /*Configure GPIO pin : LMX2572_1_MUX_Pin */
  GPIO_InitStruct.Pin = LMX2572_1_MUX_Pin;
  GPIO_InitStruct.Mode = GPIO_MODE_INPUT;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  HAL_GPIO_Init(LMX2572_1_MUX_GPIO_Port, &GPIO_InitStruct);

  /*Configure GPIO pins : TEMP_SDA_Pin TEMP_SCL_Pin CLKBUFFER_SEL_Pin */
  GPIO_InitStruct.Pin = TEMP_SDA_Pin|TEMP_SCL_Pin|CLKBUFFER_SEL_Pin;
  GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_PP;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;
  HAL_GPIO_Init(GPIOB, &GPIO_InitStruct);

  /*Configure GPIO pin : LMX2572_2_MUX_Pin */
  GPIO_InitStruct.Pin = LMX2572_2_MUX_Pin;
  GPIO_InitStruct.Mode = GPIO_MODE_INPUT;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  HAL_GPIO_Init(LMX2572_2_MUX_GPIO_Port, &GPIO_InitStruct);

}

/* USER CODE BEGIN 2 */

/* USER CODE END 2 */
