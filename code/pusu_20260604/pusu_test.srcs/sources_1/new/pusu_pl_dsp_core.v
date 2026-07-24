`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: pusu_pl_dsp_core
//
// PuSuSA PL DSP bring-up core with RBW mode control.
//
// Purpose:
//   - Accept the continuous 130 MSPS signed 16-bit ADC AXI-Stream.
//   - Mix the fixed 40 MHz IF to complex baseband using a 13-phase NCO LUT.
//     This is exact for Fs = 130 MHz because 40 / 130 = 4 / 13.
//   - Select a per-RBW debug decimation factor and output packed 32-bit IQ:
//       tdata[31:16] = signed I[15:0]
//       tdata[15:0]  = signed Q[15:0]
//
// This core now exposes the mode/status contract needed by PS/PL integration.
// The decimator is still an accumulator decimator for bring-up only.  The final
// trusted RBW path must replace it with verified continuous FIR/polyphase
// decimators, then move RBW FIR / power accumulation into PL.
//////////////////////////////////////////////////////////////////////////////////

module pusu_pl_dsp_core #(
    parameter integer DEFAULT_RBW_MODE = 2,      // 2 = 100K, keeps old /130 behavior.
    parameter integer DEFAULT_FRAME_WORDS = 4096,
    parameter integer MODE_SWITCH_HOLD_CYCLES = 16
)(
    input  wire        aclk,
    input  wire        aresetn,

    // Backward-compatible discrete control. In the final BD these should come
    // from pusu_pl_dsp_axi_regs.
    input  wire        enable,
    input  wire        clear_status,
    input  wire        soft_reset,
    input  wire        mode_update,
    input  wire        abort,
    input  wire        stream_reset,
    input  wire [2:0]  rbw_mode,
    input  wire [1:0]  output_select,
    input  wire [31:0] cfg_frame_words,

    input  wire signed [15:0] s_axis_tdata,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire        s_axis_tlast,
    input  wire        s_axis_tuser,

    output reg  [31:0] m_axis_tdata,
    output reg         m_axis_tvalid,
    input  wire        m_axis_tready,
    output reg         m_axis_tlast,
    output reg  [3:0]  m_axis_tuser,

    output reg  [31:0] dbg_input_sample_count,
    output reg  [31:0] dbg_output_sample_count,
    output reg  [31:0] dbg_output_drop_count,
    output reg  [15:0] dbg_last_i,
    output reg  [15:0] dbg_last_q,
    output reg  [3:0]  dbg_nco_phase,
    output reg  [15:0] dbg_decim_count,

    output wire [31:0] status_word,
    output wire [31:0] sample_rate_hz,
    output wire [31:0] decimation_ratio,
    output wire [31:0] data_format,
    output wire [31:0] version,
    output wire [2:0]  current_rbw_mode,
    output wire [1:0]  current_output_select,
    output wire [31:0] error_code,
    output wire        axis_fifo_aresetn
);

    localparam signed [47:0] ACC_ZERO = 48'sd0;

    localparam [2:0] PL_RBW_MODE_1M   = 3'd0;
    localparam [2:0] PL_RBW_MODE_300K = 3'd1;
    localparam [2:0] PL_RBW_MODE_100K = 3'd2;
    localparam [2:0] PL_RBW_MODE_30K  = 3'd3;
    localparam [2:0] PL_RBW_MODE_10K  = 3'd4;
    localparam [2:0] PL_RBW_MODE_1K   = 3'd5;

    localparam [1:0] OUT_DISABLED      = 2'd0;
    localparam [1:0] OUT_DECIMATED_IQ  = 2'd1;
    localparam [1:0] OUT_POST_RBW_IQ   = 2'd2;
    localparam [1:0] OUT_POINT_POWER   = 2'd3;

    localparam [31:0] DATA_FORMAT_V1_PACKED_IQ16 = 32'h0001_0401;
    localparam [31:0] CORE_VERSION = 32'h2026_0605;
    localparam [31:0] DEFAULT_FRAME_WORDS_U = DEFAULT_FRAME_WORDS;
    localparam [7:0] MODE_SWITCH_HOLD_CYCLES_U = MODE_SWITCH_HOLD_CYCLES;

    reg [2:0] active_rbw_mode;
    reg [1:0] active_output_select;
    reg [31:0] active_frame_words;

    reg [3:0] nco_phase;
    reg [15:0] decim_count;
    reg [31:0] packet_count;
    reg signed [47:0] acc_i;
    reg signed [47:0] acc_q;

    reg configured;
    reg drop_seen;
    reg overflow_seen;
    reg [31:0] error_code_reg;
    reg [7:0] mode_switch_countdown;
    reg stream_reset_meta;
    reg stream_reset_sync;

    wire [15:0] active_decim_factor = mode_decim_factor(active_rbw_mode);
    wire [5:0] active_output_shift = mode_output_shift(active_rbw_mode);
    wire mode_switch_busy = (mode_switch_countdown != 8'd0);
    wire stream_reset_active = stream_reset_sync;
    wire active_output_valid = (active_output_select == OUT_DECIMATED_IQ);
    wire output_path_enabled = enable && configured && !mode_switch_busy &&
                               !stream_reset_active && active_output_valid;
    wire about_to_emit = (decim_count == (active_decim_factor - 16'd1));

    assign s_axis_tready = output_path_enabled &&
                           (!about_to_emit || !m_axis_tvalid || m_axis_tready);

    wire input_fire = s_axis_tready && s_axis_tvalid;
    wire output_fire = m_axis_tvalid && m_axis_tready;

    wire signed [15:0] nco_c = nco_cos(nco_phase);
    wire signed [15:0] nco_s = nco_sin(nco_phase);

    wire signed [31:0] mix_i_32 = s_axis_tdata * nco_c;
    wire signed [31:0] mix_q_32 = s_axis_tdata * nco_s;

    wire signed [47:0] mix_i_48 = {{16{mix_i_32[31]}}, mix_i_32};
    wire signed [47:0] mix_q_48 = {{16{mix_q_32[31]}}, mix_q_32};

    wire signed [47:0] next_acc_i = acc_i + mix_i_48;
    wire signed [47:0] next_acc_q = acc_q + mix_q_48;

    // Debug normalization only.  The shift is chosen per decimation factor as
    // Q15 product scaling plus a nearby power-of-two divide.  The PS amplitude
    // path must treat this as debug IQ until the final FIR decimator is added.
    wire signed [47:0] out_i_full = next_acc_i >>> active_output_shift;
    wire signed [47:0] out_q_full = next_acc_q >>> active_output_shift;

    wire signed [15:0] out_i_16 = sat16(out_i_full);
    wire signed [15:0] out_q_16 = sat16(out_q_full);
    wire output_will_saturate =
        (out_i_full > 48'sd32767) || (out_i_full < -48'sd32768) ||
        (out_q_full > 48'sd32767) || (out_q_full < -48'sd32768);

    wire [31:0] frame_words_limit =
        (active_frame_words == 32'd0) ? DEFAULT_FRAME_WORDS_U : active_frame_words;

    assign sample_rate_hz = mode_sample_rate_hz(active_rbw_mode);
    assign decimation_ratio = {16'd0, active_decim_factor};
    assign data_format = DATA_FORMAT_V1_PACKED_IQ16;
    assign version = CORE_VERSION;
    assign current_rbw_mode = active_rbw_mode;
    assign current_output_select = active_output_select;
    assign error_code = error_code_reg;
    assign axis_fifo_aresetn = aresetn && !stream_reset_active;

    assign status_word = {
        24'd0,
        stream_reset_active,                // bit 7 stream_reset_active
        (error_code_reg != 32'd0),         // bit 6 error
        drop_seen,                         // bit 5 drop_seen/backpressure_seen
        overflow_seen,                     // bit 4 overflow
        output_path_enabled,               // bit 3 output_valid_enabled
        mode_switch_busy,                  // bit 2 mode_switch_busy
        (configured && !mode_switch_busy), // bit 1 configured
        (!enable || (!m_axis_tvalid && decim_count == 16'd0)) // bit 0 idle
    };

    always @(posedge aclk) begin
        if (!aresetn) begin
            stream_reset_meta <= 1'b1;
            stream_reset_sync <= 1'b1;
        end else begin
            stream_reset_meta <= stream_reset;
            stream_reset_sync <= stream_reset_meta;
        end
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            active_rbw_mode <= DEFAULT_RBW_MODE[2:0];
            active_output_select <= OUT_DECIMATED_IQ;
            active_frame_words <= DEFAULT_FRAME_WORDS_U;
            configured <= 1'b1;
            mode_switch_countdown <= 8'd0;
            error_code_reg <= 32'd0;
            drop_seen <= 1'b0;
            overflow_seen <= 1'b0;

            nco_phase <= 4'd0;
            decim_count <= 16'd0;
            packet_count <= 32'd0;
            acc_i <= ACC_ZERO;
            acc_q <= ACC_ZERO;
            m_axis_tdata <= 32'd0;
            m_axis_tvalid <= 1'b0;
            m_axis_tlast <= 1'b0;
            m_axis_tuser <= 4'd0;
            dbg_input_sample_count <= 32'd0;
            dbg_output_sample_count <= 32'd0;
            dbg_output_drop_count <= 32'd0;
            dbg_last_i <= 16'd0;
            dbg_last_q <= 16'd0;
            dbg_nco_phase <= 4'd0;
            dbg_decim_count <= 16'd0;
        end else begin
            if (mode_switch_countdown != 8'd0) begin
                mode_switch_countdown <= mode_switch_countdown - 1'b1;
            end

            if (clear_status) begin
                dbg_input_sample_count <= 32'd0;
                dbg_output_sample_count <= 32'd0;
                dbg_output_drop_count <= 32'd0;
                drop_seen <= 1'b0;
                overflow_seen <= 1'b0;
                error_code_reg <= 32'd0;
            end

            if (mode_update) begin
                if (mode_is_valid(rbw_mode)) begin
                    active_rbw_mode <= rbw_mode;
                    active_output_select <= output_select;
                    active_frame_words <= (cfg_frame_words == 32'd0) ?
                                          DEFAULT_FRAME_WORDS_U : cfg_frame_words;
                    configured <= 1'b1;
                    error_code_reg <= 32'd0;
                end else begin
                    configured <= 1'b0;
                    error_code_reg <= 32'd1;
                end

                mode_switch_countdown <= MODE_SWITCH_HOLD_CYCLES_U;
                nco_phase <= 4'd0;
                decim_count <= 16'd0;
                packet_count <= 32'd0;
                acc_i <= ACC_ZERO;
                acc_q <= ACC_ZERO;
                m_axis_tvalid <= 1'b0;
                m_axis_tlast <= 1'b0;
            end else if (soft_reset || abort) begin
                mode_switch_countdown <= MODE_SWITCH_HOLD_CYCLES_U;
                nco_phase <= 4'd0;
                decim_count <= 16'd0;
                packet_count <= 32'd0;
                acc_i <= ACC_ZERO;
                acc_q <= ACC_ZERO;
                m_axis_tvalid <= 1'b0;
                m_axis_tlast <= 1'b0;
            end else begin
                if (stream_reset_active) begin
                    nco_phase <= 4'd0;
                    decim_count <= 16'd0;
                    packet_count <= 32'd0;
                    acc_i <= ACC_ZERO;
                    acc_q <= ACC_ZERO;
                    m_axis_tvalid <= 1'b0;
                    m_axis_tlast <= 1'b0;
                end else if (output_fire) begin
                    m_axis_tvalid <= 1'b0;
                    m_axis_tlast <= 1'b0;
                end

                if (stream_reset_active) begin
                    m_axis_tvalid <= 1'b0;
                    m_axis_tlast <= 1'b0;
                end else if (!output_path_enabled) begin
                    nco_phase <= 4'd0;
                    decim_count <= 16'd0;
                    packet_count <= 32'd0;
                    acc_i <= ACC_ZERO;
                    acc_q <= ACC_ZERO;
                    m_axis_tvalid <= 1'b0;
                    m_axis_tlast <= 1'b0;
                end else if (input_fire) begin
                    dbg_input_sample_count <= dbg_input_sample_count + 1'b1;

                    if (nco_phase == 4'd12) begin
                        nco_phase <= 4'd0;
                    end else begin
                        nco_phase <= nco_phase + 1'b1;
                    end

                    if (about_to_emit) begin
                        decim_count <= 16'd0;
                        acc_i <= ACC_ZERO;
                        acc_q <= ACC_ZERO;

                        m_axis_tdata <= {out_i_16, out_q_16};
                        m_axis_tvalid <= 1'b1;
                        m_axis_tuser <= {1'b1, active_rbw_mode};
                        dbg_output_sample_count <= dbg_output_sample_count + 1'b1;
                        dbg_last_i <= out_i_16;
                        dbg_last_q <= out_q_16;
                        if (output_will_saturate) begin
                            overflow_seen <= 1'b1;
                        end

                        if (frame_words_limit > 0 && packet_count == frame_words_limit - 32'd1) begin
                            m_axis_tlast <= 1'b1;
                            packet_count <= 32'd0;
                        end else begin
                            m_axis_tlast <= 1'b0;
                            packet_count <= packet_count + 1'b1;
                        end
                    end else begin
                        decim_count <= decim_count + 1'b1;
                        acc_i <= next_acc_i;
                        acc_q <= next_acc_q;
                    end
                end else if (output_path_enabled && s_axis_tvalid && !s_axis_tready) begin
                    dbg_output_drop_count <= dbg_output_drop_count + 1'b1;
                    drop_seen <= 1'b1;
                end
            end

            dbg_nco_phase <= nco_phase;
            dbg_decim_count <= decim_count;
        end
    end

    function mode_is_valid;
        input [2:0] mode;
        begin
            mode_is_valid = (mode <= PL_RBW_MODE_1K);
        end
    endfunction

    function [15:0] mode_decim_factor;
        input [2:0] mode;
        begin
            case (mode)
                PL_RBW_MODE_1M:   mode_decim_factor = 16'd13;
                PL_RBW_MODE_300K: mode_decim_factor = 16'd40;
                PL_RBW_MODE_100K: mode_decim_factor = 16'd130;
                PL_RBW_MODE_30K:  mode_decim_factor = 16'd400;
                PL_RBW_MODE_10K:  mode_decim_factor = 16'd1300;
                PL_RBW_MODE_1K:   mode_decim_factor = 16'd1300;
                default:          mode_decim_factor = 16'd130;
            endcase
        end
    endfunction

    function [31:0] mode_sample_rate_hz;
        input [2:0] mode;
        begin
            case (mode)
                PL_RBW_MODE_1M:   mode_sample_rate_hz = 32'd10000000;
                PL_RBW_MODE_300K: mode_sample_rate_hz = 32'd3250000;
                PL_RBW_MODE_100K: mode_sample_rate_hz = 32'd1000000;
                PL_RBW_MODE_30K:  mode_sample_rate_hz = 32'd325000;
                PL_RBW_MODE_10K:  mode_sample_rate_hz = 32'd100000;
                PL_RBW_MODE_1K:   mode_sample_rate_hz = 32'd100000;
                default:          mode_sample_rate_hz = 32'd1000000;
            endcase
        end
    endfunction

    function [5:0] mode_output_shift;
        input [2:0] mode;
        begin
            case (mode)
                PL_RBW_MODE_1M:   mode_output_shift = 6'd19; // Q15 + /16 approx.
                PL_RBW_MODE_300K: mode_output_shift = 6'd20; // Q15 + /32 approx.
                PL_RBW_MODE_100K: mode_output_shift = 6'd22; // Q15 + /128 approx.
                PL_RBW_MODE_30K:  mode_output_shift = 6'd24; // Q15 + /512 approx.
                PL_RBW_MODE_10K:  mode_output_shift = 6'd25; // Q15 + /1024 approx.
                PL_RBW_MODE_1K:   mode_output_shift = 6'd25; // Q15 + /1024 approx.
                default:          mode_output_shift = 6'd22;
            endcase
        end
    endfunction

    function signed [15:0] sat16;
        input signed [47:0] x;
        begin
            if (x > 48'sd32767) begin
                sat16 = 16'sd32767;
            end else if (x < -48'sd32768) begin
                sat16 = -16'sd32768;
            end else begin
                sat16 = x[15:0];
            end
        end
    endfunction

    function signed [15:0] nco_cos;
        input [3:0] phase;
        begin
            case (phase)
                4'd0:  nco_cos =  16'sd32767;
                4'd1:  nco_cos = -16'sd11619;
                4'd2:  nco_cos = -16'sd24526;
                4'd3:  nco_cos =  16'sd29014;
                4'd4:  nco_cos =  16'sd3950;
                4'd5:  nco_cos = -16'sd31815;
                4'd6:  nco_cos =  16'sd18614;
                4'd7:  nco_cos =  16'sd18614;
                4'd8:  nco_cos = -16'sd31815;
                4'd9:  nco_cos =  16'sd3950;
                4'd10: nco_cos =  16'sd29014;
                4'd11: nco_cos = -16'sd24526;
                4'd12: nco_cos = -16'sd11619;
                default: nco_cos = 16'sd32767;
            endcase
        end
    endfunction

    function signed [15:0] nco_sin;
        input [3:0] phase;
        begin
            case (phase)
                4'd0:  nco_sin =  16'sd0;
                4'd1:  nco_sin = -16'sd30638;
                4'd2:  nco_sin =  16'sd21729;
                4'd3:  nco_sin =  16'sd15228;
                4'd4:  nco_sin = -16'sd32528;
                4'd5:  nco_sin =  16'sd7842;
                4'd6:  nco_sin =  16'sd26967;
                4'd7:  nco_sin = -16'sd26967;
                4'd8:  nco_sin = -16'sd7842;
                4'd9:  nco_sin =  16'sd32528;
                4'd10: nco_sin = -16'sd15228;
                4'd11: nco_sin = -16'sd21729;
                4'd12: nco_sin =  16'sd30638;
                default: nco_sin = 16'sd0;
            endcase
        end
    endfunction

endmodule
