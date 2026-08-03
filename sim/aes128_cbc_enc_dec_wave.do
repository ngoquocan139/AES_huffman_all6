quietly set WaveDataset [lindex [dataset list] 0]
if {$WaveDataset eq ""} {
  quietly set WaveDataset "sim"
}
quietly set tb "${WaveDataset}:/test_bench"

quietly catch {view wave}
quietly catch {delete wave *}

add wave -divider {AES-128-CBC Combined Encrypt + Decrypt}
add wave -label {clk} $tb/clk_sys
add wave -label {rst_n} $tb/rst_n
add wave -label {phase: 0 idle, 1 enc, 2 dec, 3 done} -radix unsigned $tb/wf_phase
add wave -label {key} -radix hexadecimal $tb/wf_key
add wave -label {iv} -radix hexadecimal $tb/wf_iv
add wave -label {round_key_10_from_encrypt_key_schedule} -radix hexadecimal $tb/wf_round_key_10
add wave -label {all_done} $tb/wf_all_done

add wave -divider {1. CBC Encrypt: C_i = AES(P_i XOR IV/C_prev)}
add wave -label {enc_block_index} -radix unsigned $tb/wf_enc_block_index
add wave -label {enc_start_cipher_en} $tb/cipher_en
add wave -label {enc_ready_done} $tb/enc_cipher_ready_w
add wave -label {enc_round_num_0_to_10} -radix unsigned $tb/wf_enc_round_num
add wave -label {enc_rkey_en_round_active} $tb/wf_enc_rkey_en
add wave -label {plaintext_Pi} -radix hexadecimal $tb/wf_enc_plaintext_Pi
add wave -label {cbc_feedback_IV_or_Cprev} -radix hexadecimal $tb/wf_enc_cbc_feedback
add wave -label {aes_input_Pi_xor_feedback} -radix hexadecimal $tb/wf_enc_aes_input
add wave -label {enc_round_key} -radix hexadecimal $tb/wf_enc_round_key
add wave -label {enc_after_subbytes} -radix hexadecimal $tb/wf_enc_after_subbytes
add wave -label {enc_after_shiftrows} -radix hexadecimal $tb/wf_enc_after_shiftrows
add wave -label {enc_after_mixcolumns} -radix hexadecimal $tb/wf_enc_after_mixcolumns
add wave -label {enc_after_addroundkey} -radix hexadecimal $tb/wf_enc_after_addroundkey
add wave -label {cipher_output_Ci} -radix hexadecimal $tb/wf_enc_cipher_Ci
add wave -label {expected_cipher_Ci} -radix hexadecimal $tb/wf_enc_expected_Ci
add wave -label {enc_block_match} $tb/wf_enc_match
add wave -label {enc_all_match} $tb/wf_enc_all_match

add wave -divider {2. CBC Decrypt: P_i = AES_INV(C_i) XOR IV/C_prev}
add wave -label {dec_block_index} -radix unsigned $tb/wf_dec_block_index
add wave -label {dec_start_decipher_en} $tb/decipher_en
add wave -label {dec_ready_done} $tb/dec_decipher_ready_w
add wave -label {dec_round_num_0_to_10} -radix unsigned $tb/wf_dec_round_num
add wave -label {dec_rkey_en_round_active} $tb/wf_dec_rkey_en
add wave -label {ciphertext_Ci} -radix hexadecimal $tb/wf_dec_cipher_Ci
add wave -label {cbc_feedback_IV_or_Cprev} -radix hexadecimal $tb/wf_dec_cbc_feedback
add wave -label {dec_round_key_inv} -radix hexadecimal $tb/wf_dec_round_key_inv
add wave -label {dec_after_invshiftrows} -radix hexadecimal $tb/wf_dec_after_invshift
add wave -label {dec_after_invsubbytes} -radix hexadecimal $tb/wf_dec_after_invsub
add wave -label {dec_after_invmixcolumns} -radix hexadecimal $tb/wf_dec_after_invmix
add wave -label {dec_after_addroundkey} -radix hexadecimal $tb/wf_dec_after_addroundkey
add wave -label {aes_inverse_output_DK_Ci} -radix hexadecimal $tb/wf_dec_aes_inverse
add wave -label {recovered_plaintext_Pi} -radix hexadecimal $tb/wf_dec_recovered_Pi
add wave -label {expected_plaintext_Pi} -radix hexadecimal $tb/wf_dec_expected_Pi
add wave -label {dec_block_match} $tb/wf_dec_match
add wave -label {dec_all_match} $tb/wf_dec_all_match

configure wave -namecolwidth 330
configure wave -valuecolwidth 340
configure wave -timelineunits ns
radix -hexadecimal
zoom full
