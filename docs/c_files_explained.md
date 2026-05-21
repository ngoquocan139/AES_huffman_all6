# 13. C Program Test Spec

## 1. Purpose and scope

This document explains the C programs under `testcase/` that are compiled into
RV32I instruction memory for SoC simulation. It focuses on what each file does,
which inputs it consumes, which outputs it writes, how it drives DMA/MMIO, and
which result words or error bits the testbench should check.

The active SoC firmware path is:

```text
RV32I C program
  -> RV32I load/store instructions
  -> CPU DMEM or DMA MMIO address decode
  -> cpu_mmio_to_apb_bridge
  -> dma_regfile
  -> DMA TX/RX engines and private accelerator APB paths
```

All C programs are freestanding. They do not use libc, heap, interrupts, OS
services, or a trap handler. Each program sets `sp`, jumps to `main`, writes a
small result block into DMEM, then spins forever so the testbench can inspect
the final state.

## 2. C source inventory

| C file | Main role | Status |
|---|---|---|
| `testcase/test.c` | Core smoke program with fixed RV32I instructions | reference |
| `testcase/secure_storage_fw.h` | Firmware helper API for secure write/read/delete, metadata, IV, DMA polling | active |
| `testcase/test_mmio_dma_storage_table.c` | Secure-storage demo: write file 1, write file 3, read file 1 back | active baseline |
| `testcase/test_mmio_dma.c` | Direct DMA TX+RX loopback without metadata table | active legacy |
| `testcase/test_mmio_tx_only.c` | Direct TX-only benchmark, default mode `0xD` | active |
| `testcase/test_mmio_tx_only_aes_block.c` | Wrapper for `test_mmio_tx_only.c` with mode `0x1` | coverage |
| `testcase/test_mmio_tx_only_compress_block.c` | Wrapper for `test_mmio_tx_only.c` with mode `0x5` | coverage |
| `testcase/test_mmio_tx_apb_error.c` | Expected TX APB error-path program | coverage/debug |
| `testcase/test_mmio_tx_encoder_error.c` | Expected TX encoder error-path program | coverage/debug |
| `testcase/test_mmio_regfile_basic.c` | Legal DMA register read/write, IV readback, reset behavior | coverage |
| `testcase/test_mmio_regfile_negative.c` | Illegal register/config accesses and sticky error behavior | coverage |
| `testcase/test_mmio_mode_matrix.c` | Mode-to-status decode matrix | coverage |
| `testcase/test_mmio_rx_bad_length.c` | RX rejects invalid ciphertext length | coverage |
| `testcase/test_cpu_instruction_cov.c` | RV32I instruction coverage | coverage |
| `testcase/test_cpu_mem_forward_cov.c` | Memory-stage and forwarding coverage | coverage |
| `testcase/test_log_preprocess.c` | Older preprocessing comparison flow | deprecated/debug |
| `testcase/test_sensor_phi_preprocess_rv32.c` | RV32 preprocessing + TX compression experiment | deprecated/debug |

Files named `*_preprocess*` are not the main secure-storage demo anymore. Keep
them as debug/reference programs unless a testcase explicitly selects them.

## 3. Build profile

`sim/Makefile` compiles each selected C file into RV32I code:

```text
ASM compile : -march=rv32i -mabi=ilp32 -Os -S
ELF link    : -march=rv32i -mabi=ilp32 -O1 -nostdlib -ffreestanding -Ttext=0x0 -Wl,-e,_start
Objcopy     : ELF -> binary -> .mem
Output      : testcase/<name>.S, .elf, .bin, .mem
SoC input   : sim/instruction.mem
```

Typical command:

```bash
cd sim
make compile C_SRC=test_mmio_dma_storage_table.c
make all TESTNAME=dma_storage_table_input1_then_input3 RUN_ARGS="+CASE_NAME=dma_storage_table_input1_then_input3 +INPUT_FILE=input1.txt +INPUT_FILE2=input3.txt"
```

Important build rules:

- Compile the C file before running the matching testcase.
- The `.mem` copied to `sim/instruction.mem` is what `imem_sync` executes.
- If compiler version or optimization changes, exact PC/disassembly can change,
  but the MMIO protocol and result-word contract should stay the same.

## 4. Common software-visible memory map

All addresses are byte addresses. All result words and DMA registers are
32-bit little-endian words unless stated otherwise.

| Address or range | Name | Owner | Format | Meaning |
|---:|---|---|---|---|
| `0x0000_0000` | `RESULT_BASE_ADDR` | RV32I firmware | 32-bit words | Result/debug block for testbench |
| `0x0000_0040` | `INPUT_LEN_ADDR` / `INPUT1_LEN_ADDR` | testbench writes, firmware reads | 32-bit byte count | Primary input length |
| `0x0000_0044` | `INPUT2_LEN_ADDR` / `PREPROC_LEN_ADDR` | testbench or firmware | 32-bit byte count | Secondary input length or preprocessed length |
| `0x0000_0100` | `SECURE_META_BASE_ADDR` | secure-storage firmware | metadata records | Slot metadata table |
| `0x0000_01F0` | `SECURE_IV_COUNTER_ADDR` | secure-storage firmware | 32-bit counter | IV/version counter |
| `0x0000_0200..0x0000_03FF` | misc CPU scratch | RV32I tests | bytes/halves/words | CPU coverage scratch area |
| `0x0000_2000` | `SRC_BASE_ADDR` / input1 | testbench writes, DMA reads | byte array | Primary plaintext source |
| `0x0000_3000` | input2 | testbench writes, DMA reads | byte array | Secondary plaintext source |
| `0x0000_4000` | TX output / cipher slot 0 | DMA writes | byte stream | TX ciphertext/compressed stream |
| `0x0000_5000` | cipher slot 1 | DMA writes | byte stream | Second secure-storage ciphertext slot |
| `0x0000_6000` | RX output | DMA writes | byte array | Restored plaintext destination |
| `0x4000_0000..0x4000_00FF` | DMA MMIO window | CPU via APB bridge | 32-bit registers | DMA software control plane |

