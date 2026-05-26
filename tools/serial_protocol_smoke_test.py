import argparse
import struct
import sys
import time

import serial


START_BYTE = 0xAA
END_BYTE = 0x55

CMD_SET_FREQ = 0x01
CMD_SET_AMPLITUDE = 0x02
CMD_SET_BW = 0x03
CMD_SET_DETECT = 0x04
CMD_SET_SWEEP = 0x05
CMD_GET_SPECTRUM = 0x06
CMD_GET_STATUS = 0x07
CMD_RESET = 0x08
CMD_SET_RF_FRONTEND = 0x0C
CMD_GET_RF_FRONTEND = 0x0D

CMD_ACK = 0x81
CMD_SPECTRUM_DATA = 0x82
CMD_STATUS_DATA = 0x83
CMD_RF_FRONTEND_STATUS = 0x84

RF_PATH_MODES = {
    "direct-if": 0,
    "mixer": 1,
    "auto": 2,
}

RF_LNA_MODES = {
    "bypass": 0,
    "enable": 1,
    "auto": 2,
}


def crc16_modbus(data: bytes) -> int:
    crc = 0xFFFF
    for byte in data:
        crc ^= byte
        for _ in range(8):
            if crc & 1:
                crc = (crc >> 1) ^ 0xA001
            else:
                crc >>= 1
    return crc & 0xFFFF


def build_frame(cmd: int, payload: bytes = b"") -> bytes:
    body = struct.pack(">H", len(payload)) + bytes([cmd]) + payload
    crc = crc16_modbus(body)
    return bytes([START_BYTE]) + body + struct.pack(">H", crc) + bytes([END_BYTE])


def extract_frames(buffer: bytearray):
    frames = []
    while True:
        if len(buffer) < 7:
            break
        if buffer[0] != START_BYTE:
            del buffer[0]
            continue
        payload_len = struct.unpack(">H", bytes(buffer[1:3]))[0]
        frame_len = 1 + 2 + 1 + payload_len + 2 + 1
        if len(buffer) < frame_len:
            break
        frame = bytes(buffer[:frame_len])
        del buffer[:frame_len]
        if frame[-1] != END_BYTE:
            continue
        body = frame[1:-3]
        recv_crc = struct.unpack(">H", frame[-3:-1])[0]
        calc_crc = crc16_modbus(body)
        if recv_crc != calc_crc:
            continue
        frames.append(frame)
    return frames


def parse_frame(frame: bytes):
    payload_len = struct.unpack(">H", frame[1:3])[0]
    cmd = frame[3]
    payload = frame[4:4 + payload_len]
    return cmd, payload


def read_frames(ser: serial.Serial, timeout_s: float, stop_when=None):
    deadline = time.time() + timeout_s
    rx_buffer = bytearray()
    frames = []
    while time.time() < deadline:
        waiting = ser.in_waiting
        if waiting:
            rx_buffer.extend(ser.read(waiting))
            for frame in extract_frames(rx_buffer):
                frames.append(frame)
                if stop_when is not None and stop_when(frame):
                    return frames
            deadline = time.time() + 0.3
        else:
            time.sleep(0.02)
    return frames


def format_hex(data: bytes, limit: int = 96) -> str:
    head = data[:limit]
    text = head.hex(" ").upper()
    if len(data) > limit:
        text += " ..."
    return text


def decode_status(payload: bytes) -> str:
    if len(payload) < 10:
        return "status payload too short"
    temperature = struct.unpack("<d", payload[0:8])[0]
    battery = payload[8]
    error_code = payload[9]
    text = f"temperature={temperature:.2f}, battery={battery}, error={error_code}"
    if len(payload) >= 27:
        dma_start = struct.unpack(">I", payload[10:14])[0]
        dma_error = struct.unpack(">I", payload[14:18])[0]
        frame_ready = struct.unpack(">I", payload[18:22])[0]
        process_frame = struct.unpack(">I", payload[22:26])[0]
        spectrum_valid = payload[26]
        text += (
            f", dma_start={dma_start}, dma_error={dma_error}, "
            f"frame_ready={frame_ready}, process_frame={process_frame}, "
            f"spectrum_valid={spectrum_valid}"
        )
    if len(payload) >= 43:
        s2mm_dmacr = struct.unpack(">I", payload[27:31])[0]
        s2mm_dmasr = struct.unpack(">I", payload[31:35])[0]
        dma_irq_count = struct.unpack(">I", payload[35:39])[0]
        dma_last_irq_status = struct.unpack(">I", payload[39:43])[0]
        text += (
            f", s2mm_dmacr=0x{s2mm_dmacr:08X}, s2mm_dmasr=0x{s2mm_dmasr:08X}, "
            f"dma_irq_count={dma_irq_count}, dma_last_irq=0x{dma_last_irq_status:08X}"
        )
    if len(payload) >= 59:
        rx_bad_frame = struct.unpack(">I", payload[43:47])[0]
        rx_crc_error = struct.unpack(">I", payload[47:51])[0]
        rx_overrun = struct.unpack(">I", payload[51:55])[0]
        rx_resync = struct.unpack(">I", payload[55:59])[0]
        text += (
            f", uart_rx_bad_frame={rx_bad_frame}, "
            f"uart_rx_crc_error={rx_crc_error}, "
            f"uart_rx_overrun={rx_overrun}, uart_rx_resync={rx_resync}"
        )
    return text


