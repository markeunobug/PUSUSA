# Host Spectrum Refresh Rules

This note records the intended refresh behavior for the Flutter host spectrum
view. Keep these rules in mind when touching sweep, RBW/VBW, or spectrum frame
assembly code.

## Intended behavior

- Continuous or repeated sweeps over the same display range should not clear the
  existing trace at sweep start.
- Incoming segment data should replace only the points/frequencies contained in
  that segment.
- Frequencies that have not been refreshed by the current sweep should continue
  showing the previous sweep's values.
- A completed sweep may finalize markers and sweep statistics, but it should not
  be the first time the user sees the data.
- Frequency range changes must clear the trace, because old points no longer
  match the displayed x-axis.
- RBW or VBW changes must clear the trace, because old amplitude values were
  measured with different bandwidth settings and can leave misleading residue.
- Manual clear, mode switches, or disconnects may clear the trace explicitly.

## Common pitfalls

- Do not clear `_displaySweepPoints` when a new `segment.timestamp` arrives.
  That creates a blank graph while the next sweep is still in progress.
- Do not wait until `segment.done` to show the sweep. The graph should update as
  each segment arrives.
- Do not preserve old points after RBW/VBW changes. Bandwidth changes alter the
  measurement result, so partial replacement leaves mixed old/new measurements.
- Distinguish display storage from assembly storage:
  `_displaySweepPoints` is what the user sees, while `_pendingSweepPoints`
  tracks the current sweep's received points.
- Do not round editable frequency fields too aggressively. Around 1 GHz,
  `1005 MHz` formatted as `1.00 GHz` becomes `1000 MHz` if the UI later parses
  it back, turning a 10 MHz span into 5 MHz. Editable frequency fields should
  keep enough precision, or the confirmed Hz values should remain the source of
  truth.
- Do not build a device config from stale text fields. Before applying a new
  measurement configuration, commit the last edited frequency group
  (`start/stop` or `center/span`) into confirmed start/stop Hz values.

## Related files

- `host_computer/flutter_pusu/lib/main.dart`
- `host_computer/flutter_pusu/lib/serial_protocol.dart`
