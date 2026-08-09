#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

#include "lmx2572.h"
#include "lmx2572_pfd_profile.h"
#include "lo_control.h"

static unsigned int failures;
static unsigned int apply_count;
static uint8_t applied_profiles[8];
static uint64_t applied_frequencies[8];
static uint8_t active_profile;
static uint8_t p75_qualified;
static uint8_t p75_locks;

/* The P75 CPG below is an arbitrary in-range mock used only to exercise the
 * state machine. It is not a hardware-qualified production value. */
static LMX2572_PfdProfile test_profiles[] = {
    {
        LMX2572_PFD_PROFILE_P100,
        50000000U, 1U, 1U, 1U, 1U,
        100000000ULL, 1ULL, 4U, 3U, 1U,
        2U, 0U, 0U, 0, 0U, 1U, 0, 0U
    },
    {
        LMX2572_PFD_PROFILE_P75,
        50000000U, 0U, 2U, 3U, 1U,
        75000000ULL, 1ULL, 5U, 3U, 1U,
        2U, 0U, 0U, 0, 0U, 1U, 0, 0U
    }
};

#define CHECK_EQ(label, actual, expected)                                     \
    do {                                                                       \
        uint64_t actual_value = (uint64_t)(actual);                             \
        uint64_t expected_value = (uint64_t)(expected);                         \
        if (actual_value != expected_value) {                                   \
            printf("FAIL,%s,actual=%llu,expected=%llu\n",                    \
                   label,                                                      \
                   (unsigned long long)actual_value,                            \
                   (unsigned long long)expected_value);                         \
            failures++;                                                        \
        }                                                                      \
    } while (0)

const LMX2572_PfdProfile *lmx2572_pfd_profile_get(uint8_t profile_id)
{
    if (profile_id >= (uint8_t)LMX2572_PFD_PROFILE_COUNT) {
        return 0;
    }
    test_profiles[LMX2572_PFD_PROFILE_P75].qualified = p75_qualified;
    return &test_profiles[profile_id];
}

int lmx2572_board_init(void)
{
    active_profile = LO_CONTROL_PFD_PROFILE_P100;
    return XST_SUCCESS;
}

int lmx2572_board_set_frequency(uint8_t device_index, uint64_t frequency_hz)
{
    (void)device_index;
    (void)frequency_hz;
    return XST_SUCCESS;
}

int lmx2572_board_apply_pfd_profile(uint8_t device_index,
                                    uint8_t profile_id,
                                    uint64_t frequency_hz)
{
    (void)device_index;
    if (apply_count < sizeof(applied_profiles) / sizeof(applied_profiles[0])) {
        applied_profiles[apply_count] = profile_id;
        applied_frequencies[apply_count] = frequency_hz;
    }
    apply_count++;
    active_profile = profile_id;
    return XST_SUCCESS;
}

bool lmx2572_board_is_locked(uint8_t device_index)
{
    if ((device_index == LO_CONTROL_DEVICE_LO1) &&
        (active_profile == LO_CONTROL_PFD_PROFILE_P75)) {
        return p75_locks != 0U;
    }
    return true;
}

void lock_indicator_set_lmx(uint8_t device_index, int on)
{
    (void)device_index;
    (void)on;
}

static void reset_fakes(void)
{
    unsigned int i;

    apply_count = 0U;
    active_profile = LO_CONTROL_PFD_PROFILE_P100;
    p75_qualified = 1U;
    p75_locks = 1U;
    for (i = 0U; i < sizeof(applied_profiles); i++) {
        applied_profiles[i] = 0xFFU;
        applied_frequencies[i] = 0U;
    }
}

static void test_unqualified_profile_is_rejected(void)
{
    reset_fakes();
    CHECK_EQ("unqualified-init", lo_control_init(), XST_SUCCESS);
    CHECK_EQ("unqualified-request-p100",
             lo_control_set_lo1_pfd_profile(LO_CONTROL_PFD_PROFILE_P100),
             XST_SUCCESS);
    p75_qualified = 0U;
    CHECK_EQ("unqualified-set-rf",
             lo_control_set_lo1_for_rf_hz(500000000ULL),
             XST_SUCCESS);
    CHECK_EQ("unqualified-select",
             lo_control_set_lo1_pfd_profile(LO_CONTROL_PFD_PROFILE_P75),
             XST_FAILURE);
    CHECK_EQ("unqualified-no-apply", apply_count, 0U);
    CHECK_EQ("unqualified-stays-p100",
             lo_control_get_lo1_pfd_profile(),
             LO_CONTROL_PFD_PROFILE_P100);
}

