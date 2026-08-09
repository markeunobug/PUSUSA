#ifndef TEST_XGPIO_H
#define TEST_XGPIO_H

#include <stdint.h>

typedef struct {
    uint32_t input_value;
    uint32_t output_value;
} XGpio;

static inline int XGpio_Initialize(XGpio *gpio, uint16_t device_id)
{
    (void)device_id;
    gpio->input_value = 0U;
    gpio->output_value = 0U;
    return 0;
}

static inline void XGpio_SetDataDirection(XGpio *gpio,
                                         unsigned int channel,
                                         uint32_t mask)
{
    (void)gpio;
    (void)channel;
    (void)mask;
}

static inline void XGpio_DiscreteWrite(XGpio *gpio,
                                       unsigned int channel,
                                       uint32_t value)
{
    (void)channel;
    gpio->output_value = value;
}

static inline uint32_t XGpio_DiscreteRead(XGpio *gpio, unsigned int channel)
{
    (void)channel;
    return gpio->input_value;
}

#endif
