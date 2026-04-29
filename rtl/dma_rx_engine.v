module dma_rx_engine (
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire        start_i,
    input  wire        soft_reset_i,
    input  wire        clear_done_i,
    input  wire        clear_error_i,
    input  wire [31:0] src_addr_i,
    input  wire [31:0] dst_addr_i,
    input  wire [31:0] len_bytes_i,
    input  wire [1:0]  direction_i,
    input  wire [5:0]  block_size_i,

    output wire        dmem_en_o,
    output wire [3:0]  dmem_we_o,
    output wire [31:0] dmem_addr_o,
    output wire [31:0] dmem_wdata_o,
    input  wire [31:0] dmem_rdata_i,

    output wire [127:0] rx_ciphertext_word_o,
    output wire         rx_ciphertext_word_valid_o,
    input  wire         rx_ciphertext_word_ready_i,

    output wire        rx_psel_o,
    output wire        rx_penable_o,
    output wire        rx_pwrite_o,
    output wire [31:0] rx_paddr_o,
    output wire [31:0] rx_pwdata_o,
    input  wire [31:0] rx_prdata_i,
    input  wire        rx_pready_i,
    input  wire        rx_pslverr_i,

    output wire        dma_busy_o,
    output reg         dma_done_o,
    output reg         dma_error_o,
    output reg  [31:0] bytes_done_o,
    output reg  [7:0]  last_error_code_o,
    output wire [3:0]  engine_state_o
);

    localparam [4:0] STATE_IDLE             = 5'd0;
    localparam [4:0] STATE_CAPTURE_CFG      = 5'd1;
    localparam [4:0] STATE_RESET_RX         = 5'd2;
    localparam [4:0] STATE_READ_W0_ISSUE    = 5'd3;
    localparam [4:0] STATE_READ_W0_WAIT     = 5'd4;
    localparam [4:0] STATE_READ_W0_CAPTURE  = 5'd5;
    localparam [4:0] STATE_READ_W1_ISSUE    = 5'd6;
    localparam [4:0] STATE_READ_W1_WAIT     = 5'd7;
    localparam [4:0] STATE_READ_W1_CAPTURE  = 5'd8;
    localparam [4:0] STATE_READ_W2_ISSUE    = 5'd9;
    localparam [4:0] STATE_READ_W2_WAIT     = 5'd10;
    localparam [4:0] STATE_READ_W2_CAPTURE  = 5'd11;
    localparam [4:0] STATE_READ_W3_ISSUE    = 5'd12;
    localparam [4:0] STATE_READ_W3_WAIT     = 5'd13;
    localparam [4:0] STATE_READ_W3_CAPTURE  = 5'd14;
    localparam [4:0] STATE_STREAM_WAIT      = 5'd15;
    localparam [4:0] STATE_POLL_STATUS      = 5'd16;
    localparam [4:0] STATE_POLL_STATUS_EVAL = 5'd17;
    localparam [4:0] STATE_READ_META        = 5'd18;
    localparam [4:0] STATE_READ_META_EVAL   = 5'd19;
    localparam [4:0] STATE_READ_DATA        = 5'd20;
    localparam [4:0] STATE_READ_DATA_EVAL   = 5'd21;
    localparam [4:0] STATE_DMEM_WRITE_ISSUE = 5'd22;
    localparam [4:0] STATE_APB_SETUP        = 5'd23;
    localparam [4:0] STATE_APB_ACCESS       = 5'd24;
    localparam [4:0] STATE_COMPLETE         = 5'd25;
    localparam [4:0] STATE_ERROR            = 5'd26;

    localparam [1:0] DIR_RX                 = 2'b10;

    localparam [31:0] RX_ADDR_META          = 32'h0000_0004;
    localparam [31:0] RX_ADDR_STATUS        = 32'h0000_0008;
    localparam [31:0] RX_ADDR_CONTROL       = 32'h0000_000C;
    localparam [31:0] RX_ADDR_DATA          = 32'h0000_0000;

    localparam [7:0] ERR_NONE               = 8'h00;
    localparam [7:0] ERR_BAD_ALIGNMENT      = 8'h02;
    localparam [7:0] ERR_RX_APB             = 8'h03;
    localparam [7:0] ERR_RX_STATUS          = 8'h04;
    localparam [7:0] ERR_RX_META            = 8'h05;
    localparam [7:0] ERR_RX_LENGTH          = 8'h06;

    reg [4:0]  state_r;
    reg [4:0]  apb_resume_state_r;
    reg        apb_write_r;
    reg [31:0] apb_addr_r;
    reg [31:0] apb_wdata_r;
    reg [31:0] apb_rdata_r;

    reg [31:0] src_ptr_r;
    reg [31:0] dst_ptr_r;
    reg [31:0] ctxt_bytes_remaining_r;
    reg [31:0] ctxt_w0_r;
    reg [31:0] ctxt_w1_r;
    reg [31:0] ctxt_w2_r;
    reg [31:0] ctxt_w3_r;
    reg [2:0]  meta_r;
    reg [31:0] output_word_r;
    reg        stream_pending_r;

    wire start_rx_w;
    wire config_invalid_w;
    wire [2:0] meta_valid_bytes_w;
    wire unused_control_w;

    assign start_rx_w = start_i && (direction_i == DIR_RX);
    assign config_invalid_w = (direction_i != DIR_RX) ||
                              (len_bytes_i == 32'b0) ||
                              (len_bytes_i[3:0] != 4'b0000) ||
                              (src_addr_i[1:0] != 2'b00) ||
                              (dst_addr_i[1:0] != 2'b00);
    assign meta_valid_bytes_w = meta_r;
    assign unused_control_w = clear_done_i ^ clear_error_i ^ (^block_size_i);

    assign dmem_en_o = (state_r == STATE_READ_W0_ISSUE)   ||
                       (state_r == STATE_READ_W1_ISSUE)   ||
                       (state_r == STATE_READ_W2_ISSUE)   ||
                       (state_r == STATE_READ_W3_ISSUE)   ||
                       (state_r == STATE_DMEM_WRITE_ISSUE);
    assign dmem_we_o = (state_r == STATE_DMEM_WRITE_ISSUE) ? 4'b1111 : 4'b0000;
    assign dmem_addr_o = ((state_r == STATE_DMEM_WRITE_ISSUE) ? dst_ptr_r : src_ptr_r) ^
                         {32{1'b0 & unused_control_w}};
    assign dmem_wdata_o = output_word_r;

    assign rx_ciphertext_word_o = {ctxt_w3_r, ctxt_w2_r, ctxt_w1_r, ctxt_w0_r};
    assign rx_ciphertext_word_valid_o = (state_r == STATE_STREAM_WAIT) && stream_pending_r;

    assign rx_psel_o    = (state_r == STATE_APB_SETUP) || (state_r == STATE_APB_ACCESS);
    assign rx_penable_o = (state_r == STATE_APB_ACCESS);
    assign rx_pwrite_o  = apb_write_r;
    assign rx_paddr_o   = apb_addr_r;
    assign rx_pwdata_o  = apb_wdata_r;

    assign dma_busy_o = (state_r != STATE_IDLE);
    assign engine_state_o = state_r[3:0];

    always @(posedge clk_i) begin
        if (rst_i) begin
            state_r            <= STATE_IDLE;
            apb_resume_state_r <= STATE_IDLE;
            apb_write_r        <= 1'b0;
            apb_addr_r         <= 32'b0;
            apb_wdata_r        <= 32'b0;
            apb_rdata_r        <= 32'b0;
            src_ptr_r          <= 32'b0;
            dst_ptr_r          <= 32'b0;
            ctxt_bytes_remaining_r <= 32'b0;
            ctxt_w0_r          <= 32'b0;
            ctxt_w1_r          <= 32'b0;
            ctxt_w2_r          <= 32'b0;
            ctxt_w3_r          <= 32'b0;
            meta_r             <= 3'b0;
            output_word_r      <= 32'b0;
            stream_pending_r   <= 1'b0;
            dma_done_o         <= 1'b0;
            dma_error_o        <= 1'b0;
            bytes_done_o       <= 32'b0;
            last_error_code_o  <= ERR_NONE;
        end
        else begin
            dma_done_o  <= 1'b0;
            dma_error_o <= 1'b0;

            if (clear_error_i)
                last_error_code_o <= ERR_NONE;

            if (soft_reset_i) begin
                state_r            <= STATE_IDLE;
                apb_resume_state_r <= STATE_IDLE;
                apb_write_r        <= 1'b0;
                apb_addr_r         <= 32'b0;
                apb_wdata_r        <= 32'b0;
                apb_rdata_r        <= 32'b0;
                src_ptr_r          <= 32'b0;
                dst_ptr_r          <= 32'b0;
                ctxt_bytes_remaining_r <= 32'b0;
                ctxt_w0_r          <= 32'b0;
                ctxt_w1_r          <= 32'b0;
                ctxt_w2_r          <= 32'b0;
                ctxt_w3_r          <= 32'b0;
                meta_r             <= 3'b0;
                output_word_r      <= 32'b0;
                stream_pending_r   <= 1'b0;
                bytes_done_o       <= 32'b0;
                last_error_code_o  <= ERR_NONE;
            end
            else begin
                case (state_r)
                    STATE_IDLE: begin
                        if (start_rx_w) begin
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
                        src_ptr_r          <= src_addr_i;
                        dst_ptr_r          <= dst_addr_i;
                        ctxt_bytes_remaining_r <= len_bytes_i;
                        ctxt_w0_r          <= 32'b0;
                        ctxt_w1_r          <= 32'b0;
                        ctxt_w2_r          <= 32'b0;
                        ctxt_w3_r          <= 32'b0;
                        meta_r             <= 3'b0;
                        output_word_r      <= 32'b0;
                        stream_pending_r   <= 1'b0;
                        bytes_done_o       <= 32'b0;
                        apb_write_r        <= 1'b1;
                        apb_addr_r         <= RX_ADDR_CONTROL;
                        apb_wdata_r        <= 32'h0000_0001;
                        apb_resume_state_r <= STATE_RESET_RX;
                        state_r            <= STATE_APB_SETUP;
                    end

                    STATE_RESET_RX: begin
                        state_r <= STATE_READ_W0_ISSUE;
                    end

                    STATE_READ_W0_ISSUE: state_r <= STATE_READ_W0_WAIT;

                    STATE_READ_W0_WAIT: state_r <= STATE_READ_W0_CAPTURE;

                    STATE_READ_W0_CAPTURE: begin
                        ctxt_w0_r <= dmem_rdata_i;
                        src_ptr_r <= src_ptr_r + 32'd4;
                        state_r   <= STATE_READ_W1_ISSUE;
                    end

                    STATE_READ_W1_ISSUE: state_r <= STATE_READ_W1_WAIT;

                    STATE_READ_W1_WAIT: state_r <= STATE_READ_W1_CAPTURE;

                    STATE_READ_W1_CAPTURE: begin
                        ctxt_w1_r <= dmem_rdata_i;
                        src_ptr_r <= src_ptr_r + 32'd4;
                        state_r   <= STATE_READ_W2_ISSUE;
                    end

                    STATE_READ_W2_ISSUE: state_r <= STATE_READ_W2_WAIT;

                    STATE_READ_W2_WAIT: state_r <= STATE_READ_W2_CAPTURE;

                    STATE_READ_W2_CAPTURE: begin
                        ctxt_w2_r <= dmem_rdata_i;
                        src_ptr_r <= src_ptr_r + 32'd4;
                        state_r   <= STATE_READ_W3_ISSUE;
                    end

                    STATE_READ_W3_ISSUE: state_r <= STATE_READ_W3_WAIT;

                    STATE_READ_W3_WAIT: state_r <= STATE_READ_W3_CAPTURE;

                    STATE_READ_W3_CAPTURE: begin
                        ctxt_w3_r <= dmem_rdata_i;
                        src_ptr_r <= src_ptr_r + 32'd4;
                        stream_pending_r <= 1'b1;
                        state_r   <= STATE_STREAM_WAIT;
                    end

                    STATE_STREAM_WAIT: begin
                        if (stream_pending_r && rx_ciphertext_word_ready_i) begin
                            stream_pending_r       <= 1'b0;
                            ctxt_bytes_remaining_r <= ctxt_bytes_remaining_r - 32'd16;
                            state_r                <= STATE_POLL_STATUS;
                        end
                        else begin
                            state_r                <= STATE_POLL_STATUS;
                        end
                    end

                    STATE_POLL_STATUS: begin
                        apb_write_r        <= 1'b0;
                        apb_addr_r         <= RX_ADDR_STATUS;
                        apb_wdata_r        <= 32'b0;
                        apb_resume_state_r <= STATE_POLL_STATUS_EVAL;
                        state_r            <= STATE_APB_SETUP;
                    end

                    STATE_POLL_STATUS_EVAL: begin
                        if (apb_rdata_r[5]) begin
                            last_error_code_o <= ERR_RX_STATUS;
                            state_r           <= STATE_ERROR;
                        end
                        else if (apb_rdata_r[0]) begin
                            state_r <= STATE_READ_META;
                        end
                        else if (apb_rdata_r[4]) begin
                            if ((ctxt_bytes_remaining_r == 32'b0) && (!stream_pending_r)) begin
                                state_r <= STATE_COMPLETE;
                            end
                            else begin
                                last_error_code_o <= ERR_RX_LENGTH;
                                state_r           <= STATE_ERROR;
                            end
                        end
                        else if (stream_pending_r) begin
                            state_r <= STATE_STREAM_WAIT;
                        end
                        else if (ctxt_bytes_remaining_r != 32'b0) begin
                            state_r <= STATE_READ_W0_ISSUE;
                        end
                        else begin
                            state_r <= STATE_POLL_STATUS;
                        end
                    end

                    STATE_READ_META: begin
                        apb_write_r        <= 1'b0;
                        apb_addr_r         <= RX_ADDR_META;
                        apb_wdata_r        <= 32'b0;
                        apb_resume_state_r <= STATE_READ_META_EVAL;
                        state_r            <= STATE_APB_SETUP;
                    end

                    STATE_READ_META_EVAL: begin
                        meta_r <= apb_rdata_r[2:0];
                        if ((apb_rdata_r[2:0] == 3'b000) || (apb_rdata_r[2:0] > 3'd4)) begin
                            last_error_code_o <= ERR_RX_META;
                            state_r           <= STATE_ERROR;
                        end
                        else begin
                            state_r <= STATE_READ_DATA;
                        end
                    end

                    STATE_READ_DATA: begin
                        apb_write_r        <= 1'b0;
                        apb_addr_r         <= RX_ADDR_DATA;
                        apb_wdata_r        <= 32'b0;
                        apb_resume_state_r <= STATE_READ_DATA_EVAL;
                        state_r            <= STATE_APB_SETUP;
                    end

                    STATE_READ_DATA_EVAL: begin
                        output_word_r <= apb_rdata_r;
                        state_r       <= STATE_DMEM_WRITE_ISSUE;
                    end

                    STATE_DMEM_WRITE_ISSUE: begin
                        dst_ptr_r    <= dst_ptr_r + 32'd4;
                        bytes_done_o <= bytes_done_o + {29'b0, meta_valid_bytes_w};
                        state_r      <= STATE_POLL_STATUS;
                    end

                    STATE_APB_SETUP: begin
                        state_r <= STATE_APB_ACCESS;
                    end

                    STATE_APB_ACCESS: begin
                        if (rx_pready_i) begin
                            apb_rdata_r <= rx_prdata_i;
                            if (rx_pslverr_i) begin
                                last_error_code_o <= ERR_RX_APB;
                                state_r           <= STATE_ERROR;
                            end
                            else begin
                                state_r <= apb_resume_state_r;
                            end
                        end
                    end

                    STATE_COMPLETE: begin
                        dma_done_o        <= 1'b1;
                        last_error_code_o <= ERR_NONE;
                        state_r           <= STATE_IDLE;
                    end

                    STATE_ERROR: begin
                        dma_error_o <= 1'b1;
                        state_r     <= STATE_IDLE;
                    end

                    default: begin
                        state_r <= STATE_IDLE;
                    end
                endcase
            end
        end
    end

endmodule
