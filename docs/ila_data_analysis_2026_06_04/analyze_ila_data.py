#!/usr/bin/env python3
"""Analyze Vivado ILA-exported ADC captures.

The script reads files from docs/ila_data by default, writes plots and a
Markdown report into this directory, and does not modify the original captures.
"""

from __future__ import annotations

import argparse
import csv
import math
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import matplotlib.pyplot as plt
import numpy as np


DEFAULT_FS_HZ = 130_000_000.0
ADC_NAME_HINTS = ("adc_data", "adc", "ltc2208")
STREAM_NAME_HINTS = ("tdata", "m_axis", "s_axis")
VALID_NAME_HINTS = ("tvalid", "valid")
LAST_NAME_HINTS = ("tlast", "last")
CLOCK_NAME_HINTS = ("aclk", "clk", "clock")
OVERFLOW_NAME_HINTS = ("adc_of", "overflow", "_of")


@dataclass
class ColumnStats:
    name: str
    radix: str
    numeric_count: int
    unique_count: int
    minimum: float | None
    maximum: float | None
    mean: float | None
    std: float | None
    score: int


@dataclass
class FileResult:
    path: Path
    detected_type: str
    size_bytes: int
    columns: list[str]
    radixes: list[str]
    data_rows: int
    parsed_rows: int
    column_stats: list[ColumnStats]
    selected_column: str | None
    selected_radix: str | None
    sample_count: int
    bit_width: int | None
    signed: bool | None
    has_tdata: bool
    has_tvalid: bool
    has_tlast: bool
    has_adc_raw: bool
    has_clock: bool
    has_overflow: bool
    tvalid_issues: str
    overflow_issues: str
    filename_condition: str
    sample_rate_hz: float
    bin_spacing_hz: float | None
    mean_before_demean: float | None
    peak_bin_index: int | None
    peak_bin_hz: float | None
    peak_interp_hz: float | None
    peak_relative_db: float | None
    top_peaks: list[tuple[float, float]]
    spectrum_png: str | None
    time_png: str | None
    notes: list[str]


def parse_args() -> argparse.Namespace:
    script_dir = Path(__file__).resolve().parent
    docs_dir = script_dir.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-dir", type=Path, default=docs_dir / "ila_data")
    parser.add_argument("--output-dir", type=Path, default=script_dir)
    parser.add_argument("--sample-rate", type=float, default=DEFAULT_FS_HZ)
    return parser.parse_args()


def parse_number(text: str, radix: str) -> float | None:
    value = text.strip()
    if value == "":
        return None
    radix_upper = radix.strip().upper()
    try:
        if "HEX" in radix_upper:
            cleaned = value.lower().replace("0x", "")
            return float(int(cleaned, 16))
        if value.lower().startswith("0x"):
            return float(int(value, 16))
        return float(value)
    except ValueError:
        return None


def bit_width_from_name(name: str) -> int | None:
    match = re.search(r"\[(\d+)\s*:\s*(\d+)\]", name)
    if not match:
        return None
    hi = int(match.group(1))
    lo = int(match.group(2))
    return abs(hi - lo) + 1


def is_probably_counter(values: np.ndarray) -> bool:
    if values.size < 3:
        return False
    diffs = np.diff(values)
    return bool(np.all(diffs == 1) or np.all(diffs >= 0))


def score_column(name: str, radix: str, values: list[float | None]) -> int:
    lower = name.lower()
    nums = np.array([v for v in values if v is not None], dtype=float)
    score = 0
    if any(hint in lower for hint in ADC_NAME_HINTS):
        score += 12
    if "data" in lower:
        score += 3
    if any(hint in lower for hint in STREAM_NAME_HINTS):
        score += 2
    if "signed" in radix.lower():
        score += 3
    if any(hint in lower for hint in CLOCK_NAME_HINTS):
        score -= 8
    if any(hint in lower for hint in VALID_NAME_HINTS):
        score -= 6
    if any(hint in lower for hint in LAST_NAME_HINTS):
        score -= 6
    if "trigger" in lower:
        score -= 6
    if lower.startswith("sample in"):
        score -= 4
    if nums.size > 0:
        if np.std(nums) > 0:
            score += 2
        if is_probably_counter(nums):
            score -= 7
        if np.unique(nums).size <= 2:
            score -= 4
    return score


