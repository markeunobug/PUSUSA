#include "pusu_pl_dsp_control.h"

#include "xil_io.h"
#include "xstatus.h"

#if !defined(PUSU_PL_DSP_BASEADDR)
#if defined(XPAR_PUSU_PL_DSP_CORE_0_S00_AXI_BASEADDR)
#define PUSU_PL_DSP_BASEADDR XPAR_PUSU_PL_DSP_CORE_0_S00_AXI_BASEADDR
#elif defined(XPAR_PUSU_PL_DSP_CORE_0_S_AXI_BASEADDR)
#define PUSU_PL_DSP_BASEADDR XPAR_PUSU_PL_DSP_CORE_0_S_AXI_BASEADDR
#elif defined(XPAR_PUSU_PL_DSP_CORE_0_AXI_LITE_BASEADDR)
#define PUSU_PL_DSP_BASEADDR XPAR_PUSU_PL_DSP_CORE_0_AXI_LITE_BASEADDR
#elif defined(XPAR_PUSU_PL_DSP_CORE_0_BASEADDR)
#define PUSU_PL_DSP_BASEADDR XPAR_PUSU_PL_DSP_CORE_0_BASEADDR
#elif defined(XPAR_PUSU_PL_DSP_CONTROL_0_S00_AXI_BASEADDR)
#define PUSU_PL_DSP_BASEADDR XPAR_PUSU_PL_DSP_CONTROL_0_S00_AXI_BASEADDR
#elif defined(XPAR_PUSU_PL_DSP_CONTROL_0_BASEADDR)
#define PUSU_PL_DSP_BASEADDR XPAR_PUSU_PL_DSP_CONTROL_0_BASEADDR
#elif defined(XPAR_PUSU_PL_DSP_AXI_REGS_0_S_AXI_BASEADDR)
#define PUSU_PL_DSP_BASEADDR XPAR_PUSU_PL_DSP_AXI_REGS_0_S_AXI_BASEADDR
#elif defined(XPAR_PUSU_PL_DSP_AXI_REGS_0_S00_AXI_BASEADDR)
#define PUSU_PL_DSP_BASEADDR XPAR_PUSU_PL_DSP_AXI_REGS_0_S00_AXI_BASEADDR
#elif defined(XPAR_PUSU_PL_DSP_AXI_REGS_0_BASEADDR)
#define PUSU_PL_DSP_BASEADDR XPAR_PUSU_PL_DSP_AXI_REGS_0_BASEADDR
#elif defined(XPAR_SYSTEM_PUSU_PL_DSP_AXI_REGS_0_0_S_AXI_BASEADDR)
#define PUSU_PL_DSP_BASEADDR XPAR_SYSTEM_PUSU_PL_DSP_AXI_REGS_0_0_S_AXI_BASEADDR
#elif defined(XPAR_SYSTEM_PUSU_PL_DSP_AXI_REGS_0_0_BASEADDR)
#define PUSU_PL_DSP_BASEADDR XPAR_SYSTEM_PUSU_PL_DSP_AXI_REGS_0_0_BASEADDR
#else
#define PUSU_PL_DSP_BASEADDR 0x43C00000U
#endif
#endif

#if defined(PUSU_PL_DSP_BASEADDR)
#define PUSU_PL_DSP_AXI_AVAILABLE 1
#else
#define PUSU_PL_DSP_AXI_AVAILABLE 0
#endif

#define PUSU_PL_DSP_MODE_TIMEOUT_LOOPS 100000U
#define PUSU_PL_DSP_DATA_FORMAT_PACKED_IQ16 0x00010401U
#define PUSU_PL_DSP_CONTROL_PERSISTENT_MASK \
    (PUSU_PL_DSP_CONTROL_ENABLE | PUSU_PL_DSP_CONTROL_STREAM_RESET)

static pusu_pl_dsp_status_t g_pl_dsp_status;
static u32 g_control_persistent_bits = 0U;

static const pusu_pl_dsp_rbw_config_t g_rbw_configs[] = {
    { RBW_MODE_1M,   PUSU_PL_DSP_MODE_1M,   1000000U, 10000000U, 13U,   96U, 1002220.34525446f,  0.0096321475f, 384U,  32U,  512U },
    { RBW_MODE_300K, PUSU_PL_DSP_MODE_300K,  300000U,  3250000U, 40U,  128U,  313367.843156145f, 0.1893317374f, 384U,  64U,  576U },
    { RBW_MODE_100K, PUSU_PL_DSP_MODE_100K,  100000U,  1000000U, 130U, 128U,  101477.62963112f,  0.0637031418f, 384U,  64U,  576U },
    { RBW_MODE_30K,  PUSU_PL_DSP_MODE_30K,    30000U,   325000U, 400U, 192U,   30642.7211714813f, 0.0920607469f, 256U, 128U,  576U },
    { RBW_MODE_10K,  PUSU_PL_DSP_MODE_10K,    10000U,   100000U, 1300U,256U,   10089.8633951714f, 0.0388528644f,2560U,128U, 2944U },
    { RBW_MODE_1K,   PUSU_PL_DSP_MODE_1K,      1000U,   100000U, 1300U,768U,     983.424247431691f,-0.0725908789f,256U,128U, 1152U }
};

