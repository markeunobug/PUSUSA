#ifndef UART_CONTROL_H
#define UART_CONTROL_H

typedef void (*uart_rbw_callback_t)(int mode);
typedef void (*uart_gain_callback_t)(int code);

void uart_control_poll(uart_rbw_callback_t rbw_callback, uart_gain_callback_t gain_callback);

#endif
