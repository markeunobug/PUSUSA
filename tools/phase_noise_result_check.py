import argparse
import csv
import io
import math
import sys
from dataclasses import dataclass
from pathlib import Path


REQUIRED_METADATA = {
    "carrier_hz",
    "carrier_dbm",
    "start_offset_hz",
    "stop_offset_hz",
    "average_count",
    "enbw_mode",
}

DENSITY_METADATA = {
    "points_per_decade",
    "planned_points",
    "received_points",
}

REQUIRED_COLUMNS = {
    "offset_hz",
    "raw_dbc_hz",
    "avg_dbc_hz",
    "noise_power_dbm",
    "rbw_hz",
    "valid",
    "warning",
}

OFFSET_BELOW_RBW_WARNINGS = {
    "offset < rbw",
    "pn_warn_offset_below_rbw",
    "offset_below_rbw",
}


@dataclass
class CheckResult:
    errors: list[str]
    warnings: list[str]
    row_count: int

    @property
    def ok(self) -> bool:
        return not self.errors


def parse_float(value: str, label: str, errors: list[str]) -> float:
    try:
        parsed = float(value)
    except (TypeError, ValueError):
        errors.append(f"{label}: expected a number, got {value!r}")
        return math.nan
    if not math.isfinite(parsed):
        errors.append(f"{label}: expected a finite number, got {value!r}")
        return math.nan
    return parsed


def parse_int(value: str, label: str, errors: list[str]) -> int:
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        errors.append(f"{label}: expected an integer, got {value!r}")
        return 0
    return parsed


def round_expected_point_count(start_offset_hz: float, stop_offset_hz: float, points_per_decade: int) -> int:
    if start_offset_hz <= 0 or stop_offset_hz < start_offset_hz or points_per_decade <= 0:
        return 0
    decades = math.log10(stop_offset_hz / start_offset_hz)
    return max(1, round(decades * points_per_decade) + 1)


def normalize_warning(value: str) -> str:
    return " ".join(value.strip().lower().replace(";", " ").replace(",", " ").split())


def has_offset_below_rbw_warning(value: str) -> bool:
    normalized = normalize_warning(value)
    return any(token in normalized for token in OFFSET_BELOW_RBW_WARNINGS)


def load_phase_noise_csv(text: str) -> tuple[dict[str, str], list[dict[str, str]], list[str]]:
    errors: list[str] = []
    metadata: dict[str, str] = {}
    data_lines: list[str] = []
    in_data = False

    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if line.startswith("#"):
            continue
        if line.lower().startswith("offset_hz,"):
            in_data = True
        if in_data:
            data_lines.append(raw_line)
            continue

        cells = next(csv.reader([raw_line]))
        if len(cells) < 2:
            errors.append(f"metadata line must have key,value: {raw_line!r}")
            continue
        key = cells[0].strip()
        value = cells[1].strip()
        if key and key.lower() != "metadata_key":
            metadata[key] = value

    missing_metadata = sorted(REQUIRED_METADATA - set(metadata))
    if missing_metadata:
        errors.append(f"missing metadata keys: {', '.join(missing_metadata)}")

    if not data_lines:
        errors.append("missing data table header starting with offset_hz")
        return metadata, [], errors

    reader = csv.DictReader(io.StringIO("\n".join(data_lines)))
    if reader.fieldnames is None:
        errors.append("missing data table header")
        return metadata, [], errors

    fieldnames = {name.strip() for name in reader.fieldnames if name is not None}
    missing_columns = sorted(REQUIRED_COLUMNS - fieldnames)
    if missing_columns:
        errors.append(f"missing data columns: {', '.join(missing_columns)}")

    rows = list(reader)
    if not rows:
        errors.append("data table has no rows")

    return metadata, rows, errors