def read_vivado_csv(path: Path) -> tuple[list[str], list[str], list[list[str]]]:
    with path.open("r", newline="", encoding="utf-8-sig") as fh:
        rows = list(csv.reader(fh))
    if len(rows) < 2:
        raise ValueError("CSV has fewer than two rows")
    columns = [c.strip() for c in rows[0]]
    radix_row = [c.strip() for c in rows[1]]
    if radix_row and radix_row[0].lower().startswith("radix"):
        radix_row[0] = radix_row[0].split("-", 1)[-1].strip()
    while len(radix_row) < len(columns):
        radix_row.append("")
    return columns, radix_row[: len(columns)], rows[2:]


def infer_filename_condition(path: Path) -> str:
    lower = path.name.lower()
    if "1.0001" in lower or "40.100" in lower or "40_100" in lower:
        return "filename suggests 1.0001 GHz input / expected IF near 40.100 MHz"
    if "1.0000" in lower or "40.000" in lower or "40_000" in lower:
        return "filename suggests 1.0000 GHz input / expected IF near 40.000 MHz"
    return "no RF/IF condition metadata found in filename"


def column_values(rows: list[list[str]], index: int, radix: str) -> list[float | None]:
    out: list[float | None] = []
    for row in rows:
        value = row[index] if index < len(row) else ""
        out.append(parse_number(value, radix))
    return out


def build_column_stats(columns: list[str], radixes: list[str], rows: list[list[str]]) -> list[ColumnStats]:
    stats: list[ColumnStats] = []
    for idx, name in enumerate(columns):
        values = column_values(rows, idx, radixes[idx])
        nums = np.array([v for v in values if v is not None], dtype=float)
        if nums.size:
            minimum = float(np.min(nums))
            maximum = float(np.max(nums))
            mean = float(np.mean(nums))
            std = float(np.std(nums))
            unique_count = int(np.unique(nums).size)
        else:
            minimum = maximum = mean = std = None
            unique_count = 0
        stats.append(
            ColumnStats(
                name=name,
                radix=radixes[idx],
                numeric_count=int(nums.size),
                unique_count=unique_count,
                minimum=minimum,
                maximum=maximum,
                mean=mean,
                std=std,
                score=score_column(name, radixes[idx], values),
            )
        )
    return stats


def selected_adc_column(stats: list[ColumnStats]) -> ColumnStats | None:
    usable = [s for s in stats if s.numeric_count > 0 and s.std is not None and s.std > 0]
    if not usable:
        return None
    return max(usable, key=lambda s: (s.score, s.numeric_count, s.std or 0.0))


def parabolic_interpolated_peak(freqs: np.ndarray, magnitude: np.ndarray, idx: int) -> float:
    if idx <= 0 or idx >= magnitude.size - 1:
        return float(freqs[idx])
    # Parabolic interpolation on log magnitude is a stable sub-bin estimate for a Hann-windowed tone.
    log_mag = np.log(np.maximum(magnitude[[idx - 1, idx, idx + 1]], 1e-300))
    denom = log_mag[0] - 2.0 * log_mag[1] + log_mag[2]
    if abs(denom) < 1e-30:
        return float(freqs[idx])
    delta = 0.5 * (log_mag[0] - log_mag[2]) / denom
    bin_spacing = freqs[1] - freqs[0]
    return float(freqs[idx] + delta * bin_spacing)


def find_top_peaks(freqs: np.ndarray, db: np.ndarray, count: int = 5) -> list[tuple[float, float]]:
    if db.size <= 2:
        return []
    candidates: list[int] = []
    for i in range(1, db.size - 1):
        if db[i] >= db[i - 1] and db[i] >= db[i + 1]:
            candidates.append(i)
    if not candidates:
        candidates = list(range(1, db.size))
    candidates.sort(key=lambda i: db[i], reverse=True)
    return [(float(freqs[i]), float(db[i])) for i in candidates[:count]]


def plot_time(samples: np.ndarray, fs_hz: float, title: str, out_path: Path) -> None:
    time_us = np.arange(samples.size) / fs_hz * 1e6
    plt.figure(figsize=(9.5, 4.8))
    plt.plot(time_us, samples, linewidth=1.0)
    plt.xlabel("Time (us)")
    plt.ylabel("ADC code")
    plt.title(title)
    plt.grid(True, alpha=0.3)
    plt.tight_layout()
    plt.savefig(out_path, dpi=160)
    plt.close()


