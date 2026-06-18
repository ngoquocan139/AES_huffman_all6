quietly set WaveDataset [lindex [dataset list] 0]
if {$WaveDataset eq ""} {
  quietly set WaveDataset "sim"
}
quietly set tb "${WaveDataset}:/test_bench"

quietly catch {view wave}
quietly catch {delete wave *}

add wave -divider {TP-01 SpO2 Secure-Storage Loopback - Report View}
add wave -label {clk} $tb/clk
add wave -label {rst} $tb/rst
add wave -label {cycle} -radix decimal $tb/cycle_counter

add wave -divider {1. CPU Configures DMA Through APB}
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
add wave -label {dma_dir} -radix unsigned $tb/wf_dma_dir
add wave -label {whole_file} $tb/wf_dma_whole_file
add wave -label {compress_only} $tb/wf_dma_compress_only

add wave -divider {2. TX Path: DMEM Plaintext to Huffman/AES to Ciphertext DMEM}
add wave -label {tx_busy} $tb/wf_tx_busy
add wave -label {tx_state} -radix unsigned $tb/wf_tx_state
add wave -label {tx_dmem_addr} -radix hexadecimal $tb/wf_dmem_dma_addr
add wave -label {tx_dmem_we} -radix hexadecimal $tb/wf_dmem_dma_we
add wave -label {tx_dmem_rdata} -radix hexadecimal $tb/wf_dmem_dma_rdata
add wave -label {tx_dmem_wdata} -radix hexadecimal $tb/wf_dmem_dma_wdata
add wave -label {plain_word_valid} $tb/wf_tx_apb_word_valid
add wave -label {plain_word_ready} $tb/wf_tx_apb_word_ready
add wave -label {plain_word} -radix hexadecimal $tb/wf_tx_apb_word_in
add wave -label {huff_transport_valid} $tb/wf_tx_transport_valid
add wave -label {huff_transport_bits} -radix decimal $tb/wf_tx_transport_valid_bits
add wave -label {huff_transport_word} -radix hexadecimal $tb/wf_tx_transport_word
add wave -label {aes_cipher_en} $tb/wf_tx_cipher_en
add wave -label {aes_block_in} -radix hexadecimal $tb/wf_tx_aes_block_in
add wave -label {tx_done} $tb/wf_tx_done
add wave -label {tx_error} $tb/wf_tx_error
add wave -label {tx_bytes_done} -radix decimal $tb/wf_tx_bytes_done

add wave -divider {3. RX Path: Ciphertext DMEM to AES/Huffman to Restored Plaintext}
add wave -label {rx_busy} $tb/wf_rx_busy
add wave -label {rx_state} -radix unsigned $tb/wf_rx_state
add wave -label {cipher_valid} $tb/wf_rx_ciphertext_valid
add wave -label {cipher_ready} $tb/wf_rx_ciphertext_ready
add wave -label {cipher_word} -radix hexadecimal $tb/wf_rx_ciphertext_word
add wave -label {rx_aes_ready} $tb/wf_rx_aes_ready
add wave -label {rx_transport_valid} $tb/wf_rx_transport_valid
add wave -label {rx_transport_word} -radix hexadecimal $tb/wf_rx_transport_word
add wave -label {decoder_busy} $tb/wf_rx_decoder_busy
add wave -label {plain_out_valid} $tb/wf_rx_word_valid
add wave -label {plain_out_word} -radix hexadecimal $tb/wf_rx_word_data
add wave -label {plain_out_bytes} -radix unsigned $tb/wf_rx_word_valid_bytes
add wave -label {last_block} $tb/wf_rx_word_last_in_block
add wave -label {last_frame} $tb/wf_rx_word_last_in_frame
add wave -label {rx_done} $tb/wf_rx_done
add wave -label {rx_error} $tb/wf_rx_error
add wave -label {rx_bytes_done} -radix decimal $tb/wf_rx_bytes_done

add wave -divider {4. PASS/FAIL Result and Size Counters}
add wave -label {signature_DMA} -radix hexadecimal $tb/wf_result_signature
add wave -label {error_mask} -radix hexadecimal $tb/wf_error_mask
add wave -label {input_bytes} -radix decimal $tb/wf_input_len_bytes
add wave -label {cipher_bytes} -radix decimal $tb/wf_tx_ciphertext_bytes
add wave -label {restored_bytes} -radix decimal $tb/wf_rx_plaintext_bytes
add wave -label {tx_dma_cycles} -radix decimal $tb/wf_perf_tx_dma_cycles
add wave -label {rx_dma_cycles} -radix decimal $tb/wf_perf_rx_dma_cycles
add wave -label {tx_huff_cycles} -radix decimal $tb/wf_perf_tx_huffman_cycles
add wave -label {tx_aes_cycles} -radix decimal $tb/wf_perf_tx_aes_cycles
add wave -label {rx_huff_cycles} -radix decimal $tb/wf_perf_rx_huffman_cycles
add wave -label {rx_aes_cycles} -radix decimal $tb/wf_perf_rx_aes_cycles

configure wave -namecolwidth 210
configure wave -valuecolwidth 180
configure wave -timelineunits ns
radix -hexadecimal

# Useful report screenshot windows for dma_compress_aes_input1:
# TX configuration/start: roughly 0 us to 5 us.
# TX completion: roughly 320 us to 330 us.
# RX completion and final PASS counters: roughly 470 us to 612 us.
zoom full
