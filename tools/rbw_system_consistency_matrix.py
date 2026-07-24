import argparse
import csv
import re
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path


DEFAULT_RBWS = ["1m", "300k", "100k", "30k", "10k", "1k"]


def parse_args():
    parser = argparse.ArgumentParser(
        description="Run serial RBW consistency tests and summarize peak/amplitude/DMA health."
    )
    parser.add_argument("--port", default="COM7")
    parser.add_argument("--baud", type=int, default=921600)
    parser.add_argument("--script", default=r"C:\learning\pusu_V2\tools\serial_300k_rbw_diagnose.py")
    parser.add_argument("--python", default=r"C:\software\python\python.exe")
    parser.add_argument("--rbws", nargs="+", default=DEFAULT_RBWS)
    parser.add_argument("--repeats", type=int, default=1)
    parser.add_argument("--start-hz", type=int, default=1_000_000_000)
    parser.add_argument("--stop-hz", type=int, default=1_000_000_000)
    parser.add_argument("--marker-hz", type=int, default=1_000_000_000)
    parser.add_argument("--timeout-s", type=int, default=80)
    parser.add_argument("--reference-dbm", type=float, default=-10.0)
    parser.add_argument("--out-dir", default=None)
    return parser.parse_args()


def last_match(pattern, text):
    matches = list(re.finditer(pattern, text, re.MULTILINE))
    return matches[-1] if matches else None


def parse_output(rbw, repeat_index, reference_dbm, text, return_code):
    row = {
        "rbw": rbw,
        "repeat": repeat_index,
        "return_code": return_code,
        "ok": 0,
        "points_received": "",
        "peak_hz": "",
        "peak_dbm": "",
        "marker_hz": "",
        "marker_dbm": "",
        "error_vs_ref_db": "",
        "suggested_correction_db": "",
        "sweep_err": "",
        "sweep_frame_ready": "",
        "sweep_dma_err": "",
        "sweep_dmasr": "",
        "sweep_last_irq": "",
        "sweep_accum": "",
        "sweep_target": "",
        "pl_mode": "",
        "pl_fs_hz": "",
        "pl_decim": "",
        "pl_drop": "",
        "pl_err": "",
        "capture_csv": "",
    }

    summary = last_match(r"points_received=(\d+).*?done_seen=(\w+)", text)
    if summary:
        row["points_received"] = summary.group(1)

    peak = last_match(r"peak=([0-9.]+)\s+MHz\s+([-0-9.]+)\s+dBm\s+index=(\d+)", text)
    if peak:
        peak_hz = float(peak.group(1)) * 1e6
        peak_dbm = float(peak.group(2))
        row["peak_hz"] = f"{peak_hz:.0f}"
        row["peak_dbm"] = f"{peak_dbm:.2f}"
        row["error_vs_ref_db"] = f"{peak_dbm - reference_dbm:.2f}"
        row["suggested_correction_db"] = f"{reference_dbm - peak_dbm:.2f}"

    marker = last_match(
        r"marker_nearest=([0-9.]+)\s+MHz\s+([-0-9.]+)\s+dBm\s+delta=([+-]?\d+)\s+Hz",
        text,
    )
    if marker:
        row["marker_hz"] = f"{float(marker.group(1)) * 1e6:.0f}"
        row["marker_dbm"] = f"{float(marker.group(2)):.2f}"

    sweep = last_match(
        r"SWEEP state=\d+\s+err=(\d+)\s+frame_ready=(\d+)\s+dma_err=(\d+).*?"
        r"dmasr=(0x[0-9A-Fa-f]+)\s+last_irq=(0x[0-9A-Fa-f]+).*?"
        r"accum=(\d+)\s+target=(\d+)",
        text,
    )
    if sweep:
        row["sweep_err"] = sweep.group(1)
        row["sweep_frame_ready"] = sweep.group(2)
        row["sweep_dma_err"] = sweep.group(3)
        row["sweep_dmasr"] = sweep.group(4)
        row["sweep_last_irq"] = sweep.group(5)
        row["sweep_accum"] = sweep.group(6)
        row["sweep_target"] = sweep.group(7)

    pl = last_match(
        r"PL avail=1\s+mode=(\d+).*?fs=(\d+)\s+decim=(\d+).*?drop=(\d+)\s+err=(\d+)",
        text,
    )
    if pl:
        row["pl_mode"] = pl.group(1)
        row["pl_fs_hz"] = pl.group(2)
        row["pl_decim"] = pl.group(3)
        row["pl_drop"] = pl.group(4)
        row["pl_err"] = pl.group(5)

    capture = last_match(r"CSV saved:\s+(.+)", text)
    if capture:
        row["capture_csv"] = capture.group(1).strip()

    row["ok"] = int(
        return_code == 0
        and row["points_received"] not in ("", "0")
        and row["sweep_err"] == "0"
        and row["sweep_frame_ready"] == "1"
        and row["sweep_dma_err"] == "0"
        and row["sweep_last_irq"] == "0x00001000"
        and row["peak_dbm"] != ""
    )
    return row


