module dmem_sync_wrab (
  input  wire       clka,
  input  wire       ena,
  input  wire [3:0] wea,
  input  wire [7:0] addra,
  input  wire [31:0] dina,
  output wire [31:0] douta
);

  dmem_sync dmem_uut0 (
    .clka (clka),
    .ena  (ena),
    .wea  (wea[0]),
    .addra(addra),
    .dina (dina[7:0]),
    .douta(douta[7:0])
  );

  dmem_sync dmem_uut1 (
    .clka (clka),
    .ena  (ena),
    .wea  (wea[1]),
    .addra(addra),
    .dina (dina[15:8]),
    .douta(douta[15:8])
  );

  dmem_sync dmem_uut2 (
    .clka (clka),
    .ena  (ena),
    .wea  (wea[2]),
    .addra(addra),
    .dina (dina[23:16]),
    .douta(douta[23:16])
  );

  dmem_sync dmem_uut3 (
    .clka (clka),
    .ena  (ena),
    .wea  (wea[3]),
    .addra(addra),
    .dina (dina[31:24]),
    .douta(douta[31:24])
  );
endmodule
