-- Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
-- --------------------------------------------------------------------------------
-- Tool Version: Vivado v.2021.1 (win64) Build 3247384 Thu Jun 10 19:36:33 MDT 2021
-- Date        : Sun Mar 15 20:32:56 2026
-- Host        : MarkeuPro running 64-bit major release  (build 9200)
-- Command     : write_vhdl -force -mode funcsim -rename_top decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix -prefix
--               decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix_ system_LTC2208_0_0_sim_netlist.vhdl
-- Design      : system_LTC2208_0_0
-- Purpose     : This VHDL netlist is a functional simulation representation of the design and should not be modified or
--               synthesized. This netlist cannot be used for SDF annotated simulation.
-- Device      : xc7z010clg400-1
-- --------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library UNISIM;
use UNISIM.VCOMPONENTS.ALL;
entity decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix_LTC2208 is
  port (
    enc_p : out STD_LOGIC;
    enc_n : out STD_LOGIC;
    m_axis_aclk : out STD_LOGIC;
    adc_data : out STD_LOGIC_VECTOR ( 15 downto 0 );
    adc_of : out STD_LOGIC;
    m_axis_tvalid : out STD_LOGIC;
    m_axis_tdata : out STD_LOGIC_VECTOR ( 15 downto 0 );
    m_axis_tuser : out STD_LOGIC;
    m_axis_tlast : out STD_LOGIC;
    data_p : in STD_LOGIC_VECTOR ( 15 downto 0 );
    data_n : in STD_LOGIC_VECTOR ( 15 downto 0 );
    enc_clk : in STD_LOGIC;
    clkout_p : in STD_LOGIC;
    clkout_n : in STD_LOGIC;
    of_p : in STD_LOGIC;
    of_n : in STD_LOGIC;
    rst_n : in STD_LOGIC;
    m_axis_tready : in STD_LOGIC
  );
end decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix_LTC2208;

