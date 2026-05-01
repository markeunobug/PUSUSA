#ifndef LO_CONTROL_H
#define LO_CONTROL_H

#include <stdint.h>

#include "xstatus.h"

/* Frequency plan:
 * LO1 translates RF(0~1.5 GHz) to IF1 = 2.180 GHz above RF.
 * LO2 is fixed at 2.220 GHz, so IF2 becomes 40 MHz for ADC sampling.
 */
#define LO_CONTROL_IF1_HZ  2180000000ULL
#define LO_CONTROL_LO2_HZ  2220000000ULL
#define LO_CONTROL_IF2_HZ  40000000ULL
#define LO_CONTROL_INIT_LOCK_TIMEOUT_LOOPS 500000U

#define LO_CONTROL_DEVICE_LO1 0U
#define LO_CONTROL_DEVICE_LO2 1U

int lo_control_init(void);
uint64_t lo_control_calculate_lo1_hz(uint64_t rf_hz);
int lo_control_set_lo1_for_rf_hz(uint64_t rf_hz);
int lo_control_set_lo2_fixed(void);
int lo_control_wait_lock(uint8_t device_index, uint32_t timeout_loops);
int lo_control_is_locked(uint8_t device_index);

#endif
