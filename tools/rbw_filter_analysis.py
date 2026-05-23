#!/usr/bin/env python3
"""
Offline RBW filter analysis for the current firmware.

The firmware sweep path is:

    DDC -> CIC decimator -> post-decimation FIR -> mean(I^2 + Q^2)

This script mirrors the CIC and FIR parameters in app_config.h and plots the
steady-state frequency response seen by a tone after DDC.
"""

from __future__ import annotations

import argparse
import csv
import math
import re
from dataclasses import dataclass
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np


ROOT = Path(__file__).resolve().parents[1]
APP_CONFIG = ROOT / "code" / "pusu_20260516" / "vitis" / "pusu_20260516" / "src" / "app_config.h"
DEFAULT_OUT_DIR = ROOT / "docs" / "rbw_filter_analysis"
ADC_FS_HZ = 130_000_000.0

MODE_ORDER = ("1K", "10K", "30K", "100K", "300K", "1M")
FINITE_WINDOW_MODE_ORDER = ("1K", "10K", "100K", "1M")
FINITE_WINDOW_OFFSETS_HZ = (
    1_000.0,
    3_000.0,
    10_000.0,
    14_000.0,
    100_000.0,
    1_000_000.0,
    10_000_000.0,
    14_000_000.0,
)
FINITE_WINDOW_PLOT_FLOOR_DB = -220.0
_CIC_IMPULSE_CACHE: dict[tuple[int, int], np.ndarray] = {}


@dataclass(frozen=True)
class RbwMode:
    name: str
    rbw_hz: float
    cic_r: int
    cic_n: int
    fir_taps: int
    observe_points: int
    skip_points: int

    @property
    def fs_out_hz(self) -> float:
        return ADC_FS_HZ / float(self.cic_r)


def parse_macros(path: Path) -> dict[str, float]:
    text = path.read_text(encoding="utf-8", errors="ignore")
    macros: dict[str, float] = {}
    pattern = re.compile(r"^\s*#define\s+([A-Za-z0-9_]+)\s+([0-9]+(?:\.[0-9]+)?)(?:[fFuUlL]*)\b", re.MULTILINE)
    for match in pattern.finditer(text):
        name, value = match.groups()
        macros[name] = float(value)
    return macros


def load_modes() -> list[RbwMode]:
    macros = parse_macros(APP_CONFIG)
    modes: list[RbwMode] = []
    for name in MODE_ORDER:
        prefix = f"RBW_{name}"
        modes.append(
            RbwMode(
                name=name,
                rbw_hz=macros[f"{prefix}_HZ"],
                cic_r=int(macros[f"{prefix}_CIC_R"]),
                cic_n=int(macros[f"{prefix}_CIC_N"]),
                fir_taps=int(macros[f"{prefix}_FIR_TAPS"]),
                observe_points=int(macros[f"{prefix}_OBSERVE_POINTS"]),
                skip_points=int(macros[f"{prefix}_SKIP_POINTS"]),
            )
        )
    return modes


def db20(mag: np.ndarray | float) -> np.ndarray | float:
    return 20.0 * np.log10(np.maximum(mag, 1e-300))


def design_fir(mode: RbwMode) -> np.ndarray:
    """Mirror compensating_fir_init() in signal_processing.c."""
    taps = mode.fir_taps
    fs_out = mode.fs_out_hz
    fc_norm = mode.rbw_hz / fs_out
    mid = taps // 2
    coeffs = np.zeros(taps, dtype=np.float64)

    for n in range(taps):
        k = n - mid
        if k == 0:
            sinc_val = 2.0 * fc_norm
        else:
            x = 2.0 * math.pi * fc_norm * float(k)
            sinc_val = math.sin(x) / (math.pi * float(k))

        window = 0.54 - 0.46 * math.cos(2.0 * math.pi * float(n) / float(taps - 1))
        coeffs[n] = sinc_val * window

    coeff_sum = float(np.sum(coeffs))
    if abs(coeff_sum) > 1e-12:
        coeffs /= coeff_sum
    return coeffs


