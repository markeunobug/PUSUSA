# PL DDC / Decimation Architecture Plan

Date: 2026-06-04

Active engineering workspace:

`C:\learning\pusu_V2\code\pusu_20260604`

## 1. Background

The current PuSuSA sweep DSP path captures `LTC2208` ADC samples through AXI DMA into PS memory, then performs DDC, RBW decimation, FIR filtering, and power calculation in firmware.

Recent 10 kHz RBW diagnosis showed:

- RF front-end, 40 MHz IF, and ADC raw data are usable.
- UART and Flutter display are not the primary cause of the abnormal result.
- DDC / NCO frequency mapping is plausible.
- The abnormal residual appears after DDC, especially in the 10 kHz FIR-decimation / RBW path.
- Continuous synthetic signals are filtered correctly, while block-reset synthetic signals reproduce the abnormal residual.

Current leading root cause:

The PS-side RBW decimator assumes a continuous stream, but the real DMA rearm path supplies data in blocks. If those DMA blocks are not sample-continuous, or have phase/time discontinuity, a long FIR decimator carrying state across block boundaries convolves across invalid boundaries and leaks energy into the RBW passband.

Therefore, the production fix should move the fragile streaming DSP section into PL, where the ADC stream can be processed continuously before DMA packet boundaries.

## 2. Design Goal

Build a PL-side DDC / decimation path that makes RBW measurement trustworthy by preserving stream continuity.

Primary goals:

- Move DDC and decimation from PS block processing to PL continuous streaming.
- First prove the fix on 10 kHz RBW.
- Preserve enough debug visibility to compare old PS DSP and new PL DSP.
- Keep PS responsible for sweep control, LO programming, calibration, UART protocol, and host communication.
- Design the path so future PL-side power accumulation and RBW ENBW calibration can be added cleanly.

Non-goals for the first implementation:

- Do not redesign the RF front-end.
- Do not change the host UI as part of the first PL verification.
- Do not implement all RBW modes at once.
- Do not rely on CIC as the final trusted RBW filter unless its droop, aliasing, and ENBW are explicitly compensated and verified.

## 3. Existing System Constraints

Relevant current constants:

| Item | Current value | Source |
|---|---:|---|
| ADC sample rate | 130 MSPS | `ADC_SAMPLE_RATE_HZ` |
| IF2 center | 40 MHz | `DDC_IF_HZ` |
| Current DMA frame | 4096 samples | `FFT_SIZE` |
| ADC stream width | signed 16 bit | `LTC2208.v` |
| Current DMA mode | AXI DMA S2MM simple transfer | Vitis app |
| Current DMA length limit | 65535 bytes | BSP / `DMA_SIMPLE_MAX_BYTES` |

Important current PL point:

`LTC2208.v` already converts the ADC LVDS data into an AXI4-Stream style 16-bit signed stream. The new PL DSP should be inserted between this ADC stream and the AXI DMA input.

Current simplified path:

```text
LTC2208 ADC
-> LTC2208.v AXI4-Stream, signed int16
-> AXI Stream FIFO / AXI DMA
-> PS DDR
-> PS DDC / RBW / power
-> UART / host
```

Target path:

```text
LTC2208 ADC
-> LTC2208.v AXI4-Stream, signed int16
-> PL DDC
-> PL multi-stage decimation
-> PL RBW filter / optional PL power accumulator
-> AXI DMA or AXI-Lite result
-> PS sweep control / calibration / UART / host
```

## 4. Recommended Architecture

The architecture should be staged. Each stage must have a standalone hardware test and a comparison with the current firmware path.

### 4.1 Stage D0: Offline Fixed-Point Reference

Before editing the block design, build a fixed-point reference model.

Inputs:

- Synthetic ADC tone at 40.000 MHz.
- Synthetic ADC tone at 40.100 MHz.
- ILA-exported ADC data if available.
- Optional real ADC captures from prior zero-span tests.

Model chain:

```text
real int16 ADC
-> NCO at 40 MHz
-> complex mixer
-> multi-stage FIR decimation
-> 10 kHz RBW FIR
-> power / dBFS
```

Acceptance:

- 40.000 MHz IF maps to near DC and remains high.
- 40.100 MHz IF maps to +100 kHz and is rejected by the 10 kHz RBW path.
- Fixed-point result matches floating-point result within an agreed tolerance.

Recommended initial tolerance:

| Metric | Target |
|---|---:|
| DDC frequency placement | within one output-bin equivalent |
| 40.000 MHz amplitude error | <= 1 dB before calibration |
| 40.100 MHz rejection improvement | at least 30 dB better than current broken 10K path |
| Fixed vs float power error | <= 0.5 dB for the controlled test tones |

### 4.2 Stage D1: PL DDC Debug Path

Add only PL DDC first. Do not replace the full measurement path yet.

Block:

