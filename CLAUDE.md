# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

PuSuSA is a spectrum analyzer. The signal chain is:
`RF → LNA → attenuator → ADL5801(mixer1) → filter → ADL5801(mixer2) → filter → AD8370(VGA) → LTC2208(ADC) → Zynq`

Two LMX2572 PLLs generate LO1 and LO2. The Zynq-7000 ARM core runs bare-metal C firmware that controls the RF frontend, captures ADC data via DMA, performs DDC + RBW filtering + time-domain power measurement, and communicates with a host PC over UART.

## Repository structure

| Directory | Purpose |
|---|---|
| `code/pusu_20260516/` | **Active Vivado/Vitis hardware + firmware tree** |
| `code/pusu_20260516/pusu_test.xpr` | **Active Vivado hardware project** |
| `code/pusu_20260516/vitis/pusu_20260516/src/` | **Active lower-machine firmware** (C, bare-metal on Zynq) |
| `code/pusu_20260516/vitis/pusu_20260516/mylib/` | CMSIS-DSP library headers/libraries used by firmware |
| `code/pusu_test/` | Legacy/reference Vivado + Vitis trees, including `vitis_20260409` |
| `code/stm32f1/` | STM32F1 clock source firmware — separate subsystem |
| `host_computer/flutter_pusu/` | **Active Flutter host app** (spectrum analyzer UI) |
| `host_computer/flutter_hello/` | Older Flutter app — reference only |
| `host_computer/参考下位机代码/` | Reference STM32 USB code for LMX2592 driver |
| `tools/` | Python serial protocol smoke tests |
| `docs/` | Architecture diagrams and protocol documentation |
| `CMSIS-DSP-main/` | CMSIS-DSP library source (used by firmware DSP) |

## Lower-machine firmware architecture

Entry: `main.c`. Init sequence:
1. `init_platform()` — interrupts, UART, GPIO
2. `ad8370_init()` — VGA control
3. `lock_indicator_init()` — PLL lock detect via EMIO (P19)
4. `lo_control_init()` — LMX2572 PLL init
5. `device_protocol_init()` — UART protocol engine
6. `signal_processing_init()` — DDC + RBW filter init
7. `sweep_engine_init()` — sweep state machine init
8. `dma_capture_init()` + `dma_capture_start()` — DMA from ADC

Main loop polls `device_protocol_poll()` for incoming UART commands, then services the sweep engine if active, or processes DMA frames through `signal_processing_process_frame()`.

**Key modules:**
- `device_protocol.c` — Binary frame protocol (0xAA/0x55 framing, CRC16 Modbus). Parses incoming commands, dispatches to providers registered via function pointers (`spectrum_provider`, `status_provider`, `sweep_control`, `rf_frontend_control`). Sends ACK/spectrum/status/RF frontend/profile responses.
- `sweep_engine.c` — Non-blocking sweep state machine. Per point: set LO1 → wait lock → arm/rearm DMA → wait frame(s) → accumulate DMA data → measure power (DDC/CIC/RBW filtering → mean(I² + Q²) → dBFS → dBm) → apply amplitude correction → stream one point.
- `sweep_plan.c` — Computes sweep plan from frequency config: start/stop/step frequencies based on RBW.
- `dma_capture.c` — AXI DMA S2MM capture from LTC2208 ADC. Uses interrupt-driven transfer completion.
- `signal_processing.c` — DDC around 40 MHz IF, RBW low-pass filtering (5 preset modes: 10k/30k/100k/300k/1M Hz), time-domain power computation.
- `lo_control.c` — Sets LO1 (RF + 2.180 GHz) and LO2 (fixed 2.220 GHz) on LMX2572 PLLs. Waits for lock via EMIO.
- `lmx2572.c` — Register-level SPI bit-banging for LMX2572.
- `ad8370.c` — AD8370 VGA gain control via GPIO (3-wire serial).

## Frequency plan

| Parameter | Value |
|---|---|
| LO1 | RF + 2.180 GHz (maps 0~1.5 GHz input to 2.18~3.68 GHz IF1) |
| LO2 | 2.220 GHz (fixed) |
| IF2 (ADC input) | 40 MHz |
| ADC sample rate | 130 Msps |

## Binary protocol (UART)

