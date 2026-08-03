`timescale 1ns / 1ps

module test_bench;
  // NIST SP 800-38A AES-128 CBC example vectors, first two blocks.
  localparam [127:0] AES_KEY =
      128'h2b7e151628aed2a6abf7158809cf4f3c;
  localparam [127:0] AES_IV =
      128'h000102030405060708090a0b0c0d0e0f;
  localparam [127:0] PLAIN_BLOCK_1 =
      128'h6bc1bee22e409f96e93d7e117393172a;
  localparam [127:0] PLAIN_BLOCK_2 =
      128'hae2d8a571e03ac9c9eb76fac45af8e51;
  localparam [127:0] EXPECTED_CIPHER_1 =
      128'h7649abac8119b246cee98e9b12e9197d;
  localparam [127:0] EXPECTED_CIPHER_2 =
      128'h5086cb9b507219ee95db113a917678b2;

  localparam [1:0] PHASE_IDLE    = 2'd0;
  localparam [1:0] PHASE_ENCRYPT = 2'd1;
  localparam [1:0] PHASE_DECRYPT = 2'd2;
  localparam [1:0] PHASE_DONE    = 2'd3;

  reg          clk_sys;
  reg          rst_n;

  reg  [1:0]   phase_r;
  reg          cipher_en;
  reg          decipher_en;

  reg  [127:0] enc_plaintext_block_r;
  reg  [127:0] enc_cbc_feedback_r;
  reg  [127:0] enc_aes_core_input_r;
  reg  [127:0] enc_expected_cipher_r;
  reg  [127:0] enc_previous_cipher_r;
  reg  [127:0] enc_cipher_block1_r;
  reg  [127:0] enc_cipher_block2_r;
  reg  [1:0]   enc_block_index_r;
  reg          enc_match_r;
  reg          enc_all_match_r;

  reg  [127:0] dec_ciphertext_block_r;
  reg  [127:0] dec_cbc_feedback_r;
  reg  [127:0] dec_previous_cipher_r;
  reg  [127:0] dec_expected_plain_r;
  reg  [1:0]   dec_block_index_r;
  reg          dec_match_r;
  reg          dec_all_match_r;
  reg          all_done_r;

  wire [127:0] enc_cipher_text_w;
  wire         enc_cipher_ready_w;
  wire [127:0] enc_round_key10_w;

  wire [127:0] dec_aes_inverse_output_w;
  wire [127:0] dec_recovered_plain_w;
  wire         dec_decipher_ready_w;

  aes128_cipher_top u_enc (
    .clk_sys      (clk_sys),
    .rst_n        (rst_n),
    .cipher_key   (AES_KEY),
    .plain_text   (enc_aes_core_input_r),
    .cipher_en    (cipher_en),
    .cipher_text  (enc_cipher_text_w),
    .cipher_ready (enc_cipher_ready_w),
    .cipher_key10 (enc_round_key10_w)
  );

  aes128_cipher_inv_top u_dec (
    .clk_sys        (clk_sys),
    .rst_n          (rst_n),
    .cipher_text    (dec_ciphertext_block_r),
    .round_key_10   (enc_round_key10_w),
    .decipher_en    (decipher_en),
    .plain_text     (dec_aes_inverse_output_w),
    .decipher_ready (dec_decipher_ready_w)
  );

  assign dec_recovered_plain_w = dec_aes_inverse_output_w ^ dec_cbc_feedback_r;

  // Common waveform aliases.
  wire [1:0]   wf_phase                 = phase_r;
  wire [127:0] wf_key                   = AES_KEY;
  wire [127:0] wf_iv                    = AES_IV;
  wire [127:0] wf_round_key_10          = enc_round_key10_w;
  wire         wf_all_done              = all_done_r;

  // Encrypt waveform aliases.
  wire [1:0]   wf_enc_block_index       = enc_block_index_r;
  wire [127:0] wf_enc_plaintext_Pi      = enc_plaintext_block_r;
  wire [127:0] wf_enc_cbc_feedback      = enc_cbc_feedback_r;
  wire [127:0] wf_enc_aes_input         = enc_aes_core_input_r;
  wire [3:0]   wf_enc_round_num         = u_enc.round_num;
  wire         wf_enc_rkey_en           = u_enc.rkey_en;
  wire [127:0] wf_enc_round_key         = u_enc.round_key_out;
  wire [127:0] wf_enc_after_subbytes    = u_enc.u_aes128_cipher_core.after_subBytes;
  wire [127:0] wf_enc_after_shiftrows   = u_enc.u_aes128_cipher_core.after_shiftRows;
  wire [127:0] wf_enc_after_mixcolumns  = u_enc.u_aes128_cipher_core.after_mixColumns;
  wire [127:0] wf_enc_after_addroundkey = u_enc.u_aes128_cipher_core.after_addRoundkey;
  wire [127:0] wf_enc_cipher_Ci         = enc_cipher_text_w;
  wire [127:0] wf_enc_expected_Ci       = enc_expected_cipher_r;
  wire         wf_enc_match             = enc_match_r;
  wire         wf_enc_all_match         = enc_all_match_r;

  // Decrypt waveform aliases.
  wire [1:0]   wf_dec_block_index       = dec_block_index_r;
  wire [127:0] wf_dec_cipher_Ci         = dec_ciphertext_block_r;
  wire [127:0] wf_dec_cbc_feedback      = dec_cbc_feedback_r;
  wire [3:0]   wf_dec_round_num         = u_dec.round_num;
  wire         wf_dec_rkey_en           = u_dec.rkey_en;
  wire [127:0] wf_dec_round_key_inv     = u_dec.round_key_inv_out;
  wire [127:0] wf_dec_after_invshift    = u_dec.u_aes128_cipher_core_inv.after_InvShiftRows;
  wire [127:0] wf_dec_after_invsub      = u_dec.u_aes128_cipher_core_inv.after_InvSubBytes;
  wire [127:0] wf_dec_after_invmix      = u_dec.u_aes128_cipher_core_inv.after_InvMixColumns;
  wire [127:0] wf_dec_after_addroundkey = u_dec.u_aes128_cipher_core_inv.after_AddRoundKey;
  wire [127:0] wf_dec_aes_inverse       = dec_aes_inverse_output_w;
  wire [127:0] wf_dec_recovered_Pi      = dec_recovered_plain_w;
  wire [127:0] wf_dec_expected_Pi       = dec_expected_plain_r;
  wire         wf_dec_match             = dec_match_r;
  wire         wf_dec_all_match         = dec_all_match_r;

  initial begin
    clk_sys = 1'b0;
    forever #5 clk_sys = ~clk_sys;
  end

  initial begin
    $dumpfile("aes128_cbc_enc_dec_wave.vcd");
    $dumpvars(0, test_bench);
  end

  task run_encrypt_block;
    input [127:0] plaintext_i;
    input [127:0] expected_cipher_i;
    begin
      wait (enc_cipher_ready_w == 1'b1);
      @(negedge clk_sys);
      phase_r                = PHASE_ENCRYPT;
      enc_plaintext_block_r  = plaintext_i;
      enc_cbc_feedback_r     = (enc_block_index_r == 2'd0) ? AES_IV : enc_previous_cipher_r;
      enc_aes_core_input_r   = plaintext_i ^ ((enc_block_index_r == 2'd0) ? AES_IV : enc_previous_cipher_r);
      enc_expected_cipher_r  = expected_cipher_i;
      enc_match_r            = 1'b0;
      cipher_en              = 1'b1;

      @(negedge clk_sys);
      cipher_en = 1'b0;

      wait (enc_cipher_ready_w == 1'b0);
      wait (enc_cipher_ready_w == 1'b1);
      @(posedge clk_sys);

      enc_match_r = (enc_cipher_text_w == expected_cipher_i);
      enc_all_match_r = enc_all_match_r && (enc_cipher_text_w == expected_cipher_i);

      if (enc_block_index_r == 2'd0)
        enc_cipher_block1_r = enc_cipher_text_w;
      else
        enc_cipher_block2_r = enc_cipher_text_w;

      if (enc_cipher_text_w == expected_cipher_i) begin
        $display("[PASS] CBC encrypt block %0d matched expected ciphertext.", enc_block_index_r + 1);
      end else begin
        $display("[FAIL] CBC encrypt block %0d mismatch.", enc_block_index_r + 1);
        $display("plaintext = 0x%032h", plaintext_i);
        $display("feedback  = 0x%032h", enc_cbc_feedback_r);
        $display("aes_input = 0x%032h", enc_aes_core_input_r);
        $display("cipher    = 0x%032h", enc_cipher_text_w);
        $display("expected  = 0x%032h", expected_cipher_i);
      end

      enc_previous_cipher_r = enc_cipher_text_w;
      enc_block_index_r     = enc_block_index_r + 1'b1;
      @(posedge clk_sys);
    end
  endtask

  task run_decrypt_block;
    input [127:0] ciphertext_i;
    input [127:0] expected_plain_i;
    begin
      wait (dec_decipher_ready_w == 1'b1);
      @(negedge clk_sys);
      phase_r                = PHASE_DECRYPT;
      dec_ciphertext_block_r = ciphertext_i;
      dec_cbc_feedback_r     = (dec_block_index_r == 2'd0) ? AES_IV : dec_previous_cipher_r;
      dec_expected_plain_r   = expected_plain_i;
      dec_match_r            = 1'b0;
      decipher_en            = 1'b1;

      @(negedge clk_sys);
      decipher_en = 1'b0;

      wait (dec_decipher_ready_w == 1'b0);
      wait (dec_decipher_ready_w == 1'b1);
      @(posedge clk_sys);

      dec_match_r = (dec_recovered_plain_w == expected_plain_i);
      dec_all_match_r = dec_all_match_r && (dec_recovered_plain_w == expected_plain_i);

      if (dec_recovered_plain_w == expected_plain_i) begin
        $display("[PASS] CBC decrypt block %0d recovered expected plaintext.", dec_block_index_r + 1);
      end else begin
        $display("[FAIL] CBC decrypt block %0d mismatch.", dec_block_index_r + 1);
        $display("ciphertext = 0x%032h", ciphertext_i);
        $display("feedback   = 0x%032h", dec_cbc_feedback_r);
        $display("aes_inv    = 0x%032h", dec_aes_inverse_output_w);
        $display("plaintext  = 0x%032h", dec_recovered_plain_w);
        $display("expected   = 0x%032h", expected_plain_i);
      end

      dec_previous_cipher_r = ciphertext_i;
      dec_block_index_r     = dec_block_index_r + 1'b1;
      @(posedge clk_sys);
    end
  endtask

  initial begin
    rst_n                 = 1'b0;
    phase_r               = PHASE_IDLE;
    cipher_en             = 1'b0;
    decipher_en           = 1'b0;

    enc_plaintext_block_r = 128'b0;
    enc_cbc_feedback_r    = 128'b0;
    enc_aes_core_input_r  = 128'b0;
    enc_expected_cipher_r = 128'b0;
    enc_previous_cipher_r = 128'b0;
    enc_cipher_block1_r   = 128'b0;
    enc_cipher_block2_r   = 128'b0;
    enc_block_index_r     = 2'd0;
    enc_match_r           = 1'b0;
    enc_all_match_r       = 1'b1;

    dec_ciphertext_block_r = 128'b0;
    dec_cbc_feedback_r     = 128'b0;
    dec_previous_cipher_r  = 128'b0;
    dec_expected_plain_r   = 128'b0;
    dec_block_index_r      = 2'd0;
    dec_match_r            = 1'b0;
    dec_all_match_r        = 1'b1;
    all_done_r             = 1'b0;

    repeat (4) @(posedge clk_sys);
    rst_n = 1'b1;
    repeat (2) @(posedge clk_sys);

    run_encrypt_block(PLAIN_BLOCK_1, EXPECTED_CIPHER_1);
    run_encrypt_block(PLAIN_BLOCK_2, EXPECTED_CIPHER_2);

    repeat (2) @(posedge clk_sys);

    run_decrypt_block(enc_cipher_block1_r, PLAIN_BLOCK_1);
    run_decrypt_block(enc_cipher_block2_r, PLAIN_BLOCK_2);

    phase_r    = PHASE_DONE;
    all_done_r = enc_all_match_r && dec_all_match_r;

    if (all_done_r) begin
      $display("[PASS] AES-128-CBC encrypt and decrypt both matched the NIST two-block vector.");
      $display("C1 = 0x%032h", enc_cipher_block1_r);
      $display("C2 = 0x%032h", enc_cipher_block2_r);
      $display("P1 = 0x%032h", PLAIN_BLOCK_1);
      $display("P2 = 0x%032h", PLAIN_BLOCK_2);
    end else begin
      $display("[FAIL] AES-128-CBC combined encrypt/decrypt waveform test failed.");
    end

    repeat (8) @(posedge clk_sys);
    $finish;
  end
endmodule