def check_density_metadata(
    metadata: dict[str, str],
    rows: list[dict[str, str]],
    errors: list[str],
    warnings: list[str],
    start_offset_hz: float,
    stop_offset_hz: float,
) -> None:
    present = DENSITY_METADATA & set(metadata)
    missing = DENSITY_METADATA - set(metadata)
    if not present:
        warnings.append(
            "missing dense-point metadata: points_per_decade, planned_points, "
            "received_points; legacy CSV accepted with reduced density validation"
        )
        return

    if missing:
        errors.append(f"missing dense-point metadata keys: {', '.join(sorted(missing))}")
        return

    points_per_decade = parse_int(
        metadata["points_per_decade"], "metadata points_per_decade", errors
    )
    planned_points = parse_int(
        metadata["planned_points"], "metadata planned_points", errors
    )
    received_points = parse_int(
        metadata["received_points"], "metadata received_points", errors
    )

    if points_per_decade <= 0:
        errors.append("metadata points_per_decade must be positive")
    if planned_points <= 0:
        errors.append("metadata planned_points must be positive")
    if received_points < 0:
        errors.append("metadata received_points must be non-negative")
    if received_points > planned_points:
        errors.append("metadata received_points must be <= planned_points")
    if received_points != len(rows):
        errors.append(
            f"metadata received_points ({received_points}) must match data rows ({len(rows)})"
        )

    expected_points = round_expected_point_count(
        start_offset_hz, stop_offset_hz, points_per_decade
    )
    if expected_points > 0 and planned_points != expected_points:
        errors.append(
            "metadata planned_points mismatch for configured density: "
            f"expected {expected_points}, got {planned_points}"
        )

    if (
        math.isclose(start_offset_hz, 1000.0)
        and math.isclose(stop_offset_hz, 1000000.0)
        and points_per_decade in {30, 60, 90}
    ):
        expected_by_preset = {30: 91, 60: 181, 90: 271}[points_per_decade]
        if planned_points != expected_by_preset:
            errors.append(
                f"1 kHz..1 MHz density preset {points_per_decade} pts/dec "
                f"must plan {expected_by_preset} points, got {planned_points}"
            )


def pick_enbw(row: dict[str, str], metadata: dict[str, str], errors: list[str], row_number: int) -> float:
    if row.get("enbw_hz", "").strip():
        return parse_float(row["enbw_hz"], f"row {row_number} enbw_hz", errors)
    if metadata.get("enbw_hz", "").strip():
        return parse_float(metadata["enbw_hz"], "metadata enbw_hz", errors)
    return parse_float(row.get("rbw_hz", ""), f"row {row_number} rbw_hz", errors)


def check_csv_text(text: str, tolerance_db: float = 0.25) -> CheckResult:
    metadata, rows, load_errors = load_phase_noise_csv(text)
    errors = list(load_errors)
    warnings: list[str] = []

    if errors:
        return CheckResult(errors=errors, warnings=warnings, row_count=len(rows))

    carrier_hz = parse_float(metadata["carrier_hz"], "metadata carrier_hz", errors)
    carrier_dbm = parse_float(metadata["carrier_dbm"], "metadata carrier_dbm", errors)
    start_offset_hz = parse_float(metadata["start_offset_hz"], "metadata start_offset_hz", errors)
    stop_offset_hz = parse_float(metadata["stop_offset_hz"], "metadata stop_offset_hz", errors)
    average_count = parse_int(metadata["average_count"], "metadata average_count", errors)
    enbw_mode = metadata["enbw_mode"].strip().lower()

    if carrier_hz <= 0:
        errors.append("metadata carrier_hz must be positive")
    if start_offset_hz <= 0:
        errors.append("metadata start_offset_hz must be positive")
    if stop_offset_hz < start_offset_hz:
        errors.append("metadata stop_offset_hz must be >= start_offset_hz")
    if average_count <= 0:
        errors.append("metadata average_count must be positive")
    if enbw_mode == "estimated":
        warnings.append("ENBW is estimated from RBW; result should remain marked UNCAL/Estimated ENBW")
    elif enbw_mode not in {"calibrated", "measured"}:
        warnings.append(f"unknown enbw_mode {metadata['enbw_mode']!r}; treating ENBW source cautiously")

    check_density_metadata(
        metadata,
        rows,
        errors,
        warnings,
        start_offset_hz,
        stop_offset_hz,
    )

    previous_offset = -math.inf
    valid_count = 0

    for index, row in enumerate(rows, start=1):
        offset_hz = parse_float(row.get("offset_hz", ""), f"row {index} offset_hz", errors)
        raw_dbc_hz = parse_float(row.get("raw_dbc_hz", ""), f"row {index} raw_dbc_hz", errors)
        avg_dbc_hz = parse_float(row.get("avg_dbc_hz", ""), f"row {index} avg_dbc_hz", errors)
        noise_power_dbm = parse_float(row.get("noise_power_dbm", ""), f"row {index} noise_power_dbm", errors)
        rbw_hz = parse_float(row.get("rbw_hz", ""), f"row {index} rbw_hz", errors)
        valid = parse_int(row.get("valid", ""), f"row {index} valid", errors)
        warning_text = row.get("warning", "")
        enbw_hz = pick_enbw(row, metadata, errors, index)

        if offset_hz <= 0:
            errors.append(f"row {index}: offset_hz must be positive")
        if offset_hz < previous_offset:
            errors.append(f"row {index}: offset_hz must be monotonically increasing")
        previous_offset = offset_hz

        if offset_hz < start_offset_hz or offset_hz > stop_offset_hz:
            errors.append(
                f"row {index}: offset_hz {offset_hz:g} outside metadata range "
                f"{start_offset_hz:g}..{stop_offset_hz:g}"
            )
        if rbw_hz <= 0:
            errors.append(f"row {index}: rbw_hz must be positive")
        if enbw_hz <= 0:
            errors.append(f"row {index}: enbw_hz must be positive")
        if valid not in (0, 1):
            errors.append(f"row {index}: valid must be 0 or 1")

        if valid == 1:
            valid_count += 1

        if math.isfinite(noise_power_dbm) and math.isfinite(carrier_dbm) and math.isfinite(enbw_hz) and enbw_hz > 0:
            expected_raw = noise_power_dbm - carrier_dbm - 10.0 * math.log10(enbw_hz)
            if abs(raw_dbc_hz - expected_raw) > tolerance_db:
                errors.append(
                    f"row {index}: raw_dbc_hz mismatch, expected {expected_raw:.3f}, "
                    f"got {raw_dbc_hz:.3f}"
                )

        if not math.isfinite(avg_dbc_hz):
            errors.append(f"row {index}: avg_dbc_hz must be finite")

        if offset_hz < rbw_hz and valid == 1 and not has_offset_below_rbw_warning(warning_text):
            errors.append(
                f"row {index}: offset_hz < rbw_hz must be invalid or carry Offset < RBW warning"
            )

    if valid_count == 0:
        errors.append("data table has no valid points")

    return CheckResult(errors=errors, warnings=warnings, row_count=len(rows))


