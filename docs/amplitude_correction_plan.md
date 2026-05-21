# Amplitude Correction Plan

## Summary

The sweep output should report RF input power, not just ADC input power. Front-end gain and loss must be removed from the measured value before `amp_dbm` is sent to the host.

For the first implementation, firmware applies the correction. The UART spectrum frame remains unchanged, and the existing `amp_dbm` field becomes corrected RF input power.

## Correction Model

The sweep path still measures ADC input power first:

```text
raw_adc_dbm = power_dbfs + ADC_INPUT_FULL_SCALE_DBM
```

Firmware then converts it to RF input power:

```text
rf_input_dbm = raw_adc_dbm
             + atten_db
             - lna_gain_db
             - vga_gain_db
             + path_cal_db
             + freq_cal_db
```

Where:

- `atten_db = atten_code * 0.25`
- `vga_gain_db` uses the existing AD8370 theoretical gain function.
- `lna_gain_db` is `30.0 dB` when LNA is enabled.
- `path_cal_db` is `0.0 dB` for both direct IF and mixer chain for now.
- `freq_cal_db` comes from a frequency calibration table whose current entries are all `0.0 dB`.

This means the first version immediately corrects for RF attenuation, the 30 dB LNA gain, and VGA gain, while leaving frequency/channel calibration ready for later measured values.

## Firmware Changes

- Add an amplitude correction module in the Vitis firmware source tree.
- Keep raw ADC input power internally for diagnostics.
- Apply correction in `sweep_engine` after `signal_processing_measure_accumulated_power_dbm()`.
- Continue streaming the existing spectrum payload with the corrected value in `amp_dbm`.
- Keep `RF_FRONTEND_STATUS` as the source of truth for LNA/path/attenuator state.

## Public Interfaces

The new firmware API should provide:

```c
int amplitude_correction_apply(uint64_t rf_hz,
                               float raw_adc_dbm,
                               float *out_rf_input_dbm,
                               float *out_correction_db);

float amplitude_correction_get_total_db(uint64_t rf_hz);
```

Default calibration constants live in `app_config.h` so later calibration work can change values in one place.

## Test Plan

- Build the Vitis firmware.
- With fixed RF input and fixed VGA, increase RF attenuation by `X dB`; reported RF input power should rise by about `X dB` compared with the uncorrected ADC reading.
- With fixed RF input and fixed attenuation, increase VGA gain by `X dB`; reported RF input power should stay approximately stable instead of rising by `X dB`.
- With fixed RF input and fixed attenuation, enable the LNA; reported RF input power should stay approximately stable after the 30 dB correction.

## Assumptions

- `amp_dbm` now means RF input power.
- The host protocol and Flutter parsing do not change in this phase.
- Frequency and path calibration tables are placeholders until real calibration data is available.
- AD8370 theoretical gain is good enough for the first version.
