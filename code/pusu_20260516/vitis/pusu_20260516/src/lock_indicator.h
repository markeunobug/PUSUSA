#ifndef LOCK_INDICATOR_H
#define LOCK_INDICATOR_H

#include <stdint.h>

#include "xstatus.h"

/* PS GPIO numbering: MIO uses 0..53, EMIO[0] starts at 54. The hardware
 * exports four EMIO GPIO bits to four LEDs. LED1/EMIO[0] is reserved here;
 * LED2..LED4/EMIO[1]..EMIO[3] indicate LMX2572_0..LMX2572_2 lock.
 */
#define LOCK_INDICATOR_FIRST_PS_PIN 54U
#define LOCK_INDICATOR_COUNT        4U
#define LOCK_INDICATOR_LO0_PS_PIN   55U
#define LOCK_INDICATOR_LO1_PS_PIN   56U
#define LOCK_INDICATOR_LO2_PS_PIN   57U

int lock_indicator_init(void);
void lock_indicator_set(int on);
void lock_indicator_set_lmx(uint8_t device_index, int on);
void lock_indicator_toggle_activity(void);
void lock_indicator_self_test(void);

#endif