Physical: COM12 @ 921600 baud, 8N1.

Frame: `0xAA | Len(2B BE) | Cmd(1B) | Data(NB) | CRC16_Modbus(2B BE) | 0x55`

Commands: `SET_FREQ(0x01)`, `SET_AMPLITUDE(0x02)`, `SET_BW(0x03)`, `SET_DETECT(0x04)`, `SET_SWEEP(0x05)`, `GET_SPECTRUM(0x06)`, `GET_STATUS(0x07)`, `RESET(0x08)`, `START_SWEEP(0x09)`, `STOP_SWEEP(0x0A)`, `SET_VGA_GAIN(0x0B)`, `SET_RF_FRONTEND(0x0C)`, `GET_RF_FRONTEND(0x0D)`, `GET_PROFILE(0x0E)`.

Responses: `ACK(0x81)`, `SPECTRUM_DATA(0x82)`, `STATUS_DATA(0x83)`, `RF_FRONTEND_STATUS(0x84)`, `PROFILE_DATA(0x85)`.

See `docs/uart_protocol_summary.md` for the complete protocol spec.

## Critical gotchas

- **Use the 2026-05-16 firmware tree for current work**: `code/pusu_20260516/vitis/pusu_20260516/src/`. Older `code/pusu_test/vitis_20260409/` code is legacy/reference unless explicitly requested.
- **DMA IRQ follows the exported 2026-05-16 BSP**: current hardware connects `axi_dma_0/s2mm_introut` to `xlconcat_0/In0`, mapping to `IRQ_F2P[0]`. `RX_INTR_ID` is `XPAR_FABRIC_AXI_DMA_0_S2MM_INTROUT_INTR` in `app_config.h`.
- **Sweep profiling is gated off by default**: `SWEEP_PROFILE_ENABLE 0` in `app_config.h`. When enabled, `profile_timer.c/.h` records coarse per-sweep-point timing and exposes it through `GET_PROFILE(0x0E)` / `PROFILE_DATA(0x85)`. Host display is in the bottom status bar.
- **Two Flutter projects exist**: `flutter_pusu/` is the current active host app. `flutter_hello/` is older and should not be modified.
- **Multiple Vitis project trees exist**: `code/pusu_20260516/vitis/pusu_20260516/` is current. `vitis_20260409/` and older `vitis/` trees are reference code.
- **Never pull or overwrite from GitHub without explicit user approval**: do not run `git pull`, merge/rebase fetched remote changes, reset/checkout over local files, or otherwise sync from GitHub in a way that could overwrite local work. If remote sync or recovery seems necessary, explain the risk and ask the user before acting.

## Build and development

### Lower machine (Vitis)
- Open `code/pusu_20260516/pusu_test.xpr` in Vivado for hardware design.
- Export hardware to XSA, then create/update the Vitis workspace under `code/pusu_20260516/vitis/`.
- Build the `pusu_20260516` application project in Vitis.
- Program via JTAG; serial console on COM12 @ 921600.

### Host app (Flutter)
```bash
cd host_computer/flutter_pusu
flutter pub get
flutter run -d windows          # debug
flutter build windows           # release build at build/windows/x64/install_bundle/
```

### Protocol smoke tests (Python)
```bash
pip install pyserial
python tools/serial_protocol_smoke_test.py --port COM12 --mode basic
python tools/serial_protocol_smoke_test.py --port COM12 --mode spectrum --start-hz 50e6 --stop-hz 1.5e9
python tools/vga_gain_command_test.py
```

## Key files for common changes

| Change | Files |
|---|---|
| Add UART command | `code/pusu_20260516/vitis/pusu_20260516/src/device_protocol.c`, `host_computer/flutter_pusu/lib/serial_protocol.dart` |
| Change sweep behavior | `code/pusu_20260516/vitis/pusu_20260516/src/sweep_engine.c`, `sweep_plan.c` |
| Change signal processing | `code/pusu_20260516/vitis/pusu_20260516/src/signal_processing.c`, `app_config.h` |
| Add UI control | `host_computer/flutter_pusu/lib/main.dart`, `serial_protocol.dart`, `device_models.dart` |
| Change frequency plan | `code/pusu_20260516/vitis/pusu_20260516/src/lo_control.h`, `app_config.h` |
