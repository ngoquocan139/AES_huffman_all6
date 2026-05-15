# Bit Depacker 128 Specification

## 1. Purpose

`bit_depacker_128` la khoi RX doi xung voi `bit_packer_128` ben TX. No nhan
transport word 128-bit sau AES-CBC decrypt va tach thanh stream bit chunk 32-bit
cho `huffman_block_parser`.

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
| `frame_last` | 1 | bool | Word cuoi cua frame |
| `valid_bits` | 7 | unsigned bit count | So bit payload hop le trong word |
| `payload` | 120 | bit payload | Bitstream payload |

`valid_bits` phai:

- khac zero
- bang `120` neu chua phai word cuoi
- nho hon hoac bang `120` neu la word cuoi

## 3. Data Flow

```mermaid
flowchart LR
  TW["128-bit transport word"] --> BUF["bit buffer"]
  BUF --> CHK["32-bit chunk output"]
  CHK --> PAR["huffman_block_parser"]
```

## 4. Input Contract

| Port | Dir | Width | Data format | Meaning |
|---|---|---:|---|---|
| `clk` | in | 1 | `clk` | System clock |
| `rst_n` | in | 1 | `rst_n` | Active-low reset |
| `transport_word_in` | in | 128 | 128-bit transport frame | Input transport word |
| `transport_word_valid` | in | 1 | valid flag | Input transport word is valid |
| `transport_word_ready` | out | 1 | ready flag | Depacker can accept transport word |

RX top chi day word moi khi depacker co kha nang nhan va khong co error.

## 5. Output Contract

| Port | Dir | Width | Data format | Meaning |
|---|---|---:|---|---|
| `stream_data` | out | 32 | little-endian chunk | Output bit chunk |
| `stream_len` | out | 6 | unsigned bit count | Number of valid bits in chunk |
| `stream_valid` | out | 1 | valid flag | Output chunk is valid |
| `stream_last` | out | 1 | bool | Last output chunk of current frame |
| `stream_ready` | in | 1 | ready flag | Downstream parser ready |

`stream_data[0]` la bit som nhat cua chunk. Thu tu nay phai khop voi TX
packer va Huffman parser.

## 6. Frame Completion

Khi gap transport word co `frame_last = 1`:

- depacker emit toan bo bit con lai
- chunk cuoi co `stream_last = 1`
- sau khi downstream accept chunk cuoi, `done` pulse 1 cycle

## 7. Error Conditions

`error_flag` duoc set khi:

- `valid_bits = 0`
- non-final word co `valid_bits != 120`
- final word co `valid_bits > 120`
- append chunk lam tran buffer noi bo

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

## 9. Related Specs

- [APB Huffman AES RX top](./apb_huffman_aes_rx_top_spec.md)
- [RX path end-to-end](./rx_path_end_to_end_spec.md)
- [Huffman block parser](./huffman_block_parser_spec.md)