def alias_to_output(freq_hz: np.ndarray, fs_out_hz: float) -> np.ndarray:
    """Map pre-decimation frequency to the post-decimation Nyquist interval."""
    return ((freq_hz + fs_out_hz / 2.0) % fs_out_hz) - fs_out_hz / 2.0


def cic_mag(freq_hz: np.ndarray, mode: RbwMode) -> np.ndarray:
    """Normalized CIC magnitude, differential delay M=1."""
    f = np.asarray(freq_hz, dtype=np.float64)
    numerator = np.sin(math.pi * f * float(mode.cic_r) / ADC_FS_HZ)
    denominator = float(mode.cic_r) * np.sin(math.pi * f / ADC_FS_HZ)
    response = np.ones_like(f, dtype=np.float64)
    mask = np.abs(denominator) > 1e-30
    response[mask] = np.abs(numerator[mask] / denominator[mask]) ** mode.cic_n
    return response


def fir_mag_at(freq_hz: np.ndarray, coeffs: np.ndarray, fs_out_hz: float) -> np.ndarray:
    freq = np.asarray(freq_hz, dtype=np.float64)
    n = np.arange(coeffs.size, dtype=np.float64)
    out = np.empty(freq.size, dtype=np.float64)
    chunk = 8192
    for start in range(0, freq.size, chunk):
        stop = min(start + chunk, freq.size)
        phase = -2j * math.pi * freq[start:stop, None] / fs_out_hz * n[None, :]
        out[start:stop] = np.abs(np.exp(phase).dot(coeffs))
    return out


def total_mag(freq_hz: np.ndarray, mode: RbwMode, coeffs: np.ndarray) -> np.ndarray:
    alias = alias_to_output(np.asarray(freq_hz, dtype=np.float64), mode.fs_out_hz)
    return cic_mag(freq_hz, mode) * fir_mag_at(alias, coeffs, mode.fs_out_hz)


def cic_impulse_response(mode: RbwMode) -> np.ndarray:
    """Normalized high-rate impulse response of the zero-state CIC stage."""
    key = (mode.cic_r, mode.cic_n)
    cached = _CIC_IMPULSE_CACHE.get(key)
    if cached is not None:
        return cached

    r = mode.cic_r
    n_stages = mode.cic_n
    length = n_stages * (r - 1) + 1
    h = np.zeros(length, dtype=np.float64)

    # Coefficients of ((1 - z^-R) / (1 - z^-1))^N.
    # h[m] = sum_j (-1)^j C(N,j) C(m-jR+N-1,N-1), normalized by R^N.
    for j in range(n_stages + 1):
        start = j * r
        if start >= length:
            break
        sample_index = np.arange(length - start, dtype=np.float64)
        term = np.ones_like(sample_index)
        for p in range(1, n_stages):
            term *= (sample_index + float(p)) / float(p)
        sign = -1.0 if (j & 1) else 1.0
        h[start:] += sign * float(math.comb(n_stages, j)) * term

    h /= float(r) ** n_stages
    _CIC_IMPULSE_CACHE[key] = h
    return h


def cic_zero_state_tone_output(mode: RbwMode, offset_hz: float, output_count: int) -> np.ndarray:
    """Generate the decimated CIC output for a tone after a reset."""
    h = cic_impulse_response(mode)
    omega = 2.0 * math.pi * float(offset_hz) / ADC_FS_HZ
    impulse_index = np.arange(h.size, dtype=np.float64)
    partial_response = np.cumsum(h * np.exp(-1j * omega * impulse_index))

    k = np.arange(output_count, dtype=np.int64)
    output_time = (k + 1) * mode.cic_r - 1
    response_index = np.minimum(output_time, h.size - 1)
    return np.exp(1j * omega * output_time.astype(np.float64)) * partial_response[response_index]


