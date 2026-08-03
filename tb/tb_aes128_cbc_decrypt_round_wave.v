`timescale 1ns / 1ps

module test_bench;
  // NIST SP 800-38A CBC-AES128 example vectors.
  localparam [127:0] ROUND_KEY_10 =
      128'hd014f9a8c9ee2589e13f0cc8b6630ca6;
  localparam [127:0] AES_IV =
      128'h000102030405060708090a0b0c0d0e0f;
  localparam [127:0] CIPHER_BLOCK_1 =
      128'h7649abac8119b246cee98e9b12e9197d;
  localparam [127:0] CIPHER_BLOCK_2 =
      128'h5086cb9b507219ee95db113a917678b2;
  localparam [127:0] EXPECTED_PLAIN_1 =
      128'h6bc1bee22e409f96e93d7e117393172a;
  localparam [127:0] EXPECTED_PLAIN_2 =
      128'hae2d8a571e03ac9c9eb76fac45af8e51;

  reg          clk_sys;
  reg          rst_n;
  reg          decipher_en;
  reg  [127:0] ciphertext_block_r;
  reg  [127:0] cbc_feedback_r;
  reg  [127:0] previous_cipher_r;
  reg  [127:0] expected_plain_r;
  reg  [1:0]   block_index_r;
  reg          output_match_r;
  reg          all_done_r;

  wire [127:0] aes_inverse_output_w;
  wire [127:0] recovered_plain_w;
  wire         decipher_ready;

  aes128_cipher_inv_top u_aes_cbc_dec_core (
    .clk_sys        (clk_sys),
    .rst_n          (rst_n),
    .cipher_text    (ciphertext_block_r),
    .round_key_10   (ROUND_KEY_10),
    .decipher_en    (decipher_en),
    .plain_text     (aes_inverse_output_w),
    .decipher_ready (decipher_ready)
  );

  assign recovered_plain_w = aes_inverse_output_w ^ cbc_feedback_r;

  // Waveform aliases.
  wire [1:0]   wf_cbc_block_index      = block_index_r;
  wire [127:0] wf_ciphertext_block_Ci  = ciphertext_block_r;
  wire [127:0] wf_iv                   = AES_IV;
  wire [127:0] wf_cbc_feedback         = cbc_feedback_r;
  wire [127:0] wf_round_key_10         = ROUND_KEY_10;
  wire [127:0] wf_aes_inverse_output   = aes_inverse_output_w;
  wire [127:0] wf_recovered_plaintext  = recovered_plain_w;
  wire [127:0] wf_expected_plaintext   = expected_plain_r;
  wire [3:0]   wf_round_num            = u_aes_cbc_dec_core.round_num;
  wire         wf_rkey_en              = u_aes_cbc_dec_core.rkey_en;
  wire [127:0] wf_round_key_inv        = u_aes_cbc_dec_core.round_key_inv_out;
  wire [127:0] wf_state_reg            = u_aes_cbc_dec_core.u_aes128_cipher_core_inv.plainText_reg;
  wire [127:0] wf_after_invshiftrows   = u_aes_cbc_dec_core.u_aes128_cipher_core_inv.after_InvShiftRows;
  wire [127:0] wf_after_invsubbytes    = u_aes_cbc_dec_core.u_aes128_cipher_core_inv.after_InvSubBytes;
  wire [127:0] wf_after_invmixcolumns  = u_aes_cbc_dec_core.u_aes128_cipher_core_inv.after_InvMixColumns;
  wire [127:0] wf_after_addroundkey    = u_aes_cbc_dec_core.u_aes128_cipher_core_inv.after_AddRoundKey;
  wire         wf_output_match         = output_match_r;
  wire         wf_all_done             = all_done_r;

  initial begin
    clk_sys = 1'b0;
    forever #5 clk_sys = ~clk_sys;
  end

  initial begin
    $dumpfile("aes128_cbc_decrypt_round_wave.vcd");
    $dumpvars(0, test_bench);
  end

  task run_cbc_decrypt_block;
    input [127:0] ciphertext_i;
    input [127:0] expected_plain_i;
    begin
      wait (decipher_ready == 1'b1);
      @(negedge clk_sys);
      ciphertext_block_r = ciphertext_i;
      cbc_feedback_r     = (block_index_r == 2'd0) ? AES_IV : previous_cipher_r;
      expected_plain_r   = expected_plain_i;
      output_match_r     = 1'b0;
      decipher_en        = 1'b1;

      @(negedge clk_sys);
      decipher_en = 1'b0;

      wait (decipher_ready == 1'b0);
      wait (decipher_ready == 1'b1);
      @(posedge clk_sys);

      output_match_r = (recovered_plain_w == expected_plain_i);
      if (recovered_plain_w == expected_plain_i) begin
        $display("[PASS] CBC decrypt block %0d recovered expected plaintext.", block_index_r + 1);
      end else begin
        $display("[FAIL] CBC decrypt block %0d mismatch.", block_index_r + 1);
        $display("ciphertext = 0x%032h", ciphertext_i);
        $display("feedback   = 0x%032h", cbc_feedback_r);
        $display("aes_inv    = 0x%032h", aes_inverse_output_w);
        $display("plaintext  = 0x%032h", recovered_plain_w);
        $display("expected   = 0x%032h", expected_plain_i);
      end

      previous_cipher_r = ciphertext_i;
      block_index_r     = block_index_r + 1'b1;
      @(posedge clk_sys);
    end
  endtask

  initial begin
    rst_n              = 1'b0;
    decipher_en        = 1'b0;
    ciphertext_block_r = 128'b0;
    cbc_feedback_r     = 128'b0;
    previous_cipher_r  = 128'b0;
    expected_plain_r   = 128'b0;
    block_index_r      = 2'd0;
    output_match_r     = 1'b0;
    all_done_r         = 1'b0;

    repeat (4) @(posedge clk_sys);
    rst_n = 1'b1;
    repeat (2) @(posedge clk_sys);

    run_cbc_decrypt_block(CIPHER_BLOCK_1, EXPECTED_PLAIN_1);
    run_cbc_decrypt_block(CIPHER_BLOCK_2, EXPECTED_PLAIN_2);

    all_done_r = output_match_r;
    if (output_match_r) begin
      $display("[PASS] AES-128-CBC decrypt recovered both NIST plaintext blocks.");
      $display("IV = 0x%032h", AES_IV);
      $display("P1 = 0x%032h", EXPECTED_PLAIN_1);
      $display("P2 = 0x%032h", EXPECTED_PLAIN_2);
    end else begin
      $display("[FAIL] AES-128-CBC decrypt final result did not match the reference vector.");
    end

    repeat (8) @(posedge clk_sys);
    $finish;
  end
endmodule
