quietly set WaveDataset [lindex [dataset list] 0]
if {$WaveDataset eq ""} {
  quietly set WaveDataset "sim"
}
quietly set tb "${WaveDataset}:/test_bench"

quietly catch {view wave}
quietly catch {delete wave *}

add wave -divider {AES-128-CBC: Input XOR Feedback, 10 AES Rounds, Cipher Output}
add wave -label {clk} $tb/clk_sys
add wave -label {rst_n} $tb/rst_n
add wave -label {cbc_block_index} -radix unsigned $tb/wf_cbc_block_index
add wave -label {cipher_en_start_pulse} $tb/cipher_en
add wave -label {cipher_ready_done} $tb/cipher_ready
add wave -label {round_num_0_to_10} -radix unsigned $tb/wf_round_num
add wave -label {rkey_en_round_active} $tb/wf_rkey_en

add wave -divider {CBC Input Selection}
add wave -label {plaintext_block_Pi} -radix hexadecimal $tb/wf_plaintext_block
add wave -label {iv_for_first_block} -radix hexadecimal $tb/wf_iv
add wave -label {cbc_feedback_IV_or_Cprev} -radix hexadecimal $tb/wf_cbc_feedback
add wave -label {aes_core_input_Pi_xor_feedback} -radix hexadecimal $tb/wf_aes_core_input

add wave -divider {AES Round Datapath}
add wave -label {round_key} -radix hexadecimal $tb/wf_round_key
add wave -label {state_register_after_round} -radix hexadecimal $tb/wf_state_reg
add wave -label {after_subbytes} -radix hexadecimal $tb/wf_after_subbytes
add wave -label {after_shiftrows} -radix hexadecimal $tb/wf_after_shiftrows
add wave -label {after_mixcolumns} -radix hexadecimal $tb/wf_after_mixcolumns
add wave -label {after_addroundkey} -radix hexadecimal $tb/wf_after_addroundkey

add wave -divider {CBC Ciphertext Output}
add wave -label {cipher_output_Ci} -radix hexadecimal $tb/wf_cipher_output
add wave -label {expected_cipher_Ci} -radix hexadecimal $tb/wf_expected_cipher
add wave -label {block_output_match} $tb/wf_output_match
add wave -label {all_done} $tb/wf_all_done

configure wave -namecolwidth 270
configure wave -valuecolwidth 330
configure wave -timelineunits ns
radix -hexadecimal
zoom full
