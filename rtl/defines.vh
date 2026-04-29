//`include "defines.vh"
`ifndef RISCV_DEFS_VH
`define RISCV_DEFS_VH
// -------------------------------------------------
// TAG
// -------------------------------------------------
`define _NOT_USE_YET_
// -------------------------------------------------
// SIZE
// -------------------------------------------------
// `define DMEM_ZISE 32
// `define IMEM_ZISE 32
// -------------------------------------------------
// RESET / NOP
// -------------------------------------------------
`define RESET_PC   32'b00000000
`define NOP_INSTR  32'h00000013

// -------------------------------------------------
// RV32I OPCODES
// -------------------------------------------------
`define OPCODE_R        7'b0110011
`define OPCODE_I_ARITH  7'b0010011
`define OPCODE_I_LOAD   7'b0000011
`define OPCODE_I_JALR   7'b1100111
`define OPCODE_SYSTEM   7'b1110011
`define OPCODE_S        7'b0100011
`define OPCODE_B        7'b1100011
`define OPCODE_LUI      7'b0110111
`define OPCODE_AUIPC    7'b0010111
`define OPCODE_JAL      7'b1101111
`define OPCODE_FENCE    7'b0001111

// -------------------------------------------------
// ALU OPCODES
// -------------------------------------------------
`define ALU_ADD   4'b0000
`define ALU_SUB   4'b0001
`define ALU_SLL   4'b0010
`define ALU_SLT   4'b0011
`define ALU_SLTU  4'b0100
`define ALU_XOR   4'b0101
`define ALU_SRL   4'b0110
`define ALU_SRA   4'b0111
`define ALU_OR    4'b1000
`define ALU_AND   4'b1001

// -------------------------------------------------
// ALU BRANCH OPCODES
// -------------------------------------------------
`define ALU_BEQ   4'b1010
`define ALU_BNE   4'b1011
`define ALU_BLT   4'b1100
`define ALU_BGE   4'b1101
`define ALU_BLTU  4'b1110
`define ALU_BGEU  4'b1111

// -------------------------------------------------
// MEMORY FUNCT3 (LOAD / STORE)
// -------------------------------------------------
`define LB    3'b000
`define LH    3'b001
`define LW    3'b010
`define LBU   3'b100
`define LHU   3'b101

`define SB    3'b000
`define SH    3'b001
`define SW    3'b010

// -------------------------------------------------
// WRITE BACK
// -------------------------------------------------
// WRITEBACK SELECT = 2'b00 ALU RESULT
// WRITEBACK SELECT = 2'b01 MEMORY DATA
// WRITEBACK SELECT = 2'b10 PC + 4



`endif
