`timescale 1ns/1ps

module test_bench;

    parameter BLOCK_SIZE_WIDTH         = 6;
    parameter BUFFER_ADDR_WIDTH        = 5;
    parameter SYMBOL_WIDTH             = 8;
    parameter SYMBOL_COUNT_WIDTH       = 6;
    parameter COUNT_WIDTH              = 6;
    parameter SYMBOL_INDEX_WIDTH       = 7;
    parameter CODE_LEN_WIDTH           = 5;
    parameter CODE_WIDTH               = 31;
    parameter HEADER_BITS_WIDTH        = 10;
    parameter TOTAL_BITS_WIDTH         = 11;
    parameter CHUNK_DATA_WIDTH         = 32;
    parameter CHUNK_LEN_WIDTH          = 6;
    parameter MAX_SYMBOLS_PER_BLOCK    = 32;
    parameter MAX_TREE_NODES           = 63;
    parameter [7:0] ASCII_MIN          = 8'h20;
    parameter [7:0] ASCII_MAX          = 8'h7E;
    parameter TRANSPORT_WORD_WIDTH     = 128;
    parameter VALID_BITS_WIDTH         = 7;
    parameter [127:0] AES_KEY_FIXED    = 128'h00112233445566778899AABBCCDDEEFF;
    parameter [127:0] ROUND_KEY_10_FIXED = 128'h36D024461D84B8375FC0F9C04CBAB6BB;

    localparam integer MAX_INPUT_BYTES      = 16384;
    localparam integer MAX_BLOCKS           = 1024;
    localparam integer MAX_COMPRESSED_WORDS = 4096;
    localparam integer TB_DLY               = 2;
    localparam integer TRANSPORT_PAYLOAD_WIDTH = TRANSPORT_WORD_WIDTH - 1 - VALID_BITS_WIDTH;

    localparam [1:0] MODE_RAW_FULL    = 2'b00;
    localparam [1:0] MODE_RAW_PARTIAL = 2'b01;
    localparam [1:0] MODE_COMPRESSED  = 2'b10;
    localparam [1:0] MODE_ONE_SYMBOL  = 2'b11;

    localparam [31:0] TX_ADDR_START_BLOCK = 32'h0000_0000;
    localparam [31:0] TX_ADDR_BLOCK_SIZE  = 32'h0000_0004;
    localparam [31:0] TX_ADDR_WORD_IN     = 32'h0000_0008;
    localparam [31:0] TX_ADDR_STATUS      = 32'h0000_000C;
    localparam [31:0] TX_ADDR_CONTROL     = 32'h0000_0010;
    localparam [31:0] TX_ADDR_AES_OUT_DATA   = 32'h0000_0020;
    localparam [31:0] TX_ADDR_AES_OUT_META   = 32'h0000_0024;
    localparam [31:0] TX_ADDR_AES_OUT_STATUS = 32'h0000_0028;

    localparam [31:0] RX_ADDR_DATA    = 32'h0000_0000;
    localparam [31:0] RX_ADDR_META    = 32'h0000_0004;
    localparam [31:0] RX_ADDR_STATUS  = 32'h0000_0008;
    localparam [31:0] RX_ADDR_CONTROL = 32'h0000_000C;

    reg                         PCLK;
    reg                         PRESETn;

    reg                         tx_PSEL;
    reg                         tx_PENABLE;
    reg                         tx_PWRITE;
    reg  [31:0]                 tx_PADDR;
    reg  [31:0]                 tx_PWDATA;
    wire [31:0]                 tx_PRDATA;
    wire                        tx_PREADY;
    wire                        tx_PSLVERR;

    reg                         rx_PSEL;
    reg                         rx_PENABLE;
    reg                         rx_PWRITE;
    reg  [31:0]                 rx_PADDR;
    reg  [31:0]                 rx_PWDATA;
    wire [31:0]                 rx_PRDATA;
    wire                        rx_PREADY;
    wire                        rx_PSLVERR;

    wire                        tx_busy;
    wire                        tx_done;
    wire                        tx_error;
    wire                        tx_encoder_busy;
    wire                        tx_encoder_done;
    wire                        tx_encoder_error;
    wire [1:0]                  tx_selected_mode_out;
    wire [3:0]                  tx_fsm_state;
    wire                        tx_packer_busy;
    wire                        tx_packer_done;
    wire                        tx_packer_error;

    wire                        rx_busy;
    wire                        rx_done;
    wire                        rx_error;
    wire                        rx_depacker_busy;
    wire                        rx_depacker_done;
    wire                        rx_depacker_error;
    wire                        rx_parser_busy;
    wire                        rx_parser_block_done;
    wire                        rx_parser_frame_done;
    wire                        rx_parser_error;
    wire                        rx_decoder_busy;
    wire                        rx_decoder_block_done;
    wire                        rx_decoder_frame_done;
    wire                        rx_decoder_error;
    wire                        rx_word_packer_busy;
    wire                        rx_word_packer_block_done;
    wire                        rx_word_packer_frame_done;
    wire                        rx_word_packer_error;

    wire                        bridge_nonempty;
    wire                        bridge_full;
    wire [4:0]                  bridge_level;
    wire                        bridge_error;
    wire [127:0]                bridge_head_word_dbg;
    wire                        bridge_word_valid_dbg;

    wire [127:0]                tx_aes_data_out_dbg;
    wire                        tx_aes_ready_out_dbg;
    wire                        tx_cipher_en_dbg;
    wire                        rx_ciphertext_word_ready_dbg;
    wire [TRANSPORT_WORD_WIDTH-1:0] tx_transport_word_dbg_h;
    wire [VALID_BITS_WIDTH-1:0]     tx_transport_valid_bits_h;
    wire [31:0]                     tx_transport_valid_bits_ext_h;

    reg  [7:0]                  input_mem [0:MAX_INPUT_BYTES-1];
    reg  [7:0]                  expected_mem [0:MAX_INPUT_BYTES-1];
    reg  [7:0]                  actual_mem[0:MAX_INPUT_BYTES-1];
    reg  [TRANSPORT_WORD_WIDTH-1:0] compressed_word_mem [0:MAX_COMPRESSED_WORDS-1];
    reg  [VALID_BITS_WIDTH-1:0]     compressed_valid_bits_mem [0:MAX_COMPRESSED_WORDS-1];
    reg                             compressed_last_mem [0:MAX_COMPRESSED_WORDS-1];
    integer                     block_base [0:MAX_BLOCKS-1];
    integer                     block_len  [0:MAX_BLOCKS-1];
    integer                     block_continue [0:MAX_BLOCKS-1];
    integer                     expected_mode [0:MAX_BLOCKS-1];

    integer                     pass_count;
    integer                     fail_count;
    integer                     case_count;
    integer                     text_len;
    integer                     unsupported_input_bytes;
    integer                     expected_total_bytes;
    integer                     actual_total_bytes;
    integer                     expected_block_count;
    integer                     expected_frame_count;
    integer                     expected_rx_word_count;
    integer                     expected_block_last_word_count;
    integer                     expected_frame_last_word_count;
    integer                     actual_rx_word_count;
    integer                     actual_block_last_word_count;
    integer                     actual_frame_last_word_count;
    integer                     actual_tx_aes_word_count;
    integer                     actual_tx_aes_last_word_count;
    integer                     actual_tx_aes_word_idx_in_block;
    integer                     compressed_word_count;
    integer                     compressed_payload_bits;
    integer                     compressed_payload_bytes_ceil;
    integer                     total_input_bits;
    integer                     total_aes_channel_bits;
    integer                     saved_bits;
    integer                     tx_done_pulse_count;
    integer                     rx_done_pulse_count;
    integer                     tx_cipher_pulse_count;
    integer                     bridge_nonempty_seen_count;
    integer                     system_rc;
    integer                     i;
    integer                     j;
    integer                     block_idx;
    integer                     words_needed;
    integer                     byte_lane;
    integer                     local_timeout;
    integer                     apb_waits;
    integer                     got_done;
    integer                     got_error;
    reg                         apb_err;
    reg  [31:0]                 apb_rdata;
    reg  [31:0]                 tx_status_r;
    reg  [31:0]                 tx_aes_status_r;
    reg  [31:0]                 tx_aes_meta_r;
    reg  [31:0]                 tx_aes_data_r;
    reg  [31:0]                 rx_status_before_clear_r;
    reg  [31:0]                 rx_status_after_clear_r;
    reg  [31:0]                 rx_meta_r;
    reg  [31:0]                 rx_data_r;
    reg  [2:0]                  rx_valid_bytes_r;
    reg  [7:0]                  b0;
    reg  [7:0]                  b1;
    reg  [7:0]                  b2;
    reg  [7:0]                  b3;
    reg  [31:0]                 word_v;
    integer                     pre_dump_fd;
    integer                     compress_dump_fd;
    integer                     post_dump_fd;
    integer                     ascii_dump_fd;
    integer                     fd;
    integer                     ch;
    real                        compression_ratio_pct;
    real                        space_saving_pct;

    function [31:0] pack_word4;
        input [7:0] x0;
        input [7:0] x1;
        input [7:0] x2;
        input [7:0] x3;
        begin
            pack_word4 = {x3, x2, x1, x0};
        end
    endfunction

    function [7:0] normalize_byte;
        input [7:0] raw_byte;
        begin
            if ((raw_byte != 8'h0A) &&
                ((raw_byte < ASCII_MIN) || (raw_byte > ASCII_MAX)))
                normalize_byte = ASCII_MIN;
            else
                normalize_byte = raw_byte;
        end
    endfunction

    task fwrite_ascii_token;
        input integer out_fd;
        input [7:0] raw_byte;
    begin
        case (raw_byte)
            8'h0A: $fwrite(out_fd, "\n");
            8'h0D: $fwrite(out_fd, "\\r");
            8'h09: $fwrite(out_fd, "\\t");
            default: begin
                if ((raw_byte >= 8'h20) && (raw_byte <= 8'h7E))
                    $fwrite(out_fd, "%c", raw_byte);
                else
                    $fwrite(out_fd, ".");
            end
        endcase
    end
    endtask

    apb_huffman_aes_tx_rx_top #(
        .BLOCK_SIZE_WIDTH         (BLOCK_SIZE_WIDTH),
        .BUFFER_ADDR_WIDTH        (BUFFER_ADDR_WIDTH),
        .SYMBOL_WIDTH             (SYMBOL_WIDTH),
        .SYMBOL_COUNT_WIDTH       (SYMBOL_COUNT_WIDTH),
        .COUNT_WIDTH              (COUNT_WIDTH),
        .SYMBOL_INDEX_WIDTH       (SYMBOL_INDEX_WIDTH),
        .CODE_LEN_WIDTH           (CODE_LEN_WIDTH),
        .CODE_WIDTH               (CODE_WIDTH),
        .HEADER_BITS_WIDTH        (HEADER_BITS_WIDTH),
        .TOTAL_BITS_WIDTH         (TOTAL_BITS_WIDTH),
        .CHUNK_DATA_WIDTH         (CHUNK_DATA_WIDTH),
        .CHUNK_LEN_WIDTH          (CHUNK_LEN_WIDTH),
        .MAX_SYMBOLS_PER_BLOCK    (MAX_SYMBOLS_PER_BLOCK),
        .MAX_TREE_NODES           (MAX_TREE_NODES),
        .ASCII_MIN                (ASCII_MIN),
        .ASCII_MAX                (ASCII_MAX),
        .TRANSPORT_WORD_WIDTH     (TRANSPORT_WORD_WIDTH),
        .VALID_BITS_WIDTH         (VALID_BITS_WIDTH),
        .AES_KEY_FIXED            (AES_KEY_FIXED),
        .ROUND_KEY_10_FIXED       (ROUND_KEY_10_FIXED)
    ) u_dut (
        .PCLK                     (PCLK),
        .PRESETn                  (PRESETn),
        .tx_PSEL                  (tx_PSEL),
        .tx_PENABLE               (tx_PENABLE),
        .tx_PWRITE                (tx_PWRITE),
        .tx_PADDR                 (tx_PADDR),
        .tx_PWDATA                (tx_PWDATA),
        .tx_PRDATA                (tx_PRDATA),
        .tx_PREADY                (tx_PREADY),
        .tx_PSLVERR               (tx_PSLVERR),
        .rx_PSEL                  (rx_PSEL),
        .rx_PENABLE               (rx_PENABLE),
        .rx_PWRITE                (rx_PWRITE),
        .rx_PADDR                 (rx_PADDR),
        .rx_PWDATA                (rx_PWDATA),
        .rx_PRDATA                (rx_PRDATA),
        .rx_PREADY                (rx_PREADY),
        .rx_PSLVERR               (rx_PSLVERR),
        .tx_busy                  (tx_busy),
        .tx_done                  (tx_done),
        .tx_error                 (tx_error),
        .tx_encoder_busy          (tx_encoder_busy),
        .tx_encoder_done          (tx_encoder_done),
        .tx_encoder_error         (tx_encoder_error),
        .tx_selected_mode_out     (tx_selected_mode_out),
        .tx_fsm_state             (tx_fsm_state),
        .tx_packer_busy           (tx_packer_busy),
        .tx_packer_done           (tx_packer_done),
        .tx_packer_error          (tx_packer_error),
        .rx_busy                  (rx_busy),
        .rx_done                  (rx_done),
        .rx_error                 (rx_error),
        .rx_depacker_busy         (rx_depacker_busy),
        .rx_depacker_done         (rx_depacker_done),
        .rx_depacker_error        (rx_depacker_error),
        .rx_parser_busy           (rx_parser_busy),
        .rx_parser_block_done     (rx_parser_block_done),
        .rx_parser_frame_done     (rx_parser_frame_done),
        .rx_parser_error          (rx_parser_error),
        .rx_decoder_busy          (rx_decoder_busy),
        .rx_decoder_block_done    (rx_decoder_block_done),
        .rx_decoder_frame_done    (rx_decoder_frame_done),
        .rx_decoder_error         (rx_decoder_error),
        .rx_word_packer_busy      (rx_word_packer_busy),
        .rx_word_packer_block_done(rx_word_packer_block_done),
        .rx_word_packer_frame_done(rx_word_packer_frame_done),
        .rx_word_packer_error     (rx_word_packer_error),
        .bridge_nonempty          (bridge_nonempty),
        .bridge_full              (bridge_full),
        .bridge_level             (bridge_level),
        .bridge_error             (bridge_error),
        .bridge_head_word_dbg     (bridge_head_word_dbg),
        .bridge_word_valid_dbg    (bridge_word_valid_dbg),
        .tx_aes_data_out_dbg      (tx_aes_data_out_dbg),
        .tx_aes_ready_out_dbg     (tx_aes_ready_out_dbg),
        .tx_cipher_en_dbg         (tx_cipher_en_dbg),
        .rx_ciphertext_word_ready_dbg(rx_ciphertext_word_ready_dbg)
    );

    assign tx_transport_word_dbg_h       = u_dut.u_tx_top.transport_word_dbg;
    assign tx_transport_valid_bits_h     = tx_transport_word_dbg_h[TRANSPORT_WORD_WIDTH-2 -: VALID_BITS_WIDTH];
    assign tx_transport_valid_bits_ext_h = {{(32-VALID_BITS_WIDTH){1'b0}}, tx_transport_valid_bits_h};

    initial begin
        PCLK = 1'b0;
        forever #5 PCLK = ~PCLK;
    end

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            tx_done_pulse_count       <= 0;
            rx_done_pulse_count       <= 0;
            tx_cipher_pulse_count     <= 0;
            bridge_nonempty_seen_count<= 0;
            compressed_word_count     <= 0;
            compressed_payload_bits   <= 0;
        end
        else begin
            if (tx_done)
                tx_done_pulse_count <= tx_done_pulse_count + 1;

            if (rx_done)
                rx_done_pulse_count <= rx_done_pulse_count + 1;

            if (tx_cipher_en_dbg)
                tx_cipher_pulse_count <= tx_cipher_pulse_count + 1;

            if (tx_cipher_en_dbg) begin
                compressed_payload_bits <= compressed_payload_bits + tx_transport_valid_bits_ext_h;
                if (compressed_word_count < MAX_COMPRESSED_WORDS) begin
                    compressed_word_mem[compressed_word_count]       <= tx_transport_word_dbg_h;
                    compressed_valid_bits_mem[compressed_word_count] <= tx_transport_valid_bits_h;
                    compressed_last_mem[compressed_word_count]       <= tx_transport_word_dbg_h[TRANSPORT_WORD_WIDTH-1];
                    compressed_word_count                            <= compressed_word_count + 1;
                end
                else begin
                    $display("[FAIL] compressed_word_mem overflow, increase MAX_COMPRESSED_WORDS=%0d",
                             MAX_COMPRESSED_WORDS);
                    fail_count = fail_count + 1;
                end
            end

            if (bridge_nonempty)
                bridge_nonempty_seen_count <= bridge_nonempty_seen_count + 1;
        end
    end

    task clear_buses;
    begin
        tx_PSEL    = 1'b0;
        tx_PENABLE = 1'b0;
        tx_PWRITE  = 1'b0;
        tx_PADDR   = 32'b0;
        tx_PWDATA  = 32'b0;

        rx_PSEL    = 1'b0;
        rx_PENABLE = 1'b0;
        rx_PWRITE  = 1'b0;
        rx_PADDR   = 32'b0;
        rx_PWDATA  = 32'b0;
    end
    endtask

    task clear_vectors;
    begin
        text_len                        = 0;
        unsupported_input_bytes         = 0;
        expected_total_bytes           = 0;
        actual_total_bytes             = 0;
        expected_block_count           = 0;
        expected_frame_count           = 0;
        expected_rx_word_count         = 0;
        expected_block_last_word_count = 0;
        expected_frame_last_word_count = 0;
        actual_rx_word_count           = 0;
        actual_block_last_word_count   = 0;
        actual_frame_last_word_count   = 0;
        actual_tx_aes_word_count       = 0;
        actual_tx_aes_last_word_count  = 0;
        actual_tx_aes_word_idx_in_block= 0;
        compressed_word_count          = 0;
        compressed_payload_bits        = 0;
        compressed_payload_bytes_ceil  = 0;
        total_input_bits               = 0;
        total_aes_channel_bits         = 0;
        saved_bits                     = 0;
        tx_done_pulse_count            = 0;
        rx_done_pulse_count            = 0;
        tx_cipher_pulse_count          = 0;
        bridge_nonempty_seen_count     = 0;
        compression_ratio_pct          = 0.0;
        space_saving_pct               = 0.0;
        tx_status_r                    = 32'b0;
        tx_aes_status_r                = 32'b0;
        tx_aes_meta_r                  = 32'b0;
        tx_aes_data_r                  = 32'b0;
        rx_status_before_clear_r       = 32'b0;
        rx_status_after_clear_r        = 32'b0;
        rx_meta_r                      = 32'b0;
        rx_data_r                      = 32'b0;
        rx_valid_bytes_r               = 3'b000;

        for (i = 0; i < MAX_INPUT_BYTES; i = i + 1) begin
            input_mem[i]    = 8'h00;
            expected_mem[i] = 8'h00;
            actual_mem[i]   = 8'h00;
        end

        for (i = 0; i < MAX_COMPRESSED_WORDS; i = i + 1) begin
            compressed_word_mem[i]       = {TRANSPORT_WORD_WIDTH{1'b0}};
            compressed_valid_bits_mem[i] = {VALID_BITS_WIDTH{1'b0}};
            compressed_last_mem[i]       = 1'b0;
        end

        for (i = 0; i < MAX_BLOCKS; i = i + 1) begin
            block_base[i]     = 0;
            block_len[i]      = 0;
            block_continue[i] = 0;
            expected_mode[i]  = -1;
        end
    end
    endtask

    task reset_dut;
    begin
        clear_buses;
        clear_vectors;
        PRESETn = 1'b0;
        repeat (6) @(posedge PCLK);
        #TB_DLY;
        PRESETn = 1'b1;
        repeat (6) @(posedge PCLK);
        #TB_DLY;
    end
    endtask

    task load_input_file;
    begin
        text_len                = 0;
        unsupported_input_bytes = 0;

        fd = $fopen("input2.txt", "r");
        if (fd == 0) begin
            $display("[FAIL] cannot open file: input.txt");
            fail_count = fail_count + 1;
            $finish;
        end

        while (!$feof(fd)) begin
            ch = $fgetc(fd);
            if (ch != -1) begin
                if (text_len < MAX_INPUT_BYTES) begin
                    if (ch != 8'h0D) begin
                        input_mem[text_len]    = ch[7:0];
                        expected_mem[text_len] = normalize_byte(ch[7:0]);
                        if ((ch[7:0] != 8'h0A) &&
                            ((ch[7:0] < ASCII_MIN) || (ch[7:0] > ASCII_MAX)))
                            unsupported_input_bytes = unsupported_input_bytes + 1;
                        text_len = text_len + 1;
                    end
                end
                else begin
                    $display("[FAIL] input file too large, increase MAX_INPUT_BYTES");
                    fail_count = fail_count + 1;
                    $finish;
                end
            end
        end

        $fclose(fd);
    end
    endtask

    task build_case_from_input_file;
        integer base_idx;
        integer blk_len;
    begin
        expected_block_count = 0;
        base_idx             = 0;

        while (base_idx < text_len) begin
            if ((text_len - base_idx) > MAX_SYMBOLS_PER_BLOCK)
                blk_len = MAX_SYMBOLS_PER_BLOCK;
            else
                blk_len = text_len - base_idx;

            if (expected_block_count >= MAX_BLOCKS) begin
                $display("[FAIL] too many blocks for MAX_BLOCKS=%0d", MAX_BLOCKS);
                fail_count = fail_count + 1;
                $finish;
            end

            set_block_desc(expected_block_count,
                           base_idx,
                           blk_len,
                           ((base_idx + blk_len) < text_len) ? 1 : 0,
                           -1);

            expected_block_count = expected_block_count + 1;
            base_idx             = base_idx + blk_len;
        end

        finalize_case_vectors;
    end
    endtask

    task open_dump_files;
    begin
        system_rc = $system("mkdir -p loopback");
        pre_dump_fd      = $fopen("loopback/loopback_pre_compress_dump.txt", "w");
        compress_dump_fd = $fopen("loopback/loopback_post_compress_dump.txt", "w");
        post_dump_fd     = $fopen("loopback/loopback_post_decode_dump.txt", "w");
        ascii_dump_fd = $fopen("loopback/loopback_ascii_compare.txt", "w");

        if (pre_dump_fd == 0) begin
            $display("[FAIL] could not open loopback/loopback_pre_compress_dump.txt");
            fail_count = fail_count + 1;
        end

        if (post_dump_fd == 0) begin
            $display("[FAIL] could not open loopback/loopback_post_decode_dump.txt");
            fail_count = fail_count + 1;
        end

        if (compress_dump_fd == 0) begin
            $display("[FAIL] could not open loopback/loopback_post_compress_dump.txt");
            fail_count = fail_count + 1;
        end

        if (ascii_dump_fd == 0) begin
            $display("[FAIL] could not open loopback/loopback_ascii_compare.txt");
            fail_count = fail_count + 1;
        end

        if (pre_dump_fd != 0) begin
            $fdisplay(pre_dump_fd, "TX/RX LOOPBACK PRE-COMPRESS DUMP");
            $fdisplay(pre_dump_fd, "format: case index raw_byte normalized_expected");
            $fdisplay(pre_dump_fd, "");
        end

        if (post_dump_fd != 0) begin
            $fdisplay(post_dump_fd, "TX/RX LOOPBACK POST-DECODE DUMP");
            $fdisplay(post_dump_fd, "format: case index actual_byte");
            $fdisplay(post_dump_fd, "");
        end

        if (compress_dump_fd != 0) begin
            $fdisplay(compress_dump_fd, "TX/RX LOOPBACK POST-COMPRESS DUMP");
            $fdisplay(compress_dump_fd, "format: case index frame_last valid_bits cumulative_bits transport_word payload");
            $fdisplay(compress_dump_fd, "");
        end

        if (ascii_dump_fd != 0) begin
            $fdisplay(ascii_dump_fd, "TX/RX LOOPBACK ASCII COMPARE");
            $fdisplay(ascii_dump_fd, "non-printable bytes are shown as '.', LF is written as a real newline, CR/TAB stay escaped as \\r \\t");
            $fdisplay(ascii_dump_fd, "");
        end
    end
    endtask

    task close_dump_files;
    begin
        if (pre_dump_fd != 0)
            $fclose(pre_dump_fd);

        if (compress_dump_fd != 0)
            $fclose(compress_dump_fd);

        if (post_dump_fd != 0)
            $fclose(post_dump_fd);

        if (ascii_dump_fd != 0)
            $fclose(ascii_dump_fd);
    end
    endtask

    task dump_pre_case;
        input [8*64-1:0] case_name;
    begin
        if (pre_dump_fd != 0) begin
            $fdisplay(pre_dump_fd, "===== CASE %0s =====", case_name);
            $fdisplay(pre_dump_fd, "input_file=input.txt total_bytes=%0d block_count=%0d frame_count=%0d unsupported_input_bytes=%0d",
                      expected_total_bytes,
                      expected_block_count,
                      expected_frame_count,
                      unsupported_input_bytes);

            for (i = 0; i < expected_total_bytes; i = i + 1)
                $fdisplay(pre_dump_fd,
                          "%0s %0d %02x %02x",
                          case_name,
                          i,
                          input_mem[i],
                          expected_mem[i]);

            $fdisplay(pre_dump_fd, "");
        end
    end
    endtask

    task dump_compressed_case;
        input [8*64-1:0] case_name;
        integer idx;
        integer cumulative_bits;
    begin
        if (compress_dump_fd != 0) begin
            cumulative_bits = 0;
            $fdisplay(compress_dump_fd, "===== CASE %0s =====", case_name);
            $fdisplay(compress_dump_fd,
                      "compressed_words=%0d compressed_bits=%0d transport_payload_bits=%0d",
                      compressed_word_count,
                      compressed_payload_bits,
                      TRANSPORT_PAYLOAD_WIDTH);

            for (idx = 0; idx < compressed_word_count; idx = idx + 1) begin
                cumulative_bits = cumulative_bits + compressed_valid_bits_mem[idx];
                $fdisplay(compress_dump_fd,
                          "%0s %0d %0d %0d %0d %032x %030x",
                          case_name,
                          idx,
                          compressed_last_mem[idx],
                          compressed_valid_bits_mem[idx],
                          cumulative_bits,
                          compressed_word_mem[idx],
                          compressed_word_mem[idx][TRANSPORT_PAYLOAD_WIDTH-1:0]);
            end

            $fdisplay(compress_dump_fd, "");
        end
    end
    endtask

    task dump_ascii_pre_case;
        input [8*64-1:0] case_name;
        integer idx;
    begin
        if (ascii_dump_fd != 0) begin
            $fdisplay(ascii_dump_fd, "===== CASE %0s =====", case_name);
            $fdisplay(ascii_dump_fd,
                      "input_file=input.txt expected_total_bytes=%0d block_count=%0d frame_count=%0d unsupported_input_bytes=%0d",
                      expected_total_bytes,
                      expected_block_count,
                      expected_frame_count,
                      unsupported_input_bytes);

            $fwrite(ascii_dump_fd, "PRE_RAW      : ");
            for (idx = 0; idx < expected_total_bytes; idx = idx + 1)
                fwrite_ascii_token(ascii_dump_fd, input_mem[idx]);
            $fdisplay(ascii_dump_fd, "");

            $fwrite(ascii_dump_fd, "PRE_EXPECTED : ");
            for (idx = 0; idx < expected_total_bytes; idx = idx + 1)
                fwrite_ascii_token(ascii_dump_fd, expected_mem[idx]);
            $fdisplay(ascii_dump_fd, "");
        end
    end
    endtask

    task dump_post_case;
        input [8*64-1:0] case_name;
    begin
        if (post_dump_fd != 0) begin
            $fdisplay(post_dump_fd, "===== CASE %0s =====", case_name);
            $fdisplay(post_dump_fd, "decoded_bytes=%0d", actual_total_bytes);

            for (i = 0; i < actual_total_bytes; i = i + 1)
                $fdisplay(post_dump_fd,
                          "%0s %0d %02x",
                          case_name,
                          i,
                          actual_mem[i]);

            $fdisplay(post_dump_fd, "");
        end
    end
    endtask

    task dump_ascii_post_case;
        input [8*64-1:0] case_name;
        integer idx;
    begin
        if (ascii_dump_fd != 0) begin
            $fdisplay(ascii_dump_fd, "actual_total_bytes=%0d", actual_total_bytes);
            $fdisplay(ascii_dump_fd,
                      "input_bits=%0d compressed_bits=%0d compressed_bytes_ceil=%0d aes_channel_bits=%0d packed_aes_words=%0d transport_payload_bits=%0d",
                      total_input_bits,
                      compressed_payload_bits,
                      compressed_payload_bytes_ceil,
                      total_aes_channel_bits,
                      tx_cipher_pulse_count,
                      TRANSPORT_PAYLOAD_WIDTH);
            $fdisplay(ascii_dump_fd,
                      "compression_ratio=%0.2f%% space_saving=%0.2f%%",
                      compression_ratio_pct,
                      space_saving_pct);

            $fwrite(ascii_dump_fd, "POST_DECODED : ");
            for (idx = 0; idx < actual_total_bytes; idx = idx + 1)
                fwrite_ascii_token(ascii_dump_fd, actual_mem[idx]);
            $fdisplay(ascii_dump_fd, "");
            $fdisplay(ascii_dump_fd, "");
        end
    end
    endtask

    task check1;
        input actual;
        input expected;
        input [8*96-1:0] name;
    begin
        if (actual === expected) begin
            $display("[PASS] %0s | actual=%0d expected=%0d", name, actual, expected);
            pass_count = pass_count + 1;
        end
        else begin
            $display("[FAIL] %0s | actual=%0d expected=%0d", name, actual, expected);
            fail_count = fail_count + 1;
        end
    end
    endtask

    task check_int;
        input integer actual;
        input integer expected;
        input [8*96-1:0] name;
    begin
        if (actual == expected) begin
            $display("[PASS] %0s | actual=%0d expected=%0d", name, actual, expected);
            pass_count = pass_count + 1;
        end
        else begin
            $display("[FAIL] %0s | actual=%0d expected=%0d", name, actual, expected);
            fail_count = fail_count + 1;
        end
    end
    endtask

    task apb_tx_write;
        input  [31:0] addr;
        input  [31:0] data;
        output        err;
        output integer wait_cycles;
        reg sampled_err;
    begin : apb_tx_write_blk
        err         = 1'b0;
        wait_cycles = 0;
        sampled_err = 1'b0;

        @(posedge PCLK);
        #TB_DLY;
        tx_PSEL    = 1'b1;
        tx_PENABLE = 1'b0;
        tx_PWRITE  = 1'b1;
        tx_PADDR   = addr;
        tx_PWDATA  = data;

        @(posedge PCLK);
        #TB_DLY;
        tx_PENABLE = 1'b1;

        local_timeout = 0;
        while (1'b1) begin
            @(negedge PCLK);
            #1;
            if (tx_PREADY === 1'b1) begin
                sampled_err = tx_PSLVERR;
                @(posedge PCLK);
                #TB_DLY;
                clear_buses;
                err = sampled_err;
                disable apb_tx_write_blk;
            end
            else begin
                wait_cycles   = wait_cycles + 1;
                local_timeout = local_timeout + 1;
                if (local_timeout > 5000) begin
                    $display("[FAIL] apb_tx_write timeout addr=0x%08x data=0x%08x", addr, data);
                    fail_count = fail_count + 1;
                    @(posedge PCLK);
                    #TB_DLY;
                    clear_buses;
                    disable apb_tx_write_blk;
                end
            end
        end
    end
    endtask

    task apb_tx_read;
        input  [31:0] addr;
        output [31:0] data;
        output        err;
        output integer wait_cycles;
        reg [31:0] sampled_data;
        reg sampled_err;
    begin : apb_tx_read_blk
        data         = 32'b0;
        err          = 1'b0;
        wait_cycles  = 0;
        sampled_data = 32'b0;
        sampled_err  = 1'b0;

        @(posedge PCLK);
        #TB_DLY;
        tx_PSEL    = 1'b1;
        tx_PENABLE = 1'b0;
        tx_PWRITE  = 1'b0;
        tx_PADDR   = addr;
        tx_PWDATA  = 32'b0;

        @(posedge PCLK);
        #TB_DLY;
        tx_PENABLE = 1'b1;

        local_timeout = 0;
        while (1'b1) begin
            @(negedge PCLK);
            #1;
            if (tx_PREADY === 1'b1) begin
                sampled_data = tx_PRDATA;
                sampled_err  = tx_PSLVERR;
                @(posedge PCLK);
                #TB_DLY;
                clear_buses;
                data = sampled_data;
                err  = sampled_err;
                disable apb_tx_read_blk;
            end
            else begin
                wait_cycles   = wait_cycles + 1;
                local_timeout = local_timeout + 1;
                if (local_timeout > 5000) begin
                    $display("[FAIL] apb_tx_read timeout addr=0x%08x", addr);
                    fail_count = fail_count + 1;
                    @(posedge PCLK);
                    #TB_DLY;
                    clear_buses;
                    disable apb_tx_read_blk;
                end
            end
        end
    end
    endtask

    task apb_rx_write;
        input  [31:0] addr;
        input  [31:0] data;
        output        err;
        output integer wait_cycles;
        reg sampled_err;
    begin : apb_rx_write_blk
        err         = 1'b0;
        wait_cycles = 0;
        sampled_err = 1'b0;

        @(posedge PCLK);
        #TB_DLY;
        rx_PSEL    = 1'b1;
        rx_PENABLE = 1'b0;
        rx_PWRITE  = 1'b1;
        rx_PADDR   = addr;
        rx_PWDATA  = data;

        @(posedge PCLK);
        #TB_DLY;
        rx_PENABLE = 1'b1;

        local_timeout = 0;
        while (1'b1) begin
            @(negedge PCLK);
            #1;
            if (rx_PREADY === 1'b1) begin
                sampled_err = rx_PSLVERR;
                @(posedge PCLK);
                #TB_DLY;
                clear_buses;
                err = sampled_err;
                disable apb_rx_write_blk;
            end
            else begin
                wait_cycles   = wait_cycles + 1;
                local_timeout = local_timeout + 1;
                if (local_timeout > 5000) begin
                    $display("[FAIL] apb_rx_write timeout addr=0x%08x data=0x%08x", addr, data);
                    fail_count = fail_count + 1;
                    @(posedge PCLK);
                    #TB_DLY;
                    clear_buses;
                    disable apb_rx_write_blk;
                end
            end
        end
    end
    endtask

    task apb_rx_read;
        input  [31:0] addr;
        output [31:0] data;
        output        err;
        output integer wait_cycles;
        reg [31:0] sampled_data;
        reg sampled_err;
    begin : apb_rx_read_blk
        data         = 32'b0;
        err          = 1'b0;
        wait_cycles  = 0;
        sampled_data = 32'b0;
        sampled_err  = 1'b0;

        @(posedge PCLK);
        #TB_DLY;
        rx_PSEL    = 1'b1;
        rx_PENABLE = 1'b0;
        rx_PWRITE  = 1'b0;
        rx_PADDR   = addr;
        rx_PWDATA  = 32'b0;

        @(posedge PCLK);
        #TB_DLY;
        rx_PENABLE = 1'b1;

        local_timeout = 0;
        while (1'b1) begin
            @(negedge PCLK);
            #1;
            if (rx_PREADY === 1'b1) begin
                sampled_data = rx_PRDATA;
                sampled_err  = rx_PSLVERR;
                @(posedge PCLK);
                #TB_DLY;
                clear_buses;
                data = sampled_data;
                err  = sampled_err;
                disable apb_rx_read_blk;
            end
            else begin
                wait_cycles   = wait_cycles + 1;
                local_timeout = local_timeout + 1;
                if (local_timeout > 5000) begin
                    $display("[FAIL] apb_rx_read timeout addr=0x%08x", addr);
                    fail_count = fail_count + 1;
                    @(posedge PCLK);
                    #TB_DLY;
                    clear_buses;
                    disable apb_rx_read_blk;
                end
            end
        end
    end
    endtask

    task set_block_desc;
        input integer block_id;
        input integer base;
        input integer count;
        input integer continue_frame;
        input integer exp_mode;
    begin
        block_base[block_id]     = base;
        block_len[block_id]      = count;
        block_continue[block_id] = continue_frame;
        expected_mode[block_id]  = exp_mode;
    end
    endtask

    task put_input_byte;
        input integer index;
        input [7:0] raw_byte;
    begin
        input_mem[index]    = raw_byte;
        expected_mem[index] = normalize_byte(raw_byte);
    end
    endtask

    task finalize_case_vectors;
    begin
        expected_total_bytes           = 0;
        expected_frame_count           = 0;
        expected_rx_word_count         = 0;
        expected_block_last_word_count = expected_block_count;
        expected_frame_last_word_count = 0;

        for (j = 0; j < expected_block_count; j = j + 1) begin
            expected_total_bytes   = expected_total_bytes + block_len[j];
            expected_rx_word_count = expected_rx_word_count + ((block_len[j] + 3) / 4);
            if (block_continue[j] == 0)
                expected_frame_count = expected_frame_count + 1;
        end

        expected_frame_last_word_count = expected_frame_count;
    end
    endtask

    task build_case_single_byte_raw_partial;
    begin
        expected_block_count = 1;
        set_block_desc(0, 0, 1, 0, MODE_RAW_PARTIAL);
        put_input_byte(0, 8'h5A);
        finalize_case_vectors;
    end
    endtask

    task build_case_raw_partial_unique_31;
    begin
        expected_block_count = 1;
        set_block_desc(0, 0, 31, 0, MODE_RAW_PARTIAL);
        for (j = 0; j < 31; j = j + 1)
            put_input_byte(j, (8'h41 + j[7:0]));
        finalize_case_vectors;
    end
    endtask

    task build_case_raw_full_unique_32;
    begin
        expected_block_count = 1;
        set_block_desc(0, 0, 32, 0, MODE_RAW_FULL);
        for (j = 0; j < 32; j = j + 1)
            put_input_byte(j, (8'h30 + j[7:0]));
        finalize_case_vectors;
    end
    endtask

    task build_case_one_symbol_two_frames;
    begin
        expected_block_count = 2;

        set_block_desc(0, 0, 2, 0, MODE_ONE_SYMBOL);
        put_input_byte(0, 8'h51);
        put_input_byte(1, 8'h51);

        set_block_desc(1, 2, 32, 0, MODE_ONE_SYMBOL);
        for (j = 0; j < 32; j = j + 1)
            put_input_byte(2 + j, 8'h52);

        finalize_case_vectors;
    end
    endtask

    task build_case_compressed_multiblock_single_frame;
    begin
        expected_block_count = 2;

        set_block_desc(0, 0, 8, 1, MODE_COMPRESSED);
        put_input_byte(0, 8'h41);
        put_input_byte(1, 8'h42);
        put_input_byte(2, 8'h41);
        put_input_byte(3, 8'h42);
        put_input_byte(4, 8'h41);
        put_input_byte(5, 8'h42);
        put_input_byte(6, 8'h41);
        put_input_byte(7, 8'h42);

        set_block_desc(1, 8, 12, 0, MODE_COMPRESSED);
        put_input_byte(8,  8'h58);
        put_input_byte(9,  8'h59);
        put_input_byte(10, 8'h58);
        put_input_byte(11, 8'h59);
        put_input_byte(12, 8'h58);
        put_input_byte(13, 8'h59);
        put_input_byte(14, 8'h58);
        put_input_byte(15, 8'h59);
        put_input_byte(16, 8'h58);
        put_input_byte(17, 8'h59);
        put_input_byte(18, 8'h58);
        put_input_byte(19, 8'h59);

        finalize_case_vectors;
    end
    endtask

    task build_case_mixed_modes_multiframe;
    begin
        expected_block_count = 4;

        set_block_desc(0, 0, 5, 1, MODE_ONE_SYMBOL);
        put_input_byte(0, 8'h41);
        put_input_byte(1, 8'h41);
        put_input_byte(2, 8'h41);
        put_input_byte(3, 8'h41);
        put_input_byte(4, 8'h41);

        set_block_desc(1, 5, 7, 0, MODE_RAW_PARTIAL);
        put_input_byte(5,  8'h48);
        put_input_byte(6,  8'h45);
        put_input_byte(7,  8'h4C);
        put_input_byte(8,  8'h4C);
        put_input_byte(9,  8'h4F);
        put_input_byte(10, 8'h21);
        put_input_byte(11, 8'h21);

        set_block_desc(2, 12, 6, 1, MODE_ONE_SYMBOL);
        put_input_byte(12, 8'h42);
        put_input_byte(13, 8'h42);
        put_input_byte(14, 8'h42);
        put_input_byte(15, 8'h42);
        put_input_byte(16, 8'h42);
        put_input_byte(17, 8'h42);

        set_block_desc(3, 18, 9, 0, MODE_COMPRESSED);
        put_input_byte(18, 8'h58);
        put_input_byte(19, 8'h59);
        put_input_byte(20, 8'h58);
        put_input_byte(21, 8'h59);
        put_input_byte(22, 8'h58);
        put_input_byte(23, 8'h59);
        put_input_byte(24, 8'h58);
        put_input_byte(25, 8'h59);
        put_input_byte(26, 8'h21);

        finalize_case_vectors;
    end
    endtask

    task build_case_remap_and_normalized_mode_switch;
    begin
        expected_block_count = 2;

        set_block_desc(0, 0, 5, 1, MODE_RAW_PARTIAL);
        put_input_byte(0, 8'h10);
        put_input_byte(1, 8'h41);
        put_input_byte(2, 8'h00);
        put_input_byte(3, 8'h7F);
        put_input_byte(4, 8'h42);

        set_block_desc(1, 5, 4, 0, MODE_ONE_SYMBOL);
        put_input_byte(5, 8'h09);
        put_input_byte(6, 8'h0A);
        put_input_byte(7, 8'h1F);
        put_input_byte(8, 8'h80);

        finalize_case_vectors;
    end
    endtask

    task wait_tx_done_or_error;
        output integer done_seen;
        output integer error_seen;
        input integer max_polls;
        integer polls;
    begin
        done_seen  = 0;
        error_seen = 0;
        polls      = 0;

        while ((polls < max_polls) && (done_seen == 0) && (error_seen == 0)) begin
            service_background_io;
            apb_tx_read(TX_ADDR_STATUS, tx_status_r, apb_err, apb_waits);
            if (apb_err) begin
                error_seen = 1;
            end
            else begin
                if (tx_status_r[4]) done_seen  = 1;
                if (tx_status_r[5]) error_seen = 1;
            end
            polls = polls + 1;
        end

        if ((done_seen == 0) && (error_seen == 0)) begin
            $display("[FAIL] wait_tx_done_or_error timeout");
            fail_count = fail_count + 1;
        end
    end
    endtask

    task record_rx_word;
        input [31:0] meta_word;
        input [31:0] data_word;
        integer local_byte_lane;
    begin
        rx_valid_bytes_r = meta_word[2:0];
        actual_rx_word_count = actual_rx_word_count + 1;

        if (meta_word[3])
            actual_block_last_word_count = actual_block_last_word_count + 1;

        if (meta_word[4])
            actual_frame_last_word_count = actual_frame_last_word_count + 1;

        if ((rx_valid_bytes_r < 3'd1) || (rx_valid_bytes_r > 3'd4)) begin
            $display("[FAIL] rx_valid_bytes_out_of_range_during_service | meta=0x%08x", meta_word);
            fail_count = fail_count + 1;
        end

        if (meta_word[4] && !meta_word[3]) begin
            $display("[FAIL] last_in_frame without last_in_block");
            fail_count = fail_count + 1;
        end

        for (local_byte_lane = 0; local_byte_lane < rx_valid_bytes_r; local_byte_lane = local_byte_lane + 1) begin
            if (actual_total_bytes < MAX_INPUT_BYTES) begin
                actual_mem[actual_total_bytes] = data_word[(8*local_byte_lane)+7 -: 8];
                actual_total_bytes = actual_total_bytes + 1;
            end
            else begin
                $display("[FAIL] actual_mem overflow");
                fail_count = fail_count + 1;
                $finish;
            end
        end
    end
    endtask

    task record_tx_aes_word;
        input [31:0] meta_word;
    begin
        actual_tx_aes_word_count      = actual_tx_aes_word_count + 1;
        actual_tx_aes_word_idx_in_block = actual_tx_aes_word_idx_in_block + 1;

        if (meta_word[0]) begin
            actual_tx_aes_last_word_count = actual_tx_aes_last_word_count + 1;
            if (actual_tx_aes_word_idx_in_block != 4) begin
                $display("[FAIL] tx_aes_out_last_should_arrive_on_4th_word | actual=%0d expected=4",
                         actual_tx_aes_word_idx_in_block);
                fail_count = fail_count + 1;
            end
            actual_tx_aes_word_idx_in_block = 0;
        end
        else if (actual_tx_aes_word_idx_in_block >= 4) begin
            $display("[FAIL] tx_aes_out_non_last_word_index_should_be_lt_4 | actual=%0d expected<4",
                     actual_tx_aes_word_idx_in_block);
            fail_count = fail_count + 1;
        end
    end
    endtask

    task service_rx_fifo_once;
    begin
        apb_rx_read(RX_ADDR_STATUS, apb_rdata, apb_err, apb_waits);
        if (apb_err) begin
            $display("[FAIL] rx_service_status_read_should_succeed");
            fail_count = fail_count + 1;
        end
        else if (apb_rdata[0]) begin
            apb_rx_read(RX_ADDR_META, rx_meta_r, apb_err, apb_waits);
            if (apb_err) begin
                $display("[FAIL] rx_service_meta_read_should_succeed");
                fail_count = fail_count + 1;
            end
            else begin
                apb_rx_read(RX_ADDR_DATA, rx_data_r, apb_err, apb_waits);
                if (apb_err) begin
                    $display("[FAIL] rx_service_data_read_should_succeed");
                    fail_count = fail_count + 1;
                end
                else begin
                    record_rx_word(rx_meta_r, rx_data_r);
                end
            end
        end
    end
    endtask

    task service_tx_aes_out_once;
    begin
        apb_tx_read(TX_ADDR_AES_OUT_STATUS, tx_aes_status_r, apb_err, apb_waits);
        if (apb_err) begin
            $display("[FAIL] tx_aes_out_service_status_read_should_succeed");
            fail_count = fail_count + 1;
        end
        else if (tx_aes_status_r[0]) begin
            apb_tx_read(TX_ADDR_AES_OUT_META, tx_aes_meta_r, apb_err, apb_waits);
            if (apb_err) begin
                $display("[FAIL] tx_aes_out_service_meta_read_should_succeed");
                fail_count = fail_count + 1;
            end
            else begin
                apb_tx_read(TX_ADDR_AES_OUT_DATA, tx_aes_data_r, apb_err, apb_waits);
                if (apb_err) begin
                    $display("[FAIL] tx_aes_out_service_data_read_should_succeed");
                    fail_count = fail_count + 1;
                end
                else begin
                    record_tx_aes_word(tx_aes_meta_r);
                end
            end
        end
    end
    endtask

    task service_background_io;
    begin
        service_rx_fifo_once;
        service_tx_aes_out_once;
    end
    endtask

    task send_one_block;
        input integer block_id;
        integer base;
        integer count;
        integer has_more_blocks;
        integer word_idx;
    begin
        base            = block_base[block_id];
        count           = block_len[block_id];
        has_more_blocks = block_continue[block_id];
        words_needed    = (count + 3) / 4;

        $display("send block %0d | base=%0d len=%0d continue_frame=%0d expected_mode=%0d",
                 block_id, base, count, has_more_blocks, expected_mode[block_id]);

        apb_tx_write(TX_ADDR_BLOCK_SIZE, count, apb_err, apb_waits);
        check1(apb_err, 1'b0, "tx_block_size_write_should_succeed");

        for (word_idx = 0; word_idx < words_needed; word_idx = word_idx + 1) begin
            b0 = input_mem[base + (4*word_idx) + 0];
            b1 = 8'h00;
            b2 = 8'h00;
            b3 = 8'h00;

            if ((4*word_idx + 1) < count) b1 = input_mem[base + (4*word_idx) + 1];
            if ((4*word_idx + 2) < count) b2 = input_mem[base + (4*word_idx) + 2];
            if ((4*word_idx + 3) < count) b3 = input_mem[base + (4*word_idx) + 3];

            word_v = pack_word4(b0, b1, b2, b3);
            apb_tx_write(TX_ADDR_WORD_IN, word_v, apb_err, apb_waits);
            check1(apb_err, 1'b0, "tx_word_in_write_should_succeed");
        end

        apb_tx_read(TX_ADDR_STATUS, tx_status_r, apb_err, apb_waits);
        check1(apb_err, 1'b0, "tx_status_read_should_succeed");
        check1(tx_status_r[7], 1'b1, "tx_can_start_should_be_1");

        apb_tx_write(TX_ADDR_START_BLOCK,
                     has_more_blocks ? 32'h0000_0003 : 32'h0000_0001,
                     apb_err,
                     apb_waits);
        check1(apb_err, 1'b0, "tx_start_block_write_should_succeed");

        wait_tx_done_or_error(got_done, got_error, 20000);
        check_int(got_done, 1, "tx_done_should_be_seen");
        check_int(got_error, 0, "tx_error_should_not_be_seen");
        check1(tx_error, 1'b0, "tx_error_should_be_0");

        if (expected_mode[block_id] >= 0)
            check_int(tx_selected_mode_out, expected_mode[block_id], "tx_selected_mode_should_match_expected");

        apb_tx_write(TX_ADDR_CONTROL, 32'h0000_0002, apb_err, apb_waits);
        check1(apb_err, 1'b0, "tx_clear_done_should_succeed");

        apb_tx_write(TX_ADDR_CONTROL, 32'h0000_0004, apb_err, apb_waits);
        check1(apb_err, 1'b0, "tx_clear_error_should_succeed");
    end
    endtask

    task wait_rx_done_or_error;
        output integer done_seen;
        output integer error_seen;
        input integer max_cycles;
        integer polls;
    begin
        done_seen  = 0;
        error_seen = 0;
        polls      = 0;

        while ((polls < max_cycles) && (done_seen == 0) && (error_seen == 0)) begin
            @(posedge PCLK);
            #TB_DLY;

            service_background_io;

            if (rx_done_pulse_count >= expected_frame_count)
                done_seen = 1;

            if (rx_error)
                error_seen = 1;

            polls = polls + 1;
        end

        if ((done_seen == 0) && (error_seen == 0)) begin
            $display("[FAIL] wait_rx_done_or_error timeout");
            fail_count = fail_count + 1;
        end
    end
    endtask

    task wait_system_idle;
        input integer max_cycles;
        integer stable_cycles;
        integer polls;
    begin : wait_system_idle_blk
        stable_cycles = 0;
        polls         = 0;

        while (polls < max_cycles) begin
            @(posedge PCLK);
            #TB_DLY;

            service_background_io;

            if ((tx_busy == 1'b0) &&
                (rx_busy == 1'b0) &&
                (tx_error == 1'b0) &&
                (rx_error == 1'b0) &&
                (bridge_nonempty == 1'b0) &&
                (tx_aes_ready_out_dbg == 1'b1)) begin
                stable_cycles = stable_cycles + 1;
                if (stable_cycles >= 8)
                    disable wait_system_idle_blk;
            end
            else begin
                stable_cycles = 0;
            end

            polls = polls + 1;
        end

        $display("[FAIL] wait_system_idle timeout");
        fail_count = fail_count + 1;
    end
    endtask

    task drain_rx_fifo_and_check;
    begin : drain_rx_fifo_and_check_blk
        apb_rx_read(RX_ADDR_STATUS, rx_status_before_clear_r, apb_err, apb_waits);
        check1(apb_err, 1'b0, "rx_status_before_clear_should_succeed");
        check1(rx_status_before_clear_r[3], 1'b1, "rx_block_done_sticky_should_be_1");
        check1(rx_status_before_clear_r[4], 1'b1, "rx_frame_done_sticky_should_be_1");
        check1(rx_status_before_clear_r[5], 1'b0, "rx_error_sticky_should_be_0");

        while (1'b1) begin
            apb_rx_read(RX_ADDR_STATUS, apb_rdata, apb_err, apb_waits);
            check1(apb_err, 1'b0, "rx_status_poll_should_succeed");

            if (apb_rdata[0] == 1'b0)
                disable drain_rx_fifo_and_check_blk;

            apb_rx_read(RX_ADDR_META, rx_meta_r, apb_err, apb_waits);
            check1(apb_err, 1'b0, "rx_meta_read_should_succeed");

            apb_rx_read(RX_ADDR_DATA, rx_data_r, apb_err, apb_waits);
            check1(apb_err, 1'b0, "rx_data_read_should_succeed");
            record_rx_word(rx_meta_r, rx_data_r);
            check1((rx_meta_r[2:0] >= 3'd1), 1'b1, "rx_valid_bytes_should_be_ge_1");
            check1((rx_meta_r[2:0] <= 3'd4), 1'b1, "rx_valid_bytes_should_be_le_4");
        end
    end
    endtask

    task drain_tx_aes_out_fifo_and_check;
    begin : drain_tx_aes_out_fifo_and_check_blk
        apb_tx_read(TX_ADDR_AES_OUT_STATUS, tx_aes_status_r, apb_err, apb_waits);
        check1(apb_err, 1'b0, "tx_aes_out_status_before_drain_should_succeed");

        while (1'b1) begin
            apb_tx_read(TX_ADDR_AES_OUT_STATUS, tx_aes_status_r, apb_err, apb_waits);
            check1(apb_err, 1'b0, "tx_aes_out_status_poll_should_succeed");

            if (tx_aes_status_r[0] == 1'b0)
                disable drain_tx_aes_out_fifo_and_check_blk;

            apb_tx_read(TX_ADDR_AES_OUT_META, tx_aes_meta_r, apb_err, apb_waits);
            check1(apb_err, 1'b0, "tx_aes_out_meta_read_should_succeed");

            apb_tx_read(TX_ADDR_AES_OUT_DATA, tx_aes_data_r, apb_err, apb_waits);
            check1(apb_err, 1'b0, "tx_aes_out_data_read_should_succeed");
            record_tx_aes_word(tx_aes_meta_r);
        end
    end
    endtask

    task check_tx_aes_out_post_drain;
    begin
        apb_tx_read(TX_ADDR_AES_OUT_STATUS, tx_aes_status_r, apb_err, apb_waits);
        check1(apb_err, 1'b0, "tx_aes_out_status_after_drain_should_succeed");
        check1(tx_aes_status_r[0], 1'b0, "tx_aes_out_fifo_should_be_empty_after_drain");
    end
    endtask

    task check_post_drain_and_clear;
    begin
        apb_rx_read(RX_ADDR_STATUS, apb_rdata, apb_err, apb_waits);
        check1(apb_err, 1'b0, "rx_status_after_drain_should_succeed");
        check1(apb_rdata[0], 1'b0, "rx_fifo_nonempty_should_be_0_after_drain");

        apb_rx_read(RX_ADDR_META, rx_meta_r, apb_err, apb_waits);
        check1(apb_err, 1'b0, "rx_meta_after_drain_should_succeed");
        check_int(rx_meta_r, 0, "rx_meta_after_drain_should_be_0");

        apb_rx_write(RX_ADDR_CONTROL, 32'h0000_0002, apb_err, apb_waits);
        check1(apb_err, 1'b0, "rx_clear_done_should_succeed");

        apb_rx_write(RX_ADDR_CONTROL, 32'h0000_0004, apb_err, apb_waits);
        check1(apb_err, 1'b0, "rx_clear_error_should_succeed");

        apb_rx_read(RX_ADDR_STATUS, rx_status_after_clear_r, apb_err, apb_waits);
        check1(apb_err, 1'b0, "rx_status_after_clear_should_succeed");
        check1(rx_status_after_clear_r[3], 1'b0, "rx_block_done_sticky_should_clear");
        check1(rx_status_after_clear_r[4], 1'b0, "rx_frame_done_sticky_should_clear");
        check1(rx_status_after_clear_r[5], 1'b0, "rx_error_sticky_should_remain_0");
    end
    endtask

    task compare_expected_bytes;
        input [8*64-1:0] case_name;
    begin
        check_int(actual_rx_word_count,
                  expected_rx_word_count,
                  "rx_word_count_should_match_expected_block_packing");
        check_int(actual_block_last_word_count,
                  expected_block_last_word_count,
                  "last_in_block_word_count_should_match_block_count");
        check_int(actual_frame_last_word_count,
                  expected_frame_last_word_count,
                  "last_in_frame_word_count_should_match_frame_count");
        check_int(actual_total_bytes,
                  expected_total_bytes,
                  "loopback_byte_count_should_match");

        for (i = 0; i < expected_total_bytes; i = i + 1) begin
            if (actual_mem[i] === expected_mem[i]) begin
                pass_count = pass_count + 1;
            end
            else begin
                $display("[FAIL] %0s byte mismatch at index %0d | actual=0x%02x expected=0x%02x",
                         case_name, i, actual_mem[i], expected_mem[i]);
                fail_count = fail_count + 1;
            end
        end
    end
    endtask

    task print_compression_summary;
        input [8*64-1:0] case_name;
    begin
        total_input_bits              = expected_total_bytes * 8;
        compressed_payload_bytes_ceil = (compressed_payload_bits + 7) / 8;
        total_aes_channel_bits        = tx_cipher_pulse_count * 128;
        saved_bits                    = total_input_bits - compressed_payload_bits;

        if (total_input_bits > 0) begin
            compression_ratio_pct = (100.0 * compressed_payload_bits) / total_input_bits;
            space_saving_pct      = (100.0 * saved_bits) / total_input_bits;
        end
        else begin
            compression_ratio_pct = 0.0;
            space_saving_pct      = 0.0;
        end

        $display("\n===== COMPRESSION SUMMARY: %0s =====", case_name);
        $display("input file                 = input.txt");
        $display("input bytes                = %0d", expected_total_bytes);
        $display("unsupported bytes remapped = %0d", unsupported_input_bytes);
        $display("input bits                 = %0d", total_input_bits);
        $display("compressed bits            = %0d", compressed_payload_bits);
        $display("compressed bytes ceil      = %0d", compressed_payload_bytes_ceil);
        $display("aes channel bits           = %0d", total_aes_channel_bits);
        $display("transport payload bits     = %0d", TRANSPORT_PAYLOAD_WIDTH);
        $display("packed aes words emitted   = %0d", tx_cipher_pulse_count);
        $display("compression ratio          = %0.2f%%", compression_ratio_pct);
        $display("space saving               = %0.2f%%", space_saving_pct);
    end
    endtask

    task run_loopback_case;
        input [8*64-1:0] case_name;
    begin
        case_count = case_count + 1;
        actual_total_bytes             = 0;
        actual_rx_word_count           = 0;
        actual_block_last_word_count   = 0;
        actual_frame_last_word_count   = 0;
        actual_tx_aes_word_count       = 0;
        actual_tx_aes_last_word_count  = 0;
        actual_tx_aes_word_idx_in_block= 0;
        compressed_word_count          = 0;
        compressed_payload_bits        = 0;
        compressed_payload_bytes_ceil  = 0;
        total_input_bits               = 0;
        total_aes_channel_bits         = 0;
        saved_bits                     = 0;
        compression_ratio_pct          = 0.0;
        space_saving_pct               = 0.0;

        for (i = 0; i < MAX_INPUT_BYTES; i = i + 1)
            actual_mem[i] = 8'h00;

        $display("\n===== CASE %0d: %0s =====", case_count, case_name);
        dump_pre_case(case_name);
        dump_ascii_pre_case(case_name);

        for (block_idx = 0; block_idx < expected_block_count; block_idx = block_idx + 1)
            send_one_block(block_idx);

        wait_rx_done_or_error(got_done, got_error, 40000);
        check_int(got_done, 1, "rx_done_should_be_seen");
        check_int(got_error, 0, "rx_error_should_not_be_seen");

        wait_system_idle(8000);
        dump_compressed_case(case_name);

        $display("\n===== DRAIN TX AES OUT FIFO: %0s =====", case_name);
        drain_tx_aes_out_fifo_and_check;
        check_tx_aes_out_post_drain;

        $display("\n===== DRAIN RX FIFO: %0s =====", case_name);
        drain_rx_fifo_and_check;
        print_compression_summary(case_name);
        dump_post_case(case_name);
        dump_ascii_post_case(case_name);
        check_post_drain_and_clear;

        $display("\n===== LOOPBACK CHECKS: %0s =====", case_name);
        check1(tx_error, 1'b0, "tx_error_final_should_be_0");
        check1(rx_error, 1'b0, "rx_error_final_should_be_0");
        check1(bridge_error, 1'b0, "bridge_error_should_be_0");
        check1(rx_depacker_error, 1'b0, "depacker_error_should_be_0");
        check1(rx_parser_error, 1'b0, "parser_error_should_be_0");
        check1(rx_decoder_error, 1'b0, "decoder_error_should_be_0");
        check1(rx_word_packer_error, 1'b0, "word_packer_error_should_be_0");
        check_int(tx_done_pulse_count,
                  expected_block_count,
                  "tx_done_pulse_count_should_match_block_count");
        check_int(rx_done_pulse_count,
                  expected_frame_count,
                  "rx_done_pulse_count_should_match_frame_count");
        check1((tx_cipher_pulse_count > 0), 1'b1, "ciphertext_word_count_should_be_non_zero");
        check_int(actual_tx_aes_word_count,
                  (tx_cipher_pulse_count * 4),
                  "tx_aes_out_word_count_should_match_4_words_per_cipher_block");
        check_int(actual_tx_aes_last_word_count,
                  tx_cipher_pulse_count,
                  "tx_aes_out_last_word_count_should_match_cipher_block_count");
        check1((bridge_nonempty_seen_count > 0), 1'b1, "bridge_should_have_seen_activity");
        check1(bridge_nonempty, 1'b0, "bridge_should_be_empty");
        compare_expected_bytes(case_name);
    end
    endtask

    task check_reset_state;
    begin
        $display("\n===== RESET CHECK =====");
        check1(tx_busy, 1'b0, "reset_tx_busy");
        check1(tx_done, 1'b0, "reset_tx_done");
        check1(tx_error, 1'b0, "reset_tx_error");
        check1(rx_busy, 1'b0, "reset_rx_busy");
        check1(rx_done, 1'b0, "reset_rx_done");
        check1(rx_error, 1'b0, "reset_rx_error");
        check1(tx_aes_ready_out_dbg, 1'b1, "reset_tx_aes_ready_out");
        check1(rx_ciphertext_word_ready_dbg, 1'b1, "reset_rx_ciphertext_word_ready");
        check1(bridge_nonempty, 1'b0, "reset_bridge_nonempty");
        check1(bridge_error, 1'b0, "reset_bridge_error");
        apb_tx_read(TX_ADDR_AES_OUT_STATUS, tx_aes_status_r, apb_err, apb_waits);
        check1(apb_err, 1'b0, "reset_tx_aes_out_status_should_succeed");
        check1(tx_aes_status_r[0], 1'b0, "reset_tx_aes_out_fifo_should_be_empty");
    end
    endtask

    task check_input_file_loaded;
    begin
        $display("\n===== INPUT FILE CHECK =====");
        check1((text_len > 0), 1'b1, "input_file_should_not_be_empty");
        check1((expected_total_bytes == text_len), 1'b1, "expected_total_bytes_should_match_text_len");
    end
    endtask

    initial begin
        PRESETn    = 1'b0;
        pass_count = 0;
        fail_count = 0;
        case_count = 0;
        pre_dump_fd = 0;
        compress_dump_fd = 0;
        post_dump_fd = 0;
        ascii_dump_fd = 0;
        clear_buses;
        clear_vectors;
        open_dump_files;

        reset_dut;
        check_reset_state;
        load_input_file;
        build_case_from_input_file;
        check_input_file_loaded;
        run_loopback_case("input_txt_loopback");

        $display("\n===== FINAL RESULT =====");
        if (fail_count == 0)
            $display("[PASS] TX->AES->bridge->RX loopback for input.txt is correct.");
        else
            $display("[FAIL] TX->AES->bridge->RX loopback for input.txt has mismatches or protocol issues.");

        $display("\n===========================================================");
        $display("TX/RX INPUT.TXT LOOPBACK SUMMARY: CASES=%0d PASS=%0d FAIL=%0d",
                 case_count,
                 pass_count,
                 fail_count);
        $display("===========================================================");

        close_dump_files;

        #20;
        $finish;
    end

endmodule
