# 07. Memory Map and DMA Software Contract

## 1. Purpose

This document defines the current CPU-visible memory map and the software
contract used by RV32I firmware to control DMA, Huffman, AES-CBC, metadata, and
IV state.

Current active firmware:

```text
testcase/secure_storage_fw.h
testcase/test_mmio_dma_storage_table.c
```

Latest focused verification:

| Item | Value |
|---|---|
| Testcase | `dma_storage_table_input1_then_input3` |
| Result | `PASS=22`, `FAIL=0` |
| Stored records | 2 |
| Selected readback | `file_id=1` |
| RX restored length | 2551 bytes |

## 2. Global Address Map

| Region | Base | End | Owner / meaning |
|---|---:|---:|---|
| `DMEM` | `0x0000_0000` | `0x0000_7FFF` | CPU data, DMA source/destination, metadata, testbench/UART preload |
| `DMA MMIO` | `0x4000_0000` | `0x4000_00FF` | `dma_regfile` through `cpu_mmio_to_apb_bridge` |

Rules:

- All system addresses used by firmware and DMA are byte addresses.
- Current DMA engines require `SRC_ADDR` and `DST_ADDR` to be 4-byte aligned.
- CPU controls DMA through MMIO only.
- CPU does not directly program TX/RX accelerator APB wrappers in the main
  secure-storage flow; DMA engines own the private accelerator transactions.

## 3. DMEM Layout

Current secure-storage testcase layout:

| Address | Name | Meaning |
|---:|---|---|
| `0x0000_0000` | `RESULT_BASE_ADDR` | Firmware result/debug words for the testbench |
| `0x0000_0040` | `INPUT1_LEN_ADDR` | Primary input length written by TB/UART |
| `0x0000_0044` | `INPUT2_LEN_ADDR` | Secondary input length written by TB/UART |
| `0x0000_0050` | `BOARD_STATUS_ADDR` | ZCU102 pushbutton/run/debug status word written by FPGA wrapper |
| `0x0000_0054` | `BOARD_FILE_ID_ADDR` | Selected secure-storage `file_id`; default/valid values are `1` and `3` |
| `0x0000_0058` | `BOARD_EVENT_ADDR` | Monotonic board-control event counter |
| `0x0000_0100` | `SECURE_META_BASE_ADDR` | Metadata table slot 0 |
| `0x0000_0140` | metadata slot 1 | Slot 1, because record stride is `0x40` bytes |
| `0x0000_01F0` | `SECURE_IV_COUNTER_ADDR` | Firmware IV/version counter |
| `0x0000_0200` | `BOARD_SNAPSHOT_ADDR` | Optional FPGA-button snapshot copy of result words `0..15` |
| `0x0000_0240` | `BOARD_SNAPSHOT_META` | Snapshot magic/count/status words |
| `0x0000_2000` | `INPUT1_SRC_ADDR` | Primary plaintext source |
| `0x0000_3000` | `INPUT2_SRC_ADDR` | Secondary plaintext source |
| `0x0000_4000` | ciphertext slot 0 | Secure write destination for metadata slot 0 |
| `0x0000_5000` | ciphertext slot 1 | Secure write destination for metadata slot 1 |
| `0x0000_6000` | `INPUT1_RX_ADDR` | Restored plaintext destination |

Firmware chooses ciphertext slots using:

```text
cipher_addr = 0x0000_4000 + slot * 0x1000
```

The current slot size is therefore:

```text
SECURE_CIPHER_SLOT_BYTES = 0x1000
```

## 3.1 ZCU102 Pushbutton Board-Control Contract

The ZCU102 FPGA wrapper has a small board-control master sharing the DMEM
auxiliary Port B with the UART loader. It writes these words only when the UART
loader is idle.

