`include "defines.vh"

module if_stage (
  input  wire        clk_i,
  input  wire        rst_i,

  input  wire        flush_i,
  input  wire        stall_i,

  input  wire        if_bj_taken_i,
  input  wire [31:0] if_pc_bj_i,

  // imem interface
  output wire        imem_en_o,
  output wire [31:0] imem_addr_o,
  input  wire [31:0] imem_instr_i,

  // IF/ID pipeline outputs
  output wire [31:0] ifid_pc_o,
  output wire [31:0] ifid_instruction_o
);

  // -------------------------
  // PC logic
  // -------------------------
  reg  [31:0] pc_r;
  wire [31:0] pc_next_w;

  //(pc_r == 32'h80000ffc) ? 32'h80000ffc :
  assign pc_next_w   = if_bj_taken_i ? if_pc_bj_i : (pc_r == 32'h80000ffc) ? 32'h80000ffc : (pc_r + 32'h4);
  assign imem_addr_o = pc_r;

  // imem always enabled unless stall/reset
  assign imem_en_o = ~(stall_i | rst_i);

  // -------------------------
  // IF/ID pipeline registers
  // -------------------------
  reg [31:0] ifid_pc_r;
  reg [31:0] ifid_instruction_r;

  assign ifid_pc_o          = ifid_pc_r;
  assign ifid_instruction_o = ifid_instruction_r;

  // -------------------------
  // PC register
  // -------------------------
  always @(posedge clk_i) begin
    if (rst_i)
      pc_r <= `RESET_PC;
    else if (!stall_i)
      pc_r <= pc_next_w;
  end

  // -------------------------
  // IF/ID register
  // -------------------------
  always @(posedge clk_i) begin
    if (rst_i || flush_i || if_bj_taken_i) begin
      ifid_pc_r          <= `RESET_PC;
      ifid_instruction_r <= `NOP_INSTR;
    end 
    else if (!stall_i) begin
      ifid_pc_r          <= pc_r;
      ifid_instruction_r <= imem_instr_i;
    end
  end

endmodule
