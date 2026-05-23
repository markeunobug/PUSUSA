# PuSuSA Project Context (Compressed)

## 1. System architecture

Current signal chain:

`RF -> LNA(bypassable) -> attenuator -> ADL5801 -> filter -> ADL5801 -> filter -> AD8370 -> LTC2208 -> Zynq`

Notes:

- two `LMX2572` devices, one per mixer
- `AD8370` is used as IF VGA
- `LTC2208` is the ADC
- Zynq handles digital processing and protocol

## 2. Frequency plan

- first IF:
  - `IF1 = 2.180 GHz`
- first LO:
  - `LO1 = RF + 2.180 GHz`
  - therefore `0 ~ 1.5 GHz` input maps to `2.18 ~ 3.68 GHz`
- second LO:
  - `LO2 = 2.220 GHz`
- second IF:
  - `IF2 = 40 MHz`

So the ADC samples a fixed:

- `40 MHz IF`

## 3. Lower-machine active software

Primary Vitis application:

- `C:\learning\pusu_V2\code\pusu_20260516\vitis\pusu_20260516`

Main source directory:

- `C:\learning\pusu_V2\code\pusu_20260516\vitis\pusu_20260516\src`

Active Vivado project:

- `C:\learning\pusu_V2\code\pusu_20260516\pusu_test.xpr`

Older `code\pusu_test\vitis_20260409` and `code\pusu_test\vitis` trees are legacy/reference unless explicitly requested.

Key files:

- `main.c`
- `app_config.h`
- `device_protocol.c/.h`
- `dma_capture.c/.h`
- `signal_processing.c/.h`
- `lo_control.c/.h`
- `sweep_plan.c/.h`
- `sweep_engine.c/.h`
- `profile_timer.c/.h` (optional coarse sweep profiling, gated by `SWEEP_PROFILE_ENABLE`)

## 4. Current processing mode

The main path is now **sweep mode**, not FFT upload.

Per sweep point:

1. set `LO1`
2. wait for lock
3. capture/rearm DMA until enough decimated data has accumulated
4. DDC around `40 MHz`
5. apply CIC/RBW filtering
6. compute time-domain power:
   - `mean(I^2 + Q^2)`
7. convert to approximate `dBm`

Current `GET_SPECTRUM` returns sweep trace data, not FFT bins.

## 5. Current sweep implementation state

- sweep engine is a non-blocking state machine serviced from the main loop
- host sends `GET_SPECTRUM` / `START_SWEEP`
- lower machine streams spectrum points as `SPECTRUM_DATA`
- host requests coarse profiling after sweep completion with `GET_PROFILE(0x0E)`
- lower machine replies with `PROFILE_DATA(0x85)`

## 6. Power calculation model

Current power extraction does **not** use per-point FFT.

Used method:

- `DDC -> RBW low-pass -> mean(I^2 + Q^2)`

Then:

- power -> `dBFS`
- `dBFS` -> approximate ADC-input `dBm`

This is the intended main sweep power path.

## 7. Critical platform note

On the 2026-05-16 platform, DMA IRQ is exported by the BSP:

- `RX_INTR_ID = XPAR_FABRIC_AXI_DMA_0_S2MM_INTROUT_INTR`

The hardware connects `axi_dma_0/s2mm_introut` to `xlconcat_0/In0`, mapping to `IRQ_F2P[0]`.

## 8. Lock indication

- `P19` is connected through EMIO
- it is used as a PLL lock indicator
- expected behavior:
  - power-up self-test flash once
  - stay on after lock succeeds

## 9. Serial and protocol

Validated serial link:

- `COM12`
- `921600`

Main protocol commands:

- `SET_FREQ`
- `SET_BW`
- `SET_SWEEP`
- `GET_SPECTRUM`
- `GET_STATUS`
- `GET_PROFILE`

Sweep execution is triggered by:

- `GET_SPECTRUM`

Coarse profiling:

- enabled by setting `SWEEP_PROFILE_ENABLE` to `1` in active `app_config.h`
- disabled by default for minimal hot-path risk
- reports point total, set LO1, wait lock, DMA reset/start/wait, DMA accumulation, measurement, UART emit, and DMA rearm count

## 10. Host application

Flutter host project:

- `C:\learning\pusu_V2\host_computer\flutter_pusu`

Correct runtime executable:

- `C:\learning\pusu_V2\host_computer\flutter_pusu\build\windows\x64\install_bundle\flutter_pusu.exe`

`host_computer\flutter_hello` is older/reference.

Current source defaults are intended to be:

- `Start = 50 MHz`
- `Stop = 1.5 GHz`

## 11. Current priority

Main next-step focus:

1. enable `SWEEP_PROFILE_ENABLE` temporarily and rebuild lower-machine firmware
2. compare RBW 1M / 30K / 10K timing in the bottom status bar
3. use the coarse profile to decide whether to optimize DMA accumulation, measurement, LO wait, or UART streaming first

## 12. Deferred host behavior change

Planned but not implemented yet:

- when host frequency parameters change during continuous sweep:
  - automatically stop the current continuous sweep
  - send the updated frequency configuration
  - restart continuous sweep after configuration has been applied
