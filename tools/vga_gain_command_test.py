import argparse
import struct
import sys
import time

import serial


START_BYTE = 0xAA
END_BYTE = 0x55
CMD_SET_VGA_GAIN = 0x0B
CMD_ACK = 0x81

GAIN_CODES = {
    "-11": 0x05,
    "-10": 0x06,
    "-6": 0x09,
    "-3": 0x0D,
    "0": 0x12,
    "3": 0x19,
    "6": 0x24,
    "10": 0x39,
    "20": 0x99,
    "30": 0xD0,
    "34": 0xFF,
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
    while len(buffer) >= 7:
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
        if recv_crc == crc16_modbus(body):
            frames.append(frame)
    return frames


def format_hex(data: bytes) -> str:
    return data.hex(" ").upper()


def main() -> int:
    parser = argparse.ArgumentParser(description="Send CMD_SET_VGA_GAIN to PuSuSA lower machine.")
    parser.add_argument("--port", default="COM12")
    parser.add_argument("--baud", type=int, default=921600)
    parser.add_argument("--gain", choices=sorted(GAIN_CODES.keys(), key=lambda x: int(x)), default="0")
    parser.add_argument("--code", type=lambda s: int(s, 0), help="Override raw AD8370 gain code, e.g. 0x39")
    parser.add_argument("--timeout-s", type=float, default=1.0)
    args = parser.parse_args()

    code = args.code if args.code is not None else GAIN_CODES[args.gain]
    if code < 0 or code > 0xFF:
        print("gain code must be 0..255")
        return 2

    frame = build_frame(CMD_SET_VGA_GAIN, bytes([code]))
    print(f"TX CMD_SET_VGA_GAIN code=0x{code:02X}: {format_hex(frame)}")

    try:
        with serial.Serial(args.port, args.baud, timeout=0.05) as ser:
            ser.reset_input_buffer()
            ser.write(frame)
            ser.flush()

            deadline = time.time() + args.timeout_s
            rx_buffer = bytearray()
            frames = []
            while time.time() < deadline:
                waiting = ser.in_waiting
                if waiting:
                    rx_buffer.extend(ser.read(waiting))
                    frames.extend(extract_frames(rx_buffer))
                    if frames:
                        break
                else:
                    time.sleep(0.01)

            if not frames:
                print("RX no response")
                return 1

            for item in frames:
                payload_len = struct.unpack(">H", item[1:3])[0]
                cmd = item[3]
                payload = item[4:4 + payload_len]
                print(f"RX cmd=0x{cmd:02X}, len={payload_len}, raw={format_hex(item)}")
                if cmd == CMD_ACK and len(payload) >= 3:
                    print(
                        f"ACK original_cmd=0x{payload[0]:02X}, "
                        f"success={payload[1]}, error={payload[2]}"
                    )
                    if payload[0] == CMD_SET_VGA_GAIN and payload[1] == 1 and payload[2] == 0:
                        print("VGA command accepted by lower machine.")
                        return 0
            return 1
    except serial.SerialException as exc:
        print(f"Serial error: {exc}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
