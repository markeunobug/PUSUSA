#include "lo_control.h"

#include "app_config.h"
#include "lock_indicator.h"
#include "lmx2572.h"

#define LO_CONTROL_PLAN_A 0U
#define LO_CONTROL_PLAN_B 1U

static uint8_t g_current_plan = LO_CONTROL_PLAN_A;

static uint64_t lo_control_abs_diff_u64(uint64_t a, uint64_t b)
{
    return (a >= b) ? (a - b) : (b - a);
}

static uint8_t lo_control_select_sweep_plan(uint64_t rf_hz)
{
#if LO_CONTROL_SPUR_AVOIDANCE_ENABLE
    uint64_t spur_a_hz = lo_control_abs_diff_u64(2ULL * rf_hz,
                                                 2300000000ULL);
    uint64_t distance_a_hz = lo_control_abs_diff_u64(spur_a_hz,
                                                      LO_CONTROL_IF2_HZ);

    if (distance_a_hz < LO_CONTROL_SPUR_GUARD_HZ) {
        return LO_CONTROL_PLAN_B;
    }
#else
    (void)rf_hz;
#endif

    return LO_CONTROL_PLAN_A;
}

static int lo_control_apply_plan_for_rf_hz(uint64_t rf_hz, uint8_t plan)
{
    uint64_t if1_hz = (plan == LO_CONTROL_PLAN_B)
        ? LO_CONTROL_IF1_PLAN_B_HZ
        : LO_CONTROL_IF1_HZ;
    uint64_t lo2_hz = (plan == LO_CONTROL_PLAN_B)
        ? LO_CONTROL_LO2_PLAN_B_HZ
        : LO_CONTROL_LO2_HZ;

    if (plan != g_current_plan) {
        if (lmx2572_board_set_frequency(LO_CONTROL_DEVICE_LO2, lo2_hz) != XST_SUCCESS) {
            return XST_FAILURE;
        }
        g_current_plan = plan;
    }

    return lmx2572_board_set_frequency(LO_CONTROL_DEVICE_LO1, rf_hz + if1_hz);
}

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
    return lo_control_apply_plan_for_rf_hz(rf_hz, LO_CONTROL_PLAN_A);
}

int lo_control_set_sweep_frequency_for_rf_hz(uint64_t rf_hz)
{
    return lo_control_apply_plan_for_rf_hz(
        rf_hz,
        lo_control_select_sweep_plan(rf_hz));
}

int lo_control_set_lo2_fixed(void)
{
    int status = lmx2572_board_set_frequency(LO_CONTROL_DEVICE_LO2,
                                             LO_CONTROL_LO2_HZ);

    if (status == XST_SUCCESS) {
        g_current_plan = LO_CONTROL_PLAN_A;
    }
    return status;
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
#if LO_CONTROL_SPUR_AVOIDANCE_ENABLE
    if (device_index == LO_CONTROL_DEVICE_LO1) {
        int lo1_locked = lmx2572_board_is_locked(LO_CONTROL_DEVICE_LO1) ? 1 : 0;
        int lo2_locked = lmx2572_board_is_locked(LO_CONTROL_DEVICE_LO2) ? 1 : 0;

        lo_control_update_lock_indicator(LO_CONTROL_DEVICE_LO1, lo1_locked);
        lo_control_update_lock_indicator(LO_CONTROL_DEVICE_LO2, lo2_locked);
        return (lo1_locked && lo2_locked) ? XST_SUCCESS : XST_FAILURE;
    }
#endif

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
