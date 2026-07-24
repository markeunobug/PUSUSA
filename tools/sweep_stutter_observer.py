import argparse
import csv
import statistics
import struct
import sys
import time
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

import serial

import serial_300k_rbw_diagnose as proto


SECTION_NAMES = [
    "point_total",
    "set_lo1",
    "wait_lock",
    "dma_reset",
    "dma_start",
    "dma_wait",
    "accumulate",
    "measure",
    "emit_uart",
    "acc_ddc",
    "acc_cic",
]

DMA_BURST_FIELDS = [
    "valid",
    "sequence",
    "samples_per_bd",
    "bd_count",
    "requested_samples",
    "requested_bytes",
    "completed_bd_count",
    "completed_bytes",
    "wait_loops",
    "result_code",
    "reset_us",
    "cache_flush_us",
    "bd_submit_us",
    "pl_start_us",
    "wait_reclaim_us",
    "stop_us",
    "cache_invalidate_us",
    "status_us",
    "final_reset_us",
    "total_us",
    "packet_count",
    "burst_packet_count",
    "burst_remaining",
    "overflow_count",
    "backpressure_count",
    "raw_status",
    "s2mm_dmasr",
    "irq_count",
    "last_irq_status",
]

DMA_ERROR_DETAIL_FIELDS = [
    ("dma_error_bg_irq", 59),
    ("dma_error_bg_start", 63),
    ("dma_error_bg_reset", 67),
    ("dma_error_sweep_reset", 71),
    ("dma_error_direct_if", 75),
    ("dma_error_phase_noise", 79),
    ("dma_error_capture_test", 83),
]

DMA_START_DETAIL_FIELDS = [
    ("dma_start_last_result", 87),
    ("dma_start_last_transfer_bytes", 91),
    ("dma_start_last_capture_samples", 95),
    ("dma_start_last_s2mm_dmasr", 99),
    ("dma_start_last_sg_ring_ready", 103),
    ("dma_start_last_sg_active_bd_count", 107),
    ("dma_start_last_sg_free_bd_count", 111),
]

DMA_START_FAIL_FIELDS = [
    ("dma_start_fail_invalid_arg", 115),
    ("dma_start_fail_invalid_samples", 119),
    ("dma_start_fail_pl_abort", 123),
    ("dma_start_fail_pl_clear", 127),
    ("dma_start_fail_pl_config", 131),
    ("dma_start_fail_submit_sg", 135),
    ("dma_start_fail_simple_transfer", 139),
    ("dma_start_fail_pl_start", 143),
]

DMA_START_RESULT_NAMES = {
    0: "OK",
    1: "INVALID_ARG",
    2: "INVALID_SAMPLES",
    3: "PL_ABORT_FAIL",
    4: "PL_CLEAR_FAIL",
    5: "PL_CONFIG_FAIL",
    6: "SUBMIT_SG_FAIL",
    7: "SIMPLE_TRANSFER_FAIL",
    8: "PL_START_FAIL",
}


@dataclass
class TimedPoint:
    host_time_s: float
    delta_ms: float | None
    frame_index: int
    timestamp: int
    total_points: int
    current_index: int
    done: bool
    freq_hz: int
    amp_dbm: float


def default_csv_path() -> Path:
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    return Path(__file__).with_name(f"sweep_stutter_observe_{stamp}.csv")


def parse_status_payload(payload: bytes) -> dict:
    if len(payload) < 59:
        return {}
    status = {
        "temp_c": struct.unpack("<d", payload[0:8])[0],
        "battery": payload[8],
        "error": payload[9],
        "dma_start": struct.unpack(">I", payload[10:14])[0],
        "dma_error": struct.unpack(">I", payload[14:18])[0],
        "frame_ready": struct.unpack(">I", payload[18:22])[0],
        "process_frame": struct.unpack(">I", payload[22:26])[0],
        "spectrum_valid": payload[26],
        "s2mm_dmacr": struct.unpack(">I", payload[27:31])[0],
        "s2mm_dmasr": struct.unpack(">I", payload[31:35])[0],
        "dma_irq": struct.unpack(">I", payload[35:39])[0],
        "last_irq": struct.unpack(">I", payload[39:43])[0],
        "uart_bad": struct.unpack(">I", payload[43:47])[0],
        "uart_crc": struct.unpack(">I", payload[47:51])[0],
        "uart_overrun": struct.unpack(">I", payload[51:55])[0],
        "uart_resync": struct.unpack(">I", payload[55:59])[0],
    }
    for name, offset in DMA_ERROR_DETAIL_FIELDS:
        if len(payload) >= offset + 4:
            status[name] = struct.unpack(">I", payload[offset:offset + 4])[0]
    for name, offset in DMA_START_DETAIL_FIELDS:
        if len(payload) >= offset + 4:
            status[name] = struct.unpack(">I", payload[offset:offset + 4])[0]
    for name, offset in DMA_START_FAIL_FIELDS:
        if len(payload) >= offset + 4:
            status[name] = struct.unpack(">I", payload[offset:offset + 4])[0]
    return status


