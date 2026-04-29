`timescale 1ns / 1ps
//`define _DMEM_IP_
//`define _DEBUG_WIRE_
module test_bench;
  localparam integer TB_RUN_CYCLES = 200;

  reg clk;
  reg rst;
  integer pass_count;
  integer fail_count;
  integer wb_x4_count;
  reg [31:0] last_wb_x4_data;
`ifdef _DEBUG_WIRE_
  wire [31:0] pc_r = dut.u_if_stage.pc_r;
`endif
  wire imem_en;
  wire [31:0] imem_addr;
  wire [31:0] imem_instr;
`ifdef _DEBUG_WIRE_
  wire [31:0] ifid_pc_o = dut.u_if_stage.ifid_pc_o;
  wire [31:0] ifid_instruction_o = dut.u_if_stage.ifid_instruction_o;
`endif
  wire rf_reg_write = dut.rf_reg_write_w;
  wire [4:0] rf_rd_addr = dut.rf_rd_addr_w;
  wire [31:0] rf_rd_data = dut.rf_rd_data_w;
  wire dmem_en;
  wire [3:0] dmem_we;
  wire [31:0] dmem_addr;
  wire [31:0] dmem_w_data;
  wire [31:0] dmem_r_data;

  wire [1:0] mem_err_o;
  reg if_flush = 0;
  reg stall = 0;
  // Register file interface
  wire [4:0] rs1_addr;
  wire [4:0] rs2_addr;
  wire [31:0] rs1_data;
  wire [31:0] rs2_data;
  wire reg_write;
  wire [4:0] rd_addr;
  wire [31:0] rd_data;

  wire [7:0] dmem_word_addr = dmem_addr[9:2];
  wire [31:0] dmem_word0 = {
    dut_dmem.dmem_uut3.mem[0],
    dut_dmem.dmem_uut2.mem[0],
    dut_dmem.dmem_uut1.mem[0],
    dut_dmem.dmem_uut0.mem[0]
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

  task automatic check_ge_32;
    input [8*64-1:0] name;
    input [31:0] actual;
    input [31:0] minimum;
    begin
      if ((^actual === 1'bx) || (actual < minimum)) begin
        fail_count = fail_count + 1;
        $display("[FAIL] %0s | actual=0x%08x minimum=0x%08x", name, actual, minimum);
      end else begin
        pass_count = pass_count + 1;
        $display("[PASS] %0s | actual=0x%08x minimum=0x%08x", name, actual, minimum);
      end
    end
  endtask

  // ============================================================
  // DUT Instantiation
  // ============================================================
  top_rv32 dut (
    .clk_i(clk),
    .rst_i(rst),

    // IMEM
    .imem_en_o(imem_en),
    .imem_addr_o(imem_addr),
    .imem_instr_i(imem_instr),

    // DMEM
    .dmem_en_o(dmem_en),
    .dmem_we_o(dmem_we),
    .dmem_addr_o(dmem_addr),
    .dmem_w_data_o(dmem_w_data),
    .dmem_r_data_i(dmem_r_data),
      // Register file interface
    .rs1_addr(rs1_addr),
    .rs2_addr(rs2_addr),
    .rs1_data(rs1_data),
    .rs2_data(rs2_data),
    .reg_write(reg_write),
    .rd_addr(rd_addr),
    .rd_data(rd_data),

    .if_flush_i(if_flush),
    .stall_i(stall),
    .mem_err_o(mem_err_o)
  );

  dmem_wrab dut_dmem (
    .clka   (clk),
    .ena    (dmem_en),
    .wea    (dmem_we),
    .addra  (dmem_word_addr),
    .dina   (dmem_w_data),
    .douta  (dmem_r_data)
  );

  // --------------------------------------------------
  // Instruction Memory
  // --------------------------------------------------

  imem dut_imem (
    .en_i          (imem_en),
    .instr_addr_i  (imem_addr[11:2]),
    .instruction_o (imem_instr)
  );

  registers_file dut_reg_file(
    .clk      (clk),
    .rst      (rst),

    .rs1_addr (rs1_addr),
    .rs2_addr (rs2_addr),
    .rs1_data (rs1_data),
    .rs2_data (rs2_data),

    .reg_write(reg_write),
    .rd_addr  (rd_addr),
    .rd_data  (rd_data)
  );

  always #5 clk = ~clk;

  always @(posedge clk) begin
    if (rst) begin
      wb_x4_count <= 0;
      last_wb_x4_data <= 32'b0;
    end else if (reg_write && (rd_addr == 5'd4)) begin
      wb_x4_count <= wb_x4_count + 1;
      last_wb_x4_data <= rd_data;
    end
  end

  initial begin
    clk = 0;
    rst = 1;
    pass_count = 0;
    fail_count = 0;
    wb_x4_count = 0;
    last_wb_x4_data = 32'b0;

    repeat (2) @(negedge clk);
    rst = 0;

    repeat (TB_RUN_CYCLES) @(posedge clk);

    $display("# ===== RV32I CHECK =====");
    check_eq_2 ("mem_err_o_should_be_zero", mem_err_o, 2'b00);
    check_eq_32("instruction_0", dut_imem.instructions_r[0], 32'h00500093);
    check_eq_32("x0", dut_reg_file.registers[0], 32'h00000000);
    check_eq_32("x1_should_hold_5", dut_reg_file.registers[1], 32'h00000005);
    check_eq_32("x2_should_hold_10", dut_reg_file.registers[2], 32'h0000000a);
    check_eq_32("x3_should_hold_15", dut_reg_file.registers[3], 32'h0000000f);
    check_eq_32("x4_should_hold_sum_to_7", dut_reg_file.registers[4], 32'h0000001c);
    check_ge_32("dmem_word0_should_be_incremented", dmem_word0, 32'h0000001c);

    $display("# ===== FINAL STATE =====");
    $display("mem_err_o      = %b", mem_err_o);
    $display("reg_write/rd   = %0d x%0d 0x%08h", reg_write, rd_addr, rd_data);
    $display("instruction[0] = %h", dut_imem.instructions_r[0]);
    $display("dmem_word0     = %h", dmem_word0);
    $display("x1             = %h", dut_reg_file.registers[1]);
    $display("x2             = %h", dut_reg_file.registers[2]);
    $display("x3             = %h", dut_reg_file.registers[3]);
    $display("x4             = %h", dut_reg_file.registers[4]);
    $display("x5             = %h", dut_reg_file.registers[5]);
    $display("x6             = %h", dut_reg_file.registers[6]);
    $display("x7             = %h", dut_reg_file.registers[7]);
    $display("wb_x4_count    = %0d", wb_x4_count);
    $display("last_wb_x4     = %h", last_wb_x4_data);
    $display("# SUMMARY: PASS=%0d FAIL=%0d", pass_count, fail_count);

    if (fail_count == 0)
      $display("[PASS] rv32i_smoke_test");
    else
      $display("[FAIL] rv32i_smoke_test");

    $writememh("regfile_dump_king.txt", dut_reg_file.registers);
    $finish;
  end

endmodule