def decode_spectrum(payload: bytes) -> str:
    if len(payload) < 11:
        return "spectrum payload too short"
    point_count = struct.unpack(">H", payload[0:2])[0]
    timestamp = struct.unpack(">I", payload[2:6])[0]
    total_points = struct.unpack(">H", payload[6:8])[0]
    current_index = struct.unpack(">H", payload[8:10])[0]
    done = payload[10] != 0
    expected = 11 + point_count * 8
    if len(payload) < expected:
        return (
            f"point_count={point_count}, timestamp={timestamp}, "
            f"total_points={total_points}, current_index={current_index}, "
            f"done={done}, payload_truncated={len(payload)}"
        )
    first_freq = struct.unpack("<I", payload[11:15])[0]
    first_amp = struct.unpack("<f", payload[15:19])[0]
    last_base = 11 + (point_count - 1) * 8
    last_freq = struct.unpack("<I", payload[last_base:last_base + 4])[0]
    last_amp = struct.unpack("<f", payload[last_base + 4:last_base + 8])[0]
    return (
        f"point_count={point_count}, timestamp={timestamp}, "
        f"progress={current_index + point_count}/{total_points}, done={done}, "
        f"first=({first_freq:.3f}, {first_amp:.3f}), "
        f"last=({last_freq:.3f}, {last_amp:.3f})"
    )


def decode_spectrum_points(payload: bytes) -> tuple[int, int, bool, list[tuple[int, float]]]:
    if len(payload) < 11:
        return 0, 0, False, []
    point_count = struct.unpack(">H", payload[0:2])[0]
    total_points = struct.unpack(">H", payload[6:8])[0]
    current_index = struct.unpack(">H", payload[8:10])[0]
    done = payload[10] != 0
    points = []
    offset = 11
    for _ in range(point_count):
        if offset + 8 > len(payload):
            break
        freq_hz = struct.unpack("<I", payload[offset:offset + 4])[0]
        amp_dbm = struct.unpack("<f", payload[offset + 4:offset + 8])[0]
        points.append((freq_hz, amp_dbm))
        offset += 8
    return total_points, current_index, done, points


def pack_frequency_payload(start_hz: float, stop_hz: float, center_hz: float, span_hz: float) -> bytes:
    return (
        struct.pack("<d", start_hz) +
        struct.pack("<d", stop_hz) +
        struct.pack("<d", center_hz) +
        struct.pack("<d", span_hz)
    )


def pack_rf_frontend_payload(lna_mode: str, path_mode: str, atten_code: int) -> bytes:
    return bytes([
        RF_LNA_MODES[lna_mode],
        RF_PATH_MODES[path_mode],
        atten_code & 0x7F,
        0x01,
    ])


def decode_rf_frontend(payload: bytes) -> str:
    if len(payload) < 5:
        return "rf frontend payload too short"
    return (
        f"lna={payload[0]}, path={payload[1]}, atten_code={payload[2]}, "
        f"gpio=0x{payload[3]:02X}, error={payload[4]}"
    )


def print_decoded_frame(frame: bytes):
    cmd, payload = parse_frame(frame)
    print(f"  RX cmd=0x{cmd:02X}, len={len(payload)}")
    print(f"  RX raw={format_hex(frame)}")
    if cmd == CMD_ACK and len(payload) >= 3:
        print(
            f"  ACK original_cmd=0x{payload[0]:02X}, success={payload[1]}, error={payload[2]}"
        )
    elif cmd == CMD_STATUS_DATA:
        print(f"  STATUS {decode_status(payload)}")
    elif cmd == CMD_SPECTRUM_DATA:
        print(f"  SPECTRUM {decode_spectrum(payload)}")
    elif cmd == CMD_RF_FRONTEND_STATUS:
        print(f"  RF_FRONTEND {decode_rf_frontend(payload)}")


def do_transaction(ser: serial.Serial, name: str, cmd: int, payload: bytes = b"", timeout_s: float = 1.0):
    frame = build_frame(cmd, payload)
    print(f"[{name}] TX {format_hex(frame, limit=len(frame))}")
    ser.reset_input_buffer()
    ser.write(frame)
    ser.flush()
    frames = read_frames(ser, timeout_s)
    print(f"[{name}] RX_FRAMES {len(frames)}")
    for frame_item in frames:
        print_decoded_frame(frame_item)
    if not frames:
        print(f"[{name}] no response")
    print("---")