def parse_profile_payload(payload: bytes) -> dict:
    if len(payload) < 24:
        return {}

    counts_per_second = struct.unpack(">I", payload[4:8])[0]
    section_count = struct.unpack(">H", payload[20:22])[0]
    profile = {
        "version": payload[0],
        "enabled": payload[1],
        "rbw_mode": payload[2],
        "counts_per_second": counts_per_second,
        "sweeps": struct.unpack(">I", payload[8:12])[0],
        "points": struct.unpack(">I", payload[12:16])[0],
        "dma_rearms": struct.unpack(">I", payload[16:20])[0],
        "sections": [],
        "dma_burst": {},
    }

    offset = 24
    for _ in range(section_count):
        if offset + 30 > len(payload):
            break
        section_id = payload[offset]
        count = struct.unpack(">I", payload[offset + 2:offset + 6])[0]
        total_ticks = struct.unpack(">Q", payload[offset + 6:offset + 14])[0]
        min_ticks = struct.unpack(">Q", payload[offset + 14:offset + 22])[0]
        max_ticks = struct.unpack(">Q", payload[offset + 22:offset + 30])[0]
        name = SECTION_NAMES[section_id] if section_id < len(SECTION_NAMES) else f"section_{section_id}"
        if counts_per_second:
            total_ms = total_ticks * 1000.0 / counts_per_second
            min_ms = min_ticks * 1000.0 / counts_per_second
            max_ms = max_ticks * 1000.0 / counts_per_second
        else:
            total_ms = min_ms = max_ms = 0.0
        avg_ms = total_ms / count if count else 0.0
        profile["sections"].append({
            "id": section_id,
            "name": name,
            "count": count,
            "total_ms": total_ms,
            "avg_ms": avg_ms,
            "min_ms": min_ms,
            "max_ms": max_ms,
        })
        offset += 30

    while offset + 8 <= len(payload):
        magic = payload[offset:offset + 4]
        ext_len = payload[offset + 5]
        if ext_len < 8 or offset + ext_len > len(payload):
            break
        if magic == b"DMAD":
            values = {}
            field_offset = offset + 8
            for name in DMA_BURST_FIELDS:
                if field_offset + 4 > offset + ext_len:
                    break
                values[name] = struct.unpack(">I", payload[field_offset:field_offset + 4])[0]
                field_offset += 4
            values["version"] = payload[offset + 4]
            values["ext_len"] = ext_len
            profile["dma_burst"] = values
        offset += ext_len
    return profile


def request_payload(ser: serial.Serial, name: str, cmd: int, expected_cmd: int) -> bytes | None:
    frames = proto.send_command(ser, name, cmd, print_frames=False)
    for rx_cmd, payload in frames:
        if rx_cmd == expected_cmd:
            print(f"[{name}] {proto.describe_frame(rx_cmd, payload, 1)}")
            return payload
        print(f"[{name}] {proto.describe_frame(rx_cmd, payload, 1)}")
    if not frames:
        print(f"[{name}] no response")
    return None


