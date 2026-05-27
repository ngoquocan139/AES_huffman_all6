task run_test;
  reg [31:0] read_word0;
  reg [31:0] read_word1;
  reg [31:0] read_len;
  reg [7:0]  read_byte;
begin
  clk = 1'b0;
  rst = 1'b1;
  aux_en = 1'b0;
  aux_we = 4'b0000;
  aux_addr = 32'b0;
  aux_wdata = 32'b0;
  cpu_if_flush = 1'b0;
  cpu_stall = 1'b0;
  pass_count = 0;
  fail_count = 0;
  input_len_bytes = 6;
  input2_len_bytes = 0;
  input2_file_enable = 0;
  tx_ciphertext_bytes = 0;
  rx_plaintext_bytes = 0;
  compressed_payload_bits = 0;

  system_rc = $system("mkdir -p loopback dmem_dump");
  repeat (4) @(posedge clk);

  $display("# ===== DMEM LOAD/READBACK SMOKE CHECK =====");
  $display("# This testcase uses the standard make-all testbench path.");
  $display("# It verifies the DMEM aux-port contract used by the FPGA UART loader.");

  aux_write_word(SRC_BASE_ADDR + 32'h00000000, 32'h67452301);
  aux_write_word(SRC_BASE_ADDR + 32'h00000004, 32'hdeadbeef);

  aux_en    = 1'b1;
  aux_we    = 4'b0011;
  aux_addr  = SRC_BASE_ADDR + 32'h00000004;
  aux_wdata = 32'h0000ab89;
  @(posedge clk);
  #1;
  aux_en    = 1'b0;
  aux_we    = 4'b0000;
  aux_addr  = 32'b0;
  aux_wdata = 32'b0;

  aux_write_word(INPUT_LEN_ADDR, 32'd6);

  aux_read_word(SRC_BASE_ADDR + 32'h00000000, read_word0);
  aux_read_word(SRC_BASE_ADDR + 32'h00000004, read_word1);
  aux_read_word(INPUT_LEN_ADDR, read_len);

  check_eq_32("readback_word0_little_endian", read_word0, 32'h67452301);
  check_eq_32("readback_word1_byte_enable", read_word1, 32'hdeadab89);
  check_eq_32("readback_input_len_word", read_len, 32'd6);

  aux_read_byte(SRC_BASE_ADDR + 32'h00000000, read_byte);
  check_eq_32("readback_byte0", {24'd0, read_byte}, 32'h00000001);
  aux_read_byte(SRC_BASE_ADDR + 32'h00000001, read_byte);
  check_eq_32("readback_byte1", {24'd0, read_byte}, 32'h00000023);
  aux_read_byte(SRC_BASE_ADDR + 32'h00000002, read_byte);
  check_eq_32("readback_byte2", {24'd0, read_byte}, 32'h00000045);
  aux_read_byte(SRC_BASE_ADDR + 32'h00000003, read_byte);
  check_eq_32("readback_byte3", {24'd0, read_byte}, 32'h00000067);
  aux_read_byte(SRC_BASE_ADDR + 32'h00000004, read_byte);
  check_eq_32("readback_byte4", {24'd0, read_byte}, 32'h00000089);
  aux_read_byte(SRC_BASE_ADDR + 32'h00000005, read_byte);
  check_eq_32("readback_byte5", {24'd0, read_byte}, 32'h000000ab);

  check_eq_2("mem_err_o_should_be_zero", mem_err_o, 2'b00);

  $display("# SUMMARY: PASS=%0d FAIL=%0d", pass_count, fail_count);
  if (fail_count == 0)
    $display("[PASS] rv32_soc_unified_test");
  else
    $display("[FAIL] rv32_soc_unified_test");

  write_summary_file;
  $finish;
end
endtask
