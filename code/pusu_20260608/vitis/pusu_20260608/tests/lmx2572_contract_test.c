#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "lmx2572.h"
#include "lmx2572_frequency.h"
#include "lmx2572_pfd_profile.h"
#include "lmx2572_registers.h"

static unsigned int failures;

#define CHECK_EQ_U64(label, actual, expected)                                  \
    do {                                                                       \
        uint64_t actual_value = (uint64_t)(actual);                             \
        uint64_t expected_value = (uint64_t)(expected);                         \
        if (actual_value != expected_value) {                                   \
            printf("FAIL,%s,actual=%" PRIu64 ",expected=%" PRIu64 "\n",       \
                   label, actual_value, expected_value);                        \
            failures++;                                                        \
        }                                                                      \
    } while (0)

#define CHECK_STATUS(label, actual, expected)                                  \
    CHECK_EQ_U64(label, (int)(actual), (int)(expected))

typedef struct {
    uint64_t output_hz;
    uint16_t r36;
    uint16_t r37;
    uint16_t r42;
    uint16_t r43;
    uint16_t r45;
    uint16_t r46;
    uint16_t r75;
} golden_frequency_t;

static uint64_t register_image_fingerprint(const uint16_t *image)
{
    uint64_t hash = 14695981039346656037ULL;
    unsigned int i;

    for (i = 0U; i < LMX2572_REGISTER_COUNT; i++) {
        hash ^= image[i];
        hash *= 1099511628211ULL;
    }
    return hash;
}

static void test_authoritative_p100_image(void)
{
    LMX2572_Device dev;

    LMX2572_Device_Init(&dev, 1U, 2U, 4U, 8U, 1U);
    CHECK_EQ_U64("p100-image-fingerprint",
                 register_image_fingerprint(dev.reg_config),
                 0xEDD9A99D818B8D77ULL);
}

static void init_p100(LMX2572_Device *dev)
{
    LMX2572_Device_Init(dev, 1U, 2U, 4U, 8U, 1U);
    CHECK_EQ_U64("p100-return",
                 LMX2572_SetReferenceFrequency(
                     dev, 50000000U, 1U, 1U, 1U, 1U),
                 100000000U);
    CHECK_EQ_U64("p100-num", dev->fpd_num_hz, 100000000U);
    CHECK_EQ_U64("p100-den", dev->fpd_den, 1U);
    CHECK_EQ_U64("p100-r0",
                 lmx2572_shadow_get(dev->reg_config, LMX2572_R0),
                 0x2318U);
    CHECK_EQ_U64("p100-r9",
                 lmx2572_shadow_get(dev->reg_config, LMX2572_R9),
                 0x1004U);
    CHECK_EQ_U64("p100-r10",
                 lmx2572_shadow_get(dev->reg_config, LMX2572_R10),
                 0x10F8U);
}

static void test_public_api_contract(void)
{
    uint32_t (*set_reference)(LMX2572_Device *, uint32_t, uint8_t,
                              uint8_t, uint8_t, uint8_t) =
        LMX2572_SetReferenceFrequency;
    int8_t (*set_frequency)(LMX2572_Device *, uint64_t) =
        LMX2572_SetFrequency;
    int (*board_set_frequency)(uint8_t, uint64_t) =
        lmx2572_board_set_frequency;

    CHECK_EQ_U64("api-set-reference", set_reference != 0, 1U);
    CHECK_EQ_U64("api-set-frequency", set_frequency != 0, 1U);
    CHECK_EQ_U64("api-board-frequency", board_set_frequency != 0, 1U);
}

