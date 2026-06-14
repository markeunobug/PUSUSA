#include "rf_frontend.h"

#include "app_config.h"
#include "sleep.h"
#include "xgpio.h"

#if RF_FRONTEND_GPIO_AVAILABLE
static XGpio rf_gpio;
#endif
static uint32_t rf_gpio_state;
static int rf_gpio_ready;
static rf_frontend_state_t rf_state = {
    RF_LNA_BYPASS,
    RF_PATH_MIXER_CHAIN,
    RF_FRONTEND_DEFAULT_ATTEN_CODE,
    31.75f,
    0U,
    RF_FRONTEND_ERR_NONE
};

static int rf_frontend_validate_state(const rf_frontend_state_t *state);
static uint32_t rf_frontend_make_switch_bits(const rf_frontend_state_t *state);
static void rf_frontend_gpio_commit(void);
static void rf_frontend_set_mask(uint32_t mask, int level);
static void rf_frontend_write_switch_bits(const rf_frontend_state_t *state);
static void rf_frontend_write_atten_code(uint8_t code);
static void rf_frontend_short_delay(void);
static void rf_frontend_set_error(uint8_t error);
static float rf_frontend_code_to_db(uint8_t code);

int rf_frontend_init(void)
{
    int status;

    rf_state.lna_mode = RF_LNA_BYPASS;
    rf_state.path_mode = RF_PATH_MIXER_CHAIN;
    rf_state.atten_code = RF_FRONTEND_DEFAULT_ATTEN_CODE;
    rf_state.atten_db = rf_frontend_code_to_db(rf_state.atten_code);
    rf_state.applied_gpio = 0U;
    rf_state.last_error = RF_FRONTEND_ERR_NONE;

#if RF_FRONTEND_GPIO_AVAILABLE
    status = XGpio_Initialize(&rf_gpio, RF_FRONTEND_GPIO_DEVICE_ID);
    if (status != XST_SUCCESS) {
        rf_frontend_set_error(RF_FRONTEND_ERR_GPIO_INIT);
        return status;
    }

    XGpio_SetDataDirection(&rf_gpio, RF_FRONTEND_GPIO_CHANNEL, 0x00U);
    rf_gpio_state = 0U;
    rf_gpio_ready = 1;
    rf_frontend_gpio_commit();

    return rf_frontend_apply(&rf_state);
#else
    status = XST_SUCCESS;
    rf_gpio_ready = 0;
    rf_frontend_set_error(RF_FRONTEND_ERR_NO_GPIO);
    return status;
#endif
}

int rf_frontend_set_lna_mode(rf_lna_mode_t mode)
{
    rf_frontend_state_t next = rf_state;

    next.lna_mode = mode;
    return rf_frontend_apply(&next);
}

int rf_frontend_set_path_mode(rf_path_mode_t mode)
{
    rf_frontend_state_t next = rf_state;

    next.path_mode = mode;
    return rf_frontend_apply(&next);
}

int rf_frontend_set_atten_code(uint8_t code)
{
    rf_frontend_state_t next = rf_state;

    next.atten_code = code;
    next.atten_db = rf_frontend_code_to_db(code);
    return rf_frontend_apply(&next);
}

int rf_frontend_set_atten_db(float atten_db)
{
    uint8_t code;

    if ((atten_db < 0.0f) || (atten_db > 31.75f)) {
        rf_frontend_set_error(RF_FRONTEND_ERR_BAD_PARAM);
        return XST_FAILURE;
    }

    code = (uint8_t)((atten_db * 4.0f) + 0.5f);
    return rf_frontend_set_atten_code(code);
}

int rf_frontend_apply(const rf_frontend_state_t *state)
{
    if (rf_frontend_validate_state(state) != XST_SUCCESS) {
        rf_frontend_set_error(RF_FRONTEND_ERR_BAD_PARAM);
        return XST_FAILURE;
    }

    rf_state = *state;
    rf_state.atten_db = rf_frontend_code_to_db(rf_state.atten_code);

    if (rf_gpio_ready == 0) {
        rf_frontend_set_error(RF_FRONTEND_ERR_NO_GPIO);
        return XST_FAILURE;
    }

    rf_frontend_write_switch_bits(&rf_state);
    rf_frontend_write_atten_code(rf_state.atten_code);
    rf_state.applied_gpio = (uint8_t)(rf_gpio_state & 0xFFU);
    rf_frontend_set_error(RF_FRONTEND_ERR_NONE);
    return XST_SUCCESS;
}

