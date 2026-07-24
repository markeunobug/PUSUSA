import argparse
import csv
import math
import statistics
import struct
import sys
import time
from collections import Counter
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

import serial

import serial_300k_rbw_diagnose as proto


DEFAULT_RBWS = ["1m", "300k", "100k", "30k", "10k", "1k"]


@dataclass
class RunSummary:
    rbw: str
    repeat: int
    span_hz: float
    points: int
    done_seen: bool
    peak_freq_hz: float
    peak_dbm: float
    marker_freq_hz: float
    marker_dbm: float
    amp_min_dbm: float
    amp_mean_dbm: float
    amp_median_dbm: float
    floor_threshold_count: int
    min_value_count: int
    most_common_floor_dbm: float
    most_common_floor_count: int
    csv_path: Path
    status_before: str
    status_after: str
    profile_before: str
    profile_after: str
    note: str


def firmware_floor_dbm(epsilon: float, full_scale_complex_power: float, adc_full_scale_dbm: float) -> float:
    return 10.0 * math.log10(epsilon / full_scale_complex_power) + adc_full_scale_dbm


def collect_descriptions(
    ser: serial.Serial,
    name: str,
    cmd: int,
    payload: bytes = b"",
    wait_s: float = 0.8,
) -> list[str]:
    frames = proto.send_command(ser, name, cmd, payload, wait_s=wait_s, print_frames=False)
    if not frames:
        return [f"[{name}] no response"]
    return [
        f"[{name}] {proto.describe_frame(rx_cmd, rx_payload, index)}"
        for index, (rx_cmd, rx_payload) in enumerate(frames, start=1)
    ]


def stream_spectrum_quiet(
    ser: serial.Serial,
    point_count: int,
    timeout_s: float,
) -> tuple[list[proto.SpectrumPoint], list[str]]:
    ser.reset_input_buffer()
    ser.write(proto.build_frame(proto.CMD_GET_SPECTRUM, struct.pack("<H", point_count & 0xFFFF)))
    ser.flush()

    points: list[proto.SpectrumPoint] = []
    events: list[str] = []
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
            for frame in proto.extract_frames(rx_buffer):
                frame_index += 1
                cmd, payload = proto.parse_frame(frame)
                if cmd == proto.CMD_SPECTRUM_DATA:
                    parsed = proto.parse_spectrum_payload(payload, frame_index)
                    if parsed:
                        points.extend(parsed)
                        last_data_at = time.time()
                        saw_done = parsed[-1].done
                else:
                    events.append(f"[GET_SPECTRUM] {proto.describe_frame(cmd, payload, frame_index)}")
                if saw_done:
                    return points, events
        else:
            if points and (time.time() - last_data_at) > 2.0:
                events.append("[GET_SPECTRUM] idle for 2s after spectrum data, stop reading")
                break
            time.sleep(0.01)

    return points, events


def write_points_csv(path: Path, points: list[proto.SpectrumPoint]) -> None:
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


def first_matching_line(lines: list[str], token: str) -> str:
    for line in lines:
        if token in line:
            return line
    return ""


def configure_device(
    ser: serial.Serial,
    rbw: str,
    rbw_mode: int,
    rbw_hz: float,
    start_hz: float,
    stop_hz: float,
    args: argparse.Namespace,
) -> list[str]:
    events: list[str] = []
    events.extend(collect_descriptions(ser, "STOP_SWEEP", proto.CMD_STOP_SWEEP, wait_s=0.5))
    events.extend(
        collect_descriptions(
            ser,
            "SET_RF_FRONTEND",
            proto.CMD_SET_RF_FRONTEND,
            proto.pack_rf_frontend_payload(args.lna, args.path, args.atten_code),
        )
    )
    events.extend(
        collect_descriptions(
            ser,
            "SET_VGA_GAIN",
            proto.CMD_SET_VGA_GAIN,
            bytes([proto.VGA_CODES[args.vga_db]]),
        )
    )
    events.extend(
        collect_descriptions(
            ser,
            "SET_AMPLITUDE",
            proto.CMD_SET_AMPLITUDE,
            proto.pack_amplitude_payload(args.ref_level_dbm, 0, 0),
        )
    )
    events.extend(
        collect_descriptions(
            ser,
            "SET_FREQ",
            proto.CMD_SET_FREQ,
            proto.pack_frequency_payload(start_hz, stop_hz),
        )
    )
    events.extend(
        collect_descriptions(
            ser,
            "SET_BW",
            proto.CMD_SET_BW,
            proto.pack_bw_payload(rbw_mode, rbw_hz),
        )
    )
    events.extend(
        collect_descriptions(
            ser,
            "SET_SWEEP",
            proto.CMD_SET_SWEEP,
            proto.pack_sweep_payload(args.sweep_speed, 0, args.point_count),
        )
    )
    events.append(
        f"[CONFIG] rbw={rbw} span={start_hz / 1e6:.6f}-{stop_hz / 1e6:.6f} MHz "
        f"front_end=lna:{args.lna},path:{args.path},atten_code:{args.atten_code},vga:{args.vga_db}dB"
    )
    return events


