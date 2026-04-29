`include "defines.vh"

// Synchronous-memory MEM stage.
//
// This version assumes read data comes back one cycle after the request, so a
// load spends an extra cycle waiting for memory response before entering MEM/WB.
module mem_stage_sync (
  input  wire        clk_i,
  input  wire        rst_i,
  input  wire        hold_i,

  // Inputs from EX/MEM stage
  input  wire        mem_we_i,
  input  wire        mem_en_i,
  input  wire        mem_is_mmio_i,
  input  wire [2:0]  mem_width_se_i,

  input  wire [31:0] mem_alu_result_i,
  input  wire [31:0] mem_data_i,

  input  wire        mem_regwrite_i,
  input  wire [4:0]  mem_rd_addr_i,
  input  wire [1:0]  mem_wb_se_i,
  input  wire [31:0] mem_pc_plus_i,

  // Memory interface
  output reg         en_o,
  output reg  [3:0]  we_o,
  output wire [31:0] addr_o,
  output reg  [31:0] data_w_o,
  input  wire [31:0] data_r_i,

  // Outputs to WB stage (MEM/WB registers)
  output reg         memwb_regwrite_o,
  output reg  [4:0]  memwb_rd_addr_o,
  output reg  [1:0]  memwb_wb_se_o,
  output reg  [31:0] memwb_pc_plus_o,
  output reg  [31:0] memwb_alu_result_o,
  output reg  [31:0] memwb_mem_data_o,
  output wire [31:0] mem_data_w,
  output reg  [1:0]  mem_stage_err_o,
  output wire        load_wait_o,
  output wire        load_resp_is_mmio_o
);

  reg write_error;
  reg read_error;
  reg [31:0] data_r_cvt_w;

  reg        load_pending_r;
  reg        load_regwrite_r;
  reg [4:0]  load_rd_addr_r;
  reg [1:0]  load_wb_se_r;
  reg [31:0] load_pc_plus_r;
  reg [31:0] load_alu_result_r;
  reg [2:0]  load_width_se_r;
  reg [1:0]  load_addr_low_r;
  reg [1:0]  load_err_r;
  reg        load_is_mmio_r;

  wire [2:0] active_width_w = load_pending_r ? load_width_se_r : mem_width_se_i;
  wire [1:0] active_op_w = load_pending_r ? load_addr_low_r : mem_alu_result_i[1:0];
  wire [1:0] mem_stage_err_w = write_error ? 2'b01 : read_error ? 2'b10 : 2'b00;
  wire       issue_req_w = mem_en_i && (!load_pending_r);

  assign mem_data_w = data_r_cvt_w;
  assign addr_o = issue_req_w ? mem_alu_result_i : 32'b0;
  assign load_wait_o = load_pending_r;
  assign load_resp_is_mmio_o = load_pending_r && load_is_mmio_r;

  always @(*) begin
    we_o = 4'b0000;
    en_o = 1'b0;
    data_r_cvt_w = 32'b0;
    data_w_o = 32'b0;
    read_error = 1'b0;
    write_error = 1'b0;

    if (issue_req_w) begin
      en_o = 1'b1;
      if (mem_we_i) begin
        case (mem_width_se_i)
          `SB: begin
            case (mem_alu_result_i[1:0])
              2'b00: begin we_o = 4'b0001; data_w_o[7:0]   = mem_data_i[7:0]; end
              2'b01: begin we_o = 4'b0010; data_w_o[15:8]  = mem_data_i[7:0]; end
              2'b10: begin we_o = 4'b0100; data_w_o[23:16] = mem_data_i[7:0]; end
              default: begin we_o = 4'b1000; data_w_o[31:24] = mem_data_i[7:0]; end
            endcase
          end
          `SH: begin
            if (mem_alu_result_i[1:0] == 2'b00) begin
              we_o = 4'b0011;
              data_w_o[15:0] = mem_data_i[15:0];
            end else if (mem_alu_result_i[1:0] == 2'b10) begin
              we_o = 4'b1100;
              data_w_o[31:16] = mem_data_i[15:0];
            end else begin
              write_error = 1'b1;
            end
          end
          `SW: begin
            if (mem_alu_result_i[1:0] == 2'b00) begin
              we_o = 4'b1111;
              data_w_o = mem_data_i;
            end else begin
              write_error = 1'b1;
            end
          end
          default: write_error = 1'b1;
        endcase
      end
    end

    case (active_width_w)
      `LB: begin
        case (active_op_w)
          2'b00: data_r_cvt_w = {{24{data_r_i[7]}}, data_r_i[7:0]};
          2'b01: data_r_cvt_w = {{24{data_r_i[15]}}, data_r_i[15:8]};
          2'b10: data_r_cvt_w = {{24{data_r_i[23]}}, data_r_i[23:16]};
          default: data_r_cvt_w = {{24{data_r_i[31]}}, data_r_i[31:24]};
        endcase
      end
      `LH: begin
        if (active_op_w == 2'b00)
          data_r_cvt_w = {{16{data_r_i[15]}}, data_r_i[15:0]};
        else if (active_op_w == 2'b10)
          data_r_cvt_w = {{16{data_r_i[31]}}, data_r_i[31:16]};
        else begin
          data_r_cvt_w = 32'b0;
          read_error = 1'b1;
        end
      end
      `LW: begin
        if (active_op_w == 2'b00)
          data_r_cvt_w = data_r_i;
        else begin
          data_r_cvt_w = 32'b0;
          read_error = 1'b1;
        end
      end
      `LBU: begin
        case (active_op_w)
          2'b00: data_r_cvt_w = {24'b0, data_r_i[7:0]};
          2'b01: data_r_cvt_w = {24'b0, data_r_i[15:8]};
          2'b10: data_r_cvt_w = {24'b0, data_r_i[23:16]};
          default: data_r_cvt_w = {24'b0, data_r_i[31:24]};
        endcase
      end
      `LHU: begin
        if (active_op_w == 2'b00)
          data_r_cvt_w = {16'b0, data_r_i[15:0]};
        else if (active_op_w == 2'b10)
          data_r_cvt_w = {16'b0, data_r_i[31:16]};
        else begin
          data_r_cvt_w = 32'b0;
          read_error = 1'b1;
        end
      end
      default: begin
        if (load_pending_r) begin
          data_r_cvt_w = 32'b0;
          read_error = 1'b1;
        end
      end
    endcase
  end

  always @(posedge clk_i) begin
    if (rst_i) begin
      memwb_regwrite_o   <= 1'b0;
      memwb_rd_addr_o    <= 5'b0;
      memwb_wb_se_o      <= 2'b0;
      memwb_pc_plus_o    <= (`RESET_PC + 32'h4);
      memwb_alu_result_o <= 32'b0;
      memwb_mem_data_o   <= 32'b0;
      mem_stage_err_o    <= 2'b00;
      load_pending_r     <= 1'b0;
      load_regwrite_r    <= 1'b0;
      load_rd_addr_r     <= 5'b0;
      load_wb_se_r       <= 2'b0;
      load_pc_plus_r     <= (`RESET_PC + 32'h4);
      load_alu_result_r  <= 32'b0;
      load_width_se_r    <= 3'b0;
      load_addr_low_r    <= 2'b0;
      load_err_r         <= 2'b00;
      load_is_mmio_r     <= 1'b0;
    end else if (hold_i && (!load_pending_r) && mem_en_i && !mem_we_i) begin
      memwb_regwrite_o   <= 1'b0;
      memwb_rd_addr_o    <= 5'b0;
      memwb_wb_se_o      <= 2'b0;
      memwb_pc_plus_o    <= mem_pc_plus_i;
      memwb_alu_result_o <= mem_alu_result_i;
      memwb_mem_data_o   <= 32'b0;
      mem_stage_err_o    <= mem_stage_err_w;

      load_pending_r     <= 1'b1;
      load_regwrite_r    <= mem_regwrite_i;
      load_rd_addr_r     <= mem_rd_addr_i;
      load_wb_se_r       <= mem_wb_se_i;
      load_pc_plus_r     <= mem_pc_plus_i;
      load_alu_result_r  <= mem_alu_result_i;
      load_width_se_r    <= mem_width_se_i;
      load_addr_low_r    <= mem_alu_result_i[1:0];
      load_err_r         <= mem_stage_err_w;
      load_is_mmio_r     <= mem_is_mmio_i;
    end else if (hold_i) begin
      memwb_regwrite_o   <= memwb_regwrite_o;
      memwb_rd_addr_o    <= memwb_rd_addr_o;
      memwb_wb_se_o      <= memwb_wb_se_o;
      memwb_pc_plus_o    <= memwb_pc_plus_o;
      memwb_alu_result_o <= memwb_alu_result_o;
      memwb_mem_data_o   <= memwb_mem_data_o;
      mem_stage_err_o    <= mem_stage_err_o;
      load_pending_r     <= load_pending_r;
      load_regwrite_r    <= load_regwrite_r;
      load_rd_addr_r     <= load_rd_addr_r;
      load_wb_se_r       <= load_wb_se_r;
      load_pc_plus_r     <= load_pc_plus_r;
      load_alu_result_r  <= load_alu_result_r;
      load_width_se_r    <= load_width_se_r;
      load_addr_low_r    <= load_addr_low_r;
      load_err_r         <= load_err_r;
      load_is_mmio_r     <= load_is_mmio_r;
    end else if (load_pending_r) begin
      memwb_regwrite_o   <= load_regwrite_r;
      memwb_rd_addr_o    <= load_rd_addr_r;
      memwb_wb_se_o      <= load_wb_se_r;
      memwb_pc_plus_o    <= load_pc_plus_r;
      memwb_alu_result_o <= load_alu_result_r;
      memwb_mem_data_o   <= data_r_cvt_w;
      mem_stage_err_o    <= load_err_r | mem_stage_err_w;
      load_pending_r     <= 1'b0;
      load_is_mmio_r     <= 1'b0;
    end else if (mem_en_i && !mem_we_i) begin
      // First cycle of a synchronous load: issue the request and wait one more
      // cycle for the response before exposing it to MEM/WB.
      memwb_regwrite_o   <= 1'b0;
      memwb_rd_addr_o    <= 5'b0;
      memwb_wb_se_o      <= 2'b0;
      memwb_pc_plus_o    <= mem_pc_plus_i;
      memwb_alu_result_o <= mem_alu_result_i;
      memwb_mem_data_o   <= 32'b0;
      mem_stage_err_o    <= mem_stage_err_w;

      load_pending_r     <= 1'b1;
      load_regwrite_r    <= mem_regwrite_i;
      load_rd_addr_r     <= mem_rd_addr_i;
      load_wb_se_r       <= mem_wb_se_i;
      load_pc_plus_r     <= mem_pc_plus_i;
      load_alu_result_r  <= mem_alu_result_i;
      load_width_se_r    <= mem_width_se_i;
      load_addr_low_r    <= mem_alu_result_i[1:0];
      load_err_r         <= mem_stage_err_w;
      load_is_mmio_r     <= mem_is_mmio_i;
    end else begin
      memwb_regwrite_o   <= mem_regwrite_i;
      memwb_rd_addr_o    <= mem_rd_addr_i;
      memwb_wb_se_o      <= mem_wb_se_i;
      memwb_pc_plus_o    <= mem_pc_plus_i;
      memwb_alu_result_o <= mem_alu_result_i;
      memwb_mem_data_o   <= data_r_cvt_w;
      mem_stage_err_o    <= mem_stage_err_w;
      load_pending_r     <= 1'b0;
      load_is_mmio_r     <= 1'b0;
    end
  end

endmodule
