module dma_tx_engine #(
    parameter BLOCK_SIZE_WIDTH = 6
)(
    input  wire                         clk_i,
    input  wire                         rst_i,
    input  wire                         start_i,
    input  wire                         soft_reset_i,
    input  wire                         clear_done_i,
    input  wire                         clear_error_i,
    input  wire [31:0]                  src_addr_i,
    input  wire [31:0]                  dst_addr_i,
    input  wire [31:0]                  len_bytes_i,
    input  wire [1:0]                   direction_i,
    input  wire                         compress_only_i,
    input  wire                         whole_file_i,
    input  wire [BLOCK_SIZE_WIDTH-1:0]  block_size_i,

    output wire                         dmem_en_o,
    output wire [3:0]                   dmem_we_o,
    output wire [31:0]                  dmem_addr_o,
    output wire [31:0]                  dmem_wdata_o,
    input  wire [31:0]                  dmem_rdata_i,

    output wire                         tx_psel_o,
    output wire                         tx_penable_o,
    output wire                         tx_pwrite_o,
    output wire [31:0]                  tx_paddr_o,
    output wire [31:0]                  tx_pwdata_o,
    input  wire [31:0]                  tx_prdata_i,
    input  wire                         tx_pready_i,
    input  wire                         tx_pslverr_i,

    output wire                         dma_busy_o,
    output reg                          dma_done_o,
    output reg                          dma_error_o,
    output reg  [31:0]                  bytes_done_o,
    output reg  [7:0]                   last_error_code_o,
    output wire [3:0]                   engine_state_o
);

    localparam [4:0] STATE_IDLE                 = 5'd0;
    localparam [4:0] STATE_CAPTURE_CFG          = 5'd1;
    localparam [4:0] STATE_RESET_TX             = 5'd2;
    localparam [4:0] STATE_PREP_BLOCK           = 5'd3;
    localparam [4:0] STATE_LOAD_WORD_CHECK      = 5'd4;
    localparam [4:0] STATE_DMEM_READ_ISSUE      = 5'd5;
    localparam [4:0] STATE_DMEM_READ_WAIT       = 5'd6;
    localparam [4:0] STATE_DMEM_READ_CAPTURE    = 5'd7;
    localparam [4:0] STATE_CHECK_CAN_START      = 5'd8;
    localparam [4:0] STATE_CHECK_CAN_START_EVAL = 5'd9;
    localparam [4:0] STATE_WAIT_BLOCK_DONE      = 5'd10;
    localparam [4:0] STATE_WAIT_BLOCK_DONE_EVAL = 5'd11;
    localparam [4:0] STATE_DRAIN_STATUS         = 5'd12;
    localparam [4:0] STATE_DRAIN_STATUS_EVAL    = 5'd13;
    localparam [4:0] STATE_DRAIN_META           = 5'd14;
    localparam [4:0] STATE_DRAIN_META_EVAL      = 5'd15;
    localparam [4:0] STATE_DRAIN_DATA           = 5'd16;
    localparam [4:0] STATE_DRAIN_DATA_EVAL      = 5'd17;
    localparam [4:0] STATE_DMEM_WRITE_ISSUE     = 5'd18;
    localparam [4:0] STATE_FINAL_IDLE_CHECK     = 5'd19;
    localparam [4:0] STATE_FINAL_IDLE_EVAL      = 5'd20;
    localparam [4:0] STATE_APB_SETUP            = 5'd21;
    localparam [4:0] STATE_APB_ACCESS           = 5'd22;
    localparam [4:0] STATE_COMPLETE             = 5'd23;
    localparam [4:0] STATE_ERROR                = 5'd24;
    localparam [4:0] STATE_GLOBAL_CLEAR         = 5'd25;
    localparam [4:0] STATE_SET_COUNT_POLICY     = 5'd26;
    localparam [4:0] STATE_START_GLOBAL_BUILD   = 5'd27;
    localparam [4:0] STATE_WAIT_GLOBAL_BUILD    = 5'd28;
    localparam [4:0] STATE_WAIT_GLOBAL_BUILD_EVAL = 5'd29;
    localparam [4:0] STATE_SET_EMIT_POLICY      = 5'd30;

    localparam [1:0] DIR_TX                     = 2'b01;

    localparam [31:0] TX_ADDR_START_BLOCK       = 32'h0000_0000;
    localparam [31:0] TX_ADDR_BLOCK_SIZE        = 32'h0000_0004;
    localparam [31:0] TX_ADDR_WORD_IN           = 32'h0000_0008;
    localparam [31:0] TX_ADDR_STATUS            = 32'h0000_000C;
    localparam [31:0] TX_ADDR_CONTROL           = 32'h0000_0010;
    localparam [31:0] TX_ADDR_POLICY            = 32'h0000_0018;
    localparam [31:0] TX_ADDR_AES_OUT_DATA      = 32'h0000_0020;
    localparam [31:0] TX_ADDR_AES_OUT_META      = 32'h0000_0024;
    localparam [31:0] TX_ADDR_AES_OUT_STATUS    = 32'h0000_0028;

    localparam [7:0] ERR_NONE                   = 8'h00;
    localparam [7:0] ERR_INVALID_START          = 8'h01;
    localparam [7:0] ERR_BAD_ALIGNMENT          = 8'h02;
    localparam [7:0] ERR_TX_APB                 = 8'h03;
    localparam [7:0] ERR_TX_STATUS              = 8'h04;
    localparam [7:0] ERR_TX_AES_OUT             = 8'h05;
    localparam [7:0] ERR_TX_GLOBAL_BUILD        = 8'h06;

    localparam [6:0] FINAL_EMPTY_POLLS_REQUIRED = 7'd64;

    reg [4:0]  state_r;
    reg [4:0]  apb_resume_state_r;
    reg        apb_write_r;
    reg [31:0] apb_addr_r;
    reg [31:0] apb_wdata_r;
    reg [31:0] apb_rdata_r;

    reg [31:0] src_ptr_r;
    reg [31:0] dst_ptr_r;
    reg [31:0] src_base_r;
    reg [31:0] dst_base_r;
    reg [31:0] len_bytes_r;
    reg [31:0] bytes_remaining_r;
    reg [BLOCK_SIZE_WIDTH-1:0] cfg_block_size_r;
    reg [31:0] current_block_bytes_r;
    reg [3:0]  words_remaining_r;
    reg        current_block_continue_r;
    reg        final_drain_r;
    reg        drain_during_block_r;
    reg        whole_file_r;
    reg        count_phase_r;
    reg        compress_only_r;
    reg [6:0]  final_empty_polls_r;

    reg [31:0] output_word_r;
    reg [31:0] tx_meta_r;

    wire start_tx_w;
    wire config_invalid_w;
    wire [31:0] next_block_bytes_w;
    wire [5:0]  next_block_words_full_w;
    wire [3:0]  next_block_words_w;
    wire unused_control_w;

    assign start_tx_w = start_i && (direction_i == DIR_TX);
    assign config_invalid_w = (direction_i != DIR_TX) ||
                              (len_bytes_i == 32'b0) ||
                              (block_size_i == {BLOCK_SIZE_WIDTH{1'b0}}) ||
                              (block_size_i > 6'd32) ||
                              (src_addr_i[1:0] != 2'b00) ||
                              (dst_addr_i[1:0] != 2'b00);
    assign next_block_bytes_w = (bytes_remaining_r > cfg_block_size_r) ?
                                {{(32-BLOCK_SIZE_WIDTH){1'b0}}, cfg_block_size_r} :
                                bytes_remaining_r;
    assign next_block_words_full_w = (next_block_bytes_w[5:0] + 6'd3) >> 2;
    assign next_block_words_w = next_block_words_full_w[3:0];
    assign unused_control_w = clear_done_i ^ clear_error_i ^ (^tx_meta_r) ^
                              (^next_block_words_full_w[5:4]);

    assign dmem_en_o    = (state_r == STATE_DMEM_READ_ISSUE) ||
                          (state_r == STATE_DMEM_WRITE_ISSUE);
    assign dmem_we_o    = (state_r == STATE_DMEM_WRITE_ISSUE) ? 4'b1111 : 4'b0000;
    assign dmem_addr_o  = (state_r == STATE_DMEM_WRITE_ISSUE) ? dst_ptr_r : src_ptr_r;
    assign dmem_wdata_o = output_word_r ^ {32{1'b0 & unused_control_w}};

    assign tx_psel_o    = (state_r == STATE_APB_SETUP) || (state_r == STATE_APB_ACCESS);
    assign tx_penable_o = (state_r == STATE_APB_ACCESS);
    assign tx_pwrite_o  = apb_write_r;
    assign tx_paddr_o   = apb_addr_r;
    assign tx_pwdata_o  = apb_wdata_r;

    assign dma_busy_o     = (state_r != STATE_IDLE);
    assign engine_state_o = state_r[3:0];

    always @(posedge clk_i) begin
        if (rst_i) begin
            state_r                  <= STATE_IDLE;
            apb_resume_state_r       <= STATE_IDLE;
            apb_write_r              <= 1'b0;
            apb_addr_r               <= 32'b0;
            apb_wdata_r              <= 32'b0;
            apb_rdata_r              <= 32'b0;
            src_ptr_r                <= 32'b0;
            dst_ptr_r                <= 32'b0;
            src_base_r               <= 32'b0;
            dst_base_r               <= 32'b0;
            len_bytes_r              <= 32'b0;
            bytes_remaining_r        <= 32'b0;
            cfg_block_size_r         <= {BLOCK_SIZE_WIDTH{1'b0}};
            current_block_bytes_r    <= 32'b0;
            words_remaining_r        <= 4'b0;
            current_block_continue_r <= 1'b0;
            final_drain_r            <= 1'b0;
            drain_during_block_r     <= 1'b0;
            whole_file_r             <= 1'b0;
            count_phase_r            <= 1'b0;
            compress_only_r          <= 1'b0;
            final_empty_polls_r      <= 7'b0;
            output_word_r            <= 32'b0;
            tx_meta_r                <= 32'b0;
            dma_done_o               <= 1'b0;
            dma_error_o              <= 1'b0;
            bytes_done_o             <= 32'b0;
            last_error_code_o        <= ERR_NONE;
        end else begin
            dma_done_o  <= 1'b0;
            dma_error_o <= 1'b0;

            if (clear_error_i)
                last_error_code_o <= ERR_NONE;

            if (soft_reset_i) begin
                state_r                  <= STATE_IDLE;
                apb_resume_state_r       <= STATE_IDLE;
                apb_write_r              <= 1'b0;
                apb_addr_r               <= 32'b0;
                apb_wdata_r              <= 32'b0;
                apb_rdata_r              <= 32'b0;
                src_ptr_r                <= 32'b0;
                dst_ptr_r                <= 32'b0;
                src_base_r               <= 32'b0;
                dst_base_r               <= 32'b0;
                len_bytes_r              <= 32'b0;
                bytes_remaining_r        <= 32'b0;
                cfg_block_size_r         <= {BLOCK_SIZE_WIDTH{1'b0}};
                current_block_bytes_r    <= 32'b0;
                words_remaining_r        <= 4'b0;
                current_block_continue_r <= 1'b0;
                final_drain_r            <= 1'b0;
                drain_during_block_r     <= 1'b0;
                whole_file_r             <= 1'b0;
                count_phase_r            <= 1'b0;
                compress_only_r          <= 1'b0;
                final_empty_polls_r      <= 7'b0;
                output_word_r            <= 32'b0;
                tx_meta_r                <= 32'b0;
                bytes_done_o             <= 32'b0;
                last_error_code_o        <= ERR_NONE;
            end else begin
                case (state_r)
                    STATE_IDLE: begin
                        if (start_tx_w) begin
                            if (config_invalid_w) begin
                                last_error_code_o <= ERR_BAD_ALIGNMENT;
                                state_r           <= STATE_ERROR;
                            end
                            else begin
                                state_r <= STATE_CAPTURE_CFG;
                            end
                        end
                    end

	                    STATE_CAPTURE_CFG: begin
	                        src_ptr_r                <= src_addr_i;
	                        dst_ptr_r                <= dst_addr_i;
	                        src_base_r               <= src_addr_i;
	                        dst_base_r               <= dst_addr_i;
	                        len_bytes_r              <= len_bytes_i;
	                        bytes_remaining_r        <= len_bytes_i;
	                        cfg_block_size_r         <= block_size_i;
	                        current_block_bytes_r    <= 32'b0;
	                        words_remaining_r        <= 4'b0;
	                        current_block_continue_r <= 1'b0;
	                        final_drain_r            <= 1'b0;
	                        drain_during_block_r     <= 1'b0;
	                        whole_file_r             <= whole_file_i;
	                        count_phase_r            <= whole_file_i;
	                        compress_only_r          <= compress_only_i;
	                        final_empty_polls_r      <= 7'b0;
	                        bytes_done_o             <= 32'b0;

                        apb_write_r        <= 1'b1;
                        apb_addr_r         <= TX_ADDR_CONTROL;
                        apb_wdata_r        <= 32'h0000_0001;
                        apb_resume_state_r <= STATE_RESET_TX;
                        state_r            <= STATE_APB_SETUP;
                    end

	                    STATE_RESET_TX: begin
	                        apb_write_r        <= 1'b1;
	                        if (whole_file_r) begin
	                            apb_addr_r         <= TX_ADDR_CONTROL;
	                            apb_wdata_r        <= 32'h0000_0008;
	                            apb_resume_state_r <= STATE_GLOBAL_CLEAR;
	                        end
	                        else begin
	                            apb_addr_r         <= TX_ADDR_POLICY;
	                            apb_wdata_r        <= {31'b0, compress_only_r};
	                            apb_resume_state_r <= STATE_PREP_BLOCK;
	                        end
	                        state_r            <= STATE_APB_SETUP;
	                    end

	                    STATE_GLOBAL_CLEAR: begin
	                        apb_write_r        <= 1'b1;
	                        apb_addr_r         <= TX_ADDR_POLICY;
	                        apb_wdata_r        <= 32'h0000_0006;
	                        apb_resume_state_r <= STATE_SET_COUNT_POLICY;
	                        state_r            <= STATE_APB_SETUP;
	                    end

	                    STATE_SET_COUNT_POLICY: begin
	                        state_r <= STATE_PREP_BLOCK;
	                    end

                    STATE_PREP_BLOCK: begin
                        current_block_bytes_r    <= next_block_bytes_w;
                        words_remaining_r        <= next_block_words_w[3:0];
                        current_block_continue_r <= (bytes_remaining_r > next_block_bytes_w);
                        final_empty_polls_r      <= 7'b0;
                        drain_during_block_r     <= 1'b0;

                        apb_write_r        <= 1'b1;
                        apb_addr_r         <= TX_ADDR_BLOCK_SIZE;
                        apb_wdata_r        <= next_block_bytes_w;
                        apb_resume_state_r <= STATE_LOAD_WORD_CHECK;
                        state_r            <= STATE_APB_SETUP;
                    end

                    STATE_LOAD_WORD_CHECK: begin
                        if (words_remaining_r == 4'b0) begin
                            state_r <= STATE_CHECK_CAN_START;
                        end
                        else begin
                            state_r <= STATE_DMEM_READ_ISSUE;
                        end
                    end

                    STATE_DMEM_READ_ISSUE: begin
                        state_r <= STATE_DMEM_READ_WAIT;
                    end

                    STATE_DMEM_READ_WAIT: begin
                        state_r <= STATE_DMEM_READ_CAPTURE;
                    end

                    STATE_DMEM_READ_CAPTURE: begin
                        src_ptr_r          <= src_ptr_r + 32'd4;
                        words_remaining_r  <= words_remaining_r - 1'b1;
                        apb_write_r        <= 1'b1;
                        apb_addr_r         <= TX_ADDR_WORD_IN;
                        apb_wdata_r        <= dmem_rdata_i;
                        apb_resume_state_r <= STATE_LOAD_WORD_CHECK;
                        state_r            <= STATE_APB_SETUP;
                    end

                    STATE_CHECK_CAN_START: begin
                        apb_write_r        <= 1'b0;
                        apb_addr_r         <= TX_ADDR_STATUS;
                        apb_wdata_r        <= 32'b0;
                        apb_resume_state_r <= STATE_CHECK_CAN_START_EVAL;
                        state_r            <= STATE_APB_SETUP;
                    end

                    STATE_CHECK_CAN_START_EVAL: begin
                        if (apb_rdata_r[5]) begin
                            last_error_code_o <= ERR_TX_STATUS;
                            state_r           <= STATE_ERROR;
                        end
                        else if (apb_rdata_r[7]) begin
                            apb_write_r        <= 1'b1;
                            apb_addr_r         <= TX_ADDR_START_BLOCK;
                            apb_wdata_r        <= current_block_continue_r ? 32'h0000_0003
                                                                           : 32'h0000_0001;
                            apb_resume_state_r <= STATE_WAIT_BLOCK_DONE;
                            state_r            <= STATE_APB_SETUP;
                        end
                        else begin
                            state_r <= STATE_CHECK_CAN_START;
                        end
                    end

                    STATE_WAIT_BLOCK_DONE: begin
                        apb_write_r        <= 1'b0;
                        apb_addr_r         <= TX_ADDR_STATUS;
                        apb_wdata_r        <= 32'b0;
                        apb_resume_state_r <= STATE_WAIT_BLOCK_DONE_EVAL;
                        state_r            <= STATE_APB_SETUP;
                    end

	                    STATE_WAIT_BLOCK_DONE_EVAL: begin
	                        if (apb_rdata_r[5]) begin
	                            last_error_code_o <= ERR_TX_STATUS;
	                            state_r           <= STATE_ERROR;
	                        end
	                        else if (apb_rdata_r[4]) begin
	                            bytes_remaining_r <= bytes_remaining_r - current_block_bytes_r;
	                            if (count_phase_r) begin
	                                if (current_block_continue_r) begin
	                                    state_r <= STATE_PREP_BLOCK;
	                                end
	                                else begin
	                                    state_r <= STATE_START_GLOBAL_BUILD;
	                                end
	                            end
	                            else begin
	                                final_drain_r       <= !current_block_continue_r;
	                                drain_during_block_r<= 1'b0;
	                                final_empty_polls_r <= 7'b0;
	                                state_r             <= STATE_DRAIN_STATUS;
	                            end
	                        end
	                        else begin
	                            if (!count_phase_r) begin
	                                drain_during_block_r <= 1'b1;
	                                state_r              <= STATE_DRAIN_STATUS;
	                            end
	                            else begin
	                                state_r <= STATE_WAIT_BLOCK_DONE;
	                            end
	                        end
	                    end

	                    STATE_START_GLOBAL_BUILD: begin
	                        apb_write_r        <= 1'b1;
	                        apb_addr_r         <= TX_ADDR_CONTROL;
	                        apb_wdata_r        <= 32'h0000_0010;
	                        apb_resume_state_r <= STATE_WAIT_GLOBAL_BUILD;
	                        state_r            <= STATE_APB_SETUP;
	                    end

	                    STATE_WAIT_GLOBAL_BUILD: begin
	                        apb_write_r        <= 1'b0;
	                        apb_addr_r         <= TX_ADDR_STATUS;
	                        apb_wdata_r        <= 32'b0;
	                        apb_resume_state_r <= STATE_WAIT_GLOBAL_BUILD_EVAL;
	                        state_r            <= STATE_APB_SETUP;
	                    end

	                    STATE_WAIT_GLOBAL_BUILD_EVAL: begin
	                        if (apb_rdata_r[11]) begin
	                            last_error_code_o <= ERR_TX_GLOBAL_BUILD;
	                            state_r           <= STATE_ERROR;
	                        end
	                        else if (apb_rdata_r[8] || apb_rdata_r[10]) begin
	                            apb_write_r        <= 1'b1;
	                            apb_addr_r         <= TX_ADDR_POLICY;
	                            apb_wdata_r        <= {29'b0, 1'b0, 1'b1, compress_only_r};
	                            apb_resume_state_r <= STATE_SET_EMIT_POLICY;
	                            state_r            <= STATE_APB_SETUP;
	                        end
	                        else begin
	                            state_r <= STATE_WAIT_GLOBAL_BUILD;
	                        end
	                    end

	                    STATE_SET_EMIT_POLICY: begin
	                        src_ptr_r                <= src_base_r;
	                        dst_ptr_r                <= dst_base_r;
	                        bytes_remaining_r        <= len_bytes_r;
	                        current_block_bytes_r    <= 32'b0;
	                        words_remaining_r        <= 4'b0;
	                        current_block_continue_r <= 1'b0;
	                        final_drain_r            <= 1'b0;
	                        drain_during_block_r     <= 1'b0;
	                        count_phase_r            <= 1'b0;
	                        final_empty_polls_r      <= 7'b0;
	                        bytes_done_o             <= 32'b0;
	                        state_r                  <= STATE_PREP_BLOCK;
	                    end

                    STATE_DRAIN_STATUS: begin
                        apb_write_r        <= 1'b0;
                        apb_addr_r         <= TX_ADDR_AES_OUT_STATUS;
                        apb_wdata_r        <= 32'b0;
                        apb_resume_state_r <= STATE_DRAIN_STATUS_EVAL;
                        state_r            <= STATE_APB_SETUP;
                    end

                    STATE_DRAIN_STATUS_EVAL: begin
                        if (apb_rdata_r[9]) begin
                            last_error_code_o <= ERR_TX_AES_OUT;
                            state_r           <= STATE_ERROR;
                        end
                        else if (apb_rdata_r[0]) begin
                            final_empty_polls_r <= 7'b0;
                            state_r             <= STATE_DRAIN_META;
                        end
                        else if (drain_during_block_r) begin
                            drain_during_block_r <= 1'b0;
                            state_r              <= STATE_WAIT_BLOCK_DONE;
                        end
                        else if (final_drain_r) begin
                            state_r <= STATE_FINAL_IDLE_CHECK;
                        end
                        else begin
                            state_r <= STATE_PREP_BLOCK;
                        end
                    end

                    STATE_DRAIN_META: begin
                        apb_write_r        <= 1'b0;
                        apb_addr_r         <= TX_ADDR_AES_OUT_META;
                        apb_wdata_r        <= 32'b0;
                        apb_resume_state_r <= STATE_DRAIN_META_EVAL;
                        state_r            <= STATE_APB_SETUP;
                    end

                    STATE_DRAIN_META_EVAL: begin
                        tx_meta_r <= apb_rdata_r;
                        state_r   <= STATE_DRAIN_DATA;
                    end

                    STATE_DRAIN_DATA: begin
                        apb_write_r        <= 1'b0;
                        apb_addr_r         <= TX_ADDR_AES_OUT_DATA;
                        apb_wdata_r        <= 32'b0;
                        apb_resume_state_r <= STATE_DRAIN_DATA_EVAL;
                        state_r            <= STATE_APB_SETUP;
                    end

                    STATE_DRAIN_DATA_EVAL: begin
                        output_word_r <= apb_rdata_r;
                        state_r       <= STATE_DMEM_WRITE_ISSUE;
                    end

                    STATE_DMEM_WRITE_ISSUE: begin
                        dst_ptr_r    <= dst_ptr_r + 32'd4;
                        bytes_done_o <= bytes_done_o + 32'd4;
                        state_r      <= STATE_DRAIN_STATUS;
                    end

                    STATE_FINAL_IDLE_CHECK: begin
                        apb_write_r        <= 1'b0;
                        apb_addr_r         <= TX_ADDR_STATUS;
                        apb_wdata_r        <= 32'b0;
                        apb_resume_state_r <= STATE_FINAL_IDLE_EVAL;
                        state_r            <= STATE_APB_SETUP;
                    end

                    STATE_FINAL_IDLE_EVAL: begin
                        if (apb_rdata_r[5]) begin
                            last_error_code_o <= ERR_TX_STATUS;
                            state_r           <= STATE_ERROR;
                        end
                        else if (!apb_rdata_r[3]) begin
                            if (final_empty_polls_r == (FINAL_EMPTY_POLLS_REQUIRED - 1'b1)) begin
                                state_r <= STATE_COMPLETE;
                            end
                            else begin
                                final_empty_polls_r <= final_empty_polls_r + 1'b1;
                                state_r             <= STATE_DRAIN_STATUS;
                            end
                        end
                        else begin
                            final_empty_polls_r <= 7'b0;
                            state_r             <= STATE_DRAIN_STATUS;
                        end
                    end

                    STATE_APB_SETUP: begin
                        state_r <= STATE_APB_ACCESS;
                    end

                    STATE_APB_ACCESS: begin
                        if (tx_pready_i) begin
                            apb_rdata_r <= tx_prdata_i;
                            if (tx_pslverr_i) begin
                                last_error_code_o <= ERR_TX_APB;
                                state_r           <= STATE_ERROR;
                            end
                            else begin
                                state_r <= apb_resume_state_r;
                            end
                        end
                    end

                    STATE_COMPLETE: begin
                        dma_done_o <= 1'b1;
                        state_r    <= STATE_IDLE;
                    end

                    STATE_ERROR: begin
                        dma_error_o <= 1'b1;
                        state_r     <= STATE_IDLE;
                    end

                    default: begin
                        last_error_code_o <= ERR_INVALID_START;
                        state_r           <= STATE_ERROR;
                    end
                endcase
            end
        end
    end

endmodule
