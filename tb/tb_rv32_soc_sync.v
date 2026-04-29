`timescale 1ns / 1ps

module tb_rv32_soc_sync;
  localparam integer TB_RUN_CYCLES = 250;

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
  reg [31:0] aux_word0_r;

  wire [31:0] dmem_word0 = {
    dut.u_dmem.u_dmem_ip.mem[3],
    dut.u_dmem.u_dmem_ip.mem[2],
    dut.u_dmem.u_dmem_ip.mem[1],
    dut.u_dmem.u_dmem_ip.mem[0]
  };

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
      aux_en = 1'b0;
      aux_addr = 32'b0;
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
    aux_word0_r = 32'b0;

    repeat (2) @(negedge clk);
    rst = 0;

    repeat (TB_RUN_CYCLES) @(posedge clk);

    aux_read_word(32'h0000_0000, aux_word0_r);

    $display("# ===== RV32I SOC SYNC CHECK =====");
    check_eq_2 ("mem_err_o_should_be_zero", mem_err_o, 2'b00);
    check_eq_32("x1_should_hold_5", dut.u_reg_file.registers[1], 32'h00000005);
    check_eq_32("x2_should_hold_10", dut.u_reg_file.registers[2], 32'h0000000a);
    check_eq_32("x3_should_hold_15", dut.u_reg_file.registers[3], 32'h0000000f);
    check_eq_32("x4_should_hold_sum_to_7", dut.u_reg_file.registers[4], 32'h0000001c);
    check_eq_32("dmem_word0_raw", dmem_word0, 32'h0000001c);
    check_eq_32("aux_port_word0", aux_word0_r, 32'h0000001c);

    $display("# SUMMARY: PASS=%0d FAIL=%0d", pass_count, fail_count);
    if (fail_count == 0)
      $display("[PASS] rv32_soc_sync_smoke_test");
    else
      $display("[FAIL] rv32_soc_sync_smoke_test");

    $finish;
  end
endmodule
