`timescale 1ns / 1ps

module tb_rv32_sensor_phi_preprocess_rv32;
  localparam integer MAX_WAIT_CYCLES = 2000000;
  localparam integer MAX_INPUT_BYTES = 10000;
  localparam integer DMEM_SIZE_BYTES = 32768;
  localparam real    CLOCK_PERIOD_NS = 10.0;

  localparam [31:0] RESULT_SIGNATURE = 32'h53505231;
  localparam [31:0] MAGIC_SPH1       = 32'h31485053;
  localparam [31:0] EXPECTED_TX_IDLE = 32'h00000018;
  localparam [31:0] EXPECTED_TX_DONE = 32'h0000001a;

  localparam [31:0] INPUT_LEN_ADDR            = 32'h00000040;
  localparam [31:0] PREPROC_LEN_ADDR          = 32'h00000044;
  localparam [31:0] SRC_BASE_ADDR             = 32'h00000400;
  localparam [31:0] PREPROC_BASE_ADDR         = 32'h00002000;
  localparam [31:0] RAW_TX_DST_BASE_ADDR      = 32'h00004000;
  localparam [31:0] PREPROC_TX_DST_BASE_ADDR  = 32'h00006000;

  localparam integer SRC_BUFFER_BYTES         = PREPROC_BASE_ADDR - SRC_BASE_ADDR;
  localparam integer PREPROC_BUFFER_BYTES     = RAW_TX_DST_BASE_ADDR - PREPROC_BASE_ADDR;
  localparam integer RAW_TX_BUFFER_BYTES      = PREPROC_TX_DST_BASE_ADDR - RAW_TX_DST_BASE_ADDR;
  localparam integer PREPROC_TX_BUFFER_BYTES  = DMEM_SIZE_BYTES - PREPROC_TX_DST_BASE_ADDR;

  localparam [8*72-1:0] SUMMARY_FILE      = "preprocess/tb_rv32_sensor_phi_preprocess_rv32_summary.txt";
  localparam [8*72-1:0] SRC_DUMP_FILE     = "dmem_dump/tb_rv32_sensor_phi_preprocess_rv32_src.txt";
  localparam [8*72-1:0] PREPROC_DUMP_FILE = "dmem_dump/tb_rv32_sensor_phi_preprocess_rv32_preproc.txt";
  localparam [8*72-1:0] RAW_TX_DUMP_FILE  = "dmem_dump/tb_rv32_sensor_phi_preprocess_rv32_raw_tx.txt";
  localparam [8*72-1:0] PRE_TX_DUMP_FILE  = "dmem_dump/tb_rv32_sensor_phi_preprocess_rv32_pre_tx.txt";

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
  integer input_len_bytes;
  integer preproc_len_bytes;
  integer record_count;
  integer raw_tx_cipher_bytes;
  integer pre_tx_cipher_bytes;
  integer raw_tx_nonzero_count;
  integer pre_tx_nonzero_count;
  integer preproc_mismatch_count;
  integer idx;
  integer fd;
  integer ch;
  integer word_idx;
  integer lane_idx;
  integer host_rc;
  integer cycle_counter;
  integer raw_tx_busy_cycles;
  integer pre_tx_busy_cycles;
  integer tx_phase;

  reg tx_busy_prev;
  reg [31:0] result_words [0:15];
  reg [7:0] input_bytes [0:MAX_INPUT_BYTES-1];
  reg [7:0] golden_bytes [0:MAX_INPUT_BYTES-1];
  reg [8*40-1:0] input_file_name;
  reg [8*200-1:0] host_cmd;
  reg [31:0] packed_word;
  reg [7:0] byte_val;
  reg [31:0] aligned_word;

  real preprocess_ratio_pct;
  real raw_storage_ratio_pct;
  real pre_storage_ratio_pct;
  real tx_improvement_pct;

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
    input [7:0] byte_in;
    begin
      if ((byte_in >= 8'h20) && (byte_in <= 8'h7e))
        printable_byte = byte_in;
      else
        printable_byte = ".";
    end
  endfunction

  initial begin
    input_file_name = "input_sensor_phi.txt";
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
    input [8*80-1:0] name;
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
    input [8*80-1:0] name;
    input cond;
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
    input [31:0] addr;
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
    input [31:0] byte_addr;
    output [7:0] data;
    begin
      aux_read_word({byte_addr[31:2], 2'b00}, aligned_word);
      data = byte_from_word(aligned_word, byte_addr[1:0]);
    end
  endtask

  task automatic load_input_txt_to_dmem;
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

  task automatic load_host_golden;
    integer golden_len;
    begin
      for (idx = 0; idx < MAX_INPUT_BYTES; idx = idx + 1)
        golden_bytes[idx] = 8'h00;

      host_cmd = {"python3 ../testcase/sensor_phi_preprocess_host.py ", input_file_name,
                  " preprocess/host_sensor_phi_preprocessed.bin"};
      host_rc = $system(host_cmd);
      if (host_rc != 0) begin
        $display("[FAIL] host sensor preprocess failed rc=%0d", host_rc);
        fail_count = fail_count + 1;
        $finish;
      end

      golden_len = 0;
      fd = $fopen("preprocess/host_sensor_phi_preprocessed.bin", "rb");
      if (fd == 0) begin
        $display("[FAIL] cannot open preprocess/host_sensor_phi_preprocessed.bin");
        fail_count = fail_count + 1;
        $finish;
      end

      while (!$feof(fd)) begin
        ch = $fgetc(fd);
        if (ch != -1) begin
          golden_bytes[golden_len] = ch[7:0];
          golden_len = golden_len + 1;
        end
      end
      $fclose(fd);
      preproc_len_bytes = golden_len;
      $display("# Generated host golden preprocessed binary: %0d byte(s)", preproc_len_bytes);
    end
  endtask

  task automatic dump_dmem_region;
    input [8*72-1:0] file_name;
    input [31:0] base_addr;
    input integer byte_count;
    integer dump_fd;
    begin
      dump_fd = $fopen(file_name, "w");
      $fdisplay(dump_fd, "base_addr=0x%08x byte_count=%0d", base_addr, byte_count);
      $fdisplay(dump_fd, "idx addr byte ascii");
      for (idx = 0; idx < byte_count; idx = idx + 1) begin
        aux_read_byte(base_addr + idx, byte_val);
        $fdisplay(dump_fd, "%0d 0x%08x %02x %c",
                  idx, base_addr + idx, byte_val, printable_byte(byte_val));
      end
      $fclose(dump_fd);
    end
  endtask

  task automatic count_nonzero_region;
    input [31:0] base_addr;
    input integer byte_count;
    output integer nonzero_count;
    begin
      nonzero_count = 0;
      for (idx = 0; idx < byte_count; idx = idx + 1) begin
        aux_read_byte(base_addr + idx, byte_val);
        if (byte_val != 8'h00)
          nonzero_count = nonzero_count + 1;
      end
    end
  endtask

  task automatic compare_preproc_against_golden;
    begin
      preproc_mismatch_count = 0;
      for (idx = 0; idx < preproc_len_bytes; idx = idx + 1) begin
        aux_read_byte(PREPROC_BASE_ADDR + idx, byte_val);
        if (byte_val !== golden_bytes[idx])
          preproc_mismatch_count = preproc_mismatch_count + 1;
      end
    end
  endtask

  task automatic write_summary_file;
    integer summary_fd;
    begin
      summary_fd = $fopen(SUMMARY_FILE, "w");
      $fdisplay(summary_fd, "input_file=%0s", input_file_name);
      $fdisplay(summary_fd, "input_len_bytes=%0d", input_len_bytes);
      $fdisplay(summary_fd, "preproc_len_bytes=%0d", preproc_len_bytes);
      $fdisplay(summary_fd, "record_count=%0d", record_count);
      $fdisplay(summary_fd, "raw_tx_cipher_bytes=%0d", raw_tx_cipher_bytes);
      $fdisplay(summary_fd, "pre_tx_cipher_bytes=%0d", pre_tx_cipher_bytes);
      $fdisplay(summary_fd, "preproc_mismatch_count=%0d", preproc_mismatch_count);
      $fdisplay(summary_fd, "raw_tx_busy_cycles=%0d", raw_tx_busy_cycles);
      $fdisplay(summary_fd, "pre_tx_busy_cycles=%0d", pre_tx_busy_cycles);
      $fdisplay(summary_fd, "preprocess_ratio_pct=%0.2f", preprocess_ratio_pct);
      $fdisplay(summary_fd, "raw_storage_ratio_pct=%0.2f", raw_storage_ratio_pct);
      $fdisplay(summary_fd, "pre_storage_ratio_pct=%0.2f", pre_storage_ratio_pct);
      $fdisplay(summary_fd, "tx_improvement_pct=%0.2f", tx_improvement_pct);
      $fdisplay(summary_fd, "raw_tx_nonzero_count=%0d", raw_tx_nonzero_count);
      $fdisplay(summary_fd, "pre_tx_nonzero_count=%0d", pre_tx_nonzero_count);
      $fdisplay(summary_fd, "pass_count=%0d", pass_count);
      $fdisplay(summary_fd, "fail_count=%0d", fail_count);
      $fclose(summary_fd);
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
      raw_tx_busy_cycles    <= 0;
      pre_tx_busy_cycles    <= 0;
      tx_phase              <= 0;
      tx_busy_prev          <= 1'b0;
    end else begin
      cycle_counter <= cycle_counter + 1;
      if (dut.u_dma_regfile.start_pulse_o && (dut.u_dma_regfile.direction_o == 2'b01)) begin
        dma_start_pulse_count <= dma_start_pulse_count + 1;
        tx_phase <= tx_phase + 1;
      end
      if (dut.tx_dma_busy_w) begin
        if (tx_phase == 1)
          raw_tx_busy_cycles <= raw_tx_busy_cycles + 1;
        else if (tx_phase >= 2)
          pre_tx_busy_cycles <= pre_tx_busy_cycles + 1;
      end
      tx_busy_prev <= dut.tx_dma_busy_w;
    end
  end

  initial begin
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
    preproc_len_bytes = 0;
    record_count = 0;
    raw_tx_cipher_bytes = 0;
    pre_tx_cipher_bytes = 0;
    raw_tx_nonzero_count = 0;
    pre_tx_nonzero_count = 0;
    preproc_mismatch_count = 0;
    preprocess_ratio_pct = 0.0;
    raw_storage_ratio_pct = 0.0;
    pre_storage_ratio_pct = 0.0;
    tx_improvement_pct = 0.0;

    for (idx = 0; idx < 16; idx = idx + 1)
      result_words[idx] = 32'b0;

    host_rc = $system("mkdir -p preprocess dmem_dump");

    repeat (2) @(negedge clk);
    load_input_txt_to_dmem;
    load_host_golden;
    rst = 0;

    wait_cycles = 0;
    begin : wait_signature
      while (wait_cycles < MAX_WAIT_CYCLES) begin
        repeat (64) @(posedge clk);
        wait_cycles = wait_cycles + 64;
        aux_read_word(32'h00000000, result_words[0]);
        if (result_words[0] === RESULT_SIGNATURE)
          disable wait_signature;
      end
    end

    repeat (128) @(posedge clk);
    for (idx = 0; idx < 16; idx = idx + 1)
      aux_read_word(idx * 4, result_words[idx]);

    preproc_len_bytes = result_words[3];
    record_count = result_words[4];
    raw_tx_cipher_bytes = result_words[8];
    pre_tx_cipher_bytes = result_words[12];

    dump_dmem_region(SRC_DUMP_FILE, SRC_BASE_ADDR, input_len_bytes);
    dump_dmem_region(PREPROC_DUMP_FILE, PREPROC_BASE_ADDR, preproc_len_bytes);
    dump_dmem_region(RAW_TX_DUMP_FILE, RAW_TX_DST_BASE_ADDR, raw_tx_cipher_bytes);
    dump_dmem_region(PRE_TX_DUMP_FILE, PREPROC_TX_DST_BASE_ADDR, pre_tx_cipher_bytes);
    compare_preproc_against_golden;
    count_nonzero_region(RAW_TX_DST_BASE_ADDR, raw_tx_cipher_bytes, raw_tx_nonzero_count);
    count_nonzero_region(PREPROC_TX_DST_BASE_ADDR, pre_tx_cipher_bytes, pre_tx_nonzero_count);

    if (input_len_bytes > 0) begin
      preprocess_ratio_pct = (100.0 * preproc_len_bytes) / input_len_bytes;
      raw_storage_ratio_pct = (100.0 * raw_tx_cipher_bytes) / input_len_bytes;
      pre_storage_ratio_pct = (100.0 * pre_tx_cipher_bytes) / input_len_bytes;
    end
    if (raw_tx_cipher_bytes > 0)
      tx_improvement_pct = (100.0 * (raw_tx_cipher_bytes - pre_tx_cipher_bytes)) / raw_tx_cipher_bytes;

    $display("# ===== RV32I SENSOR PHI PREPROCESS TX BENCH =====");
    $display("# input_file=%0s input_len=%0d preproc_len=%0d records=%0d",
             input_file_name, input_len_bytes, preproc_len_bytes, record_count);
    $display("# raw_tx_cipher_bytes=%0d pre_tx_cipher_bytes=%0d improvement=%0.2f%%",
             raw_tx_cipher_bytes, pre_tx_cipher_bytes, tx_improvement_pct);
    $display("# preprocess_ratio=%0.2f%% raw_storage_ratio=%0.2f%% pre_storage_ratio=%0.2f%%",
             preprocess_ratio_pct, raw_storage_ratio_pct, pre_storage_ratio_pct);
    $display("# FILES summary=%0s src_dump=%0s preproc_dump=%0s raw_tx_dump=%0s pre_tx_dump=%0s",
             SUMMARY_FILE, SRC_DUMP_FILE, PREPROC_DUMP_FILE, RAW_TX_DUMP_FILE, PRE_TX_DUMP_FILE);

    check_eq_2 ("mem_err_o_should_be_zero", mem_err_o, 2'b00);
    check_true ("cpu_should_publish_result_signature_before_timeout", result_words[0] == RESULT_SIGNATURE);
    check_eq_32("result_signature", result_words[0], RESULT_SIGNATURE);
    check_eq_32("cpu_error_mask_should_be_zero", result_words[1], 32'h00000000);
    check_eq_32("input_len_should_match_loader", result_words[2], input_len_bytes);
    check_true ("preproc_len_should_be_nonzero", result_words[3] != 32'h00000000);
    check_true ("record_count_should_be_nonzero", result_words[4] != 32'h00000000);
    check_eq_32("raw_tx_status_before_should_be_idle", result_words[5], EXPECTED_TX_IDLE);
    check_eq_32("raw_tx_status_after_should_be_done", result_words[6], EXPECTED_TX_DONE);
    check_eq_32("raw_tx_cipher_bytes_should_match_bytes_done", result_words[8], result_words[7]);
    check_true ("pre_tx_status_before_should_be_idle_or_done",
                (result_words[9] == EXPECTED_TX_IDLE) || (result_words[9] == EXPECTED_TX_DONE));
    check_eq_32("pre_tx_status_after_should_be_done", result_words[10], EXPECTED_TX_DONE);
    check_eq_32("pre_tx_cipher_bytes_should_match_bytes_done", result_words[12], result_words[11]);
    check_eq_32("preproc_header_magic", result_words[13], MAGIC_SPH1);
    check_true ("preprocessed_tx_should_beat_raw_tx", result_words[12] < result_words[8]);
    check_eq_32("dma_start_pulse_count_should_be_two", dma_start_pulse_count, 32'h00000002);
    check_eq_32("preprocessed_binary_should_match_host_golden", preproc_mismatch_count, 32'h00000000);
    check_true ("raw_tx_region_should_not_be_all_zero", raw_tx_nonzero_count != 0);
    check_true ("pre_tx_region_should_not_be_all_zero", pre_tx_nonzero_count != 0);

    $display("# SUMMARY: PASS=%0d FAIL=%0d", pass_count, fail_count);
    if (fail_count == 0)
      $display("[PASS] rv32_sensor_phi_preprocess_tx_bench");
    else
      $display("[FAIL] rv32_sensor_phi_preprocess_tx_bench");

    write_summary_file;
    $finish;
  end
endmodule
