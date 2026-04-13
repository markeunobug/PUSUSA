#include "device_protocol.h"

#include <math.h>
#include <string.h>

#include "app_config.h"
#include "xuartps_hw.h"

#define FRAME_START_BYTE 0xAAU
#define FRAME_END_BYTE   0x55U

#define CMD_SET_FREQ       0x01U
#define CMD_SET_AMPLITUDE  0x02U
#define CMD_SET_BW         0x03U
#define CMD_SET_DETECT     0x04U
#define CMD_SET_SWEEP      0x05U
#define CMD_GET_SPECTRUM   0x06U
#define CMD_GET_STATUS     0x07U
#define CMD_RESET          0x08U

#define CMD_ACK            0x81U
#define CMD_SPECTRUM_DATA  0x82U
#define CMD_STATUS_DATA    0x83U

#define ACK_OK             0x01U
#define ACK_FAIL           0x00U
#define ERR_NONE           0x00U
#define ERR_BAD_CRC        0x01U
#define ERR_BAD_FRAME      0x02U
#define ERR_BAD_CMD        0x03U
#define ERR_INTERNAL       0x04U

#define RX_BUFFER_SIZE          2048U
#define TX_FRAME_MAX_SIZE       16384U
#define DEFAULT_POINT_COUNT     256U
#define MIN_POINT_COUNT         8U
#define MAX_POINT_COUNT         512U

typedef struct {
    unsigned char buffer[RX_BUFFER_SIZE];
    unsigned int length;
    unsigned int timestamp;
    unsigned int rng_state;
    device_control_config_t config;
    device_protocol_spectrum_provider_t spectrum_provider;
    device_protocol_status_provider_t status_provider;
    spectrum_point_t spectrum_points[MAX_POINT_COUNT];
    unsigned char tx_buffer[TX_FRAME_MAX_SIZE];
} device_protocol_state_t;

static device_protocol_state_t g_protocol;

static unsigned short crc16_modbus(const unsigned char *data, unsigned int length);
static void uart_send_bytes(const unsigned char *data, unsigned int length);
static void send_frame(unsigned char cmd, const unsigned char *data, unsigned short length);
static void send_frame_inplace(unsigned char cmd, unsigned short length);
static void send_ack(unsigned char original_cmd, unsigned char success, unsigned char error_code);
static void send_status(void);
static void send_spectrum(void);
static void handle_frame(unsigned char cmd, const unsigned char *data, unsigned short length);
static void reset_default_config(void);
static int fake_spectrum_provider(
    const device_control_config_t *config,
    spectrum_point_t *points,
    unsigned short max_points,
    unsigned short *out_point_count);
static int fake_status_provider(device_status_t *status);
static unsigned int fake_rand(void);
static double make_fake_amplitude(double ratio, const device_control_config_t *config);
static void write_u16_be(unsigned char *dst, unsigned short value);
static void write_u32_be(unsigned char *dst, unsigned int value);
static void write_f64_le(unsigned char *dst, double value);
static unsigned short read_u16_le(const unsigned char *src);
static double read_f64_le(const unsigned char *src);
static unsigned short sanitize_point_count(unsigned short value);

int device_protocol_init(void)
{
    memset(&g_protocol, 0, sizeof(g_protocol));
    g_protocol.rng_state = 0x12345678U;
    reset_default_config();
    g_protocol.spectrum_provider = fake_spectrum_provider;
    g_protocol.status_provider = fake_status_provider;
    return XST_SUCCESS;
}

