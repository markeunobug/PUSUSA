# RBW Finite Window Leakage

This models the firmware FIR output window for a single carrier at each offset. `current` starts at `skip`; `fixed` starts at `taps - 1 + skip`.

| Mode | Offset | Current response | Fixed response | Current density | Fixed density | Improvement |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1K | 1000 Hz | -5.91 dB | -6.02 dB | -35.91 dBc/Hz | -36.02 dBc/Hz | -0.11 dB |
| 1K | 3000 Hz | -29.53 dB | -55.46 dB | -59.53 dBc/Hz | -85.46 dBc/Hz | -25.93 dB |
| 1K | 10000 Hz | -40.38 dB | -65.07 dB | -70.38 dBc/Hz | -95.07 dBc/Hz | -24.69 dB |
| 1K | 10200 Hz | -40.56 dB | -74.81 dB | -70.56 dBc/Hz | -104.81 dBc/Hz | -34.25 dB |
| 1K | 14000 Hz | -43.33 dB | -74.23 dB | -73.33 dBc/Hz | -104.23 dBc/Hz | -30.91 dB |
| 1K | 100000 Hz | -60.42 dB | -316.72 dB | -90.42 dBc/Hz | -346.72 dBc/Hz | -256.30 dB |
| 1K | 1000000 Hz | -80.42 dB | -332.16 dB | -110.42 dBc/Hz | -362.16 dBc/Hz | -251.74 dB |
| 1K | 10000000 Hz | -100.34 dB | -328.89 dB | -130.34 dBc/Hz | -358.89 dBc/Hz | -228.55 dB |
| 1K | 14000000 Hz | -103.18 dB | -312.82 dB | -133.18 dBc/Hz | -342.82 dBc/Hz | -209.64 dB |
| 10K | 1000 Hz | -0.05 dB | -0.00 dB | -40.05 dBc/Hz | -40.00 dBc/Hz | 0.04 dB |
| 10K | 3000 Hz | -0.11 dB | -0.07 dB | -40.11 dBc/Hz | -40.07 dBc/Hz | 0.04 dB |
| 10K | 10000 Hz | -6.48 dB | -6.73 dB | -46.48 dBc/Hz | -46.73 dBc/Hz | -0.26 dB |
| 10K | 10200 Hz | -11.52 dB | -13.05 dB | -51.52 dBc/Hz | -53.05 dBc/Hz | -1.53 dB |
| 10K | 14000 Hz | -28.48 dB | -66.15 dB | -68.48 dBc/Hz | -106.15 dBc/Hz | -37.68 dB |
| 10K | 100000 Hz | -48.03 dB | -316.72 dB | -88.03 dBc/Hz | -356.72 dBc/Hz | -268.68 dB |
| 10K | 1000000 Hz | -68.07 dB | -332.16 dB | -108.07 dBc/Hz | -372.16 dBc/Hz | -264.09 dB |
| 10K | 10000000 Hz | -87.99 dB | -328.89 dB | -127.99 dBc/Hz | -368.89 dBc/Hz | -240.90 dB |
| 10K | 14000000 Hz | -90.83 dB | -312.82 dB | -130.83 dBc/Hz | -352.82 dBc/Hz | -221.99 dB |
| 100K | 1000 Hz | -0.03 dB | -0.00 dB | -50.03 dBc/Hz | -50.00 dBc/Hz | 0.03 dB |
| 100K | 3000 Hz | -0.04 dB | -0.01 dB | -50.04 dBc/Hz | -50.01 dBc/Hz | 0.03 dB |
| 100K | 10000 Hz | -0.05 dB | -0.02 dB | -50.05 dBc/Hz | -50.02 dBc/Hz | 0.03 dB |
| 100K | 10200 Hz | -0.05 dB | -0.02 dB | -50.05 dBc/Hz | -50.02 dBc/Hz | 0.03 dB |
| 100K | 14000 Hz | -0.05 dB | -0.02 dB | -50.05 dBc/Hz | -50.02 dBc/Hz | 0.03 dB |
| 100K | 100000 Hz | -6.66 dB | -6.75 dB | -56.66 dBc/Hz | -56.75 dBc/Hz | -0.09 dB |
| 100K | 1000000 Hz | -49.85 dB | -325.28 dB | -99.85 dBc/Hz | -375.28 dBc/Hz | -275.44 dB |
| 100K | 10000000 Hz | -69.80 dB | -322.49 dB | -119.80 dBc/Hz | -372.49 dBc/Hz | -252.69 dB |
| 100K | 14000000 Hz | -72.64 dB | -308.71 dB | -122.64 dBc/Hz | -358.71 dBc/Hz | -236.07 dB |
| 1M | 1000 Hz | -0.02 dB | 0.00 dB | -60.02 dBc/Hz | -60.00 dBc/Hz | 0.02 dB |
| 1M | 3000 Hz | -0.02 dB | 0.00 dB | -60.02 dBc/Hz | -60.00 dBc/Hz | 0.02 dB |
| 1M | 10000 Hz | -0.02 dB | 0.00 dB | -60.02 dBc/Hz | -60.00 dBc/Hz | 0.02 dB |
| 1M | 10200 Hz | -0.02 dB | 0.00 dB | -60.02 dBc/Hz | -60.00 dBc/Hz | 0.02 dB |
| 1M | 14000 Hz | -0.02 dB | 0.00 dB | -60.02 dBc/Hz | -60.00 dBc/Hz | 0.02 dB |
| 1M | 100000 Hz | -0.02 dB | 0.00 dB | -60.02 dBc/Hz | -60.00 dBc/Hz | 0.02 dB |
| 1M | 1000000 Hz | -6.53 dB | -6.57 dB | -66.53 dBc/Hz | -66.57 dBc/Hz | -0.04 dB |
| 1M | 10000000 Hz | -50.27 dB | -326.70 dB | -110.27 dBc/Hz | -386.70 dBc/Hz | -276.43 dB |
| 1M | 14000000 Hz | -53.12 dB | -115.00 dB | -113.12 dBc/Hz | -175.00 dBc/Hz | -61.87 dB |
