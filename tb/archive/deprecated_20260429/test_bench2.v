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

    localparam [31:0] ADDR_START_BLOCK = 32'h0000_0000;
    localparam [31:0] ADDR_BLOCK_SIZE  = 32'h0000_0004;
    localparam [31:0] ADDR_WORD_IN     = 32'h0000_0008;
    localparam [31:0] ADDR_STATUS      = 32'h0000_000C;
    localparam [31:0] ADDR_CONTROL     = 32'h0000_0010;
    localparam [31:0] ADDR_DEBUG       = 32'h0000_0014;

    localparam integer TB_DLY = 2;
    localparam [8*256-1:0] INPUT_FILE = "input.txt";

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

    integer pass_count;
    integer fail_count;
    integer apb_waits;
    integer timeout_cnt;
    reg     apb_err;
    reg [31:0] apb_rdata;

    integer start_pulse_count;
    integer cipher_pulse_count;
    integer tx_done_pulse_count;

    integer done_flag;
    integer err_flag;

    integer block_count;
    integer total_words_sent;

    // --------------------------------------------------------------------
    // File buffer
    // --------------------------------------------------------------------
    reg [7:0] file_bytes [0:65535];
    integer   file_size;

    // --------------------------------------------------------------------
    // DUT
    // --------------------------------------------------------------------
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
        .segment_len_dbg       (segment_len_dbg)
    );

    // --------------------------------------------------------------------
    // Clock
    // --------------------------------------------------------------------
    initial begin
        PCLK = 1'b0;
        forever #5 PCLK = ~PCLK;
    end

    // --------------------------------------------------------------------
    // Pulse counters
    // --------------------------------------------------------------------
    always @(posedge PCLK) begin
        if (apb_start_block_dbg)
            start_pulse_count <= start_pulse_count + 1;

        if (cipher_en_dbg)
            cipher_pulse_count <= cipher_pulse_count + 1;

        if (tx_done)
            tx_done_pulse_count <= tx_done_pulse_count + 1;
    end

    // --------------------------------------------------------------------
    // Helpers
    // --------------------------------------------------------------------
    function [31:0] pack_word4;
        input [7:0] b0;
        input [7:0] b1;
        input [7:0] b2;
        input [7:0] b3;
        begin
            pack_word4 = {b3, b2, b1, b0};
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

    task reset_dut;
    begin
        clear_inputs();
        PRESETn = 1'b0;
        repeat (4) @(posedge PCLK);
        #TB_DLY;
        PRESETn = 1'b1;
        repeat (4) @(posedge PCLK);
        #TB_DLY;
    end
    endtask

    task check_bit;
        input actual;
        input expected;
        input [8*80-1:0] name;
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
        input [8*80-1:0] name;
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

    task check32;
        input [31:0] actual;
        input [31:0] expected;
        input [8*80-1:0] name;
    begin
        if (actual === expected) begin
            $display("[PASS] %0s | actual=0x%08x expected=0x%08x", name, actual, expected);
            pass_count = pass_count + 1;
        end
        else begin
            $display("[FAIL] %0s | actual=0x%08x expected=0x%08x", name, actual, expected);
            fail_count = fail_count + 1;
        end
    end
    endtask

    task check6;
        input [BLOCK_SIZE_WIDTH-1:0] actual;
        input [BLOCK_SIZE_WIDTH-1:0] expected;
        input [8*80-1:0] name;
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

    // --------------------------------------------------------------------
    // APB write
    // --------------------------------------------------------------------
    task apb_write;
        input  [31:0] addr;
        input  [31:0] data;
        output        err;
        output integer wait_cycles;
        integer timeout_ctr;
        reg sampled_err;
        begin : apb_write_blk
            err         = 1'b0;
            wait_cycles = 0;
            sampled_err = 1'b0;

            // SETUP
            @(posedge PCLK);
            #TB_DLY;
            PSEL    = 1'b1;
            PENABLE = 1'b0;
            PWRITE  = 1'b1;
            PADDR   = addr;
            PWDATA  = data;

            // ACCESS
            @(posedge PCLK);
            #TB_DLY;
            PENABLE = 1'b1;

            timeout_ctr = 0;
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
                    wait_cycles = wait_cycles + 1;
                    timeout_ctr = timeout_ctr + 1;
                    if (timeout_ctr > 5000) begin
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

    // --------------------------------------------------------------------
    // APB read
    // --------------------------------------------------------------------
    task apb_read;
        input  [31:0] addr;
        output [31:0] data;
        output        err;
        output integer wait_cycles;
        integer timeout_ctr;
        reg [31:0] sampled_data;
        reg sampled_err;
        begin : apb_read_blk
            data         = 32'b0;
            err          = 1'b0;
            wait_cycles  = 0;
            sampled_data = 32'b0;
            sampled_err  = 1'b0;

            // SETUP
            @(posedge PCLK);
            #TB_DLY;
            PSEL    = 1'b1;
            PENABLE = 1'b0;
            PWRITE  = 1'b0;
            PADDR   = addr;
            PWDATA  = 32'b0;

            // ACCESS
            @(posedge PCLK);
            #TB_DLY;
            PENABLE = 1'b1;

            timeout_ctr = 0;
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
                    wait_cycles = wait_cycles + 1;
                    timeout_ctr = timeout_ctr + 1;
                    if (timeout_ctr > 5000) begin
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

    // --------------------------------------------------------------------
    // Wait until STATUS says done or error
    // STATUS[4] = done_sticky
    // STATUS[5] = error_sticky
    // --------------------------------------------------------------------
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

    // --------------------------------------------------------------------
    // File load
    // --------------------------------------------------------------------
    task load_text_file;
        input [8*256-1:0] filename;
        integer fd;
        integer c;
        integer k;
        begin
            file_size = 0;
            fd = $fopen(filename, "rb");
            if (fd == 0) begin
                $display("[FAIL] Cannot open file: %0s", filename);
                fail_count = fail_count + 1;
            end
            else begin
                while (!$feof(fd)) begin
                    c = $fgetc(fd);
                    if (c != -1) begin
                        file_bytes[file_size] = c[7:0];
                        file_size = file_size + 1;
                    end
                end
                $fclose(fd);

                $display("[INFO] Loaded file '%0s' : %0d bytes", filename, file_size);
                $write("[INFO] File preview: ");
                for (k = 0; (k < file_size) && (k < 128); k = k + 1)
                    $write("%c", file_bytes[k]);
                $write("\n");
            end
        end
    endtask

    // --------------------------------------------------------------------
    // Send one block from file_bytes[start_idx .. start_idx+block_bytes-1]
    // --------------------------------------------------------------------
    task send_block_from_array;
        input integer start_idx;
        input integer block_bytes;
        integer words_needed;
        integer w;
        reg [7:0] b0, b1, b2, b3;
        integer done_local;
        integer err_local;
        begin
            words_needed = (block_bytes + 3) / 4;

            $display("\n[INFO] Send block #%0d : start_idx=%0d block_bytes=%0d words=%0d",
                     block_count, start_idx, block_bytes, words_needed);

            apb_write(ADDR_BLOCK_SIZE, block_bytes, apb_err, apb_waits);
            check_bit(apb_err, 1'b0, "file_block_block_size_write_should_succeed");
            check6(apb_block_size_dbg, block_bytes[BLOCK_SIZE_WIDTH-1:0], "file_block_block_size_dbg_should_match");

            for (w = 0; w < words_needed; w = w + 1) begin
                b0 = 8'h00;
                b1 = 8'h00;
                b2 = 8'h00;
                b3 = 8'h00;

                if ((4*w + 0) < block_bytes) b0 = file_bytes[start_idx + 4*w + 0];
                if ((4*w + 1) < block_bytes) b1 = file_bytes[start_idx + 4*w + 1];
                if ((4*w + 2) < block_bytes) b2 = file_bytes[start_idx + 4*w + 2];
                if ((4*w + 3) < block_bytes) b3 = file_bytes[start_idx + 4*w + 3];

                $display("  word[%0d] = 0x%08x  bytes={%02x,%02x,%02x,%02x}",
                         w, pack_word4(b0,b1,b2,b3), b0,b1,b2,b3);

                apb_write(ADDR_WORD_IN, pack_word4(b0,b1,b2,b3), apb_err, apb_waits);
                check_bit(apb_err, 1'b0, "file_block_word_write_should_succeed");
                total_words_sent = total_words_sent + 1;
            end

            apb_read(ADDR_STATUS, apb_rdata, apb_err, apb_waits);
            check_bit(apb_rdata[7], 1'b1, "file_block_can_start_should_be_1");

            apb_write(ADDR_START_BLOCK, 32'h0000_0001, apb_err, apb_waits);
            check_bit(apb_err, 1'b0, "file_block_start_should_succeed");

            wait_done_or_error(done_local, err_local, 20000);

            if (done_local) begin
                $display("[PASS] File block done");
                pass_count = pass_count + 1;
            end
            if (err_local) begin
                $display("[FAIL] File block error");
                fail_count = fail_count + 1;
            end

            apb_write(ADDR_CONTROL, 32'h0000_0002, apb_err, apb_waits); // clear done
            check_bit(apb_err, 1'b0, "file_block_clear_done_should_succeed");

            apb_write(ADDR_CONTROL, 32'h0000_0004, apb_err, apb_waits); // clear error
            check_bit(apb_err, 1'b0, "file_block_clear_error_should_succeed");

            block_count = block_count + 1;
        end
    endtask

    // --------------------------------------------------------------------
    // Send full file in 32-byte blocks
    // --------------------------------------------------------------------
    task send_text_file_via_apb;
        input [8*256-1:0] filename;
        integer idx;
        integer blk;
        begin
            load_text_file(filename);

            if (file_size <= 0) begin
                $display("[FAIL] Empty file or file load failed");
                fail_count = fail_count + 1;
            end
            else begin
                idx = 0;
                block_count = 0;
                total_words_sent = 0;

                while (idx < file_size) begin
                    if ((file_size - idx) >= 32)
                        blk = 32;
                    else
                        blk = file_size - idx;

                    send_block_from_array(idx, blk);
                    idx = idx + blk;
                end

                $display("\n[INFO] File send complete: %0d blocks, %0d words, %0d bytes",
                         block_count, total_words_sent, file_size);
            end
        end
    endtask

    // --------------------------------------------------------------------
    // Main
    // --------------------------------------------------------------------
    initial begin
        pass_count          = 0;
        fail_count          = 0;
        start_pulse_count   = 0;
        cipher_pulse_count  = 0;
        tx_done_pulse_count = 0;
        block_count         = 0;
        total_words_sent    = 0;
        file_size           = 0;

        reset_dut();

        // ================================================================
        // TEST 0: RESET / IDLE
        // ================================================================
        $display("\n===== TEST 0: RESET / IDLE =====");
        check_bit(PREADY,               1'b1, "t0_pready_should_be_1");
        check_bit(PSLVERR,              1'b0, "t0_pslverr_should_be_0");
        check_bit(tx_busy,              1'b0, "t0_tx_busy_should_be_0");
        check_bit(tx_error,             1'b0, "t0_tx_error_should_be_0");
        check_bit(apb_start_block_dbg,  1'b0, "t0_start_block_dbg_should_be_0");
        check6(apb_block_size_dbg,      6'd0, "t0_block_size_dbg_should_be_0");
        check_bit(cipher_en_dbg,        1'b0, "t0_cipher_en_dbg_should_be_0");
        check32(mode_dbg,               32'h0000_0000, "t0_mode_dbg_should_be_ecb_zeroextended");
        check32(segment_len_dbg,        32'h0000_0000, "t0_segment_len_dbg_should_be_zeroextended");

        apb_read(ADDR_STATUS, apb_rdata, apb_err, apb_waits);
        check_bit(apb_err,      1'b0, "t0_read_status_should_not_error");
        check_bit(apb_rdata[0], 1'b0, "t0_cfg_valid_should_be_0");
        check_bit(apb_rdata[6], 1'b0, "t0_fifo_nonempty_should_be_0");

        // ================================================================
        // TEST 1: TXT FILE THROUGH APB
        // ================================================================
        $display("\n===== TEST 1: TXT FILE THROUGH APB =====");
        send_text_file_via_apb(INPUT_FILE);

        check_bit(start_pulse_count > 0, 1'b1, "t1_start_pulse_count_should_be_nonzero");
        check_bit(cipher_pulse_count > 0, 1'b1, "t1_cipher_pulse_count_should_be_nonzero");
        check_bit(tx_done_pulse_count > 0, 1'b1, "t1_tx_done_pulse_count_should_be_nonzero");
        check_bit(tx_error, 1'b0, "t1_final_tx_error_should_be_0");

        // ================================================================
        // TEST 2: INVALID BLOCK_SIZE
        // ================================================================
        $display("\n===== TEST 2: INVALID BLOCK_SIZE =====");
        apb_write(ADDR_BLOCK_SIZE, 32'h0000_0000, apb_err, apb_waits);
        check_bit(apb_err, 1'b1, "t2_block_size_zero_should_error");

        apb_write(ADDR_CONTROL, 32'h0000_0004, apb_err, apb_waits);
        check_bit(apb_err, 1'b0, "t2_clear_error_should_succeed");

        // ================================================================
        // TEST 3: INVALID READ ADDRESS
        // ================================================================
        $display("\n===== TEST 3: INVALID READ ADDRESS =====");
        apb_read(32'h0000_00FC, apb_rdata, apb_err, apb_waits);
        check_bit(apb_err, 1'b1, "t3_invalid_read_should_error");

        apb_write(ADDR_CONTROL, 32'h0000_0004, apb_err, apb_waits);
        check_bit(apb_err, 1'b0, "t3_clear_error_should_succeed");

        // ================================================================
        // TEST 4: SOFT RESET
        // ================================================================
        $display("\n===== TEST 4: SOFT RESET =====");
        apb_write(ADDR_CONTROL, 32'h0000_0001, apb_err, apb_waits);
        check_bit(apb_err, 1'b0, "t4_soft_reset_should_succeed");

        apb_read(ADDR_STATUS, apb_rdata, apb_err, apb_waits);
        check_bit(apb_rdata[0], 1'b0, "t4_cfg_valid_should_be_0");
        check_bit(apb_rdata[2], 1'b0, "t4_block_active_should_be_0");
        check_bit(apb_rdata[4], 1'b0, "t4_done_sticky_should_be_0");
        check_bit(apb_rdata[5], 1'b0, "t4_error_sticky_should_be_0");
        check_bit(apb_rdata[6], 1'b0, "t4_fifo_nonempty_should_be_0");

        $display("\n========================================");
        $display("APB_HUFFMAN_AES_FULL_TOP FILE TEST SUMMARY: PASS=%0d FAIL=%0d", pass_count, fail_count);
        $display("========================================");

        #20;
        $finish;
    end

endmodule
