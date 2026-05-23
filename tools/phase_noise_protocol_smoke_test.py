import argparse
import math
import struct
import sys
from dataclasses import dataclass


START_BYTE = 0xAA
END_BYTE = 0x55

CMD_SET_PHASE_NOISE_CONFIG = 0x0F
CMD_START_PHASE_NOISE = 0x10
CMD_STOP_PHASE_NOISE = 0x11
CMD_GET_PHASE_NOISE_STATUS = 0x12
CMD_PHASE_NOISE_DATA = 0x86
CMD_PHASE_NOISE_STATUS = 0x87

PN_VERSION = 1
PN_FLAG_DONE = 1 << 0
PN_FLAG_CARRIER_VALID = 1 << 1
PN_FLAG_WARNING = 1 << 2
PN_FLAG_PHASE_NOISE_VALID = 1 << 5

PN_STATUS_CONFIGURED = 1 << 0
PN_STATUS_RUNNING = 1 << 1
PN_STATUS_CARRIER_VALID = 1 << 2
PN_STATUS_DATA_VALID = 1 << 3
PN_STATUS_WARNING = 1 << 4
PN_STATUS_COMPLETE = 1 << 6

PN_STATE_MEASURING = 3
PN_ERR_OK = 0
PN_WARN_ENBW_ESTIMATED = 2
DEFAULT_POINTS_PER_DECADE = 60
DEFAULT_CARRIER_SEARCH_SPAN_KHZ = 100
DEFAULT_MINIMUM_CARRIER_LEVEL_DBM = -50


class ProtocolError(Exception):
    pass


@dataclass(frozen=True)
class PhaseNoiseDataPoint:
    version: int
    flags: int
    trace_id: int
    total_points: int
    current_index: int
    average_index: int
    carrier_hz: float
    carrier_level_dbm: float
    offset_hz: int
    noise_power_dbm: float
    phase_noise_dbc_hz: float
    rbw_hz: int
    error_code: int


@dataclass(frozen=True)
class PhaseNoiseStatus:
    version: int
    state: int
    flags: int
    error_code: int
    trace_id: int
    total_points: int
    current_index: int
    average_index: int
    nominal_carrier_hz: float
    measured_carrier_hz: float
    carrier_level_dbm: float
    start_offset_hz: float
    stop_offset_hz: float
    current_offset_hz: int
    current_rbw_hz: int
    elapsed_ms: int
    warning_code: int


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
    if not 0 <= cmd <= 0xFF:
        raise ValueError("cmd must fit in one byte")
    if len(payload) > 0xFFFF:
        raise ValueError("payload too long")
    body = struct.pack(">H", len(payload)) + bytes([cmd]) + payload
    crc = crc16_modbus(body)
    return bytes([START_BYTE]) + body + struct.pack(">H", crc) + bytes([END_BYTE])


def parse_frame(frame: bytes) -> tuple[int, bytes]:
    if len(frame) < 7:
        raise ProtocolError("frame too short")
    if frame[0] != START_BYTE:
        raise ProtocolError("bad start byte")
    if frame[-1] != END_BYTE:
        raise ProtocolError("bad end byte")

    payload_len = struct.unpack(">H", frame[1:3])[0]
    expected_len = 1 + 2 + 1 + payload_len + 2 + 1
    if len(frame) != expected_len:
        raise ProtocolError(f"bad frame length: expected {expected_len}, got {len(frame)}")

    body = frame[1:-3]
    expected_crc = struct.unpack(">H", frame[-3:-1])[0]
    actual_crc = crc16_modbus(body)
    if actual_crc != expected_crc:
        raise ProtocolError(
            f"bad crc: expected 0x{expected_crc:04X}, calculated 0x{actual_crc:04X}"
        )

    return frame[3], frame[4 : 4 + payload_len]