def write_summary_md(path, rows, args):
    groups = {}
    for row in rows:
        groups.setdefault(row["rbw"], []).append(row)

    lines = []
    lines.append("# RBW System Consistency Test")
    lines.append("")
    lines.append(f"- Created: {datetime.now().isoformat(timespec='seconds')}")
    lines.append(f"- Reference power: {args.reference_dbm:.2f} dBm")
    lines.append(f"- Frequency: {args.marker_hz} Hz")
    lines.append(f"- Repeats: {args.repeats}")
    lines.append("")
    lines.append("| RBW | OK/Total | Mean peak dBm | Mean error dB | Suggested correction dB | Notes |")
    lines.append("|---|---:|---:|---:|---:|---|")
    for rbw in args.rbws:
        rbw_rows = groups.get(rbw, [])
        ok_count = sum(int(r["ok"]) for r in rbw_rows)
        peaks = [float(r["peak_dbm"]) for r in rbw_rows if r["peak_dbm"]]
        if peaks:
            mean_peak = sum(peaks) / len(peaks)
            mean_error = mean_peak - args.reference_dbm
            correction = args.reference_dbm - mean_peak
            mean_peak_s = f"{mean_peak:.2f}"
            mean_error_s = f"{mean_error:+.2f}"
            correction_s = f"{correction:+.2f}"
        else:
            mean_peak_s = ""
            mean_error_s = ""
            correction_s = ""
        notes = []
        if ok_count != len(rbw_rows):
            notes.append("has failed runs")
        bad_dma = [r for r in rbw_rows if r["sweep_dma_err"] not in ("", "0")]
        if bad_dma:
            notes.append("dma_err observed")
        lines.append(
            f"| {rbw} | {ok_count}/{len(rbw_rows)} | {mean_peak_s} | "
            f"{mean_error_s} | {correction_s} | {', '.join(notes)} |"
        )
    lines.append("")
    lines.append("## Raw Captures")
    lines.append("")
    for row in rows:
        lines.append(
            f"- {row['rbw']} repeat {row['repeat']}: ok={row['ok']}, "
            f"peak={row['peak_dbm']} dBm, csv={row['capture_csv']}"
        )
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main():
    args = parse_args()
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    out_dir = Path(args.out_dir) if args.out_dir else Path(r"C:\learning\pusu_V2\docs") / f"rbw_system_consistency_{timestamp}"
    out_dir.mkdir(parents=True, exist_ok=True)

    rows = []
    for repeat in range(1, args.repeats + 1):
        for rbw in args.rbws:
            cmd = [
                args.python,
                args.script,
                "--port",
                args.port,
                "--baud",
                str(args.baud),
                "--rbw",
                rbw,
                "--start-hz",
                str(args.start_hz),
                "--stop-hz",
                str(args.stop_hz),
                "--marker-hz",
                str(args.marker_hz),
                "--timeout-s",
                str(args.timeout_s),
            ]
            print(f"RUN rbw={rbw} repeat={repeat}: {' '.join(cmd)}", flush=True)
            completed = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=args.timeout_s + 30,
            )
            log_path = out_dir / f"{timestamp}_{rbw}_rep{repeat}.log"
            log_path.write_text(completed.stdout + completed.stderr, encoding="utf-8")
            row = parse_output(rbw, repeat, args.reference_dbm, completed.stdout + completed.stderr, completed.returncode)
            rows.append(row)
            print(
                f"RESULT rbw={rbw} repeat={repeat} ok={row['ok']} "
                f"peak={row['peak_dbm']} dBm sweep_err={row['sweep_err']} "
                f"dma_err={row['sweep_dma_err']}",
                flush=True,
            )
            time.sleep(0.5)

    csv_path = out_dir / "rbw_system_consistency_results.csv"
    fieldnames = list(rows[0].keys()) if rows else []
    with csv_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    md_path = out_dir / "rbw_system_consistency_summary.md"
    write_summary_md(md_path, rows, args)
    print(f"CSV: {csv_path}")
    print(f"SUMMARY: {md_path}")


if __name__ == "__main__":
    sys.exit(main())