```text
ADC int16
-> DDS/NCO 40 MHz
-> signed mixer
-> complex I/Q stream
-> debug capture path
```

Implementation recommendation:

- Use Vivado DDS Compiler for the first version.
- Use explicit signed fixed-point multiplier stages.
- Keep enough internal width after mixing, for example 24 to 32 bits before later scaling.
- Add ILA probes at:
  - ADC input sample
  - NCO sin/cos
  - mixer I/Q
  - optional valid/sample counter

Acceptance:

| Test | Expected DDC result |
|---|---|
| RF fixed 1 GHz, sweep center 1 GHz | IF2 40.000 MHz -> DDC near DC |
| RF fixed 1 GHz, sweep center 999.900 MHz | IF2 40.100 MHz -> DDC near +100 kHz |

This stage proves the PL NCO and frequency mapping. It does not yet prove RBW.

### 4.3 Stage D2: PL Continuous Decimation to 1 MSPS

For the first 10 kHz RBW fix, output a continuous 1 MSPS complex stream.

Recommended decimation chain:

| Stage | Input rate | Decim | Output rate | Suggested filter |
|---|---:|---:|---:|---|
| D2.1 | 130 MSPS | 2 | 65 MSPS | Halfband FIR or FIR Compiler |
| D2.2 | 65 MSPS | 5 | 13 MSPS | FIR decimator |
| D2.3 | 13 MSPS | 13 | 1 MSPS | FIR decimator |

Total decimation: `2 * 5 * 13 = 130`.

Reason for 1 MSPS output:

- It is much lower than 130 MSPS, so PS and DMA pressure drop sharply.
- It still preserves +/-500 kHz baseband bandwidth.
- The important 40.100 MHz test appears as +100 kHz after DDC, so it remains visible and can be rejected by the 10 kHz RBW filter.
- It avoids the old narrow-output-rate alias geometry where nearby offsets fold back into the RBW passband.

The filters in D2 are anti-alias filters, not the RBW definition itself. The RBW definition should still be checked by final ENBW.

### 4.4 Stage D3: PL 10 kHz RBW Filter and Power Accumulation

The preferred production direction is to continue past decimation and do the 10 kHz RBW FIR and power accumulation inside PL.

Target:

```text
1 MSPS complex I/Q
-> 10 kHz RBW FIR
-> transient skip / valid gating
-> |I|^2 + |Q|^2
-> accumulation over configured observation window
-> result register or compact DMA packet
```

Why PL-side power is preferred:

- It avoids sending long I/Q streams back to PS.
- It avoids PS-side block-boundary filtering hazards.
- It makes each sweep point a compact result instead of a large sample transfer.
- It is closer to a real spectrum analyzer RBW detector chain.

Initial result format:

| Field | Suggested type | Meaning |
|---|---|---|
| `valid` | 1 bit | result ready |
| `point_index` | uint16 or uint32 | sweep point index |
| `rbw_mode` | uint8 | RBW mode |
| `sample_count` | uint32 | valid power samples accumulated |
| `power_accum` | uint64 | accumulated linear power |
| `debug_peak_bin` | optional | debug only |
| `overflow_flags` | uint32 | ADC/FIR/accumulator saturation flags |

For the first implementation, either AXI DMA compact result packets or AXI-Lite readable registers are acceptable. AXI-Lite is simpler for one result per sweep point; DMA is better if later returning dense traces or I/Q debug data.

## 5. Data Width and Fixed-Point Plan

Initial conservative fixed-point choices:

| Signal | Suggested width | Note |
|---|---:|---|
| ADC input | signed 16 bit | from `LTC2208.v` |
| NCO sin/cos | signed 16 to 18 bit | DDS Compiler output |
| Mixer product | signed 32 to 36 bit | keep guard bits |
| Decimator internal | signed 24 to 32 bit | scale after each stage |
| RBW FIR output | signed 24 to 32 bit | avoid premature truncation |
| Power | unsigned 48 to 64 bit | `I^2 + Q^2` |
| Accumulator | unsigned 64 bit or wider if needed | depends on observation count |

Rules:

- Saturation flags must be observable.
- Scaling must be documented stage by stage.
- The same scaling constants must be used by offline model and RTL.
- Do not normalize power in multiple hidden places. Prefer one explicit conversion from linear accumulator to dBFS/dBm in PS.

## 6. Control Interface

Minimum registers for the first PL DSP IP:

| Register | Direction | Purpose |
|---|---|---|
| `CTRL.enable` | PS -> PL | enable PL DSP path |
| `CTRL.reset_state` | PS -> PL | reset NCO/filter/accumulator state |
| `CTRL.mode` | PS -> PL | raw ADC / PL DDC debug / PL decim / PL power |
| `NCO.phase_inc` | PS -> PL | programmable DDC frequency, default 40 MHz |
| `RBW.mode` | PS -> PL | first version only needs 10 kHz |
| `OBS.target_count` | PS -> PL | power samples per point |
| `STATUS.valid` | PL -> PS | result ready |
| `STATUS.overflow` | PL -> PS | saturation / ADC overflow / FIFO drop |
| `RESULT.power_accum` | PL -> PS | linear accumulated power |
| `RESULT.sample_count` | PL -> PS | valid accumulated samples |

