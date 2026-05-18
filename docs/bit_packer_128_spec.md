# Bit Packer 128 Specification

## 1. Purpose

`bit_packer_128` receives the bitstream from `dynamic_huffman_encoder`, collecting the resulting bits
into 128-bit transport words, then feeds the AES layer or bypass FIFO.

This module does not know anything about Huffman tree, codebook or DMA. It only ensures
bitstream is continuously packed into `transport_word`.

Current verification status:

| Case | Coverage/use |
|---|---|
| `tx_compress_only_input1/input4_cov` | Normal transport packing in TX-only storage measurement |
| `dma_compress_aes_input1/input3/alnum63` | Packing before AES-CBC in full loopback |
| `tx_compress_only_short_raw_cov` | Short final-word padding and partial valid bits |
| `tx_builder_packer_direct_cov` | Direct packer ready/valid and flush corner branches |
| `rx_depacker_packer_direct_cov` | Cross-check TX packer format against RX depacker assumptions |

## 2. In TX Stack Role

Position in the stack:

```text
dynamic_huffman_encoder
-> bit_packer_128
-> TX policy select
-> AES or bypass
```

`bit_packer_128` is the bridge:

- bit-level encoder output
- word-level crypto/storage datapath

## 3. Contract input

| Port | Direction | Width | Data format | Meaning |
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

## 4. High level behavior

```mermaid
flowchart LR
  IN["32-bit bit chunks"] --> SH["shift / accumulate"]
  SH --> OUT["128-bit transport word"]
  OUT --> FLUSH["flush on frame end"]
```

Module:

- 32-bit bit chunk reception
- Store the full bit in the counter register
- Outputs a 128-bit transport word when enough bits are available
- If the frame ends without 128 bits, zero-pad and flush

## 5. Contract output

| Port | Direction | Width | Data format | Meaning |
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

In the current active flow:

- `valid_bits` indicates the number of truly significant bits in the payload
- AES needs this word to encrypt, while bypass can store the transport word directly

## 6. Pack rules

Packer works according to the following rules:

1. load chunk bits into buffer
2. insert bits into the LSB-first position of the internal buffer
3. When buffer >= 128 bits, cut 128 bits out as one word
4. If the frame ends with the buffer remaining, then pad 0 to the full 128 bits

## 7. Storage semantics

Compared to bitstream raw:

- `bit_packer_128` does not change Huffman content
- it only changes the way it is saved/transmitted
- The final storage cost is quantized according to the 128-bit transport word

Therefore, the TX mode decision must use the results after the packer, not just see
the pure Huffman bit count.

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

## 8. Error conditions

The module may report an error if:

- receive `stream_valid` when full without `stream_ready`
- `stream_len = 0` while `stream_valid = 1`
- `stream_len > 32`
- frame ends in wrong protocol

## 9. Related specs

- [TX path end-to-end](./tx_path_end_to_end_spec.md)
- [System top `apb_huffman_aes_tx_top`](./apb_huffman_aes_tx_top_spec.md)
