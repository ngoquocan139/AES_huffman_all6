module huffman_aes_tx_top #(
    // --------------------------------------------------------------------
    // Encoder parameters
    // --------------------------------------------------------------------
    parameter BLOCK_SIZE_WIDTH      = 6,
    parameter BUFFER_ADDR_WIDTH     = 5,
    parameter SYMBOL_WIDTH          = 8,
    parameter SYMBOL_COUNT_WIDTH    = 9,
    parameter COUNT_WIDTH           = 6,
    parameter SYMBOL_INDEX_WIDTH    = 8,
    parameter CODE_LEN_WIDTH        = 5,
    parameter CODE_WIDTH            = 13,
    parameter HEADER_BITS_WIDTH     = 12,
    parameter TOTAL_BITS_WIDTH      = 16,
    parameter CHUNK_DATA_WIDTH      = 32,
    parameter CHUNK_LEN_WIDTH       = 6,
    parameter MAX_SYMBOLS_PER_BLOCK = 32,
    parameter MAX_TREE_NODES        = 63,
    parameter [7:0] ASCII_MIN       = 8'h20,
    parameter [7:0] ASCII_MAX       = 8'h7E,

    // --------------------------------------------------------------------
    // Bit packer / AES wrapper parameters
    // --------------------------------------------------------------------
    parameter TRANSPORT_WORD_WIDTH  = 128,
    parameter VALID_BITS_WIDTH      = 7,
    parameter [127:0] AES_KEY_FIXED = 128'h00112233445566778899AABBCCDDEEFF
)(
    input  wire                          clk,
    input  wire                          rst_n,

    // --------------------------------------------------------------------
    // Block input from controller / APB wrapper
    // start_block is a one-cycle pulse for a new block.
    // continue_frame = 1 means another Huffman block will follow in the
    // same AES frame, so the bit packer must not flush on this block end.
    // block_size is the number of valid bytes in this block: 1..32.
    // --------------------------------------------------------------------
    input  wire                          start_block,
    input  wire                          continue_frame,
    input  wire                          whole_file_enable,
    input  wire                          whole_file_count_mode,
    input  wire                          global_clear,
    input  wire                          global_build_start,
    input  wire [BLOCK_SIZE_WIDTH-1:0]   block_size,

    // --------------------------------------------------------------------
    // 32-bit word stream input
    // word_in[7:0]   = first byte
    // word_in[15:8]  = second byte
    // word_in[23:16] = third byte
    // word_in[31:24] = fourth byte
    // --------------------------------------------------------------------
    input  wire [31:0]                   word_in,
    input  wire                          word_valid,
    output wire                          word_ready,

    // --------------------------------------------------------------------
    // AES core ready input
    // --------------------------------------------------------------------
    input  wire                          aes_ready,

    // --------------------------------------------------------------------
    // AES IP input-side outputs
    // --------------------------------------------------------------------
    output wire                          block_accept,
    output wire                          cipher_en,
    output wire                          decipher_en,
    output wire                          chain_en,
    output wire [127:0]                  data_in,
    output wire [3:0]                    mode,
    output wire [127:0]                  init_vector,
    output wire [15:0]                   segment_len,
    output wire [127:0]                  key,

    // --------------------------------------------------------------------
    // Top-level status
    // tx_done means:
    // - if continue_frame = 1 for this block:
    //     encoder finished current block and handed all bits to the packer
    // - otherwise:
    //     bit_packer finished the current AES frame and the final transport
    //     word was accepted by aes_input_wrapper
    // It does NOT mean AES output ciphertext is finished.
    // --------------------------------------------------------------------
    output wire                          tx_busy,
    output wire                          tx_done,
    output wire                          tx_error,
    output wire                          global_build_busy,
    output wire                          global_build_done,
    output wire                          global_build_error,
    output wire                          global_table_valid,
    output wire [SYMBOL_COUNT_WIDTH-1:0] global_symbol_count,

    // --------------------------------------------------------------------
    // Optional debug / visibility
    // --------------------------------------------------------------------
    output wire                          encoder_busy,
    output wire                          encoder_done,
    output wire                          encoder_error,
    output wire [1:0]                    selected_mode_out,
    output wire [3:0]                    fsm_state,

    output wire                          packer_busy,
    output wire                          packer_done,
    output wire                          packer_error,
    output wire [TRANSPORT_WORD_WIDTH-1:0] transport_word_dbg,
    output wire                          transport_word_valid_dbg,

    output wire                          adapter_error_dbg
);

    // --------------------------------------------------------------------
    // Internal interconnect: adapter -> dynamic_huffman_encoder
    // --------------------------------------------------------------------
    localparam integer HUFFMAN_ALPHABET_SIZE = 256;
    localparam integer FILE_COUNT_WIDTH      = 16;
    localparam integer FILE_MAX_SYMBOLS      = 256;
    localparam integer FILE_MAX_TREE_NODES   = 511;

    wire                          enc_start_block_w;
    wire [SYMBOL_WIDTH-1:0]       enc_byte_in_w;
    wire                          enc_byte_valid_w;
    wire                          enc_block_start_w;
    wire                          enc_block_end_w;
    wire                          enc_byte_ready_w;
    wire                          count_byte_valid_w;
    wire                          count_byte_fire_w;
    wire                          file_count_clear_w;
    wire                          file_count_overflow_w;
    wire [SYMBOL_WIDTH-1:0]       file_normalized_byte_w;
    wire [SYMBOL_INDEX_WIDTH-1:0] file_symbol_index_w;
    wire [SYMBOL_INDEX_WIDTH-1:0] file_freq_read_index_w;
    wire [FILE_COUNT_WIDTH-1:0]   file_freq_read_count_w;
    wire [SYMBOL_COUNT_WIDTH-1:0] file_symbol_count_w;
    wire [SYMBOL_COUNT_WIDTH-1:0] file_symbol_read_addr_w;
    wire [SYMBOL_WIDTH-1:0]       file_symbol_read_data_w;
    wire [SYMBOL_INDEX_WIDTH-1:0] file_code_len_read_index_w;
    wire [CODE_LEN_WIDTH-1:0]     file_code_len_read_data_w;
    wire [SYMBOL_INDEX_WIDTH-1:0] file_code_read_index_w;
    wire [CODE_WIDTH-1:0]         file_code_read_data_w;
    wire                          file_build_busy_w;
    wire                          file_build_done_w;
    wire                          file_build_error_w;

    // --------------------------------------------------------------------
    // Internal interconnect: encoder -> bit_packer
    // --------------------------------------------------------------------
    wire [CHUNK_DATA_WIDTH-1:0]   encoder_stream_data;
    wire [CHUNK_LEN_WIDTH-1:0]    encoder_stream_len;
    wire                          encoder_stream_valid;
    wire                          encoder_stream_last;
    wire                          encoder_stream_ready;

    // --------------------------------------------------------------------
    // Internal interconnect: bit_packer -> aes_input_wrapper
    // --------------------------------------------------------------------
    wire [TRANSPORT_WORD_WIDTH-1:0] packer_transport_word;
    wire                            packer_transport_valid;
    wire                            packer_transport_ready;

    // --------------------------------------------------------------------
    // Adapter state: 32-bit word -> byte stream
    // --------------------------------------------------------------------
    reg  [31:0]                    word_buf_r;
    reg                            word_buf_valid_r;
    reg  [2:0]                     word_buf_bytes_valid_r; // 1..4
    reg  [1:0]                     byte_index_r;

    reg  [BLOCK_SIZE_WIDTH-1:0]    bytes_total_r;
    reg  [BLOCK_SIZE_WIDTH-1:0]    bytes_queued_r;  // bytes accepted from word side
    reg  [BLOCK_SIZE_WIDTH-1:0]    bytes_sent_r;    // bytes accepted by encoder
    reg                            block_active_r;
    reg                            start_pending_r;
    reg                            first_byte_pending_r;
    reg                            flush_on_block_end_r;
    reg                            adapter_error_r;
    reg                            count_mode_active_r;
    reg                            count_done_r;
    reg                            global_table_valid_r;
    reg                            global_emit_table_pending_r;

    wire [7:0]                     current_byte_w;
    wire                           current_byte_fire_w;
    wire                           current_word_last_byte_w;
    wire                           can_start_block_w;
    wire                           packer_flush_on_last_w;
    wire [BLOCK_SIZE_WIDTH-1:0]    bytes_remaining_to_queue_w;
    wire [2:0]                     next_word_bytes_valid_w;
    wire                           block_core_busy_w;
    wire                           frame_flush_busy_w;
    wire                           unused_file_debug_w;

    // --------------------------------------------------------------------
    // Helper: select current byte from buffered 32-bit word
    // --------------------------------------------------------------------
    function [7:0] select_word_byte;
        input [31:0] word_val;
        input [1:0]  idx;
        begin
            case (idx)
                2'd0: select_word_byte = word_val[7:0];
                2'd1: select_word_byte = word_val[15:8];
                2'd2: select_word_byte = word_val[23:16];
                default: select_word_byte = word_val[31:24];
            endcase
        end
    endfunction

    assign current_byte_w = select_word_byte(word_buf_r, byte_index_r);
    assign current_word_last_byte_w =
        ({1'b0, byte_index_r} == (word_buf_bytes_valid_r - 3'd1));
    assign count_byte_valid_w  = word_buf_valid_r && (!start_pending_r) &&
                                 (!adapter_error_r) && count_mode_active_r;
    assign count_byte_fire_w   = count_byte_valid_w;
    assign current_byte_fire_w = count_mode_active_r ? count_byte_fire_w :
                                                       (enc_byte_valid_w && enc_byte_ready_w);

    assign bytes_remaining_to_queue_w = bytes_total_r - bytes_queued_r;
    assign next_word_bytes_valid_w    = (bytes_remaining_to_queue_w >= 6'd4) ? 3'd4
                                                                              : bytes_remaining_to_queue_w[2:0];

    // New block collection only depends on the block-local path being idle.
    // The packer may still hold a partially filled frame from prior blocks.
    assign can_start_block_w =
        (!block_active_r) &&
        (!word_buf_valid_r) &&
        (!start_pending_r) &&
        (!adapter_error_r) &&
        (!encoder_busy) &&
        (!file_build_busy_w);

    // Accept a new input word only while current block is active,
    // no buffered word is waiting, and more bytes are still needed.
    assign word_ready =
        block_active_r &&
        (!word_buf_valid_r) &&
        (bytes_queued_r < bytes_total_r) &&
        (!adapter_error_r) &&
        (!encoder_error) &&
        (!packer_error);

    // --------------------------------------------------------------------
    // Adapter outputs toward encoder
    // Hold stable while enc_byte_ready_w = 0
    // --------------------------------------------------------------------
    assign enc_start_block_w = start_pending_r && (!count_mode_active_r);
    assign enc_byte_in_w     = current_byte_w;
    assign enc_byte_valid_w  = word_buf_valid_r && (!start_pending_r) &&
                               (!adapter_error_r) && (!count_mode_active_r);
    assign enc_block_start_w = first_byte_pending_r && enc_byte_valid_w;
    assign enc_block_end_w   = (bytes_sent_r == (bytes_total_r - 1'b1)) && enc_byte_valid_w;

    assign file_count_clear_w = global_clear;
    assign unused_file_debug_w = (^file_normalized_byte_w) ^ (^file_symbol_index_w);
    assign global_build_busy  = file_build_busy_w;
    assign global_build_done  = file_build_done_w;
    assign global_build_error = file_build_error_w | file_count_overflow_w;
    assign global_table_valid = global_table_valid_r;
    assign global_symbol_count = file_symbol_count_w;

    // --------------------------------------------------------------------
    // Adapter sequential logic
    // --------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            word_buf_r             <= 32'b0;
            word_buf_valid_r       <= 1'b0;
            word_buf_bytes_valid_r <= 3'b000;
            byte_index_r           <= 2'b00;

            bytes_total_r          <= {BLOCK_SIZE_WIDTH{1'b0}};
            bytes_queued_r         <= {BLOCK_SIZE_WIDTH{1'b0}};
            bytes_sent_r           <= {BLOCK_SIZE_WIDTH{1'b0}};

            block_active_r         <= 1'b0;
            start_pending_r        <= 1'b0;
            first_byte_pending_r   <= 1'b0;
            flush_on_block_end_r   <= 1'b1;
            adapter_error_r        <= 1'b0;
            count_mode_active_r    <= 1'b0;
            count_done_r           <= 1'b0;
            global_table_valid_r   <= 1'b0;
            global_emit_table_pending_r <= 1'b0;
        end
        else begin
            count_done_r <= 1'b0;

            if (global_clear) begin
                global_table_valid_r        <= 1'b0;
                global_emit_table_pending_r <= 1'b0;
            end
            else if (global_build_start) begin
                global_table_valid_r        <= 1'b0;
                global_emit_table_pending_r <= 1'b0;
            end
            else if (file_build_done_w && !global_table_valid_r &&
                     !file_build_error_w && !file_count_overflow_w) begin
                global_table_valid_r        <= 1'b1;
                global_emit_table_pending_r <= 1'b1;
            end
            else if (whole_file_enable && (!whole_file_count_mode) &&
                     encoder_done && global_emit_table_pending_r) begin
                global_emit_table_pending_r <= 1'b0;
            end

            // ------------------------------------------------------------
            // Start a new block
            // ------------------------------------------------------------
            if (start_block) begin
                if (!can_start_block_w) begin
                    adapter_error_r <= 1'b1;
                end
                else if ((block_size == {BLOCK_SIZE_WIDTH{1'b0}}) || (block_size > 6'd32)) begin
                    adapter_error_r <= 1'b1;
                end
                else begin
                    bytes_total_r          <= block_size;
                    bytes_queued_r         <= {BLOCK_SIZE_WIDTH{1'b0}};
                    bytes_sent_r           <= {BLOCK_SIZE_WIDTH{1'b0}};
                    block_active_r         <= 1'b1;
                    start_pending_r        <= 1'b1;
                    first_byte_pending_r   <= 1'b1;
                    flush_on_block_end_r   <= !continue_frame;
                    count_mode_active_r    <= whole_file_count_mode;

                    word_buf_r             <= 32'b0;
                    word_buf_valid_r       <= 1'b0;
                    word_buf_bytes_valid_r <= 3'b000;
                    byte_index_r           <= 2'b00;
                end
            end

            // ------------------------------------------------------------
            // start_block pulse toward encoder lasts exactly one cycle
            // and is emitted before first byte is presented
            // ------------------------------------------------------------
            if (start_pending_r)
                start_pending_r <= 1'b0;

            // ------------------------------------------------------------
            // Accept one 32-bit input word from upstream
            // ------------------------------------------------------------
            if (word_valid && word_ready) begin
                word_buf_r             <= word_in;
                word_buf_valid_r       <= 1'b1;
                word_buf_bytes_valid_r <= next_word_bytes_valid_w;
                byte_index_r           <= 2'b00;
                bytes_queued_r         <= bytes_queued_r +
                                          {{(BLOCK_SIZE_WIDTH-3){1'b0}}, next_word_bytes_valid_w};
            end

            // ------------------------------------------------------------
            // Current byte accepted by encoder
            // ------------------------------------------------------------
            if (current_byte_fire_w) begin
                bytes_sent_r <= bytes_sent_r + 1'b1;

                if (first_byte_pending_r)
                    first_byte_pending_r <= 1'b0;

                if (current_word_last_byte_w) begin
                    word_buf_valid_r       <= 1'b0;
                    word_buf_bytes_valid_r <= 3'b000;
                    byte_index_r           <= 2'b00;
                end
                else begin
                    byte_index_r <= byte_index_r + 1'b1;
                end

                // Last byte of the block has just been accepted
                if (bytes_sent_r == (bytes_total_r - 1'b1)) begin
                    block_active_r <= 1'b0;
                    if (count_mode_active_r) begin
                        count_done_r        <= 1'b1;
                        count_mode_active_r <= 1'b0;
                    end
                end
            end
        end
    end

    assign adapter_error_dbg = adapter_error_r;

    // --------------------------------------------------------------------
    // Whole-file global frequency counter / builder
    // --------------------------------------------------------------------
    frequency_counter #(
        .ALPHABET_SIZE      (HUFFMAN_ALPHABET_SIZE),
        .SYMBOL_WIDTH       (SYMBOL_WIDTH),
        .COUNT_WIDTH        (FILE_COUNT_WIDTH),
        .SYMBOL_INDEX_WIDTH (SYMBOL_INDEX_WIDTH),
        .ASCII_MIN          (ASCII_MIN),
        .ASCII_MAX          (ASCII_MAX),
        .DEFAULT_REMAP      (ASCII_MIN)
    ) u_file_frequency_counter (
        .clk             (clk),
        .rst_n           (rst_n),
        .clear           (file_count_clear_w),
        .count_en        (count_byte_fire_w),
        .count_data      (current_byte_w),
        .read_index      (file_freq_read_index_w),
        .read_count      (file_freq_read_count_w),
        .normalized_byte (file_normalized_byte_w),
        .symbol_index    (file_symbol_index_w),
        .count_overflow  (file_count_overflow_w)
    );

    huffman_builder #(
        .ALPHABET_SIZE         (HUFFMAN_ALPHABET_SIZE),
        .SYMBOL_WIDTH          (SYMBOL_WIDTH),
        .SYMBOL_COUNT_WIDTH    (SYMBOL_COUNT_WIDTH),
        .COUNT_WIDTH           (FILE_COUNT_WIDTH),
        .SYMBOL_INDEX_WIDTH    (SYMBOL_INDEX_WIDTH),
        .CODE_LEN_WIDTH        (CODE_LEN_WIDTH),
        .CODE_WIDTH            (CODE_WIDTH),
        .MAX_SYMBOLS_PER_BLOCK (FILE_MAX_SYMBOLS),
        .MAX_TREE_NODES        (FILE_MAX_TREE_NODES),
        .ASCII_MIN             (ASCII_MIN)
    ) u_file_huffman_builder (
        .clk                 (clk),
        .rst_n               (rst_n),
        .start               (global_build_start),
        .block_size          ({{(SYMBOL_COUNT_WIDTH-1){1'b0}}, 1'b1}),
        .freq_read_index     (file_freq_read_index_w),
        .freq_read_count     (file_freq_read_count_w),
        .busy                (file_build_busy_w),
        .done                (file_build_done_w),
        .error_flag          (file_build_error_w),
        .symbol_count        (file_symbol_count_w),
        .symbol_read_addr    (file_symbol_read_addr_w),
        .symbol_read_data    (file_symbol_read_data_w),
        .code_len_read_index (file_code_len_read_index_w),
        .code_len_read_data  (file_code_len_read_data_w),
        .code_read_index     (file_code_read_index_w),
        .code_read_data      (file_code_read_data_w)
    );

    // --------------------------------------------------------------------
    // dynamic_huffman_encoder
    // --------------------------------------------------------------------
    dynamic_huffman_encoder #(
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
        .ASCII_MAX             (ASCII_MAX)
    ) u_dynamic_huffman_encoder (
        .clk               (clk),
        .rst_n             (rst_n),
        .start_block       (enc_start_block_w),
        .whole_file_enable (whole_file_enable),
        .whole_file_emit_table(global_emit_table_pending_r),
        .whole_file_table_valid(global_table_valid_r),
        .external_symbol_count(file_symbol_count_w),
        .external_symbol_read_addr(file_symbol_read_addr_w),
        .external_symbol_read_data(file_symbol_read_data_w),
        .external_code_len_read_index(file_code_len_read_index_w),
        .external_code_len_read_data(file_code_len_read_data_w),
        .external_code_read_index(file_code_read_index_w),
        .external_code_read_data(file_code_read_data_w),
        .byte_in           (enc_byte_in_w),
        .byte_valid        (enc_byte_valid_w),
        .byte_ready        (enc_byte_ready_w),
        .block_start       (enc_block_start_w),
        .block_end         (enc_block_end_w),
        .stream_ready      (encoder_stream_ready),
        .stream_data       (encoder_stream_data),
        .stream_len        (encoder_stream_len),
        .stream_valid      (encoder_stream_valid),
        .stream_last       (encoder_stream_last),
        .busy              (encoder_busy),
        .done              (encoder_done),
        .error_flag        (encoder_error),
        .selected_mode_out (selected_mode_out),
        .fsm_state         (fsm_state)
    );

    // --------------------------------------------------------------------
    // bit_packer_128
    // --------------------------------------------------------------------
    bit_packer_128 #(
        .CHUNK_DATA_WIDTH     (CHUNK_DATA_WIDTH),
        .CHUNK_LEN_WIDTH      (CHUNK_LEN_WIDTH),
        .TRANSPORT_WORD_WIDTH (TRANSPORT_WORD_WIDTH),
        .VALID_BITS_WIDTH     (VALID_BITS_WIDTH)
    ) u_bit_packer_128 (
        .clk                  (clk),
        .rst_n                (rst_n),
        .stream_data          (encoder_stream_data),
        .stream_len           (encoder_stream_len),
        .stream_valid         (encoder_stream_valid),
        .stream_last          (encoder_stream_last),
        .flush_on_last        (packer_flush_on_last_w),
        .stream_ready         (encoder_stream_ready),
        .transport_word_out   (packer_transport_word),
        .transport_word_valid (packer_transport_valid),
        .transport_word_ready (packer_transport_ready),
        .busy                 (packer_busy),
        .done                 (packer_done),
        .error_flag           (packer_error)
    );

    // --------------------------------------------------------------------
    // aes_input_wrapper
    // --------------------------------------------------------------------
    wrapper #(
        .AES_KEY_FIXED (AES_KEY_FIXED)
    ) u_aes_input_wrapper (
        .clk          (clk),
        .rst_n        (rst_n),
        .block_in     (packer_transport_word),
        .block_valid  (packer_transport_valid),
        .aes_ready    (aes_ready),
        .block_accept (block_accept),
        .cipher_en    (cipher_en),
        .decipher_en  (decipher_en),
        .chain_en     (chain_en),
        .data_in      (data_in),
        .mode         (mode),
        .init_vector  (init_vector),
        .segment_len  (segment_len),
        .key          (key)
    );

    assign packer_transport_ready = block_accept;
    assign packer_flush_on_last_w = encoder_stream_last && flush_on_block_end_r;

    // --------------------------------------------------------------------
    // Top-level status composition
    // --------------------------------------------------------------------
    assign block_core_busy_w =
        block_active_r   |
        word_buf_valid_r |
        start_pending_r  |
        encoder_busy;

    assign frame_flush_busy_w =
        flush_on_block_end_r &&
        (packer_busy | packer_transport_valid);

    assign tx_busy  = block_core_busy_w | frame_flush_busy_w | file_build_busy_w |
                      (1'b0 & unused_file_debug_w);
    assign tx_done  = count_done_r ? 1'b1 :
                      (flush_on_block_end_r ? packer_done : encoder_done);
    assign tx_error = adapter_error_r | encoder_error | packer_error |
                      file_count_overflow_w;

    // --------------------------------------------------------------------
    // Debug visibility
    // --------------------------------------------------------------------
    assign transport_word_dbg       = packer_transport_word;
    assign transport_word_valid_dbg = packer_transport_valid;

endmodule
