`timescale 1ns / 1ps

module test_bench;
  // NIST SP 800-38A AES-128 CBC example vectors.
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

  reg          clk_sys;
  reg          rst_n;
  reg          cipher_en;
  reg  [127:0] plaintext_block_r;
  reg  [127:0] cbc_feedback_r;
  reg  [127:0] aes_core_input_r;
  reg  [127:0] expected_cipher_r;
  reg  [127:0] previous_cipher_r;
  reg  [1:0]   block_index_r;
  reg          output_match_r;
  reg          all_done_r;

  wire [127:0] cipher_text;
  wire         cipher_ready;
  wire [127:0] cipher_key10;

  aes128_cipher_top u_aes_cbc_core (
    .clk_sys      (clk_sys),
    .rst_n        (rst_n),
    .cipher_key   (AES_KEY),
    .plain_text   (aes_core_input_r),
    .cipher_en    (cipher_en),
    .cipher_text  (cipher_text),
    .cipher_ready (cipher_ready),
    .cipher_key10 (cipher_key10)
  );

  // Waveform aliases.
  wire [127:0] wf_plaintext_block      = plaintext_block_r;
  wire [127:0] wf_iv                   = AES_IV;
  wire [127:0] wf_cbc_feedback         = cbc_feedback_r;
  wire [127:0] wf_aes_core_input       = aes_core_input_r;
  wire [127:0] wf_cipher_output        = cipher_text;
  wire [127:0] wf_expected_cipher      = expected_cipher_r;
  wire [1:0]   wf_cbc_block_index      = block_index_r;
  wire [3:0]   wf_round_num            = u_aes_cbc_core.round_num;
  wire         wf_rkey_en              = u_aes_cbc_core.rkey_en;
  wire [127:0] wf_round_key            = u_aes_cbc_core.round_key_out;
  wire [127:0] wf_state_reg            = u_aes_cbc_core.u_aes128_cipher_core.cipherText_reg;
  wire [127:0] wf_after_subbytes       = u_aes_cbc_core.u_aes128_cipher_core.after_subBytes;
  wire [127:0] wf_after_shiftrows      = u_aes_cbc_core.u_aes128_cipher_core.after_shiftRows;
  wire [127:0] wf_after_mixcolumns     = u_aes_cbc_core.u_aes128_cipher_core.after_mixColumns;
  wire [127:0] wf_after_addroundkey    = u_aes_cbc_core.u_aes128_cipher_core.after_addRoundkey;
  wire         wf_output_match         = output_match_r;
  wire         wf_all_done             = all_done_r;

  initial begin
    clk_sys = 1'b0;
    forever #5 clk_sys = ~clk_sys;
  end

  initial begin
    $dumpfile("aes128_cbc_round_wave.vcd");
    $dumpvars(0, test_bench);
  end

  task run_cbc_block;
    input [127:0] plaintext_i;
    input [127:0] expected_i;
    begin
      wait (cipher_ready == 1'b1);
      @(negedge clk_sys);
      plaintext_block_r = plaintext_i;
      cbc_feedback_r    = (block_index_r == 2'd0) ? AES_IV : previous_cipher_r;
      aes_core_input_r  = plaintext_i ^ ((block_index_r == 2'd0) ? AES_IV : previous_cipher_r);
      expected_cipher_r = expected_i;
      output_match_r    = 1'b0;
      cipher_en         = 1'b1;

      @(negedge clk_sys);
      cipher_en = 1'b0;

      wait (cipher_ready == 1'b0);
      wait (cipher_ready == 1'b1);
      @(posedge clk_sys);

      output_match_r = (cipher_text == expected_i);
      if (cipher_text == expected_i) begin
        $display("[PASS] CBC block %0d matched expected ciphertext.", block_index_r + 1'b1);
      end else begin
        $display("[FAIL] CBC block %0d mismatch.", block_index_r + 1'b1);
        $display("plaintext = 0x%032h", plaintext_i);
        $display("feedback  = 0x%032h", cbc_feedback_r);
        $display("aes_input = 0x%032h", aes_core_input_r);
        $display("cipher    = 0x%032h", cipher_text);
        $display("expected  = 0x%032h", expected_i);
      end

      previous_cipher_r = cipher_text;
      block_index_r     = block_index_r + 1'b1;
      @(posedge clk_sys);
    end
  endtask

  initial begin
    rst_n              = 1'b0;
    cipher_en          = 1'b0;
    plaintext_block_r  = 128'b0;
    cbc_feedback_r     = 128'b0;
    aes_core_input_r   = 128'b0;
    expected_cipher_r  = 128'b0;
    previous_cipher_r  = 128'b0;
    block_index_r      = 2'd0;
    output_match_r     = 1'b0;
    all_done_r         = 1'b0;

    repeat (4) @(posedge clk_sys);
    rst_n = 1'b1;
    repeat (2) @(posedge clk_sys);

    run_cbc_block(PLAIN_BLOCK_1, EXPECTED_CIPHER_1);
    run_cbc_block(PLAIN_BLOCK_2, EXPECTED_CIPHER_2);

    all_done_r = output_match_r;
    if (output_match_r) begin
      $display("[PASS] AES-128-CBC encryption matched the two-block reference vector.");
      $display("key = 0x%032h", AES_KEY);
      $display("iv  = 0x%032h", AES_IV);
      $display("C1  = 0x%032h", EXPECTED_CIPHER_1);
      $display("C2  = 0x%032h", EXPECTED_CIPHER_2);
    end else begin
      $display("[FAIL] AES-128-CBC final result did not match the reference vector.");
    end

    repeat (8) @(posedge clk_sys);
    $finish;
  end
endmodule
