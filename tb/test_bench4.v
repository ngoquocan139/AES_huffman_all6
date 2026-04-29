`timescale 1ns/1ps

module test_bench;

    parameter BLOCK_SIZE_WIDTH      = 6;
    parameter BUFFER_ADDR_WIDTH     = 5;
    parameter SYMBOL_WIDTH          = 8;
    parameter SYMBOL_COUNT_WIDTH    = 6;
    parameter COUNT_WIDTH           = 6;
    parameter SYMBOL_INDEX_WIDTH    = 7;
    parameter CODE_LEN_WIDTH        = 5;
    parameter CODE_WIDTH            = 31;
    parameter HEADER_BITS_WIDTH     = 10;
    parameter TOTAL_BITS_WIDTH      = 11;
    parameter CHUNK_DATA_WIDTH      = 32;
    parameter CHUNK_LEN_WIDTH       = 6;
    parameter MAX_SYMBOLS_PER_BLOCK = 32;
    parameter MAX_TREE_NODES        = 63;
    parameter [7:0] ASCII_MIN       = 8'h20;
    parameter [7:0] ASCII_MAX       = 8'h7E;
    parameter TRANSPORT_WORD_WIDTH  = 128;
    parameter VALID_BITS_WIDTH      = 7;
    parameter [127:0] AES_KEY_FIXED = 128'h00112233445566778899AABBCCDDEEFF;

    parameter MAX_TEXT_BYTES = 16384;
    parameter MAX_AES_BLOCKS = 65536;

    localparam [31:0] ADDR_START_BLOCK = 32'h0000_0000;
    localparam [31:0] ADDR_BLOCK_SIZE  = 32'h0000_0004;
    localparam [31:0] ADDR_WORD_IN     = 32'h0000_0008;
    localparam [31:0] ADDR_STATUS      = 32'h0000_000C;
    localparam [31:0] ADDR_CONTROL     = 32'h0000_0010;
    localparam [31:0] ADDR_DEBUG       = 32'h0000_0014;
    localparam [31:0] ADDR_INVALID     = 32'h0000_00FC;

    localparam integer TB_DLY = 2;

    reg                         PCLK;
    reg                         PRESETn;
    reg                         PSEL;
    reg                         PENABLE;
    reg                         PWRITE;
    reg  [31:0]                 PADDR;
    reg  [31:0]                 PWDATA;
    wire [31:0]                 PRDATA;
    wire                        PREADY;
    wire                        PSLVERR;

    wire [127:0]                aes_data_out;
    wire                        aes_ready_out;

    wire                        tx_busy;
    wire                        tx_done;
    wire                        tx_error;

    wire                        encoder_busy;
    wire                        encoder_done;
    wire                        encoder_error;
    wire [1:0]                  selected_mode_out;
    wire [3:0]                  fsm_state;

    wire                        packer_busy;
    wire                        packer_done;
    wire                        packer_error;
    wire [TRANSPORT_WORD_WIDTH-1:0] transport_word_dbg;
    wire                        transport_word_valid_dbg;
    wire                        adapter_error_dbg;

    wire                        apb_start_block_dbg;
    wire [BLOCK_SIZE_WIDTH-1:0] apb_block_size_dbg;
    wire [31:0]                 apb_word_in_dbg;
    wire                        apb_word_valid_dbg;
    wire                        apb_word_ready_dbg;

    wire                        cipher_en_dbg;
    wire                        decipher_en_dbg;
    wire                        chain_en_dbg;
    wire [127:0]                data_in_dbg;
    wire [127:0]                key_dbg;
    wire [3:0]                  mode_dbg;
    wire [127:0]                init_vector_dbg;
    wire [15:0]                 segment_len_dbg;

    wire [CHUNK_DATA_WIDTH-1:0] enc_stream_data_dbg;
    wire [CHUNK_LEN_WIDTH-1:0]  enc_stream_len_dbg;
    wire                        enc_stream_valid_dbg;
    wire                        enc_stream_ready_dbg;
    wire                        enc_stream_last_dbg;

    reg [7:0]                   text_mem [0:MAX_TEXT_BYTES-1];
    integer                     text_len;

    reg [127:0]                 cap_aes_in [0:MAX_AES_BLOCKS-1];
    reg [6:0]                   cap_valid_bits [0:MAX_AES_BLOCKS-1];
    reg                         cap_block_last [0:MAX_AES_BLOCKS-1];
    integer                     cap_count;

    integer                     pass_count;
    integer                     fail_count;
    integer                     i;
    integer                     j;
    integer                     k;
    integer                     w;
    integer                     fd;
    integer                     ch;
    integer                     base_idx;
    integer                     blk_len;
    integer                     words_needed;
    integer                     done_flag;
    integer                     err_flag;
    integer                     apb_waits;
    integer                     local_timeout;
    reg                         apb_err;
    reg [31:0]                  apb_rdata;

    integer                     start_pulse_count;
    integer                     cipher_pulse_count;
    integer                     tx_done_pulse_count;

    integer                     block_total;
    integer                     raw_full_blocks;
    integer                     raw_partial_blocks;
    integer                     compressed_blocks;
    integer                     one_symbol_blocks;

    integer                     total_input_bits;
    integer                     total_encoder_bits;
    integer                     total_packer_bits;
    integer                     total_aes_channel_bits;
    integer                     saved_bits;
    integer                     saved_bytes_ceil;
    integer                     encoder_saved_bits;
    integer                     packer_overhead_bits;
    integer                     aes_overhead_bits;
    integer                     total_output_bytes_ceil;
    real                        total_compress_pct;
    real                        encoder_compress_pct;

    integer                     blk_input_bits;
    integer                     blk_encoder_bits;
    integer                     blk_packer_bits;
    integer                     blk_saved_bits;
    real                        blk_compress_pct;

    integer                     packer_to_aes_mismatch_count;
    integer                     total_block_last_count;

    reg [7:0]                   b0;
    reg [7:0]                   b1;
    reg [7:0]                   b2;
    reg [7:0]                   b3;
    reg [31:0]                  word_v;

    integer                     current_block_encoder_bits;
    integer                     current_block_packer_bits;

    // ------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------
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
    ) dut (
        .PCLK                  (PCLK),
        .PRESETn               (PRESETn),
        .PSEL                  (PSEL),
        .PENABLE               (PENABLE),
        .PWRITE                (PWRITE),
        .PADDR                 (PADDR),
        .PWDATA                (PWDATA),
        .PRDATA                (PRDATA),
        .PREADY                (PREADY),
        .PSLVERR               (PSLVERR),
        .cbc_iv_i              (128'b0),

        .aes_data_out          (aes_data_out),
        .aes_ready_out         (aes_ready_out),

        .tx_busy               (tx_busy),
        .tx_done               (tx_done),
        .tx_error              (tx_error),

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
        .adapter_error_dbg     (adapter_error_dbg),

        .apb_start_block_dbg   (apb_start_block_dbg),
        .apb_block_size_dbg    (apb_block_size_dbg),
        .apb_word_in_dbg       (apb_word_in_dbg),
        .apb_word_valid_dbg    (apb_word_valid_dbg),
        .apb_word_ready_dbg    (apb_word_ready_dbg),

        .cipher_en_dbg         (cipher_en_dbg),
        .decipher_en_dbg       (decipher_en_dbg),
        .chain_en_dbg          (chain_en_dbg),
        .data_in_dbg           (data_in_dbg),
        .key_dbg               (key_dbg),
        .mode_dbg              (mode_dbg),
        .init_vector_dbg       (init_vector_dbg),
        .segment_len_dbg       (segment_len_dbg),

        .enc_stream_data_dbg   (enc_stream_data_dbg),
        .enc_stream_len_dbg    (enc_stream_len_dbg),
        .enc_stream_valid_dbg  (enc_stream_valid_dbg),
        .enc_stream_ready_dbg  (enc_stream_ready_dbg),
        .enc_stream_last_dbg   (enc_stream_last_dbg)
    );

    // ------------------------------------------------------------
    // Clock
    // ------------------------------------------------------------
    initial begin
        PCLK = 1'b0;
        forever #5 PCLK = ~PCLK;
    end

    // ------------------------------------------------------------
    // Capture accepted encoder chunks and AES input blocks
    // ------------------------------------------------------------
    always @(posedge PCLK) begin
        #1;

        if (apb_start_block_dbg)
            start_pulse_count = start_pulse_count + 1;

        if (enc_stream_valid_dbg && enc_stream_ready_dbg) begin
            total_encoder_bits         = total_encoder_bits + enc_stream_len_dbg;
            current_block_encoder_bits = current_block_encoder_bits + enc_stream_len_dbg;
        end

        if (cipher_en_dbg) begin
            cipher_pulse_count = cipher_pulse_count + 1;

            cap_aes_in[cap_count]     = data_in_dbg;
            cap_valid_bits[cap_count] = data_in_dbg[126:120];
            cap_block_last[cap_count] = data_in_dbg[127];
            cap_count                 = cap_count + 1;

            total_packer_bits         = total_packer_bits + data_in_dbg[126:120];
            current_block_packer_bits = current_block_packer_bits + data_in_dbg[126:120];
            total_aes_channel_bits    = total_aes_channel_bits + 128;

            if (data_in_dbg[127])
                total_block_last_count = total_block_last_count + 1;

            if (data_in_dbg !== transport_word_dbg) begin
                $display("[FAIL] transport_word_dbg != data_in_dbg");
                $display("       transport_word_dbg = 0x%032x", transport_word_dbg);
                $display("       data_in_dbg        = 0x%032x", data_in_dbg);
                fail_count = fail_count + 1;
                packer_to_aes_mismatch_count = packer_to_aes_mismatch_count + 1;
            end
            else begin
                $display("[PASS] transport_word_dbg == data_in_dbg | block_last=%0d valid_bits=%0d",
                         data_in_dbg[127], data_in_dbg[126:120]);
                pass_count = pass_count + 1;
            end
        end

        if (tx_done)
            tx_done_pulse_count = tx_done_pulse_count + 1;
    end

    // ------------------------------------------------------------
    // Utility
    // ------------------------------------------------------------
    function [31:0] pack_word4;
        input [7:0] x0;
        input [7:0] x1;
        input [7:0] x2;
        input [7:0] x3;
        begin
            pack_word4 = {x3, x2, x1, x0};
        end
    endfunction

    task clear_inputs;
    begin
        PSEL    = 1'b0;
        PENABLE = 1'b0;
        PWRITE  = 1'b0;
        PADDR   = 32'b0;
        PWDATA  = 32'b0;
    end
    endtask

    task clear_text_mem;
    begin
        text_len = 0;
        for (i = 0; i < MAX_TEXT_BYTES; i = i + 1)
            text_mem[i] = 8'h00;
    end
    endtask

    task clear_capture;
    begin
        cap_count = 0;
        for (i = 0; i < MAX_AES_BLOCKS; i = i + 1) begin
            cap_aes_in[i]     = 128'b0;
            cap_valid_bits[i] = 7'd0;
            cap_block_last[i] = 1'b0;
        end
    end
    endtask

    task reset_dut;
    begin
        clear_inputs;
        clear_text_mem;
        clear_capture;
        PRESETn = 1'b0;
        repeat (4) @(posedge PCLK);
        #TB_DLY;
        PRESETn = 1'b1;
        repeat (4) @(posedge PCLK);
        #TB_DLY;
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

    task print_mode_name;
        input [1:0] mode;
    begin
        case (mode)
            2'b00: $write("RAW_FULL");
            2'b01: $write("RAW_PARTIAL");
            2'b10: $write("COMPRESSED");
            2'b11: $write("ONE_SYMBOL_COMPRESSED");
            default: $write("UNKNOWN");
        endcase
    end
    endtask

    // ------------------------------------------------------------
    // APB write
    // ------------------------------------------------------------
    task apb_write;
        input  [31:0] addr;
        input  [31:0] data;
        output        err;
        output integer wait_cycles;
        reg sampled_err;
    begin : apb_write_blk
        err         = 1'b0;
        wait_cycles = 0;
        sampled_err = 1'b0;

        @(posedge PCLK);
        #TB_DLY;
        PSEL    = 1'b1;
        PENABLE = 1'b0;
        PWRITE  = 1'b1;
        PADDR   = addr;
        PWDATA  = data;

        @(posedge PCLK);
        #TB_DLY;
        PENABLE = 1'b1;

        local_timeout = 0;
        while (1'b1) begin
            @(negedge PCLK);
            #1;
            if (PREADY === 1'b1) begin
                sampled_err = PSLVERR;

                @(posedge PCLK);
                #TB_DLY;
                PSEL    = 1'b0;
                PENABLE = 1'b0;
                PWRITE  = 1'b0;
                PADDR   = 32'b0;
                PWDATA  = 32'b0;

                err = sampled_err;
                disable apb_write_blk;
            end
            else begin
                wait_cycles   = wait_cycles + 1;
                local_timeout = local_timeout + 1;
                if (local_timeout > 5000) begin
                    $display("[FAIL] apb_write timeout addr=0x%08x data=0x%08x", addr, data);
                    fail_count = fail_count + 1;

                    @(posedge PCLK);
                    #TB_DLY;
                    PSEL    = 1'b0;
                    PENABLE = 1'b0;
                    PWRITE  = 1'b0;
                    PADDR   = 32'b0;
                    PWDATA  = 32'b0;

                    disable apb_write_blk;
                end
            end
        end
    end
    endtask

    // ------------------------------------------------------------
    // APB read
    // ------------------------------------------------------------
    task apb_read;
        input  [31:0] addr;
        output [31:0] data;
        output        err;
        output integer wait_cycles;
        reg [31:0] sampled_data;
        reg sampled_err;
    begin : apb_read_blk
        data         = 32'b0;
        err          = 1'b0;
        wait_cycles  = 0;
        sampled_data = 32'b0;
        sampled_err  = 1'b0;

        @(posedge PCLK);
        #TB_DLY;
        PSEL    = 1'b1;
        PENABLE = 1'b0;
        PWRITE  = 1'b0;
        PADDR   = addr;
        PWDATA  = 32'b0;

        @(posedge PCLK);
        #TB_DLY;
        PENABLE = 1'b1;

        local_timeout = 0;
        while (1'b1) begin
            @(negedge PCLK);
            #1;
            if (PREADY === 1'b1) begin
                sampled_data = PRDATA;
                sampled_err  = PSLVERR;

                @(posedge PCLK);
                #TB_DLY;
                PSEL    = 1'b0;
                PENABLE = 1'b0;
                PWRITE  = 1'b0;
                PADDR   = 32'b0;
                PWDATA  = 32'b0;

                data = sampled_data;
                err  = sampled_err;
                disable apb_read_blk;
            end
            else begin
                wait_cycles   = wait_cycles + 1;
                local_timeout = local_timeout + 1;
                if (local_timeout > 5000) begin
                    $display("[FAIL] apb_read timeout addr=0x%08x", addr);
                    fail_count = fail_count + 1;

                    @(posedge PCLK);
                    #TB_DLY;
                    PSEL    = 1'b0;
                    PENABLE = 1'b0;
                    PWRITE  = 1'b0;
                    PADDR   = 32'b0;
                    PWDATA  = 32'b0;

                    disable apb_read_blk;
                end
            end
        end
    end
    endtask

    // ------------------------------------------------------------
    // Wait until STATUS says done or error
    // ------------------------------------------------------------
    task wait_done_or_error;
        output integer is_done;
        output integer is_error;
        input integer max_polls;
        integer polls;
    begin
        is_done  = 0;
        is_error = 0;
        polls    = 0;

        while ((polls < max_polls) && (is_done == 0) && (is_error == 0)) begin
            apb_read(ADDR_STATUS, apb_rdata, apb_err, apb_waits);
            if (apb_err) begin
                is_error = 1;
            end
            else begin
                if (apb_rdata[4]) is_done  = 1;
                if (apb_rdata[5]) is_error = 1;
            end
            polls = polls + 1;
        end

        if ((is_done == 0) && (is_error == 0)) begin
            $display("[FAIL] wait_done_or_error timeout");
            fail_count = fail_count + 1;
        end
    end
    endtask

    // ------------------------------------------------------------
    // Load input.txt into text_mem
    // - keep LF
    // - drop CR
    // ------------------------------------------------------------
    task load_input_file;
    begin
        clear_text_mem;

        fd = $fopen("input.txt", "r");
        if (fd == 0) begin
            $display("[FAIL] cannot open file: input.txt");
            fail_count = fail_count + 1;
            $finish;
        end

        while (!$feof(fd)) begin
            ch = $fgetc(fd);
            if (ch != -1) begin
                if (text_len < MAX_TEXT_BYTES) begin
                    if (ch != 8'h0D) begin
                        text_mem[text_len] = ch[7:0];
                        text_len = text_len + 1;
                    end
                end
                else begin
                    $display("[FAIL] input file too large, increase MAX_TEXT_BYTES");
                    fail_count = fail_count + 1;
                    $finish;
                end
            end
        end

        $fclose(fd);
    end
    endtask

    // ------------------------------------------------------------
    // Print helpers
    // ------------------------------------------------------------
    task print_input_text;
    begin
        $display("\n===== INITIAL INPUT TEXT =====");
        for (i = 0; i < text_len; i = i + 1) begin
            if (text_mem[i] == 8'h0A)
                $write("\n");
            else
                $write("%c", text_mem[i]);
        end
        $display("\n===== END OF INPUT TEXT =====");
    end
    endtask

    task print_input_bytes;
    begin
        $display("\n===== INPUT BYTES =====");
        for (i = 0; i < text_len; i = i + 1) begin
            if (text_mem[i] >= 8'h20 && text_mem[i] <= 8'h7E)
                $display("input[%0d] = 0x%02x ('%c')", i, text_mem[i], text_mem[i]);
            else if (text_mem[i] == 8'h0A)
                $display("input[%0d] = 0x%02x ('\\n')", i, text_mem[i]);
            else
                $display("input[%0d] = 0x%02x", i, text_mem[i]);
        end
        $display("===== END OF INPUT BYTES =====");
    end
    endtask

    task print_output_blocks;
    begin
        $display("\n===== OUTPUT BLOCKS TO AES =====");
        for (i = 0; i < cap_count; i = i + 1) begin
            $display("block[%0d] data=0x%032x valid_bits=%0d last=%0d",
                     i, cap_aes_in[i], cap_valid_bits[i], cap_block_last[i]);
        end
        $display("===== END OF OUTPUT BLOCKS TO AES =====");
    end
    endtask

    task print_output_size;
    begin
        total_input_bits        = text_len * 8;
        total_output_bytes_ceil = (total_encoder_bits + 7) / 8;
        encoder_saved_bits      = total_input_bits - total_encoder_bits;
        saved_bits              = encoder_saved_bits;
        saved_bytes_ceil        = (saved_bits + 7) / 8;

        if (total_input_bits > 0)
            encoder_compress_pct = (100.0 * encoder_saved_bits) / total_input_bits;
        else
            encoder_compress_pct = 0.0;

        total_compress_pct    = encoder_compress_pct;
        packer_overhead_bits  = total_packer_bits - total_encoder_bits;
        aes_overhead_bits     = total_aes_channel_bits - total_encoder_bits;

        $display("\n===== OUTPUT SIZE =====");
        $display("input bytes            = %0d", text_len);
        $display("input bits             = %0d", total_input_bits);
        $display("encoder bits           = %0d", total_encoder_bits);
        $display("packer payload bits    = %0d", total_packer_bits);
        $display("aes channel bits       = %0d", total_aes_channel_bits);
        $display("encoder bytes ceil     = %0d", total_output_bytes_ceil);
        $display("encoder saved bits     = %0d", encoder_saved_bits);
        $display("encoder saved bytes    = %0d", (encoder_saved_bits + 7) / 8);
        $display("encoder compression    = %0.2f%%", encoder_compress_pct);
        $display("packer overhead bits   = %0d", packer_overhead_bits);
        $display("aes overhead bits      = %0d", aes_overhead_bits);
        $display("===== END OF OUTPUT SIZE =====");
    end
    endtask

    // ------------------------------------------------------------
    // Send one block via APB using text_mem
    // ------------------------------------------------------------
    task send_block_from_text;
        input integer base;
        input integer count;
        integer start_cap_idx;
    begin
        words_needed             = (count + 3) / 4;
        start_cap_idx            = cap_count;
        blk_input_bits           = count * 8;
        blk_encoder_bits         = 0;
        blk_packer_bits          = 0;
        blk_saved_bits           = 0;
        blk_compress_pct         = 0.0;
        current_block_encoder_bits = 0;
        current_block_packer_bits  = 0;

        $display("\n----- PROCESS BLOCK %0d -----", block_total);
        $display("input byte range: [%0d .. %0d], len=%0d",
                 base, base + count - 1, count);

        apb_write(ADDR_BLOCK_SIZE, count, apb_err, apb_waits);
        check1(apb_err, 1'b0, "block_size_write_should_succeed");

        for (w = 0; w < words_needed; w = w + 1) begin
            b0 = 8'h00;
            b1 = 8'h00;
            b2 = 8'h00;
            b3 = 8'h00;

            if ((4*w + 0) < count) b0 = text_mem[base + 4*w + 0];
            if ((4*w + 1) < count) b1 = text_mem[base + 4*w + 1];
            if ((4*w + 2) < count) b2 = text_mem[base + 4*w + 2];
            if ((4*w + 3) < count) b3 = text_mem[base + 4*w + 3];

            word_v = pack_word4(b0,b1,b2,b3);

            $display("  word[%0d] = 0x%08x  bytes={%02x,%02x,%02x,%02x}",
                     w, word_v, b0,b1,b2,b3);

            apb_write(ADDR_WORD_IN, word_v, apb_err, apb_waits);
            check1(apb_err, 1'b0, "word_in_write_should_succeed");
        end

        apb_read(ADDR_STATUS, apb_rdata, apb_err, apb_waits);
        check1(apb_rdata[7], 1'b1, "can_start_should_be_1");

        apb_write(ADDR_START_BLOCK, 32'h0000_0001, apb_err, apb_waits);
        check1(apb_err, 1'b0, "start_block_write_should_succeed");

        wait_done_or_error(done_flag, err_flag, 20000);
        check_int(done_flag, 1, "done_flag_should_be_1");
        check_int(err_flag,  0, "err_flag_should_be_0");
        check1(tx_error, 1'b0, "tx_error_should_be_0");

        case (selected_mode_out)
            2'b00: raw_full_blocks    = raw_full_blocks + 1;
            2'b01: raw_partial_blocks = raw_partial_blocks + 1;
            2'b10: compressed_blocks  = compressed_blocks + 1;
            2'b11: one_symbol_blocks  = one_symbol_blocks + 1;
            default: begin end
        endcase

        blk_encoder_bits = current_block_encoder_bits;
        blk_packer_bits  = current_block_packer_bits;
        blk_saved_bits   = blk_input_bits - blk_encoder_bits;

        if (blk_input_bits > 0)
            blk_compress_pct = (100.0 * blk_saved_bits) / blk_input_bits;
        else
            blk_compress_pct = 0.0;

        $write("selected_mode_out = %0d (", selected_mode_out);
        print_mode_name(selected_mode_out);
        $write(")\n");

        $display("output blocks for this block = %0d", cap_count - start_cap_idx);
        for (j = start_cap_idx; j < cap_count; j = j + 1) begin
            $display("  aes_in[%0d] = 0x%032x valid_bits=%0d last=%0d",
                     j - start_cap_idx, cap_aes_in[j], cap_valid_bits[j], cap_block_last[j]);
        end

        $display("[BLOCK SUMMARY] block_id=%0d", block_total);
        $display("  byte range             = %0d .. %0d", base, base + count - 1);
        $write  ("  selected mode          = %0d (", selected_mode_out);
        print_mode_name(selected_mode_out);
        $write(")\n");
        $display("  input bytes            = %0d", count);
        $display("  input bits             = %0d", blk_input_bits);
        $display("  encoder bits           = %0d", blk_encoder_bits);
        $display("  packer payload bits    = %0d", blk_packer_bits);
        $display("  aes channel bits       = %0d", (cap_count - start_cap_idx) * 128);
        $display("  encoder saved bits     = %0d", blk_saved_bits);
        $display("  encoder compression    = %0.2f%%", blk_compress_pct);

        apb_write(ADDR_CONTROL, 32'h0000_0002, apb_err, apb_waits);
        check1(apb_err, 1'b0, "clear_done_should_succeed");

        apb_write(ADDR_CONTROL, 32'h0000_0004, apb_err, apb_waits);
        check1(apb_err, 1'b0, "clear_error_should_succeed");

        block_total = block_total + 1;
    end
    endtask

    // ------------------------------------------------------------
    // Main test
    // ------------------------------------------------------------
    initial begin
        pass_count                  = 0;
        fail_count                  = 0;
        start_pulse_count           = 0;
        cipher_pulse_count          = 0;
        tx_done_pulse_count         = 0;
        block_total                 = 0;
        raw_full_blocks             = 0;
        raw_partial_blocks          = 0;
        compressed_blocks           = 0;
        one_symbol_blocks           = 0;
        packer_to_aes_mismatch_count= 0;
        total_block_last_count      = 0;
        total_input_bits            = 0;
        total_encoder_bits          = 0;
        total_packer_bits           = 0;
        total_aes_channel_bits      = 0;
        total_output_bytes_ceil     = 0;
        total_aes_input_bits        = 0;
        saved_bits                  = 0;
        saved_bytes_ceil            = 0;
        total_compress_pct          = 0.0;
        encoder_compress_pct        = 0.0;
        encoder_saved_bits          = 0;
        packer_overhead_bits        = 0;
        aes_overhead_bits           = 0;
        current_block_encoder_bits  = 0;
        current_block_packer_bits   = 0;

        reset_dut;
        load_input_file;

        $display("\n===== TEST 0: RESET =====");
        check1(tx_busy,                1'b0, "reset_tx_busy");
        check1(tx_done,                1'b0, "reset_tx_done");
        check1(tx_error,               1'b0, "reset_tx_error");
        check1(cipher_en_dbg,          1'b0, "reset_cipher_en_dbg");
        check1(decipher_en_dbg,        1'b0, "reset_decipher_en_dbg");
        check1(chain_en_dbg,           1'b0, "reset_chain_en_dbg");
        check1(transport_word_valid_dbg, 1'b0, "reset_transport_word_valid_dbg");
        check1(mode_dbg == 4'b0000,    1'b1, "reset_mode_dbg_should_be_0");
        check1(segment_len_dbg == 16'b0, 1'b1, "reset_segment_len_dbg_should_be_0");

        $display("\n===== TEST 1: LOAD INPUT FILE =====");
        if (text_len > 0) begin
            $display("[PASS] text_len=%0d", text_len);
            pass_count = pass_count + 1;
        end
        else begin
            $display("[FAIL] text_len should be > 0");
            fail_count = fail_count + 1;
        end

        clear_capture;
        block_total        = 0;
        raw_full_blocks    = 0;
        raw_partial_blocks = 0;
        compressed_blocks  = 0;
        one_symbol_blocks  = 0;
        total_block_last_count = 0;

        $display("\n===== TEST 2: PROCESS FULL INPUT FILE BLOCK-BY-BLOCK =====");
        base_idx = 0;
        while (base_idx < text_len) begin
            if ((text_len - base_idx) > MAX_SYMBOLS_PER_BLOCK)
                blk_len = MAX_SYMBOLS_PER_BLOCK;
            else
                blk_len = text_len - base_idx;

            send_block_from_text(base_idx, blk_len);
            base_idx = base_idx + blk_len;
        end

        print_input_text;
        print_input_bytes;
        print_output_blocks;
        print_output_size;

        $display("\n===== TEST 3: SUMMARY CHECKS =====");
        if (block_total > 0) begin
            $display("[PASS] block_total=%0d", block_total);
            pass_count = pass_count + 1;
        end
        else begin
            $display("[FAIL] block_total should be > 0");
            fail_count = fail_count + 1;
        end

        if (cap_count > 0) begin
            $display("[PASS] total output blocks=%0d", cap_count);
            pass_count = pass_count + 1;
        end
        else begin
            $display("[FAIL] cap_count should be > 0");
            fail_count = fail_count + 1;
        end

        check_int(raw_full_blocks + raw_partial_blocks + compressed_blocks + one_symbol_blocks,
                  block_total,
                  "sum of all mode blocks should equal block_total");

        check_int(total_block_last_count,
                  block_total,
                  "sum of block_last should equal block_total");

        check_int(packer_to_aes_mismatch_count,
                  0,
                  "packer output should match AES input every accepted block");

        $display("raw_full_blocks       = %0d", raw_full_blocks);
        $display("raw_partial_blocks    = %0d", raw_partial_blocks);
        $display("compressed_blocks     = %0d", compressed_blocks);
        $display("one_symbol_blocks     = %0d", one_symbol_blocks);

        $display("\n========================================");
        $display("FILE INPUT TEST SUMMARY: PASS=%0d FAIL=%0d", pass_count, fail_count);
        $display("========================================");

        #20;
        $finish;
    end

endmodule