def summarize_run(
    rbw: str,
    repeat: int,
    span_hz: float,
    marker_hz: float,
    points: list[proto.SpectrumPoint],
    floor_dbm: float,
    fixed_tol_db: float,
    csv_path: Path,
    status_before: str,
    status_after: str,
    profile_before: str,
    profile_after: str,
) -> RunSummary:
    if not points:
        return RunSummary(
            rbw=rbw,
            repeat=repeat,
            span_hz=span_hz,
            points=0,
            done_seen=False,
            peak_freq_hz=0.0,
            peak_dbm=float("nan"),
            marker_freq_hz=0.0,
            marker_dbm=float("nan"),
            amp_min_dbm=float("nan"),
            amp_mean_dbm=float("nan"),
            amp_median_dbm=float("nan"),
            floor_threshold_count=0,
            min_value_count=0,
            most_common_floor_dbm=float("nan"),
            most_common_floor_count=0,
            csv_path=csv_path,
            status_before=status_before,
            status_after=status_after,
            profile_before=profile_before,
            profile_after=profile_after,
            note="no_points",
        )

    amps = [point.amp_dbm for point in points if math.isfinite(point.amp_dbm)]
    peak = max(points, key=lambda point: point.amp_dbm)
    marker = proto.nearest_point(points, marker_hz)
    amp_min = min(amps)
    floor_threshold_count = sum(1 for point in points if point.amp_dbm <= floor_dbm)
    min_value_count = sum(1 for point in points if abs(point.amp_dbm - amp_min) <= fixed_tol_db)
    rounded_floor_values = Counter(round(point.amp_dbm, 2) for point in points if point.amp_dbm <= floor_dbm)
    if rounded_floor_values:
        most_common_floor_dbm, most_common_floor_count = rounded_floor_values.most_common(1)[0]
    else:
        most_common_floor_dbm, most_common_floor_count = float("nan"), 0

    floor_ratio = floor_threshold_count / len(points)
    min_ratio = min_value_count / len(points)
    if floor_ratio >= 0.6:
        note = "floor_clamp_dominant"
    elif min_ratio >= 0.4:
        note = "fixed_min_dominant"
    elif floor_threshold_count > 0:
        note = "floor_clamp_present"
    else:
        note = "no_floor_clamp"

    return RunSummary(
        rbw=rbw,
        repeat=repeat,
        span_hz=span_hz,
        points=len(points),
        done_seen=any(point.done for point in points),
        peak_freq_hz=float(peak.freq_hz),
        peak_dbm=peak.amp_dbm,
        marker_freq_hz=float(marker.freq_hz),
        marker_dbm=marker.amp_dbm,
        amp_min_dbm=amp_min,
        amp_mean_dbm=statistics.fmean(amps),
        amp_median_dbm=statistics.median(amps),
        floor_threshold_count=floor_threshold_count,
        min_value_count=min_value_count,
        most_common_floor_dbm=most_common_floor_dbm,
        most_common_floor_count=most_common_floor_count,
        csv_path=csv_path,
        status_before=status_before,
        status_after=status_after,
        profile_before=profile_before,
        profile_after=profile_after,
        note=note,
    )


