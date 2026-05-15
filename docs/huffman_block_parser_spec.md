# Huffman Block Parser Specification

## 1. Purpose

`huffman_block_parser` nhan bit chunks tu `bit_depacker_128`, tach thanh metadata
block, table entry va payload window cho `huffman_block_decoder`.

Parser khong tu decode Huffman symbol. No chi parse format transport cua TX.

Current verification status:

| Case | Coverage/use |
|---|---|
| `dma_compress_aes_input1/input3/alnum63` | Normal parser path from real TX transport stream |
| `rx_parser_decoder_cov` | Legal raw/compressed/one-symbol parser branches |
| `rx_parser_decoder_error_direct_cov` | Invalid mode/size/table/payload parser branches |
| `rx_depacker_packer_direct_cov` | Parser receives malformed depacker output and reports error |

## 2. Position In RX Path

```text
bit_depacker_128
-> huffman_block_parser
-> huffman_block_decoder
```

## 3. Supported Block Modes

| Bits | Mode | Data format | Parser action |
|---:|---|---|---|
| `00` | `RAW_FULL` | 2-bit mode code | Set block size 32, expose raw payload |
| `01` | `RAW_PARTIAL` | 2-bit mode code | Parse 6-bit block size, expose raw payload |
| `10` | `COMPRESSED` | 2-bit mode code | Parse 6-bit block size, 9-bit symbol count, table entries, payload |
| `11` | `ONE_SYMBOL` | 2-bit mode code | Parse block size and repeated symbol |

## 4. Parser State Flow

```mermaid
flowchart LR
  M["ST_PARSE_MODE"] --> RP["RAW_PARTIAL"]
  M --> OS["ONE_SYMBOL"]
  M --> CF["COMP_FIXED"]
  M --> META["ST_META"]
  RP --> META
  OS --> META
  CF --> META
  META --> ENT["ST_ENTRY"]
  META --> PAY["ST_PAYLOAD"]
  ENT --> PAY
```

### 4.1 Input From Depacker

| Port | Dir | Width | Data format | Meaning |
|---|---|---:|---|---|
| `stream_data` | in | 32 | little-endian chunk | Input bit chunk from depacker |
| `stream_len` | in | 6 | unsigned bit count | Number of valid bits in `stream_data` |
| `stream_valid` | in | 1 | valid flag | Input chunk is valid |
| `stream_last` | in | 1 | bool | Last chunk of frame |
| `stream_ready` | out | 1 | ready flag | Parser can accept next chunk |

## 5. Outputs To Decoder

| Output | Width | Data format | Meaning |
|---|---:|---|---|
| `block_meta_valid` | 1 | valid flag | Metadata ready for decoder |
| `block_mode` | 2 | mode code | One of 4 block modes |
| `block_size` | 6 | unsigned byte count | Expected plaintext bytes in this block |
| `symbol_count` | 9 | unsigned symbol count | Number of compressed table entries; `0` means reuse previous table, `1..256` means load table |
| `one_symbol_value` | 8 | symbol byte | Repeated byte for one-symbol mode |
| `entry_valid` | 1 | valid flag | One `symbol + code_len` table entry valid |
| `entry_last` | 1 | bool | Last compressed table entry |
| `payload_window_valid` | 1 | valid flag | Payload bits available |
| `payload_window_len` | 6 | unsigned bit count | Number of valid payload bits visible |

## 6. Payload Handshake

Decoder consumes payload by asserting:

| Signal | Dir | Width | Data format | Meaning |
|---|---|---:|---|---|
| `payload_consume_valid` | out | 1 | valid flag | Consume payload bits |
| `payload_consume_len` | out | 6 | unsigned bit count | Number of payload bits to consume |
| `payload_block_done` | in | 1 | pulse | Decoder reports payload for current block fully consumed |

Parser then shifts the consumed bits out of its buffer. For compressed mode,
parser lets decoder decide how many bits correspond to the matched code.

## 7. Frame Done

Parser asserts:

- `block_done` when the current block payload is fully consumed
- `frame_done` when the final chunk has been consumed and no bits remain

## 8. Validation

Parser validates:

- legal block mode
- legal block size for raw/one-symbol/compressed modes
- legal symbol value: any byte `0x00..0xFF`
- legal compressed code length
- table entry format

## 9. Internal registers

| Reg | Width | Data format | Meaning |
|---|---:|---|---|
| `state_r` | 3 | state code | Parser state machine |
| `frame_active_r` | 1 | bool | Frame currently active |
| `frame_last_seen_r` | 1 | bool | Frame-last already seen |
| `block_mode_r` | 2 | mode code | Current block mode |
| `block_size_r` | 6 | unsigned byte count | Current block size |
| `symbol_count_r` | 9 | unsigned symbol count | Current symbol count |
| `one_symbol_value_r` | 8 | symbol byte | One-symbol mode byte |
| `raw_payload_bits_remaining_r` | 9 | unsigned bit count | Raw payload bits remaining |
| `entry_count_remaining_r` | 9 | unsigned symbol count | Table entries remaining |
| `block_meta_valid_r` | 1 | valid flag | Metadata valid |
| `entry_symbol_r` | 8 | symbol byte | Current table entry symbol |
| `entry_code_len_r` | 5 | code length | Current table entry code length |
| `entry_valid_r` | 1 | valid flag | Current entry valid |
| `entry_last_r` | 1 | bool | Current entry is last |
| `block_done_r` | 1 | pulse | Block done pulse |
| `frame_done_r` | 1 | pulse | Frame done pulse |
| `error_r` | 1 | error flag | Parser error sticky |

## 10. Related Specs

- [RX path end-to-end](./rx_path_end_to_end_spec.md)
- [Huffman block decoder](./huffman_block_decoder_spec.md)
- [Bit depacker 128](./bit_depacker_128_spec.md)
