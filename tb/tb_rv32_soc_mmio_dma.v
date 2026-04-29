`timescale 1ns / 1ps

module test_bench;
  localparam integer MAX_WAIT_CYCLES = 1000000;
  localparam integer MAX_INPUT_BYTES = 10000;
  localparam integer DMEM_SIZE_BYTES = 32768;
  localparam integer TRANSPORT_WORD_WIDTH = 128;
  localparam integer VALID_BITS_WIDTH = 7;
  localparam real    CLOCK_PERIOD_NS = 10.0;

  localparam [31:0] RESULT_SIGNATURE = 32'h44525831;
  localparam [31:0] EXPECTED_TX_IDLE = 32'h00000098;
  localparam [31:0] EXPECTED_TX_DONE = 32'h0000009a;
  localparam [31:0] EXPECTED_RX_IDLE = 32'h00000028;
  localparam [31:0] EXPECTED_RX_DONE = 32'h0000002a;

  localparam [31:0] INPUT_LEN_ADDR   = 32'h00000040;
  localparam [31:0] SRC_BASE_ADDR    = 32'h00000400;
  localparam [31:0] TX_DST_BASE_ADDR = 32'h00002000;
  localparam [31:0] RX_DST_BASE_ADDR = 32'h00004000;

  localparam integer SRC_BUFFER_BYTES = TX_DST_BASE_ADDR - SRC_BASE_ADDR;
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
  integer wait_cycles;
  integer system_rc;
  integer i;

  integer input_len_bytes;
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

  reg tx_seen_busy;
  reg rx_seen_busy;
  reg tx_busy_prev;
  reg rx_busy_prev;
  reg [8*32-1:0] input_file_name;

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

  initial begin
    input_file_name = "input1.txt";
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
      fd = $fopen(LOOPBACK_SUMMARY_FILE, "w");
      if (fd == 0) begin
        $display("[FAIL] cannot open summary file: %0s", LOOPBACK_SUMMARY_FILE);
        fail_count = fail_count + 1;
        $finish;
      end

      $fdisplay(fd, "input_file=%0s", input_file_name);
      $fdisplay(fd, "input_len_bytes=%0d", input_len_bytes);
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
    rst = 0;

    wait_cycles = 0;
    while ((wait_cycles < MAX_WAIT_CYCLES) &&
           ((dut.u_dma_regfile.done_sticky_r !== 1'b1) || dut.dma_engine_busy_w)) begin
      @(posedge clk);
      wait_cycles = wait_cycles + 1;
    end

    repeat (256) @(posedge clk);

    begin : wait_for_signature_done
      while (wait_cycles < (MAX_WAIT_CYCLES + 50000)) begin
        aux_read_word(32'h00000000, result_words[0]);
        if (result_words[0] === RESULT_SIGNATURE)
          disable wait_for_signature_done;
        wait_cycles = wait_cycles + 1;
      end
    end

    repeat (128) @(posedge clk);

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

    if (rx_plaintext_bytes > RX_BUFFER_BYTES) begin
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
    dump_dmem_region(RX_DUMP_FILE, RX_DST_BASE_ADDR, rx_plaintext_bytes);
    write_loopback_compare_file(LOOPBACK_COMPARE_FILE);
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

    $display("# ===== RV32I SOC DMA TX->RX CHECK =====");
    $display("# input_file=%0s input_len=%0d", input_file_name, input_len_bytes);
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
    for (i = 0; i < 8; i = i + 1) begin
      $display("# DEBUG mmio_write[%0d] addr=%08x data=%08x",
               i, mmio_write_addr_log[i], mmio_write_data_log[i]);
    end
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
    check_true ("cpu_should_publish_result_signature_before_timeout", result_words[0] == RESULT_SIGNATURE);
    check_eq_32("result_signature", result_words[0], RESULT_SIGNATURE);
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

    $display("# SUMMARY: PASS=%0d FAIL=%0d", pass_count, fail_count);
    if (fail_count == 0)
      $display("[PASS] rv32_soc_dma_tx_rx_test");
    else
      $display("[FAIL] rv32_soc_dma_tx_rx_test");

    write_summary_file;
    $finish;
    end
  endtask

  `include "run_test.v"

  initial begin
    run_test();
  end
endmodule
