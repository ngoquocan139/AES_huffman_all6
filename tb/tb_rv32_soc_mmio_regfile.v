`timescale 1ns / 1ps

module tb_rv32_soc_mmio_regfile;
  localparam integer MAX_WAIT_CYCLES = 200000;
  localparam [31:0] RESULT_BASE_ADDR = 32'h00000000;
  localparam [31:0] RESULT_SIGNATURE_REG1 = 32'h52454731;
  localparam [31:0] RESULT_SIGNATURE_NEG1 = 32'h4e454731;
  localparam [31:0] RESULT_SIGNATURE_MODE = 32'h4d4f4445;

  reg clk;
  reg rst;

  reg        aux_en;
  reg [3:0]  aux_we;
  reg [31:0] aux_addr;
  reg [31:0] aux_wdata;
  wire [31:0] aux_rdata;

  wire [1:0] mem_err_o;

  reg cpu_if_flush;
  reg cpu_stall;

  integer i;
  integer pass_count;
  integer fail_count;
  integer wait_cycles;
  integer dma_start_pulse_count;
  integer soft_reset_pulse_count;
  integer clear_done_pulse_count;
  integer clear_error_pulse_count;
  integer apb_error_count;
  integer bridge_error_count;

  reg [31:0] result_words [0:15];
  reg [8*64-1:0] case_name;
  reg [8*32-1:0] input_file_name;

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
      dma_start_pulse_count   <= 0;
      soft_reset_pulse_count  <= 0;
      clear_done_pulse_count  <= 0;
      clear_error_pulse_count <= 0;
      apb_error_count         <= 0;
      bridge_error_count      <= 0;
    end else begin
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
    end
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

  task automatic run_selected_test;
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
      wait_cycles = 0;
      case_name = "mmio_regfile";
      if ($value$plusargs("CASE_NAME=%s", case_name))
        $display("Test_result STARTED %0s", case_name);

      for (i = 0; i < 16; i = i + 1)
        result_words[i] = 32'b0;

      repeat (8) @(posedge clk);
      rst = 1'b0;

      while (wait_cycles < MAX_WAIT_CYCLES) begin
        aux_read_word(RESULT_BASE_ADDR, result_words[0]);
        if ((result_words[0] === RESULT_SIGNATURE_REG1) ||
            (result_words[0] === RESULT_SIGNATURE_NEG1) ||
            (result_words[0] === RESULT_SIGNATURE_MODE))
          wait_cycles = MAX_WAIT_CYCLES;
        else begin
          @(posedge clk);
          wait_cycles = wait_cycles + 1;
        end
      end

      repeat (32) @(posedge clk);

      for (i = 0; i < 16; i = i + 1)
        aux_read_word(RESULT_BASE_ADDR + (i * 4), result_words[i]);

      $display("# ===== RV32I SOC MMIO REGFILE CHECK =====");
      $display("# case=%0s signature=0x%08x error_mask=0x%08x", case_name, result_words[0], result_words[1]);
      $display("# status0=0x%08x status1=0x%08x status2=0x%08x mode=0x%08x block=0x%08x",
               result_words[2], result_words[3], result_words[4], result_words[5], result_words[6]);
      $display("# iv0=0x%08x iv1=0x%08x iv2=0x%08x iv3=0x%08x",
               result_words[7], result_words[8], result_words[9], result_words[10]);
      $display("# pulses start=%0d soft_reset=%0d clear_done=%0d clear_error=%0d apb_err=%0d bridge_err=%0d",
               dma_start_pulse_count, soft_reset_pulse_count, clear_done_pulse_count,
               clear_error_pulse_count, apb_error_count, bridge_error_count);

      check_true("cpu_should_publish_known_signature",
                 (result_words[0] == RESULT_SIGNATURE_REG1) ||
                 (result_words[0] == RESULT_SIGNATURE_NEG1) ||
                 (result_words[0] == RESULT_SIGNATURE_MODE));
      check_eq_2("mem_err_o_should_be_zero", mem_err_o, 2'b00);

      if (result_words[0] == RESULT_SIGNATURE_REG1) begin
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
      end

      $display("# SUMMARY: PASS=%0d FAIL=%0d", pass_count, fail_count);
      if (fail_count == 0)
        $display("[PASS] rv32_soc_mmio_regfile_test");
      else
        $display("[FAIL] rv32_soc_mmio_regfile_test");

      $finish;
    end
  endtask

  `include "run_test.v"

  initial begin
    run_test();
  end
endmodule
