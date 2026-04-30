# 13. C Program Test Spec

## 1. Scope

Repo hien tai co nhom chuong trinh C phuc vu RV32I simulation/coverage:

| C file | Main role | Active baseline |
|---|---|---|
| `testcase/test.c` | smoke program cu cho core sync | reference only |
| `testcase/test_mmio_dma.c` | main DMA loopback: TX `COMPRESS_AES + whole_file` roi RX decode ve DMEM | yes |
| `testcase/test_mmio_tx_only.c` | TX-only `COMPRESS_ONLY + whole_file` de do saving truc tiep | yes |
| `testcase/test_mmio_tx_only_aes_block.c` | TX-only `COMPRESS_AES` per-block 32B | coverage |
| `testcase/test_mmio_tx_only_compress_block.c` | TX-only `COMPRESS_ONLY` per-block 32B | coverage |
| `testcase/test_mmio_tx_encoder_error.c` | expected TX symbol-overflow error path | coverage |
| `testcase/test_mmio_regfile_basic.c` | legal MMIO register read/write, IV, reset/clear pulse | coverage |
| `testcase/test_mmio_regfile_negative.c` | invalid MMIO/config/error propagation | coverage |
| `testcase/test_mmio_mode_matrix.c` | mode decode/status matrix | coverage |
| `testcase/test_mmio_rx_bad_length.c` | expected RX bad ciphertext length error | coverage |
| `testcase/test_cpu_instruction_cov.c` | RV32I instruction coverage | coverage |
| `testcase/test_cpu_mem_forward_cov.c` | CPU memory-stage/forwarding corner coverage | coverage |

Nhanh cu `RV32I` tu preprocess/parser text va host-preprocess benchmark khong con
la flow chinh. Neu thay cac artifact ten `*_preprocess*`, xem chung la
deprecated/debug history, khong dung lam demo mac dinh.

Tai lieu nay giai thich ro:

1. Moi file test cai gi.
2. Dung instruction nao.
3. Tieu chi pass/fail va expected state.

## 1.1 C Test Selection Flow Chart

```mermaid
flowchart TD
  A["Choose what to verify"] --> B{"Goal"}
  B -->|"core smoke"| C["test.c"]
  B -->|"full TX/RX loopback"| D["test_mmio_dma.c"]
  B -->|"TX-only saving"| E["test_mmio_tx_only.c"]
  B -->|"MMIO/CPU coverage"| F["test_mmio_regfile_basic.c / test_cpu_*.c"]
  C --> G["make compile C_SRC=test.c"]
  D --> H["make compile C_SRC=test_mmio_dma.c"]
  E --> I["make compile C_SRC=test_mmio_tx_only.c"]
  F --> J["make compile C_SRC=<coverage>.c"]
  G --> K["make all TESTNAME=... RUN_ARGS=..."]
  H --> K
  I --> K
  J --> K
```

## 2. Build Profile (dang duoc dung)

Compile trong `sim/Makefile`:

- ASM: `-march=rv32i -mabi=ilp32 -Os -S`
- ELF: `-march=rv32i -mabi=ilp32 -O1 -nostdlib -ffreestanding -Ttext=0x0 -Wl,-e,_start`
- Objcopy: binary
- Output `.S/.elf/.bin/.mem` duoc tao trong `testcase/`.
- File `.mem` sinh ra duoc copy sang `sim/instruction.mem` de `imem_sync` dung cho simulation.

Luu y:
- Instruction sequence cua `test_mmio_dma.c` duoi day la theo disassembly hien tai cua `testcase/test_mmio_dma.elf`.
- Neu doi compiler/version/optimization, dia chi PC va instruction co the thay doi.

---

## 3. `testcase/test.c` (RV32I Smoke Program)

### 3.1 Muc tieu test

- Xac nhan duong arith + load/store co ban.
- Xac nhan vong lap branch va ghi DMEM word0.
- Dung cho testbench sync core (`tb_risc_v_sync_mem.v`).

### 3.2 Instruction sequence (co dinh bang `.word`)