void device_protocol_poll(void)
{
    while (XUartPs_IsReceiveData(UART_BASEADDR) != 0U) {
        unsigned char ch = (unsigned char)(XUartPs_ReadReg(UART_BASEADDR, XUARTPS_FIFO_OFFSET) & 0xFFU);

        if ((g_protocol.length == 0U) && (ch != FRAME_START_BYTE)) {
            continue;
        }

        if (g_protocol.length < RX_BUFFER_SIZE) {
            g_protocol.buffer[g_protocol.length++] = ch;
        } else {
            g_protocol.length = 0U;
            continue;
        }

        while (g_protocol.length >= 7U) {
            unsigned short payload_length;
            unsigned int frame_length;
            unsigned short rx_crc;
            unsigned short calc_crc;
            unsigned char cmd;

            if (g_protocol.buffer[0] != FRAME_START_BYTE) {
                memmove(&g_protocol.buffer[0], &g_protocol.buffer[1], g_protocol.length - 1U);
                g_protocol.length--;
                continue;
            }

            payload_length = (unsigned short)(((unsigned short)g_protocol.buffer[1] << 8) |
                                              (unsigned short)g_protocol.buffer[2]);
            frame_length = 1U + 2U + 1U + (unsigned int)payload_length + 2U + 1U;

            if (frame_length > RX_BUFFER_SIZE) {
                g_protocol.length = 0U;
                break;
            }

            if (g_protocol.length < frame_length) {
                break;
            }

            if (g_protocol.buffer[frame_length - 1U] != FRAME_END_BYTE) {
                memmove(&g_protocol.buffer[0], &g_protocol.buffer[1], g_protocol.length - 1U);
                g_protocol.length--;
                continue;
            }

            rx_crc = (unsigned short)(((unsigned short)g_protocol.buffer[frame_length - 3U] << 8) |
                                      (unsigned short)g_protocol.buffer[frame_length - 2U]);
            calc_crc = crc16_modbus(&g_protocol.buffer[1], 2U + 1U + payload_length);

            cmd = g_protocol.buffer[3];
            if (calc_crc != rx_crc) {
                send_ack(cmd, ACK_FAIL, ERR_BAD_CRC);
            } else {
                handle_frame(cmd, &g_protocol.buffer[4], payload_length);
            }

            if (g_protocol.length > frame_length) {
                memmove(&g_protocol.buffer[0],
                        &g_protocol.buffer[frame_length],
                        g_protocol.length - frame_length);
            }
            g_protocol.length -= frame_length;
        }
    }
}

const device_control_config_t *device_protocol_get_config(void)
{
    return &g_protocol.config;
}

void device_protocol_set_spectrum_provider(device_protocol_spectrum_provider_t provider)
{
    g_protocol.spectrum_provider = provider;
}

void device_protocol_set_status_provider(device_protocol_status_provider_t provider)
{
    g_protocol.status_provider = provider;
}

static void handle_frame(unsigned char cmd, const unsigned char *data, unsigned short length)
{
    switch (cmd) {
    case CMD_SET_FREQ:
        if (length == 32U) {
            g_protocol.config.frequency.start_hz = read_f64_le(&data[0]);
            g_protocol.config.frequency.stop_hz = read_f64_le(&data[8]);
            g_protocol.config.frequency.center_hz = read_f64_le(&data[16]);
            g_protocol.config.frequency.span_hz = read_f64_le(&data[24]);
            send_ack(cmd, ACK_OK, ERR_NONE);
        } else {
            send_ack(cmd, ACK_FAIL, ERR_BAD_FRAME);
        }
        break;
    case CMD_SET_AMPLITUDE:
        if (length == 10U) {
            g_protocol.config.amplitude.ref_level_dbm = read_f64_le(&data[0]);
            g_protocol.config.amplitude.attenuator_mode = data[8];
            g_protocol.config.amplitude.preamp_mode = data[9];
            send_ack(cmd, ACK_OK, ERR_NONE);
        } else {
            send_ack(cmd, ACK_FAIL, ERR_BAD_FRAME);
        }
        break;
    case CMD_SET_BW:
        if (length == 18U) {
            g_protocol.config.bandwidth.rbw_mode = data[0];
            g_protocol.config.bandwidth.rbw_hz = read_f64_le(&data[1]);
            g_protocol.config.bandwidth.vbw_mode = data[9];
            g_protocol.config.bandwidth.vbw_hz = read_f64_le(&data[10]);
            send_ack(cmd, ACK_OK, ERR_NONE);
        } else {
            send_ack(cmd, ACK_FAIL, ERR_BAD_FRAME);
        }
        break;
    case CMD_SET_DETECT:
        if (length == 1U) {
            g_protocol.config.detect.detect_mode = data[0];
            send_ack(cmd, ACK_OK, ERR_NONE);
        } else {
            send_ack(cmd, ACK_FAIL, ERR_BAD_FRAME);
        }
        break;
    case CMD_SET_SWEEP:
        if (length == 11U) {
            g_protocol.config.sweep.speed_hz = read_f64_le(&data[0]);
            g_protocol.config.sweep.mode = data[8];
            g_protocol.config.sweep.point_count = sanitize_point_count(read_u16_le(&data[9]));
            send_ack(cmd, ACK_OK, ERR_NONE);
        } else {
            send_ack(cmd, ACK_FAIL, ERR_BAD_FRAME);
        }
        break;
    case CMD_GET_SPECTRUM:
        if ((length == 0U) || (length == 2U)) {
            if (length == 2U) {
                g_protocol.config.sweep.point_count = sanitize_point_count(read_u16_le(data));
            }
            send_ack(cmd, ACK_OK, ERR_NONE);
            send_spectrum();
        } else {
            send_ack(cmd, ACK_FAIL, ERR_BAD_FRAME);
        }
        break;
    case CMD_GET_STATUS:
        if (length == 0U) {
            send_ack(cmd, ACK_OK, ERR_NONE);
            send_status();
        } else {
            send_ack(cmd, ACK_FAIL, ERR_BAD_FRAME);
        }
        break;
    case CMD_RESET:
        if (length == 0U) {
            g_protocol.timestamp = 0U;
            g_protocol.rng_state = 0x12345678U;
            reset_default_config();
            send_ack(cmd, ACK_OK, ERR_NONE);
        } else {
            send_ack(cmd, ACK_FAIL, ERR_BAD_FRAME);
        }
        break;
    default:
        send_ack(cmd, ACK_FAIL, ERR_BAD_CMD);
        break;
    }
}

