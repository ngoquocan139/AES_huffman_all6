# APB Huffman TX Interface Specification

## 1. Mục đích

`apb_huffman_tx_if` là APB slave dung o đầu vao TX stack. No cung cấp:

- thanh ghi cấu hình block size
- FIFO nạp `WORD_IN` 32-bit
- pulse `START_BLOCK`
- sticky status cho done/error
- output FIFO cho ciphertext 32-bit đọc ra bởi CPU hoặc DMA
- policy bits cho `COMPRESS_ONLY` và whole-file mode

Module này là cau noi giua APB master và `huffman_aes_tx_top`. No không tu
nén Huffman và không tu mã hóa AES.

Trạng thái kiểm chứng hiện tại:

| Case | Coverage/use |
|---|---|
| `tx_if_direct_cov` | APB register map, FIFO backpressure, control pulse, sticky status |
| `tx_compress_only_input1/input4_cov` | Normal data load and block launch through TX APB path |
| `dma_compress_aes_input1/input3/alnum63` | SoC TX path uses this wrapper before encoder/AES |

## 2. Vai trò In TX Stack

```text
APB master
-> apb_huffman_tx_if
-> huffman_aes_tx_top
-> AES or bypass output FIFO
```

Internal input flow:

```text
WORD_IN writes
-> 8-word input FIFO
-> word_in_o / word_valid_o
-> TX top
```

Internal output flow:

```text
TX top AES output
-> 16-word output FIFO
-> AES_OUT_DATA / AES_OUT_META / AES_OUT_STATUS
```

## 3. Main Interfaces

### 3.1 APB slave

| Cổng | Hướng | Độ rộng | Định dạng dữ liệu | Ý nghĩa |
|---|---|---:|---|---|
| `PCLK` | in | 1 | `clk` | APB clock |
| `PRESETn` | in | 1 | `rst_n` | Active-low reset |
| `PSEL` | in | 1 | `apb_sel` | APB select |
| `PENABLE` | in | 1 | `apb_enable` | APB enable phase |
| `PWRITE` | in | 1 | `apb_write` | `1` write, `0` read |
| `PADDR` | in | 32 | byte address | Local register address |
| `PWDATA` | in | 32 | little-endian word | APB write data |
| `PRDATA` | out | 32 | little-endian word | APB read data |
| `PREADY` | out | 1 | handshake | Stall when FIFO cannot accept or start is premature |
| `PSLVERR` | out | 1 | sticky error pulse | Invalid address, reserved bits, or protocol error |

### 3.2 Downstream TX-top control

| Cổng | Hướng | Độ rộng | Định dạng dữ liệu | Ý nghĩa |
|---|---|---:|---|---|
| `start_block_o` | out | 1 | pulse | Launch one loaded block |
| `continue_frame_o` | out | 1 | bool | `1` means more blocks follow in the same frame |
| `compress_only_o` | out | 1 | bool | `1` bypasses AES, `0` uses AES-CBC |
| `whole_file_enable_o` | out | 1 | bool | Enable whole-file codebook flow |
| `whole_file_count_mode_o` | out | 1 | bool | Count-only mode for whole-file build |
| `block_size_o` | out | 6 | unsigned byte count | Block size in bytes, valid `1..32` |
| `word_in_o` | out | 32 | little-endian word | FIFO head word for TX top |
| `word_valid_o` | out | 1 | valid flag | Word at FIFO head is valid |
| `word_ready_i` | in | 1 | ready flag | TX top accepts FIFO head |

### 3.3 AES output stream

| Cổng | Hướng | Độ rộng | Định dạng dữ liệu | Ý nghĩa |
|---|---|---:|---|---|
| `aes_out_word_i` | in | 32 | little-endian word | Ciphertext/output word from TX top |
| `aes_out_word_last_i` | in | 1 | bool | Last word of output frame |
| `aes_out_word_valid_i` | in | 1 | valid flag | Output word is present |
| `aes_out_word_ready_o` | out | 1 | ready flag | Wrapper can accept another output word |
| `aes_out_error_i` | in | 1 | bool | TX-top output path error |

### 3.4 TX-top status

| Cổng | Hướng | Độ rộng | Định dạng dữ liệu | Ý nghĩa |
|---|---|---:|---|---|
| `tx_busy_i` | in | 1 | bool | TX top is busy |
| `tx_done_i` | in | 1 | pulse / sticky event | TX top completed the current block |
| `tx_error_i` | in | 1 | bool | TX top reported error |
| `global_build_busy_i` | in | 1 | bool | Whole-file builder busy |
| `global_build_done_i` | in | 1 | bool | Whole-file builder finished |
| `global_build_error_i` | in | 1 | bool | Whole-file builder error |
| `global_table_valid_i` | in | 1 | bool | Whole-file table valid |
| `global_symbol_count_i` | in | 9 | unsigned symbol count | Number of symbols in current global table |

## 4. Bản đồ thanh ghi

