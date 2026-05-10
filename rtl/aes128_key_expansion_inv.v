//===================================================================
// File: aes128_key_expansion_inv.v
// Description: AES-128 key expansion inverse (Verilog-2001)
// Notes: Converted from SystemVerilog to Verilog-2001 without changing logic.
// Author (original): Nguyen Hung Quan
// Website: http://nguyenquanicd.blogspot.com/
// Dependencies:
//   - aes_inverse_funcs.v  (provides aes128_sbox() and aes128_rcon_inv())
//===================================================================

module aes128_key_expansion_inv (
    // input
    input              clk_sys,
    input              rst_n,          // kept for interface compatibility (not used in original)
    input              decipher_en,
    input              rkey_en,
    input      [127:0] round_key_10,
    input      [3:0]   round_num,
    // output
    output     [127:0] round_key_inv_out
);

`include "aes_inverse_funcs.vh"

/* verilator lint_off UNUSEDSIGNAL */
wire _unused_rst_n = rst_n;
/* verilator lint_on  UNUSEDSIGNAL */

    // ----------------------------------------------------------------
    // Internal signals (Verilog-2001: use reg/wire)
    // ----------------------------------------------------------------
    reg  [127:0] round_key_reg;

    wire [127:0] key_in;
    wire [127:0] round_key;

    wire [31:0]  after_subW;
    wire [31:0]  after_rotW;
    wire [31:0]  after_addRcon;
    wire [31:0]  rcon_value_inv;

    // ----------------------------------------------------------------
    // Store round key (same behavior as original)
    // ----------------------------------------------------------------
    always @(posedge clk_sys) begin
        if (decipher_en | rkey_en) begin
            round_key_reg[127:0] <= round_key[127:0];
        end
    end

    assign round_key_inv_out[127:0] = round_key_reg[127:0];

    assign key_in[127:0] = (round_num[3:0] == 4'd0) ? round_key_10[127:0]
                                                    : round_key_reg[127:0];

    // ----------------------------------------------------------------
    // AddW (inverse key expansion word relations)
    // ----------------------------------------------------------------
    assign round_key[31:0]   = key_in[31:0]   ^ key_in[63:32];
    assign round_key[63:32]  = key_in[63:32]  ^ key_in[95:64];
    assign round_key[95:64]  = key_in[95:64]  ^ key_in[127:96];

    // RotWord (on round_key[31:0])
    assign after_rotW[31:0] = {round_key[23:0], round_key[31:24]};

    // ----------------------------------------------------------------
    // SubWord with S-BOX (encrypt_en=1 uses forward S-Box, same as original)
    // Requires aes128_sbox() function available in compilation (e.g. aes_inverse_funcs.v)
    // ----------------------------------------------------------------
    assign after_subW[31:24] = aes128_sbox(after_rotW[31:24], 1'b1);
    assign after_subW[23:16] = aes128_sbox(after_rotW[23:16], 1'b1);
    assign after_subW[15:8]  = aes128_sbox(after_rotW[15:8],  1'b1);
    assign after_subW[7:0]   = aes128_sbox(after_rotW[7:0],   1'b1);

    // ----------------------------------------------------------------
    // InvAddRcon (XOR with inverse Rcon value)
    // Requires aes128_rcon_inv() function available in compilation (e.g. aes_inverse_funcs.v)
    // ----------------------------------------------------------------
    assign rcon_value_inv[31:0] = aes128_rcon_inv(round_num[3:0]);
    assign after_addRcon[31:0]  = after_subW[31:0] ^ rcon_value_inv[31:0];

    // Calculate word[0] (MSW)
    assign round_key[127:96] = after_addRcon[31:0] ^ key_in[127:96];

endmodule

