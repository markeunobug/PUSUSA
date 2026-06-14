#!/usr/bin/env python3
"""Offline validation for the current 10K RBW sweep DSP chain.

Inputs are Vivado ILA CSV files under docs/ila_data. Outputs are written next
to this script. The original captures are never modified.
"""

from __future__ import annotations

import argparse
import csv
import math
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import matplotlib.pyplot as plt
import numpy as np


REPO_ROOT = Path(__file__).resolve().parents[2]
SRC_DIR = REPO_ROOT / "code" / "pusu_20260516" / "vitis" / "pusu_20260516" / "src"
APP_CONFIG = SRC_DIR / "app_config.h"
RBW_COEFFS_C = SRC_DIR / "rbw_filter_coeffs.c"
DEFAULT_ILA_DIR = REPO_ROOT / "docs" / "ila_data"
DEFAULT_OUT_DIR = Path(__file__).resolve().parent
PREFERRED_ADC_COLUMN = "system_i/LTC2208_0_adc_data[15:0]"


@dataclass
class FirmwareConfig:
    fs_hz: float
    ddc_if_hz: float
    fft_size: int
    full_scale_complex_power: float
    adc_input_full_scale_dbm: float
    epsilon: float
    decim_r: int
    decim_taps: int
    decim_cutoff_hz: float
    decim_beta: float
    rbw_10k_fir_taps: int
    rbw_10k_observe_points: int
    rbw_10k_skip_points: int
    accum_buffer_size: int

    @property
    def fs_decimated_hz(self) -> float:
        return self.fs_hz / self.decim_r

    @property
    def accum_target(self) -> int:
        return min(
            self.rbw_10k_observe_points + self.rbw_10k_skip_points + self.rbw_10k_fir_taps,
            self.accum_buffer_size,
        )

    @property
    def post_fir_first_valid(self) -> int:
        return (self.rbw_10k_fir_taps - 1) + self.rbw_10k_skip_points


@dataclass
class IlaCapture:
    path: Path
    samples_i16: np.ndarray
    sample_count: int
    selected_column: str
    mean_code: float
    rms_code: float
    hann_peak_hz: float
    hann_peak_db_code: float
    fitted_freq_hz: float
    fitted_amp_code: float
    fitted_phase_rad: float
    decim_outputs_from_short_record: int
    final_outputs_after_post_fir: int
    direct_power_dbfs: float | None
    direct_unclamped_power_dbfs: float | None
    notes: list[str]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-dir", type=Path, default=DEFAULT_ILA_DIR)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUT_DIR)
    parser.add_argument("--synthetic-samples", type=int, default=400_000)
    return parser.parse_args()


def parse_c_number(text: str) -> float:
    value = text.strip()
    value = re.sub(r"/\*.*?\*/", "", value)
    value = value.split("//", 1)[0].strip()
    value = value.rstrip("fFuUlL")
    if value.startswith("(") and value.endswith(")"):
        value = value[1:-1]
    return float(value)


def read_defines(path: Path) -> dict[str, str]:
    defines: dict[str, str] = {}
    pattern = re.compile(r"^\s*#define\s+([A-Za-z0-9_]+)\s+(.+?)\s*$")
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = pattern.match(line)
        if match:
            defines[match.group(1)] = match.group(2)
    return defines


def define_float(defines: dict[str, str], name: str) -> float:
    return parse_c_number(defines[name])


def define_int(defines: dict[str, str], name: str) -> int:
    return int(round(define_float(defines, name)))


