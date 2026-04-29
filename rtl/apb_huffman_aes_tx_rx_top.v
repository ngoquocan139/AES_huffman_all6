module apb_huffman_aes_tx_rx_top #(
    parameter BLOCK_SIZE_WIDTH           = 6,
    parameter BUFFER_ADDR_WIDTH          = 5,
    parameter SYMBOL_WIDTH               = 8,
    parameter SYMBOL_COUNT_WIDTH         = 6,
    parameter COUNT_WIDTH                = 6,
    parameter SYMBOL_INDEX_WIDTH         = 7,
    parameter CODE_LEN_WIDTH             = 5,
    parameter CODE_WIDTH                 = 31,
    parameter HEADER_BITS_WIDTH          = 10,
    parameter TOTAL_BITS_WIDTH           = 11,
    parameter CHUNK_DATA_WIDTH           = 32,
    parameter CHUNK_LEN_WIDTH            = 6,
    parameter MAX_SYMBOLS_PER_BLOCK      = 32,
    parameter MAX_TREE_NODES             = 63,
    parameter [7:0] ASCII_MIN            = 8'h20,
    parameter [7:0] ASCII_MAX            = 8'h7E,
    parameter TRANSPORT_WORD_WIDTH       = 128,
    parameter VALID_BITS_WIDTH           = 7,
    parameter [127:0] AES_KEY_FIXED      = 128'h00112233445566778899AABBCCDDEEFF,
    parameter [127:0] ROUND_KEY_10_FIXED = 128'h36D024461D84B8375FC0F9C04CBAB6BB,
    parameter integer BRIDGE_FIFO_DEPTH  = 16,
    parameter integer BRIDGE_FIFO_PTR_WIDTH = 4,
    parameter integer BRIDGE_FIFO_COUNT_WIDTH = 5
)(
    input  wire                              PCLK,
    input  wire                              PRESETn,

    // TX-side APB slave
    input  wire                              tx_PSEL,
    input  wire                              tx_PENABLE,
    input  wire                              tx_PWRITE,
    input  wire [31:0]                       tx_PADDR,
    input  wire [31:0]                       tx_PWDATA,
    output wire [31:0]                       tx_PRDATA,
    output wire                              tx_PREADY,
    output wire                              tx_PSLVERR,

    // RX-side APB slave
    input  wire                              rx_PSEL,
    input  wire                              rx_PENABLE,
    input  wire                              rx_PWRITE,
    input  wire [31:0]                       rx_PADDR,
    input  wire [31:0]                       rx_PWDATA,
    output wire [31:0]                       rx_PRDATA,
    output wire                              rx_PREADY,
    output wire                              rx_PSLVERR,

    // TX top status
    output wire                              tx_busy,
    output wire                              tx_done,
    output wire                              tx_error,
    output wire                              tx_encoder_busy,
    output wire                              tx_encoder_done,
    output wire                              tx_encoder_error,
    output wire [1:0]                        tx_selected_mode_out,
    output wire [3:0]                        tx_fsm_state,
    output wire                              tx_packer_busy,
    output wire                              tx_packer_done,
    output wire                              tx_packer_error,

    // RX top status
    output wire                              rx_busy,
    output wire                              rx_done,
    output wire                              rx_error,
    output wire                              rx_depacker_busy,
    output wire                              rx_depacker_done,
    output wire                              rx_depacker_error,
    output wire                              rx_parser_busy,
    output wire                              rx_parser_block_done,
    output wire                              rx_parser_frame_done,
    output wire                              rx_parser_error,
    output wire                              rx_decoder_busy,
    output wire                              rx_decoder_block_done,
    output wire                              rx_decoder_frame_done,
    output wire                              rx_decoder_error,
    output wire                              rx_word_packer_busy,
    output wire                              rx_word_packer_block_done,
    output wire                              rx_word_packer_frame_done,
    output wire                              rx_word_packer_error,

    // Internal TX->RX ciphertext bridge status/debug
    output wire                              bridge_nonempty,
    output wire                              bridge_full,
    output wire [BRIDGE_FIFO_COUNT_WIDTH-1:0] bridge_level,
    output wire                              bridge_error,
    output wire [TRANSPORT_WORD_WIDTH-1:0]   bridge_head_word_dbg,
    output wire                              bridge_word_valid_dbg,

    // Optional forwarded debug
    output wire [TRANSPORT_WORD_WIDTH-1:0]   tx_aes_data_out_dbg,
    output wire                              tx_aes_ready_out_dbg,
    output wire                              tx_cipher_en_dbg,
    output wire                              rx_ciphertext_word_ready_dbg
);

    localparam [31:0] TX_ADDR_CONTROL = 32'h0000_0010;
    localparam [31:0] RX_ADDR_CONTROL = 32'h0000_000C;

    function [BRIDGE_FIFO_COUNT_WIDTH-1:0] bridge_count_const;
        input integer value_in;
        integer bit_idx;
        begin
            bridge_count_const = {BRIDGE_FIFO_COUNT_WIDTH{1'b0}};
            for (bit_idx = 0; bit_idx < BRIDGE_FIFO_COUNT_WIDTH; bit_idx = bit_idx + 1)
                bridge_count_const[bit_idx] = value_in[bit_idx];
        end
    endfunction

    function [BRIDGE_FIFO_PTR_WIDTH-1:0] bridge_ptr_const;
        input integer value_in;
        integer bit_idx;
        begin
            bridge_ptr_const = {BRIDGE_FIFO_PTR_WIDTH{1'b0}};
            for (bit_idx = 0; bit_idx < BRIDGE_FIFO_PTR_WIDTH; bit_idx = bit_idx + 1)
                bridge_ptr_const[bit_idx] = value_in[bit_idx];
        end
    endfunction

    function [BRIDGE_FIFO_PTR_WIDTH-1:0] bridge_ptr_inc;
        input [BRIDGE_FIFO_PTR_WIDTH-1:0] ptr_in;
        begin
            if (ptr_in == bridge_ptr_const(BRIDGE_FIFO_DEPTH - 1))
                bridge_ptr_inc = {BRIDGE_FIFO_PTR_WIDTH{1'b0}};
            else
                bridge_ptr_inc = ptr_in + {{(BRIDGE_FIFO_PTR_WIDTH-1){1'b0}}, 1'b1};
        end
    endfunction

    localparam [BRIDGE_FIFO_COUNT_WIDTH-1:0] BRIDGE_FIFO_DEPTH_COUNT =
        bridge_count_const(BRIDGE_FIFO_DEPTH);

    reg  [TRANSPORT_WORD_WIDTH-1:0]          bridge_fifo_mem [0:BRIDGE_FIFO_DEPTH-1];
    reg  [BRIDGE_FIFO_PTR_WIDTH-1:0]         bridge_wr_ptr_r;
    reg  [BRIDGE_FIFO_PTR_WIDTH-1:0]         bridge_rd_ptr_r;
    reg  [BRIDGE_FIFO_COUNT_WIDTH-1:0]       bridge_count_r;
    reg                                      bridge_error_r;
    reg                                      tx_aes_ready_dly_r;
    reg                                      tx_cipher_inflight_r;

    wire [TRANSPORT_WORD_WIDTH-1:0]          tx_aes_data_out_w;
    wire                                     tx_aes_ready_out_w;
    wire                                     tx_cipher_en_dbg_w;
    wire                                     rx_ciphertext_word_ready_w;

    wire                                     bridge_empty_w;
    wire                                     bridge_full_w;
    wire [TRANSPORT_WORD_WIDTH-1:0]          bridge_head_word_w;
    wire                                     bridge_word_valid_w;
    wire                                     bridge_pop_w;
    wire                                     bridge_capture_w;
    wire                                     bridge_push_w;

    wire                                     tx_apb_write_fire_w;
    wire                                     rx_apb_write_fire_w;
    wire                                     tx_bridge_soft_reset_w;
    wire                                     tx_bridge_clear_error_w;
    wire                                     rx_bridge_soft_reset_w;
    wire                                     rx_bridge_clear_error_w;
    wire                                     bridge_soft_reset_w;
    wire                                     bridge_clear_error_w;

    integer i;

    assign bridge_empty_w      = (bridge_count_r == {BRIDGE_FIFO_COUNT_WIDTH{1'b0}});
    assign bridge_full_w       = (bridge_count_r == BRIDGE_FIFO_DEPTH_COUNT);
    assign bridge_head_word_w  = bridge_fifo_mem[bridge_rd_ptr_r];
    assign bridge_word_valid_w = !bridge_empty_w;
    assign bridge_pop_w        = bridge_word_valid_w && rx_ciphertext_word_ready_w;

    assign bridge_capture_w    = tx_cipher_inflight_r &&
                                 (!tx_aes_ready_dly_r) &&
                                 tx_aes_ready_out_w;
    assign bridge_push_w       = bridge_capture_w &&
                                 ((!bridge_full_w) || bridge_pop_w);

    assign tx_apb_write_fire_w = tx_PSEL && tx_PENABLE && tx_PWRITE && tx_PREADY && (!tx_PSLVERR);
    assign rx_apb_write_fire_w = rx_PSEL && rx_PENABLE && rx_PWRITE && rx_PREADY && (!rx_PSLVERR);

    assign tx_bridge_soft_reset_w  = tx_apb_write_fire_w &&
                                     (tx_PADDR == TX_ADDR_CONTROL) &&
                                     tx_PWDATA[0];
    assign tx_bridge_clear_error_w = tx_apb_write_fire_w &&
                                     (tx_PADDR == TX_ADDR_CONTROL) &&
                                     tx_PWDATA[2];
    assign rx_bridge_soft_reset_w  = rx_apb_write_fire_w &&
                                     (rx_PADDR == RX_ADDR_CONTROL) &&
                                     rx_PWDATA[0];
    assign rx_bridge_clear_error_w = rx_apb_write_fire_w &&
                                     (rx_PADDR == RX_ADDR_CONTROL) &&
                                     rx_PWDATA[2];

    assign bridge_soft_reset_w  = tx_bridge_soft_reset_w || rx_bridge_soft_reset_w;
    assign bridge_clear_error_w = tx_bridge_clear_error_w || rx_bridge_clear_error_w;

    assign bridge_nonempty          = !bridge_empty_w;
    assign bridge_full              = bridge_full_w;
    assign bridge_level             = bridge_count_r;
    assign bridge_error             = bridge_error_r;
    assign bridge_head_word_dbg     = bridge_empty_w ?
                                      {TRANSPORT_WORD_WIDTH{1'b0}} :
                                      bridge_head_word_w;
    assign bridge_word_valid_dbg    = bridge_word_valid_w;
    assign tx_aes_data_out_dbg      = tx_aes_data_out_w;
    assign tx_aes_ready_out_dbg     = tx_aes_ready_out_w;
    assign tx_cipher_en_dbg         = tx_cipher_en_dbg_w;
    assign rx_ciphertext_word_ready_dbg = rx_ciphertext_word_ready_w;

    /* verilator lint_off PINCONNECTEMPTY */
    apb_huffman_aes_tx_top #(
        .BLOCK_SIZE_WIDTH      (BLOCK_SIZE_WIDTH),
        .BUFFER_ADDR_WIDTH     (BUFFER_ADDR_WIDTH),
        .SYMBOL_WIDTH          (SYMBOL_WIDTH),
        .SYMBOL_COUNT_WIDTH    (SYMBOL_COUNT_WIDTH),
        .COUNT_WIDTH           (COUNT_WIDTH),
        .SYMBOL_INDEX_WIDTH    (SYMBOL_INDEX_WIDTH),
        .CODE_LEN_WIDTH        (CODE_LEN_WIDTH),
        .CODE_WIDTH            (CODE_WIDTH),
        .HEADER_BITS_WIDTH     (HEADER_BITS_WIDTH),
        .TOTAL_BITS_WIDTH      (TOTAL_BITS_WIDTH),
        .CHUNK_DATA_WIDTH      (CHUNK_DATA_WIDTH),
        .CHUNK_LEN_WIDTH       (CHUNK_LEN_WIDTH),
        .MAX_SYMBOLS_PER_BLOCK (MAX_SYMBOLS_PER_BLOCK),
        .MAX_TREE_NODES        (MAX_TREE_NODES),
        .ASCII_MIN             (ASCII_MIN),
        .ASCII_MAX             (ASCII_MAX),
        .TRANSPORT_WORD_WIDTH  (TRANSPORT_WORD_WIDTH),
        .VALID_BITS_WIDTH      (VALID_BITS_WIDTH),
        .AES_KEY_FIXED         (AES_KEY_FIXED)
    ) u_tx_top (
        .PCLK                    (PCLK),
        .PRESETn                 (PRESETn),
        .PSEL                    (tx_PSEL),
        .PENABLE                 (tx_PENABLE),
        .PWRITE                  (tx_PWRITE),
        .PADDR                   (tx_PADDR),
        .PWDATA                  (tx_PWDATA),
        .PRDATA                  (tx_PRDATA),
        .PREADY                  (tx_PREADY),
        .PSLVERR                 (tx_PSLVERR),
        .cbc_iv_i                (128'b0),
        .aes_data_out            (tx_aes_data_out_w),
        .aes_ready_out           (tx_aes_ready_out_w),
        .tx_busy                 (tx_busy),
        .tx_done                 (tx_done),
        .tx_error                (tx_error),
        .encoder_busy            (tx_encoder_busy),
        .encoder_done            (tx_encoder_done),
        .encoder_error           (tx_encoder_error),
        .selected_mode_out       (tx_selected_mode_out),
        .fsm_state               (tx_fsm_state),
        .packer_busy             (tx_packer_busy),
        .packer_done             (tx_packer_done),
        .packer_error            (tx_packer_error),
        .transport_word_dbg      (),
        .transport_word_valid_dbg(),
        .adapter_error_dbg       (),
        .apb_start_block_dbg     (),
        .apb_block_size_dbg      (),
        .apb_word_in_dbg         (),
        .apb_word_valid_dbg      (),
        .apb_word_ready_dbg      (),
        .cipher_en_dbg           (tx_cipher_en_dbg_w),
        .decipher_en_dbg         (),
        .chain_en_dbg            (),
        .data_in_dbg             (),
        .key_dbg                 (),
        .mode_dbg                (),
        .init_vector_dbg         (),
        .segment_len_dbg         ()
    );

    apb_huffman_aes_rx_top #(
        .BLOCK_SIZE_WIDTH      (BLOCK_SIZE_WIDTH),
        .SYMBOL_WIDTH          (SYMBOL_WIDTH),
        .SYMBOL_COUNT_WIDTH    (SYMBOL_COUNT_WIDTH),
        .CODE_LEN_WIDTH        (CODE_LEN_WIDTH),
        .CODE_WIDTH            (CODE_WIDTH),
        .CHUNK_DATA_WIDTH      (CHUNK_DATA_WIDTH),
        .CHUNK_LEN_WIDTH       (CHUNK_LEN_WIDTH),
        .MAX_SYMBOLS           (MAX_SYMBOLS_PER_BLOCK),
        .ASCII_MIN             (ASCII_MIN),
        .ASCII_MAX             (ASCII_MAX),
        .TRANSPORT_WORD_WIDTH  (TRANSPORT_WORD_WIDTH),
        .VALID_BITS_WIDTH      (VALID_BITS_WIDTH),
        .ROUND_KEY_10_FIXED    (ROUND_KEY_10_FIXED)
    ) u_rx_top (
        .PCLK                    (PCLK),
        .PRESETn                 (PRESETn),
        .rst_i                   (!PRESETn),
        .ciphertext_word_in      (bridge_head_word_w),
        .ciphertext_word_valid   (bridge_word_valid_w),
        .ciphertext_word_ready   (rx_ciphertext_word_ready_w),
        .PSEL                    (rx_PSEL),
        .PENABLE                 (rx_PENABLE),
        .PWRITE                  (rx_PWRITE),
        .PADDR                   (rx_PADDR),
        .PWDATA                  (rx_PWDATA),
        .PRDATA                  (rx_PRDATA),
        .PREADY                  (rx_PREADY),
        .PSLVERR                 (rx_PSLVERR),
        .cbc_iv_i                (128'b0),
        .rx_busy                 (rx_busy),
        .rx_done                 (rx_done),
        .rx_error                (rx_error),
        .aes_ready_out           (),
        .depacker_busy           (rx_depacker_busy),
        .depacker_done           (rx_depacker_done),
        .depacker_error          (rx_depacker_error),
        .parser_busy             (rx_parser_busy),
        .parser_block_done       (rx_parser_block_done),
        .parser_frame_done       (rx_parser_frame_done),
        .parser_error            (rx_parser_error),
        .decoder_busy            (rx_decoder_busy),
        .decoder_block_done      (rx_decoder_block_done),
        .decoder_frame_done      (rx_decoder_frame_done),
        .decoder_error           (rx_decoder_error),
        .word_packer_busy        (rx_word_packer_busy),
        .word_packer_block_done  (rx_word_packer_block_done),
        .word_packer_frame_done  (rx_word_packer_frame_done),
        .word_packer_error       (rx_word_packer_error),
        .transport_word_dbg      (),
        .transport_word_valid_dbg(),
        .rx_word_dbg             (),
        .rx_word_valid_bytes_dbg (),
        .rx_word_last_in_block_dbg(),
        .rx_word_last_in_frame_dbg(),
        .rx_word_valid_dbg       ()
    );
    /* verilator lint_on PINCONNECTEMPTY */

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            bridge_wr_ptr_r      <= {BRIDGE_FIFO_PTR_WIDTH{1'b0}};
            bridge_rd_ptr_r      <= {BRIDGE_FIFO_PTR_WIDTH{1'b0}};
            bridge_count_r       <= {BRIDGE_FIFO_COUNT_WIDTH{1'b0}};
            bridge_error_r       <= 1'b0;
            tx_aes_ready_dly_r   <= 1'b1;
            tx_cipher_inflight_r <= 1'b0;

            for (i = 0; i < BRIDGE_FIFO_DEPTH; i = i + 1)
                bridge_fifo_mem[i] <= {TRANSPORT_WORD_WIDTH{1'b0}};
        end
        else begin
            tx_aes_ready_dly_r <= tx_aes_ready_out_w;

            if (bridge_soft_reset_w) begin
                bridge_wr_ptr_r      <= {BRIDGE_FIFO_PTR_WIDTH{1'b0}};
                bridge_rd_ptr_r      <= {BRIDGE_FIFO_PTR_WIDTH{1'b0}};
                bridge_count_r       <= {BRIDGE_FIFO_COUNT_WIDTH{1'b0}};
                bridge_error_r       <= 1'b0;
                tx_cipher_inflight_r <= 1'b0;
            end
            else begin
                if (bridge_clear_error_w)
                    bridge_error_r <= 1'b0;

                if (tx_cipher_en_dbg_w && tx_cipher_inflight_r && (!bridge_capture_w))
                    bridge_error_r <= 1'b1;

                case ({tx_cipher_en_dbg_w, bridge_capture_w})
                    2'b10: tx_cipher_inflight_r <= 1'b1;
                    2'b01: tx_cipher_inflight_r <= 1'b0;
                    2'b11: tx_cipher_inflight_r <= 1'b1;
                    default: tx_cipher_inflight_r <= tx_cipher_inflight_r;
                endcase

                if (bridge_capture_w) begin
                    if (bridge_push_w)
                        bridge_fifo_mem[bridge_wr_ptr_r] <= tx_aes_data_out_w;
                    else
                        bridge_error_r <= 1'b1;
                end

                case ({bridge_push_w, bridge_pop_w})
                    2'b10: begin
                        bridge_wr_ptr_r <= bridge_ptr_inc(bridge_wr_ptr_r);
                        bridge_count_r  <= bridge_count_r +
                                           {{(BRIDGE_FIFO_COUNT_WIDTH-1){1'b0}}, 1'b1};
                    end

                    2'b01: begin
                        bridge_rd_ptr_r <= bridge_ptr_inc(bridge_rd_ptr_r);
                        bridge_count_r  <= bridge_count_r -
                                           {{(BRIDGE_FIFO_COUNT_WIDTH-1){1'b0}}, 1'b1};
                    end

                    2'b11: begin
                        bridge_wr_ptr_r <= bridge_ptr_inc(bridge_wr_ptr_r);
                        bridge_rd_ptr_r <= bridge_ptr_inc(bridge_rd_ptr_r);
                    end

                    default: begin
                        bridge_wr_ptr_r <= bridge_wr_ptr_r;
                        bridge_rd_ptr_r <= bridge_rd_ptr_r;
                        bridge_count_r  <= bridge_count_r;
                    end
                endcase
            end
        end
    end

endmodule
