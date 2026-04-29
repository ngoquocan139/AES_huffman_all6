# Coverage Regression Report

## 1. Scope

Bao cao nay ghi lai regression coverage hien tai cho SoC RV32I + Huffman +
AES-128 sau khi doi flow testcase sang form giong `timer_standard_hv`.

Flow hien tai:

1. `sim/pat.list` liet ke testcase.
2. `sim/run.csh` doc tung testcase, compile C program tuong ung, va chon TB.
3. `sim/Makefile` copy `testcase/<TESTNAME>.v` thanh `sim/run_test.v`.
4. Moi TB include `run_test.v` va goi `run_selected_test()`.
5. Moi testcase sinh mot `.ucdb`.
6. `make gen_cov` merge thanh `sim/IP.ucdb`.

## 2. Testbench Form

Da refactor cac TB chinh:

| TB | Mode |
|---|---|
| `test_bench` | End-to-end `COMPRESS_AES`: TX compress + AES-CBC, RX decrypt + decode |
| `tb_rv32_soc_tx_only` | `COMPRESS_ONLY` TX-only benchmark |
| `tb_rv32_soc_mmio_regfile` | MMIO register file legal, negative, and mode-matrix tests |
| `tb_rv32_log_preprocess` | Host preprocess + TX benchmark debug branch |

Moi TB co cung co che:

```verilog
`include "run_test.v"

initial begin
  run_test();
