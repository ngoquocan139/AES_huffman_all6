# Bit Packer 128 Specification

## 1. Purpose

`bit_packer_128` nhan bitstream tu `dynamic_huffman_encoder`, gom cac bit do
thanh 128-bit transport word, sau do cap cho layer AES hoac bypass FIFO.

Module nay khong biet gi ve Huffman tree, codebook hay DMA. No chi dam bao
bitstream lien tuc duoc dong goi thanh `transport_word`.

Current verification status:

| Case | Coverage/use |
|---|---|
| `tx_compress_only_input1/input4_cov` | Normal transport packing in TX-only storage measurement |
| `dma_compress_aes_input1/input3/alnum63` | Packing before AES-CBC in full loopback |
| `tx_compress_only_short_raw_cov` | Short final-word padding and partial valid bits |
| `tx_builder_packer_direct_cov` | Direct packer ready/valid and flush corner branches |
| `rx_depacker_packer_direct_cov` | Cross-check TX packer format against RX depacker assumptions |

## 2. Role In TX Stack

Vi tri trong stack:

```text
dynamic_huffman_encoder
-> bit_packer_128
-> TX policy select
-> AES or bypass
```

`bit_packer_128` la cau noi giua:

- bit-level encoder output
- word-level crypto/storage datapath

## 3. Input Contract

| Port | Dir | Width | Data format | Meaning |
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

## 4. High-Level Behavior

```mermaid
flowchart LR
  IN["32-bit bit chunks"] --> SH["shift / accumulate"]
  SH --> OUT["128-bit transport word"]
  OUT --> FLUSH["flush on frame end"]
```

Module:

- tiep nhan chunk bit 32-bit
- luu bit du trong thanh ghi dem
- xuat mot transport word 128-bit khi du bit
- neu frame ket thuc ma chua du 128 bit thi zero-pad va flush

## 5. Output Contract

| Port | Dir | Width | Data format | Meaning |
|---|---|---:|---|---|
| `transport_word_out` | out | 128 | 128-bit transport frame | Packed output word |
| `transport_word_valid` | out | 1 | valid flag | Packed output word is valid |
| `transport_word_ready` | in | 1 | ready flag | Downstream accepts packed word |
| `busy` | out | 1 | busy flag | Packer has buffered bits or pending output |
| `done` | out | 1 | pulse | Frame packing completed |
| `error_flag` | out | 1 | error flag | Packing protocol error |

Transport word format:

| Field | Width | Data format | Meaning |
|---|---:|---|---|
| `frame_last` | 1 | bool | Frame end marker |
| `valid_bits` | 7 | unsigned bit count | Number of valid payload bits |
| `payload` | 120 | bit payload | Packed Huffman/raw payload |

Trong flow active hien tai:

- `valid_bits` chi ro so bit that su co y nghia trong payload
- AES can word day de ma hoa, con bypass co the luu transport word truc tiep

## 6. Packing Rule

Packer lam viec theo quy tac:

1. load chunk bit vao buffer
2. chen bit vao vi tri LSB-first cua buffer noi bo
3. khi buffer >= 128 bit thi cat 128 bit ra mot word
4. neu frame ket thuc ma buffer con bit le thi pad 0 den du 128 bit

## 7. Storage Semantics

So voi bitstream raw:

- `bit_packer_128` khong doi noi dung Huffman
- no chi thay doi cach luu/truyen
- storage cost sau cung duoc quantize theo transport word 128-bit

Vi vay mode decision cua TX phai xem ket qua sau packer, khong chi xem
so bit Huffman thuan.

### 7.1 Internal registers

| Reg | Width | Data format | Meaning |
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

## 8. Error Conditions

Module co the bao loi neu:

- nhan `stream_valid` khi dang full ma khong co `stream_ready`
- `stream_len = 0` trong khi `stream_valid = 1`
- `stream_len > 32`
- frame ket thuc sai protocol

## 9. Related Specs

- [TX path end-to-end](./tx_path_end_to_end_spec.md)
- [System top `apb_huffman_aes_tx_top`](./apb_huffman_aes_tx_top_spec.md)
