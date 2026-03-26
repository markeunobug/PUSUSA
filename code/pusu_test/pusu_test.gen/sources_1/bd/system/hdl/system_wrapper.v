//Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2021.1 (win64) Build 3247384 Thu Jun 10 19:36:33 MDT 2021
//Date        : Sat Mar 21 13:58:49 2026
//Host        : MarkeuPro running 64-bit major release  (build 9200)
//Command     : generate_target system_wrapper.bd
//Design      : system_wrapper
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

module system_wrapper
   (DDR_addr,
    DDR_ba,
    DDR_cas_n,
    DDR_ck_n,
    DDR_ck_p,
    DDR_cke,
    DDR_cs_n,
    DDR_dm,
    DDR_dq,
    DDR_dqs_n,
    DDR_dqs_p,
    DDR_odt,
    DDR_ras_n,
    DDR_reset_n,
    DDR_we_n,
    FIXED_IO_ddr_vrn,
    FIXED_IO_ddr_vrp,
    FIXED_IO_mio,
    FIXED_IO_ps_clk,
    FIXED_IO_ps_porb,
    FIXED_IO_ps_srstb,
    GPIO_EMIO_tri_io,
    clkout_n_0,
    clkout_p_0,
    data_n_0,
    data_p_0,
    enc_n_0,
    enc_p_0,
    of_n_0,
    of_p_0);
  inout [14:0]DDR_addr;
  inout [2:0]DDR_ba;
  inout DDR_cas_n;
  inout DDR_ck_n;
  inout DDR_ck_p;
  inout DDR_cke;
  inout DDR_cs_n;
  inout [3:0]DDR_dm;
  inout [31:0]DDR_dq;
  inout [3:0]DDR_dqs_n;
  inout [3:0]DDR_dqs_p;
  inout DDR_odt;
  inout DDR_ras_n;
  inout DDR_reset_n;
  inout DDR_we_n;
  inout FIXED_IO_ddr_vrn;
  inout FIXED_IO_ddr_vrp;
  inout [53:0]FIXED_IO_mio;
  inout FIXED_IO_ps_clk;
  inout FIXED_IO_ps_porb;
  inout FIXED_IO_ps_srstb;
  inout [0:0]GPIO_EMIO_tri_io;
  input clkout_n_0;
  input clkout_p_0;
  input [15:0]data_n_0;
  input [15:0]data_p_0;
  output enc_n_0;
  output enc_p_0;
  input of_n_0;
  input of_p_0;

  wire [14:0]DDR_addr;
  wire [2:0]DDR_ba;
  wire DDR_cas_n;
  wire DDR_ck_n;
  wire DDR_ck_p;
  wire DDR_cke;
  wire DDR_cs_n;
  wire [3:0]DDR_dm;
  wire [31:0]DDR_dq;
  wire [3:0]DDR_dqs_n;
  wire [3:0]DDR_dqs_p;
  wire DDR_odt;
  wire DDR_ras_n;
  wire DDR_reset_n;
  wire DDR_we_n;
  wire FIXED_IO_ddr_vrn;
  wire FIXED_IO_ddr_vrp;
  wire [53:0]FIXED_IO_mio;
  wire FIXED_IO_ps_clk;
  wire FIXED_IO_ps_porb;
  wire FIXED_IO_ps_srstb;
  wire [0:0]GPIO_EMIO_tri_i_0;
  wire [0:0]GPIO_EMIO_tri_io_0;
  wire [0:0]GPIO_EMIO_tri_o_0;
  wire [0:0]GPIO_EMIO_tri_t_0;
  wire clkout_n_0;
  wire clkout_p_0;
  wire [15:0]data_n_0;
  wire [15:0]data_p_0;
  wire enc_n_0;
  wire enc_p_0;
  wire of_n_0;
  wire of_p_0;

  IOBUF GPIO_EMIO_tri_iobuf_0
       (.I(GPIO_EMIO_tri_o_0),
        .IO(GPIO_EMIO_tri_io[0]),
        .O(GPIO_EMIO_tri_i_0),
        .T(GPIO_EMIO_tri_t_0));
  system system_i
       (.DDR_addr(DDR_addr),
        .DDR_ba(DDR_ba),
        .DDR_cas_n(DDR_cas_n),
        .DDR_ck_n(DDR_ck_n),
        .DDR_ck_p(DDR_ck_p),
        .DDR_cke(DDR_cke),
        .DDR_cs_n(DDR_cs_n),
        .DDR_dm(DDR_dm),
        .DDR_dq(DDR_dq),
        .DDR_dqs_n(DDR_dqs_n),
        .DDR_dqs_p(DDR_dqs_p),
        .DDR_odt(DDR_odt),
        .DDR_ras_n(DDR_ras_n),
        .DDR_reset_n(DDR_reset_n),
        .DDR_we_n(DDR_we_n),
        .FIXED_IO_ddr_vrn(FIXED_IO_ddr_vrn),
        .FIXED_IO_ddr_vrp(FIXED_IO_ddr_vrp),
        .FIXED_IO_mio(FIXED_IO_mio),
        .FIXED_IO_ps_clk(FIXED_IO_ps_clk),
        .FIXED_IO_ps_porb(FIXED_IO_ps_porb),
        .FIXED_IO_ps_srstb(FIXED_IO_ps_srstb),
        .GPIO_EMIO_tri_i(GPIO_EMIO_tri_i_0),
        .GPIO_EMIO_tri_o(GPIO_EMIO_tri_o_0),
        .GPIO_EMIO_tri_t(GPIO_EMIO_tri_t_0),
        .clkout_n_0(clkout_n_0),
        .clkout_p_0(clkout_p_0),
        .data_n_0(data_n_0),
        .data_p_0(data_p_0),
        .enc_n_0(enc_n_0),
        .enc_p_0(enc_p_0),
        .of_n_0(of_n_0),
        .of_p_0(of_p_0));
endmodule