architecture STRUCTURE of decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix_LTC2208 is
  signal \adc_data[15]_i_1_n_0\ : STD_LOGIC;
  signal data0 : STD_LOGIC_VECTOR ( 31 downto 1 );
  signal data_s : STD_LOGIC_VECTOR ( 15 downto 0 );
  signal \^m_axis_aclk\ : STD_LOGIC;
  signal m_axis_tdata0 : STD_LOGIC;
  signal m_axis_tlast_0 : STD_LOGIC;
  signal m_axis_tlast_i_10_n_0 : STD_LOGIC;
  signal m_axis_tlast_i_1_n_0 : STD_LOGIC;
  signal m_axis_tlast_i_3_n_0 : STD_LOGIC;
  signal m_axis_tlast_i_4_n_0 : STD_LOGIC;
  signal m_axis_tlast_i_5_n_0 : STD_LOGIC;
  signal m_axis_tlast_i_6_n_0 : STD_LOGIC;
  signal m_axis_tlast_i_7_n_0 : STD_LOGIC;
  signal m_axis_tlast_i_8_n_0 : STD_LOGIC;
  signal m_axis_tlast_i_9_n_0 : STD_LOGIC;
  signal \^m_axis_tvalid\ : STD_LOGIC;
  signal of_s : STD_LOGIC;
  signal transfer_cnt : STD_LOGIC_VECTOR ( 31 downto 0 );
  signal transfer_cnt_1 : STD_LOGIC_VECTOR ( 31 downto 0 );
  signal \transfer_cnt_reg[12]_i_2_n_0\ : STD_LOGIC;
  signal \transfer_cnt_reg[12]_i_2_n_1\ : STD_LOGIC;
  signal \transfer_cnt_reg[12]_i_2_n_2\ : STD_LOGIC;
  signal \transfer_cnt_reg[12]_i_2_n_3\ : STD_LOGIC;
  signal \transfer_cnt_reg[16]_i_2_n_0\ : STD_LOGIC;
  signal \transfer_cnt_reg[16]_i_2_n_1\ : STD_LOGIC;
  signal \transfer_cnt_reg[16]_i_2_n_2\ : STD_LOGIC;
  signal \transfer_cnt_reg[16]_i_2_n_3\ : STD_LOGIC;
  signal \transfer_cnt_reg[20]_i_2_n_0\ : STD_LOGIC;
  signal \transfer_cnt_reg[20]_i_2_n_1\ : STD_LOGIC;
  signal \transfer_cnt_reg[20]_i_2_n_2\ : STD_LOGIC;
  signal \transfer_cnt_reg[20]_i_2_n_3\ : STD_LOGIC;
  signal \transfer_cnt_reg[24]_i_2_n_0\ : STD_LOGIC;
  signal \transfer_cnt_reg[24]_i_2_n_1\ : STD_LOGIC;
  signal \transfer_cnt_reg[24]_i_2_n_2\ : STD_LOGIC;
  signal \transfer_cnt_reg[24]_i_2_n_3\ : STD_LOGIC;
  signal \transfer_cnt_reg[28]_i_2_n_0\ : STD_LOGIC;
  signal \transfer_cnt_reg[28]_i_2_n_1\ : STD_LOGIC;
  signal \transfer_cnt_reg[28]_i_2_n_2\ : STD_LOGIC;
  signal \transfer_cnt_reg[28]_i_2_n_3\ : STD_LOGIC;
  signal \transfer_cnt_reg[31]_i_2_n_2\ : STD_LOGIC;
  signal \transfer_cnt_reg[31]_i_2_n_3\ : STD_LOGIC;
  signal \transfer_cnt_reg[4]_i_2_n_0\ : STD_LOGIC;
  signal \transfer_cnt_reg[4]_i_2_n_1\ : STD_LOGIC;
  signal \transfer_cnt_reg[4]_i_2_n_2\ : STD_LOGIC;
  signal \transfer_cnt_reg[4]_i_2_n_3\ : STD_LOGIC;
  signal \transfer_cnt_reg[8]_i_2_n_0\ : STD_LOGIC;
  signal \transfer_cnt_reg[8]_i_2_n_1\ : STD_LOGIC;
  signal \transfer_cnt_reg[8]_i_2_n_2\ : STD_LOGIC;
  signal \transfer_cnt_reg[8]_i_2_n_3\ : STD_LOGIC;
  signal \NLW_transfer_cnt_reg[31]_i_2_CO_UNCONNECTED\ : STD_LOGIC_VECTOR ( 3 downto 2 );
  signal \NLW_transfer_cnt_reg[31]_i_2_O_UNCONNECTED\ : STD_LOGIC_VECTOR ( 3 to 3 );
  attribute BOX_TYPE : string;
  attribute BOX_TYPE of \gen_data_ibuf[0].u_ibufds_data\ : label is "PRIMITIVE";
  attribute CAPACITANCE : string;
  attribute CAPACITANCE of \gen_data_ibuf[0].u_ibufds_data\ : label is "DONT_CARE";
  attribute IBUF_DELAY_VALUE : string;
  attribute IBUF_DELAY_VALUE of \gen_data_ibuf[0].u_ibufds_data\ : label is "0";
  attribute IFD_DELAY_VALUE : string;
  attribute IFD_DELAY_VALUE of \gen_data_ibuf[0].u_ibufds_data\ : label is "AUTO";
  attribute BOX_TYPE of \gen_data_ibuf[10].u_ibufds_data\ : label is "PRIMITIVE";
  attribute CAPACITANCE of \gen_data_ibuf[10].u_ibufds_data\ : label is "DONT_CARE";
  attribute IBUF_DELAY_VALUE of \gen_data_ibuf[10].u_ibufds_data\ : label is "0";
  attribute IFD_DELAY_VALUE of \gen_data_ibuf[10].u_ibufds_data\ : label is "AUTO";
  attribute BOX_TYPE of \gen_data_ibuf[11].u_ibufds_data\ : label is "PRIMITIVE";
  attribute CAPACITANCE of \gen_data_ibuf[11].u_ibufds_data\ : label is "DONT_CARE";
  attribute IBUF_DELAY_VALUE of \gen_data_ibuf[11].u_ibufds_data\ : label is "0";
  attribute IFD_DELAY_VALUE of \gen_data_ibuf[11].u_ibufds_data\ : label is "AUTO";
  attribute BOX_TYPE of \gen_data_ibuf[12].u_ibufds_data\ : label is "PRIMITIVE";
  attribute CAPACITANCE of \gen_data_ibuf[12].u_ibufds_data\ : label is "DONT_CARE";
  attribute IBUF_DELAY_VALUE of \gen_data_ibuf[12].u_ibufds_data\ : label is "0";
  attribute IFD_DELAY_VALUE of \gen_data_ibuf[12].u_ibufds_data\ : label is "AUTO";
  attribute BOX_TYPE of \gen_data_ibuf[13].u_ibufds_data\ : label is "PRIMITIVE";
  attribute CAPACITANCE of \gen_data_ibuf[13].u_ibufds_data\ : label is "DONT_CARE";
  attribute IBUF_DELAY_VALUE of \gen_data_ibuf[13].u_ibufds_data\ : label is "0";
  attribute IFD_DELAY_VALUE of \gen_data_ibuf[13].u_ibufds_data\ : label is "AUTO";
  attribute BOX_TYPE of \gen_data_ibuf[14].u_ibufds_data\ : label is "PRIMITIVE";
  attribute CAPACITANCE of \gen_data_ibuf[14].u_ibufds_data\ : label is "DONT_CARE";
  attribute IBUF_DELAY_VALUE of \gen_data_ibuf[14].u_ibufds_data\ : label is "0";
  attribute IFD_DELAY_VALUE of \gen_data_ibuf[14].u_ibufds_data\ : label is "AUTO";
  attribute BOX_TYPE of \gen_data_ibuf[15].u_ibufds_data\ : label is "PRIMITIVE";
  attribute CAPACITANCE of \gen_data_ibuf[15].u_ibufds_data\ : label is "DONT_CARE";
  attribute IBUF_DELAY_VALUE of \gen_data_ibuf[15].u_ibufds_data\ : label is "0";
  attribute IFD_DELAY_VALUE of \gen_data_ibuf[15].u_ibufds_data\ : label is "AUTO";
  attribute BOX_TYPE of \gen_data_ibuf[1].u_ibufds_data\ : label is "PRIMITIVE";
  attribute CAPACITANCE of \gen_data_ibuf[1].u_ibufds_data\ : label is "DONT_CARE";
  attribute IBUF_DELAY_VALUE of \gen_data_ibuf[1].u_ibufds_data\ : label is "0";
  attribute IFD_DELAY_VALUE of \gen_data_ibuf[1].u_ibufds_data\ : label is "AUTO";
  attribute BOX_TYPE of \gen_data_ibuf[2].u_ibufds_data\ : label is "PRIMITIVE";
  attribute CAPACITANCE of \gen_data_ibuf[2].u_ibufds_data\ : label is "DONT_CARE";
  attribute IBUF_DELAY_VALUE of \gen_data_ibuf[2].u_ibufds_data\ : label is "0";
  attribute IFD_DELAY_VALUE of \gen_data_ibuf[2].u_ibufds_data\ : label is "AUTO";
  attribute BOX_TYPE of \gen_data_ibuf[3].u_ibufds_data\ : label is "PRIMITIVE";
  attribute CAPACITANCE of \gen_data_ibuf[3].u_ibufds_data\ : label is "DONT_CARE";
  attribute IBUF_DELAY_VALUE of \gen_data_ibuf[3].u_ibufds_data\ : label is "0";
  attribute IFD_DELAY_VALUE of \gen_data_ibuf[3].u_ibufds_data\ : label is "AUTO";
  attribute BOX_TYPE of \gen_data_ibuf[4].u_ibufds_data\ : label is "PRIMITIVE";
  attribute CAPACITANCE of \gen_data_ibuf[4].u_ibufds_data\ : label is "DONT_CARE";
  attribute IBUF_DELAY_VALUE of \gen_data_ibuf[4].u_ibufds_data\ : label is "0";
  attribute IFD_DELAY_VALUE of \gen_data_ibuf[4].u_ibufds_data\ : label is "AUTO";
  attribute BOX_TYPE of \gen_data_ibuf[5].u_ibufds_data\ : label is "PRIMITIVE";
  attribute CAPACITANCE of \gen_data_ibuf[5].u_ibufds_data\ : label is "DONT_CARE";
  attribute IBUF_DELAY_VALUE of \gen_data_ibuf[5].u_ibufds_data\ : label is "0";
  attribute IFD_DELAY_VALUE of \gen_data_ibuf[5].u_ibufds_data\ : label is "AUTO";
  attribute BOX_TYPE of \gen_data_ibuf[6].u_ibufds_data\ : label is "PRIMITIVE";
  attribute CAPACITANCE of \gen_data_ibuf[6].u_ibufds_data\ : label is "DONT_CARE";
  attribute IBUF_DELAY_VALUE of \gen_data_ibuf[6].u_ibufds_data\ : label is "0";
  attribute IFD_DELAY_VALUE of \gen_data_ibuf[6].u_ibufds_data\ : label is "AUTO";
  attribute BOX_TYPE of \gen_data_ibuf[7].u_ibufds_data\ : label is "PRIMITIVE";
  attribute CAPACITANCE of \gen_data_ibuf[7].u_ibufds_data\ : label is "DONT_CARE";
  attribute IBUF_DELAY_VALUE of \gen_data_ibuf[7].u_ibufds_data\ : label is "0";
  attribute IFD_DELAY_VALUE of \gen_data_ibuf[7].u_ibufds_data\ : label is "AUTO";
  attribute BOX_TYPE of \gen_data_ibuf[8].u_ibufds_data\ : label is "PRIMITIVE";
  attribute CAPACITANCE of \gen_data_ibuf[8].u_ibufds_data\ : label is "DONT_CARE";
  attribute IBUF_DELAY_VALUE of \gen_data_ibuf[8].u_ibufds_data\ : label is "0";
  attribute IFD_DELAY_VALUE of \gen_data_ibuf[8].u_ibufds_data\ : label is "AUTO";
  attribute BOX_TYPE of \gen_data_ibuf[9].u_ibufds_data\ : label is "PRIMITIVE";
  attribute CAPACITANCE of \gen_data_ibuf[9].u_ibufds_data\ : label is "DONT_CARE";
  attribute IBUF_DELAY_VALUE of \gen_data_ibuf[9].u_ibufds_data\ : label is "0";
  attribute IFD_DELAY_VALUE of \gen_data_ibuf[9].u_ibufds_data\ : label is "AUTO";
  attribute SOFT_HLUTNM : string;
  attribute SOFT_HLUTNM of m_axis_tlast_i_2 : label is "soft_lutpair0";
  attribute SOFT_HLUTNM of \transfer_cnt[1]_i_1\ : label is "soft_lutpair0";
  attribute ADDER_THRESHOLD : integer;
  attribute ADDER_THRESHOLD of \transfer_cnt_reg[12]_i_2\ : label is 35;
  attribute ADDER_THRESHOLD of \transfer_cnt_reg[16]_i_2\ : label is 35;
  attribute ADDER_THRESHOLD of \transfer_cnt_reg[20]_i_2\ : label is 35;
  attribute ADDER_THRESHOLD of \transfer_cnt_reg[24]_i_2\ : label is 35;
  attribute ADDER_THRESHOLD of \transfer_cnt_reg[28]_i_2\ : label is 35;
  attribute ADDER_THRESHOLD of \transfer_cnt_reg[31]_i_2\ : label is 35;
  attribute ADDER_THRESHOLD of \transfer_cnt_reg[4]_i_2\ : label is 35;
  attribute ADDER_THRESHOLD of \transfer_cnt_reg[8]_i_2\ : label is 35;
  attribute BOX_TYPE of u_ibufds_clkout : label is "PRIMITIVE";
  attribute CAPACITANCE of u_ibufds_clkout : label is "DONT_CARE";
  attribute IBUF_DELAY_VALUE of u_ibufds_clkout : label is "0";
  attribute IFD_DELAY_VALUE of u_ibufds_clkout : label is "AUTO";
  attribute BOX_TYPE of u_ibufds_of : label is "PRIMITIVE";
  attribute CAPACITANCE of u_ibufds_of : label is "DONT_CARE";
  attribute IBUF_DELAY_VALUE of u_ibufds_of : label is "0";
  attribute IFD_DELAY_VALUE of u_ibufds_of : label is "AUTO";
  attribute BOX_TYPE of u_obufds_enc : label is "PRIMITIVE";
  attribute CAPACITANCE of u_obufds_enc : label is "DONT_CARE";