def load_firmware_config() -> FirmwareConfig:
    defines = read_defines(APP_CONFIG)
    return FirmwareConfig(
        fs_hz=define_float(defines, "ADC_SAMPLE_RATE_HZ"),
        ddc_if_hz=define_float(defines, "DDC_IF_HZ"),
        fft_size=define_int(defines, "FFT_SIZE"),
        full_scale_complex_power=define_float(defines, "FULL_SCALE_COMPLEX_POWER"),
        adc_input_full_scale_dbm=define_float(defines, "ADC_INPUT_FULL_SCALE_DBM"),
        epsilon=define_float(defines, "EPSILON"),
        decim_r=define_int(defines, "RBW_10K_FIR_DECIMATOR_R"),
        decim_taps=define_int(defines, "RBW_10K_FIR_DECIMATOR_TAPS"),
        decim_cutoff_hz=define_float(defines, "RBW_10K_FIR_DECIMATOR_CUTOFF_HZ"),
        decim_beta=define_float(defines, "RBW_10K_FIR_DECIMATOR_BETA"),
        rbw_10k_fir_taps=define_int(defines, "RBW_10K_FIR_TAPS"),
        rbw_10k_observe_points=define_int(defines, "RBW_10K_OBSERVE_POINTS"),
        rbw_10k_skip_points=define_int(defines, "RBW_10K_SKIP_POINTS"),
        accum_buffer_size=define_int(defines, "ACCUM_BUFFER_SIZE"),
    )


def load_rbw_10k_coeffs(path: Path = RBW_COEFFS_C) -> np.ndarray:
    text = path.read_text(encoding="utf-8", errors="replace")
    match = re.search(r"rbw_coeffs_10k\s*\[[^\]]+\]\s*=\s*\{(?P<body>.*?)\};", text, re.S)
    if not match:
        raise ValueError(f"Could not find rbw_coeffs_10k in {path}")
    values = []
    for token in match.group("body").replace("\n", " ").split(","):
        cleaned = token.strip().rstrip("fF")
        if cleaned:
            values.append(float(cleaned))
    return np.asarray(values, dtype=np.float64)


def design_10k_decimator_coeffs(cfg: FirmwareConfig) -> np.ndarray:
    n = np.arange(cfg.decim_taps, dtype=np.float64)
    center = 0.5 * (cfg.decim_taps - 1)
    k = n - center
    cutoff_norm = cfg.decim_cutoff_hz / cfg.fs_hz
    h = np.empty_like(k)
    near_zero = np.abs(k) < 1.0e-12
    h[near_zero] = 2.0 * cutoff_norm
    h[~near_zero] = np.sin(2.0 * np.pi * cutoff_norm * k[~near_zero]) / (np.pi * k[~near_zero])
    h *= np.kaiser(cfg.decim_taps, cfg.decim_beta)
    h /= np.sum(h)
    return h


def parse_ila_number(text: str, radix: str) -> int | None:
    value = text.strip()
    if not value:
        return None
    try:
        if "HEX" in radix.upper() or value.lower().startswith("0x"):
            return int(value.lower().replace("0x", ""), 16)
        return int(float(value))
    except ValueError:
        return None


def read_vivado_ila_csv(path: Path) -> tuple[list[str], list[str], list[list[str]]]:
    with path.open("r", newline="", encoding="utf-8-sig") as fh:
        rows = list(csv.reader(fh))
    if len(rows) < 3:
        raise ValueError(f"{path} has too few rows for Vivado ILA CSV")
    columns = [c.strip() for c in rows[0]]
    radixes = [c.strip() for c in rows[1]]
    if radixes and radixes[0].lower().startswith("radix"):
        radixes[0] = radixes[0].split("-", 1)[-1].strip()
    while len(radixes) < len(columns):
        radixes.append("")
    return columns, radixes[: len(columns)], rows[2:]


def select_adc_column(columns: list[str]) -> int:
    if PREFERRED_ADC_COLUMN in columns:
        return columns.index(PREFERRED_ADC_COLUMN)
    scored: list[tuple[int, int]] = []
    for idx, name in enumerate(columns):
        lower = name.lower()
        score = 0
        if "adc_data" in lower:
            score += 100
        if "ltc2208" in lower:
            score += 20
        if "adc" in lower:
            score += 10
        if "data" in lower:
            score += 5
        if any(bad in lower for bad in ("clock", "aclk", "valid", "last", "trigger", "sample in")):
            score -= 50
        scored.append((score, idx))
    scored.sort(reverse=True)
    if not scored or scored[0][0] <= 0:
        raise ValueError("Could not select an ADC data column")
    return scored[0][1]


