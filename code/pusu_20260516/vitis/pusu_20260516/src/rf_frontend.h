#ifndef RF_FRONTEND_H
#define RF_FRONTEND_H

#include <stdint.h>

#include "xstatus.h"

typedef enum {
    RF_LNA_BYPASS = 0,
    RF_LNA_ENABLE = 1
} rf_lna_mode_t;

typedef enum {
    RF_PATH_DIRECT_IF = 0,
    RF_PATH_MIXER_CHAIN = 1
} rf_path_mode_t;

typedef enum {
    RF_FRONTEND_ERR_NONE = 0,
    RF_FRONTEND_ERR_NO_GPIO = 1,
    RF_FRONTEND_ERR_BAD_PARAM = 2,
    RF_FRONTEND_ERR_GPIO_INIT = 3
} rf_frontend_error_t;

typedef struct {
    rf_lna_mode_t lna_mode;
    rf_path_mode_t path_mode;
    uint8_t atten_code;
    float atten_db;
    uint8_t applied_gpio;
    uint8_t last_error;
} rf_frontend_state_t;

int rf_frontend_init(void);
int rf_frontend_set_lna_mode(rf_lna_mode_t mode);
int rf_frontend_set_path_mode(rf_path_mode_t mode);
int rf_frontend_set_atten_code(uint8_t code);
int rf_frontend_set_atten_db(float atten_db);
int rf_frontend_apply(const rf_frontend_state_t *state);
const rf_frontend_state_t *rf_frontend_get_state(void);

#endif
