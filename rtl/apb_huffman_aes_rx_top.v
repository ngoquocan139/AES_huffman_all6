module apb_huffman_aes_rx_top #(
    parameter BLOCK_SIZE_WIDTH      = 6,
    parameter SYMBOL_WIDTH          = 8,
    parameter SYMBOL_COUNT_WIDTH    = 9,
    parameter CODE_LEN_WIDTH        = 5,
    parameter CODE_WIDTH            = 31,
    parameter CHUNK_DATA_WIDTH      = 32,
    parameter CHUNK_LEN_WIDTH       = 6,
    parameter MAX_SYMBOLS           = 256,
    parameter [7:0] ASCII_MIN       = 8'h20,
    parameter [7:0] ASCII_MAX       = 8'h7E,
    parameter TRANSPORT_WORD_WIDTH   = 128,
    parameter VALID_BITS_WIDTH       = 7,
    parameter [127:0] ROUND_KEY_10_FIXED = 128'h36D024461D84B8375FC0F9C04CBAB6BB
)(
    input  wire                         PCLK,
    input  wire                         PRESETn,
    input  wire                         rst_i,

    // --------------------------------------------------------------------
    // Ciphertext transport-word input stream
    // --------------------------------------------------------------------
    input  wire [127:0]                 ciphertext_word_in,
    input  wire                         ciphertext_word_valid,
    output wire                         ciphertext_word_ready,

    // --------------------------------------------------------------------
    // APB slave interface for RV32I CPU writes/reads
    // --------------------------------------------------------------------
    input  wire                         PSEL,
    input  wire                         PENABLE,
    input  wire                         PWRITE,
    input  wire [31:0]                  PADDR,
    input  wire [31:0]                  PWDATA,
    output wire [31:0]                  PRDATA,
    output wire                         PREADY,
    output wire                         PSLVERR,

    // --------------------------------------------------------------------
    // CBC IV from DMA register file. Must match the TX frame IV.
    // --------------------------------------------------------------------
    input  wire [127:0]                 cbc_iv_i,

    // --------------------------------------------------------------------
    // Top-level status
    // --------------------------------------------------------------------
    output wire                         rx_busy,
    output wire                         rx_done,
    output wire                         rx_error,
    output wire                         aes_ready_out,

    // --------------------------------------------------------------------
    // Optional per-stage status/debug
    // --------------------------------------------------------------------
    output wire                         depacker_busy,
    output wire                         depacker_done,
    output wire                         depacker_error,

    output wire                         parser_busy,
    output wire                         parser_block_done,
    output wire                         parser_frame_done,
    output wire                         parser_error,

    output wire                         decoder_busy,
    output wire                         decoder_block_done,
    output wire                         decoder_frame_done,
    output wire                         decoder_error,

    output wire                         word_packer_busy,
    output wire                         word_packer_block_done,
    output wire                         word_packer_frame_done,
    output wire                         word_packer_error,

    output wire [TRANSPORT_WORD_WIDTH-1:0] transport_word_dbg,
    output wire                            transport_word_valid_dbg,
    output wire [31:0]                     rx_word_dbg,
    output wire [2:0]                      rx_word_valid_bytes_dbg,
    output wire                            rx_word_last_in_block_dbg,
    output wire                            rx_word_last_in_frame_dbg,
    output wire                            rx_word_valid_dbg
);
    // --------------------------------------------------------------------
    // AES decrypt front-end
    // --------------------------------------------------------------------
    reg  [127:0] cipher_buf_data_r;
    reg          cipher_buf_valid_r;

    wire [127:0] aes_data_out_w;
    wire         aes_ready_w;
    wire         aes_output_capture_w;
    wire         ciphertext_word_fire_w;
    reg          aes_ready_dly_r;
    reg          aes_inflight_r;
    reg          aes_path_error_r;
    reg  [127:0] aes_current_cipher_r;
    reg  [127:0] rx_cbc_chain_r;
    reg          rx_cbc_active_r;

    wire         aes_wrapper_ready_w;
    wire         aes_block_accept_w;
    wire         decipher_en_w;
    wire [127:0] aes_data_in_w;
    wire [127:0] aes_round_key10_w;
    wire [127:0] rx_cbc_prev_w;
    wire [127:0] rx_plain_cbc_w;

    // --------------------------------------------------------------------
    // AES output buffer -> bit_depacker_128
    // --------------------------------------------------------------------
    reg  [TRANSPORT_WORD_WIDTH-1:0] transport_buf_data_r;
    reg                             transport_buf_valid_r;

    wire                            transport_buf_fire_w;
    wire                            transport_word_ready_w;

    // --------------------------------------------------------------------
    // bit_depacker_128 -> huffman_block_parser
    // --------------------------------------------------------------------
    wire [CHUNK_DATA_WIDTH-1:0]     depacker_stream_data_w;
    wire [CHUNK_LEN_WIDTH-1:0]      depacker_stream_len_w;
    wire                            depacker_stream_valid_w;
    wire                            depacker_stream_last_w;
    wire                            depacker_stream_ready_w;

    // --------------------------------------------------------------------
    // huffman_block_parser -> huffman_block_decoder
    // --------------------------------------------------------------------
    wire [1:0]                      parser_block_mode_w;
    wire [BLOCK_SIZE_WIDTH-1:0]     parser_block_size_w;
    wire [SYMBOL_COUNT_WIDTH-1:0]   parser_symbol_count_w;
    wire [SYMBOL_WIDTH-1:0]         parser_one_symbol_value_w;
    wire                            parser_block_meta_valid_w;
    wire                            parser_block_meta_ready_w;

    wire [SYMBOL_WIDTH-1:0]         parser_entry_symbol_w;
    wire [CODE_LEN_WIDTH-1:0]       parser_entry_code_len_w;
    wire                            parser_entry_valid_w;
    wire                            parser_entry_last_w;
    wire                            parser_entry_ready_w;

    wire [CHUNK_DATA_WIDTH-1:0]     parser_payload_window_data_w;
    wire [CHUNK_LEN_WIDTH-1:0]      parser_payload_window_len_w;
    wire                            parser_payload_window_valid_w;
    wire                            parser_payload_consume_valid_w;
    wire [CHUNK_LEN_WIDTH-1:0]      parser_payload_consume_len_w;
    wire                            parser_payload_block_done_w;

    // --------------------------------------------------------------------
    // huffman_block_decoder -> rx_byte_packer_32
    // --------------------------------------------------------------------
    wire [7:0]                      decoder_out_byte_w;
    wire                            decoder_out_valid_w;
    wire                            decoder_out_last_in_block_w;
    wire                            decoder_out_last_in_frame_w;
    wire                            decoder_out_ready_w;

    // --------------------------------------------------------------------
    // rx_byte_packer_32 -> apb_huffman_rx_if
    // --------------------------------------------------------------------
    wire [31:0]                     rx_word_data_w;
    wire [2:0]                      rx_word_valid_bytes_w;
    wire                            rx_word_last_in_block_w;
    wire                            rx_word_last_in_frame_w;
    wire                            rx_word_valid_w;
    wire                            rx_word_ready_w;
    wire [127:0]                    apb_ciphertext_word_w;
    wire                            apb_ciphertext_word_valid_w;
    wire                            apb_ciphertext_word_ready_w;
    wire [127:0]                    selected_ciphertext_word_w;
    wire                            selected_ciphertext_valid_w;
    wire                            ciphertext_source_ready_w;

    wire                            upstream_rx_error_w;

    assign aes_wrapper_ready_w  = aes_ready_w &&
                                   (!aes_inflight_r) &&
                                   (!transport_buf_valid_r) &&
                                   (!rx_error);

    assign ciphertext_source_ready_w = (!rx_error) &&
                                       ((!cipher_buf_valid_r) || aes_block_accept_w);

    assign selected_ciphertext_word_w  = apb_ciphertext_word_valid_w ?
                                         apb_ciphertext_word_w :
                                         ciphertext_word_in;
    assign selected_ciphertext_valid_w = apb_ciphertext_word_valid_w ?
                                         1'b1 :
                                         ciphertext_word_valid;
    assign apb_ciphertext_word_ready_w = ciphertext_source_ready_w &&
                                         apb_ciphertext_word_valid_w;
    assign ciphertext_word_ready       = ciphertext_source_ready_w &&
                                         (!apb_ciphertext_word_valid_w);

    assign ciphertext_word_fire_w      = selected_ciphertext_valid_w &&
                                         (apb_ciphertext_word_valid_w ?
                                          apb_ciphertext_word_ready_w :
                                          ciphertext_word_ready);

    assign aes_output_capture_w  = aes_inflight_r &&
                                   (!aes_ready_dly_r) &&
                                   aes_ready_w;

    assign transport_buf_fire_w  = transport_buf_valid_r && transport_word_ready_w;
    assign rx_cbc_prev_w         = rx_cbc_active_r ? rx_cbc_chain_r : cbc_iv_i;
    assign rx_plain_cbc_w        = aes_data_out_w ^ rx_cbc_prev_w;

    assign aes_ready_out         = aes_ready_w;

    always @(posedge PCLK) begin
        if (rst_i) begin
            cipher_buf_data_r    <= 128'b0;
            cipher_buf_valid_r   <= 1'b0;
            aes_ready_dly_r      <= 1'b1;
            aes_inflight_r       <= 1'b0;
            aes_path_error_r     <= 1'b0;
            aes_current_cipher_r <= 128'b0;
            transport_buf_data_r <= {TRANSPORT_WORD_WIDTH{1'b0}};
            transport_buf_valid_r<= 1'b0;
            rx_cbc_chain_r       <= 128'b0;
            rx_cbc_active_r      <= 1'b0;
        end
        else begin
            aes_ready_dly_r <= aes_ready_w;

            case ({ciphertext_word_fire_w, aes_block_accept_w})
                2'b10: begin
                    cipher_buf_data_r  <= selected_ciphertext_word_w;
                    cipher_buf_valid_r <= 1'b1;
                end

                2'b01: begin
                    cipher_buf_valid_r <= 1'b0;
                end

                2'b11: begin
                    cipher_buf_data_r  <= selected_ciphertext_word_w;
                    cipher_buf_valid_r <= 1'b1;
                end

                default: begin
                    cipher_buf_data_r  <= cipher_buf_data_r;
                    cipher_buf_valid_r <= cipher_buf_valid_r;
                end
            endcase

            if (aes_block_accept_w) begin
                aes_inflight_r <= 1'b1;
                aes_current_cipher_r <= cipher_buf_data_r;
            end

            if (aes_output_capture_w) begin
                if (transport_buf_valid_r && (!transport_buf_fire_w))
                    aes_path_error_r <= 1'b1;

                transport_buf_data_r  <= rx_plain_cbc_w;
                transport_buf_valid_r <= 1'b1;
                aes_inflight_r        <= 1'b0;
                rx_cbc_chain_r        <= aes_current_cipher_r;
                rx_cbc_active_r       <= 1'b1;
            end
            else if (transport_buf_fire_w) begin
                transport_buf_valid_r <= 1'b0;
            end

            if (word_packer_frame_done) begin
                rx_cbc_chain_r  <= 128'b0;
                rx_cbc_active_r <= 1'b0;
            end
        end
    end

    // --------------------------------------------------------------------
    // AES decrypt wrapper: mirrors TX-side wrapper behavior
    // and drives the inverse cipher core directly with a fixed round_key_10.
    // --------------------------------------------------------------------
    /* verilator lint_off PINCONNECTEMPTY */
    wrapper_rx #(
        .ROUND_KEY_10_FIXED (ROUND_KEY_10_FIXED)
    ) u_aes_input_wrapper_rx (
        .clk          (PCLK),
        .rst_n        (PRESETn),
        .block_in     (cipher_buf_data_r),
        .block_valid  (cipher_buf_valid_r),
        .aes_ready    (aes_wrapper_ready_w),
        .block_accept (aes_block_accept_w),
        .cipher_en    (),
        .decipher_en  (decipher_en_w),
        .chain_en     (),
        .data_in      (aes_data_in_w),
        .mode         (),
        .init_vector  (),
        .segment_len  (),
        .key          (),
        .round_key_10 (aes_round_key10_w)
    );
    /* verilator lint_on PINCONNECTEMPTY */

    // --------------------------------------------------------------------
    // AES decrypt core
    // --------------------------------------------------------------------
    aes128_cipher_inv_top u_AES_top_rx (
        .clk_sys        (PCLK),
        .rst_n          (PRESETn),
        .cipher_text    (aes_data_in_w),
        .round_key_10   (aes_round_key10_w),
        .decipher_en    (decipher_en_w),
        .plain_text     (aes_data_out_w),
        .decipher_ready (aes_ready_w)
    );

    // --------------------------------------------------------------------
    // Bit depacker
    // --------------------------------------------------------------------
    bit_depacker_128 #(
        .CHUNK_DATA_WIDTH     (CHUNK_DATA_WIDTH),
        .CHUNK_LEN_WIDTH      (CHUNK_LEN_WIDTH),
        .TRANSPORT_WORD_WIDTH (TRANSPORT_WORD_WIDTH),
        .VALID_BITS_WIDTH     (VALID_BITS_WIDTH)
    ) u_bit_depacker_128 (
        .clk                  (PCLK),
        .rst_n                (PRESETn),
        .transport_word_in    (transport_buf_data_r),
        .transport_word_valid (transport_buf_valid_r),
        .transport_word_ready (transport_word_ready_w),
        .stream_data          (depacker_stream_data_w),
        .stream_len           (depacker_stream_len_w),
        .stream_valid         (depacker_stream_valid_w),
        .stream_last          (depacker_stream_last_w),
        .stream_ready         (depacker_stream_ready_w),
        .busy                 (depacker_busy),
        .done                 (depacker_done),
        .error_flag           (depacker_error)
    );

    // --------------------------------------------------------------------
    // Huffman block parser
    // --------------------------------------------------------------------
    huffman_block_parser #(
        .STREAM_DATA_WIDTH    (CHUNK_DATA_WIDTH),
        .STREAM_LEN_WIDTH     (CHUNK_LEN_WIDTH),
        .BLOCK_SIZE_WIDTH     (BLOCK_SIZE_WIDTH),
        .SYMBOL_WIDTH         (SYMBOL_WIDTH),
        .SYMBOL_COUNT_WIDTH   (SYMBOL_COUNT_WIDTH),
        .CODE_LEN_WIDTH       (CODE_LEN_WIDTH),
        .ASCII_MIN            (ASCII_MIN),
        .ASCII_MAX            (ASCII_MAX)
    ) u_huffman_block_parser (
        .clk                  (PCLK),
        .rst_i                (rst_i),
        .stream_data          (depacker_stream_data_w),
        .stream_len           (depacker_stream_len_w),
        .stream_valid         (depacker_stream_valid_w),
        .stream_last          (depacker_stream_last_w),
        .stream_ready         (depacker_stream_ready_w),
        .block_mode           (parser_block_mode_w),
        .block_size           (parser_block_size_w),
        .symbol_count         (parser_symbol_count_w),
        .one_symbol_value     (parser_one_symbol_value_w),
        .block_meta_valid     (parser_block_meta_valid_w),
        .block_meta_ready     (parser_block_meta_ready_w),
        .entry_symbol         (parser_entry_symbol_w),
        .entry_code_len       (parser_entry_code_len_w),
        .entry_valid          (parser_entry_valid_w),
        .entry_last           (parser_entry_last_w),
        .entry_ready          (parser_entry_ready_w),
        .payload_window_data  (parser_payload_window_data_w),
        .payload_window_len   (parser_payload_window_len_w),
        .payload_window_valid (parser_payload_window_valid_w),
        .payload_consume_valid(parser_payload_consume_valid_w),
        .payload_consume_len  (parser_payload_consume_len_w),
        .payload_block_done   (parser_payload_block_done_w),
        .busy                 (parser_busy),
        .block_done           (parser_block_done),
        .frame_done           (parser_frame_done),
        .error_flag           (parser_error)
    );

    // --------------------------------------------------------------------
    // Huffman block decoder
    // --------------------------------------------------------------------
    huffman_block_decoder #(
        .STREAM_DATA_WIDTH    (CHUNK_DATA_WIDTH),
        .STREAM_LEN_WIDTH     (CHUNK_LEN_WIDTH),
        .BLOCK_SIZE_WIDTH     (BLOCK_SIZE_WIDTH),
        .SYMBOL_WIDTH         (SYMBOL_WIDTH),
        .SYMBOL_COUNT_WIDTH   (SYMBOL_COUNT_WIDTH),
        .CODE_LEN_WIDTH       (CODE_LEN_WIDTH),
        .CODE_WIDTH           (CODE_WIDTH),
        .MAX_SYMBOLS          (MAX_SYMBOLS),
        .ASCII_MIN            (ASCII_MIN),
        .ASCII_MAX            (ASCII_MAX)
    ) u_huffman_block_decoder (
        .clk                  (PCLK),
        .rst_i                (rst_i),
        .block_mode           (parser_block_mode_w),
        .block_size           (parser_block_size_w),
        .symbol_count         (parser_symbol_count_w),
        .one_symbol_value     (parser_one_symbol_value_w),
        .block_meta_valid     (parser_block_meta_valid_w),
        .block_meta_ready     (parser_block_meta_ready_w),
        .entry_symbol         (parser_entry_symbol_w),
        .entry_code_len       (parser_entry_code_len_w),
        .entry_valid          (parser_entry_valid_w),
        .entry_last           (parser_entry_last_w),
        .entry_ready          (parser_entry_ready_w),
        .payload_window_data  (parser_payload_window_data_w),
        .payload_window_len   (parser_payload_window_len_w),
        .payload_window_valid (parser_payload_window_valid_w),
        .payload_consume_valid(parser_payload_consume_valid_w),
        .payload_consume_len  (parser_payload_consume_len_w),
        .payload_block_done   (parser_payload_block_done_w),
        .parser_block_done    (parser_block_done),
        .parser_frame_done    (parser_frame_done),
        .out_byte             (decoder_out_byte_w),
        .out_valid            (decoder_out_valid_w),
        .out_last_in_block    (decoder_out_last_in_block_w),
        .out_last_in_frame    (decoder_out_last_in_frame_w),
        .out_ready            (decoder_out_ready_w),
        .busy                 (decoder_busy),
        .block_done           (decoder_block_done),
        .frame_done           (decoder_frame_done),
        .error_flag           (decoder_error)
    );

    // --------------------------------------------------------------------
    // RX byte packer
    // --------------------------------------------------------------------
    rx_byte_packer_32 u_rx_byte_packer_32 (
        .clk                  (PCLK),
        .rst_n                (PRESETn),
        .in_byte              (decoder_out_byte_w),
        .in_valid             (decoder_out_valid_w),
        .in_last_in_block     (decoder_out_last_in_block_w),
        .in_last_in_frame     (decoder_out_last_in_frame_w),
        .in_ready             (decoder_out_ready_w),
        .word_data            (rx_word_data_w),
        .word_valid_bytes     (rx_word_valid_bytes_w),
        .word_last_in_block   (rx_word_last_in_block_w),
        .word_last_in_frame   (rx_word_last_in_frame_w),
        .word_valid           (rx_word_valid_w),
        .word_ready           (rx_word_ready_w),
        .busy                 (word_packer_busy),
        .block_done           (word_packer_block_done),
        .frame_done           (word_packer_frame_done),
        .error_flag           (word_packer_error)
    );

    // --------------------------------------------------------------------
    // APB RX interface
    // --------------------------------------------------------------------
    assign upstream_rx_error_w = aes_path_error_r ||
                                 depacker_error ||
                                 parser_error ||
                                 decoder_error ||
                                 word_packer_error;

    apb_huffman_rx_if u_apb_huffman_rx_if (
        .PCLK                    (PCLK),
        .PRESETn                 (PRESETn),
        .PSEL                    (PSEL),
        .PENABLE                 (PENABLE),
        .PWRITE                  (PWRITE),
        .PADDR                   (PADDR),
        .PWDATA                  (PWDATA),
        .PRDATA                  (PRDATA),
        .PREADY                  (PREADY),
        .PSLVERR                 (PSLVERR),
        .ciphertext_word_o       (apb_ciphertext_word_w),
        .ciphertext_word_valid_o (apb_ciphertext_word_valid_w),
        .ciphertext_word_ready_i (apb_ciphertext_word_ready_w),
        .rx_word_data_i          (rx_word_data_w),
        .rx_word_valid_bytes_i   (rx_word_valid_bytes_w),
        .rx_word_last_in_block_i (rx_word_last_in_block_w),
        .rx_word_last_in_frame_i (rx_word_last_in_frame_w),
        .rx_word_valid_i         (rx_word_valid_w),
        .rx_word_ready_o         (rx_word_ready_w),
        .rx_error_i              (upstream_rx_error_w)
    );

    // --------------------------------------------------------------------
    // Top-level status/debug exports
    // --------------------------------------------------------------------
    assign rx_busy                  = cipher_buf_valid_r ||
                                      apb_ciphertext_word_valid_w ||
                                      aes_inflight_r ||
                                      transport_buf_valid_r ||
                                      depacker_busy ||
                                      parser_busy ||
                                      decoder_busy ||
                                      word_packer_busy;

    assign rx_done                  = word_packer_frame_done;
    assign rx_error                 = upstream_rx_error_w;

    assign transport_word_dbg       = transport_buf_data_r;
    assign transport_word_valid_dbg = transport_buf_valid_r;

    assign rx_word_dbg              = rx_word_data_w;
    assign rx_word_valid_bytes_dbg  = rx_word_valid_bytes_w;
    assign rx_word_last_in_block_dbg= rx_word_last_in_block_w;
    assign rx_word_last_in_frame_dbg= rx_word_last_in_frame_w;
    assign rx_word_valid_dbg        = rx_word_valid_w;

endmodule