| Idx | Hex       | Mnemonic           | Y nghia |
|-----|-----------|--------------------|--------|
| 0   | 00500093  | `addi x1, x0, 5`   | x1 = 5 |
| 1   | 00a00113  | `addi x2, x0, 10`  | x2 = 10 |
| 2   | 002081b3  | `add x3, x1, x2`   | x3 = 15 |
| 3   | 00302023  | `sw x3, 0(x0)`     | DMEM[0] = 15 |
| 4   | 00000213  | `addi x4, x0, 0`   | x4 = 0 |
| 5   | 00000293  | `addi x5, x0, 0`   | x5 = 0 |
| 6   | 00800313  | `addi x6, x0, 8`   | x6 = 8 |
| 7   | 00520233  | `add x4, x4, x5`   | x4 += x5 |
| 8   | 00128293  | `addi x5, x5, 1`   | x5++ |
| 9   | fe62cce3  | `blt x5, x6, loop` | lap den khi x5 == 8 |
| 10  | 00402023  | `sw x4, 0(x0)`     | DMEM[0] = tong |
| 11  | 00002383  | `lw x7, 0(x0)`     | x7 = DMEM[0] |
| 12  | 00138393  | `addi x7, x7, 1`   | x7++ |
| 13  | 00702023  | `sw x7, 0(x0)`     | DMEM[0] = x7 |
| 14  | fe000ae3  | `beq x0, x0, spin` | dung tai vong lap vo han |

### 3.3 Expected state

- `x1 = 5`
- `x2 = 10`
- `x3 = 15`
- `x4 = 0x1c` (tong 0..7 = 28)
- `DMEM[0] >= 0x1c` (thuc te thuong la `0x1d` sau buoc increment x7 + store)

---

## 4. `testcase/test_mmio_dma.c` (DMA TX/RX Loopback Test)

### 4.1 Muc tieu test

Test duong data-plane loopback hien tai:

- testbench load file input text vao `DMEM[0x00000400 ..]`;
- CPU cau hinh DMA TX whole-file Huffman + AES (`MODE = 0x9`);
- DMA TX doc plaintext 2 pass: pass 1 count/build global table, pass 2 emit compressed AES stream vao `DMEM[0x00002000 ..]`;
- CPU doc `DMA_CIPHERTEXT_BYTES_PRODUCED`;
- CPU cau hinh DMA RX (`MODE = 0x2`) de doc ciphertext vua tao va ghi plaintext ve `DMEM[0x00004000 ..]`;
- CPU ghi `signature + error_mask + status + length/result head` ve `DMEM word 0..15`;
- testbench dump source/TX/RX va compare RX output voi input goc.

### 4.2 DMA MMIO map su dung trong test

Base: `0x4000_0000`

- `+0x00` `DMA_CONTROL`
- `+0x04` `DMA_STATUS`
- `+0x08` `DMA_SRC_ADDR`
- `+0x0C` `DMA_DST_ADDR`
- `+0x10` `DMA_LEN_BYTES`
- `+0x14` `DMA_MODE`
- `+0x18` `DMA_BLOCK_CFG`
- `+0x1C` `DMA_BYTES_DONE`
- `+0x20` `DMA_DEBUG`
- `+0x24` `DMA_CIPHERTEXT_BYTES_PRODUCED`

Gia tri config duoc ghi:

- TX: `SRC_ADDR = 0x00000400`
- TX: `DST_ADDR = 0x00002000`
- TX: `LEN_BYTES = INPUT_LEN_ADDR`
- TX: `MODE = 0x00000009`
- RX: `SRC_ADDR = 0x00002000`
- RX: `DST_ADDR = 0x00004000`
- RX: `LEN_BYTES = DMA_CIPHERTEXT_BYTES_PRODUCED`
- RX: `MODE = 0x00000002`
- `BLOCK_CFG = 0x20`
- `CONTROL = 0x1` (start)

### 4.3 Result layout trong DMEM (word offset)

- `word0`  = signature `0x44525831`
- `word1`  = `error_mask`
- `word2`  = `tx_status_before_start`
- `word3`  = `tx_status_after_done`
- `word4`  = `tx_bytes_done`
- `word5`  = `tx_ciphertext_bytes`
- `word6`  = `tx_poll_count`
- `word7`  = `rx_status_before_start`
- `word8`  = `rx_status_after_done`
- `word9`  = `rx_bytes_done`
- `word10` = `rx_debug`
- `word11` = `rx_poll_count`
- `word12..15` = 4 word dau cua RX output

