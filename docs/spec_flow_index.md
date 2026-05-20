# Spec Flow Index

## 1. Read This First

The current source of truth is:

| Priority | Document | Purpose |
|---:|---|---|
| 1 | [00_current_system_spec.md](./00_current_system_spec.md) | Complete current SoC architecture, secure-storage firmware API, modes, memory map, TX/RX flow, verification, FPGA status |
| 2 | [memory_map_dma_software_contract.md](./memory_map_dma_software_contract.md) | CPU-visible memory map, DMA MMIO contract, metadata layout, polling rules |
| 3 | [iv_generation_and_cbc_contract_spec.md](./iv_generation_and_cbc_contract_spec.md) | Current firmware IV generation and AES-CBC restore contract |
| 4 | [paper_comparison_huffman_aes_cbc.md](./paper_comparison_huffman_aes_cbc.md) | MIT-BIH comparison against the referenced paper |
| 5 | [soc_4_5_end_to_end_report.md](./soc_4_5_end_to_end_report.md) | Main SoC end-to-end testcase evidence |
| 6 | [coverage_regression_report.md](./coverage_regression_report.md) | Historical coverage and regression result |
| 7 | [soc_usage_and_fpga_guide.md](./soc_usage_and_fpga_guide.md) | Day-to-day commands and FPGA preparation |

Policy for the current report:

- Present the system as an RV32I secure-storage SoC.
- Present Huffman + AES as RTL accelerators controlled by RV32I firmware.
- Present metadata and IV/nonce management as firmware responsibilities.
- Use MIT-BIH already-preprocessed `.bin` inputs for paper comparison.
- Present ECG preprocessing as external to the RTL.
- Treat `00_current_system_spec.md` as the top-level spec and module specs as
  technical appendices.

## 2. Current Baseline

| Item | Value |
|---|---|
| Simulation top | `test_bench` |
| Active secure-storage firmware API | `testcase/secure_storage_fw.h` |
| Active secure-storage testcase | `testcase/test_mmio_dma_storage_table.c` |
| Latest focused secure-storage result | `dma_storage_table_input1_then_input3`: `PASS=22`, `FAIL=0` |
| Main secure-storage mode | `MODE=0x9`, whole-file Huffman + AES-128-CBC |
| Main RX mode | `MODE=0x2`, AES-CBC decrypt + Huffman decode |
| Metadata table | DMEM records at `0x0000_0100`, 2 slots, `0x40` bytes per slot |
| IV counter | DMEM word at `0x0000_01F0`, seed `0x31415926` |
| MIT-BIH comparison | External preprocessed input, `32.76%` average final storage ratio |
| FPGA strategy | Area-optimized project-mode implementation at 50 MHz |
| TX-only FPGA status | Routed, WNS `+1.277 ns`, LUTs `11933`, regs `5469`, slices `3979`, control sets `208` |
| Full FPGA demo SoC status | Routed, WNS `+0.811 ns`, LUTs `28379`, regs `18898`, slices `10165`, control sets `778` |
| Legacy RX-only FPGA status | Routed, WNS `+0.341 ns`, LUTs `22730`, regs `27658`, control sets `917` |
| Historical full regression | `34/34` PASS before secure-storage API refactor |
| Historical coverage | Raw DUT `93.52%`, closed DUT `95.90%` |

The full regression should be rerun if the final report needs a fresh
post-secure-API full-regression number. The latest focused storage testcase is
the current API-level evidence.

## 3. Architecture Reading Path

Read in this order when explaining the full system:

| Order | Spec | Topic |
|---:|---|---|
| 1 | [00_current_system_spec.md](./00_current_system_spec.md) | Full current SoC overview |
| 2 | [memory_map_dma_software_contract.md](./memory_map_dma_software_contract.md) | DMEM layout, DMA registers, secure metadata contract |
| 3 | [iv_generation_and_cbc_contract_spec.md](./iv_generation_and_cbc_contract_spec.md) | IV generation, metadata storage, CBC word order |
| 4 | [bram_port_usage_spec.md](./bram_port_usage_spec.md) | IMEM/DMEM BRAM ownership |
| 5 | [cpu_dma_stall_policy_spec.md](./cpu_dma_stall_policy_spec.md) | CPU stall and DMA busy behavior |
| 6 | [cpu_mmio_to_apb_bridge_spec.md](./cpu_mmio_to_apb_bridge_spec.md) | CPU MMIO to APB transaction semantics |
| 7 | [dma_regfile_spec.md](./dma_regfile_spec.md) | DMA registers and mode decode |
| 8 | [dma_riscv_instruction_programming_spec.md](./dma_riscv_instruction_programming_spec.md) | RV32I instructions used by control software |

