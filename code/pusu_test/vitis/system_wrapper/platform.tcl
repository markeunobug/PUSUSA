# 
# Usage: To re-create this platform project launch xsct with below options.
# xsct C:\learning\XC7Z010_WS\pusu_test\vitis\system_wrapper\platform.tcl
# 
# OR launch xsct and run below command.
# source C:\learning\XC7Z010_WS\pusu_test\vitis\system_wrapper\platform.tcl
# 
# To create the platform in a different location, modify the -out option of "platform create" command.
# -out option specifies the output directory of the platform project.

platform create -name {system_wrapper}\
-hw {C:\learning\XC7Z010_WS\pusu_test\vitis\system_wrapper.xsa}\
-out {C:/learning/XC7Z010_WS/pusu_test/vitis}

platform write
domain create -name {standalone_ps7_cortexa9_0} -display-name {standalone_ps7_cortexa9_0} -os {standalone} -proc {ps7_cortexa9_0} -runtime {cpp} -arch {32-bit} -support-app {empty_application}
platform generate -domains 
platform active {system_wrapper}
domain active {zynq_fsbl}
domain active {standalone_ps7_cortexa9_0}
platform generate -quick
platform generate
platform active {system_wrapper}
platform config -updatehw {C:/learning/XC7Z010_WS/pusu_test/vitis/system_wrapper.xsa}
platform generate -domains 
platform config -updatehw {C:/learning/XC7Z010_WS/pusu_test/vitis/system_wrapper.xsa}
platform clean
platform generate
platform config -updatehw {C:/learning/XC7Z010_WS/pusu_test/vitis/system_wrapper.xsa}
platform clean
platform generate
platform active {system_wrapper}
platform config -updatehw {C:/learning/XC7Z010_WS/pusu_test/vitis/system_wrapper.xsa}
platform generate -domains standalone_ps7_cortexa9_0,zynq_fsbl 
platform clean
platform generate
platform clean
platform generate