def build_config_payload(
    *,
    flags: int = 0b00000110,
    carrier_mode: int = 1,
    sideband_mode: int = 0,
    nominal_carrier_hz: float = 100_000_000.0,
    start_offset_hz: float = 1_000.0,
    stop_offset_hz: float = 1_000_000.0,
    points_per_decade: int = DEFAULT_POINTS_PER_DECADE,
    average_count: int = 10,
    carrier_search_span_khz: int = DEFAULT_CARRIER_SEARCH_SPAN_KHZ,
    minimum_carrier_level_dbm_i8: int = DEFAULT_MINIMUM_CARRIER_LEVEL_DBM,
) -> bytes:
    if not 0 <= carrier_search_span_khz <= 0xFFFF:
        raise ValueError("carrier_search_span_khz must fit in uint16")
    if not -128 <= minimum_carrier_level_dbm_i8 <= 127:
        raise ValueError("minimum_carrier_level_dbm_i8 must fit in int8")

    payload = bytearray()
    payload.extend(struct.pack("BBBB", PN_VERSION, flags, carrier_mode, sideband_mode))
    payload.extend(struct.pack("<d", nominal_carrier_hz))
    payload.extend(struct.pack("<d", start_offset_hz))
    payload.extend(struct.pack("<d", stop_offset_hz))
    payload.extend(struct.pack("<H", points_per_decade))
    payload.extend(struct.pack("<H", average_count))
    payload.extend(struct.pack("<HbB", carrier_search_span_khz, minimum_carrier_level_dbm_i8, 0))
    if len(payload) != 36:
        raise AssertionError(f"config payload length is {len(payload)}, expected 36")
    return bytes(payload)


def build_data_payload(
    *,
    trace_id: int = 7,
    total_points: int = 4,
    current_index: int = 0,
    average_index: int = 1,
    carrier_hz: float = 100_000_000.0,
    carrier_level_dbm: float = 0.0,
    offset_hz: int = 10_000,
    noise_power_dbm: float = -80.0,
    rbw_hz: int = 10_000,
    error_code: int = PN_ERR_OK,
    done: bool = False,
) -> bytes:
    phase_noise_dbc_hz = noise_power_dbm - carrier_level_dbm - 10.0 * math.log10(rbw_hz)
    flags = PN_FLAG_CARRIER_VALID | PN_FLAG_PHASE_NOISE_VALID
    if done:
        flags |= PN_FLAG_DONE
    payload = bytearray()
    payload.extend(struct.pack("BB", PN_VERSION, flags))
    payload.extend(struct.pack(">HHHH", trace_id, total_points, current_index, average_index))
    payload.extend(struct.pack("<d", carrier_hz))
    payload.extend(struct.pack("<f", carrier_level_dbm))
    payload.extend(struct.pack("<I", offset_hz))
    payload.extend(struct.pack("<f", noise_power_dbm))
    payload.extend(struct.pack("<f", phase_noise_dbc_hz))
    payload.extend(struct.pack("<I", rbw_hz))
    payload.extend(struct.pack("B", error_code))
    payload.extend(b"\x00\x00\x00")
    if len(payload) != 42:
        raise AssertionError(f"data payload length is {len(payload)}, expected 42")
    return bytes(payload)


