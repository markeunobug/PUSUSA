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