static void reset_default_config(void)
{
    g_protocol.config.frequency.start_hz = 0.0;
    g_protocol.config.frequency.stop_hz = 1.0e9;
    g_protocol.config.frequency.center_hz = 5.0e8;
    g_protocol.config.frequency.span_hz = 1.0e9;

    g_protocol.config.amplitude.ref_level_dbm = 0.0;
    g_protocol.config.amplitude.attenuator_mode = 0U;
    g_protocol.config.amplitude.preamp_mode = 0U;

    g_protocol.config.bandwidth.rbw_mode = 0U;
    g_protocol.config.bandwidth.rbw_hz = 1.0e6;
    g_protocol.config.bandwidth.vbw_mode = 0U;
    g_protocol.config.bandwidth.vbw_hz = 1.0e6;

    g_protocol.config.sweep.speed_hz = 30.0;
    g_protocol.config.sweep.mode = 0U;
    g_protocol.config.sweep.point_count = DEFAULT_POINT_COUNT;

    g_protocol.config.detect.detect_mode = 0U;
}

static void send_ack(unsigned char original_cmd, unsigned char success, unsigned char error_code)
{
    unsigned char payload[3];

    payload[0] = original_cmd;
    payload[1] = success;
    payload[2] = error_code;
    send_frame(CMD_ACK, payload, 3U);
}

static void send_status(void)
{
    device_status_t status;
    unsigned char payload[43];
    int ok = 0;

    if (g_protocol.status_provider != 0) {
        ok = g_protocol.status_provider(&status);
    }

    if (ok != 0) {
        send_ack(CMD_GET_STATUS, ACK_FAIL, ERR_INTERNAL);
        return;
    }

    write_f64_le(&payload[0], status.temperature_c);
    payload[8] = status.battery_percent;
    payload[9] = status.error_code;
    write_u32_be(&payload[10], status.dma_start_count);
    write_u32_be(&payload[14], status.dma_error_count);
    write_u32_be(&payload[18], status.frame_ready_count);
    write_u32_be(&payload[22], status.process_frame_count);
    payload[26] = status.spectrum_valid;
    write_u32_be(&payload[27], status.s2mm_dmacr);
    write_u32_be(&payload[31], status.s2mm_dmasr);
    write_u32_be(&payload[35], status.dma_irq_count);
    write_u32_be(&payload[39], status.dma_last_irq_status);
    send_frame(CMD_STATUS_DATA, payload, 43U);
}

