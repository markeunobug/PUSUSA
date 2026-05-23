#ifndef AD8370_H
#define AD8370_H

#include <stdint.h>
#include "arm_math.h"
#include "xstatus.h"

int ad8370_init(void);
void ad8370_write_code(uint8_t code);
void ad8370_set_gain_code(uint8_t code);
uint8_t ad8370_get_gain_code(void);
float32_t ad8370_get_theoretical_gain_db(uint8_t code);
void ad8370_run_startup_test(void);

#endif
