`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: pusu_pl_dsp_axi_regs
//
// Lightweight AXI-Lite register bank for pusu_pl_dsp_core.
//
// This module intentionally stays small.  It gives PS a stable way to select
// RBW mode and lets PS read back the PL sample rate / decimation metadata
// before interpreting DMA IQ data.
//////////////////////////////////////////////////////////////////////////////////

module pusu_pl_dsp_axi_regs #(
    parameter integer C_S_AXI_ADDR_WIDTH = 6,
    parameter integer C_S_AXI_DATA_WIDTH = 32
)(
    input  wire                              s_axi_aclk,
    input  wire                              s_axi_aresetn,

    input  wire [C_S_AXI_ADDR_WIDTH-1:0]     s_axi_awaddr,
    input  wire                              s_axi_awvalid,
    output reg                               s_axi_awready,
    input  wire [C_S_AXI_DATA_WIDTH-1:0]     s_axi_wdata,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input  wire                              s_axi_wvalid,
    output reg                               s_axi_wready,
    output reg  [1:0]                        s_axi_bresp,
    output reg                               s_axi_bvalid,
    input  wire                              s_axi_bready,

    input  wire [C_S_AXI_ADDR_WIDTH-1:0]     s_axi_araddr,
    input  wire                              s_axi_arvalid,
    output reg                               s_axi_arready,
    output reg  [C_S_AXI_DATA_WIDTH-1:0]     s_axi_rdata,
    output reg  [1:0]                        s_axi_rresp,
    output reg                               s_axi_rvalid,
    input  wire                              s_axi_rready,

    output reg                               pl_enable,
    output reg                               pl_soft_reset,
    output reg                               pl_clear_status,
    output reg                               pl_mode_update,
    output reg                               pl_abort,
    output reg                               pl_stream_reset,
    output reg  [2:0]                        pl_rbw_mode,
    output reg  [1:0]                        pl_output_select,
    output reg  [31:0]                       pl_frame_words,

    input  wire [31:0]                       pl_status_word,
    input  wire [31:0]                       pl_sample_rate_hz,
    input  wire [31:0]                       pl_decimation_ratio,
    input  wire [31:0]                       pl_data_format,
    input  wire [31:0]                       pl_input_sample_count,
    input  wire [31:0]                       pl_output_sample_count,
    input  wire [31:0]                       pl_output_drop_count,
    input  wire [31:0]                       pl_error_code,
    input  wire [31:0]                       pl_version
);

    localparam [5:0] REG_CONTROL             = 6'h00;
    localparam [5:0] REG_STATUS              = 6'h04;
    localparam [5:0] REG_RBW_MODE            = 6'h08;
    localparam [5:0] REG_OUTPUT_SELECT       = 6'h0C;
    localparam [5:0] REG_SAMPLE_RATE_HZ      = 6'h10;
    localparam [5:0] REG_DECIMATION_RATIO    = 6'h14;
    localparam [5:0] REG_FRAME_WORDS         = 6'h18;
    localparam [5:0] REG_DATA_FORMAT         = 6'h1C;
    localparam [5:0] REG_INPUT_SAMPLE_COUNT  = 6'h20;
    localparam [5:0] REG_OUTPUT_SAMPLE_COUNT = 6'h24;
    localparam [5:0] REG_OUTPUT_DROP_COUNT   = 6'h28;
    localparam [5:0] REG_ERROR_CODE          = 6'h2C;
    localparam [5:0] REG_VERSION             = 6'h30;

    reg [C_S_AXI_ADDR_WIDTH-1:0]     awaddr_hold;
    reg                              aw_hold_valid;
    reg [C_S_AXI_DATA_WIDTH-1:0]     wdata_hold;
    reg [(C_S_AXI_DATA_WIDTH/8)-1:0] wstrb_hold;
    reg                              w_hold_valid;

    wire aw_accept = s_axi_awvalid && !aw_hold_valid && !s_axi_bvalid;
    wire w_accept = s_axi_wvalid && !w_hold_valid && !s_axi_bvalid;
    wire write_fire = !s_axi_bvalid &&
                      (aw_hold_valid || aw_accept) &&
                      (w_hold_valid || w_accept);
    wire [C_S_AXI_ADDR_WIDTH-1:0] write_addr =
        aw_hold_valid ? awaddr_hold : s_axi_awaddr;
    wire [C_S_AXI_DATA_WIDTH-1:0] write_data =
        w_hold_valid ? wdata_hold : s_axi_wdata;
    wire [(C_S_AXI_DATA_WIDTH/8)-1:0] write_strb =
        w_hold_valid ? wstrb_hold : s_axi_wstrb;

    wire read_fire = s_axi_arvalid && !s_axi_rvalid;

    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_awready <= 1'b0;
            s_axi_wready <= 1'b0;
            s_axi_bresp <= 2'b00;
            s_axi_bvalid <= 1'b0;
            s_axi_arready <= 1'b0;
            s_axi_rdata <= 32'd0;
            s_axi_rresp <= 2'b00;
            s_axi_rvalid <= 1'b0;
            awaddr_hold <= {C_S_AXI_ADDR_WIDTH{1'b0}};
            aw_hold_valid <= 1'b0;
            wdata_hold <= {C_S_AXI_DATA_WIDTH{1'b0}};
            wstrb_hold <= {(C_S_AXI_DATA_WIDTH/8){1'b0}};
            w_hold_valid <= 1'b0;

            pl_enable <= 1'b0;
            pl_soft_reset <= 1'b0;
            pl_clear_status <= 1'b0;
            pl_mode_update <= 1'b0;
            pl_abort <= 1'b0;
            pl_stream_reset <= 1'b0;
            pl_rbw_mode <= 3'd2;       // 100K default, matches legacy /130 bring-up.
            pl_output_select <= 2'd1;  // decimated IQ
            pl_frame_words <= 32'd4096;
        end else begin
            s_axi_awready <= 1'b0;
            s_axi_wready <= 1'b0;
            s_axi_arready <= 1'b0;
            pl_soft_reset <= 1'b0;
            pl_clear_status <= 1'b0;
            pl_mode_update <= 1'b0;
            pl_abort <= 1'b0;

            if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end

            if (aw_accept) begin
                s_axi_awready <= 1'b1;
            end

            if (w_accept) begin
                s_axi_wready <= 1'b1;
            end

            if (write_fire) begin
                s_axi_bvalid <= 1'b1;
                s_axi_bresp <= 2'b00;
                aw_hold_valid <= 1'b0;
                w_hold_valid <= 1'b0;

                case (write_addr[5:0])
                    REG_CONTROL: begin
                        if (write_strb[0]) begin
                            pl_enable <= write_data[0];
                            pl_soft_reset <= write_data[1];
                            pl_clear_status <= write_data[2];
                            pl_mode_update <= write_data[3];
                            pl_abort <= write_data[4];
                            pl_stream_reset <= write_data[5];
                        end
                    end
                    REG_RBW_MODE: begin
                        if (write_strb[0]) begin
                            pl_rbw_mode <= write_data[2:0];
                        end
                    end
                    REG_OUTPUT_SELECT: begin
                        if (write_strb[0]) begin
                            pl_output_select <= write_data[1:0];
                        end
                    end
                    REG_FRAME_WORDS: begin
                        pl_frame_words <= merge_wstrb(pl_frame_words, write_data, write_strb);
                    end
                    default: begin
                        // Read-only or reserved register.  Return OKAY for simple PS code.
                    end
                endcase
            end else begin
                if (aw_accept) begin
                    awaddr_hold <= s_axi_awaddr;
                    aw_hold_valid <= 1'b1;
                end

                if (w_accept) begin
                    wdata_hold <= s_axi_wdata;
                    wstrb_hold <= s_axi_wstrb;
                    w_hold_valid <= 1'b1;
                end
            end

            if (read_fire) begin
                s_axi_arready <= 1'b1;
                s_axi_rvalid <= 1'b1;
                s_axi_rresp <= 2'b00;

                case (s_axi_araddr[5:0])
                    REG_CONTROL:             s_axi_rdata <= {26'd0, pl_stream_reset, 4'd0, pl_enable};
                    REG_STATUS:              s_axi_rdata <= pl_status_word;
                    REG_RBW_MODE:            s_axi_rdata <= {29'd0, pl_rbw_mode};
                    REG_OUTPUT_SELECT:       s_axi_rdata <= {30'd0, pl_output_select};
                    REG_SAMPLE_RATE_HZ:      s_axi_rdata <= pl_sample_rate_hz;
                    REG_DECIMATION_RATIO:    s_axi_rdata <= pl_decimation_ratio;
                    REG_FRAME_WORDS:         s_axi_rdata <= pl_frame_words;
                    REG_DATA_FORMAT:         s_axi_rdata <= pl_data_format;
                    REG_INPUT_SAMPLE_COUNT:  s_axi_rdata <= pl_input_sample_count;
                    REG_OUTPUT_SAMPLE_COUNT: s_axi_rdata <= pl_output_sample_count;
                    REG_OUTPUT_DROP_COUNT:   s_axi_rdata <= pl_output_drop_count;
                    REG_ERROR_CODE:          s_axi_rdata <= pl_error_code;
                    REG_VERSION:             s_axi_rdata <= pl_version;
                    default:                 s_axi_rdata <= 32'd0;
                endcase
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

    function [31:0] merge_wstrb;
        input [31:0] old_value;
        input [31:0] new_value;
        input [3:0]  strb;
        integer i;
        begin
            merge_wstrb = old_value;
            for (i = 0; i < 4; i = i + 1) begin
                if (strb[i]) begin
                    merge_wstrb[i*8 +: 8] = new_value[i*8 +: 8];
                end
            end
        end
    endfunction

endmodule
