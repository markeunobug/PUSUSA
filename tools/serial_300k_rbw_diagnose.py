import argparse
import csv
import math
import statistics
import struct
import sys
import time
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

import serial


START_BYTE = 0xAA
END_BYTE = 0x55

CMD_SET_FREQ = 0x01
CMD_SET_AMPLITUDE = 0x02
CMD_SET_BW = 0x03
CMD_SET_SWEEP = 0x05
CMD_GET_SPECTRUM = 0x06
CMD_GET_STATUS = 0x07
CMD_STOP_SWEEP = 0x0A
CMD_SET_VGA_GAIN = 0x0B
CMD_SET_RF_FRONTEND = 0x0C
CMD_GET_RF_FRONTEND = 0x0D
CMD_GET_PROFILE = 0x0E

CMD_ACK = 0x81
CMD_SPECTRUM_DATA = 0x82
CMD_STATUS_DATA = 0x83
CMD_RF_FRONTEND_STATUS = 0x84
CMD_PROFILE_DATA = 0x85

RBW_MODES = {
    "1k": (5, 1_000.0),
    "10k": (0, 10_000.0),
    "30k": (1, 30_000.0),
    "100k": (2, 100_000.0),
    "300k": (3, 300_000.0),
    "1m": (4, 1_000_000.0),
}

LNA_MODES = {
    "bypass": 0,
    "enable": 1,
    "auto": 2,
}

PATH_MODES = {
    "direct-if": 0,
    "mixer": 1,
    "auto": 2,
}