def print_result(result: CheckResult) -> None:
    status = "PASS" if result.ok else "FAIL"
    print(f"{status}: checked {result.row_count} phase-noise CSV rows")
    for warning in result.warnings:
        print(f"WARN: {warning}")
    for error in result.errors:
        print(f"ERROR: {error}")


def build_self_test_csv() -> str:
    return """metadata_key,metadata_value
carrier_hz,100000000
carrier_dbm,0
start_offset_hz,1000
stop_offset_hz,1000000
average_count,10
enbw_mode,estimated
calibration_state,UNCAL
points_per_decade,60
planned_points,181
received_points,3

offset_hz,raw_dbc_hz,avg_dbc_hz,noise_power_dbm,rbw_hz,valid,warning
1000,-110.0,-111.0,-80.0,1000,1,Estimated ENBW
10000,-120.0,-121.0,-80.0,10000,1,Estimated ENBW
100000,-130.0,-131.0,-90.0,10000,1,Estimated ENBW
"""


def run_self_test() -> int:
    good = check_csv_text(build_self_test_csv())
    if not good.ok:
        print("FAIL: self-test good CSV did not pass")
        print_result(good)
        return 1

    bad_csv = build_self_test_csv().replace("10000,-120.0", "10000,-100.0")
    bad = check_csv_text(bad_csv)
    if bad.ok:
        print("FAIL: self-test bad CSV unexpectedly passed")
        print_result(bad)
        return 1

    print("PASS: result checker self-test passed")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate PuSuSA phase-noise CSV exports."
    )
    parser.add_argument("csv_path", nargs="?", help="CSV export to validate")
    parser.add_argument(
        "--tolerance-db",
        type=float,
        default=0.25,
        help="Allowed dB mismatch when recomputing raw_dbc_hz, default 0.25.",
    )
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="Run built-in pass/fail samples without reading a file.",
    )
    args = parser.parse_args()

    if args.self_test:
        return run_self_test()

    if not args.csv_path:
        parser.error("csv_path is required unless --self-test is used")

    path = Path(args.csv_path)
    try:
        text = path.read_text(encoding="utf-8-sig")
    except OSError as exc:
        print(f"FAIL: could not read {path}: {exc}", file=sys.stderr)
        return 1

    result = check_csv_text(text, tolerance_db=args.tolerance_db)
    print_result(result)
    return 0 if result.ok else 1


if __name__ == "__main__":
    sys.exit(main())