begin
  m_axis_aclk <= \^m_axis_aclk\;
  m_axis_tvalid <= \^m_axis_tvalid\;
\adc_data[15]_i_1\: unisim.vcomponents.LUT1
    generic map(
      INIT => X"1"
    )
        port map (
      I0 => rst_n,
      O => \adc_data[15]_i_1_n_0\
    );
\adc_data_reg[0]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => '1',
      CLR => \adc_data[15]_i_1_n_0\,
      D => data_s(0),
      Q => adc_data(0)
    );
\adc_data_reg[10]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => '1',
      CLR => \adc_data[15]_i_1_n_0\,
      D => data_s(10),
      Q => adc_data(10)
    );
\adc_data_reg[11]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => '1',
      CLR => \adc_data[15]_i_1_n_0\,
      D => data_s(11),
      Q => adc_data(11)
    );
\adc_data_reg[12]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => '1',
      CLR => \adc_data[15]_i_1_n_0\,
      D => data_s(12),
      Q => adc_data(12)
    );
\adc_data_reg[13]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => '1',
      CLR => \adc_data[15]_i_1_n_0\,
      D => data_s(13),
      Q => adc_data(13)
    );
\adc_data_reg[14]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => '1',
      CLR => \adc_data[15]_i_1_n_0\,
      D => data_s(14),
      Q => adc_data(14)
    );
\adc_data_reg[15]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => '1',
      CLR => \adc_data[15]_i_1_n_0\,
      D => data_s(15),
      Q => adc_data(15)
    );
\adc_data_reg[1]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => '1',
      CLR => \adc_data[15]_i_1_n_0\,
      D => data_s(1),
      Q => adc_data(1)
    );
\adc_data_reg[2]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => '1',
      CLR => \adc_data[15]_i_1_n_0\,
      D => data_s(2),
      Q => adc_data(2)
    );
\adc_data_reg[3]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => '1',
      CLR => \adc_data[15]_i_1_n_0\,
      D => data_s(3),
      Q => adc_data(3)
    );
\adc_data_reg[4]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => '1',
      CLR => \adc_data[15]_i_1_n_0\,
      D => data_s(4),
      Q => adc_data(4)
    );
\adc_data_reg[5]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => '1',
      CLR => \adc_data[15]_i_1_n_0\,
      D => data_s(5),
      Q => adc_data(5)
    );
\adc_data_reg[6]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => '1',
      CLR => \adc_data[15]_i_1_n_0\,
      D => data_s(6),
      Q => adc_data(6)
    );
\adc_data_reg[7]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => '1',
      CLR => \adc_data[15]_i_1_n_0\,
      D => data_s(7),
      Q => adc_data(7)
    );
\adc_data_reg[8]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => '1',
      CLR => \adc_data[15]_i_1_n_0\,
      D => data_s(8),
      Q => adc_data(8)
    );
\adc_data_reg[9]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => '1',
      CLR => \adc_data[15]_i_1_n_0\,
      D => data_s(9),
      Q => adc_data(9)
    );
adc_of_reg: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => '1',
      CLR => \adc_data[15]_i_1_n_0\,
      D => of_s,
      Q => adc_of
    );
\gen_data_ibuf[0].u_ibufds_data\: unisim.vcomponents.IBUFDS
     port map (
      I => data_p(0),
      IB => data_n(0),
      O => data_s(0)
    );
\gen_data_ibuf[10].u_ibufds_data\: unisim.vcomponents.IBUFDS
     port map (
      I => data_p(10),
      IB => data_n(10),
      O => data_s(10)
    );
\gen_data_ibuf[11].u_ibufds_data\: unisim.vcomponents.IBUFDS
     port map (
      I => data_p(11),
      IB => data_n(11),
      O => data_s(11)
    );
\gen_data_ibuf[12].u_ibufds_data\: unisim.vcomponents.IBUFDS
     port map (
      I => data_p(12),
      IB => data_n(12),
      O => data_s(12)
    );
\gen_data_ibuf[13].u_ibufds_data\: unisim.vcomponents.IBUFDS
     port map (
      I => data_p(13),
      IB => data_n(13),
      O => data_s(13)
    );
\gen_data_ibuf[14].u_ibufds_data\: unisim.vcomponents.IBUFDS
     port map (
      I => data_p(14),
      IB => data_n(14),
      O => data_s(14)
    );
\gen_data_ibuf[15].u_ibufds_data\: unisim.vcomponents.IBUFDS
     port map (
      I => data_p(15),
      IB => data_n(15),
      O => data_s(15)
    );
\gen_data_ibuf[1].u_ibufds_data\: unisim.vcomponents.IBUFDS
     port map (
      I => data_p(1),
      IB => data_n(1),
      O => data_s(1)
    );
\gen_data_ibuf[2].u_ibufds_data\: unisim.vcomponents.IBUFDS
     port map (
      I => data_p(2),
      IB => data_n(2),
      O => data_s(2)
    );
\gen_data_ibuf[3].u_ibufds_data\: unisim.vcomponents.IBUFDS
     port map (
      I => data_p(3),
      IB => data_n(3),
      O => data_s(3)
    );
\gen_data_ibuf[4].u_ibufds_data\: unisim.vcomponents.IBUFDS
     port map (
      I => data_p(4),
      IB => data_n(4),
      O => data_s(4)
    );
