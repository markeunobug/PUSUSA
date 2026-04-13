# New Platform DMA IRQ Note - 2026-04-13

## Scope
- Project: `C:\learning\pusu_V2`
- New lower-machine app: `C:\learning\pusu_V2\code\pusu_test\vitis_20260409\pusu_20260409`
- Hardware export used by Vitis:
  - `C:\learning\pusu_V2\code\pusu_test\vitis_20260409\system_wrapper\export\system_wrapper\hw\system_wrapper.xsa`

## Confirmed current behavior
- Lower machine on the new platform now works with DMA + FFT + binary protocol.
- Real serial test on `COM12` shows:
  - `SET_FREQ` ACK normal
  - `GET_STATUS` ACK + status frame normal
  - `GET_SPECTRUM` ACK + spectrum frame normal
- Diagnostic counters from status frame show DMA is continuously running:
  - `dma_start > 0`
  - `frame_ready > 0`
  - `process_frame > 0`
  - `spectrum_valid = 1`
  - `dma_irq_count > 0`

## Key finding
- With BSP-exported interrupt ID (`61`), DMA never raised `frame_ready`.
- After forcing:
  - `RX_INTR_ID = 62U`
  in `app_config.h`, DMA immediately worked.

## Evidence
- `system.hwh` inside `system_wrapper.xsa` shows:
  - `axi_dma_0/s2mm_introut -> xlconcat_0/In1`
  - `xlconcat_0/dout[1:0] -> processing_system7_0/IRQ_F2P`
- On Zynq-7000, this strongly suggests the physical interrupt line should be:
  - `IRQ_F2P[1] -> GIC ID 62`

## Why BSP likely exported `61`
Current best explanation:
- `xlconcat_0/In0` is unconnected
- `xlconcat_0/In1` is connected to `axi_dma_0/s2mm_introut`
- The exported BSP appears to compress or enumerate only "active fabric interrupt sources"
  instead of preserving the physical bit index within `IRQ_F2P[1:0]`
- Result:
  - BSP macro says `XPAR_FABRIC_AXI_DMA_0_S2MM_INTROUT_INTR = 61`
  - Actual working interrupt line is `62`

This is not fully proven at generator-internal level, but it matches:
- `system.hwh` connectivity
- serial diagnostics
- runtime behavior

## Current temporary workaround
File:
- `C:\learning\pusu_V2\code\pusu_test\vitis_20260409\pusu_20260409\src\app_config.h`

Temporary fix:
- force `#define RX_INTR_ID 62U`

## Recommended permanent fixes
Choose one of the following:

1. Preferred hardware fix
- Rewire DMA interrupt to `xlconcat_0/In0`
- Regenerate bitstream
- Re-export hardware platform
- Rebuild Vitis BSP/app
- Then BSP should more likely export `61`, matching the physical path

2. Software workaround
- Keep current hardware
- Keep `RX_INTR_ID = 62U` override in software
- Add comment explaining why BSP macro is not trusted on this platform

## Notes
- Changing `S2MM Max Burst Size 128 -> 16` did **not** solve the issue.
- Changing DMA buffer placement from fixed DDR address to static aligned buffer did **not** solve the issue.
- The decisive fix was the interrupt ID change to `62`.