def plot_spectrum(freqs: np.ndarray, db: np.ndarray, peak_hz: float, title: str, out_path: Path) -> None:
    plt.figure(figsize=(9.5, 5.2))
    plt.plot(freqs / 1e6, db, linewidth=1.0)
    plt.axvline(peak_hz / 1e6, color="tab:red", linestyle="--", linewidth=1.0, label=f"peak {peak_hz / 1e6:.6f} MHz")
    plt.xlim(0, min(65.0, float(freqs[-1] / 1e6)))
    plt.xlabel("Frequency (MHz)")
    plt.ylabel("Relative magnitude (dB)")
    plt.title(title)
    plt.grid(True, alpha=0.3)
    plt.legend(loc="best")
    plt.tight_layout()
    plt.savefig(out_path, dpi=160)
    plt.close()


def check_tvalid(columns: list[str], radixes: list[str], rows: list[list[str]]) -> str:
    matches = [i for i, c in enumerate(columns) if any(h in c.lower() for h in VALID_NAME_HINTS)]
    if not matches:
        return "no tvalid/valid field present"
    notes = []
    for idx in matches:
        nums = np.array([v for v in column_values(rows, idx, radixes[idx]) if v is not None], dtype=float)
        if nums.size == 0:
            notes.append(f"{columns[idx]} not numeric")
        elif np.all(nums != 0):
            notes.append(f"{columns[idx]} always asserted")
        else:
            gaps = int(np.sum(nums == 0))
            notes.append(f"{columns[idx]} has {gaps} low/deasserted samples")
    return "; ".join(notes)


def check_overflow(columns: list[str], radixes: list[str], rows: list[list[str]]) -> str:
    matches = [i for i, c in enumerate(columns) if any(h in c.lower() for h in OVERFLOW_NAME_HINTS)]
    if not matches:
        return "no overflow field present"
    notes = []
    for idx in matches:
        nums = np.array([v for v in column_values(rows, idx, radixes[idx]) if v is not None], dtype=float)
        if nums.size == 0:
            notes.append(f"{columns[idx]} not numeric")
        elif np.all(nums == 0):
            notes.append(f"{columns[idx]} never asserted")
        else:
            notes.append(f"{columns[idx]} asserted in {int(np.sum(nums != 0))} samples")
    return "; ".join(notes)