The direct DMA tests normally use:

```text
plaintext source  = 0x0000_2000
TX destination    = 0x0000_4000
RX destination    = 0x0000_6000
```

The secure-storage testcase uses two ciphertext slots:

```text
slot 0 = 0x0000_4000
slot 1 = 0x0000_5000
slot size = 0x1000 bytes
```

## 5. Common DMA MMIO register contract

The C files use `volatile uint32_t *` macros for DMA registers. This is
intentional: every read/write must become an RV32I `lw`/`sw` transaction and
must not be optimized away by the compiler.

Base address:

```text
DMA_BASE_ADDR = 0x4000_0000
```

| Offset | Register | Access from C | Width | Data format and function |
|---:|---|---|---:|---|
| `0x00` | `DMA_CONTROL` | write | 32 bit | Pulse-style control. Bit0 `start`, bit1 `soft_reset`, bit2 `clear_done`, bit3 `clear_error`. Common writes are `0x1` start, `0x8` clear error, `0x0C` clear done+error, `0x2` soft reset. |
| `0x04` | `DMA_STATUS` | read | 32 bit | Status. Bit0 `busy`, bit1 `done_sticky`, bit2 `error_sticky`, bit3 `cfg_valid`, bits `[5:4]` direction echo, bits `[7:6]` policy echo from mode bits `[3:2]`. |
| `0x08` | `DMA_SRC_ADDR` | read/write | 32 bit | DMEM byte address where DMA reads input. Current engines expect aligned DMEM addresses. |
| `0x0C` | `DMA_DST_ADDR` | read/write | 32 bit | DMEM byte address where DMA writes output. |
| `0x10` | `DMA_LEN_BYTES` | read/write | 32 bit | Number of input bytes requested by software. TX uses plaintext length. RX uses ciphertext stream length. |
| `0x14` | `DMA_MODE` | read/write | 32 bit | Mode selector. `0x1` TX AES block, `0x5` TX compress-only block, `0x9` TX AES whole-file, `0xD` TX compress-only whole-file, `0x2` RX. Reserved values should raise error. |
| `0x18` | `DMA_BLOCK_CFG` | read/write | 32 bit | Block size/config. Current C tests use `0x20` (32 bytes). Whole-file modes still require a valid nonzero config. |
| `0x1C` | `DMA_BYTES_DONE` | read | 32 bit | Number of bytes completed/reported by DMA. TX reports output stream bytes in current tests. RX should report restored plaintext bytes. |
| `0x20` | `DMA_DEBUG` | read | 32 bit | Debug/error code. Normal path expects `0`. Error tests check bits `[11:4]`, for example `0x20`, `0x30`, `0x60`. |
| `0x24` | `DMA_CIPHERTEXT_BYTES_PRODUCED` | read | 32 bit | TX-produced stream length. Direct TX/RX code uses it as RX input length. |
| `0x28` | `DMA_IV0` | read/write | 32 bit | AES-CBC IV word 0. |
| `0x2C` | `DMA_IV1` | read/write | 32 bit | AES-CBC IV word 1. |
| `0x30` | `DMA_IV2` | read/write | 32 bit | AES-CBC IV word 2. |
| `0x34` | `DMA_IV3` | read/write | 32 bit | AES-CBC IV word 3. |

Common expected idle/done status values:

| Mode | Meaning | Idle/configured status | Done status |
|---:|---|---:|---:|
| `0x1` | TX `COMPRESS_AES`, block mode | `0x18` | `0x1A` |
| `0x5` | TX `COMPRESS_ONLY`, block mode | `0x58` | `0x5A` |
| `0x9` | TX `COMPRESS_AES`, whole-file mode | `0x98` | `0x9A` |
| `0xD` | TX `COMPRESS_ONLY`, whole-file mode | `0xD8` | `0xDA` |
| `0x2` | RX | `0x28` | `0x2A` |

## 6. Common RV32I DMA software flow

The phrase "RV32I software flow: configure, start, poll, read result" refers to
the same pattern implemented by `secure_run_dma()`, `run_dma()`, and
`run_tx_dma()`.

The pattern is:

1. Firmware writes `DMA_SRC_ADDR`, `DMA_DST_ADDR`, `DMA_LEN_BYTES`,
   `DMA_MODE`, and `DMA_BLOCK_CFG`.
2. Firmware optionally writes `DMA_IV0..DMA_IV3` before AES-enabled TX/RX.
3. Firmware reads `DMA_STATUS` before start and expects an idle/config-valid
   value such as `0x98`, `0xD8`, or `0x28`.
4. Firmware writes `DMA_CONTROL = 0x1`.
5. Firmware loops on `DMA_STATUS`.
6. The loop exits when error bit2 is set, or when done bit1 is set while busy
   bit0 is clear and progress has been observed, or when the poll counter
   reaches `MAX_POLLS`.
7. Firmware reads `DMA_BYTES_DONE`, `DMA_CIPHERTEXT_BYTES_PRODUCED`, and
   `DMA_DEBUG`.
8. Firmware writes a compact result block into DMEM word0..N.

Typical C polling condition:

```text
while true:
  status = DMA_STATUS
  if status[0] busy: saw_busy = 1
  if status[2] error: break
  if !status[0] and status[1] and (saw_busy or progress != 0): break
  polls++
  if polls >= MAX_POLLS: break
```

TX progress normally reads `DMA_CIPHERTEXT_BYTES_PRODUCED`. RX progress normally
reads `DMA_BYTES_DONE`.

## 7. Result word convention

Most C programs write result words at `DMEM[0x0 + 4*idx]`.

Common convention:

| Word | Usual field | Format |
|---:|---|---|
| `0` | signature | 32-bit tag identifying the program |
| `1` | error mask | 32-bit bitmask, `0` means pass |
| `2..N` | testcase-specific status/data | 32-bit words |

