# Bit Packer 128 Specification

## 1. Mục đích

`bit_packer_128` nhận bitstream tu `dynamic_huffman_encoder`, gom các bit do
thanh 128-bit transport word, sau đó cap cho layer AES hoặc bypass FIFO.

Module này không biet gi ve Huffman tree, codebook hay DMA. No chỉ đảm bảo
bitstream liên tục được đóng gói thanh `transport_word`.

Trạng thái kiểm chứng hiện tại:

| Case | Coverage/use |
|---|---|
| `tx_compress_only_input1/input4_cov` | Normal transport packing in TX-only storage measurement |
| `dma_compress_aes_input1/input3/alnum63` | Packing before AES-CBC in full loopback |
| `tx_compress_only_short_raw_cov` | Short final-word padding and partial valid bits |
| `tx_builder_packer_direct_cov` | Direct packer ready/valid and flush corner branches |
| `rx_depacker_packer_direct_cov` | Cross-check TX packer format against RX depacker assumptions |

## 2. Vai trò In TX Stack

Vi tri trong stack:

```text
dynamic_huffman_encoder
-> bit_packer_128
-> TX policy select
-> AES or bypass
```

`bit_packer_128` là cau noi giua:

- bit-level encoder output
- word-level crypto/storage datapath

## 3. Contract input

| Cổng | Hướng | Độ rộng | Định dạng dữ liệu | Ý nghĩa |
|---|---|---:|---|---|
| `clk` | in | 1 | `clk` | System clock |
| `rst_n` | in | 1 | `rst_n` | Active-low reset |
| `stream_data` | in | 32 | little-endian chunk | Bit chunk from encoder |
| `stream_len` | in | 6 | unsigned bit count | Number of valid bits in `stream_data` |
| `stream_valid` | in | 1 | valid flag | Input chunk is valid |
| `stream_last` | in | 1 | bool | Last chunk of current frame |
| `flush_on_last` | in | 1 | policy flag | Force flush when `stream_last` arrives |
| `stream_ready` | out | 1 | ready flag | Packer can accept next chunk |
| `transport_word_ready` | in | 1 | ready flag | Downstream transport consumer ready |

## 4. Hành vi mức cao

```mermaid
flowchart LR
  IN["32-bit bit chunks"] --> SH["shift / accumulate"]
  SH --> OUT["128-bit transport word"]
  OUT --> FLUSH["flush on frame end"]
```

Module:

- tiep nhận chunk bit 32-bit
- lưu bit đủ trong thanh ghi đếm
- xuất một transport word 128-bit khi đủ bit
- nếu frame kết thúc mà chưa đủ 128 bit thì zero-pad và flush

## 5. Contract output

| Cổng | Hướng | Độ rộng | Định dạng dữ liệu | Ý nghĩa |
|---|---|---:|---|---|
| `transport_word_out` | out | 128 | 128-bit transport frame | Packed output word |
| `transport_word_valid` | out | 1 | valid flag | Packed output word is valid |
| `transport_word_ready` | in | 1 | ready flag | Downstream accepts packed word |
| `busy` | out | 1 | busy flag | Packer has buffered bits or pending output |
| `done` | out | 1 | pulse | Frame packing completed |
| `error_flag` | out | 1 | error flag | Packing protocol error |

Transport word format:

| Trường | Độ rộng | Định dạng dữ liệu | Ý nghĩa |
|---|---:|---|---|
| `frame_last` | 1 | bool | Frame end marker |
| `valid_bits` | 7 | unsigned bit count | Number of valid payload bits |
| `payload` | 120 | bit payload | Packed Huffman/raw payload |

Trong flow active hiện tại:

- `valid_bits` chỉ ro số bit thật sự có ý nghĩa trong payload
- AES cần word đây để mã hóa, còn bypass có thể lưu transport word trực tiếp

## 6. Quy tắc pack

Packer làm việc theo quy tac:

1. load chunk bit vao buffer
2. chen bit vao vi tri LSB-first của buffer nội bộ
3. khi buffer >= 128 bit thì cat 128 bit ra một word
4. nếu frame kết thúc ma buffer còn bit le thì pad 0 đến đủ 128 bit

## 7. Ngữ nghĩa lưu trữ

So với bitstream raw:

- `bit_packer_128` không đổi nội dung Huffman
- no chỉ thay đổi cách lưu/truyền
- storage cost sau cung được quantize theo transport word 128-bit

Vi vay mode decision của TX phải xem kết quả sau packer, không chỉ xem
số bit Huffman thuan.

### 7.1 Thanh ghi nội bộ

| Reg | Độ rộng | Định dạng dữ liệu | Ý nghĩa |
|---|---:|---|---|
| `payload_buf_r` | 120 | bit payload buffer | Buffered payload bits |
| `payload_count_r` | 7 | unsigned bit count | Number of valid bits buffered |
| `transport_word_r` | 128 | 128-bit transport frame | Output frame register |
| `transport_valid_r` | 1 | valid flag | Output frame valid |
| `pending_payload_r` | 32 | little-endian chunk | Pending chunk not yet merged |
| `pending_len_r` | 7 | unsigned bit count | Valid bit count for pending chunk |
| `pending_valid_r` | 1 | bool | Pending chunk present |
| `busy_r` | 1 | busy flag | Packer busy state |
| `done_r` | 1 | pulse | Completion pulse |
| `error_r` | 1 | error flag | Error sticky |

## 8. Điều kiện lỗi

Module có thể báo lỗi nếu:

- nhận `stream_valid` khi dang full mà không có `stream_ready`
- `stream_len = 0` trong khi `stream_valid = 1`
- `stream_len > 32`
- frame kết thúc sai protocol

## 9. Spec liên quan

- [TX path end-to-end](./tx_path_end_to_end_spec.md)
- [System top `apb_huffman_aes_tx_top`](./apb_huffman_aes_tx_top_spec.md)
