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

- `stream_data[31:0]`
- `stream_len[5:0]`
- `stream_valid`
- `stream_last`
- `flush_on_last`
- `stream_ready`

Y nghia:

- `stream_len` cho biet bao nhieu bit trong `stream_data` co y nghia
- `stream_last = 1` nghia la chunk nay la cuoi block/packet tu encoder
- `flush_on_last = 1` yeu cau packer tao final transport word khi gap
  `stream_last`
- `stream_last = 1` nhung `flush_on_last = 0` la truong hop hop le khi TX
  dang `continue_frame`; packer giu bit trong frame hien tai va khong tao
  final transport word

## 5. Output Contract

Module xuat:

- `transport_word_out[127:0]`
- `transport_word_valid`
- `transport_word_ready`
- `busy`
- `done`
- `error_flag`

Trong flow active hien tai:

- so bit that su co y nghia khong di bang mot output rieng; no duoc nhung
  truc tiep vao `transport_word_out[126:120]`
- AES can word day de ma hoa, con bypass co the luu transport word truc tiep

Transport word format:

| Bits | Field | Meaning |
|---:|---|---|
| `127` | `frame_last` | `1` neu day la transport word cuoi frame |
| `126:120` | `valid_bits` | So bit payload hop le trong field payload |
| `119:0` | `payload` | 120 bit Huffman bitstream, LSB-first |

`done` pulse khi final transport word (`frame_last=1`) da duoc downstream
accept qua `transport_word_ready`.

## 6. Packing Rule

Packer lam viec theo quy tac:

1. load chunk bit vao buffer
2. chen bit vao vi tri LSB-first cua payload buffer noi bo
3. khi buffer du 120 bit payload thi tao transport word non-final
4. neu frame ket thuc ma buffer con bit le thi zero-pad payload field va set
   `frame_last=1`

## 7. Storage Semantics

So voi bitstream raw:

- `bit_packer_128` khong doi noi dung Huffman
- no chi thay doi cach luu/truyen
- storage cost sau cung duoc quantize theo transport word 128-bit

Vi vay neu can quyet dinh compressed/raw o cap storage, firmware phai so sanh
ket qua sau packer/AES padding, khong chi xem so bit Huffman thuan. RTL TX hien
khong con block-level mode decision.

## 8. Error Conditions

RTL hien tai chi set `error_flag` khi module accept mot chunk co length khong
hop le:

- `stream_len = 0` trong khi `stream_valid = 1`
- `stream_len > 32`

Cac truong hop backpressure khac duoc chan bang `stream_ready=0`, nen khong tao
loi rieng. `stream_last` ma `flush_on_last=0` khong phai loi; day la co che
noi nhieu Huffman block trong cung mot transport frame.

## 9. Related Specs

- [TX path end-to-end](./tx_path_end_to_end_spec.md)
- [System top `apb_huffman_aes_tx_top`](./apb_huffman_aes_tx_top_spec.md)