The testbench should treat `word1 == 0` as the primary firmware pass
condition, then use the remaining words for diagnosis.

## 8. `testcase/test.c` - RV32I smoke program

### Function

This is the simplest reference program for the sync core. It is not a DMA test.
It proves that the core can execute arithmetic, branches, load/store, and an
infinite spin loop.

### Inputs

None. It does not depend on testbench-loaded text input.

### Outputs

It writes to DMEM address `0x0`.

Expected final behavior:

| Item | Expected |
|---|---:|
| `x1` | `5` |
| `x2` | `10` |
| `x3` | `15` |
| `x4` | `0x1C` (sum `0..7`) |
| `DMEM[0]` | normally `0x1D` after final increment/store |

### Instruction-level flow

The program uses fixed `.word` instructions:

| Idx | Hex | Mnemonic | Function |
|---:|---:|---|---|
| 0 | `00500093` | `addi x1,x0,5` | Load constant 5 |
| 1 | `00a00113` | `addi x2,x0,10` | Load constant 10 |
| 2 | `002081b3` | `add x3,x1,x2` | Add 5+10 |
| 3 | `00302023` | `sw x3,0(x0)` | Store 15 to DMEM word0 |
| 4 | `00000213` | `addi x4,x0,0` | Clear sum |
| 5 | `00000293` | `addi x5,x0,0` | Clear loop index |
| 6 | `00800313` | `addi x6,x0,8` | Loop limit |
| 7 | `00520233` | `add x4,x4,x5` | Accumulate |
| 8 | `00128293` | `addi x5,x5,1` | Increment index |
| 9 | `fe62cce3` | `blt x5,x6,loop` | Loop while `x5 < 8` |
| 10 | `00402023` | `sw x4,0(x0)` | Store sum |
| 11 | `00002383` | `lw x7,0(x0)` | Load sum |
| 12 | `00138393` | `addi x7,x7,1` | Add one |
| 13 | `00702023` | `sw x7,0(x0)` | Store final value |
| 14 | `fe000ae3` | `beq x0,x0,spin` | Infinite loop |

## 9. `testcase/secure_storage_fw.h` - secure-storage firmware API

### Function

This header is compiled into C test programs that include it. It is the active
firmware layer above the DMA register file. It provides a software storage
table:

- assign a `file_id` to a ciphertext slot;
- generate and store a deterministic IV;
- configure and run DMA TX for secure write;
- restore IV and run DMA RX for secure read;
- keep metadata in DMEM so the second operation can find the correct slot.

The header does not implement encryption itself. It only programs the DMA and
stores software metadata.

### Public API

| Function | Inputs | Outputs | Function |
|---|---|---|---|
| `secure_storage_init()` | none | clears metadata, seeds IV counter | Initializes two metadata records and `SECURE_IV_COUNTER_ADDR`. |
| `secure_write(file_id, plain_addr, plain_len, result)` | file ID, plaintext DMEM address, plaintext byte length, result pointer | return code, `secure_dma_result_t`, metadata commit | Allocates/reuses a slot, creates IV, runs TX mode `0x9`, commits ciphertext length and valid bit. |
| `secure_read(file_id, dst_addr, result)` | file ID, plaintext destination, result pointer | return code, `secure_dma_result_t` | Finds metadata, restores IV, runs RX mode `0x2`, verifies restored byte count. |
| `secure_delete(file_id)` | file ID | return code | Clears metadata slot if found. |
| `secure_find_record(file_id)` | file ID | slot index or `0xFFFFFFFF` | Scans valid metadata records. |
| `secure_record_count()` | none | count | Counts valid metadata records. |

### Return codes

| Code | Name | Meaning |
|---:|---|---|
| `0` | `SECURE_OK` | Operation completed. |
| `1` | `SECURE_ERR_BAD_ARG` | Invalid `file_id`, length, address, or result pointer. |
| `2` | `SECURE_ERR_NO_SLOT` | No metadata slot is available. |
| `3` | `SECURE_ERR_DMA_TIMEOUT` | DMA did not finish before `SECURE_MAX_POLLS`. |
| `4` | `SECURE_ERR_DMA_ERROR` | DMA reported sticky error. |
| `5` | `SECURE_ERR_CIPHER_LEN` | TX produced invalid ciphertext length. |
| `6` | `SECURE_ERR_NOT_FOUND` | `secure_read/delete` could not find the `file_id`. |
| `7` | `SECURE_ERR_READ_LEN` | RX restored byte count did not match metadata plaintext length. |

### `secure_dma_result_t` data format

Each field is `uint32_t`.

| Field | Meaning |
|---|---|
| `status_before` | `DMA_STATUS` read after config and before `CONTROL.start`. |
| `status_after` | Final `DMA_STATUS` after polling. |
| `bytes_done` | Final `DMA_BYTES_DONE`. |
| `ciphertext_bytes` | Final `DMA_CIPHERTEXT_BYTES_PRODUCED`. |
| `debug_after` | Final `DMA_DEBUG`. |
| `polls` | Number of polling iterations. |

### Metadata data format

Metadata starts at `0x0000_0100`. There are 2 records. Each record is 16 words
= 64 bytes. Slot `n` starts at:

```text
record_addr = 0x0000_0100 + (n << 6)
```

