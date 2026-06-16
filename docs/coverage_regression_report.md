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
| CPU-04 | RV32I instruction coverage | `cpu_instruction_cov` | Ep R-type, I-type, load/store byte/half/word, branch, `lui`, `jalr` | Signature `CPUC`, error mask 0, R-type/I-type/memory/branch signatures dung | `test_cpu_instruction_cov.c` + `cpu_instruction_cov.v` | PASS | Tang CPU decode/execute coverage |
| CPU-05 | CPU memory stage corner coverage | `cpu_mem_forward_cov` | Ep byte/half/word load-store offsets, signed/unsigned load va misaligned access branches trong `mem_stage` | Signature `CPUH`, error mask 0, checksum non-zero | `test_cpu_mem_forward_cov.c` + `cpu_mem_forward_cov.v` | PASS | Tang `mem_stage` branch/condition/statement coverage |
| CPU-06 | CPU forwarding direct mux coverage | `cpu_forward_direct_cov` | Force EX/MEM va MEM/WB rs1/rs2 forwarding, x0 no-match, byte/half/word select va priority path | Base MMIO pass, forwarding mix non-zero | `test_mmio_regfile_basic.c` + `cpu_forward_direct_cov.v` | PASS | Dua `forwarding` len gan/full coverage |

### 3.2 DMA / MMIO Contract

| ID | Function | Testname | Description | Expectation | Testcase | Status | Comment |
|---|---|---|---|---|---|---|---|
| DMA-01 | Mode decode matrix | `mmio_mode_matrix` | Kiem tra mode `0x1`, `0x5`, `0x9`, `0xd`, RX `0x2`, invalid `0x0/0x3`, reserved bits | Status/mode readback dung, invalid/reserved set error, no DMA start | `test_mmio_mode_matrix.c` + `mmio_mode_matrix.v` | PASS | Cover software contract cua `DMA_MODE` |
| DMA-02 | RX bad length config | `mmio_rx_bad_length` | Start RX voi ciphertext length khong align 16B | RX error, bytes_done 0, last error `0x02` | `test_mmio_rx_bad_length.c` + `mmio_rx_bad_length.v` | PASS | Cover RX DMA expected-error |
| DMA-03 | TX APB wait-state | `tx_apb_wait_cov` | Inject TX APB `PREADY=0` trong ACCESS | TX-only flow pass, DMA TX wait dung | `test_mmio_tx_only.c` + `tx_apb_wait_cov.v` | PASS | Cover `dma_tx_engine` wait branch |
| DMA-04 | TX APB slave error | `tx_apb_error_cov` | Inject TX APB `PSLVERR=1` | TX error sticky set, last error `0x03` | `test_mmio_tx_apb_error.c` + `tx_apb_error_cov.v` | PASS | Cover `tx_dma_error_w` |
| DMA-05 | RX APB wait/backpressure | `rx_backpressure_cov` | Inject RX APB wait-state va ciphertext ready low | Loopback pass, RX khong mat data | `test_mmio_dma.c` + `rx_backpressure_cov.v` | PASS | Cover RX wait/backpressure co ban |
| DMA-06 | DMA bridge/regfile direct defensive coverage | `dma_bridge_direct_cov` | TB force truc tiep bridge, DMA regfile va DMA TX/RX engine vao cac pha wait/error/invalid config hiem: APB wait, PSLVERR readback, invalid state, busy-write, misaligned config, bad block size va defensive state eval. | Base MMIO pass, bridge/regfile/DMA engine branch/statement coverage tang, khong thay doi software contract | `test_mmio_regfile_basic.c` + `dma_bridge_direct_cov.v` | PASS | Coverage hook tap trung vao defensive branches kho tao bang CPU program |

### 3.3 TX Encode / Compress / AES