Pass condition:

- `word1 == 0`
- `word2 == 0x98`
- `word3 == 0x9a`
- `word4 != 0` va align `16 byte`
- `word5 == word4`
- `word8 == 0x2a`
- `word9 == input_len`
- RX output trong dump phai match input goc.

---

## 5. `testcase/test_mmio_tx_only.c` (COMPRESS_ONLY TX-Only Benchmark)

### 5.1 Muc tieu test

Test rieng nhanh `COMPRESS_ONLY` de do saving truc tiep o phia TX:

- testbench load file text vao `DMEM[SRC_BASE_ADDR ..]`;
- CPU ghi `dma_regfile` qua MMIO/APB;
- `DMA_MODE = 0xD` (`direction=TX`, `compress_only=1`, `whole_file=1`);
- DMA doc plaintext tu `DMEM`, day qua Huffman TX, bypass AES, roi ghi ket qua ve `DMEM[TX_DST_BASE_ADDR ..]`;
- CPU poll `DMA_STATUS`, doc `DMA_BYTES_DONE`, `DMA_CIPHERTEXT_BYTES_PRODUCED`, `DMA_DEBUG`, va 4 word dau cua output;
- CPU ghi `signature + error_mask + status + output head` ve `DMEM word 0..13`;
- testbench chi check TX output va benchmark saving, khong chay RX.
- flow dung cho nhom input "chi can nen", mac dinh la `input1.txt`.

### 5.2 DMA MMIO map su dung trong test

Base: `0x4000_0000`

- `+0x00` `DMA_CONTROL`
- `+0x04` `DMA_STATUS`
- `+0x08` `DMA_SRC_ADDR`
- `+0x0C` `DMA_DST_ADDR`
- `+0x10` `DMA_LEN_BYTES`
- `+0x14` `DMA_MODE`
- `+0x18` `DMA_BLOCK_CFG`
- `+0x1C` `DMA_BYTES_DONE`
- `+0x20` `DMA_DEBUG`
- `+0x24` `DMA_CIPHERTEXT_BYTES_PRODUCED`

Gia tri config duoc ghi:

- `SRC_ADDR = 0x00000400`
- `DST_ADDR = 0x00002000`
- `LEN_BYTES = INPUT_LEN_ADDR`
- `MODE = 0x0000000D`
- `BLOCK_CFG = 0x00000020`
- `CONTROL = 0x1` (start)

### 5.3 Result layout trong DMEM (word offset)

- `word0`  = signature `0x44545843`
- `word1`  = `error_mask`
- `word2`  = `tx_status_before_start`
- `word3`  = `tx_status_after_done`
- `word4`  = `tx_bytes_done`
- `word5`  = `tx_ciphertext_bytes`
- `word6`  = `tx_poll_count`
- `word7`  = `tx_debug`
- `word8`  = `mode_echo`
- `word9`  = `input_len_echo`
- `word10` = TX output word 0
- `word11` = TX output word 1
- `word12` = TX output word 2
- `word13` = TX output word 3

### 5.4 Expected state

- `word0 = 0x44545843`
- `word1 = 0`
- `word2 = 0x000000d8`
- `word3 = 0x000000da`
- `word4 != 0` va align `16 byte`
- `word5 = word4`
- `word6 != 0`
- `word7 = 0`
- `word8 = 0x0000000D`
- vung `TX_DST_BASE_ADDR` khong duoc all-zero

### 5.5 Input policy

- `input1.txt` va cac file text thuong: chay `test_mmio_tx_only.c` + `test_bench`
- mode DMA: `COMPRESS_ONLY`
- du lieu di theo duong `DMEM -> Huffman TX -> DMEM`

## 6. Disassembly Notes for `testcase/test_mmio_dma.c`

### 6.1 Boot

| PC    | Hex      | Mnemonic |
|-------|----------|----------|
| 0x000 | 00008137 | `lui sp,0x8` |
| 0x004 | f0010113 | `addi sp,sp,-256` |
| 0x008 | 0040006f | `j 0x00c` |

### 6.2 Write DMA config

Generated assembly co the thay doi theo option compile, nhung instruction
class chinh van la RV32I co ban:

