quietly set WaveDataset [lindex [dataset list] 0]
if {$WaveDataset eq ""} {
  quietly set WaveDataset "sim"
}
quietly set tb "${WaveDataset}:/test_bench"

quietly catch {view wave}
quietly catch {delete wave *}

add wave -divider {TP-03 Log-Event Huffman Compression-Only - Report View}
add wave -label {clk} $tb/clk
add wave -label {rst} $tb/rst
add wave -label {cycle} -radix decimal $tb/cycle_counter

add wave -divider {1. CPU Configures TX-Only DMA Through APB}
add wave -label {pc} -radix hexadecimal $tb/wf_if_pc
add wave -label {mmio_sel} $tb/wf_mmio_sel
add wave -label {cpu_stall} $tb/wf_mmio_stall
add wave -label {apb_psel} $tb/wf_apb_psel
add wave -label {apb_penable} $tb/wf_apb_penable
add wave -label {apb_write} $tb/wf_apb_pwrite
add wave -label {apb_addr} -radix hexadecimal $tb/wf_apb_paddr
add wave -label {apb_wdata} -radix hexadecimal $tb/wf_apb_pwdata
add wave -label {apb_rdata} -radix hexadecimal $tb/wf_apb_prdata
add wave -label {apb_ready} $tb/wf_apb_pready
add wave -label {dma_start} $tb/wf_dma_start
add wave -label {dma_src} -radix hexadecimal $tb/wf_dma_src
add wave -label {dma_dst} -radix hexadecimal $tb/wf_dma_dst
add wave -label {dma_len} -radix decimal $tb/wf_dma_len
add wave -label {dma_dir_TX} -radix unsigned $tb/wf_dma_dir
add wave -label {whole_file} $tb/wf_dma_whole_file
add wave -label {compress_only} $tb/wf_dma_compress_only

add wave -divider {2. DMEM Log Bytes and Compressed Output Writes}
add wave -label {tx_busy} $tb/wf_tx_busy
add wave -label {tx_state} -radix unsigned $tb/wf_tx_state
add wave -label {dmem_owner} -radix unsigned $tb/wf_dmem_dma_owner
add wave -label {dmem_en} $tb/wf_dmem_dma_en
add wave -label {dmem_we} -radix hexadecimal $tb/wf_dmem_dma_we
add wave -label {dmem_addr} -radix hexadecimal $tb/wf_dmem_dma_addr
add wave -label {dmem_rdata_log_in} -radix hexadecimal $tb/wf_dmem_dma_rdata
add wave -label {dmem_wdata_compressed} -radix hexadecimal $tb/wf_dmem_dma_wdata

add wave -divider {3. Huffman Stream and 128-bit Transport Packing}
add wave -label {log_word_valid} $tb/wf_tx_apb_word_valid
add wave -label {log_word_ready} $tb/wf_tx_apb_word_ready
add wave -label {log_word} -radix hexadecimal $tb/wf_tx_apb_word_in
add wave -label {encoder_busy} $tb/wf_tx_encoder_busy
add wave -label {encoder_done} $tb/wf_tx_encoder_done
add wave -label {encoder_error} $tb/wf_tx_encoder_error
add wave -label {selected_mode} -radix unsigned $tb/wf_tx_selected_mode
add wave -label {tx_fsm_state} -radix unsigned $tb/wf_tx_accel_fsm_state
add wave -label {packer_busy} $tb/wf_tx_packer_busy
add wave -label {packer_done} $tb/wf_tx_packer_done
add wave -label {packer_error} $tb/wf_tx_packer_error
add wave -label {transport_valid} $tb/wf_tx_transport_valid
add wave -label {transport_valid_bits} -radix decimal $tb/wf_tx_transport_valid_bits
add wave -label {transport_word_128b} -radix hexadecimal $tb/wf_tx_transport_word
add wave -label {output_block_valid_bypass} $tb/wf_tx_cipher_en
add wave -label {output_block_128b_bypass} -radix hexadecimal $tb/wf_tx_aes_block_in

add wave -divider {4. TX-Only PASS/FAIL Result and Counters}
add wave -label {tx_done} $tb/wf_tx_done
add wave -label {tx_error} $tb/wf_tx_error
add wave -label {tx_bytes_done} -radix decimal $tb/wf_tx_bytes_done
add wave -label {signature_TX} -radix hexadecimal $tb/wf_result_signature
add wave -label {error_mask} -radix hexadecimal $tb/wf_error_mask
add wave -label {log_input_bytes} -radix decimal $tb/wf_input_len_bytes
add wave -label {compressed_output_bytes} -radix decimal $tb/wf_tx_ciphertext_bytes
add wave -label {tx_dma_cycles} -radix decimal $tb/wf_perf_tx_dma_cycles
add wave -label {tx_huff_cycles} -radix decimal $tb/wf_perf_tx_huffman_cycles
add wave -label {tx_aes_cycles_should_be_zero} -radix decimal $tb/wf_perf_tx_aes_cycles

configure wave -namecolwidth 250
configure wave -valuecolwidth 190
configure wave -timelineunits ns
radix -hexadecimal

# Useful report screenshot windows for tx_compress_only_input4_cov:
# TX configuration/start: roughly 0 us to 5 us.
# Huffman emission/packing: use a region where transport_valid pulses.
# Final result: use the tx_done/signature_TX/error_mask region.
zoom full
