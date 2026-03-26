// Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2021.1 (win64) Build 3247384 Thu Jun 10 19:36:33 MDT 2021
// Date        : Sun Mar 15 20:33:56 2026
// Host        : MarkeuPro running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub
//               c:/learning/XC7Z010_WS/pusu_test/pusu_test.gen/sources_1/bd/system/ip/system_ila_0_1/system_ila_0_1_stub.v
// Design      : system_ila_0_1
// Purpose     : Stub declaration of top-level module interface
// Device      : xc7z010clg400-1
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* X_CORE_INFO = "ila,Vivado 2021.1" *)
module system_ila_0_1(clk, probe0, probe1, probe2)
/* synthesis syn_black_box black_box_pad_pin="clk,probe0[15:0],probe1[0:0],probe2[0:0]" */;
  input clk;
  input [15:0]probe0;
  input [0:0]probe1;
  input [0:0]probe2;
endmodule