end
```

`run_test.v` la testcase duoc copy tu `testcase/<TESTNAME>.v`.

## 3. Active Testcases

| Testcase | C program | TB | Input | Result |
|---|---|---|---|---|
| `dma_compress_aes_input1` | `test_mmio_dma.c` | `test_bench` | `input1.txt` | PASS |
| `dma_compress_aes_input3` | `test_mmio_dma.c` | `test_bench` | `input3.txt` | PASS |
| `tx_compress_only_input1` | `test_mmio_tx_only.c` | `tb_rv32_soc_tx_only` | `input1.txt` | PASS |
| `tx_compress_only_input4_cov` | `test_mmio_tx_only.c` | `tb_rv32_soc_tx_only` | `input4_cov.txt` | PASS |
| `tx_compress_aes_block_input3` | `test_mmio_tx_only_aes_block.c` | `tb_rv32_soc_tx_only` | `input3.txt` | PASS |
| `tx_compress_only_block_input3` | `test_mmio_tx_only_compress_block.c` | `tb_rv32_soc_tx_only` | `input3.txt` | PASS |
| `mmio_regfile_basic` | `test_mmio_regfile_basic.c` | `tb_rv32_soc_mmio_regfile` | none | PASS |
| `mmio_mode_matrix` | `test_mmio_mode_matrix.c` | `tb_rv32_soc_mmio_regfile` | none | PASS |
| `mmio_regfile_negative` | `test_mmio_regfile_negative.c` | `tb_rv32_soc_mmio_regfile` | none | PASS |

Pass/fail summary:

```text
TOTAL/PASSED/REMAIN:9/9/0
```

Coverage da chay lai sau khi them 3 testcase mode-coverage moi. UCDB merged:

```text
dma_compress_aes_input1.ucdb
dma_compress_aes_input3.ucdb
mmio_mode_matrix.ucdb
mmio_regfile_basic.ucdb
mmio_regfile_negative.ucdb
tx_compress_aes_block_input3.ucdb
tx_compress_only_block_input3.ucdb
tx_compress_only_input1.ucdb
tx_compress_only_input4_cov.ucdb
```

Coverage summary:

```text
Total Coverage By Instance (filtered view): 46.16%
```

Ghi chu: report dang tinh theo instance/top-level nen khi them TB moi, cac
instance inactive trong tung TB cung lam mau so coverage lon hon. Vi vay tong
coverage 46.16% khong nen so truc tiep voi 52.43% cu. Gia tri regression chinh
la 9/9 testcase pass, 9 UCDB merged, va `vcover merge` sach 0 warning.

## 4. Compression Results

| Testcase | Input length | Mode | Payload ratio | Payload saving | Storage ratio | Storage saving |
|---|---:|---|---:|---:|---:|---:|
| `dma_compress_aes_input1` | 2551 bytes | `COMPRESS_AES` | 36.32% | 63.68% | 38.89% | 61.11% |
| `dma_compress_aes_input3` | 242 bytes | `COMPRESS_AES` | 40.81% | 59.19% | 46.28% | 53.72% |
| `tx_compress_only_input1` | 2551 bytes | `COMPRESS_ONLY + whole_file` | 36.32% | 63.68% | 38.89% | 61.11% |
| `tx_compress_only_input4_cov` | 6000 bytes | `COMPRESS_ONLY + whole_file` | 62.23% | 37.77% | 66.40% | 33.60% |
| `tx_compress_aes_block_input3` | 242 bytes | `COMPRESS_AES + block_32B` | 28.56% | 71.44% | 33.06% | 66.94% |
| `tx_compress_only_block_input3` | 242 bytes | `COMPRESS_ONLY + block_32B` | 28.56% | 71.44% | 33.06% | 66.94% |

Nhan xet:

- `input1.txt` va `input3.txt` nen chay `COMPRESS_AES` neu can secure storage vi storage saving duong.
- `COMPRESS_ONLY` mac dinh da chuyen sang whole-file dynamic Huffman, nen `input4_cov.txt` tu saving am thanh saving duong.
- Per-block mode `0x1` va `0x5` da duoc cover rieng bang `input3.txt`; hai mode nay dung de giu compatibility voi block-32B flow cu.
- Log-like input van co the tang saving them bang preprocess/tokenize, nhung khong con bat buoc de tranh storage expansion trong testcase nay.

## 5. Mode Coverage

| Mode | Meaning | Current coverage |
|---|---|---|
| `0x1` | TX `COMPRESS_AES`, per-block Huffman | `tx_compress_aes_block_input3` |
| `0x5` | TX `COMPRESS_ONLY`, per-block Huffman | `tx_compress_only_block_input3` |
| `0x9` | TX `COMPRESS_AES`, whole-file Huffman | `dma_compress_aes_input1`, `dma_compress_aes_input3` |
| `0xd` | TX `COMPRESS_ONLY`, whole-file Huffman | `tx_compress_only_input1`, `tx_compress_only_input4_cov` |
| `0x2` | RX decrypt + decode | RX phase of `dma_compress_aes_input1`, RX phase of `dma_compress_aes_input3` |
| invalid `0x0/0x3` | Invalid/unsupported direction encoding | `mmio_mode_matrix` |
| reserved bit write | Illegal mode programming | `mmio_mode_matrix`, `mmio_regfile_negative` |

## 6. Current Gap To 100% Coverage

Coverage 46.16% la baseline sach, chua phai closure 100%.

Nhung nhom test con thieu:

| Missing class | Purpose |
|---|---|
| DMA invalid config | Bad direction/reserved/bad block partially covered; still need zero-length/start edge if targeting closure |
| APB bridge wait-state | Cover `PREADY=0`, hold semantics, APB access phase corner cases |
| RX malformed transport | Cover parser/depacker/decoder error states |
| TX/RX backpressure | Cover FIFO full/empty and stall paths |

Da cover them trong run 2026-04-29:

| Added case | Covered behavior |
|---|---|
| `mmio_regfile_basic` | legal MMIO read/write, IV regs, status cfg-valid, clear done/error, soft reset |
| `mmio_regfile_negative` | invalid start, readonly write, invalid address, reserved mode write, invalid block start, byte-store reject, no DMA start |
| `mmio_mode_matrix` | all current mode status encodings, invalid direction encodings, reserved mode error |
| `tx_compress_aes_block_input3` | TX `COMPRESS_AES` block mode |
| `tx_compress_only_block_input3` | TX `COMPRESS_ONLY` block mode |
| AES IV variation | Cover non-zero IV and CBC chain transitions |
| UART loader | Cover FPGA data-loading wrapper |
| CPU instruction stress | Cover RV32I instructions not used by current DMA software |

## 7. Commands Used

```sh
cd sim
./run.csh
./run.csh cov
./report.csh
make drc
```

Reports:

```text
sim/coverage/summary_report.txt
sim/coverage/detail_report.txt
sim/rep.log
```