def write_summary_csv(path: Path, summaries: list[RunSummary]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow([
            "rbw",
            "repeat",
            "span_hz",
            "points",
            "done_seen",
            "peak_mhz",
            "peak_dbm",
            "marker_mhz",
            "marker_dbm",
            "amp_min_dbm",
            "amp_mean_dbm",
            "amp_median_dbm",
            "floor_threshold_count",
            "floor_threshold_ratio",
            "min_value_count",
            "min_value_ratio",
            "most_common_floor_dbm",
            "most_common_floor_count",
            "note",
            "csv_path",
        ])
        for item in summaries:
            floor_ratio = item.floor_threshold_count / item.points if item.points else 0.0
            min_ratio = item.min_value_count / item.points if item.points else 0.0
            writer.writerow([
                item.rbw,
                item.repeat,
                f"{item.span_hz:.3f}",
                item.points,
                int(item.done_seen),
                f"{item.peak_freq_hz / 1e6:.6f}" if item.points else "",
                f"{item.peak_dbm:.3f}" if item.points else "",
                f"{item.marker_freq_hz / 1e6:.6f}" if item.points else "",
                f"{item.marker_dbm:.3f}" if item.points else "",
                f"{item.amp_min_dbm:.3f}" if item.points else "",
                f"{item.amp_mean_dbm:.3f}" if item.points else "",
                f"{item.amp_median_dbm:.3f}" if item.points else "",
                item.floor_threshold_count,
                f"{floor_ratio:.3f}",
                item.min_value_count,
                f"{min_ratio:.3f}",
                f"{item.most_common_floor_dbm:.2f}" if math.isfinite(item.most_common_floor_dbm) else "",
                item.most_common_floor_count,
                item.note,
                str(item.csv_path),
            ])


def write_summary_md(
    path: Path,
    args: argparse.Namespace,
    summaries: list[RunSummary],
    expected_floor_dbm: float,
) -> None:
    lines = [
        "# RBW floor clamp diagnosis",
        "",
        f"- input_rf_hz: `{args.rf_input_hz:.0f}`",
        f"- target_if_hz: `{args.target_if_hz:.0f}`",
        f"- frontend: `lna={args.lna}, path={args.path}, atten_code={args.atten_code}, vga={args.vga_db} dB`",
        f"- floor_threshold_dbm: `{args.floor_dbm:.2f}`",
        f"- expected_firmware_eps_floor_dbm: `{expected_floor_dbm:.2f}`",
        "",
        "| RBW | repeat | points | peak MHz | peak dBm | marker dBm | min dBm | floor <= threshold | fixed min | common floor | note |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |",
    ]
    for item in summaries:
        floor_ratio = item.floor_threshold_count * 100.0 / item.points if item.points else 0.0
        min_ratio = item.min_value_count * 100.0 / item.points if item.points else 0.0
        common_floor = (
            f"{item.most_common_floor_dbm:.2f} x{item.most_common_floor_count}"
            if math.isfinite(item.most_common_floor_dbm)
            else ""
        )
        lines.append(
            f"| {item.rbw} | {item.repeat} | {item.points} | "
            f"{item.peak_freq_hz / 1e6:.6f} | {item.peak_dbm:.2f} | {item.marker_dbm:.2f} | "
            f"{item.amp_min_dbm:.2f} | {item.floor_threshold_count}/{item.points} ({floor_ratio:.1f}%) | "
            f"{item.min_value_count}/{item.points} ({min_ratio:.1f}%) | {common_floor} | {item.note} |"
        )
    lines.extend([
        "",
        "## Interpretation",
        "",
        "- If `common floor` is near `expected_firmware_eps_floor_dbm`, the fixed value is generated by the firmware power clamp before Flutter.",
        "- If the carrier peak is reasonable but most other points are clamped, the RF path is working and the visible flat noise floor is a dynamic-range/floor-clamp issue.",
        "- If both carrier and floor are low or no points return, check RF path, LO lock, DMA status, and serial ownership before changing display scaling.",
        "",
    ])
    path.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Measure fixed floor-clamp ratio across RBW modes through the PuSuSA serial protocol."
    )
    parser.add_argument("--port", default="COM7")
    parser.add_argument("--baud", type=int, default=921600)
    parser.add_argument("--rf-input-hz", type=float, default=1_000_000_000.0)
    parser.add_argument("--target-if-hz", type=float, default=40_000_000.0)
    parser.add_argument("--nominal-if-hz", type=float, default=proto.NOMINAL_IF_HZ)
    parser.add_argument("--rbws", nargs="+", choices=sorted(proto.RBW_MODES.keys()), default=DEFAULT_RBWS)
    parser.add_argument("--repeats", type=int, default=1)
    parser.add_argument("--span-rbw-multiple", type=float, default=20.0)
    parser.add_argument("--min-span-hz", type=float, default=20_000.0)
    parser.add_argument("--point-count", type=int, default=512)
    parser.add_argument("--timeout-s", type=float, default=45.0)
    parser.add_argument("--sweep-speed", type=float, default=1.0)
    parser.add_argument("--ref-level-dbm", type=float, default=-20.0)
    parser.add_argument("--lna", choices=sorted(proto.LNA_MODES.keys()), default="bypass")
    parser.add_argument("--path", choices=sorted(proto.PATH_MODES.keys()), default="mixer")
    parser.add_argument("--atten-code", type=int, default=0)
    parser.add_argument("--vga-db", choices=sorted(proto.VGA_CODES.keys(), key=lambda value: float(value)), default="0")
    parser.add_argument("--floor-dbm", type=float, default=-105.0)
    parser.add_argument("--fixed-tol-db", type=float, default=0.02)
    parser.add_argument("--epsilon", type=float, default=1.0e-12)
    parser.add_argument("--full-scale-complex-power", type=float, default=0.25)
    parser.add_argument("--adc-full-scale-dbm", type=float, default=8.02)
    parser.add_argument("--out-dir", type=Path, default=None)
    args = parser.parse_args()

    if args.repeats < 1:
        print("--repeats must be >= 1")
        return 2
    if args.span_rbw_multiple <= 0:
        print("--span-rbw-multiple must be > 0")
        return 2

    if_offset_hz = args.target_if_hz - args.nominal_if_hz
    center_hz = args.rf_input_hz - if_offset_hz
    marker_hz = center_hz
    expected_floor_dbm = firmware_floor_dbm(
        args.epsilon,
        args.full_scale_complex_power,
        args.adc_full_scale_dbm,
    )

    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    out_dir = args.out_dir or Path("docs") / f"rbw_floor_clamp_diag_{stamp}"
    out_dir.mkdir(parents=True, exist_ok=True)
    raw_log_path = out_dir / "raw_events.txt"
    summary_csv_path = out_dir / "summary.csv"
    summary_md_path = out_dir / "summary.md"

    print(
        f"Floor clamp diagnosis: port={args.port} rbws={','.join(args.rbws)} repeats={args.repeats} "
        f"expected_eps_floor={expected_floor_dbm:.2f} dBm out={out_dir.resolve()}"
    )

    summaries: list[RunSummary] = []
    raw_events: list[str] = []

    try:
        with serial.Serial(args.port, args.baud, timeout=0.05) as ser:
            for rbw in args.rbws:
                rbw_mode, rbw_hz = proto.RBW_MODES[rbw]
                span_hz = max(args.min_span_hz, args.span_rbw_multiple * rbw_hz)
                start_hz = center_hz - span_hz / 2.0
                stop_hz = center_hz + span_hz / 2.0
                for repeat in range(1, args.repeats + 1):
                    print(f"[{rbw} repeat {repeat}] span={span_hz / 1e3:.1f} kHz")
                    raw_events.extend(configure_device(ser, rbw, rbw_mode, rbw_hz, start_hz, stop_hz, args))
                    time.sleep(0.05)

                    before_status_lines = collect_descriptions(ser, "GET_STATUS_BEFORE", proto.CMD_GET_STATUS)
                    before_profile_lines = collect_descriptions(ser, "GET_PROFILE_BEFORE", proto.CMD_GET_PROFILE)
                    raw_events.extend(before_status_lines)
                    raw_events.extend(before_profile_lines)

                    points, stream_events = stream_spectrum_quiet(ser, args.point_count, args.timeout_s)
                    raw_events.extend(stream_events)

                    after_status_lines = collect_descriptions(ser, "GET_STATUS_AFTER", proto.CMD_GET_STATUS)
                    after_profile_lines = collect_descriptions(ser, "GET_PROFILE_AFTER", proto.CMD_GET_PROFILE)
                    raw_events.extend(after_status_lines)
                    raw_events.extend(after_profile_lines)

                    csv_path = out_dir / f"{rbw}_repeat{repeat}.csv"
                    write_points_csv(csv_path, points)
                    summary = summarize_run(
                        rbw=rbw,
                        repeat=repeat,
                        span_hz=span_hz,
                        marker_hz=marker_hz,
                        points=points,
                        floor_dbm=args.floor_dbm,
                        fixed_tol_db=args.fixed_tol_db,
                        csv_path=csv_path,
                        status_before=first_matching_line(before_status_lines, "STATUS"),
                        status_after=first_matching_line(after_status_lines, "STATUS"),
                        profile_before=first_matching_line(before_profile_lines, "PROFILE"),
                        profile_after=first_matching_line(after_profile_lines, "PROFILE"),
                    )
                    summaries.append(summary)
                    floor_ratio = summary.floor_threshold_count * 100.0 / summary.points if summary.points else 0.0
                    print(
                        f"  points={summary.points} peak={summary.peak_freq_hz / 1e6:.6f}MHz "
                        f"{summary.peak_dbm:.2f}dBm marker={summary.marker_dbm:.2f}dBm "
                        f"min={summary.amp_min_dbm:.2f}dBm floor={floor_ratio:.1f}% note={summary.note}"
                    )

    except serial.SerialException as exc:
        print(f"Serial error: {exc}")
        print("Hint: close Flutter/other serial tools if the port is already open.")
        try:
            if out_dir.exists() and not any(out_dir.iterdir()):
                out_dir.rmdir()
        except OSError:
            pass
        return 1

    raw_log_path.write_text("\n".join(raw_events) + "\n", encoding="utf-8")
    write_summary_csv(summary_csv_path, summaries)
    write_summary_md(summary_md_path, args, summaries, expected_floor_dbm)

    print("")
    print(f"summary_csv={summary_csv_path.resolve()}")
    print(f"summary_md={summary_md_path.resolve()}")
    print(f"raw_events={raw_log_path.resolve()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