| ID | Function | Testname | Description | Expectation | Testcase | Status | Comment |
|---|---|---|---|---|---|---|---|
| TX-01 | TX whole-file `COMPRESS_ONLY` | `tx_compress_only_input1` | Nen `input1.txt`, bypass AES | TX done, output align 16B, TX region non-zero, saving duong | `test_mmio_tx_only.c` + `tx_compress_only_input1.v` | PASS | Benchmark saving truc tiep |
| TX-02 | TX whole-file log-like | `tx_compress_only_input4_cov` | Nen `input4_cov.txt`, bypass AES | TX done, storage saving duong | `test_mmio_tx_only.c` + `tx_compress_only_input4_cov.v` | PASS | Theo doi log-like compression |
| TX-03 | TX block `COMPRESS_AES` | `tx_compress_aes_block_input3` | Mode `0x1`, block 32B + AES-CBC | Status `0x18/0x1a`, bytes_done align 16B | `test_mmio_tx_only_aes_block.c` + `tx_compress_aes_block_input3.v` | PASS | Cover block mode co AES |
| TX-04 | TX block `COMPRESS_ONLY` | `tx_compress_only_block_input3` | Mode `0x5`, block 32B bypass AES | Status `0x58/0x5a`, transport output hop le | `test_mmio_tx_only_compress_block.c` + `tx_compress_only_block_input3.v` | PASS | Cover block mode bypass AES |
| TX-05 | TX one-symbol whole-file | `tx_compress_only_one_symbol_cov` | Nen file lap lai mot ky tu, bypass AES | TX done, output align 16B, saving duong | `test_mmio_tx_only.c` + `tx_compress_only_one_symbol_cov.v` | PASS | Cover symbol distribution cuc doan |
| TX-06 | TX 256-symbol sweep stress | `tx_compress_only_ascii_sweep_cov` | File co nhieu byte-symbol khac nhau, chay tren alphabet 256 symbol de stress table/header/code-length path | TX done, output align 16B, source match; storage expansion la expected voi input gan uniform | `test_mmio_tx_only.c` + `tx_compress_only_ascii_sweep_cov.v` | PASS | Sau nang codebook 256, case nay khong con la overflow error |
| TX-07 | TX alnum63 stress | `tx_compress_only_alnum63_cov` | File co 63 symbol hop le, dung de stress codebook lon vua phai trong alphabet 256 | TX done, output align 16B, debug 0 | `test_mmio_tx_only.c` + `tx_compress_only_alnum63_cov.v` | PASS | Stress Huffman builder hop le |
| TX-08 | TX short input | `tx_compress_only_short_raw_cov` | File rat ngan de hit header/payload corner | TX done, output hop le | `test_mmio_tx_only.c` + `tx_compress_only_short_raw_cov.v` | PASS | Cover short-input path |
| TX-09 | TX APB IF direct coverage | `tx_if_direct_cov` | Ep TX APB IF doc empty/full/error/status, invalid config, soft reset, output FIFO full va simultaneous push/pop | Base MMIO test pass, `apb_huffman_tx_if` branch/statement coverage tang manh | `test_mmio_regfile_basic.c` + `tx_if_direct_cov.v` | PASS | Coverage hook cho TX APB wrapper, khong thay doi software contract |
| TX-10 | TX encoder direct coverage | `tx_encoder_direct_cov` | TB force cac stage encoder/header/payload de cover transition va error flags hiem. Block-level mode decision da bi loai khoi RTL active. | Base MMIO pass, TX encoder branch/statement coverage tang | `test_mmio_regfile_basic.c` + `tx_encoder_direct_cov.v` | PASS | White-box coverage hook cho module con TX |
| TX-11 | TX builder/packer direct coverage | `tx_builder_packer_direct_cov` | TB force Huffman builder, code-length/canonical generator va bit-packer qua cac state/transition hiem: one-symbol, multi-symbol, overflow/short frame, final partial word va flush. | Base MMIO pass, TX builder/packer bins tang | `test_mmio_regfile_basic.c` + `tx_builder_packer_direct_cov.v` | PASS | White-box coverage hook cho Huffman builder/packer |

