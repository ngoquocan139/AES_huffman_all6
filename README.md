# AES Huffman All6

RISC-V RV32I SoC for secure data storage using dynamic whole-file Huffman and
AES-128-CBC.

## Current Status

- Simulation top: `test_bench`
- Main secure-storage mode: `MODE=0x9`
- TX-only benchmark mode: `MODE=0xD`
- RX mode: `MODE=0x2`
- Coverage baseline: `34/34` PASS
- Raw DUT coverage: `93.52%`
- Closed DUT coverage: `95.90%`
- FPGA strategy: split TX-only and RX-only bitstreams

## What The SoC Does

```text
DMEM plaintext
-> TX DMA
-> dynamic Huffman compression
-> AES-128-CBC encrypt, or AES bypass for COMPRESS_ONLY
-> DMEM ciphertext/transport

DMEM ciphertext/transport
-> RX DMA
-> AES-128-CBC decrypt
-> Huffman decode
-> DMEM plaintext restore
```

RV32I is the control plane. It programs the DMA register file over MMIO/APB
and polls status. The high-speed data path is handled by DMA and the TX/RX
accelerators.

## Quick Start

```bash
cd sim
make compile C_SRC=test_mmio_dma.c
make drc
make all TESTNAME=dma_compress_aes_input1 RUN_ARGS="+CASE_NAME=dma_compress_aes_input1 +INPUT_FILE=input1.txt"
```

MIT-BIH paper comparison with already-preprocessed input:

```bash
cd sim
make compile C_SRC=test_mmio_dma.c
make all TESTNAME=dma_mitdb_100_delta2_var_e2e \
  RUN_ARGS="+CASE_NAME=dma_mitdb_100_delta2_var_e2e +INPUT_FILE=mitdb_100_mlii_10s_delta2_var.bin +INPUT_BINARY"
```

## Key Docs

- [Current system spec](docs/00_current_system_spec.md)
- [Spec flow index](docs/spec_flow_index.md)
- [Usage guide](docs/soc_usage_and_fpga_guide.md)
- [SoC 4.5 end-to-end report](docs/soc_4_5_end_to_end_report.md)
- [Paper comparison](docs/paper_comparison_huffman_aes_cbc.md)
- [Coverage plan](docs/coverage_test_plan_spec.md)

## Reports

Vivado reports and simulation outputs are stored under `sim/vivado_reports/`,
`sim/log/`, `sim/loopback/`, and `sim/dmem_dump/`.

## FPGA

The practical FPGA path is split:

- TX-only bitstream
- RX-only bitstream

Use the Vivado flow from `sim/Makefile` and `vivado/synth_soc.tcl`.
