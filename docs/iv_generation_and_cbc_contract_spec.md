# IV Generation and CBC Contract Specification

## 1. Purpose

This document fixes the current contract for:

1. where the IV is generated,
2. how RV32I firmware stores and restores it,
3. how TX/RX consume it in AES-128-CBC.

This spec describes the active repo state. It does not describe older flows
where IV was generated only inside `test_mmio_dma.c`.

Current implementation:

| Item | Current value |
|---|---|
| IV owner | RV32I firmware |
| Active source file | `testcase/secure_storage_fw.h` |
| Active testcase | `testcase/test_mmio_dma_storage_table.c` |
| IV counter address | `0x0000_01F0` in DMEM |
| IV seed | `0x31415926` |
| IV storage | DMA IV registers plus metadata words `iv0..iv3` |
| TX mode using IV | `MODE=0x9`, whole-file Huffman + AES-128-CBC |
| RX mode using IV | `MODE=0x2`, AES-CBC decrypt + Huffman decode |

## 2. Ownership

The current RTL does not generate IV by itself.

Hardware provides:

- DMA IV register words `IV0..IV3`.
- CBC datapath in TX and RX.
- Fixed AES-128 key material in RTL.

Firmware provides:

- IV counter in DMEM.
- IV generation formula.
- IV metadata storage.
- IV restore before read/decrypt.

There is no TRNG, no hardware entropy source, and no runtime key register in
the current implementation.

## 3. Register Contract

DMA register base:

```text
DMA_BASE = 0x4000_0000
```

| Offset | Register | Meaning |
|---:|---|---|
| `0x28` | `IV0` | CBC IV bits `[31:0]` |
| `0x2C` | `IV1` | CBC IV bits `[63:32]` |
| `0x30` | `IV2` | CBC IV bits `[95:64]` |
| `0x34` | `IV3` | CBC IV bits `[127:96]` |

The 128-bit IV passed to RTL is:

```text
cbc_iv = {IV3, IV2, IV1, IV0}
```

Rules:

- Firmware must write `IV0..IV3` before `CONTROL.start` for AES TX/RX.
- Firmware must not rewrite IV while `STATUS.busy = 1`.
- `CONTROL.soft_reset` clears IV registers to zero.
- RX must restore the same IV words used by the corresponding TX write.
- `COMPRESS_ONLY` bypasses AES and therefore does not consume IV.

## 4. Current IV Generation

The active code is:

```text
testcase/secure_storage_fw.h
```

Generation happens in:

```c
secure_prepare_record(slot, file_id, plain_addr, cipher_addr, plain_len)
```

Input fields:

| Field | Source |
|---|---|
| `plain_len` | Caller-provided plaintext length |
| `plain_addr` | Caller-provided plaintext source address |
| `cipher_addr` | Firmware-selected ciphertext slot address |
| `file_id` | Caller-provided storage object ID |
| `counter` | DMEM word at `SECURE_IV_COUNTER_ADDR` after increment |
| `0x43424331` | Fixed debug constant, ASCII-like `CBC1` |

Counter state:

```text
SECURE_IV_COUNTER_ADDR = 0x0000_01F0
SECURE_IV_SEED         = 0x31415926
```

At initialization:

```c
SECURE_IV_COUNTER_WORD = SECURE_IV_SEED;
```

Before every secure write:

```c
counter = SECURE_IV_COUNTER_WORD + 1u;
if (counter == 0u)
    counter = SECURE_IV_SEED + 1u;
SECURE_IV_COUNTER_WORD = counter;
```

## 5. Exact Formula

Current formula:

```c
mix = plain_len ^ plain_addr ^ cipher_addr ^ file_id ^ counter ^ 0x43424331u;
mix = mix ^ (mix << 13);
mix = mix ^ (mix >> 17);
mix = mix ^ (mix << 5);

iv0 = 0x43424331u ^ file_id;
iv1 = mix ^ 0x3a5c742eu;
iv2 = rotl32(iv1 ^ 0x9e3779b9u, 7u);
iv3 = rotl32(iv2 + 0x3c6ef372u, 17u);
```

where:

```c
rotl32(x, sh) = (x << sh) | (x >> (32u - sh))
```

Firmware then writes:

```text
DMA_IV0 <- iv0
DMA_IV1 <- iv1
DMA_IV2 <- iv2
DMA_IV3 <- iv3
```

and stores the same words into the selected metadata record.

