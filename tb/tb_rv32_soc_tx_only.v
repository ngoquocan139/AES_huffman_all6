`timescale 1ns / 1ps

module tb_rv32_soc_tx_only;
  localparam integer MAX_WAIT_CYCLES = 1000000;
  localparam integer MAX_INPUT_BYTES = 10000;
  localparam integer DMEM_SIZE_BYTES = 32768;
  localparam integer TRANSPORT_WORD_WIDTH = 128;
  localparam integer VALID_BITS_WIDTH = 7;
  localparam real    CLOCK_PERIOD_NS = 10.0;

  localparam [31:0] RESULT_SIGNATURE = 32'h44545843;
  localparam [31:0] MODE_TX_COMPRESS_AES_BLOCK  = 32'h00000001;
  localparam [31:0] MODE_TX_COMPRESS_ONLY_BLOCK = 32'h00000005;
  localparam [31:0] MODE_TX_COMPRESS_AES_WHOLE  = 32'h00000009;
  localparam [31:0] MODE_TX_COMPRESS_ONLY_WHOLE = 32'h0000000d;

  localparam [31:0] INPUT_LEN_ADDR   = 32'h00000040;
  localparam [31:0] SRC_BASE_ADDR    = 32'h00000400;
  localparam [31:0] TX_DST_BASE_ADDR = 32'h00002000;

  localparam integer SRC_BUFFER_BYTES = TX_DST_BASE_ADDR - SRC_BASE_ADDR;
  localparam integer TX_BUFFER_BYTES  = DMEM_SIZE_BYTES - TX_DST_BASE_ADDR;

  localparam [8*64-1:0] SUMMARY_FILE  = "tx_only/tb_rv32_soc_tx_only_summary.txt";
  localparam [8*64-1:0] SRC_DUMP_FILE = "dmem_dump/tb_rv32_soc_tx_only_src.txt";
  localparam [8*64-1:0] TX_DUMP_FILE  = "dmem_dump/tb_rv32_soc_tx_only_tx.txt";

  reg clk;
  reg rst;

  reg        aux_en;
  reg [3:0]  aux_we;
  reg [31:0] aux_addr;
  reg [31:0] aux_wdata;
  wire [31:0] aux_rdata;

  reg cpu_if_flush;
  reg cpu_stall;

  wire [1:0] mem_err_o;

  integer pass_count;
  integer fail_count;
  integer dma_start_pulse_count;
  integer wait_cycles;
  integer system_rc;
  integer i;

  integer input_len_bytes;
  integer src_mismatch_count;
  integer tx_nonzero_byte_count;
  integer tx_ciphertext_bytes;
  integer compressed_payload_bits;
  integer compressed_payload_bytes_ceil;

  integer cycle_counter;
  integer tx_busy_cycles;
  integer tx_start_cycle;
  integer tx_end_cycle;

  reg tx_seen_busy;
  reg tx_busy_prev;
  reg [8*32-1:0] input_file_name;

  real tx_input_bytes_per_cycle;
  real tx_output_bytes_per_cycle;
  real tx_input_mbytes_per_sec;
  real tx_output_mbytes_per_sec;
  real payload_ratio_pct;
  real payload_space_saving_pct;
  real storage_ratio_pct;
  real space_saving_pct;

  reg [31:0] result_words [0:13];
  reg [31:0] tx_dst_words [0:3];
  reg [7:0]  input_bytes [0:MAX_INPUT_BYTES-1];

  function automatic [7:0] byte_from_word;
    input [31:0] word;
    input [1:0]  lane;
    begin
      case (lane)
        2'd0: byte_from_word = word[7:0];
        2'd1: byte_from_word = word[15:8];
        2'd2: byte_from_word = word[23:16];
        default: byte_from_word = word[31:24];
      endcase
    end
  endfunction

  function automatic [7:0] printable_byte;
    input [7:0] byte_val;
    begin
      if ((byte_val >= 8'h20) && (byte_val <= 8'h7e))
        printable_byte = byte_val;
      else
        printable_byte = ".";
    end
  endfunction

  function automatic [31:0] tx_transport_valid_bits;
    input [TRANSPORT_WORD_WIDTH-1:0] transport_word;
    begin
      tx_transport_valid_bits = {{(32-VALID_BITS_WIDTH){1'b0}},
                                 transport_word[TRANSPORT_WORD_WIDTH-2 -: VALID_BITS_WIDTH]};
    end
  endfunction

  function automatic [31:0] expected_tx_idle_status;
    input [31:0] mode;
    begin
      expected_tx_idle_status = 32'h00000008 |
                                ((mode & 32'h00000003) << 4) |
                                ((mode & 32'h0000000c) << 4);
    end
  endfunction

  function automatic known_tx_mode;
    input [31:0] mode;
    begin
      known_tx_mode = (mode == MODE_TX_COMPRESS_AES_BLOCK)  ||
                      (mode == MODE_TX_COMPRESS_ONLY_BLOCK) ||
                      (mode == MODE_TX_COMPRESS_AES_WHOLE)  ||
                      (mode == MODE_TX_COMPRESS_ONLY_WHOLE);
    end
  endfunction

  initial begin
    input_file_name = "input4.txt";
    if ($value$plusargs("INPUT_FILE=%s", input_file_name))
      $display("# INPUT_FILE override: %0s", input_file_name);
  end

  task automatic check_eq_2;
    input [8*64-1:0] name;
    input [1:0] actual;
    input [1:0] expected;
    begin
      if (actual === expected) begin
        pass_count = pass_count + 1;
        $display("[PASS] %0s | actual=%0b expected=%0b", name, actual, expected);
      end else begin
        fail_count = fail_count + 1;
        $display("[FAIL] %0s | actual=%0b expected=%0b", name, actual, expected);
      end
    end
  endtask

  task automatic check_eq_32;
    input [8*64-1:0] name;
    input [31:0] actual;
    input [31:0] expected;
    begin
      if (actual === expected) begin
        pass_count = pass_count + 1;
        $display("[PASS] %0s | actual=0x%08x expected=0x%08x", name, actual, expected);
      end else begin
        fail_count = fail_count + 1;
        $display("[FAIL] %0s | actual=0x%08x expected=0x%08x", name, actual, expected);
      end
    end
  endtask

  task automatic check_true;
    input [8*64-1:0] name;
    input             cond;
    begin
      if (cond) begin
        pass_count = pass_count + 1;
        $display("[PASS] %0s", name);
      end else begin
        fail_count = fail_count + 1;
        $display("[FAIL] %0s", name);
      end
    end
  endtask

  task automatic aux_write_word;
    input [31:0] addr;
    input [31:0] data;
    begin
      aux_en    = 1'b1;
      aux_we    = 4'b1111;
      aux_addr  = addr;
      aux_wdata = data;
      @(posedge clk);
      #1;
      aux_en    = 1'b0;
      aux_we    = 4'b0000;
      aux_addr  = 32'b0;
      aux_wdata = 32'b0;
    end
  endtask

  task automatic aux_read_word;
    input  [31:0] addr;
    output [31:0] data;
    begin
      aux_en    = 1'b1;
      aux_we    = 4'b0000;
      aux_addr  = addr;
      aux_wdata = 32'b0;
      @(posedge clk);
      #1 data = aux_rdata;
      aux_en    = 1'b0;
      aux_addr  = 32'b0;
      aux_wdata = 32'b0;
    end
  endtask

  task automatic aux_read_byte;
    input  [31:0] byte_addr;
    output [7:0]  data;
    reg [31:0] aligned_word;
    begin
      aux_read_word({byte_addr[31:2], 2'b00}, aligned_word);
      data = byte_from_word(aligned_word, byte_addr[1:0]);
    end
  endtask

  task automatic load_input_txt_to_dmem;
    integer fd;
    integer ch;
    integer idx;
    integer word_idx;
    integer lane_idx;
    reg [31:0] packed_word;
    begin
      for (idx = 0; idx < MAX_INPUT_BYTES; idx = idx + 1)
        input_bytes[idx] = 8'h00;

      input_len_bytes = 0;
      fd = $fopen(input_file_name, "r");
      if (fd == 0) begin
        $display("[FAIL] cannot open file: %0s", input_file_name);
        fail_count = fail_count + 1;
        $finish;
      end

      while (!$feof(fd)) begin
        ch = $fgetc(fd);
        if ((ch != -1) && (ch[7:0] != 8'h0D)) begin
          if (input_len_bytes >= MAX_INPUT_BYTES) begin
            $display("[FAIL] input file is larger than MAX_INPUT_BYTES=%0d", MAX_INPUT_BYTES);
            fail_count = fail_count + 1;
            $finish;
          end
          input_bytes[input_len_bytes] = ch[7:0];
          input_len_bytes = input_len_bytes + 1;
        end
      end
      $fclose(fd);

      if (input_len_bytes == 0) begin
        $display("[FAIL] input file is empty");
        fail_count = fail_count + 1;
        $finish;
      end

      if (input_len_bytes > SRC_BUFFER_BYTES) begin
        $display("[FAIL] input file exceeds source buffer size: %0d > %0d",
                 input_len_bytes, SRC_BUFFER_BYTES);
        fail_count = fail_count + 1;
        $finish;
      end

      for (word_idx = 0; word_idx < ((input_len_bytes + 3) / 4); word_idx = word_idx + 1) begin
        packed_word = 32'b0;
        for (lane_idx = 0; lane_idx < 4; lane_idx = lane_idx + 1) begin
          idx = (word_idx * 4) + lane_idx;
          if (idx < input_len_bytes)
            packed_word[(lane_idx * 8) +: 8] = input_bytes[idx];
        end
        aux_write_word(SRC_BASE_ADDR + (word_idx * 4), packed_word);
      end

      aux_write_word(INPUT_LEN_ADDR, input_len_bytes);
      $display("# Loaded %0d byte(s) from %0s into DMEM @ 0x%08x",
               input_len_bytes, input_file_name, SRC_BASE_ADDR);
    end
  endtask

  task automatic dump_dmem_region;
    input [8*64-1:0] file_name;
    input [31:0]     base_addr;
    input integer    byte_count;
    integer fd;
    integer idx;
    reg [7:0] byte_val;
    begin
      fd = $fopen(file_name, "w");
      if (fd == 0) begin
        $display("[FAIL] cannot open dump file: %0s", file_name);
        fail_count = fail_count + 1;
        $finish;
      end

      $fdisplay(fd, "base_addr=0x%08x byte_count=%0d", base_addr, byte_count);
      $fdisplay(fd, "idx addr byte ascii");
      for (idx = 0; idx < byte_count; idx = idx + 1) begin
        aux_read_byte(base_addr + idx, byte_val);
        $fdisplay(fd, "%0d 0x%08x %02x %c",
                  idx, base_addr + idx, byte_val, printable_byte(byte_val));
      end
      $fclose(fd);
    end
  endtask

  task automatic compare_source_file;
    integer idx;
    reg [7:0] src_byte;
    begin
      src_mismatch_count = 0;
      for (idx = 0; idx < input_len_bytes; idx = idx + 1) begin
        aux_read_byte(SRC_BASE_ADDR + idx, src_byte);
        if (src_byte !== input_bytes[idx])
          src_mismatch_count = src_mismatch_count + 1;
      end
    end
  endtask

  task automatic count_nonzero_region;
    input [31:0]  base_addr;
    input integer byte_count;
    output integer nonzero_count;
    integer idx;
    reg [7:0] byte_val;
    begin
      nonzero_count = 0;
      for (idx = 0; idx < byte_count; idx = idx + 1) begin
        aux_read_byte(base_addr + idx, byte_val);
        if (byte_val != 8'h00)
          nonzero_count = nonzero_count + 1;
      end
    end
  endtask

  task automatic write_summary_file;
    integer fd;
    begin
      fd = $fopen(SUMMARY_FILE, "w");
      if (fd == 0) begin
        $display("[FAIL] cannot open summary file: %0s", SUMMARY_FILE);
        fail_count = fail_count + 1;
        $finish;
      end

      $fdisplay(fd, "input_file=%0s", input_file_name);
      $fdisplay(fd, "input_len_bytes=%0d", input_len_bytes);
      $fdisplay(fd, "src_base_addr=0x%08x", SRC_BASE_ADDR);
      $fdisplay(fd, "tx_dst_base_addr=0x%08x", TX_DST_BASE_ADDR);
      $fdisplay(fd, "tx_ciphertext_bytes=%0d", tx_ciphertext_bytes);
      $fdisplay(fd, "compressed_payload_bits=%0d", compressed_payload_bits);
      $fdisplay(fd, "compressed_payload_bytes_ceil=%0d", compressed_payload_bytes_ceil);
      $fdisplay(fd, "tx_start_cycle=%0d", tx_start_cycle);
      $fdisplay(fd, "tx_end_cycle=%0d", tx_end_cycle);
      $fdisplay(fd, "tx_busy_cycles=%0d", tx_busy_cycles);
      $fdisplay(fd, "tx_input_bytes_per_cycle=%0.6f", tx_input_bytes_per_cycle);
      $fdisplay(fd, "tx_output_bytes_per_cycle=%0.6f", tx_output_bytes_per_cycle);
      $fdisplay(fd, "tx_input_mbytes_per_sec=%0.3f", tx_input_mbytes_per_sec);
      $fdisplay(fd, "tx_output_mbytes_per_sec=%0.3f", tx_output_mbytes_per_sec);
      $fdisplay(fd, "payload_ratio_pct=%0.2f", payload_ratio_pct);
      $fdisplay(fd, "payload_space_saving_pct=%0.2f", payload_space_saving_pct);
      $fdisplay(fd, "storage_ratio_pct=%0.2f", storage_ratio_pct);
      $fdisplay(fd, "space_saving_pct=%0.2f", space_saving_pct);
      $fdisplay(fd, "src_mismatch_count=%0d", src_mismatch_count);
      $fdisplay(fd, "tx_nonzero_byte_count=%0d", tx_nonzero_byte_count);
      $fdisplay(fd, "pass_count=%0d", pass_count);
      $fdisplay(fd, "fail_count=%0d", fail_count);
      $fclose(fd);
    end
  endtask

  rv32_soc_top dut (
    .clk_i          (clk),
    .rst_i          (rst),
    .aux_en_i       (aux_en),
    .aux_we_i       (aux_we),
    .aux_addr_i     (aux_addr),
    .aux_wdata_i    (aux_wdata),
    .aux_rdata_o    (aux_rdata),
    .cpu_if_flush_i (cpu_if_flush),
    .cpu_stall_i    (cpu_stall),
    .mem_err_o      (mem_err_o)
  );

  always #5 clk = ~clk;

  always @(posedge clk) begin
    if (rst) begin
      dma_start_pulse_count <= 0;
      cycle_counter         <= 0;
      tx_busy_cycles        <= 0;
      tx_start_cycle        <= -1;
      tx_end_cycle          <= -1;
      tx_seen_busy          <= 1'b0;
      tx_busy_prev          <= 1'b0;
      compressed_payload_bits <= 0;
    end else begin
      cycle_counter <= cycle_counter + 1;

      if (dut.u_dma_regfile.start_pulse_o)
        dma_start_pulse_count <= dma_start_pulse_count + 1;

      if (dut.tx_dma_busy_w)
        tx_busy_cycles <= tx_busy_cycles + 1;

      if ((!tx_seen_busy) && dut.tx_dma_busy_w) begin
        tx_seen_busy   <= 1'b1;
        tx_start_cycle <= cycle_counter;
      end

      if (dut.tx_cipher_en_dbg_w)
        compressed_payload_bits <= compressed_payload_bits +
                                   tx_transport_valid_bits(dut.tx_transport_word_dbg_w);

      if (tx_seen_busy && tx_busy_prev && (!dut.tx_dma_busy_w) && (tx_end_cycle < 0))
        tx_end_cycle <= cycle_counter;

      tx_busy_prev <= dut.tx_dma_busy_w;
    end
  end

  task automatic run_selected_test;
    begin
    clk = 0;
    rst = 1;
    aux_en = 1'b0;
    aux_we = 4'b0000;
    aux_addr = 32'b0;
    aux_wdata = 32'b0;
    cpu_if_flush = 1'b0;
    cpu_stall = 1'b0;
    pass_count = 0;
    fail_count = 0;
    dma_start_pulse_count = 0;
    wait_cycles = 0;
    input_len_bytes = 0;
    src_mismatch_count = 0;
    tx_nonzero_byte_count = 0;
    tx_ciphertext_bytes = 0;
    compressed_payload_bytes_ceil = 0;
    tx_input_bytes_per_cycle = 0.0;
    tx_output_bytes_per_cycle = 0.0;
    tx_input_mbytes_per_sec = 0.0;
    tx_output_mbytes_per_sec = 0.0;
    payload_ratio_pct = 0.0;
    payload_space_saving_pct = 0.0;
    storage_ratio_pct = 0.0;
    space_saving_pct = 0.0;

    for (i = 0; i < 14; i = i + 1)
      result_words[i] = 32'b0;
    for (i = 0; i < 4; i = i + 1)
      tx_dst_words[i] = 32'b0;

    system_rc = $system("mkdir -p tx_only dmem_dump");

    repeat (2) @(negedge clk);
    load_input_txt_to_dmem;
    rst = 0;

    wait_cycles = 0;
    begin : wait_signature
      while (wait_cycles < MAX_WAIT_CYCLES) begin
        aux_read_word(32'h00000000, result_words[0]);
        if (result_words[0] === RESULT_SIGNATURE)
          disable wait_signature;
        @(posedge clk);
        wait_cycles = wait_cycles + 1;
      end
    end

    repeat (128) @(posedge clk);

    for (i = 0; i < 14; i = i + 1)
      aux_read_word(i * 4, result_words[i]);

    tx_ciphertext_bytes = result_words[5];

    if (tx_ciphertext_bytes > TX_BUFFER_BYTES) begin
      $display("[FAIL] tx ciphertext length exceeds TX buffer: %0d > %0d",
               tx_ciphertext_bytes, TX_BUFFER_BYTES);
      fail_count = fail_count + 1;
      $finish;
    end

    for (i = 0; i < 4; i = i + 1)
      aux_read_word(TX_DST_BASE_ADDR + (i * 4), tx_dst_words[i]);

    dump_dmem_region(SRC_DUMP_FILE, SRC_BASE_ADDR, input_len_bytes);
    dump_dmem_region(TX_DUMP_FILE, TX_DST_BASE_ADDR, tx_ciphertext_bytes);
    compare_source_file;
    count_nonzero_region(TX_DST_BASE_ADDR, tx_ciphertext_bytes, tx_nonzero_byte_count);

    if (tx_busy_cycles > 0) begin
      tx_input_bytes_per_cycle  = input_len_bytes;
      tx_input_bytes_per_cycle  = tx_input_bytes_per_cycle / tx_busy_cycles;
      tx_output_bytes_per_cycle = tx_ciphertext_bytes;
      tx_output_bytes_per_cycle = tx_output_bytes_per_cycle / tx_busy_cycles;
      tx_input_mbytes_per_sec   = (tx_input_bytes_per_cycle * (1000.0 / CLOCK_PERIOD_NS));
      tx_output_mbytes_per_sec  = (tx_output_bytes_per_cycle * (1000.0 / CLOCK_PERIOD_NS));
    end

    if (input_len_bytes > 0) begin
      compressed_payload_bytes_ceil = (compressed_payload_bits + 7) / 8;
      payload_ratio_pct = (100.0 * compressed_payload_bits) / (input_len_bytes * 8.0);
      payload_space_saving_pct = 100.0 - payload_ratio_pct;
      storage_ratio_pct = (100.0 * tx_ciphertext_bytes) / input_len_bytes;
      space_saving_pct  = 100.0 - storage_ratio_pct;
    end

    $display("# ===== RV32I SOC DMA TX-ONLY CHECK =====");
    $display("# input_file=%0s input_len=%0d", input_file_name, input_len_bytes);
    $display("# dma_cfg src=0x%08x dst=0x%08x len=0x%08x dir=0x%0x compress_only=%0b block=0x%0x",
             dut.u_dma_regfile.src_addr_o,
             dut.u_dma_regfile.dst_addr_o,
             dut.u_dma_regfile.len_bytes_o,
             dut.u_dma_regfile.direction_o,
             dut.u_dma_regfile.compress_only_o,
             dut.u_dma_regfile.block_size_o);
    $display("# tx_dma state=%0d busy=%0b done=%0b err=%0b bytes=0x%08x last_err=0x%02x",
             dut.tx_dma_state_w,
             dut.tx_dma_busy_w,
             dut.tx_dma_done_w,
             dut.tx_dma_error_w,
             dut.tx_dma_bytes_done_w,
             dut.tx_dma_last_error_w);
    $display("# DEBUG tx_if cfg=%0b block_inflight=%0b stream_active=%0b fifo_count=%0d done_sticky=%0b count_mode=%0b count_done=%0b tx_busy_i=%0b",
             dut.u_tx_top.u_apb_huffman_tx_if.cfg_valid_r,
             dut.u_tx_top.u_apb_huffman_tx_if.block_inflight_r,
             dut.u_tx_top.u_apb_huffman_tx_if.stream_active_r,
             dut.u_tx_top.u_apb_huffman_tx_if.fifo_count_r,
             dut.u_tx_top.u_apb_huffman_tx_if.done_sticky_r,
             dut.u_tx_top.u_apb_huffman_tx_if.whole_file_count_mode_o,
             dut.u_tx_top.u_apb_huffman_tx_if.count_mode_done_w,
             dut.u_tx_top.u_apb_huffman_tx_if.tx_busy_i);
    $display("# DEBUG tx_core block_active=%0b word_buf_valid=%0b start_pending=%0b count_mode_active=%0b count_done=%0b bytes_total=%0d queued=%0d sent=%0d file_busy=%0b file_done=%0b file_err=%0b table_valid=%0b flush=%0b packer_busy=%0b packer_valid=%0b encoder_busy=%0b encoder_done=%0b",
             dut.u_tx_top.u_huffman_aes_tx_top.block_active_r,
             dut.u_tx_top.u_huffman_aes_tx_top.word_buf_valid_r,
             dut.u_tx_top.u_huffman_aes_tx_top.start_pending_r,
             dut.u_tx_top.u_huffman_aes_tx_top.count_mode_active_r,
             dut.u_tx_top.u_huffman_aes_tx_top.count_done_r,
             dut.u_tx_top.u_huffman_aes_tx_top.bytes_total_r,
             dut.u_tx_top.u_huffman_aes_tx_top.bytes_queued_r,
             dut.u_tx_top.u_huffman_aes_tx_top.bytes_sent_r,
             dut.u_tx_top.u_huffman_aes_tx_top.file_build_busy_w,
             dut.u_tx_top.u_huffman_aes_tx_top.file_build_done_w,
             dut.u_tx_top.u_huffman_aes_tx_top.file_build_error_w,
             dut.u_tx_top.u_huffman_aes_tx_top.global_table_valid_r,
             dut.u_tx_top.u_huffman_aes_tx_top.flush_on_block_end_r,
             dut.u_tx_top.u_huffman_aes_tx_top.packer_busy,
             dut.u_tx_top.u_huffman_aes_tx_top.packer_transport_valid,
             dut.u_tx_top.u_huffman_aes_tx_top.encoder_busy,
             dut.u_tx_top.u_huffman_aes_tx_top.encoder_done);
    $display("# tx_dst_head = %08x %08x %08x %08x",
             tx_dst_words[0], tx_dst_words[1], tx_dst_words[2], tx_dst_words[3]);
    $display("# BENCHMARK tx_cycles=%0d tx_cipher_bytes=%0d",
             tx_busy_cycles, tx_ciphertext_bytes);
    $display("# THROUGHPUT tx_in=%0.3f MB/s tx_out=%0.3f MB/s",
             tx_input_mbytes_per_sec, tx_output_mbytes_per_sec);
    $display("# PAYLOAD compressed_bits=%0d compressed_bytes_ceil=%0d ratio=%0.2f%% space_saving=%0.2f%%",
             compressed_payload_bits, compressed_payload_bytes_ceil,
             payload_ratio_pct, payload_space_saving_pct);
    $display("# STORAGE ratio=%0.2f%% space_saving=%0.2f%%",
             storage_ratio_pct, space_saving_pct);
    $display("# TX_ONLY src_mismatch=%0d tx_nonzero_bytes=%0d",
             src_mismatch_count, tx_nonzero_byte_count);
    $display("# FILES summary=%0s src_dump=%0s tx_dump=%0s",
             SUMMARY_FILE, SRC_DUMP_FILE, TX_DUMP_FILE);

    check_eq_2 ("mem_err_o_should_be_zero", mem_err_o, 2'b00);
    check_true ("cpu_should_publish_result_signature_before_timeout", result_words[0] == RESULT_SIGNATURE);
    check_eq_32("result_signature", result_words[0], RESULT_SIGNATURE);
    check_eq_32("cpu_error_mask_should_be_zero", result_words[1], 32'h00000000);
    check_true ("tx_mode_should_be_known", known_tx_mode(result_words[8]));
    check_eq_32("tx_status_before_start", result_words[2], expected_tx_idle_status(result_words[8]));
    check_eq_32("tx_status_after_done", result_words[3], expected_tx_idle_status(result_words[8]) | 32'h00000002);
    check_true ("tx_bytes_done_should_be_transport_aligned",
                (result_words[4] != 32'h00000000) &&
                ((result_words[4] & 32'h0000000f) == 32'h00000000));
    check_eq_32("tx_ciphertext_bytes_produced_should_match_tx_bytes_done",
                result_words[5], result_words[4]);
    check_true ("tx_poll_count_should_be_nonzero", result_words[6] != 32'h00000000);
    check_eq_32("tx_debug_after_done", result_words[7], 32'h00000000);
    check_eq_32("input_len_echo", result_words[9], input_len_bytes);
    check_eq_32("source_dmem_should_match_input_file", src_mismatch_count, 32'h00000000);
    check_true ("tx_region_should_not_be_all_zero", tx_nonzero_byte_count != 0);
    check_eq_32("dma_start_pulse_count", dma_start_pulse_count, 32'h00000001);

    $display("# SUMMARY: PASS=%0d FAIL=%0d", pass_count, fail_count);
    if (fail_count == 0)
      $display("[PASS] rv32_soc_dma_tx_only_test");
    else
      $display("[FAIL] rv32_soc_dma_tx_only_test");

    write_summary_file;
    $finish;
    end
  endtask

  `include "run_test.v"

  initial begin
    run_test();
  end
endmodule
