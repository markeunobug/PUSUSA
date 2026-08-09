#ifndef LMX2572_BUS_H
#define LMX2572_BUS_H

#include <stdbool.h>
#include <stdint.h>

#include "lmx2572.h"

int lmx2572_bus_gpio_init(void);
void lmx2572_bus_set_device_idle(LMX2572_Device *dev);
void lmx2572_bus_set_enabled(LMX2572_Device *dev, bool enabled);
void lmx2572_bus_write_register(LMX2572_Device *dev,
                                uint8_t reg_addr,
                                uint16_t data);
uint16_t lmx2572_bus_read_register(LMX2572_Device *dev, uint8_t reg_addr);
int lmx2572_bus_read_mux(LMX2572_Device *dev);

#endif
