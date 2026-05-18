# Huffman Block Decoder Specification

## 1. Mục đích

`huffman_block_decoder` nhận metadata/payload tu `huffman_block_parser`, phục hồi
plaintext byte stream và dua byte sang `rx_byte_packer_32`.

Module này không biet AES hay DMA. No chỉ decode từng Huffman/raw block.

Trạng thái kiểm chứng hiện tại:

| Case | Coverage/use |
|---|---|
| `dma_compress_aes_input1/input3/alnum63` | Normal decode of TX-generated whole-file frames |
| `rx_parser_decoder_cov` | Legal `RAW_FULL`, `RAW_PARTIAL`, `COMPRESSED`, `ONE_SYMBOL` decode paths |
| `rx_decoder_direct_cov` | Direct canonical lookup/fallback and byte-output branches |
| `rx_parser_decoder_error_direct_cov` | Duplicate/invalid code length/lookup miss/error paths |

## 2. Mode được hỗ trợ

| Mode | Định dạng dữ liệu | Decoder behavior |
|---|---|---|
| `RAW_FULL` | 2-bit mode code | Emit 32 raw bytes |
| `RAW_PARTIAL` | 2-bit mode code | Emit `block_size` raw bytes |
| `COMPRESSED` | 2-bit mode code | Rebuild canonical table when `symbol_count > 0`, or reuse previous table when `symbol_count == 0`, then decode payload bits |
| `ONE_SYMBOL` | 2-bit mode code | Emit repeated `one_symbol_value` |

## 3. Canonical Huffman Flow

```mermaid
flowchart LR
  ENT["table entries"] --> SORT["sort by code_len, symbol"]
  SORT --> ASSIGN["assign canonical codes"]
  ASSIGN --> TABLE["main lookup table + fallback"]
  TABLE --> DECODE["payload decode"]
```

Compressed mode steps:

1. if `symbol_count > 0`, receive all `symbol + code_len` entries
2. check duplicate symbol and invalid length
3. sort entries
4. assign canonical codes
5. fill main decode table for short codes
6. keep fallback list for long codes
7. if `symbol_count == 0`, reuse the valid table from the previous compressed block
8. consume payload bits until `block_size` bytes are emitted

## 4. Main Table And Fallback

Decoder uses `HUFFMAN_DECODE_TABLE_IP` as main lookup table.

Current split:

- main table handles prefixes up to `MAIN_LOOKUP_BITS = 11`
- longer codes are handled by fallback scan

This keeps decode architecture general while moving the common lookup into BRAM.

### 4.1 Decoder Inputs

| Cổng | Hướng | Độ rộng | Định dạng dữ liệu | Ý nghĩa |
|---|---|---:|---|---|
| `block_mode` | in | 2 | mode code | Block mode from parser |
| `block_size` | in | 6 | unsigned byte count | Expected bytes in current block |
| `symbol_count` | in | 9 | unsigned symbol count | Number of compressed entries |
| `one_symbol_value` | in | 8 | symbol byte | Repeated byte for one-symbol mode |
| `out_ready` | in | 1 | ready flag | Downstream byte packer ready |

## 5. Parser Handshake

| Tín hiệu | Hướng | Độ rộng | Định dạng dữ liệu | Ý nghĩa |
|---|---|---:|---|---|
| `block_meta_valid` | in | 1 | valid flag | Parser metadata valid |
| `block_meta_ready` | out | 1 | ready flag | Decoder can accept metadata |
| `entry_symbol` | in | 8 | symbol byte | Parser table entry symbol |
| `entry_code_len` | in | 5 | code length | Parser table entry code length |
| `entry_valid` | in | 1 | valid flag | Parser table entry valid |
| `entry_last` | in | 1 | bool | Parser table entry is last |
| `entry_ready` | out | 1 | ready flag | Decoder can accept entry |
| `payload_window_data` | in | 32 | little-endian chunk | Parser payload window |
| `payload_window_len` | in | 6 | unsigned bit count | Number of visible payload bits |
| `payload_window_valid` | in | 1 | valid flag | Payload window valid |
| `payload_consume_valid` | out | 1 | consume pulse | Consume payload bits |
| `payload_consume_len` | out | 6 | unsigned bit count | Number of payload bits to consume |
| `payload_block_done` | in | 1 | pulse | Parser reports block payload done |
| `parser_block_done` | in | 1 | pulse | Parser block-done notification |
| `parser_frame_done` | in | 1 | pulse | Parser frame-done notification |

## 6. Byte Contract output

