// Behavioral simulation model for the Vivado-generated DMEM_ip.
//
// Matches the currently generated native interface:
// - True dual port
// - 32-bit data
// - byte write enable on both ports
// - 13-bit word address, 8192 x 32-bit words
// - READ_FIRST behavior
// - 1-cycle synchronous read latency
//
// This file is for simulation only. When integrating the real Vivado IP into
// the project, do not compile this model alongside the generated IP wrapper.
module DMEM_ip (
  input  wire        clka,
  input  wire        ena,
  input  wire [3:0]  wea,
  input  wire [12:0] addra,
  input  wire [31:0] dina,
  output reg  [31:0] douta,
  input  wire        clkb,
  input  wire        enb,
  input  wire [3:0]  web,
  input  wire [12:0] addrb,
  input  wire [31:0] dinb,
  output reg  [31:0] doutb
);

  localparam integer MEM_BYTES = 32768; // 8192 words x 4 bytes
  localparam integer MEM_WORDS = MEM_BYTES / 4;
  (* ram_style = "block" *) reg [31:0] mem [0:MEM_WORDS-1];
  integer i;

  initial begin
    for (i = 0; i < MEM_WORDS; i = i + 1)
      mem[i] = 32'h00000000;
    douta = 32'h00000000;
    doutb = 32'h00000000;
  end

  always @(posedge clka) begin
    if (ena) begin
      // READ_FIRST: return the old contents before any write on this edge.
      douta <= mem[addra];

      if (wea[0]) mem[addra][7:0]   <= dina[7:0];
      if (wea[1]) mem[addra][15:8]  <= dina[15:8];
      if (wea[2]) mem[addra][23:16] <= dina[23:16];
      if (wea[3]) mem[addra][31:24] <= dina[31:24];
    end
  end

  always @(posedge clkb) begin
    if (enb) begin
      doutb <= mem[addrb];

      if (web[0]) mem[addrb][7:0]   <= dinb[7:0];
      if (web[1]) mem[addrb][15:8]  <= dinb[15:8];
      if (web[2]) mem[addrb][23:16] <= dinb[23:16];
      if (web[3]) mem[addrb][31:24] <= dinb[31:24];
    end
  end

endmodule
