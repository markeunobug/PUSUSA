#include "lo_control.h"

#include "app_config.h"
#include "lock_indicator.h"
#include "lmx2572.h"

static void lo_control_update_lock_indicator(uint8_t device_index, int locked)
{
    lock_indicator_set_lmx(device_index, locked);
}

static void lo_control_update_all_lock_indicators(void)
{
    uint8_t device_index;

    for (device_index = 0U; device_index < 3U; device_index++) {
        lo_control_update_lock_indicator(
            device_index,
            lmx2572_board_is_locked(device_index) ? 1 : 0);
    }
}

int lo_control_init(void)
{
    int status;

    status = lmx2572_board_init();
    if (status != XST_SUCCESS) {
        return status;
    }

    status = lmx2572_board_set_frequency(LO_CONTROL_DEVICE_ADC_CLK,
                                         LMX2572_ADC_CLK_OUTPUT_HZ);
    if (status != XST_SUCCESS) {
        return status;
    }

    status = lo_control_set_lo2_fixed();
    if (status != XST_SUCCESS) {
        return status;
    }

    lo_control_update_all_lock_indicators();

    /* LO2 is fixed in this architecture. If the board is healthy, we should
     * be able to show an immediate lock indication after initialization.
     */
    return lo_control_wait_lock(LO_CONTROL_DEVICE_LO2,
                                LO_CONTROL_INIT_LOCK_TIMEOUT_LOOPS);
}

uint64_t lo_control_calculate_lo1_hz(uint64_t rf_hz)
{
    return rf_hz + LO_CONTROL_IF1_HZ;
}

int lo_control_set_lo1_for_rf_hz(uint64_t rf_hz)
{
    return lmx2572_board_set_frequency(LO_CONTROL_DEVICE_LO1,
                                       lo_control_calculate_lo1_hz(rf_hz));
}

int lo_control_set_lo2_fixed(void)
{
    return lmx2572_board_set_frequency(LO_CONTROL_DEVICE_LO2, LO_CONTROL_LO2_HZ);
}

int lo_control_wait_lock(uint8_t device_index, uint32_t timeout_loops)
{
    uint32_t i;

    lo_control_update_lock_indicator(device_index, 0);

    for (i = 0U; i < timeout_loops; i++) {
        if (lmx2572_board_is_locked(device_index)) {
            lo_control_update_lock_indicator(device_index, 1);
            lo_control_update_all_lock_indicators();
            return XST_SUCCESS;
        }
    }

    lo_control_update_lock_indicator(device_index, 0);
    lo_control_update_all_lock_indicators();
    return XST_FAILURE;
}

int lo_control_is_locked(uint8_t device_index)
{

//	if (device_index == LO_CONTROL_DEVICE_LO1) {
//	        return XST_SUCCESS;
//	    }


    if (lmx2572_board_is_locked(device_index)) {
        lo_control_update_lock_indicator(device_index, 1);
        return XST_SUCCESS;
    }

    lo_control_update_lock_indicator(device_index, 0);
    return XST_FAILURE;
}