The first version may hard-code `NCO.phase_inc` for 40 MHz, but the register should exist in the architecture so later center-frequency experiments do not require rebuilding the bitstream.

## 7. Debug and Validation Hooks

Required ILA probes:

| Probe point | Purpose |
|---|---|
| ADC raw sample | confirm input data and overflow |
| DDC I/Q | confirm 40.000 MHz -> DC and 40.100 MHz -> +100 kHz |
| Decimator output valid | confirm exact decimation schedule |
| Decimator I/Q output | inspect alias and saturation |
| RBW FIR output | confirm out-of-band rejection |
| Power accumulator | confirm observation window and reset timing |
| FIFO/DMA ready-valid | detect dropped or stalled output |

Required software debug:

- Keep a runtime switch between old PS path and new PL path.
- Add a command or profile extension that reports PL path mode, sample count, overflow flags, and raw power accumulator.
- Keep the existing serial diagnostic script as the first host-side verification tool.

## 8. Verification Plan

### 8.1 Bench Tests

Use the same zero-span test style that exposed the current problem.

Signal source:

- Fixed RF input: 1.000000 GHz.
- Power: start from a safe level such as -30 dBm.
- RF front-end: mixer path, LNA bypass, attenuation controlled and recorded.

Test cases:

| Case | Sweep center | IF2 target | Expected |
|---|---:|---:|---|
| A | 1.000000 GHz | 40.000 MHz | high measured power |
| B | 0.999900 GHz | 40.100 MHz | strong DDC +100 kHz before RBW, low power after 10K RBW |
| C | 1.000100 GHz | 39.900 MHz | symmetric negative-offset check |
| D | no input | noise floor and spur check |

Acceptance for the first 10K proof:

- Case A remains measurable and stable.
- Case B no longer shows the current high residual near `-49 dBm`.
- Case B should improve by at least 30 dB relative to the current broken PL-disabled result.
- ILA and serial/debug output must agree on where the signal exists in the chain.

### 8.2 Regression Tests

After 10K passes:

- Verify 1 MHz RBW still works through the old path.
- Verify raw ADC direct IF debug mode still works if it is enabled.
- Verify sweep point counts and UART packet format are not broken.
- Verify amplitude calibration can be applied to the PL result path with a clear calibration flag.

## 9. Implementation Phases

| Phase | Deliverable | Exit criterion |
|---|---|---|
| D0 | Offline fixed-point model | 40.000 / 40.100 MHz cases match float model |
| D1 | PL DDC debug IP inserted | ILA proves DC / +100 kHz mapping |
| D2 | PL decimation to 1 MSPS | I/Q output is continuous and alias-safe for +100 kHz |
| D3 | PL 10K RBW + power | zero-span 40.100 MHz residual is fixed |
| D4 | Firmware integration switch | host can compare old PS path and new PL path |
| D5 | Extend RBW modes | ENBW-calibrated parameters for 1K to 1M |

Recommended immediate next step:

Dispatch two bounded tasks:

1. Offline DSP task: build D0 model and choose fixed-point filter coefficients for 10K validation.
2. Vivado architecture task: inspect `system.bd`, identify the exact insertion point between `LTC2208_0` and `axi_dma_0`, and propose the minimum block-design changes for D1.

## 10. Main Risks

| Risk | Impact | Mitigation |
|---|---|---|
| ADC stream backpressure drops samples | corrupts DSP continuity | do not let DMA readiness control ADC capture; process continuously and buffer only outputs |
| NCO phase increment mismatch | wrong frequency mapping | D1 ILA test with 40.000 and 40.100 MHz IF |
| Fixed-point truncation or overflow | false amplitude / leakage | wide internal paths and observable saturation flags |
| FIR resource usage too high | timing/resource failure | use staged decimation and FIR Compiler; start with 10K only |
| PL and PS paths use different scaling | confusing dBm results | keep one explicit dBFS/dBm conversion point in PS |
| Debug hooks disturb timing | unstable implementation | keep D1/D2 debug builds separate from final D3 build if needed |

## 11. Design Decision Summary

The recommended production direction is:

```text
ADC stream continuous in PL
-> PL DDC
-> PL multi-stage FIR decimation
-> PL RBW FIR
-> PL power accumulation
-> PS reads compact result
```

This directly addresses the diagnosed failure mode. Reducing PS-side decimation or resetting FIR state per DMA block can improve symptoms, but it does not fully remove the root problem. A continuous PL streaming chain is the cleaner architecture and should become the baseline for future trusted RBW work.