\gen_data_ibuf[5].u_ibufds_data\: unisim.vcomponents.IBUFDS
     port map (
      I => data_p(5),
      IB => data_n(5),
      O => data_s(5)
    );
\gen_data_ibuf[6].u_ibufds_data\: unisim.vcomponents.IBUFDS
     port map (
      I => data_p(6),
      IB => data_n(6),
      O => data_s(6)
    );
\gen_data_ibuf[7].u_ibufds_data\: unisim.vcomponents.IBUFDS
     port map (
      I => data_p(7),
      IB => data_n(7),
      O => data_s(7)
    );
\gen_data_ibuf[8].u_ibufds_data\: unisim.vcomponents.IBUFDS
     port map (
      I => data_p(8),
      IB => data_n(8),
      O => data_s(8)
    );
\gen_data_ibuf[9].u_ibufds_data\: unisim.vcomponents.IBUFDS
     port map (
      I => data_p(9),
      IB => data_n(9),
      O => data_s(9)
    );
\m_axis_tdata[15]_i_1\: unisim.vcomponents.LUT2
    generic map(
      INIT => X"B"
    )
        port map (
      I0 => m_axis_tready,
      I1 => \^m_axis_tvalid\,
      O => m_axis_tdata0
    );
\m_axis_tdata_reg[0]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tdata0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => data_s(0),
      Q => m_axis_tdata(0)
    );
\m_axis_tdata_reg[10]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tdata0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => data_s(10),
      Q => m_axis_tdata(10)
    );
\m_axis_tdata_reg[11]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tdata0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => data_s(11),
      Q => m_axis_tdata(11)
    );
\m_axis_tdata_reg[12]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tdata0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => data_s(12),
      Q => m_axis_tdata(12)
    );
\m_axis_tdata_reg[13]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tdata0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => data_s(13),
      Q => m_axis_tdata(13)
    );
\m_axis_tdata_reg[14]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tdata0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => data_s(14),
      Q => m_axis_tdata(14)
    );
\m_axis_tdata_reg[15]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tdata0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => data_s(15),
      Q => m_axis_tdata(15)
    );
\m_axis_tdata_reg[1]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tdata0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => data_s(1),
      Q => m_axis_tdata(1)
    );
\m_axis_tdata_reg[2]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tdata0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => data_s(2),
      Q => m_axis_tdata(2)
    );
\m_axis_tdata_reg[3]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tdata0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => data_s(3),
      Q => m_axis_tdata(3)
    );
\m_axis_tdata_reg[4]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tdata0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => data_s(4),
      Q => m_axis_tdata(4)
    );
\m_axis_tdata_reg[5]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tdata0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => data_s(5),
      Q => m_axis_tdata(5)
    );
\m_axis_tdata_reg[6]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tdata0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => data_s(6),
      Q => m_axis_tdata(6)
    );
\m_axis_tdata_reg[7]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tdata0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => data_s(7),
      Q => m_axis_tdata(7)
    );
\m_axis_tdata_reg[8]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tdata0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => data_s(8),
      Q => m_axis_tdata(8)
    );
\m_axis_tdata_reg[9]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tdata0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => data_s(9),
      Q => m_axis_tdata(9)
    );
m_axis_tlast_i_1: unisim.vcomponents.LUT2
    generic map(
      INIT => X"8"
    )
        port map (
      I0 => m_axis_tready,
      I1 => \^m_axis_tvalid\,
      O => m_axis_tlast_i_1_n_0
    );
m_axis_tlast_i_10: unisim.vcomponents.LUT4
    generic map(
      INIT => X"FFFE"
    )
        port map (
      I0 => transfer_cnt(13),
      I1 => transfer_cnt(12),
      I2 => transfer_cnt(15),
      I3 => transfer_cnt(14),
      O => m_axis_tlast_i_10_n_0
    );
m_axis_tlast_i_2: unisim.vcomponents.LUT4
    generic map(
      INIT => X"0001"
    )
        port map (
      I0 => m_axis_tlast_i_3_n_0,
      I1 => m_axis_tlast_i_4_n_0,
      I2 => m_axis_tlast_i_5_n_0,
      I3 => m_axis_tlast_i_6_n_0,
      O => m_axis_tlast_0
    );
m_axis_tlast_i_3: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFFFFFE"
    )
        port map (
      I0 => transfer_cnt(18),
      I1 => transfer_cnt(19),
      I2 => transfer_cnt(16),
      I3 => transfer_cnt(17),
      I4 => m_axis_tlast_i_7_n_0,
      O => m_axis_tlast_i_3_n_0
    );
m_axis_tlast_i_4: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFFFFFE"
    )
        port map (
      I0 => transfer_cnt(26),
      I1 => transfer_cnt(27),
      I2 => transfer_cnt(24),
      I3 => transfer_cnt(25),
      I4 => m_axis_tlast_i_8_n_0,
      O => m_axis_tlast_i_4_n_0
    );
m_axis_tlast_i_5: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFF7FFF"
    )
        port map (
      I0 => transfer_cnt(2),
      I1 => transfer_cnt(3),
      I2 => transfer_cnt(0),
      I3 => transfer_cnt(1),
      I4 => m_axis_tlast_i_9_n_0,
      O => m_axis_tlast_i_5_n_0
    );
m_axis_tlast_i_6: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFF7FFF"
    )
        port map (
      I0 => transfer_cnt(10),
      I1 => transfer_cnt(11),
      I2 => transfer_cnt(8),
      I3 => transfer_cnt(9),
      I4 => m_axis_tlast_i_10_n_0,
      O => m_axis_tlast_i_6_n_0
    );
m_axis_tlast_i_7: unisim.vcomponents.LUT4
    generic map(
      INIT => X"FFFE"
    )
        port map (
      I0 => transfer_cnt(21),
      I1 => transfer_cnt(20),
      I2 => transfer_cnt(23),
      I3 => transfer_cnt(22),
      O => m_axis_tlast_i_7_n_0
    );
m_axis_tlast_i_8: unisim.vcomponents.LUT4
    generic map(
      INIT => X"FFFE"
    )
        port map (
      I0 => transfer_cnt(29),
      I1 => transfer_cnt(28),
      I2 => transfer_cnt(31),
      I3 => transfer_cnt(30),
      O => m_axis_tlast_i_8_n_0
    );
m_axis_tlast_i_9: unisim.vcomponents.LUT4
    generic map(
      INIT => X"7FFF"
    )
        port map (
      I0 => transfer_cnt(5),
      I1 => transfer_cnt(4),
      I2 => transfer_cnt(7),
      I3 => transfer_cnt(6),
      O => m_axis_tlast_i_9_n_0
    );
m_axis_tlast_reg: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tlast_i_1_n_0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => m_axis_tlast_0,
      Q => m_axis_tlast
    );
m_axis_tuser_reg: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tdata0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => of_s,
      Q => m_axis_tuser
    );
m_axis_tvalid_reg: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tdata0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => m_axis_tdata0,
      Q => \^m_axis_tvalid\
    );
\transfer_cnt[0]_i_1\: unisim.vcomponents.LUT1
    generic map(
      INIT => X"1"
    )
        port map (
      I0 => transfer_cnt(0),
      O => transfer_cnt_1(0)
    );
