module registers_file (
  input  wire        clk,
  input  wire        rst,

  input  wire [4:0]  rs1_addr,
  input  wire [4:0]  rs2_addr,
  output wire [31:0] rs1_data,
  output wire [31:0] rs2_data,

  input  wire        reg_write,
  input  wire [4:0]  rd_addr,
  input  wire [31:0] rd_data
);

  reg [31:0] registers [0:31];

  integer i;
  initial begin
    for (i = 0; i < 32; i = i + 1) begin
      registers[i] = 32'b0;
    end
  end
  // Synchronous write
  always @(posedge clk) begin
    if (rst) begin
      for (i = 0; i < 32; i = i + 1) begin
        registers[i] <= 32'b0;
      end
    end else if (reg_write && rd_addr != 5'd0) begin
      registers[rd_addr] <= rd_data;
    end
  end

  // Asynchronous read with same-cycle write-through so decode sees the value
  // being written back on this clock edge.
  assign rs1_data = (rs1_addr == 5'd0) ? 32'b0 :
                    ((reg_write && (rd_addr == rs1_addr) && (rd_addr != 5'd0)) ?
                     rd_data : registers[rs1_addr]);
  assign rs2_data = (rs2_addr == 5'd0) ? 32'b0 :
                    ((reg_write && (rd_addr == rs2_addr) && (rd_addr != 5'd0)) ?
                     rd_data : registers[rs2_addr]);

endmodule
