/*
 * protocol.h
 *
 *  Created on: Feb 25, 2026
 *      Author: 10663
 */

#ifndef INC_PROTOCOL_H_
#define INC_PROTOCOL_H_

// 文件: protocol.h
// STM32G431 下位机通信协议库头文件

#ifndef PROTOCOL_H
#define PROTOCOL_H

#include "stm32g4xx_hal.h"
#include <stdint.h>

// 命令码定义
#define CMD_SET_FREQ        0x01
#define CMD_SET_AMPLITUDE   0x02
#define CMD_SET_BW          0x03
#define CMD_SET_DETECT      0x04
#define CMD_SET_SWEEP       0x05
#define CMD_GET_SPECTRUM    0x06
#define CMD_GET_STATUS      0x07
#define CMD_RESET           0x08

#define RESP_ACK            0x81
#define RESP_SPECTRUM_DATA  0x82
#define RESP_STATUS_DATA    0x83

// 错误码
#define ERR_SUCCESS         0x00
#define ERR_INVALID_CMD     0x01
#define ERR_INVALID_DATA    0x02
#define ERR_BUSY            0x03

// 最大数据点数（示例）
#define MAX_POINTS          1024

// 函数原型
void Protocol_Init(void);
void Protocol_ProcessRxData(uint8_t* buf, uint16_t len); // 处理接收数据
uint8_t  Protocol_SendAck(uint8_t originalCmd, uint8_t success, uint8_t errorCode);
uint8_t Protocol_SendSpectrumData(const double* freqs, const double* amps, uint16_t pointCount, uint32_t timestamp);
uint8_t  Protocol_SendStatus(double temp, uint8_t battery, uint8_t errorCode);

// 测试函数
void Protocol_Test(void);
//测试发送2.4GHz CW带噪声的频谱数据（500点） 实时模式
void Protocol_TestSendCW24GHzSpectrum(void);
//测试发送2GHz-3GHz CW带噪声的频谱数据 标准模式
void Protocol_TestSendSegmentedSpectrum(void);

#endif // PROTOCOL_H

#endif /* INC_PROTOCOL_H_ */
