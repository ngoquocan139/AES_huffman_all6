# Spec Flow Index

## 1. Read This First

The current source of truth is:

| Priority | Document | Purpose |
|---:|---|---|
| 1 | [00_current_system_spec.md](./00_current_system_spec.md) | Complete current SoC architecture, modes, memory map, TX/RX flow, verification, FPGA, paper comparison |
| 2 | [report_presentation_guide.md](./report_presentation_guide.md) | What to present to the advisor |
| 3 | [paper_comparison_huffman_aes_cbc.md](./paper_comparison_huffman_aes_cbc.md) | MIT-BIH comparison against the referenced paper |
| 4 | [soc_4_5_end_to_end_report.md](./soc_4_5_end_to_end_report.md) | Main SoC end-to-end testcase result |
| 5 | [coverage_regression_report.md](./coverage_regression_report.md) | Coverage and regression result |
| 6 | [soc_usage_and_fpga_guide.md](./soc_usage_and_fpga_guide.md) | Day-to-day commands and FPGA preparation |

Policy for the current report:

- Use MIT-BIH already-preprocessed `.bin` inputs for paper comparison.
- Present preprocessing as external to the RTL.
- Treat `00_current_system_spec.md` as the top-level spec and module specs as
  technical appendices.

## 2. Current Baseline

| Item | Value |
|---|---|
| Simulation top | `test_bench` |
| Active testcase source | `sim/pat.list` |
| Coverage runner | `cd sim && ./run.csh cov` |
| Latest pass/fail | `34/34` PASS |
| Raw DUT full coverage | `93.52%` |
| Raw DUT branches/statements | `94.22% / 96.33%` |
| Closed DUT coverage | `95.90%` |
| Main secure-storage mode | `MODE=0x9`, whole-file Huffman + AES-128-CBC |
| Main RX mode | `MODE=0x2`, AES-CBC decrypt + Huffman decode |
| MIT-BIH comparison | external preprocessed input, `32.76%` average final storage ratio |
| FPGA strategy | split TX-only and RX-only bitstreams at 50 MHz |

## 3. Architecture Reading Path

Read in this order when explaining the full system:

| Order | Spec | Topic |
|---:|---|---|
| 1 | [00_current_system_spec.md](./00_current_system_spec.md) | Full SoC overview |
| 2 | [memory_map_dma_software_contract.md](./memory_map_dma_software_contract.md) | CPU-visible memory map and DMA software contract |
| 3 | [bram_port_usage_spec.md](./bram_port_usage_spec.md) | IMEM/DMEM BRAM ownership |
| 4 | [cpu_dma_stall_policy_spec.md](./cpu_dma_stall_policy_spec.md) | CPU stall and DMA busy behavior |
| 5 | [cpu_mmio_to_apb_bridge_spec.md](./cpu_mmio_to_apb_bridge_spec.md) | CPU MMIO to APB transaction semantics |
| 6 | [dma_regfile_spec.md](./dma_regfile_spec.md) | DMA registers and mode decode |
| 7 | [iv_generation_and_cbc_contract_spec.md](./iv_generation_and_cbc_contract_spec.md) | IV and AES-CBC contract |
| 8 | [dma_riscv_instruction_programming_spec.md](./dma_riscv_instruction_programming_spec.md) | RV32I instructions used by control software |

## 4. TX Reading Path

| Order | Spec | Topic |
|---:|---|---|
| 1 | [tx_path_end_to_end_spec.md](./tx_path_end_to_end_spec.md) | TX end-to-end data/control flow |
| 2 | [dma_tx_engine_spec.md](./dma_tx_engine_spec.md) | TX DMA data mover |
| 3 | [apb_huffman_aes_tx_top_spec.md](./apb_huffman_aes_tx_top_spec.md) | TX APB wrapper, Huffman, AES/bypass |
| 4 | [dynamic_huffman_encoder_spec.md](./dynamic_huffman_encoder_spec.md) | Whole-file dynamic Huffman encoder |
| 5 | [bit_packer_128_spec.md](./bit_packer_128_spec.md) | 128-bit transport packing |
| 6 | [14_dynamic_whole_file_huffman_spec.md](./14_dynamic_whole_file_huffman_spec.md) | Whole-file Huffman policy |

