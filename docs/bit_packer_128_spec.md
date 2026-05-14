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

## 3. High-Level Behavior

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

## 4. Input Contract

`bit_packer_128` nhan:

- `chunk_in[31:0]`
- `chunk_valid`
- `chunk_bits[5:0]`
- `frame_last`
- `ready`

Y nghia:

- `chunk_bits` cho biet bao nhieu bit trong `chunk_in` co y nghia
- `frame_last = 1` nghia la doan bitstream nay la cuoi frame

## 5. Output Contract

Module xuat:

- `transport_word[127:0]`
- `transport_valid`
- `transport_ready`
- `transport_bits[6:0]`
- `busy`
- `done`
- `error`

Trong flow active hien tai:

- `transport_bits` chi ro so bit that su co y nghia trong word 128-bit
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

## 8. Error Conditions

Module co the bao loi neu:

- nhan `chunk_valid` khi dang full ma khong co `ready`
- `chunk_bits = 0` trong khi `chunk_valid = 1`
- `chunk_bits > 32`
- frame ket thuc sai protocol

## 9. Related Specs

- [TX path end-to-end](./tx_path_end_to_end_spec.md)
- [System top `apb_huffman_aes_tx_top`](./apb_huffman_aes_tx_top_spec.md)