static void send_spectrum(void)
{
    unsigned short point_count = 0U;
    unsigned short payload_length;
    unsigned int offset = 4U;
    unsigned int i;
    int ok = 0;

    if (g_protocol.spectrum_provider != 0) {
        ok = g_protocol.spectrum_provider(
            &g_protocol.config,
            g_protocol.spectrum_points,
            MAX_POINT_COUNT,
            &point_count);
    }

    if ((ok != 0) || (point_count == 0U)) {
        send_ack(CMD_GET_SPECTRUM, ACK_FAIL, ERR_INTERNAL);
        return;
    }

    payload_length = (unsigned short)(6U + (unsigned int)point_count * 16U);
    if ((unsigned int)payload_length + 7U > TX_FRAME_MAX_SIZE) {
        send_ack(CMD_GET_SPECTRUM, ACK_FAIL, ERR_INTERNAL);
        return;
    }

    write_u16_be(&g_protocol.tx_buffer[offset], point_count);
    offset += 2U;

    g_protocol.timestamp++;
    write_u32_be(&g_protocol.tx_buffer[offset], g_protocol.timestamp);
    offset += 4U;

    for (i = 0U; i < point_count; i++) {
        write_f64_le(&g_protocol.tx_buffer[offset], g_protocol.spectrum_points[i].freq_hz);
        write_f64_le(&g_protocol.tx_buffer[offset + 8U], g_protocol.spectrum_points[i].amp_dbm);
        offset += 16U;
    }

    send_frame_inplace(CMD_SPECTRUM_DATA, payload_length);
}

static int fake_status_provider(device_status_t *status)
{
    status->temperature_c = 32.5;
    status->battery_percent = 85U;
    status->error_code = 0U;
    return 0;
}

static int fake_spectrum_provider(
    const device_control_config_t *config,
    spectrum_point_t *points,
    unsigned short max_points,
    unsigned short *out_point_count)
{
    unsigned short point_count = sanitize_point_count(config->sweep.point_count);
    double start_hz = config->frequency.start_hz;
    double stop_hz = config->frequency.stop_hz;
    double step_hz;
    unsigned int i;

    if (point_count > max_points) {
        point_count = max_points;
    }

    if (stop_hz <= start_hz) {
        start_hz = 0.0;
        stop_hz = 1.0e9;
    }

    step_hz = (point_count > 1U) ? ((stop_hz - start_hz) / (double)(point_count - 1U)) : 0.0;

    for (i = 0U; i < point_count; i++) {
        double ratio = (point_count > 1U) ? ((double)i / (double)(point_count - 1U)) : 0.0;
        points[i].freq_hz = start_hz + step_hz * (double)i;
        points[i].amp_dbm = make_fake_amplitude(ratio, config);
    }

    *out_point_count = point_count;
    return 0;
}

static double make_fake_amplitude(double ratio, const device_control_config_t *config)
{
    double peak1_center = 0.22;
    double peak2_center = 0.68;
    double peak1_width = 0.004 + (1.5e6 / (config->bandwidth.rbw_hz + 1.0)) * 0.0002;
    double peak2_width = 0.007 + (1.0e6 / (config->bandwidth.rbw_hz + 1.0)) * 0.0002;
    double detect_bias = (double)config->detect.detect_mode * 0.8;
    double mode_bias = (double)config->sweep.mode * 1.2;
    double noise = ((double)(fake_rand() % 1000U) / 1000.0) * 2.5;
    double baseline = -88.0 + noise + detect_bias - mode_bias;
    double peak1 = 36.0 * exp(-((ratio - peak1_center) * (ratio - peak1_center)) / peak1_width);
    double peak2 = 24.0 * exp(-((ratio - peak2_center) * (ratio - peak2_center)) / peak2_width);

    return baseline + peak1 + peak2;
}

static unsigned int fake_rand(void)
{
    g_protocol.rng_state = g_protocol.rng_state * 1664525U + 1013904223U;
    return g_protocol.rng_state;
}