def build_status_payload(
    *,
    trace_id: int = 7,
    total_points: int = 4,
    current_index: int = 1,
    average_index: int = 1,
    nominal_carrier_hz: float = 100_000_000.0,
    measured_carrier_hz: float = 100_000_000.0,
    carrier_level_dbm: float = 0.0,
    start_offset_hz: float = 1_000.0,
    stop_offset_hz: float = 1_000_000.0,
    current_offset_hz: int = 10_000,
    current_rbw_hz: int = 10_000,
    elapsed_ms: int = 250,
    warning_code: int = PN_WARN_ENBW_ESTIMATED,
) -> bytes:
    flags = (
        PN_STATUS_CONFIGURED
        | PN_STATUS_RUNNING
        | PN_STATUS_CARRIER_VALID
        | PN_STATUS_DATA_VALID
        | PN_STATUS_WARNING
        | PN_STATUS_COMPLETE
    )
    payload = bytearray()
    payload.extend(struct.pack("BBBB", PN_VERSION, PN_STATE_MEASURING, flags, PN_ERR_OK))
    payload.extend(struct.pack(">HHHH", trace_id, total_points, current_index, average_index))
    payload.extend(struct.pack("<d", nominal_carrier_hz))
    payload.extend(struct.pack("<d", measured_carrier_hz))
    payload.extend(struct.pack("<f", carrier_level_dbm))
    payload.extend(struct.pack("<d", start_offset_hz))
    payload.extend(struct.pack("<d", stop_offset_hz))
    payload.extend(struct.pack("<I", current_offset_hz))
    payload.extend(struct.pack("<I", current_rbw_hz))
    payload.extend(struct.pack("<I", elapsed_ms))
    payload.extend(struct.pack("<H", warning_code))
    payload.extend(b"\x00\x00")
    if len(payload) != 64:
        raise AssertionError(f"status payload length is {len(payload)}, expected 64")
    return bytes(payload)


def parse_phase_noise_data(payload: bytes) -> PhaseNoiseDataPoint:
    if len(payload) != 42:
        raise ProtocolError(f"PHASE_NOISE_DATA payload must be 42B, got {len(payload)}")
    if payload[0] != PN_VERSION:
        raise ProtocolError(f"unsupported data version {payload[0]}")
    if payload[39:42] != b"\x00\x00\x00":
        raise ProtocolError("data reserved bytes must be zero")

    trace_id, total_points, current_index, average_index = struct.unpack(">HHHH", payload[2:10])
    carrier_hz = struct.unpack("<d", payload[10:18])[0]
    carrier_level_dbm = struct.unpack("<f", payload[18:22])[0]
    offset_hz = struct.unpack("<I", payload[22:26])[0]
    noise_power_dbm = struct.unpack("<f", payload[26:30])[0]
    phase_noise_dbc_hz = struct.unpack("<f", payload[30:34])[0]
    rbw_hz = struct.unpack("<I", payload[34:38])[0]
    error_code = payload[38]

    return PhaseNoiseDataPoint(
        version=payload[0],
        flags=payload[1],
        trace_id=trace_id,
        total_points=total_points,
        current_index=current_index,
        average_index=average_index,
        carrier_hz=carrier_hz,
        carrier_level_dbm=carrier_level_dbm,
        offset_hz=offset_hz,
        noise_power_dbm=noise_power_dbm,
        phase_noise_dbc_hz=phase_noise_dbc_hz,
        rbw_hz=rbw_hz,
        error_code=error_code,
    )


def parse_phase_noise_status(payload: bytes) -> PhaseNoiseStatus:
    if len(payload) != 64:
        raise ProtocolError(f"PHASE_NOISE_STATUS payload must be 64B, got {len(payload)}")
    if payload[0] != PN_VERSION:
        raise ProtocolError(f"unsupported status version {payload[0]}")
    if payload[62:64] != b"\x00\x00":
        raise ProtocolError("status reserved bytes must be zero")

    trace_id, total_points, current_index, average_index = struct.unpack(">HHHH", payload[4:12])
    nominal_carrier_hz = struct.unpack("<d", payload[12:20])[0]
    measured_carrier_hz = struct.unpack("<d", payload[20:28])[0]
    carrier_level_dbm = struct.unpack("<f", payload[28:32])[0]
    start_offset_hz = struct.unpack("<d", payload[32:40])[0]
    stop_offset_hz = struct.unpack("<d", payload[40:48])[0]
    current_offset_hz = struct.unpack("<I", payload[48:52])[0]
    current_rbw_hz = struct.unpack("<I", payload[52:56])[0]
    elapsed_ms = struct.unpack("<I", payload[56:60])[0]
    warning_code = struct.unpack("<H", payload[60:62])[0]

    return PhaseNoiseStatus(
        version=payload[0],
        state=payload[1],
        flags=payload[2],
        error_code=payload[3],
        trace_id=trace_id,
        total_points=total_points,
        current_index=current_index,
        average_index=average_index,
        nominal_carrier_hz=nominal_carrier_hz,
        measured_carrier_hz=measured_carrier_hz,
        carrier_level_dbm=carrier_level_dbm,
        start_offset_hz=start_offset_hz,
        stop_offset_hz=stop_offset_hz,
        current_offset_hz=current_offset_hz,
        current_rbw_hz=current_rbw_hz,
        elapsed_ms=elapsed_ms,
        warning_code=warning_code,
    )


