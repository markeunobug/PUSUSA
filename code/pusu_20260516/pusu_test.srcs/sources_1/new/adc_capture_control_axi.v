`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: adc_capture_control_axi
// Description:
//   AXI-Lite register wrapper for adc_capture_axis.
//
//   S_AXI runs in the PS FCLK domain. The capture core runs in adc_clk. This
//   wrapper provides write-pulse CDC for control events and two-stage status
//   sampling for readback. Multi-bit frame_len/frame_id are held stable by the
//   PS before start; they are double-sampled and latched in the adc_clk domain
//   before the start pulse is issued to adc_capture_axis.
//////////////////////////////////////////////////////////////////////////////////
module adc_capture_control_axi #(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 6,
    parameter [31:0]  VERSION            = 32'h20260607
)(
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME s_axi_aclk, ASSOCIATED_BUSIF S_AXI, ASSOCIATED_RESET s_axi_aresetn" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 s_axi_aclk CLK" *)
    input  wire                              s_axi_aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 s_axi_aresetn RST" *)
    input  wire                              s_axi_aresetn,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR" *)
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]     s_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWPROT" *)
    input  wire [2:0]                        s_axi_awprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *)
    input  wire                              s_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *)
    output wire                              s_axi_awready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WDATA" *)
    input  wire [C_S_AXI_DATA_WIDTH-1:0]     s_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *)
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WVALID" *)
    input  wire                              s_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WREADY" *)
    output wire                              s_axi_wready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BRESP" *)
    output reg [1:0]                         s_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BVALID" *)
    output reg                               s_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BREADY" *)
    input  wire                              s_axi_bready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *)
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]     s_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARPROT" *)
    input  wire [2:0]                        s_axi_arprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *)
    input  wire                              s_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *)
    output wire                              s_axi_arready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RDATA" *)
    output reg [C_S_AXI_DATA_WIDTH-1:0]      s_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RRESP" *)
    output reg [1:0]                         s_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RVALID" *)
    output reg                               s_axi_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RREADY" *)
    input  wire                              s_axi_rready,

    input  wire                              adc_clk,
    input  wire                              adc_rst_n,

    output reg                               capture_start,
    output reg                               capture_abort,
    output reg                               capture_clear_status,
    output reg                               capture_clear_counters,
    output reg                               capture_continuous_mode,
    output reg                               capture_stream_enable,
    output reg [15:0]                        capture_frame_len,
    output reg [31:0]                        capture_frame_id,
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME fifo_resetn, POLARITY ACTIVE_LOW" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 fifo_resetn RST" *)
    output reg                               fifo_resetn,

    input  wire                              status_busy,
    input  wire                              status_done,
    input  wire                              status_error,
    input  wire                              status_overflow_seen,
    input  wire                              status_backpressure_seen,
    input  wire                              status_tlast_seen,
    input  wire                              status_streaming,
    input  wire [15:0]                       status_sample_count,
    input  wire [31:0]                       status_frame_id,
    input  wire [7:0]                        status_error_code,
    input  wire [31:0]                       status_total_sample_count_lo,
    input  wire [31:0]                       status_total_sample_count_hi,
    input  wire [31:0]                       status_packet_count,
    input  wire [31:0]                       status_overflow_count,
    input  wire [31:0]                       status_backpressure_count
);

    localparam [3:0] REG_CONTROL               = 4'd0;  // 0x00
    localparam [3:0] REG_STATUS                = 4'd1;  // 0x04
    localparam [3:0] REG_FRAME_LEN             = 4'd2;  // 0x08
    localparam [3:0] REG_FRAME_ID              = 4'd3;  // 0x0C
    localparam [3:0] REG_SAMPLE_COUNT          = 4'd4;  // 0x10
    localparam [3:0] REG_DONE_FRAME_ID         = 4'd5;  // 0x14
    localparam [3:0] REG_ERROR_CODE            = 4'd6;  // 0x18
    localparam [3:0] REG_VERSION               = 4'd7;  // 0x1C
    localparam [3:0] REG_TOTAL_SAMPLE_COUNT_LO = 4'd8;  // 0x20
    localparam [3:0] REG_TOTAL_SAMPLE_COUNT_HI = 4'd9;  // 0x24
    localparam [3:0] REG_PACKET_COUNT          = 4'd10; // 0x28
    localparam [3:0] REG_OVERFLOW_COUNT        = 4'd11; // 0x2C
    localparam [3:0] REG_BACKPRESSURE_COUNT    = 4'd12; // 0x30

    localparam [1:0] AXI_RESP_OKAY = 2'b00;

    reg [15:0] frame_len_axi;
    reg [31:0] frame_id_axi;

    reg [C_S_AXI_ADDR_WIDTH-1:0] awaddr_latched;
    reg                          awaddr_valid;
    reg [31:0]                   wdata_latched;
    reg [3:0]                    wstrb_latched;
    reg                          wdata_valid;

    reg start_toggle_axi;
    reg abort_toggle_axi;
    reg clear_toggle_axi;
    reg counter_clear_toggle_axi;
    reg soft_reset_toggle_axi;
    reg continuous_mode_axi;
    reg stream_enable_axi;
    reg fifo_reset_axi;

    reg [2:0] start_sync_adc;
    reg [2:0] abort_sync_adc;
    reg [2:0] clear_sync_adc;
    reg [2:0] counter_clear_sync_adc;
    reg [2:0] soft_reset_sync_adc;

    reg [15:0] frame_len_adc_meta;
    reg [15:0] frame_len_adc_sync;
    reg [31:0] frame_id_adc_meta;
    reg [31:0] frame_id_adc_sync;
    reg continuous_mode_adc_meta;
    reg continuous_mode_adc_sync;
    reg stream_enable_adc_meta;
    reg stream_enable_adc_sync;
    reg fifo_reset_adc_meta;
    reg fifo_reset_adc_sync;

    reg status_busy_axi_1;
    reg status_busy_axi_2;
    reg status_done_axi_1;
    reg status_done_axi_2;
    reg status_error_axi_1;
    reg status_error_axi_2;
    reg status_overflow_axi_1;
    reg status_overflow_axi_2;
    reg status_backpressure_axi_1;
    reg status_backpressure_axi_2;
    reg status_tlast_axi_1;
    reg status_tlast_axi_2;
    reg status_streaming_axi_1;
    reg status_streaming_axi_2;

    reg [15:0] sample_count_axi_1;
    reg [15:0] sample_count_axi_2;
    reg [31:0] done_frame_id_axi_1;
    reg [31:0] done_frame_id_axi_2;
    reg [7:0]  error_code_axi_1;
    reg [7:0]  error_code_axi_2;
    reg [31:0] total_sample_count_lo_axi_1;
    reg [31:0] total_sample_count_lo_axi_2;
    reg [31:0] total_sample_count_hi_axi_1;
    reg [31:0] total_sample_count_hi_axi_2;
    reg [31:0] packet_count_axi_1;
    reg [31:0] packet_count_axi_2;
    reg [31:0] overflow_count_axi_1;
    reg [31:0] overflow_count_axi_2;
    reg [31:0] backpressure_count_axi_1;
    reg [31:0] backpressure_count_axi_2;

    wire                              aw_accept;
    wire                              w_accept;
    wire                              write_fire;
    wire                              read_fire;
    wire [C_S_AXI_ADDR_WIDTH-1:0]     write_addr;
    wire [31:0]                       write_data;
    wire [3:0]                        write_wstrb;
    wire [3:0]                        write_reg_sel;
    wire [3:0]                        read_reg_sel;
    wire [31:0] status_word_axi;

    assign s_axi_awready = !awaddr_valid && !s_axi_bvalid;
    assign s_axi_wready  = !wdata_valid && !s_axi_bvalid;
    assign s_axi_arready = !s_axi_rvalid;

    assign aw_accept = s_axi_awvalid && s_axi_awready;
    assign w_accept  = s_axi_wvalid && s_axi_wready;
    assign write_fire = (awaddr_valid || aw_accept) &&
                        (wdata_valid || w_accept) &&
                        !s_axi_bvalid;
    assign read_fire = s_axi_arvalid && s_axi_arready;
    assign write_addr = aw_accept ? s_axi_awaddr : awaddr_latched;
    assign write_data = w_accept ? s_axi_wdata : wdata_latched;
    assign write_wstrb = w_accept ? s_axi_wstrb : wstrb_latched;
    assign write_reg_sel = addr_to_reg_sel(write_addr);
    assign read_reg_sel = addr_to_reg_sel(s_axi_araddr);

    assign status_word_axi = {
        24'd0,
        status_streaming_axi_2,
        status_tlast_axi_2,
        status_backpressure_axi_2,
        status_overflow_axi_2,
        status_error_axi_2,
        status_done_axi_2,
        status_busy_axi_2,
        ~status_busy_axi_2
    };

    function [31:0] apply_wstrb;
        input [31:0] old_value;
        input [31:0] new_value;
        input [3:0]  wstrb;
        integer i;
        begin
            apply_wstrb = old_value;
            for (i = 0; i < 4; i = i + 1) begin
                if (wstrb[i]) begin
                    apply_wstrb[(8 * i) +: 8] = new_value[(8 * i) +: 8];
                end
            end
        end
    endfunction

    function [31:0] read_register;
        input [3:0] reg_sel;
        begin
            case (reg_sel)
                REG_CONTROL:
                    read_register = {24'd0,
                                     fifo_reset_axi,
                                     1'b0,
                                     stream_enable_axi,
                                     continuous_mode_axi,
                                     4'd0};
                REG_STATUS:        read_register = status_word_axi;
                REG_FRAME_LEN:     read_register = {16'd0, frame_len_axi};
                REG_FRAME_ID:      read_register = frame_id_axi;
                REG_SAMPLE_COUNT:  read_register = {16'd0, sample_count_axi_2};
                REG_DONE_FRAME_ID: read_register = done_frame_id_axi_2;
                REG_ERROR_CODE:    read_register = {24'd0, error_code_axi_2};
                REG_VERSION:       read_register = VERSION;
                REG_TOTAL_SAMPLE_COUNT_LO:
                    read_register = total_sample_count_lo_axi_2;
                REG_TOTAL_SAMPLE_COUNT_HI:
                    read_register = total_sample_count_hi_axi_2;
                REG_PACKET_COUNT:
                    read_register = packet_count_axi_2;
                REG_OVERFLOW_COUNT:
                    read_register = overflow_count_axi_2;
                REG_BACKPRESSURE_COUNT:
                    read_register = backpressure_count_axi_2;
                default:           read_register = 32'd0;
            endcase
        end
    endfunction

    function [3:0] addr_to_reg_sel;
        input [C_S_AXI_ADDR_WIDTH-1:0] addr;
        begin
            addr_to_reg_sel = (addr >> 2);
        end
    endfunction

    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_bresp         <= AXI_RESP_OKAY;
            s_axi_bvalid        <= 1'b0;
            s_axi_rdata         <= 32'd0;
            s_axi_rresp         <= AXI_RESP_OKAY;
            s_axi_rvalid        <= 1'b0;

            awaddr_latched      <= {C_S_AXI_ADDR_WIDTH{1'b0}};
            awaddr_valid        <= 1'b0;
            wdata_latched       <= 32'd0;
            wstrb_latched       <= 4'd0;
            wdata_valid         <= 1'b0;
            frame_len_axi       <= 16'd4096;
            frame_id_axi        <= 32'd0;
            start_toggle_axi    <= 1'b0;
            abort_toggle_axi    <= 1'b0;
            clear_toggle_axi    <= 1'b0;
            counter_clear_toggle_axi <= 1'b0;
            soft_reset_toggle_axi <= 1'b0;
            continuous_mode_axi <= 1'b0;
            stream_enable_axi   <= 1'b0;
            fifo_reset_axi      <= 1'b0;
        end else begin
            if (aw_accept) begin
                awaddr_latched <= s_axi_awaddr;
                awaddr_valid   <= 1'b1;
            end

            if (w_accept) begin
                wdata_latched <= s_axi_wdata;
                wstrb_latched <= s_axi_wstrb;
                wdata_valid   <= 1'b1;
            end

            if (write_fire) begin
                awaddr_valid <= 1'b0;
                wdata_valid  <= 1'b0;
                s_axi_bresp  <= AXI_RESP_OKAY;
                s_axi_bvalid <= 1'b1;

                case (write_reg_sel)
                    REG_CONTROL: begin
                        if (write_wstrb[0]) begin
                            if (write_data[0]) begin
                                start_toggle_axi <= ~start_toggle_axi;
                            end
                            if (write_data[1]) begin
                                abort_toggle_axi <= ~abort_toggle_axi;
                            end
                            if (write_data[2]) begin
                                clear_toggle_axi <= ~clear_toggle_axi;
                            end
                            if (write_data[3]) begin
                                soft_reset_toggle_axi <= ~soft_reset_toggle_axi;
                            end
                            continuous_mode_axi <= write_data[4];
                            stream_enable_axi   <= write_data[5];
                            if (write_data[6]) begin
                                counter_clear_toggle_axi <= ~counter_clear_toggle_axi;
                            end
                            fifo_reset_axi <= write_data[7];
                        end
                    end

                    REG_FRAME_LEN: begin
                        if (write_wstrb[0]) begin
                            frame_len_axi[7:0] <= write_data[7:0];
                        end
                        if (write_wstrb[1]) begin
                            frame_len_axi[15:8] <= write_data[15:8];
                        end
                    end

                    REG_FRAME_ID: begin
                        frame_id_axi <= apply_wstrb(frame_id_axi,
                                                    write_data,
                                                    write_wstrb);
                    end

                    default: begin
                    end
                endcase
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end

            if (read_fire) begin
                s_axi_rdata   <= read_register(read_reg_sel);
                s_axi_rresp   <= AXI_RESP_OKAY;
                s_axi_rvalid  <= 1'b1;
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            status_busy_axi_1         <= 1'b0;
            status_busy_axi_2         <= 1'b0;
            status_done_axi_1         <= 1'b0;
            status_done_axi_2         <= 1'b0;
            status_error_axi_1        <= 1'b0;
            status_error_axi_2        <= 1'b0;
            status_overflow_axi_1     <= 1'b0;
            status_overflow_axi_2     <= 1'b0;
            status_backpressure_axi_1 <= 1'b0;
            status_backpressure_axi_2 <= 1'b0;
            status_tlast_axi_1        <= 1'b0;
            status_tlast_axi_2        <= 1'b0;
            status_streaming_axi_1    <= 1'b0;
            status_streaming_axi_2    <= 1'b0;
            sample_count_axi_1        <= 16'd0;
            sample_count_axi_2        <= 16'd0;
            done_frame_id_axi_1       <= 32'd0;
            done_frame_id_axi_2       <= 32'd0;
            error_code_axi_1          <= 8'd0;
            error_code_axi_2          <= 8'd0;
            total_sample_count_lo_axi_1 <= 32'd0;
            total_sample_count_lo_axi_2 <= 32'd0;
            total_sample_count_hi_axi_1 <= 32'd0;
            total_sample_count_hi_axi_2 <= 32'd0;
            packet_count_axi_1          <= 32'd0;
            packet_count_axi_2          <= 32'd0;
            overflow_count_axi_1        <= 32'd0;
            overflow_count_axi_2        <= 32'd0;
            backpressure_count_axi_1    <= 32'd0;
            backpressure_count_axi_2    <= 32'd0;
        end else begin
            status_busy_axi_1         <= status_busy;
            status_busy_axi_2         <= status_busy_axi_1;
            status_done_axi_1         <= status_done;
            status_done_axi_2         <= status_done_axi_1;
            status_error_axi_1        <= status_error;
            status_error_axi_2        <= status_error_axi_1;
            status_overflow_axi_1     <= status_overflow_seen;
            status_overflow_axi_2     <= status_overflow_axi_1;
            status_backpressure_axi_1 <= status_backpressure_seen;
            status_backpressure_axi_2 <= status_backpressure_axi_1;
            status_tlast_axi_1        <= status_tlast_seen;
            status_tlast_axi_2        <= status_tlast_axi_1;
            status_streaming_axi_1    <= status_streaming;
            status_streaming_axi_2    <= status_streaming_axi_1;
            sample_count_axi_1        <= status_sample_count;
            sample_count_axi_2        <= sample_count_axi_1;
            done_frame_id_axi_1       <= status_frame_id;
            done_frame_id_axi_2       <= done_frame_id_axi_1;
            error_code_axi_1          <= status_error_code;
            error_code_axi_2          <= error_code_axi_1;
            total_sample_count_lo_axi_1 <= status_total_sample_count_lo;
            total_sample_count_lo_axi_2 <= total_sample_count_lo_axi_1;
            total_sample_count_hi_axi_1 <= status_total_sample_count_hi;
            total_sample_count_hi_axi_2 <= total_sample_count_hi_axi_1;
            packet_count_axi_1          <= status_packet_count;
            packet_count_axi_2          <= packet_count_axi_1;
            overflow_count_axi_1        <= status_overflow_count;
            overflow_count_axi_2        <= overflow_count_axi_1;
            backpressure_count_axi_1    <= status_backpressure_count;
            backpressure_count_axi_2    <= backpressure_count_axi_1;
        end
    end

    always @(posedge adc_clk) begin
        if (!adc_rst_n) begin
            start_sync_adc        <= 3'd0;
            abort_sync_adc        <= 3'd0;
            clear_sync_adc        <= 3'd0;
            counter_clear_sync_adc <= 3'd0;
            soft_reset_sync_adc   <= 3'd0;
            frame_len_adc_meta    <= 16'd4096;
            frame_len_adc_sync    <= 16'd4096;
            frame_id_adc_meta     <= 32'd0;
            frame_id_adc_sync     <= 32'd0;
            continuous_mode_adc_meta <= 1'b0;
            continuous_mode_adc_sync <= 1'b0;
            stream_enable_adc_meta <= 1'b0;
            stream_enable_adc_sync <= 1'b0;
            fifo_reset_adc_meta <= 1'b0;
            fifo_reset_adc_sync <= 1'b0;
            capture_start         <= 1'b0;
            capture_abort         <= 1'b0;
            capture_clear_status  <= 1'b0;
            capture_clear_counters <= 1'b0;
            capture_continuous_mode <= 1'b0;
            capture_stream_enable <= 1'b0;
            capture_frame_len     <= 16'd4096;
            capture_frame_id      <= 32'd0;
            fifo_resetn           <= 1'b1;
        end else begin
            start_sync_adc      <= {start_sync_adc[1:0], start_toggle_axi};
            abort_sync_adc      <= {abort_sync_adc[1:0], abort_toggle_axi};
            clear_sync_adc      <= {clear_sync_adc[1:0], clear_toggle_axi};
            counter_clear_sync_adc <=
                {counter_clear_sync_adc[1:0], counter_clear_toggle_axi};
            soft_reset_sync_adc <= {soft_reset_sync_adc[1:0], soft_reset_toggle_axi};

            frame_len_adc_meta <= frame_len_axi;
            frame_len_adc_sync <= frame_len_adc_meta;
            frame_id_adc_meta  <= frame_id_axi;
            frame_id_adc_sync  <= frame_id_adc_meta;
            continuous_mode_adc_meta <= continuous_mode_axi;
            continuous_mode_adc_sync <= continuous_mode_adc_meta;
            stream_enable_adc_meta <= stream_enable_axi;
            stream_enable_adc_sync <= stream_enable_adc_meta;
            fifo_reset_adc_meta <= fifo_reset_axi;
            fifo_reset_adc_sync <= fifo_reset_adc_meta;

            capture_start        <= 1'b0;
            capture_abort        <= 1'b0;
            capture_clear_status <= 1'b0;
            capture_clear_counters <= 1'b0;
            capture_continuous_mode <= continuous_mode_adc_sync;
            capture_stream_enable <= stream_enable_adc_sync;
            capture_frame_len <= frame_len_adc_sync;
            capture_frame_id <= frame_id_adc_sync;
            fifo_resetn <= ~fifo_reset_adc_sync;

            if (start_sync_adc[2] ^ start_sync_adc[1]) begin
                capture_start     <= 1'b1;
            end

            if (abort_sync_adc[2] ^ abort_sync_adc[1]) begin
                capture_abort <= 1'b1;
            end

            if (clear_sync_adc[2] ^ clear_sync_adc[1]) begin
                capture_clear_status <= 1'b1;
            end

            if (counter_clear_sync_adc[2] ^ counter_clear_sync_adc[1]) begin
                capture_clear_counters <= 1'b1;
            end

            if (soft_reset_sync_adc[2] ^ soft_reset_sync_adc[1]) begin
                capture_abort        <= 1'b1;
                capture_clear_status <= 1'b1;
                capture_clear_counters <= 1'b1;
            end
        end
    end

    // Unused AXI protection signals are intentionally ignored.
    wire unused_axi_inputs;
    assign unused_axi_inputs = ^{s_axi_awprot, s_axi_arprot};

endmodule