static void set_shadow_from_config(const pusu_pl_dsp_rbw_config_t *cfg);
static int mode_readback_matches(const pusu_pl_dsp_rbw_config_t *cfg);
static void set_control_persistent(u32 persistent_bits);
static void pulse_control(u32 pulse_bits);
static u32 read_reg(u32 offset);
static void write_reg(u32 offset, u32 value);
static int wait_not_busy(void);

int pusu_pl_dsp_init(void)
{
    set_shadow_from_config(pusu_pl_dsp_get_rbw_config(RBW_MODE_100K));

#if PUSU_PL_DSP_AXI_AVAILABLE
    (void)pusu_pl_dsp_read_status(&g_pl_dsp_status);
#endif
    return XST_SUCCESS;
}

int pusu_pl_dsp_configure_rbw(rbw_mode_t mode)
{
    const pusu_pl_dsp_rbw_config_t *cfg = pusu_pl_dsp_get_rbw_config(mode);

    set_shadow_from_config(cfg);

#if PUSU_PL_DSP_AXI_AVAILABLE
    set_control_persistent(0U);
    pulse_control(PUSU_PL_DSP_CONTROL_ABORT);
    write_reg(PUSU_PL_DSP_REG_RBW_MODE, cfg->pl_mode_value);
    write_reg(PUSU_PL_DSP_REG_OUTPUT_SELECT, PUSU_PL_DSP_OUTPUT_DECIMATED_IQ);
    write_reg(PUSU_PL_DSP_REG_FRAME_WORDS, FFT_SIZE);
    write_reg(PUSU_PL_DSP_REG_CONTROL,
              g_control_persistent_bits | PUSU_PL_DSP_CONTROL_MODE_UPDATE);

    if (wait_not_busy() != XST_SUCCESS) {
        (void)pusu_pl_dsp_read_status(&g_pl_dsp_status);
        return XST_FAILURE;
    }

    set_control_persistent(g_control_persistent_bits);
    pulse_control(PUSU_PL_DSP_CONTROL_CLEAR_STATUS);
    set_control_persistent(PUSU_PL_DSP_CONTROL_ENABLE);

    if (pusu_pl_dsp_read_status(&g_pl_dsp_status) != XST_SUCCESS) {
        return XST_FAILURE;
    }
    if ((g_pl_dsp_status.pl_mode_value != (u8)cfg->pl_mode_value) ||
        (g_pl_dsp_status.sample_rate_hz != cfg->expected_sample_rate_hz) ||
        (g_pl_dsp_status.decimation_ratio != (u32)cfg->total_decimation)) {
        return XST_FAILURE;
    }
#endif

    return XST_SUCCESS;
}

int pusu_pl_dsp_enable(int enable)
{
#if PUSU_PL_DSP_AXI_AVAILABLE
    if (enable != 0) {
        set_control_persistent(g_control_persistent_bits |
                               PUSU_PL_DSP_CONTROL_ENABLE);
    } else {
        set_control_persistent(g_control_persistent_bits &
                               ~PUSU_PL_DSP_CONTROL_ENABLE);
    }
    (void)pusu_pl_dsp_read_status(&g_pl_dsp_status);
#else
    if (enable != 0) {
        g_pl_dsp_status.status |= PUSU_PL_DSP_STATUS_OUTPUT_ENABLED;
    } else {
        g_pl_dsp_status.status &= ~PUSU_PL_DSP_STATUS_OUTPUT_ENABLED;
    }
#endif
    return XST_SUCCESS;
}

int pusu_pl_dsp_set_stream_reset(int asserted)
{
#if PUSU_PL_DSP_AXI_AVAILABLE
    if (asserted != 0) {
        set_control_persistent(g_control_persistent_bits |
                               PUSU_PL_DSP_CONTROL_STREAM_RESET);
    } else {
        set_control_persistent(g_control_persistent_bits &
                               ~PUSU_PL_DSP_CONTROL_STREAM_RESET);
    }
    (void)pusu_pl_dsp_read_status(&g_pl_dsp_status);
#else
    if (asserted != 0) {
        g_pl_dsp_status.status |= PUSU_PL_DSP_STATUS_STREAM_RESET_ACTIVE;
    } else {
        g_pl_dsp_status.status &= ~PUSU_PL_DSP_STATUS_STREAM_RESET_ACTIVE;
    }
#endif
    return XST_SUCCESS;
}