def expected_freq_from_name(path: Path, cfg: FirmwareConfig) -> float:
    lower = path.name.lower()
    if "1.0001" in lower or "40.100" in lower or "40100" in lower:
        return cfg.ddc_if_hz + 100_000.0
    return cfg.ddc_if_hz


def estimate_hann_peak(samples_code: np.ndarray, fs_hz: float) -> tuple[float, float]:
    centered = samples_code.astype(np.float64) - float(np.mean(samples_code))
    window = np.hanning(samples_code.size)
    spectrum = np.fft.rfft(centered * window)
    freqs = np.fft.rfftfreq(samples_code.size, d=1.0 / fs_hz)
    mag = np.abs(spectrum)
    if mag.size <= 1:
        return math.nan, math.nan
    mag[0] = 0.0
    idx = int(np.argmax(mag))
    peak_hz = float(freqs[idx])
    if 0 < idx < mag.size - 1:
        log_mag = np.log(np.maximum(mag[[idx - 1, idx, idx + 1]], 1e-300))
        denom = log_mag[0] - 2.0 * log_mag[1] + log_mag[2]
        if abs(denom) > 1e-30:
            delta = 0.5 * (log_mag[0] - log_mag[2]) / denom
            peak_hz = float(freqs[idx] + delta * (freqs[1] - freqs[0]))
    ref = np.sum(window) / 2.0 if np.sum(window) > 0 else 1.0
    peak_db = 20.0 * math.log10(max(float(mag[idx]) / ref, 1e-300))
    return peak_hz, peak_db


def fit_tone(samples_code: np.ndarray, fs_hz: float, freq_hz: float) -> tuple[float, float, float]:
    n = np.arange(samples_code.size, dtype=np.float64)
    omega_n = 2.0 * np.pi * freq_hz * n / fs_hz
    design = np.column_stack((np.cos(omega_n), np.sin(omega_n), np.ones(samples_code.size)))
    coeffs, *_ = np.linalg.lstsq(design, samples_code.astype(np.float64), rcond=None)
    cos_coeff, sin_coeff, _dc = coeffs
    amp = float(np.hypot(cos_coeff, sin_coeff))
    phase = float(math.atan2(-sin_coeff, cos_coeff))
    return freq_hz, amp, phase


def load_ila_capture(path: Path, cfg: FirmwareConfig, decim_coeffs: np.ndarray, rbw_coeffs: np.ndarray) -> IlaCapture:
    columns, radixes, rows = read_vivado_ila_csv(path)
    idx = select_adc_column(columns)
    raw_values = [parse_ila_number(row[idx] if idx < len(row) else "", radixes[idx]) for row in rows]
    values = np.asarray([v for v in raw_values if v is not None], dtype=np.int16)
    notes: list[str] = []
    hann_peak_hz, hann_peak_db_code = estimate_hann_peak(values, cfg.fs_hz)
    expected = expected_freq_from_name(path, cfg)
    fit_freq, fit_amp, fit_phase = fit_tone(values.astype(np.float64), cfg.fs_hz, expected)

    mixed = ddc_mix(values.astype(np.float64) / 32768.0, cfg)
    decim = fir_decimate_like_firmware(mixed, decim_coeffs, cfg.decim_r)
    final, direct_power, direct_unclamped_power = apply_post_fir_and_measure(decim, rbw_coeffs, cfg)
    if values.size < cfg.decim_taps:
        notes.append(
            f"Only {values.size} raw samples are present; this is shorter than the "
            f"{cfg.decim_taps}-tap FIR decimator, so all direct decimator outputs are startup transient."
        )
    if final.size == 0:
        notes.append(
            f"Post-RBW FIR needs first_valid={cfg.post_fir_first_valid} decimated samples; "
            f"short record produced only {decim.size}."
        )
    return IlaCapture(
        path=path,
        samples_i16=values,
        sample_count=int(values.size),
        selected_column=columns[idx],
        mean_code=float(np.mean(values)) if values.size else math.nan,
        rms_code=float(np.sqrt(np.mean(values.astype(np.float64) ** 2))) if values.size else math.nan,
        hann_peak_hz=hann_peak_hz,
        hann_peak_db_code=hann_peak_db_code,
        fitted_freq_hz=fit_freq,
        fitted_amp_code=fit_amp,
        fitted_phase_rad=fit_phase,
        decim_outputs_from_short_record=int(decim.size),
        final_outputs_after_post_fir=int(final.size),
        direct_power_dbfs=direct_power,
        direct_unclamped_power_dbfs=direct_unclamped_power,
        notes=notes,
    )