### 3.4 RX Decode / Decrypt

| ID | Function | Testname | Description | Expectation | Testcase | Status | Comment |
|---|---|---|---|---|---|---|---|
| RX-01 | RX normal decode input1 | `dma_compress_aes_input1` | RX doc ciphertext cua input1 tu DMEM, AES decrypt, Huffman decode | RX done, bytes_done bang input_len, output match source | `test_mmio_dma.c` + `dma_compress_aes_input1.v` | PASS | RX normal path voi input dai |
| RX-02 | RX normal decode input3 | `dma_compress_aes_input3` | RX doc ciphertext cua input3, frame nho/lap lai cao | RX done, output match source | `test_mmio_dma.c` + `dma_compress_aes_input3.v` | PASS | RX small-frame path |
| RX-07 | RX one-symbol loopback | `dma_compress_aes_one_symbol_cov` | TX tao ciphertext cho file mot ky tu, RX decrypt/decode lai | RX output match source | `test_mmio_dma.c` + `dma_compress_aes_one_symbol_cov.v` | PASS | Cover one-symbol/short-frame behavior |
| RX-09 | RX alnum63 loopback | `dma_compress_aes_alnum63_cov` | TX tao ciphertext tu file 63 symbol hop le, RX decrypt/decode lai voi codebook lon hon input binh thuong | RX output match source, `rx_bytes_done=504`, decoder meta `symbol_count=63` | `test_mmio_dma.c` + `dma_compress_aes_alnum63_cov.v` | PASS | Functional E2E stress; saving am la expected |
| RX-03 | RX malformed length | `mmio_rx_bad_length` | RX length khong align 16B | Expected error, khong ghi plaintext | `test_mmio_rx_bad_length.c` + `mmio_rx_bad_length.v` | PASS | Error path cua RX DMA |
| RX-04 | RX stream backpressure | `rx_backpressure_cov` | Giu ready low khi ciphertext valid high | Loopback van pass | `test_mmio_dma.c` + `rx_backpressure_cov.v` | PASS | Chua cover FIFO full sau |
| RX-05 | RX APB IF direct coverage | `rx_if_direct_cov` | Ep APB RX IF empty/full/error/pending CTXT va simultaneous push/pop | Base MMIO test pass, RX IF branch/expression coverage tang manh | `test_mmio_regfile_basic.c` + `rx_if_direct_cov.v` | PASS | Coverage hook cho `apb_huffman_rx_if` |
| RX-06 | RX parser/decoder direct coverage | `rx_parser_decoder_cov` | Ep parser nhan raw partial, one-symbol, compressed va malformed frame | Base MMIO test pass, parser/decoder state/error bins tang | `test_mmio_regfile_basic.c` + `rx_parser_decoder_cov.v` | PASS | Coverage hook, khong thay doi software contract |
| RX-08 | RX decoder fallback/error direct coverage | `rx_decoder_direct_cov` | Force truc tiep cac wire parser->decoder de cover long-code fallback, reuse table, duplicate entry, entry-last miss/early va metadata error | Base MMIO test pass, decoder fallback/error bins tang | `test_mmio_regfile_basic.c` + `rx_decoder_direct_cov.v` | PASS | Coverage hook tap trung vao `huffman_block_decoder` |
| RX-10 | RX depacker/packer direct coverage | `rx_depacker_packer_direct_cov` | TB drive depacker/byte-packer bang malformed transport, valid_bytes corner, fifo full/empty va packer backpressure/error branches. | Base MMIO pass, depacker/packer bins tang | `test_mmio_regfile_basic.c` + `rx_depacker_packer_direct_cov.v` | PASS | White-box coverage hook cho RX data formatting |
| RX-11 | RX parser/decoder error direct coverage | `rx_parser_decoder_error_direct_cov` | TB tao malformed parser/decode entries: invalid header, invalid code length, missing/early entry last, zero-length va append dummy path. | Base MMIO pass, parser/decoder defensive error bins tang | `test_mmio_regfile_basic.c` + `rx_parser_decoder_error_direct_cov.v` | PASS | Bo sung nhung malformed path khong nen tao bang normal DMA |

