# Bit Depacker 128 Specification

## 1. Mục đích

`bit_depacker_128` là khối RX đối xứng với `bit_packer_128` ben TX. No nhận
transport word 128-bit sau AES-CBC decrypt và tách thanh stream bit chunk 32-bit
cho `huffman_block_parser`.

Trạng thái kiểm chứng hiện tại:

| Case | Coverage/use |
|---|---|
| `dma_compress_aes_input1/input3/alnum63` | Normal depack path after AES-CBC decrypt |
| `rx_depacker_packer_direct_cov` | Invalid `valid_bits`, malformed transport frame, and direct pack/depack edge chunks |
| `rx_parser_decoder_error_direct_cov` | Error propagation into parser/decoder stack |

## 2. Transport Word Format

Transport word gom:

| Trường | Độ rộng | Định dạng dữ liệu | Ý nghĩa |
|---|---:|---|---|
| `frame_last` | 1 | bool | Word cuối của frame |
| `valid_bits` | 7 | unsigned bit count | Số bit payload hợp lệ trong word |
| `payload` | 120 | bit payload | Bitstream payload |

`valid_bits` phải:

- khác zero
- bằng `120` nếu chưa phải word cuối
- nhỏ hơn hoặc bằng `120` nếu là word cuối

## 3. Data Flow

```mermaid
flowchart LR
  TW["128-bit transport word"] --> BUF["bit buffer"]
  BUF --> CHK["32-bit chunk output"]
  CHK --> PAR["huffman_block_parser"]
```

## 4. Contract input

| Cổng | Hướng | Độ rộng | Định dạng dữ liệu | Ý nghĩa |
|---|---|---:|---|---|
| `clk` | in | 1 | `clk` | System clock |
| `rst_n` | in | 1 | `rst_n` | Active-low reset |
| `transport_word_in` | in | 128 | 128-bit transport frame | Input transport word |
| `transport_word_valid` | in | 1 | valid flag | Input transport word is valid |
| `transport_word_ready` | out | 1 | ready flag | Depacker can accept transport word |

RX top chỉ đây word mới khi depacker có kha nang nhận và không có error.

## 5. Contract output

| Cổng | Hướng | Độ rộng | Định dạng dữ liệu | Ý nghĩa |
|---|---|---:|---|---|
| `stream_data` | out | 32 | little-endian chunk | Output bit chunk |
| `stream_len` | out | 6 | unsigned bit count | Number of valid bits in chunk |
| `stream_valid` | out | 1 | valid flag | Output chunk is valid |
| `stream_last` | out | 1 | bool | Last output chunk of current frame |
| `stream_ready` | in | 1 | ready flag | Downstream parser ready |

`stream_data[0]` là bit som nhất của chunk. Thứ tự này phải khop với TX
packer và Huffman parser.

## 6. Frame Completion

Khi gặp transport word có `frame_last = 1`:

- depacker emit toàn bộ bit còn lại
- chunk cuối có `stream_last = 1`
- sau khi downstream accept chunk cuối, `done` pulse 1 cycle

## 7. Điều kiện lỗi

`error_flag` được set khi:

- `valid_bits = 0`
- non-final word có `valid_bits != 120`
- final word có `valid_bits > 120`
- append chunk làm tran buffer nội bộ

## 8. Thanh ghi nội bộ

| Reg | Độ rộng | Định dạng dữ liệu | Ý nghĩa |
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

## 9. Spec liên quan

- [APB Huffman AES RX top](./apb_huffman_aes_rx_top_spec.md)
- [RX path end-to-end](./rx_path_end_to_end_spec.md)
- [Huffman block parser](./huffman_block_parser_spec.md)
