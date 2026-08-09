#include "lo_control.h"

#include "app_config.h"
#include "lock_indicator.h"
#include "lmx2572.h"
#include "lmx2572_pfd_profile.h"

#define LO_CONTROL_PLAN_A 0U
#define LO_CONTROL_PLAN_B 1U

static uint8_t g_current_plan = LO_CONTROL_PLAN_A;
static uint8_t g_current_pfd_profile = LO_CONTROL_PFD_PROFILE_P100;
static uint8_t g_requested_pfd_profile = LO_CONTROL_PFD_PROFILE_P100;
static uint64_t g_last_rf_hz;
static uint8_t g_last_rf_valid;

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
    uint8_t previous_plan = g_current_plan;
    uint64_t if1_hz = (plan == LO_CONTROL_PLAN_B)
        ? LO_CONTROL_IF1_PLAN_B_HZ
        : LO_CONTROL_IF1_HZ;
    uint64_t lo2_hz = (plan == LO_CONTROL_PLAN_B)
        ? LO_CONTROL_LO2_PLAN_B_HZ
        : LO_CONTROL_LO2_HZ;

    if (plan != previous_plan) {
        if (lmx2572_board_set_frequency(LO_CONTROL_DEVICE_LO2, lo2_hz) != XST_SUCCESS) {
            return XST_FAILURE;
        }
    }

    if (g_requested_pfd_profile != g_current_pfd_profile) {
        const LMX2572_PfdProfile *requested_profile =
            lmx2572_pfd_profile_get(g_requested_pfd_profile);
        const LMX2572_PfdProfile *rollback_profile =
            lmx2572_pfd_profile_get(g_current_pfd_profile);
        uint64_t lo1_hz = rf_hz + if1_hz;

        if ((requested_profile == 0) || (rollback_profile == 0) ||
            (lmx2572_board_apply_pfd_profile(
                 LO_CONTROL_DEVICE_LO1,
                 g_requested_pfd_profile,
                 lo1_hz) != XST_SUCCESS) ||
            (lo_control_wait_lock(
                 LO_CONTROL_DEVICE_LO1,
                 requested_profile->lock_timeout_loops) != XST_SUCCESS)) {
            uint64_t rollback_rf_hz = (g_last_rf_valid != 0U)
                ? g_last_rf_hz
                : rf_hz;
            uint64_t rollback_if1_hz =
                (previous_plan == LO_CONTROL_PLAN_B)
                    ? LO_CONTROL_IF1_PLAN_B_HZ
                    : LO_CONTROL_IF1_HZ;
            (void)lmx2572_board_apply_pfd_profile(
                LO_CONTROL_DEVICE_LO1,
                g_current_pfd_profile,
                rollback_rf_hz + rollback_if1_hz);
            (void)lo_control_wait_lock(
                LO_CONTROL_DEVICE_LO1,
                rollback_profile != 0
                    ? rollback_profile->lock_timeout_loops
                    : LO_CONTROL_INIT_LOCK_TIMEOUT_LOOPS);
            if (plan != previous_plan) {
                uint64_t previous_lo2_hz = (previous_plan == LO_CONTROL_PLAN_B)
                    ? LO_CONTROL_LO2_PLAN_B_HZ
                    : LO_CONTROL_LO2_HZ;
                (void)lmx2572_board_set_frequency(
                    LO_CONTROL_DEVICE_LO2,
                    previous_lo2_hz);
            }
            return XST_FAILURE;
        }
        g_current_pfd_profile = g_requested_pfd_profile;
    } else if (lmx2572_board_set_frequency(
                   LO_CONTROL_DEVICE_LO1,
                   rf_hz + if1_hz) != XST_SUCCESS) {
        if (plan != previous_plan) {
            uint64_t previous_lo2_hz = (previous_plan == LO_CONTROL_PLAN_B)
                ? LO_CONTROL_LO2_PLAN_B_HZ
                : LO_CONTROL_LO2_HZ;
            (void)lmx2572_board_set_frequency(
                LO_CONTROL_DEVICE_LO2,
                previous_lo2_hz);
        }
        return XST_FAILURE;
    }

    g_current_plan = plan;
    g_last_rf_hz = rf_hz;
    g_last_rf_valid = 1U;
    return XST_SUCCESS;
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

    g_current_pfd_profile = LO_CONTROL_PFD_PROFILE_P100;
    g_requested_pfd_profile = LO_CONTROL_PFD_PROFILE_P100;
    g_last_rf_hz = 0U;
    g_last_rf_valid = 0U;
    if ((LO_CONTROL_DEFAULT_PFD_PROFILE != LO_CONTROL_PFD_PROFILE_P100) &&
        (lo_control_set_lo1_pfd_profile(
             LO_CONTROL_DEFAULT_PFD_PROFILE) != XST_SUCCESS)) {
        return XST_FAILURE;
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

int lo_control_set_lo1_pfd_profile(uint8_t profile_id)
{
    const LMX2572_PfdProfile *profile =
        lmx2572_pfd_profile_get(profile_id);
    uint8_t previous_requested = g_requested_pfd_profile;

    if ((profile == 0) || (profile->qualified == 0U)) {
        return XST_FAILURE;
    }

    g_requested_pfd_profile = profile_id;
    if ((g_last_rf_valid != 0U) &&
        (lo_control_apply_plan_for_rf_hz(g_last_rf_hz,
                                         g_current_plan) != XST_SUCCESS)) {
        g_requested_pfd_profile = previous_requested;
        return XST_FAILURE;
    }
    return XST_SUCCESS;
}

uint8_t lo_control_get_lo1_pfd_profile(void)
{
    return g_current_pfd_profile;
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
