# 00. Spec Flow Index

## 1. Purpose

This is the cleaned reading order for the current SoC.

The main rule is:

- read `00_current_system_spec.md` first;
- treat debug reports and old exploration notes as archive material;
- do not use old preprocess/RV32I sensor notes as the main architecture.

Current baseline:

| Item | Value |
|---|---|
| Main simulation top | `test_bench` only |
| Active testcase source | `sim/pat.list` |
| Coverage runner | `cd sim && ./run.csh cov` |
| Latest pass/fail | `32/32` PASS |
| Raw DUT full coverage | `86.44%` |
| Raw DUT branches / statements | `93.49% / 96.38%` |
| Closed DUT coverage | `95.59%` |
| Usage guide | [soc_usage_and_fpga_guide.md](/mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/docs/soc_usage_and_fpga_guide.md) |
| SOC 4.5 report | [soc_4_5_end_to_end_report.md](/mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/docs/soc_4_5_end_to_end_report.md) |
| Presentation guide | [report_presentation_guide.md](/mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/docs/report_presentation_guide.md) |
| Defense Q&A guide | [29_defense_qa_code_focus_spec.md](/mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/docs/29_defense_qa_code_focus_spec.md) |

## 2. Main Flow

1. `00` [00_current_system_spec.md](/mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/docs/00_current_system_spec.md)
   - current source of truth for architecture, modes, AES status, FPGA status.

2. `01` [memory_map_dma_software_contract.md](/mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/docs/memory_map_dma_software_contract.md)
   - CPU-visible memory map and DMA software contract.

3. `02` [bram_port_usage_spec.md](/mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/docs/bram_port_usage_spec.md)
   - IMEM/DMEM BRAM usage and port ownership.

4. `03` [cpu_dma_stall_policy_spec.md](/mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/docs/cpu_dma_stall_policy_spec.md)
   - when CPU stalls and when it must not stall.

5. `04` [cpu_mmio_to_apb_bridge_spec.md](/mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/docs/cpu_mmio_to_apb_bridge_spec.md)
   - CPU MMIO to APB transaction behavior.

6. `05` [dma_regfile_spec.md](/mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/docs/dma_regfile_spec.md)
   - `dma_regfile` registers and semantics.

7. `06` [iv_generation_and_cbc_contract_spec.md](/mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/docs/iv_generation_and_cbc_contract_spec.md)
   - who creates IV, how RV32I computes it, and how TX/RX consume it in CBC.

8. `07` [dma_riscv_instruction_programming_spec.md](/mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/docs/dma_riscv_instruction_programming_spec.md)
   - RV32I instructions used by the DMA control software.

9. `08` [tx_path_end_to_end_spec.md](/mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/docs/tx_path_end_to_end_spec.md)
   - end-to-end TX flow, module connectivity, software flow, DMA flow.

10. `09` [dma_tx_engine_spec.md](/mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/docs/dma_tx_engine_spec.md)
    - TX DMA data mover.

11. `10` [apb_huffman_aes_tx_top_spec.md](/mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/docs/apb_huffman_aes_tx_top_spec.md)
    - TX accelerator wrapper, Huffman path, AES/bypass output policy.

12. `11` [dynamic_huffman_encoder_spec.md](/mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/docs/dynamic_huffman_encoder_spec.md)
    - TX encoder core phases: collect, build, mode decision, emit.

13. `12` [bit_packer_128_spec.md](/mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/docs/bit_packer_128_spec.md)
    - bitstream packing into 128-bit transport words.

14. `13` [14_dynamic_whole_file_huffman_spec.md](/mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/docs/14_dynamic_whole_file_huffman_spec.md)
    - whole-file dynamic Huffman design used by the current main loopback.

15. `14` [rx_path_end_to_end_spec.md](/mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/docs/rx_path_end_to_end_spec.md)
    - end-to-end RX flow, module connectivity, software flow, DMA flow.

16. `15` [dma_rx_engine_spec.md](/mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/docs/dma_rx_engine_spec.md)
    - RX DMA data mover.

17. `16` [apb_huffman_aes_rx_top_spec.md](/mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/docs/apb_huffman_aes_rx_top_spec.md)
    - RX accelerator wrapper, AES-CBC decrypt, depacker, parser, decoder, output FIFO.

18. `17` [bit_depacker_128_spec.md](/mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/docs/bit_depacker_128_spec.md)
    - 128-bit transport word depacking into RX bit chunks.

19. `18` [huffman_block_parser_spec.md](/mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/docs/huffman_block_parser_spec.md)
    - RX block mode/header/table/payload parser.

20. `19` [huffman_block_decoder_spec.md](/mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/docs/huffman_block_decoder_spec.md)
    - RX canonical Huffman decoder, main table and fallback decode.

