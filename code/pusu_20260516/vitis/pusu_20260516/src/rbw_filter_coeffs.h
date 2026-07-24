#ifndef RBW_FILTER_COEFFS_H
#define RBW_FILTER_COEFFS_H

#include "app_config.h"

typedef struct {
    rbw_mode_t mode;
    unsigned int tap_count;
    float enbw_hz;
    float correction_db;
    const float *coeffs;
} rbw_filter_config_t;

const rbw_filter_config_t *rbw_filter_get_config(rbw_mode_t mode);

#endif
