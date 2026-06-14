# MATLAB RBW ENBW Offline Design

This folder is the MATLAB side branch for making PuSuSA RBW trustworthy by
defining each RBW mode by complete-chain ENBW.

## Run

From MATLAB:

```matlab
cd C:\learning\pusu_V2
run("docs/rbw_filter_analysis/matlab/run_rbw_enbw_design.m")
```

The script adds `tools/matlab` to the MATLAB path and writes all generated
outputs back into this folder.

## Current Scope

The first pass reproduces the current Hamming-sinc firmware baseline for all
six RBW modes:

```text
1K, 10K, 30K, 100K, 300K, 1M
```

The default profile is `firmware_current`, matching
`docs/rbw_filter_analysis/rbw_enbw_design_spec.md`:

```text
1K: R=13000, N=5, 256 taps
10K: R=1300, N=5, 256 taps
30K: R=433, N=5, 256 taps
100K: R=130, N=5, 128 taps
300K: R=43, N=4, 128 taps
1M: R=13, N=4, 64 taps
```

To inspect the earlier 1 kHz alias-rework candidate, change this line in
`run_rbw_enbw_design.m`:

```matlab
profile = "alias_rework_1k";
```

That keeps the same FIR shape but changes 1K to `R=1300`, `Fs_out=100 kHz`.

## Expected Outputs

Running the script should produce:

```text
docs/rbw_filter_analysis/matlab/rbw_enbw_metrics.csv
docs/rbw_filter_analysis/matlab/rbw_enbw_metrics.md
docs/rbw_filter_analysis/matlab/rbw_coefficients_float.csv
docs/rbw_filter_analysis/matlab/rbw_response_1K.csv
docs/rbw_filter_analysis/matlab/rbw_response_10K.csv
docs/rbw_filter_analysis/matlab/rbw_response_30K.csv
docs/rbw_filter_analysis/matlab/rbw_response_100K.csv
docs/rbw_filter_analysis/matlab/rbw_response_300K.csv
docs/rbw_filter_analysis/matlab/rbw_response_1M.csv
docs/rbw_filter_analysis/matlab/rbw_response_*.png
docs/rbw_filter_analysis/matlab/rbw_response_normalized.png
```

`rbw_enbw_metrics.csv` is the machine-readable summary. It reports CIC+FIR
ENBW, ENBW/RBW, ENBW correction, -3 dB and -6 dB bandwidth, passband flatness,
and responses at 0.5x, 1x, 2x, 5x, and 10x nominal RBW.

## Next Design Steps

1. Keep the Hamming-sinc output as the regression baseline.
2. Add a cutoff sweep around each FIR design and choose the cutoff where the
   combined CIC+FIR `enbw_main_hz` equals nominal RBW.
3. Compare `design_method = "kaiser"` and `design_method = "equiripple"` once
   MATLAB Signal Processing Toolbox functions are available.
4. Recheck rejection at 2x and 5x RBW after ENBW tuning. Narrowing ENBW can
   improve noise bandwidth but may move the transition band in a way that
   changes tone rejection.
5. Export quantized coefficients only after the float design meets ENBW and
   rejection targets, then rerun this same analysis on quantized taps.

Kaiser and equiripple entry points already exist in `tools/matlab/rbw_enbw_lib.m`.
They currently serve as placeholders for the next pass and fall back gracefully
if the needed toolbox functions are missing.
