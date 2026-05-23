#ifndef UART_CONTROL_H
#define UART_CONTROL_H

typedef void (*uart_rbw_callback_t)(int mode);

void uart_control_poll(uart_rbw_callback_t callback);

#endif