static void test_p100_golden_registers(void)
{
    static const golden_frequency_t golden[] = {
        {130000000ULL, 0x0029U, 0x0205U, 0x9999U, 0x9999U,
         0xC61EU, 0x07F0U, 0xF9C0U},
        {1000000000ULL, 0x0028U, 0x0205U, 0x0000U, 0x0000U,
         0xC61EU, 0x07F0U, 0xF840U},
        {2230000000ULL, 0x002CU, 0x0205U, 0x9999U, 0x9999U,
         0xC61EU, 0x07F0U, 0xF800U},
        {3000000000ULL, 0x003CU, 0x0305U, 0x0000U, 0x0000U,
         0xC61EU, 0x07F0U, 0xF800U},
        {3190000000ULL, 0x003FU, 0x0305U, 0xCCCCU, 0xCCCCU,
         0xC61EU, 0x07F0U, 0xF800U},
        {3200000000ULL, 0x0020U, 0x0205U, 0x0000U, 0x0000U,
         0xCE1EU, 0x07F1U, 0x08C0U},
        {3210000000ULL, 0x0020U, 0x0205U, 0x1999U, 0x999AU,
         0xCE1EU, 0x07F1U, 0x08C0U},
        {3680000000ULL, 0x0024U, 0x0205U, 0xCCCCU, 0xCCCCU,
         0xCE1EU, 0x07F1U, 0x08C0U}
    };
    unsigned int i;

    for (i = 0U; i < sizeof(golden) / sizeof(golden[0]); i++) {
        LMX2572_Device dev;
        char label[48];

        init_p100(&dev);
        CHECK_EQ_U64("golden-set-frequency",
                     LMX2572_SetFrequency(&dev, golden[i].output_hz),
                     1U);

#define CHECK_REG(reg_name, expected_value)                                    \
        do {                                                                   \
            (void)snprintf(label, sizeof(label),                               \
                           "%" PRIu64 "-%s", golden[i].output_hz, #reg_name);   \
            CHECK_EQ_U64(label,                                                \
                         lmx2572_shadow_get(dev.reg_config,                     \
                                            LMX2572_##reg_name),               \
                         expected_value);                                      \
        } while (0)
        CHECK_REG(R36, golden[i].r36);
        CHECK_REG(R37, golden[i].r37);
        CHECK_REG(R42, golden[i].r42);
        CHECK_REG(R43, golden[i].r43);
        CHECK_REG(R45, golden[i].r45);
        CHECK_REG(R46, golden[i].r46);
        CHECK_REG(R75, golden[i].r75);
#undef CHECK_REG

        CHECK_EQ_U64("diag-output",
                     dev.last_requested_frequency_hz,
                     golden[i].output_hz);
        CHECK_STATUS("diag-status",
                     LMX2572_GetLastStatus(&dev),
                     LMX2572_STATUS_OK);
    }
}

static void test_exact_reference_paths(void)
{
    LMX2572_Device dev;
    uint16_t before_r9;

    LMX2572_Device_Init(&dev, 1U, 2U, 4U, 8U, 1U);
    CHECK_EQ_U64("p75-return",
                 LMX2572_SetReferenceFrequency(
                     &dev, 50000000U, 0U, 2U, 3U, 1U),
                 75000000U);
    CHECK_EQ_U64("p75-num", dev.fpd_num_hz, 75000000U);
    CHECK_EQ_U64("p75-den", dev.fpd_den, 1U);
    CHECK_EQ_U64("p75-r0",
                 lmx2572_shadow_get(dev.reg_config, LMX2572_R0),
                 0x2298U);
    CHECK_EQ_U64("p75-r9",
                 lmx2572_shadow_get(dev.reg_config, LMX2572_R9),
                 0x0004U);
    CHECK_EQ_U64("p75-r10",
                 lmx2572_shadow_get(dev.reg_config, LMX2572_R10),
                 0x11F8U);
    CHECK_EQ_U64("p75-r12",
                 lmx2572_shadow_get(dev.reg_config, LMX2572_R12),
                 0x5002U);

    LMX2572_Device_Init(&dev, 1U, 2U, 4U, 8U, 1U);
    CHECK_EQ_U64("p116-return",
                 LMX2572_SetReferenceFrequency(
                     &dev, 50000000U, 0U, 3U, 7U, 1U),
                 116666666U);
    CHECK_EQ_U64("p116-num", dev.fpd_num_hz, 350000000U);
    CHECK_EQ_U64("p116-den", dev.fpd_den, 3U);
    CHECK_EQ_U64("p116-r0",
                 lmx2572_shadow_get(dev.reg_config, LMX2572_R0),
                 0x2398U);
    CHECK_EQ_U64("p116-r9",
                 lmx2572_shadow_get(dev.reg_config, LMX2572_R9),
                 0x4004U);
    CHECK_EQ_U64("p116-r10",
                 lmx2572_shadow_get(dev.reg_config, LMX2572_R10),
                 0x13F8U);

    before_r9 = lmx2572_shadow_get(dev.reg_config, LMX2572_R9);
    CHECK_EQ_U64("invalid-doubler-mult",
                 LMX2572_SetReferenceFrequency(
                     &dev, 50000000U, 1U, 1U, 3U, 1U),
                 0U);
    CHECK_STATUS("invalid-doubler-status",
                 LMX2572_GetLastStatus(&dev),
                 LMX2572_STATUS_INVALID_ARGUMENT);
    CHECK_EQ_U64("invalid-doubler-no-write",
                 lmx2572_shadow_get(dev.reg_config, LMX2572_R9),
                 before_r9);
}

static void test_pfd_profiles_are_explicitly_qualified(void)
{
    const LMX2572_PfdProfile *p100 =
        lmx2572_pfd_profile_get(LMX2572_PFD_PROFILE_P100);
    const LMX2572_PfdProfile *p75 =
        lmx2572_pfd_profile_get(LMX2572_PFD_PROFILE_P75);
    LMX2572_PfdProfile unqualified_p75;
    LMX2572_Device dev;
    LMX2572_Device before;

    CHECK_EQ_U64("p100-profile-present", p100 != 0, 1U);
    CHECK_EQ_U64("p100-profile-qualified", p100->qualified, 1U);
    CHECK_EQ_U64("p100-profile-fpd", p100->fpd_num_hz, 100000000U);
    CHECK_EQ_U64("p100-profile-cpg", p100->cpg_code, 4U);
    CHECK_EQ_U64("p100-profile-mash", p100->mash_order, 3U);

    CHECK_EQ_U64("p75-profile-present", p75 != 0, 1U);
    CHECK_EQ_U64("p75-profile-qualified", p75->qualified, 1U);
    CHECK_EQ_U64("p75-profile-fpd", p75->fpd_num_hz, 75000000U);
    CHECK_EQ_U64("p75-profile-pre-r", p75->pll_r_pre, 2U);
    CHECK_EQ_U64("p75-profile-mult", p75->mult, 3U);
    CHECK_EQ_U64("p75-profile-cpg", p75->cpg_code, 5U);
    CHECK_EQ_U64("p75-profile-mash", p75->mash_order, 3U);

    LMX2572_Device_Init(&dev, 1U, 2U, 4U, 8U, 1U);
    CHECK_STATUS("p100-profile-apply",
                 lmx2572_pfd_profile_apply(
                     &dev, p100, 3200000000ULL),
                 LMX2572_STATUS_OK);
    CHECK_EQ_U64("p100-profile-id",
                 dev.pfd_profile_id,
                 LMX2572_PFD_PROFILE_P100);
    CHECK_EQ_U64("p100-profile-r14",
                 lmx2572_shadow_get(dev.reg_config, LMX2572_R14),
                 0x1820U);
    CHECK_EQ_U64("p100-profile-r44",
                 lmx2572_shadow_get(dev.reg_config, LMX2572_R44),
                 0x1E63U);

    CHECK_STATUS("p75-profile-apply",
                 lmx2572_pfd_profile_apply(
                     &dev, p75, 3200000000ULL),
                 LMX2572_STATUS_OK);
    CHECK_EQ_U64("p75-profile-id",
                 dev.pfd_profile_id,
                 LMX2572_PFD_PROFILE_P75);
    CHECK_EQ_U64("p75-profile-r0",
                 lmx2572_shadow_get(dev.reg_config, LMX2572_R0),
                 0x2298U);
    CHECK_EQ_U64("p75-profile-r9",
                 lmx2572_shadow_get(dev.reg_config, LMX2572_R9),
                 0x0004U);
    CHECK_EQ_U64("p75-profile-r10",
                 lmx2572_shadow_get(dev.reg_config, LMX2572_R10),
                 0x11F8U);
    CHECK_EQ_U64("p75-profile-r12",
                 lmx2572_shadow_get(dev.reg_config, LMX2572_R12),
                 0x5002U);
    CHECK_EQ_U64("p75-profile-r14",
                 lmx2572_shadow_get(dev.reg_config, LMX2572_R14),
                 0x1828U);
    CHECK_EQ_U64("p75-profile-r44",
                 lmx2572_shadow_get(dev.reg_config, LMX2572_R44),
                 0x1E63U);

    before = dev;
    unqualified_p75 = *p75;
    unqualified_p75.qualified = 0U;
    CHECK_STATUS("p75-unqualified-rejected",
                 lmx2572_pfd_profile_apply(
                     &dev, &unqualified_p75, 3200000000ULL),
                 LMX2572_STATUS_PROFILE_NOT_QUALIFIED);
    CHECK_EQ_U64("p75-unqualified-registers-unchanged",
                 memcmp(before.reg_config,
                        dev.reg_config,
                        sizeof(before.reg_config)),
                 0U);
    CHECK_EQ_U64("p75-unqualified-profile-unchanged",
                 dev.pfd_profile_id,
                 before.pfd_profile_id);
}

static void test_mash_rules_and_boundaries(void)
{
    LMX2572_FrequencyPlan plan;

    CHECK_STATUS("mash3-3g",
                 lmx2572_frequency_plan(
                     3000000000ULL, 100000000ULL, 1U, 3U,
                     0xFFFFFFFFU, &plan),
                 LMX2572_STATUS_OK);
    CHECK_EQ_U64("mash3-3g-chdiv", plan.chdiv, 2U);
    CHECK_EQ_U64("mash3-3g-delay", plan.pfd_dly_sel, 3U);

    CHECK_STATUS("mash3-3p2g",
                 lmx2572_frequency_plan(
                     3200000000ULL, 100000000ULL, 1U, 3U,
                     0xFFFFFFFFU, &plan),
                 LMX2572_STATUS_OK);
    CHECK_EQ_U64("mash3-3p2g-chdiv", plan.chdiv, 1U);
    CHECK_EQ_U64("mash3-3p2g-delay", plan.pfd_dly_sel, 2U);

    CHECK_STATUS("p116-mash3-reject",
                 lmx2572_frequency_plan(
                     3210000000ULL, 350000000ULL, 3U, 3U,
                     0xFFFFFFFFU, &plan),
                 LMX2572_STATUS_NO_VALID_DIVIDER);
    CHECK_STATUS("p116-mash2-accept",
                 lmx2572_frequency_plan(
                     3210000000ULL, 350000000ULL, 3U, 2U,
                     0xFFFFFFFFU, &plan),
                 LMX2572_STATUS_OK);
    CHECK_EQ_U64("p116-mash2-chdiv", plan.chdiv, 1U);
    CHECK_EQ_U64("p116-mash2-delay", plan.pfd_dly_sel, 1U);
}

static void test_full_lo1_runtime_range(void)
{
    LMX2572_Device dev;
    uint64_t frequency_hz;

    init_p100(&dev);
    for (frequency_hz = 2230000000ULL;
         frequency_hz <= 3680000000ULL;
         frequency_hz += 1000000ULL) {
        CHECK_EQ_U64("lo1-range-set-frequency",
                     LMX2572_SetFrequency(&dev, frequency_hz),
                     1U);
        CHECK_STATUS("lo1-range-status",
                     LMX2572_GetLastStatus(&dev),
                     LMX2572_STATUS_OK);
        CHECK_EQ_U64("lo1-range-requested",
                     dev.last_requested_frequency_hz,
                     frequency_hz);
        CHECK_EQ_U64("lo1-range-vco-lower-bound",
                     dev.last_fvco_hz >= 3200000000ULL,
                     1U);
        CHECK_EQ_U64("lo1-range-vco-upper-bound",
                     dev.last_fvco_hz <= 6400000000ULL,
                     1U);
    }

    CHECK_EQ_U64("output-lower-bound",
                 LMX2572_SetFrequency(&dev, 12500000ULL),
                 1U);
    CHECK_EQ_U64("output-upper-bound",
                 LMX2572_SetFrequency(&dev, 6400000000ULL),
                 1U);
}

static void test_p75_full_lo1_runtime_range(void)
{
    const LMX2572_PfdProfile *p75 =
        lmx2572_pfd_profile_get(LMX2572_PFD_PROFILE_P75);
    uint64_t frequency_hz;

    for (frequency_hz = 2230000000ULL;
         frequency_hz <= 3680000000ULL;
         frequency_hz += 1000000ULL) {
        CHECK_STATUS("p75-lo1-range-valid",
                     lmx2572_pfd_profile_validate(p75, frequency_hz),
                     LMX2572_STATUS_OK);
    }
}

static void test_failure_paths_do_not_mutate_frequency(void)
{
    LMX2572_Device dev;
    uint16_t before_image[LMX2572_REGISTER_COUNT];

    init_p100(&dev);
    CHECK_EQ_U64("valid-before-invalid",
                 LMX2572_SetFrequency(&dev, 3200000000ULL),
                 1U);
    memcpy(before_image, dev.reg_config, sizeof(before_image));

    CHECK_EQ_U64("invalid-frequency",
                 LMX2572_SetFrequency(&dev, 1U),
                 0U);
    CHECK_STATUS("invalid-frequency-status",
                 LMX2572_GetLastStatus(&dev),
                 LMX2572_STATUS_OUTPUT_OUT_OF_RANGE);
    CHECK_EQ_U64("invalid-frequency-no-register-write",
                 memcmp(before_image, dev.reg_config, sizeof(before_image)),
                 0U);

    LMX2572_SetOutputChannel(&dev, 99U);
    CHECK_STATUS("invalid-output-channel",
                 LMX2572_GetLastStatus(&dev),
                 LMX2572_STATUS_INVALID_ARGUMENT);

    LMX2572_SetMuxFunction(&dev, 1U);
    (void)LMX2572_ReadRegister(&dev, LMX2572_R0);
    CHECK_STATUS("read-lock-mux-conflict",
                 LMX2572_GetLastStatus(&dev),
                 LMX2572_STATUS_MUX_MODE_CONFLICT);
}

int main(void)
{
    test_public_api_contract();
    test_authoritative_p100_image();
    test_p100_golden_registers();
    test_exact_reference_paths();
    test_pfd_profiles_are_explicitly_qualified();
    test_mash_rules_and_boundaries();
    test_full_lo1_runtime_range();
    test_p75_full_lo1_runtime_range();
    test_failure_paths_do_not_mutate_frequency();

    if (failures != 0U) {
        printf("LMX2572_TESTS_FAILED,%u\n", failures);
        return 1;
    }
    printf("LMX2572_TESTS_PASSED\n");
    return 0;
}