def find_bandwidth(freq_hz: np.ndarray, mag: np.ndarray, db_down: float) -> float:
    target = 10.0 ** (-db_down / 20.0)
    below = np.flatnonzero(mag <= target)
    if below.size == 0:
        return float("nan")
    i = int(below[0])
    if i == 0:
        return float(freq_hz[0])
    x0, x1 = float(freq_hz[i - 1]), float(freq_hz[i])
    y0, y1 = float(mag[i - 1]), float(mag[i])
    if y1 == y0:
        return x1
    return x0 + (target - y0) * (x1 - x0) / (y1 - y0)


def enbw_main(mode: RbwMode, coeffs: np.ndarray) -> float:
    f = np.linspace(-mode.fs_out_hz / 2.0, mode.fs_out_hz / 2.0, 120_001, endpoint=False)
    mag = total_mag(f, mode, coeffs)
    return float(np.trapezoid(mag * mag, f))


def enbw_full_adc(mode: RbwMode, coeffs: np.ndarray) -> float:
    """Integrate response over ADC Nyquist, including post-decimation aliasing."""
    f = np.linspace(-ADC_FS_HZ / 2.0, ADC_FS_HZ / 2.0, 240_001, endpoint=False)
    alias = alias_to_output(f, mode.fs_out_hz)

    # FIR response is periodic after decimation. Interpolate a dense positive
    # grid instead of doing a huge direct matrix multiply over the ADC band.
    grid = np.linspace(0.0, mode.fs_out_hz / 2.0, 40_001)
    fir_grid = fir_mag_at(grid, coeffs, mode.fs_out_hz)
    fir_response = np.interp(np.abs(alias), grid, fir_grid)
    mag = cic_mag(f, mode) * fir_response
    return float(np.trapezoid(mag * mag, f))


def phase_noise_auto_rbw(offset_hz: float) -> str:
    # Mirrors phase_noise_plan.c rbw_mode_for_offset().
    if offset_hz < 10_000.0:
        return "1K"
    if offset_hz < 100_000.0:
        return "10K"
    if offset_hz <= 1_000_000.0:
        return "30K"
    return "100K"


def analyze_modes(modes: list[RbwMode]) -> tuple[list[dict[str, float | str]], dict[str, np.ndarray]]:
    rows: list[dict[str, float | str]] = []
    responses: dict[str, np.ndarray] = {}

    for mode in modes:
        coeffs = design_fir(mode)
        norm_f = np.linspace(0.0, 12.0 * mode.rbw_hz, 6001)
        mag = total_mag(norm_f, mode, coeffs)
        responses[mode.name] = np.column_stack([norm_f, db20(mag)])

        main_f = np.linspace(0.0, min(mode.fs_out_hz / 2.0, 4.0 * mode.rbw_hz), 40_001)
        main_mag = total_mag(main_f, mode, coeffs)
        bw_3db = find_bandwidth(main_f, main_mag, 3.0103)
        bw_6db = find_bandwidth(main_f, main_mag, 6.0)
        main_enbw = enbw_main(mode, coeffs)
        full_enbw = enbw_full_adc(mode, coeffs)

        row: dict[str, float | str] = {
            "mode": mode.name,
            "rbw_hz": mode.rbw_hz,
            "cic_r": mode.cic_r,
            "cic_n": mode.cic_n,
            "fs_out_hz": mode.fs_out_hz,
            "fir_taps": mode.fir_taps,
            "fir_cutoff_norm": mode.rbw_hz / mode.fs_out_hz,
            "bw_3db_hz": bw_3db,
            "bw_6db_hz": bw_6db,
            "enbw_main_hz": main_enbw,
            "enbw_full_adc_hz": full_enbw,
            "enbw_main_over_rbw": main_enbw / mode.rbw_hz,
            "enbw_full_over_rbw": full_enbw / mode.rbw_hz,
            "noise_correction_db": 10.0 * math.log10(main_enbw / mode.rbw_hz),
        }

        for multiple in (0.5, 1.0, 2.0, 5.0, 10.0):
            att = db20(total_mag(np.array([multiple * mode.rbw_hz]), mode, coeffs))[0]
            row[f"att_{multiple:g}x_rbw_db"] = float(att)
        row["att_10khz_db"] = float(db20(total_mag(np.array([10_000.0]), mode, coeffs))[0])
        rows.append(row)

    return rows, responses


