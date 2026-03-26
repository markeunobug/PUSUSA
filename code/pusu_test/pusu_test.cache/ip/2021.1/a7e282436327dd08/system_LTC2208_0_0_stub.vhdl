-- Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
-- --------------------------------------------------------------------------------
-- Tool Version: Vivado v.2021.1 (win64) Build 3247384 Thu Jun 10 19:36:33 MDT 2021
-- Date        : Sun Mar 15 20:32:56 2026
-- Host        : MarkeuPro running 64-bit major release  (build 9200)
-- Command     : write_vhdl -force -mode synth_stub -rename_top decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix -prefix
--               decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix_ system_LTC2208_0_0_stub.vhdl
-- Design      : system_LTC2208_0_0
-- Purpose     : Stub declaration of top-level module interface
-- Device      : xc7z010clg400-1
-- --------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix is
  Port ( 
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

end decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix;

architecture stub of decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix is
attribute syn_black_box : boolean;
attribute black_box_pad_pin : string;
attribute syn_black_box of stub : architecture is true;
attribute black_box_pad_pin of stub : architecture is "rst_n,enc_clk,enc_p,enc_n,clkout_p,clkout_n,data_p[15:0],data_n[15:0],of_p,of_n,adc_data[15:0],adc_of,adc_clk,m_axis_aclk,m_axis_tdata[15:0],m_axis_tvalid,m_axis_tready,m_axis_tlast,m_axis_tuser";
attribute X_CORE_INFO : string;
attribute X_CORE_INFO of stub : architecture is "LTC2208,Vivado 2021.1";
begin
end;