static void send_frame(unsigned char cmd, const unsigned char *data, unsigned short length)
{
    unsigned int offset = 0U;
    unsigned short crc;

    if ((unsigned int)length + 7U > TX_FRAME_MAX_SIZE) {
        return;
    }

    g_protocol.tx_buffer[offset++] = FRAME_START_BYTE;
    write_u16_be(&g_protocol.tx_buffer[offset], length);
    offset += 2U;
    g_protocol.tx_buffer[offset++] = cmd;

    if ((data != 0) && (length > 0U)) {
        memmove(&g_protocol.tx_buffer[offset], data, length);
        offset += length;
    }

    crc = crc16_modbus(&g_protocol.tx_buffer[1], 2U + 1U + length);
    write_u16_be(&g_protocol.tx_buffer[offset], crc);
    offset += 2U;
    g_protocol.tx_buffer[offset++] = FRAME_END_BYTE;

    uart_send_bytes(g_protocol.tx_buffer, offset);
}

static void send_frame_inplace(unsigned char cmd, unsigned short length)
{
    unsigned int offset = 0U;
    unsigned short crc;

    if ((unsigned int)length + 7U > TX_FRAME_MAX_SIZE) {
        return;
    }

    g_protocol.tx_buffer[offset++] = FRAME_START_BYTE;
    write_u16_be(&g_protocol.tx_buffer[offset], length);
    offset += 2U;
    g_protocol.tx_buffer[offset++] = cmd;

    crc = crc16_modbus(&g_protocol.tx_buffer[1], 2U + 1U + length);
    write_u16_be(&g_protocol.tx_buffer[4U + length], crc);
    g_protocol.tx_buffer[6U + length] = FRAME_END_BYTE;

    uart_send_bytes(g_protocol.tx_buffer, 7U + length);
}

static unsigned short crc16_modbus(const unsigned char *data, unsigned int length)
{
    unsigned short crc = 0xFFFFU;
    unsigned int i;
    unsigned int bit;

    for (i = 0U; i < length; i++) {
        crc ^= (unsigned short)data[i];
        for (bit = 0U; bit < 8U; bit++) {
            if ((crc & 0x0001U) != 0U) {
                crc = (unsigned short)((crc >> 1U) ^ 0xA001U);
            } else {
                crc = (unsigned short)(crc >> 1U);
            }
        }
    }

    return crc;
}

static void uart_send_bytes(const unsigned char *data, unsigned int length)
{
    unsigned int i;

    for (i = 0U; i < length; i++) {
        XUartPs_SendByte(UART_BASEADDR, data[i]);
    }
}

static void write_u16_be(unsigned char *dst, unsigned short value)
{
    dst[0] = (unsigned char)((value >> 8) & 0xFFU);
    dst[1] = (unsigned char)(value & 0xFFU);
}

static void write_u32_be(unsigned char *dst, unsigned int value)
{
    dst[0] = (unsigned char)((value >> 24) & 0xFFU);
    dst[1] = (unsigned char)((value >> 16) & 0xFFU);
    dst[2] = (unsigned char)((value >> 8) & 0xFFU);
    dst[3] = (unsigned char)(value & 0xFFU);
}

static void write_f64_le(unsigned char *dst, double value)
{
    union {
        double d;
        unsigned char b[8];
    } conv;
    unsigned int i;

    conv.d = value;
    for (i = 0U; i < 8U; i++) {
        dst[i] = conv.b[i];
    }
}

static unsigned short read_u16_le(const unsigned char *src)
{
    return (unsigned short)(((unsigned short)src[1] << 8) | (unsigned short)src[0]);
}

static double read_f64_le(const unsigned char *src)
{
    union {
        double d;
        unsigned char b[8];
    } conv;
    unsigned int i;

    for (i = 0U; i < 8U; i++) {
        conv.b[i] = src[i];
    }
    return conv.d;
}

static unsigned short sanitize_point_count(unsigned short value)
{
    if (value < MIN_POINT_COUNT) {
        return DEFAULT_POINT_COUNT;
    }
    if (value > MAX_POINT_COUNT) {
        return MAX_POINT_COUNT;
    }
    return value;
}
