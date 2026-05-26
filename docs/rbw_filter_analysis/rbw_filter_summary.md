# RBW Filter Analysis

Source config: `C:\learning\pusu_V2\code\pusu_20260516\vitis\pusu_20260516\src\app_config.h`

| Mode | Fs out | 3 dB BW | ENBW main | ENBW/RBW | Correction | Att @ 1x RBW | Att @ 10 kHz |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1K | 100000.0 | 842.6 | 1688.6 | 1.689 | 2.28 dB | -6.0 dB | -65.1 dB |
| 10K | 100000.0 | 9793.1 | 18699.6 | 1.870 | 2.72 dB | -6.7 dB | -6.7 dB |
| 30K | 300230.9 | 29379.1 | 56098.7 | 1.870 | 2.72 dB | -6.7 dB | -0.1 dB |
| 100K | 1000000.0 | 95882.8 | 183915.0 | 1.839 | 2.65 dB | -6.7 dB | -0.0 dB |
| 300K | 3023255.8 | 288216.8 | 557799.4 | 1.859 | 2.69 dB | -6.6 dB | -0.0 dB |
| 1M | 10000000.0 | 922790.0 | 1807416.4 | 1.807 | 2.57 dB | -6.6 dB | 0.0 dB |

`Correction` is based on main-lobe ENBW and is the amount by which noise density is high if firmware divides by nominal RBW instead of actual ENBW.