const rf_frontend_state_t *rf_frontend_get_state(void)
{
    return &rf_state;
}

static int rf_frontend_validate_state(const rf_frontend_state_t *state)
{
    if (state == 0) {
        return XST_FAILURE;
    }

    if ((state->lna_mode != RF_LNA_BYPASS) &&
        (state->lna_mode != RF_LNA_ENABLE)) {
        return XST_FAILURE;
    }

    if ((state->path_mode != RF_PATH_DIRECT_IF) &&
        (state->path_mode != RF_PATH_MIXER_CHAIN)) {
        return XST_FAILURE;
    }

    if (state->atten_code > 127U) {
        return XST_FAILURE;
    }

    return XST_SUCCESS;
}

static uint32_t rf_frontend_make_switch_bits(const rf_frontend_state_t *state)
{
    uint32_t value = 0U;

    if (state->lna_mode == RF_LNA_BYPASS) {
        value |= RF_SW1_CTL_MASK;
    } else {
        value |= RF_SW2_CTL_MASK;
    }

    if (state->path_mode == RF_PATH_DIRECT_IF) {
        value |= RF_SW3_CTL_MASK;
        value |= RF_SW4_A_MASK;
    } else {
        value |= RF_SW4_B_MASK;
    }

    return value;
}

static void rf_frontend_gpio_commit(void)
{
#if RF_FRONTEND_GPIO_AVAILABLE
    XGpio_DiscreteWrite(&rf_gpio, RF_FRONTEND_GPIO_CHANNEL, rf_gpio_state);
#endif
}

static void rf_frontend_set_mask(uint32_t mask, int level)
{
    if (level != 0) {
        rf_gpio_state |= mask;
    } else {
        rf_gpio_state &= ~mask;
    }

    rf_frontend_gpio_commit();
}

static void rf_frontend_write_switch_bits(const rf_frontend_state_t *state)
{
    const uint32_t switch_mask =
        RF_SW1_CTL_MASK | RF_SW2_CTL_MASK | RF_SW3_CTL_MASK |
        RF_SW4_A_MASK | RF_SW4_B_MASK;
    uint32_t switch_bits = rf_frontend_make_switch_bits(state);

    rf_gpio_state &= ~switch_mask;
    rf_gpio_state |= switch_bits;
    rf_gpio_state &= ~(RF_DSA_CLK_MASK | RF_DSA_SI_MASK | RF_DSA_LE_MASK);
    rf_frontend_gpio_commit();
}

static void rf_frontend_write_atten_code(uint8_t code)
{
    uint8_t data = (uint8_t)(code & 0x7FU);
    uint32_t bit_idx;

    rf_frontend_set_mask(RF_DSA_LE_MASK, 0);
    rf_frontend_set_mask(RF_DSA_CLK_MASK, 0);

    for (bit_idx = 0U; bit_idx < 8U; bit_idx++) {
        rf_frontend_set_mask(RF_DSA_SI_MASK, (data >> bit_idx) & 0x01U);
        rf_frontend_short_delay();
        rf_frontend_set_mask(RF_DSA_CLK_MASK, 1);
        rf_frontend_short_delay();
        rf_frontend_set_mask(RF_DSA_CLK_MASK, 0);
        rf_frontend_short_delay();
    }

    rf_frontend_set_mask(RF_DSA_LE_MASK, 1);
    rf_frontend_short_delay();
    rf_frontend_set_mask(RF_DSA_LE_MASK, 0);
    rf_frontend_set_mask(RF_DSA_SI_MASK, 0);
    rf_frontend_short_delay();
}

static void rf_frontend_short_delay(void)
{
    usleep(1U);
}

static void rf_frontend_set_error(uint8_t error)
{
    rf_state.last_error = error;
}

static float rf_frontend_code_to_db(uint8_t code)
{
    return (float)(code & 0x7FU) * 0.25f;
}
