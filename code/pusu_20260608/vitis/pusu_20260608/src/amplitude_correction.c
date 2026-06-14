#include "amplitude_correction.h"

#include "ad8370.h"
#include "app_config.h"
#include "rf_frontend.h"

typedef struct {
    uint64_t max_hz;
    float correction_db;
} amplitude_freq_cal_point_t;

static const amplitude_freq_cal_point_t freq_cal_table[] = {
    { 50000000ULL, AMPLITUDE_FREQ_CAL_DB_0 },
    { 500000000ULL, AMPLITUDE_FREQ_CAL_DB_1 },
    { 1000000000ULL, AMPLITUDE_FREQ_CAL_DB_2 },
    { 1500000000ULL, AMPLITUDE_FREQ_CAL_DB_3 }
};

static float amplitude_correction_get_lna_gain_db(const rf_frontend_state_t *state);
static float amplitude_correction_get_path_cal_db(const rf_frontend_state_t *state);
static float amplitude_correction_get_freq_cal_db(uint64_t rf_hz);

int amplitude_correction_apply(uint64_t rf_hz,
                               float raw_adc_dbm,
                               float *out_rf_input_dbm,
                               float *out_correction_db)
{
    float correction_db;

    if ((out_rf_input_dbm == 0) || (out_correction_db == 0)) {
        return -1;
    }

    correction_db = amplitude_correction_get_total_db(rf_hz);
    *out_correction_db = correction_db;
    *out_rf_input_dbm = raw_adc_dbm + correction_db;
    return 0;
}

float amplitude_correction_get_total_db(uint64_t rf_hz)
{
    const rf_frontend_state_t *state = rf_frontend_get_state();
    float atten_db = 0.0f;
    float lna_gain_db;
    float vga_gain_db;
    float path_cal_db;
    float freq_cal_db;

    if (state != 0) {
        atten_db = state->atten_db;
    }

    lna_gain_db = amplitude_correction_get_lna_gain_db(state);
    vga_gain_db = ad8370_get_theoretical_gain_db(ad8370_get_gain_code());
    path_cal_db = amplitude_correction_get_path_cal_db(state);
    freq_cal_db = amplitude_correction_get_freq_cal_db(rf_hz);

    return atten_db - lna_gain_db - vga_gain_db + path_cal_db + freq_cal_db;
}

static float amplitude_correction_get_lna_gain_db(const rf_frontend_state_t *state)
{
    if ((state != 0) && (state->lna_mode == RF_LNA_ENABLE)) {
        return AMPLITUDE_LNA_GAIN_DB;
    }

    return 0.0f;
}

static float amplitude_correction_get_path_cal_db(const rf_frontend_state_t *state)
{
    if ((state != 0) && (state->path_mode == RF_PATH_DIRECT_IF)) {
        return AMPLITUDE_DIRECT_IF_CAL_DB;
    }

    return AMPLITUDE_MIXER_CHAIN_CAL_DB;
}

static float amplitude_correction_get_freq_cal_db(uint64_t rf_hz)
{
    uint32_t i;

    for (i = 0U; i < (sizeof(freq_cal_table) / sizeof(freq_cal_table[0])); i++) {
        if (rf_hz <= freq_cal_table[i].max_hz) {
            return freq_cal_table[i].correction_db;
        }
    }

    return freq_cal_table[(sizeof(freq_cal_table) / sizeof(freq_cal_table[0])) - 1U].correction_db;
}
