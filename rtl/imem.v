`include "defines.vh"
module imem (
  input wire en_i,
  input wire [9:0] instr_addr_i,
  output wire [31:0] instruction_o
);
  reg [31:0] instructions_r [0:1023];
  assign instruction_o = (en_i == 1) ? instructions_r[instr_addr_i] : 32'h00000013;
  integer i;
  initial begin
    for(i = 0; i < 1024 ; i=i+1)
    instructions_r[i] =32'b0;
    $readmemh("instruction.mem", instructions_r);
    $display("Istr 0: %h", instructions_r[0]);
    $display("Istr 1: %h", instructions_r[1]);
    $display("Istr 2: %h", instructions_r[2]);
    $display("Istr 3: %h", instructions_r[3]);
  end 
  /*
  always @ (posedge clk_i) begin
    if (en_i) instruction_o <= instructions_r[instr_addr_i];
  end
  */
endmodule