int pusu_pl_dsp_prepare_clean_dma_start(rbw_mode_t mode)
{
    const pusu_pl_dsp_rbw_config_t *cfg = pusu_pl_dsp_get_rbw_config(mode);

#if PUSU_PL_DSP_AXI_AVAILABLE
    if (mode_readback_matches(cfg) == 0) {
        if (pusu_pl_dsp_configure_rbw(mode) != XST_SUCCESS) {
            return XST_FAILURE;
        }
    } else {
        set_shadow_from_config(cfg);
        g_pl_dsp_status.fw_mode = cfg->fw_mode;
    }

    set_control_persistent(PUSU_PL_DSP_CONTROL_STREAM_RESET);
    (void)pusu_pl_dsp_read_status(&g_pl_dsp_status);
#else
    set_shadow_from_config(cfg);
    g_pl_dsp_status.status &= ~PUSU_PL_DSP_STATUS_OUTPUT_ENABLED;
    g_pl_dsp_status.status |= PUSU_PL_DSP_STATUS_STREAM_RESET_ACTIVE;
#endif
    return XST_SUCCESS;
}

int pusu_pl_dsp_release_clean_dma_start(void)
{
#if PUSU_PL_DSP_AXI_AVAILABLE
    set_control_persistent(PUSU_PL_DSP_CONTROL_ENABLE);
    (void)pusu_pl_dsp_read_status(&g_pl_dsp_status);
#else
    g_pl_dsp_status.status &= ~PUSU_PL_DSP_STATUS_STREAM_RESET_ACTIVE;
    g_pl_dsp_status.status |= PUSU_PL_DSP_STATUS_OUTPUT_ENABLED;
#endif
    return XST_SUCCESS;
}

void pusu_pl_dsp_clear_status(void)
{
#if PUSU_PL_DSP_AXI_AVAILABLE
    pulse_control(PUSU_PL_DSP_CONTROL_CLEAR_STATUS);
    (void)pusu_pl_dsp_read_status(&g_pl_dsp_status);
#else
    g_pl_dsp_status.output_drop_count = 0U;
    g_pl_dsp_status.error_code = 0U;
#endif
}

int pusu_pl_dsp_read_status(pusu_pl_dsp_status_t *out_status)
{
#if PUSU_PL_DSP_AXI_AVAILABLE
    u32 rbw_mode_reg;
    u32 output_select_reg;

    rbw_mode_reg = read_reg(PUSU_PL_DSP_REG_RBW_MODE);
    output_select_reg = read_reg(PUSU_PL_DSP_REG_OUTPUT_SELECT);

    g_pl_dsp_status.available = 1U;
    g_pl_dsp_status.pl_mode_value = (u8)(rbw_mode_reg & 0xFFU);
    g_pl_dsp_status.output_select = (u8)(output_select_reg & 0xFFU);
    g_pl_dsp_status.status = read_reg(PUSU_PL_DSP_REG_STATUS);
    g_pl_dsp_status.sample_rate_hz = read_reg(PUSU_PL_DSP_REG_SAMPLE_RATE_HZ);
    g_pl_dsp_status.decimation_ratio = read_reg(PUSU_PL_DSP_REG_DECIMATION_RATIO);
    g_pl_dsp_status.frame_words = read_reg(PUSU_PL_DSP_REG_FRAME_WORDS);
    g_pl_dsp_status.data_format = read_reg(PUSU_PL_DSP_REG_DATA_FORMAT);
    g_pl_dsp_status.input_sample_count = read_reg(PUSU_PL_DSP_REG_INPUT_SAMPLE_COUNT);
    g_pl_dsp_status.output_sample_count = read_reg(PUSU_PL_DSP_REG_OUTPUT_SAMPLE_COUNT);
    g_pl_dsp_status.output_drop_count = read_reg(PUSU_PL_DSP_REG_OUTPUT_DROP_COUNT);
    g_pl_dsp_status.error_code = read_reg(PUSU_PL_DSP_REG_ERROR_CODE);
    g_pl_dsp_status.version = read_reg(PUSU_PL_DSP_REG_VERSION);
#endif

    if (out_status != 0) {
        *out_status = g_pl_dsp_status;
    }
    return XST_SUCCESS;
}

const pusu_pl_dsp_status_t *pusu_pl_dsp_get_last_status(void)
{
    return &g_pl_dsp_status;
}

const pusu_pl_dsp_rbw_config_t *pusu_pl_dsp_get_rbw_config(rbw_mode_t mode)
{
    unsigned int i;

    for (i = 0U; i < (sizeof(g_rbw_configs) / sizeof(g_rbw_configs[0])); i++) {
        if (g_rbw_configs[i].fw_mode == mode) {
            return &g_rbw_configs[i];
        }
    }

    return &g_rbw_configs[2];
}

