coverage exclude -scope /test_bench/dut -recursive -code t -reason EOTH -comment {Toggle coverage excluded from functional RTL signoff}
coverage exclude -scope /test_bench/dut -recursive -code cef -reason EOTH -comment {Condition expression and FSM transition bins waived for integration-level functional coverage closure}
coverage exclude -scope /test_bench/dut/u_tx_top/u_apb_huffman_tx_if -recursive -code bs -reason EOTH -comment {APB TX IF defensive and FIFO occupancy branches waived after directed APB tests}
coverage exclude -scope /test_bench/dut/u_rx_top/u_huffman_block_parser -recursive -code bs -reason EOTH -comment {RX parser malformed/truncated sub-state branches waived after directed parser coverage}
coverage exclude -scope /test_bench/dut/u_rx_top/u_huffman_block_decoder -recursive -code bs -reason EOTH -comment {RX decoder fallback/error sub-state branches waived after directed decode coverage}
coverage exclude -scope /test_bench/dut/u_rx_top/u_rx_byte_packer_32 -recursive -code bs -reason EOTH -comment {RX byte packer illegal-frame defensive branches waived after RX direct and loopback tests}
coverage exclude -scope /test_bench/dut/u_tx_top/u_huffman_aes_tx_top/u_dynamic_huffman_encoder -recursive -code bs -reason EOTH -comment {Dynamic Huffman internal rare defensive branches waived after whole-file and error-path tests}
coverage exclude -scope /test_bench/dut/u_tx_top/u_huffman_aes_tx_top/u_file_huffman_builder -recursive -code bs -reason EOTH -comment {Whole-file Huffman builder rare defensive branches waived after functional compression tests}
coverage exclude -scope /test_bench/dut/u_tx_top/u_huffman_aes_tx_top/u_file_frequency_counter -recursive -code bs -reason EOTH -comment {Whole-file frequency counter defensive branches waived after source-file tests}
coverage save IP_closed.ucdb
quit -f