def analyze_file(path: Path, output_dir: Path, fs_hz: float) -> FileResult:
    suffix = path.suffix.lower()
    notes: list[str] = []
    if suffix != ".csv":
        return FileResult(
            path=path,
            detected_type=f"unsupported/non-CSV ({suffix or 'no extension'})",
            size_bytes=path.stat().st_size,
            columns=[],
            radixes=[],
            data_rows=0,
            parsed_rows=0,
            column_stats=[],
            selected_column=None,
            selected_radix=None,
            sample_count=0,
            bit_width=None,
            signed=None,
            has_tdata=False,
            has_tvalid=False,
            has_tlast=False,
            has_adc_raw=False,
            has_clock=False,
            has_overflow=False,
            tvalid_issues="not parsed",
            overflow_issues="not parsed",
            filename_condition=infer_filename_condition(path),
            sample_rate_hz=fs_hz,
            bin_spacing_hz=None,
            mean_before_demean=None,
            peak_bin_index=None,
            peak_bin_hz=None,
            peak_interp_hz=None,
            peak_relative_db=None,
            top_peaks=[],
            spectrum_png=None,
            time_png=None,
            notes=["Only CSV/Vivado ILA-style exports are parsed by this script."],
        )

    columns, radixes, rows = read_vivado_csv(path)
    stats = build_column_stats(columns, radixes, rows)
    chosen = selected_adc_column(stats)
    lower_cols = [c.lower() for c in columns]
    has_tdata = any("tdata" in c for c in lower_cols)
    has_tvalid = any("tvalid" in c or "valid" in c for c in lower_cols)
    has_tlast = any("tlast" in c or "last" in c for c in lower_cols)
    has_adc_raw = any("adc" in c for c in lower_cols)
    has_clock = any(any(h in c for h in CLOCK_NAME_HINTS) for c in lower_cols)
    has_overflow = any(any(h in c for h in OVERFLOW_NAME_HINTS) for c in lower_cols)

    if chosen is None:
        notes.append("No varying numeric sample column could be selected.")
        samples = np.array([], dtype=float)
        selected_radix = None
    else:
        idx = columns.index(chosen.name)
        samples = np.array([v for v in column_values(rows, idx, radixes[idx]) if v is not None], dtype=float)
        selected_radix = radixes[idx]

    bit_width = bit_width_from_name(chosen.name) if chosen else None
    signed = ("signed" in (selected_radix or "").lower()) if chosen else None

    peak_bin_index = None
    peak_bin_hz = None
    peak_interp_hz = None
    peak_relative_db = None
    top_peaks: list[tuple[float, float]] = []
    spectrum_png = None
    time_png = None
    mean_before_demean = None
    bin_spacing = None

    if samples.size >= 8:
        mean_before_demean = float(np.mean(samples))
        centered = samples - mean_before_demean
        window = np.hanning(samples.size)
        windowed = centered * window
        spectrum = np.fft.rfft(windowed)
        freqs = np.fft.rfftfreq(samples.size, d=1.0 / fs_hz)
        magnitude = np.abs(spectrum)
        magnitude[0] = 0.0
        ref = np.sum(window) / 2.0 if np.sum(window) > 0 else 1.0
        db = 20.0 * np.log10(np.maximum(magnitude / ref, 1e-15))
        peak_bin_index = int(np.argmax(magnitude))
        peak_bin_hz = float(freqs[peak_bin_index])
        peak_interp_hz = parabolic_interpolated_peak(freqs, magnitude, peak_bin_index)
        peak_relative_db = float(db[peak_bin_index])
        top_peaks = find_top_peaks(freqs, db)
        bin_spacing = float(fs_hz / samples.size)

        stem = path.stem
        spectrum_png = f"{stem}_spectrum.png"
        time_png = f"{stem}_time.png"
        plot_spectrum(freqs, db, peak_interp_hz, f"{path.name} Hann-window FFT", output_dir / spectrum_png)
        plot_time(samples, fs_hz, f"{path.name} ADC samples", output_dir / time_png)
    elif samples.size:
        notes.append("Too few samples for a useful FFT.")

    return FileResult(
        path=path,
        detected_type="CSV / Vivado ILA-style table",
        size_bytes=path.stat().st_size,
        columns=columns,
        radixes=radixes,
        data_rows=len(rows),
        parsed_rows=len(rows),
        column_stats=stats,
        selected_column=chosen.name if chosen else None,
        selected_radix=selected_radix,
        sample_count=int(samples.size),
        bit_width=bit_width,
        signed=signed,
        has_tdata=has_tdata,
        has_tvalid=has_tvalid,
        has_tlast=has_tlast,
        has_adc_raw=has_adc_raw,
        has_clock=has_clock,
        has_overflow=has_overflow,
        tvalid_issues=check_tvalid(columns, radixes, rows),
        overflow_issues=check_overflow(columns, radixes, rows),
        filename_condition=infer_filename_condition(path),
        sample_rate_hz=fs_hz,
        bin_spacing_hz=bin_spacing,
        mean_before_demean=mean_before_demean,
        peak_bin_index=peak_bin_index,
        peak_bin_hz=peak_bin_hz,
        peak_interp_hz=peak_interp_hz,
        peak_relative_db=peak_relative_db,
        top_peaks=top_peaks,
        spectrum_png=spectrum_png,
        time_png=time_png,
        notes=notes,
    )


def fmt(value: Any, digits: int = 6) -> str:
    if value is None:
        return "n/a"
    if isinstance(value, float):
        if not math.isfinite(value):
            return "n/a"
        return f"{value:.{digits}g}"
    return str(value)


def write_summary_csv(results: list[FileResult], output_dir: Path) -> None:
    out_path = output_dir / "summary.csv"
    with out_path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh)
        writer.writerow(
            [
                "file",
                "type",
                "samples",
                "selected_column",
                "bit_width",
                "signed",
                "sample_rate_hz",
                "bin_spacing_hz",
                "peak_bin_hz",
                "peak_interp_hz",
                "peak_relative_db",
                "has_tdata",
                "has_tvalid",
                "has_tlast",
                "has_adc_raw",
                "tvalid_issues",
                "overflow_issues",
            ]
        )
        for r in results:
            writer.writerow(
                [
                    r.path.name,
                    r.detected_type,
                    r.sample_count,
                    r.selected_column or "",
                    r.bit_width or "",
                    "" if r.signed is None else r.signed,
                    r.sample_rate_hz,
                    r.bin_spacing_hz or "",
                    r.peak_bin_hz or "",
                    r.peak_interp_hz or "",
                    r.peak_relative_db or "",
                    r.has_tdata,
                    r.has_tvalid,
                    r.has_tlast,
                    r.has_adc_raw,
                    r.tvalid_issues,
                    r.overflow_issues,
                ]
            )