## 5. RX Reading Path

| Order | Spec | Topic |
|---:|---|---|
| 1 | [rx_path_end_to_end_spec.md](./rx_path_end_to_end_spec.md) | RX end-to-end data/control flow |
| 2 | [dma_rx_engine_spec.md](./dma_rx_engine_spec.md) | RX DMA data mover |
| 3 | [apb_huffman_aes_rx_top_spec.md](./apb_huffman_aes_rx_top_spec.md) | RX wrapper and AES/decode pipeline |
| 4 | [bit_depacker_128_spec.md](./bit_depacker_128_spec.md) | 128-bit transport depacking |
| 5 | [huffman_block_parser_spec.md](./huffman_block_parser_spec.md) | Huffman frame parser |
| 6 | [huffman_block_decoder_spec.md](./huffman_block_decoder_spec.md) | Huffman decode table and fallback |
| 7 | [rx_byte_packer_32_spec.md](./rx_byte_packer_32_spec.md) | RX byte-to-word packing |
| 8 | [apb_huffman_rx_if_spec.md](./apb_huffman_rx_if_spec.md) | RX APB status/output interface |

## 6. Verification And Report Path

| Spec | Use |
|---|---|
| [coverage_test_plan_spec.md](./coverage_test_plan_spec.md) | Testcase plan and coverage intent |
| [coverage_regression_report.md](./coverage_regression_report.md) | Latest coverage result |
| [soc_4_5_end_to_end_report.md](./soc_4_5_end_to_end_report.md) | Main SoC end-to-end evidence |
| [paper_comparison_huffman_aes_cbc.md](./paper_comparison_huffman_aes_cbc.md) | Comparison with paper |
| [29_defense_qa_code_focus_spec.md](./29_defense_qa_code_focus_spec.md) | Oral defense Q&A |
| [c_files_explained.md](./c_files_explained.md) | What each C program does |

## 7. FPGA And Workflow Path

| Spec | Use |
|---|---|
| [soc_usage_and_fpga_guide.md](./soc_usage_and_fpga_guide.md) | Commands, input selection, FPGA preparation |
| [fpga_uart_dmem_loader_spec.md](./fpga_uart_dmem_loader_spec.md) | UART DMEM loader protocol |
| [github_sync_and_self_hosted_runner_usage_spec.md](./github_sync_and_self_hosted_runner_usage_spec.md) | GitHub/self-hosted runner workflow |

## 8. Main Commands

Normal SoC loopback:

```bash
cd sim
make compile C_SRC=test_mmio_dma.c
make drc
make all TESTNAME=dma_compress_aes_input1 RUN_ARGS="+CASE_NAME=dma_compress_aes_input1 +INPUT_FILE=input1.txt"
```

MIT-BIH preprocessed comparison:

```bash
cd sim
make compile C_SRC=test_mmio_dma.c
make all TESTNAME=dma_mitdb_100_delta2_var_e2e \
  RUN_ARGS="+CASE_NAME=dma_mitdb_100_delta2_var_e2e +INPUT_FILE=mitdb_100_mlii_10s_delta2_var.bin +INPUT_BINARY"
```

Coverage:

```bash
cd sim
./run.csh cov
./report.csh
```

FPGA implementation:

```bash
cd sim
make vivado_impl_tx
make vivado_impl_rx
```

## 9. Archived Or Non-Report Branches

Do not use these as the main report story:

| Branch/topic | Current status |
|---|---|
| Full TX+RX monolithic bitstream | Analysis only; split bitstreams are current practical flow |
| Interrupt/trap DMA completion | Not implemented; polling is active |
| Production entropy/secret IV generation | Not implemented; current IV is demo software-generated |
