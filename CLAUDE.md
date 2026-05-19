# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

PuSuSA is a spectrum analyzer. The signal chain is:
`RF → LNA → attenuator → ADL5801(mixer1) → filter → ADL5801(mixer2) → filter → AD8370(VGA) → LTC2208(ADC) → Zynq`

Two LMX2572 PLLs generate LO1 and LO2. The Zynq-7000 ARM core runs bare-metal C firmware that controls the RF frontend, captures ADC data via DMA, performs DDC + RBW filtering + time-domain power measurement, and communicates with a host PC over UART.

## Repository structure

| Directory | Purpose |
|---|---|
| `code/pusu_test/` | Vivado hardware project (block design, constraints, IP) |
| `code/pusu_test/vitis_20260409/pusu_20260409/code/` | **Active lower-machine firmware** (C, bare-metal on Zynq) |
| `code/pusu_test/vitis_20260409/pusu_20260409/mylib/` | CMSIS-DSP library headers used by firmware |
| `code/pusu_test/vitis/` | Older Vitis projects (helloworld, memorytest) — reference only |
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
- `device_protocol.c` — Binary frame protocol (0xAA/0x55 framing, CRC16 Modbus). Parses incoming commands, dispatches to providers registered via function pointers (`spectrum_provider`, `status_provider`, `sweep_control`). Sends ACK/spectrum/status responses.
- `sweep_engine.c` — Blocking sweep state machine. Per point: set LO1 → wait lock → arm DMA → wait frame → measure power (DDC → RBW filter → mean(I² + Q²) → dBFS → dBm). Currently synchronous; non-blocking conversion is planned.
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

Commands: `SET_FREQ(0x01)`, `SET_AMPLITUDE(0x02)`, `SET_BW(0x03)`, `SET_DETECT(0x04)`, `SET_SWEEP(0x05)`, `GET_SPECTRUM(0x06)`, `GET_STATUS(0x07)`, `RESET(0x08)`, `START_SWEEP(0x09)`, `STOP_SWEEP(0x0A)`, `SET_VGA_GAIN(0x0B)`.

Responses: `ACK(0x81)`, `SPECTRUM_DATA(0x82)`, `STATUS_DATA(0x83)`.

See `docs/uart_protocol_summary.md` for the complete protocol spec.

## Critical gotchas

- **DMA IRQ number must be forced to 62**: The hardware BD connects `axi_dma_0/s2mm_introut` to `xlconcat_0/In1` which maps to IRQ_F2P[1] = 62. The BSP-exported interrupt ID may be wrong. Defined as `RX_INTR_ID 62U` in `app_config.h`.
- **Sweep is currently blocking/synchronous**: `GET_SPECTRUM` runs the entire sweep in the request handler. Point count temporarily limited to 32 for bring-up stability.
- **Two Flutter projects exist**: `flutter_pusu/` is the current active host app. `flutter_hello/` is older and should not be modified.
- **Two Vitis project trees exist**: `vitis_20260409/` is current. `vitis/` is older reference code.

## Build and development

### Lower machine (Vitis)
- Open `code/pusu_test/pusu_test.xpr` in Vivado for hardware design.
- Export hardware to XSA, then create/update Vitis workspace from `code/pusu_test/vitis_20260409/`.
- Build the `pusu_20260409` application project in Vitis.
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
| Add UART command | `device_protocol.h` (cmd constant), `device_protocol.c` (parsing + response), `serial_protocol.dart` (host side) |
| Change sweep behavior | `sweep_engine.c` (state machine), `sweep_plan.c` (point calculation) |
| Change signal processing | `signal_processing.c` (DDC/RBW/power), `app_config.h` (RBW presets) |
| Add UI control | `main.dart` (UI), `serial_protocol.dart` (command), `device_models.dart` (data model) |
| Change frequency plan | `lo_control.h` (IF/LO constants), `app_config.h` (DDC IF) |
