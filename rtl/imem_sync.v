`include "defines.vh"

module imem_sync (
  input  wire        clk_i,
  input  wire        en_i,
  input  wire [10:0] instr_addr_i,
  output wire [31:0] instruction_o
);

`ifdef VIVADO_USE_IP
  IMEM_ip u_imem_ip (
    .clka  (clk_i),
    .ena   (en_i),
    .addra (instr_addr_i),
    .douta (instruction_o)
  );
`else
  reg [31:0] instructions_r [0:2047];
  reg [31:0] instruction_r;
  integer i;

  assign instruction_o = instruction_r;

  initial begin
    for (i = 0; i < 2048; i = i + 1)
      instructions_r[i] = 32'b0;
    instruction_r = `NOP_INSTR;
    $readmemh("instruction.mem", instructions_r);
    $display("Sync Istr 0: %h", instructions_r[0]);
    $display("Sync Istr 1: %h", instructions_r[1]);
    $display("Sync Istr 2: %h", instructions_r[2]);
    $display("Sync Istr 3: %h", instructions_r[3]);
  end

  always @(posedge clk_i) begin
    if (en_i)
      instruction_r <= instructions_r[instr_addr_i];
    else
      instruction_r <= `NOP_INSTR;
  end
`endif
endmodule
