`include "defines.vh"

module mem_stage (
  input  wire        clk_i,
  input  wire        rst_i,

  // Inputs from EX/MEM stage
  input  wire        mem_we_i,
  input  wire        mem_en_i,
  input  wire [2:0]  mem_width_se_i,

  input  wire [31:0] mem_alu_result_i,
  input  wire [31:0] mem_data_i,

  input  wire        mem_regwrite_i,
  input  wire [4:0]  mem_rd_addr_i,
  input  wire [1:0]  mem_wb_se_i,
  input  wire [31:0] mem_pc_plus_i,

  // Memory interface (1-cycle)
  output reg        en_o,
  output reg [3:0]  we_o,
  output wire [31:0] addr_o,
  output reg [31:0] data_w_o,
  input wire [31:0] data_r_i,

  // Outputs to WB stage (MEM/WB registers)
  output reg         memwb_regwrite_o,
  output reg  [4:0]  memwb_rd_addr_o,
  output reg  [1:0]  memwb_wb_se_o,
  output reg  [31:0] memwb_pc_plus_o,
  output reg  [31:0] memwb_alu_result_o,
  output reg [31:0] memwb_mem_data_o,
  output wire [31:0] mem_data_w,
  output reg  [1:0]  mem_stage_err_o
);

  reg write_error;
  reg read_error;
  reg [31:0] data_r_cvt_w;
  assign mem_data_w = data_r_cvt_w;
  
  wire [1:0] mem_stage_err_w;
  wire [1:0] op = mem_alu_result_i [1:0];
  assign addr_o = (mem_en_i == 1) ? mem_alu_result_i [31:0] : 32'b0;
  assign mem_stage_err_w = write_error ? 2'b01 : read_error ? 2'b10 : 2'b00;

  always @ (*) begin
    we_o = 4'b0000;
    data_r_cvt_w = 32'b0;
    data_w_o = 32'b0;
    read_error = 1'b0;
    write_error = 1'b0;
  if (mem_en_i) begin
    en_o = 1'b1;
    if (mem_we_i) begin // write
      case (mem_width_se_i)
        `SB: begin
          if (op == 2'b00) begin we_o = 4'b0001; data_w_o[7:0] = mem_data_i[7:0]; end
          else if (op == 2'b01) begin we_o = 4'b0010; data_w_o[15:8] = mem_data_i[7:0]; end
          else if (op == 2'b10) begin we_o = 4'b0100; data_w_o[23:16] = mem_data_i[7:0]; end
          else begin we_o = 4'b1000; data_w_o[31:24] = mem_data_i[7:0]; end
        end
        `SH: begin
          if (op == 2'b00) begin we_o = 4'b0011; data_w_o[15:0] = mem_data_i[15:0]; end
          else if (op == 2'b10) begin we_o = 4'b1100; data_w_o[31:16] = mem_data_i[15:0]; end
          else begin
            we_o = 4'b0000;
            write_error = 1;
          end
        end
        `SW: begin
          if (op == 2'b00) begin
            we_o = 4'b1111;
            data_w_o = mem_data_i;
          end else write_error = 1;
        end
        default: begin
          write_error = 1;
          data_w_o = 32'b0;
        end
      endcase
    end else begin // read
      case(mem_width_se_i)
        `LB: begin
          if (op == 2'b00) data_r_cvt_w = {{24{data_r_i[7]}}, data_r_i[7:0]};
          else if (op == 2'b01) data_r_cvt_w = {{24{data_r_i[15]}}, data_r_i[15:8]};
          else if (op == 2'b10) data_r_cvt_w = {{24{data_r_i[23]}}, data_r_i[23:16]};
          else data_r_cvt_w = {{24{data_r_i[31]}}, data_r_i[31:24]};
        end
        `LH: begin
          if (op == 2'b00) data_r_cvt_w = {{16{data_r_i[15]}}, data_r_i[15:0]};
          else if (op == 2'b10) data_r_cvt_w = {{16{data_r_i[31]}}, data_r_i[31:16]};
          else begin
            data_r_cvt_w = 32'b0;
            read_error = 1;
          end
        end
        `LW: begin
          if (op == 2'b00) data_r_cvt_w = data_r_i;
          else begin
            data_r_cvt_w = 32'b0;
            read_error = 1;
          end
        end
        `LBU: begin
          if (op == 2'b00) data_r_cvt_w = {24'b0, data_r_i[7:0]};
          else if (op == 2'b01) data_r_cvt_w = {24'b0, data_r_i[15:8]};
          else if (op == 2'b10) data_r_cvt_w = {24'b0, data_r_i[23:16]};
          else data_r_cvt_w = {24'b0, data_r_i[31:24]};
        end
        `LHU: begin
          if (op == 2'b00) data_r_cvt_w = {16'b0, data_r_i[15:0]};
          else if (op == 2'b10) data_r_cvt_w = {16'b0, data_r_i[31:16]};
          else begin
            data_r_cvt_w = 32'b0;
            read_error = 1;
          end
        end
        default: begin
            read_error = 1;
            data_r_cvt_w = 32'b0;
        end
      endcase
    end
    end else begin
      en_o = 1'b0;
      data_r_cvt_w = 32'b0;
    end
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
    end else begin
      memwb_regwrite_o   <= mem_regwrite_i;
      memwb_rd_addr_o    <= mem_rd_addr_i;
      memwb_wb_se_o      <= mem_wb_se_i;
      memwb_pc_plus_o    <= mem_pc_plus_i;
      memwb_alu_result_o <= mem_alu_result_i;
      memwb_mem_data_o   <= data_r_cvt_w;
      mem_stage_err_o    <= mem_stage_err_w;
    end
  end

endmodule
