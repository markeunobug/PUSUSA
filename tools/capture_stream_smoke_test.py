import argparse
import struct
import time

import serial


START_BYTE = 0xAA
END_BYTE = 0x55

CMD_CAPTURE_STREAM_SMOKE = 0x13
CMD_CAPTURE_SG_SMOKE = 0x14
CMD_CAPTURE_MAIN_SMOKE = 0x15
CMD_CAPTURE_SG_RING_SMOKE = 0x16
CMD_CAPTURE_SG_BURST_SMOKE = 0x17
CMD_ACK = 0x81
CMD_CAPTURE_STREAM_SMOKE_RESULT = 0x88
CMD_CAPTURE_SG_SMOKE_RESULT = 0x89

STREAM_RESULT_FIELDS = [
    "version",
    "result_code",
    "requested_samples",
    "transfer_bytes",
    "dma_completed",
    "dma_error",
    "timed_out",
    "wait_loops",
    "raw_status",
    "status_error_code",
    "total_sample_count_lo",
    "total_sample_count_hi",
    "packet_count",
    "overflow_count",
    "backpressure_count",
    "s2mm_dmacr",
    "s2mm_dmasr",
    "irq_count",
    "last_irq_status",
]

SG_RESULT_FIELDS = [
    "version",
    "result_code",
    "samples_per_bd",
    "bd_count",
    "requested_samples",
    "requested_bytes",
    "completed_bd_count",
    "completed_bytes",
    "dma_completed",
    "dma_error",
    "timed_out",
    "wait_loops",
    "first_bd_status",
    "last_bd_status",
    "raw_status",
    "status_error_code",
    "total_sample_count_lo",
    "total_sample_count_hi",
    "packet_count",
    "overflow_count",
    "backpressure_count",
    "s2mm_dmacr",
    "s2mm_dmasr",
    "irq_count",
    "last_irq_status",
    "debug_config_has_sg",
    "debug_instance_has_sg",
    "debug_ring_ready",
    "debug_dma_device_id",
    "debug_dma_baseaddr",
]

STREAM_RESULT_CODES = {
    0: "OK",
    1: "INVALID_ARG",
    2: "PL_UNAVAILABLE",
    3: "DMA_RESET_FAIL",
    4: "DMA_START_FAIL",
    5: "STREAM_START_FAIL",
    6: "DMA_TIMEOUT",
    7: "DMA_ERROR",
    8: "PL_STATUS_ERROR",
    9: "COUNTER_MISMATCH",
    10: "BACKPRESSURE",
    11: "OVERFLOW",
    12: "BUSY",
}

