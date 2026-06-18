quietly set WaveDataset [lindex [dataset list] 0]
if {$WaveDataset eq ""} {
  quietly set WaveDataset "sim"
}
quietly set tb "${WaveDataset}:/test_bench"

quietly catch {view wave}
quietly catch {delete wave *}

add wave -divider {TP-04 Software-Managed Multi-Record Storage - Report View}
add wave -label {clk} $tb/clk
add wave -label {rst} $tb/rst
add wave -label {cycle} -radix decimal $tb/cycle_counter

add wave -divider {1. CPU APB Configuration}
add wave -label {pc} -radix hexadecimal $tb/wf_if_pc
add wave -label {apb_psel} $tb/wf_apb_psel
add wave -label {apb_enable} $tb/wf_apb_penable
add wave -label {apb_write} $tb/wf_apb_pwrite
add wave -label {apb_addr} -radix hexadecimal $tb/wf_apb_paddr
add wave -label {apb_wdata} -radix hexadecimal $tb/wf_apb_pwdata
add wave -label {apb_ready} $tb/wf_apb_pready

add wave -divider {2. DMA Command}
add wave -label {dma_start} $tb/wf_dma_start
add wave -label {dma_src} -radix hexadecimal $tb/wf_dma_src
add wave -label {dma_dst} -radix hexadecimal $tb/wf_dma_dst
add wave -label {dma_len} -radix decimal $tb/wf_dma_len
add wave -label {dma_dir} -radix unsigned $tb/wf_dma_dir
add wave -label {whole_file} $tb/wf_dma_whole_file
add wave -label {compress_only} $tb/wf_dma_compress_only
add wave -label {record_count} -radix decimal $tb/storage_expected_record_count

add wave -divider {3. TX Secure Write}
add wave -label {tx_start_seen} $tb/first_tx_start_seen
add wave -label {tx_state} -radix unsigned $tb/wf_tx_state
add wave -label {tx_busy} $tb/wf_tx_busy
add wave -label {tx_done} $tb/wf_tx_done
add wave -label {tx_error} $tb/wf_tx_error
add wave -label {tx_bytes_done} -radix decimal $tb/wf_tx_bytes_done
add wave -label {tx_ciphertext_bytes} -radix decimal $tb/wf_tx_ciphertext_bytes

add wave -divider {4. RX Secure Readback}
add wave -label {rx_start_seen} $tb/first_rx_start_seen
add wave -label {rx_state} -radix unsigned $tb/wf_rx_state
add wave -label {rx_busy} $tb/wf_rx_busy
add wave -label {rx_done} $tb/wf_rx_done
add wave -label {rx_error} $tb/wf_rx_error
add wave -label {rx_bytes_done} -radix decimal $tb/wf_rx_bytes_done
add wave -label {rx_plaintext_bytes} -radix decimal $tb/wf_rx_plaintext_bytes

add wave -divider {5. Final PASS/FAIL Result}
add wave -label {input1_bytes} -radix decimal $tb/wf_input_len_bytes
add wave -label {result_signature} -radix hexadecimal $tb/wf_result_signature
add wave -label {error_mask} -radix hexadecimal $tb/wf_error_mask
add wave -label {tx_dma_cycles} -radix decimal $tb/wf_perf_tx_dma_cycles
add wave -label {rx_dma_cycles} -radix decimal $tb/wf_perf_rx_dma_cycles

configure wave -namecolwidth 210
configure wave -valuecolwidth 160
configure wave -timelineunits ns
radix -hexadecimal

# Suggested screenshot window:
# Zoom around the DMA start pulses and the final result update.
# Expected final values:
#   record_count      = 2
#   tx_start_seen     = 1
#   rx_start_seen     = 1
#   result_signature  = 0x53544f52
#   error_mask        = 0x00000000
zoom full