| Address | Field | Meaning |
|---:|---|---|
| `0x0000_0050` | status | bit0 `run_latched` auto-set after UART `LOAD`, bit1 board-control busy, bit2 zeroize done, bit3 snapshot valid, bits `15:8` selected file ID, bits `23:16` zeroize count, bits `31:24` snapshot count |
| `0x0000_0054` | selected file ID | Hardware-selected `file_id`; firmware accepts `1` and `3`, otherwise defaults to `1` |
| `0x0000_0058` | event count | Incremented when the wrapper records a board-control event |
| `0x0000_0200..0x0000_023F` | snapshot words | Copy of `RESULT_WORD(0..15)` after the snapshot pushbutton |
| `0x0000_0240` | snapshot magic | `0x534E4150` (`"SNAP"`) |
| `0x0000_0244` | snapshot file ID | selected file ID at snapshot time |
| `0x0000_0248` | snapshot count | 1-based snapshot counter |
| `0x0000_024C` | snapshot status | board-control status word at snapshot completion |

The zeroize pushbutton clears `0x0000_0100..0x0000_01FF`, which covers the
secure metadata records and firmware IV counter. It also holds the SoC in reset
while clearing and drops the run latch. The AES key is currently a fixed RTL
parameter, not writable key RAM, so this operation zeroizes firmware-owned IV
and metadata state and resets DMA IV registers through SoC reset; it does not
erase a runtime key store because no runtime key store exists yet.

## 4. Secure Metadata Contract

Metadata is a firmware-owned DMEM structure. It is not a hardware filesystem.

Constants:

```text
SECURE_META_BASE_ADDR        = 0x0000_0100
SECURE_META_RECORD_SHIFT     = 6
SECURE_META_RECORD_COUNT     = 2
SECURE_META_RECORD_WORDS     = 16
```

Record address:

```text
record_addr(slot) = 0x0000_0100 + slot * 0x40
```

Record layout:

| Word index | Field | Required use |
|---:|---|---|
| `0` | `valid` | `1` means committed readable record |
| `1` | `file_id` | Application storage key |
| `2` | `plain_addr` | Plaintext source address used by `secure_write` |
| `3` | `cipher_addr` | Ciphertext address to feed RX `SRC_ADDR` |
| `4` | `plain_len` | Expected restored plaintext length |
| `5` | `cipher_len` | Value to feed RX `LEN_BYTES` |
| `6` | `mode` | Original TX mode, normally `0x9` |
| `7` | `iv0` | Stored CBC IV word 0 |
| `8` | `iv1` | Stored CBC IV word 1 |
| `9` | `iv2` | Stored CBC IV word 2 |
| `10` | `iv3` | Stored CBC IV word 3 |
| `11` | `version` | Current implementation stores the IV counter value |
| `12` | `flags` | Reserved, currently `0` |
| `13..15` | reserved | Cleared by init/delete |

Commit rule:

1. `secure_prepare_record()` writes `valid = 0`.
2. Firmware generates IV and writes provisional metadata.
3. Firmware runs DMA TX.
4. If TX succeeds and ciphertext length is valid, firmware writes `cipher_len`.
5. Firmware writes `valid = 1` last.

This makes `valid=1` the commit point.

## 5. Secure Storage API Contract

Active API:

| Function | Contract |
|---|---|
| `secure_storage_init()` | Clear all metadata records and seed the IV counter |
| `secure_write(file_id, plain_addr, plain_len, result)` | Allocate/find a slot, choose ciphertext address, generate IV, run TX, commit metadata |
| `secure_read(file_id, dst_addr, result)` | Find valid record, restore IV, run RX, require `bytes_done == plain_len` |
| `secure_delete(file_id)` | Clear the selected metadata slot |
| `secure_find_record(file_id)` | Return slot index or `0xffffffff` |
| `secure_record_count()` | Count committed records |

Error codes:

