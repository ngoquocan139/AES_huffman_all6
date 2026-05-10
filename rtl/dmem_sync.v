module dmem_sync (
  input  wire       clka,
  input  wire       ena,
  input  wire       wea,
  input  wire [7:0] addra,
  input  wire [7:0] dina,
  output reg  [7:0] douta
);

  reg [7:0] mem [0:255];
  integer i;

  initial begin
    for (i = 0; i < 256; i = i + 1)
      mem[i] = 8'b0;
    douta = 8'b0;
    $display("Sync Index 0: %h", mem[0]);
  end

  always @(posedge clka) begin
    if (ena) begin
      douta <= mem[addra];
      if (wea)
        mem[addra] <= dina;
    end
  end
endmodule