| Cổng | Hướng | Độ rộng | Định dạng dữ liệu | Ý nghĩa |
|---|---|---:|---|---|
| `out_byte` | out | 8 | symbol byte | Decoded plaintext byte |
| `out_valid` | out | 1 | valid flag | Output byte valid |
| `out_last_in_block` | out | 1 | bool | Last byte in current block |
| `out_last_in_frame` | out | 1 | bool | Last byte in full frame |
| `out_ready` | in | 1 | ready flag | Downstream byte packer ready |
| `busy` | out | 1 | busy flag | Decoder active |
| `block_done` | out | 1 | pulse | Block completed |
| `frame_done` | out | 1 | pulse | Frame completed |
| `error_flag` | out | 1 | error flag | Decoder error |

`out_last_in_frame` is only asserted on the last plaintext byte of the full
frame, not just the last block.

## 7. Thanh ghi nội bộ

| Reg | Độ rộng | Định dạng dữ liệu | Ý nghĩa |
|---|---:|---|---|
| `state_r` | 5 | state code | Decoder state machine |
| `symbol_count_r` | 9 | unsigned symbol count | Current block symbol count |
| `one_symbol_value_r` | 8 | symbol byte | One-symbol mode value |
| `bytes_remaining_r` | 6 | unsigned byte count | Remaining bytes in current block |
| `current_block_is_frame_last_r` | 1 | bool | Current block is last in frame |
| `entry_load_count_r` | 9 | unsigned symbol count | Loaded canonical entries |
| `sort_pass_r` | 9 | unsigned pass count | Sort pass counter |
| `sort_idx_r` | 9 | unsigned index | Sort index |
| `assign_idx_r` | 9 | unsigned index | Canonical assign index |
| `table_build_idx_r` | 9 | unsigned index | Table build index |
| `table_clear_idx_r` | 11 | unsigned table index | Main table clear index |
| `table_fill_idx_r` | 11 | unsigned table index | Main table fill index |
| `table_fill_limit_r` | 11 | unsigned table index | Table fill limit |
| `table_prefix_r` | 11 | bit prefix | Current main-table prefix |
| `table_len_r` | 5 | code length | Current table code length |
| `table_symbol_r` | 8 | symbol byte | Current table symbol |
| `fallback_count_r` | 9 | unsigned symbol count | Fallback entry count |
| `fallback_scan_idx_r` | 9 | unsigned index | Fallback scan index |
| `fallback_prefix_seen_r` | 1 | bool | Fallback prefix match seen |
| `current_code_r` | 31 | code word | Current canonical code |
| `prev_len_r` | 5 | code length | Previous code length |
| `pending_final_byte_r` | 8 | symbol byte | Buffered final byte |
| `pending_final_frame_r` | 1 | bool | Buffered final frame flag |
| `out_byte_r` | 8 | symbol byte | Output byte register |
| `out_valid_r` | 1 | valid flag | Output valid |
| `out_last_in_block_r` | 1 | bool | Output last-in-block |
| `out_last_in_frame_r` | 1 | bool | Output last-in-frame |
| `payload_consume_valid_r` | 1 | consume pulse | Payload consume request |
| `payload_consume_len_r` | 6 | unsigned bit count | Number of payload bits consumed |
| `payload_block_done_r` | 1 | pulse | Payload block done |
| `block_done_r` | 1 | pulse | Block done |
| `frame_done_r` | 1 | pulse | Frame done |
| `error_r` | 1 | error flag | Error sticky |
| `table_valid_r` | 1 | valid flag | Canonical table valid |
| `debug_error_code_r` | 8 | error code | Debug error code |
| `debug_error_state_r` | 5 | state code | State at error |
| `debug_error_bytes_remaining_r` | 6 | unsigned byte count | Bytes remaining at error |
| `debug_error_payload_len_r` | 6 | unsigned bit count | Payload length at error |
| `symbol_local[]` | 256 x 8 | symbol array | Canonical symbol list |
| `len_local[]` | 256 x 5 | code length array | Canonical code lengths |
| `code_local[]` | 256 x 31 | code word array | Canonical code words |
| `fallback_symbol[]` | 256 x 8 | symbol array | Fallback symbol list |
| `fallback_len[]` | 256 x 5 | code length array | Fallback code lengths |
| `fallback_code[]` | 256 x 31 | code word array | Fallback code words |

## 8. Điều kiện lỗi

Decoder can raise `error_flag` for:

- invalid metadata for selected mode
- duplicate compressed symbol
- invalid code length
- malformed canonical order
- fallback table overflow
- lookup miss
- payload ended before enough bytes were decoded
- no matching long-code fallback entry

## 9. Spec liên quan

- [RX path end-to-end](./rx_path_end_to_end_spec.md)
- [Huffman block parser](./huffman_block_parser_spec.md)
- [RX byte packer 32](./rx_byte_packer_32_spec.md)