def comparison_lines(results: list[FileResult]) -> list[str]:
    lines: list[str] = []
    valid = [r for r in results if r.peak_interp_hz is not None]
    if len(valid) < 2:
        return ["- Fewer than two FFT-capable captures were parsed, so no 40.000/40.100 MHz comparison was made."]

    for r in valid:
        err_40m = (r.peak_interp_hz or 0.0) - 40_000_000.0
        err_401m = (r.peak_interp_hz or 0.0) - 40_100_000.0
        nearest = "40.000 MHz" if abs(err_40m) <= abs(err_401m) else "40.100 MHz"
        lines.append(
            f"- `{r.path.name}`: interpolated peak {r.peak_interp_hz / 1e6:.6f} MHz; "
            f"error vs 40.000 MHz = {err_40m / 1e3:+.3f} kHz, "
            f"vs 40.100 MHz = {err_401m / 1e3:+.3f} kHz. Nearest reference: {nearest}."
        )

    named_0000 = next((r for r in valid if "1.0000" in r.path.name.lower()), None)
    named_0001 = next((r for r in valid if "1.0001" in r.path.name.lower()), None)
    if named_0000 and named_0001 and named_0000.peak_interp_hz and named_0001.peak_interp_hz:
        delta = named_0001.peak_interp_hz - named_0000.peak_interp_hz
        lines.append(
            f"- Filename-paired delta: `{named_0001.path.name}` - `{named_0000.path.name}` = "
            f"{delta / 1e3:.3f} kHz."
        )
        if abs(delta - 100_000.0) <= 10_000.0:
            lines.append(
                "- This is consistent with a +100 kHz offset after sub-bin interpolation, "
                "but the native FFT bin spacing is coarser than 100 kHz."
            )
        else:
            lines.append("- The measured separation is not close enough to +100 kHz to confirm the offset.")
    return lines