21. `20` [rx_byte_packer_32_spec.md](/mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/docs/rx_byte_packer_32_spec.md)
    - decoded byte packing into 32-bit output words.

22. `21` [apb_huffman_rx_if_spec.md](/mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/docs/apb_huffman_rx_if_spec.md)
    - RX APB output/status interface.

23. `22` [c_files_explained.md](/mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/docs/c_files_explained.md)
    - C tests, expected behavior, generated instruction memory.

24. `23` [soc_usage_and_fpga_guide.md](/mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/docs/soc_usage_and_fpga_guide.md)
    - practical usage guide: choose mode, choose C file, choose input txt, run simulation, and prepare FPGA bring-up.

25. `24` [github_sync_and_self_hosted_runner_usage_spec.md](/mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/docs/github_sync_and_self_hosted_runner_usage_spec.md)
    - Git/GitHub sync flow, GitHub-hosted DRC CI, and local self-hosted runner usage for Questa/Vivado.

26. `25` [fpga_uart_dmem_loader_spec.md](/mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/docs/fpga_uart_dmem_loader_spec.md)
    - runtime UART input loader for FPGA demo top, protocol, wiring, and loader reset flow.

27. `26` [coverage_test_plan_spec.md](/mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/docs/coverage_test_plan_spec.md)
    - `pat.list`, `run.csh`, `report.csh`, UCDB merge flow, and 100% coverage closure policy.
28. `27` [coverage_regression_report.md](/mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/docs/coverage_regression_report.md)
    - Current coverage regression result, active testcase list, compression ratios, and remaining closure gaps.

29. `28` [soc_4_5_end_to_end_report.md](/mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/docs/soc_4_5_end_to_end_report.md)
    - Focused report for the SoC 4.5 end-to-end cases, including logs, data flow, throughput, compression ratio, and dump paths.

30. `29` [report_presentation_guide.md](/mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/docs/report_presentation_guide.md)
    - Short guide for what to present to the advisor: architecture, key results, main testcase group, coverage, FPGA implementation, and topics to study.

31. `30` [29_defense_qa_code_focus_spec.md](/mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/docs/29_defense_qa_code_focus_spec.md)
    - Oral defense backup: what code to know best, detailed diagrams including register/mux view, and short answers for likely questions.

## 3. Removed Old Specs

These old files were removed because they were debug-only, test-policy-only, or
described branches that are no longer part of the current architecture:

| Document | Status |
|---|---|
| `09A_tx_policy_compress_only_vs_compress_aes_spec.md` | Folded into current system spec and DMA mode contract. |
| `09B_input_policy_input1_vs_input4_spec.md` | Demo naming policy, not RTL architecture. |
| `dma_tx_rx_fix_report.md` | Historical bug-fix report. |
| `host_preprocess_space_saving_report.md` | Old benchmark branch, not active flow. |
| `log_preprocess_binary_format_spec.md` | Old host preprocess branch, removed from current architecture. |
| `loopback_mmio_first_write_debug.md` | Historical MMIO debug note. |
| `spo2_hr_rv32i_spec.md` | Side exploration unrelated to current storage SoC. |
| `huffman_encode_decode_spec.md` | Old combined redirect doc, no longer needed. |
| `huffman_tx_encode_spec.md` | Folded into `dynamic_huffman_encoder_spec.md`, `bit_packer_128_spec.md`, and `apb_huffman_aes_tx_top_spec.md`. |
| `huffman_rx_decode_spec.md` | Folded into RX module specs: depacker, parser, decoder, byte packer, and RX APB IF. |
| `soc_current_status_report.md` | Old status report, removed because `00_current_system_spec.md` is the active source of truth. |
| `system_communication_mechanism_spec.md` | Old tổng flow spec, replaced by `tx_path_end_to_end_spec.md` and `rx_path_end_to_end_spec.md`. |

## 4. Quick Reading Paths

For architecture:

```text
00 -> 01 -> 06
TX: 08 -> 09 -> 10 -> 11 -> 12 -> 13
RX: 14 -> 15 -> 16 -> 17 -> 18 -> 19 -> 20 -> 21
```

For software/MMIO:

```text
00 -> 01 -> 05 -> 06 -> 07 -> 22 -> 23
```

For FPGA:

```text
00 -> 02 -> 23 -> 24 -> vivado/README.md
```

For coverage closure:

```text
25 -> 26 -> sim/pat.list -> ./run.csh cov -> ./report.csh -> coverage/detail_report.txt
```

For advisor presentation:

```text
00 -> 27 -> 26 -> 28 -> 29
```

For day-to-day commands:

```text
23 -> make compile C_SRC=... -> make drc -> make all TESTNAME=... RUN_ARGS=...
```

For GitHub/self-hosted runner:

```text
24 -> git push -> Actions -> Local Self-Hosted Flow
```
