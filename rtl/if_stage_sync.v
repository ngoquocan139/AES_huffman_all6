`include "defines.vh"

// Synchronous-memory IF stage.
//
// This version assumes imem returns the instruction one clock after a fetch
// request, which matches BRAM-style behavior more closely than the original
// async model. Keep only one if_stage implementation active in sim/rtl.f.
module if_stage_sync (
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

  reg [31:0] pc_r;
  reg [31:0] req_pc_r;
  reg        req_valid_r;
  reg [31:0] resp_pc_r;
  reg [31:0] resp_instr_r;
  reg        resp_valid_r;

  reg [31:0] ifid_pc_r;
  reg [31:0] ifid_instruction_r;

  wire [31:0] pc_seq_w  = (pc_r == 32'h80000ffc) ? 32'h80000ffc : (pc_r + 32'h4);
  wire [31:0] pc_next_w = if_bj_taken_i ? if_pc_bj_i : pc_seq_w;
  wire        have_resp_w = resp_valid_r || req_valid_r;
  wire [31:0] resp_pc_mux_w = resp_valid_r ? resp_pc_r : req_pc_r;
  wire [31:0] resp_instr_mux_w = resp_valid_r ? resp_instr_r : imem_instr_i;

  // Do not issue a new request on flush/redirect. The redirected PC is loaded
  // into pc_r first, then fetched on the next cycle.
  wire fetch_req_w = ~(rst_i | stall_i | flush_i | if_bj_taken_i);

  assign imem_en_o = fetch_req_w;
  assign imem_addr_o = pc_r;

  assign ifid_pc_o = ifid_pc_r;
  assign ifid_instruction_o = ifid_instruction_r;

  always @(posedge clk_i) begin
    if (rst_i) begin
      pc_r <= `RESET_PC;
      req_pc_r <= `RESET_PC;
      req_valid_r <= 1'b0;
      resp_pc_r <= `RESET_PC;
      resp_instr_r <= `NOP_INSTR;
      resp_valid_r <= 1'b0;
      ifid_pc_r <= `RESET_PC;
      ifid_instruction_r <= `NOP_INSTR;
    end else begin
      if (flush_i || if_bj_taken_i) begin
        req_valid_r <= 1'b0;
        resp_valid_r <= 1'b0;
        ifid_pc_r <= `RESET_PC;
        ifid_instruction_r <= `NOP_INSTR;
        pc_r <= pc_next_w;
      end else begin
        if (stall_i) begin
          if (req_valid_r && !resp_valid_r) begin
            resp_pc_r <= req_pc_r;
            resp_instr_r <= imem_instr_i;
            resp_valid_r <= 1'b1;
          end
          req_valid_r <= 1'b0;
        end else begin
          if (have_resp_w) begin
            ifid_pc_r <= resp_pc_mux_w;
            ifid_instruction_r <= resp_instr_mux_w;
          end else begin
            ifid_pc_r <= `RESET_PC;
            ifid_instruction_r <= `NOP_INSTR;
          end

          if (fetch_req_w) begin
            req_pc_r <= pc_r;
            req_valid_r <= 1'b1;
          end else begin
            req_valid_r <= 1'b0;
          end

          resp_valid_r <= 1'b0;
          pc_r <= pc_next_w;
        end
      end
    end
  end

endmodule