| Code | Name | Meaning |
|---:|---|---|
| `0` | `SECURE_OK` | Operation succeeded |
| `1` | `SECURE_ERR_BAD_ARG` | Bad file ID or zero length |
| `2` | `SECURE_ERR_NO_SLOT` | No free metadata slot |
| `3` | `SECURE_ERR_DMA_TIMEOUT` | DMA polling exceeded `SECURE_MAX_POLLS` |
| `4` | `SECURE_ERR_DMA_ERROR` | DMA reported error |
| `5` | `SECURE_ERR_CIPHER_LEN` | TX output length was zero or not 16-byte aligned |
| `6` | `SECURE_ERR_NOT_FOUND` | No valid metadata record for the file ID |
| `7` | `SECURE_ERR_READ_LEN` | RX output length did not match metadata `plain_len` |

## 6. DMA MMIO Register Map

Base address:

```text
DMA_BASE = 0x4000_0000
```

| Offset | Name | Access | Meaning |
|---:|---|---|---|
| `0x00` | `CONTROL` | W | `start`, `soft_reset`, `clear_done`, `clear_error` |
| `0x04` | `STATUS` | R | `busy`, `done_sticky`, `error_sticky`, `cfg_valid`, mode mirror |
| `0x08` | `SRC_ADDR` | R/W | DMEM source byte address |
| `0x0C` | `DST_ADDR` | R/W | DMEM destination byte address |
| `0x10` | `LEN_BYTES` | R/W | TX plaintext length or RX ciphertext length |
| `0x14` | `MODE` | R/W | `direction[1:0]`, `compress_only[2]`, `whole_file[3]` |
| `0x18` | `BLOCK_CFG` | R/W | Block size, valid `1..32`, recommended `32` |
| `0x1C` | `BYTES_DONE` | R | Produced byte count for active engine |
| `0x20` | `DEBUG` | R | `engine_state`, `last_error_code` |
| `0x24` | `CIPHERTEXT_BYTES_PRODUCED` | R | TX output byte count |
| `0x28` | `IV0` | R/W | CBC IV bits `[31:0]` |
| `0x2C` | `IV1` | R/W | CBC IV bits `[63:32]` |
| `0x30` | `IV2` | R/W | CBC IV bits `[95:64]` |
| `0x34` | `IV3` | R/W | CBC IV bits `[127:96]` |

## 7. Register Semantics

### 7.1 CONTROL

| Bit | Name | Type | Meaning |
|---:|---|---|---|
| `0` | `start` | W1P | Start one DMA transfer |
| `1` | `soft_reset` | W1P | Reset DMA state and sticky state |
| `2` | `clear_done` | W1P | Clear `done_sticky` |
| `3` | `clear_error` | W1P | Clear `error_sticky` |

Rules:

- `start` is valid only when `cfg_valid = 1` and `busy = 0`.
- Writes with reserved bits set are invalid.
- Current firmware clears sticky flags using `CONTROL = 0x0000000C`.

### 7.2 STATUS

| Bit | Name | Meaning |
|---:|---|---|
| `0` | `busy` | DMA engine is active |
| `1` | `done_sticky` | Last transfer completed |
| `2` | `error_sticky` | Last transfer failed |
| `3` | `cfg_valid` | Current config is valid |
| `5:4` | `direction` | Mirror of `MODE.direction` |
| `6` | `compress_only` | Mirror of `MODE.compress_only` |
| `7` | `whole_file` | Mirror of `MODE.whole_file` |
| `31:8` | reserved | Reads as zero |

Expected status values used by the storage-table testcase:

| State | Value |
|---|---:|
| TX idle configured | `0x00000098` |
| TX done | `0x0000009A` |
| RX idle configured | `0x00000028` |
| RX done | `0x0000002A` |

### 7.3 SRC_ADDR and DST_ADDR

Rules:

- Values are byte addresses in DMEM.
- Values must be 4-byte aligned.
- Software must ensure the region is inside DMEM.
- Software must not modify an active DMA source/destination while `busy=1`.

