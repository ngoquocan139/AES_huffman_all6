module apb_huffman_aes_tx_top #(
    // --------------------------------------------------------------------
    // APB / block-size parameter
    // --------------------------------------------------------------------
    parameter BLOCK_SIZE_WIDTH      = 6,

    // --------------------------------------------------------------------
    // Huffman / encoder parameters
    // --------------------------------------------------------------------
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
    // Bit-packer / AES-wrapper parameters
    // --------------------------------------------------------------------
    parameter TRANSPORT_WORD_WIDTH  = 128,
    parameter VALID_BITS_WIDTH      = 7,
    parameter [127:0] AES_KEY_FIXED = 128'h00112233445566778899AABBCCDDEEFF
)(
    // --------------------------------------------------------------------
    // APB slave interface
    // --------------------------------------------------------------------
    input  wire                         PCLK,
    input  wire                         PRESETn,
    input  wire                         PSEL,
    input  wire                         PENABLE,
    input  wire                         PWRITE,
    input  wire [31:0]                  PADDR,
    input  wire [31:0]                  PWDATA,
    output wire [31:0]                  PRDATA,
    output wire                         PREADY,
    output wire                         PSLVERR,

    // --------------------------------------------------------------------
    // CBC IV from DMA register file. CPU writes one IV per frame.
    // --------------------------------------------------------------------
    input  wire [127:0]                 cbc_iv_i,

    // --------------------------------------------------------------------
    // AES core outputs
    // --------------------------------------------------------------------
    output wire [127:0]                 aes_data_out,
    output wire                         aes_ready_out,

    // --------------------------------------------------------------------
    // Optional top-level debug
    // --------------------------------------------------------------------
    output wire                         tx_busy,
    output wire                         tx_done,
    output wire                         tx_error,

    output wire                         encoder_busy,
    output wire                         encoder_done,
    output wire                         encoder_error,
    output wire [1:0]                   selected_mode_out,
    output wire [3:0]                   fsm_state,

    output wire                         packer_busy,
    output wire                         packer_done,
    output wire                         packer_error,
    output wire [TRANSPORT_WORD_WIDTH-1:0] transport_word_dbg,
    output wire                         transport_word_valid_dbg,
    output wire                         adapter_error_dbg,

    // --------------------------------------------------------------------
    // Optional APB-wrapper debug
    // --------------------------------------------------------------------
    output wire                         apb_start_block_dbg,
    output wire [BLOCK_SIZE_WIDTH-1:0]  apb_block_size_dbg,
    output wire [31:0]                  apb_word_in_dbg,
    output wire                         apb_word_valid_dbg,
    output wire                         apb_word_ready_dbg,

    // --------------------------------------------------------------------
    // Optional AES-input debug (from aes_input_wrapper inside TX top)
    // --------------------------------------------------------------------
    output wire                         cipher_en_dbg,
    output wire                         decipher_en_dbg,
    output wire                         chain_en_dbg,
    output wire [127:0]                 data_in_dbg,
    output wire [127:0]                 key_dbg,
    output wire [3:0]                   mode_dbg,
    output wire [127:0]                 init_vector_dbg,
    output wire [15:0]                  segment_len_dbg
);

    // --------------------------------------------------------------------
    // Internal wires: APB IF -> huffman_aes_tx_top
    // --------------------------------------------------------------------
    wire                         apb_start_block_w;
    wire                         apb_continue_frame_w;
    wire                         apb_compress_only_w;
    wire                         apb_whole_file_enable_w;
    wire                         apb_whole_file_count_mode_w;
    wire                         apb_global_clear_w;
    wire                         apb_global_build_start_w;
    wire [BLOCK_SIZE_WIDTH-1:0]  apb_block_size_w;
    wire [31:0]                  apb_word_in_w;
    wire                         apb_word_valid_w;
    wire                         apb_word_ready_w;

    // --------------------------------------------------------------------
    // Internal wires: TX top -> AES_top
    // These are outputs of aes_input_wrapper inside huffman_aes_tx_top
    // --------------------------------------------------------------------
    wire                         cipher_en_w;
    wire                         decipher_en_w;
    wire                         chain_en_w;
    wire [127:0]                 data_in_w;
    wire [127:0]                 key_w;
    wire [3:0]                   mode_w;
    wire [127:0]                 init_vector_w;
    wire [15:0]                  segment_len_w;

    // --------------------------------------------------------------------
    // Internal wire: AES_top ready fed back to TX top
    // --------------------------------------------------------------------
    wire                         aes_ready_core_w;
    wire                         tx_path_ready_w;
    wire                         tx_busy_core_w;
    wire                         tx_done_core_w;
    wire                         tx_error_core_w;
    wire                         global_build_busy_w;
    wire                         global_build_done_w;
    wire                         global_build_error_w;
    wire                         global_table_valid_w;
    wire [SYMBOL_COUNT_WIDTH-1:0] global_symbol_count_w;
    wire [31:0]                  aes_out_word_w;
    wire                         aes_out_word_last_w;
    wire                         aes_out_word_valid_w;
    wire                         aes_out_word_ready_w;
    wire                         apb_soft_reset_w;
    wire                         apb_clear_error_w;
    wire unused;

    reg                          aes_ready_dly_r;
    reg                          tx_cipher_inflight_r;
    reg                          aes_output_error_r;
    reg  [127:0]                 aes_emit_block_r;
    reg                          aes_emit_valid_r;
    reg  [1:0]                   aes_emit_word_idx_r;
    reg  [127:0]                 aes_hold_block_r;
    reg                          aes_hold_valid_r;
    reg  [127:0]                 tx_cbc_chain_r;
    reg                          tx_cbc_active_r;

    wire                         aes_output_capture_w;
    wire                         bypass_capture_w;
    wire                         emit_capture_w;
    wire [127:0]                 emit_capture_data_w;
    wire [127:0]                 tx_cbc_prev_w;
    wire [127:0]                 tx_aes_plain_w;
    wire                         aes_out_word_fire_w;
    wire                         aes_emit_last_word_w;
    wire                         aes_emit_complete_w;
    wire                         aes_emit_can_load_hold_w;
    wire                         emit_accept_ready_w;

    function [31:0] select_aes_word32;
        input [127:0] block_val;
        input [1:0]   idx;
        begin
            case (idx)
                2'd0: select_aes_word32 = block_val[31:0];
                2'd1: select_aes_word32 = block_val[63:32];
                2'd2: select_aes_word32 = block_val[95:64];
                default: select_aes_word32 = block_val[127:96];
            endcase
        end
    endfunction
    // --------------------------------------------------------------------
    // APB slave wrapper
    // --------------------------------------------------------------------
    apb_huffman_tx_if #(
        .BLOCK_SIZE_WIDTH (BLOCK_SIZE_WIDTH),
        .SYMBOL_COUNT_WIDTH(SYMBOL_COUNT_WIDTH)
    ) u_apb_huffman_tx_if (
        .PCLK          (PCLK),
        .PRESETn       (PRESETn),
        .PSEL          (PSEL),
        .PENABLE       (PENABLE),
        .PWRITE        (PWRITE),
        .PADDR         (PADDR),
        .PWDATA        (PWDATA),
        .PRDATA        (PRDATA),
        .PREADY        (PREADY),
        .PSLVERR       (PSLVERR),

        .start_block_o (apb_start_block_w),
        .continue_frame_o(apb_continue_frame_w),
        .compress_only_o(apb_compress_only_w),
        .whole_file_enable_o(apb_whole_file_enable_w),
        .whole_file_count_mode_o(apb_whole_file_count_mode_w),
        .block_size_o  (apb_block_size_w),
        .word_in_o     (apb_word_in_w),
        .word_valid_o  (apb_word_valid_w),
        .word_ready_i  (apb_word_ready_w),
        .aes_out_word_i(aes_out_word_w),
        .aes_out_word_last_i(aes_out_word_last_w),
        .aes_out_word_valid_i(aes_out_word_valid_w),
        .aes_out_word_ready_o(aes_out_word_ready_w),
        .aes_out_error_i(aes_output_error_r),
        .soft_reset_o   (apb_soft_reset_w),
        .clear_error_o  (apb_clear_error_w),
        .global_clear_o (apb_global_clear_w),
        .global_build_start_o(apb_global_build_start_w),

        .tx_busy_i     (tx_busy_core_w),
        .tx_done_i     (tx_done_core_w),
        .tx_error_i    (tx_error_core_w),
        .global_build_busy_i(global_build_busy_w),
        .global_build_done_i(global_build_done_w),
        .global_build_error_i(global_build_error_w),
        .global_table_valid_i(global_table_valid_w),
        .global_symbol_count_i(global_symbol_count_w)
    );

    // --------------------------------------------------------------------
    // Huffman TX top
    // --------------------------------------------------------------------
    huffman_aes_tx_top #(
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
    ) u_huffman_aes_tx_top (
        .clk                   (PCLK),
        .rst_n                 (PRESETn),

        .start_block           (apb_start_block_w),
        .continue_frame        (apb_continue_frame_w),
        .whole_file_enable     (apb_whole_file_enable_w),
        .whole_file_count_mode (apb_whole_file_count_mode_w),
        .global_clear          (apb_global_clear_w | apb_soft_reset_w),
        .global_build_start    (apb_global_build_start_w),
        .block_size            (apb_block_size_w),

        .word_in               (apb_word_in_w),
        .word_valid            (apb_word_valid_w),
        .word_ready            (apb_word_ready_w),

        .aes_ready             (tx_path_ready_w),

        .block_accept          (unused ),
        .cipher_en             (cipher_en_w),
        .decipher_en           (decipher_en_w),
        .chain_en              (chain_en_w),
        .data_in               (data_in_w),
        .mode                  (mode_w),
        .init_vector           (init_vector_w),
        .segment_len           (segment_len_w),
        .key                   (key_w),

        .tx_busy               (tx_busy_core_w),
        .tx_done               (tx_done_core_w),
        .tx_error              (tx_error_core_w),
        .global_build_busy     (global_build_busy_w),
        .global_build_done     (global_build_done_w),
        .global_build_error    (global_build_error_w),
        .global_table_valid    (global_table_valid_w),
        .global_symbol_count   (global_symbol_count_w),

        .encoder_busy          (encoder_busy),
        .encoder_done          (encoder_done),
        .encoder_error         (encoder_error),
        .selected_mode_out     (selected_mode_out),
        .fsm_state             (fsm_state),

        .packer_busy           (packer_busy),
        .packer_done           (packer_done),
        .packer_error          (packer_error),
        .transport_word_dbg    (transport_word_dbg),
        .transport_word_valid_dbg(transport_word_valid_dbg),
        .adapter_error_dbg     (adapter_error_dbg)
    );

    // --------------------------------------------------------------------
    // AES core
    // TX currently uses a fixed encrypt-only path:
    // - wrapper.v only pulses cipher_en
    // - mode is fixed ECB
    // - chain/IV/segment settings are hard-wired
    // Therefore TX can instantiate the encrypt core directly instead of the
    // generic AES_top wrapper used for multi-mode encrypt/decrypt flows.
    // --------------------------------------------------------------------
    /* verilator lint_off PINCONNECTEMPTY */
    aes128_cipher_top u_AES_top_tx (
        .clk_sys      (PCLK),
        .rst_n        (PRESETn),
        .cipher_key   (key_w),
        .plain_text   (tx_aes_plain_w),
        .cipher_en    (cipher_en_w && (!apb_compress_only_w)),
        .cipher_text  (aes_data_out),
        .cipher_ready (aes_ready_core_w),
        .cipher_key10 ()
    );
    /* verilator lint_on PINCONNECTEMPTY */

    assign emit_accept_ready_w   = !(aes_emit_valid_r && aes_hold_valid_r);
    assign tx_path_ready_w       = apb_compress_only_w ? emit_accept_ready_w
                                                       : aes_ready_core_w;
    assign aes_output_capture_w  = (!apb_compress_only_w) &&
                                   tx_cipher_inflight_r &&
                                   (!aes_ready_dly_r) &&
                                   aes_ready_core_w;
    assign bypass_capture_w      = apb_compress_only_w && cipher_en_w;
    assign emit_capture_w        = apb_compress_only_w ? bypass_capture_w
                                                       : aes_output_capture_w;
    assign emit_capture_data_w   = apb_compress_only_w ? data_in_w
                                                       : aes_data_out;
    assign tx_cbc_prev_w         = aes_output_capture_w ? aes_data_out :
                                   (tx_cbc_active_r ? tx_cbc_chain_r : cbc_iv_i);
    assign tx_aes_plain_w        = data_in_w ^ tx_cbc_prev_w;
    assign aes_out_word_w        = select_aes_word32(aes_emit_block_r, aes_emit_word_idx_r);
    assign aes_out_word_valid_w  = aes_emit_valid_r;
    assign aes_emit_last_word_w  = (aes_emit_word_idx_r == 2'd3);
    assign aes_out_word_last_w   = aes_emit_valid_r && aes_emit_last_word_w;
    assign aes_out_word_fire_w   = aes_out_word_valid_w && aes_out_word_ready_w;
    assign aes_emit_complete_w   = aes_out_word_fire_w && aes_emit_last_word_w;
    assign aes_emit_can_load_hold_w = ((!aes_emit_valid_r) || aes_emit_complete_w) &&
                                      aes_hold_valid_r;

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            aes_ready_dly_r       <= 1'b1;
            tx_cipher_inflight_r  <= 1'b0;
            aes_output_error_r    <= 1'b0;
            aes_emit_block_r      <= 128'b0;
            aes_emit_valid_r      <= 1'b0;
            aes_emit_word_idx_r   <= 2'b00;
            aes_hold_block_r      <= 128'b0;
            aes_hold_valid_r      <= 1'b0;
            tx_cbc_chain_r        <= 128'b0;
            tx_cbc_active_r       <= 1'b0;
        end
        else begin
            aes_ready_dly_r <= aes_ready_core_w;

            if (apb_soft_reset_w || apb_global_clear_w) begin
                tx_cipher_inflight_r  <= 1'b0;
                aes_output_error_r    <= 1'b0;
                aes_emit_block_r      <= 128'b0;
                aes_emit_valid_r      <= 1'b0;
                aes_emit_word_idx_r   <= 2'b00;
                aes_hold_block_r      <= 128'b0;
                aes_hold_valid_r      <= 1'b0;
                tx_cbc_chain_r        <= 128'b0;
                tx_cbc_active_r       <= 1'b0;
            end
            else begin

                if (apb_clear_error_w)
                    aes_output_error_r <= 1'b0;

                if ((!apb_compress_only_w) && cipher_en_w &&
                    tx_cipher_inflight_r && (!aes_output_capture_w))
                    aes_output_error_r <= 1'b1;

                if (apb_compress_only_w) begin
                    tx_cipher_inflight_r <= 1'b0;
                end
                else begin
                    case ({cipher_en_w, aes_output_capture_w})
                        2'b10: begin
                            tx_cipher_inflight_r <= 1'b1;
                        end

                        2'b01: begin
                            tx_cipher_inflight_r <= 1'b0;
                        end

                        2'b11: begin
                            tx_cipher_inflight_r <= 1'b1;
                        end

                        default: begin
                            tx_cipher_inflight_r <= tx_cipher_inflight_r;
                        end
                    endcase

                    if (cipher_en_w)
                        tx_cbc_active_r <= 1'b1;

                    if (aes_output_capture_w)
                        tx_cbc_chain_r <= aes_data_out;
                end

                if (emit_capture_w) begin
                    if (!aes_emit_valid_r) begin
                        aes_emit_block_r    <= emit_capture_data_w;
                        aes_emit_valid_r    <= 1'b1;
                        aes_emit_word_idx_r <= 2'b00;
                    end
                    else if (!aes_hold_valid_r) begin
                        aes_hold_block_r    <= emit_capture_data_w;
                        aes_hold_valid_r    <= 1'b1;
                    end
                    else begin
                        aes_output_error_r  <= 1'b1;
                    end
                end

                if (aes_out_word_fire_w) begin
                    if (aes_emit_last_word_w) begin
                        aes_emit_valid_r    <= 1'b0;
                        aes_emit_word_idx_r <= 2'b00;
                    end
                    else begin
                        aes_emit_word_idx_r <= aes_emit_word_idx_r + 1'b1;
                    end
                end

                if (aes_emit_can_load_hold_w) begin
                    aes_emit_block_r      <= aes_hold_block_r;
                    aes_emit_valid_r      <= 1'b1;
                    aes_emit_word_idx_r   <= 2'b00;
                    aes_hold_valid_r      <= 1'b0;
                end
            end
        end
    end

    // --------------------------------------------------------------------
    // Export AES ready
    // --------------------------------------------------------------------
    assign aes_ready_out = aes_ready_core_w;
    assign tx_busy       = tx_busy_core_w;
    assign tx_done       = tx_done_core_w;
    assign tx_error      = tx_error_core_w;

    // --------------------------------------------------------------------
    // Optional APB-wrapper debug
    // --------------------------------------------------------------------
    assign apb_start_block_dbg = apb_start_block_w;
    assign apb_block_size_dbg  = apb_block_size_w;
    assign apb_word_in_dbg     = apb_word_in_w;
    assign apb_word_valid_dbg  = apb_word_valid_w;
    assign apb_word_ready_dbg  = apb_word_ready_w;

    // --------------------------------------------------------------------
    // Optional AES-input debug
    // --------------------------------------------------------------------
    assign cipher_en_dbg    = cipher_en_w;
    assign decipher_en_dbg  = decipher_en_w;
    assign chain_en_dbg     = chain_en_w;
    assign data_in_dbg      = tx_aes_plain_w;
    assign key_dbg          = key_w;
    assign mode_dbg         = mode_w;
    assign init_vector_dbg  = cbc_iv_i ^ {128{1'b0 & (|init_vector_w)}};
    assign segment_len_dbg  = segment_len_w;

endmodule
