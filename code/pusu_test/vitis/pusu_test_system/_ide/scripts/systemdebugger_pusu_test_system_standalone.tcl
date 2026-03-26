# Usage with Vitis IDE:
# In Vitis IDE create a Single Application Debug launch configuration,
# change the debug type to 'Attach to running target' and provide this 
# tcl script in 'Execute Script' option.
# Path of this script: C:\learning\XC7Z010_WS\pusu_test\vitis\pusu_test_system\_ide\scripts\systemdebugger_pusu_test_system_standalone.tcl
# 
# 
# Usage with xsct:
# To debug using xsct, launch xsct and run below command
# source C:\learning\XC7Z010_WS\pusu_test\vitis\pusu_test_system\_ide\scripts\systemdebugger_pusu_test_system_standalone.tcl
# 
connect -url tcp:127.0.0.1:3121
targets -set -nocase -filter {name =~"APU*"}
rst -system
after 3000
targets -set -filter {jtag_cable_name =~ "my vendor co my board 0ABC01A" && level==0 && jtag_device_ctx=="jsn-my board-0ABC01A-13722093-0"}
fpga -file C:/learning/XC7Z010_WS/pusu_test/vitis/pusu_test/_ide/bitstream/system_wrapper.bit
targets -set -nocase -filter {name =~"APU*"}
loadhw -hw C:/learning/XC7Z010_WS/pusu_test/vitis/system_wrapper/export/system_wrapper/hw/system_wrapper.xsa -mem-ranges [list {0x40000000 0xbfffffff}] -regs
configparams force-mem-access 1
targets -set -nocase -filter {name =~"APU*"}
source C:/learning/XC7Z010_WS/pusu_test/vitis/pusu_test/_ide/psinit/ps7_init.tcl
ps7_init
ps7_post_config
targets -set -nocase -filter {name =~ "*A9*#0"}
dow C:/learning/XC7Z010_WS/pusu_test/vitis/pusu_test/Debug/pusu_test.elf
configparams force-mem-access 0
targets -set -nocase -filter {name =~ "*A9*#0"}
con