### 3.5 SoC End-To-End

| ID | Function | Testname | Description | Expectation | Testcase | Status | Comment |
|---|---|---|---|---|---|---|---|
| SOC-01 | Full TX->RX secure storage | `dma_compress_aes_input1` | CPU cau hinh TX `COMPRESS_AES`, ghi ciphertext DMEM, RX decrypt/decode ve DMEM | Source match input, RX match source, TX non-zero, 2 DMA starts | `test_mmio_dma.c` + `dma_compress_aes_input1.v` | PASS | Main regression |
| SOC-02 | Full TX->RX small input | `dma_compress_aes_input3` | E2E voi input ngan/co lap lai cao | Loopback pass, saving duong | `test_mmio_dma.c` + `dma_compress_aes_input3.v` | PASS | Variation cho whole-file Huffman |
| SOC-03 | Full TX->RX alnum63 stress | `dma_compress_aes_alnum63_cov` | E2E voi 63 symbol hop le de stress codebook lon va AES/RX loopback | Loopback pass, TX ciphertext non-zero, 2 DMA starts | `test_mmio_dma.c` + `dma_compress_aes_alnum63_cov.v` | PASS | Functional stress, khong dung de danh gia saving |
| SOC-04 | Software-managed storage table | `dma_storage_table_input1_then_input3` | CPU TX input1, ghi metadata record 0, TX input2, ghi metadata record 1, sau do RX lai selected file_id=1 tu metadata | RX output match input1, total records 2, selected id 1, 3 DMA starts | `test_mmio_dma_storage_table.c` + `dma_storage_table_input1_then_input3.v` | PASS | Chung minh software RV32I co the quan ly nhieu ciphertext record |
| SOC-05 | Raw DUT stress closure | `raw_dut_stress_cov` | TB-only hook ep cac FSM reset transition, large debug OR expression, memory-array toggle va defensive state/toggle bins | Base MMIO pass, raw DUT `bcesft` > 90% | `test_mmio_regfile_basic.c` + `raw_dut_stress_cov.v` | PASS | Coverage closure hook, khong phai demo functional |

Pass/fail summary:

```text
TOTAL/PASSED/REMAIN:34/34/0
```

Coverage da chay lai sau khi gom ve mot testbench chinh. UCDB merged:

```text
cpu_forward_direct_cov.ucdb
cpu_instruction_cov.ucdb
cpu_mem_forward_cov.ucdb
dma_bridge_direct_cov.ucdb
dma_compress_aes_input1.ucdb
dma_compress_aes_alnum63_cov.ucdb
dma_compress_aes_input3.ucdb
dma_compress_aes_one_symbol_cov.ucdb
dma_storage_table_input1_then_input3.ucdb
mmio_mode_matrix.ucdb
mmio_regfile_basic.ucdb
mmio_regfile_negative.ucdb
mmio_rx_bad_length.ucdb
raw_dut_stress_cov.ucdb
rx_backpressure_cov.ucdb
rx_decoder_direct_cov.ucdb
rx_depacker_packer_direct_cov.ucdb
rx_if_direct_cov.ucdb
rx_parser_decoder_cov.ucdb
rx_parser_decoder_error_direct_cov.ucdb
soc_sideband_cov.ucdb
tx_apb_error_cov.ucdb
tx_apb_wait_cov.ucdb
tx_builder_packer_direct_cov.ucdb
tx_compress_aes_block_input3.ucdb
tx_compress_only_alnum63_cov.ucdb
tx_compress_only_ascii_sweep_cov.ucdb
tx_compress_only_block_input3.ucdb
tx_compress_only_input1.ucdb
tx_compress_only_input4_cov.ucdb
tx_compress_only_one_symbol_cov.ucdb
tx_compress_only_short_raw_cov.ucdb
tx_encoder_direct_cov.ucdb
tx_if_direct_cov.ucdb
```

