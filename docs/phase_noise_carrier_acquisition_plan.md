# Phase Noise Carrier Acquisition Plan

## 1. Background

The dedicated phase-noise page can now receive real `PHASE_NOISE_DATA(0x86)` and
`PHASE_NOISE_STATUS(0x87)` frames. The next blocker is measurement quality:

- Spectrum mode shows the 1 GHz carrier at about `-15 dBm`.
- Phase-noise mode reports carrier level around `-34 dBm`.
- That 19 dB carrier-reference error directly shifts `dBc/Hz` results.

The current firmware carrier acquisition is too narrow:

- Auto mode only checks nominal carrier `-1 kHz`, nominal, and `+1 kHz`.
- Manual mode effectively measures only the nominal carrier point.
- Carrier search uses `1 kHz RBW`, so even a small frequency error can attenuate
  the carrier measurement.

The goal of this round is to make carrier acquisition explicit, configurable,
observable, and strict enough that invalid phase-noise data is not treated as
valid.

## 2. Active paths

- Host app: `host_computer/flutter_pusu`
- Firmware: `code/pusu_20260516/vitis/pusu_20260516/src`
- Protocol doc: `docs/phase_noise_protocol.md`

Do not modify:

- `host_computer/flutter_hello`
- `code/pusu_test`
- Vivado/Vitis generated output, build products, bitstreams, XSA archives

## 3. Requirements

### 3.1 Firmware carrier acquisition

Replace the current fixed 3-point `nominal +/- 1 kHz` search with a staged
search:

1. Coarse search around `nominal_carrier_hz`.
2. Fine search around the strongest coarse candidate.
3. Use the strongest measured candidate as:
   - `measured_carrier_hz`
   - `carrier_level_dbm`
   - `initial_delta_hz = measured - nominal` for host display

Recommended first implementation:

- Configurable search span from host.
- Default search span: `100 kHz`.
- Coarse step: `10 kHz` or `search_span / 20`, whichever is practical.
- Fine span: one coarse step around the best candidate.
- Fine step: `1 kHz`.
- Keep the state machine non-blocking.

The carrier is valid only if:

- `best_carrier_level_dbm >= minimum_carrier_level_dbm`
- RF target stays in valid RF range
- LO lock and DMA measurement succeed

If carrier is not valid:

- set `PN_ERR_CARRIER_NOT_FOUND` or `PHASE_NOISE_WARN_CARRIER_LEVEL_LOW`
- clear `PHASE_NOISE_DATA_FLAG_PHASE_NOISE_VALID`
- do not let the host draw invalid phase-noise points as a normal trace

### 3.2 Protocol compatibility

Keep `SET_PHASE_NOISE_CONFIG(0x0F)` payload length at `36B` for this round.
Use the existing 4 reserved bytes:

| Offset | Field | Type | Endian | Unit | Notes |
| --- | --- | --- | --- | --- | --- |
| 32 | `carrier_search_span_khz` | `uint16` | LE | kHz | `0` means firmware default |
| 34 | `minimum_carrier_level_dbm_i8` | `int8` | - | dBm | signed integer threshold |
| 35 | `reserved` | `uint8` | - | - | must be `0` |

Rationale:

- This preserves the v1 frame length and parser shape.
- `uint16 kHz` supports up to 65 MHz search span, enough for current needs.
- `int8 dBm` is enough for trigger thresholds such as `-80..0 dBm`.

### 3.3 Host controls

Expose carrier acquisition controls in the Phase Noise carrier panel:

- Search span: numeric input with units, default `100 kHz`.
- Minimum carrier level / trigger level: numeric input in dBm, default `-50 dBm`.

Behavior:

- Auto mode uses current center frequency as nominal search center.
- Manual mode uses the carrier input as nominal search center, but still allows
  searching within the configured span.
- The status bar should continue showing nominal carrier, measured carrier,
  measured level, initial delta, drift, warning, and progress.

### 3.4 Validation expectations

With a known 1 GHz carrier:

- Spectrum-mode marker and phase-noise measured carrier should be close after
  calibration. A 19 dB mismatch is not acceptable for normal operation.
- If the phase-noise engine cannot find a carrier above threshold, it should
  clearly report low carrier / not found instead of drawing a plausible-looking
  curve.
