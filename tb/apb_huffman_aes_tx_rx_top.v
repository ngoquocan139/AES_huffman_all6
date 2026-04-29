`timescale 1ns/1ps

module test_bench_apb_huffman_aes_rx_top;

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

    localparam integer MAX_INPUT_BYTES = 128;
    localparam integer MAX_BLOCKS      = 8;
    localparam integer MAX_AES_WORDS   = 64;
    localparam integer TB_DLY          = 2;

    localparam [31:0] TX_ADDR_START_BLOCK = 32'h0000_0000;
    localparam [31:0] TX_ADDR_BLOCK_SIZE  = 32'h0000_0004;
    localparam [31:0] TX_ADDR_WORD_IN     = 32'h0000_0008;
    localparam [31:0] TX_ADDR_STATUS      = 32'h0000_000C;
    localparam [31:0] TX_ADDR_CONTROL     = 32'h0000_0010;

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

    wire [127:0]                tx_aes_data_out;
    wire                        tx_aes_ready_out;
    wire                        tx_busy;
    wire                        tx_done;
    wire                        tx_error;
    wire                        tx_cipher_en_dbg;

    wire [127:0]                rx_ciphertext_word_in_w;
    wire                        rx_ciphertext_word_valid_w;
    wire                        rx_ciphertext_word_ready_w;

    wire                        rx_busy;
    wire                        rx_done;
    wire                        rx_error;
    wire                        rx_aes_ready_out;

    wire                        depacker_error;
    wire                        parser_error;
    wire                        decoder_error;
    wire                        word_packer_error;

    reg  [7:0]                  input_mem [0:MAX_INPUT_BYTES-1];
    reg  [7:0]                  actual_mem[0:MAX_INPUT_BYTES-1];
    reg  [127:0]                cipher_queue [0:MAX_AES_WORDS-1];

    integer                     block_base [0:MAX_BLOCKS-1];
    integer                     block_len  [0:MAX_BLOCKS-1];
    integer                     block_continue [0:MAX_BLOCKS-1];

    integer                     pass_count;
    integer                     fail_count;
    integer                     expected_total_bytes;
    integer                     actual_total_bytes;
    integer                     expected_block_count;
    integer                     expected_frame_count;
    integer                     expected_rx_word_count;
    integer                     actual_rx_word_count;
    integer                     actual_block_last_word_count;
    integer                     actual_frame_last_word_count;
    integer                     tx_done_pulse_count;
    integer                     rx_done_pulse_count;
    integer                     tx_cipher_start_count;
    integer                     tx_cipher_capture_count;
    integer                     rx_cipher_feed_count;
    integer                     cipher_q_wr;
    integer                     cipher_q_rd;
    integer                     cipher_q_count;
    integer                     cipher_q_max_seen;
    integer                     i;
    integer                     block_idx;
    integer                     w;
    integer                     byte_lane;
    integer                     apb_waits;
    integer                     polls;
    integer                     done_flag;
    integer                     err_flag;
    reg                         apb_err;
    reg  [31:0]                 apb_rdata;
    reg                         tx_aes_ready_sampled_r;
    reg  [31:0]                 rx_status_before_clear_r;
    reg  [31:0]                 rx_status_after_clear_r;
    reg  [31:0]                 rx_meta_r;
    reg  [31:0]                 rx_data_r;
    reg  [2:0]                  rx_valid_bytes_r;

    function [31:0] pack_word4;
        input [7:0] x0;
        input [7:0] x1;
        input [7:0] x2;
        input [7:0] x3;
        begin
            pack_word4 = {x3, x2, x1, x0};
        end
    endfunction

    assign rx_ciphertext_word_valid_w = (cipher_q_count > 0);
    assign rx_ciphertext_word_in_w    = cipher_queue[cipher_q_rd];

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
        .PCLK                   (PCLK),
        .PRESETn                (PRESETn),
        .PSEL                   (tx_PSEL),
        .PENABLE                (tx_PENABLE),
        .PWRITE                 (tx_PWRITE),
        .PADDR                  (tx_PADDR),
        .PWDATA                 (tx_PWDATA),
        .PRDATA                 (tx_PRDATA),
        .PREADY                 (tx_PREADY),
        .PSLVERR                (tx_PSLVERR),
        .cbc_iv_i               (128'b0),
        .aes_data_out           (tx_aes_data_out),
        .aes_ready_out          (tx_aes_ready_out),
        .tx_busy                (tx_busy),
        .tx_done                (tx_done),
        .tx_error               (tx_error),
        .encoder_busy           (),
        .encoder_done           (),
        .encoder_error          (),
        .selected_mode_out      (),
        .fsm_state              (),
        .packer_busy            (),
        .packer_done            (),
        .packer_error           (),
        .transport_word_dbg     (),
        .transport_word_valid_dbg(),
        .adapter_error_dbg      (),
        .apb_start_block_dbg    (),
        .apb_block_size_dbg     (),
        .apb_word_in_dbg        (),
        .apb_word_valid_dbg     (),
        .apb_word_ready_dbg     (),
        .cipher_en_dbg          (tx_cipher_en_dbg),
        .decipher_en_dbg        (),
        .chain_en_dbg           (),
        .data_in_dbg            (),
        .key_dbg                (),
        .mode_dbg               (),
        .init_vector_dbg        (),
        .segment_len_dbg        ()
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
        .AES_KEY_FIXED         (AES_KEY_FIXED)
    ) u_rx_top (
        .PCLK                   (PCLK),
        .PRESETn                (PRESETn),
        .rst_i                  (!PRESETn),
        .ciphertext_word_in     (rx_ciphertext_word_in_w),
        .ciphertext_word_valid  (rx_ciphertext_word_valid_w),
        .ciphertext_word_ready  (rx_ciphertext_word_ready_w),
        .PSEL                   (rx_PSEL),
        .PENABLE                (rx_PENABLE),
        .PWRITE                 (rx_PWRITE),
        .PADDR                  (rx_PADDR),
        .PWDATA                 (rx_PWDATA),
        .PRDATA                 (rx_PRDATA),
        .PREADY                 (rx_PREADY),
        .PSLVERR                (rx_PSLVERR),
        .cbc_iv_i               (128'b0),
        .rx_busy                (rx_busy),
        .rx_done                (rx_done),
        .rx_error               (rx_error),
        .aes_ready_out          (rx_aes_ready_out),
        .depacker_busy          (),
        .depacker_done          (),
        .depacker_error         (depacker_error),
        .parser_busy            (),
        .parser_block_done      (),
        .parser_frame_done      (),
        .parser_error           (parser_error),
        .decoder_busy           (),
        .decoder_block_done     (),
        .decoder_frame_done     (),
        .decoder_error          (decoder_error),
        .word_packer_busy       (),
        .word_packer_block_done (),
        .word_packer_frame_done (),
        .word_packer_error      (word_packer_error),
        .transport_word_dbg     (),
        .transport_word_valid_dbg(),
        .rx_word_dbg            (),
        .rx_word_valid_bytes_dbg(),
        .rx_word_last_in_block_dbg(),
        .rx_word_last_in_frame_dbg(),
        .rx_word_valid_dbg      ()
    );

    initial begin
        PCLK = 1'b0;
        forever #5 PCLK = ~PCLK;
    end

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            tx_done_pulse_count   <= 0;
            rx_done_pulse_count   <= 0;
            tx_cipher_start_count <= 0;
        end
        else begin
            if (tx_done)
                tx_done_pulse_count <= tx_done_pulse_count + 1;

            if (rx_done)
                rx_done_pulse_count <= rx_done_pulse_count + 1;

            if (tx_cipher_en_dbg)
                tx_cipher_start_count <= tx_cipher_start_count + 1;
        end
    end

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            tx_aes_ready_sampled_r  = 1'b1;
            cipher_q_wr             = 0;
            cipher_q_rd             = 0;
            cipher_q_count          = 0;
            cipher_q_max_seen       = 0;
            tx_cipher_capture_count = 0;
            rx_cipher_feed_count    = 0;
        end
        else begin
            #1;

            if ((!tx_aes_ready_sampled_r) && tx_aes_ready_out) begin
                if (cipher_q_count < MAX_AES_WORDS) begin
                    cipher_queue[cipher_q_wr] = tx_aes_data_out;

                    if (cipher_q_wr == (MAX_AES_WORDS - 1))
                        cipher_q_wr = 0;
                    else
                        cipher_q_wr = cipher_q_wr + 1;

                    cipher_q_count = cipher_q_count + 1;
                    tx_cipher_capture_count = tx_cipher_capture_count + 1;

                    if (cipher_q_count > cipher_q_max_seen)
                        cipher_q_max_seen = cipher_q_count;
                end
                else begin
                    $display("[FAIL] ciphertext queue overflow");
                    fail_count = fail_count + 1;
                    $finish;
                end
            end

            if ((cipher_q_count > 0) && rx_ciphertext_word_ready_w) begin
                if (cipher_q_rd == (MAX_AES_WORDS - 1))
                    cipher_q_rd = 0;
                else
                    cipher_q_rd = cipher_q_rd + 1;

                cipher_q_count = cipher_q_count - 1;
                rx_cipher_feed_count = rx_cipher_feed_count + 1;
            end

            tx_aes_ready_sampled_r = tx_aes_ready_out;
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

    task clear_memories;
    begin
        for (i = 0; i < MAX_INPUT_BYTES; i = i + 1) begin
            input_mem[i]  = 8'h00;
            actual_mem[i] = 8'h00;
        end

        for (i = 0; i < MAX_AES_WORDS; i = i + 1)
            cipher_queue[i] = 128'h0;

        for (i = 0; i < MAX_BLOCKS; i = i + 1) begin
            block_base[i]     = 0;
            block_len[i]      = 0;
            block_continue[i] = 0;
        end
    end
    endtask

    task clear_scoreboard;
    begin
        pass_count                   = 0;
        fail_count                   = 0;
        expected_total_bytes         = 0;
        actual_total_bytes           = 0;
        expected_block_count         = 0;
        expected_frame_count         = 0;
        expected_rx_word_count       = 0;
        actual_rx_word_count         = 0;
        actual_block_last_word_count = 0;
        actual_frame_last_word_count = 0;
        tx_done_pulse_count          = 0;
        rx_done_pulse_count          = 0;
        tx_cipher_start_count        = 0;
        tx_cipher_capture_count      = 0;
        rx_cipher_feed_count         = 0;
        cipher_q_wr                  = 0;
        cipher_q_rd                  = 0;
        cipher_q_count               = 0;
        cipher_q_max_seen            = 0;
        tx_aes_ready_sampled_r       = 1'b1;
        rx_status_before_clear_r     = 32'b0;
        rx_status_after_clear_r      = 32'b0;
        rx_meta_r                    = 32'b0;
        rx_data_r                    = 32'b0;
        rx_valid_bytes_r             = 3'b000;
    end
    endtask

    task reset_dut;
    begin
        clear_buses;
        clear_memories;
        clear_scoreboard;
        PRESETn = 1'b0;
        repeat (6) @(posedge PCLK);
        #TB_DLY;
        PRESETn = 1'b1;
        repeat (6) @(posedge PCLK);
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

    task append_byte;
        input [7:0] value;
    begin
        if (expected_total_bytes < MAX_INPUT_BYTES) begin
            input_mem[expected_total_bytes] = value;
            expected_total_bytes = expected_total_bytes + 1;
        end
        else begin
            $display("[FAIL] input_mem overflow");
            fail_count = fail_count + 1;
            $finish;
        end
    end
    endtask

    task start_block_desc;
        input integer len_i;
        input integer continue_i;
    begin
        if (expected_block_count < MAX_BLOCKS) begin
            block_base[expected_block_count]     = expected_total_bytes;
            block_len[expected_block_count]      = len_i;
            block_continue[expected_block_count] = continue_i;
            expected_block_count                 = expected_block_count + 1;
            expected_rx_word_count               = expected_rx_word_count + ((len_i + 3) / 4);

            if (continue_i == 0)
                expected_frame_count = expected_frame_count + 1;
        end
        else begin
            $display("[FAIL] block descriptor overflow");
            fail_count = fail_count + 1;
            $finish;
        end
    end
    endtask

    task build_test_vectors;
    begin
        expected_total_bytes   = 0;
        expected_block_count   = 0;
        expected_frame_count   = 0;
        expected_rx_word_count = 0;

        start_block_desc(5, 1);
        append_byte("A");
        append_byte("A");
        append_byte("A");
        append_byte("A");
        append_byte("A");

        start_block_desc(7, 0);
        append_byte("H");
        append_byte("E");
        append_byte("L");
        append_byte("L");
        append_byte("O");
        append_byte("!");
        append_byte("!");

        start_block_desc(6, 1);
        append_byte("B");
        append_byte("B");
        append_byte("B");
        append_byte("B");
        append_byte("B");
        append_byte("B");

        start_block_desc(9, 0);
        append_byte("X");
        append_byte("Y");
        append_byte("X");
        append_byte("Y");
        append_byte("X");
        append_byte("Y");
        append_byte("X");
        append_byte("Y");
        append_byte("!");
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

        while (tx_PREADY !== 1'b1) begin
            wait_cycles = wait_cycles + 1;
            @(posedge PCLK);
            #TB_DLY;
        end

        sampled_err = tx_PSLVERR;

        @(posedge PCLK);
        #TB_DLY;
        tx_PSEL    = 1'b0;
        tx_PENABLE = 1'b0;
        tx_PWRITE  = 1'b0;
        tx_PADDR   = 32'b0;
        tx_PWDATA  = 32'b0;

        err = sampled_err;
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

        while (tx_PREADY !== 1'b1) begin
            wait_cycles = wait_cycles + 1;
            @(posedge PCLK);
            #TB_DLY;
        end

        sampled_data = tx_PRDATA;
        sampled_err  = tx_PSLVERR;

        @(posedge PCLK);
        #TB_DLY;
        tx_PSEL    = 1'b0;
        tx_PENABLE = 1'b0;
        tx_PWRITE  = 1'b0;
        tx_PADDR   = 32'b0;
        tx_PWDATA  = 32'b0;

        data = sampled_data;
        err  = sampled_err;
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

        while (rx_PREADY !== 1'b1) begin
            wait_cycles = wait_cycles + 1;
            @(posedge PCLK);
            #TB_DLY;
        end

        sampled_err = rx_PSLVERR;

        @(posedge PCLK);
        #TB_DLY;
        rx_PSEL    = 1'b0;
        rx_PENABLE = 1'b0;
        rx_PWRITE  = 1'b0;
        rx_PADDR   = 32'b0;
        rx_PWDATA  = 32'b0;

        err = sampled_err;
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

        while (rx_PREADY !== 1'b1) begin
            wait_cycles = wait_cycles + 1;
            @(posedge PCLK);
            #TB_DLY;
        end

        sampled_data = rx_PRDATA;
        sampled_err  = rx_PSLVERR;

        @(posedge PCLK);
        #TB_DLY;
        rx_PSEL    = 1'b0;
        rx_PENABLE = 1'b0;
        rx_PWRITE  = 1'b0;
        rx_PADDR   = 32'b0;
        rx_PWDATA  = 32'b0;

        data = sampled_data;
        err  = sampled_err;
    end
    endtask

    task wait_tx_done_or_error;
        output integer is_done;
        output integer is_error;
        input integer max_polls;
    begin
        is_done  = 0;
        is_error = 0;
        polls    = 0;

        while ((polls < max_polls) && (is_done == 0) && (is_error == 0)) begin
            apb_tx_read(TX_ADDR_STATUS, apb_rdata, apb_err, apb_waits);
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
            $display("[FAIL] wait_tx_done_or_error timeout");
            fail_count = fail_count + 1;
        end
    end
    endtask

    task send_tx_block_from_mem;
        input integer base;
        input integer count;
        input integer continue_frame_i;
        reg [7:0] b0;
        reg [7:0] b1;
        reg [7:0] b2;
        reg [7:0] b3;
        reg [31:0] word_v;
        integer words_needed;
    begin
        words_needed = (count + 3) / 4;

        apb_tx_write(TX_ADDR_BLOCK_SIZE, count, apb_err, apb_waits);
        check1(apb_err, 1'b0, "tx_block_size_write_should_succeed");

        for (w = 0; w < words_needed; w = w + 1) begin
            b0 = 8'h00;
            b1 = 8'h00;
            b2 = 8'h00;
            b3 = 8'h00;

            if ((4*w + 0) < count) b0 = input_mem[base + 4*w + 0];
            if ((4*w + 1) < count) b1 = input_mem[base + 4*w + 1];
            if ((4*w + 2) < count) b2 = input_mem[base + 4*w + 2];
            if ((4*w + 3) < count) b3 = input_mem[base + 4*w + 3];

            word_v = pack_word4(b0, b1, b2, b3);
            apb_tx_write(TX_ADDR_WORD_IN, word_v, apb_err, apb_waits);
            check1(apb_err, 1'b0, "tx_word_in_write_should_succeed");
        end

        apb_tx_read(TX_ADDR_STATUS, apb_rdata, apb_err, apb_waits);
        check1(apb_err, 1'b0, "tx_status_read_should_succeed");
        check1(apb_rdata[7], 1'b1, "tx_can_start_should_be_1");

        if (continue_frame_i != 0)
            apb_tx_write(TX_ADDR_START_BLOCK, 32'h0000_0003, apb_err, apb_waits);
        else
            apb_tx_write(TX_ADDR_START_BLOCK, 32'h0000_0001, apb_err, apb_waits);

        check1(apb_err, 1'b0, "tx_start_block_write_should_succeed");

        wait_tx_done_or_error(done_flag, err_flag, 20000);
        check_int(done_flag, 1, "tx_done_flag_should_be_1");
        check_int(err_flag,  0, "tx_err_flag_should_be_0");
        check1(tx_error, 1'b0, "tx_error_should_be_0");

        apb_tx_write(TX_ADDR_CONTROL, 32'h0000_0002, apb_err, apb_waits);
        check1(apb_err, 1'b0, "tx_clear_done_should_succeed");

        apb_tx_write(TX_ADDR_CONTROL, 32'h0000_0004, apb_err, apb_waits);
        check1(apb_err, 1'b0, "tx_clear_error_should_succeed");
    end
    endtask

    task wait_loopback_idle;
        input integer max_cycles;
        integer stable_cycles;
        integer cycles_left;
    begin : wait_loopback_idle_blk
        stable_cycles = 0;
        cycles_left   = max_cycles;

        while (cycles_left > 0) begin
            @(posedge PCLK);
            #TB_DLY;

            if ((cipher_q_count == 0) &&
                (tx_busy == 1'b0) &&
                (tx_error == 1'b0) &&
                (rx_busy == 1'b0) &&
                (rx_error == 1'b0) &&
                (tx_aes_ready_out == 1'b1) &&
                (rx_aes_ready_out == 1'b1)) begin
                stable_cycles = stable_cycles + 1;
                if (stable_cycles >= 8)
                    disable wait_loopback_idle_blk;
            end
            else begin
                stable_cycles = 0;
            end

            cycles_left = cycles_left - 1;
        end

        $display("[FAIL] wait_loopback_idle timeout");
        fail_count = fail_count + 1;
    end
    endtask

    task drain_rx_fifo_and_check;
    begin : drain_rx_fifo_and_check_blk
        actual_total_bytes           = 0;
        actual_rx_word_count         = 0;
        actual_block_last_word_count = 0;
        actual_frame_last_word_count = 0;

        apb_rx_read(RX_ADDR_STATUS, rx_status_before_clear_r, apb_err, apb_waits);
        check1(apb_err, 1'b0, "rx_status_before_clear_should_succeed");
        check1(rx_status_before_clear_r[3], 1'b1, "rx_block_done_sticky_should_be_1");
        check1(rx_status_before_clear_r[4], 1'b1, "rx_frame_done_sticky_should_be_1");
        check1(rx_status_before_clear_r[5], 1'b0, "rx_error_sticky_should_be_0");

        apb_rx_read(RX_ADDR_META, rx_meta_r, apb_err, apb_waits);
        check1(apb_err, 1'b0, "rx_meta_peek_should_succeed");
        check1((rx_meta_r != 32'b0), 1'b1, "rx_meta_peek_should_be_non_zero_when_fifo_has_data");

        while (1) begin
            apb_rx_read(RX_ADDR_STATUS, apb_rdata, apb_err, apb_waits);
            check1(apb_err, 1'b0, "rx_status_poll_should_succeed");

            if (apb_rdata[0] == 1'b0)
                disable drain_rx_fifo_and_check_blk;

            apb_rx_read(RX_ADDR_META, rx_meta_r, apb_err, apb_waits);
            check1(apb_err, 1'b0, "rx_meta_read_should_succeed");

            apb_rx_read(RX_ADDR_DATA, rx_data_r, apb_err, apb_waits);
            check1(apb_err, 1'b0, "rx_data_read_should_succeed");

            rx_valid_bytes_r = rx_meta_r[2:0];
            actual_rx_word_count = actual_rx_word_count + 1;

            if (rx_meta_r[3])
                actual_block_last_word_count = actual_block_last_word_count + 1;

            if (rx_meta_r[4])
                actual_frame_last_word_count = actual_frame_last_word_count + 1;

            check1((rx_valid_bytes_r >= 3'd1), 1'b1, "rx_valid_bytes_should_be_ge_1");
            check1((rx_valid_bytes_r <= 3'd4), 1'b1, "rx_valid_bytes_should_be_le_4");

            if (rx_meta_r[4] && !rx_meta_r[3]) begin
                $display("[FAIL] last_in_frame without last_in_block");
                fail_count = fail_count + 1;
            end

            for (byte_lane = 0; byte_lane < rx_valid_bytes_r; byte_lane = byte_lane + 1) begin
                if (actual_total_bytes < MAX_INPUT_BYTES) begin
                    actual_mem[actual_total_bytes] = rx_data_r[(8*byte_lane)+7 -: 8];
                    actual_total_bytes = actual_total_bytes + 1;
                end
                else begin
                    $display("[FAIL] actual_mem overflow");
                    fail_count = fail_count + 1;
                    $finish;
                end
            end
        end
    end
    endtask

    initial begin
        reset_dut;
        build_test_vectors;

        $display("\n===== RESET CHECK =====");
        check1(tx_busy,          1'b0, "reset_tx_busy");
        check1(tx_done,          1'b0, "reset_tx_done");
        check1(tx_error,         1'b0, "reset_tx_error");
        check1(rx_busy,          1'b0, "reset_rx_busy");
        check1(rx_done,          1'b0, "reset_rx_done");
        check1(rx_error,         1'b0, "reset_rx_error");
        check1(tx_aes_ready_out, 1'b1, "reset_tx_aes_ready_out");
        check1(rx_aes_ready_out, 1'b1, "reset_rx_aes_ready_out");

        $display("\n===== SEND LOOPBACK TRAFFIC =====");
        for (block_idx = 0; block_idx < expected_block_count; block_idx = block_idx + 1) begin
            $display("send block %0d | base=%0d len=%0d continue_frame=%0d",
                     block_idx,
                     block_base[block_idx],
                     block_len[block_idx],
                     block_continue[block_idx]);

            send_tx_block_from_mem(block_base[block_idx],
                                   block_len[block_idx],
                                   block_continue[block_idx]);
        end

        wait_loopback_idle(4000);

        $display("\n===== DRAIN RX FIFO =====");
        drain_rx_fifo_and_check;

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

        $display("\n===== LOOPBACK CHECKS =====");
        check1(tx_error, 1'b0, "tx_error_final_should_be_0");
        check1(rx_error, 1'b0, "rx_error_final_should_be_0");
        check1(depacker_error, 1'b0, "depacker_error_should_be_0");
        check1(parser_error, 1'b0, "parser_error_should_be_0");
        check1(decoder_error, 1'b0, "decoder_error_should_be_0");
        check1(word_packer_error, 1'b0, "word_packer_error_should_be_0");

        check_int(tx_done_pulse_count,
                  expected_block_count,
                  "tx_done_pulse_count_should_match_block_count");

        check_int(rx_done_pulse_count,
                  expected_frame_count,
                  "rx_done_pulse_count_should_match_frame_count");

        check_int(tx_cipher_capture_count,
                  rx_cipher_feed_count,
                  "captured_cipher_words_should_match_fed_cipher_words");

        check_int(tx_cipher_start_count,
                  tx_cipher_capture_count,
                  "cipher_start_count_should_match_captured_outputs");

        check1((tx_cipher_capture_count > 0), 1'b1, "ciphertext_word_count_should_be_non_zero");
        check1((cipher_q_max_seen > 0), 1'b1, "cipher_queue_should_have_seen_activity");
        check_int(cipher_q_count, 0, "cipher_queue_should_be_empty");

        check_int(actual_rx_word_count,
                  expected_rx_word_count,
                  "rx_word_count_should_match_expected_block_packing");

        check_int(actual_block_last_word_count,
                  expected_block_count,
                  "last_in_block_word_count_should_match_block_count");

        check_int(actual_frame_last_word_count,
                  expected_frame_count,
                  "last_in_frame_word_count_should_match_frame_count");

        check_int(actual_total_bytes,
                  expected_total_bytes,
                  "loopback_byte_count_should_match");

        for (i = 0; i < expected_total_bytes; i = i + 1) begin
            if (actual_mem[i] === input_mem[i]) begin
                pass_count = pass_count + 1;
            end
            else begin
                $display("[FAIL] byte mismatch at index %0d | actual=0x%02x expected=0x%02x",
                         i, actual_mem[i], input_mem[i]);
                fail_count = fail_count + 1;
            end
        end

        $display("\n===== FINAL RESULT =====");
        if (fail_count == 0)
            $display("[PASS] TX->AES->RX loopback recovered the original byte stream.");
        else
            $display("[FAIL] TX->AES->RX loopback has mismatches or protocol issues.");

        $display("\n===========================================================");
        $display("RX TOP LOOPBACK TEST SUMMARY: PASS=%0d FAIL=%0d", pass_count, fail_count);
        $display("===========================================================");

        #20;
        $finish;
    end

endmodule
