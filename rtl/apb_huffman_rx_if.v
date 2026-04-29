module apb_huffman_rx_if #(
    parameter FIFO_PTR_WIDTH   = 4,
    parameter FIFO_COUNT_WIDTH = 5,
    parameter [FIFO_COUNT_WIDTH-1:0] FIFO_DEPTH = 5'd16
)(
    input  wire         PCLK,
    input  wire         PRESETn,
    input  wire         PSEL,
    input  wire         PENABLE,
    input  wire         PWRITE,
    input  wire [31:0]  PADDR,
    input  wire [31:0]  PWDATA,
    output reg  [31:0]  PRDATA,
    output reg          PREADY,
    output reg          PSLVERR,

    output wire [127:0] ciphertext_word_o,
    output wire         ciphertext_word_valid_o,
    input  wire         ciphertext_word_ready_i,

    input  wire [31:0]  rx_word_data_i,
    input  wire [2:0]   rx_word_valid_bytes_i,
    input  wire         rx_word_last_in_block_i,
    input  wire         rx_word_last_in_frame_i,
    input  wire         rx_word_valid_i,
    output wire         rx_word_ready_o,

    input  wire         rx_error_i
);

    localparam [31:0] ADDR_RX_DATA      = 32'h0000_0000;
    localparam [31:0] ADDR_RX_META      = 32'h0000_0004;
    localparam [31:0] ADDR_STATUS       = 32'h0000_0008;
    localparam [31:0] ADDR_CONTROL      = 32'h0000_000C;
    localparam [31:0] ADDR_DEBUG        = 32'h0000_0010;
    localparam [31:0] ADDR_CTXT_W0      = 32'h0000_0020;
    localparam [31:0] ADDR_CTXT_W1      = 32'h0000_0024;
    localparam [31:0] ADDR_CTXT_W2      = 32'h0000_0028;
    localparam [31:0] ADDR_CTXT_W3      = 32'h0000_002C;
    localparam [31:0] ADDR_CTXT_START   = 32'h0000_0030;
    localparam [31:0] ADDR_CTXT_STATUS  = 32'h0000_0034;

    localparam [2:0] VALID_BYTES_ZERO = 3'd0;
    localparam [2:0] VALID_BYTES_FOUR = 3'd4;

    reg [31:0] fifo_data_mem [0:FIFO_DEPTH-1];
    reg [2:0]  fifo_valid_bytes_mem [0:FIFO_DEPTH-1];
    reg        fifo_last_block_mem [0:FIFO_DEPTH-1];
    reg        fifo_last_frame_mem [0:FIFO_DEPTH-1];

    reg [FIFO_PTR_WIDTH-1:0]   wr_ptr_r;
    reg [FIFO_PTR_WIDTH-1:0]   rd_ptr_r;
    reg [FIFO_COUNT_WIDTH-1:0] fifo_count_r;

    reg block_done_sticky_r;
    reg frame_done_sticky_r;
    reg error_sticky_r;

    reg [31:0] cipher_stage_word0_r;
    reg [31:0] cipher_stage_word1_r;
    reg [31:0] cipher_stage_word2_r;
    reg [31:0] cipher_stage_word3_r;
    reg [3:0]  cipher_stage_valid_r;

    reg [127:0] cipher_pending_word_r;
    reg         cipher_pending_valid_r;

    wire apb_access_w;
    wire apb_write_access_w;
    wire apb_read_access_w;
    wire write_commit_w;
    wire read_commit_w;

    wire fifo_empty_w;
    wire fifo_full_w;
    wire control_reserved_bits_set_w;
    wire ctxt_start_reserved_bits_set_w;
    wire control_write_ok_w;
    wire soft_reset_pulse_w;
    wire read_rx_data_commit_w;
    wire rx_push_w;
    wire rx_input_error_w;

    wire [31:0] head_data_w;
    wire [2:0]  head_valid_bytes_w;
    wire        head_last_block_w;
    wire        head_last_frame_w;

    wire        cipher_stage_complete_w;
    wire        ciphertext_word_fire_w;
    wire        ctxt_w0_write_commit_w;
    wire        ctxt_w1_write_commit_w;
    wire        ctxt_w2_write_commit_w;
    wire        ctxt_w3_write_commit_w;
    wire        ctxt_start_write_ok_w;
    wire        invalid_write_commit_w;

    integer i;

    assign apb_access_w               = PSEL && PENABLE;
    assign apb_write_access_w         = apb_access_w && PWRITE;
    assign apb_read_access_w          = apb_access_w && (!PWRITE);
    assign write_commit_w             = apb_write_access_w && PREADY;
    assign read_commit_w              = apb_read_access_w && PREADY;

    assign fifo_empty_w               = (fifo_count_r == {FIFO_COUNT_WIDTH{1'b0}});
    assign fifo_full_w                = (fifo_count_r == FIFO_DEPTH);
    assign control_reserved_bits_set_w= |PWDATA[31:3];
    assign ctxt_start_reserved_bits_set_w = |PWDATA[31:1];
    assign control_write_ok_w         = write_commit_w &&
                                        (PADDR == ADDR_CONTROL) &&
                                        (!control_reserved_bits_set_w);
    assign soft_reset_pulse_w         = control_write_ok_w && PWDATA[0];
    assign read_rx_data_commit_w      = read_commit_w &&
                                        (PADDR == ADDR_RX_DATA) &&
                                        (!fifo_empty_w);

    assign rx_word_ready_o            = (((!fifo_full_w) || read_rx_data_commit_w) &&
                                         (!soft_reset_pulse_w));
    assign rx_push_w                  = rx_word_valid_i && rx_word_ready_o;

    assign rx_input_error_w           = rx_push_w &&
                                        ((rx_word_valid_bytes_i == VALID_BYTES_ZERO) ||
                                         (rx_word_valid_bytes_i > VALID_BYTES_FOUR) ||
                                         (rx_word_last_in_frame_i &&
                                          (!rx_word_last_in_block_i)));

    assign head_data_w                = fifo_data_mem[rd_ptr_r];
    assign head_valid_bytes_w         = fifo_valid_bytes_mem[rd_ptr_r];
    assign head_last_block_w          = fifo_last_block_mem[rd_ptr_r];
    assign head_last_frame_w          = fifo_last_frame_mem[rd_ptr_r];

    assign cipher_stage_complete_w    = &cipher_stage_valid_r;
    assign ciphertext_word_o          = cipher_pending_word_r;
    assign ciphertext_word_valid_o    = cipher_pending_valid_r;
    assign ciphertext_word_fire_w     = cipher_pending_valid_r &&
                                        ciphertext_word_ready_i;

    assign ctxt_w0_write_commit_w     = write_commit_w && (PADDR == ADDR_CTXT_W0);
    assign ctxt_w1_write_commit_w     = write_commit_w && (PADDR == ADDR_CTXT_W1);
    assign ctxt_w2_write_commit_w     = write_commit_w && (PADDR == ADDR_CTXT_W2);
    assign ctxt_w3_write_commit_w     = write_commit_w && (PADDR == ADDR_CTXT_W3);
    assign ctxt_start_write_ok_w      = write_commit_w &&
                                        (PADDR == ADDR_CTXT_START) &&
                                        (!ctxt_start_reserved_bits_set_w) &&
                                        PWDATA[0] &&
                                        cipher_stage_complete_w;

    assign invalid_write_commit_w     = write_commit_w &&
                                        (
                                            ((PADDR == ADDR_CONTROL) &&
                                             control_reserved_bits_set_w) ||
                                            ((PADDR == ADDR_CTXT_START) &&
                                             (ctxt_start_reserved_bits_set_w ||
                                              (PWDATA[0] != 1'b1) ||
                                              (!cipher_stage_complete_w))) ||
                                            ((PADDR != ADDR_CONTROL) &&
                                             (PADDR != ADDR_CTXT_W0) &&
                                             (PADDR != ADDR_CTXT_W1) &&
                                             (PADDR != ADDR_CTXT_W2) &&
                                             (PADDR != ADDR_CTXT_W3) &&
                                             (PADDR != ADDR_CTXT_START))
                                        );

    always @(*) begin
        PRDATA  = 32'b0;
        PREADY  = 1'b1;
        PSLVERR = 1'b0;

        if (apb_read_access_w) begin
            case (PADDR)
                ADDR_RX_DATA: begin
                    if (fifo_empty_w) begin
                        PREADY = 1'b0;
                    end
                    else begin
                        PRDATA = head_data_w;
                    end
                end

                ADDR_RX_META: begin
                    if (!fifo_empty_w) begin
                        PRDATA[2:0] = head_valid_bytes_w;
                        PRDATA[3]   = head_last_block_w;
                        PRDATA[4]   = head_last_frame_w;
                    end
                end

                ADDR_STATUS: begin
                    PRDATA[0]      = !fifo_empty_w;
                    PRDATA[1]      = fifo_full_w;
                    PRDATA[2]      = !fifo_full_w;
                    PRDATA[3]      = block_done_sticky_r;
                    PRDATA[4]      = frame_done_sticky_r;
                    PRDATA[5]      = error_sticky_r;
                    PRDATA[12:8]   = fifo_count_r;

                    if (!fifo_empty_w) begin
                        PRDATA[15:13] = head_valid_bytes_w;
                        PRDATA[16]    = head_last_block_w;
                        PRDATA[17]    = head_last_frame_w;
                    end

                    PRDATA[21:18] = cipher_stage_valid_r;
                    PRDATA[22]    = cipher_stage_complete_w;
                    PRDATA[23]    = cipher_pending_valid_r;
                    PRDATA[24]    = !cipher_pending_valid_r;
                end

                ADDR_CONTROL: begin
                    PRDATA = 32'b0;
                end

                ADDR_DEBUG: begin
                    PRDATA[4:0]   = fifo_count_r;
                    PRDATA[8:5]   = wr_ptr_r;
                    PRDATA[12:9]  = rd_ptr_r;
                    PRDATA[13]    = !fifo_empty_w;
                    PRDATA[14]    = 1'b1;
                    PRDATA[18:15] = cipher_stage_valid_r;
                    PRDATA[19]    = cipher_stage_complete_w;
                    PRDATA[20]    = cipher_pending_valid_r;
                    PRDATA[21]    = ciphertext_word_ready_i;
                end

                ADDR_CTXT_W0: begin
                    PRDATA = cipher_stage_word0_r;
                end

                ADDR_CTXT_W1: begin
                    PRDATA = cipher_stage_word1_r;
                end

                ADDR_CTXT_W2: begin
                    PRDATA = cipher_stage_word2_r;
                end

                ADDR_CTXT_W3: begin
                    PRDATA = cipher_stage_word3_r;
                end

                ADDR_CTXT_START: begin
                    PRDATA = 32'b0;
                end

                ADDR_CTXT_STATUS: begin
                    PRDATA[3:0]   = cipher_stage_valid_r;
                    PRDATA[4]     = cipher_stage_complete_w;
                    PRDATA[5]     = cipher_pending_valid_r;
                    PRDATA[6]     = !cipher_pending_valid_r;
                    PRDATA[7]     = ciphertext_word_ready_i;
                end

                default: begin
                    PSLVERR = 1'b1;
                end
            endcase
        end

        if (apb_write_access_w) begin
            case (PADDR)
                ADDR_CONTROL: begin
                    PREADY  = 1'b1;
                    PSLVERR = control_reserved_bits_set_w;
                end

                ADDR_CTXT_W0: begin
                    PREADY  = 1'b1;
                    PSLVERR = 1'b0;
                end

                ADDR_CTXT_W1: begin
                    PREADY  = 1'b1;
                    PSLVERR = 1'b0;
                end

                ADDR_CTXT_W2: begin
                    PREADY  = 1'b1;
                    PSLVERR = 1'b0;
                end

                ADDR_CTXT_W3: begin
                    PREADY  = 1'b1;
                    PSLVERR = 1'b0;
                end

                ADDR_CTXT_START: begin
                    if (ctxt_start_reserved_bits_set_w) begin
                        PREADY  = 1'b1;
                        PSLVERR = 1'b1;
                    end
                    else if (PWDATA[0] != 1'b1) begin
                        PREADY  = 1'b1;
                        PSLVERR = 1'b1;
                    end
                    else if (!cipher_stage_complete_w) begin
                        PREADY  = 1'b1;
                        PSLVERR = 1'b1;
                    end
                    else if (cipher_pending_valid_r) begin
                        PREADY = 1'b0;
                    end
                    else begin
                        PREADY  = 1'b1;
                        PSLVERR = 1'b0;
                    end
                end

                default: begin
                    PREADY  = 1'b1;
                    PSLVERR = 1'b1;
                end
            endcase
        end
    end

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            wr_ptr_r              <= {FIFO_PTR_WIDTH{1'b0}};
            rd_ptr_r              <= {FIFO_PTR_WIDTH{1'b0}};
            fifo_count_r          <= {FIFO_COUNT_WIDTH{1'b0}};
            block_done_sticky_r   <= 1'b0;
            frame_done_sticky_r   <= 1'b0;
            error_sticky_r        <= 1'b0;
            cipher_stage_word0_r  <= 32'h00000000;
            cipher_stage_word1_r  <= 32'h00000000;
            cipher_stage_word2_r  <= 32'h00000000;
            cipher_stage_word3_r  <= 32'h00000000;
            cipher_stage_valid_r  <= 4'b0000;
            cipher_pending_word_r <= 128'h0;
            cipher_pending_valid_r<= 1'b0;

            for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
                fifo_data_mem[i]        <= 32'h00000000;
                fifo_valid_bytes_mem[i] <= VALID_BYTES_ZERO;
                fifo_last_block_mem[i]  <= 1'b0;
                fifo_last_frame_mem[i]  <= 1'b0;
            end
        end
        else begin
            if (soft_reset_pulse_w) begin
                wr_ptr_r               <= {FIFO_PTR_WIDTH{1'b0}};
                rd_ptr_r               <= {FIFO_PTR_WIDTH{1'b0}};
                fifo_count_r           <= {FIFO_COUNT_WIDTH{1'b0}};
                block_done_sticky_r    <= 1'b0;
                frame_done_sticky_r    <= 1'b0;
                error_sticky_r         <= 1'b0;
                cipher_stage_word0_r   <= 32'h00000000;
                cipher_stage_word1_r   <= 32'h00000000;
                cipher_stage_word2_r   <= 32'h00000000;
                cipher_stage_word3_r   <= 32'h00000000;
                cipher_stage_valid_r   <= 4'b0000;
                cipher_pending_word_r  <= 128'h0;
                cipher_pending_valid_r <= 1'b0;
            end
            else begin
                if (control_write_ok_w) begin
                    if (PWDATA[1]) begin
                        block_done_sticky_r <= 1'b0;
                        frame_done_sticky_r <= 1'b0;
                    end

                    if (PWDATA[2])
                        error_sticky_r <= 1'b0;
                end

                if (rx_error_i)
                    error_sticky_r <= 1'b1;

                if (ctxt_w0_write_commit_w) begin
                    cipher_stage_word0_r <= PWDATA;
                    cipher_stage_valid_r[0] <= 1'b1;
                end

                if (ctxt_w1_write_commit_w) begin
                    cipher_stage_word1_r <= PWDATA;
                    cipher_stage_valid_r[1] <= 1'b1;
                end

                if (ctxt_w2_write_commit_w) begin
                    cipher_stage_word2_r <= PWDATA;
                    cipher_stage_valid_r[2] <= 1'b1;
                end

                if (ctxt_w3_write_commit_w) begin
                    cipher_stage_word3_r <= PWDATA;
                    cipher_stage_valid_r[3] <= 1'b1;
                end

                if (ctxt_start_write_ok_w) begin
                    cipher_pending_word_r <= {cipher_stage_word3_r,
                                              cipher_stage_word2_r,
                                              cipher_stage_word1_r,
                                              cipher_stage_word0_r};
                    cipher_pending_valid_r <= 1'b1;
                    cipher_stage_valid_r   <= 4'b0000;
                end

                if (ciphertext_word_fire_w)
                    cipher_pending_valid_r <= 1'b0;

                if (rx_push_w) begin
                    fifo_data_mem[wr_ptr_r]        <= rx_word_data_i;
                    fifo_valid_bytes_mem[wr_ptr_r] <= rx_word_valid_bytes_i;
                    fifo_last_block_mem[wr_ptr_r]  <= rx_word_last_in_block_i;
                    fifo_last_frame_mem[wr_ptr_r]  <= rx_word_last_in_frame_i;

                    if (rx_word_last_in_block_i)
                        block_done_sticky_r <= 1'b1;

                    if (rx_word_last_in_frame_i)
                        frame_done_sticky_r <= 1'b1;

                    if (rx_input_error_w)
                        error_sticky_r <= 1'b1;
                end

                case ({rx_push_w, read_rx_data_commit_w})
                    2'b10: begin
                        wr_ptr_r     <= wr_ptr_r + 1'b1;
                        fifo_count_r <= fifo_count_r + 1'b1;
                    end

                    2'b01: begin
                        rd_ptr_r     <= rd_ptr_r + 1'b1;
                        fifo_count_r <= fifo_count_r - 1'b1;
                    end

                    2'b11: begin
                        wr_ptr_r     <= wr_ptr_r + 1'b1;
                        rd_ptr_r     <= rd_ptr_r + 1'b1;
                        fifo_count_r <= fifo_count_r;
                    end

                    default: begin
                        wr_ptr_r     <= wr_ptr_r;
                        rd_ptr_r     <= rd_ptr_r;
                        fifo_count_r <= fifo_count_r;
                    end
                endcase

                if (invalid_write_commit_w)
                    error_sticky_r <= 1'b1;

                if (read_commit_w && PSLVERR)
                    error_sticky_r <= 1'b1;
            end
        end
    end

endmodule
