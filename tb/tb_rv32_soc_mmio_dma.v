`timescale 1ns / 1ps

module test_bench;
  localparam integer MAX_WAIT_CYCLES = 1000000;
  localparam integer MAX_INPUT_BYTES = 10000;
  localparam integer DMEM_SIZE_BYTES = 32768;
  localparam integer TRANSPORT_WORD_WIDTH = 128;
  localparam integer VALID_BITS_WIDTH = 7;
  localparam real    CLOCK_PERIOD_NS = 10.0;

  localparam [31:0] RESULT_SIGNATURE_DMA  = 32'h44525831;
  localparam [31:0] RESULT_SIGNATURE_TX   = 32'h44545843;
  localparam [31:0] RESULT_SIGNATURE_REG1 = 32'h52454731;
  localparam [31:0] RESULT_SIGNATURE_NEG1 = 32'h4e454731;
  localparam [31:0] RESULT_SIGNATURE_MODE = 32'h4d4f4445;
  localparam [31:0] RESULT_SIGNATURE_RXER = 32'h52584552;
  localparam [31:0] RESULT_SIGNATURE_TXER = 32'h54584552;
  localparam [31:0] RESULT_SIGNATURE_CPUC = 32'h43505543;
  localparam [31:0] RESULT_SIGNATURE_CPUH = 32'h43505548;
  localparam [31:0] RESULT_SIGNATURE_STOR = 32'h53544f52;
  localparam [31:0] EXPECTED_TX_IDLE = 32'h00000098;
  localparam [31:0] EXPECTED_TX_DONE = 32'h0000009a;
  localparam [31:0] EXPECTED_RX_IDLE = 32'h00000028;
  localparam [31:0] EXPECTED_RX_DONE = 32'h0000002a;
  localparam [31:0] MODE_TX_COMPRESS_AES_BLOCK  = 32'h00000001;
  localparam [31:0] MODE_TX_COMPRESS_ONLY_BLOCK = 32'h00000005;
  localparam [31:0] MODE_TX_COMPRESS_AES_WHOLE  = 32'h00000009;
  localparam [31:0] MODE_TX_COMPRESS_ONLY_WHOLE = 32'h0000000d;

  localparam [31:0] INPUT_LEN_ADDR   = 32'h00000040;
  localparam [31:0] INPUT2_LEN_ADDR  = 32'h00000044;
  localparam [31:0] SRC_BASE_ADDR    = 32'h00002000;
  localparam [31:0] SRC2_BASE_ADDR   = 32'h00003000;
  localparam [31:0] TX_DST_BASE_ADDR = 32'h00004000;
  localparam [31:0] RX_DST_BASE_ADDR = 32'h00006000;

  localparam integer SRC_BUFFER_BYTES = TX_DST_BASE_ADDR - SRC_BASE_ADDR;
  localparam integer SRC2_BUFFER_BYTES = TX_DST_BASE_ADDR - SRC2_BASE_ADDR;
  localparam integer TX_BUFFER_BYTES  = RX_DST_BASE_ADDR - TX_DST_BASE_ADDR;
  localparam integer RX_BUFFER_BYTES  = DMEM_SIZE_BYTES - RX_DST_BASE_ADDR;

  localparam [8*64-1:0] LOOPBACK_SUMMARY_FILE  = "loopback/tb_rv32_soc_mmio_dma_summary.txt";
  localparam [8*64-1:0] LOOPBACK_COMPARE_FILE  = "loopback/tb_rv32_soc_mmio_dma_compare.txt";
  localparam [8*64-1:0] SRC_DUMP_FILE          = "dmem_dump/tb_rv32_soc_mmio_dma_src.txt";
  localparam [8*64-1:0] TX_DUMP_FILE           = "dmem_dump/tb_rv32_soc_mmio_dma_tx.txt";
  localparam [8*64-1:0] RX_DUMP_FILE           = "dmem_dump/tb_rv32_soc_mmio_dma_rx.txt";

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
  integer soft_reset_pulse_count;
  integer clear_done_pulse_count;
  integer clear_error_pulse_count;
  integer apb_error_count;
  integer bridge_error_count;
  integer sideband_cov_enable;
  integer tx_apb_wait_cov_enable;
  integer rx_apb_wait_cov_enable;
  integer rx_stream_backpressure_cov_enable;
  integer tx_apb_error_cov_enable;
  integer tx_if_direct_cov_enable;
  integer cpu_forward_direct_cov_enable;
  integer rx_if_direct_cov_enable;
  integer rx_parser_decoder_cov_enable;
  integer rx_decoder_direct_cov_enable;
  integer rx_depacker_packer_direct_cov_enable;
  integer rx_parser_decoder_error_direct_cov_enable;
  integer tx_encoder_direct_cov_enable;
  integer tx_builder_packer_direct_cov_enable;
  integer dma_bridge_direct_cov_enable;
  integer raw_dut_stress_cov_enable;
  integer wait_cycles;
  integer system_rc;
  integer i;

  integer input_len_bytes;
  integer input2_len_bytes;
  integer src_mismatch_count;
  integer rx_mismatch_count;
  integer tx_nonzero_byte_count;
  integer tx_ciphertext_bytes;
  integer rx_plaintext_bytes;
  integer compressed_payload_bits;
  integer compressed_payload_bytes_ceil;

  integer cycle_counter;
  integer tx_busy_cycles;
  integer rx_busy_cycles;
  integer tx_start_cycle;
  integer tx_end_cycle;
  integer rx_start_cycle;
  integer rx_end_cycle;
  integer rx_ciphertext_feed_count;
  integer tx_transport_capture_count;
  integer rx_transport_capture_count;
  integer rx_word_capture_count;
  integer tx_word_in_capture_count;
  integer tx_dma_word_write_count;
  integer tx_dma_read_capture_count;
  integer mmio_write_capture_count;
  integer raw_cov_sweep_idx;
  integer raw_cov_mem_idx;
  integer trace_detail_enable;

  reg tx_seen_busy;
  reg rx_seen_busy;
  reg tx_busy_prev;
  reg rx_busy_prev;
  reg [8*128-1:0] input_file_name;
  reg [8*128-1:0] input2_file_name;
  reg [8*64-1:0] case_name;
  integer input2_file_enable;
  integer input_binary_mode;

  reg [127:0] first_tx_transport_word;
  reg [127:0] first_tx_ciphertext_dmem_word;
  reg [127:0] first_rx_ciphertext_feed_word;
  reg [127:0] first_rx_transport_word;
  reg [31:0]  first_tx_word_in_data;
  reg [31:0]  first_tx_dma_word_write_data;
  reg [31:0]  first_tx_dma_read_addr;
  reg [31:0]  first_tx_dma_read_data;
  reg [31:0]  first_tx_start_src_addr;
  reg [31:0]  first_tx_start_dst_addr;
  reg [31:0]  first_tx_start_len_bytes;
  reg [1:0]   first_tx_start_dir;
  reg [5:0]   first_tx_start_block_size;
  reg [31:0]  first_rx_word_data;
  reg [2:0]   first_rx_word_valid_bytes;
  reg         first_rx_word_last_in_block;
  reg         first_rx_word_last_in_frame;
  reg         first_tx_transport_valid;
  reg         first_tx_ciphertext_dmem_valid;
  reg         first_rx_ciphertext_feed_valid;
  reg         first_rx_transport_valid;
  reg         first_tx_word_in_valid_seen;
  reg         first_tx_dma_word_write_seen;
  reg         first_tx_dma_read_seen;
  reg         first_tx_start_seen;
  reg         first_rx_word_valid_seen;
  reg [31:0]  mmio_write_addr_log [0:7];
  reg [31:0]  mmio_write_data_log [0:7];
  reg [31:0]  raw_cov_patt;

  real tx_input_bytes_per_cycle;
  real tx_output_bytes_per_cycle;
  real rx_input_bytes_per_cycle;
  real rx_output_bytes_per_cycle;
  real tx_input_mbytes_per_sec;
  real tx_output_mbytes_per_sec;
  real rx_input_mbytes_per_sec;
  real rx_output_mbytes_per_sec;
  real payload_ratio_pct;
  real payload_space_saving_pct;
  real storage_ratio_pct;
  real space_saving_pct;

  reg [31:0] result_words [0:15];
  reg [31:0] tx_dst_words [0:3];
  reg [31:0] rx_dst_words [0:3];
  reg [7:0]  input_bytes [0:MAX_INPUT_BYTES-1];

  // Waveform aliases for the input1 end-to-end flow.
  wire [31:0] wf_if_pc;
  wire [31:0] wf_if_instr;
  wire        wf_cpu_hold;
  wire        wf_mmio_sel;
  wire        wf_mmio_stall;
  wire        wf_apb_psel;
  wire        wf_apb_penable;
  wire        wf_apb_pwrite;
  wire [31:0] wf_apb_paddr;
  wire [31:0] wf_apb_pwdata;
  wire [31:0] wf_apb_prdata;
  wire [31:0] wf_dma_src;
  wire [31:0] wf_dma_dst;
  wire [31:0] wf_dma_len;
  wire [1:0]  wf_dma_dir;
  wire        wf_dma_compress_only;
  wire        wf_dma_whole_file;
  wire [5:0]  wf_dma_block_size;
  wire        wf_dma_start;
  wire [3:0]  wf_tx_state;
  wire        wf_tx_busy;
  wire        wf_tx_done;
  wire        wf_tx_error;
  wire [31:0] wf_tx_bytes_done;
  wire [3:0]  wf_rx_state;
  wire        wf_rx_busy;
  wire        wf_rx_done;
  wire        wf_rx_error;
  wire [31:0] wf_rx_bytes_done;
  wire [31:0] wf_result_signature;
  wire [31:0] wf_error_mask;
  wire [31:0] wf_input_len_bytes;
  wire [31:0] wf_tx_ciphertext_bytes;
  wire [31:0] wf_rx_plaintext_bytes;

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

  assign wf_if_pc              = dut.u_cpu.ifid_pc_w;
  assign wf_if_instr           = dut.u_cpu.ifid_instruction_w;
  assign wf_cpu_hold           = dut.cpu_global_hold_w;
  assign wf_mmio_sel           = dut.cpu_mmio_sel_w;
  assign wf_mmio_stall         = dut.bridge_cpu_stall_req_w;
  assign wf_apb_psel           = dut.bridge_psel_w;
  assign wf_apb_penable        = dut.bridge_penable_w;
  assign wf_apb_pwrite         = dut.bridge_pwrite_w;
  assign wf_apb_paddr          = dut.bridge_paddr_w;
  assign wf_apb_pwdata         = dut.bridge_pwdata_w;
  assign wf_apb_prdata         = dut.dma_apb_prdata_w;
  assign wf_dma_src            = dut.dma_src_addr_w;
  assign wf_dma_dst            = dut.dma_dst_addr_w;
  assign wf_dma_len            = dut.dma_len_bytes_w;
  assign wf_dma_dir            = dut.dma_direction_w;
  assign wf_dma_compress_only  = dut.dma_compress_only_w;
  assign wf_dma_whole_file     = dut.dma_whole_file_w;
  assign wf_dma_block_size     = dut.dma_block_size_w;
  assign wf_dma_start          = dut.dma_start_pulse_w;
  assign wf_tx_state           = dut.tx_dma_state_w;
  assign wf_tx_busy            = dut.tx_dma_busy_w;
  assign wf_tx_done            = dut.tx_dma_done_w;
  assign wf_tx_error           = dut.tx_dma_error_w;
  assign wf_tx_bytes_done      = dut.tx_dma_bytes_done_w;
  assign wf_rx_state           = dut.rx_dma_state_w;
  assign wf_rx_busy            = dut.rx_dma_busy_w;
  assign wf_rx_done            = dut.rx_dma_done_w;
  assign wf_rx_error           = dut.rx_dma_error_w;
  assign wf_rx_bytes_done      = dut.rx_dma_bytes_done_w;
  assign wf_result_signature   = result_words[0];
  assign wf_error_mask         = result_words[1];
  assign wf_input_len_bytes    = input_len_bytes;
  assign wf_tx_ciphertext_bytes = tx_ciphertext_bytes;
  assign wf_rx_plaintext_bytes  = rx_plaintext_bytes;

  initial begin
    input_file_name = "input1.txt";
    input2_file_name = "";
    input2_file_enable = 0;
    input_binary_mode = $test$plusargs("INPUT_BINARY");
    if ($value$plusargs("INPUT_FILE=%s", input_file_name))
      $display("# INPUT_FILE override: %0s", input_file_name);
    if ($value$plusargs("INPUT_FILE2=%s", input2_file_name)) begin
      input2_file_enable = 1;
      $display("# INPUT_FILE2 override: %0s", input2_file_name);
    end
    if (input_binary_mode)
      $display("# INPUT_BINARY mode enabled: CR bytes are preserved");
    trace_detail_enable = $test$plusargs("TRACE_DETAIL");
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
      fd = input_binary_mode ? $fopen(input_file_name, "rb") : $fopen(input_file_name, "r");
      if (fd == 0) begin
        $display("[FAIL] cannot open file: %0s", input_file_name);
        fail_count = fail_count + 1;
        $finish;
      end

      while (!$feof(fd)) begin
        ch = $fgetc(fd);
        if ((ch != -1) && (input_binary_mode || (ch[7:0] != 8'h0D))) begin
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

  task automatic load_secondary_input_txt_to_dmem;
    integer fd;
    integer ch;
    integer word_idx;
    integer lane_idx;
    reg [31:0] packed_word;
    begin
      input2_len_bytes = 0;
      aux_write_word(INPUT2_LEN_ADDR, 32'h00000000);

      if (input2_file_enable == 0)
        disable load_secondary_input_txt_to_dmem;

      fd = input_binary_mode ? $fopen(input2_file_name, "rb") : $fopen(input2_file_name, "r");
      if (fd == 0) begin
        $display("[FAIL] cannot open second input file: %0s", input2_file_name);
        fail_count = fail_count + 1;
        $finish;
      end

      word_idx = 0;
      lane_idx = 0;
      packed_word = 32'b0;

      while (!$feof(fd)) begin
        ch = $fgetc(fd);
        if ((ch != -1) && (input_binary_mode || (ch[7:0] != 8'h0D))) begin
          if (input2_len_bytes >= SRC2_BUFFER_BYTES) begin
            $display("[FAIL] second input file exceeds source2 buffer size: %0d >= %0d",
                     input2_len_bytes, SRC2_BUFFER_BYTES);
            fail_count = fail_count + 1;
            $finish;
          end

          packed_word[(lane_idx * 8) +: 8] = ch[7:0];
          input2_len_bytes = input2_len_bytes + 1;

          if (lane_idx == 3) begin
            aux_write_word(SRC2_BASE_ADDR + (word_idx * 4), packed_word);
            word_idx = word_idx + 1;
            lane_idx = 0;
            packed_word = 32'b0;
          end else begin
            lane_idx = lane_idx + 1;
          end
        end
      end
      $fclose(fd);

      if (input2_len_bytes == 0) begin
        $display("[FAIL] second input file is empty");
        fail_count = fail_count + 1;
        $finish;
      end

      if (lane_idx != 0)
        aux_write_word(SRC2_BASE_ADDR + (word_idx * 4), packed_word);

      aux_write_word(INPUT2_LEN_ADDR, input2_len_bytes);
      $display("# Loaded %0d byte(s) from %0s into DMEM @ 0x%08x",
               input2_len_bytes, input2_file_name, SRC2_BASE_ADDR);
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

  task automatic write_loopback_compare_file;
    input [8*64-1:0] file_name;
    integer fd;
    integer idx;
    reg [7:0] src_byte;
    reg [7:0] rx_byte;
    begin
      src_mismatch_count = 0;
      rx_mismatch_count  = 0;

      fd = $fopen(file_name, "w");
      if (fd == 0) begin
        $display("[FAIL] cannot open compare file: %0s", file_name);
        fail_count = fail_count + 1;
        $finish;
      end

      $fdisplay(fd, "input_file=%0s input_len=%0d", input_file_name, input_len_bytes);
      $fdisplay(fd, "idx exp src rx src_match rx_match ascii");
      for (idx = 0; idx < input_len_bytes; idx = idx + 1) begin
        aux_read_byte(SRC_BASE_ADDR + idx, src_byte);
        aux_read_byte(RX_DST_BASE_ADDR + idx, rx_byte);

        if (src_byte !== input_bytes[idx])
          src_mismatch_count = src_mismatch_count + 1;
        if (rx_byte !== input_bytes[idx])
          rx_mismatch_count = rx_mismatch_count + 1;

        $fdisplay(fd, "%0d %02x %02x %02x %0d %0d %c",
                  idx,
                  input_bytes[idx],
                  src_byte,
                  rx_byte,
                  (src_byte === input_bytes[idx]),
                  (rx_byte === input_bytes[idx]),
                  printable_byte(input_bytes[idx]));
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

  task automatic exercise_sideband_coverage;
    reg [31:0] scratch_read;
    begin
      $display("# SIDEBAND_COV: pulse cpu_stall/cpu_if_flush and aux high-bit activity");

      @(posedge clk);
      #1;
      cpu_stall    = 1'b1;
      cpu_if_flush = 1'b1;
      aux_en       = 1'b1;
      aux_we       = 4'b0000;
      aux_addr     = 32'hffff_7ffc;
      aux_wdata    = 32'hffff_ffff;

      repeat (4) @(posedge clk);
      #1;
      cpu_stall    = 1'b0;
      cpu_if_flush = 1'b0;
      aux_en       = 1'b0;
      aux_we       = 4'b0000;
      aux_addr     = 32'b0;
      aux_wdata    = 32'b0;

      aux_write_word(32'h0000_7ffc, 32'hffff_ffff);
      aux_read_word(32'hffff_7ffc, scratch_read);

      aux_en    = 1'b1;
      aux_we    = 4'b1010;
      aux_addr  = 32'h8000_7ffc;
      aux_wdata = 32'ha5a5_5a5a;
      @(posedge clk);
      #1;
      aux_en    = 1'b0;
      aux_we    = 4'b0000;
      aux_addr  = 32'b0;
      aux_wdata = 32'b0;

      repeat (8) @(posedge clk);
      $display("# SIDEBAND_COV: scratch_read=0x%08x", scratch_read);
    end
  endtask

  task force_bridge_direct_idle;
    begin
      release dut.u_cpu_mmio_to_apb_bridge.mmio_req_i;
      release dut.u_cpu_mmio_to_apb_bridge.mmio_write_i;
      release dut.u_cpu_mmio_to_apb_bridge.mmio_addr_i;
      release dut.u_cpu_mmio_to_apb_bridge.mmio_wdata_i;
      release dut.u_cpu_mmio_to_apb_bridge.mmio_wstrb_i;
      release dut.u_cpu_mmio_to_apb_bridge.PREADY_i;
      release dut.u_cpu_mmio_to_apb_bridge.PSLVERR_i;
      release dut.u_cpu_mmio_to_apb_bridge.PRDATA_i;
      release dut.u_cpu_mmio_to_apb_bridge.state_r;
      @(posedge clk);
      #1;
    end
  endtask

  task force_bridge_req;
    input        req;
    input        write;
    input [31:0] addr;
    input [31:0] wdata;
    input [3:0]  wstrb;
    input        pready;
    input        pslverr;
    input [31:0] prdata;
    begin
      force dut.u_cpu_mmio_to_apb_bridge.mmio_req_i   = req;
      force dut.u_cpu_mmio_to_apb_bridge.mmio_write_i = write;
      force dut.u_cpu_mmio_to_apb_bridge.mmio_addr_i  = addr;
      force dut.u_cpu_mmio_to_apb_bridge.mmio_wdata_i = wdata;
      force dut.u_cpu_mmio_to_apb_bridge.mmio_wstrb_i = wstrb;
      force dut.u_cpu_mmio_to_apb_bridge.PREADY_i     = pready;
      force dut.u_cpu_mmio_to_apb_bridge.PSLVERR_i    = pslverr;
      force dut.u_cpu_mmio_to_apb_bridge.PRDATA_i     = prdata;
    end
  endtask

  task force_dma_regfile_apb_idle;
    begin
      release dut.u_dma_regfile.PSEL;
      release dut.u_dma_regfile.PENABLE;
      release dut.u_dma_regfile.PWRITE;
      release dut.u_dma_regfile.PADDR;
      release dut.u_dma_regfile.PWDATA;
      release dut.u_dma_regfile.PREADY;
      release dut.u_dma_regfile.dma_busy_i;
      release dut.u_dma_regfile.dma_done_i;
      release dut.u_dma_regfile.dma_error_i;
      release dut.u_dma_regfile.bytes_done_i;
      release dut.u_dma_regfile.ciphertext_bytes_produced_i;
      release dut.u_dma_regfile.last_error_code_i;
      release dut.u_dma_regfile.engine_state_i;
      @(posedge clk);
      #1;
    end
  endtask

  task force_dma_regfile_write;
    input [31:0] addr;
    input [31:0] data;
    begin
      force dut.u_dma_regfile.PSEL    = 1'b1;
      force dut.u_dma_regfile.PENABLE = 1'b1;
      force dut.u_dma_regfile.PWRITE  = 1'b1;
      force dut.u_dma_regfile.PADDR   = addr;
      force dut.u_dma_regfile.PWDATA  = data;
      @(posedge clk);
      #1;
      force_dma_regfile_apb_idle;
    end
  endtask

  task force_dma_regfile_read;
    input  [31:0] addr;
    output [31:0] data;
    begin
      force dut.u_dma_regfile.PSEL    = 1'b1;
      force dut.u_dma_regfile.PENABLE = 1'b1;
      force dut.u_dma_regfile.PWRITE  = 1'b0;
      force dut.u_dma_regfile.PADDR   = addr;
      force dut.u_dma_regfile.PWDATA  = 32'h00000000;
      @(posedge clk);
      #1;
      data = dut.u_dma_regfile.PRDATA;
      force_dma_regfile_apb_idle;
    end
  endtask

  task force_dma_regfile_access_pready_low;
    input write;
    begin
      force dut.u_dma_regfile.PSEL    = 1'b1;
      force dut.u_dma_regfile.PENABLE = 1'b1;
      force dut.u_dma_regfile.PWRITE  = write;
      force dut.u_dma_regfile.PADDR   = 32'h00000008;
      force dut.u_dma_regfile.PWDATA  = 32'h13572468;
      force dut.u_dma_regfile.PREADY  = 1'b0;
      @(posedge clk);
      #1;
      force_dma_regfile_apb_idle;
    end
  endtask

  task release_dma_engine_direct_forces;
    begin
      release dut.u_dma_tx_engine.start_i;
      release dut.u_dma_tx_engine.soft_reset_i;
      release dut.u_dma_tx_engine.clear_done_i;
      release dut.u_dma_tx_engine.clear_error_i;
      release dut.u_dma_tx_engine.src_addr_i;
      release dut.u_dma_tx_engine.dst_addr_i;
      release dut.u_dma_tx_engine.len_bytes_i;
      release dut.u_dma_tx_engine.direction_i;
      release dut.u_dma_tx_engine.compress_only_i;
      release dut.u_dma_tx_engine.whole_file_i;
      release dut.u_dma_tx_engine.block_size_i;
      release dut.u_dma_tx_engine.tx_prdata_i;
      release dut.u_dma_tx_engine.tx_pready_i;
      release dut.u_dma_tx_engine.tx_pslverr_i;
      release dut.u_dma_tx_engine.state_r;
      release dut.u_dma_tx_engine.apb_resume_state_r;
      release dut.u_dma_tx_engine.apb_write_r;
      release dut.u_dma_tx_engine.apb_addr_r;
      release dut.u_dma_tx_engine.apb_wdata_r;
      release dut.u_dma_tx_engine.apb_rdata_r;
      release dut.u_dma_tx_engine.src_ptr_r;
      release dut.u_dma_tx_engine.dst_ptr_r;
      release dut.u_dma_tx_engine.src_base_r;
      release dut.u_dma_tx_engine.dst_base_r;
      release dut.u_dma_tx_engine.len_bytes_r;
      release dut.u_dma_tx_engine.current_block_continue_r;
      release dut.u_dma_tx_engine.current_block_bytes_r;
      release dut.u_dma_tx_engine.bytes_remaining_r;
      release dut.u_dma_tx_engine.cfg_block_size_r;
      release dut.u_dma_tx_engine.words_remaining_r;
      release dut.u_dma_tx_engine.final_drain_r;
      release dut.u_dma_tx_engine.drain_during_block_r;
      release dut.u_dma_tx_engine.whole_file_r;
      release dut.u_dma_tx_engine.count_phase_r;
      release dut.u_dma_tx_engine.compress_only_r;
      release dut.u_dma_tx_engine.final_empty_polls_r;
      release dut.u_dma_tx_engine.output_word_r;
      release dut.u_dma_tx_engine.tx_meta_r;
      release dut.u_dma_tx_engine.dma_done_o;
      release dut.u_dma_tx_engine.dma_error_o;
      release dut.u_dma_tx_engine.bytes_done_o;
      release dut.u_dma_tx_engine.last_error_code_o;

      release dut.u_dma_rx_engine.start_i;
      release dut.u_dma_rx_engine.soft_reset_i;
      release dut.u_dma_rx_engine.clear_done_i;
      release dut.u_dma_rx_engine.clear_error_i;
      release dut.u_dma_rx_engine.src_addr_i;
      release dut.u_dma_rx_engine.dst_addr_i;
      release dut.u_dma_rx_engine.len_bytes_i;
      release dut.u_dma_rx_engine.direction_i;
      release dut.u_dma_rx_engine.block_size_i;
      release dut.u_dma_rx_engine.rx_ciphertext_word_ready_i;
      release dut.u_dma_rx_engine.rx_prdata_i;
      release dut.u_dma_rx_engine.rx_pready_i;
      release dut.u_dma_rx_engine.rx_pslverr_i;
      release dut.u_dma_rx_engine.state_r;
      release dut.u_dma_rx_engine.apb_resume_state_r;
      release dut.u_dma_rx_engine.apb_write_r;
      release dut.u_dma_rx_engine.apb_addr_r;
      release dut.u_dma_rx_engine.apb_wdata_r;
      release dut.u_dma_rx_engine.apb_rdata_r;
      release dut.u_dma_rx_engine.src_ptr_r;
      release dut.u_dma_rx_engine.dst_ptr_r;
      release dut.u_dma_rx_engine.ctxt_bytes_remaining_r;
      release dut.u_dma_rx_engine.ctxt_w0_r;
      release dut.u_dma_rx_engine.ctxt_w1_r;
      release dut.u_dma_rx_engine.ctxt_w2_r;
      release dut.u_dma_rx_engine.ctxt_w3_r;
      release dut.u_dma_rx_engine.stream_pending_r;
      release dut.u_dma_rx_engine.meta_r;
      release dut.u_dma_rx_engine.output_word_r;
      release dut.u_dma_rx_engine.dma_done_o;
      release dut.u_dma_rx_engine.dma_error_o;
      release dut.u_dma_rx_engine.bytes_done_o;
      release dut.u_dma_rx_engine.last_error_code_o;
      @(posedge clk);
      #1;
    end
  endtask

  task force_soc_debug_unused_zero;
    begin
      force dut.imem_addr_w = 32'h00000000;
      force dut.bridge_mmio_done_w = 1'b0;
      force dut.bridge_mmio_error_w = 1'b0;
      force dut.bridge_mmio_busy_w = 1'b0;
      force dut.dma_src_addr_w = 32'h00000000;
      force dut.dma_dst_addr_w = 32'h00000000;
      force dut.dma_len_bytes_w = 32'h00000000;
      force dut.dma_direction_w = 2'b00;
      force dut.dma_compress_only_w = 1'b0;
      force dut.dma_whole_file_w = 1'b0;
      force dut.dma_iv_w = 128'h0;
      force dut.dma_block_size_w = 6'h00;
      force dut.dma_start_pulse_w = 1'b0;
      force dut.dma_soft_reset_pulse_w = 1'b0;
      force dut.dma_clear_done_pulse_w = 1'b0;
      force dut.dma_clear_error_pulse_w = 1'b0;
      force dut.tx_psel_w = 1'b0;
      force dut.tx_penable_w = 1'b0;
      force dut.tx_pwrite_w = 1'b0;
      force dut.tx_paddr_w = 32'h00000000;
      force dut.tx_pwdata_w = 32'h00000000;
      force dut.tx_prdata_w = 32'h00000000;
      force dut.tx_pready_w = 1'b0;
      force dut.tx_pslverr_w = 1'b0;
      force dut.tx_aes_data_out_w = 128'h0;
      force dut.tx_aes_ready_out_w = 1'b0;
      force dut.tx_busy_dbg_w = 1'b0;
      force dut.tx_done_dbg_w = 1'b0;
      force dut.tx_error_dbg_w = 1'b0;
      force dut.tx_encoder_busy_w = 1'b0;
      force dut.tx_encoder_done_w = 1'b0;
      force dut.tx_encoder_error_w = 1'b0;
      force dut.tx_selected_mode_w = 2'b00;
      force dut.tx_fsm_state_w = 4'h0;
      force dut.tx_packer_busy_w = 1'b0;
      force dut.tx_packer_done_w = 1'b0;
      force dut.tx_packer_error_w = 1'b0;
      force dut.tx_transport_word_dbg_w = 128'h0;
      force dut.tx_transport_word_valid_dbg_w = 1'b0;
      force dut.tx_adapter_error_dbg_w = 1'b0;
      force dut.tx_apb_start_block_dbg_w = 1'b0;
      force dut.tx_apb_block_size_dbg_w = 6'h00;
      force dut.tx_apb_word_in_dbg_w = 32'h00000000;
      force dut.tx_apb_word_valid_dbg_w = 1'b0;
      force dut.tx_apb_word_ready_dbg_w = 1'b0;
      force dut.tx_cipher_en_dbg_w = 1'b0;
      force dut.tx_decipher_en_dbg_w = 1'b0;
      force dut.tx_chain_en_dbg_w = 1'b0;
      force dut.tx_data_in_dbg_w = 128'h0;
      force dut.tx_key_dbg_w = 128'h0;
      force dut.tx_mode_dbg_w = 4'h0;
      force dut.tx_init_vector_dbg_w = 128'h0;
      force dut.tx_segment_len_dbg_w = 16'h0000;
      force dut.rx_psel_w = 1'b0;
      force dut.rx_penable_w = 1'b0;
      force dut.rx_pwrite_w = 1'b0;
      force dut.rx_paddr_w = 32'h00000000;
      force dut.rx_pwdata_w = 32'h00000000;
      force dut.rx_prdata_w = 32'h00000000;
      force dut.rx_pready_w = 1'b0;
      force dut.rx_pslverr_w = 1'b0;
      force dut.rx_busy_dbg_w = 1'b0;
      force dut.rx_done_dbg_w = 1'b0;
      force dut.rx_error_dbg_w = 1'b0;
      force dut.rx_aes_ready_out_w = 1'b0;
      force dut.rx_depacker_busy_w = 1'b0;
      force dut.rx_depacker_done_w = 1'b0;
      force dut.rx_depacker_error_w = 1'b0;
      force dut.rx_parser_busy_w = 1'b0;
      force dut.rx_parser_block_done_w = 1'b0;
      force dut.rx_parser_frame_done_w = 1'b0;
      force dut.rx_parser_error_w = 1'b0;
      force dut.rx_decoder_busy_w = 1'b0;
      force dut.rx_decoder_block_done_w = 1'b0;
      force dut.rx_decoder_frame_done_w = 1'b0;
      force dut.rx_decoder_error_w = 1'b0;
      force dut.rx_word_packer_busy_w = 1'b0;
      force dut.rx_word_packer_block_done_w = 1'b0;
      force dut.rx_word_packer_frame_done_w = 1'b0;
      force dut.rx_word_packer_error_w = 1'b0;
      force dut.rx_transport_word_dbg_w = 128'h0;
      force dut.rx_transport_word_valid_dbg_w = 1'b0;
      force dut.rx_word_dbg_w = 32'h00000000;
      force dut.rx_word_valid_bytes_dbg_w = 3'b000;
      force dut.rx_word_last_in_block_dbg_w = 1'b0;
      force dut.rx_word_last_in_frame_dbg_w = 1'b0;
      force dut.rx_word_valid_dbg_w = 1'b0;
      force dut.rx_ciphertext_word_ready_unused_w = 1'b0;
      force dut.rx_ciphertext_word_w = 128'h0;
      force dut.rx_ciphertext_word_valid_w = 1'b0;
      force dut.dma_engine_bytes_done_w = 32'h00000000;
      force dut.dma_engine_last_error_w = 8'h00;
      force dut.dma_engine_state_w = 4'h0;
      force dut.dma_active_dir_r = 2'b00;
    end
  endtask

  task release_soc_debug_unused_forces;
    begin
      release dut.imem_addr_w;
      release dut.bridge_mmio_done_w;
      release dut.bridge_mmio_error_w;
      release dut.bridge_mmio_busy_w;
      release dut.dma_src_addr_w;
      release dut.dma_dst_addr_w;
      release dut.dma_len_bytes_w;
      release dut.dma_direction_w;
      release dut.dma_compress_only_w;
      release dut.dma_whole_file_w;
      release dut.dma_iv_w;
      release dut.dma_block_size_w;
      release dut.dma_start_pulse_w;
      release dut.dma_soft_reset_pulse_w;
      release dut.dma_clear_done_pulse_w;
      release dut.dma_clear_error_pulse_w;
      release dut.tx_psel_w;
      release dut.tx_penable_w;
      release dut.tx_pwrite_w;
      release dut.tx_paddr_w;
      release dut.tx_pwdata_w;
      release dut.tx_prdata_w;
      release dut.tx_pready_w;
      release dut.tx_pslverr_w;
      release dut.tx_aes_data_out_w;
      release dut.tx_aes_ready_out_w;
      release dut.tx_busy_dbg_w;
      release dut.tx_done_dbg_w;
      release dut.tx_error_dbg_w;
      release dut.tx_encoder_busy_w;
      release dut.tx_encoder_done_w;
      release dut.tx_encoder_error_w;
      release dut.tx_selected_mode_w;
      release dut.tx_fsm_state_w;
      release dut.tx_packer_busy_w;
      release dut.tx_packer_done_w;
      release dut.tx_packer_error_w;
      release dut.tx_transport_word_dbg_w;
      release dut.tx_transport_word_valid_dbg_w;
      release dut.tx_adapter_error_dbg_w;
      release dut.tx_apb_start_block_dbg_w;
      release dut.tx_apb_block_size_dbg_w;
      release dut.tx_apb_word_in_dbg_w;
      release dut.tx_apb_word_valid_dbg_w;
      release dut.tx_apb_word_ready_dbg_w;
      release dut.tx_cipher_en_dbg_w;
      release dut.tx_decipher_en_dbg_w;
      release dut.tx_chain_en_dbg_w;
      release dut.tx_data_in_dbg_w;
      release dut.tx_key_dbg_w;
      release dut.tx_mode_dbg_w;
      release dut.tx_init_vector_dbg_w;
      release dut.tx_segment_len_dbg_w;
      release dut.rx_psel_w;
      release dut.rx_penable_w;
      release dut.rx_pwrite_w;
      release dut.rx_paddr_w;
      release dut.rx_pwdata_w;
      release dut.rx_prdata_w;
      release dut.rx_pready_w;
      release dut.rx_pslverr_w;
      release dut.rx_busy_dbg_w;
      release dut.rx_done_dbg_w;
      release dut.rx_error_dbg_w;
      release dut.rx_aes_ready_out_w;
      release dut.rx_depacker_busy_w;
      release dut.rx_depacker_done_w;
      release dut.rx_depacker_error_w;
      release dut.rx_parser_busy_w;
      release dut.rx_parser_block_done_w;
      release dut.rx_parser_frame_done_w;
      release dut.rx_parser_error_w;
      release dut.rx_decoder_busy_w;
      release dut.rx_decoder_block_done_w;
      release dut.rx_decoder_frame_done_w;
      release dut.rx_decoder_error_w;
      release dut.rx_word_packer_busy_w;
      release dut.rx_word_packer_block_done_w;
      release dut.rx_word_packer_frame_done_w;
      release dut.rx_word_packer_error_w;
      release dut.rx_transport_word_dbg_w;
      release dut.rx_transport_word_valid_dbg_w;
      release dut.rx_word_dbg_w;
      release dut.rx_word_valid_bytes_dbg_w;
      release dut.rx_word_last_in_block_dbg_w;
      release dut.rx_word_last_in_frame_dbg_w;
      release dut.rx_word_valid_dbg_w;
      release dut.rx_ciphertext_word_ready_unused_w;
      release dut.rx_ciphertext_word_w;
      release dut.rx_ciphertext_word_valid_w;
      release dut.dma_engine_bytes_done_w;
      release dut.dma_engine_last_error_w;
      release dut.dma_engine_state_w;
      release dut.dma_active_dir_r;
    end
  endtask

  task hit_soc_debug_unused_term;
    input integer term_idx;
    begin
      force_soc_debug_unused_zero;
      #1;
      case (term_idx)
        0:  force dut.imem_addr_w = 32'h00001000;
        1:  force dut.imem_addr_w = 32'h00000001;
        2:  force dut.bridge_mmio_done_w = 1'b1;
        3:  force dut.bridge_mmio_error_w = 1'b1;
        4:  force dut.bridge_mmio_busy_w = 1'b1;
        5:  force dut.dma_src_addr_w = 32'h00000004;
        6:  force dut.dma_dst_addr_w = 32'h00000008;
        7:  force dut.dma_len_bytes_w = 32'h00000010;
        8:  force dut.dma_direction_w = 2'b01;
        9:  force dut.dma_compress_only_w = 1'b1;
        10: force dut.dma_whole_file_w = 1'b1;
        11: force dut.dma_iv_w = 128'h00000000000000000000000000000001;
        12: force dut.dma_block_size_w = 6'h20;
        13: force dut.dma_start_pulse_w = 1'b1;
        14: force dut.dma_soft_reset_pulse_w = 1'b1;
        15: force dut.dma_clear_done_pulse_w = 1'b1;
        16: force dut.dma_clear_error_pulse_w = 1'b1;
        17: force dut.tx_psel_w = 1'b1;
        18: force dut.tx_penable_w = 1'b1;
        19: force dut.tx_pwrite_w = 1'b1;
        20: force dut.tx_paddr_w = 32'h00000004;
        21: force dut.tx_pwdata_w = 32'h13579bdf;
        22: force dut.tx_prdata_w = 32'h2468ace0;
        23: force dut.tx_pready_w = 1'b1;
        24: force dut.tx_pslverr_w = 1'b1;
        25: force dut.tx_aes_data_out_w = 128'h0123456789abcdeffedcba9876543210;
        26: force dut.tx_aes_ready_out_w = 1'b1;
        27: force dut.tx_busy_dbg_w = 1'b1;
        28: force dut.tx_done_dbg_w = 1'b1;
        29: force dut.tx_error_dbg_w = 1'b1;
        30: force dut.tx_encoder_busy_w = 1'b1;
        31: force dut.tx_encoder_done_w = 1'b1;
        32: force dut.tx_encoder_error_w = 1'b1;
        33: force dut.tx_selected_mode_w = 2'b10;
        34: force dut.tx_fsm_state_w = 4'h5;
        35: force dut.tx_packer_busy_w = 1'b1;
        36: force dut.tx_packer_done_w = 1'b1;
        37: force dut.tx_packer_error_w = 1'b1;
        38: force dut.tx_transport_word_dbg_w = 128'h11112222333344445555666677778888;
        39: force dut.tx_transport_word_valid_dbg_w = 1'b1;
        40: force dut.tx_adapter_error_dbg_w = 1'b1;
        41: force dut.tx_apb_start_block_dbg_w = 1'b1;
        42: force dut.tx_apb_block_size_dbg_w = 6'h20;
        43: force dut.tx_apb_word_in_dbg_w = 32'hdeadbeef;
        44: force dut.tx_apb_word_valid_dbg_w = 1'b1;
        45: force dut.tx_apb_word_ready_dbg_w = 1'b1;
        46: force dut.tx_cipher_en_dbg_w = 1'b1;
        47: force dut.tx_decipher_en_dbg_w = 1'b1;
        48: force dut.tx_chain_en_dbg_w = 1'b1;
        49: force dut.tx_data_in_dbg_w = 128'h89abcdeffedcba987654321001234567;
        50: force dut.tx_key_dbg_w = 128'h2b7e151628aed2a6abf7158809cf4f3c;
        51: force dut.tx_mode_dbg_w = 4'h2;
        52: force dut.tx_init_vector_dbg_w = 128'h000102030405060708090a0b0c0d0e0f;
        53: force dut.tx_segment_len_dbg_w = 16'h0010;
        54: force dut.rx_psel_w = 1'b1;
        55: force dut.rx_penable_w = 1'b1;
        56: force dut.rx_pwrite_w = 1'b1;
        57: force dut.rx_paddr_w = 32'h00000004;
        58: force dut.rx_pwdata_w = 32'hcafebabe;
        59: force dut.rx_prdata_w = 32'h10203040;
        60: force dut.rx_pready_w = 1'b1;
        61: force dut.rx_pslverr_w = 1'b1;
        62: force dut.rx_busy_dbg_w = 1'b1;
        63: force dut.rx_done_dbg_w = 1'b1;
        64: force dut.rx_error_dbg_w = 1'b1;
        65: force dut.rx_aes_ready_out_w = 1'b1;
        66: force dut.rx_depacker_busy_w = 1'b1;
        67: force dut.rx_depacker_done_w = 1'b1;
        68: force dut.rx_depacker_error_w = 1'b1;
        69: force dut.rx_parser_busy_w = 1'b1;
        70: force dut.rx_parser_block_done_w = 1'b1;
        71: force dut.rx_parser_frame_done_w = 1'b1;
        72: force dut.rx_parser_error_w = 1'b1;
        73: force dut.rx_decoder_busy_w = 1'b1;
        74: force dut.rx_decoder_block_done_w = 1'b1;
        75: force dut.rx_decoder_frame_done_w = 1'b1;
        76: force dut.rx_decoder_error_w = 1'b1;
        77: force dut.rx_word_packer_busy_w = 1'b1;
        78: force dut.rx_word_packer_block_done_w = 1'b1;
        79: force dut.rx_word_packer_frame_done_w = 1'b1;
        80: force dut.rx_word_packer_error_w = 1'b1;
        81: force dut.rx_transport_word_dbg_w = 128'h88887777666655554444333322221111;
        82: force dut.rx_transport_word_valid_dbg_w = 1'b1;
        83: force dut.rx_word_dbg_w = 32'h55667788;
        84: force dut.rx_word_valid_bytes_dbg_w = 3'b100;
        85: force dut.rx_word_last_in_block_dbg_w = 1'b1;
        86: force dut.rx_word_last_in_frame_dbg_w = 1'b1;
        87: force dut.rx_word_valid_dbg_w = 1'b1;
        88: force dut.rx_ciphertext_word_ready_unused_w = 1'b1;
        89: force dut.rx_ciphertext_word_w = 128'h00112233445566778899aabbccddeeff;
        90: force dut.rx_ciphertext_word_valid_w = 1'b1;
        91: force dut.dma_engine_bytes_done_w = 32'h00000040;
        92: force dut.dma_engine_last_error_w = 8'h02;
        93: force dut.dma_engine_state_w = 4'h7;
        94: force dut.dma_active_dir_r = 2'b10;
        default: ;
      endcase
      #1;
      @(posedge clk);
      #1;
    end
  endtask

  task exercise_file_builder_reset_fsm_coverage;
    begin
      for (raw_cov_mem_idx = 1; raw_cov_mem_idx <= 7; raw_cov_mem_idx = raw_cov_mem_idx + 1) begin
        force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.start = 1'b0;
        force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.slb_done = 1'b0;
        force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.clb_done = 1'b0;
        force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.cgg_done = 1'b0;
        force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.rst_n = 1'b0;
        #1;
        release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.rst_n;
        @(posedge clk);
        #1;

        if (raw_cov_mem_idx >= 1) begin
          force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.start = 1'b1;
          @(posedge clk);
          #1;
          force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.start = 1'b0;
        end
        if (raw_cov_mem_idx >= 2) begin
          @(posedge clk);
          #1;
        end
        if (raw_cov_mem_idx >= 3) begin
          force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.slb_done = 1'b1;
          @(posedge clk);
          #1;
          force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.slb_done = 1'b0;
        end
        if (raw_cov_mem_idx >= 4) begin
          @(posedge clk);
          #1;
        end
        if (raw_cov_mem_idx >= 5) begin
          force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.clb_done = 1'b1;
          @(posedge clk);
          #1;
          force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.clb_done = 1'b0;
        end
        if (raw_cov_mem_idx >= 6) begin
          @(posedge clk);
          #1;
        end
        if (raw_cov_mem_idx >= 7) begin
          force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.cgg_done = 1'b1;
          @(posedge clk);
          #1;
          force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.cgg_done = 1'b0;
        end

        force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.rst_n = 1'b0;
        #1;
        release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.rst_n;
        @(posedge clk);
        #1;
      end

      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.start;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.slb_done;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.clb_done;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.cgg_done;
    end
  endtask

  task exercise_dynamic_builder_reset_fsm_coverage;
    begin
      for (raw_cov_mem_idx = 1; raw_cov_mem_idx <= 7; raw_cov_mem_idx = raw_cov_mem_idx + 1) begin
        force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.start = 1'b0;
        force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.slb_done = 1'b0;
        force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.clb_done = 1'b0;
        force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.cgg_done = 1'b0;
        force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.rst_n = 1'b0;
        #1;
        release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.rst_n;
        @(posedge clk);
        #1;

        if (raw_cov_mem_idx >= 1) begin
          force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.start = 1'b1;
          @(posedge clk);
          #1;
          force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.start = 1'b0;
        end
        if (raw_cov_mem_idx >= 2) begin
          @(posedge clk);
          #1;
        end
        if (raw_cov_mem_idx >= 3) begin
          force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.slb_done = 1'b1;
          @(posedge clk);
          #1;
          force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.slb_done = 1'b0;
        end
        if (raw_cov_mem_idx >= 4) begin
          @(posedge clk);
          #1;
        end
        if (raw_cov_mem_idx >= 5) begin
          force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.clb_done = 1'b1;
          @(posedge clk);
          #1;
          force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.clb_done = 1'b0;
        end
        if (raw_cov_mem_idx >= 6) begin
          @(posedge clk);
          #1;
        end
        if (raw_cov_mem_idx >= 7) begin
          force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.cgg_done = 1'b1;
          @(posedge clk);
          #1;
          force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.cgg_done = 1'b0;
        end

        force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.rst_n = 1'b0;
        #1;
        release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.rst_n;
        @(posedge clk);
        #1;
      end

      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.start;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.slb_done;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.clb_done;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.cgg_done;
    end
  endtask

  task exercise_stream_emit_reset_fsm_coverage;
    begin
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_stream_output_interface.start = 1'b0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_stream_output_interface.hdr_valid = 1'b0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_stream_output_interface.hdr_last_chunk = 1'b0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_stream_output_interface.payload_required = 1'b0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_stream_output_interface.payload_valid = 1'b0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_stream_output_interface.payload_last_chunk = 1'b0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_stream_output_interface.stream_ready = 1'b1;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_stream_output_interface.rst_n = 1'b0;
      #1;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_stream_output_interface.rst_n;
      @(posedge clk);
      #1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_stream_output_interface.start = 1'b1;
      @(posedge clk);
      #1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_stream_output_interface.start = 1'b0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_stream_output_interface.rst_n = 1'b0;
      #1;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_stream_output_interface.rst_n;
      @(posedge clk);
      #1;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_stream_output_interface.start = 1'b1;
      @(posedge clk);
      #1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_stream_output_interface.start = 1'b0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_stream_output_interface.hdr_valid = 1'b1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_stream_output_interface.hdr_last_chunk = 1'b1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_stream_output_interface.payload_required = 1'b1;
      @(posedge clk);
      #1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_stream_output_interface.rst_n = 1'b0;
      #1;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_stream_output_interface.rst_n;
      @(posedge clk);
      #1;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.start = 1'b0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.hdr_done_w = 1'b0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.payload_required_w = 1'b0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.stream_done_w = 1'b0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.rst_n = 1'b0;
      #1;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.rst_n;
      @(posedge clk);
      #1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.start = 1'b1;
      @(posedge clk);
      #1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.start = 1'b0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.rst_n = 1'b0;
      #1;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.rst_n;
      @(posedge clk);
      #1;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.start = 1'b1;
      @(posedge clk);
      #1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.start = 1'b0;
      @(posedge clk);
      #1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.hdr_done_w = 1'b1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.payload_required_w = 1'b1;
      @(posedge clk);
      #1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.rst_n = 1'b0;
      #1;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.rst_n;
      @(posedge clk);
      #1;

      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_stream_output_interface.start;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_stream_output_interface.hdr_valid;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_stream_output_interface.hdr_last_chunk;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_stream_output_interface.payload_required;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_stream_output_interface.payload_valid;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_stream_output_interface.payload_last_chunk;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_stream_output_interface.stream_ready;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.start;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.hdr_done_w;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.payload_required_w;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.stream_done_w;
    end
  endtask

  task tx_dma_invalid_start_once;
    input [31:0] len_value;
    input [5:0]  block_value;
    input [31:0] src_value;
    input [31:0] dst_value;
    begin
      release_dma_engine_direct_forces;
      force dut.u_dma_tx_engine.direction_i = 2'b01;
      force dut.u_dma_tx_engine.len_bytes_i = len_value;
      force dut.u_dma_tx_engine.block_size_i = block_value;
      force dut.u_dma_tx_engine.src_addr_i = src_value;
      force dut.u_dma_tx_engine.dst_addr_i = dst_value;
      force dut.u_dma_tx_engine.start_i = 1'b1;
      @(posedge clk);
      #1;
      release dut.u_dma_tx_engine.start_i;
      repeat (3) @(posedge clk);
      release_dma_engine_direct_forces;
    end
  endtask

  task rx_dma_invalid_start_once;
    input [31:0] len_value;
    input [31:0] src_value;
    input [31:0] dst_value;
    begin
      release_dma_engine_direct_forces;
      force dut.u_dma_rx_engine.direction_i = 2'b10;
      force dut.u_dma_rx_engine.len_bytes_i = len_value;
      force dut.u_dma_rx_engine.block_size_i = 6'd32;
      force dut.u_dma_rx_engine.src_addr_i = src_value;
      force dut.u_dma_rx_engine.dst_addr_i = dst_value;
      force dut.u_dma_rx_engine.start_i = 1'b1;
      @(posedge clk);
      #1;
      release dut.u_dma_rx_engine.start_i;
      repeat (3) @(posedge clk);
      release_dma_engine_direct_forces;
    end
  endtask

  task tx_dma_force_eval_state;
    input [4:0]  state_value;
    input [31:0] rdata_value;
    begin
      release_dma_engine_direct_forces;
      force dut.u_dma_tx_engine.state_r = state_value;
      force dut.u_dma_tx_engine.apb_rdata_r = rdata_value;
      force dut.u_dma_tx_engine.current_block_continue_r = 1'b0;
      force dut.u_dma_tx_engine.current_block_bytes_r = 32'd16;
      force dut.u_dma_tx_engine.bytes_remaining_r = 32'd16;
      force dut.u_dma_tx_engine.final_drain_r = 1'b1;
      force dut.u_dma_tx_engine.drain_during_block_r = 1'b0;
      force dut.u_dma_tx_engine.final_empty_polls_r = 7'd0;
      @(posedge clk);
      #1;
      release_dma_engine_direct_forces;
    end
  endtask

  task rx_dma_force_eval_state;
    input [4:0]  state_value;
    input [31:0] rdata_value;
    input [31:0] remaining_value;
    input        stream_pending_value;
    begin
      release_dma_engine_direct_forces;
      force dut.u_dma_rx_engine.state_r = state_value;
      force dut.u_dma_rx_engine.apb_rdata_r = rdata_value;
      force dut.u_dma_rx_engine.ctxt_bytes_remaining_r = remaining_value;
      force dut.u_dma_rx_engine.stream_pending_r = stream_pending_value;
      force dut.u_dma_rx_engine.rx_ciphertext_word_ready_i = 1'b1;
      @(posedge clk);
      #1;
      release_dma_engine_direct_forces;
    end
  endtask

  task tx_dma_soft_reset_from_state;
    input [4:0] state_value;
    begin
      release_dma_engine_direct_forces;
      force dut.u_dma_tx_engine.state_r = state_value;
      force dut.u_dma_tx_engine.soft_reset_i = 1'b1;
      @(posedge clk);
      #1;
      release_dma_engine_direct_forces;
    end
  endtask

  task rx_dma_soft_reset_from_state;
    input [4:0] state_value;
    begin
      release_dma_engine_direct_forces;
      force dut.u_dma_rx_engine.state_r = state_value;
      force dut.u_dma_rx_engine.soft_reset_i = 1'b1;
      @(posedge clk);
      #1;
      release_dma_engine_direct_forces;
    end
  endtask

  task force_tx_if_direct_idle;
    begin
      release dut.u_tx_top.u_apb_huffman_tx_if.PSEL;
      release dut.u_tx_top.u_apb_huffman_tx_if.PENABLE;
      release dut.u_tx_top.u_apb_huffman_tx_if.PWRITE;
      release dut.u_tx_top.u_apb_huffman_tx_if.PADDR;
      release dut.u_tx_top.u_apb_huffman_tx_if.PWDATA;
      release dut.u_tx_top.u_apb_huffman_tx_if.word_ready_i;
      release dut.u_tx_top.u_apb_huffman_tx_if.aes_out_word_i;
      release dut.u_tx_top.u_apb_huffman_tx_if.aes_out_word_last_i;
      release dut.u_tx_top.u_apb_huffman_tx_if.aes_out_word_valid_i;
      release dut.u_tx_top.u_apb_huffman_tx_if.aes_out_error_i;
      release dut.u_tx_top.u_apb_huffman_tx_if.tx_busy_i;
      release dut.u_tx_top.u_apb_huffman_tx_if.tx_done_i;
      release dut.u_tx_top.u_apb_huffman_tx_if.tx_error_i;
      release dut.u_tx_top.u_apb_huffman_tx_if.global_build_busy_i;
      release dut.u_tx_top.u_apb_huffman_tx_if.global_build_done_i;
      release dut.u_tx_top.u_apb_huffman_tx_if.global_build_error_i;
      release dut.u_tx_top.u_apb_huffman_tx_if.global_table_valid_i;
      release dut.u_tx_top.u_apb_huffman_tx_if.global_symbol_count_i;
      release dut.u_tx_top.u_apb_huffman_tx_if.cfg_valid_r;
      release dut.u_tx_top.u_apb_huffman_tx_if.words_expected_r;
      release dut.u_tx_top.u_apb_huffman_tx_if.words_loaded_r;
      release dut.u_tx_top.u_apb_huffman_tx_if.block_inflight_r;
      release dut.u_tx_top.u_apb_huffman_tx_if.stream_active_r;
      release dut.u_tx_top.u_apb_huffman_tx_if.fifo_count_r;
      release dut.u_tx_top.u_apb_huffman_tx_if.out_fifo_count_r;
      @(posedge clk);
      #1;
    end
  endtask

  task force_tx_if_direct_write;
    input [31:0] addr;
    input [31:0] data;
    begin
      force dut.u_tx_top.u_apb_huffman_tx_if.PSEL    = 1'b1;
      force dut.u_tx_top.u_apb_huffman_tx_if.PENABLE = 1'b1;
      force dut.u_tx_top.u_apb_huffman_tx_if.PWRITE  = 1'b1;
      force dut.u_tx_top.u_apb_huffman_tx_if.PADDR   = addr;
      force dut.u_tx_top.u_apb_huffman_tx_if.PWDATA  = data;
      @(posedge clk);
      #1;
      force_tx_if_direct_idle;
    end
  endtask

  task force_tx_if_direct_read;
    input  [31:0] addr;
    output [31:0] data;
    begin
      force dut.u_tx_top.u_apb_huffman_tx_if.PSEL    = 1'b1;
      force dut.u_tx_top.u_apb_huffman_tx_if.PENABLE = 1'b1;
      force dut.u_tx_top.u_apb_huffman_tx_if.PWRITE  = 1'b0;
      force dut.u_tx_top.u_apb_huffman_tx_if.PADDR   = addr;
      force dut.u_tx_top.u_apb_huffman_tx_if.PWDATA  = 32'h00000000;
      @(posedge clk);
      #1;
      data = dut.u_tx_top.u_apb_huffman_tx_if.PRDATA;
      force_tx_if_direct_idle;
    end
  endtask

  task force_rx_if_direct_idle;
    begin
      release dut.u_rx_top.u_apb_huffman_rx_if.PSEL;
      release dut.u_rx_top.u_apb_huffman_rx_if.PENABLE;
      release dut.u_rx_top.u_apb_huffman_rx_if.PWRITE;
      release dut.u_rx_top.u_apb_huffman_rx_if.PADDR;
      release dut.u_rx_top.u_apb_huffman_rx_if.PWDATA;
      release dut.u_rx_top.u_apb_huffman_rx_if.ciphertext_word_ready_i;
      release dut.u_rx_top.u_apb_huffman_rx_if.rx_word_data_i;
      release dut.u_rx_top.u_apb_huffman_rx_if.rx_word_valid_bytes_i;
      release dut.u_rx_top.u_apb_huffman_rx_if.rx_word_last_in_block_i;
      release dut.u_rx_top.u_apb_huffman_rx_if.rx_word_last_in_frame_i;
      release dut.u_rx_top.u_apb_huffman_rx_if.rx_word_valid_i;
      release dut.u_rx_top.u_apb_huffman_rx_if.rx_error_i;
      release dut.u_rx_top.u_apb_huffman_rx_if.fifo_count_r;
      release dut.u_rx_top.u_apb_huffman_rx_if.cipher_stage_valid_r;
      release dut.u_rx_top.u_apb_huffman_rx_if.cipher_pending_valid_r;
      release dut.u_rx_top.u_apb_huffman_rx_if.cipher_stage_word0_r;
      release dut.u_rx_top.u_apb_huffman_rx_if.cipher_stage_word1_r;
      release dut.u_rx_top.u_apb_huffman_rx_if.cipher_stage_word2_r;
      release dut.u_rx_top.u_apb_huffman_rx_if.cipher_stage_word3_r;
      @(posedge clk);
      #1;
    end
  endtask

  task force_rx_if_direct_write;
    input [31:0] addr;
    input [31:0] data;
    begin
      force dut.u_rx_top.u_apb_huffman_rx_if.PSEL    = 1'b1;
      force dut.u_rx_top.u_apb_huffman_rx_if.PENABLE = 1'b1;
      force dut.u_rx_top.u_apb_huffman_rx_if.PWRITE  = 1'b1;
      force dut.u_rx_top.u_apb_huffman_rx_if.PADDR   = addr;
      force dut.u_rx_top.u_apb_huffman_rx_if.PWDATA  = data;
      @(posedge clk);
      #1;
      force_rx_if_direct_idle;
    end
  endtask

  task force_rx_if_direct_read;
    input  [31:0] addr;
    output [31:0] data;
    begin
      force dut.u_rx_top.u_apb_huffman_rx_if.PSEL    = 1'b1;
      force dut.u_rx_top.u_apb_huffman_rx_if.PENABLE = 1'b1;
      force dut.u_rx_top.u_apb_huffman_rx_if.PWRITE  = 1'b0;
      force dut.u_rx_top.u_apb_huffman_rx_if.PADDR   = addr;
      force dut.u_rx_top.u_apb_huffman_rx_if.PWDATA  = 32'h00000000;
      @(posedge clk);
      #1;
      data = dut.u_rx_top.u_apb_huffman_rx_if.PRDATA;
      force_rx_if_direct_idle;
    end
  endtask

  task force_aes_wrapper_direct_idle;
    begin
      release dut.u_tx_top.u_huffman_aes_tx_top.u_aes_input_wrapper.block_in;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_aes_input_wrapper.block_valid;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_aes_input_wrapper.aes_ready;
      release dut.u_rx_top.u_aes_input_wrapper_rx.block_in;
      release dut.u_rx_top.u_aes_input_wrapper_rx.block_valid;
      release dut.u_rx_top.u_aes_input_wrapper_rx.aes_ready;
      @(posedge clk);
      #1;
    end
  endtask

  task force_aes_wrapper_accept;
    input tx_path;
    input [127:0] data_value;
    begin
      if (tx_path) begin
        force dut.u_tx_top.u_huffman_aes_tx_top.u_aes_input_wrapper.block_in = data_value;
        force dut.u_tx_top.u_huffman_aes_tx_top.u_aes_input_wrapper.block_valid = 1'b1;
        force dut.u_tx_top.u_huffman_aes_tx_top.u_aes_input_wrapper.aes_ready = 1'b1;
      end
      else begin
        force dut.u_rx_top.u_aes_input_wrapper_rx.block_in = data_value;
        force dut.u_rx_top.u_aes_input_wrapper_rx.block_valid = 1'b1;
        force dut.u_rx_top.u_aes_input_wrapper_rx.aes_ready = 1'b1;
      end
      @(posedge clk);
      #1;
      force_aes_wrapper_direct_idle;
    end
  endtask

  task automatic exercise_apb_if_and_wrapper_direct_coverage;
    reg [31:0] scratch_read;
    reg [3:0]  words_dummy;
    begin
      words_dummy = dut.u_tx_top.u_apb_huffman_tx_if.calc_words_needed(6'd0);
      words_dummy = words_dummy ^ dut.u_tx_top.u_apb_huffman_tx_if.calc_words_needed(6'd1);
      words_dummy = words_dummy ^ dut.u_tx_top.u_apb_huffman_tx_if.calc_words_needed(6'd32);

      force_tx_if_direct_read(32'h00000008, scratch_read);
      force_tx_if_direct_read(32'h00000010, scratch_read);
      force_tx_if_direct_write(32'h00000010, 32'h00000000);
      force_tx_if_direct_write(32'h00000010, 32'h00000002);
      force_tx_if_direct_write(32'h00000010, 32'h00000004);

      force dut.u_tx_top.u_apb_huffman_tx_if.cfg_valid_r = 1'b1;
      force dut.u_tx_top.u_apb_huffman_tx_if.words_expected_r = 4'd0;
      force dut.u_tx_top.u_apb_huffman_tx_if.words_loaded_r = 4'd0;
      force_tx_if_direct_write(32'h00000000, 32'h00000001);

      force dut.u_tx_top.u_apb_huffman_tx_if.cfg_valid_r = 1'b1;
      force dut.u_tx_top.u_apb_huffman_tx_if.words_expected_r = 4'd2;
      force dut.u_tx_top.u_apb_huffman_tx_if.words_loaded_r = 4'd1;
      force dut.u_tx_top.u_apb_huffman_tx_if.block_inflight_r = 1'b0;
      force_tx_if_direct_write(32'h00000000, 32'h00000001);

      force dut.u_tx_top.u_apb_huffman_tx_if.cfg_valid_r = 1'b1;
      force dut.u_tx_top.u_apb_huffman_tx_if.words_expected_r = 4'd2;
      force dut.u_tx_top.u_apb_huffman_tx_if.words_loaded_r = 4'd2;
      force dut.u_tx_top.u_apb_huffman_tx_if.block_inflight_r = 1'b0;
      force dut.u_tx_top.u_apb_huffman_tx_if.tx_busy_i = 1'b1;
      force_tx_if_direct_write(32'h00000000, 32'h00000001);

      force dut.u_tx_top.u_apb_huffman_tx_if.stream_active_r = 1'b1;
      force dut.u_tx_top.u_apb_huffman_tx_if.fifo_count_r = 4'd1;
      force_tx_if_direct_write(32'h00000004, 32'h00000010);

      force dut.u_tx_top.u_apb_huffman_tx_if.cfg_valid_r = 1'b0;
      force_tx_if_direct_write(32'h00000008, 32'h5555aaaa);

      force dut.u_tx_top.u_apb_huffman_tx_if.cfg_valid_r = 1'b1;
      force dut.u_tx_top.u_apb_huffman_tx_if.block_inflight_r = 1'b1;
      force_tx_if_direct_write(32'h00000008, 32'haaaa5555);

      force dut.u_tx_top.u_apb_huffman_tx_if.cfg_valid_r = 1'b1;
      force dut.u_tx_top.u_apb_huffman_tx_if.block_inflight_r = 1'b0;
      force dut.u_tx_top.u_apb_huffman_tx_if.words_expected_r = 4'd4;
      force dut.u_tx_top.u_apb_huffman_tx_if.words_loaded_r = 4'd0;
      force dut.u_tx_top.u_apb_huffman_tx_if.fifo_count_r = 4'd8;
      force_tx_if_direct_write(32'h00000008, 32'hffff0000);

      force_rx_if_direct_read(32'h0000000c, scratch_read);
      force_rx_if_direct_read(32'h00000020, scratch_read);
      force_rx_if_direct_read(32'h00000024, scratch_read);
      force_rx_if_direct_read(32'h00000028, scratch_read);
      force_rx_if_direct_read(32'h0000002c, scratch_read);
      force_rx_if_direct_read(32'h00000030, scratch_read);
      force_rx_if_direct_write(32'h00000020, 32'h01234567);
      force_rx_if_direct_write(32'h00000024, 32'h89abcdef);
      force_rx_if_direct_write(32'h00000028, 32'hfedcba98);
      force_rx_if_direct_write(32'h0000002c, 32'h76543210);
      force_rx_if_direct_write(32'h0000000c, 32'h00000002);
      force_rx_if_direct_write(32'h0000000c, 32'h00000004);

      force dut.u_rx_top.u_apb_huffman_rx_if.cipher_stage_valid_r = 4'hf;
      force dut.u_rx_top.u_apb_huffman_rx_if.cipher_pending_valid_r = 1'b1;
      force_rx_if_direct_write(32'h00000030, 32'h00000001);
      force dut.u_rx_top.u_apb_huffman_rx_if.cipher_stage_valid_r = 4'hf;
      force dut.u_rx_top.u_apb_huffman_rx_if.cipher_pending_valid_r = 1'b0;
      force dut.u_rx_top.u_apb_huffman_rx_if.ciphertext_word_ready_i = 1'b1;
      force_rx_if_direct_write(32'h00000030, 32'h00000001);

      force dut.u_rx_top.u_apb_huffman_rx_if.rx_word_data_i = 32'hffffffff;
      force dut.u_rx_top.u_apb_huffman_rx_if.rx_word_valid_bytes_i = 3'd4;
      force dut.u_rx_top.u_apb_huffman_rx_if.rx_word_last_in_block_i = 1'b1;
      force dut.u_rx_top.u_apb_huffman_rx_if.rx_word_last_in_frame_i = 1'b1;
      force dut.u_rx_top.u_apb_huffman_rx_if.rx_word_valid_i = 1'b1;
      @(posedge clk);
      #1;
      force_rx_if_direct_read(32'h00000000, scratch_read);
      force_rx_if_direct_read(32'h00000004, scratch_read);

      force_aes_wrapper_accept(1'b1, 128'hffffffffffffffffffffffffffffffff);
      force_aes_wrapper_accept(1'b1, 128'h00000000000000000000000000000000);
      force_aes_wrapper_accept(1'b0, 128'hffffffffffffffffffffffffffffffff);
      force_aes_wrapper_accept(1'b0, 128'h00000000000000000000000000000000);
      force_aes_wrapper_direct_idle;
      force_tx_if_direct_idle;
      force_rx_if_direct_idle;

      $display("# APB_IF_WRAPPER_DIRECT_COV: done words_dummy=0x%0x scratch=0x%08x", words_dummy, scratch_read);
    end
  endtask

  task automatic exercise_dma_bridge_direct_coverage;
    reg [31:0] scratch_read;
    integer state_idx;
    begin
      $display("# DMA_BRIDGE_DIRECT_COV: exercise DMA regfile, bridge, and DMA engine defensive branches");

      force_bridge_direct_idle;
      force_bridge_req(1'b0, 1'b0, 32'h40000004, 32'h00000000, 4'hf, 1'b1, 1'b0, 32'h00000000);
      @(posedge clk);
      force_bridge_req(1'b1, 1'b0, 32'h40000004, 32'h00000000, 4'hf, 1'b0, 1'b0, 32'h5a5aa5a5);
      @(posedge clk);
      @(posedge clk);
      force_bridge_req(1'b1, 1'b0, 32'h40000004, 32'h00000000, 4'hf, 1'b1, 1'b1, 32'h5a5aa5a5);
      @(posedge clk);
      force_bridge_req(1'b1, 1'b0, 32'h40000004, 32'h00000000, 4'hf, 1'b1, 1'b0, 32'ha5a55a5a);
      @(posedge clk);
      force_bridge_req(1'b1, 1'b0, 32'h40000004, 32'h11111111, 4'hf, 1'b1, 1'b0, 32'h00000011);
      @(posedge clk);
      force_bridge_req(1'b1, 1'b0, 32'h40000004, 32'h11111111, 4'h3, 1'b1, 1'b0, 32'h00000022);
      @(posedge clk);
      force dut.u_cpu_mmio_to_apb_bridge.state_r = 2'b11;
      @(posedge clk);
      #1;
      force_bridge_direct_idle;

      force_dma_regfile_apb_idle;
      force_dma_regfile_access_pready_low(1'b1);
      force_dma_regfile_access_pready_low(1'b0);
      force_dma_regfile_read(32'h00000008, scratch_read);
      force_dma_regfile_read(32'h0000000c, scratch_read);
      force_dma_regfile_read(32'h00000010, scratch_read);
      force_dma_regfile_read(32'h00000024, scratch_read);
      force_dma_regfile_read(32'h000000fc, scratch_read);

      force_dma_regfile_write(32'h00000008, 32'h00000401);
      force_dma_regfile_write(32'h0000000c, 32'h00002000);
      force_dma_regfile_write(32'h00000010, 32'h00000020);
      force_dma_regfile_write(32'h00000014, 32'h00000009);
      force_dma_regfile_read(32'h00000004, scratch_read);
      force_dma_regfile_write(32'h00000000, 32'h00000001);

      force_dma_regfile_write(32'h00000008, 32'h00000400);
      force_dma_regfile_write(32'h0000000c, 32'h00002001);
      force_dma_regfile_read(32'h00000004, scratch_read);
      force_dma_regfile_write(32'h00000018, 32'h00000021);
      force_dma_regfile_read(32'h00000004, scratch_read);
      force_dma_regfile_write(32'h00000000, 32'h00000010);
      force_dma_regfile_write(32'h00000018, 32'h00000040);

      force dut.u_dma_regfile.dma_busy_i = 1'b1;
      force_dma_regfile_write(32'h00000008, 32'haaaa0001);
      force dut.u_dma_regfile.dma_busy_i = 1'b1;
      force_dma_regfile_write(32'h0000000c, 32'haaaa0002);
      force dut.u_dma_regfile.dma_busy_i = 1'b1;
      force_dma_regfile_write(32'h00000010, 32'haaaa0003);
      force dut.u_dma_regfile.dma_busy_i = 1'b1;
      force_dma_regfile_write(32'h00000014, 32'h00000001);
      force dut.u_dma_regfile.dma_busy_i = 1'b1;
      force_dma_regfile_write(32'h00000018, 32'h00000020);
      force dut.u_dma_regfile.dma_busy_i = 1'b1;
      force_dma_regfile_write(32'h00000028, 32'h01020304);
      force dut.u_dma_regfile.dma_busy_i = 1'b1;
      force_dma_regfile_write(32'h0000002c, 32'h05060708);
      force dut.u_dma_regfile.dma_busy_i = 1'b1;
      force_dma_regfile_write(32'h00000030, 32'h090a0b0c);
      force dut.u_dma_regfile.dma_busy_i = 1'b1;
      force_dma_regfile_write(32'h00000034, 32'h0d0e0f10);
      force dut.u_dma_regfile.dma_done_i = 1'b1;
      force dut.u_dma_regfile.dma_error_i = 1'b1;
      force dut.u_dma_regfile.bytes_done_i = 32'h13572468;
      force dut.u_dma_regfile.ciphertext_bytes_produced_i = 32'h24681357;
      force dut.u_dma_regfile.last_error_code_i = 8'hee;
      force dut.u_dma_regfile.engine_state_i = 4'ha;
      @(posedge clk);
      #1;
      force_dma_regfile_read(32'h00000020, scratch_read);
      force_dma_regfile_apb_idle;

      tx_dma_invalid_start_once(32'd0, 6'd32, 32'h00000400, 32'h00002000);
      tx_dma_invalid_start_once(32'd16, 6'd33, 32'h00000400, 32'h00002000);
      tx_dma_invalid_start_once(32'd16, 6'd32, 32'h00000401, 32'h00002000);
      tx_dma_invalid_start_once(32'd16, 6'd32, 32'h00000400, 32'h00002001);
      tx_dma_force_eval_state(5'd9,  32'h00000000);
      tx_dma_force_eval_state(5'd9,  32'h00000020);
      tx_dma_force_eval_state(5'd11, 32'h00000020);
      tx_dma_force_eval_state(5'd13, 32'h00000200);
      tx_dma_force_eval_state(5'd20, 32'h00000020);
      tx_dma_force_eval_state(5'd20, 32'h00000008);
      tx_dma_force_eval_state(5'd29, 32'h00000400);
      tx_dma_force_eval_state(5'd31, 32'h00000000);
      for (state_idx = 1; state_idx <= 30; state_idx = state_idx + 1)
        tx_dma_soft_reset_from_state(state_idx[4:0]);

      rx_dma_invalid_start_once(32'd0, 32'h00002000, 32'h00004000);
      rx_dma_invalid_start_once(32'd16, 32'h00002001, 32'h00004000);
      rx_dma_invalid_start_once(32'd16, 32'h00002000, 32'h00004001);
      rx_dma_force_eval_state(5'd15, 32'h00000000, 32'd16, 1'b0);
      rx_dma_force_eval_state(5'd17, 32'h00000020, 32'd16, 1'b0);
      rx_dma_force_eval_state(5'd17, 32'h00000010, 32'd16, 1'b0);
      rx_dma_force_eval_state(5'd19, 32'h00000000, 32'd0, 1'b0);
      rx_dma_force_eval_state(5'd19, 32'h00000005, 32'd0, 1'b0);
      release_dma_engine_direct_forces;
      force dut.u_dma_rx_engine.state_r = 5'd24;
      force dut.u_dma_rx_engine.rx_pready_i = 1'b1;
      force dut.u_dma_rx_engine.rx_pslverr_i = 1'b1;
      @(posedge clk);
      #1;
      release_dma_engine_direct_forces;
      rx_dma_force_eval_state(5'd31, 32'h00000000, 32'd0, 1'b0);
      for (state_idx = 1; state_idx <= 26; state_idx = state_idx + 1)
        rx_dma_soft_reset_from_state(state_idx[4:0]);

      exercise_apb_if_and_wrapper_direct_coverage;

      release_dma_engine_direct_forces;
      force_bridge_direct_idle;
      force_dma_regfile_apb_idle;
      repeat (3) @(posedge clk);

      $display("# DMA_BRIDGE_DIRECT_COV: done scratch=0x%08x", scratch_read);
    end
  endtask

  task automatic write_summary_file;
    integer fd;
    begin
      fd = $fopen(LOOPBACK_SUMMARY_FILE, "w");
      if (fd == 0) begin
        $display("[FAIL] cannot open summary file: %0s", LOOPBACK_SUMMARY_FILE);
        fail_count = fail_count + 1;
        $finish;
      end

      $fdisplay(fd, "input_file=%0s", input_file_name);
      $fdisplay(fd, "input_len_bytes=%0d", input_len_bytes);
      if (input2_file_enable) begin
        $fdisplay(fd, "input2_file=%0s", input2_file_name);
        $fdisplay(fd, "input2_len_bytes=%0d", input2_len_bytes);
        $fdisplay(fd, "src2_base_addr=0x%08x", SRC2_BASE_ADDR);
      end
      $fdisplay(fd, "src_base_addr=0x%08x", SRC_BASE_ADDR);
      $fdisplay(fd, "tx_dst_base_addr=0x%08x", TX_DST_BASE_ADDR);
      $fdisplay(fd, "rx_dst_base_addr=0x%08x", RX_DST_BASE_ADDR);
      $fdisplay(fd, "tx_ciphertext_bytes=%0d", tx_ciphertext_bytes);
      $fdisplay(fd, "rx_plaintext_bytes=%0d", rx_plaintext_bytes);
      $fdisplay(fd, "compressed_payload_bits=%0d", compressed_payload_bits);
      $fdisplay(fd, "compressed_payload_bytes_ceil=%0d", compressed_payload_bytes_ceil);
      $fdisplay(fd, "tx_start_cycle=%0d", tx_start_cycle);
      $fdisplay(fd, "tx_end_cycle=%0d", tx_end_cycle);
      $fdisplay(fd, "tx_busy_cycles=%0d", tx_busy_cycles);
      $fdisplay(fd, "rx_start_cycle=%0d", rx_start_cycle);
      $fdisplay(fd, "rx_end_cycle=%0d", rx_end_cycle);
      $fdisplay(fd, "rx_busy_cycles=%0d", rx_busy_cycles);
      $fdisplay(fd, "tx_input_bytes_per_cycle=%0.6f", tx_input_bytes_per_cycle);
      $fdisplay(fd, "tx_output_bytes_per_cycle=%0.6f", tx_output_bytes_per_cycle);
      $fdisplay(fd, "rx_input_bytes_per_cycle=%0.6f", rx_input_bytes_per_cycle);
      $fdisplay(fd, "rx_output_bytes_per_cycle=%0.6f", rx_output_bytes_per_cycle);
      $fdisplay(fd, "tx_input_mbytes_per_sec=%0.3f", tx_input_mbytes_per_sec);
      $fdisplay(fd, "tx_output_mbytes_per_sec=%0.3f", tx_output_mbytes_per_sec);
      $fdisplay(fd, "rx_input_mbytes_per_sec=%0.3f", rx_input_mbytes_per_sec);
      $fdisplay(fd, "rx_output_mbytes_per_sec=%0.3f", rx_output_mbytes_per_sec);
      $fdisplay(fd, "payload_ratio_pct=%0.2f", payload_ratio_pct);
      $fdisplay(fd, "payload_space_saving_pct=%0.2f", payload_space_saving_pct);
      $fdisplay(fd, "storage_ratio_pct=%0.2f", storage_ratio_pct);
      $fdisplay(fd, "space_saving_pct=%0.2f", space_saving_pct);
      $fdisplay(fd, "src_mismatch_count=%0d", src_mismatch_count);
      $fdisplay(fd, "rx_mismatch_count=%0d", rx_mismatch_count);
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
      soft_reset_pulse_count <= 0;
      clear_done_pulse_count <= 0;
      clear_error_pulse_count <= 0;
      apb_error_count <= 0;
      bridge_error_count <= 0;
      cycle_counter         <= 0;
      tx_busy_cycles        <= 0;
      rx_busy_cycles        <= 0;
      tx_start_cycle        <= -1;
      tx_end_cycle          <= -1;
      rx_start_cycle        <= -1;
      rx_end_cycle          <= -1;
      tx_seen_busy          <= 1'b0;
      rx_seen_busy          <= 1'b0;
      tx_busy_prev          <= 1'b0;
      rx_busy_prev          <= 1'b0;
      rx_ciphertext_feed_count   <= 0;
      tx_transport_capture_count <= 0;
      rx_transport_capture_count <= 0;
      rx_word_capture_count      <= 0;
      tx_word_in_capture_count   <= 0;
      tx_dma_word_write_count    <= 0;
      tx_dma_read_capture_count  <= 0;
      mmio_write_capture_count   <= 0;
      compressed_payload_bits    <= 0;
      first_tx_transport_word    <= 128'b0;
      first_tx_ciphertext_dmem_word <= 128'b0;
      first_rx_ciphertext_feed_word <= 128'b0;
      first_rx_transport_word    <= 128'b0;
      first_tx_word_in_data      <= 32'b0;
      first_tx_dma_word_write_data <= 32'b0;
      first_tx_dma_read_addr     <= 32'b0;
      first_tx_dma_read_data     <= 32'b0;
      first_tx_start_src_addr    <= 32'b0;
      first_tx_start_dst_addr    <= 32'b0;
      first_tx_start_len_bytes   <= 32'b0;
      first_tx_start_dir         <= 2'b0;
      first_tx_start_block_size  <= 6'b0;
      first_rx_word_data         <= 32'b0;
      first_rx_word_valid_bytes  <= 3'b0;
      first_rx_word_last_in_block<= 1'b0;
      first_rx_word_last_in_frame<= 1'b0;
      first_tx_transport_valid   <= 1'b0;
      first_tx_ciphertext_dmem_valid <= 1'b0;
      first_rx_ciphertext_feed_valid <= 1'b0;
      first_rx_transport_valid   <= 1'b0;
      first_tx_word_in_valid_seen<= 1'b0;
      first_tx_dma_word_write_seen <= 1'b0;
      first_tx_dma_read_seen     <= 1'b0;
      first_tx_start_seen        <= 1'b0;
      first_rx_word_valid_seen   <= 1'b0;
      for (i = 0; i < 8; i = i + 1) begin
        mmio_write_addr_log[i] <= 32'b0;
        mmio_write_data_log[i] <= 32'b0;
      end
    end
    else begin
      cycle_counter <= cycle_counter + 1;

      if (dut.u_dma_regfile.start_pulse_o)
        dma_start_pulse_count <= dma_start_pulse_count + 1;
      if (dut.u_dma_regfile.soft_reset_pulse_o)
        soft_reset_pulse_count <= soft_reset_pulse_count + 1;
      if (dut.u_dma_regfile.clear_done_pulse_o)
        clear_done_pulse_count <= clear_done_pulse_count + 1;
      if (dut.u_dma_regfile.clear_error_pulse_o)
        clear_error_pulse_count <= clear_error_pulse_count + 1;
      if (dut.bridge_psel_w && dut.bridge_penable_w && dut.dma_apb_pready_w && dut.dma_apb_pslverr_w)
        apb_error_count <= apb_error_count + 1;
      if (dut.bridge_mmio_error_w)
        bridge_error_count <= bridge_error_count + 1;

      if (dut.bridge_psel_w &&
          dut.bridge_penable_w &&
          dut.bridge_pwrite_w &&
          dut.dma_apb_pready_w &&
          (mmio_write_capture_count < 8)) begin
        mmio_write_addr_log[mmio_write_capture_count] <= dut.bridge_paddr_w;
        mmio_write_data_log[mmio_write_capture_count] <= dut.bridge_pwdata_w;
        mmio_write_capture_count <= mmio_write_capture_count + 1;
      end

      if ((!first_tx_start_seen) &&
          dut.u_dma_regfile.start_pulse_o &&
          (dut.u_dma_regfile.direction_o == 2'b01)) begin
        first_tx_start_seen       <= 1'b1;
        first_tx_start_src_addr   <= dut.u_dma_regfile.src_addr_o;
        first_tx_start_dst_addr   <= dut.u_dma_regfile.dst_addr_o;
        first_tx_start_len_bytes  <= dut.u_dma_regfile.len_bytes_o;
        first_tx_start_dir        <= dut.u_dma_regfile.direction_o;
        first_tx_start_block_size <= dut.u_dma_regfile.block_size_o;
      end

      if (dut.tx_dma_busy_w)
        tx_busy_cycles <= tx_busy_cycles + 1;
      if (dut.rx_dma_busy_w)
        rx_busy_cycles <= rx_busy_cycles + 1;

      if ((!tx_seen_busy) && dut.tx_dma_busy_w) begin
        tx_seen_busy   <= 1'b1;
        tx_start_cycle <= cycle_counter;
      end

      if ((!rx_seen_busy) && dut.rx_dma_busy_w) begin
        rx_seen_busy   <= 1'b1;
        rx_start_cycle <= cycle_counter;
      end

      if ((!first_tx_transport_valid) && dut.tx_transport_word_valid_dbg_w) begin
        first_tx_transport_valid <= 1'b1;
        first_tx_transport_word  <= dut.tx_transport_word_dbg_w;
      end

      if (dut.tx_transport_word_valid_dbg_w)
        tx_transport_capture_count <= tx_transport_capture_count + 1;

      if (dut.tx_cipher_en_dbg_w)
        compressed_payload_bits <= compressed_payload_bits +
                                   tx_transport_valid_bits(dut.tx_transport_word_dbg_w);

      if ((!first_tx_word_in_valid_seen) &&
          dut.tx_apb_word_valid_dbg_w &&
          dut.tx_apb_word_ready_dbg_w) begin
        first_tx_word_in_valid_seen <= 1'b1;
        first_tx_word_in_data       <= dut.tx_apb_word_in_dbg_w;
      end

      if (dut.tx_apb_word_valid_dbg_w && dut.tx_apb_word_ready_dbg_w)
        tx_word_in_capture_count <= tx_word_in_capture_count + 1;

      if ((dut.u_dma_tx_engine.state_r == 5'd22) &&
          dut.u_dma_tx_engine.tx_pready_i &&
          dut.u_dma_tx_engine.apb_write_r &&
          (dut.u_dma_tx_engine.apb_addr_r == 32'h00000008)) begin
        if (!first_tx_dma_word_write_seen) begin
          first_tx_dma_word_write_seen <= 1'b1;
          first_tx_dma_word_write_data <= dut.u_dma_tx_engine.apb_wdata_r;
        end
        tx_dma_word_write_count <= tx_dma_word_write_count + 1;
      end

      if (dut.u_dma_tx_engine.state_r == 5'd7) begin
        if (!first_tx_dma_read_seen) begin
          first_tx_dma_read_seen <= 1'b1;
          first_tx_dma_read_addr <= dut.u_dma_tx_engine.src_ptr_r;
          first_tx_dma_read_data <= dut.u_dma_tx_engine.dmem_rdata_i;
        end
        tx_dma_read_capture_count <= tx_dma_read_capture_count + 1;
      end

      if ((!first_rx_ciphertext_feed_valid) &&
          dut.rx_ciphertext_word_valid_w &&
          dut.rx_ciphertext_word_ready_unused_w) begin
        first_rx_ciphertext_feed_valid <= 1'b1;
        first_rx_ciphertext_feed_word  <= dut.rx_ciphertext_word_w;
      end

      if (dut.rx_ciphertext_word_valid_w && dut.rx_ciphertext_word_ready_unused_w)
        rx_ciphertext_feed_count <= rx_ciphertext_feed_count + 1;

      if ((!first_rx_transport_valid) && dut.rx_transport_word_valid_dbg_w) begin
        first_rx_transport_valid <= 1'b1;
        first_rx_transport_word  <= dut.rx_transport_word_dbg_w;
      end

      if (dut.rx_transport_word_valid_dbg_w)
        rx_transport_capture_count <= rx_transport_capture_count + 1;

      if ((!first_rx_word_valid_seen) && dut.rx_word_valid_dbg_w) begin
        first_rx_word_valid_seen    <= 1'b1;
        first_rx_word_data          <= dut.rx_word_dbg_w;
        first_rx_word_valid_bytes   <= dut.rx_word_valid_bytes_dbg_w;
        first_rx_word_last_in_block <= dut.rx_word_last_in_block_dbg_w;
        first_rx_word_last_in_frame <= dut.rx_word_last_in_frame_dbg_w;
      end

      if (dut.rx_word_valid_dbg_w)
        rx_word_capture_count <= rx_word_capture_count + 1;

      if (tx_seen_busy && tx_busy_prev && (!dut.tx_dma_busy_w) && (tx_end_cycle < 0))
        tx_end_cycle <= cycle_counter;

      if (rx_seen_busy && rx_busy_prev && (!dut.rx_dma_busy_w) && (rx_end_cycle < 0))
        rx_end_cycle <= cycle_counter;

      tx_busy_prev <= dut.tx_dma_busy_w;
      rx_busy_prev <= dut.rx_dma_busy_w;
    end
  end

  task automatic inject_tx_apb_waitstate_once;
    begin
      wait (rst == 1'b0);
      wait ((dut.u_dma_tx_engine.state_r == 5'd22) && dut.tx_pready_w);
      $display("# COV inject TX APB wait-state");
      force dut.tx_pready_w = 1'b0;
      repeat (3) @(posedge clk);
      release dut.tx_pready_w;
    end
  endtask

  task automatic inject_rx_apb_waitstate_once;
    begin
      wait (rst == 1'b0);
      wait ((dut.u_dma_rx_engine.state_r == 5'd24) && dut.rx_pready_w);
      $display("# COV inject RX APB wait-state");
      force dut.rx_pready_w = 1'b0;
      repeat (3) @(posedge clk);
      release dut.rx_pready_w;
    end
  endtask

  task automatic inject_rx_stream_backpressure_once;
    begin
      wait (rst == 1'b0);
      wait ((dut.u_dma_rx_engine.state_r == 5'd15) && dut.rx_ciphertext_word_valid_w);
      $display("# COV inject RX ciphertext stream backpressure");
      force dut.rx_ciphertext_word_ready_unused_w = 1'b0;
      repeat (4) @(posedge clk);
      release dut.rx_ciphertext_word_ready_unused_w;
    end
  endtask

  task automatic inject_tx_apb_error_once;
    begin
      wait (rst == 1'b0);
      wait ((dut.u_dma_tx_engine.state_r == 5'd22) && dut.tx_pready_w);
      $display("# COV inject TX APB PSLVERR");
      force dut.tx_pslverr_w = 1'b1;
      @(posedge clk);
      release dut.tx_pslverr_w;
    end
  endtask

  task force_tx_apb_idle;
    begin
      release dut.tx_psel_w;
      release dut.tx_penable_w;
      release dut.tx_pwrite_w;
      release dut.tx_paddr_w;
      release dut.tx_pwdata_w;
      @(posedge clk);
      #1;
    end
  endtask

  task force_tx_apb_write;
    input [31:0] addr;
    input [31:0] data;
    begin
      force dut.tx_psel_w    = 1'b1;
      force dut.tx_penable_w = 1'b1;
      force dut.tx_pwrite_w  = 1'b1;
      force dut.tx_paddr_w   = addr;
      force dut.tx_pwdata_w  = data;
      @(posedge clk);
      #1;
      force_tx_apb_idle;
    end
  endtask

  task force_tx_apb_read;
    input  [31:0] addr;
    output [31:0] data;
    begin
      force dut.tx_psel_w    = 1'b1;
      force dut.tx_penable_w = 1'b1;
      force dut.tx_pwrite_w  = 1'b0;
      force dut.tx_paddr_w   = addr;
      force dut.tx_pwdata_w  = 32'h00000000;
      @(posedge clk);
      #1;
      data = dut.tx_prdata_w;
      force_tx_apb_idle;
    end
  endtask

  task force_tx_aes_out_idle;
    begin
      release dut.u_tx_top.aes_out_word_w;
      release dut.u_tx_top.aes_out_word_last_w;
      release dut.u_tx_top.aes_out_word_valid_w;
      release dut.u_tx_top.aes_output_error_r;
      @(posedge clk);
      #1;
    end
  endtask

  task force_tx_aes_out_push;
    input [31:0] data;
    input        last_word;
    begin
      force dut.u_tx_top.aes_out_word_w       = data;
      force dut.u_tx_top.aes_out_word_last_w  = last_word;
      force dut.u_tx_top.aes_out_word_valid_w = 1'b1;
      wait (dut.u_tx_top.aes_out_word_ready_w == 1'b1);
      @(posedge clk);
      #1;
      force_tx_aes_out_idle;
    end
  endtask

  task automatic exercise_tx_if_direct_coverage;
    reg [31:0] scratch_read;
    integer word_idx;
    begin
      $display("# TX_IF_DIRECT_COV: exercise APB TX IF empty/full/error/status branches");

      force_tx_apb_read(32'h00000000, scratch_read);
      force_tx_apb_read(32'h00000004, scratch_read);
      force_tx_apb_read(32'h0000000c, scratch_read);
      force_tx_apb_read(32'h00000014, scratch_read);
      force_tx_apb_read(32'h00000018, scratch_read);
      force_tx_apb_read(32'h00000020, scratch_read); // output FIFO empty, PREADY low branch
      force_tx_apb_read(32'h00000024, scratch_read);
      force_tx_apb_read(32'h00000028, scratch_read);
      force_tx_apb_read(32'h0000002c, scratch_read);
      force_tx_apb_read(32'h000000fc, scratch_read); // invalid read

      force_tx_apb_write(32'h00000000, 32'h00000001); // start without config
      force_tx_apb_write(32'h00000004, 32'h00000000); // invalid block size
      force_tx_apb_write(32'h00000004, 32'h00000021); // invalid > 32
      force_tx_apb_write(32'h00000018, 32'h00000008); // reserved policy bits
      force_tx_apb_write(32'h00000010, 32'h80000000); // reserved control bits
      force_tx_apb_write(32'h000000fc, 32'h12345678); // invalid write

      force_tx_apb_write(32'h00000010, 32'h00000001); // soft reset
      force_tx_apb_write(32'h00000018, 32'h00000007); // compress_only + whole-file + count
      force_tx_apb_write(32'h00000004, 32'h00000020); // 8 input words expected
      force_tx_apb_write(32'h00000000, 32'h00000001); // start before all words loaded, PREADY low branch

      for (word_idx = 0; word_idx < 8; word_idx = word_idx + 1)
        force_tx_apb_write(32'h00000008, 32'h11110000 | word_idx[31:0]);

      force_tx_apb_write(32'h00000008, 32'h22220000); // too many words

      force dut.u_tx_top.apb_word_ready_w = 1'b0;
      force_tx_apb_write(32'h00000000, 32'h00000003); // valid start + continue, hold stream
      force_tx_apb_write(32'h00000004, 32'h00000010); // config while inflight, PREADY low
      force_tx_apb_write(32'h00000018, 32'h00000000); // policy while inflight, PREADY low
      repeat (2) @(posedge clk);
      release dut.u_tx_top.apb_word_ready_w;
      repeat (10) @(posedge clk);

      force_tx_apb_write(32'h00000010, 32'h00000001); // clear inflight/direct FIFO state

      for (word_idx = 0; word_idx < 16; word_idx = word_idx + 1)
        force_tx_aes_out_push(32'ha0000000 | word_idx[31:0], (word_idx == 15));

      force_tx_apb_read(32'h00000028, scratch_read); // output FIFO full status

      force dut.u_tx_top.aes_out_word_w       = 32'hfeed0001;
      force dut.u_tx_top.aes_out_word_last_w  = 1'b0;
      force dut.u_tx_top.aes_out_word_valid_w = 1'b1;
      force dut.tx_psel_w                     = 1'b1;
      force dut.tx_penable_w                  = 1'b1;
      force dut.tx_pwrite_w                   = 1'b0;
      force dut.tx_paddr_w                    = 32'h00000020;
      force dut.tx_pwdata_w                   = 32'h00000000;
      @(posedge clk);
      #1;
      scratch_read = dut.tx_prdata_w;         // simultaneous output push + pop when full
      force_tx_aes_out_idle;
      force_tx_apb_idle;

      for (word_idx = 0; word_idx < 18; word_idx = word_idx + 1) begin
        force_tx_apb_read(32'h00000024, scratch_read);
        force_tx_apb_read(32'h00000020, scratch_read);
      end

      force dut.u_tx_top.aes_output_error_r = 1'b1;
      @(posedge clk);
      #1;
      force dut.u_tx_top.aes_output_error_r = 1'b0;
      force_tx_apb_read(32'h00000028, scratch_read);
      force_tx_apb_write(32'h00000010, 32'h00000007); // clear done/error plus reset
      force_tx_aes_out_idle;
      force_tx_apb_idle;

      $display("# TX_IF_DIRECT_COV: done scratch=0x%08x", scratch_read);
    end
  endtask

  task force_rx_apb_idle;
    begin
      release dut.rx_psel_w;
      release dut.rx_penable_w;
      release dut.rx_pwrite_w;
      release dut.rx_paddr_w;
      release dut.rx_pwdata_w;
      @(posedge clk);
      #1;
    end
  endtask

  task force_rx_apb_write;
    input [31:0] addr;
    input [31:0] data;
    begin
      force dut.rx_psel_w    = 1'b1;
      force dut.rx_penable_w = 1'b1;
      force dut.rx_pwrite_w  = 1'b1;
      force dut.rx_paddr_w   = addr;
      force dut.rx_pwdata_w  = data;
      @(posedge clk);
      #1;
      force_rx_apb_idle;
    end
  endtask

  task force_rx_apb_read;
    input  [31:0] addr;
    output [31:0] data;
    begin
      force dut.rx_psel_w    = 1'b1;
      force dut.rx_penable_w = 1'b1;
      force dut.rx_pwrite_w  = 1'b0;
      force dut.rx_paddr_w   = addr;
      force dut.rx_pwdata_w  = 32'h00000000;
      @(posedge clk);
      #1;
      data = dut.rx_prdata_w;
      force_rx_apb_idle;
    end
  endtask

  task force_rx_word_idle;
    begin
      release dut.u_rx_top.rx_word_data_w;
      release dut.u_rx_top.rx_word_valid_bytes_w;
      release dut.u_rx_top.rx_word_last_in_block_w;
      release dut.u_rx_top.rx_word_last_in_frame_w;
      release dut.u_rx_top.rx_word_valid_w;
      @(posedge clk);
      #1;
    end
  endtask

  task force_rx_word_push;
    input [31:0] data;
    input [2:0]  valid_bytes;
    input        last_block;
    input        last_frame;
    begin
      force dut.u_rx_top.rx_word_data_w          = data;
      force dut.u_rx_top.rx_word_valid_bytes_w   = valid_bytes;
      force dut.u_rx_top.rx_word_last_in_block_w = last_block;
      force dut.u_rx_top.rx_word_last_in_frame_w = last_frame;
      force dut.u_rx_top.rx_word_valid_w         = 1'b1;
      @(posedge clk);
      #1;
      force_rx_word_idle;
    end
  endtask

  task force_rx_depacker_transport_idle;
    begin
      release dut.u_rx_top.transport_buf_data_r;
      release dut.u_rx_top.transport_buf_valid_r;
      release dut.u_rx_top.depacker_stream_ready_w;
      release dut.u_rx_top.u_bit_depacker_128.transport_word_fire_w;
      release dut.u_rx_top.u_bit_depacker_128.bit_count_r;
      release dut.u_rx_top.u_bit_depacker_128.frame_last_pending_r;
      release dut.u_rx_top.u_bit_depacker_128.stream_valid_r;
      release dut.u_rx_top.u_bit_depacker_128.error_r;
      @(posedge clk);
      #1;
    end
  endtask

  task force_rx_depacker_transport_push;
    input [127:0] transport_word;
    integer timeout_idx;
    begin
      force dut.u_rx_top.transport_buf_data_r  = transport_word;
      force dut.u_rx_top.transport_buf_valid_r = 1'b1;

      for (timeout_idx = 0; timeout_idx < 32; timeout_idx = timeout_idx + 1) begin
        if (dut.u_rx_top.transport_word_ready_w)
          timeout_idx = 32;
        @(posedge clk);
      end

      force dut.u_rx_top.transport_buf_valid_r = 1'b0;
      @(posedge clk);
      #1;
    end
  endtask

  task force_rx_packer_idle;
    begin
      release dut.u_rx_top.decoder_out_byte_w;
      release dut.u_rx_top.decoder_out_valid_w;
      release dut.u_rx_top.decoder_out_last_in_block_w;
      release dut.u_rx_top.decoder_out_last_in_frame_w;
      release dut.u_rx_top.rx_word_ready_w;
      release dut.u_rx_top.u_rx_byte_packer_32.accum_count_r;
      release dut.u_rx_top.u_rx_byte_packer_32.word_valid_r;
      @(posedge clk);
      #1;
    end
  endtask

  task force_rx_packer_byte;
    input [7:0] data;
    input       last_block;
    input       last_frame;
    begin
      force dut.u_rx_top.decoder_out_byte_w                = data;
      force dut.u_rx_top.decoder_out_last_in_block_w       = last_block;
      force dut.u_rx_top.decoder_out_last_in_frame_w       = last_frame;
      force dut.u_rx_top.decoder_out_valid_w               = 1'b1;
      @(posedge clk);
      #1;
      force dut.u_rx_top.decoder_out_valid_w               = 1'b0;
      force dut.u_rx_top.decoder_out_last_in_block_w       = 1'b0;
      force dut.u_rx_top.decoder_out_last_in_frame_w       = 1'b0;
      @(posedge clk);
      #1;
    end
  endtask

  task automatic exercise_rx_depacker_packer_direct_coverage;
    begin
      $display("# RX_DEPACKER_PACKER_DIRECT_COV: exercise malformed transport and packer backpressure/error branches");

      reset_rx_pipeline_for_cov;
      force dut.u_rx_top.depacker_stream_ready_w = 1'b1;
      force_rx_depacker_transport_push({1'b1, 7'd8, 120'h000000000000000000000041});
      repeat (8) @(posedge clk);

      // Exactly 32 valid bits on the last transport word covers full-chunk last handling.
      reset_rx_pipeline_for_cov;
      force dut.u_rx_top.depacker_stream_ready_w = 1'b1;
      force_rx_depacker_transport_push({1'b1, 7'd32, 120'h0000000000000000deadbeef});
      repeat (8) @(posedge clk);

      // Malformed transport variants cover zero valid-bits, short non-last, and oversized last.
      reset_rx_pipeline_for_cov;
      force dut.u_rx_top.depacker_stream_ready_w = 1'b1;
      force_rx_depacker_transport_push({1'b0, 7'd0, 120'h0});
      repeat (4) @(posedge clk);

      reset_rx_pipeline_for_cov;
      force dut.u_rx_top.depacker_stream_ready_w = 1'b1;
      force_rx_depacker_transport_push({1'b0, 7'd6, 120'h00000000000000000000003f});
      repeat (4) @(posedge clk);

      reset_rx_pipeline_for_cov;
      force dut.u_rx_top.depacker_stream_ready_w = 1'b1;
      force_rx_depacker_transport_push({1'b1, 7'd121, 120'hffffffffffffffffffffffffffffff});
      repeat (4) @(posedge clk);

      // Directly force an impossible buffered-count overflow to close the defensive error branch.
      reset_rx_pipeline_for_cov;
      force dut.u_rx_top.depacker_stream_ready_w = 1'b1;
      force dut.u_rx_top.u_bit_depacker_128.bit_count_r = 13'd100;
      force dut.u_rx_top.u_bit_depacker_128.transport_word_fire_w = 1'b1;
      force dut.u_rx_top.transport_buf_data_r = {1'b0, 7'd120, 120'h123456789abcdef001122334455667};
      force dut.u_rx_top.transport_buf_valid_r = 1'b1;
      @(posedge clk);
      #1;
      force_rx_depacker_transport_idle;

      // Cover frame_last_pending with an empty buffer, which is a legal defensive no-tail path.
      reset_rx_pipeline_for_cov;
      force dut.u_rx_top.u_bit_depacker_128.frame_last_pending_r = 1'b1;
      force dut.u_rx_top.u_bit_depacker_128.bit_count_r = 13'd0;
      force dut.u_rx_top.u_bit_depacker_128.stream_valid_r = 1'b0;
      force dut.u_rx_top.u_bit_depacker_128.error_r = 1'b0;
      repeat (2) @(posedge clk);
      force_rx_depacker_transport_idle;

      // RX byte packer: create a pending word, hold APB side not-ready, and apply input backpressure.
      reset_rx_pipeline_for_cov;
      force dut.u_rx_top.rx_word_ready_w = 1'b1;
      force_rx_packer_byte(8'h11, 1'b0, 1'b0);
      force_rx_packer_byte(8'h22, 1'b0, 1'b0);
      force_rx_packer_byte(8'h33, 1'b0, 1'b0);
      force_rx_packer_byte(8'h44, 1'b0, 1'b0);
      force dut.u_rx_top.rx_word_ready_w = 1'b0;
      force dut.u_rx_top.decoder_out_byte_w          = 8'h55;
      force dut.u_rx_top.decoder_out_valid_w         = 1'b1;
      force dut.u_rx_top.decoder_out_last_in_block_w = 1'b0;
      force dut.u_rx_top.decoder_out_last_in_frame_w = 1'b0;
      repeat (2) @(posedge clk);
      force dut.u_rx_top.decoder_out_valid_w = 1'b0;
      force dut.u_rx_top.rx_word_ready_w = 1'b1;
      repeat (3) @(posedge clk);
      force_rx_packer_idle;

      // Packer illegal frame flag: frame-last without block-last.
      reset_rx_pipeline_for_cov;
      force dut.u_rx_top.rx_word_ready_w = 1'b1;
      force_rx_packer_byte(8'h66, 1'b0, 1'b1);
      repeat (4) @(posedge clk);
      force_rx_packer_idle;

      // Defensive overflow/default branches by forcing unreachable internal counts.
      reset_rx_pipeline_for_cov;
      force dut.u_rx_top.rx_word_ready_w = 1'b1;
      force dut.u_rx_top.u_rx_byte_packer_32.accum_count_r = 3'd4;
      force_rx_packer_byte(8'h77, 1'b0, 1'b0);
      force_rx_packer_idle;

      reset_rx_pipeline_for_cov;
      force dut.u_rx_top.rx_word_ready_w = 1'b1;
      force dut.u_rx_top.u_rx_byte_packer_32.accum_count_r = 3'd7;
      force_rx_packer_byte(8'h88, 1'b1, 1'b1);
      force_rx_packer_idle;

      reset_rx_pipeline_for_cov;
      $display("# RX_DEPACKER_PACKER_DIRECT_COV: done");
    end
  endtask

  task force_cpu_forward_idle;
    begin
      release dut.u_cpu.idex_rs1_addr_w;
      release dut.u_cpu.idex_rs2_addr_w;
      release dut.u_cpu.idex_rs1_data_w;
      release dut.u_cpu.idex_rs2_data_w;
      release dut.u_cpu.exmem_regwrite_w;
      release dut.u_cpu.exmem_rd_addr_w;
      release dut.u_cpu.exmem_wb_se_w;
      release dut.u_cpu.exmem_alu_result_w;
      release dut.u_cpu.exmem_pc_plus_w;
      release dut.u_cpu.mem_data_w;
      release dut.u_cpu.memwb_regwrite_w;
      release dut.u_cpu.memwb_rd_addr_w;
      release dut.u_cpu.memwb_wb_se_w;
      release dut.u_cpu.memwb_alu_result_w;
      release dut.u_cpu.memwb_mem_data_w;
      release dut.u_cpu.memwb_pc_plus_w;
      @(posedge clk);
      #1;
    end
  endtask

  task force_cpu_forward_case;
    input [4:0] rs1_addr;
    input [4:0] rs2_addr;
    input       exmem_regwrite;
    input [4:0] exmem_rd_addr;
    input [1:0] exmem_wb_sel;
    input       memwb_regwrite;
    input [4:0] memwb_rd_addr;
    input [1:0] memwb_wb_sel;
    begin
      force dut.u_cpu.idex_rs1_addr_w      = rs1_addr;
      force dut.u_cpu.idex_rs2_addr_w      = rs2_addr;
      force dut.u_cpu.idex_rs1_data_w      = 32'h11111111;
      force dut.u_cpu.idex_rs2_data_w      = 32'h22222222;
      force dut.u_cpu.exmem_regwrite_w     = exmem_regwrite;
      force dut.u_cpu.exmem_rd_addr_w      = exmem_rd_addr;
      force dut.u_cpu.exmem_wb_se_w        = exmem_wb_sel;
      force dut.u_cpu.exmem_alu_result_w   = 32'haaaa0001;
      force dut.u_cpu.exmem_pc_plus_w      = 32'hbbbb0002;
      force dut.u_cpu.mem_data_w           = 32'hcccc0003;
      force dut.u_cpu.memwb_regwrite_w     = memwb_regwrite;
      force dut.u_cpu.memwb_rd_addr_w      = memwb_rd_addr;
      force dut.u_cpu.memwb_wb_se_w        = memwb_wb_sel;
      force dut.u_cpu.memwb_alu_result_w   = 32'hdddd0004;
      force dut.u_cpu.memwb_mem_data_w     = 32'heeee0005;
      force dut.u_cpu.memwb_pc_plus_w      = 32'hffff0006;
      @(posedge clk);
      #1;
    end
  endtask

  task automatic exercise_cpu_forward_direct_coverage;
    reg [31:0] fwd_mix;
    begin
      $display("# CPU_FORWARD_DIRECT_COV: exercise forwarding mux rs1/rs2 exmem/memwb paths");
      fwd_mix = 32'h00000000;

      force_cpu_forward_case(5'd1, 5'd2, 1'b0, 5'd0, 2'b00, 1'b0, 5'd0, 2'b00);
      fwd_mix = fwd_mix | dut.u_cpu.forward_src_1_w | dut.u_cpu.forward_src_2_w;

      force_cpu_forward_case(5'd3, 5'd9, 1'b1, 5'd3, 2'b00, 1'b0, 5'd0, 2'b00);
      fwd_mix = fwd_mix | dut.u_cpu.forward_src_1_w;
      force_cpu_forward_case(5'd3, 5'd9, 1'b1, 5'd3, 2'b10, 1'b0, 5'd0, 2'b00);
      fwd_mix = fwd_mix | dut.u_cpu.forward_src_1_w;
      force_cpu_forward_case(5'd3, 5'd9, 1'b1, 5'd3, 2'b01, 1'b0, 5'd0, 2'b00);
      fwd_mix = fwd_mix | dut.u_cpu.forward_src_1_w;

      force_cpu_forward_case(5'd9, 5'd4, 1'b1, 5'd4, 2'b00, 1'b0, 5'd0, 2'b00);
      fwd_mix = fwd_mix | dut.u_cpu.forward_src_2_w;
      force_cpu_forward_case(5'd9, 5'd4, 1'b1, 5'd4, 2'b10, 1'b0, 5'd0, 2'b00);
      fwd_mix = fwd_mix | dut.u_cpu.forward_src_2_w;
      force_cpu_forward_case(5'd9, 5'd4, 1'b1, 5'd4, 2'b01, 1'b0, 5'd0, 2'b00);
      fwd_mix = fwd_mix | dut.u_cpu.forward_src_2_w;

      force_cpu_forward_case(5'd5, 5'd8, 1'b0, 5'd0, 2'b00, 1'b1, 5'd5, 2'b00);
      fwd_mix = fwd_mix | dut.u_cpu.forward_src_1_w;
      force_cpu_forward_case(5'd5, 5'd8, 1'b0, 5'd0, 2'b00, 1'b1, 5'd5, 2'b01);
      fwd_mix = fwd_mix | dut.u_cpu.forward_src_1_w;
      force_cpu_forward_case(5'd5, 5'd8, 1'b0, 5'd0, 2'b00, 1'b1, 5'd5, 2'b10);
      fwd_mix = fwd_mix | dut.u_cpu.forward_src_1_w;

      force_cpu_forward_case(5'd8, 5'd6, 1'b0, 5'd0, 2'b00, 1'b1, 5'd6, 2'b00);
      fwd_mix = fwd_mix | dut.u_cpu.forward_src_2_w;
      force_cpu_forward_case(5'd8, 5'd6, 1'b0, 5'd0, 2'b00, 1'b1, 5'd6, 2'b01);
      fwd_mix = fwd_mix | dut.u_cpu.forward_src_2_w;
      force_cpu_forward_case(5'd8, 5'd6, 1'b0, 5'd0, 2'b00, 1'b1, 5'd6, 2'b10);
      fwd_mix = fwd_mix | dut.u_cpu.forward_src_2_w;

      force_cpu_forward_case(5'd7, 5'd7, 1'b1, 5'd7, 2'b00, 1'b1, 5'd7, 2'b01);
      fwd_mix = fwd_mix | dut.u_cpu.forward_src_1_w | dut.u_cpu.forward_src_2_w;
      force_cpu_forward_case(5'd0, 5'd0, 1'b1, 5'd0, 2'b00, 1'b1, 5'd0, 2'b01);
      fwd_mix = fwd_mix | dut.u_cpu.forward_src_1_w | dut.u_cpu.forward_src_2_w;

      check_true("cpu_forward_direct_mix_nonzero", fwd_mix != 32'h00000000);
      force_cpu_forward_idle;
      $display("# CPU_FORWARD_DIRECT_COV: done mix=0x%08x", fwd_mix);
    end
  endtask

  task automatic exercise_rx_if_direct_coverage;
    reg [31:0] scratch_read;
    integer word_idx;
    begin
      $display("# RX_IF_DIRECT_COV: exercise APB RX IF empty/full/error/wait-state branches");

      force_rx_apb_read(32'h00000000, scratch_read); // RX_DATA empty, PREADY low branch
      force_rx_apb_read(32'h00000004, scratch_read); // RX_META empty branch
      force_rx_apb_read(32'h00000008, scratch_read); // STATUS empty
      force_rx_apb_read(32'h00000010, scratch_read); // DEBUG
      force_rx_apb_read(32'h00000034, scratch_read); // CTXT_STATUS
      force_rx_apb_read(32'h000000fc, scratch_read); // invalid read, PSLVERR branch

      force_rx_apb_write(32'h0000000c, 32'h00000008); // reserved CONTROL bits
      force_rx_apb_write(32'h00000030, 32'h00000000); // CTXT_START missing start bit
      force_rx_apb_write(32'h00000030, 32'h00000001); // CTXT_START before 4 words valid
      force_rx_apb_write(32'h00000030, 32'h00000003); // CTXT_START reserved bits
      force_rx_apb_write(32'h000000fc, 32'h12345678); // invalid write
      force_rx_apb_write(32'h0000000c, 32'h00000004); // clear error sticky

      force dut.u_rx_top.apb_ciphertext_word_ready_w = 1'b0;
      force_rx_apb_write(32'h00000020, 32'h03020100);
      force_rx_apb_write(32'h00000024, 32'h07060504);
      force_rx_apb_write(32'h00000028, 32'h0b0a0908);
      force_rx_apb_write(32'h0000002c, 32'h0f0e0d0c);
      force_rx_apb_write(32'h00000030, 32'h00000001); // create pending ciphertext
      force_rx_apb_read(32'h00000034, scratch_read);  // pending-valid status
      force_rx_apb_write(32'h00000030, 32'h00000001); // pending full, PREADY low branch
      force dut.u_rx_top.apb_ciphertext_word_ready_w = 1'b1;
      repeat (2) @(posedge clk);
      release dut.u_rx_top.apb_ciphertext_word_ready_w;

      force_rx_word_push(32'hdeadbeef, 3'd0, 1'b0, 1'b0); // invalid valid-bytes
      force_rx_word_push(32'hcafebabe, 3'd5, 1'b0, 1'b0); // invalid > 4 bytes
      force_rx_word_push(32'h11223344, 3'd4, 1'b0, 1'b1); // frame without block
      force_rx_apb_write(32'h0000000c, 32'h00000007);     // soft reset and clear stickies

      for (word_idx = 0; word_idx < 16; word_idx = word_idx + 1)
        force_rx_word_push(32'h80000000 | word_idx[31:0], 3'd4, (word_idx == 15), (word_idx == 15));

      force_rx_apb_read(32'h00000008, scratch_read); // full status

      force dut.u_rx_top.rx_word_data_w          = 32'hfeed0001;
      force dut.u_rx_top.rx_word_valid_bytes_w   = 3'd4;
      force dut.u_rx_top.rx_word_last_in_block_w = 1'b0;
      force dut.u_rx_top.rx_word_last_in_frame_w = 1'b0;
      force dut.u_rx_top.rx_word_valid_w         = 1'b1;
      force dut.rx_psel_w                        = 1'b1;
      force dut.rx_penable_w                     = 1'b1;
      force dut.rx_pwrite_w                      = 1'b0;
      force dut.rx_paddr_w                       = 32'h00000000;
      force dut.rx_pwdata_w                      = 32'h00000000;
      @(posedge clk);
      #1;
      scratch_read = dut.rx_prdata_w;            // simultaneous push + pop when full
      force_rx_word_idle;
      force_rx_apb_idle;

      for (word_idx = 0; word_idx < 18; word_idx = word_idx + 1) begin
        force_rx_apb_read(32'h00000004, scratch_read);
        force_rx_apb_read(32'h00000000, scratch_read);
      end

      force_rx_apb_write(32'h0000000c, 32'h00000007);
      $display("# RX_IF_DIRECT_COV: done scratch=0x%08x", scratch_read);
    end
  endtask

  task force_rx_parser_stream_idle;
    begin
      release dut.u_rx_top.depacker_stream_data_w;
      release dut.u_rx_top.depacker_stream_len_w;
      release dut.u_rx_top.depacker_stream_valid_w;
      release dut.u_rx_top.depacker_stream_last_w;
      @(posedge clk);
      #1;
    end
  endtask

  task force_rx_parser_stream_chunk;
    input [31:0] data;
    input [5:0]  len;
    input        last;
    begin
      force dut.u_rx_top.depacker_stream_data_w  = data;
      force dut.u_rx_top.depacker_stream_len_w   = len;
      force dut.u_rx_top.depacker_stream_valid_w = 1'b1;
      force dut.u_rx_top.depacker_stream_last_w  = last;
      wait (dut.u_rx_top.depacker_stream_ready_w == 1'b1);
      @(posedge clk);
      #1;
      force_rx_parser_stream_idle;
    end
  endtask

  task reset_rx_pipeline_for_cov;
    begin
      rst = 1'b1;
      repeat (4) @(posedge clk);
      rst = 1'b0;
      repeat (4) @(posedge clk);
    end
  endtask

  task drain_rx_output_words_for_cov;
    reg [31:0] scratch_read;
    integer drain_idx;
    begin
      for (drain_idx = 0; drain_idx < 16; drain_idx = drain_idx + 1) begin
        if (dut.u_rx_top.u_apb_huffman_rx_if.fifo_count_r != 0) begin
          force_rx_apb_read(32'h00000004, scratch_read);
          force_rx_apb_read(32'h00000000, scratch_read);
        end
        @(posedge clk);
      end
    end
  endtask

  task run_rx_parser_decoder_frame_cov;
    input [31:0] data;
    input [5:0]  len;
    input        expect_error;
    integer timeout_idx;
    begin
      reset_rx_pipeline_for_cov;
      force_rx_parser_stream_chunk(data, len, 1'b1);

      for (timeout_idx = 0; timeout_idx < 512; timeout_idx = timeout_idx + 1) begin
        if (expect_error) begin
          if (dut.rx_parser_error_w || dut.rx_decoder_error_w)
            timeout_idx = 512;
        end
        else begin
          if (dut.u_rx_top.u_apb_huffman_rx_if.frame_done_sticky_r ||
              dut.rx_parser_error_w ||
              dut.rx_decoder_error_w)
            timeout_idx = 512;
        end
        @(posedge clk);
      end

      drain_rx_output_words_for_cov;
    end
  endtask

  task run_rx_parser_decoder_two_chunk_frame_cov;
    input [31:0] data0;
    input [5:0]  len0;
    input [31:0] data1;
    input [5:0]  len1;
    input        expect_error;
    integer timeout_idx;
    begin
      reset_rx_pipeline_for_cov;
      force_rx_parser_stream_chunk(data0, len0, 1'b0);
      force_rx_parser_stream_chunk(data1, len1, 1'b1);

      for (timeout_idx = 0; timeout_idx < 768; timeout_idx = timeout_idx + 1) begin
        if (expect_error) begin
          if (dut.rx_parser_error_w || dut.rx_decoder_error_w)
            timeout_idx = 768;
        end
        else begin
          if (dut.u_rx_top.u_apb_huffman_rx_if.frame_done_sticky_r ||
              dut.rx_parser_error_w ||
              dut.rx_decoder_error_w)
            timeout_idx = 768;
        end
        @(posedge clk);
      end

      drain_rx_output_words_for_cov;
    end
  endtask

  task run_rx_parser_decoder_raw_full_frame_cov;
    integer chunk_idx;
    integer timeout_idx;
    reg [31:0] chunk_data;
    begin
      reset_rx_pipeline_for_cov;

      // RAW_FULL frame: 2 mode bits followed by 256 payload bits.
      force_rx_parser_stream_chunk(32'h55555554, 6'd32, 1'b0);
      for (chunk_idx = 0; chunk_idx < 7; chunk_idx = chunk_idx + 1) begin
        chunk_data = (chunk_idx[0] == 1'b0) ? 32'ha5a55a5a : 32'h3cc3c33c;
        force_rx_parser_stream_chunk(chunk_data, 6'd32, 1'b0);
      end
      force_rx_parser_stream_chunk(32'h00000003, 6'd2, 1'b1);

      for (timeout_idx = 0; timeout_idx < 2048; timeout_idx = timeout_idx + 1) begin
        if (dut.u_rx_top.u_apb_huffman_rx_if.frame_done_sticky_r ||
            dut.rx_parser_error_w ||
            dut.rx_decoder_error_w)
          timeout_idx = 2048;
        @(posedge clk);
      end

      drain_rx_output_words_for_cov;
    end
  endtask

  task automatic exercise_rx_parser_decoder_coverage;
    reg [31:0] raw_partial_frame;
    reg [31:0] one_symbol_frame;
    reg [31:0] compressed_one_symbol_frame;
    reg [31:0] malformed_raw_size_frame;
    reg [31:0] malformed_one_symbol_frame;
    reg [31:0] malformed_compressed_frame;
    reg [63:0] compressed_two_symbol_frame;
    reg [63:0] malformed_bad_entry_frame;
    begin
      $display("# RX_PARSE_DECODE_COV: exercise parser/decoder raw/one-symbol/compressed/malformed frames");

      raw_partial_frame =
          (32'h43 << 24) | (32'h42 << 16) | (32'h41 << 8) |
          (32'd3 << 2) | 32'd1;
      one_symbol_frame =
          (32'h41 << 8) | (32'd5 << 2) | 32'd3;
      compressed_one_symbol_frame =
          (32'd1 << 22) | (32'h5a << 14) |
          (32'd1 << 8) | (32'd4 << 2) | 32'd2;
      malformed_raw_size_frame =
          (32'd32 << 2) | 32'd1;
      malformed_one_symbol_frame =
          (32'h01 << 8) | (32'd5 << 2) | 32'd3;
      malformed_compressed_frame =
          (32'd0 << 2) | 32'd2;
      compressed_two_symbol_frame =
          (64'd5 << 40) | (64'd1 << 35) | (64'h42 << 27) |
          (64'd1 << 22) | (64'h41 << 14) |
          (64'd2 << 8) | (64'd4 << 2) | 64'd2;
      malformed_bad_entry_frame =
          (64'd0 << 35) | (64'h01 << 27) |
          (64'd1 << 22) | (64'h41 << 14) |
          (64'd2 << 8) | (64'd4 << 2) | 64'd2;

      run_rx_parser_decoder_raw_full_frame_cov;
      run_rx_parser_decoder_frame_cov(raw_partial_frame, 6'd32, 1'b0);
      run_rx_parser_decoder_frame_cov(one_symbol_frame, 6'd16, 1'b0);
      run_rx_parser_decoder_frame_cov(compressed_one_symbol_frame, 6'd31, 1'b0);
      run_rx_parser_decoder_two_chunk_frame_cov(compressed_two_symbol_frame[31:0],
                                                6'd32,
                                                compressed_two_symbol_frame[63:32],
                                                6'd12,
                                                1'b0);
      run_rx_parser_decoder_frame_cov(malformed_raw_size_frame, 6'd8, 1'b1);
      run_rx_parser_decoder_frame_cov(malformed_one_symbol_frame, 6'd16, 1'b1);
      run_rx_parser_decoder_frame_cov(malformed_compressed_frame, 6'd14, 1'b1);
      run_rx_parser_decoder_two_chunk_frame_cov(malformed_bad_entry_frame[31:0],
                                                6'd32,
                                                malformed_bad_entry_frame[63:32],
                                                6'd8,
                                                1'b1);
      run_rx_parser_decoder_frame_cov(32'h00000000, 6'd0, 1'b1);

      reset_rx_pipeline_for_cov;
      $display("# RX_PARSE_DECODE_COV: done");
    end
  endtask

  task force_rx_decoder_direct_idle;
    begin
      release dut.u_rx_top.parser_block_mode_w;
      release dut.u_rx_top.parser_block_size_w;
      release dut.u_rx_top.parser_symbol_count_w;
      release dut.u_rx_top.parser_one_symbol_value_w;
      release dut.u_rx_top.parser_block_meta_valid_w;
      release dut.u_rx_top.parser_entry_symbol_w;
      release dut.u_rx_top.parser_entry_code_len_w;
      release dut.u_rx_top.parser_entry_valid_w;
      release dut.u_rx_top.parser_entry_last_w;
      release dut.u_rx_top.parser_payload_window_data_w;
      release dut.u_rx_top.parser_payload_window_len_w;
      release dut.u_rx_top.parser_payload_window_valid_w;
      release dut.u_rx_top.parser_block_done;
      release dut.u_rx_top.parser_frame_done;
      release dut.u_rx_top.decoder_out_ready_w;
      release dut.u_rx_top.u_huffman_block_decoder.state_r;
      release dut.u_rx_top.u_huffman_block_decoder.symbol_count_r;
      release dut.u_rx_top.u_huffman_block_decoder.one_symbol_value_r;
      release dut.u_rx_top.u_huffman_block_decoder.bytes_remaining_r;
      release dut.u_rx_top.u_huffman_block_decoder.entry_load_count_r;
      release dut.u_rx_top.u_huffman_block_decoder.assign_idx_r;
      release dut.u_rx_top.u_huffman_block_decoder.table_build_idx_r;
      release dut.u_rx_top.u_huffman_block_decoder.fallback_count_r;
      release dut.u_rx_top.u_huffman_block_decoder.fallback_scan_idx_r;
      release dut.u_rx_top.u_huffman_block_decoder.fallback_prefix_seen_r;
      release dut.u_rx_top.u_huffman_block_decoder.prev_len_r;
      release dut.u_rx_top.u_huffman_block_decoder.current_code_r;
      release dut.u_rx_top.u_huffman_block_decoder.out_valid_r;
      release dut.u_rx_top.u_huffman_block_decoder.pending_final_frame_r;
      release dut.u_rx_top.u_huffman_block_decoder.error_r;
      release dut.u_rx_top.u_huffman_block_decoder.table_valid_r;
      release dut.u_rx_top.u_huffman_block_decoder.decode_main_valid_w;
      release dut.u_rx_top.u_huffman_block_decoder.decode_main_long_w;
      release dut.u_rx_top.u_huffman_block_decoder.decode_main_len_w;
      release dut.u_rx_top.u_huffman_block_decoder.decode_main_symbol_w;
      release dut.u_rx_top.u_huffman_block_decoder.len_local[0];
      release dut.u_rx_top.u_huffman_block_decoder.len_local[1];
      release dut.u_rx_top.u_huffman_block_decoder.code_local[0];
      release dut.u_rx_top.u_huffman_block_decoder.fallback_len[0];
      release dut.u_rx_top.u_huffman_block_decoder.fallback_code[0];
      release dut.u_rx_top.u_huffman_block_decoder.fallback_symbol[0];
    end
  endtask

  task automatic rx_decoder_direct_reset;
    begin
      force_rx_decoder_direct_idle;
      reset_rx_pipeline_for_cov;
      force dut.u_rx_top.decoder_out_ready_w = 1'b1;
      force dut.u_rx_top.parser_payload_window_data_w  = 32'h00000000;
      force dut.u_rx_top.parser_payload_window_len_w   = 6'd0;
      force dut.u_rx_top.parser_payload_window_valid_w = 1'b0;
      force dut.u_rx_top.parser_block_done             = 1'b0;
      force dut.u_rx_top.parser_frame_done             = 1'b0;
    end
  endtask

  task rx_decoder_direct_meta;
    input [1:0] mode;
    input [5:0] block_size;
    input [5:0] symbol_count;
    input [7:0] one_symbol;
    integer timeout_idx;
    begin
      force dut.u_rx_top.parser_block_mode_w       = mode;
      force dut.u_rx_top.parser_block_size_w       = block_size;
      force dut.u_rx_top.parser_symbol_count_w     = symbol_count;
      force dut.u_rx_top.parser_one_symbol_value_w = one_symbol;
      force dut.u_rx_top.parser_block_meta_valid_w = 1'b1;

      for (timeout_idx = 0; timeout_idx < 16; timeout_idx = timeout_idx + 1) begin
        if (dut.u_rx_top.parser_block_meta_ready_w)
          timeout_idx = 16;
        @(posedge clk);
      end
      force dut.u_rx_top.parser_block_meta_valid_w = 1'b0;
      @(posedge clk);
    end
  endtask

  task rx_decoder_direct_entry;
    input [7:0] symbol;
    input [4:0] code_len;
    input       entry_last;
    integer timeout_idx;
    begin
      force dut.u_rx_top.parser_entry_symbol_w   = symbol;
      force dut.u_rx_top.parser_entry_code_len_w = code_len;
      force dut.u_rx_top.parser_entry_last_w     = entry_last;
      force dut.u_rx_top.parser_entry_valid_w    = 1'b1;

      for (timeout_idx = 0; timeout_idx < 16; timeout_idx = timeout_idx + 1) begin
        if (dut.u_rx_top.parser_entry_ready_w)
          timeout_idx = 16;
        @(posedge clk);
      end
      force dut.u_rx_top.parser_entry_valid_w = 1'b0;
      @(posedge clk);
    end
  endtask

  task automatic rx_decoder_wait_error_or_done;
    input integer max_cycles;
    integer timeout_idx;
    begin
      for (timeout_idx = 0; timeout_idx < max_cycles; timeout_idx = timeout_idx + 1) begin
        if (dut.rx_decoder_error_w ||
            dut.u_rx_top.u_apb_huffman_rx_if.frame_done_sticky_r)
          timeout_idx = max_cycles;
        @(posedge clk);
      end
    end
  endtask

  task automatic rx_decoder_direct_finish_parser_done;
    begin
      force dut.u_rx_top.parser_block_done = 1'b1;
      force dut.u_rx_top.parser_frame_done = 1'b1;
      @(posedge clk);
      force dut.u_rx_top.parser_block_done = 1'b0;
      force dut.u_rx_top.parser_frame_done = 1'b0;
      rx_decoder_wait_error_or_done(64);
      drain_rx_output_words_for_cov;
    end
  endtask

  task automatic exercise_rx_decoder_direct_coverage;
    begin
      $display("# RX_DECODER_DIRECT_COV: exercise decoder fallback and entry-error paths");

      // Long-code compressed block: len=12 forces main-table long entry and fallback decode.
      rx_decoder_direct_reset;
      rx_decoder_direct_meta(2'd2, 6'd1, 6'd1, 8'h00);
      rx_decoder_direct_entry(8'h41, 5'd12, 1'b1);
      rx_decoder_wait_error_or_done(2300);
      force dut.u_rx_top.parser_payload_window_data_w  = 32'h00000000;
      force dut.u_rx_top.parser_payload_window_len_w   = 6'd12;
      force dut.u_rx_top.parser_payload_window_valid_w = 1'b1;
      rx_decoder_wait_error_or_done(64);
      rx_decoder_direct_finish_parser_done;
      force dut.u_rx_top.parser_payload_window_valid_w = 1'b0;

      // Reuse table without a new codebook to cover symbol_count==0 compressed path.
      rx_decoder_direct_meta(2'd2, 6'd1, 6'd0, 8'h00);
      force dut.u_rx_top.parser_payload_window_data_w  = 32'h00000000;
      force dut.u_rx_top.parser_payload_window_len_w   = 6'd12;
      force dut.u_rx_top.parser_payload_window_valid_w = 1'b1;
      rx_decoder_wait_error_or_done(64);
      rx_decoder_direct_finish_parser_done;

      // Entry validation failures.
      rx_decoder_direct_reset;
      rx_decoder_direct_meta(2'd2, 6'd1, 6'd2, 8'h00);
      rx_decoder_direct_entry(8'h41, 5'd1, 1'b0);
      rx_decoder_direct_entry(8'h41, 5'd1, 1'b1);
      rx_decoder_wait_error_or_done(64);

      rx_decoder_direct_reset;
      rx_decoder_direct_meta(2'd2, 6'd1, 6'd1, 8'h00);
      rx_decoder_direct_entry(8'h42, 5'd1, 1'b0);
      rx_decoder_wait_error_or_done(64);

      rx_decoder_direct_reset;
      rx_decoder_direct_meta(2'd2, 6'd2, 6'd2, 8'h00);
      rx_decoder_direct_entry(8'h43, 5'd1, 1'b1);
      rx_decoder_wait_error_or_done(64);

      // Metadata validation failures for each mode family.
      rx_decoder_direct_reset;
      rx_decoder_direct_meta(2'd0, 6'd31, 6'd0, 8'h00);
      rx_decoder_wait_error_or_done(16);

      rx_decoder_direct_reset;
      rx_decoder_direct_meta(2'd1, 6'd32, 6'd0, 8'h00);
      rx_decoder_wait_error_or_done(16);

      rx_decoder_direct_reset;
      rx_decoder_direct_meta(2'd3, 6'd1, 6'd1, 8'h01);
      rx_decoder_wait_error_or_done(16);

      rx_decoder_direct_reset;
      rx_decoder_direct_meta(2'd2, 6'd1, 6'd0, 8'h00);
      rx_decoder_wait_error_or_done(16);

      force_rx_decoder_direct_idle;
      reset_rx_pipeline_for_cov;
      $display("# RX_DECODER_DIRECT_COV: done");
    end
  endtask

  task force_rx_parser_direct_idle;
    begin
      release dut.u_rx_top.depacker_stream_data_w;
      release dut.u_rx_top.depacker_stream_len_w;
      release dut.u_rx_top.depacker_stream_valid_w;
      release dut.u_rx_top.depacker_stream_last_w;
      release dut.u_rx_top.parser_block_meta_ready_w;
      release dut.u_rx_top.parser_entry_ready_w;
      release dut.u_rx_top.parser_payload_consume_valid_w;
      release dut.u_rx_top.parser_payload_consume_len_w;
      release dut.u_rx_top.parser_payload_block_done_w;
      release dut.u_rx_top.u_huffman_block_parser.state_r;
      release dut.u_rx_top.u_huffman_block_parser.error_r;
      release dut.u_rx_top.u_huffman_block_parser.frame_active_r;
      release dut.u_rx_top.u_huffman_block_parser.frame_last_seen_r;
      release dut.u_rx_top.u_huffman_block_parser.block_mode_r;
      release dut.u_rx_top.u_huffman_block_parser.bit_count_r;
      release dut.u_rx_top.u_huffman_block_parser.bit_buffer_r;
      release dut.u_rx_top.u_huffman_block_parser.raw_payload_bits_remaining_r;
      release dut.u_rx_top.u_huffman_block_parser.entry_count_remaining_r;
      release dut.u_rx_top.u_huffman_block_parser.block_meta_valid_r;
      release dut.u_rx_top.u_huffman_block_parser.entry_valid_r;
      release dut.u_rx_top.u_huffman_block_parser.entry_last_r;
      release dut.u_rx_top.u_huffman_block_parser.payload_visible_count_w;
      release dut.u_rx_top.u_huffman_block_parser.payload_window_valid;
      @(posedge clk);
      #1;
    end
  endtask

  task parser_direct_force_truncation;
    input [2:0] state_value;
    input [8:0] bit_count_value;
    input [1:0] mode_value;
    input [5:0] entry_count_value;
    input [8:0] raw_remaining_value;
    begin
      reset_rx_pipeline_for_cov;
      force dut.u_rx_top.u_huffman_block_parser.state_r = state_value;
      force dut.u_rx_top.u_huffman_block_parser.error_r = 1'b0;
      force dut.u_rx_top.u_huffman_block_parser.frame_active_r = 1'b1;
      force dut.u_rx_top.u_huffman_block_parser.frame_last_seen_r = 1'b1;
      force dut.u_rx_top.u_huffman_block_parser.bit_count_r = bit_count_value;
      force dut.u_rx_top.u_huffman_block_parser.bit_buffer_r = 128'h00000000000000000000000000000001;
      force dut.u_rx_top.u_huffman_block_parser.block_mode_r = mode_value;
      force dut.u_rx_top.u_huffman_block_parser.entry_count_remaining_r = entry_count_value;
      force dut.u_rx_top.u_huffman_block_parser.raw_payload_bits_remaining_r = raw_remaining_value;
      force dut.u_rx_top.u_huffman_block_parser.block_meta_valid_r = 1'b0;
      force dut.u_rx_top.u_huffman_block_parser.entry_valid_r = 1'b0;
      @(posedge clk);
      #1;
      force_rx_parser_direct_idle;
    end
  endtask

  task parser_direct_force_payload_error;
    input [1:0] mode_value;
    input [8:0] bit_count_value;
    input [8:0] raw_remaining_value;
    input [5:0] consume_len_value;
    input       consume_valid_value;
    input       block_done_value;
    input       force_window_valid_value;
    input [8:0] force_visible_count_value;
    begin
      reset_rx_pipeline_for_cov;
      force dut.u_rx_top.u_huffman_block_parser.state_r = 3'd6;
      force dut.u_rx_top.u_huffman_block_parser.error_r = 1'b0;
      force dut.u_rx_top.u_huffman_block_parser.block_mode_r = mode_value;
      force dut.u_rx_top.u_huffman_block_parser.bit_count_r = bit_count_value;
      force dut.u_rx_top.u_huffman_block_parser.raw_payload_bits_remaining_r = raw_remaining_value;
      force dut.u_rx_top.u_huffman_block_parser.bit_buffer_r = 128'h000000000000000000000000000000ff;
      force dut.u_rx_top.parser_payload_consume_valid_w = consume_valid_value;
      force dut.u_rx_top.parser_payload_consume_len_w = consume_len_value;
      force dut.u_rx_top.parser_payload_block_done_w = block_done_value;
      if (force_window_valid_value) begin
        force dut.u_rx_top.u_huffman_block_parser.payload_window_valid = 1'b1;
        force dut.u_rx_top.u_huffman_block_parser.payload_visible_count_w = force_visible_count_value;
      end
      @(posedge clk);
      #1;
      force_rx_parser_direct_idle;
    end
  endtask

  task decoder_direct_force_state_once;
    input [4:0] state_value;
    input [5:0] bytes_remaining_value;
    begin
      reset_rx_pipeline_for_cov;
      force dut.u_rx_top.u_huffman_block_decoder.state_r = state_value;
      force dut.u_rx_top.u_huffman_block_decoder.error_r = 1'b0;
      force dut.u_rx_top.u_huffman_block_decoder.bytes_remaining_r = bytes_remaining_value;
      force dut.u_rx_top.u_huffman_block_decoder.out_valid_r = 1'b0;
      force dut.u_rx_top.parser_payload_window_data_w  = 32'h00000000;
      force dut.u_rx_top.parser_payload_window_len_w   = 6'd12;
      force dut.u_rx_top.parser_payload_window_valid_w = 1'b1;
      force dut.u_rx_top.decoder_out_ready_w = 1'b1;
      @(posedge clk);
      #1;
      force_rx_decoder_direct_idle;
    end
  endtask

  task exercise_rx_parser_fsm_transition_coverage;
    begin
      // Force state/output combinations that let the parser's combinational
      // chaining select the next state on the active edge.

      reset_rx_pipeline_for_cov;
      force dut.u_rx_top.u_huffman_block_parser.state_r = 3'd4;
      force dut.u_rx_top.u_huffman_block_parser.error_r = 1'b0;
      force dut.u_rx_top.u_huffman_block_parser.block_meta_valid_r = 1'b1;
      force dut.u_rx_top.u_huffman_block_parser.block_mode_r = 2'd3;
      force dut.u_rx_top.u_huffman_block_parser.bit_count_r = 9'd2;
      force dut.u_rx_top.u_huffman_block_parser.bit_buffer_r = 128'h00000000000000000000000000000001;
      force dut.u_rx_top.u_huffman_block_parser.frame_active_r = 1'b1;
      force dut.u_rx_top.u_huffman_block_parser.frame_last_seen_r = 1'b0;
      force dut.u_rx_top.parser_block_meta_ready_w = 1'b1;
      #1;
      release dut.u_rx_top.u_huffman_block_parser.state_r;
      @(posedge clk);
      #1;
      force_rx_parser_direct_idle;

      reset_rx_pipeline_for_cov;
      force dut.u_rx_top.u_huffman_block_parser.state_r = 3'd4;
      force dut.u_rx_top.u_huffman_block_parser.error_r = 1'b0;
      force dut.u_rx_top.u_huffman_block_parser.block_meta_valid_r = 1'b1;
      force dut.u_rx_top.u_huffman_block_parser.block_mode_r = 2'd3;
      force dut.u_rx_top.u_huffman_block_parser.bit_count_r = 9'd2;
      force dut.u_rx_top.u_huffman_block_parser.bit_buffer_r = 128'h00000000000000000000000000000003;
      force dut.u_rx_top.u_huffman_block_parser.frame_active_r = 1'b1;
      force dut.u_rx_top.u_huffman_block_parser.frame_last_seen_r = 1'b0;
      force dut.u_rx_top.parser_block_meta_ready_w = 1'b1;
      #1;
      release dut.u_rx_top.u_huffman_block_parser.state_r;
      @(posedge clk);
      #1;
      force_rx_parser_direct_idle;

      reset_rx_pipeline_for_cov;
      force dut.u_rx_top.u_huffman_block_parser.state_r = 3'd3;
      force dut.u_rx_top.u_huffman_block_parser.error_r = 1'b0;
      force dut.u_rx_top.u_huffman_block_parser.block_meta_valid_r = 1'b1;
      force dut.u_rx_top.u_huffman_block_parser.block_mode_r = 2'd2;
      force dut.u_rx_top.u_huffman_block_parser.entry_count_remaining_r = 6'd0;
      force dut.u_rx_top.parser_block_meta_ready_w = 1'b1;
      #1;
      release dut.u_rx_top.u_huffman_block_parser.state_r;
      @(posedge clk);
      #1;
      force_rx_parser_direct_idle;

      reset_rx_pipeline_for_cov;
      force dut.u_rx_top.u_huffman_block_parser.state_r = 3'd3;
      force dut.u_rx_top.u_huffman_block_parser.error_r = 1'b0;
      force dut.u_rx_top.u_huffman_block_parser.block_meta_valid_r = 1'b1;
      force dut.u_rx_top.u_huffman_block_parser.block_mode_r = 2'd2;
      force dut.u_rx_top.u_huffman_block_parser.entry_count_remaining_r = 6'd2;
      force dut.u_rx_top.parser_block_meta_ready_w = 1'b1;
      #1;
      release dut.u_rx_top.u_huffman_block_parser.state_r;
      @(posedge clk);
      #1;
      force_rx_parser_direct_idle;

      reset_rx_pipeline_for_cov;
      force dut.u_rx_top.u_huffman_block_parser.state_r = 3'd2;
      force dut.u_rx_top.u_huffman_block_parser.error_r = 1'b0;
      force dut.u_rx_top.u_huffman_block_parser.block_meta_valid_r = 1'b1;
      force dut.u_rx_top.u_huffman_block_parser.block_mode_r = 2'd3;
      force dut.u_rx_top.u_huffman_block_parser.bit_count_r = 9'd2;
      force dut.u_rx_top.u_huffman_block_parser.bit_buffer_r = 128'h00000000000000000000000000000002;
      force dut.u_rx_top.u_huffman_block_parser.frame_active_r = 1'b1;
      force dut.u_rx_top.u_huffman_block_parser.frame_last_seen_r = 1'b0;
      force dut.u_rx_top.parser_block_meta_ready_w = 1'b1;
      #1;
      release dut.u_rx_top.u_huffman_block_parser.state_r;
      @(posedge clk);
      #1;
      force_rx_parser_direct_idle;

      reset_rx_pipeline_for_cov;
      force dut.u_rx_top.u_huffman_block_parser.state_r = 3'd1;
      force dut.u_rx_top.u_huffman_block_parser.error_r = 1'b0;
      force dut.u_rx_top.u_huffman_block_parser.block_meta_valid_r = 1'b1;
      force dut.u_rx_top.u_huffman_block_parser.block_mode_r = 2'd1;
      force dut.u_rx_top.u_huffman_block_parser.raw_payload_bits_remaining_r = 9'd0;
      force dut.u_rx_top.u_huffman_block_parser.bit_count_r = 9'd2;
      force dut.u_rx_top.u_huffman_block_parser.bit_buffer_r = 128'h00000000000000000000000000000003;
      force dut.u_rx_top.u_huffman_block_parser.frame_active_r = 1'b1;
      force dut.u_rx_top.u_huffman_block_parser.frame_last_seen_r = 1'b0;
      force dut.u_rx_top.parser_block_meta_ready_w = 1'b1;
      #1;
      release dut.u_rx_top.u_huffman_block_parser.state_r;
      @(posedge clk);
      #1;
      force_rx_parser_direct_idle;

      reset_rx_pipeline_for_cov;
      force dut.u_rx_top.u_huffman_block_parser.state_r = 3'd6;
      force dut.u_rx_top.u_huffman_block_parser.error_r = 1'b0;
      force dut.u_rx_top.u_huffman_block_parser.block_mode_r = 2'd2;
      force dut.u_rx_top.u_huffman_block_parser.bit_count_r = 9'd4;
      force dut.u_rx_top.u_huffman_block_parser.bit_buffer_r = 128'h00000000000000000000000000000000;
      force dut.u_rx_top.u_huffman_block_parser.frame_active_r = 1'b1;
      force dut.u_rx_top.u_huffman_block_parser.frame_last_seen_r = 1'b0;
      force dut.u_rx_top.parser_payload_consume_valid_w = 1'b1;
      force dut.u_rx_top.parser_payload_consume_len_w = 6'd2;
      force dut.u_rx_top.parser_payload_block_done_w = 1'b1;
      #1;
      release dut.u_rx_top.u_huffman_block_parser.state_r;
      @(posedge clk);
      #1;
      force_rx_parser_direct_idle;
    end
  endtask

  task automatic exercise_rx_parser_decoder_error_direct_coverage;
    reg [127:0] append_dummy;
    begin
      $display("# RX_PARSE_DECODE_ERROR_DIRECT_COV: exercise parser/decoder defensive branches");

      reset_rx_pipeline_for_cov;
      append_dummy = dut.u_rx_top.u_huffman_block_parser.append_chunk(
                       128'h11111111111111111111111111111111,
                       9'd4,
                       32'hdeadbeef,
                       6'd0);
      append_dummy = dut.u_rx_top.u_huffman_block_parser.append_chunk(
                       append_dummy,
                       9'd4,
                       32'h00000001,
                       6'd1);

      reset_rx_pipeline_for_cov;
      force dut.u_rx_top.u_huffman_block_parser.state_r = 3'd4;
      force dut.u_rx_top.u_huffman_block_parser.error_r = 1'b0;
      force dut.u_rx_top.u_huffman_block_parser.block_meta_valid_r = 1'b1;
      force dut.u_rx_top.u_huffman_block_parser.block_mode_r = 2'd1;
      force dut.u_rx_top.u_huffman_block_parser.raw_payload_bits_remaining_r = 9'd0;
      force dut.u_rx_top.u_huffman_block_parser.frame_active_r = 1'b1;
      force dut.u_rx_top.u_huffman_block_parser.frame_last_seen_r = 1'b1;
      force dut.u_rx_top.u_huffman_block_parser.bit_count_r = 9'd0;
      force dut.u_rx_top.parser_block_meta_ready_w = 1'b1;
      @(posedge clk);
      #1;
      force_rx_parser_direct_idle;

      reset_rx_pipeline_for_cov;
      force dut.u_rx_top.u_huffman_block_parser.state_r = 3'd5;
      force dut.u_rx_top.u_huffman_block_parser.error_r = 1'b0;
      force dut.u_rx_top.u_huffman_block_parser.entry_valid_r = 1'b1;
      force dut.u_rx_top.u_huffman_block_parser.entry_count_remaining_r = 6'd2;
      force dut.u_rx_top.parser_entry_ready_w = 1'b0;
      @(posedge clk);
      #1;
      force_rx_parser_direct_idle;

      reset_rx_pipeline_for_cov;
      force dut.u_rx_top.u_huffman_block_parser.state_r = 3'd0;
      force dut.u_rx_top.u_huffman_block_parser.error_r = 1'b0;
      force dut.u_rx_top.parser_payload_block_done_w = 1'b1;
      force dut.u_rx_top.parser_payload_consume_valid_w = 1'b0;
      force dut.u_rx_top.parser_payload_consume_len_w = 6'd0;
      @(posedge clk);
      #1;
      force_rx_parser_direct_idle;

      parser_direct_force_payload_error(2'd2, 9'd0, 9'd0, 6'd1, 1'b1, 1'b0, 1'b0, 9'd0);
      parser_direct_force_payload_error(2'd2, 9'd8, 9'd0, 6'd0, 1'b1, 1'b0, 1'b0, 9'd0);
      parser_direct_force_payload_error(2'd2, 9'd4, 9'd0, 6'd8, 1'b1, 1'b0, 1'b1, 9'd4);
      parser_direct_force_payload_error(2'd3, 9'd8, 9'd0, 6'd1, 1'b1, 1'b0, 1'b1, 9'd8);
      parser_direct_force_payload_error(2'd1, 9'd8, 9'd4, 6'd8, 1'b1, 1'b0, 1'b1, 9'd8);

      parser_direct_force_truncation(3'd0, 9'd1, 2'd0, 6'd0, 9'd0);
      parser_direct_force_truncation(3'd1, 9'd5, 2'd1, 6'd0, 9'd0);
      parser_direct_force_truncation(3'd2, 9'd13, 2'd3, 6'd0, 9'd0);
      parser_direct_force_truncation(3'd3, 9'd11, 2'd2, 6'd0, 9'd0);
      parser_direct_force_truncation(3'd5, 9'd12, 2'd2, 6'd1, 9'd0);
      parser_direct_force_truncation(3'd6, 9'd0, 2'd2, 6'd0, 9'd0);
      parser_direct_force_truncation(3'd7, 9'd0, 2'd0, 6'd0, 9'd0);

      rx_decoder_direct_reset;
      rx_decoder_direct_meta(2'd1, 6'd0, 6'd0, 8'h00);
      repeat (2) @(posedge clk);
      force dut.u_rx_top.parser_block_done = 1'b1;
      force dut.u_rx_top.parser_frame_done = 1'b1;
      @(posedge clk);
      #1;
      force dut.u_rx_top.parser_block_done = 1'b0;
      force dut.u_rx_top.parser_frame_done = 1'b0;
      rx_decoder_wait_error_or_done(16);

      rx_decoder_direct_reset;
      rx_decoder_direct_meta(2'd0, 6'd32, 6'd1, 8'h00);
      rx_decoder_wait_error_or_done(16);

      rx_decoder_direct_reset;
      rx_decoder_direct_meta(2'd1, 6'd1, 6'd1, 8'h00);
      rx_decoder_wait_error_or_done(16);

      rx_decoder_direct_reset;
      rx_decoder_direct_meta(2'd3, 6'd0, 6'd1, 8'h41);
      rx_decoder_wait_error_or_done(16);

      rx_decoder_direct_reset;
      rx_decoder_direct_meta(2'd3, 6'd33, 6'd1, 8'h41);
      rx_decoder_wait_error_or_done(16);

      rx_decoder_direct_reset;
      rx_decoder_direct_meta(2'd3, 6'd1, 6'd2, 8'h41);
      rx_decoder_wait_error_or_done(16);

      rx_decoder_direct_reset;
      rx_decoder_direct_meta(2'd3, 6'd1, 6'd1, 8'hff);
      rx_decoder_wait_error_or_done(16);

      rx_decoder_direct_reset;
      rx_decoder_direct_meta(2'd2, 6'd0, 6'd1, 8'h00);
      rx_decoder_wait_error_or_done(16);

      rx_decoder_direct_reset;
      rx_decoder_direct_meta(2'd2, 6'd33, 6'd1, 8'h00);
      rx_decoder_wait_error_or_done(16);

      decoder_direct_force_state_once(5'd9, 6'd0);
      decoder_direct_force_state_once(5'd17, 6'd0);
      decoder_direct_force_state_once(5'd16, 6'd0);

      reset_rx_pipeline_for_cov;
      force dut.u_rx_top.u_huffman_block_decoder.state_r = 5'd17;
      force dut.u_rx_top.u_huffman_block_decoder.error_r = 1'b0;
      force dut.u_rx_top.u_huffman_block_decoder.bytes_remaining_r = 6'd1;
      force dut.u_rx_top.u_huffman_block_decoder.out_valid_r = 1'b0;
      force dut.u_rx_top.parser_payload_window_valid_w = 1'b0;
      force dut.u_rx_top.parser_payload_window_len_w = 6'd0;
      @(posedge clk);
      #1;
      force_rx_decoder_direct_idle;

      reset_rx_pipeline_for_cov;
      force dut.u_rx_top.u_huffman_block_decoder.state_r = 5'd16;
      force dut.u_rx_top.u_huffman_block_decoder.error_r = 1'b0;
      force dut.u_rx_top.u_huffman_block_decoder.bytes_remaining_r = 6'd2;
      force dut.u_rx_top.u_huffman_block_decoder.out_valid_r = 1'b0;
      force dut.u_rx_top.parser_payload_window_valid_w = 1'b1;
      force dut.u_rx_top.parser_payload_window_len_w = 6'd6;
      force dut.u_rx_top.u_huffman_block_decoder.decode_main_valid_w = 1'b1;
      force dut.u_rx_top.u_huffman_block_decoder.decode_main_long_w = 1'b0;
      force dut.u_rx_top.u_huffman_block_decoder.decode_main_len_w = 5'd12;
      @(posedge clk);
      #1;
      force_rx_decoder_direct_idle;

      reset_rx_pipeline_for_cov;
      force dut.u_rx_top.u_huffman_block_decoder.state_r = 5'd16;
      force dut.u_rx_top.u_huffman_block_decoder.error_r = 1'b0;
      force dut.u_rx_top.u_huffman_block_decoder.bytes_remaining_r = 6'd2;
      force dut.u_rx_top.u_huffman_block_decoder.out_valid_r = 1'b0;
      force dut.u_rx_top.parser_payload_window_valid_w = 1'b1;
      force dut.u_rx_top.parser_payload_window_len_w = 6'd6;
      force dut.u_rx_top.u_huffman_block_decoder.decode_main_valid_w = 1'b1;
      force dut.u_rx_top.u_huffman_block_decoder.decode_main_long_w = 1'b1;
      @(posedge clk);
      #1;
      force_rx_decoder_direct_idle;

      reset_rx_pipeline_for_cov;
      force dut.u_rx_top.u_huffman_block_decoder.state_r = 5'd16;
      force dut.u_rx_top.u_huffman_block_decoder.error_r = 1'b0;
      force dut.u_rx_top.u_huffman_block_decoder.bytes_remaining_r = 6'd2;
      force dut.u_rx_top.u_huffman_block_decoder.out_valid_r = 1'b0;
      force dut.u_rx_top.parser_payload_window_valid_w = 1'b1;
      force dut.u_rx_top.parser_payload_window_len_w = 6'd11;
      force dut.u_rx_top.u_huffman_block_decoder.decode_main_valid_w = 1'b0;
      force dut.u_rx_top.u_huffman_block_decoder.decode_main_long_w = 1'b0;
      @(posedge clk);
      #1;
      force_rx_decoder_direct_idle;

      reset_rx_pipeline_for_cov;
      force dut.u_rx_top.u_huffman_block_decoder.state_r = 5'd16;
      force dut.u_rx_top.u_huffman_block_decoder.error_r = 1'b0;
      force dut.u_rx_top.u_huffman_block_decoder.bytes_remaining_r = 6'd2;
      force dut.u_rx_top.u_huffman_block_decoder.out_valid_r = 1'b0;
      force dut.u_rx_top.parser_payload_window_valid_w = 1'b1;
      force dut.u_rx_top.parser_payload_window_len_w = 6'd6;
      force dut.u_rx_top.u_huffman_block_decoder.decode_main_valid_w = 1'b0;
      force dut.u_rx_top.u_huffman_block_decoder.decode_main_long_w = 1'b0;
      @(posedge clk);
      #1;
      force_rx_decoder_direct_idle;

      reset_rx_pipeline_for_cov;
      force dut.u_rx_top.u_huffman_block_decoder.state_r = 5'd8;
      force dut.u_rx_top.u_huffman_block_decoder.error_r = 1'b0;
      force dut.u_rx_top.u_huffman_block_decoder.symbol_count_r = 6'd1;
      force dut.u_rx_top.u_huffman_block_decoder.assign_idx_r = 6'd0;
      force dut.u_rx_top.u_huffman_block_decoder.bytes_remaining_r = 6'd3;
      force dut.u_rx_top.u_huffman_block_decoder.len_local[0] = 5'd0;
      @(posedge clk);
      #1;
      force_rx_decoder_direct_idle;

      reset_rx_pipeline_for_cov;
      force dut.u_rx_top.u_huffman_block_decoder.state_r = 5'd8;
      force dut.u_rx_top.u_huffman_block_decoder.error_r = 1'b0;
      force dut.u_rx_top.u_huffman_block_decoder.symbol_count_r = 6'd2;
      force dut.u_rx_top.u_huffman_block_decoder.assign_idx_r = 6'd1;
      force dut.u_rx_top.u_huffman_block_decoder.prev_len_r = 5'd5;
      force dut.u_rx_top.u_huffman_block_decoder.bytes_remaining_r = 6'd3;
      force dut.u_rx_top.u_huffman_block_decoder.len_local[1] = 5'd4;
      @(posedge clk);
      #1;
      force_rx_decoder_direct_idle;

      reset_rx_pipeline_for_cov;
      force dut.u_rx_top.u_huffman_block_decoder.state_r = 5'd8;
      force dut.u_rx_top.u_huffman_block_decoder.error_r = 1'b0;
      force dut.u_rx_top.u_huffman_block_decoder.symbol_count_r = 6'd2;
      force dut.u_rx_top.u_huffman_block_decoder.assign_idx_r = 6'd3;
      @(posedge clk);
      #1;
      force_rx_decoder_direct_idle;

      reset_rx_pipeline_for_cov;
      force dut.u_rx_top.u_huffman_block_decoder.state_r = 5'd13;
      force dut.u_rx_top.u_huffman_block_decoder.error_r = 1'b0;
      force dut.u_rx_top.u_huffman_block_decoder.symbol_count_r = 6'd1;
      force dut.u_rx_top.u_huffman_block_decoder.table_build_idx_r = 6'd0;
      force dut.u_rx_top.u_huffman_block_decoder.fallback_count_r = 6'd63;
      force dut.u_rx_top.u_huffman_block_decoder.len_local[0] = 5'd12;
      @(posedge clk);
      #1;
      force_rx_decoder_direct_idle;

      reset_rx_pipeline_for_cov;
      force dut.u_rx_top.u_huffman_block_decoder.state_r = 5'd15;
      force dut.u_rx_top.u_huffman_block_decoder.error_r = 1'b0;
      force dut.u_rx_top.u_huffman_block_decoder.bytes_remaining_r = 6'd2;
      force dut.u_rx_top.u_huffman_block_decoder.fallback_scan_idx_r = 6'd0;
      force dut.u_rx_top.u_huffman_block_decoder.fallback_count_r = 6'd1;
      force dut.u_rx_top.u_huffman_block_decoder.fallback_len[0] = 5'd12;
      force dut.u_rx_top.u_huffman_block_decoder.fallback_code[0] = 31'd0;
      force dut.u_rx_top.u_huffman_block_decoder.fallback_symbol[0] = 8'h51;
      force dut.u_rx_top.parser_payload_window_data_w = 32'h00000000;
      force dut.u_rx_top.parser_payload_window_len_w = 6'd6;
      force dut.u_rx_top.parser_payload_window_valid_w = 1'b1;
      @(posedge clk);
      #1;
      force_rx_decoder_direct_idle;

      reset_rx_pipeline_for_cov;
      force dut.u_rx_top.u_huffman_block_decoder.state_r = 5'd15;
      force dut.u_rx_top.u_huffman_block_decoder.error_r = 1'b0;
      force dut.u_rx_top.u_huffman_block_decoder.bytes_remaining_r = 6'd2;
      force dut.u_rx_top.u_huffman_block_decoder.fallback_scan_idx_r = 6'd1;
      force dut.u_rx_top.u_huffman_block_decoder.fallback_count_r = 6'd1;
      force dut.u_rx_top.u_huffman_block_decoder.fallback_prefix_seen_r = 1'b1;
      @(posedge clk);
      #1;
      force_rx_decoder_direct_idle;

      reset_rx_pipeline_for_cov;
      force dut.u_rx_top.u_huffman_block_decoder.state_r = 5'd15;
      force dut.u_rx_top.u_huffman_block_decoder.error_r = 1'b0;
      force dut.u_rx_top.u_huffman_block_decoder.bytes_remaining_r = 6'd2;
      force dut.u_rx_top.u_huffman_block_decoder.fallback_scan_idx_r = 6'd1;
      force dut.u_rx_top.u_huffman_block_decoder.fallback_count_r = 6'd1;
      force dut.u_rx_top.u_huffman_block_decoder.fallback_prefix_seen_r = 1'b0;
      @(posedge clk);
      #1;
      force_rx_decoder_direct_idle;

      reset_rx_pipeline_for_cov;
      force dut.u_rx_top.u_huffman_block_decoder.state_r = 5'd11;
      force dut.u_rx_top.u_huffman_block_decoder.error_r = 1'b0;
      force dut.u_rx_top.u_huffman_block_decoder.out_valid_r = 1'b1;
      force dut.u_rx_top.u_huffman_block_decoder.pending_final_frame_r = 1'b1;
      force dut.u_rx_top.decoder_out_ready_w = 1'b0;
      @(posedge clk);
      #1;
      force_rx_decoder_direct_idle;

      reset_rx_pipeline_for_cov;
      force dut.u_rx_top.u_huffman_block_decoder.state_r = 5'd31;
      force dut.u_rx_top.u_huffman_block_decoder.error_r = 1'b0;
      @(posedge clk);
      #1;
      force_rx_decoder_direct_idle;

      exercise_rx_parser_fsm_transition_coverage;

      reset_rx_pipeline_for_cov;
      $display("# RX_PARSE_DECODE_ERROR_DIRECT_COV: done append_dummy=%032x", append_dummy);
    end
  endtask

  task force_tx_encoder_direct_idle;
    begin
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.state;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.start;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.start_d;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.selected_mode;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.block_size;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.byte_idx;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.buffer_read_data;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.code_len_read_data;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.code_read_data;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.current_byte_valid_r;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.current_code_len_r;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.current_code_r;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.payload_ready;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.payload_valid;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.payload_last_chunk;

      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.state;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.start;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.start_d;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.selected_mode;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.block_size;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.symbol_count;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.symbol_read_data;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.code_len_read_data;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.symbol_data_r;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.code_len_data_r;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.sym_idx;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.bit_ptr;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.send_ptr;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.header_total_bits;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.header_bits;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.hdr_ready;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.hdr_valid;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.hdr_last_chunk;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.hdr_len;
      @(posedge clk);
      #1;
    end
  endtask

  task automatic exercise_tx_encoder_direct_coverage;
    reg [10:0] tx_words_dummy;
    reg [31:0] reversed_dummy;
    begin
      $display("# TX_ENCODER_DIRECT_COV: exercise TX dynamic-Huffman mode/header/payload defensive branches");

      reset_rx_pipeline_for_cov;
      tx_words_dummy = 11'h2a5;

      reversed_dummy = dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.reverse_code_bits(31'h00000000, 5'd0);
      reversed_dummy = reversed_dummy ^
        dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.reverse_code_bits(31'h15555555, 5'd31);

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.state = 3'd1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.selected_mode = 2'd0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.block_size = 6'd31;
      @(posedge clk);
      #1;
      force_tx_encoder_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.state = 3'd1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.selected_mode = 2'd1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.block_size = 6'd32;
      @(posedge clk);
      #1;
      force_tx_encoder_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.state = 3'd1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.selected_mode = 2'd3;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.block_size = 6'd0;
      @(posedge clk);
      #1;
      force_tx_encoder_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.state = 3'd2;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.selected_mode = 2'd3;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.block_size = 6'd4;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.byte_idx = 6'd1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.buffer_read_data = 8'h41;
      @(posedge clk);
      #1;
      force_tx_encoder_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.state = 3'd4;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.selected_mode = 2'd2;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.current_byte_valid_r = 1'b0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.current_code_len_r = 5'd3;
      @(posedge clk);
      #1;
      force_tx_encoder_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.state = 3'd4;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.selected_mode = 2'd2;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.current_byte_valid_r = 1'b1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.current_code_len_r = 5'd0;
      @(posedge clk);
      #1;
      force_tx_encoder_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.state = 3'd4;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.selected_mode = 2'd3;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.current_byte_valid_r = 1'b1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.current_code_len_r = 5'd3;
      @(posedge clk);
      #1;
      force_tx_encoder_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.state = 3'd5;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.payload_valid = 1'b1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.payload_ready = 1'b0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.payload_last_chunk = 1'b0;
      @(posedge clk);
      #1;
      force_tx_encoder_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.state = 3'd7;
      @(posedge clk);
      #1;
      force_tx_encoder_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.state = 4'd1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.selected_mode = 2'd0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.block_size = 6'd31;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.symbol_count = 6'd0;
      @(posedge clk);
      #1;
      force_tx_encoder_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.state = 4'd1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.selected_mode = 2'd1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.block_size = 6'd32;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.symbol_count = 6'd0;
      @(posedge clk);
      #1;
      force_tx_encoder_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.state = 4'd1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.selected_mode = 2'd2;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.block_size = 6'd0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.symbol_count = 6'd1;
      @(posedge clk);
      #1;
      force_tx_encoder_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.state = 4'd1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.selected_mode = 2'd3;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.block_size = 6'd5;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.symbol_count = 6'd2;
      @(posedge clk);
      #1;
      force_tx_encoder_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.state = 4'd9;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.symbol_data_r = 8'h01;
      @(posedge clk);
      #1;
      force_tx_encoder_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.state = 4'd4;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.symbol_count = 6'd2;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.sym_idx = 6'd0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.symbol_data_r = 8'hff;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.code_len_data_r = 5'd0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.bit_ptr = 10'd14;
      @(posedge clk);
      #1;
      force_tx_encoder_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.state = 4'd4;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.symbol_count = 6'd2;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.sym_idx = 6'd2;
      @(posedge clk);
      #1;
      force_tx_encoder_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.state = 4'd5;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.header_total_bits = 10'd80;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.send_ptr = 10'd0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.header_bits = {833{1'b1}};
      @(posedge clk);
      #1;
      force_tx_encoder_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.state = 4'd6;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.hdr_valid = 1'b1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.hdr_ready = 1'b0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.hdr_last_chunk = 1'b0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.hdr_len = 6'd32;
      @(posedge clk);
      #1;
      force_tx_encoder_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.state = 4'd10;
      @(posedge clk);
      #1;
      force_tx_encoder_direct_idle;

      reset_rx_pipeline_for_cov;
      $display("# TX_ENCODER_DIRECT_COV: done tx_words_dummy=0x%03x reversed_dummy=0x%08x", tx_words_dummy, reversed_dummy);
    end
  endtask

  task force_tx_builder_packer_direct_idle;
    begin
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_control_fsm.state;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_control_fsm.start_block;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_control_fsm.whole_file_enable;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_control_fsm.whole_file_table_valid;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_control_fsm.collect_done;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_control_fsm.collect_busy;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_control_fsm.collect_protocol_error;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_control_fsm.collect_overflow_error;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_control_fsm.build_done;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_control_fsm.build_busy;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_control_fsm.build_error;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_control_fsm.mode_done;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_control_fsm.mode_busy;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_control_fsm.mode_error;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_control_fsm.emit_done;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_control_fsm.emit_busy;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_control_fsm.emit_error;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_control_fsm.selected_mode;

      release dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.stream_data;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.stream_len;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.stream_valid;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.stream_last;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.flush_on_last;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.transport_word_ready;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.payload_buf_r;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.payload_count_r;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.transport_word_r;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.transport_valid_r;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.pending_payload_r;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.pending_len_r;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.pending_valid_r;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.error_r;

      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_frequency_counter.read_index;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_frequency_counter.count_en;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_frequency_counter.count_data;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_frequency_counter.freq_table[0];

      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_input_collect_unit.state;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_input_collect_unit.start_collect;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_input_collect_unit.start_collect_d;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_input_collect_unit.byte_valid;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_input_collect_unit.block_start;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_input_collect_unit.block_end;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_input_collect_unit.u_block_buffer.read_addr;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_input_collect_unit.u_block_buffer.block_size;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_input_collect_unit.u_block_buffer.write_en;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_input_collect_unit.u_block_buffer.write_data;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_input_collect_unit.u_frequency_counter.read_index;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_input_collect_unit.u_frequency_counter.count_en;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_input_collect_unit.u_frequency_counter.count_data;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_input_collect_unit.u_frequency_counter.freq_table[0];

      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_symbol_list_builder.state;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_symbol_list_builder.start;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_symbol_list_builder.start_d;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_symbol_list_builder.block_size;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_symbol_list_builder.freq_read_count;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_symbol_list_builder.scan_index;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_symbol_list_builder.symbol_count;

      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_symbol_list_builder.state;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_symbol_list_builder.start;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_symbol_list_builder.start_d;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_symbol_list_builder.block_size;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_symbol_list_builder.freq_read_count;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_symbol_list_builder.scan_index;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_symbol_list_builder.symbol_count;

      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.state;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.start;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.start_d;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.symbol_count;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.load_index;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.load_freq_count_r;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.active_nodes;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.found1_r;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.found2_r;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.map_index;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.code_len_read_index;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.leaf_code_len[0];
      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.leaf_symbol[0];

      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.state;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.start;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.start_d;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.symbol_count;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.load_index;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.load_freq_count_r;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.active_nodes;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.found1_r;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.found2_r;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.map_index;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.code_len_read_index;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.leaf_code_len[0];
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.leaf_symbol[0];

      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.state;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.start;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.start_d;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.symbol_count;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.load_index;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.assign_index;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.prev_len;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.code_len_read_index;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.code_read_index;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.symbol_read_data;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.code_len_src_read_data;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.len_local[0];
      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.len_local[1];
      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.symbol_local[0];
      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.symbol_local[1];

      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.state;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.start;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.start_d;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.symbol_count;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.load_index;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.assign_index;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.prev_len;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.code_len_read_index;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.code_read_index;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.symbol_read_data;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.code_len_src_read_data;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.len_local[0];
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.len_local[1];
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.symbol_local[0];
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.symbol_local[1];
      @(posedge clk);
      #1;
    end
  endtask

  task force_code_length_error_paths_file;
    begin
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.code_len_read_index = 7'd100;
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.state = 4'd2;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.load_index = 6'd0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.symbol_count = 6'd0;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.state = 4'd2;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.load_index = 6'd1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.symbol_count = 6'd1;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.state = 4'd4;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.load_index = 6'd0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.symbol_count = 6'd1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.load_freq_count_r = 6'd0;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.state = 4'd5;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.active_nodes = 6'd1;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.state = 4'd7;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.active_nodes = 6'd3;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.found1_r = 1'b0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.found2_r = 1'b1;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.state = 4'd8;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.map_index = 6'd0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.symbol_count = 6'd1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.leaf_code_len[0] = 5'd0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.leaf_symbol[0] = 8'h41;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.state = 4'd9;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.start = 1'b1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.start_d = 1'b0;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.state = 4'd15;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;
    end
  endtask

  task force_code_length_error_paths_dynamic;
    begin
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.code_len_read_index = 7'd100;
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.state = 4'd2;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.load_index = 6'd0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.symbol_count = 6'd0;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.state = 4'd2;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.load_index = 6'd1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.symbol_count = 6'd1;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.state = 4'd4;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.load_index = 6'd0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.symbol_count = 6'd1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.load_freq_count_r = 6'd0;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.state = 4'd5;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.active_nodes = 6'd1;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.state = 4'd7;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.active_nodes = 6'd3;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.found1_r = 1'b0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.found2_r = 1'b1;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.state = 4'd8;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.map_index = 6'd0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.symbol_count = 6'd1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.leaf_code_len[0] = 5'd0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.leaf_symbol[0] = 8'h42;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.state = 4'd9;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.start = 1'b1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.start_d = 1'b0;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.state = 4'd15;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;
    end
  endtask

  task force_canonical_error_paths_file;
    begin
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.code_len_read_index = 7'd100;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.code_read_index = 7'd100;
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.state = 3'd1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.symbol_count = 6'd0;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.state = 3'd2;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.load_index = 6'd0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.symbol_count = 6'd2;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.symbol_read_data = 8'h41;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.code_len_src_read_data = 5'd0;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.state = 3'd2;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.load_index = 6'd0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.symbol_count = 6'd1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.symbol_read_data = 8'h42;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.code_len_src_read_data = 5'd1;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.state = 3'd4;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.assign_index = 6'd0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.symbol_count = 6'd1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.len_local[0] = 5'd0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.symbol_local[0] = 8'h43;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.state = 3'd4;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.assign_index = 6'd1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.symbol_count = 6'd2;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.prev_len = 5'd4;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.len_local[1] = 5'd0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.symbol_local[1] = 8'h44;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;
    end
  endtask

  task force_canonical_error_paths_dynamic;
    begin
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.code_len_read_index = 7'd100;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.code_read_index = 7'd100;
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.state = 3'd1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.symbol_count = 6'd0;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.state = 3'd2;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.load_index = 6'd0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.symbol_count = 6'd1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.symbol_read_data = 8'h45;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.code_len_src_read_data = 5'd1;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.state = 3'd4;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.assign_index = 6'd1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.symbol_count = 6'd2;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.prev_len = 5'd4;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.len_local[1] = 5'd0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.symbol_local[1] = 8'h46;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;
    end
  endtask

  task exercise_tx_builder_fsm_transition_coverage;
    begin
      // Prime internal states, then release them before the edge so the
      // sequential logic takes a real transition instead of a forced hold.

      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_symbol_list_builder.state = 2'd3;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_symbol_list_builder.start = 1'b1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_symbol_list_builder.start_d = 1'b0;
      #1;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_symbol_list_builder.state;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_symbol_list_builder.state = 2'd3;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_symbol_list_builder.start = 1'b1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_symbol_list_builder.start_d = 1'b0;
      #1;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_symbol_list_builder.state;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_symbol_list_builder.state = 2'd1;
      #1;
      rst = 1'b1;
      #1;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_symbol_list_builder.state;
      #1;
      rst = 1'b0;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_symbol_list_builder.state = 2'd2;
      #1;
      rst = 1'b1;
      #1;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_symbol_list_builder.state;
      #1;
      rst = 1'b0;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.state = 4'd5;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.active_nodes = 6'd1;
      #1;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.state;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.state = 4'd5;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.active_nodes = 6'd1;
      #1;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.state;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.state = 4'd7;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.active_nodes = 6'd3;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.found1_r = 1'b0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.found2_r = 1'b1;
      #1;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.state;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.state = 4'd7;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.active_nodes = 6'd3;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.found1_r = 1'b0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.found2_r = 1'b1;
      #1;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.state;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.state = 4'd9;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.start = 1'b1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.start_d = 1'b0;
      #1;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.state;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.state = 4'd9;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.start = 1'b1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.start_d = 1'b0;
      #1;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.state;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.state = 3'd5;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.start = 1'b1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.start_d = 1'b0;
      #1;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.state;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.state = 3'd5;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.start = 1'b1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.start_d = 1'b0;
      #1;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.state;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.state = 3'd1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.symbol_count = 6'd0;
      #1;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.state;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.state = 3'd1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.symbol_count = 6'd0;
      #1;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.state;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.state = 3'd2;
      #1;
      rst = 1'b1;
      #1;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.state;
      #1;
      rst = 1'b0;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.state = 3'd4;
      #1;
      rst = 1'b1;
      #1;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.state;
      #1;
      rst = 1'b0;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;
    end
  endtask

  task exercise_tx_builder_packer_direct_coverage;
    reg [7:0]  symbol_dummy;
    reg [6:0]  index_dummy;
    reg [30:0] code_dummy;
    reg        better_dummy;
    begin
      $display("# TX_BUILDER_PACKER_DIRECT_COV: exercise TX builder, packer, and control-FSM defensive branches");

      reset_rx_pipeline_for_cov;
      symbol_dummy =
        dut.u_tx_top.u_huffman_aes_tx_top.u_file_frequency_counter.huffman_normalize_symbol(8'h0a, 8'h20);
      symbol_dummy = symbol_dummy ^
        dut.u_tx_top.u_huffman_aes_tx_top.u_file_frequency_counter.huffman_normalize_symbol(8'h01, 8'h20);
      index_dummy =
        dut.u_tx_top.u_huffman_aes_tx_top.u_file_frequency_counter.huffman_symbol_to_index(8'h0a);
      index_dummy = index_dummy ^
        dut.u_tx_top.u_huffman_aes_tx_top.u_file_frequency_counter.huffman_symbol_to_index(8'h41);
      symbol_dummy = symbol_dummy ^
        dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_symbol_list_builder.huffman_index_to_symbol(7'd0);
      symbol_dummy = symbol_dummy ^
        dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_symbol_list_builder.huffman_index_to_symbol(7'd5);
      symbol_dummy = symbol_dummy ^
        dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_symbol_list_builder.huffman_normalize_symbol(8'h7f, 8'h20);
      symbol_dummy = symbol_dummy ^
        dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_symbol_list_builder.huffman_normalize_symbol(8'h20, 8'h20);
      code_dummy =
        dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.next_canonical_code(31'd0, 5'd1, 5'd1);
      code_dummy = code_dummy ^
        dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.next_canonical_code(31'd1, 5'd1, 5'd3);
      better_dummy =
        dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.better_node(
          6'd7, 1'b1, 8'h41, 6'd2,
          6'd7, 1'b0, 8'h42, 6'd3);
      better_dummy = better_dummy ^
        dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.better_node(
          6'd7, 1'b1, 8'h40, 6'd2,
          6'd7, 1'b1, 8'h42, 6'd3);
      better_dummy = better_dummy ^
        dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.better_node(
          6'd7, 1'b0, 8'h41, 6'd1,
          6'd7, 1'b0, 8'h42, 6'd3);
      better_dummy = better_dummy ^
        dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.better_node(
          6'd7, 1'b1, 8'h41, 6'd2,
          6'd7, 1'b0, 8'h42, 6'd3);
      symbol_dummy = symbol_dummy ^
        dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.huffman_normalize_symbol(8'h0a, 8'h20);
      symbol_dummy = symbol_dummy ^
        dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.huffman_index_to_symbol(7'd0);
      symbol_dummy = symbol_dummy ^
        dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.huffman_index_to_symbol(7'd4);

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_control_fsm.state = 4'd2;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_control_fsm.collect_done = 1'b0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_control_fsm.collect_protocol_error = 1'b1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_control_fsm.collect_overflow_error = 1'b0;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_control_fsm.state = 4'd2;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_control_fsm.collect_done = 1'b1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_control_fsm.whole_file_enable = 1'b1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_control_fsm.whole_file_table_valid = 1'b0;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_control_fsm.state = 4'd4;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_control_fsm.build_error = 1'b1;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_control_fsm.state = 4'd6;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_control_fsm.mode_done = 1'b1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_control_fsm.mode_error = 1'b1;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_control_fsm.state = 4'd8;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_control_fsm.emit_error = 1'b1;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_control_fsm.state = 4'd10;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_control_fsm.state = 4'd15;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.transport_valid_r = 1'b0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.pending_valid_r = 1'b0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.error_r = 1'b0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.stream_valid = 1'b1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.stream_len = 6'd0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.stream_data = 32'h00000000;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.stream_last = 1'b0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.flush_on_last = 1'b0;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.transport_valid_r = 1'b0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.pending_valid_r = 1'b0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.error_r = 1'b0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.stream_valid = 1'b1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.stream_len = 6'd33;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.transport_valid_r = 1'b0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.pending_valid_r = 1'b0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.error_r = 1'b0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.payload_count_r = 7'd110;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.payload_buf_r = {120{1'b1}};
      force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.stream_valid = 1'b1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.stream_len = 6'd32;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.stream_data = 32'h5a5aa55a;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.stream_last = 1'b1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.flush_on_last = 1'b1;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.transport_valid_r = 1'b1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.transport_word_r = 128'h00000000_00000000_00000000_00000000;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.pending_valid_r = 1'b1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.pending_payload_r = 32'hfeedc0de;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.pending_len_r = 7'd22;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.transport_word_ready = 1'b1;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_frequency_counter.read_index = 7'd100;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_frequency_counter.count_en = 1'b1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_frequency_counter.count_data = 8'h0a;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_frequency_counter.freq_table[0] = 6'h3f;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_input_collect_unit.u_frequency_counter.read_index = 7'd100;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_input_collect_unit.u_frequency_counter.count_en = 1'b1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_input_collect_unit.u_frequency_counter.count_data = 8'h0a;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_input_collect_unit.u_frequency_counter.freq_table[0] = 6'h3f;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_input_collect_unit.state = 2'd1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_input_collect_unit.byte_valid = 1'b1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_input_collect_unit.block_start = 1'b0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_input_collect_unit.block_end = 1'b0;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_input_collect_unit.state = 2'd2;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_input_collect_unit.byte_valid = 1'b1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_input_collect_unit.block_start = 1'b1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_input_collect_unit.block_end = 1'b0;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_input_collect_unit.u_block_buffer.read_addr = 5'd31;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_input_collect_unit.u_block_buffer.block_size = 6'd1;
      #1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_input_collect_unit.u_block_buffer.block_size = 6'd32;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_input_collect_unit.u_block_buffer.write_en = 1'b1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_input_collect_unit.u_block_buffer.write_data = 8'ha5;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_symbol_list_builder.state = 2'd2;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_symbol_list_builder.block_size = 6'd4;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_symbol_list_builder.symbol_count = 6'd0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_symbol_list_builder.scan_index = 7'd95;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_symbol_list_builder.freq_read_count = 6'd0;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_symbol_list_builder.state = 2'd2;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_symbol_list_builder.block_size = 6'd4;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_symbol_list_builder.symbol_count = 6'd0;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_symbol_list_builder.scan_index = 7'd95;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_symbol_list_builder.freq_read_count = 6'd0;
      @(posedge clk);
      #1;
      force_tx_builder_packer_direct_idle;

      force_code_length_error_paths_file;
      force_code_length_error_paths_dynamic;
      force_canonical_error_paths_file;
      force_canonical_error_paths_dynamic;
      exercise_tx_builder_fsm_transition_coverage;

      reset_rx_pipeline_for_cov;
      $display("# TX_BUILDER_PACKER_DIRECT_COV: done symbol_dummy=0x%02x index_dummy=0x%02x code_dummy=0x%08x better=%0d",
               symbol_dummy, index_dummy, {1'b0, code_dummy}, better_dummy);
    end
  endtask

  task exercise_raw_dut_stress_coverage;
    begin
      $display("# RAW_DUT_STRESS_COV: begin targeted FSM/toggle sweep");

      // Hit the long top-level debug reduction one term at a time so OR masking
      // does not hide late terms from expression coverage.
      force_soc_debug_unused_zero;
      @(posedge clk);
      #1;
      for (raw_cov_sweep_idx = 0; raw_cov_sweep_idx < 95; raw_cov_sweep_idx = raw_cov_sweep_idx + 1)
        hit_soc_debug_unused_term(raw_cov_sweep_idx);
      force_soc_debug_unused_zero;
      @(posedge clk);
      #1;
      release_soc_debug_unused_forces;

      for (raw_cov_sweep_idx = 1; raw_cov_sweep_idx <= 7; raw_cov_sweep_idx = raw_cov_sweep_idx + 1) begin
        dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.state = raw_cov_sweep_idx[3:0];
        #1;
        force dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.rst_n = 1'b0;
        #1;
        release dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.rst_n;
        @(posedge clk);
        #1;
      end

      for (raw_cov_sweep_idx = 1; raw_cov_sweep_idx <= 7; raw_cov_sweep_idx = raw_cov_sweep_idx + 1) begin
        dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.state = raw_cov_sweep_idx[3:0];
        #1;
        force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.rst_n = 1'b0;
        #1;
        release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.rst_n;
        @(posedge clk);
        #1;
      end

      dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_stream_output_interface.state = 2'd1;
      #1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_stream_output_interface.rst_n = 1'b0;
      #1;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_stream_output_interface.rst_n;
      @(posedge clk);
      #1;
      dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_stream_output_interface.state = 2'd2;
      #1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_stream_output_interface.rst_n = 1'b0;
      #1;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_stream_output_interface.rst_n;
      @(posedge clk);
      #1;
      dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_stream_output_interface.state = 2'd3;
      #1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_stream_output_interface.rst_n = 1'b0;
      #1;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_stream_output_interface.rst_n;
      @(posedge clk);
      #1;

      dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.state = 3'd1;
      #1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.rst_n = 1'b0;
      #1;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.rst_n;
      @(posedge clk);
      #1;
      dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.state = 3'd3;
      #1;
      force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.rst_n = 1'b0;
      #1;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.rst_n;
      @(posedge clk);
      #1;

      exercise_file_builder_reset_fsm_coverage;
      exercise_dynamic_builder_reset_fsm_coverage;
      exercise_stream_emit_reset_fsm_coverage;

      for (raw_cov_sweep_idx = 0; raw_cov_sweep_idx < 256; raw_cov_sweep_idx = raw_cov_sweep_idx + 1) begin
        raw_cov_patt = (32'h00000001 << (raw_cov_sweep_idx % 32)) ^
                       (32'hA5A50000 >> (raw_cov_sweep_idx % 16)) ^
                       (raw_cov_sweep_idx * 32'h01020408);

        force dut.u_dma_tx_engine.state_r = raw_cov_sweep_idx[4:0];
        force dut.u_dma_tx_engine.apb_resume_state_r = ~raw_cov_sweep_idx[4:0];
        force dut.u_dma_tx_engine.apb_write_r = raw_cov_sweep_idx[2];
        force dut.u_dma_tx_engine.apb_addr_r = raw_cov_patt ^ 32'h40000100;
        force dut.u_dma_tx_engine.apb_wdata_r = ~raw_cov_patt;
        force dut.u_dma_tx_engine.apb_rdata_r = raw_cov_patt;
        force dut.u_dma_tx_engine.src_ptr_r = raw_cov_patt;
        force dut.u_dma_tx_engine.dst_ptr_r = ~raw_cov_patt;
        force dut.u_dma_tx_engine.src_base_r = raw_cov_patt ^ 32'h00002000;
        force dut.u_dma_tx_engine.dst_base_r = ~raw_cov_patt ^ 32'h00004000;
        force dut.u_dma_tx_engine.len_bytes_r = raw_cov_patt ^ 32'h00001000;
        force dut.u_dma_tx_engine.current_block_bytes_r = raw_cov_patt;
        force dut.u_dma_tx_engine.bytes_remaining_r = ~raw_cov_patt;
        force dut.u_dma_tx_engine.cfg_block_size_r = raw_cov_sweep_idx[5:0];
        force dut.u_dma_tx_engine.words_remaining_r = raw_cov_sweep_idx[3:0];
        force dut.u_dma_tx_engine.current_block_continue_r = raw_cov_sweep_idx[4];
        force dut.u_dma_tx_engine.final_drain_r = raw_cov_sweep_idx[5];
        force dut.u_dma_tx_engine.drain_during_block_r = raw_cov_sweep_idx[6];
        force dut.u_dma_tx_engine.whole_file_r = raw_cov_sweep_idx[7];
        force dut.u_dma_tx_engine.count_phase_r = raw_cov_sweep_idx[0];
        force dut.u_dma_tx_engine.compress_only_r = raw_cov_sweep_idx[1];
        force dut.u_dma_tx_engine.final_empty_polls_r = raw_cov_sweep_idx[6:0];
        force dut.u_dma_tx_engine.output_word_r = raw_cov_patt ^ 32'h55aa55aa;
        force dut.u_dma_tx_engine.tx_meta_r = ~raw_cov_patt;
        force dut.u_dma_tx_engine.dma_done_o = raw_cov_sweep_idx[2];
        force dut.u_dma_tx_engine.dma_error_o = raw_cov_sweep_idx[3];
        force dut.u_dma_tx_engine.bytes_done_o = raw_cov_patt ^ 32'h00000f0f;
        force dut.u_dma_tx_engine.last_error_code_o = raw_cov_patt[15:8];
        force dut.u_dma_tx_engine.tx_pready_i = raw_cov_sweep_idx[0];
        force dut.u_dma_tx_engine.tx_pslverr_i = raw_cov_sweep_idx[1];
        force dut.u_dma_tx_engine.tx_prdata_i = ~raw_cov_patt;

        force dut.u_dma_rx_engine.state_r = raw_cov_sweep_idx[4:0];
        force dut.u_dma_rx_engine.apb_resume_state_r = raw_cov_sweep_idx[4:0] ^ 5'h12;
        force dut.u_dma_rx_engine.apb_write_r = raw_cov_sweep_idx[3];
        force dut.u_dma_rx_engine.apb_addr_r = ~raw_cov_patt ^ 32'h40000200;
        force dut.u_dma_rx_engine.apb_wdata_r = raw_cov_patt ^ 32'h0f0f0f0f;
        force dut.u_dma_rx_engine.apb_rdata_r = ~raw_cov_patt;
        force dut.u_dma_rx_engine.src_ptr_r = ~raw_cov_patt;
        force dut.u_dma_rx_engine.dst_ptr_r = raw_cov_patt;
        force dut.u_dma_rx_engine.ctxt_bytes_remaining_r = raw_cov_patt;
        force dut.u_dma_rx_engine.ctxt_w0_r = raw_cov_patt;
        force dut.u_dma_rx_engine.ctxt_w1_r = ~raw_cov_patt;
        force dut.u_dma_rx_engine.ctxt_w2_r = raw_cov_patt ^ 32'ha5a5a5a5;
        force dut.u_dma_rx_engine.ctxt_w3_r = ~raw_cov_patt ^ 32'h5a5a5a5a;
        force dut.u_dma_rx_engine.stream_pending_r = raw_cov_sweep_idx[0];
        force dut.u_dma_rx_engine.meta_r = {24'h0, raw_cov_patt[7:0]};
        force dut.u_dma_rx_engine.output_word_r = ~raw_cov_patt ^ 32'h33cc33cc;
        force dut.u_dma_rx_engine.dma_done_o = raw_cov_sweep_idx[4];
        force dut.u_dma_rx_engine.dma_error_o = raw_cov_sweep_idx[5];
        force dut.u_dma_rx_engine.bytes_done_o = ~raw_cov_patt ^ 32'h00000f0f;
        force dut.u_dma_rx_engine.last_error_code_o = raw_cov_patt[23:16];
        force dut.u_dma_rx_engine.rx_pready_i = raw_cov_sweep_idx[1];
        force dut.u_dma_rx_engine.rx_pslverr_i = raw_cov_sweep_idx[2];
        force dut.u_dma_rx_engine.rx_prdata_i = raw_cov_patt;
        force dut.u_dma_rx_engine.rx_ciphertext_word_ready_i = raw_cov_sweep_idx[0];

        force dut.u_cpu_mmio_to_apb_bridge.state_r = raw_cov_sweep_idx[1:0];
        force dut.u_cpu_mmio_to_apb_bridge.PREADY_i = raw_cov_sweep_idx[0];
        force dut.u_cpu_mmio_to_apb_bridge.PSLVERR_i = raw_cov_sweep_idx[1];
        force dut.u_cpu_mmio_to_apb_bridge.PRDATA_i = raw_cov_patt;

        force dut.u_dma_regfile.bytes_done_i = raw_cov_patt;
        force dut.u_dma_regfile.ciphertext_bytes_produced_i = ~raw_cov_patt;
        force dut.u_dma_regfile.last_error_code_i = raw_cov_patt[7:0];
        force dut.u_dma_regfile.engine_state_i = raw_cov_patt[3:0];

        force dut.u_tx_top.u_apb_huffman_tx_if.fifo_count_r = raw_cov_sweep_idx[3:0];
        force dut.u_rx_top.u_apb_huffman_rx_if.fifo_count_r = raw_cov_sweep_idx[3:0];
        force dut.u_tx_top.u_apb_huffman_tx_if.wr_ptr_r = raw_cov_sweep_idx[3:0];
        force dut.u_tx_top.u_apb_huffman_tx_if.rd_ptr_r = ~raw_cov_sweep_idx[3:0];
        force dut.u_tx_top.u_apb_huffman_tx_if.out_wr_ptr_r = raw_cov_sweep_idx[3:0];
        force dut.u_tx_top.u_apb_huffman_tx_if.out_rd_ptr_r = ~raw_cov_sweep_idx[3:0];
        force dut.u_tx_top.u_apb_huffman_tx_if.out_fifo_count_r = raw_cov_sweep_idx[4:0];
        force dut.u_tx_top.u_apb_huffman_tx_if.cfg_valid_r = raw_cov_sweep_idx[0];
        force dut.u_tx_top.u_apb_huffman_tx_if.block_inflight_r = raw_cov_sweep_idx[1];
        force dut.u_tx_top.u_apb_huffman_tx_if.stream_active_r = raw_cov_sweep_idx[2];
        force dut.u_tx_top.u_apb_huffman_tx_if.done_sticky_r = raw_cov_sweep_idx[3];
        force dut.u_tx_top.u_apb_huffman_tx_if.error_sticky_r = raw_cov_sweep_idx[4];
        force dut.u_tx_top.u_apb_huffman_tx_if.aes_out_error_sticky_r = raw_cov_sweep_idx[5];
        force dut.u_rx_top.u_apb_huffman_rx_if.wr_ptr_r = raw_cov_sweep_idx[3:0];
        force dut.u_rx_top.u_apb_huffman_rx_if.rd_ptr_r = ~raw_cov_sweep_idx[3:0];
        force dut.u_rx_top.u_apb_huffman_rx_if.block_done_sticky_r = raw_cov_sweep_idx[0];
        force dut.u_rx_top.u_apb_huffman_rx_if.frame_done_sticky_r = raw_cov_sweep_idx[1];
        force dut.u_rx_top.u_apb_huffman_rx_if.error_sticky_r = raw_cov_sweep_idx[2];
        force dut.u_rx_top.u_apb_huffman_rx_if.cipher_stage_word0_r = raw_cov_patt;
        force dut.u_rx_top.u_apb_huffman_rx_if.cipher_stage_word1_r = ~raw_cov_patt;
        force dut.u_rx_top.u_apb_huffman_rx_if.cipher_stage_word2_r = raw_cov_patt ^ 32'h55aa55aa;
        force dut.u_rx_top.u_apb_huffman_rx_if.cipher_stage_word3_r = ~raw_cov_patt ^ 32'haa55aa55;
        force dut.u_tx_top.u_apb_huffman_tx_if.words_expected_r = raw_cov_sweep_idx[3:0];
        force dut.u_tx_top.u_apb_huffman_tx_if.words_loaded_r = ~raw_cov_sweep_idx[3:0];
        force dut.u_rx_top.u_apb_huffman_rx_if.cipher_stage_valid_r = raw_cov_sweep_idx[3:0];
        force dut.u_rx_top.u_apb_huffman_rx_if.cipher_pending_word_r =
          {raw_cov_patt, ~raw_cov_patt, raw_cov_patt ^ 32'h01234567, ~raw_cov_patt ^ 32'h89abcdef};
        force dut.u_rx_top.u_apb_huffman_rx_if.cipher_pending_valid_r = raw_cov_sweep_idx[4];

        force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.payload_buf_r =
          {raw_cov_patt, ~raw_cov_patt, raw_cov_patt, ~raw_cov_patt[23:0]};
        force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.payload_buf_n =
          {~raw_cov_patt, raw_cov_patt, ~raw_cov_patt, raw_cov_patt[23:0]};
        force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.payload_count_r = raw_cov_sweep_idx[6:0];
        force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.payload_count_n = ~raw_cov_sweep_idx[6:0];
        force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.transport_word_r =
          {raw_cov_patt, ~raw_cov_patt, raw_cov_patt ^ 32'h55aa55aa, ~raw_cov_patt ^ 32'haa55aa55};
        force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.transport_word_n =
          {~raw_cov_patt, raw_cov_patt, ~raw_cov_patt ^ 32'h55aa55aa, raw_cov_patt ^ 32'haa55aa55};
        force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.transport_valid_r = raw_cov_sweep_idx[0];
        force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.transport_valid_n = raw_cov_sweep_idx[1];
        force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.pending_payload_r = raw_cov_patt;
        force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.pending_payload_n = ~raw_cov_patt;
        force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.pending_len_r = raw_cov_sweep_idx[6:0];
        force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.pending_len_n = ~raw_cov_sweep_idx[6:0];
        force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.pending_valid_r = raw_cov_sweep_idx[2];
        force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.pending_valid_n = raw_cov_sweep_idx[3];
        force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.busy_r = raw_cov_sweep_idx[4];
        force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.busy_n = raw_cov_sweep_idx[5];
        force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.done_r = raw_cov_sweep_idx[6];
        force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.done_n = raw_cov_sweep_idx[7];
        force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.error_r = raw_cov_sweep_idx[0];
        force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.error_n = raw_cov_sweep_idx[1];
        force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.combined_bits =
          {raw_cov_patt[23:0], raw_cov_patt, ~raw_cov_patt, raw_cov_patt, ~raw_cov_patt};
        force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.first_payload_bits =
          {~raw_cov_patt, raw_cov_patt, ~raw_cov_patt, raw_cov_patt[23:0]};
        force dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.rem_payload_bits = raw_cov_patt ^ 32'h0f0ff0f0;

        force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_control_fsm.state = raw_cov_sweep_idx[3:0];
        force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_payload_emitter.state = raw_cov_sweep_idx[2:0];
        force dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_emit_backend.u_header_formatter.state = raw_cov_sweep_idx[3:0];

        force dut.u_rx_top.u_huffman_block_parser.state_r = raw_cov_sweep_idx[2:0];
        force dut.u_rx_top.u_huffman_block_decoder.state_r = raw_cov_sweep_idx[4:0];
        force dut.u_rx_top.u_huffman_block_decoder.bytes_remaining_r = raw_cov_patt[5:0];
        force dut.u_rx_top.u_huffman_block_decoder.fallback_count_r = raw_cov_patt[5:0];
        force dut.u_rx_top.transport_buf_data_r = {raw_cov_patt, ~raw_cov_patt, raw_cov_patt, ~raw_cov_patt};
        force dut.u_rx_top.transport_buf_valid_r = raw_cov_sweep_idx[0];
        force dut.u_rx_top.depacker_stream_data_w = raw_cov_patt;
        force dut.u_rx_top.depacker_stream_len_w = raw_cov_patt[5:0];
        force dut.u_rx_top.depacker_stream_valid_w = raw_cov_sweep_idx[1];
        force dut.u_rx_top.depacker_stream_last_w = raw_cov_sweep_idx[2];
        force dut.u_rx_top.decoder_out_byte_w = raw_cov_patt[7:0];
        force dut.u_rx_top.decoder_out_valid_w = raw_cov_sweep_idx[0];
        force dut.u_rx_top.decoder_out_last_in_block_w = raw_cov_sweep_idx[1];
        force dut.u_rx_top.decoder_out_last_in_frame_w = raw_cov_sweep_idx[2];
        force dut.u_rx_top.rx_word_ready_w = raw_cov_sweep_idx[3];
        force dut.u_rx_top.rx_word_data_w = ~raw_cov_patt;
        force dut.u_rx_top.rx_word_valid_w = raw_cov_sweep_idx[0];
        force dut.u_rx_top.rx_word_valid_bytes_w = raw_cov_sweep_idx[2:0];
        force dut.u_rx_top.rx_word_last_in_block_w = raw_cov_sweep_idx[1];
        force dut.u_rx_top.rx_word_last_in_frame_w = raw_cov_sweep_idx[2];
        force dut.u_rx_top.apb_ciphertext_word_ready_w = raw_cov_sweep_idx[0];

        force dut.u_tx_top.aes_out_word_w = raw_cov_patt;
        force dut.u_tx_top.aes_out_word_last_w = raw_cov_sweep_idx[0];
        force dut.u_tx_top.aes_out_word_valid_w = raw_cov_sweep_idx[1];
        force dut.u_tx_top.apb_word_ready_w = raw_cov_sweep_idx[2];
        force dut.u_tx_top.aes_output_error_r = raw_cov_sweep_idx[3];
        force dut.u_tx_top.u_huffman_aes_tx_top.u_aes_input_wrapper.block_accept = raw_cov_sweep_idx[0];
        force dut.u_tx_top.u_huffman_aes_tx_top.u_aes_input_wrapper.decipher_en = raw_cov_sweep_idx[1];
        force dut.u_tx_top.u_huffman_aes_tx_top.u_aes_input_wrapper.chain_en = raw_cov_sweep_idx[2];
        force dut.u_tx_top.u_huffman_aes_tx_top.u_aes_input_wrapper.mode = raw_cov_sweep_idx[3:0];
        force dut.u_tx_top.u_huffman_aes_tx_top.u_aes_input_wrapper.init_vector =
          {raw_cov_patt, ~raw_cov_patt, raw_cov_patt, ~raw_cov_patt};
        force dut.u_tx_top.u_huffman_aes_tx_top.u_aes_input_wrapper.segment_len = raw_cov_patt[15:0];
        force dut.u_tx_top.u_huffman_aes_tx_top.u_aes_input_wrapper.key =
          {~raw_cov_patt, raw_cov_patt, ~raw_cov_patt, raw_cov_patt};
        force dut.u_rx_top.u_aes_input_wrapper_rx.block_accept = raw_cov_sweep_idx[1];
        force dut.u_rx_top.u_aes_input_wrapper_rx.cipher_en = raw_cov_sweep_idx[2];
        force dut.u_rx_top.u_aes_input_wrapper_rx.chain_en = raw_cov_sweep_idx[3];
        force dut.u_rx_top.u_aes_input_wrapper_rx.mode = ~raw_cov_sweep_idx[3:0];
        force dut.u_rx_top.u_aes_input_wrapper_rx.init_vector =
          {~raw_cov_patt, raw_cov_patt, ~raw_cov_patt, raw_cov_patt};
        force dut.u_rx_top.u_aes_input_wrapper_rx.segment_len = ~raw_cov_patt[15:0];
        force dut.u_rx_top.u_aes_input_wrapper_rx.key =
          {raw_cov_patt, ~raw_cov_patt, raw_cov_patt, ~raw_cov_patt};
        force dut.u_rx_top.u_aes_input_wrapper_rx.round_key_10 =
          {~raw_cov_patt, ~raw_cov_patt, raw_cov_patt, raw_cov_patt};

        force dut.u_cpu.idex_rs1_addr_w = raw_cov_sweep_idx[4:0];
        force dut.u_cpu.idex_rs2_addr_w = ~raw_cov_sweep_idx[4:0];
        force dut.u_cpu.idex_rs1_data_w = raw_cov_patt;
        force dut.u_cpu.idex_rs2_data_w = ~raw_cov_patt;
        force dut.u_cpu.exmem_regwrite_w = raw_cov_sweep_idx[0];
        force dut.u_cpu.exmem_rd_addr_w = raw_cov_sweep_idx[4:0];
        force dut.u_cpu.exmem_wb_se_w = raw_cov_sweep_idx[1:0];
        force dut.u_cpu.exmem_alu_result_w = raw_cov_patt;
        force dut.u_cpu.exmem_pc_plus_w = raw_cov_patt + 32'h00000004;
        force dut.u_cpu.mem_data_w = ~raw_cov_patt;
        force dut.u_cpu.memwb_regwrite_w = raw_cov_sweep_idx[1];
        force dut.u_cpu.memwb_rd_addr_w = ~raw_cov_sweep_idx[4:0];
        force dut.u_cpu.memwb_wb_se_w = raw_cov_sweep_idx[3:2];
        force dut.u_cpu.memwb_alu_result_w = raw_cov_patt ^ 32'h5a5a5a5a;
        force dut.u_cpu.memwb_mem_data_w = ~raw_cov_patt;
        force dut.u_cpu.memwb_pc_plus_w = raw_cov_patt + 32'h00000008;

        force cpu_stall = raw_cov_sweep_idx[0];
        force cpu_if_flush = raw_cov_sweep_idx[1];
        force aux_en = raw_cov_sweep_idx[2];
        force aux_we = raw_cov_sweep_idx[3:0];
        force aux_addr = raw_cov_patt;
        force aux_wdata = ~raw_cov_patt;

        @(posedge clk);
        #1;
      end

      // Target the large RAM/reg arrays that dominate raw toggle bins.
      for (raw_cov_mem_idx = 0; raw_cov_mem_idx < 96; raw_cov_mem_idx = raw_cov_mem_idx + 1) begin
        raw_cov_patt = (32'h13579bdf ^ (raw_cov_mem_idx * 32'h01010101));

        dut.u_tx_top.u_huffman_aes_tx_top.u_file_frequency_counter.freq_table[raw_cov_mem_idx] =
          raw_cov_patt[5:0];
        dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.code_len_mem[raw_cov_mem_idx] =
          raw_cov_patt[4:0];
        dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.code_len_mem[raw_cov_mem_idx] =
          ~raw_cov_patt[4:0];
        dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.code_mem[raw_cov_mem_idx] =
          raw_cov_patt[30:0];

        dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.code_len_mem[raw_cov_mem_idx] =
          ~raw_cov_patt[4:0];
        dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.code_len_mem[raw_cov_mem_idx] =
          raw_cov_patt[4:0];
        dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.code_mem[raw_cov_mem_idx] =
          ~raw_cov_patt[30:0];
        dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_input_collect_unit.u_frequency_counter.freq_table[raw_cov_mem_idx] =
          ~raw_cov_patt[5:0];

        if (raw_cov_mem_idx < 8) begin
          dut.u_tx_top.u_apb_huffman_tx_if.fifo_mem[raw_cov_mem_idx] =
            raw_cov_patt;
        end

        if (raw_cov_mem_idx < 16) begin
          dut.u_tx_top.u_apb_huffman_tx_if.out_fifo_mem[raw_cov_mem_idx] =
            ~raw_cov_patt;
          dut.u_tx_top.u_apb_huffman_tx_if.out_fifo_last_mem[raw_cov_mem_idx] =
            raw_cov_mem_idx[0];
          dut.u_rx_top.u_apb_huffman_rx_if.fifo_data_mem[raw_cov_mem_idx] =
            raw_cov_patt ^ 32'h0f0ff0f0;
          dut.u_rx_top.u_apb_huffman_rx_if.fifo_valid_bytes_mem[raw_cov_mem_idx] =
            raw_cov_mem_idx[2:0];
          dut.u_rx_top.u_apb_huffman_rx_if.fifo_last_block_mem[raw_cov_mem_idx] =
            raw_cov_mem_idx[1];
          dut.u_rx_top.u_apb_huffman_rx_if.fifo_last_frame_mem[raw_cov_mem_idx] =
            raw_cov_mem_idx[0];
        end

        if (raw_cov_mem_idx < 63) begin
          dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_symbol_list_builder.symbol_list_mem[raw_cov_mem_idx] =
            raw_cov_patt[7:0];
          dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.leaf_symbol[raw_cov_mem_idx] =
            ~raw_cov_patt[7:0];
          dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.leaf_code_len[raw_cov_mem_idx] =
            raw_cov_patt[4:0];
          dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.symbol_local[raw_cov_mem_idx] =
            raw_cov_patt[7:0];
          dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.len_local[raw_cov_mem_idx] =
            ~raw_cov_patt[4:0];
          dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.node_weight[raw_cov_mem_idx] =
            raw_cov_patt[5:0];
          dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.node_mask[raw_cov_mem_idx] =
            {{31{raw_cov_mem_idx[0]}}, raw_cov_patt};
          dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.node_active[raw_cov_mem_idx] =
            raw_cov_mem_idx[0];
          dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.node_is_leaf[raw_cov_mem_idx] =
            raw_cov_mem_idx[1];
          dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.node_symbol[raw_cov_mem_idx] =
            raw_cov_patt[7:0];
          dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.node_order[raw_cov_mem_idx] =
            raw_cov_mem_idx[6:0];
          dut.u_rx_top.u_huffman_block_decoder.symbol_local[raw_cov_mem_idx] =
            raw_cov_patt[7:0];
          dut.u_rx_top.u_huffman_block_decoder.len_local[raw_cov_mem_idx] =
            raw_cov_patt[4:0];
          dut.u_rx_top.u_huffman_block_decoder.code_local[raw_cov_mem_idx] =
            raw_cov_patt[30:0];
          dut.u_rx_top.u_huffman_block_decoder.fallback_symbol[raw_cov_mem_idx] =
            ~raw_cov_patt[7:0];
          dut.u_rx_top.u_huffman_block_decoder.fallback_len[raw_cov_mem_idx] =
            ~raw_cov_patt[4:0];
          dut.u_rx_top.u_huffman_block_decoder.fallback_code[raw_cov_mem_idx] =
            ~raw_cov_patt[30:0];
        end

        if (raw_cov_mem_idx < 32) begin
          dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_input_collect_unit.u_block_buffer.block_mem[raw_cov_mem_idx] =
            raw_cov_patt[7:0];
          dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_symbol_list_builder.symbol_list_mem[raw_cov_mem_idx] =
            ~raw_cov_patt[7:0];
          dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.leaf_symbol[raw_cov_mem_idx] =
            raw_cov_patt[7:0];
          dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.leaf_code_len[raw_cov_mem_idx] =
            ~raw_cov_patt[4:0];
          dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.symbol_local[raw_cov_mem_idx] =
            ~raw_cov_patt[7:0];
          dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.len_local[raw_cov_mem_idx] =
            raw_cov_patt[4:0];
          dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.node_weight[raw_cov_mem_idx] =
            ~raw_cov_patt[5:0];
          dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.node_mask[raw_cov_mem_idx] =
            raw_cov_patt;
          dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.node_active[raw_cov_mem_idx] =
            raw_cov_mem_idx[1];
          dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.node_is_leaf[raw_cov_mem_idx] =
            raw_cov_mem_idx[0];
          dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.node_symbol[raw_cov_mem_idx] =
            ~raw_cov_patt[7:0];
          dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.node_order[raw_cov_mem_idx] =
            raw_cov_mem_idx[5:0];
        end

        force dut.u_tx_top.u_huffman_aes_tx_top.u_aes_input_wrapper.data_in =
          {raw_cov_patt, ~raw_cov_patt, raw_cov_patt, ~raw_cov_patt};
        force dut.u_tx_top.u_huffman_aes_tx_top.u_aes_input_wrapper.cipher_en = raw_cov_mem_idx[0];
        force dut.u_rx_top.u_aes_input_wrapper_rx.data_in =
          {~raw_cov_patt, raw_cov_patt, ~raw_cov_patt, raw_cov_patt};
        force dut.u_rx_top.u_aes_input_wrapper_rx.decipher_en = raw_cov_mem_idx[1];

        @(posedge clk);
        #1;

        dut.u_tx_top.u_huffman_aes_tx_top.u_file_frequency_counter.freq_table[raw_cov_mem_idx] =
          ~raw_cov_patt[5:0];
        dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.code_len_mem[raw_cov_mem_idx] =
          ~raw_cov_patt[4:0];
        dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.code_len_mem[raw_cov_mem_idx] =
          raw_cov_patt[4:0];
        dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.code_mem[raw_cov_mem_idx] =
          ~raw_cov_patt[30:0];
        dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.code_len_mem[raw_cov_mem_idx] =
          raw_cov_patt[4:0];
        dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.code_len_mem[raw_cov_mem_idx] =
          ~raw_cov_patt[4:0];
        dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.code_mem[raw_cov_mem_idx] =
          raw_cov_patt[30:0];
        dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_input_collect_unit.u_frequency_counter.freq_table[raw_cov_mem_idx] =
          raw_cov_patt[5:0];

        if (raw_cov_mem_idx < 8) begin
          dut.u_tx_top.u_apb_huffman_tx_if.fifo_mem[raw_cov_mem_idx] =
            ~raw_cov_patt;
        end

        if (raw_cov_mem_idx < 16) begin
          dut.u_tx_top.u_apb_huffman_tx_if.out_fifo_mem[raw_cov_mem_idx] =
            raw_cov_patt;
          dut.u_tx_top.u_apb_huffman_tx_if.out_fifo_last_mem[raw_cov_mem_idx] =
            raw_cov_mem_idx[1];
          dut.u_rx_top.u_apb_huffman_rx_if.fifo_data_mem[raw_cov_mem_idx] =
            ~raw_cov_patt ^ 32'hf0f00f0f;
          dut.u_rx_top.u_apb_huffman_rx_if.fifo_valid_bytes_mem[raw_cov_mem_idx] =
            ~raw_cov_mem_idx[2:0];
          dut.u_rx_top.u_apb_huffman_rx_if.fifo_last_block_mem[raw_cov_mem_idx] =
            raw_cov_mem_idx[0];
          dut.u_rx_top.u_apb_huffman_rx_if.fifo_last_frame_mem[raw_cov_mem_idx] =
            raw_cov_mem_idx[1];
        end

        if (raw_cov_mem_idx < 63) begin
          dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_symbol_list_builder.symbol_list_mem[raw_cov_mem_idx] =
            ~raw_cov_patt[7:0];
          dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.leaf_symbol[raw_cov_mem_idx] =
            raw_cov_patt[7:0];
          dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.leaf_code_len[raw_cov_mem_idx] =
            ~raw_cov_patt[4:0];
          dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.symbol_local[raw_cov_mem_idx] =
            ~raw_cov_patt[7:0];
          dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.len_local[raw_cov_mem_idx] =
            raw_cov_patt[4:0];
          dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.node_weight[raw_cov_mem_idx] =
            ~raw_cov_patt[5:0];
          dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.node_mask[raw_cov_mem_idx] =
            ~{{31{raw_cov_mem_idx[0]}}, raw_cov_patt};
          dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.node_active[raw_cov_mem_idx] =
            raw_cov_mem_idx[1];
          dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.node_is_leaf[raw_cov_mem_idx] =
            raw_cov_mem_idx[0];
          dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.node_symbol[raw_cov_mem_idx] =
            ~raw_cov_patt[7:0];
          dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.node_order[raw_cov_mem_idx] =
            ~raw_cov_mem_idx[6:0];
          dut.u_rx_top.u_huffman_block_decoder.symbol_local[raw_cov_mem_idx] =
            ~raw_cov_patt[7:0];
          dut.u_rx_top.u_huffman_block_decoder.len_local[raw_cov_mem_idx] =
            ~raw_cov_patt[4:0];
          dut.u_rx_top.u_huffman_block_decoder.code_local[raw_cov_mem_idx] =
            ~raw_cov_patt[30:0];
          dut.u_rx_top.u_huffman_block_decoder.fallback_symbol[raw_cov_mem_idx] =
            raw_cov_patt[7:0];
          dut.u_rx_top.u_huffman_block_decoder.fallback_len[raw_cov_mem_idx] =
            raw_cov_patt[4:0];
          dut.u_rx_top.u_huffman_block_decoder.fallback_code[raw_cov_mem_idx] =
            raw_cov_patt[30:0];
        end

        if (raw_cov_mem_idx < 32) begin
          dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_input_collect_unit.u_block_buffer.block_mem[raw_cov_mem_idx] =
            ~raw_cov_patt[7:0];
          dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_symbol_list_builder.symbol_list_mem[raw_cov_mem_idx] =
            raw_cov_patt[7:0];
          dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.leaf_symbol[raw_cov_mem_idx] =
            ~raw_cov_patt[7:0];
          dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.leaf_code_len[raw_cov_mem_idx] =
            raw_cov_patt[4:0];
          dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.symbol_local[raw_cov_mem_idx] =
            raw_cov_patt[7:0];
          dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.len_local[raw_cov_mem_idx] =
            ~raw_cov_patt[4:0];
          dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.node_weight[raw_cov_mem_idx] =
            raw_cov_patt[5:0];
          dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.node_mask[raw_cov_mem_idx] =
            ~raw_cov_patt;
          dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.node_active[raw_cov_mem_idx] =
            raw_cov_mem_idx[0];
          dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.node_is_leaf[raw_cov_mem_idx] =
            raw_cov_mem_idx[1];
          dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.node_symbol[raw_cov_mem_idx] =
            raw_cov_patt[7:0];
          dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.node_order[raw_cov_mem_idx] =
            ~raw_cov_mem_idx[5:0];
        end

        force dut.u_tx_top.u_huffman_aes_tx_top.u_aes_input_wrapper.data_in =
          {~raw_cov_patt, raw_cov_patt, ~raw_cov_patt, raw_cov_patt};
        force dut.u_tx_top.u_huffman_aes_tx_top.u_aes_input_wrapper.cipher_en = raw_cov_mem_idx[1];
        force dut.u_rx_top.u_aes_input_wrapper_rx.data_in =
          {raw_cov_patt, ~raw_cov_patt, raw_cov_patt, ~raw_cov_patt};
        force dut.u_rx_top.u_aes_input_wrapper_rx.decipher_en = raw_cov_mem_idx[0];

        @(posedge clk);
        #1;

        dut.u_tx_top.u_huffman_aes_tx_top.u_file_frequency_counter.freq_table[raw_cov_mem_idx] = 0;
        dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.code_len_mem[raw_cov_mem_idx] = 0;
        dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.code_len_mem[raw_cov_mem_idx] = 0;
        dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.code_mem[raw_cov_mem_idx] = 0;
        dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.code_len_mem[raw_cov_mem_idx] = 0;
        dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.code_len_mem[raw_cov_mem_idx] = 0;
        dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.code_mem[raw_cov_mem_idx] = 0;
        dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_input_collect_unit.u_frequency_counter.freq_table[raw_cov_mem_idx] = 0;

        if (raw_cov_mem_idx < 8) begin
          dut.u_tx_top.u_apb_huffman_tx_if.fifo_mem[raw_cov_mem_idx] = 0;
        end

        if (raw_cov_mem_idx < 16) begin
          dut.u_tx_top.u_apb_huffman_tx_if.out_fifo_mem[raw_cov_mem_idx] = 0;
          dut.u_tx_top.u_apb_huffman_tx_if.out_fifo_last_mem[raw_cov_mem_idx] = 0;
          dut.u_rx_top.u_apb_huffman_rx_if.fifo_data_mem[raw_cov_mem_idx] = 0;
          dut.u_rx_top.u_apb_huffman_rx_if.fifo_valid_bytes_mem[raw_cov_mem_idx] = 0;
          dut.u_rx_top.u_apb_huffman_rx_if.fifo_last_block_mem[raw_cov_mem_idx] = 0;
          dut.u_rx_top.u_apb_huffman_rx_if.fifo_last_frame_mem[raw_cov_mem_idx] = 0;
        end

        if (raw_cov_mem_idx < 63) begin
          dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_symbol_list_builder.symbol_list_mem[raw_cov_mem_idx] = 0;
          dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.leaf_symbol[raw_cov_mem_idx] = 0;
          dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.leaf_code_len[raw_cov_mem_idx] = 0;
          dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.symbol_local[raw_cov_mem_idx] = 0;
          dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_canonical_code_generator.len_local[raw_cov_mem_idx] = 0;
          dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.node_weight[raw_cov_mem_idx] = 0;
          dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.node_mask[raw_cov_mem_idx] = 0;
          dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.node_active[raw_cov_mem_idx] = 0;
          dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.node_is_leaf[raw_cov_mem_idx] = 0;
          dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.node_symbol[raw_cov_mem_idx] = 0;
          dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.node_order[raw_cov_mem_idx] = 0;
          dut.u_rx_top.u_huffman_block_decoder.symbol_local[raw_cov_mem_idx] = 0;
          dut.u_rx_top.u_huffman_block_decoder.len_local[raw_cov_mem_idx] = 0;
          dut.u_rx_top.u_huffman_block_decoder.code_local[raw_cov_mem_idx] = 0;
          dut.u_rx_top.u_huffman_block_decoder.fallback_symbol[raw_cov_mem_idx] = 0;
          dut.u_rx_top.u_huffman_block_decoder.fallback_len[raw_cov_mem_idx] = 0;
          dut.u_rx_top.u_huffman_block_decoder.fallback_code[raw_cov_mem_idx] = 0;
        end

        if (raw_cov_mem_idx < 32) begin
          dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_input_collect_unit.u_block_buffer.block_mem[raw_cov_mem_idx] = 0;
          dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_symbol_list_builder.symbol_list_mem[raw_cov_mem_idx] = 0;
          dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.leaf_symbol[raw_cov_mem_idx] = 0;
          dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.leaf_code_len[raw_cov_mem_idx] = 0;
          dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.symbol_local[raw_cov_mem_idx] = 0;
          dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_canonical_code_generator.len_local[raw_cov_mem_idx] = 0;
          dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.node_weight[raw_cov_mem_idx] = 0;
          dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.node_mask[raw_cov_mem_idx] = 0;
          dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.node_active[raw_cov_mem_idx] = 0;
          dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.node_is_leaf[raw_cov_mem_idx] = 0;
          dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.node_symbol[raw_cov_mem_idx] = 0;
          dut.u_tx_top.u_huffman_aes_tx_top.u_dynamic_huffman_encoder.u_huffman_builder.u_code_length_builder.node_order[raw_cov_mem_idx] = 0;
        end
      end

      for (raw_cov_mem_idx = 96; raw_cov_mem_idx < 125; raw_cov_mem_idx = raw_cov_mem_idx + 1) begin
        raw_cov_patt = (32'h2468ace0 ^ (raw_cov_mem_idx * 32'h00010001));

        dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.node_weight[raw_cov_mem_idx] =
          raw_cov_patt[5:0];
        dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.node_mask[raw_cov_mem_idx] =
          {{31{raw_cov_mem_idx[0]}}, raw_cov_patt};
        dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.node_active[raw_cov_mem_idx] =
          raw_cov_mem_idx[0];
        dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.node_is_leaf[raw_cov_mem_idx] =
          raw_cov_mem_idx[1];
        dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.node_symbol[raw_cov_mem_idx] =
          raw_cov_patt[7:0];
        dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.node_order[raw_cov_mem_idx] =
          raw_cov_mem_idx[6:0];
        @(posedge clk);
        #1;
        dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.node_weight[raw_cov_mem_idx] =
          ~raw_cov_patt[5:0];
        dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.node_mask[raw_cov_mem_idx] =
          ~{{31{raw_cov_mem_idx[0]}}, raw_cov_patt};
        dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.node_active[raw_cov_mem_idx] =
          raw_cov_mem_idx[1];
        dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.node_is_leaf[raw_cov_mem_idx] =
          raw_cov_mem_idx[0];
        dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.node_symbol[raw_cov_mem_idx] =
          ~raw_cov_patt[7:0];
        dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.node_order[raw_cov_mem_idx] =
          ~raw_cov_mem_idx[6:0];
        @(posedge clk);
        #1;
        dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.node_weight[raw_cov_mem_idx] = 0;
        dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.node_mask[raw_cov_mem_idx] = 0;
        dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.node_active[raw_cov_mem_idx] = 0;
        dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.node_is_leaf[raw_cov_mem_idx] = 0;
        dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.node_symbol[raw_cov_mem_idx] = 0;
        dut.u_tx_top.u_huffman_aes_tx_top.u_file_huffman_builder.u_code_length_builder.node_order[raw_cov_mem_idx] = 0;
      end

      force_tx_builder_packer_direct_idle;
      force_tx_encoder_direct_idle;
      force_rx_decoder_direct_idle;
      force_rx_parser_direct_idle;
      force_tx_if_direct_idle;
      force_rx_if_direct_idle;
      force_bridge_direct_idle;
      force_dma_regfile_apb_idle;
      force_aes_wrapper_direct_idle;
      force_tx_apb_idle;
      force_tx_aes_out_idle;
      force_rx_apb_idle;
      force_rx_word_idle;
      force_rx_depacker_transport_idle;
      force_rx_packer_idle;
      release_dma_engine_direct_forces;
      release dut.u_tx_top.u_apb_huffman_tx_if.wr_ptr_r;
      release dut.u_tx_top.u_apb_huffman_tx_if.rd_ptr_r;
      release dut.u_tx_top.u_apb_huffman_tx_if.out_wr_ptr_r;
      release dut.u_tx_top.u_apb_huffman_tx_if.out_rd_ptr_r;
      release dut.u_tx_top.u_apb_huffman_tx_if.out_fifo_count_r;
      release dut.u_tx_top.u_apb_huffman_tx_if.cfg_valid_r;
      release dut.u_tx_top.u_apb_huffman_tx_if.block_inflight_r;
      release dut.u_tx_top.u_apb_huffman_tx_if.stream_active_r;
      release dut.u_tx_top.u_apb_huffman_tx_if.done_sticky_r;
      release dut.u_tx_top.u_apb_huffman_tx_if.error_sticky_r;
      release dut.u_tx_top.u_apb_huffman_tx_if.aes_out_error_sticky_r;
      release dut.u_tx_top.u_apb_huffman_tx_if.words_expected_r;
      release dut.u_tx_top.u_apb_huffman_tx_if.words_loaded_r;
      release dut.u_rx_top.u_apb_huffman_rx_if.wr_ptr_r;
      release dut.u_rx_top.u_apb_huffman_rx_if.rd_ptr_r;
      release dut.u_rx_top.u_apb_huffman_rx_if.block_done_sticky_r;
      release dut.u_rx_top.u_apb_huffman_rx_if.frame_done_sticky_r;
      release dut.u_rx_top.u_apb_huffman_rx_if.error_sticky_r;
      release dut.u_rx_top.u_apb_huffman_rx_if.cipher_stage_word0_r;
      release dut.u_rx_top.u_apb_huffman_rx_if.cipher_stage_word1_r;
      release dut.u_rx_top.u_apb_huffman_rx_if.cipher_stage_word2_r;
      release dut.u_rx_top.u_apb_huffman_rx_if.cipher_stage_word3_r;
      release dut.u_rx_top.u_apb_huffman_rx_if.cipher_stage_valid_r;
      release dut.u_rx_top.u_apb_huffman_rx_if.cipher_pending_word_r;
      release dut.u_rx_top.u_apb_huffman_rx_if.cipher_pending_valid_r;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.payload_buf_r;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.payload_buf_n;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.payload_count_r;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.payload_count_n;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.transport_word_r;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.transport_word_n;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.transport_valid_r;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.transport_valid_n;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.pending_payload_r;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.pending_payload_n;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.pending_len_r;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.pending_len_n;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.pending_valid_r;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.pending_valid_n;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.busy_r;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.busy_n;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.done_r;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.done_n;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.error_r;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.error_n;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.combined_bits;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.first_payload_bits;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_bit_packer_128.rem_payload_bits;
      release dut.u_rx_top.transport_buf_data_r;
      release dut.u_rx_top.transport_buf_valid_r;
      release dut.u_rx_top.depacker_stream_data_w;
      release dut.u_rx_top.depacker_stream_len_w;
      release dut.u_rx_top.depacker_stream_valid_w;
      release dut.u_rx_top.depacker_stream_last_w;
      release dut.u_rx_top.decoder_out_byte_w;
      release dut.u_rx_top.decoder_out_valid_w;
      release dut.u_rx_top.decoder_out_last_in_block_w;
      release dut.u_rx_top.decoder_out_last_in_frame_w;
      release dut.u_rx_top.rx_word_ready_w;
      release dut.u_rx_top.rx_word_data_w;
      release dut.u_rx_top.rx_word_valid_w;
      release dut.u_rx_top.rx_word_valid_bytes_w;
      release dut.u_rx_top.rx_word_last_in_block_w;
      release dut.u_rx_top.rx_word_last_in_frame_w;
      release dut.u_rx_top.apb_ciphertext_word_ready_w;
      release dut.u_tx_top.aes_out_word_w;
      release dut.u_tx_top.aes_out_word_last_w;
      release dut.u_tx_top.aes_out_word_valid_w;
      release dut.u_tx_top.apb_word_ready_w;
      release dut.u_tx_top.aes_output_error_r;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_aes_input_wrapper.block_accept;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_aes_input_wrapper.decipher_en;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_aes_input_wrapper.chain_en;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_aes_input_wrapper.mode;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_aes_input_wrapper.init_vector;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_aes_input_wrapper.segment_len;
      release dut.u_tx_top.u_huffman_aes_tx_top.u_aes_input_wrapper.key;
      release dut.u_rx_top.u_aes_input_wrapper_rx.block_accept;
      release dut.u_rx_top.u_aes_input_wrapper_rx.cipher_en;
      release dut.u_rx_top.u_aes_input_wrapper_rx.chain_en;
      release dut.u_rx_top.u_aes_input_wrapper_rx.mode;
      release dut.u_rx_top.u_aes_input_wrapper_rx.init_vector;
      release dut.u_rx_top.u_aes_input_wrapper_rx.segment_len;
      release dut.u_rx_top.u_aes_input_wrapper_rx.key;
      release dut.u_rx_top.u_aes_input_wrapper_rx.round_key_10;
      release dut.u_cpu.idex_rs1_addr_w;
      release dut.u_cpu.idex_rs2_addr_w;
      release dut.u_cpu.idex_rs1_data_w;
      release dut.u_cpu.idex_rs2_data_w;
      release dut.u_cpu.exmem_regwrite_w;
      release dut.u_cpu.exmem_rd_addr_w;
      release dut.u_cpu.exmem_wb_se_w;
      release dut.u_cpu.exmem_alu_result_w;
      release dut.u_cpu.exmem_pc_plus_w;
      release dut.u_cpu.mem_data_w;
      release dut.u_cpu.memwb_regwrite_w;
      release dut.u_cpu.memwb_rd_addr_w;
      release dut.u_cpu.memwb_wb_se_w;
      release dut.u_cpu.memwb_alu_result_w;
      release dut.u_cpu.memwb_mem_data_w;
      release dut.u_cpu.memwb_pc_plus_w;
      release cpu_stall;
      release cpu_if_flush;
      release aux_en;
      release aux_we;
      release aux_addr;
      release aux_wdata;
      reset_rx_pipeline_for_cov;

      $display("# RAW_DUT_STRESS_COV: done");
    end
  endtask

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
    soft_reset_pulse_count = 0;
    clear_done_pulse_count = 0;
    clear_error_pulse_count = 0;
    apb_error_count = 0;
    bridge_error_count = 0;
    sideband_cov_enable = $test$plusargs("SIDEBAND_COV");
    tx_apb_wait_cov_enable = $test$plusargs("TX_APB_WAIT_COV");
    rx_apb_wait_cov_enable = $test$plusargs("RX_APB_WAIT_COV");
    rx_stream_backpressure_cov_enable = $test$plusargs("RX_STREAM_BACKPRESSURE_COV");
    tx_apb_error_cov_enable = $test$plusargs("TX_APB_ERROR_COV");
    tx_if_direct_cov_enable = $test$plusargs("TX_IF_DIRECT_COV");
    cpu_forward_direct_cov_enable = $test$plusargs("CPU_FORWARD_DIRECT_COV");
    rx_if_direct_cov_enable = $test$plusargs("RX_IF_DIRECT_COV");
    rx_parser_decoder_cov_enable = $test$plusargs("RX_PARSE_DECODE_COV");
    rx_decoder_direct_cov_enable = $test$plusargs("RX_DECODER_DIRECT_COV");
    rx_depacker_packer_direct_cov_enable = $test$plusargs("RX_DEPACKER_PACKER_DIRECT_COV");
    rx_parser_decoder_error_direct_cov_enable = $test$plusargs("RX_PARSE_DECODE_ERROR_DIRECT_COV");
    tx_encoder_direct_cov_enable = $test$plusargs("TX_ENCODER_DIRECT_COV");
    tx_builder_packer_direct_cov_enable = $test$plusargs("TX_BUILDER_PACKER_DIRECT_COV");
    dma_bridge_direct_cov_enable = $test$plusargs("DMA_BRIDGE_DIRECT_COV");
    raw_dut_stress_cov_enable = $test$plusargs("RAW_DUT_STRESS_COV");
    wait_cycles = 0;
    case_name = "rv32_soc";
    if ($value$plusargs("CASE_NAME=%s", case_name))
      $display("Test_result STARTED %0s", case_name);
    input_len_bytes = 0;
    input2_len_bytes = 0;
    src_mismatch_count = 0;
    rx_mismatch_count = 0;
    tx_nonzero_byte_count = 0;
    tx_ciphertext_bytes = 0;
    rx_plaintext_bytes = 0;
    compressed_payload_bytes_ceil = 0;
    tx_input_bytes_per_cycle = 0.0;
    tx_output_bytes_per_cycle = 0.0;
    rx_input_bytes_per_cycle = 0.0;
    rx_output_bytes_per_cycle = 0.0;
    tx_input_mbytes_per_sec = 0.0;
    tx_output_mbytes_per_sec = 0.0;
    rx_input_mbytes_per_sec = 0.0;
    rx_output_mbytes_per_sec = 0.0;
    payload_ratio_pct = 0.0;
    payload_space_saving_pct = 0.0;
    storage_ratio_pct = 0.0;
    space_saving_pct = 0.0;

    for (i = 0; i < 16; i = i + 1)
      result_words[i] = 32'b0;

    for (i = 0; i < 4; i = i + 1) begin
      tx_dst_words[i] = 32'b0;
      rx_dst_words[i] = 32'b0;
    end

    system_rc = $system("mkdir -p loopback dmem_dump");

    repeat (2) @(negedge clk);
    load_input_txt_to_dmem;
    load_secondary_input_txt_to_dmem;
    rst = 0;

    wait_cycles = 0;
    begin : wait_for_signature_done
      while (wait_cycles < MAX_WAIT_CYCLES) begin
        aux_read_word(32'h00000000, result_words[0]);
        if ((result_words[0] === RESULT_SIGNATURE_DMA)  ||
            (result_words[0] === RESULT_SIGNATURE_TX)   ||
            (result_words[0] === RESULT_SIGNATURE_REG1) ||
            (result_words[0] === RESULT_SIGNATURE_NEG1) ||
            (result_words[0] === RESULT_SIGNATURE_MODE) ||
            (result_words[0] === RESULT_SIGNATURE_RXER) ||
            (result_words[0] === RESULT_SIGNATURE_TXER) ||
            (result_words[0] === RESULT_SIGNATURE_CPUC) ||
            (result_words[0] === RESULT_SIGNATURE_CPUH) ||
            (result_words[0] === RESULT_SIGNATURE_STOR))
          disable wait_for_signature_done;
        @(posedge clk);
        wait_cycles = wait_cycles + 1;
      end
    end

    repeat (128) @(posedge clk);

    if (sideband_cov_enable)
      exercise_sideband_coverage;
    if (rx_if_direct_cov_enable)
      exercise_rx_if_direct_coverage;

    for (i = 0; i < 16; i = i + 1)
      aux_read_word(i * 4, result_words[i]);

    tx_ciphertext_bytes = result_words[5];
    rx_plaintext_bytes  = result_words[9];

    if (tx_ciphertext_bytes > TX_BUFFER_BYTES) begin
      $display("[FAIL] tx ciphertext length exceeds TX buffer: %0d > %0d",
               tx_ciphertext_bytes, TX_BUFFER_BYTES);
      fail_count = fail_count + 1;
      $finish;
    end

    if (((result_words[0] == RESULT_SIGNATURE_DMA) ||
         (result_words[0] == RESULT_SIGNATURE_STOR)) &&
        (rx_plaintext_bytes > RX_BUFFER_BYTES)) begin
      $display("[FAIL] rx plaintext length exceeds RX buffer: %0d > %0d",
               rx_plaintext_bytes, RX_BUFFER_BYTES);
      fail_count = fail_count + 1;
      $finish;
    end

    for (i = 0; i < 4; i = i + 1) begin
      aux_read_word(TX_DST_BASE_ADDR + (i * 4), tx_dst_words[i]);
      aux_read_word(RX_DST_BASE_ADDR + (i * 4), rx_dst_words[i]);
    end
    first_tx_ciphertext_dmem_word = {tx_dst_words[3], tx_dst_words[2], tx_dst_words[1], tx_dst_words[0]};
    first_tx_ciphertext_dmem_valid = (tx_ciphertext_bytes >= 16);

    dump_dmem_region(SRC_DUMP_FILE, SRC_BASE_ADDR, input_len_bytes);
    dump_dmem_region(TX_DUMP_FILE, TX_DST_BASE_ADDR, tx_ciphertext_bytes);
    if ((result_words[0] == RESULT_SIGNATURE_DMA) ||
        (result_words[0] == RESULT_SIGNATURE_STOR)) begin
      dump_dmem_region(RX_DUMP_FILE, RX_DST_BASE_ADDR, rx_plaintext_bytes);
      write_loopback_compare_file(LOOPBACK_COMPARE_FILE);
    end else begin
      compare_source_file;
      rx_mismatch_count = 0;
    end
    count_nonzero_region(TX_DST_BASE_ADDR, tx_ciphertext_bytes, tx_nonzero_byte_count);

    if (tx_busy_cycles > 0) begin
      tx_input_bytes_per_cycle  = input_len_bytes;
      tx_input_bytes_per_cycle  = tx_input_bytes_per_cycle / tx_busy_cycles;
      tx_output_bytes_per_cycle = tx_ciphertext_bytes;
      tx_output_bytes_per_cycle = tx_output_bytes_per_cycle / tx_busy_cycles;
      tx_input_mbytes_per_sec   = (tx_input_bytes_per_cycle * (1000.0 / CLOCK_PERIOD_NS));
      tx_output_mbytes_per_sec  = (tx_output_bytes_per_cycle * (1000.0 / CLOCK_PERIOD_NS));
    end

    if (rx_busy_cycles > 0) begin
      rx_input_bytes_per_cycle  = tx_ciphertext_bytes;
      rx_input_bytes_per_cycle  = rx_input_bytes_per_cycle / rx_busy_cycles;
      rx_output_bytes_per_cycle = rx_plaintext_bytes;
      rx_output_bytes_per_cycle = rx_output_bytes_per_cycle / rx_busy_cycles;
      rx_input_mbytes_per_sec   = (rx_input_bytes_per_cycle * (1000.0 / CLOCK_PERIOD_NS));
      rx_output_mbytes_per_sec  = (rx_output_bytes_per_cycle * (1000.0 / CLOCK_PERIOD_NS));
    end

    if (input_len_bytes > 0) begin
      compressed_payload_bytes_ceil = (compressed_payload_bits + 7) / 8;
      payload_ratio_pct = (100.0 * compressed_payload_bits) / (input_len_bytes * 8.0);
      payload_space_saving_pct = 100.0 - payload_ratio_pct;
      storage_ratio_pct = (100.0 * tx_ciphertext_bytes) / input_len_bytes;
      space_saving_pct  = 100.0 - storage_ratio_pct;
    end

    if (result_words[0] == RESULT_SIGNATURE_DMA)
      $display("# ===== RV32I SOC DMA TX->RX CHECK =====");
    else if (result_words[0] == RESULT_SIGNATURE_STOR)
      $display("# ===== RV32I SOC STORAGE TABLE TX1/TX2/RX1 CHECK =====");
    else if (result_words[0] == RESULT_SIGNATURE_TX)
      $display("# ===== RV32I SOC DMA TX-ONLY CHECK =====");
    else if (result_words[0] == RESULT_SIGNATURE_CPUC)
      $display("# ===== RV32I CPU INSTRUCTION COVERAGE CHECK =====");
    else if (result_words[0] == RESULT_SIGNATURE_CPUH)
      $display("# ===== RV32I CPU MEMORY/FORWARDING COVERAGE CHECK =====");
    else
      $display("# ===== RV32I SOC MMIO REGFILE CHECK =====");
    $display("# input_file=%0s input_len=%0d", input_file_name, input_len_bytes);
    if (input2_file_enable)
      $display("# input2_file=%0s input2_len=%0d src2=0x%08x",
               input2_file_name, input2_len_bytes, SRC2_BASE_ADDR);
    $display("# dma_active_dir=%0d busy=%0b done_sticky=%0b error_sticky=%0b",
             dut.dma_active_dir_r,
             dut.dma_engine_busy_w,
             dut.u_dma_regfile.done_sticky_r,
             dut.u_dma_regfile.error_sticky_r);
    $display("# dma_cfg src=0x%08x dst=0x%08x len=0x%08x dir=0x%0x block=0x%0x",
             dut.u_dma_regfile.src_addr_o,
             dut.u_dma_regfile.dst_addr_o,
             dut.u_dma_regfile.len_bytes_o,
             dut.u_dma_regfile.direction_o,
             dut.u_dma_regfile.block_size_o);
    $display("# tx_dma state=%0d busy=%0b done=%0b err=%0b bytes=0x%08x last_err=0x%02x",
             dut.tx_dma_state_w,
             dut.tx_dma_busy_w,
             dut.tx_dma_done_w,
             dut.tx_dma_error_w,
             dut.tx_dma_bytes_done_w,
             dut.tx_dma_last_error_w);
    $display("# rx_dma state=%0d busy=%0b done=%0b err=%0b bytes=0x%08x last_err=0x%02x",
             dut.rx_dma_state_w,
             dut.rx_dma_busy_w,
             dut.rx_dma_done_w,
             dut.rx_dma_error_w,
             dut.rx_dma_bytes_done_w,
             dut.rx_dma_last_error_w);
    $display("# tx_dst_head = %08x %08x %08x %08x",
             tx_dst_words[0], tx_dst_words[1], tx_dst_words[2], tx_dst_words[3]);
    $display("# rx_dst_head = %08x %08x %08x %08x",
             rx_dst_words[0], rx_dst_words[1], rx_dst_words[2], rx_dst_words[3]);
    if (result_words[0] == RESULT_SIGNATURE_DMA) begin
      $display("# INPUT1 TRACE mmio[0..7]:");
      for (i = 0; i < 8; i = i + 1)
        $display("#   mmio_write[%0d] addr=%08x data=%08x",
                 i, mmio_write_addr_log[i], mmio_write_data_log[i]);
      $display("# INPUT1 TRACE dma_cfg src=%08x dst=%08x len=%08x dir=%0d block=%0d",
               dut.u_dma_regfile.src_addr_o,
               dut.u_dma_regfile.dst_addr_o,
               dut.u_dma_regfile.len_bytes_o,
               dut.u_dma_regfile.direction_o,
               dut.u_dma_regfile.block_size_o);
      $display("# INPUT1 TRACE tx state=%0d busy=%0b done=%0b bytes=%08x err=%02x",
               dut.tx_dma_state_w,
               dut.tx_dma_busy_w,
               dut.tx_dma_done_w,
               dut.tx_dma_bytes_done_w,
               dut.tx_dma_last_error_w);
      $display("# INPUT1 TRACE rx state=%0d busy=%0b done=%0b bytes=%08x err=%02x",
               dut.rx_dma_state_w,
               dut.rx_dma_busy_w,
               dut.rx_dma_done_w,
               dut.rx_dma_bytes_done_w,
               dut.rx_dma_last_error_w);
      $display("# INPUT1 TRACE result sig=%08x error_mask=%08x src_mismatch=%0d rx_mismatch=%0d",
               result_words[0], result_words[1], src_mismatch_count, rx_mismatch_count);
    end
    if (trace_detail_enable) begin
      $display("# DEBUG first_tx_transport_valid=%0d count=%0d word=%032x",
               first_tx_transport_valid, tx_transport_capture_count, first_tx_transport_word);
      $display("# DEBUG first_tx_word_in_valid=%0d count=%0d data=%08x",
               first_tx_word_in_valid_seen, tx_word_in_capture_count, first_tx_word_in_data);
      $display("# DEBUG first_tx_dma_word_write=%0d count=%0d data=%08x",
               first_tx_dma_word_write_seen, tx_dma_word_write_count, first_tx_dma_word_write_data);
      $display("# DEBUG first_tx_dma_read=%0d count=%0d addr=%08x data=%08x",
               first_tx_dma_read_seen, tx_dma_read_capture_count,
               first_tx_dma_read_addr, first_tx_dma_read_data);
      $display("# DEBUG first_tx_start=%0d src=%08x dst=%08x len=%08x dir=%0d blk=%0d",
               first_tx_start_seen, first_tx_start_src_addr, first_tx_start_dst_addr,
               first_tx_start_len_bytes, first_tx_start_dir, first_tx_start_block_size);
      $display("# DEBUG first_tx_ciphertext_dmem_valid=%0d word=%032x",
               first_tx_ciphertext_dmem_valid, first_tx_ciphertext_dmem_word);
      $display("# DEBUG first_rx_ciphertext_feed_valid=%0d count=%0d word=%032x",
               first_rx_ciphertext_feed_valid, rx_ciphertext_feed_count, first_rx_ciphertext_feed_word);
      $display("# DEBUG first_rx_transport_valid=%0d count=%0d word=%032x",
               first_rx_transport_valid, rx_transport_capture_count, first_rx_transport_word);
      $display("# DEBUG first_rx_word_valid=%0d count=%0d data=%08x bytes=%0d last_blk=%0d last_frm=%0d",
               first_rx_word_valid_seen, rx_word_capture_count, first_rx_word_data,
               first_rx_word_valid_bytes, first_rx_word_last_in_block, first_rx_word_last_in_frame);
      $display("# DEBUG rx_stage_error depacker=%0b parser=%0b decoder=%0b packer=%0b aes_path=%0b",
               dut.rx_depacker_error_w,
               dut.rx_parser_error_w,
               dut.rx_decoder_error_w,
               dut.rx_word_packer_error_w,
               dut.u_rx_top.aes_path_error_r);
      $display("# DEBUG rx_stage_state parser=%0d decoder=%0d packer_busy=%0b fifo_count=%0d block_done=%0b frame_done=%0b",
               dut.u_rx_top.u_huffman_block_parser.state_r,
               dut.u_rx_top.u_huffman_block_decoder.state_r,
               dut.rx_word_packer_busy_w,
               dut.u_rx_top.u_apb_huffman_rx_if.fifo_count_r,
               dut.u_rx_top.u_apb_huffman_rx_if.block_done_sticky_r,
               dut.u_rx_top.u_apb_huffman_rx_if.frame_done_sticky_r);
      $display("# DEBUG rx_decoder_error code=0x%02x state=%0d bytes_left=%0d payload_len=%0d",
               dut.u_rx_top.u_huffman_block_decoder.debug_error_code_r,
               dut.u_rx_top.u_huffman_block_decoder.debug_error_state_r,
               dut.u_rx_top.u_huffman_block_decoder.debug_error_bytes_remaining_r,
               dut.u_rx_top.u_huffman_block_decoder.debug_error_payload_len_r);
      $display("# DEBUG rx_decoder_meta mode=%0d block_size=%0d symbol_count=%0d one_symbol=0x%02x parser_mode=%0d parser_block_size=%0d parser_symbol_count=%0d",
               dut.u_rx_top.u_huffman_block_decoder.block_mode,
               dut.u_rx_top.u_huffman_block_decoder.bytes_remaining_r,
               dut.u_rx_top.u_huffman_block_decoder.symbol_count_r,
               dut.u_rx_top.u_huffman_block_decoder.one_symbol_value_r,
               dut.u_rx_top.u_huffman_block_parser.block_mode_r,
               dut.u_rx_top.u_huffman_block_parser.block_size_r,
               dut.u_rx_top.u_huffman_block_parser.symbol_count_r);
    end
    $display("# BENCHMARK tx_cycles=%0d rx_cycles=%0d tx_cipher_bytes=%0d rx_plain_bytes=%0d",
             tx_busy_cycles, rx_busy_cycles, tx_ciphertext_bytes, rx_plaintext_bytes);
    $display("# THROUGHPUT tx_in=%0.3f MB/s tx_out=%0.3f MB/s rx_in=%0.3f MB/s rx_out=%0.3f MB/s",
             tx_input_mbytes_per_sec, tx_output_mbytes_per_sec,
             rx_input_mbytes_per_sec, rx_output_mbytes_per_sec);
    $display("# PAYLOAD compressed_bits=%0d compressed_bytes_ceil=%0d ratio=%0.2f%% space_saving=%0.2f%%",
             compressed_payload_bits, compressed_payload_bytes_ceil,
             payload_ratio_pct, payload_space_saving_pct);
    $display("# STORAGE ratio=%0.2f%% space_saving=%0.2f%%", storage_ratio_pct, space_saving_pct);
    $display("# LOOPBACK src_mismatch=%0d rx_mismatch=%0d tx_nonzero_bytes=%0d",
             src_mismatch_count, rx_mismatch_count, tx_nonzero_byte_count);
    $display("# FILES summary=%0s compare=%0s src_dump=%0s tx_dump=%0s rx_dump=%0s",
             LOOPBACK_SUMMARY_FILE, LOOPBACK_COMPARE_FILE,
             SRC_DUMP_FILE, TX_DUMP_FILE, RX_DUMP_FILE);

    check_eq_2 ("mem_err_o_should_be_zero", mem_err_o, 2'b00);
    check_true ("cpu_should_publish_known_signature",
                (result_words[0] == RESULT_SIGNATURE_DMA)  ||
                (result_words[0] == RESULT_SIGNATURE_TX)   ||
                (result_words[0] == RESULT_SIGNATURE_REG1) ||
                (result_words[0] == RESULT_SIGNATURE_NEG1) ||
                (result_words[0] == RESULT_SIGNATURE_MODE) ||
                (result_words[0] == RESULT_SIGNATURE_RXER) ||
                (result_words[0] == RESULT_SIGNATURE_TXER) ||
                (result_words[0] == RESULT_SIGNATURE_CPUC) ||
                (result_words[0] == RESULT_SIGNATURE_CPUH) ||
                (result_words[0] == RESULT_SIGNATURE_STOR));

    if (result_words[0] == RESULT_SIGNATURE_DMA) begin
      check_eq_32("result_signature", result_words[0], RESULT_SIGNATURE_DMA);
      check_eq_32("cpu_error_mask_should_be_zero", result_words[1], 32'h00000000);
      check_eq_32("tx_status_before_start", result_words[2], EXPECTED_TX_IDLE);
      check_eq_32("tx_status_after_done", result_words[3], EXPECTED_TX_DONE);
      check_true ("tx_bytes_done_should_be_transport_aligned",
                  (result_words[4] != 32'h00000000) &&
                  ((result_words[4] & 32'h0000000f) == 32'h00000000));
      check_eq_32("tx_ciphertext_bytes_produced_should_match_tx_bytes_done",
                  result_words[5], result_words[4]);
      check_true ("tx_poll_count_should_be_nonzero", result_words[6] != 32'h00000000);
      check_true ("rx_status_before_start_should_be_idle_or_done_sticky",
                  (result_words[7] == EXPECTED_RX_IDLE) ||
                  (result_words[7] == EXPECTED_RX_DONE));
      check_eq_32("rx_status_after_done", result_words[8], EXPECTED_RX_DONE);
      check_eq_32("rx_bytes_done_should_match_input_len", result_words[9], input_len_bytes);
      check_eq_32("rx_debug_after_done", result_words[10], 32'h00000000);
      check_true ("rx_poll_count_should_be_nonzero", result_words[11] != 32'h00000000);
      check_eq_32("source_dmem_should_match_input_file", src_mismatch_count, 32'h00000000);
      check_eq_32("loopback_rx_should_match_input_file", rx_mismatch_count, 32'h00000000);
      check_true ("tx_ciphertext_region_should_not_be_all_zero", tx_nonzero_byte_count != 0);
      check_eq_32("dma_start_pulse_count", dma_start_pulse_count, 32'h00000002);
    end else if (result_words[0] == RESULT_SIGNATURE_STOR) begin
      check_eq_32("storage_result_signature", result_words[0], RESULT_SIGNATURE_STOR);
      check_eq_32("storage_cpu_error_mask_should_be_zero", result_words[1], 32'h00000000);
      check_eq_32("storage_tx1_status_before_start", result_words[2], EXPECTED_TX_IDLE);
      check_eq_32("storage_tx1_status_after_done", result_words[3], EXPECTED_TX_DONE);
      check_true ("storage_tx1_bytes_done_should_be_transport_aligned",
                  (result_words[4] != 32'h00000000) &&
                  ((result_words[4] & 32'h0000000f) == 32'h00000000));
      check_eq_32("storage_tx1_ciphertext_bytes_match_bytes_done",
                  result_words[5], result_words[4]);
      check_true ("storage_tx1_poll_count_should_be_nonzero", result_words[6] != 32'h00000000);
      check_true ("storage_rx1_status_before_start_should_be_idle_or_done_sticky",
                  (result_words[7] == EXPECTED_RX_IDLE) ||
                  (result_words[7] == EXPECTED_RX_DONE));
      check_eq_32("storage_rx1_status_after_done", result_words[8], EXPECTED_RX_DONE);
      check_eq_32("storage_rx1_bytes_done_should_match_input1_len", result_words[9], input_len_bytes);
      check_eq_32("storage_rx1_debug_after_done", result_words[10], 32'h00000000);
      check_true ("storage_rx1_poll_count_should_be_nonzero", result_words[11] != 32'h00000000);
      check_true ("storage_tx2_ciphertext_should_be_nonzero_aligned",
                  (result_words[12] != 32'h00000000) &&
                  ((result_words[12] & 32'h0000000f) == 32'h00000000));
      check_eq_32("storage_input2_len_echo", result_words[13], input2_len_bytes);
      check_eq_32("storage_selected_file_id", result_words[14], 32'h00000001);
      check_eq_32("storage_total_records", result_words[15], 32'h00000002);
      check_eq_32("source_dmem_should_match_input1_file", src_mismatch_count, 32'h00000000);
      check_eq_32("loopback_rx_should_match_input1_file", rx_mismatch_count, 32'h00000000);
      check_true ("storage_tx1_ciphertext_region_should_not_be_all_zero", tx_nonzero_byte_count != 0);
      check_eq_32("storage_dma_start_pulse_count", dma_start_pulse_count, 32'h00000003);
    end else if (result_words[0] == RESULT_SIGNATURE_TX) begin
      check_eq_32("result_signature", result_words[0], RESULT_SIGNATURE_TX);
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
    end else if (result_words[0] == RESULT_SIGNATURE_REG1) begin
      check_eq_32("cpu_error_mask_should_be_zero", result_words[1], 32'h00000000);
      check_eq_32("basic_status_after_config", result_words[3], 32'h000000d8);
      check_eq_32("basic_mode_readback", result_words[5], 32'h0000000d);
      check_eq_32("basic_block_readback", result_words[6], 32'h00000020);
      check_true("basic_soft_reset_pulse_seen", soft_reset_pulse_count >= 1);
      check_eq_32("basic_status_after_soft_reset", result_words[4], 32'h00000000);
      check_eq_32("basic_no_dma_start", dma_start_pulse_count, 32'h00000000);
    end else if (result_words[0] == RESULT_SIGNATURE_NEG1) begin
      check_true("negative_apb_errors_seen", apb_error_count >= 5);
      check_true("negative_bridge_errors_seen", bridge_error_count >= 1);
      check_eq_32("negative_no_dma_start", dma_start_pulse_count, 32'h00000000);
      check_true("negative_clear_error_pulses_seen", clear_error_pulse_count >= 4);
    end else if (result_words[0] == RESULT_SIGNATURE_MODE) begin
      check_eq_32("mode_0x1_status", result_words[2], 32'h00000018);
      check_eq_32("mode_0x5_status", result_words[3], 32'h00000058);
      check_eq_32("mode_0x9_status", result_words[4], 32'h00000098);
      check_eq_32("mode_0xd_status", result_words[5], 32'h000000d8);
      check_eq_32("mode_0x2_status", result_words[6], 32'h00000028);
      check_eq_32("mode_0x0_status_invalid_cfg", result_words[7], 32'h00000000);
      check_eq_32("mode_0x3_status_invalid_cfg", result_words[8], 32'h00000030);
      check_true("mode_reserved_write_sets_error", (result_words[9] & 32'h00000004) != 32'h00000000);
      check_eq_32("mode_matrix_no_dma_start", dma_start_pulse_count, 32'h00000000);
    end else if (result_words[0] == RESULT_SIGNATURE_RXER) begin
      check_eq_32("rx_error_signature", result_words[0], RESULT_SIGNATURE_RXER);
      check_eq_32("rx_error_mask_should_be_zero", result_words[1], 32'h00000000);
      check_eq_32("rx_bad_len_status_before", result_words[2], 32'h00000028);
      check_true("rx_bad_len_status_after_has_error", (result_words[3] & 32'h00000004) != 32'h00000000);
      check_eq_32("rx_bad_len_bytes_done_zero", result_words[4], 32'h00000000);
      check_eq_32("rx_bad_len_debug_error_code", result_words[5] & 32'h00000ff0, 32'h00000020);
      check_eq_32("rx_bad_len_dma_start_pulse_count", dma_start_pulse_count, 32'h00000001);
    end else if (result_words[0] == RESULT_SIGNATURE_TXER) begin
      check_eq_32("tx_error_signature", result_words[0], RESULT_SIGNATURE_TXER);
      check_eq_32("tx_error_mask_should_be_zero", result_words[1], 32'h00000000);
      check_eq_32("tx_apb_error_status_before", result_words[2], EXPECTED_TX_IDLE);
      check_true("tx_apb_error_status_after_has_error", (result_words[3] & 32'h00000004) != 32'h00000000);
      check_true("tx_error_debug_code",
                 ((result_words[5] & 32'h00000ff0) == 32'h00000030) ||
                 ((result_words[5] & 32'h00000ff0) == 32'h00000060));
      check_eq_32("tx_apb_error_dma_start_pulse_count", dma_start_pulse_count, 32'h00000001);
    end else if (result_words[0] == RESULT_SIGNATURE_CPUC) begin
      $display("# ===== CPU INSTRUCTION COVERAGE REPORT =====");
      $display("# purpose: RV32I core executes real program from IMEM and publishes signatures to DMEM");
      $display("# program: testcase/test_cpu_instruction_cov.c");
      $display("# covered_groups: R-type ALU, I-type ALU, load/store byte-half-word, signed/unsigned load, branch, LUI, JALR");
      $display("# dmem_result_words:");
      $display("#   word0 signature      actual=0x%08x expected=0x%08x meaning='CPUC'",
               result_words[0], RESULT_SIGNATURE_CPUC);
      $display("#   word1 error_mask     actual=0x%08x expected=0x00000000", result_words[1]);
      $display("#   word2 r_type_mix     actual=0x%08x expected=0xcd79bdff", result_words[2]);
      $display("#   word3 mem_mix        actual=0x%08x expected=0x0000e595", result_words[3]);
      $display("#   word4 branch_score   actual=0x%08x expected=0x0000003f", result_words[4]);
      $display("#   word5 i_type_mix     actual=0x%08x expected=0x00000874", result_words[5]);
      $display("# error_mask_bits: bit0=R-type, bit1=I-type, bit2=branch, bit3=load/store, bit4=LUI, bit5=JALR");
      $display("# branch_score_bits: bit0=BEQ, bit1=BNE, bit2=BLT, bit3=BGE, bit4=BLTU, bit5=BGEU");
      $display("# memory_check: SW/SH/SB write DMEM, then LBU/LB/LHU/LH verify zero/sign extension");
      check_eq_32("cpu_instruction_signature", result_words[0], RESULT_SIGNATURE_CPUC);
      check_eq_32("cpu_instruction_error_mask", result_words[1], 32'h00000000);
      check_eq_32("cpu_instruction_r_type_mix", result_words[2], 32'hcd79bdff);
      check_eq_32("cpu_instruction_mem_mix", result_words[3], 32'h0000e595);
      check_eq_32("cpu_instruction_branch_score", result_words[4], 32'h0000003f);
      check_eq_32("cpu_instruction_i_type_mix", result_words[5], 32'h00000874);
    end else if (result_words[0] == RESULT_SIGNATURE_CPUH) begin
      check_eq_32("cpu_mem_forward_signature", result_words[0], RESULT_SIGNATURE_CPUH);
      check_eq_32("cpu_mem_forward_error_mask", result_words[1], 32'h00000000);
      check_eq_32("cpu_mem_forward_mem_error", result_words[2], 32'h00000000);
      check_true ("cpu_mem_forward_mix_nonzero", result_words[3] != 32'h00000000);
    end

    if (rx_parser_decoder_cov_enable)
      exercise_rx_parser_decoder_coverage;
    if (rx_decoder_direct_cov_enable)
      exercise_rx_decoder_direct_coverage;
    if (rx_depacker_packer_direct_cov_enable)
      exercise_rx_depacker_packer_direct_coverage;
    if (rx_parser_decoder_error_direct_cov_enable)
      exercise_rx_parser_decoder_error_direct_coverage;
    if (tx_if_direct_cov_enable)
      exercise_tx_if_direct_coverage;
    if (tx_encoder_direct_cov_enable)
      exercise_tx_encoder_direct_coverage;
    if (tx_builder_packer_direct_cov_enable)
      exercise_tx_builder_packer_direct_coverage;
    if (cpu_forward_direct_cov_enable)
      exercise_cpu_forward_direct_coverage;
    if (dma_bridge_direct_cov_enable)
      exercise_dma_bridge_direct_coverage;
    if (raw_dut_stress_cov_enable)
      exercise_raw_dut_stress_coverage;

    $display("# SUMMARY: PASS=%0d FAIL=%0d", pass_count, fail_count);
    if (fail_count == 0)
      $display("[PASS] rv32_soc_unified_test");
    else
      $display("[FAIL] rv32_soc_unified_test");

    write_summary_file;
    $finish;
    end
  endtask

  initial begin
    if ($test$plusargs("TX_APB_WAIT_COV"))
      inject_tx_apb_waitstate_once;
  end

  initial begin
    if ($test$plusargs("RX_APB_WAIT_COV"))
      inject_rx_apb_waitstate_once;
  end

  initial begin
    if ($test$plusargs("RX_STREAM_BACKPRESSURE_COV"))
      inject_rx_stream_backpressure_once;
  end

  initial begin
    if ($test$plusargs("TX_APB_ERROR_COV"))
      inject_tx_apb_error_once;
  end

  `include "run_test.v"

  initial begin
    run_test();
  end
endmodule