- `lui` de tao base MMIO `0x40000000`
- `lw` de doc `INPUT_LEN_ADDR`, `DMA_STATUS`, `DMA_BYTES_DONE`,
  `DMA_CIPHERTEXT_BYTES_PRODUCED`
- `sw` de ghi `SRC_ADDR`, `DST_ADDR`, `LEN_BYTES`, `MODE`, `BLOCK_CFG`,
  `CONTROL.start`
- `andi`, `beq`, `bne`, `bltu` de poll status va check timeout

### 6.3 Poll / collect result

Sau khi ghi `CONTROL.start`, chuong trinh:

1. loop doc `DMA_STATUS` cho den khi:
   - `error_sticky = 1`, hoac
   - da thay busy roi sau do `busy = 0` va `done_sticky = 1`, hoac
   - qua `MAX_POLLS`.
2. TX: doc `DMA_BYTES_DONE` va `DMA_CIPHERTEXT_BYTES_PRODUCED`
3. RX: doc `DMA_BYTES_DONE`
4. doc `DMA_DEBUG`
5. doc 4 word dau cua vung RX output
6. lap `error_mask`

`error_mask` hien tai dung cac bit:

- bit0: `tx_status_before_start != 0x98`
- bit1: `tx_status_after_done != 0x9a`
- bit2: TX length invalid hoac ciphertext length khong align 16 byte
- bit3: TX debug khac 0
- bit4: TX timeout
- bit5: ciphertext head all-zero
- bit6: RX status_before khong phai idle/done hop le
- bit7: `rx_status_after_done != 0x2a`
- bit8: `rx_bytes_done != input_len`
- bit9: RX debug khac 0
- bit10: RX timeout
- bit11: `CIPHERTEXT_BYTES_PRODUCED != TX_BYTES_DONE`
- bit12: input length bang 0

### 6.4 Write result words to DMEM[0..15]

| PC    | Hex      | Mnemonic |
|-------|----------|----------|
Chuong trinh ghi:

- signature
- error_mask
- status_before
- status_after
- bytes_done
- debug
- poll_count
- 4 word RX output head

roi nhay vao vong lap vo han de giu trang thai.

---

## 7. Checklist khi doi bai test

De tranh chay nham chuong trinh:

1. Compile dung file C:
   - `make compile C_SRC=<file>.c`
2. Dam bao `instruction.mem` dang la output ban muon.
3. Dam bao `rtl.f/tb.f` dang dung unified SoC mode, `tb.f` chi compile `test_bench`.
4. Chay:
   - `make drc`
   - `make all TESTNAME=<name> RUN_ARGS="+CASE_NAME=<name> +INPUT_FILE=<input>.txt"`
5. Kiem tra 4 instruction dau trong log:
   - MMIO test: bat dau bang `00008137`
   - Smoke sync: bat dau bang `00500093`

## 8. Flow khuyen nghi theo loai input

- `input1.txt` full loopback:
  - compile: `make compile C_SRC=test_mmio_dma.c`
  - run: `make all TESTNAME=dma_compress_aes_input1 RUN_ARGS="+CASE_NAME=dma_compress_aes_input1 +INPUT_FILE=input1.txt"`
  - policy: TX `COMPRESS_AES + whole_file`, RX decrypt/decode.

- `input1.txt` TX-only saving:
  - compile: `make compile C_SRC=test_mmio_tx_only.c`
  - run: `make all TESTNAME=tx_compress_only_input1 RUN_ARGS="+CASE_NAME=tx_compress_only_input1 +INPUT_FILE=input1.txt"`
  - policy: TX `COMPRESS_ONLY + whole_file`.

- `input4_cov.txt` TX-only log-like saving:
  - compile: `make compile C_SRC=test_mmio_tx_only.c`
  - run: `make all TESTNAME=tx_compress_only_input4_cov RUN_ARGS="+CASE_NAME=tx_compress_only_input4_cov +INPUT_FILE=input4_cov.txt"`
  - policy: TX `COMPRESS_ONLY + whole_file`.

- Full coverage:
  - command: `cd sim && ./run.csh cov && ./report.csh`
  - result hien tai: `32/32` PASS, closed DUT `95.59%`.
