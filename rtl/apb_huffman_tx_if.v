module apb_huffman_tx_if #(
    parameter BLOCK_SIZE_WIDTH  = 6,
    parameter SYMBOL_COUNT_WIDTH = 9
)(
    input  wire                         PCLK,
    input  wire                         PRESETn,
    input  wire                         PSEL,
    input  wire                         PENABLE,
    input  wire                         PWRITE,
    input  wire [31:0]                  PADDR,
    input  wire [31:0]                  PWDATA,
    output reg  [31:0]                  PRDATA,
    output reg                          PREADY,
    output reg                          PSLVERR,

    // --------------------------------------------------------------------
    // Downstream interface to huffman_aes_tx_top
    // --------------------------------------------------------------------
    output reg                          start_block_o,
    output reg                          continue_frame_o,
    output reg                          compress_only_o,
    output reg                          whole_file_enable_o,
    output reg                          whole_file_count_mode_o,
    output reg  [BLOCK_SIZE_WIDTH-1:0]  block_size_o,
    output wire [31:0]                  word_in_o,
    output wire                         word_valid_o,
    input  wire                         word_ready_i,

    // --------------------------------------------------------------------
    // AES ciphertext output stream as 32-bit words for CPU reads
    // --------------------------------------------------------------------
    input  wire [31:0]                  aes_out_word_i,
    input  wire                         aes_out_word_last_i,
    input  wire                         aes_out_word_valid_i,
    output wire                         aes_out_word_ready_o,
    input  wire                         aes_out_error_i,
    output wire                         soft_reset_o,
    output wire                         clear_error_o,
    output wire                         global_clear_o,
    output wire                         global_build_start_o,

    // --------------------------------------------------------------------
    // Status from huffman_aes_tx_top
    // --------------------------------------------------------------------
    input  wire                         tx_busy_i,
    input  wire                         tx_done_i,
    input  wire                         tx_error_i,
    input  wire                         global_build_busy_i,
    input  wire                         global_build_done_i,
    input  wire                         global_build_error_i,
    input  wire                         global_table_valid_i,
    input  wire [SYMBOL_COUNT_WIDTH-1:0] global_symbol_count_i
);

    // --------------------------------------------------------------------
    // Address map
    // --------------------------------------------------------------------
    localparam [31:0] ADDR_START_BLOCK = 32'h0000_0000;
    localparam [31:0] ADDR_BLOCK_SIZE  = 32'h0000_0004;
    localparam [31:0] ADDR_WORD_IN     = 32'h0000_0008;
    localparam [31:0] ADDR_STATUS      = 32'h0000_000C;
    localparam [31:0] ADDR_CONTROL     = 32'h0000_0010;
    localparam [31:0] ADDR_DEBUG       = 32'h0000_0014;
    localparam [31:0] ADDR_TX_POLICY   = 32'h0000_0018;
    localparam [31:0] ADDR_AES_OUT_DATA   = 32'h0000_0020;
    localparam [31:0] ADDR_AES_OUT_META   = 32'h0000_0024;
    localparam [31:0] ADDR_AES_OUT_STATUS = 32'h0000_0028;
    localparam [31:0] ADDR_AES_OUT_DEBUG  = 32'h0000_002C;

    // --------------------------------------------------------------------
    // FIFO: max 8 words for max 32-byte block
    // --------------------------------------------------------------------
    localparam FIFO_DEPTH       = 8;
    localparam FIFO_PTR_WIDTH   = 3;
    localparam FIFO_COUNT_WIDTH = 4;
    localparam OUT_FIFO_DEPTH       = 16;
    localparam OUT_FIFO_PTR_WIDTH   = 4;
    localparam OUT_FIFO_COUNT_WIDTH = 5;
    localparam [OUT_FIFO_COUNT_WIDTH-1:0] OUT_FIFO_DEPTH_VAL = 5'd16;

    (* ram_style = "distributed" *) reg [31:0] fifo_mem [0:FIFO_DEPTH-1];
    reg [FIFO_PTR_WIDTH-1:0] wr_ptr_r;
    reg [FIFO_PTR_WIDTH-1:0] rd_ptr_r;
    reg [FIFO_COUNT_WIDTH-1:0] fifo_count_r;

    (* ram_style = "distributed" *) reg [31:0] out_fifo_mem [0:OUT_FIFO_DEPTH-1];
    (* ram_style = "distributed" *) reg        out_fifo_last_mem [0:OUT_FIFO_DEPTH-1];
    reg [OUT_FIFO_PTR_WIDTH-1:0] out_wr_ptr_r;
    reg [OUT_FIFO_PTR_WIDTH-1:0] out_rd_ptr_r;
    reg [OUT_FIFO_COUNT_WIDTH-1:0] out_fifo_count_r;

    reg                        cfg_valid_r;
    reg [3:0]                  words_expected_r;
    reg [3:0]                  words_loaded_r;

    reg                        block_inflight_r;
    reg                        stream_active_r;

    reg                        done_sticky_r;
    reg                        error_sticky_r;
    reg                        aes_out_error_sticky_r;

    // --------------------------------------------------------------------
    // APB phase detect
    // --------------------------------------------------------------------
    wire apb_access_w;
    wire apb_write_access_w;
    wire apb_read_access_w;
    wire write_commit_w;
    wire read_commit_w;
    wire read_aes_out_data_commit_w;
    wire out_fifo_empty_w;
    wire out_fifo_full_w;
    wire control_reserved_bits_set_w;
    wire control_write_ok_w;
    wire soft_reset_pulse_w;
    wire aes_out_push_w;
    wire count_mode_done_w;
    wire block_done_event_w;
    wire [31:0] out_head_word_w;
    wire        out_head_last_w;

    assign apb_access_w       = PSEL && PENABLE;
    assign apb_write_access_w = apb_access_w && PWRITE;
    assign apb_read_access_w  = apb_access_w && (!PWRITE);

    assign write_commit_w     = apb_write_access_w && PREADY;
    assign read_commit_w      = apb_read_access_w  && PREADY;
    assign control_reserved_bits_set_w = |PWDATA[31:5];
    assign control_write_ok_w = write_commit_w &&
                                (PADDR == ADDR_CONTROL) &&
                                (!control_reserved_bits_set_w);
    assign soft_reset_pulse_w = control_write_ok_w && PWDATA[0];
    assign soft_reset_o       = soft_reset_pulse_w;
    assign clear_error_o      = control_write_ok_w && PWDATA[2];
    assign global_clear_o     = control_write_ok_w && PWDATA[3];
    assign global_build_start_o = control_write_ok_w && PWDATA[4];

    // --------------------------------------------------------------------
    // FIFO head to TX top
    // --------------------------------------------------------------------
    assign word_in_o    = fifo_mem[rd_ptr_r];
    assign word_valid_o = stream_active_r && (fifo_count_r != 0);
    assign out_head_word_w = out_fifo_mem[out_rd_ptr_r];
    assign out_head_last_w = out_fifo_last_mem[out_rd_ptr_r];
    assign out_fifo_empty_w = (out_fifo_count_r == {OUT_FIFO_COUNT_WIDTH{1'b0}});
    assign out_fifo_full_w  = (out_fifo_count_r == OUT_FIFO_DEPTH_VAL);
    assign read_aes_out_data_commit_w = read_commit_w &&
                                        (PADDR == ADDR_AES_OUT_DATA) &&
                                        (!out_fifo_empty_w);
    assign aes_out_word_ready_o = (!out_fifo_full_w) || read_aes_out_data_commit_w;
    assign aes_out_push_w = aes_out_word_valid_i && aes_out_word_ready_o;
    assign count_mode_done_w = whole_file_count_mode_o &&
                               block_inflight_r &&
                               (!stream_active_r) &&
                               (fifo_count_r == {FIFO_COUNT_WIDTH{1'b0}}) &&
                               (!tx_busy_i);
    assign block_done_event_w = tx_done_i || count_mode_done_w;

    wire stream_fire_w;
    assign stream_fire_w = word_valid_o && word_ready_i;

    // --------------------------------------------------------------------
    // Helper: ceil(block_size / 4)
    // --------------------------------------------------------------------
    function [3:0] calc_words_needed;
        input [BLOCK_SIZE_WIDTH-1:0] size_bytes;
        begin
            if (size_bytes == {BLOCK_SIZE_WIDTH{1'b0}})
                calc_words_needed = 4'd0;
            else
                calc_words_needed = size_bytes[5:2] +
                                    ((|size_bytes[1:0]) ? 4'd1 : 4'd0);
        end
    endfunction

    always @(posedge PCLK) begin
        if (aes_out_push_w) begin
            out_fifo_mem[out_wr_ptr_r]      <= aes_out_word_i;
            out_fifo_last_mem[out_wr_ptr_r] <= aes_out_word_last_i;
        end

        if (write_commit_w && (PADDR == ADDR_WORD_IN) && !PSLVERR)
            fifo_mem[wr_ptr_r] <= PWDATA;
    end

    // --------------------------------------------------------------------
    // Combinational APB response logic
    // --------------------------------------------------------------------
    always @(*) begin
        PRDATA  = 32'b0;
        PREADY  = 1'b1;
        PSLVERR = 1'b0;

        // ------------------------------------------------------------
        // Read mux
        // ------------------------------------------------------------
        if (apb_read_access_w) begin
            case (PADDR)
                ADDR_START_BLOCK: begin
                    PRDATA = 32'b0;
                end

                ADDR_BLOCK_SIZE: begin
                    PRDATA[BLOCK_SIZE_WIDTH-1:0] = block_size_o;
                end

                ADDR_WORD_IN: begin
                    PRDATA = 32'b0;
                end

                ADDR_STATUS: begin
                    PRDATA[0] = cfg_valid_r;                                // cfg_valid
                    PRDATA[1] = cfg_valid_r &&
                                (!block_inflight_r) &&
                                (words_loaded_r < words_expected_r) &&
                                (fifo_count_r < FIFO_DEPTH);                // input_ready
                    PRDATA[2] = block_inflight_r;                           // block_active
                    PRDATA[3] = tx_busy_i;                                  // tx_busy
                    PRDATA[4] = done_sticky_r;                              // done_sticky
                    PRDATA[5] = error_sticky_r;                             // tx_core_error_sticky
                    PRDATA[6] = (fifo_count_r != 0);                        // fifo_nonempty
                    PRDATA[7] = cfg_valid_r &&
                                (words_loaded_r == words_expected_r) &&
                                (words_expected_r != 0) &&
                                (!block_inflight_r) &&
                                (!tx_busy_i);                               // can_start
                    PRDATA[8]  = global_table_valid_i;
                    PRDATA[9]  = global_build_busy_i;
                    PRDATA[10] = global_build_done_i;
                    PRDATA[11] = global_build_error_i;
                    PRDATA[12] = whole_file_enable_o;
                    PRDATA[13] = whole_file_count_mode_o;
                end

                ADDR_CONTROL: begin
                    PRDATA[0] = 1'b0;         // soft_reset pulse write-only
                    PRDATA[1] = 1'b0;         // clear_done pulse write-only
                    PRDATA[2] = 1'b0;         // clear_error pulse write-only
                end

                ADDR_DEBUG: begin
                    PRDATA[3:0]   = fifo_count_r;
                    PRDATA[7:4]   = words_expected_r;
                    PRDATA[11:8]  = words_loaded_r;
                    PRDATA[15]    = stream_active_r;
                    PRDATA[16]    = block_inflight_r;
                    PRDATA[19:17] = wr_ptr_r;
                    PRDATA[22:20] = rd_ptr_r;
                    PRDATA[23]    = compress_only_o;
                    PRDATA[24]    = whole_file_enable_o;
                    PRDATA[25]    = whole_file_count_mode_o;
                end

                ADDR_TX_POLICY: begin
                    PRDATA[0] = compress_only_o;
                    PRDATA[1] = whole_file_enable_o;
                    PRDATA[2] = whole_file_count_mode_o;
                    PRDATA[SYMBOL_COUNT_WIDTH+8-1:8] = global_symbol_count_i;
                end

                ADDR_AES_OUT_DATA: begin
                    if (out_fifo_empty_w) begin
                        PREADY = 1'b0;
                    end
                    else begin
                        PRDATA = out_head_word_w;
                    end
                end

                ADDR_AES_OUT_META: begin
                    if (!out_fifo_empty_w) begin
                        PRDATA[0] = out_head_last_w;
                        PRDATA[1] = compress_only_o;
                    end
                end

                ADDR_AES_OUT_STATUS: begin
                    PRDATA[0]    = !out_fifo_empty_w;
                    PRDATA[1]    = out_fifo_full_w;
                    PRDATA[2]    = !out_fifo_full_w;
                    PRDATA[7:3]  = out_fifo_count_r;
                    PRDATA[9]    = aes_out_error_sticky_r;
                    PRDATA[10]   = compress_only_o;
                    PRDATA[11]   = whole_file_enable_o;

                    if (!out_fifo_empty_w)
                        PRDATA[8] = out_head_last_w;
                end

                ADDR_AES_OUT_DEBUG: begin
                    PRDATA[4:0]   = out_fifo_count_r;
                    PRDATA[8:5]   = out_wr_ptr_r;
                    PRDATA[12:9]  = out_rd_ptr_r;
                    PRDATA[13]    = !out_fifo_empty_w;
                    PRDATA[14]    = 1'b1;
                    PRDATA[15]    = aes_out_error_sticky_r;
                end

                default: begin
                    PRDATA  = 32'b0;
                    PSLVERR = 1'b1;
                end
            endcase
        end

        // ------------------------------------------------------------
        // Write-side PREADY / PSLVERR policy
        // ------------------------------------------------------------
        if (apb_write_access_w) begin
            case (PADDR)

                // ----------------------------------------------------
                // REG_START_BLOCK
                // ----------------------------------------------------
                ADDR_START_BLOCK: begin
                    if (!cfg_valid_r) begin
                        PREADY  = 1'b1;
                        PSLVERR = 1'b1;
                    end
                    else if (words_expected_r == 0) begin
                        PREADY  = 1'b1;
                        PSLVERR = 1'b1;
                    end
                    else if (words_loaded_r != words_expected_r) begin
                        PREADY = 1'b0;
                    end
                    else if (block_inflight_r || tx_busy_i) begin
                        PREADY = 1'b0;
                    end
                    else begin
                        PREADY  = 1'b1;
                        PSLVERR = (PWDATA[0] != 1'b1);
                    end
                end

                // ----------------------------------------------------
                // REG_BLOCK_SIZE
                // ----------------------------------------------------
                ADDR_BLOCK_SIZE: begin
                    if (block_inflight_r || stream_active_r || (fifo_count_r != 0) || tx_busy_i) begin
                        PREADY = 1'b0;
                    end
                    else begin
                        PREADY = 1'b1;
                        if ((PWDATA[BLOCK_SIZE_WIDTH-1:0] == {BLOCK_SIZE_WIDTH{1'b0}}) ||
                            (PWDATA[BLOCK_SIZE_WIDTH-1:0] > 6'd32)) begin
                            PSLVERR = 1'b1;
                        end
                    end
                end

                // ----------------------------------------------------
                // REG_WORD_IN
                // ----------------------------------------------------
                ADDR_WORD_IN: begin
                    if (!cfg_valid_r) begin
                        PREADY  = 1'b1;
                        PSLVERR = 1'b1;
                    end
                    else if (block_inflight_r) begin
                        PREADY  = 1'b1;
                        PSLVERR = 1'b1;
                    end
                    else if (words_loaded_r >= words_expected_r) begin
                        PREADY  = 1'b1;
                        PSLVERR = 1'b1;
                    end
                    else if (fifo_count_r == FIFO_DEPTH) begin
                        PREADY = 1'b0;
                    end
                    else begin
                        PREADY = 1'b1;
                    end
                end

                // ----------------------------------------------------
                // REG_CONTROL
                // ----------------------------------------------------
                ADDR_CONTROL: begin
                    PREADY = 1'b1;
                    PSLVERR = control_reserved_bits_set_w;
                end

                ADDR_TX_POLICY: begin
                    if (block_inflight_r || stream_active_r || (fifo_count_r != 0) || tx_busy_i) begin
                        PREADY = 1'b0;
                    end
                    else begin
                        PREADY = 1'b1;
                        PSLVERR = |PWDATA[31:3];
                    end
                end

                default: begin
                    PREADY  = 1'b1;
                    PSLVERR = 1'b1;
                end
            endcase
        end
    end

    // --------------------------------------------------------------------
    // Sequential logic
    // --------------------------------------------------------------------
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            wr_ptr_r         <= {FIFO_PTR_WIDTH{1'b0}};
            rd_ptr_r         <= {FIFO_PTR_WIDTH{1'b0}};
            fifo_count_r     <= {FIFO_COUNT_WIDTH{1'b0}};
            out_wr_ptr_r     <= {OUT_FIFO_PTR_WIDTH{1'b0}};
            out_rd_ptr_r     <= {OUT_FIFO_PTR_WIDTH{1'b0}};
            out_fifo_count_r <= {OUT_FIFO_COUNT_WIDTH{1'b0}};

            cfg_valid_r      <= 1'b0;
            compress_only_o  <= 1'b0;
            whole_file_enable_o <= 1'b0;
            whole_file_count_mode_o <= 1'b0;
            block_size_o     <= {BLOCK_SIZE_WIDTH{1'b0}};
            words_expected_r <= 4'd0;
            words_loaded_r   <= 4'd0;

            block_inflight_r <= 1'b0;
            stream_active_r  <= 1'b0;

            done_sticky_r    <= 1'b0;
            error_sticky_r   <= 1'b0;
            aes_out_error_sticky_r <= 1'b0;

            start_block_o    <= 1'b0;
            continue_frame_o <= 1'b0;

        end
        else begin
            // pulse default
            start_block_o    <= 1'b0;
            continue_frame_o <= 1'b0;

            // sticky from downstream
            if (block_done_event_w)
                done_sticky_r <= 1'b1;

            if (tx_error_i)
                error_sticky_r <= 1'b1;

            if (aes_out_error_i)
                aes_out_error_sticky_r <= 1'b1;

            // pop FIFO when TX top accepts a word
            if (stream_fire_w) begin
                rd_ptr_r     <= rd_ptr_r + 1'b1;
                fifo_count_r <= fifo_count_r - 1'b1;

                if (fifo_count_r == 4'd1)
                    stream_active_r <= 1'b0;
            end

            // block completion from TX top
            if (block_done_event_w || tx_error_i) begin
                wr_ptr_r         <= {FIFO_PTR_WIDTH{1'b0}};
                rd_ptr_r         <= {FIFO_PTR_WIDTH{1'b0}};
                fifo_count_r     <= {FIFO_COUNT_WIDTH{1'b0}};

                cfg_valid_r      <= 1'b0;
                block_size_o     <= {BLOCK_SIZE_WIDTH{1'b0}};
                words_expected_r <= 4'd0;
                words_loaded_r   <= 4'd0;

                block_inflight_r <= 1'b0;
                stream_active_r  <= 1'b0;
            end

            case ({aes_out_push_w, read_aes_out_data_commit_w})
                2'b10: begin
                    out_wr_ptr_r     <= out_wr_ptr_r + 1'b1;
                    out_fifo_count_r <= out_fifo_count_r + 1'b1;
                end

                2'b01: begin
                    out_rd_ptr_r     <= out_rd_ptr_r + 1'b1;
                    out_fifo_count_r <= out_fifo_count_r - 1'b1;
                end

                2'b11: begin
                    out_wr_ptr_r     <= out_wr_ptr_r + 1'b1;
                    out_rd_ptr_r     <= out_rd_ptr_r + 1'b1;
                    out_fifo_count_r <= out_fifo_count_r;
                end

                default: begin
                    out_wr_ptr_r     <= out_wr_ptr_r;
                    out_rd_ptr_r     <= out_rd_ptr_r;
                    out_fifo_count_r <= out_fifo_count_r;
                end
            endcase

            // --------------------------------------------------------
            // APB write commit
            // --------------------------------------------------------
            if (write_commit_w) begin
                case (PADDR)

                    ADDR_START_BLOCK: begin
                        if ((PWDATA[0] == 1'b1) && !PSLVERR) begin
                            start_block_o    <= 1'b1;
                            continue_frame_o <= PWDATA[1];
                            block_inflight_r <= 1'b1;
                            stream_active_r  <= 1'b1;
                            done_sticky_r    <= 1'b0;
                        end
                        else if (PSLVERR) begin
                            error_sticky_r <= 1'b1;
                        end
                    end

                    ADDR_BLOCK_SIZE: begin
                        if (!PSLVERR) begin
                            block_size_o     <= PWDATA[BLOCK_SIZE_WIDTH-1:0];
                            cfg_valid_r      <= 1'b1;
                            words_expected_r <= calc_words_needed(PWDATA[BLOCK_SIZE_WIDTH-1:0]);
                            words_loaded_r   <= 4'd0;

                            wr_ptr_r         <= {FIFO_PTR_WIDTH{1'b0}};
                            rd_ptr_r         <= {FIFO_PTR_WIDTH{1'b0}};
                            fifo_count_r     <= {FIFO_COUNT_WIDTH{1'b0}};

                            done_sticky_r    <= 1'b0;
                            error_sticky_r   <= 1'b0;
                        end
                        else begin
                            error_sticky_r <= 1'b1;
                        end
                    end

                    ADDR_TX_POLICY: begin
                        if (!PSLVERR) begin
                            compress_only_o          <= PWDATA[0];
                            whole_file_enable_o      <= PWDATA[1];
                            whole_file_count_mode_o  <= PWDATA[2];
                        end
                        else begin
                            error_sticky_r <= 1'b1;
                        end
                    end

                    ADDR_WORD_IN: begin
                        if (!PSLVERR) begin
                            wr_ptr_r           <= wr_ptr_r + 1'b1;
                            fifo_count_r       <= fifo_count_r + 1'b1;
                            words_loaded_r     <= words_loaded_r + 1'b1;
                        end
                        else begin
                            error_sticky_r <= 1'b1;
                        end
                    end

                    ADDR_CONTROL: begin
                        if (control_write_ok_w) begin
                            if (PWDATA[0]) begin
                                wr_ptr_r         <= {FIFO_PTR_WIDTH{1'b0}};
                                rd_ptr_r         <= {FIFO_PTR_WIDTH{1'b0}};
                                fifo_count_r     <= {FIFO_COUNT_WIDTH{1'b0}};
                                out_wr_ptr_r     <= {OUT_FIFO_PTR_WIDTH{1'b0}};
                                out_rd_ptr_r     <= {OUT_FIFO_PTR_WIDTH{1'b0}};
                                out_fifo_count_r <= {OUT_FIFO_COUNT_WIDTH{1'b0}};

                                cfg_valid_r      <= 1'b0;
                                compress_only_o  <= 1'b0;
                                whole_file_enable_o <= 1'b0;
                                whole_file_count_mode_o <= 1'b0;
                                block_size_o     <= {BLOCK_SIZE_WIDTH{1'b0}};
                                words_expected_r <= 4'd0;
                                words_loaded_r   <= 4'd0;

                                block_inflight_r <= 1'b0;
                                stream_active_r  <= 1'b0;

                                done_sticky_r    <= 1'b0;
                                error_sticky_r   <= 1'b0;
                                aes_out_error_sticky_r <= 1'b0;
                                start_block_o    <= 1'b0;
                                continue_frame_o <= 1'b0;
                            end
                            else begin
                                if (PWDATA[1])
                                    done_sticky_r <= 1'b0;
                                if (PWDATA[2]) begin
                                    error_sticky_r <= 1'b0;
                                    aes_out_error_sticky_r <= 1'b0;
                                end
                            end
                        end
                        else begin
                            error_sticky_r <= 1'b1;
                        end
                    end

                    default: begin
                        error_sticky_r <= 1'b1;
                    end
                endcase
            end

            if (read_commit_w && PSLVERR)
                error_sticky_r <= 1'b1;
        end
    end

endmodule
