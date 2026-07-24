#ifndef PUSU_PL_DSP_CONTROL_H
#define PUSU_PL_DSP_CONTROL_H

#include "app_config.h"
#include "xil_types.h"

#define PUSU_PL_DSP_REG_CONTROL             0x00U
#define PUSU_PL_DSP_REG_STATUS              0x04U
#define PUSU_PL_DSP_REG_RBW_MODE            0x08U
#define PUSU_PL_DSP_REG_OUTPUT_SELECT       0x0CU
#define PUSU_PL_DSP_REG_SAMPLE_RATE_HZ      0x10U
#define PUSU_PL_DSP_REG_DECIMATION_RATIO    0x14U
#define PUSU_PL_DSP_REG_FRAME_WORDS         0x18U
#define PUSU_PL_DSP_REG_DATA_FORMAT         0x1CU
#define PUSU_PL_DSP_REG_INPUT_SAMPLE_COUNT  0x20U
#define PUSU_PL_DSP_REG_OUTPUT_SAMPLE_COUNT 0x24U
#define PUSU_PL_DSP_REG_OUTPUT_DROP_COUNT   0x28U
#define PUSU_PL_DSP_REG_ERROR_CODE          0x2CU
#define PUSU_PL_DSP_REG_VERSION             0x30U

#define PUSU_PL_DSP_CONTROL_ENABLE          (1U << 0)
#define PUSU_PL_DSP_CONTROL_SOFT_RESET      (1U << 1)
#define PUSU_PL_DSP_CONTROL_CLEAR_STATUS    (1U << 2)
#define PUSU_PL_DSP_CONTROL_MODE_UPDATE     (1U << 3)
#define PUSU_PL_DSP_CONTROL_ABORT           (1U << 4)
#define PUSU_PL_DSP_CONTROL_STREAM_RESET    (1U << 5)

#define PUSU_PL_DSP_STATUS_IDLE             (1U << 0)
#define PUSU_PL_DSP_STATUS_CONFIGURED       (1U << 1)
#define PUSU_PL_DSP_STATUS_MODE_BUSY        (1U << 2)
#define PUSU_PL_DSP_STATUS_OUTPUT_ENABLED   (1U << 3)
#define PUSU_PL_DSP_STATUS_OVERFLOW         (1U << 4)
#define PUSU_PL_DSP_STATUS_DROP_SEEN        (1U << 5)
#define PUSU_PL_DSP_STATUS_ERROR            (1U << 6)
#define PUSU_PL_DSP_STATUS_STREAM_RESET_ACTIVE (1U << 7)

#define PUSU_PL_DSP_OUTPUT_DISABLED         0U
#define PUSU_PL_DSP_OUTPUT_DECIMATED_IQ     1U
#define PUSU_PL_DSP_OUTPUT_POST_RBW_IQ      2U
#define PUSU_PL_DSP_OUTPUT_POINT_POWER      3U

#define PUSU_PL_DSP_MODE_1M                 0U
#define PUSU_PL_DSP_MODE_300K               1U
#define PUSU_PL_DSP_MODE_100K               2U
#define PUSU_PL_DSP_MODE_30K                3U
#define PUSU_PL_DSP_MODE_10K                4U
#define PUSU_PL_DSP_MODE_1K                 5U

typedef struct {
    rbw_mode_t fw_mode;
    u32 pl_mode_value;
    u32 nominal_rbw_hz;
    u32 expected_sample_rate_hz;
    u16 total_decimation;
    u16 rbw_fir_taps;
    float actual_enbw_hz;
    float enbw_correction_db;
    u16 observe_points;
    u16 skip_points;
    u16 accum_target;
} pusu_pl_dsp_rbw_config_t;

typedef struct {
    u8 available;
    rbw_mode_t fw_mode;
    u8 pl_mode_value;
    u8 output_select;
    u32 status;
    u32 sample_rate_hz;
    u32 decimation_ratio;
    u32 frame_words;
    u32 data_format;
    u32 input_sample_count;
    u32 output_sample_count;
    u32 output_drop_count;
    u32 error_code;
    u32 version;
} pusu_pl_dsp_status_t;

int pusu_pl_dsp_init(void);
int pusu_pl_dsp_configure_rbw(rbw_mode_t mode);
int pusu_pl_dsp_enable(int enable);
int pusu_pl_dsp_set_stream_reset(int asserted);
int pusu_pl_dsp_prepare_clean_dma_start(rbw_mode_t mode);
int pusu_pl_dsp_release_clean_dma_start(void);
void pusu_pl_dsp_clear_status(void);
int pusu_pl_dsp_read_status(pusu_pl_dsp_status_t *out_status);
const pusu_pl_dsp_status_t *pusu_pl_dsp_get_last_status(void);
const pusu_pl_dsp_rbw_config_t *pusu_pl_dsp_get_rbw_config(rbw_mode_t mode);
u32 pusu_pl_dsp_fw_mode_to_pl_mode(rbw_mode_t mode);
u32 pusu_pl_dsp_get_active_sample_rate_hz(void);
u32 pusu_pl_dsp_get_active_decimation(void);

#endif