def stream_spectrum_timed(
    ser: serial.Serial,
    point_count: int,
    timeout_s: float,
    print_points: bool,
) -> list[TimedPoint]:
    ser.reset_input_buffer()
    ser.write(proto.build_frame(proto.CMD_GET_SPECTRUM, struct.pack("<H", point_count & 0xFFFF)))
    ser.flush()

    rx_buffer = bytearray()
    frame_index = 0
    points: list[TimedPoint] = []
    start = time.perf_counter()
    deadline = start + timeout_s
    last_point_time: float | None = None
    last_data_time = start
    saw_done = False

    while time.perf_counter() < deadline:
        waiting = ser.in_waiting
        if waiting:
            rx_buffer.extend(ser.read(waiting))
            for frame in proto.extract_frames(rx_buffer):
                frame_index += 1
                now = time.perf_counter()
                cmd, payload = proto.parse_frame(frame)
                if cmd != proto.CMD_SPECTRUM_DATA:
                    print(f"[STREAM] {proto.describe_frame(cmd, payload, frame_index)}")
                    continue
                parsed = proto.parse_spectrum_payload(payload, frame_index)
                if not parsed:
                    print(f"[STREAM] short spectrum len={len(payload)}")
                    continue
                for point in parsed:
                    delta_ms = None if last_point_time is None else (now - last_point_time) * 1000.0
                    item = TimedPoint(
                        host_time_s=now - start,
                        delta_ms=delta_ms,
                        frame_index=frame_index,
                        timestamp=point.timestamp,
                        total_points=point.total_points,
                        current_index=point.current_index,
                        done=point.done,
                        freq_hz=point.freq_hz,
                        amp_dbm=point.amp_dbm,
                    )
                    points.append(item)
                    last_point_time = now
                    last_data_time = now
                    if print_points:
                        gap = "first" if delta_ms is None else f"{delta_ms:.1f} ms"
                        print(
                            f"POINT {item.current_index + 1}/{item.total_points} "
                            f"t={item.host_time_s:.3f}s gap={gap} "
                            f"freq={item.freq_hz / 1e6:.6f}MHz amp={item.amp_dbm:.2f}dBm "
                            f"done={int(item.done)}"
                        )
                saw_done = parsed[-1].done
                if saw_done:
                    return points
        else:
            now = time.perf_counter()
            if points and (now - last_data_time) > 2.0:
                print("[STREAM] idle for 2s after data, stop reading")
                break
            time.sleep(0.002)

    return points


