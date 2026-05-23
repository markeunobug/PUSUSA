#include "platform.h"
#include "ad8370.h"
#include "dma_capture.h"
#include "signal_processing.h"
#include "uart_control.h"
#include "xil_printf.h"

static void apply_rbw_from_uart(int mode)
{
    signal_processing_apply_rbw_mode((rbw_mode_t)mode);
}

int main(void)
{
    int status;

    init_platform();
    xil_printf("Hello World\r\n");

    status = ad8370_init();
    if (status != XST_SUCCESS) {
        xil_printf("AD8370 init failed: %d\r\n", status);
        cleanup_platform();
        return -1;
    }

    ad8370_run_startup_test();

    signal_processing_init();

    status = dma_capture_init();
    if (status != XST_SUCCESS) {
        xil_printf("DMA init failed: %d\r\n", status);
        cleanup_platform();
        return -1;
    }

    status = dma_capture_start();
    if (status != XST_SUCCESS) {
        xil_printf("DMA start failed: %d\r\n", status);
        dma_capture_shutdown();
        cleanup_platform();
        return -1;
    }

    while (1) {
        uart_control_poll(apply_rbw_from_uart);

        if (dma_capture_frame_ready()) {
            signal_processing_process_frame(dma_capture_get_rx_buffer());

            status = dma_capture_start();
            if (status != XST_SUCCESS) {
                xil_printf("DMA restart failed: %d\r\n", status);
                break;
            }
        }

        if (dma_capture_take_error()) {
            xil_printf("DMA error\r\n");
        }
    }

    dma_capture_shutdown();
    cleanup_platform();
    return 0;
}
