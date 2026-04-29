//===================================================================
// File: aes128_cipher_top.v
// Description: AES-128 encrypt/cipher TOP module (Verilog-2001)
// Author (original): Nguyen Hung Quan
// Website: http://nguyenquanicd.blogspot.com/
// Notes: Converted from SystemVerilog to Verilog-2001 without changing logic.
// Dependencies:
//   - aes128_cipher_core.v
//   - aes128_key_expansion.v
//   - aes_encrypt_funcs.vh (included inside the above modules)
//===================================================================

module aes128_cipher_top (
  // input
  input              clk_sys,
  input              rst_n,
  input      [127:0] cipher_key,
  input      [127:0] plain_text,
  input              cipher_en,
  // output
  output     [127:0] cipher_text,
  output             cipher_ready,
  output wire [127:0] cipher_key10
);

  wire [3:0]   round_num;
  wire         rkey_en;
  wire [127:0] round_key_out;
  reg  [127:0]  cipher_key10_r;
  
  aes128_cipher_core u_aes128_cipher_core (
    .clk_sys      (clk_sys),
    .rst_n        (rst_n),
    .cipher_key   (cipher_key),
    .round_key    (round_key_out),
    .plain_text   (plain_text),
    .cipher_en    (cipher_en),
    .cipher_text  (cipher_text),
    .cipher_ready (cipher_ready),
    .round_num    (round_num),
    .rkey_en      (rkey_en)
  );

  aes128_key_expansion u_aes128_key_expansion (
    .clk_sys       (clk_sys),
    .rst_n         (rst_n),
    .cipher_en     (cipher_en),
    .rkey_en       (rkey_en),
    .cipher_key    (cipher_key),
    .round_num     (round_num),
    .round_key_out (round_key_out)
  );
  
    always @(posedge clk_sys)begin 
	    if (rkey_en)
		    cipher_key10_r <= round_key_out;
    end
    

    assign cipher_key10 = cipher_key10_r;
    
endmodule

