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

- `C:\learning\pusu_V2\code\pusu_test\vitis_20260409\pusu_20260409`

Main source directory:

- `C:\learning\pusu_V2\code\pusu_test\vitis_20260409\pusu_20260409\code`

Key files:

- `main.c`
- `app_config.h`
- `device_protocol.c/.h`
- `dma_capture.c/.h`
- `signal_processing.c/.h`
- `lo_control.c/.h`
- `sweep_plan.c/.h`
- `sweep_engine.c/.h`

## 4. Current processing mode

The main path is now **sweep mode**, not FFT upload.

Per sweep point:

1. set `LO1`
2. wait for lock
3. capture one DMA frame
4. DDC around `40 MHz`
5. apply RBW filtering
6. compute time-domain power:
   - `mean(I^2 + Q^2)`
7. convert to approximate `dBm`

Current `GET_SPECTRUM` returns sweep trace data, not FFT bins.

## 5. Current sweep implementation state

- sweep is still **blocking/synchronous**
- host sends `GET_SPECTRUM`
- lower machine runs the whole sweep in that request path
- then returns one trace

Current bring-up limitation:

- sweep point count is temporarily forced to:
  - `32 points`

This is for bring-up stability before moving to a non-blocking sweep state machine.

## 6. Power calculation model

Current power extraction does **not** use per-point FFT.

Used method:

- `DDC -> RBW low-pass -> mean(I^2 + Q^2)`

Then:

- power -> `dBFS`
- `dBFS` -> approximate ADC-input `dBm`

This is the intended main sweep power path.

## 7. Critical platform note

On the current new platform, DMA only works when software forces:

- `RX_INTR_ID = 62`

This is a confirmed working workaround and must not be forgotten.

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

Sweep execution is triggered by:

- `GET_SPECTRUM`

## 10. Host application

Flutter host project:

- `C:\learning\pusu_V2\host_computer\flutter_hello`

Correct runtime executable:

- `C:\learning\pusu_V2\host_computer\flutter_hello\build\windows\x64\install_bundle\flutter_hello.exe`

Current source defaults are intended to be:

- `Start = 50 MHz`
- `Stop = 1.5 GHz`

## 11. Current priority

Main next-step focus:

1. verify `32-point` sweep stability
2. verify lock / timing behavior during sweep
3. later convert sweep from blocking mode to a non-blocking state machine

## 12. Deferred host behavior change

Planned but not implemented yet:

- when host frequency parameters change during continuous sweep:
  - automatically stop the current continuous sweep
  - send the updated frequency configuration
  - restart continuous sweep after configuration has been applied
