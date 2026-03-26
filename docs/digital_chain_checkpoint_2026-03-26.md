# pusu_V2 digital chain checkpoint (2026-03-26)

Project path: C:\learning\pusu_V2\code\pusu_test\vitis\helloworld\src\helloworld.c

Current working digital chain:
- ADC raw capture via AXI DMA S2MM
- Single DDC from 50 MHz IF to 0 Hz
- Selectable RBW FIR via UART command
- Time-domain power output in dBFS: POWER_DBFS,<RBW>,<value>
- FFT peak debug output: PEAK,<RBW>,<bin>,<kHz>,<Hz_rem>,<dB>

Current UART RBW protocol:
- '0' -> 10 kHz
- '1' -> 30 kHz
- '2' -> 100 kHz
- '3' -> 300 kHz
- '4' -> 1 MHz

Confirmed behavior:
- RBW switching over UART works
- POWER_DBFS is stable within each RBW setting
- PEAK stays near low-frequency bins after DDC as expected
- Wider RBW gives higher integrated power, trend is correct

Known issue to revisit later:
- Noise measurement is lifted by low-frequency spur / near-DC residual in the first few FFT bins
- This affects total-noise estimation more than the wideband noise floor itself
- We intentionally removed temporary NOISE_DBG code and returned to the cleaner mainline version

Recommended next steps:
1. Add frame averaging for POWER_DBFS
2. Build sweep-point control around the current single-point power chain
3. Later revisit low-frequency spur handling / noise measurement mode if needed
