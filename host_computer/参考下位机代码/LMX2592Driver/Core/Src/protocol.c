/*
 * protocol.c
 *
 *  Created on: Feb 25, 2026
 *      Author: 10663
 */

// 文件: protocol.c
// STM32G431 下位机通信协议库实现文件
// 假设使用USB CDC虚拟串口，需包含usbd_cdc_if.h或类似，并使用CDC_Transmit_FS发送

#include "protocol.h"
#include "usbd_cdc_if.h" // 假设路径，STM32 USB CDC接口
#include <string.h>
#include <math.h> // 对于double处理
#include "LMX2592.h"
#include "usbd_def.h"

// CRC16 Modbus计算函数
uint16_t Calculate_CRC16(const uint8_t* data, uint16_t len) {
    uint16_t crc = 0xFFFF;
    for (uint16_t i = 0; i < len; i++) {
        crc ^= (uint16_t)data[i];
        for (uint8_t j = 0; j < 8; j++) {
            if (crc & 0x0001) {
                crc = (crc >> 1) ^ 0xA001;
            } else {
                crc >>= 1;
            }
        }
    }
    return crc;
}

// 构建帧并发送
static uint8_t  Send_Frame(uint8_t cmd, const uint8_t* data, uint16_t dataLen) {
    uint8_t frame[5 + dataLen + 2]; // Start + Len(2) + Cmd + Data + CRC(2) + End
    frame[0] = 0xAA;
    frame[1] = (dataLen >> 8) & 0xFF; // Length MSB
    frame[2] = dataLen & 0xFF;        // Length LSB
    frame[3] = cmd;
    if (dataLen > 0) {
        memcpy(&frame[4], data, dataLen);
    }
    uint16_t crc = Calculate_CRC16(&frame[1], 3 + dataLen); // 计算Length+Cmd+Data
    frame[4 + dataLen] = (crc >> 8) & 0xFF;
    frame[5 + dataLen] = crc & 0xFF;
    frame[6 + dataLen] = 0x55;

    // 使用虚拟串口发送（USB CDC），捕获返回值并返回
    uint8_t send_result = CDC_Transmit_FS(frame, 7 + dataLen);
    return send_result;
}

// 全局变量（示例，存储配置）
static double startFreq = 0, stopFreq = 10e9, centerFreq = 5e9, span = 10e9;
static double refLevel = 0;
static uint8_t attenuator = 0, preamp = 0;  // 0=auto
static uint8_t rbwMode = 0; double rbwHz = 0;
static uint8_t vbwMode = 0; double vbwHz = 0;
static uint8_t detectMode = 0;  // 0=平均 等
static double sweepSpeed = 30; uint8_t sweepMode = 0;  // fps, mode=0单次

