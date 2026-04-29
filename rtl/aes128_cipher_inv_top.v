//===================================================================
// File: aes128_cipher_inv_top.v
// Description: AES-128 decrypt/decipher TOP module (Verilog-2001)
// Notes: Converted from SystemVerilog to Verilog-2001 without changing logic.
// Author (original): Nguyen Hung Quan
// Website: http://nguyenquanicd.blogspot.com/
// Dependencies:
//   - aes_inverse_funcs.v
//   - aes128_key_expansion_inv.v
//   - aes128_cipher_core_inv.v
//===================================================================

module aes128_cipher_inv_top (
    // input
    input              clk_sys,
    input              rst_n,
    input      [127:0] cipher_text,
    input      [127:0] round_key_10,
    input              decipher_en,
    // output
    output     [127:0] plain_text,
    output             decipher_ready
);

    // ----------------------------------------------------------------
    // Internal signals (Verilog-2001: wire)
    // ----------------------------------------------------------------
    wire [127:0] round_key_inv_out;
    wire [3:0]   round_num;
    wire         rkey_en;

    // ----------------------------------------------------------------
    // Instances
    // ----------------------------------------------------------------
    aes128_cipher_core_inv u_aes128_cipher_core_inv (
        .clk_sys        (clk_sys),
        .rst_n          (rst_n),
        .round_key_10   (round_key_10[127:0]),
        .round_key_inv  (round_key_inv_out[127:0]),
        .cipher_text    (cipher_text[127:0]),
        .decipher_en    (decipher_en),
        .plain_text     (plain_text[127:0]),
        .decipher_ready (decipher_ready),
        .round_num      (round_num[3:0]),
        .rkey_en        (rkey_en)
    );

    aes128_key_expansion_inv u_aes128_key_expansion_inv (
        .clk_sys           (clk_sys),
        .rst_n             (rst_n),
        .decipher_en       (decipher_en),
        .rkey_en           (rkey_en),
        .round_key_10      (round_key_10[127:0]),
        .round_num         (round_num[3:0]),
        .round_key_inv_out (round_key_inv_out[127:0])
    );

endmodule