Coverage summary:

```text
Raw overall summary coverage: 92.51%
Raw DUT total with toggle (-code bcesft): 93.52%
Raw DUT total without toggle (-code bcesf): 94.44%
Raw DUT statement coverage: 96.33%
Raw DUT branch coverage: 94.22%
Raw DUT branch+statement (-code bs): 95.27%
Closed DUT Total Coverage By Instance (/test_bench/dut recursive): 95.90%
vcover merge: Errors=0, Warnings=0
```

Ghi chu: `summary_report.txt` la raw coverage, khong exclude. `dut_closed_report.txt`
la coverage-closure report sau `sim/coverage_close.do`. Closed report exclude
toggle, condition/expression/FSM-transition bins va mot so defensive/rare
branch/statement scope co comment/reason trong UCDB. Khong duoc nham lan 95.90%
voi raw DUT total coverage 93.52%.

Module target sau lan chay nay:

| Module / Instance | Branch | Condition | Expression | Statement | Comment |
|---|---:|---:|---:|---:|---|
| `u_tx_top/u_apb_huffman_tx_if` | 98.94% | 75.00% | 82.35% | 100.00% | Tang manh nho `tx_if_direct_cov`; con thieu condition/expression bins |
| `u_rx_top/u_apb_huffman_rx_if` | 100.00% | 100.00% | 100.00% | 100.00% | RX APB IF dat full code coverage theo b/c/e/s |
| `u_rx_top/u_huffman_block_parser` | 94.11% | 76.59% | 88.88% | 98.54% | Da tang bang raw-full/multi-entry/malformed direct frame; con thieu condition/toggle |
| `u_rx_top/u_huffman_block_decoder` | 97.64% | 85.41% | 78.94% | 99.44% | Da tang bang fallback/error direct coverage; con thieu expression/toggle |
| `u_cpu/u_id_stage` | 98.11% | 88.88% | 88.23% | 100.00% | `cpu_instruction_cov` da tang instruction coverage |
| `u_cpu/u_ex_stage` | 100.00% | 100.00% | 100.00% | 100.00% | ALU/branch path dat full code coverage |
| `u_cpu/u_mem_stage` | 91.22% | 92.85% | 100.00% | 96.40% | `cpu_mem_forward_cov` da cover byte/half/word offsets va misaligned branches |
| `u_cpu/u_forwarding` | 100.00% | 100.00% | 100.00% | 100.00% | `cpu_forward_direct_cov` da cover EX/MEM, MEM/WB va priority path |

## 4. Compression Results

