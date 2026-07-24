#!/usr/bin/env python3
"""Validate the 10K RBW FIR decimator design used by signal_processing.c."""

import math

import numpy as np


FS_HZ = 130_000_000.0
DECIM = 130
TAPS = 8192
CUTOFF_HZ = 50_000.0
BETA = 6.0
CHECK_OFFSET_HZ = 100_000.0


def design_coeffs() -> np.ndarray:
    n = np.arange(TAPS, dtype=np.float64)
    center = (TAPS - 1) / 2.0
    h = 2.0 * CUTOFF_HZ / FS_HZ
    h *= np.sinc(2.0 * CUTOFF_HZ / FS_HZ * (n - center))
    h *= np.kaiser(TAPS, BETA)
    h /= np.sum(h)
    return h


def response_db(coeffs: np.ndarray, freq_hz: float) -> float:
    n = np.arange(coeffs.size, dtype=np.float64)
    omega = 2.0 * math.pi * freq_hz / FS_HZ
    response = abs(np.sum(coeffs * np.exp(-1j * omega * n)))
    return 20.0 * math.log10(max(response, 1e-300))


def main() -> None:
    coeffs = design_coeffs()
    attenuation_db = response_db(coeffs, CHECK_OFFSET_HZ)
    print(f"fs_hz={FS_HZ:.0f}")
    print(f"decim={DECIM}")
    print(f"taps={TAPS}")
    print(f"cutoff_hz={CUTOFF_HZ:.0f}")
    print(f"kaiser_beta={BETA:.1f}")
    print(f"offset_hz={CHECK_OFFSET_HZ:.0f}")
    print(f"offset_response_db={attenuation_db:.2f}")
    print(f"output_rate_hz={FS_HZ / DECIM:.0f}")
    print(f"macs_per_output_complex={2 * TAPS}")


if __name__ == "__main__":
    main()