| Offset | Name | Truy cập | Định dạng dữ liệu | Ý nghĩa |
|---:|---|---|---|---|
| `0x00` | `START_BLOCK` | W | control pulse | Bit0 starts block, bit1 marks continue-frame |
| `0x04` | `BLOCK_SIZE` | R/W | unsigned byte count | Current block size, valid `1..32` |
| `0x08` | `WORD_IN` | W | little-endian 32-bit word | Plaintext input word FIFO |
| `0x0C` | `STATUS` | R | bitfield | Live configuration, FIFO, sticky and whole-file state |
| `0x10` | `CONTROL` | W | pulse bits | Soft reset and clear sticky flags |
| `0x14` | `DEBUG` | R | counters + pointers | FIFO occupancy and internal pointers |
| `0x18` | `TX_POLICY` | R/W | policy bits + symbol count | `compress_only`, whole-file enable, whole-file count mode |
| `0x20` | `AES_OUT_DATA` | R | little-endian 32-bit word | Output FIFO head word |
| `0x24` | `AES_OUT_META` | R | bitfield | Output last flag and policy mirror |
| `0x28` | `AES_OUT_STATUS` | R | bitfield | Output FIFO status and error mirror |
| `0x2C` | `AES_OUT_DEBUG` | R | counters + pointers | Output FIFO debug view |

### 4.1 Thanh ghi function summary

| Thanh ghi | Chức năng | Người dùng chính | Định dạng dữ liệu / ghi chú |
|---|---|---|---|
| `START_BLOCK` | Launch one loaded block | `huffman_aes_tx_top` / software | Bit0 must be `1`; bit1 preserves frame continuity |
| `BLOCK_SIZE` | Declare current plaintext block size | Software or DMA | Unsigned bytes, must be `1..32` |
| `WORD_IN` | Push one 32-bit word into input FIFO | Software or DMA | Little-endian word; max 8 words per block |
| `STATUS` | Poll configuration and progress | DMA / software | Mixed bitfield, see table below |
| `CONTROL` | Soft reset and clear sticky flags | Debug / reset flow | Write-only pulse bits |
| `DEBUG` | Inspect FIFO pointers and counters | Debug only | Non-contract debug mirror |
| `TX_POLICY` | Select compression and whole-file mode | DMA / software | Bit0/1/2 policy bits, upper bits expose symbol count |
| `AES_OUT_DATA` | Read output FIFO head word | DMA / software | Pop-on-read 32-bit ciphertext/output word |
| `AES_OUT_META` | Read output metadata | DMA / software | Last-word flag + compress-only mirror |
| `AES_OUT_STATUS` | Poll output FIFO and error status | DMA / software | Nonempty/full/count/error/policy bitfield |
| `AES_OUT_DEBUG` | Inspect output FIFO internals | Debug only | Output FIFO occupancy and pointers |

### 4.2 `STATUS` register

| Bit | Định dạng dữ liệu | Ý nghĩa |
|---:|---|---|
| 0 | 1-bit config flag | `cfg_valid` |
| 1 | 1-bit live flag | `input_ready` |
| 2 | 1-bit live flag | `block_active` |
| 3 | 1-bit live flag | `tx_busy` |
| 4 | 1-bit sticky | `done_sticky` |
| 5 | 1-bit sticky | `error_sticky` |
| 6 | 1-bit live flag | Input FIFO nonempty |
| 7 | 1-bit live flag | `can_start` |
| 8 | 1-bit live flag | `global_table_valid` |
| 9 | 1-bit live flag | `global_build_busy` |
| 10 | 1-bit live flag | `global_build_done` |
| 11 | 1-bit live flag | `global_build_error` |
| 12 | 1-bit policy flag | `whole_file_enable` |
| 13 | 1-bit policy flag | `whole_file_count_mode` |

### 4.3 `TX_POLICY` register

| Bits | Định dạng dữ liệu | Ý nghĩa |
|---:|---|---|
| 0 | 1-bit policy | `compress_only` |
| 1 | 1-bit policy | `whole_file_enable` |
| 2 | 1-bit policy | `whole_file_count_mode` |
| `SYMBOL_COUNT_WIDTH+7:8` | unsigned count | `global_symbol_count` mirror |

### 4.4 `CONTROL` register

| Bit | Định dạng dữ liệu | Ý nghĩa |
|---:|---|---|
| 0 | pulse | Soft reset wrapper state and FIFOs |
| 1 | pulse | Clear `done_sticky` |
| 2 | pulse | Clear `error_sticky` and `aes_out_error_sticky` |
| 3 | pulse | Global clear for whole-file state |
| 4 | pulse | Start whole-file build |

### 4.5 `AES_OUT_STATUS` register

| Bit | Định dạng dữ liệu | Ý nghĩa |
|---:|---|---|
| 0 | 1-bit live flag | Output FIFO nonempty |
| 1 | 1-bit live flag | Output FIFO full |
| 2 | 1-bit live flag | Output FIFO not full |
| `7:3` | unsigned count | Output FIFO occupancy |
| 8 | 1-bit meta flag | Head word last flag |
| 9 | 1-bit sticky | AES output error sticky |
| 10 | 1-bit policy flag | `compress_only` mirror |
| 11 | 1-bit policy flag | `whole_file_enable` mirror |