// 处理命令（完善数据解析与全局变量赋值）
static void Handle_Command(uint8_t cmd, const uint8_t* data, uint16_t len) {
    switch (cmd) {
        case CMD_SET_FREQ:
            if (len != 32) {
                Protocol_SendAck(cmd, 0, ERR_INVALID_DATA);
                return;
            }
            // 解析4个double（各8字节）：start, stop, center, span
            startFreq = *(double*)(data + 0);    // 0-7字节：起始频率
            stopFreq = *(double*)(data + 8);     // 8-15字节：终止频率
            centerFreq = *(double*)(data + 16);  // 16-23字节：中心频率
            span = *(double*)(data + 24);        // 24-31字节：频率跨度
            // （可选）添加硬件频率配置逻辑
            Protocol_SendAck(cmd, 1, ERR_SUCCESS);
            break;

        case CMD_SET_AMPLITUDE:
            if (len != 10) {
                Protocol_SendAck(cmd, 0, ERR_INVALID_DATA);
                return;
            }
            // 解析：8字节double(refLevel) + 1字节attenuator + 1字节preamp
            refLevel = *(double*)(data + 0);     // 0-7字节：参考电平
            attenuator = *(uint8_t*)(data + 8);  // 第8字节：衰减器
            preamp = *(uint8_t*)(data + 9);      // 第9字节：前置放大器
            // （可选）添加硬件幅度配置逻辑
            Protocol_SendAck(cmd, 1, ERR_SUCCESS);
            break;

        case CMD_SET_BW:
            if (len != 18) {
                Protocol_SendAck(cmd, 0, ERR_INVALID_DATA);
                return;
            }
            // 修复：用memcpy拷贝到对齐的临时变量，避免直接访问非对齐地址
            uint8_t tempRbwMode = data[0]; // RBW模式（1字节）
            double tempRbwHz = 0.0;
            memcpy(&tempRbwHz, data + 1, 8); // 拷贝1-8字节到对齐的tempRbwHz

            uint8_t tempVbwMode = data[9]; // VBW模式（1字节）
            double tempVbwHz = 0.0;
            memcpy(&tempVbwHz, data + 10, 8); // 拷贝10-17字节到对齐的tempVbwHz

            // 赋值到全局变量（替换原有直接解析逻辑）
            rbwMode = tempRbwMode;
            rbwHz = tempRbwHz;
            vbwMode = tempVbwMode;
            vbwHz = tempVbwHz;

            // （可选）添加硬件带宽配置逻辑
            Protocol_SendAck(cmd, 1, ERR_SUCCESS);
            break;

        case CMD_SET_DETECT:
            if (len != 1) {
                Protocol_SendAck(cmd, 0, ERR_INVALID_DATA);
                return;
            }
            // 解析：1字节检测模式
            detectMode = *(uint8_t*)(data + 0);  // 第0字节：检测模式
            // （可选）添加硬件检测模式配置逻辑
            Protocol_SendAck(cmd, 1, ERR_SUCCESS);
            break;

        case CMD_SET_SWEEP:
            if (len != 9) {
                Protocol_SendAck(cmd, 0, ERR_INVALID_DATA);
                return;
            }
            // 解析：8字节double(sweepSpeed) + 1字节sweepMode
            sweepSpeed = *(double*)(data + 0);   // 0-7字节：扫频速度
            sweepMode = *(uint8_t*)(data + 8);   // 第8字节：扫频模式
            // （可选）添加硬件扫频配置逻辑
            Protocol_SendAck(cmd, 1, ERR_SUCCESS);
            break;

        case CMD_GET_SPECTRUM:
            // 示例: 发送谱数据（在测试中使用固定数据）
            // 实际中采集数据
            Protocol_SendAck(cmd, 1, ERR_SUCCESS);
            // 模拟发送
            double freqs[3] = {1000.0, 2000.0, 3000.0};
            double amps[3] = {-50.0, -60.0, -55.0};
            Protocol_SendSpectrumData(freqs, amps, 3, 123456);
            break;

        case CMD_GET_STATUS:
            // 示例状态（可替换为全局变量的实际值）
            Protocol_SendAck(cmd, 1, ERR_SUCCESS);
            Protocol_SendStatus(25.5, 80, ERR_SUCCESS);
            break;

        case CMD_RESET:
            // 重置全局变量为默认值
            startFreq = 0; stopFreq = 10e9; centerFreq = 5e9; span = 10e9;
            refLevel = 0; attenuator = 0; preamp = 0;
            rbwMode = 0; rbwHz = 0; vbwMode = 0; vbwHz = 0;
            detectMode = 0;
            sweepSpeed = 30; sweepMode = 0;
            // （可选）添加硬件重置逻辑
            Protocol_SendAck(cmd, 1, ERR_SUCCESS);
            break;

        default:
            Protocol_SendAck(cmd, 0, ERR_INVALID_CMD);
            break;
    }
}

// 初始化
void Protocol_Init(void) {
    // 任何初始化
}

// 处理接收数据（在USB Rx回调中调用，如App_USBD_CDC_Receive_FS）
void Protocol_ProcessRxData(uint8_t* buf, uint16_t len) {
    // 简单解析（假设单帧，实际需处理粘包）
    if (len < 7 || buf[0] != 0xAA || buf[len-1] != 0x55) return;

    uint16_t dataLen = (buf[1] << 8) | buf[2];
    if (len != 7 + dataLen) return;

    uint8_t cmd = buf[3];
    uint16_t rxCrc = (buf[4 + dataLen] << 8) | buf[5 + dataLen];
    uint16_t calcCrc = Calculate_CRC16(&buf[1], 3 + dataLen);
    if (rxCrc != calcCrc) return;

    uint8_t* data = &buf[4];
    Handle_Command(cmd, data, dataLen);
}

// 发送ACK
uint8_t  Protocol_SendAck(uint8_t originalCmd, uint8_t success, uint8_t errorCode) {
    uint8_t data[3] = {originalCmd, success, errorCode};
    return Send_Frame(RESP_ACK, data, 3);
}

