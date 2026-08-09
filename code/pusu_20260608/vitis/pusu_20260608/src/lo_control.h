#ifndef LO_CONTROL_H
#define LO_CONTROL_H

#include <stdint.h>

#include "app_config.h"
#include "xstatus.h"

/* Set to 0U to restore the original fixed 2180/2220 MHz frequency plan. */
#ifndef LO_CONTROL_SPUR_AVOIDANCE_ENABLE
#define LO_CONTROL_SPUR_AVOIDANCE_ENABLE 1U
#endif

/* Normal plan A and experimental spur-avoidance plan B. Both keep IF2 at
 * 40 MHz. Plan B is selected only when plan A predicts the internal spur
 * within 4 MHz of the active IF center.
 */
#define LO_CONTROL_IF1_HZ          2180000000ULL
#define LO_CONTROL_LO2_HZ          2220000000ULL
#define LO_CONTROL_IF1_PLAN_B_HZ   2190000000ULL
#define LO_CONTROL_LO2_PLAN_B_HZ   2230000000ULL
#define LO_CONTROL_IF2_HZ  40000000ULL
#define LO_CONTROL_SPUR_GUARD_HZ   4000000ULL
#define LO_CONTROL_INIT_LOCK_TIMEOUT_LOOPS LMX2572_PROFILE_LOCK_TIMEOUT_LOOPS

#define LO_CONTROL_DEVICE_ADC_CLK 0U
#define LO_CONTROL_DEVICE_LO1     1U
#define LO_CONTROL_DEVICE_LO2     2U

#define LO_CONTROL_PFD_PROFILE_P100 0U
#define LO_CONTROL_PFD_PROFILE_P75  1U

int lo_control_init(void);
uint64_t lo_control_calculate_lo1_hz(uint64_t rf_hz);
int lo_control_set_lo1_for_rf_hz(uint64_t rf_hz);
int lo_control_set_sweep_frequency_for_rf_hz(uint64_t rf_hz);
int lo_control_set_lo1_pfd_profile(uint8_t profile_id);
uint8_t lo_control_get_lo1_pfd_profile(void);
int lo_control_set_lo2_fixed(void);
int lo_control_wait_lock(uint8_t device_index, uint32_t timeout_loops);
int lo_control_is_locked(uint8_t device_index);

#endif
