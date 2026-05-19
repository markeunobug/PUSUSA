import argparse
import struct
import sys
import time

import serial


START_BYTE = 0xAA
END_BYTE = 0x55

CMD_SET_FREQ = 0x01
CMD_SET_BW = 0x03
CMD_GET_SPECTRUM = 0x06

CMD_ACK = 0x81
CMD_SPECTRUM_DATA = 0x82

RBW_MODES = {
    "10k": (0, 10_000.0),
    "30k": (1, 30_000.0),
    "100k": (2, 100_000.0),
    "300k": (3, 300_000.0),
    "1m": (4, 1_000_000.0),
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
        if recv_crc != crc16_modbus(body):
            continue
        frames.append(frame)
    return frames


def parse_frame(frame: bytes):
    payload_len = struct.unpack(">H", frame[1:3])[0]
    cmd = frame[3]
    payload = frame[4:4 + payload_len]
    return cmd, payload


def format_hex(data: bytes, limit: int = 96) -> str:
    text = data[:limit].hex(" ").upper()
    if len(data) > limit:
        text += " ..."
    return text


def pack_frequency_payload(start_hz: float, stop_hz: float) -> bytes:
    center_hz = (start_hz + stop_hz) / 2.0
    span_hz = stop_hz - start_hz
    return (
        struct.pack("<d", start_hz) +
        struct.pack("<d", stop_hz) +
        struct.pack("<d", center_hz) +
        struct.pack("<d", span_hz)
    )


def pack_bw_payload(rbw_mode: int, rbw_hz: float, vbw_hz: float) -> bytes:
    # Protocol payload: rbw_mode/u8 + rbw_hz/f64le + vbw_mode/u8 + vbw_hz/f64le.
    return (
        bytes([rbw_mode & 0xFF]) +
        struct.pack("<d", rbw_hz) +
        bytes([1]) +
        struct.pack("<d", vbw_hz)
    )


def describe_frame(frame: bytes) -> str:
    cmd, payload = parse_frame(frame)
    if cmd == CMD_ACK and len(payload) >= 3:
        return (
            f"ACK original_cmd=0x{payload[0]:02X}, "
            f"success={payload[1]}, error={payload[2]}"
        )
    if cmd == CMD_SPECTRUM_DATA:
        if len(payload) < 19:
            return f"SPECTRUM short_payload len={len(payload)}"
        point_count = struct.unpack(">H", payload[0:2])[0]
        timestamp = struct.unpack(">I", payload[2:6])[0]
        total_points = struct.unpack(">H", payload[6:8])[0]
        current_index = struct.unpack(">H", payload[8:10])[0]
        done = payload[10] != 0
        first_freq = struct.unpack("<I", payload[11:15])[0]
        first_amp = struct.unpack("<f", payload[15:19])[0]
        return (
            f"SPECTRUM points={point_count}, timestamp={timestamp}, "
            f"progress={current_index + point_count}/{total_points}, "
            f"done={done}, "
            f"freq={first_freq / 1e6:.6f} MHz, amp={first_amp:.2f} dBm"
        )
    return f"cmd=0x{cmd:02X}, len={len(payload)}, raw={format_hex(frame)}"


def transact(ser: serial.Serial, name: str, cmd: int, payload: bytes, timeout_s: float) -> list[bytes]:
    frame = build_frame(cmd, payload)
    print(f"[{name}] TX {format_hex(frame, len(frame))}")
    ser.reset_input_buffer()
    ser.write(frame)
    ser.flush()

    deadline = time.time() + timeout_s
    rx_buffer = bytearray()
    frames = []
    while time.time() < deadline:
        waiting = ser.in_waiting
        if waiting:
            rx_buffer.extend(ser.read(waiting))
            for item in extract_frames(rx_buffer):
                frames.append(item)
                print(f"[{name}] RX {describe_frame(item)}")
        else:
            time.sleep(0.01)

    if not frames:
        print(f"[{name}] no response")
    print("---")
    return frames


def stream_spectrum(ser: serial.Serial, point_count: int, max_frames: int, timeout_s: float):
    frame = build_frame(CMD_GET_SPECTRUM, struct.pack("<H", point_count & 0xFFFF))
    print(f"[GET_SPECTRUM] TX {format_hex(frame, len(frame))}")
    ser.reset_input_buffer()
    ser.write(frame)
    ser.flush()

    rx_buffer = bytearray()
    spectrum_frames = 0
    all_frames = 0
    start_time = time.time()
    deadline = start_time + timeout_s
    last_rx_time = start_time

    while time.time() < deadline and spectrum_frames < max_frames:
        waiting = ser.in_waiting
        saw_done = False
        if waiting:
            rx_buffer.extend(ser.read(waiting))
            for item in extract_frames(rx_buffer):
                all_frames += 1
                last_rx_time = time.time()
                cmd, payload = parse_frame(item)
                if cmd == CMD_SPECTRUM_DATA:
                    spectrum_frames += 1
                print(f"[GET_SPECTRUM] RX#{all_frames} {describe_frame(item)}")
                if cmd == CMD_SPECTRUM_DATA and len(payload) >= 11 and payload[10] != 0:
                    saw_done = True
                    break
            if saw_done:
                break
        else:
            if spectrum_frames > 0 and (time.time() - last_rx_time) > 2.0:
                print("[GET_SPECTRUM] idle for 2s after data, stop reading")
                break
            time.sleep(0.01)

    elapsed = time.time() - start_time
    print(
        f"[GET_SPECTRUM] done: frames={all_frames}, "
        f"spectrum_frames={spectrum_frames}, elapsed={elapsed:.2f}s"
    )
    print("---")


def main() -> int:
    parser = argparse.ArgumentParser(description="Stream-print PuSuSA sweep data over serial.")
    parser.add_argument("--port", default="COM7")
    parser.add_argument("--baud", type=int, default=921600)
    parser.add_argument("--start-hz", type=float, default=50.0e6)
    parser.add_argument("--stop-hz", type=float, default=60.0e6)
    parser.add_argument("--rbw", choices=sorted(RBW_MODES.keys()), default="1m")
    parser.add_argument("--point-count", type=int, default=256)
    parser.add_argument("--max-frames", type=int, default=300)
    parser.add_argument("--timeout-s", type=float, default=30.0)
    args = parser.parse_args()

    if args.stop_hz <= args.start_hz:
        print("--stop-hz must be greater than --start-hz")
        return 2

    rbw_mode, rbw_hz = RBW_MODES[args.rbw]
    expected_points = int((args.stop_hz - args.start_hz) // (rbw_hz / 2.0)) + 1
    expected_points = max(2, min(expected_points, 4096))
    print(
        f"Config: {args.start_hz / 1e6:.3f}-{args.stop_hz / 1e6:.3f} MHz, "
        f"RBW={rbw_hz / 1e3:.0f} kHz, expected_internal_points~{expected_points}"
    )

    try:
        with serial.Serial(args.port, args.baud, timeout=0.05) as ser:
            print(f"Opened {args.port} @ {args.baud}")
            transact(
                ser,
                "SET_FREQ",
                CMD_SET_FREQ,
                pack_frequency_payload(args.start_hz, args.stop_hz),
                timeout_s=1.0,
            )
            transact(
                ser,
                "SET_BW",
                CMD_SET_BW,
                pack_bw_payload(rbw_mode, rbw_hz, rbw_hz),
                timeout_s=1.0,
            )
            stream_spectrum(ser, args.point_count, args.max_frames, args.timeout_s)
    except serial.SerialException as exc:
        print(f"Serial error: {exc}")
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
