//===================================================================
// File: aes128_cipher_core.v
// Description: AES-128 encrypt/cipher core (Verilog-2001)
// Author (original): Nguyen Hung Quan
// Website: http://nguyenquanicd.blogspot.com/
// Notes: Converted from SystemVerilog to Verilog-2001 without changing logic.
// Dependencies:
//   - aes_encrypt_funcs.vh  (provides aes128_sbox() and mixcol())
//===================================================================

module aes128_cipher_core(
  // input
  input              clk_sys,
  input              rst_n,
  input      [127:0] cipher_key,
  input      [127:0] round_key,
  input      [127:0] plain_text,
  input              cipher_en,
  // output
  output     [127:0] cipher_text,
  output reg         cipher_ready,
  output     [3:0]   round_num,
  output             rkey_en
);

  // Include functions inside module scope (Questa-friendly)
  `include "aes_encrypt_funcs.vh"

  // Internal signals (Verilog-2001: reg/wire)
  wire [127:0] after_mixColumns;
  wire [127:0] subbytes_sel;
  reg  [127:0] after_shiftRows;
  reg  [127:0] cipherText_reg;
  wire [127:0] mixColumns_in;
  wire [127:0] after_subBytes;
  wire [127:0] addRoundKey_in;
  wire [127:0] after_addRoundkey;

  reg  [3:0]   cipher_counter;
  wire         cipher_complete;

  // Monitor counter
  always @(posedge clk_sys or negedge rst_n) begin
    if (~rst_n)
      cipher_counter <= 4'd0;
    else if (cipher_complete)
      cipher_counter <= 4'd0;
    else if (cipher_en | rkey_en)
      cipher_counter <= cipher_counter + 1'b1;
  end

  assign cipher_complete = (cipher_counter == 4'b1010) ? 1'b1 : 1'b0;
  assign round_num       = cipher_counter;

  // Cipher status
  always @(posedge clk_sys or negedge rst_n) begin
    if (~rst_n)
      cipher_ready <= 1'b1;
    else if (cipher_en)
      cipher_ready <= 1'b0;
    else if (cipher_complete)
      cipher_ready <= 1'b1;
  end

  assign rkey_en = ~cipher_ready;

  //-------------------------------------------------------------------
  // SubBytes selection (re-ordering)
  //-------------------------------------------------------------------
  assign subbytes_sel[127:120] = cipherText_reg[127:120];
  assign subbytes_sel[119:112] = cipherText_reg[95:88];
  assign subbytes_sel[111:104] = cipherText_reg[63:56];
  assign subbytes_sel[103:96]  = cipherText_reg[31:24];
  assign subbytes_sel[95:88]   = cipherText_reg[119:112];
  assign subbytes_sel[87:80]   = cipherText_reg[87:80];
  assign subbytes_sel[79:72]   = cipherText_reg[55:48];
  assign subbytes_sel[71:64]   = cipherText_reg[23:16];
  assign subbytes_sel[63:56]   = cipherText_reg[111:104];
  assign subbytes_sel[55:48]   = cipherText_reg[79:72];
  assign subbytes_sel[47:40]   = cipherText_reg[47:40];
  assign subbytes_sel[39:32]   = cipherText_reg[15:8];
  assign subbytes_sel[31:24]   = cipherText_reg[103:96];
  assign subbytes_sel[23:16]   = cipherText_reg[71:64];
  assign subbytes_sel[15:8]    = cipherText_reg[39:32];
  assign subbytes_sel[7:0]     = cipherText_reg[7:0];

  // SubBytes - Sbox (encrypt_en=1)
  assign after_subBytes[127:120] = aes128_sbox(subbytes_sel[127:120], 1'b1);
  assign after_subBytes[119:112] = aes128_sbox(subbytes_sel[119:112], 1'b1);
  assign after_subBytes[111:104] = aes128_sbox(subbytes_sel[111:104], 1'b1);
  assign after_subBytes[103:96]  = aes128_sbox(subbytes_sel[103:96],  1'b1);
  assign after_subBytes[95:88]   = aes128_sbox(subbytes_sel[95:88],   1'b1);
  assign after_subBytes[87:80]   = aes128_sbox(subbytes_sel[87:80],   1'b1);
  assign after_subBytes[79:72]   = aes128_sbox(subbytes_sel[79:72],   1'b1);
  assign after_subBytes[71:64]   = aes128_sbox(subbytes_sel[71:64],   1'b1);
  assign after_subBytes[63:56]   = aes128_sbox(subbytes_sel[63:56],   1'b1);
  assign after_subBytes[55:48]   = aes128_sbox(subbytes_sel[55:48],   1'b1);
  assign after_subBytes[47:40]   = aes128_sbox(subbytes_sel[47:40],   1'b1);
  assign after_subBytes[39:32]   = aes128_sbox(subbytes_sel[39:32],   1'b1);
  assign after_subBytes[31:24]   = aes128_sbox(subbytes_sel[31:24],   1'b1);
  assign after_subBytes[23:16]   = aes128_sbox(subbytes_sel[23:16],   1'b1);
  assign after_subBytes[15:8]    = aes128_sbox(subbytes_sel[15:8],    1'b1);
  assign after_subBytes[7:0]     = aes128_sbox(subbytes_sel[7:0],     1'b1);

  // ShiftRows
  always @(*) begin
    // Non-shift
    after_shiftRows[127:120] = after_subBytes[127:120];
    after_shiftRows[119:112] = after_subBytes[119:112];
    after_shiftRows[111:104] = after_subBytes[111:104];
    after_shiftRows[103:96]  = after_subBytes[103:96];

    // left-shift: one byte
    after_shiftRows[71:64]   = after_subBytes[95:88];
    after_shiftRows[95:88]   = after_subBytes[87:80];
    after_shiftRows[87:80]   = after_subBytes[79:72];
    after_shiftRows[79:72]   = after_subBytes[71:64];

    // left-shift: two bytes
    after_shiftRows[47:40]   = after_subBytes[63:56];
    after_shiftRows[39:32]   = after_subBytes[55:48];
    after_shiftRows[63:56]   = after_subBytes[47:40];
    after_shiftRows[55:48]   = after_subBytes[39:32];

    // left-shift: three bytes
    after_shiftRows[23:16]   = after_subBytes[31:24];
    after_shiftRows[15:8]    = after_subBytes[23:16];
    after_shiftRows[7:0]     = after_subBytes[15:8];
    after_shiftRows[31:24]   = after_subBytes[7:0];
  end

  // Convert the bit stream to columns
  assign mixColumns_in[127:96] = {after_shiftRows[127:120],
                                  after_shiftRows[95:88],
                                  after_shiftRows[63:56],
                                  after_shiftRows[31:24]};

  assign mixColumns_in[95:64]  = {after_shiftRows[119:112],
                                  after_shiftRows[87:80],
                                  after_shiftRows[55:48],
                                  after_shiftRows[23:16]};

  assign mixColumns_in[63:32]  = {after_shiftRows[111:104],
                                  after_shiftRows[79:72],
                                  after_shiftRows[47:40],
                                  after_shiftRows[15:8]};

  assign mixColumns_in[31:0]   = {after_shiftRows[103:96],
                                  after_shiftRows[71:64],
                                  after_shiftRows[39:32],
                                  after_shiftRows[7:0]};

  // MixColumns
  assign after_mixColumns[127:96] = mixcol(mixColumns_in[127:96]);
  assign after_mixColumns[95:64]  = mixcol(mixColumns_in[95:64]);
  assign after_mixColumns[63:32]  = mixcol(mixColumns_in[63:32]);
  assign after_mixColumns[31:0]   = mixcol(mixColumns_in[31:0]);

  // AddRoundKey
  assign addRoundKey_in =
      cipher_en ? plain_text :
      (cipher_complete ? mixColumns_in : after_mixColumns);

  assign after_addRoundkey =
      addRoundKey_in ^ (cipher_en ? cipher_key : round_key);

  // Cipher text register
  always @(posedge clk_sys) begin
    if (cipher_en | rkey_en)
      cipherText_reg <= after_addRoundkey;
  end

  assign cipher_text = cipherText_reg;

endmodule

