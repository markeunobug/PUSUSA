#ifndef AD8370_H
#define AD8370_H

#include <stdint.h>
#include "xstatus.h"

int ad8370_init(void);
void ad8370_write_code(uint8_t code);
void ad8370_run_startup_test(void);

#endif