### 4.6 `AES_OUT_META` register

| Bit | Định dạng dữ liệu | Ý nghĩa |
|---:|---|---|
| 0 | 1-bit meta flag | Last word in output frame |
| 1 | 1-bit policy flag | `compress_only` mirror |

### 4.7 `DEBUG` register

| Bit | Định dạng dữ liệu | Ý nghĩa |
|---:|---|---|
| `4:0` | unsigned count | Input FIFO occupancy |
| `8:5` | FIFO pointer | Input write pointer |
| `12:9` | FIFO pointer | Input read pointer |
| `13` | 1-bit live flag | Input FIFO nonempty |
| `14` | constant 1 | Debug signature bit |
| `18:15` | 4-bit stage flags | Cipher stage valid bits |
| `19` | 1-bit stage flag | Cipher stage complete |
| `20` | 1-bit stage flag | Cipher pending valid |
| `21` | 1-bit stage flag | Ciphertext word ready |
| `24` | 1-bit policy flag | `whole_file_enable` mirror |
| `25` | 1-bit policy flag | `whole_file_count_mode` mirror |

### 4.8 `AES_OUT_DEBUG` register

| Bit | Định dạng dữ liệu | Ý nghĩa |
|---:|---|---|
| `4:0` | unsigned count | Output FIFO occupancy |
| `8:5` | FIFO pointer | Output write pointer |
| `12:9` | FIFO pointer | Output read pointer |
| `13` | 1-bit live flag | Output FIFO nonempty |
| `14` | constant 1 | Debug signature bit |
| `15` | 1-bit sticky | AES output error sticky |

## 5. Output FIFO Contract

`aes_out_word_i` writes into a 16-entry FIFO. Each entry stores:

- `word[31:0]`
- `last` flag

Read order:

1. poll `AES_OUT_STATUS[0]`
2. read `AES_OUT_META`
3. read `AES_OUT_DATA`

`AES_OUT_DATA` read pops the FIFO head.

## 6. Internal State / Registers

| Reg / FIFO | Độ rộng | Định dạng dữ liệu | Ý nghĩa |
|---|---:|---|---|
| `fifo_mem[0:7]` | 8 x 32 | little-endian words | Input FIFO for `WORD_IN` |
| `out_fifo_mem[0:15]` | 16 x 32 | little-endian words | Output FIFO for AES/top output |
| `out_fifo_last_mem[0:15]` | 16 x 1 | bool | Per-word last flag |
| `wr_ptr_r` | 3 | FIFO pointer | Input write pointer |
| `rd_ptr_r` | 3 | FIFO pointer | Input read pointer |
| `fifo_count_r` | 4 | unsigned count | Number of loaded input words |
| `out_wr_ptr_r` | 4 | FIFO pointer | Output write pointer |
| `out_rd_ptr_r` | 4 | FIFO pointer | Output read pointer |
| `out_fifo_count_r` | 5 | unsigned count | Number of output words queued |
| `cfg_valid_r` | 1 | bool | `BLOCK_SIZE` has been accepted |
| `words_expected_r` | 4 | unsigned word count | `ceil(block_size/4)` |
| `words_loaded_r` | 4 | unsigned word count | Number of input words written |
| `block_inflight_r` | 1 | bool | Block has been launched |
| `stream_active_r` | 1 | bool | Input FIFO currently streaming to TX top |
| `done_sticky_r` | 1 | sticky | Block completion sticky |
| `error_sticky_r` | 1 | sticky | Local APB / protocol sticky |
| `aes_out_error_sticky_r` | 1 | sticky | Output path error sticky |
| `block_size_o` | 6 | unsigned byte count | Current block size mirror |
| `start_block_o` | 1 | pulse | Block launch pulse |
| `continue_frame_o` | 1 | bool | Frame continuity marker |
| `compress_only_o` | 1 | bool | Output policy mirror |
| `whole_file_enable_o` | 1 | bool | Whole-file mode mirror |
| `whole_file_count_mode_o` | 1 | bool | Whole-file count mode mirror |

## 7. Điều kiện lỗi

`PSLVERR` or sticky error can be raised when:

- reserved bits are written in `CONTROL` or `TX_POLICY`
- `BLOCK_SIZE` is `0` or `> 32`
- `START_BLOCK` is written before all input words are loaded
- `WORD_IN` overflows the input FIFO
- invalid APB address is accessed
- downstream TX-top reports error

## 8. Spec liên quan

- [APB Huffman AES TX top](./apb_huffman_aes_tx_top_spec.md)
- [Dynamic Huffman encoder](./dynamic_huffman_encoder_spec.md)
- [Bit packer 128](./bit_packer_128_spec.md)