def ddc_mix(samples_norm: np.ndarray, cfg: FirmwareConfig) -> np.ndarray:
    n = np.arange(samples_norm.size, dtype=np.float64)
    phase = 2.0 * np.pi * cfg.ddc_if_hz * n / cfg.fs_hz
    return samples_norm * (np.cos(phase) - 1j * np.sin(phase))


def fir_decimate_like_firmware(x: np.ndarray, coeffs: np.ndarray, r: int) -> np.ndarray:
    if x.size == 0:
        return np.asarray([], dtype=np.complex128)
    output_indices = np.arange(r - 1, x.size, r, dtype=np.int64)
    padded = np.concatenate((np.zeros(coeffs.size - 1, dtype=np.complex128), x.astype(np.complex128)))
    coeffs_reversed = coeffs[::-1]
    out = np.empty(output_indices.size, dtype=np.complex128)
    for out_idx, n in enumerate(output_indices):
        start = int(n)
        out[out_idx] = np.dot(padded[start : start + coeffs.size], coeffs_reversed)
    return out


def apply_post_fir_and_measure(
    decimated: np.ndarray,
    rbw_coeffs: np.ndarray,
    cfg: FirmwareConfig,
) -> tuple[np.ndarray, float | None, float | None]:
    if decimated.size == 0:
        return np.asarray([], dtype=np.complex128), None, None
    filtered = np.convolve(decimated, rbw_coeffs, mode="full")[: decimated.size]
    first_valid = cfg.post_fir_first_valid
    if first_valid >= filtered.size:
        return np.asarray([], dtype=np.complex128), None, None
    valid = filtered[first_valid:]
    mean_power = float(np.mean(np.abs(valid) ** 2)) if valid.size else 0.0
    unclamped_power_dbfs = 10.0 * math.log10(max(mean_power, 1e-300) / cfg.full_scale_complex_power)
    clamped_mean_power = max(mean_power, cfg.epsilon)
    power_dbfs = 10.0 * math.log10(clamped_mean_power / cfg.full_scale_complex_power)
    return valid, power_dbfs, unclamped_power_dbfs


def synthesize_adc_tone(sample_count: int, fs_hz: float, freq_hz: float, amp_norm: float, phase_rad: float) -> np.ndarray:
    n = np.arange(sample_count, dtype=np.float64)
    return amp_norm * np.cos(2.0 * np.pi * freq_hz * n / fs_hz + phase_rad)


def frequency_response(coeffs: np.ndarray, freqs_hz: np.ndarray, fs_hz: float, chunk: int = 256) -> np.ndarray:
    n = np.arange(coeffs.size, dtype=np.float64)
    out = np.empty(freqs_hz.size, dtype=np.float64)
    for start in range(0, freqs_hz.size, chunk):
        stop = min(start + chunk, freqs_hz.size)
        omega = 2.0 * np.pi * freqs_hz[start:stop, None] / fs_hz
        resp = np.exp(-1j * omega * n) @ coeffs
        out[start:stop] = np.abs(resp)
    return out


def db20(values: np.ndarray | float) -> np.ndarray | float:
    return 20.0 * np.log10(np.maximum(values, 1e-300))