## 6. Metadata IV Storage

Metadata table base:

```text
SECURE_META_BASE_ADDR    = 0x0000_0100
SECURE_META_RECORD_COUNT = 2
SECURE_META_RECORD_SHIFT = 6
```

Record `slot` starts at:

```text
0x0000_0100 + slot * 0x40
```

IV-related fields:

| Word index | Field | Meaning |
|---:|---|---|
| `7` | `iv0` | Stored IV word 0 |
| `8` | `iv1` | Stored IV word 1 |
| `9` | `iv2` | Stored IV word 2 |
| `10` | `iv3` | Stored IV word 3 |
| `11` | `version` | Current counter value used by this record |

`secure_prepare_record()` writes IV and provisional metadata with
`valid = 0`. `secure_commit_record()` sets `cipher_len`, clears flags, and then
sets `valid = 1` only after TX succeeds.

This prevents a failed TX attempt from being treated as a readable secure
storage record.

## 7. TX CBC Use

TX secure write path:

```text
secure_write()
  -> secure_prepare_record()
  -> write DMA_IV0..DMA_IV3
  -> secure_run_dma(..., MODE=0x9)
```

CBC contract:

```text
C0 = AES_encrypt(P0 XOR IV)
Cn = AES_encrypt(Pn XOR Cn-1)
```

The TX path encrypts the packed Huffman transport stream. It does not encrypt
the original plaintext bytes directly; plaintext first becomes Huffman
transport, then AES-CBC encrypts that transport.

Relevant RTL:

```text
rtl/apb_huffman_aes_tx_top.v
rtl/dma_tx_engine.v
rtl/dma_regfile.v
```

## 8. RX CBC Use

RX secure read path:

```text
secure_read(file_id, dst_addr)
  -> find metadata record
  -> secure_restore_iv_from_record(slot)
  -> write DMA_IV0..DMA_IV3
  -> secure_run_dma(cipher_addr, dst_addr, cipher_len, MODE=0x2)
```

CBC decrypt contract:

```text
P0 = AES_decrypt(C0) XOR IV
Pn = AES_decrypt(Cn) XOR Cn-1
```

After AES-CBC decrypt, RX depacks and decodes the Huffman transport. Firmware
checks:

```text
result.bytes_done == metadata.plain_len
```

Relevant RTL:

```text
rtl/apb_huffman_aes_rx_top.v
rtl/dma_rx_engine.v
rtl/dma_regfile.v
```

## 9. RV32I Instruction-Level View

The IV and metadata flow is implemented using normal RV32I instructions:

- `lw` / `sw` for DMEM and MMIO access,
- `addi` for counter increment,
- `xor`, `slli`, `srli`, `or` for mixing and rotate,
- branches for record lookup and polling.

No custom instruction is required.

The current firmware also inserts two `nop` instructions after volatile reads
through `secure_load_delay()`. This is part of the active software contract for
the current CPU/MMIO path because immediate use of a freshly loaded value can
expose a load-use hazard.

## 10. Security Meaning

For the current academic prototype:

- IV is generated by the RV32I firmware.
- Different records get different IVs because `file_id`, `cipher_addr`, and
  the counter participate in the formula.
- Metadata preserves the exact IV needed for later read/decrypt.

For a production secure-storage design, this IV generator should be replaced or
strengthened with a real nonce/entropy policy, such as:

- TRNG or hardware unique key derived nonce,
- host-provided nonce with replay protection,
- persistent monotonic counter in non-volatile storage,
- authenticated encryption or a MAC over metadata and ciphertext.

The current RTL/firmware does not implement those production features.

## 11. Verification

Latest focused testcase:

```bash
cd sim
make compile C_SRC=test_mmio_dma_storage_table.c
make all TESTNAME=dma_storage_table_input1_then_input3 \
  TB_NAME=test_bench \
  RUN_ARGS="+CASE_NAME=dma_storage_table_input1_then_input3 +INPUT_FILE=input1.txt +INPUT_FILE2=input2.txt"
```

Observed behavior:

- Two secure records are written with different file IDs in the simulation flow.
- Slot 0 uses ciphertext address `0x0000_4000`.
- Slot 1 uses ciphertext address `0x0000_4A00`.
- IV words for the two slots are checked to be different.
- `secure_read(1, 0x0000_6000, ...)` restores the selected record.
- Simulation reports `PASS=22`, `FAIL=0`.