### 7.4 LEN_BYTES

Meaning depends on mode:

| Mode family | `LEN_BYTES` means |
|---|---|
| TX modes `0x1`, `0x5`, `0x9`, `0xD` | plaintext bytes read from `SRC_ADDR` |
| RX mode `0x2` | ciphertext bytes read from `SRC_ADDR` |

This is one of the most important software contract points. RX does not use the
original plaintext length as `LEN_BYTES`; RX uses `metadata.cipher_len`.

### 7.5 MODE

| Value | Meaning |
|---:|---|
| `0x1` | TX `COMPRESS_AES`, legacy per-block |
| `0x5` | TX `COMPRESS_ONLY`, legacy per-block |
| `0x9` | TX `COMPRESS_AES`, whole-file dynamic Huffman |
| `0xD` | TX `COMPRESS_ONLY`, whole-file dynamic Huffman |
| `0x2` | RX AES-CBC decrypt + Huffman decode |

Other values are invalid for the current DMA contract.

`MODE` does not select ECB/CBC. AES mode is fixed to CBC for
`COMPRESS_AES`. `COMPRESS_ONLY` bypasses AES and does not consume IV.

Current RTL no longer contains a block-level `mode_decision_logic` module. When
TX compression is selected, the encoder emits Huffman `COMPRESSED` blocks; any
future decision to store a whole file as compressed AES or raw AES belongs in
RV32I firmware metadata policy, not inside the Huffman block datapath.

### 7.6 BLOCK_CFG

- Valid range is `1..32`.
- Current firmware writes `32`.
- Whole-file TX still requires a valid value for config validity.
- In whole-file mode, this field is the payload chunk size used by the DMA/TX
  adapter. It does not mean a separate Huffman codebook is rebuilt for every
  chunk; the codebook is still built from the whole input file.

### 7.7 BYTES_DONE

| Active mode | Meaning |
|---|---|
| TX | Output bytes written by TX DMA |
| RX | Plaintext bytes restored by RX DMA |

For secure read, firmware checks:

```text
BYTES_DONE == metadata.plain_len
```

### 7.8 CIPHERTEXT_BYTES_PRODUCED

This register mirrors the TX DMA output length and is the value firmware stores
as `metadata.cipher_len`.

For secure read:

```text
LEN_BYTES = metadata.cipher_len
```

### 7.9 IV0..IV3

Current IV contract:

```text
cbc_iv = {IV3, IV2, IV1, IV0}
```

Rules:

- Write IV before AES TX/RX start.
- Do not write IV while DMA is busy.
- `CONTROL.soft_reset` clears IV registers.
- Store the IV in metadata after generation.
- Restore the same IV before RX.

## 8. Current IV Counter and Formula

Counter:

```text
SECURE_IV_COUNTER_ADDR = 0x0000_01F0
SECURE_IV_SEED         = 0x31415926
```

Generation:

```c
counter = SECURE_IV_COUNTER_WORD + 1u;
if (counter == 0u)
    counter = SECURE_IV_SEED + 1u;
SECURE_IV_COUNTER_WORD = counter;

mix = plain_len ^ plain_addr ^ cipher_addr ^ file_id ^ counter ^ 0x43424331u;
mix = mix ^ (mix << 13);
mix = mix ^ (mix >> 17);
mix = mix ^ (mix << 5);

iv0 = 0x43424331u ^ file_id;
iv1 = mix ^ 0x3a5c742eu;
iv2 = rotl32(iv1 ^ 0x9e3779b9u, 7u);
iv3 = rotl32(iv2 + 0x3c6ef372u, 17u);
```

This is a deterministic demo IV generator. It is useful for repeatable
simulation but is not a production entropy source.

## 9. Current DMA Run Sequence

The active helper is:

```c
secure_run_dma(src, dst, len, mode, result)
```

It performs:

1. Clear sticky state with `DMA_CONTROL = 0x0000000C`.
2. Write `DMA_SRC_ADDR`.
3. Write `DMA_DST_ADDR`.
4. Write `DMA_LEN_BYTES`.
5. Write `DMA_MODE`.
6. Write `DMA_BLOCK_CFG = 32`.
7. Read `DMA_STATUS` into `result->status_before`.
8. Write `DMA_CONTROL = 0x00000001`.
9. Poll `DMA_STATUS` until done or error.
10. Read `DMA_BYTES_DONE`.
11. Read `DMA_CIPHERTEXT_BYTES_PRODUCED`.
12. Read `DMA_DEBUG`.

The helper calls `secure_load_delay()` after volatile reads. The current
implementation is:

```c
__asm__ volatile("nop\nnop\n" ::: "memory");
```

This delay is part of the current firmware contract because the current
RV32I/MMIO path can expose a load-use hazard if loaded values are consumed
immediately.

## 10. Secure Write Sequence

`secure_write(file_id, plain_addr, plain_len, result)`:

```text
1. Reject file_id=0 or plain_len=0.
2. Find an existing record for file_id, or allocate an empty slot.
3. Select cipher_addr = 0x4000 + slot * 0x1000.
4. Generate IV from file_id, addresses, length, and counter.
5. Write IV to DMA IV registers and provisional metadata.
6. Run DMA:
   SRC_ADDR  = plain_addr
   DST_ADDR  = cipher_addr
   LEN_BYTES = plain_len
   MODE      = 0x9
7. Require ciphertext_bytes != 0.
8. Require ciphertext_bytes is 16-byte aligned.
9. Commit cipher_len and set metadata valid=1.
```

## 11. Secure Read Sequence

`secure_read(file_id, dst_addr, result)`:

```text
1. Find a valid metadata record by file_id.
2. Restore IV0..IV3 from metadata to DMA registers.
3. Read cipher_addr, cipher_len, and plain_len from metadata.
4. Run DMA:
   SRC_ADDR  = cipher_addr
   DST_ADDR  = dst_addr
   LEN_BYTES = cipher_len
   MODE      = 0x2
5. Require BYTES_DONE == plain_len.
```

## 12. Result Words in Current Testcase

`testcase/test_mmio_dma_storage_table.c` writes these result words at
`RESULT_BASE_ADDR = 0x0000_0000`:

| Word | Meaning |
|---:|---|
| `0` | Signature `0x53544f52` |
| `1` | Error mask |
| `2` | TX1 status before |
| `3` | TX1 status after |
| `4` | TX1 bytes done |
| `5` | TX1 ciphertext bytes |
| `6` | TX1 poll count |
| `7` | RX1 status before |
| `8` | RX1 status after |
| `9` | RX1 bytes done |
| `10` | RX1 debug after |
| `11` | RX1 poll count |
| `12` | TX2 ciphertext bytes |
| `13` | input2 length |
| `14` | selected file ID |
| `15` | total committed records |

The testbench interprets these result words and checks the restored bytes in
DMEM.

## 13. Software Rules While DMA Is Busy

When `STATUS.busy = 1`, software must not:

- overwrite the source buffer being read by DMA,
- read or overwrite the destination buffer being written by DMA,
- modify `SRC_ADDR`, `DST_ADDR`, `LEN_BYTES`, `MODE`, `BLOCK_CFG`, or `IV0..IV3`,
- start a second transfer.

The RTL reports MMIO write errors for many invalid busy-time register writes,
but the system-level memory semantics are still a software responsibility.

## 14. Production Gaps

The current contract is sufficient for the academic secure-storage prototype,
but it is not a production storage stack yet.

Missing production features:

- persistent metadata outside volatile DMEM,
- authenticated metadata and ciphertext,
- rollback protection,
- production IV/nonce source,
- runtime key management,
- interrupt-based completion,
- more than two metadata records in the current testcase.