def db10(values: np.ndarray | float) -> np.ndarray | float:
    return 10.0 * np.log10(np.maximum(values, 1e-300))


def write_rows(path: Path, headers: Iterable[str], rows: Iterable[Iterable[object]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh)
        writer.writerow(list(headers))
        writer.writerows(rows)


def plot_theoretical_response(path: Path, freqs_hz: np.ndarray, decim_db: np.ndarray, post_db: np.ndarray, total_db: np.ndarray) -> None:
    plt.figure(figsize=(9.5, 5.3))
    plt.plot(freqs_hz / 1e3, decim_db, label="8192-tap /130 FIR decimator")
    plt.plot(freqs_hz / 1e3, post_db, label="10K post FIR")
    plt.plot(freqs_hz / 1e3, total_db, label="combined", linewidth=2.0)
    plt.axvline(100.0, color="tab:red", linestyle="--", linewidth=1.0, label="100 kHz offset")
    plt.xlabel("Baseband offset after DDC (kHz)")
    plt.ylabel("Magnitude response (dB)")
    plt.title("Current firmware 10K RBW chain theoretical response")
    plt.grid(True, alpha=0.3)
    plt.ylim(-180, 5)
    plt.legend(loc="best")
    plt.tight_layout()
    plt.savefig(path, dpi=160)
    plt.close()


def plot_synthetic(path: Path, synthetic_rows: list[dict[str, float]]) -> None:
    labels = [f'{row["input_freq_hz"] / 1e6:.3f} MHz' for row in synthetic_rows]
    powers = [row["power_dbfs"] for row in synthetic_rows]
    plt.figure(figsize=(7.0, 4.6))
    bars = plt.bar(labels, powers, color=["tab:blue", "tab:orange"])
    plt.ylabel("Output power (dBFS)")
    plt.title("Synthetic long-record output through current 10K RBW DSP")
    plt.grid(True, axis="y", alpha=0.3)
    for bar, value in zip(bars, powers):
        plt.text(bar.get_x() + bar.get_width() / 2.0, value, f"{value:.2f}", ha="center", va="bottom")
    plt.tight_layout()
    plt.savefig(path, dpi=160)
    plt.close()


def build_report(
    output_dir: Path,
    cfg: FirmwareConfig,
    captures: list[IlaCapture],
    decim_coeffs: np.ndarray,
    rbw_coeffs: np.ndarray,
    synthetic_rows: list[dict[str, float]],
    response_at_100k: dict[str, float],
    synthetic_delta_db: float,
) -> None:
    report = output_dir / "offline_10k_rbw_dsp_report.md"
    lines: list[str] = []
    lines.append("# 10K RBW ILA Raw ADC Offline DSP Validation")
    lines.append("")
    lines.append("## Verdict")
    lines.append("")
    lines.append(
        f"- 原始 ILA 每个文件只有 {captures[0].sample_count if captures else 'n/a'} 点，"
        f"小于当前固件 10K A 方案 FIR decimator 的 {cfg.decim_taps} taps，"
        "不能直接产生稳态 decimated output。"
    )
    lines.append(
        f"- 1024 点最多只能触发 {captures[0].decim_outputs_from_short_record if captures else 'n/a'} 个 /130 decimator 输出；"
        f"后级 10K FIR 还需要 first_valid={cfg.post_fir_first_valid}，所以直接 raw capture 无法给出最终功率。"
    )
    lines.append(
        f"- 用 ILA 估计幅度合成 {int(synthetic_rows[0]['sample_count']) if synthetic_rows else 'n/a'} 点长记录后，"
        f"40.100 MHz 相对 40.000 MHz 的最终输出功率降低 {synthetic_delta_db:.2f} dB；"
        "该数值受固件 EPSILON 地板限制。"
    )
    lines.append(
        f"- 理论频响在 100 kHz offset 处：decimator={response_at_100k['decim_db']:.2f} dB，"
        f"后级 10K FIR={response_at_100k['post_fir_db']:.2f} dB，"
        f"合计={response_at_100k['combined_db']:.2f} dB。"
    )
    lines.append("")
    lines.append("## Firmware Parameters Used")
    lines.append("")
    lines.append(f"- Source: `{APP_CONFIG.relative_to(REPO_ROOT)}` and `{RBW_COEFFS_C.relative_to(REPO_ROOT)}`")
    lines.append(f"- ADC Fs: {cfg.fs_hz / 1e6:.6f} MHz")
    lines.append(f"- DDC NCO: {cfg.ddc_if_hz / 1e6:.6f} MHz, real=x*cos, imag=x*(-sin)")
    lines.append(f"- FIR decimator: R={cfg.decim_r}, taps={cfg.decim_taps}, cutoff={cfg.decim_cutoff_hz:.0f} Hz, Kaiser beta={cfg.decim_beta:.1f}")
    lines.append(f"- Decimated Fs: {cfg.fs_decimated_hz / 1e6:.6f} MHz")
    lines.append(f"- Post 10K FIR: taps={rbw_coeffs.size}, observe={cfg.rbw_10k_observe_points}, skip={cfg.rbw_10k_skip_points}, first_valid={cfg.post_fir_first_valid}")
    lines.append(f"- Accumulation target: {cfg.accum_target} decimated samples")
    lines.append("")
    lines.append("## ILA Short Record Results")
    lines.append("")
    lines.append("| File | Samples | Selected column | Mean code | RMS code | Hann peak MHz | Model freq MHz | Fit amp code | Decim outputs | Final valid outputs | Direct power dBFS |")
    lines.append("|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|")
    for cap in captures:
        direct = "n/a" if cap.direct_power_dbfs is None else f"{cap.direct_power_dbfs:.2f}"
        lines.append(
            f"| {cap.path.name} | {cap.sample_count} | `{cap.selected_column}` | "
            f"{cap.mean_code:.3f} | {cap.rms_code:.3f} | {cap.hann_peak_hz / 1e6:.6f} | "
            f"{cap.fitted_freq_hz / 1e6:.6f} | "
            f"{cap.fitted_amp_code:.3f} | {cap.decim_outputs_from_short_record} | "
            f"{cap.final_outputs_after_post_fir} | {direct} |"
        )
    lines.append("")
    for cap in captures:
        for note in cap.notes:
            lines.append(f"- `{cap.path.name}`: {note}")
    lines.append("")
    lines.append("## Synthetic Long-Record Test")
    lines.append("")
    lines.append("| Input freq MHz | Samples | ILA-derived amp code | Final valid outputs | Power dBFS | Unclamped dBFS | Power dBm | Relative to 40.000 MHz dB |")
    lines.append("|---:|---:|---:|---:|---:|---:|---:|---:|")
    for row in synthetic_rows:
        lines.append(
            f"| {row['input_freq_hz'] / 1e6:.6f} | {int(row['sample_count'])} | "
            f"{row['amp_code']:.3f} | {int(row['valid_outputs'])} | {row['power_dbfs']:.2f} | "
            f"{row['unclamped_power_dbfs']:.2f} | {row['power_dbm']:.2f} | {row['relative_db']:.2f} |"
        )
    lines.append("")
    lines.append("Interpretation: 40.100 MHz mixes to a +100 kHz complex baseband tone. The current 10K chain should heavily reject that offset in offline math; the reported firmware-style power is clipped at the EPSILON floor when the residual falls below it.")
    lines.append("")
    lines.append("## If Hardware Still Does Not Improve")
    lines.append("")
    lines.append("如果理论/离线压制很好但板上仍不改善，下一步最像运行时问题，而不是这个滤波器的离线频响问题。优先查：")
    lines.append("")
    lines.append("- 每个 sweep 点是否真的累积到 `accum_target=2944` 个 decimated samples；不足会导致后级 FIR 后没有有效功率。")
    lines.append("- 8192-tap complex FIR decimator 是否过重，导致 sweep 状态机超时、丢帧或提前读功率。")
    lines.append("- DMA 是否仍是一帧一帧 rearm，且总 rearm 次数足够；10K 需要大量 4096-sample frame 才能填满目标。")
    lines.append("- DDC NCO 相位连续性和符号是否与 `ddc_mix_to_time_domain_sweep()` 一致；符号错通常会把 offset 放到相反频率，但功率滤波仍应按绝对 offset 受抑。")
    lines.append("- 测量状态机是否在 `signal_processing_accumulation_ready()` 之前调用了功率计算，或 RBW mode/coeffs 是否没有真正切到 10K。")
    lines.append("- 如果看到固定约 -105.99 dBm 一类地板值，要优先怀疑 `EPSILON` clamp 前没有有效能量到达功率计算。")
    lines.append("")
    lines.append("## Generated Files")
    lines.append("")
    lines.append("- `offline_10k_rbw_dsp.py`: reproducible script")
    lines.append("- `ila_short_record_summary.csv`: direct ILA short-record checks")
    lines.append("- `synthetic_power_summary.csv`: long synthetic record power comparison")
    lines.append("- `theoretical_response.csv`: decimator/post-FIR/combined response")
    lines.append("- `theoretical_10k_response.png`: frequency-response plot")
    lines.append("- `synthetic_power_comparison.png`: synthetic output-power plot")
    lines.append("")
    lines.append("## Reproduce")
    lines.append("")
    lines.append("```powershell")
    lines.append(r"python docs\ila_offline_dsp_10k_2026_06_04\offline_10k_rbw_dsp.py")
    lines.append("```")
    report.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    args = parse_args()
    input_dir = args.input_dir.resolve()
    output_dir = args.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    cfg = load_firmware_config()
    rbw_coeffs = load_rbw_10k_coeffs()
    decim_coeffs = design_10k_decimator_coeffs(cfg)

    captures = [
        load_ila_capture(path, cfg, decim_coeffs, rbw_coeffs)
        for path in sorted(input_dir.glob("*.csv"))
    ]
    if not captures:
        raise SystemExit(f"No CSV captures found in {input_dir}")

    write_rows(
        output_dir / "ila_short_record_summary.csv",
        [
            "file",
            "samples",
            "selected_column",
            "mean_code",
                "rms_code",
                "hann_peak_hz",
                "hann_peak_db_code",
                "fitted_freq_hz",
            "fitted_amp_code",
            "fitted_phase_rad",
            "decim_outputs_from_short_record",
                "final_outputs_after_post_fir",
                "direct_power_dbfs",
                "direct_unclamped_power_dbfs",
                "notes",
        ],
        [
            [
                cap.path.name,
                cap.sample_count,
                cap.selected_column,
                f"{cap.mean_code:.9g}",
                f"{cap.rms_code:.9g}",
                f"{cap.hann_peak_hz:.9g}",
                f"{cap.hann_peak_db_code:.9g}",
                f"{cap.fitted_freq_hz:.9g}",
                f"{cap.fitted_amp_code:.9g}",
                f"{cap.fitted_phase_rad:.9g}",
                cap.decim_outputs_from_short_record,
                cap.final_outputs_after_post_fir,
                "" if cap.direct_power_dbfs is None else f"{cap.direct_power_dbfs:.9g}",
                "" if cap.direct_unclamped_power_dbfs is None else f"{cap.direct_unclamped_power_dbfs:.9g}",
                " | ".join(cap.notes),
            ]
            for cap in captures
        ],
    )

    amp_code = float(np.median([cap.fitted_amp_code for cap in captures if math.isfinite(cap.fitted_amp_code)]))
    phase_rad = float(captures[0].fitted_phase_rad)
    amp_norm = amp_code / 32768.0
    synthetic_rows: list[dict[str, float]] = []
    base_power: float | None = None
    for input_freq in (cfg.ddc_if_hz, cfg.ddc_if_hz + 100_000.0):
        adc_norm = synthesize_adc_tone(args.synthetic_samples, cfg.fs_hz, input_freq, amp_norm, phase_rad)
        mixed = ddc_mix(adc_norm, cfg)
        decim = fir_decimate_like_firmware(mixed, decim_coeffs, cfg.decim_r)
        valid, power_dbfs, unclamped_power_dbfs = apply_post_fir_and_measure(decim, rbw_coeffs, cfg)
        if power_dbfs is None:
            raise RuntimeError("Synthetic record did not produce final valid samples")
        if base_power is None:
            base_power = power_dbfs
        synthetic_rows.append(
            {
                "input_freq_hz": input_freq,
                "sample_count": float(args.synthetic_samples),
                "amp_code": amp_code,
                "valid_outputs": float(valid.size),
                "power_dbfs": power_dbfs,
                "unclamped_power_dbfs": unclamped_power_dbfs if unclamped_power_dbfs is not None else power_dbfs,
                "power_dbm": power_dbfs + cfg.adc_input_full_scale_dbm,
                "relative_db": power_dbfs - base_power,
            }
        )

    synthetic_delta_db = synthetic_rows[1]["power_dbfs"] - synthetic_rows[0]["power_dbfs"]
    write_rows(
        output_dir / "synthetic_power_summary.csv",
        [
            "input_freq_hz",
            "sample_count",
            "amp_code",
            "amp_norm",
            "decim_r",
            "decim_outputs_before_post_fir",
            "valid_outputs_after_post_fir",
            "power_dbfs",
            "unclamped_power_dbfs",
            "power_dbm",
            "relative_to_40mhz_db",
        ],
        [
            [
                f"{row['input_freq_hz']:.9g}",
                int(row["sample_count"]),
                f"{row['amp_code']:.9g}",
                f"{amp_norm:.9g}",
                cfg.decim_r,
                len(np.arange(cfg.decim_r - 1, args.synthetic_samples, cfg.decim_r)),
                int(row["valid_outputs"]),
                f"{row['power_dbfs']:.9g}",
                f"{row['unclamped_power_dbfs']:.9g}",
                f"{row['power_dbm']:.9g}",
                f"{row['relative_db']:.9g}",
            ]
            for row in synthetic_rows
        ],
    )

    freqs = np.linspace(0.0, 300_000.0, 1201)
    decim_mag = frequency_response(decim_coeffs, freqs, cfg.fs_hz, chunk=128)
    post_mag = frequency_response(rbw_coeffs, freqs, cfg.fs_decimated_hz, chunk=256)
    combined_mag = decim_mag * post_mag
    write_rows(
        output_dir / "theoretical_response.csv",
        ["offset_hz", "decimator_mag_db", "post_10k_fir_mag_db", "combined_mag_db"],
        zip(freqs, db20(decim_mag), db20(post_mag), db20(combined_mag)),
    )
    idx100 = int(np.argmin(np.abs(freqs - 100_000.0)))
    response_at_100k = {
        "decim_db": float(db20(decim_mag[idx100])),
        "post_fir_db": float(db20(post_mag[idx100])),
        "combined_db": float(db20(combined_mag[idx100])),
    }

    plot_theoretical_response(
        output_dir / "theoretical_10k_response.png",
        freqs,
        db20(decim_mag),
        db20(post_mag),
        db20(combined_mag),
    )
    plot_synthetic(output_dir / "synthetic_power_comparison.png", synthetic_rows)
    build_report(
        output_dir,
        cfg,
        captures,
        decim_coeffs,
        rbw_coeffs,
        synthetic_rows,
        response_at_100k,
        synthetic_delta_db,
    )

    print(f"Wrote report: {output_dir / 'offline_10k_rbw_dsp_report.md'}")
    print(f"Short-record final outputs: {[cap.final_outputs_after_post_fir for cap in captures]}")
    print(f"40.100 MHz relative output: {synthetic_delta_db:.2f} dB")


if __name__ == "__main__":
    main()