| Word | Field | Width | Format / meaning |
|---:|---|---:|---|
| `0` | `valid` | 32 bit | `1` only after TX completed and metadata commit succeeded. |
| `1` | `file_id` | 32 bit | Software file ID. `0` is rejected by `secure_write`. |
| `2` | `plain_addr` | 32 bit | Original plaintext DMEM byte address. |
| `3` | `cipher_addr` | 32 bit | Ciphertext slot DMEM byte address. |
| `4` | `plain_len` | 32 bit | Original plaintext byte count. |
| `5` | `cipher_len` | 32 bit | TX-produced ciphertext/transport byte count. |
| `6` | `mode` | 32 bit | TX mode, currently `0x9`. |
| `7` | `iv0` | 32 bit | AES-CBC IV word 0. |
| `8` | `iv1` | 32 bit | AES-CBC IV word 1. |
| `9` | `iv2` | 32 bit | AES-CBC IV word 2. |
| `10` | `iv3` | 32 bit | AES-CBC IV word 3. |
| `11` | `version` | 32 bit | IV counter value used for this record. |
| `12` | `flags` | 32 bit | Reserved, currently `0`. |
| `13..15` | reserved | 32 bit each | Cleared by init/delete. |

### IV generation and restore

The firmware keeps a counter at `0x0000_01F0`, seeded to `0x31415926`.
`secure_prepare_record()` increments the counter, derives four 32-bit IV words
from `plain_len`, `plain_addr`, `cipher_addr`, `file_id`, and the counter, then
writes the IV to both metadata and `DMA_IV0..DMA_IV3`.

`secure_restore_iv_from_record()` reads metadata words `iv0..iv3` and writes
the exact same values back to `DMA_IV0..DMA_IV3` before RX. This is required so
AES-CBC decrypt uses the same IV used by TX.

### DMA run behavior

`secure_run_dma()` does the common DMA flow:

1. clears the software result structure;
2. writes `DMA_CONTROL = 0x0C` to clear done/error sticky bits;
3. writes `SRC_ADDR`, `DST_ADDR`, `LEN_BYTES`, `MODE`, and `BLOCK_CFG`;
4. records `status_before`;
5. writes `DMA_CONTROL = 0x1` to start;
6. polls up to `SECURE_MAX_POLLS = 2_000_000`;
7. reads `bytes_done`, `ciphertext_bytes`, and `debug_after`;
8. returns `SECURE_OK`, timeout, or DMA error.

## 10. `testcase/test_mmio_dma_storage_table.c` - secure-storage demo

### Function

This is the current main firmware demo. It proves the full software-managed
secure-storage flow:

```text
secure_storage_init()
secure_write(file_id=1, input1 at 0x2000)
secure_write(file_id=3, input2 at 0x3000)
secure_read(file_id=1, restore to 0x6000)
write result words
spin forever
```

The important behavior is that the read does not simply decode the last TX
output. It selects `file_id=1` through metadata and therefore restores slot 0
even after file 3 has been written to slot 1.

### Inputs

| Input | Address | Width/format | Producer | Meaning |
|---|---:|---|---|---|
| `input1_len` | `0x0000_0040` | 32-bit byte count | testbench | Length of primary input file. |
| `input2_len` | `0x0000_0044` | 32-bit byte count | testbench | Length of secondary input file. |
| input1 bytes | `0x0000_2000` | byte array | testbench | Plaintext for `file_id=1`. |
| input2 bytes | `0x0000_3000` | byte array | testbench | Plaintext for `file_id=3`. |

### Outputs

| Output | Address | Width/format | Meaning |
|---|---:|---|---|
| metadata slot 0 | `0x0000_0100` | 16 x 32-bit words | Record for `file_id=1`. |
| metadata slot 1 | `0x0000_0140` | 16 x 32-bit words | Record for `file_id=3`. |
| ciphertext slot 0 | `0x0000_4000` | byte stream | TX output for input1. |
| ciphertext slot 1 | `0x0000_5000` | byte stream | TX output for input2. |
| RX output | `0x0000_6000` | byte array | Restored plaintext for selected file 1. |
| result words | `0x0000_0000` | 16 x 32-bit words | Test result block. |

### Register usage

TX1 and TX2 use:

```text
MODE      = 0x9
BLOCK_CFG = 0x20
IV0..IV3  = generated by firmware
```

RX uses:

```text
MODE      = 0x2
BLOCK_CFG = 0x20
IV0..IV3  = restored from selected metadata record
```

### Result word layout

| Word | Field | Expected/meaning |
|---:|---|---|
| `0` | signature | `0x53544F52` (`STOR`) |
| `1` | error mask | `0` means firmware checks passed |
| `2` | TX1 `status_before` | expected `0x98` |
| `3` | TX1 `status_after` | expected `0x9A` |
| `4` | TX1 `bytes_done` | nonzero, 16-byte aligned |
| `5` | TX1 `ciphertext_bytes` | nonzero, 16-byte aligned |
| `6` | TX1 `polls` | `< SECURE_MAX_POLLS` |
| `7` | RX1 `status_before` | expected `0x28` or already-done `0x2A` depending previous sticky state |
| `8` | RX1 `status_after` | expected `0x2A` |
| `9` | RX1 `bytes_done` | expected `input1_len` |
| `10` | RX1 `debug_after` | expected `0` |
| `11` | RX1 `polls` | `< SECURE_MAX_POLLS` |
| `12` | TX2 `ciphertext_bytes` | nonzero, 16-byte aligned |
| `13` | input2 length echo | equals `input2_len` |
| `14` | selected file ID | expected `1` |
| `15` | total metadata records | expected `2` |

### Error mask bits

| Bit | Meaning |
|---:|---|
| `0` | `input1_len == 0` |
| `1` | `input2_len == 0` |
| `2` | TX1 status before start mismatch |
| `3` | TX1 final status mismatch |
| `4` | TX1 ciphertext length invalid or not 16-byte aligned |
| `5` | TX1 output exceeds slot capacity |
| `6` | TX1 timeout |
| `7` | TX2 status before start mismatch |
| `8` | TX2 final status mismatch |
| `9` | TX2 ciphertext length invalid or not 16-byte aligned |
| `10` | TX2 timeout |
| `11` | Metadata selected slot for `file_id=1` is not slot 0 |
| `12` | RX1 status before start mismatch |
| `13` | RX1 final status mismatch |
| `14` | RX1 restored byte count mismatch |
| `15` | RX1 timeout |
| `16` | `secure_write(1, ...)` returned nonzero |
| `17` | Slot 0 ciphertext address mismatch |
| `18` | `secure_write(3, ...)` returned nonzero |
| `19` | Slot 1 ciphertext address mismatch |
| `20` | IV collision between slot 0 and slot 1 |
| `21` | `secure_read(1, ...)` returned nonzero |