def assert_close(actual: float, expected: float, tolerance: float, label: str) -> None:
    if abs(actual - expected) > tolerance:
        raise ProtocolError(f"{label}: expected {expected:.6f}, got {actual:.6f}")


def format_hex(data: bytes) -> str:
    return data.hex(" ").upper()


def run_smoke_test(
    dump_hex: bool = False,
    points_per_decade: int = DEFAULT_POINTS_PER_DECADE,
    carrier_search_span_khz: int = DEFAULT_CARRIER_SEARCH_SPAN_KHZ,
    minimum_carrier_level_dbm_i8: int = DEFAULT_MINIMUM_CARRIER_LEVEL_DBM,
) -> None:
    config_payload = build_config_payload(
        points_per_decade=points_per_decade,
        carrier_search_span_khz=carrier_search_span_khz,
        minimum_carrier_level_dbm_i8=minimum_carrier_level_dbm_i8,
    )
    configured_points_per_decade = struct.unpack("<H", config_payload[28:30])[0]
    if configured_points_per_decade != points_per_decade:
        raise ProtocolError(
            "SET_PHASE_NOISE_CONFIG points_per_decade mismatch: "
            f"expected {points_per_decade}, got {configured_points_per_decade}"
        )
    configured_search_span_khz = struct.unpack("<H", config_payload[32:34])[0]
    configured_minimum_level_dbm = struct.unpack("b", config_payload[34:35])[0]
    configured_reserved = config_payload[35]
    if configured_search_span_khz != carrier_search_span_khz:
        raise ProtocolError(
            "SET_PHASE_NOISE_CONFIG carrier_search_span_khz mismatch at offset 32: "
            f"expected {carrier_search_span_khz}, got {configured_search_span_khz}"
        )
    if configured_minimum_level_dbm != minimum_carrier_level_dbm_i8:
        raise ProtocolError(
            "SET_PHASE_NOISE_CONFIG minimum_carrier_level_dbm_i8 mismatch at offset 34: "
            f"expected {minimum_carrier_level_dbm_i8}, got {configured_minimum_level_dbm}"
        )
    if configured_reserved != 0:
        raise ProtocolError("SET_PHASE_NOISE_CONFIG reserved byte at offset 35 must be zero")
    if dump_hex:
        print(
            "SET_PHASE_NOISE_CONFIG fields: "
            f"offset32 carrier_search_span_khz={configured_search_span_khz}, "
            f"offset34 minimum_carrier_level_dbm_i8={configured_minimum_level_dbm}, "
            f"offset35 reserved={configured_reserved}"
        )

    request_frames = [
        ("SET_PHASE_NOISE_CONFIG", CMD_SET_PHASE_NOISE_CONFIG, config_payload),
        ("START_PHASE_NOISE", CMD_START_PHASE_NOISE, b""),
        ("GET_PHASE_NOISE_STATUS", CMD_GET_PHASE_NOISE_STATUS, b""),
        ("STOP_PHASE_NOISE", CMD_STOP_PHASE_NOISE, b""),
    ]

    for name, cmd, payload in request_frames:
        frame = build_frame(cmd, payload)
        parsed_cmd, parsed_payload = parse_frame(frame)
        if parsed_cmd != cmd or parsed_payload != payload:
            raise ProtocolError(f"{name}: parsed frame does not match original")
        if dump_hex:
            print(f"{name}: {format_hex(frame)}")

    data_frame = build_frame(CMD_PHASE_NOISE_DATA, build_data_payload())
    parsed_cmd, parsed_payload = parse_frame(data_frame)
    if parsed_cmd != CMD_PHASE_NOISE_DATA:
        raise ProtocolError("PHASE_NOISE_DATA command mismatch")
    data = parse_phase_noise_data(parsed_payload)
    expected_dbc_hz = data.noise_power_dbm - data.carrier_level_dbm - 10.0 * math.log10(data.rbw_hz)
    assert_close(data.phase_noise_dbc_hz, expected_dbc_hz, 1e-5, "phase_noise_dbc_hz")
    if data.flags & PN_FLAG_PHASE_NOISE_VALID == 0:
        raise ProtocolError("phase noise valid flag is not set")
    if dump_hex:
        print(f"PHASE_NOISE_DATA: {format_hex(data_frame)}")

    status_frame = build_frame(CMD_PHASE_NOISE_STATUS, build_status_payload())
    parsed_cmd, parsed_payload = parse_frame(status_frame)
    if parsed_cmd != CMD_PHASE_NOISE_STATUS:
        raise ProtocolError("PHASE_NOISE_STATUS command mismatch")
    status = parse_phase_noise_status(parsed_payload)
    if status.warning_code != PN_WARN_ENBW_ESTIMATED:
        raise ProtocolError("status warning code mismatch")
    if status.current_rbw_hz <= 0:
        raise ProtocolError("status current_rbw_hz must be positive")
    if dump_hex:
        print(f"PHASE_NOISE_STATUS: {format_hex(status_frame)}")

    corrupted = bytearray(data_frame)
    corrupted[-2] ^= 0x01
    try:
        parse_frame(bytes(corrupted))
    except ProtocolError:
        pass
    else:
        raise ProtocolError("corrupted CRC frame was accepted")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Offline smoke-test for PuSuSA phase-noise UART frames."
    )
    parser.add_argument(
        "--dump-hex",
        action="store_true",
        help="Print generated request and response frames in hex.",
    )
    parser.add_argument(
        "--points-per-decade",
        type=int,
        default=DEFAULT_POINTS_PER_DECADE,
        help=(
            "points_per_decade to encode in SET_PHASE_NOISE_CONFIG "
            f"(default: {DEFAULT_POINTS_PER_DECADE})."
        ),
    )
    parser.add_argument(
        "--carrier-search-span-khz",
        type=int,
        default=DEFAULT_CARRIER_SEARCH_SPAN_KHZ,
        help=(
            "carrier_search_span_khz to encode at SET_PHASE_NOISE_CONFIG offset 32 "
            f"(default: {DEFAULT_CARRIER_SEARCH_SPAN_KHZ}; 0 asks firmware to use its default)."
        ),
    )
    parser.add_argument(
        "--minimum-carrier-level-dbm",
        type=int,
        default=DEFAULT_MINIMUM_CARRIER_LEVEL_DBM,
        help=(
            "minimum_carrier_level_dbm_i8 to encode at SET_PHASE_NOISE_CONFIG offset 34 "
            f"(default: {DEFAULT_MINIMUM_CARRIER_LEVEL_DBM})."
        ),
    )
    args = parser.parse_args()

    try:
        run_smoke_test(
            dump_hex=args.dump_hex,
            points_per_decade=args.points_per_decade,
            carrier_search_span_khz=args.carrier_search_span_khz,
            minimum_carrier_level_dbm_i8=args.minimum_carrier_level_dbm,
        )
    except ProtocolError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1

    print("PASS: phase-noise protocol frame construction and parsing checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