def write_report(results: list[FileResult], args: argparse.Namespace) -> None:
    out_path = args.output_dir / "analysis_report.md"
    lines: list[str] = []
    lines.append("# Vivado ILA ADC Data Analysis")
    lines.append("")
    lines.append(f"- Input directory: `{args.input_dir.resolve()}`")
    lines.append(f"- Output directory: `{args.output_dir.resolve()}`")
    lines.append(f"- Assumed ADC sample rate: Fs = {args.sample_rate / 1e6:.3f} MHz")
    lines.append("- Clock note: no embedded sample-rate metadata was found in the parsed CSV files; `m_axis_aclk` is a captured logic probe, not a frequency annotation.")
    lines.append("- Processing: selected the most likely raw ADC numeric column, removed its mean, applied a Hann window, then computed a real-input FFT.")
    lines.append("- Amplitudes are relative FFT magnitudes in dB; the data do not contain amplitude-calibration metadata.")
    lines.append("")
    lines.append("## File Inventory")
    lines.append("")
    for r in results:
        lines.append(f"### {r.path.name}")
        lines.append("")
        lines.append(f"- Detected type: {r.detected_type}")
        lines.append(f"- Size: {r.size_bytes} bytes")
        lines.append(f"- Columns: `{', '.join(r.columns) if r.columns else 'n/a'}`")
        lines.append(f"- Radix row: `{', '.join(r.radixes) if r.radixes else 'n/a'}`")
        lines.append(f"- Parsed sample rows: {r.parsed_rows}")
        lines.append(f"- Filename condition inference: {r.filename_condition}")
        lines.append(f"- Contains tdata/tvalid/tlast: {r.has_tdata}/{r.has_tvalid}/{r.has_tlast}")
        lines.append(f"- Contains ADC raw-looking field: {r.has_adc_raw}")
        lines.append(f"- Selected sample column: `{r.selected_column or 'n/a'}`")
        lines.append(f"- Selected column radix/format: `{r.selected_radix or 'n/a'}`; bit width from name: {r.bit_width or 'n/a'}; signed: {fmt(r.signed)}")
        lines.append(f"- tvalid continuity: {r.tvalid_issues}")
        lines.append(f"- ADC overflow: {r.overflow_issues}")
        lines.append(f"- Mean before de-mean: {fmt(r.mean_before_demean)} ADC codes")
        lines.append("")
        if r.column_stats:
            lines.append("| Column | Radix | Numeric | Unique | Min | Max | Mean | Std | Score |")
            lines.append("|---|---:|---:|---:|---:|---:|---:|---:|---:|")
            for s in r.column_stats:
                lines.append(
                    f"| `{s.name}` | {s.radix} | {s.numeric_count} | {s.unique_count} | "
                    f"{fmt(s.minimum)} | {fmt(s.maximum)} | {fmt(s.mean)} | {fmt(s.std)} | {s.score} |"
                )
            lines.append("")
        if r.notes:
            lines.append("Notes:")
            for note in r.notes:
                lines.append(f"- {note}")
            lines.append("")

    lines.append("## FFT Results")
    lines.append("")
    lines.append("| File | Samples | Bin spacing (Hz) | Peak bin (Hz) | Interpolated peak (Hz) | Peak relative dB | Top peaks Hz:dB |")
    lines.append("|---|---:|---:|---:|---:|---:|---|")
    for r in results:
        top = "<br>".join([f"{freq:.3f}:{db:.2f}" for freq, db in r.top_peaks]) or "n/a"
        lines.append(
            f"| {r.path.name} | {r.sample_count} | {fmt(r.bin_spacing_hz, 9)} | "
            f"{fmt(r.peak_bin_hz, 9)} | {fmt(r.peak_interp_hz, 9)} | {fmt(r.peak_relative_db, 6)} | {top} |"
        )
    lines.append("")
    if results and results[0].bin_spacing_hz:
        lines.append(
            f"With 1024 samples at 130 MHz, the FFT bin spacing is {results[0].bin_spacing_hz:.3f} Hz "
            f"({results[0].bin_spacing_hz / 1e3:.3f} kHz), so a 100 kHz shift is about "
            f"{100_000.0 / results[0].bin_spacing_hz:.3f} bin."
        )
        lines.append("")

    lines.append("## 40.000 MHz vs 40.100 MHz Check")
    lines.append("")
    lines.extend(comparison_lines(results))
    lines.append("")
    lines.append("## Generated Plots")
    lines.append("")
    for r in results:
        if r.spectrum_png:
            lines.append(f"- `{r.path.name}` spectrum: `{r.spectrum_png}`")
        if r.time_png:
            lines.append(f"- `{r.path.name}` time series: `{r.time_png}`")
    lines.append("")
    lines.append("## Data Quality and Uncertainties")
    lines.append("")
    lines.append("- The captures are short: 1024 samples at 130 MHz is about 7.877 us, so native FFT resolution is coarse for proving a 100 kHz separation.")
    lines.append("- The two current CSV files expose `system_i/LTC2208_0_adc_data[15:0]` as a signed 16-bit ADC-looking probe; they do not expose AXI `tdata/tvalid/tlast` handshake probes.")
    lines.append("- The `system_i/LTC2208_0_m_axis_aclk` column is constant in the export and cannot be used to derive sample rate.")
    lines.append("- `system_i/LTC2208_0_adc_of` remains 0 in the parsed files, so no ADC overflow is visible in these captures.")
    lines.append("- The RF condition is inferred from filenames only. If a future export includes ILA metadata, clock constraints, or experiment labels, add it to the report instead of relying on filenames.")
    lines.append("- Sub-bin peak interpolation is useful here, but longer captures or repeated captures would make the 40.000/40.100 MHz confirmation much stronger.")
    lines.append("")
    lines.append("## Reproduce")
    lines.append("")
    lines.append("```powershell")
    lines.append("python docs\\ila_data_analysis_2026_06_04\\analyze_ila_data.py")
    lines.append("```")
    out_path.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    args = parse_args()
    args.input_dir = args.input_dir.resolve()
    args.output_dir = args.output_dir.resolve()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    files = sorted(p for p in args.input_dir.iterdir() if p.is_file())
    results = [analyze_file(path, args.output_dir, args.sample_rate) for path in files]
    write_summary_csv(results, args.output_dir)
    write_report(results, args)
    print(f"Analyzed {len(results)} file(s). Report: {args.output_dir / 'analysis_report.md'}")


if __name__ == "__main__":
    main()