u32 pusu_pl_dsp_fw_mode_to_pl_mode(rbw_mode_t mode)
{
    return pusu_pl_dsp_get_rbw_config(mode)->pl_mode_value;
}

u32 pusu_pl_dsp_get_active_sample_rate_hz(void)
{
    return g_pl_dsp_status.sample_rate_hz;
}

u32 pusu_pl_dsp_get_active_decimation(void)
{
    return g_pl_dsp_status.decimation_ratio;
}

static void set_shadow_from_config(const pusu_pl_dsp_rbw_config_t *cfg)
{
    if (cfg == 0) {
        cfg = pusu_pl_dsp_get_rbw_config(RBW_MODE_100K);
    }

    g_pl_dsp_status.available = (u8)PUSU_PL_DSP_AXI_AVAILABLE;
    g_pl_dsp_status.fw_mode = cfg->fw_mode;
    g_pl_dsp_status.pl_mode_value = (u8)cfg->pl_mode_value;
    g_pl_dsp_status.output_select = PUSU_PL_DSP_OUTPUT_DECIMATED_IQ;
    g_pl_dsp_status.status = PUSU_PL_DSP_STATUS_IDLE |
                             PUSU_PL_DSP_STATUS_CONFIGURED |
                             PUSU_PL_DSP_STATUS_OUTPUT_ENABLED;
    g_pl_dsp_status.sample_rate_hz = cfg->expected_sample_rate_hz;
    g_pl_dsp_status.decimation_ratio = cfg->total_decimation;
    g_pl_dsp_status.frame_words = FFT_SIZE;
    g_pl_dsp_status.data_format = PUSU_PL_DSP_DATA_FORMAT_PACKED_IQ16;
    g_pl_dsp_status.input_sample_count = 0U;
    g_pl_dsp_status.output_sample_count = 0U;
    g_pl_dsp_status.output_drop_count = 0U;
    g_pl_dsp_status.error_code = 0U;
    g_pl_dsp_status.version = 0U;
}

static int mode_readback_matches(const pusu_pl_dsp_rbw_config_t *cfg)
{
#if PUSU_PL_DSP_AXI_AVAILABLE
    pusu_pl_dsp_status_t status;

    if (cfg == 0) {
        return 0;
    }
    if (pusu_pl_dsp_read_status(&status) != XST_SUCCESS) {
        return 0;
    }

    return ((status.pl_mode_value == (u8)cfg->pl_mode_value) &&
            (status.output_select == PUSU_PL_DSP_OUTPUT_DECIMATED_IQ) &&
            (status.sample_rate_hz == cfg->expected_sample_rate_hz) &&
            (status.decimation_ratio == (u32)cfg->total_decimation) &&
            (status.frame_words == (u32)FFT_SIZE)) ? 1 : 0;
#else
    (void)cfg;
    return 1;
#endif
}

static void set_control_persistent(u32 persistent_bits)
{
    g_control_persistent_bits =
        persistent_bits & PUSU_PL_DSP_CONTROL_PERSISTENT_MASK;
    write_reg(PUSU_PL_DSP_REG_CONTROL, g_control_persistent_bits);
}

static void pulse_control(u32 pulse_bits)
{
    write_reg(PUSU_PL_DSP_REG_CONTROL,
              g_control_persistent_bits |
              (pulse_bits & ~PUSU_PL_DSP_CONTROL_PERSISTENT_MASK));
    write_reg(PUSU_PL_DSP_REG_CONTROL, g_control_persistent_bits);
}

static u32 read_reg(u32 offset)
{
#if PUSU_PL_DSP_AXI_AVAILABLE
    return Xil_In32((UINTPTR)PUSU_PL_DSP_BASEADDR + offset);
#else
    (void)offset;
    return 0U;
#endif
}

static void write_reg(u32 offset, u32 value)
{
#if PUSU_PL_DSP_AXI_AVAILABLE
    Xil_Out32((UINTPTR)PUSU_PL_DSP_BASEADDR + offset, value);
#else
    (void)offset;
    (void)value;
#endif
}

static int wait_not_busy(void)
{
#if PUSU_PL_DSP_AXI_AVAILABLE
    u32 loops;

    for (loops = 0U; loops < PUSU_PL_DSP_MODE_TIMEOUT_LOOPS; loops++) {
        u32 status = read_reg(PUSU_PL_DSP_REG_STATUS);

        if ((status & PUSU_PL_DSP_STATUS_MODE_BUSY) == 0U) {
            if ((status & PUSU_PL_DSP_STATUS_CONFIGURED) != 0U) {
                return XST_SUCCESS;
            }
        }
    }
    return XST_FAILURE;
#else
    return XST_SUCCESS;
#endif
}
