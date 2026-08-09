# Realtime IF FFT Stage-1 local tests

Run from this directory in PowerShell:

```powershell
$project = 'C:\learning\pusu_V2\code\pusu_20260608\vitis\pusu_20260608'
gcc -std=c11 -Wall -Wextra -Werror -I "$project\tests\stubs" -I "$project\src" `
    "$project\src\realtime_if_fft.c" "$project\tests\realtime_if_fft_contract_test.c" `
    -lm -o "$project\tests\realtime_if_fft_contract_test.exe"
& "$project\tests\realtime_if_fft_contract_test.exe"
```

The test covers the fixed `1103..1417` bin slice, ascending RF frequency
mapping, raw-dBFS trace metadata, inclusive 50 MHz..1.5 GHz centre-frequency
validation, short-input rejection, and the narrow FFT adapter's interaction
with mocked `signal_processing` APIs.

This is a host-side contract test only. It does **not** compile the module into
the generated Vitis image, acquire DMA data, configure an LO, transmit a
protocol frame, or make any board/hardware/amplitude-calibration claim.

## LMX2572 driver contract and frequency-math tests

Run from this directory in PowerShell:

~~~powershell
$project = 'C:\learning\pusu_V2\code\pusu_20260608\vitis\pusu_20260608'
gcc -std=c11 -Wall -Wextra -Werror -I "$project\tests\lmx2572_stubs" -I "$project\src" "$project\src\lmx2572.c" "$project\src\lmx2572_bus.c" "$project\src\lmx2572_frequency.c" "$project\src\lmx2572_pfd_profile.c" "$project\tests\lmx2572_contract_test.c" -o "$project\tests\lmx2572_contract_test.exe"
& "$project\tests\lmx2572_contract_test.exe"
~~~

The test preserves the public function signatures and fingerprints the complete
current-machine P100 TICS register image. It checks representative ADC/LO
register values, sweeps the 2.23..3.68 GHz LO1 range at 1 MHz intervals,
verifies exact P75 and 350/3 MHz reference arithmetic, applies the data-sheet
MASH minimum-N and PFD-delay table, and checks non-mutating failure paths.
P100 is qualified from the current-machine image. P75 uses the lab-only CPG=5
candidate and is also checked across the full LO1 range; this is software
eligibility, not hardware loop-stability or spur qualification.

It does not prove GPIO timing, PLL lock, phase noise, reference-spur behavior,
output power, or operation on the physical instrument.

## LO1 manual PFD-profile switching tests

~~~powershell
$project = 'C:\learning\pusu_V2\code\pusu_20260608\vitis\pusu_20260608'
gcc -std=c11 -Wall -Wextra -Werror -I "$project\tests\lmx2572_stubs" -I "$project\src" "$project\src\lo_control.c" "$project\tests\lo_control_pfd_contract_test.c" -o "$project\tests\lo_control_pfd_contract_test.exe"
& "$project\tests\lo_control_pfd_contract_test.exe"
~~~

This test verifies that an unqualified profile is non-mutating, a qualified
profile keeps the same RF/LO mapping, and a lock failure reapplies P100 at the
same LO frequency. It uses mocked lock state and does not qualify P75 hardware.