VGA_CODES = {
    "-10": 0x00,
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

NOMINAL_IF_HZ = 40.0e6


@dataclass
class SpectrumPoint:
    frame_index: int
    timestamp: int
    total_points: int
    current_index: int
    done: bool
    freq_hz: int
    amp_dbm: float


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


def extract_frames(buffer: bytearray) -> list[bytes]:
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


def parse_frame(frame: bytes) -> tuple[int, bytes]:
    payload_len = struct.unpack(">H", frame[1:3])[0]
    return frame[3], frame[4:4 + payload_len]


def pack_frequency_payload(start_hz: float, stop_hz: float) -> bytes:
    center_hz = (start_hz + stop_hz) / 2.0
    span_hz = stop_hz - start_hz
    return (
        struct.pack("<d", start_hz)
        + struct.pack("<d", stop_hz)
        + struct.pack("<d", center_hz)
        + struct.pack("<d", span_hz)
    )


def pack_amplitude_payload(ref_level_dbm: float, attenuator_mode: int, preamp_mode: int) -> bytes:
    return (
        struct.pack("<d", ref_level_dbm)
        + bytes([attenuator_mode & 0xFF, preamp_mode & 0xFF])
    )


def pack_bw_payload(rbw_mode: int, rbw_hz: float) -> bytes:
    return (
        bytes([rbw_mode & 0xFF])
        + struct.pack("<d", rbw_hz)
        + bytes([0])
        + struct.pack("<d", rbw_hz)
    )


def pack_sweep_payload(speed_hz: float, mode: int, point_count: int) -> bytes:
    return (
        struct.pack("<d", speed_hz)
        + bytes([mode & 0xFF])
        + struct.pack("<H", point_count & 0xFFFF)
    )


def pack_rf_frontend_payload(lna_mode: str, path_mode: str, atten_code: int) -> bytes:
    return bytes([
        LNA_MODES[lna_mode],
        PATH_MODES[path_mode],
        atten_code & 0x7F,
        0x01,
    ])


def parse_spectrum_payload(payload: bytes, frame_index: int) -> list[SpectrumPoint]:
    if len(payload) < 11:
        return []
    point_count = struct.unpack(">H", payload[0:2])[0]
    timestamp = struct.unpack(">I", payload[2:6])[0]
    total_points = struct.unpack(">H", payload[6:8])[0]
    current_index = struct.unpack(">H", payload[8:10])[0]
    done = payload[10] != 0
    points = []
    offset = 11
    for i in range(point_count):
        if offset + 8 > len(payload):
            break
        freq_hz = struct.unpack("<I", payload[offset:offset + 4])[0]
        amp_dbm = struct.unpack("<f", payload[offset + 4:offset + 8])[0]
        points.append(
            SpectrumPoint(
                frame_index=frame_index,
                timestamp=timestamp,
                total_points=total_points,
                current_index=current_index + i,
                done=done,
                freq_hz=freq_hz,
                amp_dbm=amp_dbm,
            )
        )
        offset += 8
    return points


def describe_frame(cmd: int, payload: bytes, frame_index: int) -> str:
    if cmd == CMD_ACK and len(payload) >= 3:
        return f"ACK cmd=0x{payload[0]:02X} success={payload[1]} error={payload[2]}"
    if cmd == CMD_RF_FRONTEND_STATUS and len(payload) >= 5:
        return (
            "RF_STATUS "
            f"lna={payload[0]} path={payload[1]} atten_code={payload[2]} "
            f"gpio=0x{payload[3]:02X} error={payload[4]}"
        )
    if cmd == CMD_STATUS_DATA and len(payload) >= 59:
        temperature_c = struct.unpack("<d", payload[0:8])[0]
        desc = (
            "STATUS "
            f"temp={temperature_c:.1f}C battery={payload[8]} error={payload[9]} "
            f"dma_start={struct.unpack('>I', payload[10:14])[0]} "
            f"dma_error={struct.unpack('>I', payload[14:18])[0]} "
            f"frame_ready={struct.unpack('>I', payload[18:22])[0]} "
            f"process_frame={struct.unpack('>I', payload[22:26])[0]} "
            f"spectrum_valid={payload[26]} "
            f"s2mm_dmacr=0x{struct.unpack('>I', payload[27:31])[0]:08X} "
            f"s2mm_dmasr=0x{struct.unpack('>I', payload[31:35])[0]:08X} "
            f"dma_irq={struct.unpack('>I', payload[35:39])[0]} "
            f"last_irq=0x{struct.unpack('>I', payload[39:43])[0]:08X} "
            f"uart_bad={struct.unpack('>I', payload[43:47])[0]} "
            f"uart_crc={struct.unpack('>I', payload[47:51])[0]} "
            f"uart_overrun={struct.unpack('>I', payload[51:55])[0]} "
            f"uart_resync={struct.unpack('>I', payload[55:59])[0]}"
        )
        if len(payload) >= 103:
            desc += (
                " PL "
                f"avail={payload[59]} mode={payload[60]} out={payload[61]} "
                f"status=0x{struct.unpack('>I', payload[63:67])[0]:08X} "
                f"fs={struct.unpack('>I', payload[67:71])[0]} "
                f"decim={struct.unpack('>I', payload[71:75])[0]} "
                f"frame_words={struct.unpack('>I', payload[75:79])[0]} "
                f"fmt=0x{struct.unpack('>I', payload[79:83])[0]:08X} "
                f"ver=0x{struct.unpack('>I', payload[83:87])[0]:08X} "
                f"in={struct.unpack('>I', payload[87:91])[0]} "
                f"out_count={struct.unpack('>I', payload[91:95])[0]} "
                f"drop={struct.unpack('>I', payload[95:99])[0]} "
                f"err={struct.unpack('>I', payload[99:103])[0]}"
            )
        return desc
    if cmd == CMD_PROFILE_DATA and len(payload) >= 24:
        version = payload[0]
        enabled = payload[1]
        rbw_mode = payload[2]
        counts_per_second = struct.unpack(">I", payload[4:8])[0]
        sweep_count = struct.unpack(">I", payload[8:12])[0]
        point_count = struct.unpack(">I", payload[12:16])[0]
        dma_rearm_count = struct.unpack(">I", payload[16:20])[0]
        section_count = struct.unpack(">H", payload[20:22])[0]
        base_len = 24 + section_count * 30
        dsp_debug = ""
        if len(payload) >= base_len + 44 and payload[base_len:base_len + 4] == b"DSPK":
            o = base_len
            ext_len = payload[o + 5]
            dsp_debug = (
                " DSP_PEAK "
                f"version={payload[o + 4]} ext_len={ext_len} "
                f"current_rbw_mode={payload[o + 6]} "
                f"point_index={struct.unpack('>I', payload[o + 8:o + 12])[0]} "
                f"pre_count={struct.unpack('>I', payload[o + 12:o + 16])[0]} "
                f"post_count={struct.unpack('>I', payload[o + 16:o + 20])[0]} "
                f"pre_power_dbfs={struct.unpack('<f', payload[o + 20:o + 24])[0]:.2f} "
                f"post_power_dbfs={struct.unpack('<f', payload[o + 24:o + 28])[0]:.2f} "
                f"pre_peak_freq_hz={struct.unpack('<f', payload[o + 28:o + 32])[0]:+.0f} "
                f"pre_peak_dbfs={struct.unpack('<f', payload[o + 32:o + 36])[0]:.2f} "
                f"post_peak_freq_hz={struct.unpack('<f', payload[o + 36:o + 40])[0]:+.0f} "
                f"post_peak_dbfs={struct.unpack('<f', payload[o + 40:o + 44])[0]:.2f}"
            )
            if len(payload) >= base_len + 72 and ext_len >= 72:
                dsp_debug += (
                    " DDC "
                    f"ddc_count={struct.unpack('>I', payload[o + 44:o + 48])[0]} "
                    f"ddc_power_dbfs={struct.unpack('<f', payload[o + 48:o + 52])[0]:.2f} "
                    f"ddc_dc_dbfs={struct.unpack('<f', payload[o + 52:o + 56])[0]:.2f} "
                    f"ddc_pos10k_dbfs={struct.unpack('<f', payload[o + 56:o + 60])[0]:.2f} "
                    f"ddc_neg10k_dbfs={struct.unpack('<f', payload[o + 60:o + 64])[0]:.2f} "
                    f"ddc_pos100k_dbfs={struct.unpack('<f', payload[o + 64:o + 68])[0]:.2f} "
                    f"ddc_neg100k_dbfs={struct.unpack('<f', payload[o + 68:o + 72])[0]:.2f}"
                )
            if len(payload) >= base_len + 112 and ext_len >= 112:
                dsp_debug += (
                    " SWEEP "
                    f"state={payload[o + 72]} "
                    f"err={payload[o + 73]} "
                    f"frame_ready={payload[o + 74]} "
                    f"dma_err={payload[o + 75]} "
                    f"wait={struct.unpack('>I', payload[o + 76:o + 80])[0]} "
                    f"dma_start={struct.unpack('>I', payload[o + 80:o + 84])[0]} "
                    f"dmasr=0x{struct.unpack('>I', payload[o + 84:o + 88])[0]:08X} "
                    f"last_irq=0x{struct.unpack('>I', payload[o + 88:o + 92])[0]:08X} "
                    f"pl_out_arm={struct.unpack('>I', payload[o + 92:o + 96])[0]} "
                    f"pl_out_now={struct.unpack('>I', payload[o + 96:o + 100])[0]} "
                    f"accum={struct.unpack('>I', payload[o + 100:o + 104])[0]} "
                    f"target={struct.unpack('>I', payload[o + 104:o + 108])[0]} "
                    f"bytes={struct.unpack('>I', payload[o + 108:o + 112])[0]}"
                )
        return (
            "PROFILE "
            f"version={version} enabled={enabled} rbw_mode={rbw_mode} "
            f"cps={counts_per_second} sweeps={sweep_count} "
            f"points={point_count} dma_rearms={dma_rearm_count} sections={section_count}"
            f"{dsp_debug}"
        )
    if cmd == CMD_SPECTRUM_DATA:
        points = parse_spectrum_payload(payload, frame_index)
        if not points:
            return f"SPECTRUM short len={len(payload)}"
        first = points[0]
        return (
            "SPECTRUM "
            f"progress={first.current_index + len(points)}/{first.total_points} "
            f"done={first.done} freq={first.freq_hz / 1e6:.6f}MHz "
            f"amp={first.amp_dbm:.2f}dBm"
        )
    return f"cmd=0x{cmd:02X} len={len(payload)}"


def read_frames(ser: serial.Serial, timeout_s: float, stop_when=None) -> list[tuple[int, bytes]]:
    deadline = time.time() + timeout_s
    rx_buffer = bytearray()
    frames = []
    while time.time() < deadline:
        waiting = ser.in_waiting
        if waiting:
            rx_buffer.extend(ser.read(waiting))
            for frame in extract_frames(rx_buffer):
                item = parse_frame(frame)
                frames.append(item)
                if stop_when is not None and stop_when(item):
                    return frames
        else:
            time.sleep(0.01)
    return frames


def send_command(
    ser: serial.Serial,
    name: str,
    cmd: int,
    payload: bytes = b"",
    wait_s: float = 0.8,
    print_frames: bool = True,
) -> list[tuple[int, bytes]]:
    ser.reset_input_buffer()
    ser.write(build_frame(cmd, payload))
    ser.flush()
    frames = read_frames(ser, wait_s)
    if print_frames:
        if not frames:
            print(f"[{name}] no response")
        for index, (rx_cmd, rx_payload) in enumerate(frames, start=1):
            print(f"[{name}] {describe_frame(rx_cmd, rx_payload, index)}")
    return frames


def stream_spectrum(ser: serial.Serial, point_count: int, timeout_s: float, print_points: bool) -> list[SpectrumPoint]:
    ser.reset_input_buffer()
    ser.write(build_frame(CMD_GET_SPECTRUM, struct.pack("<H", point_count & 0xFFFF)))
    ser.flush()

    points = []
    frame_index = 0
    rx_buffer = bytearray()
    start = time.time()
    deadline = start + timeout_s
    last_data_at = start
    saw_done = False

    while time.time() < deadline:
        waiting = ser.in_waiting
        if waiting:
            rx_buffer.extend(ser.read(waiting))
            for frame in extract_frames(rx_buffer):
                frame_index += 1
                cmd, payload = parse_frame(frame)
                if print_points or cmd != CMD_SPECTRUM_DATA:
                    print(f"[GET_SPECTRUM] {describe_frame(cmd, payload, frame_index)}")
                if cmd == CMD_SPECTRUM_DATA:
                    parsed = parse_spectrum_payload(payload, frame_index)
                    if parsed:
                        points.extend(parsed)
                        last_data_at = time.time()
                        saw_done = parsed[-1].done
                if saw_done:
                    return points
        else:
            if points and (time.time() - last_data_at) > 2.0:
                print("[GET_SPECTRUM] idle for 2s after spectrum data, stop reading")
                break
            time.sleep(0.01)

    return points


def nearest_point(points: list[SpectrumPoint], marker_hz: float) -> SpectrumPoint:
    return min(points, key=lambda point: abs(point.freq_hz - marker_hz))


def write_csv(path: Path, points: list[SpectrumPoint]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow([
            "frame_index",
            "timestamp",
            "total_points",
            "current_index",
            "done",
            "freq_hz",
            "amp_dbm",
        ])
        for point in points:
            writer.writerow([
                point.frame_index,
                point.timestamp,
                point.total_points,
                point.current_index,
                int(point.done),
                point.freq_hz,
                f"{point.amp_dbm:.6f}",
            ])


def summarize(points: list[SpectrumPoint], marker_hz: float, floor_dbm: float, expected_min_peak_dbm: float) -> None:
    if not points:
        print("SUMMARY no spectrum points received")
        return

    amps = [point.amp_dbm for point in points if math.isfinite(point.amp_dbm)]
    peak = max(points, key=lambda point: point.amp_dbm)
    marker = nearest_point(points, marker_hz)
    floor_count = sum(1 for point in points if point.amp_dbm <= floor_dbm)
    total_points_values = sorted(set(point.total_points for point in points))
    done_seen = any(point.done for point in points)

    print("")
    print("SUMMARY")
    print(f"points_received={len(points)} total_points_seen={total_points_values} done_seen={done_seen}")
    print(
        f"amp_min={min(amps):.2f} dBm amp_max={max(amps):.2f} dBm "
        f"amp_mean={statistics.fmean(amps):.2f} dBm amp_median={statistics.median(amps):.2f} dBm"
    )
    print(f"peak={peak.freq_hz / 1e6:.6f} MHz {peak.amp_dbm:.2f} dBm index={peak.current_index}")
    print(
        f"marker_nearest={marker.freq_hz / 1e6:.6f} MHz {marker.amp_dbm:.2f} dBm "
        f"delta={marker.freq_hz - marker_hz:+.0f} Hz index={marker.current_index}"
    )
    print(
        f"floor_count<={floor_dbm:.1f}dBm={floor_count}/{len(points)} "
        f"({floor_count * 100.0 / len(points):.1f}%)"
    )

    if peak.amp_dbm < expected_min_peak_dbm:
        print(
            "DIAG firmware_serial_peak_low: the raw serial spectrum peak is already "
            f"below {expected_min_peak_dbm:.1f} dBm. This points before Flutter drawing/parsing."
        )
    else:
        print(
            "DIAG firmware_serial_peak_ok: raw serial data has a reasonable peak. "
            "If Flutter is low/flat, inspect host parsing, scaling, or trace replacement."
        )


def default_csv_path() -> Path:
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    return Path("tools") / f"serial_300k_rbw_capture_{stamp}.csv"


def apply_fixed_rf_if_mapping(args: argparse.Namespace) -> str | None:
    has_mapping_arg = (
        args.rf_input_hz is not None
        or args.target_if_hz is not None
        or args.target_if_offset_hz is not None
    )
    if not has_mapping_arg:
        return None

    if args.rf_input_hz is None:
        raise ValueError("--rf-input-hz is required when using IF mapping")
    if args.target_if_hz is not None and args.target_if_offset_hz is not None:
        raise ValueError("Use only one of --target-if-hz and --target-if-offset-hz")

    if args.target_if_hz is not None:
        if_offset_hz = args.target_if_hz - args.nominal_if_hz
        target_if_hz = args.target_if_hz
    elif args.target_if_offset_hz is not None:
        if_offset_hz = args.target_if_offset_hz
        target_if_hz = args.nominal_if_hz + if_offset_hz
    else:
        raise ValueError("--target-if-hz or --target-if-offset-hz is required when using IF mapping")

    center_hz = args.rf_input_hz - if_offset_hz
    span_hz = args.span_hz if args.span_hz is not None else max(args.rbw_hz, 10_000.0)
    if span_hz < 0.0:
        raise ValueError("--span-hz must be greater than or equal to 0")

    args.start_hz = center_hz - span_hz / 2.0
    args.stop_hz = center_hz + span_hz / 2.0
    if args.marker_hz is None:
        args.marker_hz = center_hz

    return (
        "IF mapping "
        f"rf_input={args.rf_input_hz / 1e6:.6f} MHz "
        f"nominal_if={args.nominal_if_hz / 1e6:.6f} MHz "
        f"target_if={target_if_hz / 1e6:.6f} MHz "
        f"if_offset={if_offset_hz:+.0f} Hz "
        f"=> sweep_center={center_hz / 1e6:.6f} MHz "
        f"span={span_hz / 1e3:.3f} kHz"
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Diagnose PuSuSA 300 kHz RBW data directly from serial, bypassing Flutter."
    )
    parser.add_argument("--port", default="COM7")
    parser.add_argument("--baud", type=int, default=921600)
    parser.add_argument("--start-hz", type=float, default=900.0e6)
    parser.add_argument("--stop-hz", type=float, default=1.1e9)
    parser.add_argument("--marker-hz", type=float, default=None)
    parser.add_argument("--rbw", choices=sorted(RBW_MODES.keys()), default="300k")
    parser.add_argument("--span-hz", type=float, default=None)
    parser.add_argument("--rf-input-hz", type=float, default=None)
    parser.add_argument("--nominal-if-hz", type=float, default=NOMINAL_IF_HZ)
    parser.add_argument("--target-if-hz", type=float, default=None)
    parser.add_argument("--target-if-offset-hz", type=float, default=None)
    parser.add_argument("--point-count", type=int, default=2048)
    parser.add_argument("--timeout-s", type=float, default=45.0)
    parser.add_argument("--sweep-speed", type=float, default=1.0)
    parser.add_argument("--ref-level-dbm", type=float, default=-20.0)
    parser.add_argument("--lna", choices=sorted(LNA_MODES.keys()), default="bypass")
    parser.add_argument("--path", choices=sorted(PATH_MODES.keys()), default="mixer")
    parser.add_argument("--atten-code", type=int, default=0)
    parser.add_argument("--vga-db", choices=sorted(VGA_CODES.keys(), key=lambda value: float(value)), default="0")
    parser.add_argument("--floor-dbm", type=float, default=-105.0)
    parser.add_argument("--expected-min-peak-dbm", type=float, default=-30.0)
    parser.add_argument("--csv", type=Path, default=None)
    parser.add_argument("--no-config", action="store_true", help="Only request spectrum; do not change device settings.")
    parser.add_argument("--print-points", action="store_true", help="Print every spectrum point while streaming.")
    args = parser.parse_args()

    rbw_mode, rbw_hz = RBW_MODES[args.rbw]
    args.rbw_hz = rbw_hz
    try:
        mapping_description = apply_fixed_rf_if_mapping(args)
    except ValueError as exc:
        print(exc)
        return 2

    if args.stop_hz < args.start_hz:
        print("--stop-hz must be greater than or equal to --start-hz")
        return 2
    if args.marker_hz is None:
        args.marker_hz = (args.start_hz + args.stop_hz) / 2.0

    if args.stop_hz == args.start_hz:
        expected_internal_points = 1
    else:
        expected_internal_points = int((args.stop_hz - args.start_hz) // (rbw_hz / 2.0)) + 1
        expected_internal_points = max(2, min(expected_internal_points, 4096))
    csv_path = args.csv if args.csv is not None else default_csv_path()

    print(
        "Config "
        f"port={args.port} baud={args.baud} "
        f"span={args.start_hz / 1e6:.3f}-{args.stop_hz / 1e6:.3f} MHz "
        f"RBW={rbw_hz / 1e3:.0f} kHz expected_internal_points~{expected_internal_points} "
        f"RF(lna={args.lna}, path={args.path}, atten_code={args.atten_code}, vga={args.vga_db} dB)"
    )
    if mapping_description:
        print(mapping_description)

    try:
        with serial.Serial(args.port, args.baud, timeout=0.05) as ser:
            print(f"Opened {args.port} @ {args.baud}")

            if not args.no_config:
                send_command(ser, "STOP_SWEEP", CMD_STOP_SWEEP, wait_s=0.5)
                send_command(
                    ser,
                    "SET_RF_FRONTEND",
                    CMD_SET_RF_FRONTEND,
                    pack_rf_frontend_payload(args.lna, args.path, args.atten_code),
                )
                send_command(ser, "SET_VGA_GAIN", CMD_SET_VGA_GAIN, bytes([VGA_CODES[args.vga_db]]))
                send_command(
                    ser,
                    "SET_AMPLITUDE",
                    CMD_SET_AMPLITUDE,
                    pack_amplitude_payload(args.ref_level_dbm, 0, 0),
                )
                send_command(ser, "SET_FREQ", CMD_SET_FREQ, pack_frequency_payload(args.start_hz, args.stop_hz))
                send_command(ser, "SET_BW", CMD_SET_BW, pack_bw_payload(rbw_mode, rbw_hz))
                send_command(
                    ser,
                    "SET_SWEEP",
                    CMD_SET_SWEEP,
                    pack_sweep_payload(args.sweep_speed, 0, args.point_count),
                )

            send_command(ser, "GET_RF_FRONTEND", CMD_GET_RF_FRONTEND)
            send_command(ser, "GET_STATUS_BEFORE", CMD_GET_STATUS)
            send_command(ser, "GET_PROFILE_BEFORE", CMD_GET_PROFILE)
            points = stream_spectrum(ser, args.point_count, args.timeout_s, args.print_points)
            send_command(ser, "GET_STATUS_AFTER", CMD_GET_STATUS)
            send_command(ser, "GET_PROFILE_AFTER", CMD_GET_PROFILE)

    except serial.SerialException as exc:
        print(f"Serial error: {exc}")
        print("Hint: close Flutter/other serial tools if COM7 is already open.")
        return 1

    write_csv(csv_path, points)
    print(f"CSV saved: {csv_path.resolve()}")
    summarize(points, args.marker_hz, args.floor_dbm, args.expected_min_peak_dbm)
    return 0


if __name__ == "__main__":
    sys.exit(main())
