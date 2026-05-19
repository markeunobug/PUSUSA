#ifndef LMX2572_H
#define LMX2572_H

#include <stdbool.h>
#include <stdint.h>

#include "xstatus.h"

typedef struct {
    uint32_t ce_mask;
    uint32_t csb_mask;
    uint32_t sck_mask;
    uint32_t sdi_mask;
    uint32_t mux_mask;
    double fpd_hz;
    uint16_t reg_config[126];
} LMX2572_Device;

int LMX2572_GpioInit(void);
void LMX2572_Device_Init(LMX2572_Device *dev,
                         uint32_t ce_mask,
                         uint32_t csb_mask,
                         uint32_t sck_mask,
                         uint32_t sdi_mask,
                         uint32_t mux_mask);

void LMX2572_WriteRegister(LMX2572_Device *dev, uint8_t reg_addr, uint16_t data);
uint16_t LMX2572_ReadRegister(LMX2572_Device *dev, uint8_t reg_addr);
void LMX2572_Reset(LMX2572_Device *dev);
void LMX2572_SetEnabled(LMX2572_Device *dev, bool enabled);
void LMX2572_Init(LMX2572_Device *dev);
void LMX2572_Init_Block(LMX2572_Device *dev);
uint32_t LMX2572_SetReferenceFrequency(LMX2572_Device *dev,
                                       uint32_t ref_freq_hz,
                                       uint8_t doubler,
                                       uint8_t pre_r,
                                       uint8_t multiplier,
                                       uint8_t r);
int8_t LMX2572_SetFrequency(LMX2572_Device *dev, uint64_t frequency_hz);
void LMX2572_SetOutputPower(LMX2572_Device *dev, uint8_t ch, int8_t power_dbm);
void LMX2572_SetOutputChannel(LMX2572_Device *dev, uint8_t channel_en);
void LMX2572_SetOutputMux(LMX2572_Device *dev, uint8_t channel, uint8_t source);
bool LMX2572_IsLocked(LMX2572_Device *dev);
void LMX2572_SetMuxFunction(LMX2572_Device *dev, uint8_t mux);

int lmx2572_board_init(void);
int lmx2572_board_set_frequency(uint8_t device_index, uint64_t frequency_hz);
bool lmx2572_board_is_locked(uint8_t device_index);
LMX2572_Device *lmx2572_board_get_device(uint8_t device_index);

#endif