def write_summary(out_dir: Path, rows: list[dict[str, float | str]]) -> None:
    csv_path = out_dir / "rbw_filter_summary.csv"
    fieldnames = list(rows[0].keys())
    with csv_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    md_path = out_dir / "rbw_filter_summary.md"
    with md_path.open("w", encoding="utf-8") as f:
        f.write("# RBW Filter Analysis\n\n")
        f.write(f"Source config: `{APP_CONFIG}`\n\n")
        f.write("| Mode | Fs out | 3 dB BW | ENBW main | ENBW/RBW | Correction | Att @ 1x RBW | Att @ 10 kHz |\n")
        f.write("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n")
        for row in rows:
            f.write(
                "| {mode} | {fs_out_hz:.1f} | {bw_3db_hz:.1f} | {enbw_main_hz:.1f} | "
                "{enbw_main_over_rbw:.3f} | {noise_correction_db:.2f} dB | "
                "{att_1x_rbw_db:.1f} dB | {att_10khz_db:.1f} dB |\n".format(**row)
            )
        f.write("\n")
        f.write("`Correction` is based on main-lobe ENBW and is the amount by which noise density is high if firmware divides by nominal RBW instead of actual ENBW.\n")


def write_response_csvs(out_dir: Path, responses: dict[str, np.ndarray]) -> None:
    for name, data in responses.items():
        path = out_dir / f"response_{name}.csv"
        with path.open("w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(["offset_hz", "response_db"])
            writer.writerows(data.tolist())


def plot_all_modes(out_dir: Path, responses: dict[str, np.ndarray], modes: list[RbwMode]) -> None:
    fig, ax = plt.subplots(figsize=(10, 6), dpi=150)
    for mode in modes:
        data = responses[mode.name]
        ax.plot(data[:, 0] / mode.rbw_hz, data[:, 1], label=mode.name)
    ax.set_title("Firmware RBW filter response, normalized offset")
    ax.set_xlabel("Offset / nominal RBW")
    ax.set_ylabel("Magnitude response (dB)")
    ax.set_xlim(0, 12)
    ax.set_ylim(-120, 3)
    ax.grid(True, alpha=0.3)
    ax.legend(ncol=3)
    fig.tight_layout()
    fig.savefig(out_dir / "rbw_response_normalized.png")
    plt.close(fig)


def plot_mode_grid(out_dir: Path, responses: dict[str, np.ndarray], modes: list[RbwMode]) -> None:
    fig, axes = plt.subplots(3, 2, figsize=(11, 10), dpi=150)
    for ax, mode in zip(axes.flat, modes):
        data = responses[mode.name]
        ax.plot(data[:, 0], data[:, 1])
        ax.axvline(mode.rbw_hz, color="tab:red", linestyle="--", linewidth=1, label="nominal RBW")
        ax.set_title(f"{mode.name}: R={mode.cic_r}, N={mode.cic_n}, FIR={mode.fir_taps}")
        ax.set_xlabel("Offset after DDC (Hz)")
        ax.set_ylabel("dB")
        ax.set_ylim(-130, 3)
        ax.grid(True, alpha=0.3)
    fig.tight_layout()
    fig.savefig(out_dir / "rbw_response_by_mode.png")
    plt.close(fig)


def plot_mode_components(out_dir: Path, modes: list[RbwMode]) -> None:
    for mode in modes:
        coeffs = design_fir(mode)
        x_max = min(mode.fs_out_hz / 2.0, 12.0 * mode.rbw_hz)
        freq = np.linspace(0.0, x_max, 12_001)
        cic_db = db20(cic_mag(freq, mode))
        fir_db = db20(fir_mag_at(freq, coeffs, mode.fs_out_hz))
        total_db = db20(total_mag(freq, mode, coeffs))

        fig, axes = plt.subplots(3, 1, figsize=(10, 9), dpi=150, sharex=True)

        axes[0].plot(freq, cic_db, color="tab:blue")
        axes[0].set_title(f"{mode.name} RBW - CIC stage")
        axes[0].set_ylabel("dB")
        axes[0].grid(True, alpha=0.3)
        axes[0].axvline(mode.rbw_hz, color="tab:red", linestyle="--", linewidth=1)

        axes[1].plot(freq, fir_db, color="tab:green")
        axes[1].set_title(f"{mode.name} RBW - FIR stage")
        axes[1].set_ylabel("dB")
        axes[1].grid(True, alpha=0.3)
        axes[1].axvline(mode.rbw_hz, color="tab:red", linestyle="--", linewidth=1)

        axes[2].plot(freq, total_db, color="tab:purple")
        axes[2].set_title(f"{mode.name} RBW - Combined response")
        axes[2].set_xlabel("Offset after DDC (Hz)")
        axes[2].set_ylabel("dB")
        axes[2].grid(True, alpha=0.3)
        axes[2].axvline(mode.rbw_hz, color="tab:red", linestyle="--", linewidth=1, label="nominal RBW")
        axes[2].legend(loc="best")

        for ax in axes:
            ax.set_ylim(-160, 3)

        fig.tight_layout()
        fig.savefig(out_dir / f"transfer_{mode.name}.png")
        plt.close(fig)

        csv_path = out_dir / f"transfer_{mode.name}.csv"
        with csv_path.open("w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(["offset_hz", "cic_db", "fir_db", "total_db"])
            writer.writerows(zip(freq.tolist(), cic_db.tolist(), fir_db.tolist(), total_db.tolist()))


def plot_1k_detail(out_dir: Path, modes_by_name: dict[str, RbwMode]) -> None:
    mode = modes_by_name["1K"]
    coeffs = design_fir(mode)
    f = np.linspace(0.0, 25_000.0, 10_001)
    mag_db = db20(total_mag(f, mode, coeffs))

    fig, ax = plt.subplots(figsize=(10, 5), dpi=150)
    ax.plot(f, mag_db)
    for marker in (1_000.0, 5_000.0, 10_000.0, 20_000.0):
        ax.axvline(marker, color="tab:red" if marker == 1_000.0 else "gray", linestyle="--", linewidth=0.8)
    ax.set_title("1K RBW actual input-offset response")
    ax.set_xlabel("Offset after DDC (Hz)")
    ax.set_ylabel("Magnitude response (dB)")
    ax.set_xlim(0, 25_000)
    ax.set_ylim(-150, 3)
    ax.grid(True, alpha=0.3)
    fig.tight_layout()
    fig.savefig(out_dir / "rbw_1k_detail.png")
    plt.close(fig)


def plot_phase_noise_auto_rejection(out_dir: Path, modes_by_name: dict[str, RbwMode]) -> None:
    offsets = np.unique(np.concatenate([
        np.linspace(1_000.0, 12_000.0, 1600),
        np.logspace(math.log10(12_000.0), math.log10(1_000_000.0), 1200),
    ]))
    selected: list[str] = []
    rejection = np.empty_like(offsets)

    coeff_cache = {name: design_fir(mode) for name, mode in modes_by_name.items()}
    for i, offset in enumerate(offsets):
        name = phase_noise_auto_rbw(float(offset))
        selected.append(name)
        mode = modes_by_name[name]
        rejection[i] = db20(total_mag(np.array([offset]), mode, coeff_cache[name]))[0]

    fig, ax = plt.subplots(figsize=(10, 5), dpi=150)
    ax.semilogx(offsets, rejection)
    ax.axvline(10_000.0, color="tab:red", linestyle="--", linewidth=1, label="10 kHz RBW switch")
    ax.axvline(100_000.0, color="tab:orange", linestyle="--", linewidth=1, label="100 kHz RBW switch")
    ax.set_title("Carrier rejection in phase-noise auto RBW plan")
    ax.set_xlabel("Measured offset (Hz)")
    ax.set_ylabel("Response to carrier at that offset (dB)")
    ax.set_xlim(1_000, 1_000_000)
    ax.set_ylim(-150, 5)
    ax.grid(True, which="both", alpha=0.3)
    ax.legend()
    fig.tight_layout()
    fig.savefig(out_dir / "phase_noise_auto_carrier_rejection.png")
    plt.close(fig)

    csv_path = out_dir / "phase_noise_auto_carrier_rejection.csv"
    with csv_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["offset_hz", "selected_rbw_mode", "carrier_response_db"])
        writer.writerows(zip(offsets.tolist(), selected, rejection.tolist()))


def plot_phase_noise_auto_leakage_density(out_dir: Path, modes_by_name: dict[str, RbwMode]) -> None:
    """Plot the dBc/Hz a pure carrier leak would produce in firmware math."""
    offsets = np.unique(np.concatenate([
        np.linspace(1_000.0, 12_000.0, 1600),
        np.logspace(math.log10(12_000.0), math.log10(1_000_000.0), 1200),
    ]))
    selected: list[str] = []
    rbw_hz = np.empty_like(offsets)
    rejection = np.empty_like(offsets)
    leakage_dbc_hz = np.empty_like(offsets)

    coeff_cache = {name: design_fir(mode) for name, mode in modes_by_name.items()}
    for i, offset in enumerate(offsets):
        name = phase_noise_auto_rbw(float(offset))
        selected.append(name)
        mode = modes_by_name[name]
        rbw_hz[i] = mode.rbw_hz
        rejection[i] = db20(total_mag(np.array([offset]), mode, coeff_cache[name]))[0]
        leakage_dbc_hz[i] = rejection[i] - (10.0 * math.log10(mode.rbw_hz))

    fig, ax = plt.subplots(figsize=(10, 5), dpi=150)
    ax.semilogx(offsets, leakage_dbc_hz)
    ax.axhline(-90.0, color="tab:green", linestyle=":", linewidth=1.2, label="-90 dBc/Hz reference")
    ax.axvline(10_000.0, color="tab:red", linestyle="--", linewidth=1, label="10 kHz RBW switch")
    ax.axvline(100_000.0, color="tab:orange", linestyle="--", linewidth=1, label="100 kHz RBW switch")
    ax.set_title("Displayed phase noise caused by carrier leakage only")
    ax.set_xlabel("Measured offset (Hz)")
    ax.set_ylabel("Firmware-reported density (dBc/Hz)")
    ax.set_xlim(1_000, 1_000_000)
    ax.set_ylim(-170, -20)
    ax.grid(True, which="both", alpha=0.3)
    ax.legend()
    fig.tight_layout()
    fig.savefig(out_dir / "phase_noise_auto_leakage_density.png")
    plt.close(fig)

    csv_path = out_dir / "phase_noise_auto_leakage_density.csv"
    with csv_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow([
            "offset_hz",
            "selected_rbw_mode",
            "rbw_hz",
            "carrier_response_db",
            "displayed_leakage_dbc_hz",
        ])
        writer.writerows(zip(
            offsets.tolist(),
            selected,
            rbw_hz.tolist(),
            rejection.tolist(),
            leakage_dbc_hz.tolist(),
        ))


def finite_window_response_db(mode: RbwMode, offsets_hz: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Model the firmware FIR output window before and after the window fix."""
    coeffs = design_fir(mode)
    accum_count = mode.observe_points + mode.skip_points + mode.fir_taps
    fir_out_len = accum_count - mode.fir_taps + 1
    current_start = mode.skip_points
    fixed_start = mode.fir_taps - 1 + mode.skip_points
    out_len = accum_count - fixed_start

    if out_len <= 0 or current_start + out_len > accum_count or fixed_start + out_len > accum_count:
        raise ValueError(f"{mode.name}: invalid finite window geometry")
    if fir_out_len - current_start != out_len:
        raise ValueError(f"{mode.name}: current and fixed window lengths differ")

    n = np.arange(accum_count, dtype=np.float64)
    current_mag = np.empty(offsets_hz.size, dtype=np.float64)
    fixed_mag = np.empty(offsets_hz.size, dtype=np.float64)

    for i, offset_hz in enumerate(offsets_hz):
        tone = cic_zero_state_tone_output(mode, float(offset_hz), accum_count)
        stage = np.convolve(tone, coeffs, mode="full")[:accum_count]

        current_window = stage[current_start : current_start + out_len]
        fixed_window = stage[fixed_start : fixed_start + out_len]
        current_mag[i] = math.sqrt(float(np.mean(np.abs(current_window) ** 2)))
        fixed_mag[i] = math.sqrt(float(np.mean(np.abs(fixed_window) ** 2)))

    return np.asarray(db20(current_mag)), np.asarray(db20(fixed_mag))


def write_finite_window_outputs(out_dir: Path, modes_by_name: dict[str, RbwMode]) -> None:
    modes = [modes_by_name[name] for name in FINITE_WINDOW_MODE_ORDER]
    summary_rows: list[dict[str, float | str | int]] = []
    curve_rows: list[dict[str, float | str]] = []
    plot_offsets = np.unique(np.concatenate([
        np.geomspace(100.0, 20_000_000.0, 360),
        np.asarray(FINITE_WINDOW_OFFSETS_HZ, dtype=np.float64),
    ]))

    fig, axes = plt.subplots(2, 2, figsize=(12, 8), dpi=150, sharex=True, sharey=True)
    for ax, mode in zip(axes.flat, modes):
        current_db, fixed_db = finite_window_response_db(mode, plot_offsets)
        current_plot = np.maximum(current_db, FINITE_WINDOW_PLOT_FLOOR_DB)
        fixed_plot = np.maximum(fixed_db, FINITE_WINDOW_PLOT_FLOOR_DB)

        ax.semilogx(plot_offsets, current_plot, color="tab:red", linewidth=1.4, label="current window")
        ax.semilogx(plot_offsets, fixed_plot, color="tab:green", linewidth=1.4, label="fixed window")
        ax.axvline(mode.rbw_hz, color="tab:blue", linestyle="--", linewidth=0.9, label="nominal RBW")
        ax.set_title(
            f"{mode.name} RBW: taps={mode.fir_taps}, skip={mode.skip_points}, "
            f"out={mode.observe_points + 1}"
        )
        ax.grid(True, which="both", alpha=0.25)
        ax.set_ylim(FINITE_WINDOW_PLOT_FLOOR_DB, 5.0)

        for offset_hz, cur_db, fix_db in zip(plot_offsets, current_db, fixed_db):
            curve_rows.append({
                "mode": mode.name,
                "offset_hz": float(offset_hz),
                "current_window_response_db": float(cur_db),
                "fixed_window_response_db": float(fix_db),
            })

        summary_current, summary_fixed = finite_window_response_db(
            mode, np.asarray(FINITE_WINDOW_OFFSETS_HZ, dtype=np.float64)
        )
        for offset_hz, cur_db, fix_db in zip(FINITE_WINDOW_OFFSETS_HZ, summary_current, summary_fixed):
            summary_rows.append({
                "mode": mode.name,
                "rbw_hz": mode.rbw_hz,
                "cic_r": mode.cic_r,
                "fir_taps": mode.fir_taps,
                "skip_points": mode.skip_points,
                "accum_count": mode.observe_points + mode.skip_points + mode.fir_taps,
                "output_points": mode.observe_points + 1,
                "offset_hz": offset_hz,
                "current_window_response_db": float(cur_db),
                "fixed_window_response_db": float(fix_db),
                "current_window_density_dbc_hz": float(cur_db - 10.0 * math.log10(mode.rbw_hz)),
                "fixed_window_density_dbc_hz": float(fix_db - 10.0 * math.log10(mode.rbw_hz)),
                "fixed_improvement_db": float(fix_db - cur_db),
            })

    axes[0, 0].set_ylabel("Carrier leakage response (dB)")
    axes[1, 0].set_ylabel("Carrier leakage response (dB)")
    axes[1, 0].set_xlabel("Offset from carrier (Hz)")
    axes[1, 1].set_xlabel("Offset from carrier (Hz)")
    handles, labels = axes[0, 0].get_legend_handles_labels()
    fig.legend(handles, labels, loc="upper center", ncol=3, frameon=False)
    fig.suptitle("Finite FIR Window Leakage: Current vs Fixed Window", y=0.98)
    fig.tight_layout(rect=(0, 0, 1, 0.94))
    fig.savefig(out_dir / "rbw_finite_window_current_vs_fixed.png")
    plt.close(fig)

    curve_path = out_dir / "rbw_finite_window_current_vs_fixed.csv"
    with curve_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(curve_rows[0].keys()))
        writer.writeheader()
        writer.writerows(curve_rows)

    summary_path = out_dir / "rbw_finite_window_leakage_summary.csv"
    with summary_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(summary_rows[0].keys()))
        writer.writeheader()
        writer.writerows(summary_rows)

    md_path = out_dir / "rbw_finite_window_summary.md"
    with md_path.open("w", encoding="utf-8") as f:
        f.write("# RBW Finite Window Leakage\n\n")
        f.write(
            "This models the firmware FIR output window for a single carrier at each offset. "
            "`current` starts at `skip`; `fixed` starts at `taps - 1 + skip`.\n\n"
        )
        f.write(
            "| Mode | Offset | Current response | Fixed response | "
            "Current density | Fixed density | Improvement |\n"
        )
        f.write("| --- | ---: | ---: | ---: | ---: | ---: | ---: |\n")
        for row in summary_rows:
            f.write(
                "| {mode} | {offset_hz:.0f} Hz | {current_window_response_db:.2f} dB | "
                "{fixed_window_response_db:.2f} dB | {current_window_density_dbc_hz:.2f} dBc/Hz | "
                "{fixed_window_density_dbc_hz:.2f} dBc/Hz | {fixed_improvement_db:.2f} dB |\n".format(
                    **row
                )
            )


def print_summary(rows: list[dict[str, float | str]]) -> None:
    print("Mode  Fs_out(Hz)  3dB_BW(Hz)  ENBW_main(Hz)  ENBW/RBW  Corr(dB)  Att@1xRBW  Att@10k")
    for row in rows:
        print(
            "{mode:>4} {fs_out_hz:>11.1f} {bw_3db_hz:>11.1f} {enbw_main_hz:>14.1f} "
            "{enbw_main_over_rbw:>8.3f} {noise_correction_db:>8.2f} "
            "{att_1x_rbw_db:>10.1f} {att_10khz_db:>9.1f}".format(**row)
        )


def main() -> int:
    parser = argparse.ArgumentParser(description="Simulate current firmware RBW filter responses.")
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR, help="Directory for plots and CSV outputs.")
    parser.add_argument("--no-plots", action="store_true", help="Only write numeric CSV/Markdown summaries.")
    args = parser.parse_args()

    modes = load_modes()
    modes_by_name = {mode.name: mode for mode in modes}
    args.out_dir.mkdir(parents=True, exist_ok=True)

    rows, responses = analyze_modes(modes)
    write_summary(args.out_dir, rows)
    write_response_csvs(args.out_dir, responses)

    if not args.no_plots:
        plot_all_modes(args.out_dir, responses, modes)
        plot_mode_grid(args.out_dir, responses, modes)
        plot_mode_components(args.out_dir, modes)
        plot_1k_detail(args.out_dir, modes_by_name)
        plot_phase_noise_auto_rejection(args.out_dir, modes_by_name)
        plot_phase_noise_auto_leakage_density(args.out_dir, modes_by_name)
        write_finite_window_outputs(args.out_dir, modes_by_name)

    print_summary(rows)
    print(f"\nWrote analysis to: {args.out_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
