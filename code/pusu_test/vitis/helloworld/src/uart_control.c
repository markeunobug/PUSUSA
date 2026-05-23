#include "uart_control.h"

#include "app_config.h"
#include "xil_printf.h"
#include "xuartps_hw.h"

void uart_control_poll(uart_rbw_callback_t callback)
{
    if (XUartPs_IsReceiveData(UART_BASEADDR) != 0U) {
        u32 rx_data = XUartPs_ReadReg(UART_BASEADDR, XUARTPS_FIFO_OFFSET);
        char cmd = (char)(rx_data & 0xFFU);

        switch (cmd) {
        case '0':
        case '1':
        case '2':
        case '3':
        case '4':
            callback((int)(cmd - '0'));
            break;
        default:
            xil_printf("RBW_CMD_ERR,%c\r\n", cmd);
            break;
        }
    }
}