static void test_qualified_profile_switches_at_same_rf(void)
{
    reset_fakes();
    CHECK_EQ("switch-init", lo_control_init(), XST_SUCCESS);
    CHECK_EQ("switch-request-p100",
             lo_control_set_lo1_pfd_profile(LO_CONTROL_PFD_PROFILE_P100),
             XST_SUCCESS);
    CHECK_EQ("switch-set-rf",
             lo_control_set_lo1_for_rf_hz(500000000ULL),
             XST_SUCCESS);
    CHECK_EQ("switch-select-p75",
             lo_control_set_lo1_pfd_profile(LO_CONTROL_PFD_PROFILE_P75),
             XST_SUCCESS);
    CHECK_EQ("switch-apply-count", apply_count, 1U);
    CHECK_EQ("switch-profile",
             applied_profiles[0],
             LO_CONTROL_PFD_PROFILE_P75);
    CHECK_EQ("switch-same-lo1",
             applied_frequencies[0],
             2680000000ULL);
    CHECK_EQ("switch-current-p75",
             lo_control_get_lo1_pfd_profile(),
             LO_CONTROL_PFD_PROFILE_P75);
}

static void test_lock_failure_rolls_back(void)
{
    reset_fakes();
    p75_locks = 0U;
    CHECK_EQ("rollback-init", lo_control_init(), XST_SUCCESS);
    CHECK_EQ("rollback-request-p100",
             lo_control_set_lo1_pfd_profile(LO_CONTROL_PFD_PROFILE_P100),
             XST_SUCCESS);
    CHECK_EQ("rollback-set-rf",
             lo_control_set_lo1_for_rf_hz(500000000ULL),
             XST_SUCCESS);
    CHECK_EQ("rollback-select-p75",
             lo_control_set_lo1_pfd_profile(LO_CONTROL_PFD_PROFILE_P75),
             XST_FAILURE);
    CHECK_EQ("rollback-apply-count", apply_count, 2U);
    CHECK_EQ("rollback-first-p75",
             applied_profiles[0],
             LO_CONTROL_PFD_PROFILE_P75);
    CHECK_EQ("rollback-second-p100",
             applied_profiles[1],
             LO_CONTROL_PFD_PROFILE_P100);
    CHECK_EQ("rollback-same-lo1",
             applied_frequencies[1],
             2680000000ULL);
    CHECK_EQ("rollback-current-p100",
             lo_control_get_lo1_pfd_profile(),
             LO_CONTROL_PFD_PROFILE_P100);
}

static void test_plan_change_rollback_restores_plan_a_lo1(void)
{
    reset_fakes();
    p75_locks = 0U;
    CHECK_EQ("plan-rollback-init", lo_control_init(), XST_SUCCESS);
    CHECK_EQ("plan-rollback-request-p100",
             lo_control_set_lo1_pfd_profile(LO_CONTROL_PFD_PROFILE_P100),
             XST_SUCCESS);
    CHECK_EQ("plan-rollback-request-p75",
             lo_control_set_lo1_pfd_profile(LO_CONTROL_PFD_PROFILE_P75),
             XST_SUCCESS);
    CHECK_EQ("plan-rollback-current-still-p100",
             lo_control_get_lo1_pfd_profile(),
             LO_CONTROL_PFD_PROFILE_P100);
    CHECK_EQ("plan-rollback-set-rf",
             lo_control_set_sweep_frequency_for_rf_hz(1130000000ULL),
             XST_FAILURE);
    CHECK_EQ("plan-rollback-apply-count", apply_count, 2U);
    CHECK_EQ("plan-rollback-p75-plan-b-lo1",
             applied_frequencies[0],
             3320000000ULL);
    CHECK_EQ("plan-rollback-p100-plan-a-lo1",
             applied_frequencies[1],
             3310000000ULL);
}

int main(void)
{
    test_unqualified_profile_is_rejected();
    test_qualified_profile_switches_at_same_rf();
    test_lock_failure_rolls_back();
    test_plan_change_rollback_restores_plan_a_lo1();

    if (failures != 0U) {
        printf("LO_CONTROL_PFD_TESTS_FAILED,%u\n", failures);
        return 1;
    }
    printf("LO_CONTROL_PFD_TESTS_PASSED\n");
    return 0;
}
