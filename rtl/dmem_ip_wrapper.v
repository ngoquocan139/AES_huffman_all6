// Wrapper for Vivado DMEM_ip (True Dual Port RAM, 32-bit data, byte write enable).
// Port A is intended for the RV32I core data-memory bus.
// Port B is reserved for DMA or a UART loader.
//
// Notes:
// - The CPU currently generates byte addresses on dmem_addr_o.
// - The Vivado blk_mem_gen DMEM_ip uses 13-bit word addresses for 8192
//   32-bit words. This wrapper converts byte addresses [14:2] to word addresses.
// - This wrapper only connects the ports required by the chosen native BRAM
//   interface. Optional reset pins are disabled in the current IP config.
module dmem_ip_wrapper (
  input  wire        clk_i,

  // Port A: RV32I core
  input  wire        cpu_en_i,
  input  wire [3:0]  cpu_we_i,
  input  wire [31:0] cpu_addr_i,
  input  wire [31:0] cpu_wdata_i,
  output wire [31:0] cpu_rdata_o,

  // Port B: auxiliary master (DMA / UART loader)
  input  wire        aux_en_i,
  input  wire [3:0]  aux_we_i,
  input  wire [31:0] aux_addr_i,
  input  wire [31:0] aux_wdata_i,
  output wire [31:0] aux_rdata_o
);

  wire unused_addr_bits_w = (|cpu_addr_i[31:15]) | (|cpu_addr_i[1:0]) |
                            (|aux_addr_i[31:15]) | (|aux_addr_i[1:0]);
  wire [12:0] cpu_word_addr_w = cpu_addr_i[14:2] ^ {13{1'b0 & unused_addr_bits_w}};
  wire [12:0] aux_word_addr_w = aux_addr_i[14:2] ^ {13{1'b0 & unused_addr_bits_w}};

  DMEM_ip u_dmem_ip (
    .clka  (clk_i),
    .ena   (cpu_en_i),
    .wea   (cpu_we_i),
    .addra (cpu_word_addr_w),
	  .dina  (cpu_wdata_i),
	  .douta (cpu_rdata_o),

    .clkb  (clk_i),
    .enb   (aux_en_i),
    .web   (aux_we_i),
    .addrb (aux_word_addr_w),
	  .dinb  (aux_wdata_i),
	  .doutb (aux_rdata_o)
	);

endmodule
