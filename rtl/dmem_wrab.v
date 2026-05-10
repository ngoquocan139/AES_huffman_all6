/*
ENTITY dmem_ip IS
  PORT (
    clka : IN STD_LOGIC;
    ena : IN STD_LOGIC;
    wea : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    addra : IN STD_LOGIC_VECTOR(8 DOWNTO 0);
    dina : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
    douta : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
  );
END dmem;
*/
// 8 bit address x 32 = 8kb
module dmem_wrab(
  input wire clka,
  input wire ena,
  input wire [3:0] wea,
  input wire [7:0] addra,
  input wire [31:0] dina,
  output wire [31:0] douta
);

  dmem dmem_uut0(
    .clka(clka),
    .ena(ena),
    .wea(wea[0]),
    .addra(addra),
    .dina(dina[7:0]),
    .douta(douta[7:0])
  );

  dmem dmem_uut1(
    .clka(clka),
    .ena(ena),
    .wea(wea[1]),
    .addra(addra),
    .dina(dina[15:8]),
    .douta(douta[15:8])
  );

  dmem dmem_uut2(
    .clka(clka),
    .ena(ena),
    .wea(wea[2]),
    .addra(addra),
    .dina(dina[23:16]),
    .douta(douta[23:16])
  );

  dmem dmem_uut3(
    .clka(clka),
    .ena(ena),
    .wea(wea[3]),
    .addra(addra),
    .dina(dina[31:24]),
    .douta(douta[31:24])
  );

endmodule
