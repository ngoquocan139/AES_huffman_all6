quietly set WaveDataset [lindex [dataset list] 0]
if {$WaveDataset eq ""} {
  quietly set WaveDataset "sim"
}
quietly set tb "${WaveDataset}:/test_bench"

quietly catch {view wave}
quietly catch {delete wave *}

add wave -divider {TP-04 Multi-Record Secure Storage - Key Evidence}
add wave -label {clk} $tb/clk
add wave -label {rst} $tb/rst
add wave -label {cycle} -radix decimal $tb/cycle_counter

add wave -divider {1. Storage Bundle and Selected File}
add wave -label {record_count_expected} -radix decimal $tb/storage_expected_record_count
add wave -label {input1_spo2_bytes} -radix decimal $tb/input_len_bytes
add wave -label {input2_log_bytes} -radix decimal $tb/input2_len_bytes
add wave -label {input3_ecg_bytes} -radix decimal $tb/input3_len_bytes
quietly catch {add wave -label {selected_file_id} -radix decimal $tb/result_words(14)}
quietly catch {add wave -label {record_count_reported} -radix decimal $tb/result_words(15)}
add wave -label {dma_start_pulse_count} -radix decimal $tb/dma_start_pulse_count

add wave -divider {2. DMA Command}
add wave -label {dma_start} $tb/wf_dma_start
add wave -label {dma_src} -radix hexadecimal $tb/wf_dma_src
add wave -label {dma_dst} -radix hexadecimal $tb/wf_dma_dst
add wave -label {dma_len} -radix decimal $tb/wf_dma_len
add wave -label {dma_dir} -radix unsigned $tb/wf_dma_dir
add wave -label {whole_file} $tb/wf_dma_whole_file

add wave -divider {3. TX Secure Write}
add wave -label {tx_busy} $tb/wf_tx_busy
add wave -label {tx_done} $tb/wf_tx_done
add wave -label {tx_error} $tb/wf_tx_error
add wave -label {tx_bytes_done} -radix decimal $tb/wf_tx_bytes_done
add wave -label {tx_ciphertext_bytes} -radix decimal $tb/wf_tx_ciphertext_bytes
quietly catch {add wave -label {tx1_ciphertext_bytes_reported} -radix decimal $tb/result_words(5)}
quietly catch {add wave -label {tx2_ciphertext_bytes_reported} -radix decimal $tb/result_words(12)}

add wave -divider {4. RX Secure Readback}
add wave -label {rx_busy} $tb/wf_rx_busy
add wave -label {rx_done} $tb/wf_rx_done
add wave -label {rx_error} $tb/wf_rx_error
add wave -label {rx_bytes_done} -radix decimal $tb/wf_rx_bytes_done
add wave -label {rx_plaintext_bytes} -radix decimal $tb/wf_rx_plaintext_bytes
quietly catch {add wave -label {selected_rx_bytes_reported} -radix decimal $tb/result_words(9)}
add wave -label {readback_mismatch_count} -radix decimal $tb/storage_readback_mismatch_count

add wave -divider {5. Final PASS/FAIL Result}
add wave -label {result_signature} -radix hexadecimal $tb/wf_result_signature
add wave -label {error_mask} -radix hexadecimal $tb/wf_error_mask
add wave -label {tx_dma_cycles} -radix decimal $tb/wf_perf_tx_dma_cycles
add wave -label {rx_dma_cycles} -radix decimal $tb/wf_perf_rx_dma_cycles

configure wave -namecolwidth 210
configure wave -valuecolwidth 160
configure wave -timelineunits ns
radix -hexadecimal

# Suggested screenshot window:
# Zoom around the full run or around each selected_file_id change.
# Expected final values:
#   record_count_expected      = 3
#   selected_file_id           = 1, then 2, then 3 during readback checks
#   dma_start_pulse_count      = 6
#   readback_mismatch_count    = 0
#   result_signature           = 0x53544f52
#   error_mask                 = 0x00000000
zoom full