// 发送谱数据
uint8_t  Protocol_SendSpectrumData(const double* freqs, const double* amps, uint16_t pointCount, uint32_t timestamp) {
    uint16_t dataLen = 6 + pointCount * 16; // pointCount(2) + ts(4) + (freq+amp)*pointCount
    uint8_t* data = (uint8_t*)malloc(dataLen);
    if (!data) return USBD_FAIL;

    data[0] = (pointCount >> 8) & 0xFF;
    data[1] = pointCount & 0xFF;
    data[2] = (timestamp >> 24) & 0xFF;
    data[3] = (timestamp >> 16) & 0xFF;
    data[4] = (timestamp >> 8) & 0xFF;
    data[5] = timestamp & 0xFF;

    for (uint16_t i = 0; i < pointCount; i++) {
        uint16_t offset = 6 + i * 16;
        memcpy(&data[offset], &freqs[i], 8);
        memcpy(&data[offset + 8], &amps[i], 8);
    }

    // 调用Send_Frame并获取发送结果
    uint8_t send_result = Send_Frame(RESP_SPECTRUM_DATA, data, dataLen);
    free(data);

    // 返回USB发送结果（0=成功，非0=失败/忙）
    return send_result;
}

// 发送状态
uint8_t  Protocol_SendStatus(double temp, uint8_t battery, uint8_t errorCode) {
    uint8_t data[10];
    memcpy(data, &temp, 8);
    data[8] = battery;
    data[9] = errorCode;
    return Send_Frame(RESP_STATUS_DATA, data, 10);
}

// 测试函数：使用固定数据测试协议
void Protocol_Test(void) {
    // 模拟接收SET_FREQ命令
    uint8_t rxBuf[39]; // Start+Len(2)+Cmd+Data(32)+CRC(2)+End = 39
    rxBuf[0] = 0xAA;
    rxBuf[1] = 0x00; rxBuf[2] = 0x20; // Len=32
    rxBuf[3] = CMD_SET_FREQ;
    // 填充Data: 示例0.0, 10e9, 5e9, 10e9
    double start = 0.0, stop = 10000000000.0, center = 5000000000.0, span = 10000000000.0;
    memcpy(&rxBuf[4], &start, 8);
    memcpy(&rxBuf[12], &stop, 8);
    memcpy(&rxBuf[20], &center, 8);
    memcpy(&rxBuf[28], &span, 8);
    uint16_t crc = Calculate_CRC16(&rxBuf[1], 35); // Len+Cmd+Data=35
    rxBuf[36] = (crc >> 8) & 0xFF;
    rxBuf[37] = crc & 0xFF;
    rxBuf[38] = 0x55;

    Protocol_ProcessRxData(rxBuf, 39); // 应发送ACK

    // 模拟GET_SPECTRUM
    uint8_t rxGet[7] = {0xAA, 0x00, 0x00, CMD_GET_SPECTRUM, 0x00, 0x00, 0x55}; // 需计算CRC
    crc = Calculate_CRC16(&rxGet[1], 3);
    rxGet[4] = (crc >> 8) & 0xFF;
    rxGet[5] = crc & 0xFF;
    Protocol_ProcessRxData(rxGet, 7); // 应发送ACK和SPECTRUM_DATA
}

// 简易伪随机数生成（用于噪声，线性同余法）
static int32_t Simple_Random(int32_t min, int32_t max) {
    static uint32_t seed = 0x12345678; // 初始种子
    seed = seed * 1103515245 + 12345; // 标准线性同余公式
    uint32_t rand_val = (uint32_t)(seed / 65536) % 32768;
    return min + (rand_val % (max - min + 1));
}

