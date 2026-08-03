quietly set WaveDataset [lindex [dataset list] 0]
if {$WaveDataset eq ""} {
  quietly set WaveDataset "sim"
}
quietly set tb "${WaveDataset}:/test_bench"

quietly catch {view wave}
quietly catch {delete wave *}

add wave -divider {AES-128 ECB/Core Block Encryption: Input, 10 Rounds, Output}
add wave -label {clk} $tb/clk_sys
add wave -label {rst_n} $tb/rst_n
add wave -label {cipher_en_start_pulse} $tb/cipher_en
add wave -label {cipher_ready_done} $tb/cipher_ready
add wave -label {round_num_0_to_10} -radix unsigned $tb/wf_round_num
add wave -label {rkey_en_round_active} $tb/wf_rkey_en

add wave -divider {AES Input and Key}
add wave -label {plain_text_input} -radix hexadecimal $tb/plain_text
add wave -label {cipher_key_input} -radix hexadecimal $tb/cipher_key
add wave -label {round_key} -radix hexadecimal $tb/wf_round_key

add wave -divider {Round Datapath Evidence}
add wave -label {state_register_after_round} -radix hexadecimal $tb/wf_state_reg
add wave -label {after_subbytes} -radix hexadecimal $tb/wf_after_subbytes
add wave -label {after_shiftrows} -radix hexadecimal $tb/wf_after_shiftrows
add wave -label {after_mixcolumns} -radix hexadecimal $tb/wf_after_mixcols
add wave -label {after_addroundkey} -radix hexadecimal $tb/wf_after_addkey

add wave -divider {AES Output Check}
add wave -label {cipher_text_output} -radix hexadecimal $tb/cipher_text
add wave -label {expected_cipher_text} -radix hexadecimal $tb/wf_expected_cipher
add wave -label {output_match} $tb/wf_output_match

configure wave -namecolwidth 240
configure wave -valuecolwidth 300
configure wave -timelineunits ns
radix -hexadecimal
zoom full
