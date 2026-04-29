# Coverage Regression Report

## 1. Scope

Bao cao nay ghi lai regression coverage hien tai cho SoC RV32I + Huffman +
AES-128 sau khi doi flow testcase sang form giong `timer_standard_hv`.

Flow hien tai:

1. `sim/pat.list` liet ke testcase.
2. `sim/run.csh` doc tung testcase, compile C program tuong ung, va chon top `test_bench`.
3. `sim/Makefile` copy `testcase/<TESTNAME>.v` thanh `sim/run_test.v`.
4. `tb/tb_rv32_soc_mmio_dma.v` include `run_test.v` va goi `run_selected_test()`.
5. Moi testcase sinh mot `.ucdb`.
6. `make gen_cov` merge thanh `sim/IP.ucdb` va sinh them closed UCDB/report bang `sim/coverage_close.do`.

## 2. Testbench Form

Clean coverage regression hien tai chi dung mot testbench chinh:

| TB | Mode |
|---|---|
| `test_bench` in `tb/tb_rv32_soc_mmio_dma.v` | Unified SoC regression: DMA loopback, TX-only benchmark, MMIO regfile legal/negative/mode-matrix |

`sim/tb.f` chi compile top nay. Cac TB cu duoc chuyen vao
`tb/archive/deprecated_20260429/` de coverage khong bi chia denominator sang
nhieu top khac.

Testbench co co che:

```verilog
`include "run_test.v"

initial begin
  run_test();
