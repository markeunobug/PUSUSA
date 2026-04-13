#include "uart_control.h"

#include "app_config.h"
#include "xil_printf.h"
#include "xuartps_hw.h"

static int ascii_to_uint(const char *text, int *value)
{
    int result = 0;
    int idx = 0;

    if ((text == 0) || (text[0] == '\0')) {
        return 0;
    }

    while (text[idx] != '\0') {
        char ch = text[idx];

        if ((ch < '0') || (ch > '9')) {
            return 0;
        }

        result = result * 10 + (ch - '0');
        idx++;
    }

    *value = result;
    return 1;
}

static void uart_handle_line(const char *line,
                             uart_rbw_callback_t rbw_callback,
                             uart_gain_callback_t gain_callback)
{
    int gain_code;

    if ((line[0] == 'G') || (line[0] == 'g')) {
        if (!ascii_to_uint(&line[1], &gain_code)) {
            xil_printf("GAIN_CMD_ERR,%s\r\n", line);
            return;
        }

        if ((gain_code < 0) || (gain_code > 255)) {
            xil_printf("GAIN_RANGE_ERR,%d\r\n", gain_code);
            return;
        }

        gain_callback(gain_code);
        return;
    }

    if ((line[0] >= '0') && (line[0] <= '4') && (line[1] == '\0')) {
        rbw_callback((int)(line[0] - '0'));
        return;
    }

    xil_printf("UART_CMD_ERR,%s\r\n", line);
}

void uart_control_poll(uart_rbw_callback_t rbw_callback, uart_gain_callback_t gain_callback)
{
    static char cmd_buffer[16];
    static unsigned int cmd_len = 0U;

    while (XUartPs_IsReceiveData(UART_BASEADDR) != 0U) {
        u32 rx_data = XUartPs_ReadReg(UART_BASEADDR, XUARTPS_FIFO_OFFSET);
        char cmd = (char)(rx_data & 0xFFU);

        if ((cmd == '\r') || (cmd == '\n')) {
            if (cmd_len > 0U) {
                cmd_buffer[cmd_len] = '\0';
                uart_handle_line(cmd_buffer, rbw_callback, gain_callback);
                cmd_len = 0U;
            }
            continue;
        }

        if ((cmd_len == 0U) && (cmd >= '0') && (cmd <= '4')) {
            cmd_buffer[0] = cmd;
            cmd_buffer[1] = '\0';
            uart_handle_line(cmd_buffer, rbw_callback, gain_callback);
            continue;
        }

        if (cmd_len < (sizeof(cmd_buffer) - 1U)) {
            cmd_buffer[cmd_len++] = cmd;
        } else {
            cmd_len = 0U;
            xil_printf("UART_CMD_TOO_LONG\r\n");
        }
    }
}
