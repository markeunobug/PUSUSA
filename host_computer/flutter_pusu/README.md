# flutter_pusu

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Real-time spectrum (V1)

Mode menu contains **实时频谱**. It uses the dedicated protocol commands `0x18` configure, `0x19` start, `0x1A` stop and `0x1B` status, and receives `0x8A` FFT frames plus `0x8B` status. The host verifies the exact 1296-byte data payload (36-byte header + 315 little-endian `float32` bins), 4096 FFT size and bounds before drawing.

The view is fixed to a 10 MHz IF span, has latest / relative-linear average / max hold / peak marker and a 240-row waterfall. The RF-frequency axis is derived from each frame's first/last FFT bin, while the power axis is fixed at -150..+10 dBFS. Waterfall row 0 is the newest frame and older history moves downward; the display-only floor/reference range defaults to -140/-30 dBFS, is adjustable from -160..0 dBFS with a minimum 10 dB span, and never changes protocol or measurement processing. Display is explicitly **raw dBFS / calibration pending**: the received values are not calibrated absolute dBm. A future calibration may add a separately labeled preliminary dBm conversion.

A configuration transition is controlled: STOP ACK -> terminal idle status (2 s timeout) -> clear host buffers -> CONFIG ACK -> START ACK. RF center changes are disabled while active. Hardware streaming and calibration remain to be validated on a flashed device.

### Real-time sidebar and RF frontend control

The real-time view uses the same fixed 300 px, scrollable Expander-style sidebar as the ordinary spectrum view. Its **raw dBFS display reference** adjusts only the trace vertical range and resets the waterfall display range to a linked 110 dB span. It sends no amplitude (`0x02`) command, is not a dBm setting, and does not change hardware range.

LNA, 0--31.75 dB DSA (0.25 dB steps), and VGA settings are local to the real-time page. While RT is active, each change is serialized as: STOP ACK, terminal idle (error 0 or 10), mixer-chain RF frontend `0x0C`, frontend status request `0x0D`/`0x84` confirmation, VGA `0x0B`, clear host display/history, then CONFIG/START. Controls remain disabled during this operation. The VGA command has no device readback, so its UI reports only a locally sent value; it must not be read as device confirmation. Hardware behavior remains unverified until a flashed board is tested.
