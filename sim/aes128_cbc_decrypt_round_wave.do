quietly set WaveDataset [lindex [dataset list] 0]
if {$WaveDataset eq ""} {
  quietly set WaveDataset "sim"
}
quietly set tb "${WaveDataset}:/test_bench"

quietly catch {view wave}
quietly catch {delete wave *}

add wave -divider {AES-128-CBC Decrypt: AES Inverse + CBC XOR}
add wave -label {clk} $tb/clk_sys
add wave -label {rst_n} $tb/rst_n
add wave -label {cbc_block_index} -radix unsigned $tb/wf_cbc_block_index
add wave -label {decipher_en_start_pulse} $tb/decipher_en
add wave -label {decipher_ready_done} $tb/decipher_ready
add wave -label {round_num_0_to_10} -radix unsigned $tb/wf_round_num
add wave -label {rkey_en_round_active} $tb/wf_rkey_en

add wave -divider {CBC Decrypt Input}
add wave -label {ciphertext_block_Ci} -radix hexadecimal $tb/wf_ciphertext_block_Ci
add wave -label {iv_for_first_block} -radix hexadecimal $tb/wf_iv
add wave -label {cbc_feedback_IV_or_Cprev} -radix hexadecimal $tb/wf_cbc_feedback
add wave -label {round_key_10} -radix hexadecimal $tb/wf_round_key_10

add wave -divider {AES Inverse Round Datapath}
add wave -label {round_key_inv} -radix hexadecimal $tb/wf_round_key_inv
add wave -label {state_register_after_inv_round} -radix hexadecimal $tb/wf_state_reg
add wave -label {after_invshiftrows} -radix hexadecimal $tb/wf_after_invshiftrows
add wave -label {after_invsubbytes} -radix hexadecimal $tb/wf_after_invsubbytes
add wave -label {after_invmixcolumns} -radix hexadecimal $tb/wf_after_invmixcolumns
add wave -label {after_addroundkey} -radix hexadecimal $tb/wf_after_addroundkey

add wave -divider {CBC Plaintext Recovery}
add wave -label {aes_inverse_output_DK_Ci} -radix hexadecimal $tb/wf_aes_inverse_output
add wave -label {recovered_plaintext_DK_Ci_xor_feedback} -radix hexadecimal $tb/wf_recovered_plaintext
add wave -label {expected_plaintext_Pi} -radix hexadecimal $tb/wf_expected_plaintext
add wave -label {block_output_match} $tb/wf_output_match
add wave -label {all_done} $tb/wf_all_done

configure wave -namecolwidth 300
configure wave -valuecolwidth 330
configure wave -timelineunits ns
radix -hexadecimal
zoom full