### Expected full-test behavior

Pass means:

```text
result word1 == 0
selected_file_id == 1
total_records == 2
DMA start count == 3
RX output at 0x6000 matches input1 bytes
```

## 11. `testcase/test_mmio_dma.c` - direct DMA TX/RX loopback

### Function

This is a direct data-plane loopback test without the metadata table:

```text
input at 0x2000
TX COMPRESS_AES whole-file to 0x4000
RX decode/decrypt from 0x4000 to 0x6000
write result words
```

It is useful for debugging DMA, Huffman TX, AES-CBC TX, RX parser/depacker,
decoder, and AES-CBC RX without involving secure-storage metadata.

### Inputs

| Input | Address | Format | Meaning |
|---|---:|---|---|
| `input_len` | `0x0000_0040` | 32-bit byte count | Number of plaintext bytes. |
| plaintext | `0x0000_2000` | byte array | Source bytes loaded by testbench. |

### Outputs

| Output | Address | Format | Meaning |
|---|---:|---|---|
| TX output | `0x0000_4000` | byte stream | Huffman+AES transport stream. |
| RX output | `0x0000_6000` | byte array | Restored plaintext. |
| result words | `0x0000_0000` | 16 x 32-bit words | Status and output-head debug. |

### DMA configuration

TX:

```text
SRC_ADDR  = 0x0000_2000
DST_ADDR  = 0x0000_4000
LEN_BYTES = input_len
MODE      = 0x9
BLOCK_CFG = 0x20
```

RX:

```text
SRC_ADDR  = 0x0000_4000
DST_ADDR  = 0x0000_6000
LEN_BYTES = DMA_CIPHERTEXT_BYTES_PRODUCED
MODE      = 0x2
BLOCK_CFG = 0x20
```

The program writes a deterministic IV before TX and reuses the same IV for RX.

### Result word layout

| Word | Field | Expected/meaning |
|---:|---|---|
| `0` | signature | `0x44525831` (`DRX1`) |
| `1` | error mask | `0` means pass |
| `2` | TX `status_before` | `0x98` |
| `3` | TX `status_after` | `0x9A` |
| `4` | TX `bytes_done` | nonzero, 16-byte aligned |
| `5` | TX `ciphertext_bytes` | should equal word4 |
| `6` | TX polls | `< MAX_POLLS` |
| `7` | RX `status_before` | `0x28` or `0x2A` |
| `8` | RX `status_after` | `0x2A` |
| `9` | RX `bytes_done` | equals `input_len` |
| `10` | RX debug | expected `0` |
| `11` | RX polls | `< MAX_POLLS` |
| `12..15` | first four RX output words | non-authoritative debug sample |

### Error mask bits

| Bit | Meaning |
|---:|---|
| `0` | TX status before start is not `0x98` |
| `1` | TX status after done is not `0x9A` |
| `2` | TX length invalid or not 16-byte aligned |
| `3` | TX debug is nonzero |
| `4` | TX timeout |
| `5` | First four TX output words are all zero |
| `6` | RX status before start is not valid |
| `7` | RX status after done is not `0x2A` |
| `8` | RX restored byte count does not equal input length |
| `9` | RX debug is nonzero |
| `10` | RX timeout |
| `11` | `DMA_CIPHERTEXT_BYTES_PRODUCED != DMA_BYTES_DONE` after TX |
| `12` | Input length is zero |

## 12. `testcase/test_mmio_tx_only.c` - direct TX-only benchmark

### Function

This program runs only the TX side and writes the compressed/cipher output to
DMEM. It is used for output length, saving-ratio, and TX datapath coverage when
RX is not part of the testcase.

Default mode is `0xD` (`COMPRESS_ONLY + whole-file`). Two wrapper files change
the mode at compile time.

### Inputs

| Input | Address | Format | Meaning |
|---|---:|---|---|
| `input_len` | `0x0000_0040` | 32-bit byte count | Number of bytes to compress. |
| plaintext | `0x0000_2000` | byte array | Source bytes loaded by testbench. |

### Outputs

| Output | Address | Format | Meaning |
|---|---:|---|---|
| TX output | `0x0000_4000` | byte stream | Compressed/cipher transport stream. |
| result words | `0x0000_0000` | 14 x 32-bit words | TX status, length, mode echo, output head. |

### Mode variants

| Source file | Compile-time `TEST_MODE_TX` | Expected idle | Expected done | Meaning |
|---|---:|---:|---:|---|
| `test_mmio_tx_only.c` | `0xD` | `0xD8` | `0xDA` | whole-file compress-only |
| `test_mmio_tx_only_aes_block.c` | `0x1` | `0x18` | `0x1A` | block COMPRESS_AES |
| `test_mmio_tx_only_compress_block.c` | `0x5` | `0x58` | `0x5A` | block COMPRESS_ONLY |

### Result word layout

| Word | Field | Expected/meaning |
|---:|---|---|
| `0` | signature | `0x44545843` (`DTXC`) |
| `1` | error mask | `0` means pass |
| `2` | TX `status_before` | mode-dependent idle value |
| `3` | TX `status_after` | mode-dependent done value |
| `4` | TX `bytes_done` | nonzero, 16-byte aligned |
| `5` | TX `ciphertext_bytes` | equals word4 |
| `6` | TX polls | `< MAX_POLLS` |
| `7` | TX debug | expected `0` |
| `8` | mode echo | `0xD`, `0x1`, or `0x5` |
| `9` | input length echo | equals input length |
| `10..13` | first four TX output words | should not all be zero |