end
```

`run_test.v` la testcase duoc copy tu `testcase/<TESTNAME>.v`.

## 3. Active Testcases

Bang nay dung format thong nhat:

```text
id | function | testname | description | expectation | testcase | status | comment
```

### 3.1 CPU / SoC Control

| ID | Function | Testname | Description | Expectation | Testcase | Status | Comment |
|---|---|---|---|---|---|---|---|
| CPU-01 | CPU MMIO load/store | `mmio_regfile_basic` | RV32I ghi/doc config regs, IV regs, clear pulse va soft reset | Signature `REG1`, error mask 0, no DMA start, soft reset pulse seen | `test_mmio_regfile_basic.c` + `mmio_regfile_basic.v` | PASS | Cover CPU MMIO read/write co ban |
| CPU-02 | CPU MMIO illegal access | `mmio_regfile_negative` | Tao invalid start, readonly write, invalid address, reserved mode, bad block, byte-store reject | Sticky error set, bridge/APB error counted, no DMA start | `test_mmio_regfile_negative.c` + `mmio_regfile_negative.v` | PASS | Cover CPU-visible APB error path |
| CPU-03 | CPU sideband/top hold | `soc_sideband_cov` | Pulse `cpu_stall_i`, `cpu_if_flush_i`, aux high-bit activity | Base MMIO test van pass, sideband/toggle bins duoc hit | `test_mmio_regfile_basic.c` + `soc_sideband_cov.v` | PASS | Coverage hook trong TB |
| CPU-04 | RV32I instruction coverage | `cpu_instruction_cov` | Ep R-type, I-type, load/store byte/half/word, branch, `lui`, `jalr` | Signature `CPUC`, error mask 0, ALU/memory/branch signatures dung | `test_cpu_instruction_cov.c` + `cpu_instruction_cov.v` | PASS | Tang CPU decode/execute coverage |

### 3.2 DMA / MMIO Contract

| ID | Function | Testname | Description | Expectation | Testcase | Status | Comment |
|---|---|---|---|---|---|---|---|
| DMA-01 | Mode decode matrix | `mmio_mode_matrix` | Kiem tra mode `0x1`, `0x5`, `0x9`, `0xd`, RX `0x2`, invalid `0x0/0x3`, reserved bits | Status/mode readback dung, invalid/reserved set error, no DMA start | `test_mmio_mode_matrix.c` + `mmio_mode_matrix.v` | PASS | Cover software contract cua `DMA_MODE` |
| DMA-02 | RX bad length config | `mmio_rx_bad_length` | Start RX voi ciphertext length khong align 16B | RX error, bytes_done 0, last error `0x02` | `test_mmio_rx_bad_length.c` + `mmio_rx_bad_length.v` | PASS | Cover RX DMA expected-error |
| DMA-03 | TX APB wait-state | `tx_apb_wait_cov` | Inject TX APB `PREADY=0` trong ACCESS | TX-only flow pass, DMA TX wait dung | `test_mmio_tx_only.c` + `tx_apb_wait_cov.v` | PASS | Cover `dma_tx_engine` wait branch |
| DMA-04 | TX APB slave error | `tx_apb_error_cov` | Inject TX APB `PSLVERR=1` | TX error sticky set, last error `0x03` | `test_mmio_tx_apb_error.c` + `tx_apb_error_cov.v` | PASS | Cover `tx_dma_error_w` |
| DMA-05 | RX APB wait/backpressure | `rx_backpressure_cov` | Inject RX APB wait-state va ciphertext ready low | Loopback pass, RX khong mat data | `test_mmio_dma.c` + `rx_backpressure_cov.v` | PASS | Cover RX wait/backpressure co ban |

### 3.3 TX Encode / Compress / AES

| ID | Function | Testname | Description | Expectation | Testcase | Status | Comment |
|---|---|---|---|---|---|---|---|
| TX-01 | TX whole-file `COMPRESS_ONLY` | `tx_compress_only_input1` | Nen `input1.txt`, bypass AES | TX done, output align 16B, TX region non-zero, saving duong | `test_mmio_tx_only.c` + `tx_compress_only_input1.v` | PASS | Benchmark saving truc tiep |
| TX-02 | TX whole-file log-like | `tx_compress_only_input4_cov` | Nen `input4_cov.txt`, bypass AES | TX done, storage saving duong | `test_mmio_tx_only.c` + `tx_compress_only_input4_cov.v` | PASS | Theo doi log-like compression |
| TX-03 | TX block `COMPRESS_AES` | `tx_compress_aes_block_input3` | Mode `0x1`, block 32B + AES-CBC | Status `0x18/0x1a`, bytes_done align 16B | `test_mmio_tx_only_aes_block.c` + `tx_compress_aes_block_input3.v` | PASS | Cover block mode co AES |
| TX-04 | TX block `COMPRESS_ONLY` | `tx_compress_only_block_input3` | Mode `0x5`, block 32B bypass AES | Status `0x58/0x5a`, transport output hop le | `test_mmio_tx_only_compress_block.c` + `tx_compress_only_block_input3.v` | PASS | Cover block mode bypass AES |
| TX-05 | TX one-symbol whole-file | `tx_compress_only_one_symbol_cov` | Nen file lap lai mot ky tu, bypass AES | TX done, output align 16B, saving duong | `test_mmio_tx_only.c` + `tx_compress_only_one_symbol_cov.v` | PASS | Cover symbol distribution cuc doan |
| TX-06 | TX symbol-overflow error | `tx_compress_only_ascii_sweep_cov` | File co hon `MAX_SYMBOLS=63` ky tu khac nhau | TX expected error, debug code `0x06` | `test_mmio_tx_encoder_error.c` + `tx_compress_only_ascii_sweep_cov.v` | PASS | Cover encoder error path |
| TX-07 | TX short input | `tx_compress_only_short_raw_cov` | File rat ngan de hit header/payload corner | TX done, output hop le | `test_mmio_tx_only.c` + `tx_compress_only_short_raw_cov.v` | PASS | Cover short-input path |

### 3.4 RX Decode / Decrypt

| ID | Function | Testname | Description | Expectation | Testcase | Status | Comment |
|---|---|---|---|---|---|---|---|
| RX-01 | RX normal decode input1 | `dma_compress_aes_input1` | RX doc ciphertext cua input1 tu DMEM, AES decrypt, Huffman decode | RX done, bytes_done bang input_len, output match source | `test_mmio_dma.c` + `dma_compress_aes_input1.v` | PASS | RX normal path voi input dai |
| RX-02 | RX normal decode input3 | `dma_compress_aes_input3` | RX doc ciphertext cua input3, frame nho/lap lai cao | RX done, output match source | `test_mmio_dma.c` + `dma_compress_aes_input3.v` | PASS | RX small-frame path |
| RX-07 | RX one-symbol loopback | `dma_compress_aes_one_symbol_cov` | TX tao ciphertext cho file mot ky tu, RX decrypt/decode lai | RX output match source | `test_mmio_dma.c` + `dma_compress_aes_one_symbol_cov.v` | PASS | Cover one-symbol/short-frame behavior |
| RX-03 | RX malformed length | `mmio_rx_bad_length` | RX length khong align 16B | Expected error, khong ghi plaintext | `test_mmio_rx_bad_length.c` + `mmio_rx_bad_length.v` | PASS | Error path cua RX DMA |
| RX-04 | RX stream backpressure | `rx_backpressure_cov` | Giu ready low khi ciphertext valid high | Loopback van pass | `test_mmio_dma.c` + `rx_backpressure_cov.v` | PASS | Chua cover FIFO full sau |
| RX-05 | RX APB IF direct coverage | `rx_if_direct_cov` | Ep APB RX IF empty/full/error/pending CTXT va simultaneous push/pop | Base MMIO test pass, RX IF branch/expression coverage tang manh | `test_mmio_regfile_basic.c` + `rx_if_direct_cov.v` | PASS | Coverage hook cho `apb_huffman_rx_if` |
| RX-06 | RX parser/decoder direct coverage | `rx_parser_decoder_cov` | Ep parser nhan raw partial, one-symbol, compressed va malformed frame | Base MMIO test pass, parser/decoder state/error bins tang | `test_mmio_regfile_basic.c` + `rx_parser_decoder_cov.v` | PASS | Coverage hook, khong thay doi software contract |

### 3.5 SoC End-To-End

| ID | Function | Testname | Description | Expectation | Testcase | Status | Comment |
|---|---|---|---|---|---|---|---|
| SOC-01 | Full TX->RX secure storage | `dma_compress_aes_input1` | CPU cau hinh TX `COMPRESS_AES`, ghi ciphertext DMEM, RX decrypt/decode ve DMEM | Source match input, RX match source, TX non-zero, 2 DMA starts | `test_mmio_dma.c` + `dma_compress_aes_input1.v` | PASS | Main regression |
| SOC-02 | Full TX->RX small input | `dma_compress_aes_input3` | E2E voi input ngan/co lap lai cao | Loopback pass, saving duong | `test_mmio_dma.c` + `dma_compress_aes_input3.v` | PASS | Variation cho whole-file Huffman |

Pass/fail summary:

```text
TOTAL/PASSED/REMAIN:21/21/0
```

Coverage da chay lai sau khi gom ve mot testbench chinh. UCDB merged:

```text
dma_compress_aes_input1.ucdb
dma_compress_aes_input3.ucdb
dma_compress_aes_one_symbol_cov.ucdb
mmio_mode_matrix.ucdb
mmio_regfile_basic.ucdb
mmio_regfile_negative.ucdb
mmio_rx_bad_length.ucdb
rx_backpressure_cov.ucdb
rx_if_direct_cov.ucdb
rx_parser_decoder_cov.ucdb
soc_sideband_cov.ucdb
cpu_instruction_cov.ucdb
tx_apb_error_cov.ucdb
tx_apb_wait_cov.ucdb
tx_compress_aes_block_input3.ucdb
tx_compress_only_ascii_sweep_cov.ucdb
tx_compress_only_block_input3.ucdb
tx_compress_only_input1.ucdb
tx_compress_only_input4_cov.ucdb
tx_compress_only_one_symbol_cov.ucdb
tx_compress_only_short_raw_cov.ucdb
```

Coverage summary:

```text
Raw Total Coverage By Instance: 76.30%
Closed DUT Total Coverage By Instance (/test_bench/dut recursive): 90.03%
vcover merge: Errors=0, Warnings=0
```

Ghi chu: `summary_report.txt` la raw coverage, khong exclude. `dut_closed_report.txt`
la coverage-closure report sau `sim/coverage_close.do`. Closed report exclude
toggle, condition/expression/FSM-transition bins va mot so defensive/rare
branch/statement scope co comment/reason trong UCDB. Khong duoc nham lan 90.03%
voi raw functional coverage.

Module target sau lan chay nay:

| Module / Instance | Branch | Condition | Expression | Statement | Comment |
|---|---:|---:|---:|---:|---|
| `u_rx_top/u_apb_huffman_rx_if` | 87.83% | 100.00% | 98.27% | 94.33% | Tang manh nho `rx_if_direct_cov` |
| `u_rx_top/u_huffman_block_parser` | 47.05% | 27.65% | 61.11% | 66.50% | Van can malformed transport/parser testcase sau hon |
| `u_rx_top/u_huffman_block_decoder` | 64.70% | 32.29% | 47.36% | 62.22% | Van can malformed canonical/decode testcase co frame hop le vao decoder |
| `u_cpu/u_id_stage` | 98.11% | 88.88% | 88.23% | 100.00% | `cpu_instruction_cov` da tang instruction coverage |
| `u_cpu/u_ex_stage` | 100.00% | 100.00% | 100.00% | 100.00% | ALU/branch path dat full code coverage |

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

Coverage 72.62% tren `/test_bench/dut` la baseline sach, chua phai closure 100%.

Nhung nhom test con thieu:

| Missing class | Purpose |
|---|---|
| DMA invalid config | Bad direction/reserved/bad block/RX bad length partially covered; still need zero-length/start edge if targeting closure |
| APB bridge wait-state | TX/RX engine APB wait-state da cover; con CPU bridge-level external wait-state neu them APB slave moi |
| RX malformed transport | Cover parser/depacker/decoder error states |
| TX/RX backpressure | RX ciphertext stream-ready low da cover; con FIFO full/empty va stall sau hon |

Da cover them trong run 2026-04-29:

| Added case | Covered behavior |
|---|---|
| `mmio_regfile_basic` | legal MMIO read/write, IV regs, status cfg-valid, clear done/error, soft reset |
| `mmio_regfile_negative` | invalid start, readonly write, invalid address, reserved mode write, invalid block start, byte-store reject, no DMA start |
| `mmio_mode_matrix` | all current mode status encodings, invalid direction encodings, reserved mode error |
| `tx_compress_aes_block_input3` | TX `COMPRESS_AES` block mode |
| `tx_compress_only_block_input3` | TX `COMPRESS_ONLY` block mode |
| `mmio_rx_bad_length` | RX engine expected error path, non-16B ciphertext length, `dma_engine_error_w` |
| `soc_sideband_cov` | top-level sideband toggles: `cpu_stall_i`, `cpu_if_flush_i`, aux high-bit activity |
| `tx_apb_wait_cov` | TX APB `PREADY=0` wait-state inside DMA TX engine |
| `rx_backpressure_cov` | RX APB `PREADY=0` and ciphertext valid while ready is low |
| `tx_apb_error_cov` | TX APB `PSLVERR` expected error path and `tx_dma_error_w` |
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