\transfer_cnt[10]_i_1\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFE0000"
    )
        port map (
      I0 => m_axis_tlast_i_3_n_0,
      I1 => m_axis_tlast_i_4_n_0,
      I2 => m_axis_tlast_i_5_n_0,
      I3 => m_axis_tlast_i_6_n_0,
      I4 => data0(10),
      O => transfer_cnt_1(10)
    );
\transfer_cnt[11]_i_1\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFE0000"
    )
        port map (
      I0 => m_axis_tlast_i_3_n_0,
      I1 => m_axis_tlast_i_4_n_0,
      I2 => m_axis_tlast_i_5_n_0,
      I3 => m_axis_tlast_i_6_n_0,
      I4 => data0(11),
      O => transfer_cnt_1(11)
    );
\transfer_cnt[12]_i_1\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFE0000"
    )
        port map (
      I0 => m_axis_tlast_i_3_n_0,
      I1 => m_axis_tlast_i_4_n_0,
      I2 => m_axis_tlast_i_5_n_0,
      I3 => m_axis_tlast_i_6_n_0,
      I4 => data0(12),
      O => transfer_cnt_1(12)
    );
\transfer_cnt[13]_i_1\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFE0000"
    )
        port map (
      I0 => m_axis_tlast_i_3_n_0,
      I1 => m_axis_tlast_i_4_n_0,
      I2 => m_axis_tlast_i_5_n_0,
      I3 => m_axis_tlast_i_6_n_0,
      I4 => data0(13),
      O => transfer_cnt_1(13)
    );
\transfer_cnt[14]_i_1\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFE0000"
    )
        port map (
      I0 => m_axis_tlast_i_3_n_0,
      I1 => m_axis_tlast_i_4_n_0,
      I2 => m_axis_tlast_i_5_n_0,
      I3 => m_axis_tlast_i_6_n_0,
      I4 => data0(14),
      O => transfer_cnt_1(14)
    );
\transfer_cnt[15]_i_1\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFE0000"
    )
        port map (
      I0 => m_axis_tlast_i_3_n_0,
      I1 => m_axis_tlast_i_4_n_0,
      I2 => m_axis_tlast_i_5_n_0,
      I3 => m_axis_tlast_i_6_n_0,
      I4 => data0(15),
      O => transfer_cnt_1(15)
    );
\transfer_cnt[16]_i_1\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFE0000"
    )
        port map (
      I0 => m_axis_tlast_i_3_n_0,
      I1 => m_axis_tlast_i_4_n_0,
      I2 => m_axis_tlast_i_5_n_0,
      I3 => m_axis_tlast_i_6_n_0,
      I4 => data0(16),
      O => transfer_cnt_1(16)
    );
\transfer_cnt[17]_i_1\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFE0000"
    )
        port map (
      I0 => m_axis_tlast_i_3_n_0,
      I1 => m_axis_tlast_i_4_n_0,
      I2 => m_axis_tlast_i_5_n_0,
      I3 => m_axis_tlast_i_6_n_0,
      I4 => data0(17),
      O => transfer_cnt_1(17)
    );
\transfer_cnt[18]_i_1\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFE0000"
    )
        port map (
      I0 => m_axis_tlast_i_3_n_0,
      I1 => m_axis_tlast_i_4_n_0,
      I2 => m_axis_tlast_i_5_n_0,
      I3 => m_axis_tlast_i_6_n_0,
      I4 => data0(18),
      O => transfer_cnt_1(18)
    );
\transfer_cnt[19]_i_1\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFE0000"
    )
        port map (
      I0 => m_axis_tlast_i_3_n_0,
      I1 => m_axis_tlast_i_4_n_0,
      I2 => m_axis_tlast_i_5_n_0,
      I3 => m_axis_tlast_i_6_n_0,
      I4 => data0(19),
      O => transfer_cnt_1(19)
    );
\transfer_cnt[1]_i_1\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFE0000"
    )
        port map (
      I0 => m_axis_tlast_i_3_n_0,
      I1 => m_axis_tlast_i_4_n_0,
      I2 => m_axis_tlast_i_5_n_0,
      I3 => m_axis_tlast_i_6_n_0,
      I4 => data0(1),
      O => transfer_cnt_1(1)
    );
\transfer_cnt[20]_i_1\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFE0000"
    )
        port map (
      I0 => m_axis_tlast_i_3_n_0,
      I1 => m_axis_tlast_i_4_n_0,
      I2 => m_axis_tlast_i_5_n_0,
      I3 => m_axis_tlast_i_6_n_0,
      I4 => data0(20),
      O => transfer_cnt_1(20)
    );
\transfer_cnt[21]_i_1\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFE0000"
    )
        port map (
      I0 => m_axis_tlast_i_3_n_0,
      I1 => m_axis_tlast_i_4_n_0,
      I2 => m_axis_tlast_i_5_n_0,
      I3 => m_axis_tlast_i_6_n_0,
      I4 => data0(21),
      O => transfer_cnt_1(21)
    );
\transfer_cnt[22]_i_1\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFE0000"
    )
        port map (
      I0 => m_axis_tlast_i_3_n_0,
      I1 => m_axis_tlast_i_4_n_0,
      I2 => m_axis_tlast_i_5_n_0,
      I3 => m_axis_tlast_i_6_n_0,
      I4 => data0(22),
      O => transfer_cnt_1(22)
    );
\transfer_cnt[23]_i_1\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFE0000"
    )
        port map (
      I0 => m_axis_tlast_i_3_n_0,
      I1 => m_axis_tlast_i_4_n_0,
      I2 => m_axis_tlast_i_5_n_0,
      I3 => m_axis_tlast_i_6_n_0,
      I4 => data0(23),
      O => transfer_cnt_1(23)
    );
\transfer_cnt[24]_i_1\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFE0000"
    )
        port map (
      I0 => m_axis_tlast_i_3_n_0,
      I1 => m_axis_tlast_i_4_n_0,
      I2 => m_axis_tlast_i_5_n_0,
      I3 => m_axis_tlast_i_6_n_0,
      I4 => data0(24),
      O => transfer_cnt_1(24)
    );
\transfer_cnt[25]_i_1\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFE0000"
    )
        port map (
      I0 => m_axis_tlast_i_3_n_0,
      I1 => m_axis_tlast_i_4_n_0,
      I2 => m_axis_tlast_i_5_n_0,
      I3 => m_axis_tlast_i_6_n_0,
      I4 => data0(25),
      O => transfer_cnt_1(25)
    );
\transfer_cnt[26]_i_1\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFE0000"
    )
        port map (
      I0 => m_axis_tlast_i_3_n_0,
      I1 => m_axis_tlast_i_4_n_0,
      I2 => m_axis_tlast_i_5_n_0,
      I3 => m_axis_tlast_i_6_n_0,
      I4 => data0(26),
      O => transfer_cnt_1(26)
    );
\transfer_cnt[27]_i_1\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFE0000"
    )
        port map (
      I0 => m_axis_tlast_i_3_n_0,
      I1 => m_axis_tlast_i_4_n_0,
      I2 => m_axis_tlast_i_5_n_0,
      I3 => m_axis_tlast_i_6_n_0,
      I4 => data0(27),
      O => transfer_cnt_1(27)
    );