def stream_spectrum_summary(ser: serial.Serial, point_count: int, timeout_s: float):
    frame = build_frame(CMD_GET_SPECTRUM, struct.pack("<H", point_count & 0xFFFF))
    print(f"[GET_SPECTRUM] TX {format_hex(frame, limit=len(frame))}")
    ser.reset_input_buffer()
    ser.write(frame)
    ser.flush()

    def is_done(frame_item: bytes) -> bool:
        cmd, payload = parse_frame(frame_item)
        return cmd == CMD_SPECTRUM_DATA and len(payload) >= 11 and payload[10] != 0

    frames = read_frames(ser, timeout_s, stop_when=is_done)
    points = []
    total_points_values = set()
    done_seen = False
    for frame_item in frames:
        cmd, payload = parse_frame(frame_item)
        if cmd != CMD_SPECTRUM_DATA:
            print_decoded_frame(frame_item)
            continue
        total_points, _, done, parsed_points = decode_spectrum_points(payload)
        if total_points:
            total_points_values.add(total_points)
        done_seen = done_seen or done
        points.extend(parsed_points)

    print(f"[GET_SPECTRUM] RX_FRAMES {len(frames)} spectrum_points {len(points)}")
    if not points:
        print("[GET_SPECTRUM] no spectrum points")
        print("---")
        return

    peak_freq, peak_amp = max(points, key=lambda item: item[1])
    first_freq, first_amp = points[0]
    last_freq, last_amp = points[-1]
    print(
        "  SUMMARY "
        f"total_points_seen={sorted(total_points_values)} done_seen={done_seen} "
        f"first=({first_freq / 1e6:.6f} MHz, {first_amp:.2f} dBm) "
        f"last=({last_freq / 1e6:.6f} MHz, {last_amp:.2f} dBm) "
        f"peak=({peak_freq / 1e6:.6f} MHz, {peak_amp:.2f} dBm)"
    )
    print("---")


def main():
    parser = argparse.ArgumentParser(description="Smoke-test the Zynq binary serial protocol.")
    parser.add_argument("--port", default="COM12", help="Serial port, default COM12")
    parser.add_argument("--baud", type=int, default=921600, help="Baud rate, default 921600")
    parser.add_argument(
        "--mode",
        choices=["basic", "status", "spectrum", "direct-if-fft"],
        default="basic",
        help="basic=status+spectrum, direct-if-fft=configures direct IF and summarizes FFT bins",
    )
    parser.add_argument("--start-hz", type=float, default=0.0, help="Start frequency in Hz")
    parser.add_argument("--stop-hz", type=float, default=1.0e9, help="Stop frequency in Hz")
    parser.add_argument("--center-hz", type=float, default=5.0e8, help="Center frequency in Hz")
    parser.add_argument("--span-hz", type=float, default=1.0e9, help="Span in Hz")
    parser.add_argument("--point-count", type=int, default=None, help="Requested spectrum point count")
    parser.add_argument("--rf-lna", choices=sorted(RF_LNA_MODES.keys()), default="bypass")
    parser.add_argument("--rf-path", choices=sorted(RF_PATH_MODES.keys()), default=None)
    parser.add_argument("--rf-atten-code", type=int, default=127)
    parser.add_argument("--no-config", action="store_true", help="Do not send SET_FREQ/SET_RF_FRONTEND before requesting data")
    args = parser.parse_args()
    point_count = args.point_count
    if point_count is None:
        point_count = 2048 if args.mode == "direct-if-fft" else 256

    try:
        with serial.Serial(args.port, args.baud, timeout=0.2) as ser:
            print(f"Opened {args.port} @ {args.baud}")
            if not args.no_config:
                rf_path = args.rf_path or ("direct-if" if args.mode == "direct-if-fft" else None)
                if rf_path is not None:
                    do_transaction(
                        ser,
                        "SET_RF_FRONTEND",
                        CMD_SET_RF_FRONTEND,
                        pack_rf_frontend_payload(args.rf_lna, rf_path, args.rf_atten_code),
                        timeout_s=0.8,
                    )
                if args.mode != "direct-if-fft":
                    freq_payload = pack_frequency_payload(
                        args.start_hz,
                        args.stop_hz,
                        args.center_hz,
                        args.span_hz,
                    )
                    do_transaction(ser, "SET_FREQ", CMD_SET_FREQ, freq_payload, timeout_s=0.8)
            if args.mode in ("basic", "status"):
                do_transaction(ser, "GET_STATUS", CMD_GET_STATUS, timeout_s=0.8)
            if args.mode == "direct-if-fft":
                do_transaction(ser, "GET_RF_FRONTEND", CMD_GET_RF_FRONTEND, timeout_s=0.8)
                stream_spectrum_summary(ser, point_count, timeout_s=8.0)
            if args.mode in ("basic", "spectrum"):
                do_transaction(
                    ser,
                    "GET_SPECTRUM",
                    CMD_GET_SPECTRUM,
                    struct.pack("<H", point_count & 0xFFFF),
                    timeout_s=1.5,
                )
    except serial.SerialException as exc:
        print(f"Serial error: {exc}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