### Error mask bits

| Bit | Meaning |
|---:|---|
| `0` | Input length is zero |
| `1` | TX status before start mismatch |
| `2` | TX final status mismatch |
| `3` | TX byte count invalid or not 16-byte aligned |
| `4` | `ciphertext_bytes != bytes_done` |
| `5` | `DMA_DEBUG != 0` |
| `6` | TX timeout |
| `7` | First four output words are all zero |

## 13. TX expected-error C programs

### `testcase/test_mmio_tx_apb_error.c`

Function:

- Configures TX whole-file AES mode `0x9`.
- Uses length `0x20`.
- Starts DMA and expects an error-sticky status.
- Checks that `DMA_DEBUG[11:4] == 0x30`.

Inputs:

| Input | Address | Format |
|---|---:|---|
| source bytes | `0x0000_2000` | byte array, content depends on testcase wrapper |

Outputs:

| Word | Field | Expected/meaning |
|---:|---|---|
| `0` | signature | `0x54584552` (`TXER`) |
| `1` | error mask | `0` means expected error was observed correctly |
| `2` | status before | `0x98` |
| `3` | status after | bit2 error set |
| `4` | bytes done | debug value, no pass requirement except code-specific checks |
| `5` | debug after | bits `[11:4] == 0x30` |
| `6` | polls | `< 100000` |

Error bits:

| Bit | Meaning |
|---:|---|
| `0` | status before is not `0x98` |
| `1` | final status did not set error bit |
| `2` | debug class is not `0x30` |
| `3` | timeout |

### `testcase/test_mmio_tx_encoder_error.c`

Function is the same shape as `test_mmio_tx_apb_error.c`, but it uses
`DMA_LEN_BYTES = 0x240` and expects encoder error class:

```text
DMA_DEBUG[11:4] == 0x60
```

The result layout and error bits are identical to `test_mmio_tx_apb_error.c`,
except word5 should encode debug class `0x60`.

## 14. DMA register-file C programs

### `testcase/test_mmio_regfile_basic.c`

Function:

- Checks reset status.
- Writes legal config registers.
- Writes and reads back AES IV registers.
- Clears done/error, then issues soft reset.
- Checks reset returns selected registers to expected values.

Inputs:

None from the testbench. The program writes all needed MMIO values itself.

Register writes:

```text
SRC_ADDR  = 0x00002000
DST_ADDR  = 0x00004000
LEN_BYTES = 0x00000040
MODE      = 0xD
BLOCK_CFG = 0x20
IV0       = 0x11223344
IV1       = 0x55667788
IV2       = 0x99AABBCC
IV3       = 0xDDEEFF00
CONTROL   = 0x0C, then 0x02
```

Result words:

| Word | Field | Expected |
|---:|---|---:|
| `0` | signature | `0x52454731` (`REG1`) |
| `1` | error mask | `0` |
| `2` | status reset | `0x0` |
| `3` | status after config | `0xD8` |
| `4` | status after soft reset | `0x0` |
| `5` | mode readback | `0xD` |
| `6` | block readback | `0x20` |
| `7` | IV0 readback | `0x11223344` |
| `8` | IV1 readback | `0x55667788` |
| `9` | IV2 readback | `0x99AABBCC` |
| `10` | IV3 readback | `0xDDEEFF00` |

Error bits:

| Bit | Meaning |
|---:|---|
| `0` | reset status is not zero |
| `1` | configured status is not `0xD8` |
| `2` | mode readback mismatch |
| `3` | block readback mismatch |
| `4..7` | IV0..IV3 readback mismatch |
| `8` | status after soft reset is not zero |
| `9` | mode not cleared after reset |
| `10` | block config did not retain default `0x20` after reset |
| `11` | IV registers not cleared after reset |

### `testcase/test_mmio_regfile_negative.c`

Function:

Exercises illegal software actions and verifies `error_sticky` behavior.

Inputs:

None.

Negative cases:

| Case | C action | Expected |
|---|---|---|
| bad start | write `CONTROL=0x1` before valid config | `STATUS[2]` set |
| read-only status write | write `DMA_STATUS=0xFFFFFFFF` | `STATUS[2]` set |
| invalid address | write to `DMA_BASE+0xFC` | `STATUS[2]` set |
| reserved mode | write `DMA_MODE=0x10` | `STATUS[2]` set and `DMA_MODE` remains `0` |
| bad block config | set `BLOCK_CFG=0`, then start | `STATUS[2]` set |
| partial byte store | byte-write `0xFF` to mode low byte | mode remains `0xD` |
| write read-only bytes done | write `DMA_BYTES_DONE=1` | `STATUS[2]` set |
| write read-only debug | write `DMA_DEBUG=1` | `STATUS[2]` set |

Result words:

| Word | Field |
|---:|---|
| `0` | signature `0x4E454731` (`NEG1`) |
| `1` | error mask |
| `2` | status after bad start |
| `3` | status after read-only status write |
| `4` | status after invalid address |
| `5` | status after reserved mode |
| `6` | block config after bad config write |
| `7` | mode after partial store |
| `8` | status after bad block start |

Error bits:

| Bit | Meaning |
|---:|---|
| `0` | bad start did not set error |
| `1` | read-only `STATUS` write did not set error |
| `2` | invalid APB address did not set error |
| `3` | reserved mode did not set error |
| `4` | reserved mode incorrectly changed `DMA_MODE` |
| `5` | bad block start did not set error |
| `6` | block readback after bad config was not zero |
| `7` | partial byte store unexpectedly changed mode |
| `8` | write to `DMA_BYTES_DONE` did not set error |
| `9` | write to `DMA_DEBUG` did not set error |

### `testcase/test_mmio_mode_matrix.c`

Function:

Verifies that `DMA_MODE` values decode into the expected `DMA_STATUS` fields
after valid source/destination/length/block config is present.

Inputs:

None.

Common config:

```text
SRC_ADDR  = 0x00002000
DST_ADDR  = 0x00004000
LEN_BYTES = 0x20
BLOCK_CFG = 0x20
```

Expected status function:

```text
direction = mode[1:0]
cfg_valid = 1 only for direction 1 (TX) or 2 (RX)
status = cfg_valid<<3 | direction<<4 | mode[3:2]<<6
```

Result words:

| Word | Field | Expected |
|---:|---|---:|
| `0` | signature | `0x4D4F4445` (`MODE`) |
| `1` | error mask | `0` |
| `2` | status for mode `0x1` | `0x18` |
| `3` | status for mode `0x5` | `0x58` |
| `4` | status for mode `0x9` | `0x98` |
| `5` | status for mode `0xD` | `0xD8` |
| `6` | status for mode `0x2` | `0x28` |
| `7` | status for mode `0x0` | `0x00` |
| `8` | status for mode `0x3` | `0x30` |
| `9` | status for reserved mode `0x10` | error bit set |

Error bits:

| Bit | Meaning |
|---:|---|
| `0` | mode `0x1` status mismatch |
| `1` | mode `0x5` status mismatch |
| `2` | mode `0x9` status mismatch |
| `3` | mode `0xD` status mismatch |
| `4` | mode `0x2` status mismatch |
| `5` | mode `0x0` status mismatch |
| `6` | mode `0x3` status mismatch |
| `7` | reserved mode did not set error |

## 15. `testcase/test_mmio_rx_bad_length.c` - RX invalid length

### Function

This program verifies the RX front-end rejects an invalid ciphertext length.
The input length is hardcoded to 4 bytes, which is not a valid AES-CBC
ciphertext stream length for this system.

### Inputs

The program does not read `INPUT_LEN_ADDR`. It assumes any bytes at
`0x0000_2000` are irrelevant because length validation should fail first.

### DMA configuration

```text
SRC_ADDR  = 0x0000_2000
DST_ADDR  = 0x0000_4000
LEN_BYTES = 0x00000004
MODE      = 0x2
BLOCK_CFG = 0x20
```

### Outputs and result words

| Word | Field | Expected |
|---:|---|---|
| `0` | signature | `0x52584552` (`RXER`) |
| `1` | error mask | `0` |
| `2` | status before | `0x28` |
| `3` | status after | bit2 error set |
| `4` | bytes done | `0` |
| `5` | debug after | bits `[11:4] == 0x20` |
| `6` | polls | `< 100000` |

Error bits:

| Bit | Meaning |
|---:|---|
| `0` | status before is not `0x28` |
| `1` | final status did not set error bit |
| `2` | `bytes_done != 0` |
| `3` | debug class is not `0x20` |
| `4` | timeout |

## 16. CPU coverage C programs

### `testcase/test_cpu_instruction_cov.c`

Function:

Exercises RV32I instruction classes that may not all appear in DMA firmware:

- R-type ALU: `add`, `sub`, `sll`, `slt`, `sltu`, `xor`, `srl`, `sra`,
  `or`, `and`.
- I-type ALU: `addi`, `slti`, `sltiu`, `xori`, `ori`, `andi`, `slli`,
  `srli`, `srai`.
- Loads/stores: `sw`, `sh`, `sb`, `lbu`, `lb`, `lhu`, `lh`.
- Branch/jump: `beq`, `bne`, `blt`, `bge`, `bltu`, `bgeu`, `jalr`.
- Upper immediate: `lui`.

Inputs:

None.

Scratch memory:

```text
0x0000_0100..0x0000_0106
```

Result words:

| Word | Field | Expected |
|---:|---|---:|
| `0` | signature | `0x43505543` (`CPUC`) |
| `1` | error mask | `0x00000000` |
| `2` | `r_type_mix` | `0xCD79BDFF` |
| `3` | `mem_mix` | `0x0000E595` |
| `4` | `branch_score` | `0x0000003F` |
| `5` | `i_type_mix` | nonzero, current baseline `0x00000874` |

Error bits:

| Bit | Meaning |
|---:|---|
| `0` | R-type mix mismatch |
| `1` | I-type mix is zero |
| `2` | branch score mismatch |
| `3` | load/store result mismatch |
| `4` | LUI result mismatch |
| `5` | JALR control-flow mismatch |

### `testcase/test_cpu_mem_forward_cov.c`

Function:

Exercises memory byte/half/word offsets, signed/unsigned loads, misaligned
MEM-stage branches, and forwarding paths. This program is for CPU RTL
coverage, not DMA.

Inputs:

None.

Scratch memory:

```text
0x0000_0300..0x0000_0347
```

Result words:

| Word | Field | Expected/meaning |
|---:|---|---|
| `0` | signature | `0x43505548` (`CPUH`) |
| `1` | error mask | `0` |
| `2` | `mem_error` | `0` |
| `3` | `fwd_mix` | nonzero forwarding mix |

Error bits:

| Bit | Meaning |
|---:|---|
| `0` | Memory offset/sign-extension check failed |
| `1` | Forwarding mix is zero |

The code intentionally executes misaligned `sh`, `sw`, `lh`, and `lw` to cover
MEM-stage RTL branches. The current core does not use a full trap flow here, so
the test expects the program to keep running and publish a clean signature.

## 17. Deprecated preprocessing C programs

### `testcase/test_log_preprocess.c`

Function:

This older program compares raw text TX length against a preprocessed buffer
TX length. It uses fixed waits instead of the newer robust polling loop, so it
is not the recommended secure-storage demo.

Inputs:

| Input | Address | Format |
|---|---:|---|
| raw input length | `0x0000_0040` | 32-bit byte count |
| preprocessed length | `0x0000_0044` | 32-bit byte count |
| raw input | `0x0000_0400` | byte array |
| preprocessed input | `0x0000_2000` | byte array |

Outputs:

| Output | Address | Meaning |
|---|---:|---|
| raw TX output | `0x0000_4000` | TX output for raw input |
| preprocessed TX output | `0x0000_6000` | TX output for preprocessed input |
| result words | `0x0000_0000` | 16-word comparison block |

Result word highlights:

| Word | Field |
|---:|---|
| `0` | signature `0x4C505231` (`LPR1`) |
| `1` | error mask |
| `2` | raw input length |
| `6` | raw ciphertext bytes |
| `7` | preprocessed length |
| `12` | preprocessed ciphertext bytes |
| `15` | `raw_cipher_bytes - pre_cipher_bytes` |

### `testcase/test_sensor_phi_preprocess_rv32.c`

Function:

This experimental program parses CSV-like sensor/PHI records on RV32I, emits a
compact binary format, then runs TX on both raw and compact data to compare
output sizes.

Input format:

```text
delta_ms,patient_id,encounter_id,device_id,bed_id,red,ir,spo2_x10,hr,rr,alert_flags
```

Binary output format:

| Offset in record | Field | Width | Encoding |
|---:|---|---:|---|
| `0` | `delta_ms` | 16 bit | little-endian |
| `2` | `patient_id` | 16 bit | little-endian |
| `4` | `encounter_id` | 32 bit | little-endian |
| `8` | `device_id` | 8 bit | byte |
| `9` | `bed_id` | 8 bit | byte |
| `10` | `red` | 16 bit | little-endian |
| `12` | `ir` | 16 bit | little-endian |
| `14` | `spo2_x10` | 16 bit | little-endian |
| `16` | `hr` | 8 bit | byte |
| `17` | `rr` | 8 bit | byte |
| `18` | `alert_flags` | 16 bit | little-endian |

The compact file starts with a 16-byte header:

| Header offset | Field | Width |
|---:|---|---:|
| `0` | magic `0x31485053` (`SPH1`) | 32 bit |
| `4` | record count | 32 bit |
| `8` | record size, `20` | 32 bit |
| `12` | reserved | 32 bit |

Result words:

| Word | Field |
|---:|---|
| `0` | signature `0x53505231` (`SPR1`) |
| `1` | error mask |
| `2` | raw input length |
| `3` | compact/preprocessed length |
| `4` | record count |
| `5..8` | raw TX status/bytes |
| `9..12` | compact TX status/bytes |
| `13` | magic `SPH1` |
| `14` | raw TX polls |
| `15` | compact TX polls |

## 18. Recommended command map

| Goal | Compile command | Run command |
|---|---|---|
| Secure-storage main demo | `make compile C_SRC=test_mmio_dma_storage_table.c` | `make all TESTNAME=dma_storage_table_input1_then_input3 RUN_ARGS="+CASE_NAME=dma_storage_table_input1_then_input3 +INPUT_FILE=input1.txt +INPUT_FILE2=input3.txt"` |
| Direct TX/RX loopback | `make compile C_SRC=test_mmio_dma.c` | `make all TESTNAME=dma_compress_aes_input1 RUN_ARGS="+CASE_NAME=dma_compress_aes_input1 +INPUT_FILE=input1.txt"` |
| TX-only whole-file compress-only | `make compile C_SRC=test_mmio_tx_only.c` | `make all TESTNAME=tx_compress_only_input1 RUN_ARGS="+CASE_NAME=tx_compress_only_input1 +INPUT_FILE=input1.txt"` |
| TX block AES wrapper | `make compile C_SRC=test_mmio_tx_only_aes_block.c` | `make all TESTNAME=tx_compress_aes_block_input3 RUN_ARGS="+CASE_NAME=tx_compress_aes_block_input3 +INPUT_FILE=input3.txt"` |
| TX block compress-only wrapper | `make compile C_SRC=test_mmio_tx_only_compress_block.c` | `make all TESTNAME=tx_compress_only_block_input3 RUN_ARGS="+CASE_NAME=tx_compress_only_block_input3 +INPUT_FILE=input3.txt"` |
| Register-file basic | `make compile C_SRC=test_mmio_regfile_basic.c` | `make all TESTNAME=mmio_regfile_basic RUN_ARGS="+CASE_NAME=mmio_regfile_basic +INPUT_FILE=input1.txt"` |
| Register-file negative | `make compile C_SRC=test_mmio_regfile_negative.c` | `make all TESTNAME=mmio_regfile_negative RUN_ARGS="+CASE_NAME=mmio_regfile_negative +INPUT_FILE=input1.txt"` |
| Mode matrix | `make compile C_SRC=test_mmio_mode_matrix.c` | `make all TESTNAME=mmio_mode_matrix RUN_ARGS="+CASE_NAME=mmio_mode_matrix +INPUT_FILE=input1.txt"` |
| RX bad length | `make compile C_SRC=test_mmio_rx_bad_length.c` | `make all TESTNAME=mmio_rx_bad_length RUN_ARGS="+CASE_NAME=mmio_rx_bad_length +INPUT_FILE=input1.txt"` |
| CPU instruction coverage | `make compile C_SRC=test_cpu_instruction_cov.c` | `make all TESTNAME=cpu_instruction_cov RUN_ARGS="+CASE_NAME=cpu_instruction_cov +INPUT_FILE=input1.txt"` |
| CPU memory/forwarding coverage | `make compile C_SRC=test_cpu_mem_forward_cov.c` | `make all TESTNAME=cpu_mem_forward_cov RUN_ARGS="+CASE_NAME=cpu_mem_forward_cov +INPUT_FILE=input1.txt"` |

## 19. Checklist when changing a C testcase

1. Compile the exact C file selected by the testcase.
2. Confirm `sim/instruction.mem` was regenerated from the expected `.mem`.
3. Keep result word0 as a unique signature and word1 as `error_mask`.
4. When adding a DMA mode, update the status expectation table.
5. When adding result words, update this document and the testbench report
   decode.
6. Run the focused testcase before running full coverage.
7. Check for unrelated dirty files before committing.
