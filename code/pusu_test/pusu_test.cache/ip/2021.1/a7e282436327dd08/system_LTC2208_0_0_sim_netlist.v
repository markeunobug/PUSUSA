// Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2021.1 (win64) Build 3247384 Thu Jun 10 19:36:33 MDT 2021
// Date        : Sun Mar 15 20:32:56 2026
// Host        : MarkeuPro running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode funcsim -rename_top decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix -prefix
//               decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix_ system_LTC2208_0_0_sim_netlist.v
// Design      : system_LTC2208_0_0
// Purpose     : This verilog netlist is a functional simulation representation of the design and should not be modified
//               or synthesized. This netlist cannot be used for SDF annotated simulation.
// Device      : xc7z010clg400-1
// --------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

module decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix_LTC2208
   (enc_p,
    enc_n,
    m_axis_aclk,
    adc_data,
    adc_of,
    m_axis_tvalid,
    m_axis_tdata,
    m_axis_tuser,
    m_axis_tlast,
    data_p,
    data_n,
    enc_clk,
    clkout_p,
    clkout_n,
    of_p,
    of_n,
    rst_n,
    m_axis_tready);
  output enc_p;
  output enc_n;
  output m_axis_aclk;
  output [15:0]adc_data;
  output adc_of;
  output m_axis_tvalid;
  output [15:0]m_axis_tdata;
  output m_axis_tuser;
  output m_axis_tlast;
  input [15:0]data_p;
  input [15:0]data_n;
  input enc_clk;
  input clkout_p;
  input clkout_n;
  input of_p;
  input of_n;
  input rst_n;
  input m_axis_tready;

  wire [15:0]adc_data;
  wire \adc_data[15]_i_1_n_0 ;
  wire adc_of;
  wire clkout_n;
  wire clkout_p;
  wire [31:1]data0;
  wire [15:0]data_n;
  wire [15:0]data_p;
  wire [15:0]data_s;
  wire enc_clk;
  wire enc_n;
  wire enc_p;
  wire m_axis_aclk;
  wire [15:0]m_axis_tdata;
  wire m_axis_tdata0;
  wire m_axis_tlast;
  wire m_axis_tlast_0;
  wire m_axis_tlast_i_10_n_0;
  wire m_axis_tlast_i_1_n_0;
  wire m_axis_tlast_i_3_n_0;
  wire m_axis_tlast_i_4_n_0;
  wire m_axis_tlast_i_5_n_0;
  wire m_axis_tlast_i_6_n_0;
  wire m_axis_tlast_i_7_n_0;
  wire m_axis_tlast_i_8_n_0;
  wire m_axis_tlast_i_9_n_0;
  wire m_axis_tready;
  wire m_axis_tuser;
  wire m_axis_tvalid;
  wire of_n;
  wire of_p;
  wire of_s;
  wire rst_n;
  wire [31:0]transfer_cnt;
  wire [31:0]transfer_cnt_1;
  wire \transfer_cnt_reg[12]_i_2_n_0 ;
  wire \transfer_cnt_reg[12]_i_2_n_1 ;
  wire \transfer_cnt_reg[12]_i_2_n_2 ;
  wire \transfer_cnt_reg[12]_i_2_n_3 ;
  wire \transfer_cnt_reg[16]_i_2_n_0 ;
  wire \transfer_cnt_reg[16]_i_2_n_1 ;
  wire \transfer_cnt_reg[16]_i_2_n_2 ;
  wire \transfer_cnt_reg[16]_i_2_n_3 ;
  wire \transfer_cnt_reg[20]_i_2_n_0 ;
  wire \transfer_cnt_reg[20]_i_2_n_1 ;
  wire \transfer_cnt_reg[20]_i_2_n_2 ;
  wire \transfer_cnt_reg[20]_i_2_n_3 ;
  wire \transfer_cnt_reg[24]_i_2_n_0 ;
  wire \transfer_cnt_reg[24]_i_2_n_1 ;
  wire \transfer_cnt_reg[24]_i_2_n_2 ;
  wire \transfer_cnt_reg[24]_i_2_n_3 ;
  wire \transfer_cnt_reg[28]_i_2_n_0 ;
  wire \transfer_cnt_reg[28]_i_2_n_1 ;
  wire \transfer_cnt_reg[28]_i_2_n_2 ;
  wire \transfer_cnt_reg[28]_i_2_n_3 ;
  wire \transfer_cnt_reg[31]_i_2_n_2 ;
  wire \transfer_cnt_reg[31]_i_2_n_3 ;
  wire \transfer_cnt_reg[4]_i_2_n_0 ;
  wire \transfer_cnt_reg[4]_i_2_n_1 ;
  wire \transfer_cnt_reg[4]_i_2_n_2 ;
  wire \transfer_cnt_reg[4]_i_2_n_3 ;
  wire \transfer_cnt_reg[8]_i_2_n_0 ;
  wire \transfer_cnt_reg[8]_i_2_n_1 ;
  wire \transfer_cnt_reg[8]_i_2_n_2 ;
  wire \transfer_cnt_reg[8]_i_2_n_3 ;
  wire [3:2]\NLW_transfer_cnt_reg[31]_i_2_CO_UNCONNECTED ;
  wire [3:3]\NLW_transfer_cnt_reg[31]_i_2_O_UNCONNECTED ;

  LUT1 #(
    .INIT(2'h1)) 
    \adc_data[15]_i_1 
       (.I0(rst_n),
        .O(\adc_data[15]_i_1_n_0 ));
  FDCE \adc_data_reg[0] 
       (.C(m_axis_aclk),
        .CE(1'b1),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(data_s[0]),
        .Q(adc_data[0]));
  FDCE \adc_data_reg[10] 
       (.C(m_axis_aclk),
        .CE(1'b1),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(data_s[10]),
        .Q(adc_data[10]));
  FDCE \adc_data_reg[11] 
       (.C(m_axis_aclk),
        .CE(1'b1),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(data_s[11]),
        .Q(adc_data[11]));
  FDCE \adc_data_reg[12] 
       (.C(m_axis_aclk),
        .CE(1'b1),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(data_s[12]),
        .Q(adc_data[12]));
  FDCE \adc_data_reg[13] 
       (.C(m_axis_aclk),
        .CE(1'b1),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(data_s[13]),
        .Q(adc_data[13]));
  FDCE \adc_data_reg[14] 
       (.C(m_axis_aclk),
        .CE(1'b1),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(data_s[14]),
        .Q(adc_data[14]));
  FDCE \adc_data_reg[15] 
       (.C(m_axis_aclk),
        .CE(1'b1),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(data_s[15]),
        .Q(adc_data[15]));
  FDCE \adc_data_reg[1] 
       (.C(m_axis_aclk),
        .CE(1'b1),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(data_s[1]),
        .Q(adc_data[1]));
  FDCE \adc_data_reg[2] 
       (.C(m_axis_aclk),
        .CE(1'b1),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(data_s[2]),
        .Q(adc_data[2]));
  FDCE \adc_data_reg[3] 
       (.C(m_axis_aclk),
        .CE(1'b1),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(data_s[3]),
        .Q(adc_data[3]));
  FDCE \adc_data_reg[4] 
       (.C(m_axis_aclk),
        .CE(1'b1),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(data_s[4]),
        .Q(adc_data[4]));
  FDCE \adc_data_reg[5] 
       (.C(m_axis_aclk),
        .CE(1'b1),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(data_s[5]),
        .Q(adc_data[5]));
  FDCE \adc_data_reg[6] 
       (.C(m_axis_aclk),
        .CE(1'b1),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(data_s[6]),
        .Q(adc_data[6]));
  FDCE \adc_data_reg[7] 
       (.C(m_axis_aclk),
        .CE(1'b1),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(data_s[7]),
        .Q(adc_data[7]));
  FDCE \adc_data_reg[8] 
       (.C(m_axis_aclk),
        .CE(1'b1),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(data_s[8]),
        .Q(adc_data[8]));
  FDCE \adc_data_reg[9] 
       (.C(m_axis_aclk),
        .CE(1'b1),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(data_s[9]),
        .Q(adc_data[9]));
  FDCE adc_of_reg
       (.C(m_axis_aclk),
        .CE(1'b1),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(of_s),
        .Q(adc_of));
  (* BOX_TYPE = "PRIMITIVE" *) 
  (* CAPACITANCE = "DONT_CARE" *) 
  (* IBUF_DELAY_VALUE = "0" *) 
  (* IFD_DELAY_VALUE = "AUTO" *) 
  IBUFDS \gen_data_ibuf[0].u_ibufds_data 
       (.I(data_p[0]),
        .IB(data_n[0]),
        .O(data_s[0]));
  (* BOX_TYPE = "PRIMITIVE" *) 
  (* CAPACITANCE = "DONT_CARE" *) 
  (* IBUF_DELAY_VALUE = "0" *) 
  (* IFD_DELAY_VALUE = "AUTO" *) 
  IBUFDS \gen_data_ibuf[10].u_ibufds_data 
       (.I(data_p[10]),
        .IB(data_n[10]),
        .O(data_s[10]));
  (* BOX_TYPE = "PRIMITIVE" *) 
  (* CAPACITANCE = "DONT_CARE" *) 
  (* IBUF_DELAY_VALUE = "0" *) 
  (* IFD_DELAY_VALUE = "AUTO" *) 
  IBUFDS \gen_data_ibuf[11].u_ibufds_data 
       (.I(data_p[11]),
        .IB(data_n[11]),
        .O(data_s[11]));
  (* BOX_TYPE = "PRIMITIVE" *) 
  (* CAPACITANCE = "DONT_CARE" *) 
  (* IBUF_DELAY_VALUE = "0" *) 
  (* IFD_DELAY_VALUE = "AUTO" *) 
  IBUFDS \gen_data_ibuf[12].u_ibufds_data 
       (.I(data_p[12]),
        .IB(data_n[12]),
        .O(data_s[12]));
  (* BOX_TYPE = "PRIMITIVE" *) 
  (* CAPACITANCE = "DONT_CARE" *) 
  (* IBUF_DELAY_VALUE = "0" *) 
  (* IFD_DELAY_VALUE = "AUTO" *) 
  IBUFDS \gen_data_ibuf[13].u_ibufds_data 
       (.I(data_p[13]),
        .IB(data_n[13]),
        .O(data_s[13]));
  (* BOX_TYPE = "PRIMITIVE" *) 
  (* CAPACITANCE = "DONT_CARE" *) 
  (* IBUF_DELAY_VALUE = "0" *) 
  (* IFD_DELAY_VALUE = "AUTO" *) 
  IBUFDS \gen_data_ibuf[14].u_ibufds_data 
       (.I(data_p[14]),
        .IB(data_n[14]),
        .O(data_s[14]));
  (* BOX_TYPE = "PRIMITIVE" *) 
  (* CAPACITANCE = "DONT_CARE" *) 
  (* IBUF_DELAY_VALUE = "0" *) 
  (* IFD_DELAY_VALUE = "AUTO" *) 
  IBUFDS \gen_data_ibuf[15].u_ibufds_data 
       (.I(data_p[15]),
        .IB(data_n[15]),
        .O(data_s[15]));
  (* BOX_TYPE = "PRIMITIVE" *) 
  (* CAPACITANCE = "DONT_CARE" *) 
  (* IBUF_DELAY_VALUE = "0" *) 
  (* IFD_DELAY_VALUE = "AUTO" *) 
  IBUFDS \gen_data_ibuf[1].u_ibufds_data 
       (.I(data_p[1]),
        .IB(data_n[1]),
        .O(data_s[1]));
  (* BOX_TYPE = "PRIMITIVE" *) 
  (* CAPACITANCE = "DONT_CARE" *) 
  (* IBUF_DELAY_VALUE = "0" *) 
  (* IFD_DELAY_VALUE = "AUTO" *) 
  IBUFDS \gen_data_ibuf[2].u_ibufds_data 
       (.I(data_p[2]),
        .IB(data_n[2]),
        .O(data_s[2]));
  (* BOX_TYPE = "PRIMITIVE" *) 
  (* CAPACITANCE = "DONT_CARE" *) 
  (* IBUF_DELAY_VALUE = "0" *) 
  (* IFD_DELAY_VALUE = "AUTO" *) 
  IBUFDS \gen_data_ibuf[3].u_ibufds_data 
       (.I(data_p[3]),
        .IB(data_n[3]),
        .O(data_s[3]));
  (* BOX_TYPE = "PRIMITIVE" *) 
  (* CAPACITANCE = "DONT_CARE" *) 
  (* IBUF_DELAY_VALUE = "0" *) 
  (* IFD_DELAY_VALUE = "AUTO" *) 
  IBUFDS \gen_data_ibuf[4].u_ibufds_data 
       (.I(data_p[4]),
        .IB(data_n[4]),
        .O(data_s[4]));
  (* BOX_TYPE = "PRIMITIVE" *) 
  (* CAPACITANCE = "DONT_CARE" *) 
  (* IBUF_DELAY_VALUE = "0" *) 
  (* IFD_DELAY_VALUE = "AUTO" *) 
  IBUFDS \gen_data_ibuf[5].u_ibufds_data 
       (.I(data_p[5]),
        .IB(data_n[5]),
        .O(data_s[5]));
  (* BOX_TYPE = "PRIMITIVE" *) 
  (* CAPACITANCE = "DONT_CARE" *) 
  (* IBUF_DELAY_VALUE = "0" *) 
  (* IFD_DELAY_VALUE = "AUTO" *) 
  IBUFDS \gen_data_ibuf[6].u_ibufds_data 
       (.I(data_p[6]),
        .IB(data_n[6]),
        .O(data_s[6]));
  (* BOX_TYPE = "PRIMITIVE" *) 
  (* CAPACITANCE = "DONT_CARE" *) 
  (* IBUF_DELAY_VALUE = "0" *) 
  (* IFD_DELAY_VALUE = "AUTO" *) 
  IBUFDS \gen_data_ibuf[7].u_ibufds_data 
       (.I(data_p[7]),
        .IB(data_n[7]),
        .O(data_s[7]));
  (* BOX_TYPE = "PRIMITIVE" *) 
  (* CAPACITANCE = "DONT_CARE" *) 
  (* IBUF_DELAY_VALUE = "0" *) 
  (* IFD_DELAY_VALUE = "AUTO" *) 
  IBUFDS \gen_data_ibuf[8].u_ibufds_data 
       (.I(data_p[8]),
        .IB(data_n[8]),
        .O(data_s[8]));
  (* BOX_TYPE = "PRIMITIVE" *) 
  (* CAPACITANCE = "DONT_CARE" *) 
  (* IBUF_DELAY_VALUE = "0" *) 
  (* IFD_DELAY_VALUE = "AUTO" *) 
  IBUFDS \gen_data_ibuf[9].u_ibufds_data 
       (.I(data_p[9]),
        .IB(data_n[9]),
        .O(data_s[9]));
  LUT2 #(
    .INIT(4'hB)) 
    \m_axis_tdata[15]_i_1 
       (.I0(m_axis_tready),
        .I1(m_axis_tvalid),
        .O(m_axis_tdata0));
  FDCE \m_axis_tdata_reg[0] 
       (.C(m_axis_aclk),
        .CE(m_axis_tdata0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(data_s[0]),
        .Q(m_axis_tdata[0]));
  FDCE \m_axis_tdata_reg[10] 
       (.C(m_axis_aclk),
        .CE(m_axis_tdata0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(data_s[10]),
        .Q(m_axis_tdata[10]));
  FDCE \m_axis_tdata_reg[11] 
       (.C(m_axis_aclk),
        .CE(m_axis_tdata0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(data_s[11]),
        .Q(m_axis_tdata[11]));
  FDCE \m_axis_tdata_reg[12] 
       (.C(m_axis_aclk),
        .CE(m_axis_tdata0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(data_s[12]),
        .Q(m_axis_tdata[12]));
  FDCE \m_axis_tdata_reg[13] 
       (.C(m_axis_aclk),
        .CE(m_axis_tdata0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(data_s[13]),
        .Q(m_axis_tdata[13]));
  FDCE \m_axis_tdata_reg[14] 
       (.C(m_axis_aclk),
        .CE(m_axis_tdata0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(data_s[14]),
        .Q(m_axis_tdata[14]));
  FDCE \m_axis_tdata_reg[15] 
       (.C(m_axis_aclk),
        .CE(m_axis_tdata0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(data_s[15]),
        .Q(m_axis_tdata[15]));
  FDCE \m_axis_tdata_reg[1] 
       (.C(m_axis_aclk),
        .CE(m_axis_tdata0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(data_s[1]),
        .Q(m_axis_tdata[1]));
  FDCE \m_axis_tdata_reg[2] 
       (.C(m_axis_aclk),
        .CE(m_axis_tdata0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(data_s[2]),
        .Q(m_axis_tdata[2]));
  FDCE \m_axis_tdata_reg[3] 
       (.C(m_axis_aclk),
        .CE(m_axis_tdata0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(data_s[3]),
        .Q(m_axis_tdata[3]));
  FDCE \m_axis_tdata_reg[4] 
       (.C(m_axis_aclk),
        .CE(m_axis_tdata0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(data_s[4]),
        .Q(m_axis_tdata[4]));
  FDCE \m_axis_tdata_reg[5] 
       (.C(m_axis_aclk),
        .CE(m_axis_tdata0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(data_s[5]),
        .Q(m_axis_tdata[5]));
  FDCE \m_axis_tdata_reg[6] 
       (.C(m_axis_aclk),
        .CE(m_axis_tdata0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(data_s[6]),
        .Q(m_axis_tdata[6]));
  FDCE \m_axis_tdata_reg[7] 
       (.C(m_axis_aclk),
        .CE(m_axis_tdata0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(data_s[7]),
        .Q(m_axis_tdata[7]));
  FDCE \m_axis_tdata_reg[8] 
       (.C(m_axis_aclk),
        .CE(m_axis_tdata0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(data_s[8]),
        .Q(m_axis_tdata[8]));
  FDCE \m_axis_tdata_reg[9] 
       (.C(m_axis_aclk),
        .CE(m_axis_tdata0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(data_s[9]),
        .Q(m_axis_tdata[9]));
  LUT2 #(
    .INIT(4'h8)) 
    m_axis_tlast_i_1
       (.I0(m_axis_tready),
        .I1(m_axis_tvalid),
        .O(m_axis_tlast_i_1_n_0));
  LUT4 #(
    .INIT(16'hFFFE)) 
    m_axis_tlast_i_10
       (.I0(transfer_cnt[13]),
        .I1(transfer_cnt[12]),
        .I2(transfer_cnt[15]),
        .I3(transfer_cnt[14]),
        .O(m_axis_tlast_i_10_n_0));
  (* SOFT_HLUTNM = "soft_lutpair0" *) 
  LUT4 #(
    .INIT(16'h0001)) 
    m_axis_tlast_i_2
       (.I0(m_axis_tlast_i_3_n_0),
        .I1(m_axis_tlast_i_4_n_0),
        .I2(m_axis_tlast_i_5_n_0),
        .I3(m_axis_tlast_i_6_n_0),
        .O(m_axis_tlast_0));
  LUT5 #(
    .INIT(32'hFFFFFFFE)) 
    m_axis_tlast_i_3
       (.I0(transfer_cnt[18]),
        .I1(transfer_cnt[19]),
        .I2(transfer_cnt[16]),
        .I3(transfer_cnt[17]),
        .I4(m_axis_tlast_i_7_n_0),
        .O(m_axis_tlast_i_3_n_0));
  LUT5 #(
    .INIT(32'hFFFFFFFE)) 
    m_axis_tlast_i_4
       (.I0(transfer_cnt[26]),
        .I1(transfer_cnt[27]),
        .I2(transfer_cnt[24]),
        .I3(transfer_cnt[25]),
        .I4(m_axis_tlast_i_8_n_0),
        .O(m_axis_tlast_i_4_n_0));
  LUT5 #(
    .INIT(32'hFFFF7FFF)) 
    m_axis_tlast_i_5
       (.I0(transfer_cnt[2]),
        .I1(transfer_cnt[3]),
        .I2(transfer_cnt[0]),
        .I3(transfer_cnt[1]),
        .I4(m_axis_tlast_i_9_n_0),
        .O(m_axis_tlast_i_5_n_0));
  LUT5 #(
    .INIT(32'hFFFF7FFF)) 
    m_axis_tlast_i_6
       (.I0(transfer_cnt[10]),
        .I1(transfer_cnt[11]),
        .I2(transfer_cnt[8]),
        .I3(transfer_cnt[9]),
        .I4(m_axis_tlast_i_10_n_0),
        .O(m_axis_tlast_i_6_n_0));
  LUT4 #(
    .INIT(16'hFFFE)) 
    m_axis_tlast_i_7
       (.I0(transfer_cnt[21]),
        .I1(transfer_cnt[20]),
        .I2(transfer_cnt[23]),
        .I3(transfer_cnt[22]),
        .O(m_axis_tlast_i_7_n_0));
  LUT4 #(
    .INIT(16'hFFFE)) 
    m_axis_tlast_i_8
       (.I0(transfer_cnt[29]),
        .I1(transfer_cnt[28]),
        .I2(transfer_cnt[31]),
        .I3(transfer_cnt[30]),
        .O(m_axis_tlast_i_8_n_0));
  LUT4 #(
    .INIT(16'h7FFF)) 
    m_axis_tlast_i_9
       (.I0(transfer_cnt[5]),
        .I1(transfer_cnt[4]),
        .I2(transfer_cnt[7]),
        .I3(transfer_cnt[6]),
        .O(m_axis_tlast_i_9_n_0));
  FDCE m_axis_tlast_reg
       (.C(m_axis_aclk),
        .CE(m_axis_tlast_i_1_n_0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(m_axis_tlast_0),
        .Q(m_axis_tlast));
  FDCE m_axis_tuser_reg
       (.C(m_axis_aclk),
        .CE(m_axis_tdata0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(of_s),
        .Q(m_axis_tuser));
  FDCE m_axis_tvalid_reg
       (.C(m_axis_aclk),
        .CE(m_axis_tdata0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(m_axis_tdata0),
        .Q(m_axis_tvalid));
  LUT1 #(
    .INIT(2'h1)) 
    \transfer_cnt[0]_i_1 
       (.I0(transfer_cnt[0]),
        .O(transfer_cnt_1[0]));
  LUT5 #(
    .INIT(32'hFFFE0000)) 
    \transfer_cnt[10]_i_1 
       (.I0(m_axis_tlast_i_3_n_0),
        .I1(m_axis_tlast_i_4_n_0),
        .I2(m_axis_tlast_i_5_n_0),
        .I3(m_axis_tlast_i_6_n_0),
        .I4(data0[10]),
        .O(transfer_cnt_1[10]));
  LUT5 #(
    .INIT(32'hFFFE0000)) 
    \transfer_cnt[11]_i_1 
       (.I0(m_axis_tlast_i_3_n_0),
        .I1(m_axis_tlast_i_4_n_0),
        .I2(m_axis_tlast_i_5_n_0),
        .I3(m_axis_tlast_i_6_n_0),
        .I4(data0[11]),
        .O(transfer_cnt_1[11]));
  LUT5 #(
    .INIT(32'hFFFE0000)) 
    \transfer_cnt[12]_i_1 
       (.I0(m_axis_tlast_i_3_n_0),
        .I1(m_axis_tlast_i_4_n_0),
        .I2(m_axis_tlast_i_5_n_0),
        .I3(m_axis_tlast_i_6_n_0),
        .I4(data0[12]),
        .O(transfer_cnt_1[12]));
  LUT5 #(
    .INIT(32'hFFFE0000)) 
    \transfer_cnt[13]_i_1 
       (.I0(m_axis_tlast_i_3_n_0),
        .I1(m_axis_tlast_i_4_n_0),
        .I2(m_axis_tlast_i_5_n_0),
        .I3(m_axis_tlast_i_6_n_0),
        .I4(data0[13]),
        .O(transfer_cnt_1[13]));
  LUT5 #(
    .INIT(32'hFFFE0000)) 
    \transfer_cnt[14]_i_1 
       (.I0(m_axis_tlast_i_3_n_0),
        .I1(m_axis_tlast_i_4_n_0),
        .I2(m_axis_tlast_i_5_n_0),
        .I3(m_axis_tlast_i_6_n_0),
        .I4(data0[14]),
        .O(transfer_cnt_1[14]));
  LUT5 #(
    .INIT(32'hFFFE0000)) 
    \transfer_cnt[15]_i_1 
       (.I0(m_axis_tlast_i_3_n_0),
        .I1(m_axis_tlast_i_4_n_0),
        .I2(m_axis_tlast_i_5_n_0),
        .I3(m_axis_tlast_i_6_n_0),
        .I4(data0[15]),
        .O(transfer_cnt_1[15]));
  LUT5 #(
    .INIT(32'hFFFE0000)) 
    \transfer_cnt[16]_i_1 
       (.I0(m_axis_tlast_i_3_n_0),
        .I1(m_axis_tlast_i_4_n_0),
        .I2(m_axis_tlast_i_5_n_0),
        .I3(m_axis_tlast_i_6_n_0),
        .I4(data0[16]),
        .O(transfer_cnt_1[16]));
  LUT5 #(
    .INIT(32'hFFFE0000)) 
    \transfer_cnt[17]_i_1 
       (.I0(m_axis_tlast_i_3_n_0),
        .I1(m_axis_tlast_i_4_n_0),
        .I2(m_axis_tlast_i_5_n_0),
        .I3(m_axis_tlast_i_6_n_0),
        .I4(data0[17]),
        .O(transfer_cnt_1[17]));
  LUT5 #(
    .INIT(32'hFFFE0000)) 
    \transfer_cnt[18]_i_1 
       (.I0(m_axis_tlast_i_3_n_0),
        .I1(m_axis_tlast_i_4_n_0),
        .I2(m_axis_tlast_i_5_n_0),
        .I3(m_axis_tlast_i_6_n_0),
        .I4(data0[18]),
        .O(transfer_cnt_1[18]));
  LUT5 #(
    .INIT(32'hFFFE0000)) 
    \transfer_cnt[19]_i_1 
       (.I0(m_axis_tlast_i_3_n_0),
        .I1(m_axis_tlast_i_4_n_0),
        .I2(m_axis_tlast_i_5_n_0),
        .I3(m_axis_tlast_i_6_n_0),
        .I4(data0[19]),
        .O(transfer_cnt_1[19]));
  (* SOFT_HLUTNM = "soft_lutpair0" *) 
  LUT5 #(
    .INIT(32'hFFFE0000)) 
    \transfer_cnt[1]_i_1 
       (.I0(m_axis_tlast_i_3_n_0),
        .I1(m_axis_tlast_i_4_n_0),
        .I2(m_axis_tlast_i_5_n_0),
        .I3(m_axis_tlast_i_6_n_0),
        .I4(data0[1]),
        .O(transfer_cnt_1[1]));
  LUT5 #(
    .INIT(32'hFFFE0000)) 
    \transfer_cnt[20]_i_1 
       (.I0(m_axis_tlast_i_3_n_0),
        .I1(m_axis_tlast_i_4_n_0),
        .I2(m_axis_tlast_i_5_n_0),
        .I3(m_axis_tlast_i_6_n_0),
        .I4(data0[20]),
        .O(transfer_cnt_1[20]));
  LUT5 #(
    .INIT(32'hFFFE0000)) 
    \transfer_cnt[21]_i_1 
       (.I0(m_axis_tlast_i_3_n_0),
        .I1(m_axis_tlast_i_4_n_0),
        .I2(m_axis_tlast_i_5_n_0),
        .I3(m_axis_tlast_i_6_n_0),
        .I4(data0[21]),
        .O(transfer_cnt_1[21]));
  LUT5 #(
    .INIT(32'hFFFE0000)) 
    \transfer_cnt[22]_i_1 
       (.I0(m_axis_tlast_i_3_n_0),
        .I1(m_axis_tlast_i_4_n_0),
        .I2(m_axis_tlast_i_5_n_0),
        .I3(m_axis_tlast_i_6_n_0),
        .I4(data0[22]),
        .O(transfer_cnt_1[22]));
  LUT5 #(
    .INIT(32'hFFFE0000)) 
    \transfer_cnt[23]_i_1 
       (.I0(m_axis_tlast_i_3_n_0),
        .I1(m_axis_tlast_i_4_n_0),
        .I2(m_axis_tlast_i_5_n_0),
        .I3(m_axis_tlast_i_6_n_0),
        .I4(data0[23]),
        .O(transfer_cnt_1[23]));
  LUT5 #(
    .INIT(32'hFFFE0000)) 
    \transfer_cnt[24]_i_1 
       (.I0(m_axis_tlast_i_3_n_0),
        .I1(m_axis_tlast_i_4_n_0),
        .I2(m_axis_tlast_i_5_n_0),
        .I3(m_axis_tlast_i_6_n_0),
        .I4(data0[24]),
        .O(transfer_cnt_1[24]));
  LUT5 #(
    .INIT(32'hFFFE0000)) 
    \transfer_cnt[25]_i_1 
       (.I0(m_axis_tlast_i_3_n_0),
        .I1(m_axis_tlast_i_4_n_0),
        .I2(m_axis_tlast_i_5_n_0),
        .I3(m_axis_tlast_i_6_n_0),
        .I4(data0[25]),
        .O(transfer_cnt_1[25]));
  LUT5 #(
    .INIT(32'hFFFE0000)) 
    \transfer_cnt[26]_i_1 
       (.I0(m_axis_tlast_i_3_n_0),
        .I1(m_axis_tlast_i_4_n_0),
        .I2(m_axis_tlast_i_5_n_0),
        .I3(m_axis_tlast_i_6_n_0),
        .I4(data0[26]),
        .O(transfer_cnt_1[26]));
  LUT5 #(
    .INIT(32'hFFFE0000)) 
    \transfer_cnt[27]_i_1 
       (.I0(m_axis_tlast_i_3_n_0),
        .I1(m_axis_tlast_i_4_n_0),
        .I2(m_axis_tlast_i_5_n_0),
        .I3(m_axis_tlast_i_6_n_0),
        .I4(data0[27]),
        .O(transfer_cnt_1[27]));
  LUT5 #(
    .INIT(32'hFFFE0000)) 
    \transfer_cnt[28]_i_1 
       (.I0(m_axis_tlast_i_3_n_0),
        .I1(m_axis_tlast_i_4_n_0),
        .I2(m_axis_tlast_i_5_n_0),
        .I3(m_axis_tlast_i_6_n_0),
        .I4(data0[28]),
        .O(transfer_cnt_1[28]));
  LUT5 #(
    .INIT(32'hFFFE0000)) 
    \transfer_cnt[29]_i_1 
       (.I0(m_axis_tlast_i_3_n_0),
        .I1(m_axis_tlast_i_4_n_0),
        .I2(m_axis_tlast_i_5_n_0),
        .I3(m_axis_tlast_i_6_n_0),
        .I4(data0[29]),
        .O(transfer_cnt_1[29]));
  LUT5 #(
    .INIT(32'hFFFE0000)) 
    \transfer_cnt[2]_i_1 
       (.I0(m_axis_tlast_i_3_n_0),
        .I1(m_axis_tlast_i_4_n_0),
        .I2(m_axis_tlast_i_5_n_0),
        .I3(m_axis_tlast_i_6_n_0),
        .I4(data0[2]),
        .O(transfer_cnt_1[2]));
  LUT5 #(
    .INIT(32'hFFFE0000)) 
    \transfer_cnt[30]_i_1 
       (.I0(m_axis_tlast_i_3_n_0),
        .I1(m_axis_tlast_i_4_n_0),
        .I2(m_axis_tlast_i_5_n_0),
        .I3(m_axis_tlast_i_6_n_0),
        .I4(data0[30]),
        .O(transfer_cnt_1[30]));
  LUT5 #(
    .INIT(32'hFFFE0000)) 
    \transfer_cnt[31]_i_1 
       (.I0(m_axis_tlast_i_3_n_0),
        .I1(m_axis_tlast_i_4_n_0),
        .I2(m_axis_tlast_i_5_n_0),
        .I3(m_axis_tlast_i_6_n_0),
        .I4(data0[31]),
        .O(transfer_cnt_1[31]));
  LUT5 #(
    .INIT(32'hFFFE0000)) 
    \transfer_cnt[3]_i_1 
       (.I0(m_axis_tlast_i_3_n_0),
        .I1(m_axis_tlast_i_4_n_0),
        .I2(m_axis_tlast_i_5_n_0),
        .I3(m_axis_tlast_i_6_n_0),
        .I4(data0[3]),
        .O(transfer_cnt_1[3]));
  LUT5 #(
    .INIT(32'hFFFE0000)) 
    \transfer_cnt[4]_i_1 
       (.I0(m_axis_tlast_i_3_n_0),
        .I1(m_axis_tlast_i_4_n_0),
        .I2(m_axis_tlast_i_5_n_0),
        .I3(m_axis_tlast_i_6_n_0),
        .I4(data0[4]),
        .O(transfer_cnt_1[4]));
  LUT5 #(
    .INIT(32'hFFFE0000)) 
    \transfer_cnt[5]_i_1 
       (.I0(m_axis_tlast_i_3_n_0),
        .I1(m_axis_tlast_i_4_n_0),
        .I2(m_axis_tlast_i_5_n_0),
        .I3(m_axis_tlast_i_6_n_0),
        .I4(data0[5]),
        .O(transfer_cnt_1[5]));
  LUT5 #(
    .INIT(32'hFFFE0000)) 
    \transfer_cnt[6]_i_1 
       (.I0(m_axis_tlast_i_3_n_0),
        .I1(m_axis_tlast_i_4_n_0),
        .I2(m_axis_tlast_i_5_n_0),
        .I3(m_axis_tlast_i_6_n_0),
        .I4(data0[6]),
        .O(transfer_cnt_1[6]));
  LUT5 #(
    .INIT(32'hFFFE0000)) 
    \transfer_cnt[7]_i_1 
       (.I0(m_axis_tlast_i_3_n_0),
        .I1(m_axis_tlast_i_4_n_0),
        .I2(m_axis_tlast_i_5_n_0),
        .I3(m_axis_tlast_i_6_n_0),
        .I4(data0[7]),
        .O(transfer_cnt_1[7]));
  LUT5 #(
    .INIT(32'hFFFE0000)) 
    \transfer_cnt[8]_i_1 
       (.I0(m_axis_tlast_i_3_n_0),
        .I1(m_axis_tlast_i_4_n_0),
        .I2(m_axis_tlast_i_5_n_0),
        .I3(m_axis_tlast_i_6_n_0),
        .I4(data0[8]),
        .O(transfer_cnt_1[8]));
  LUT5 #(
    .INIT(32'hFFFE0000)) 
    \transfer_cnt[9]_i_1 
       (.I0(m_axis_tlast_i_3_n_0),
        .I1(m_axis_tlast_i_4_n_0),
        .I2(m_axis_tlast_i_5_n_0),
        .I3(m_axis_tlast_i_6_n_0),
        .I4(data0[9]),
        .O(transfer_cnt_1[9]));
  FDCE \transfer_cnt_reg[0] 
       (.C(m_axis_aclk),
        .CE(m_axis_tlast_i_1_n_0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(transfer_cnt_1[0]),
        .Q(transfer_cnt[0]));
  FDCE \transfer_cnt_reg[10] 
       (.C(m_axis_aclk),
        .CE(m_axis_tlast_i_1_n_0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(transfer_cnt_1[10]),
        .Q(transfer_cnt[10]));
  FDCE \transfer_cnt_reg[11] 
       (.C(m_axis_aclk),
        .CE(m_axis_tlast_i_1_n_0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(transfer_cnt_1[11]),
        .Q(transfer_cnt[11]));
  FDCE \transfer_cnt_reg[12] 
       (.C(m_axis_aclk),
        .CE(m_axis_tlast_i_1_n_0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(transfer_cnt_1[12]),
        .Q(transfer_cnt[12]));
  (* ADDER_THRESHOLD = "35" *) 
  CARRY4 \transfer_cnt_reg[12]_i_2 
       (.CI(\transfer_cnt_reg[8]_i_2_n_0 ),
        .CO({\transfer_cnt_reg[12]_i_2_n_0 ,\transfer_cnt_reg[12]_i_2_n_1 ,\transfer_cnt_reg[12]_i_2_n_2 ,\transfer_cnt_reg[12]_i_2_n_3 }),
        .CYINIT(1'b0),
        .DI({1'b0,1'b0,1'b0,1'b0}),
        .O(data0[12:9]),
        .S(transfer_cnt[12:9]));
  FDCE \transfer_cnt_reg[13] 
       (.C(m_axis_aclk),
        .CE(m_axis_tlast_i_1_n_0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(transfer_cnt_1[13]),
        .Q(transfer_cnt[13]));
  FDCE \transfer_cnt_reg[14] 
       (.C(m_axis_aclk),
        .CE(m_axis_tlast_i_1_n_0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(transfer_cnt_1[14]),
        .Q(transfer_cnt[14]));
  FDCE \transfer_cnt_reg[15] 
       (.C(m_axis_aclk),
        .CE(m_axis_tlast_i_1_n_0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(transfer_cnt_1[15]),
        .Q(transfer_cnt[15]));
  FDCE \transfer_cnt_reg[16] 
       (.C(m_axis_aclk),
        .CE(m_axis_tlast_i_1_n_0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(transfer_cnt_1[16]),
        .Q(transfer_cnt[16]));
  (* ADDER_THRESHOLD = "35" *) 
  CARRY4 \transfer_cnt_reg[16]_i_2 
       (.CI(\transfer_cnt_reg[12]_i_2_n_0 ),
        .CO({\transfer_cnt_reg[16]_i_2_n_0 ,\transfer_cnt_reg[16]_i_2_n_1 ,\transfer_cnt_reg[16]_i_2_n_2 ,\transfer_cnt_reg[16]_i_2_n_3 }),
        .CYINIT(1'b0),
        .DI({1'b0,1'b0,1'b0,1'b0}),
        .O(data0[16:13]),
        .S(transfer_cnt[16:13]));
  FDCE \transfer_cnt_reg[17] 
       (.C(m_axis_aclk),
        .CE(m_axis_tlast_i_1_n_0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(transfer_cnt_1[17]),
        .Q(transfer_cnt[17]));
  FDCE \transfer_cnt_reg[18] 
       (.C(m_axis_aclk),
        .CE(m_axis_tlast_i_1_n_0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(transfer_cnt_1[18]),
        .Q(transfer_cnt[18]));
  FDCE \transfer_cnt_reg[19] 
       (.C(m_axis_aclk),
        .CE(m_axis_tlast_i_1_n_0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(transfer_cnt_1[19]),
        .Q(transfer_cnt[19]));
  FDCE \transfer_cnt_reg[1] 
       (.C(m_axis_aclk),
        .CE(m_axis_tlast_i_1_n_0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(transfer_cnt_1[1]),
        .Q(transfer_cnt[1]));
  FDCE \transfer_cnt_reg[20] 
       (.C(m_axis_aclk),
        .CE(m_axis_tlast_i_1_n_0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(transfer_cnt_1[20]),
        .Q(transfer_cnt[20]));
  (* ADDER_THRESHOLD = "35" *) 
  CARRY4 \transfer_cnt_reg[20]_i_2 
       (.CI(\transfer_cnt_reg[16]_i_2_n_0 ),
        .CO({\transfer_cnt_reg[20]_i_2_n_0 ,\transfer_cnt_reg[20]_i_2_n_1 ,\transfer_cnt_reg[20]_i_2_n_2 ,\transfer_cnt_reg[20]_i_2_n_3 }),
        .CYINIT(1'b0),
        .DI({1'b0,1'b0,1'b0,1'b0}),
        .O(data0[20:17]),
        .S(transfer_cnt[20:17]));
  FDCE \transfer_cnt_reg[21] 
       (.C(m_axis_aclk),
        .CE(m_axis_tlast_i_1_n_0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(transfer_cnt_1[21]),
        .Q(transfer_cnt[21]));
  FDCE \transfer_cnt_reg[22] 
       (.C(m_axis_aclk),
        .CE(m_axis_tlast_i_1_n_0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(transfer_cnt_1[22]),
        .Q(transfer_cnt[22]));
  FDCE \transfer_cnt_reg[23] 
       (.C(m_axis_aclk),
        .CE(m_axis_tlast_i_1_n_0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(transfer_cnt_1[23]),
        .Q(transfer_cnt[23]));
  FDCE \transfer_cnt_reg[24] 
       (.C(m_axis_aclk),
        .CE(m_axis_tlast_i_1_n_0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(transfer_cnt_1[24]),
        .Q(transfer_cnt[24]));
  (* ADDER_THRESHOLD = "35" *) 
  CARRY4 \transfer_cnt_reg[24]_i_2 
       (.CI(\transfer_cnt_reg[20]_i_2_n_0 ),
        .CO({\transfer_cnt_reg[24]_i_2_n_0 ,\transfer_cnt_reg[24]_i_2_n_1 ,\transfer_cnt_reg[24]_i_2_n_2 ,\transfer_cnt_reg[24]_i_2_n_3 }),
        .CYINIT(1'b0),
        .DI({1'b0,1'b0,1'b0,1'b0}),
        .O(data0[24:21]),
        .S(transfer_cnt[24:21]));
  FDCE \transfer_cnt_reg[25] 
       (.C(m_axis_aclk),
        .CE(m_axis_tlast_i_1_n_0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(transfer_cnt_1[25]),
        .Q(transfer_cnt[25]));
  FDCE \transfer_cnt_reg[26] 
       (.C(m_axis_aclk),
        .CE(m_axis_tlast_i_1_n_0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(transfer_cnt_1[26]),
        .Q(transfer_cnt[26]));
  FDCE \transfer_cnt_reg[27] 
       (.C(m_axis_aclk),
        .CE(m_axis_tlast_i_1_n_0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(transfer_cnt_1[27]),
        .Q(transfer_cnt[27]));
  FDCE \transfer_cnt_reg[28] 
       (.C(m_axis_aclk),
        .CE(m_axis_tlast_i_1_n_0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(transfer_cnt_1[28]),
        .Q(transfer_cnt[28]));
  (* ADDER_THRESHOLD = "35" *) 
  CARRY4 \transfer_cnt_reg[28]_i_2 
       (.CI(\transfer_cnt_reg[24]_i_2_n_0 ),
        .CO({\transfer_cnt_reg[28]_i_2_n_0 ,\transfer_cnt_reg[28]_i_2_n_1 ,\transfer_cnt_reg[28]_i_2_n_2 ,\transfer_cnt_reg[28]_i_2_n_3 }),
        .CYINIT(1'b0),
        .DI({1'b0,1'b0,1'b0,1'b0}),
        .O(data0[28:25]),
        .S(transfer_cnt[28:25]));
  FDCE \transfer_cnt_reg[29] 
       (.C(m_axis_aclk),
        .CE(m_axis_tlast_i_1_n_0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(transfer_cnt_1[29]),
        .Q(transfer_cnt[29]));
  FDCE \transfer_cnt_reg[2] 
       (.C(m_axis_aclk),
        .CE(m_axis_tlast_i_1_n_0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(transfer_cnt_1[2]),
        .Q(transfer_cnt[2]));
  FDCE \transfer_cnt_reg[30] 
       (.C(m_axis_aclk),
        .CE(m_axis_tlast_i_1_n_0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(transfer_cnt_1[30]),
        .Q(transfer_cnt[30]));
  FDCE \transfer_cnt_reg[31] 
       (.C(m_axis_aclk),
        .CE(m_axis_tlast_i_1_n_0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(transfer_cnt_1[31]),
        .Q(transfer_cnt[31]));
  (* ADDER_THRESHOLD = "35" *) 
  CARRY4 \transfer_cnt_reg[31]_i_2 
       (.CI(\transfer_cnt_reg[28]_i_2_n_0 ),
        .CO({\NLW_transfer_cnt_reg[31]_i_2_CO_UNCONNECTED [3:2],\transfer_cnt_reg[31]_i_2_n_2 ,\transfer_cnt_reg[31]_i_2_n_3 }),
        .CYINIT(1'b0),
        .DI({1'b0,1'b0,1'b0,1'b0}),
        .O({\NLW_transfer_cnt_reg[31]_i_2_O_UNCONNECTED [3],data0[31:29]}),
        .S({1'b0,transfer_cnt[31:29]}));
  FDCE \transfer_cnt_reg[3] 
       (.C(m_axis_aclk),
        .CE(m_axis_tlast_i_1_n_0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(transfer_cnt_1[3]),
        .Q(transfer_cnt[3]));
  FDCE \transfer_cnt_reg[4] 
       (.C(m_axis_aclk),
        .CE(m_axis_tlast_i_1_n_0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(transfer_cnt_1[4]),
        .Q(transfer_cnt[4]));
  (* ADDER_THRESHOLD = "35" *) 
  CARRY4 \transfer_cnt_reg[4]_i_2 
       (.CI(1'b0),
        .CO({\transfer_cnt_reg[4]_i_2_n_0 ,\transfer_cnt_reg[4]_i_2_n_1 ,\transfer_cnt_reg[4]_i_2_n_2 ,\transfer_cnt_reg[4]_i_2_n_3 }),
        .CYINIT(transfer_cnt[0]),
        .DI({1'b0,1'b0,1'b0,1'b0}),
        .O(data0[4:1]),
        .S(transfer_cnt[4:1]));
  FDCE \transfer_cnt_reg[5] 
       (.C(m_axis_aclk),
        .CE(m_axis_tlast_i_1_n_0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(transfer_cnt_1[5]),
        .Q(transfer_cnt[5]));
  FDCE \transfer_cnt_reg[6] 
       (.C(m_axis_aclk),
        .CE(m_axis_tlast_i_1_n_0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(transfer_cnt_1[6]),
        .Q(transfer_cnt[6]));
  FDCE \transfer_cnt_reg[7] 
       (.C(m_axis_aclk),
        .CE(m_axis_tlast_i_1_n_0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(transfer_cnt_1[7]),
        .Q(transfer_cnt[7]));
  FDCE \transfer_cnt_reg[8] 
       (.C(m_axis_aclk),
        .CE(m_axis_tlast_i_1_n_0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(transfer_cnt_1[8]),
        .Q(transfer_cnt[8]));
  (* ADDER_THRESHOLD = "35" *) 
  CARRY4 \transfer_cnt_reg[8]_i_2 
       (.CI(\transfer_cnt_reg[4]_i_2_n_0 ),
        .CO({\transfer_cnt_reg[8]_i_2_n_0 ,\transfer_cnt_reg[8]_i_2_n_1 ,\transfer_cnt_reg[8]_i_2_n_2 ,\transfer_cnt_reg[8]_i_2_n_3 }),
        .CYINIT(1'b0),
        .DI({1'b0,1'b0,1'b0,1'b0}),
        .O(data0[8:5]),
        .S(transfer_cnt[8:5]));
  FDCE \transfer_cnt_reg[9] 
       (.C(m_axis_aclk),
        .CE(m_axis_tlast_i_1_n_0),
        .CLR(\adc_data[15]_i_1_n_0 ),
        .D(transfer_cnt_1[9]),
        .Q(transfer_cnt[9]));
  (* BOX_TYPE = "PRIMITIVE" *) 
  (* CAPACITANCE = "DONT_CARE" *) 
  (* IBUF_DELAY_VALUE = "0" *) 
  (* IFD_DELAY_VALUE = "AUTO" *) 
  IBUFDS u_ibufds_clkout
       (.I(clkout_p),
        .IB(clkout_n),
        .O(m_axis_aclk));
  (* BOX_TYPE = "PRIMITIVE" *) 
  (* CAPACITANCE = "DONT_CARE" *) 
  (* IBUF_DELAY_VALUE = "0" *) 
  (* IFD_DELAY_VALUE = "AUTO" *) 
  IBUFDS u_ibufds_of
       (.I(of_p),
        .IB(of_n),
        .O(of_s));
  (* BOX_TYPE = "PRIMITIVE" *) 
  (* CAPACITANCE = "DONT_CARE" *) 
  OBUFDS u_obufds_enc
       (.I(enc_clk),
        .O(enc_p),
        .OB(enc_n));
endmodule

(* CHECK_LICENSE_TYPE = "system_LTC2208_0_0,LTC2208,{}" *) (* DowngradeIPIdentifiedWarnings = "yes" *) (* IP_DEFINITION_SOURCE = "module_ref" *) 
(* X_CORE_INFO = "LTC2208,Vivado 2021.1" *) 
(* NotValidForBitStream *)
module decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix
   (rst_n,
    enc_clk,
    enc_p,
    enc_n,
    clkout_p,
    clkout_n,
    data_p,
    data_n,
    of_p,
    of_n,
    adc_data,
    adc_of,
    adc_clk,
    m_axis_aclk,
    m_axis_tdata,
    m_axis_tvalid,
    m_axis_tready,
    m_axis_tlast,
    m_axis_tuser);
  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst_n RST" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME rst_n, POLARITY ACTIVE_LOW, INSERT_VIP 0" *) input rst_n;
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 enc_clk CLK" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME enc_clk, FREQ_HZ 130000000, FREQ_TOLERANCE_HZ 0, PHASE 0.0, CLK_DOMAIN /clk_wiz_0_clk_out1, INSERT_VIP 0" *) input enc_clk;
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
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 adc_clk CLK" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME adc_clk, FREQ_HZ 100000000, FREQ_TOLERANCE_HZ 0, PHASE 0.0, CLK_DOMAIN system_LTC2208_0_0_adc_clk, INSERT_VIP 0" *) output adc_clk;
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 m_axis_aclk CLK" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME m_axis_aclk, ASSOCIATED_BUSIF m_axis, FREQ_HZ 100000000, FREQ_TOLERANCE_HZ 0, PHASE 0.0, CLK_DOMAIN system_LTC2208_0_0_m_axis_aclk, INSERT_VIP 0" *) output m_axis_aclk;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis TDATA" *) output [15:0]m_axis_tdata;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis TVALID" *) output m_axis_tvalid;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis TREADY" *) input m_axis_tready;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis TLAST" *) output m_axis_tlast;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis TUSER" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME m_axis, TDATA_NUM_BYTES 2, TDEST_WIDTH 0, TID_WIDTH 0, TUSER_WIDTH 1, HAS_TREADY 1, HAS_TSTRB 0, HAS_TKEEP 0, HAS_TLAST 1, FREQ_HZ 100000000, PHASE 0.0, CLK_DOMAIN system_LTC2208_0_0_m_axis_aclk, LAYERED_METADATA undef, INSERT_VIP 0" *) output m_axis_tuser;

  wire [15:0]adc_data;
  wire adc_of;
  (* DIFF_TERM *) (* IBUF_LOW_PWR *) (* IOSTANDARD = "LVDS_25" *) wire clkout_n;
  (* DIFF_TERM *) (* IBUF_LOW_PWR *) (* IOSTANDARD = "LVDS_25" *) wire clkout_p;
  (* DIFF_TERM *) (* IBUF_LOW_PWR *) (* IOSTANDARD = "LVDS_25" *) wire [15:0]data_n;
  (* DIFF_TERM *) (* IBUF_LOW_PWR *) (* IOSTANDARD = "LVDS_25" *) wire [15:0]data_p;
  (* IOSTANDARD = "LVDS_25" *) (* SLEW = "SLOW" *) wire enc_clk;
  (* IOSTANDARD = "LVDS_25" *) (* SLEW = "SLOW" *) wire enc_n;
  (* IOSTANDARD = "LVDS_25" *) (* SLEW = "SLOW" *) wire enc_p;
  (* DIFF_TERM *) (* IBUF_LOW_PWR *) (* IOSTANDARD = "LVDS_25" *) wire m_axis_aclk;
  wire [15:0]m_axis_tdata;
  wire m_axis_tlast;
  wire m_axis_tready;
  wire m_axis_tuser;
  wire m_axis_tvalid;
  (* DIFF_TERM *) (* IBUF_LOW_PWR *) (* IOSTANDARD = "LVDS_25" *) wire of_n;
  (* DIFF_TERM *) (* IBUF_LOW_PWR *) (* IOSTANDARD = "LVDS_25" *) wire of_p;
  wire rst_n;

  assign adc_clk = m_axis_aclk;
  decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix_LTC2208 inst
       (.adc_data(adc_data),
        .adc_of(adc_of),
        .clkout_n(clkout_n),
        .clkout_p(clkout_p),
        .data_n(data_n),
        .data_p(data_p),
        .enc_clk(enc_clk),
        .enc_n(enc_n),
        .enc_p(enc_p),
        .m_axis_aclk(m_axis_aclk),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tlast(m_axis_tlast),
        .m_axis_tready(m_axis_tready),
        .m_axis_tuser(m_axis_tuser),
        .m_axis_tvalid(m_axis_tvalid),
        .of_n(of_n),
        .of_p(of_p),
        .rst_n(rst_n));
endmodule
`ifndef GLBL
`define GLBL
`timescale  1 ps / 1 ps

module glbl ();

    parameter ROC_WIDTH = 100000;
    parameter TOC_WIDTH = 0;
    parameter GRES_WIDTH = 10000;
    parameter GRES_START = 10000;

//--------   STARTUP Globals --------------
    wire GSR;
    wire GTS;
    wire GWE;
    wire PRLD;
    wire GRESTORE;
    tri1 p_up_tmp;
    tri (weak1, strong0) PLL_LOCKG = p_up_tmp;

    wire PROGB_GLBL;
    wire CCLKO_GLBL;
    wire FCSBO_GLBL;
    wire [3:0] DO_GLBL;
    wire [3:0] DI_GLBL;
   
    reg GSR_int;
    reg GTS_int;
    reg PRLD_int;
    reg GRESTORE_int;

//--------   JTAG Globals --------------
    wire JTAG_TDO_GLBL;
    wire JTAG_TCK_GLBL;
    wire JTAG_TDI_GLBL;
    wire JTAG_TMS_GLBL;
    wire JTAG_TRST_GLBL;

    reg JTAG_CAPTURE_GLBL;
    reg JTAG_RESET_GLBL;
    reg JTAG_SHIFT_GLBL;
    reg JTAG_UPDATE_GLBL;
    reg JTAG_RUNTEST_GLBL;

    reg JTAG_SEL1_GLBL = 0;
    reg JTAG_SEL2_GLBL = 0 ;
    reg JTAG_SEL3_GLBL = 0;
    reg JTAG_SEL4_GLBL = 0;

    reg JTAG_USER_TDO1_GLBL = 1'bz;
    reg JTAG_USER_TDO2_GLBL = 1'bz;
    reg JTAG_USER_TDO3_GLBL = 1'bz;
    reg JTAG_USER_TDO4_GLBL = 1'bz;

    assign (strong1, weak0) GSR = GSR_int;
    assign (strong1, weak0) GTS = GTS_int;
    assign (weak1, weak0) PRLD = PRLD_int;
    assign (strong1, weak0) GRESTORE = GRESTORE_int;

    initial begin
	GSR_int = 1'b1;
	PRLD_int = 1'b1;
	#(ROC_WIDTH)
	GSR_int = 1'b0;
	PRLD_int = 1'b0;
    end

    initial begin
	GTS_int = 1'b1;
	#(TOC_WIDTH)
	GTS_int = 1'b0;
    end

    initial begin 
	GRESTORE_int = 1'b0;
	#(GRES_START);
	GRESTORE_int = 1'b1;
	#(GRES_WIDTH);
	GRESTORE_int = 1'b0;
    end

endmodule
`endif