| Testcase | Input length | Mode | Payload ratio | Payload saving | Storage ratio | Storage saving |
|---|---:|---|---:|---:|---:|---:|
| `dma_compress_aes_input1` | 2551 bytes | `COMPRESS_AES` | 32.11% | 67.89% | 34.50% | 65.50% |
| `dma_compress_aes_input3` | 242 bytes | `COMPRESS_AES` | 42.05% | 57.95% | 46.28% | 53.72% |
| `dma_compress_aes_alnum63_cov` | 504 bytes | `COMPRESS_AES` | 101.86% | -1.86% | 111.11% | -11.11% |
| `tx_compress_only_input1` | 2551 bytes | `COMPRESS_ONLY + whole_file` | 32.11% | 67.89% | 34.50% | 65.50% |
| `tx_compress_only_input4_cov` | 6000 bytes | `COMPRESS_ONLY + whole_file` | 63.40% | 36.60% | 67.73% | 32.27% |
| `tx_compress_only_alnum63_cov` | 504 bytes | `COMPRESS_ONLY + whole_file` | 101.86% | -1.86% | 111.11% | -11.11% |
| `tx_compress_aes_block_input3` | 242 bytes | `COMPRESS_AES + block_32B` | 29.65% | 70.35% | 33.06% | 66.94% |
| `tx_compress_only_block_input3` | 242 bytes | `COMPRESS_ONLY + block_32B` | 29.65% | 70.35% | 33.06% | 66.94% |

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
| `0x9` | TX `COMPRESS_AES`, whole-file Huffman | `dma_compress_aes_input1`, `dma_compress_aes_input3`, `dma_compress_aes_alnum63_cov` |
| `0xd` | TX `COMPRESS_ONLY`, whole-file Huffman | `tx_compress_only_input1`, `tx_compress_only_input4_cov` |
| `0x2` | RX decrypt + decode | RX phase of `dma_compress_aes_input1`, RX phase of `dma_compress_aes_input3`, RX phase of `dma_compress_aes_alnum63_cov` |
| invalid `0x0/0x3` | Invalid/unsupported direction encoding | `mmio_mode_matrix` |
| reserved bit write | Illegal mode programming | `mmio_mode_matrix`, `mmio_regfile_negative` |

## 6. Current Gap To 100% Coverage

Raw DUT total coverage tren `/test_bench/dut` hien tai la 93.52% khi tinh ca
toggle va 94.44% khi bo toggle. Branch+statement da dat 95.27%, closed DUT dat
95.90%. Raw DUT da vuot moc 90%, nhung van chua phai raw full-code 100%.

Nhung nhom test con thieu:

| Missing class | Purpose |
|---|---|
| Toggle bins | Cac bus AES/Huffman/DMA rong co bit cao/hiem it doi trang thai, van la nhom bin keo raw `bcesft` xuong |
| Condition/expression bins | Mot so condition defensive cua parser/decoder/builder chi xay ra voi malformed frame cuc doan |
| Raw full 100% | Can them testcase rat dac thu hoac waiver/exclusion co reason; khong nen coi day la loi functional neu branch/statement va testcase chinh da pass |

Da cover them trong cac run closure den 2026-05-10:

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
| `tx_if_direct_cov` | TX APB IF invalid config, soft reset, output FIFO full/empty, status/debug read branches |
| `tx_compress_only_alnum63_cov` | Valid alnum63 Huffman builder path under 256-symbol alphabet |
| `dma_compress_aes_alnum63_cov` | Full TX/RX alnum63 loopback under 256-symbol alphabet |
| `rx_parser_decoder_cov` update | Raw-full multi-chunk, compressed two-symbol frame, malformed entry, zero-length chunk |
| `rx_depacker_packer_direct_cov` | RX depacker/byte-packer malformed transport, full/empty/backpressure branches |
| `rx_parser_decoder_error_direct_cov` | RX parser/decoder malformed-entry and append-dummy error branches |
| `tx_encoder_direct_cov` | TX encoder/control/header/payload defensive branches |
| `tx_builder_packer_direct_cov` | TX Huffman builder/canonical/packer state and final-word branches |
| `dma_bridge_direct_cov` | CPU MMIO bridge, DMA regfile, DMA TX/RX engine defensive branches |
| AES IV variation | Cover non-zero IV and CBC chain transitions |
| UART loader | Cover FPGA data-loading wrapper |
| CPU instruction stress | Cover RV32I instructions not used by current DMA software |
| CPU memory-stage stress | Cover byte/half/word offsets, sign extension va misaligned access branches |
| CPU forwarding direct hook | Cover EX/MEM, MEM/WB va priority forwarding mux paths |
| `raw_dut_stress_cov` | Cover top-level debug reduction expression, FSM reset arcs, memory-array toggles va defensive internal states; day la case giup raw DUT bcesft vuot 90% |

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
