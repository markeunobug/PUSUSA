// Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2021.1 (win64) Build 3247384 Thu Jun 10 19:36:33 MDT 2021
// Date        : Sun Mar 15 20:32:56 2026
// Host        : MarkeuPro running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub -rename_top decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix -prefix
//               decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix_ system_LTC2208_0_0_stub.v
// Design      : system_LTC2208_0_0
// Purpose     : Stub declaration of top-level module interface
// Device      : xc7z010clg400-1
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* X_CORE_INFO = "LTC2208,Vivado 2021.1" *)
module decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix(rst_n, enc_clk, enc_p, enc_n, clkout_p, clkout_n, 
  data_p, data_n, of_p, of_n, adc_data, adc_of, adc_clk, m_axis_aclk, m_axis_tdata, m_axis_tvalid, 
  m_axis_tready, m_axis_tlast, m_axis_tuser)
/* synthesis syn_black_box black_box_pad_pin="rst_n,enc_clk,enc_p,enc_n,clkout_p,clkout_n,data_p[15:0],data_n[15:0],of_p,of_n,adc_data[15:0],adc_of,adc_clk,m_axis_aclk,m_axis_tdata[15:0],m_axis_tvalid,m_axis_tready,m_axis_tlast,m_axis_tuser" */;
  input rst_n;
  input enc_clk;
  output enc_p;
  output enc_n;
  input clkout_p;
  input clkout_n;
  input [15:0]data_p;
  input [15:0]data_n;
  input of_p;
  input of_n;
  output [15:0]adc_data;
  output adc_of;
  output adc_clk;
  output m_axis_aclk;
  output [15:0]m_axis_tdata;
  output m_axis_tvalid;
  input m_axis_tready;
  output m_axis_tlast;
  output m_axis_tuser;
endmodule
