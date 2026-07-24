connect -url tcp:127.0.0.1:3121
targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}
catch {stop}
rst -processor
source C:/learning/pusu_V2/code/pusu_20260608/vitis/system_wrapper/export/system_wrapper/hw/ps7_init.tcl
ps7_init
ps7_post_config
dow C:/learning/pusu_V2/code/pusu_20260608/vitis/pusu_20260608/Debug/pusu_20260608.elf
con
exit