## 4. Secure Storage Firmware Reading Path

| Order | File/spec | Topic |
|---:|---|---|
| 1 | `testcase/secure_storage_fw.h` | Current API implementation: init/write/read/delete |
| 2 | `testcase/test_mmio_dma_storage_table.c` | Current storage-table testcase and result-word checks |
| 3 | [memory_map_dma_software_contract.md](./memory_map_dma_software_contract.md) | Metadata record fields and DMEM slot addresses |
| 4 | [iv_generation_and_cbc_contract_spec.md](./iv_generation_and_cbc_contract_spec.md) | IV counter, IV formula, IV restore before RX |
| 5 | [c_files_explained.md](./c_files_explained.md) | What each C program does |

## 5. TX Reading Path

| Order | Spec | Topic |
|---:|---|---|
| 1 | [tx_path_end_to_end_spec.md](./tx_path_end_to_end_spec.md) | TX end-to-end data/control flow |
| 2 | [dma_tx_engine_spec.md](./dma_tx_engine_spec.md) | TX DMA data mover |
| 3 | [apb_huffman_aes_tx_top_spec.md](./apb_huffman_aes_tx_top_spec.md) | TX APB wrapper, Huffman, AES/bypass |
| 4 | [dynamic_huffman_encoder_spec.md](./dynamic_huffman_encoder_spec.md) | Whole-file dynamic Huffman encoder |
| 5 | [bit_packer_128_spec.md](./bit_packer_128_spec.md) | 128-bit transport packing |
| 6 | [14_dynamic_whole_file_huffman_spec.md](./14_dynamic_whole_file_huffman_spec.md) | Whole-file Huffman policy |

## 6. RX Reading Path

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

## 7. Verification And Report Path

| Spec | Use |
|---|---|
| [coverage_test_plan_spec.md](./coverage_test_plan_spec.md) | Testcase plan and coverage intent |
| [coverage_regression_report.md](./coverage_regression_report.md) | Historical coverage result |
| [soc_4_5_end_to_end_report.md](./soc_4_5_end_to_end_report.md) | Main SoC end-to-end evidence |
| [paper_comparison_huffman_aes_cbc.md](./paper_comparison_huffman_aes_cbc.md) | Comparison with paper |
| [29_defense_qa_code_focus_spec.md](./29_defense_qa_code_focus_spec.md) | Oral defense Q&A |
| [input1_instruction_wavedrom.md](./input1_instruction_wavedrom.md) | Input1 instruction/MMIO waveform trace; currently has unresolved add/add conflict |

## 8. FPGA And Workflow Path

| Spec | Use |
|---|---|
| [soc_usage_and_fpga_guide.md](./soc_usage_and_fpga_guide.md) | Commands, input selection, FPGA preparation |
| [fpga_uart_dmem_loader_spec.md](./fpga_uart_dmem_loader_spec.md) | UART DMEM loader protocol |
| [github_sync_and_self_hosted_runner_usage_spec.md](./github_sync_and_self_hosted_runner_usage_spec.md) | GitHub/self-hosted runner workflow |

## 9. Main Commands

License setup:

```bash
cd sim
make license
```

Current secure-storage focused testcase:

```bash
cd sim
make compile C_SRC=test_mmio_dma_storage_table.c
make all TESTNAME=dma_storage_table_input1_then_input3 \
  TB_NAME=test_bench \
  RUN_ARGS="+CASE_NAME=dma_storage_table_input1_then_input3 +INPUT_FILE=input1.txt +INPUT_FILE2=input3.txt"
```

Legacy normal SoC loopback:

```bash
cd sim
make compile C_SRC=test_mmio_dma.c
make drc
make all
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
make vivado_impl_full
```

## 10. Archived Or Non-Report Branches

Do not use these as the main report story:

| Branch/topic | Current status |
|---|---|
| Full TX+RX monolithic build | Current full target is board-oriented `rv32_soc_synth_full_fpga` using `rv32_soc_fpga_demo_top` |
| Interrupt/trap DMA completion | Not implemented; polling is active |
| Production entropy/secret IV generation | Not implemented; current IV is deterministic firmware demo IV |
| Custom RISC-V instruction | Not implemented; current integration uses MMIO and firmware API |