SG_RESULT_CODES = {
    0: "OK",
    1: "INVALID_ARG",
    2: "UNSUPPORTED",
    3: "PL_UNAVAILABLE",
    4: "DMA_RESET_FAIL",
    5: "RING_SETUP_FAIL",
    6: "BD_ALLOC_FAIL",
    7: "BD_SETUP_FAIL",
    8: "DMA_START_FAIL",
    9: "STREAM_START_FAIL",
    10: "TIMEOUT",
    11: "DMA_ERROR",
    12: "PL_STATUS_ERROR",
    13: "COUNTER_MISMATCH",
    14: "BACKPRESSURE",
    15: "OVERFLOW",
    16: "BUSY",
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
    return (
        bytes([START_BYTE])
        + body
        + struct.pack(">H", crc16_modbus(body))
        + bytes([END_BYTE])
    )


def extract_frames(buffer: bytearray) -> list[tuple[int, bytes]]:
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
        if recv_crc != crc16_modbus(body):
            continue
        frames.append((frame[3], frame[4 : 4 + payload_len]))
    return frames


def read_until_result(
    ser: serial.Serial, timeout_s: float, expected_result_cmd: int
) -> tuple[list[str], dict | None]:
    deadline = time.time() + timeout_s
    buffer = bytearray()
    messages = []
    result = None

    while time.time() < deadline:
        chunk = ser.read(4096)
        if chunk:
            buffer.extend(chunk)
            for cmd, payload in extract_frames(buffer):
                if cmd == CMD_ACK and len(payload) >= 3:
                    messages.append(
                        f"ACK original=0x{payload[0]:02X} "
                        f"success={payload[1]} error={payload[2]}"
                    )
                elif cmd == expected_result_cmd:
                    fields = (
                        SG_RESULT_FIELDS
                        if cmd == CMD_CAPTURE_SG_SMOKE_RESULT
                        else STREAM_RESULT_FIELDS
                    )
                    if len(payload) != 4 * len(fields):
                        messages.append(f"RESULT bad length={len(payload)}")
                        continue
                    values = struct.unpack(">" + "I" * len(fields), payload)
                    result = dict(zip(fields, values))
                    messages.append("RESULT received")
                    return messages, result
                else:
                    messages.append(f"FRAME cmd=0x{cmd:02X} len={len(payload)}")
        else:
            time.sleep(0.01)

    return messages, result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", default="COM7")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument(
        "--mode",
        choices=("stream", "sg", "main", "sgring", "sgburst"),
        default="stream",
    )
    parser.add_argument("--samples", type=int, default=4096)
    parser.add_argument("--samples-per-bd", type=int, default=4096)
    parser.add_argument("--bd-count", type=int, default=4)
    parser.add_argument("--target-bd-count", type=int, default=64)
    parser.add_argument("--timeout", type=float, default=3.0)
    args = parser.parse_args()

    if args.mode == "sgring":
        payload = struct.pack(">III", args.samples_per_bd, args.bd_count, args.target_bd_count)
        frame = build_frame(CMD_CAPTURE_SG_RING_SMOKE, payload)
        expected_result_cmd = CMD_CAPTURE_SG_SMOKE_RESULT
        fields = SG_RESULT_FIELDS
        result_codes = SG_RESULT_CODES
    elif args.mode == "sgburst":
        payload = struct.pack(">II", args.samples_per_bd, args.bd_count)
        frame = build_frame(CMD_CAPTURE_SG_BURST_SMOKE, payload)
        expected_result_cmd = CMD_CAPTURE_SG_SMOKE_RESULT
        fields = SG_RESULT_FIELDS
        result_codes = SG_RESULT_CODES
    elif args.mode == "sg":
        payload = struct.pack(">II", args.samples_per_bd, args.bd_count)
        frame = build_frame(CMD_CAPTURE_SG_SMOKE, payload)
        expected_result_cmd = CMD_CAPTURE_SG_SMOKE_RESULT
        fields = SG_RESULT_FIELDS
        result_codes = SG_RESULT_CODES
    elif args.mode == "main":
        payload = struct.pack(">I", args.samples)
        frame = build_frame(CMD_CAPTURE_MAIN_SMOKE, payload)
        expected_result_cmd = CMD_CAPTURE_STREAM_SMOKE_RESULT
        fields = STREAM_RESULT_FIELDS
        result_codes = STREAM_RESULT_CODES
    else:
        payload = struct.pack(">I", args.samples)
        frame = build_frame(CMD_CAPTURE_STREAM_SMOKE, payload)
        expected_result_cmd = CMD_CAPTURE_STREAM_SMOKE_RESULT
        fields = STREAM_RESULT_FIELDS
        result_codes = STREAM_RESULT_CODES

    with serial.Serial(args.port, args.baud, timeout=0.05) as ser:
        ser.reset_input_buffer()
        ser.write(frame)
        ser.flush()
        messages, result = read_until_result(ser, args.timeout, expected_result_cmd)

    for message in messages:
        print(message)

    if result is None:
        print("No smoke result frame received")
        return 2

    code_name = result_codes.get(result["result_code"], "UNKNOWN")
    print(f"result_code={result['result_code']} ({code_name})")
    for key in fields:
        value = result[key]
        if key in {
            "raw_status",
            "s2mm_dmacr",
            "s2mm_dmasr",
            "last_irq_status",
            "first_bd_status",
            "last_bd_status",
        }:
            print(f"{key}=0x{value:08X}")
        else:
            print(f"{key}={value}")

    return 0 if result["result_code"] == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
