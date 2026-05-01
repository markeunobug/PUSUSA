#include "../code/lo_control.h"

#include "../code/lock_indicator.h"
#include "../code/lmx2572.h"

int lo_control_init(void)
{
    int status;

    status = lmx2572_board_init();
    if (status != XST_SUCCESS) {
        return status;
    }

    status = lo_control_set_lo2_fixed();
    if (status != XST_SUCCESS) {
        return status;
    }


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

    /* A retune starts in an unlocked state. Only light the indicator once the
     * synthesizer reports a valid lock.
     */
    lock_indicator_set(0);

    for (i = 0U; i < timeout_loops; i++) {
        if (lmx2572_board_is_locked(device_index)) {
            lock_indicator_set(1);
            return XST_SUCCESS;
        }
    }

    lock_indicator_set(0);
    return XST_FAILURE;
}

int lo_control_is_locked(uint8_t device_index)
{
    if (lmx2572_board_is_locked(device_index)) {
        lock_indicator_set(1);
        return XST_SUCCESS;
    }

    return XST_FAILURE;
}