// 测试函数：生成2.4GHz单频CW带噪声的100点频谱数据并发送
void Protocol_TestSendCW24GHzSpectrum(void) {
    // 1. 配置频谱参数：100点，频率范围
    #define TEST_POINT_COUNT 500
    double freqs[TEST_POINT_COUNT];    // 频率数组（Hz）
    double amps[TEST_POINT_COUNT];     // 幅值数组（dBm）
    const double center_freq = 2400000000.0; // 2.4GHz
    const double freq_start = 2300000000.0; // 起始频率2.3GHz
    const double freq_end = 2500000000.0;   // 结束频率2.5GHz
    const double step = (freq_end - freq_start) / (TEST_POINT_COUNT - 1); // 频率步长

    // 2. 生成频率数组 + 幅值（噪声+信号）
    int target_index = -1; // 2.4GHz对应的数组索引
    for (int i = 0; i < TEST_POINT_COUNT; i++) {
        // 计算当前点频率
        freqs[i] = freq_start + i * step;

        // 生成基础噪声：-80dBm ±5dB
        double noise = -80.0 + Simple_Random(-50, 50) / 10.0;
        amps[i] = noise;

        // 找到2.4GHz对应的点（误差±1000kHz内视为目标点）
        if (fabs(freqs[i] - center_freq) < 1000000.0) {
            target_index = i;
        }
    }

    // 3. 给2.4GHz目标点添加CW信号（-40dBm ±1dB）
    if (target_index >= 0) {
        amps[target_index] = -20.0 + Simple_Random(-10, 10) / 10.0;
    }

    // 4. 获取时间戳（使用HAL系统滴答，若无HAL则替换为固定值如12345678）
    uint32_t timestamp = HAL_GetTick();

    // 5. 发送ACK + 频谱数据到上位机
    Protocol_SendAck(CMD_GET_SPECTRUM, 1, ERR_SUCCESS);

    // 接收发送结果并做基础判断（防止缓冲区溢出）
    uint8_t send_status = Protocol_SendSpectrumData(freqs, amps, TEST_POINT_COUNT, timestamp);
    if (send_status != USBD_OK) {
        // 发送失败处理逻辑（示例：可添加日志/LED提示/重试等）
        // 例如：LED闪烁提示USB发送失败，或延迟重试
        // 此处仅做示例，可根据实际需求扩展
    	LED_LD(1); // 假设LED_PIN已定义
        HAL_Delay(10);
    	LED_LD(0);
    }

    // 调试提示（可选，若有串口打印可开启）
    // printf("已发送2.4GHz CW带噪声频谱数据（%d点），时间戳：%lu\r\n", TEST_POINT_COUNT, timestamp);
}

/**
 * @brief 分段发送测试函数（模拟真实大扫宽扫描）
 *        频率范围：2.0 GHz ~ 3.0 GHz（1 GHz 扫宽）
 *        信号：
 *          • 2.4 GHz 处强 CW 单音：-10 dBm
 *          • 2.6 GHz 处中等 CW 单音：-50 dBm
 *        底噪：全带宽 -90 dBm ±7 dB 随机噪声
 *        分 10 段发送（每段 80 点），每次调用发送 1 段，实现从左到右扫频推进效果
 *        在 main.c 的 while(1) 中调用即可连续扫频
 */
void Protocol_TestSendSegmentedSpectrum(void)
{
    #define SEGMENTS        20
    #define POINTS_PER_SEG  100
    #define TOTAL_POINTS    (SEGMENTS * POINTS_PER_SEG)

    static uint8_t currentSegment = 0;   // 段索引（静态，断电不丢失）

    const double fStartTotal = 2000000000.0;   // 2.0 GHz
    const double fStopTotal  = 3000000000.0;   // 3.0 GHz
    const double totalSpan   = fStopTotal - fStartTotal;   // 1 GHz
    const double segSpan     = totalSpan / SEGMENTS;       // 每段 50 MHz

    double freqs[POINTS_PER_SEG];
    double amps[POINTS_PER_SEG];

    // 当前段起始频率
    double segStartFreq = fStartTotal + currentSegment * segSpan;

    // 生成当前段数据
    for (int i = 0; i < POINTS_PER_SEG; i++) {
        double t = (double)i / (POINTS_PER_SEG - 1);
        freqs[i] = segStartFreq + t * segSpan;

        // 底噪 -90 dBm ±7 dB 随机噪声
        amps[i] = -90.0 + (Simple_Random(-70, 70) / 10.0);

        // 2.4 GHz 强 CW 信号（-10 dBm）
        if (fabs(freqs[i] - 2400000000.0) < (segSpan / POINTS_PER_SEG * 2.0)) {
            amps[i] = -10.0 + (Simple_Random(-10, 10) / 10.0);
        }
        // 2.6 GHz 中等 CW 信号（-50 dBm）
        else if (fabs(freqs[i] - 2600000000.0) < (segSpan / POINTS_PER_SEG * 2.0)) {
            amps[i] = -50.0 + (Simple_Random(-8, 8) / 10.0);
        }
    }

    uint32_t timestamp = HAL_GetTick();

    // 先回复 ACK（让上位机知道命令被接受）
    Protocol_SendAck(CMD_GET_SPECTRUM, 1, ERR_SUCCESS);

    // 发送当前段数据
    uint8_t sendResult = Protocol_SendSpectrumData(freqs, amps, POINTS_PER_SEG, timestamp);

    if (sendResult != USBD_OK) {
        // 发送失败时闪烁 LED 提示
        LED_LD(1);
        HAL_Delay(5);
        LED_LD(0);
    }

    // 切换到下一段（循环）
    currentSegment = (currentSegment + 1) % SEGMENTS;
}
