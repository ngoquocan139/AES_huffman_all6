`include "defines.vh"

module ex_stage (
  input  wire        clk_i,
  input  wire        rst_i,

  input  wire        flush_i,
  input  wire        stall_i,

  input  wire [31:0] ex_pc_i,
  input  wire [31:0] ex_imm_i,
  input  wire [31:0] ex_rs1_data_i,
  input  wire [31:0] ex_rs2_data_i,
  
  input  wire        ex_jal_i,
  input  wire        ex_jalr_i,
  input  wire        ex_alu_src1_i,
  input  wire        ex_alu_src2_i,
  input  wire [3:0]  ex_aluop_i,
  input  wire        ex_mem_we_i,
  input  wire        ex_mem_en_i,
  input  wire [2:0]  ex_width_se_i,
  input  wire [1:0]  ex_wb_se_i,
  input  wire        ex_regwrite_i,
  input  wire [4:0]  ex_rd_addr_i,

  // EX => IF outputs
  output wire  [31:0] exif_pc_bj_o,
  output wire         exif_bj_taken_o,

  // EX/MEM outputs
  output reg         exmem_mem_we_o,
  output reg         exmem_mem_en_o,
  output reg  [2:0]  exmem_width_se_o,
  output reg  [1:0]  exmem_wb_se_o,
  output reg         exmem_regwrite_o,
  output reg  [4:0]  exmem_rd_addr_o,
  output reg  [31:0] exmem_alu_result_o,
  output reg  [31:0] exmem_rs2_data_o,
  output reg  [31:0] exmem_pc_plus_o
);

  // ------------------------------------------------------------
  // Operand select
  // ------------------------------------------------------------
  wire [31:0] operand_a = (ex_alu_src1_i) ? ex_pc_i : ex_rs1_data_i;
  wire [31:0] operand_b = (ex_alu_src2_i) ? ex_rs2_data_i : ex_imm_i;

  // ------------------------------------------------------------
  // ALU
  // ------------------------------------------------------------
  wire [31:0] add_res  = operand_a + operand_b;
  wire [31:0] sub_res  = operand_a - operand_b;
  wire [31:0] sll_res  = operand_a << operand_b[4:0];
  wire [31:0] srl_res  = operand_a >> operand_b[4:0];
  wire [31:0] sra_res  = ($signed(operand_a)) >>> operand_b[4:0];
  wire [31:0] xor_res  = operand_a ^ operand_b;
  wire [31:0] or_res   = operand_a | operand_b;
  wire [31:0] and_res  = operand_a & operand_b;
  wire [31:0] slt_res  = ($signed(operand_a) <  $signed(operand_b)) ? 32'h1 : 32'b0;
  wire [31:0] sltu_res = (operand_a < operand_b) ? 32'h1 : 32'b0;

  wire [31:0] alu_result =
      (ex_aluop_i == `ALU_ADD)  ? add_res  :
      (ex_aluop_i == `ALU_SUB)  ? sub_res  :
      (ex_aluop_i == `ALU_SLL)  ? sll_res  :
      (ex_aluop_i == `ALU_SLT)  ? slt_res  :
      (ex_aluop_i == `ALU_SLTU) ? sltu_res :
      (ex_aluop_i == `ALU_XOR)  ? xor_res  :
      (ex_aluop_i == `ALU_SRL)  ? srl_res  :
      (ex_aluop_i == `ALU_SRA)  ? sra_res  :
      (ex_aluop_i == `ALU_OR)   ? or_res   :
      (ex_aluop_i == `ALU_AND)  ? and_res  : 32'b0;

  // ------------------------------------------------------------
  // Branch / jump decision
  // ------------------------------------------------------------
  wire alu_branch_taken =
      (ex_aluop_i == `ALU_BEQ)  ? (operand_a == operand_b) :
      (ex_aluop_i == `ALU_BNE)  ? (operand_a != operand_b) :
      (ex_aluop_i == `ALU_BLT)  ? ($signed(operand_a) <  $signed(operand_b)) :
      (ex_aluop_i == `ALU_BGE)  ? ($signed(operand_a) >= $signed(operand_b)) :
      (ex_aluop_i == `ALU_BLTU) ? (operand_a <  operand_b) :
      (ex_aluop_i == `ALU_BGEU) ? (operand_a >= operand_b) : 1'b0;

  wire [31:0] pc_bj = ex_jalr_i ? ((operand_a + ex_imm_i) & 32'hFFFFFFFE) : (ex_pc_i + ex_imm_i);
  
  wire bj_taken;
  assign bj_taken = (alu_branch_taken == 1'b1) || (ex_jal_i == 1'b1) || (ex_jalr_i == 1'b1);

  // ------------------------------------------------------------
  // Pipeline registers (EX/IF + EX/MEM)
  // ------------------------------------------------------------
  assign exif_pc_bj_o = pc_bj;
  assign exif_bj_taken_o = bj_taken;

/*
  always @(posedge clk_i) begin
    if (rst_i) begin
      exif_pc_bj_o       <= `RESET_PC;
      exif_bj_taken_o    <= 1'b0;
    end else if (!stall_i) begin
      exif_pc_bj_o       <= pc_bj;
      exif_bj_taken_o    <= bj_taken;
    end
  end
*/
  
  always @(posedge clk_i) begin
    if (rst_i || flush_i) begin
      exmem_alu_result_o <= 32'b0;
      exmem_rs2_data_o   <= 32'b0;
      exmem_mem_we_o     <= 1'b0;
      exmem_mem_en_o     <= 1'b0;
      exmem_width_se_o   <= 3'b0;
      exmem_wb_se_o      <= 2'b0;
      exmem_regwrite_o   <= 1'b0;
      exmem_rd_addr_o    <= 5'b0;
      exmem_pc_plus_o    <= `RESET_PC + 32'h4;
    end
    else if (!stall_i) begin
      exmem_alu_result_o <= alu_result;
      exmem_rs2_data_o   <= ex_rs2_data_i;
      exmem_mem_we_o     <= ex_mem_we_i;
      exmem_mem_en_o     <= ex_mem_en_i;
      exmem_width_se_o   <= ex_width_se_i;
      exmem_wb_se_o      <= ex_wb_se_i;
      exmem_regwrite_o   <= ex_regwrite_i;
      exmem_rd_addr_o    <= ex_rd_addr_i;
      exmem_pc_plus_o    <= ex_pc_i + 32'h4;
    end
  end

endmodule