def percentile(values: list[float], pct: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    index = int(round((len(ordered) - 1) * pct / 100.0))
    return ordered[max(0, min(index, len(ordered) - 1))]


def write_points_csv(path: Path, points: list[TimedPoint]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow([
            "host_time_s",
            "delta_ms",
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
                f"{point.host_time_s:.6f}",
                "" if point.delta_ms is None else f"{point.delta_ms:.3f}",
                point.frame_index,
                point.timestamp,
                point.total_points,
                point.current_index,
                int(point.done),
                point.freq_hz,
                f"{point.amp_dbm:.6f}",
            ])


def print_status_delta(before: dict, after: dict) -> None:
    if not before or not after:
        return
    keys = [
        "dma_start",
        "dma_error",
        "frame_ready",
        "process_frame",
        "dma_irq",
        "uart_bad",
        "uart_crc",
        "uart_overrun",
        "uart_resync",
    ]
    detail_keys = [name for name, _ in DMA_ERROR_DETAIL_FIELDS]
    print("\nSTATUS_DELTA")
    for key in keys:
        print(f"{key}: {after.get(key, 0) - before.get(key, 0)}")
    if any(key in after for key in detail_keys):
        print("dma_error_detail_delta:")
        for key in detail_keys:
            if key in after or key in before:
                print(f"  {key}: {after.get(key, 0) - before.get(key, 0)}")
    if "dma_start_last_result" in after:
        result = after.get("dma_start_last_result", 0)
        result_name = DMA_START_RESULT_NAMES.get(result, f"UNKNOWN_{result}")
        print(
            "dma_start_last_detail: "
            f"result={result}({result_name}) "
            f"bytes={after.get('dma_start_last_transfer_bytes', 0)} "
            f"samples={after.get('dma_start_last_capture_samples', 0)} "
            f"dmasr=0x{after.get('dma_start_last_s2mm_dmasr', 0):08X} "
            f"ring_ready={after.get('dma_start_last_sg_ring_ready', 0)} "
            f"active_bd={after.get('dma_start_last_sg_active_bd_count', 0)} "
            f"free_bd={after.get('dma_start_last_sg_free_bd_count', 0)}"
        )
    fail_keys = [name for name, _ in DMA_START_FAIL_FIELDS]
    if any(key in after for key in fail_keys):
        print("dma_start_fail_delta:")
        for key in fail_keys:
            if key in after or key in before:
                print(f"  {key}: {after.get(key, 0) - before.get(key, 0)}")
    print(f"after_dmasr=0x{after.get('s2mm_dmasr', 0):08X}")
    print(f"after_last_irq=0x{after.get('last_irq', 0):08X}")


def print_profile_summary(profile: dict) -> None:
    if not profile:
        return
    print("\nPROFILE_SUMMARY")
    print(
        f"enabled={profile['enabled']} rbw_mode={profile['rbw_mode']} "
        f"points={profile['points']} dma_rearms={profile['dma_rearms']}"
    )
    sections = [section for section in profile["sections"] if section["count"]]
    sections.sort(key=lambda item: item["total_ms"], reverse=True)
    print("top sections by total time:")
    for section in sections[:8]:
        print(
            f"  {section['name']}: count={section['count']} "
            f"total={section['total_ms']:.3f} ms avg={section['avg_ms']:.3f} ms "
            f"max={section['max_ms']:.3f} ms"
        )
    dma_burst = profile.get("dma_burst") or {}
    if dma_burst:
        print("slowest DMA burst detail:")
        print(
            f"  valid={dma_burst.get('valid', 0)} seq={dma_burst.get('sequence', 0)} "
            f"result={dma_burst.get('result_code', 0)} "
            f"samples_per_bd={dma_burst.get('samples_per_bd', 0)} "
            f"bd={dma_burst.get('bd_count', 0)} "
            f"completed_bd={dma_burst.get('completed_bd_count', 0)} "
            f"wait_loops={dma_burst.get('wait_loops', 0)}"
        )
        print(
            "  us "
            f"total={dma_burst.get('total_us', 0)} "
            f"reset={dma_burst.get('reset_us', 0)} "
            f"flush={dma_burst.get('cache_flush_us', 0)} "
            f"bd_submit={dma_burst.get('bd_submit_us', 0)} "
            f"pl_start={dma_burst.get('pl_start_us', 0)} "
            f"wait_reclaim={dma_burst.get('wait_reclaim_us', 0)} "
            f"stop={dma_burst.get('stop_us', 0)} "
            f"invalidate={dma_burst.get('cache_invalidate_us', 0)} "
            f"status={dma_burst.get('status_us', 0)} "
            f"final_reset={dma_burst.get('final_reset_us', 0)}"
        )
        print(
            f"  pl packet={dma_burst.get('packet_count', 0)} "
            f"burst_packet={dma_burst.get('burst_packet_count', 0)} "
            f"remaining={dma_burst.get('burst_remaining', 0)} "
            f"overflow={dma_burst.get('overflow_count', 0)} "
            f"backpressure={dma_burst.get('backpressure_count', 0)} "
            f"dmasr=0x{dma_burst.get('s2mm_dmasr', 0):08X} "
            f"last_irq=0x{dma_burst.get('last_irq_status', 0):08X}"
        )


def print_point_summary(points: list[TimedPoint]) -> None:
    print("\nPOINT_TIMING")
    if not points:
        print("no points received")
        return
    gaps = [point.delta_ms for point in points if point.delta_ms is not None]
    elapsed = points[-1].host_time_s
    rate = len(points) / elapsed if elapsed > 0 else 0.0
    done_seen = any(point.done for point in points)
    expected = points[-1].total_points if points else 0
    print(
        f"points={len(points)}/{expected} done_seen={int(done_seen)} "
        f"elapsed={elapsed:.3f}s rate={rate:.2f} points/s"
    )
    if gaps:
        max_point = max((point for point in points if point.delta_ms is not None), key=lambda item: item.delta_ms or 0.0)
        print(
            f"gap_ms mean={statistics.mean(gaps):.3f} median={statistics.median(gaps):.3f} "
            f"p95={percentile(gaps, 95):.3f} max={max(gaps):.3f}"
        )
        print(
            f"max_gap_at index={max_point.current_index} "
            f"freq={max_point.freq_hz / 1e6:.6f}MHz"
        )


def main() -> int:
    parser = argparse.ArgumentParser(description="Observe sweep stutter timing over the PuSu serial protocol.")
    parser.add_argument("--port", default="COM7")
    parser.add_argument("--baud", type=int, default=921600)
    parser.add_argument("--start-hz", type=float, default=100.0e6)
    parser.add_argument("--stop-hz", type=float, default=101.0e6)
    parser.add_argument("--marker-hz", type=float, default=None)
    parser.add_argument("--rbw", choices=sorted(proto.RBW_MODES.keys()), default="300k")
    parser.add_argument("--point-count", type=int, default=2048)
    parser.add_argument("--timeout-s", type=float, default=60.0)
    parser.add_argument("--sweep-speed", type=float, default=1.0)
    parser.add_argument("--ref-level-dbm", type=float, default=-20.0)
    parser.add_argument("--lna", choices=sorted(proto.LNA_MODES.keys()), default="bypass")
    parser.add_argument("--path", choices=sorted(proto.PATH_MODES.keys()), default="mixer")
    parser.add_argument("--atten-code", type=int, default=0)
    parser.add_argument("--vga-db", choices=sorted(proto.VGA_CODES.keys(), key=lambda value: float(value)), default="0")
    parser.add_argument("--rf-input-hz", type=float, default=None)
    parser.add_argument("--nominal-if-hz", type=float, default=proto.NOMINAL_IF_HZ)
    parser.add_argument("--target-if-hz", type=float, default=None)
    parser.add_argument("--target-if-offset-hz", type=float, default=None)
    parser.add_argument("--no-config", action="store_true")
    parser.add_argument("--print-points", action="store_true")
    parser.add_argument("--csv", type=Path, default=None)
    args = parser.parse_args()

    rbw_mode, rbw_hz = proto.RBW_MODES[args.rbw]
    args.rbw_hz = rbw_hz
    try:
        mapping_description = proto.apply_fixed_rf_if_mapping(args)
    except ValueError as exc:
        print(exc)
        return 2

    if args.stop_hz < args.start_hz:
        print("--stop-hz must be greater than or equal to --start-hz")
        return 2
    if args.marker_hz is None:
        args.marker_hz = (args.start_hz + args.stop_hz) / 2.0
    expected_points = 1 if args.stop_hz == args.start_hz else int((args.stop_hz - args.start_hz) // (rbw_hz / 2.0)) + 1
    expected_points = max(1, min(expected_points, 4096))
    csv_path = args.csv if args.csv is not None else default_csv_path()

    print(
        "OBSERVE "
        f"port={args.port} baud={args.baud} "
        f"span={args.start_hz / 1e6:.3f}-{args.stop_hz / 1e6:.3f}MHz "
        f"rbw={args.rbw} expected_points~{expected_points}"
    )
    if mapping_description:
        print(mapping_description)

    try:
        with serial.Serial(args.port, args.baud, timeout=0.02) as ser:
            if not args.no_config:
                proto.send_command(ser, "STOP_SWEEP", proto.CMD_STOP_SWEEP, wait_s=0.5)
                proto.send_command(
                    ser,
                    "SET_RF_FRONTEND",
                    proto.CMD_SET_RF_FRONTEND,
                    proto.pack_rf_frontend_payload(args.lna, args.path, args.atten_code),
                )
                proto.send_command(ser, "SET_VGA_GAIN", proto.CMD_SET_VGA_GAIN, bytes([proto.VGA_CODES[args.vga_db]]))
                proto.send_command(
                    ser,
                    "SET_AMPLITUDE",
                    proto.CMD_SET_AMPLITUDE,
                    proto.pack_amplitude_payload(args.ref_level_dbm, 0, 0),
                )
                proto.send_command(ser, "SET_FREQ", proto.CMD_SET_FREQ, proto.pack_frequency_payload(args.start_hz, args.stop_hz))
                proto.send_command(ser, "SET_BW", proto.CMD_SET_BW, proto.pack_bw_payload(rbw_mode, rbw_hz))
                proto.send_command(
                    ser,
                    "SET_SWEEP",
                    proto.CMD_SET_SWEEP,
                    proto.pack_sweep_payload(args.sweep_speed, 0, args.point_count),
                )

            status_before_payload = request_payload(ser, "GET_STATUS_BEFORE", proto.CMD_GET_STATUS, proto.CMD_STATUS_DATA)
            profile_before_payload = request_payload(ser, "GET_PROFILE_BEFORE", proto.CMD_GET_PROFILE, proto.CMD_PROFILE_DATA)
            points = stream_spectrum_timed(ser, args.point_count, args.timeout_s, args.print_points)
            status_after_payload = request_payload(ser, "GET_STATUS_AFTER", proto.CMD_GET_STATUS, proto.CMD_STATUS_DATA)
            profile_after_payload = request_payload(ser, "GET_PROFILE_AFTER", proto.CMD_GET_PROFILE, proto.CMD_PROFILE_DATA)
    except serial.SerialException as exc:
        print(f"Serial error: {exc}")
        print("Hint: close Flutter/other serial tools if COM7 is already open.")
        return 1

    status_before = parse_status_payload(status_before_payload or b"")
    status_after = parse_status_payload(status_after_payload or b"")
    profile_after = parse_profile_payload(profile_after_payload or b"")

    write_points_csv(csv_path, points)
    print(f"\nCSV saved: {csv_path.resolve()}")
    print_point_summary(points)
    print_status_delta(status_before, status_after)
    print_profile_summary(profile_after)

    if profile_before_payload:
        _ = parse_profile_payload(profile_before_payload)
    return 0


if __name__ == "__main__":
    sys.exit(main())
