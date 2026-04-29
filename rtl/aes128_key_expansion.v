//===================================================================
// File: aes128_key_expansion.v
// Description: AES-128 Key expansion (Verilog-2001)
// Author (original): Nguyen Hung Quan
// Website: http://nguyenquanicd.blogspot.com/
// Notes: Converted from SystemVerilog to Verilog-2001 without changing logic.
// Dependencies:
//   - aes_encrypt_funcs.vh  (provides aes128_sbox() and aes128_rcon())
//===================================================================

module aes128_key_expansion (
    // input
    input              clk_sys,
    input              rst_n,       // kept for interface compatibility (not used in original)
    input              cipher_en,
    input              rkey_en,
    input      [127:0] cipher_key,
    input      [3:0]   round_num,
    // output
    output     [127:0] round_key_out
);

  // include functions inside module scope
  `include "aes_encrypt_funcs.vh"

  /* verilator lint_off UNUSEDSIGNAL */
  wire _unused_rst_n = rst_n;
  /* verilator lint_on  UNUSEDSIGNAL */

  // Internal signals (Verilog-2001: reg/wire)
  reg  [127:0] round_key_reg;
  wire [127:0] key_in;
  wire [127:0] round_key;

  wire [31:0]  after_subW;
  wire [31:0]  after_rotW;
  wire [31:0]  after_addRcon;
  wire [31:0]  rcon_value;

  //----------------------------------------------------------------------------
  // Storing round key
  //----------------------------------------------------------------------------
  always @(posedge clk_sys) begin
    if (cipher_en | rkey_en) begin
      round_key_reg <= round_key;
    end
  end

  assign round_key_out = round_key_reg;

  assign key_in = (round_num == 4'd0) ? cipher_key : round_key_reg;

  //----------------------------------------------------------------------------
  // rotW - Rotate LSB [31:0]
  // w0 is MSB [127:96], w3 is LSB [31:0]
  //----------------------------------------------------------------------------
  assign after_rotW = {key_in[23:0], key_in[31:24]};

  //----------------------------------------------------------------------------
  // subW - Subword with S-BOX (encrypt_en=1)
  //----------------------------------------------------------------------------
  assign after_subW[31:24] = aes128_sbox(after_rotW[31:24], 1'b1);
  assign after_subW[23:16] = aes128_sbox(after_rotW[23:16], 1'b1);
  assign after_subW[15:8]  = aes128_sbox(after_rotW[15:8],  1'b1);
  assign after_subW[7:0]   = aes128_sbox(after_rotW[7:0],   1'b1);

  //----------------------------------------------------------------------------
  // addRcon is XOR Rcon value
  //----------------------------------------------------------------------------
  assign rcon_value    = aes128_rcon(round_num);
  assign after_addRcon = after_subW ^ rcon_value;

  //----------------------------------------------------------------------------
  // Round key
  //----------------------------------------------------------------------------
  assign round_key[127:96] = after_addRcon     ^ key_in[127:96];
  assign round_key[95:64]  = round_key[127:96] ^ key_in[95:64];
  assign round_key[63:32]  = round_key[95:64]  ^ key_in[63:32];
  assign round_key[31:0]   = round_key[63:32]  ^ key_in[31:0];

endmodule

