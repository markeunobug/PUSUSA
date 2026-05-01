#ifndef LOCK_INDICATOR_H
#define LOCK_INDICATOR_H

#include "xstatus.h"

/* PS GPIO numbering: MIO uses 0..53, EMIO[0] starts at 54. The current
 * hardware exports a single EMIO GPIO bit to P19, so we drive pin 54 here.
 */
#define LOCK_INDICATOR_PS_PIN 54U

int lock_indicator_init(void);
void lock_indicator_set(int on);
void lock_indicator_self_test(void);

#endif
