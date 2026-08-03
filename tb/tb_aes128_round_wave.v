`timescale 1ns / 1ps

module test_bench;
  localparam [127:0] AES_KEY =
      128'h000102030405060708090a0b0c0d0e0f;
  localparam [127:0] AES_PLAIN =
      128'h00112233445566778899aabbccddeeff;
  localparam [127:0] AES_EXPECTED_CIPHER =
      128'h69c4e0d86a7b0430d8cdb78070b4c55a;

  reg          clk_sys;
  reg          rst_n;
  reg  [127:0] cipher_key;
  reg  [127:0] plain_text;
  reg          cipher_en;
  wire [127:0] cipher_text;
  wire         cipher_ready;
  wire [127:0] cipher_key10;

  reg          done_seen;

  aes128_cipher_top dut (
    .clk_sys      (clk_sys),
    .rst_n        (rst_n),
    .cipher_key   (cipher_key),
    .plain_text   (plain_text),
    .cipher_en    (cipher_en),
    .cipher_text  (cipher_text),
    .cipher_ready (cipher_ready),
    .cipher_key10 (cipher_key10)
  );

  // Short waveform aliases.
  wire [3:0]   wf_round_num       = dut.round_num;
  wire         wf_rkey_en         = dut.rkey_en;
  wire [127:0] wf_round_key       = dut.round_key_out;
  wire [127:0] wf_state_reg       = dut.u_aes128_cipher_core.cipherText_reg;
  wire [127:0] wf_after_subbytes  = dut.u_aes128_cipher_core.after_subBytes;
  wire [127:0] wf_after_shiftrows = dut.u_aes128_cipher_core.after_shiftRows;
  wire [127:0] wf_after_mixcols   = dut.u_aes128_cipher_core.after_mixColumns;
  wire [127:0] wf_after_addkey    = dut.u_aes128_cipher_core.after_addRoundkey;
  wire [127:0] wf_expected_cipher = AES_EXPECTED_CIPHER;
  wire         wf_output_match    = done_seen && (cipher_text == AES_EXPECTED_CIPHER);

  initial begin
    clk_sys = 1'b0;
    forever #5 clk_sys = ~clk_sys;
  end

  initial begin
    $dumpfile("aes128_round_wave.vcd");
    $dumpvars(0, test_bench);
  end

  initial begin
    rst_n      = 1'b0;
    cipher_key = AES_KEY;
    plain_text = AES_PLAIN;
    cipher_en  = 1'b0;
    done_seen  = 1'b0;

    repeat (4) @(posedge clk_sys);
    rst_n = 1'b1;

    repeat (2) @(posedge clk_sys);
    cipher_en = 1'b1;
    @(posedge clk_sys);
    cipher_en = 1'b0;

    wait (cipher_ready == 1'b0);
    wait (cipher_ready == 1'b1);
    @(posedge clk_sys);
    done_seen = 1'b1;

    if (cipher_text == AES_EXPECTED_CIPHER) begin
      $display("[PASS] AES-128 ECB/core block encryption matched expected NIST vector.");
      $display("plain    = 0x%032h", AES_PLAIN);
      $display("key      = 0x%032h", AES_KEY);
      $display("cipher   = 0x%032h", cipher_text);
      $display("expected = 0x%032h", AES_EXPECTED_CIPHER);
    end else begin
      $display("[FAIL] AES-128 ECB/core block encryption output mismatch.");
      $display("plain    = 0x%032h", AES_PLAIN);
      $display("key      = 0x%032h", AES_KEY);
      $display("cipher   = 0x%032h", cipher_text);
      $display("expected = 0x%032h", AES_EXPECTED_CIPHER);
    end

    repeat (8) @(posedge clk_sys);
    $finish;
  end
endmodule
