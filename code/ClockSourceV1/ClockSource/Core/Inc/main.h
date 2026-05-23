/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file           : main.h
  * @brief          : Header for main.c file.
  *                   This file contains the common defines of the application.
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

/* Define to prevent recursive inclusion -------------------------------------*/
#ifndef __MAIN_H
#define __MAIN_H

#ifdef __cplusplus
extern "C" {
#endif

/* Includes ------------------------------------------------------------------*/
#include "stm32f1xx_hal.h"

/* Private includes ----------------------------------------------------------*/
/* USER CODE BEGIN Includes */

/* USER CODE END Includes */

/* Exported types ------------------------------------------------------------*/
/* USER CODE BEGIN ET */

/* USER CODE END ET */

/* Exported constants --------------------------------------------------------*/
/* USER CODE BEGIN EC */

/* USER CODE END EC */

/* Exported macro ------------------------------------------------------------*/
/* USER CODE BEGIN EM */

/* USER CODE END EM */

/* Exported functions prototypes ---------------------------------------------*/
void Error_Handler(void);

/* USER CODE BEGIN EFP */

/* USER CODE END EFP */

/* Private defines -----------------------------------------------------------*/
#define LED_LMX2592_Pin GPIO_PIN_1
#define LED_LMX2592_GPIO_Port GPIOC
#define LED_LMX2572_1_Pin GPIO_PIN_2
#define LED_LMX2572_1_GPIO_Port GPIOC
#define LED_LMX2572_2_Pin GPIO_PIN_3
#define LED_LMX2572_2_GPIO_Port GPIOC
#define LMX2592_CE_Pin GPIO_PIN_4
#define LMX2592_CE_GPIO_Port GPIOA
#define LMX2592_SCK_Pin GPIO_PIN_5
#define LMX2592_SCK_GPIO_Port GPIOA
#define LMX2592_SDI_Pin GPIO_PIN_6
#define LMX2592_SDI_GPIO_Port GPIOA
#define LMX2592_MUX_Pin GPIO_PIN_7
#define LMX2592_MUX_GPIO_Port GPIOA
#define LMX2592_CSB_Pin GPIO_PIN_4
#define LMX2592_CSB_GPIO_Port GPIOC
#define LMX2572_1_CE_Pin GPIO_PIN_5
#define LMX2572_1_CE_GPIO_Port GPIOC
#define LMX2572_1_SCK_Pin GPIO_PIN_0
#define LMX2572_1_SCK_GPIO_Port GPIOB
#define LMX2572_1_SDI_Pin GPIO_PIN_1
#define LMX2572_1_SDI_GPIO_Port GPIOB
#define LMX2572_1_MUX_Pin GPIO_PIN_10
#define LMX2572_1_MUX_GPIO_Port GPIOB
#define LMX2572_1_CSB_Pin GPIO_PIN_11
#define LMX2572_1_CSB_GPIO_Port GPIOB
#define TEMP_SDA_Pin GPIO_PIN_12
#define TEMP_SDA_GPIO_Port GPIOB
#define TEMP_SCL_Pin GPIO_PIN_13
#define TEMP_SCL_GPIO_Port GPIOB
#define CLKBUFFER_SEL_Pin GPIO_PIN_14
#define CLKBUFFER_SEL_GPIO_Port GPIOB
#define LMX2572_2_CE_Pin GPIO_PIN_15
#define LMX2572_2_CE_GPIO_Port GPIOB
#define LMX2572_2_CSB_Pin GPIO_PIN_6
#define LMX2572_2_CSB_GPIO_Port GPIOC
#define LMX2572_2_MUX_Pin GPIO_PIN_7
#define LMX2572_2_MUX_GPIO_Port GPIOC
#define LMX2572_2_SDI_Pin GPIO_PIN_8
#define LMX2572_2_SDI_GPIO_Port GPIOC
#define LMX2572_2_SCK_Pin GPIO_PIN_9
#define LMX2572_2_SCK_GPIO_Port GPIOC

/* USER CODE BEGIN Private defines */

/* USER CODE END Private defines */

#ifdef __cplusplus
}
#endif

#endif /* __MAIN_H */
