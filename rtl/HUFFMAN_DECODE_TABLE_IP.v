// Behavioral simulation model for the Vivado-generated
// HUFFMAN_DECODE_TABLE_IP block memory.
//
// The synthesis flow creates a blk_mem_gen true dual-port RAM with the same
// native interface. This model keeps Verilator/Questa independent from Vivado
// generated simulation files.
module HUFFMAN_DECODE_TABLE_IP (
  input  wire        clka,
  input  wire        ena,
  input  wire [0:0]  wea,
  input  wire [10:0] addra,
  input  wire [14:0] dina,
  output reg  [14:0] douta,

  input  wire        clkb,
  input  wire        enb,
  input  wire [0:0]  web,
  input  wire [10:0] addrb,
  input  wire [14:0] dinb,
  output reg  [14:0] doutb
);

  localparam integer MEM_WORDS = 2048;

  (* ram_style = "block" *) reg [14:0] mem [0:MEM_WORDS-1];
  integer i;

  initial begin
    for (i = 0; i < MEM_WORDS; i = i + 1)
      mem[i] = 15'h0000;
    douta = 15'h0000;
    doutb = 15'h0000;
  end

  always @(posedge clka) begin
    if (ena) begin
      douta <= mem[addra];
      if (wea[0])
        mem[addra] <= dina;
    end
  end

  always @(posedge clkb) begin
    if (enb) begin
      doutb <= mem[addrb];
      if (web[0])
        mem[addrb] <= dinb;
    end
  end

endmodule
