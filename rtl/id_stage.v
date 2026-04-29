`include "defines.vh"

module id_stage (
  input  wire        clk_i,
  input  wire        rst_i,

  input  wire [31:0] ifid_pc_i,
  input  wire [31:0] ifid_instruction_i,

  input  wire        flush_i,
  input  wire        hold_i,
  input  wire        bubble_i,

  output wire [4:0]  rf_rs1_addr_o,
  output wire [4:0]  rf_rs2_addr_o,
  input  wire [31:0] rf_rs1_data_i,
  input  wire [31:0] rf_rs2_data_i,

  // ID/EX pipeline outputs
  output reg         idex_jal_o,
  output reg         idex_jalr_o,
  output reg         idex_se_alu_src1_o,
  output reg         idex_se_alu_src2_o,
  output reg  [3:0]  idex_aluop_o,
  output reg  [31:0] idex_rs1_data_o,
  output reg  [31:0] idex_rs2_data_o,
  output reg  [31:0] idex_imm_o,

  output reg  [4:0]  idex_rs1_addr_o,
  output reg  [4:0]  idex_rs2_addr_o,

  output reg         idex_mem_we_o,
  output reg         idex_mem_en_o,
  output reg  [2:0]  idex_width_se_o,
  output reg  [1:0]  idex_wb_se_o,
  output reg         idex_regwrite_o,
  output reg  [4:0]  idex_rd_addr_o,
  output reg  [31:0] idex_pc_o
);

  // ------------------------------------------------------------
  // Instruction fields
  // ------------------------------------------------------------
  wire [6:0] opcode = ifid_instruction_i[6:0];
  wire [4:0] rs1    = ifid_instruction_i[19:15];
  wire [4:0] rs2    = ifid_instruction_i[24:20];
  wire [4:0] rd     = ifid_instruction_i[11:7];
  wire [2:0] funct3 = ifid_instruction_i[14:12];
  wire [6:0] funct7 = ifid_instruction_i[31:25];

  // ------------------------------------------------------------
  // Immediate generation
  // ------------------------------------------------------------
  wire [31:0] imm_i = {{20{ifid_instruction_i[31]}}, ifid_instruction_i[31:20]};
  wire [31:0] imm_s = {{20{ifid_instruction_i[31]}}, ifid_instruction_i[31:25], ifid_instruction_i[11:7]};
  wire [31:0] imm_b = {{19{ifid_instruction_i[31]}}, ifid_instruction_i[31], ifid_instruction_i[7],
                       ifid_instruction_i[30:25], ifid_instruction_i[11:8], 1'b0};
  wire [31:0] imm_u = {ifid_instruction_i[31:12], 12'b0};
  wire [31:0] imm_j = {{11{ifid_instruction_i[31]}}, ifid_instruction_i[31],
                       ifid_instruction_i[19:12], ifid_instruction_i[20],
                       ifid_instruction_i[30:21], 1'b0};
  wire [31:0] imm_shamt = {27'b0, ifid_instruction_i[24:20]};

  wire [31:0] imm =
      (opcode == `OPCODE_LUI || opcode == `OPCODE_AUIPC) ? imm_u :
      (opcode == `OPCODE_JAL)                            ? imm_j :
      (opcode == `OPCODE_I_JALR)                         ? imm_i :
      (opcode == `OPCODE_B)                              ? imm_b :
      (opcode == `OPCODE_I_LOAD)                         ? imm_i :
      (opcode == `OPCODE_S)                              ? imm_s :
      (opcode == `OPCODE_I_ARITH &&
       (funct3 == 3'b001 || funct3 == 3'b101))           ? imm_shamt :
      (opcode == `OPCODE_I_ARITH)                        ? imm_i : 32'b0;

  wire [4:0] rs1_addr =
      (opcode == `OPCODE_LUI   || opcode == `OPCODE_AUIPC ||
       opcode == `OPCODE_JAL   || opcode == `OPCODE_FENCE ||
       (opcode == `OPCODE_SYSTEM &&
       (funct3 == 3'b001 || funct3 == 3'b010 || funct3 == 3'b011)))
      ? 5'b0 : rs1;

  wire [4:0] rs2_addr =
      (opcode == `OPCODE_B || opcode == `OPCODE_S || opcode == `OPCODE_R)
      ? rs2 : 5'b0;

  assign rf_rs1_addr_o = rs1_addr;
  assign rf_rs2_addr_o = rs2_addr;

  //assign idex_rs1_addr_o = rs1_addr;
  //assign idex_rs1_addr_o = rs2_addr;
  // ------------------------------------------------------------
  // Control decode
  // ------------------------------------------------------------
  wire jal  = (opcode == `OPCODE_JAL);
  wire jalr = (opcode == `OPCODE_I_JALR);

  wire se_alu_src1 = (opcode == `OPCODE_AUIPC);
  wire se_alu_src2 = (opcode == `OPCODE_R) || (opcode == `OPCODE_B);

  wire mem_we = (opcode == `OPCODE_S);
  wire mem_en = (opcode == `OPCODE_I_LOAD) || (opcode == `OPCODE_S);

  wire [2:0] load_se  =
      (funct3 == 3'b000) ? 3'b000 :
      (funct3 == 3'b001) ? 3'b001 :
      (funct3 == 3'b010) ? 3'b010 :
      (funct3 == 3'b100) ? 3'b100 :
      (funct3 == 3'b101) ? 3'b101 : 3'b010; // default = LW

  wire [2:0] store_se =
      (funct3 == 3'b000) ? 3'b000 :
      (funct3 == 3'b001) ? 3'b001 : 3'b010; // default = SW

  wire [2:0] width_se =
      (opcode == `OPCODE_I_LOAD) ? load_se :
      (opcode == `OPCODE_S)      ? store_se : 3'b000;

  wire [1:0] wb_se =
    (opcode == `OPCODE_I_LOAD) ? 2'b01 : // MEM
    (opcode == `OPCODE_JAL || opcode == `OPCODE_I_JALR)
                               ? 2'b10 : // PC+4
    (opcode == `OPCODE_R ||
     opcode == `OPCODE_I_ARITH ||
     opcode == `OPCODE_LUI ||
     opcode == `OPCODE_AUIPC ||
     opcode == `OPCODE_SYSTEM)
                               ? 2'b00 : // ALU
                                 2'b11 ; // DEFAULT = INVALID


  wire regwrite =
      (opcode == `OPCODE_R)       ||
      (opcode == `OPCODE_I_ARITH) ||
      (opcode == `OPCODE_I_LOAD)  ||
      (opcode == `OPCODE_JAL)     ||
      (opcode == `OPCODE_I_JALR)  ||
      (opcode == `OPCODE_LUI)     ||
      (opcode == `OPCODE_AUIPC)   ||
      ((opcode == `OPCODE_SYSTEM) && funct3 != 3'b000);

  wire [4:0] rd_addr = regwrite ? rd : 5'b0;

  // ------------------------------------------------------------
  // ALU decode (same logic, condensed)
  // ------------------------------------------------------------
  wire [3:0] alu_r =
      (funct3 == 3'b000 && funct7 == 7'b0100000) ? `ALU_SUB :
      (funct3 == 3'b000) ? `ALU_ADD :
      (funct3 == 3'b001) ? `ALU_SLL :
      (funct3 == 3'b010) ? `ALU_SLT :
      (funct3 == 3'b011) ? `ALU_SLTU:
      (funct3 == 3'b100) ? `ALU_XOR :
      (funct3 == 3'b101 && funct7 == 7'b0100000) ? `ALU_SRA :
      (funct3 == 3'b101) ? `ALU_SRL :
      (funct3 == 3'b110) ? `ALU_OR  :
      (funct3 == 3'b111) ? `ALU_AND : `ALU_ADD;

  wire [3:0] alu_i =
      (funct3 == 3'b000) ? `ALU_ADD :
      (funct3 == 3'b001) ? `ALU_SLL :
      (funct3 == 3'b010) ? `ALU_SLT :
      (funct3 == 3'b011) ? `ALU_SLTU:
      (funct3 == 3'b100) ? `ALU_XOR :
      (funct3 == 3'b101 && ifid_instruction_i[30]) ? `ALU_SRA :
      (funct3 == 3'b101) ? `ALU_SRL :
      (funct3 == 3'b110) ? `ALU_OR  :
      (funct3 == 3'b111) ? `ALU_AND : `ALU_ADD;

  wire [3:0] alu_b =
      (funct3 == 3'b000) ? `ALU_BEQ  :
      (funct3 == 3'b001) ? `ALU_BNE  :
      (funct3 == 3'b100) ? `ALU_BLT  :
      (funct3 == 3'b101) ? `ALU_BGE  :
      (funct3 == 3'b110) ? `ALU_BLTU :
      (funct3 == 3'b111) ? `ALU_BGEU : `ALU_BEQ;

  wire [3:0] aluop =
      (opcode == `OPCODE_R)       ? alu_r :
      (opcode == `OPCODE_I_ARITH) ? alu_i :
      (opcode == `OPCODE_B)       ? alu_b :
                                   `ALU_ADD; //default = ADD

  // ------------------------------------------------------------
  // ID/EX pipeline register
  // ------------------------------------------------------------
  always @(posedge clk_i) begin
    if (rst_i || flush_i) begin
      idex_jal_o         <= 1'b0;
      idex_jalr_o        <= 1'b0;
      idex_se_alu_src1_o <= 1'b0;
      idex_se_alu_src2_o <= 1'b0;
      idex_aluop_o       <= 4'b0;
      idex_rs1_data_o    <= 32'b0;
      idex_rs2_data_o    <= 32'b0;
      idex_imm_o         <= 32'b0;
      idex_rs1_addr_o    <= 5'b0;
      idex_rs2_addr_o    <= 5'b0;
      idex_mem_we_o      <= 1'b0;
      idex_mem_en_o      <= 1'b0;
      idex_width_se_o    <= 3'b0;
      idex_wb_se_o       <= 2'b0;
      idex_regwrite_o    <= 1'b0;
      idex_rd_addr_o     <= 5'b0;
      idex_pc_o          <= `RESET_PC;
    end else if (hold_i) begin
      idex_jal_o         <= idex_jal_o;
      idex_jalr_o        <= idex_jalr_o;
      idex_se_alu_src1_o <= idex_se_alu_src1_o;
      idex_se_alu_src2_o <= idex_se_alu_src2_o;
      idex_aluop_o       <= idex_aluop_o;
      idex_rs1_data_o    <= idex_rs1_data_o;
      idex_rs2_data_o    <= idex_rs2_data_o;
      idex_imm_o         <= idex_imm_o;
      idex_rs1_addr_o    <= idex_rs1_addr_o;
      idex_rs2_addr_o    <= idex_rs2_addr_o;
      idex_mem_we_o      <= idex_mem_we_o;
      idex_mem_en_o      <= idex_mem_en_o;
      idex_width_se_o    <= idex_width_se_o;
      idex_wb_se_o       <= idex_wb_se_o;
      idex_regwrite_o    <= idex_regwrite_o;
      idex_rd_addr_o     <= idex_rd_addr_o;
      idex_pc_o          <= idex_pc_o;
    end else if (bubble_i) begin
      idex_jal_o         <= 1'b0;
      idex_jalr_o        <= 1'b0;
      idex_se_alu_src1_o <= 1'b0;
      idex_se_alu_src2_o <= 1'b0;
      idex_aluop_o       <= 4'b0;
      idex_rs1_data_o    <= 32'b0;
      idex_rs2_data_o    <= 32'b0;
      idex_imm_o         <= 32'b0;
      idex_rs1_addr_o    <= 5'b0;
      idex_rs2_addr_o    <= 5'b0;
      idex_mem_we_o      <= 1'b0;
      idex_mem_en_o      <= 1'b0;
      idex_width_se_o    <= 3'b0;
      idex_wb_se_o       <= 2'b0;
      idex_regwrite_o    <= 1'b0;
      idex_rd_addr_o     <= 5'b0;
      idex_pc_o          <= `RESET_PC;
    end else begin
      idex_jal_o         <= jal;
      idex_jalr_o        <= jalr;
      idex_se_alu_src1_o <= se_alu_src1;
      idex_se_alu_src2_o <= se_alu_src2;
      idex_aluop_o       <= aluop;
      idex_rs1_data_o    <= rf_rs1_data_i;
      idex_rs2_data_o    <= rf_rs2_data_i;
      idex_imm_o         <= imm;
      idex_rs1_addr_o    <= rs1_addr;
      idex_rs2_addr_o    <= rs2_addr;
      idex_mem_we_o      <= mem_we;
      idex_mem_en_o      <= mem_en;
      idex_width_se_o    <= width_se;
      idex_wb_se_o       <= wb_se;
      idex_regwrite_o    <= regwrite;
      idex_rd_addr_o     <= rd_addr;
      idex_pc_o          <= ifid_pc_i;
    end
  end

endmodule