\transfer_cnt[28]_i_1\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFE0000"
    )
        port map (
      I0 => m_axis_tlast_i_3_n_0,
      I1 => m_axis_tlast_i_4_n_0,
      I2 => m_axis_tlast_i_5_n_0,
      I3 => m_axis_tlast_i_6_n_0,
      I4 => data0(28),
      O => transfer_cnt_1(28)
    );
\transfer_cnt[29]_i_1\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFE0000"
    )
        port map (
      I0 => m_axis_tlast_i_3_n_0,
      I1 => m_axis_tlast_i_4_n_0,
      I2 => m_axis_tlast_i_5_n_0,
      I3 => m_axis_tlast_i_6_n_0,
      I4 => data0(29),
      O => transfer_cnt_1(29)
    );
\transfer_cnt[2]_i_1\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFE0000"
    )
        port map (
      I0 => m_axis_tlast_i_3_n_0,
      I1 => m_axis_tlast_i_4_n_0,
      I2 => m_axis_tlast_i_5_n_0,
      I3 => m_axis_tlast_i_6_n_0,
      I4 => data0(2),
      O => transfer_cnt_1(2)
    );
\transfer_cnt[30]_i_1\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFE0000"
    )
        port map (
      I0 => m_axis_tlast_i_3_n_0,
      I1 => m_axis_tlast_i_4_n_0,
      I2 => m_axis_tlast_i_5_n_0,
      I3 => m_axis_tlast_i_6_n_0,
      I4 => data0(30),
      O => transfer_cnt_1(30)
    );
\transfer_cnt[31]_i_1\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFE0000"
    )
        port map (
      I0 => m_axis_tlast_i_3_n_0,
      I1 => m_axis_tlast_i_4_n_0,
      I2 => m_axis_tlast_i_5_n_0,
      I3 => m_axis_tlast_i_6_n_0,
      I4 => data0(31),
      O => transfer_cnt_1(31)
    );
\transfer_cnt[3]_i_1\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFE0000"
    )
        port map (
      I0 => m_axis_tlast_i_3_n_0,
      I1 => m_axis_tlast_i_4_n_0,
      I2 => m_axis_tlast_i_5_n_0,
      I3 => m_axis_tlast_i_6_n_0,
      I4 => data0(3),
      O => transfer_cnt_1(3)
    );
\transfer_cnt[4]_i_1\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFE0000"
    )
        port map (
      I0 => m_axis_tlast_i_3_n_0,
      I1 => m_axis_tlast_i_4_n_0,
      I2 => m_axis_tlast_i_5_n_0,
      I3 => m_axis_tlast_i_6_n_0,
      I4 => data0(4),
      O => transfer_cnt_1(4)
    );
\transfer_cnt[5]_i_1\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFE0000"
    )
        port map (
      I0 => m_axis_tlast_i_3_n_0,
      I1 => m_axis_tlast_i_4_n_0,
      I2 => m_axis_tlast_i_5_n_0,
      I3 => m_axis_tlast_i_6_n_0,
      I4 => data0(5),
      O => transfer_cnt_1(5)
    );
\transfer_cnt[6]_i_1\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFE0000"
    )
        port map (
      I0 => m_axis_tlast_i_3_n_0,
      I1 => m_axis_tlast_i_4_n_0,
      I2 => m_axis_tlast_i_5_n_0,
      I3 => m_axis_tlast_i_6_n_0,
      I4 => data0(6),
      O => transfer_cnt_1(6)
    );
\transfer_cnt[7]_i_1\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFE0000"
    )
        port map (
      I0 => m_axis_tlast_i_3_n_0,
      I1 => m_axis_tlast_i_4_n_0,
      I2 => m_axis_tlast_i_5_n_0,
      I3 => m_axis_tlast_i_6_n_0,
      I4 => data0(7),
      O => transfer_cnt_1(7)
    );
\transfer_cnt[8]_i_1\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFE0000"
    )
        port map (
      I0 => m_axis_tlast_i_3_n_0,
      I1 => m_axis_tlast_i_4_n_0,
      I2 => m_axis_tlast_i_5_n_0,
      I3 => m_axis_tlast_i_6_n_0,
      I4 => data0(8),
      O => transfer_cnt_1(8)
    );
\transfer_cnt[9]_i_1\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFE0000"
    )
        port map (
      I0 => m_axis_tlast_i_3_n_0,
      I1 => m_axis_tlast_i_4_n_0,
      I2 => m_axis_tlast_i_5_n_0,
      I3 => m_axis_tlast_i_6_n_0,
      I4 => data0(9),
      O => transfer_cnt_1(9)
    );
\transfer_cnt_reg[0]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tlast_i_1_n_0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => transfer_cnt_1(0),
      Q => transfer_cnt(0)
    );
\transfer_cnt_reg[10]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tlast_i_1_n_0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => transfer_cnt_1(10),
      Q => transfer_cnt(10)
    );
\transfer_cnt_reg[11]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tlast_i_1_n_0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => transfer_cnt_1(11),
      Q => transfer_cnt(11)
    );
\transfer_cnt_reg[12]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tlast_i_1_n_0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => transfer_cnt_1(12),
      Q => transfer_cnt(12)
    );
\transfer_cnt_reg[12]_i_2\: unisim.vcomponents.CARRY4
     port map (
      CI => \transfer_cnt_reg[8]_i_2_n_0\,
      CO(3) => \transfer_cnt_reg[12]_i_2_n_0\,
      CO(2) => \transfer_cnt_reg[12]_i_2_n_1\,
      CO(1) => \transfer_cnt_reg[12]_i_2_n_2\,
      CO(0) => \transfer_cnt_reg[12]_i_2_n_3\,
      CYINIT => '0',
      DI(3 downto 0) => B"0000",
      O(3 downto 0) => data0(12 downto 9),
      S(3 downto 0) => transfer_cnt(12 downto 9)
    );
\transfer_cnt_reg[13]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tlast_i_1_n_0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => transfer_cnt_1(13),
      Q => transfer_cnt(13)
    );
\transfer_cnt_reg[14]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tlast_i_1_n_0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => transfer_cnt_1(14),
      Q => transfer_cnt(14)
    );
\transfer_cnt_reg[15]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tlast_i_1_n_0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => transfer_cnt_1(15),
      Q => transfer_cnt(15)
    );
\transfer_cnt_reg[16]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tlast_i_1_n_0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => transfer_cnt_1(16),
      Q => transfer_cnt(16)
    );
\transfer_cnt_reg[16]_i_2\: unisim.vcomponents.CARRY4
     port map (
      CI => \transfer_cnt_reg[12]_i_2_n_0\,
      CO(3) => \transfer_cnt_reg[16]_i_2_n_0\,
      CO(2) => \transfer_cnt_reg[16]_i_2_n_1\,
      CO(1) => \transfer_cnt_reg[16]_i_2_n_2\,
      CO(0) => \transfer_cnt_reg[16]_i_2_n_3\,
      CYINIT => '0',
      DI(3 downto 0) => B"0000",
      O(3 downto 0) => data0(16 downto 13),
      S(3 downto 0) => transfer_cnt(16 downto 13)
    );
\transfer_cnt_reg[17]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tlast_i_1_n_0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => transfer_cnt_1(17),
      Q => transfer_cnt(17)
    );
\transfer_cnt_reg[18]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tlast_i_1_n_0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => transfer_cnt_1(18),
      Q => transfer_cnt(18)
    );
\transfer_cnt_reg[19]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tlast_i_1_n_0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => transfer_cnt_1(19),
      Q => transfer_cnt(19)
    );
