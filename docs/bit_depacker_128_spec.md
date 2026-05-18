# Bit Depacker 128 Specification

## 1. Purpose

`bit_depacker_128` is the RX block symmetrical to `bit_packer_128` on the TX side. It receives
transport word 128-bit after AES-CBC decrypt and separate 32-bit bit stream chunks
for `huffman_block_parser`.

Current verification status:

| Case | Coverage/use |
|---|---|
| `dma_compress_aes_input1/input3/alnum63` | Normal depack path after AES-CBC decrypt |
| `rx_depacker_packer_direct_cov` | Invalid `valid_bits`, malformed transport frame, and direct pack/depack edge chunks |
| `rx_parser_decoder_error_direct_cov` | Error propagation into parser/decoder stack |

## 2. Transport Word Format

Transport word gom:

| Field | Width | Data format | Meaning |
|---|---:|---|---|
| `frame_last` | 1 | bool | Last word of frame |
| `valid_bits` | 7 | unsigned bit count | Number of valid payload bits in word |
| `payload` | 120 | bit payload | Bitstream payload |

`valid_bits` must:

- other than zero
- equal to `120` if not the last word
- less than or equal to `120` if it is the last word

## 3. Data Flow

```mermaid
flowchart LR
  TW["128-bit transport word"] --> BUF["bit buffer"]
  BUF --> CHK["32-bit chunk output"]
  CHK --> PAR["huffman_block_parser"]
```

## 4. Contract input

| Port | Direction | Width | Data format | Meaning |
|---|---|---:|---|---|
| `clk` | in | 1 | `clk` | System clock |
| `rst_n` | in | 1 | `rst_n` | Active-low reset |
| `transport_word_in` | in | 128 | 128-bit transport frame | Input transport word |
| `transport_word_valid` | in | 1 | valid flag | Input transport word is valid |
| `transport_word_ready` | out | 1 | ready flag | Depacker can accept transport words |

RX top indicates new words when the depacker has the capacity to receive and there are no errors.

## 5. Contract output

| Port | Direction | Width | Data format | Meaning |
|---|---|---:|---|---|
| `stream_data` | out | 32 | little-endian chunk | Output bit chunk |
| `stream_len` | out | 6 | unsigned bit count | Number of valid bits in chunk |
| `stream_valid` | out | 1 | valid flag | Output chunk is valid |
| `stream_last` | out | 1 | bool | Last output chunk of current frame |
| `stream_ready` | in | 1 | ready flag | Downstream parser ready |

`stream_data[0]` is the lowest bit of the chunk. This order must match TX
packer and Huffman parser.

## 6. Frame Completion

When encountering a transport word with `frame_last = 1`:

- depacker emits all remaining bits
- The last chunk has `stream_last = 1`
- After downstream accepts the last chunk, `done` pulses 1 cycle

## 7. Error conditions

`error_flag` is set when:

- `valid_bits = 0`
- non-final word has `valid_bits != 120`
- final word has `valid_bits > 120`
- append chunk as an internal tran buffer

## 8. Internal registers

| Reg | Width | Data format | Meaning |
|---|---:|---|---|
| `bit_buffer_r` | 152 | bit buffer | Buffered transport payload bits |
| `bit_count_r` | 9 | unsigned bit count | Number of buffered bits |
| `frame_active_r` | 1 | bool | Frame currently active |
| `frame_last_pending_r` | 1 | bool | Frame-last has been seen but not yet flushed |
| `stream_data_r` | 32 | little-endian chunk | Output chunk register |
| `stream_len_r` | 6 | unsigned bit count | Output chunk valid bits |
| `stream_valid_r` | 1 | valid flag | Output chunk valid |
| `stream_last_r` | 1 | bool | Output chunk is last in frame |
| `done_r` | 1 | pulse | Completion pulse |
| `error_r` | 1 | error flag | Error sticky |

## 9. Related specs

- [APB Huffman AES RX top](./apb_huffman_aes_rx_top_spec.md)
- [RX path end-to-end](./rx_path_end_to_end_spec.md)
- [Huffman block parser](./huffman_block_parser_spec.md)