- Host CSV should keep exporting carrier metadata and warnings.

## 4. Subtask split

### A. Firmware carrier acquisition

Owned files:

- `code/pusu_20260516/vitis/pusu_20260516/src/phase_noise_engine.c`
- `code/pusu_20260516/vitis/pusu_20260516/src/phase_noise_engine.h`
- possible small protocol decode update in `device_protocol.c`

Deliverables:

- Parse new config fields into `phase_noise_config_t`.
- Implement configurable coarse/fine carrier search.
- Apply minimum carrier level threshold.
- Keep `PHASE_NOISE_DATA(0x86)` and `PHASE_NOISE_STATUS(0x87)` payload lengths
  unchanged.
- Run ARM syntax check if toolchain is available.

### B. Host protocol and UI

Owned files:

- `host_computer/flutter_pusu/lib/phase_noise_models.dart`
- `host_computer/flutter_pusu/lib/serial_protocol.dart`
- `host_computer/flutter_pusu/lib/main.dart`
- `host_computer/flutter_pusu/test/phase_noise_protocol_test.dart`

Deliverables:

- Add `carrierSearchSpanHz` and `minimumCarrierLevelDbm` to
  `PhaseNoiseConfig`.
- Encode the new fields at payload offsets `32..35`.
- Add carrier panel controls.
- Preserve nominal carrier handling for auto/manual modes.
- Run Dart analyzer and relevant tests.

### C. Docs and validation

Owned files:

- `docs/phase_noise_protocol.md`
- `docs/phase_noise_validation.md`
- `tools/phase_noise_protocol_smoke_test.py`
- optional test updates

Deliverables:

- Document reserved field reuse.
- Update smoke test to dump/check default `carrier_search_span_khz=100` and
  `minimum_carrier_level_dbm_i8=-50`.
- Add validation checklist comparing spectrum marker carrier level with
  phase-noise carrier acquisition result.

## 5. Risks

- A wider carrier search increases startup time before the first phase-noise
  point.
- Searching with too narrow RBW can still underestimate a drifting carrier.
- Searching with too wide RBW improves capture but changes measured carrier
  power semantics. If this becomes a problem, add a separate carrier-search RBW
  mode in a later round.
- Absolute dBm agreement still depends on amplitude calibration; this round only
  makes the carrier reference search less fragile and more observable.

## 6. Recommended checks

Host:

```powershell
C:\learning\tools\flutter\bin\cache\dart-sdk\bin\dart.exe analyze host_computer\flutter_pusu\lib host_computer\flutter_pusu\test
C:\learning\tools\flutter\bin\flutter.bat test test\phase_noise_protocol_test.dart test\phase_noise_chart_test.dart test\phase_noise_processor_test.dart
```

Protocol smoke:

```powershell
python tools\phase_noise_protocol_smoke_test.py --dump-hex
python -m py_compile tools\phase_noise_protocol_smoke_test.py
```

Firmware:

```powershell
& 'C:\software\Xilinx\Vitis\2021.1\gnu\aarch32\nt\gcc-arm-none-eabi\bin\arm-none-eabi-gcc.exe' -mcpu=cortex-a9 -mfpu=vfpv3 -mfloat-abi=hard -Icode\pusu_20260516\vitis\pusu_20260516\src -Icode\pusu_20260516\vitis\pusu_20260516\mylib -Icode\pusu_20260516\vitis\pusu_20260516\mylib\dsp -Icode\pusu_20260516\vitis\system_wrapper\export\system_wrapper\sw\system_wrapper\standalone_ps7_cortexa9_0\bspinclude\include -Wall -Werror=implicit-function-declaration -O0 -fsyntax-only code\pusu_20260516\vitis\pusu_20260516\src\phase_noise_plan.c code\pusu_20260516\vitis\pusu_20260516\src\phase_noise_engine.c code\pusu_20260516\vitis\pusu_20260516\src\device_protocol.c code\pusu_20260516\vitis\pusu_20260516\src\main.c code\pusu_20260516\vitis\pusu_20260516\src\signal_processing.c code\pusu_20260516\vitis\pusu_20260516\src\sweep_plan.c
```
