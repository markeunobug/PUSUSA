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
#include "stm32g4xx_hal.h"

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
#define PLL_CE_Pin GPIO_PIN_0
#define PLL_CE_GPIO_Port GPIOA
#define PLL_CSB_Pin GPIO_PIN_1
#define PLL_CSB_GPIO_Port GPIOA
#define PLL_MUX_Pin GPIO_PIN_2
#define PLL_MUX_GPIO_Port GPIOA
#define PLL_SDI_Pin GPIO_PIN_3
#define PLL_SDI_GPIO_Port GPIOA
#define PLL_SCL_Pin GPIO_PIN_4
#define PLL_SCL_GPIO_Port GPIOA
#define LED_LD_Pin GPIO_PIN_4
#define LED_LD_GPIO_Port GPIOC
#define LED_OUTB_Pin GPIO_PIN_0
#define LED_OUTB_GPIO_Port GPIOB
#define LED_OUTA_Pin GPIO_PIN_1
#define LED_OUTA_GPIO_Port GPIOB

/* USER CODE BEGIN Private defines */

/* USER CODE END Private defines */

#ifdef __cplusplus
}
#endif

#endif /* __MAIN_H */
