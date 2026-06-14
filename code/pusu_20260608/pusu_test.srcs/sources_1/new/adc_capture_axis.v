`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: adc_capture_axis
// Description:
//   Controlled ADC sample gate for AXI DMA S2MM capture.
//
//   Mode 0: verified single-frame capture. PS arms DMA, pulses ctrl_start, and
//           this block emits exactly ctrl_frame_len samples with one TLAST.
//   Mode 1: continuous stream capture. PS enables ctrl_continuous_mode and
//           ctrl_stream_enable, and this block emits fixed-size AXIS packets
//           continuously with TLAST every ctrl_frame_len samples when
//           ctrl_frame_count is zero. A non-zero ctrl_frame_count starts a
//           finite burst only on ctrl_start and stops after that many packets.
//////////////////////////////////////////////////////////////////////////////////
module adc_capture_axis #(
    parameter integer MAX_FRAME_LEN = 16384
)(
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME adc_clk, ASSOCIATED_BUSIF m_axis, ASSOCIATED_RESET rst_n" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 adc_clk CLK" *)
    input  wire               adc_clk,
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME rst_n, POLARITY ACTIVE_LOW" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst_n RST" *)
    input  wire               rst_n,

    input  wire signed [15:0] adc_sample,
    input  wire               adc_overflow,

    input  wire               ctrl_start,
    input  wire               ctrl_abort,
    input  wire               ctrl_clear_status,
    input  wire               ctrl_clear_counters,
    input  wire               ctrl_continuous_mode,
    input  wire               ctrl_stream_enable,
    input  wire        [15:0] ctrl_frame_len,
    input  wire        [31:0] ctrl_frame_count,
    input  wire        [31:0] ctrl_frame_id,

    output reg                status_busy,
    output reg                status_done,
    output reg                status_error,
    output reg                status_overflow_seen,
    output reg                status_backpressure_seen,
    output reg                status_tlast_seen,
    output reg                status_streaming,
    output reg                status_burst_active,
    output reg                status_burst_done,
    output reg         [15:0] status_sample_count,
    output reg         [31:0] status_frame_id,
    output reg         [7:0]  status_error_code,
    output reg         [31:0] status_total_sample_count_lo,
    output reg         [31:0] status_total_sample_count_hi,
    output reg         [31:0] status_packet_count,
    output reg         [31:0] status_burst_packet_count,
    output reg         [31:0] status_burst_remaining,
    output reg         [31:0] status_overflow_count,
    output reg         [31:0] status_backpressure_count,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis TDATA" *)
    output reg signed  [15:0] m_axis_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis TVALID" *)
    output reg                m_axis_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis TREADY" *)
    input  wire               m_axis_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis TLAST" *)
    output reg                m_axis_tlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis TUSER" *)
    output reg                m_axis_tuser
);

    localparam [1:0] ST_IDLE    = 2'd0;
    localparam [1:0] ST_CAPTURE = 2'd1;
    localparam [1:0] ST_DONE    = 2'd2;
    localparam [1:0] ST_STREAM  = 2'd3;

    localparam [7:0] ERR_NONE              = 8'd0;
    localparam [7:0] ERR_INVALID_FRAME_LEN = 8'd1;
    localparam [7:0] ERR_START_WHILE_BUSY  = 8'd2;
    localparam [7:0] ERR_ADC_OVERFLOW      = 8'd3;
    localparam [7:0] ERR_BACKPRESSURE      = 8'd4;
    localparam [7:0] ERR_ABORT             = 8'd5;
    localparam [7:0] ERR_INVALID_FRAME_COUNT = 8'd6;

    reg [1:0]  state;
    reg [15:0] frame_len_reg;
    reg [31:0] frame_count_reg;
    reg        ctrl_start_d;

    wire       start_req;
    wire       frame_len_invalid;
    wire       axis_accept;
    wire       axis_last_beat;
    wire       continuous_req;
    wire       finite_burst_req;
    wire       infinite_stream_req;

    assign start_req = ctrl_start & ~ctrl_start_d;
    assign frame_len_invalid =
        (ctrl_frame_len == 16'd0) || (ctrl_frame_len > MAX_FRAME_LEN);
    assign axis_accept = m_axis_tvalid & m_axis_tready;
    assign axis_last_beat = (status_sample_count == (frame_len_reg - 16'd1));
    assign continuous_req = ctrl_continuous_mode & ctrl_stream_enable;
    assign finite_burst_req = continuous_req & (ctrl_frame_count != 32'd0);
    assign infinite_stream_req = continuous_req & (ctrl_frame_count == 32'd0);

    task clear_status_flags;
        begin
            status_done              <= 1'b0;
            status_error             <= 1'b0;
            status_overflow_seen     <= 1'b0;
            status_backpressure_seen <= 1'b0;
            status_tlast_seen        <= 1'b0;
            status_burst_active      <= 1'b0;
            status_burst_done        <= 1'b0;
            status_sample_count      <= 16'd0;
            status_frame_id          <= 32'd0;
            status_error_code        <= ERR_NONE;
            status_burst_packet_count <= 32'd0;
            status_burst_remaining   <= 32'd0;
        end
    endtask

    task clear_counters;
        begin
            status_total_sample_count_lo <= 32'd0;
            status_total_sample_count_hi <= 32'd0;
            status_packet_count          <= 32'd0;
            status_burst_packet_count    <= 32'd0;
            status_overflow_count        <= 32'd0;
            status_backpressure_count    <= 32'd0;
        end
    endtask

    task increment_total_sample_count;
        begin
            status_total_sample_count_lo <= status_total_sample_count_lo + 32'd1;
            if (status_total_sample_count_lo == 32'hFFFF_FFFF) begin
                status_total_sample_count_hi <= status_total_sample_count_hi + 32'd1;
            end
        end
    endtask

    always @(posedge adc_clk) begin
        if (!rst_n) begin
            state                    <= ST_IDLE;
            frame_len_reg            <= 16'd0;
            frame_count_reg           <= 32'd0;
            ctrl_start_d             <= 1'b0;

            status_busy              <= 1'b0;
            status_done              <= 1'b0;
            status_error             <= 1'b0;
            status_overflow_seen     <= 1'b0;
            status_backpressure_seen <= 1'b0;
            status_tlast_seen        <= 1'b0;
            status_streaming         <= 1'b0;
            status_burst_active      <= 1'b0;
            status_burst_done        <= 1'b0;
            status_sample_count      <= 16'd0;
            status_frame_id          <= 32'd0;
            status_error_code        <= ERR_NONE;
            status_total_sample_count_lo <= 32'd0;
            status_total_sample_count_hi <= 32'd0;
            status_packet_count          <= 32'd0;
            status_burst_packet_count    <= 32'd0;
            status_burst_remaining       <= 32'd0;
            status_overflow_count        <= 32'd0;
            status_backpressure_count    <= 32'd0;

            m_axis_tdata             <= 16'sd0;
            m_axis_tvalid            <= 1'b0;
            m_axis_tlast             <= 1'b0;
            m_axis_tuser             <= 1'b0;
        end else begin
            ctrl_start_d <= ctrl_start;

            if (ctrl_clear_counters) begin
                clear_counters();
            end

            case (state)
                ST_IDLE,
                ST_DONE: begin
                    status_busy      <= 1'b0;
                    status_streaming <= 1'b0;
                    m_axis_tvalid    <= 1'b0;
                    m_axis_tlast     <= 1'b0;
                    m_axis_tuser     <= 1'b0;

                    if (ctrl_abort) begin
                        status_done       <= 1'b0;
                        status_error      <= 1'b1;
                        status_error_code <= ERR_ABORT;
                        state             <= ST_DONE;
                    end else if (ctrl_clear_status) begin
                        clear_status_flags();
                        frame_len_reg  <= 16'd0;
                        frame_count_reg <= 32'd0;
                        state          <= ST_IDLE;
                    end else if (start_req) begin
                        clear_status_flags();
                        status_frame_id <= ctrl_frame_id;

                        if (frame_len_invalid) begin
                            status_error      <= 1'b1;
                            status_error_code <= ERR_INVALID_FRAME_LEN;
                            frame_len_reg     <= 16'd0;
                            frame_count_reg    <= 32'd0;
                            state             <= ST_DONE;
                        end else if ((ctrl_frame_count != 32'd0) &&
                                     ctrl_continuous_mode &&
                                     !ctrl_stream_enable) begin
                            status_error      <= 1'b1;
                            status_error_code <= ERR_INVALID_FRAME_COUNT;
                            frame_len_reg     <= 16'd0;
                            frame_count_reg    <= 32'd0;
                            state             <= ST_DONE;
                        end else if (finite_burst_req) begin
                            frame_len_reg             <= ctrl_frame_len;
                            frame_count_reg            <= ctrl_frame_count;
                            status_busy                <= 1'b1;
                            status_streaming           <= 1'b1;
                            status_burst_active        <= 1'b1;
                            status_burst_done          <= 1'b0;
                            status_burst_packet_count  <= 32'd0;
                            status_burst_remaining     <= ctrl_frame_count;
                            m_axis_tdata               <= adc_sample;
                            m_axis_tvalid              <= 1'b1;
                            m_axis_tlast               <= (ctrl_frame_len == 16'd1);
                            m_axis_tuser               <= adc_overflow;
                            status_overflow_seen       <= adc_overflow;
                            if (adc_overflow) begin
                                status_error      <= 1'b1;
                                status_error_code <= ERR_ADC_OVERFLOW;
                            end
                            state <= ST_STREAM;
                        end else if (infinite_stream_req) begin
                            frame_len_reg        <= ctrl_frame_len;
                            frame_count_reg       <= 32'd0;
                            status_busy          <= 1'b1;
                            status_streaming     <= 1'b1;
                            m_axis_tdata         <= adc_sample;
                            m_axis_tvalid        <= 1'b1;
                            m_axis_tlast         <= (ctrl_frame_len == 16'd1);
                            m_axis_tuser         <= adc_overflow;
                            status_overflow_seen <= adc_overflow;
                            if (adc_overflow) begin
                                status_error      <= 1'b1;
                                status_error_code <= ERR_ADC_OVERFLOW;
                            end
                            state <= ST_STREAM;
                        end else begin
                            frame_len_reg        <= ctrl_frame_len;
                            frame_count_reg       <= 32'd0;
                            status_busy          <= 1'b1;
                            status_streaming     <= 1'b0;
                            m_axis_tdata         <= adc_sample;
                            m_axis_tvalid        <= 1'b1;
                            m_axis_tlast         <= (ctrl_frame_len == 16'd1);
                            m_axis_tuser         <= adc_overflow;
                            status_overflow_seen <= adc_overflow;
                            if (adc_overflow) begin
                                status_error      <= 1'b1;
                                status_error_code <= ERR_ADC_OVERFLOW;
                            end
                            state <= ST_CAPTURE;
                        end
                    end else if (infinite_stream_req) begin
                        clear_status_flags();
                        status_frame_id <= ctrl_frame_id;

                        if (frame_len_invalid) begin
                            status_error      <= 1'b1;
                            status_error_code <= ERR_INVALID_FRAME_LEN;
                            frame_len_reg     <= 16'd0;
                            frame_count_reg    <= 32'd0;
                            state             <= ST_DONE;
                        end else begin
                            frame_len_reg        <= ctrl_frame_len;
                            frame_count_reg       <= 32'd0;
                            status_busy          <= 1'b1;
                            status_streaming     <= 1'b1;
                            m_axis_tdata         <= adc_sample;
                            m_axis_tvalid        <= 1'b1;
                            m_axis_tlast         <= (ctrl_frame_len == 16'd1);
                            m_axis_tuser         <= adc_overflow;
                            status_overflow_seen <= adc_overflow;
                            if (adc_overflow) begin
                                status_error      <= 1'b1;
                                status_error_code <= ERR_ADC_OVERFLOW;
                            end
                            state <= ST_STREAM;
                        end
                    end
                end

                ST_CAPTURE: begin
                    status_busy      <= 1'b1;
                    status_streaming <= 1'b0;

                    if (ctrl_abort) begin
                        status_busy       <= 1'b0;
                        status_done       <= 1'b0;
                        status_error      <= 1'b1;
                        status_error_code <= ERR_ABORT;
                        m_axis_tvalid     <= 1'b0;
                        m_axis_tlast      <= 1'b0;
                        state             <= ST_DONE;
                    end else if (ctrl_clear_status) begin
                        clear_status_flags();
                    end else if (start_req) begin
                        status_busy       <= 1'b0;
                        status_done       <= 1'b0;
                        status_error      <= 1'b1;
                        status_error_code <= ERR_START_WHILE_BUSY;
                        m_axis_tvalid     <= 1'b0;
                        m_axis_tlast      <= 1'b0;
                        state             <= ST_DONE;
                    end else begin
                        if (adc_overflow) begin
                            status_overflow_seen <= 1'b1;
                            status_error         <= 1'b1;
                            if (status_error_code == ERR_NONE) begin
                                status_error_code <= ERR_ADC_OVERFLOW;
                            end
                        end

                        if (m_axis_tvalid && !m_axis_tready) begin
                            status_backpressure_seen  <= 1'b1;
                            status_error              <= 1'b1;
                            status_backpressure_count <= status_backpressure_count + 32'd1;
                            if (status_error_code == ERR_NONE) begin
                                status_error_code <= ERR_BACKPRESSURE;
                            end
                        end

                        if (axis_accept) begin
                            increment_total_sample_count();
                            status_sample_count <= status_sample_count + 16'd1;

                            if (m_axis_tuser) begin
                                status_overflow_count <= status_overflow_count + 32'd1;
                            end

                            if (axis_last_beat) begin
                                status_busy        <= 1'b0;
                                status_done        <= 1'b1;
                                status_tlast_seen  <= 1'b1;
                                status_packet_count <= status_packet_count + 32'd1;
                                m_axis_tvalid      <= 1'b0;
                                m_axis_tlast       <= 1'b0;
                                state              <= ST_DONE;
                            end else begin
                                m_axis_tdata <= adc_sample;
                                m_axis_tuser <= adc_overflow;
                                m_axis_tlast <=
                                    ((status_sample_count + 16'd1) ==
                                     (frame_len_reg - 16'd1));
                            end
                        end
                    end
                end

                ST_STREAM: begin
                    status_busy      <= 1'b1;
                    status_streaming <= 1'b1;

                    if (ctrl_abort || !continuous_req) begin
                        status_busy         <= 1'b0;
                        status_streaming    <= 1'b0;
                        status_done         <= 1'b1;
                        status_burst_active <= 1'b0;
                        frame_count_reg     <= 32'd0;
                        m_axis_tvalid       <= 1'b0;
                        m_axis_tlast        <= 1'b0;
                        if (ctrl_abort) begin
                            status_done       <= 1'b0;
                            status_burst_done <= 1'b0;
                            status_error      <= 1'b1;
                            status_error_code <= ERR_ABORT;
                        end
                        state <= ST_DONE;
                    end else if (ctrl_clear_status) begin
                        status_done              <= 1'b0;
                        status_error             <= 1'b0;
                        status_overflow_seen     <= 1'b0;
                        status_backpressure_seen <= 1'b0;
                        status_tlast_seen        <= 1'b0;
                        status_burst_done        <= 1'b0;
                        status_error_code        <= ERR_NONE;
                    end else if (start_req) begin
                        status_busy         <= 1'b0;
                        status_streaming    <= 1'b0;
                        status_burst_active <= 1'b0;
                        status_burst_done   <= 1'b0;
                        status_done         <= 1'b0;
                        status_error        <= 1'b1;
                        status_error_code   <= ERR_START_WHILE_BUSY;
                        frame_count_reg     <= 32'd0;
                        m_axis_tvalid       <= 1'b0;
                        m_axis_tlast        <= 1'b0;
                        state               <= ST_DONE;
                    end else begin
                        if (adc_overflow) begin
                            status_overflow_seen <= 1'b1;
                            status_error         <= 1'b1;
                            if (status_error_code == ERR_NONE) begin
                                status_error_code <= ERR_ADC_OVERFLOW;
                            end
                        end

                        if (m_axis_tvalid && !m_axis_tready) begin
                            status_backpressure_seen  <= 1'b1;
                            status_error              <= 1'b1;
                            status_backpressure_count <= status_backpressure_count + 32'd1;
                            if (status_error_code == ERR_NONE) begin
                                status_error_code <= ERR_BACKPRESSURE;
                            end
                        end

                        if (axis_accept) begin
                            increment_total_sample_count();

                            if (m_axis_tuser) begin
                                status_overflow_count <= status_overflow_count + 32'd1;
                            end

                            if (axis_last_beat) begin
                                status_tlast_seen    <= 1'b1;
                                status_packet_count  <= status_packet_count + 32'd1;
                                status_sample_count  <= 16'd0;

                                if (frame_count_reg != 32'd0) begin
                                    status_burst_packet_count <=
                                        status_burst_packet_count + 32'd1;
                                    status_burst_remaining <=
                                        status_burst_remaining - 32'd1;

                                    if (status_burst_remaining == 32'd1) begin
                                        status_busy         <= 1'b0;
                                        status_streaming    <= 1'b0;
                                        status_done         <= 1'b1;
                                        status_burst_active <= 1'b0;
                                        status_burst_done   <= 1'b1;
                                        frame_count_reg     <= 32'd0;
                                        m_axis_tvalid       <= 1'b0;
                                        m_axis_tlast        <= 1'b0;
                                        state               <= ST_DONE;
                                    end else begin
                                        m_axis_tdata <= adc_sample;
                                        m_axis_tuser <= adc_overflow;
                                        m_axis_tlast <= (frame_len_reg == 16'd1);
                                    end
                                end else begin
                                    m_axis_tdata <= adc_sample;
                                    m_axis_tuser <= adc_overflow;
                                    m_axis_tlast <= (frame_len_reg == 16'd1);
                                end
                            end else begin
                                status_sample_count <= status_sample_count + 16'd1;
                                m_axis_tlast <=
                                    ((status_sample_count + 16'd1) ==
                                     (frame_len_reg - 16'd1));
                                m_axis_tdata <= adc_sample;
                                m_axis_tuser <= adc_overflow;
                            end
                        end
                    end
                end

                default: begin
                    state            <= ST_IDLE;
                    status_busy      <= 1'b0;
                    status_streaming <= 1'b0;
                    status_burst_active <= 1'b0;
                    m_axis_tvalid    <= 1'b0;
                    m_axis_tlast     <= 1'b0;
                end
            endcase
        end
    end

endmodule