\transfer_cnt_reg[1]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tlast_i_1_n_0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => transfer_cnt_1(1),
      Q => transfer_cnt(1)
    );
\transfer_cnt_reg[20]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tlast_i_1_n_0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => transfer_cnt_1(20),
      Q => transfer_cnt(20)
    );
\transfer_cnt_reg[20]_i_2\: unisim.vcomponents.CARRY4
     port map (
      CI => \transfer_cnt_reg[16]_i_2_n_0\,
      CO(3) => \transfer_cnt_reg[20]_i_2_n_0\,
      CO(2) => \transfer_cnt_reg[20]_i_2_n_1\,
      CO(1) => \transfer_cnt_reg[20]_i_2_n_2\,
      CO(0) => \transfer_cnt_reg[20]_i_2_n_3\,
      CYINIT => '0',
      DI(3 downto 0) => B"0000",
      O(3 downto 0) => data0(20 downto 17),
      S(3 downto 0) => transfer_cnt(20 downto 17)
    );
\transfer_cnt_reg[21]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tlast_i_1_n_0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => transfer_cnt_1(21),
      Q => transfer_cnt(21)
    );
\transfer_cnt_reg[22]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tlast_i_1_n_0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => transfer_cnt_1(22),
      Q => transfer_cnt(22)
    );
\transfer_cnt_reg[23]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tlast_i_1_n_0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => transfer_cnt_1(23),
      Q => transfer_cnt(23)
    );
\transfer_cnt_reg[24]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tlast_i_1_n_0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => transfer_cnt_1(24),
      Q => transfer_cnt(24)
    );
\transfer_cnt_reg[24]_i_2\: unisim.vcomponents.CARRY4
     port map (
      CI => \transfer_cnt_reg[20]_i_2_n_0\,
      CO(3) => \transfer_cnt_reg[24]_i_2_n_0\,
      CO(2) => \transfer_cnt_reg[24]_i_2_n_1\,
      CO(1) => \transfer_cnt_reg[24]_i_2_n_2\,
      CO(0) => \transfer_cnt_reg[24]_i_2_n_3\,
      CYINIT => '0',
      DI(3 downto 0) => B"0000",
      O(3 downto 0) => data0(24 downto 21),
      S(3 downto 0) => transfer_cnt(24 downto 21)
    );
\transfer_cnt_reg[25]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tlast_i_1_n_0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => transfer_cnt_1(25),
      Q => transfer_cnt(25)
    );
\transfer_cnt_reg[26]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tlast_i_1_n_0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => transfer_cnt_1(26),
      Q => transfer_cnt(26)
    );
\transfer_cnt_reg[27]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tlast_i_1_n_0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => transfer_cnt_1(27),
      Q => transfer_cnt(27)
    );
\transfer_cnt_reg[28]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tlast_i_1_n_0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => transfer_cnt_1(28),
      Q => transfer_cnt(28)
    );
\transfer_cnt_reg[28]_i_2\: unisim.vcomponents.CARRY4
     port map (
      CI => \transfer_cnt_reg[24]_i_2_n_0\,
      CO(3) => \transfer_cnt_reg[28]_i_2_n_0\,
      CO(2) => \transfer_cnt_reg[28]_i_2_n_1\,
      CO(1) => \transfer_cnt_reg[28]_i_2_n_2\,
      CO(0) => \transfer_cnt_reg[28]_i_2_n_3\,
      CYINIT => '0',
      DI(3 downto 0) => B"0000",
      O(3 downto 0) => data0(28 downto 25),
      S(3 downto 0) => transfer_cnt(28 downto 25)
    );
\transfer_cnt_reg[29]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tlast_i_1_n_0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => transfer_cnt_1(29),
      Q => transfer_cnt(29)
    );
\transfer_cnt_reg[2]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tlast_i_1_n_0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => transfer_cnt_1(2),
      Q => transfer_cnt(2)
    );
\transfer_cnt_reg[30]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tlast_i_1_n_0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => transfer_cnt_1(30),
      Q => transfer_cnt(30)
    );
\transfer_cnt_reg[31]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tlast_i_1_n_0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => transfer_cnt_1(31),
      Q => transfer_cnt(31)
    );
\transfer_cnt_reg[31]_i_2\: unisim.vcomponents.CARRY4
     port map (
      CI => \transfer_cnt_reg[28]_i_2_n_0\,
      CO(3 downto 2) => \NLW_transfer_cnt_reg[31]_i_2_CO_UNCONNECTED\(3 downto 2),
      CO(1) => \transfer_cnt_reg[31]_i_2_n_2\,
      CO(0) => \transfer_cnt_reg[31]_i_2_n_3\,
      CYINIT => '0',
      DI(3 downto 0) => B"0000",
      O(3) => \NLW_transfer_cnt_reg[31]_i_2_O_UNCONNECTED\(3),
      O(2 downto 0) => data0(31 downto 29),
      S(3) => '0',
      S(2 downto 0) => transfer_cnt(31 downto 29)
    );
\transfer_cnt_reg[3]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tlast_i_1_n_0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => transfer_cnt_1(3),
      Q => transfer_cnt(3)
    );
\transfer_cnt_reg[4]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tlast_i_1_n_0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => transfer_cnt_1(4),
      Q => transfer_cnt(4)
    );
\transfer_cnt_reg[4]_i_2\: unisim.vcomponents.CARRY4
     port map (
      CI => '0',
      CO(3) => \transfer_cnt_reg[4]_i_2_n_0\,
      CO(2) => \transfer_cnt_reg[4]_i_2_n_1\,
      CO(1) => \transfer_cnt_reg[4]_i_2_n_2\,
      CO(0) => \transfer_cnt_reg[4]_i_2_n_3\,
      CYINIT => transfer_cnt(0),
      DI(3 downto 0) => B"0000",
      O(3 downto 0) => data0(4 downto 1),
      S(3 downto 0) => transfer_cnt(4 downto 1)
    );
\transfer_cnt_reg[5]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tlast_i_1_n_0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => transfer_cnt_1(5),
      Q => transfer_cnt(5)
    );
\transfer_cnt_reg[6]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tlast_i_1_n_0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => transfer_cnt_1(6),
      Q => transfer_cnt(6)
    );
\transfer_cnt_reg[7]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tlast_i_1_n_0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => transfer_cnt_1(7),
      Q => transfer_cnt(7)
    );
\transfer_cnt_reg[8]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tlast_i_1_n_0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => transfer_cnt_1(8),
      Q => transfer_cnt(8)
    );
\transfer_cnt_reg[8]_i_2\: unisim.vcomponents.CARRY4
     port map (
      CI => \transfer_cnt_reg[4]_i_2_n_0\,
      CO(3) => \transfer_cnt_reg[8]_i_2_n_0\,
      CO(2) => \transfer_cnt_reg[8]_i_2_n_1\,
      CO(1) => \transfer_cnt_reg[8]_i_2_n_2\,
      CO(0) => \transfer_cnt_reg[8]_i_2_n_3\,
      CYINIT => '0',
      DI(3 downto 0) => B"0000",
      O(3 downto 0) => data0(8 downto 5),
      S(3 downto 0) => transfer_cnt(8 downto 5)
    );
