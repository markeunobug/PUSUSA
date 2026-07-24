#ifndef AMPLITUDE_CORRECTION_H
#define AMPLITUDE_CORRECTION_H

#include <stdint.h>

int amplitude_correction_apply(uint64_t rf_hz,
                               float raw_adc_dbm,
                               float *out_rf_input_dbm,
                               float *out_correction_db);
float amplitude_correction_get_total_db(uint64_t rf_hz);

#endif