\transfer_cnt_reg[9]\: unisim.vcomponents.FDCE
     port map (
      C => \^m_axis_aclk\,
      CE => m_axis_tlast_i_1_n_0,
      CLR => \adc_data[15]_i_1_n_0\,
      D => transfer_cnt_1(9),
      Q => transfer_cnt(9)
    );
u_ibufds_clkout: unisim.vcomponents.IBUFDS
     port map (
      I => clkout_p,
      IB => clkout_n,
      O => \^m_axis_aclk\
    );
u_ibufds_of: unisim.vcomponents.IBUFDS
     port map (
      I => of_p,
      IB => of_n,
      O => of_s
    );
u_obufds_enc: unisim.vcomponents.OBUFDS
     port map (
      I => enc_clk,
      O => enc_p,
      OB => enc_n
    );
end STRUCTURE;
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library UNISIM;
use UNISIM.VCOMPONENTS.ALL;
entity decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix is
  port (
    rst_n : in STD_LOGIC;
    enc_clk : in STD_LOGIC;
    enc_p : out STD_LOGIC;
    enc_n : out STD_LOGIC;
    clkout_p : in STD_LOGIC;
    clkout_n : in STD_LOGIC;
    data_p : in STD_LOGIC_VECTOR ( 15 downto 0 );
    data_n : in STD_LOGIC_VECTOR ( 15 downto 0 );
    of_p : in STD_LOGIC;
    of_n : in STD_LOGIC;
    adc_data : out STD_LOGIC_VECTOR ( 15 downto 0 );
    adc_of : out STD_LOGIC;
    adc_clk : out STD_LOGIC;
    m_axis_aclk : out STD_LOGIC;
    m_axis_tdata : out STD_LOGIC_VECTOR ( 15 downto 0 );
    m_axis_tvalid : out STD_LOGIC;
    m_axis_tready : in STD_LOGIC;
    m_axis_tlast : out STD_LOGIC;
    m_axis_tuser : out STD_LOGIC
  );
  attribute NotValidForBitStream : boolean;
  attribute NotValidForBitStream of decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix : entity is true;
  attribute CHECK_LICENSE_TYPE : string;
  attribute CHECK_LICENSE_TYPE of decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix : entity is "system_LTC2208_0_0,LTC2208,{}";
  attribute DowngradeIPIdentifiedWarnings : string;
  attribute DowngradeIPIdentifiedWarnings of decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix : entity is "yes";
  attribute IP_DEFINITION_SOURCE : string;
  attribute IP_DEFINITION_SOURCE of decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix : entity is "module_ref";
  attribute X_CORE_INFO : string;
  attribute X_CORE_INFO of decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix : entity is "LTC2208,Vivado 2021.1";
end decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix;

architecture STRUCTURE of decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix is
  signal \^m_axis_aclk\ : STD_LOGIC;
  attribute DIFF_TERM : boolean;
  attribute DIFF_TERM of m_axis_aclk : signal is std.standard.true;
  attribute IBUF_LOW_PWR : boolean;
  attribute IBUF_LOW_PWR of m_axis_aclk : signal is std.standard.true;
  attribute IOSTANDARD : string;
  attribute IOSTANDARD of m_axis_aclk : signal is "LVDS_25";
  attribute X_INTERFACE_INFO : string;
  attribute X_INTERFACE_INFO of adc_clk : signal is "xilinx.com:signal:clock:1.0 adc_clk CLK";
  attribute X_INTERFACE_PARAMETER : string;
  attribute X_INTERFACE_PARAMETER of adc_clk : signal is "XIL_INTERFACENAME adc_clk, FREQ_HZ 100000000, FREQ_TOLERANCE_HZ 0, PHASE 0.0, CLK_DOMAIN system_LTC2208_0_0_adc_clk, INSERT_VIP 0";
  attribute X_INTERFACE_INFO of enc_clk : signal is "xilinx.com:signal:clock:1.0 enc_clk CLK";
  attribute X_INTERFACE_PARAMETER of enc_clk : signal is "XIL_INTERFACENAME enc_clk, FREQ_HZ 130000000, FREQ_TOLERANCE_HZ 0, PHASE 0.0, CLK_DOMAIN /clk_wiz_0_clk_out1, INSERT_VIP 0";
  attribute X_INTERFACE_INFO of m_axis_aclk : signal is "xilinx.com:signal:clock:1.0 m_axis_aclk CLK";
  attribute X_INTERFACE_PARAMETER of m_axis_aclk : signal is "XIL_INTERFACENAME m_axis_aclk, ASSOCIATED_BUSIF m_axis, FREQ_HZ 100000000, FREQ_TOLERANCE_HZ 0, PHASE 0.0, CLK_DOMAIN system_LTC2208_0_0_m_axis_aclk, INSERT_VIP 0";
  attribute X_INTERFACE_INFO of m_axis_tlast : signal is "xilinx.com:interface:axis:1.0 m_axis TLAST";
  attribute X_INTERFACE_INFO of m_axis_tready : signal is "xilinx.com:interface:axis:1.0 m_axis TREADY";
  attribute X_INTERFACE_INFO of m_axis_tuser : signal is "xilinx.com:interface:axis:1.0 m_axis TUSER";
  attribute X_INTERFACE_PARAMETER of m_axis_tuser : signal is "XIL_INTERFACENAME m_axis, TDATA_NUM_BYTES 2, TDEST_WIDTH 0, TID_WIDTH 0, TUSER_WIDTH 1, HAS_TREADY 1, HAS_TSTRB 0, HAS_TKEEP 0, HAS_TLAST 1, FREQ_HZ 100000000, PHASE 0.0, CLK_DOMAIN system_LTC2208_0_0_m_axis_aclk, LAYERED_METADATA undef, INSERT_VIP 0";
  attribute X_INTERFACE_INFO of m_axis_tvalid : signal is "xilinx.com:interface:axis:1.0 m_axis TVALID";
  attribute X_INTERFACE_INFO of rst_n : signal is "xilinx.com:signal:reset:1.0 rst_n RST";
  attribute X_INTERFACE_PARAMETER of rst_n : signal is "XIL_INTERFACENAME rst_n, POLARITY ACTIVE_LOW, INSERT_VIP 0";
  attribute X_INTERFACE_INFO of m_axis_tdata : signal is "xilinx.com:interface:axis:1.0 m_axis TDATA";
begin
  adc_clk <= \^m_axis_aclk\;
  m_axis_aclk <= \^m_axis_aclk\;
inst: entity work.decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix_LTC2208
     port map (
      adc_data(15 downto 0) => adc_data(15 downto 0),
      adc_of => adc_of,
      clkout_n => clkout_n,
      clkout_p => clkout_p,
      data_n(15 downto 0) => data_n(15 downto 0),
      data_p(15 downto 0) => data_p(15 downto 0),
      enc_clk => enc_clk,
      enc_n => enc_n,
      enc_p => enc_p,
      m_axis_aclk => \^m_axis_aclk\,
      m_axis_tdata(15 downto 0) => m_axis_tdata(15 downto 0),
      m_axis_tlast => m_axis_tlast,
      m_axis_tready => m_axis_tready,
      m_axis_tuser => m_axis_tuser,
      m_axis_tvalid => m_axis_tvalid,
      of_n => of_n,
      of_p => of_p,
      rst_n => rst_n
    );
end STRUCTURE;
