# TX Path End-to-End Specification

## 1. Purpose

Tai lieu nay mo ta rieng nhanh `TX` cua SoC hien tai:

- module nao tham gia
- ket noi giua cac module
- chuc nang cua tung module
- flow chi tiet tu CPU/MMIO den `DMEM -> TX -> DMEM`

Spec nay chi mo ta path active hien tai trong repo.

Current verification status:

| Item | Status |
|---|---|
| Main TX loopback mode | `MODE=0x9`, whole-file Huffman + AES-CBC |
| TX-only saving mode | `MODE=0xD`, whole-file Huffman + AES bypass |
| Active TX testcase examples | `dma_compress_aes_input1`, `tx_compress_only_input4_cov`, `tx_apb_error_cov` |
| Coverage hooks | `tx_if_direct_cov`, `tx_encoder_direct_cov`, `tx_builder_packer_direct_cov` |
| Historical full regression | included in `34/34` PASS coverage baseline before secure-storage API refactor |

## 2. TX Goal

TX nhan plaintext trong `DMEM`, nen Huffman, sau do:

- neu `COMPRESS_AES`: ma hoa AES-128 CBC
- neu `COMPRESS_ONLY`: bo qua AES

va ghi output tro lai `DMEM`.

## 3. Top-Level TX Path

```mermaid
flowchart LR
    CPU["RV32I CPU"] --> BR[/"cpu_mmio_to_apb_bridge"/]
    BR --> REG[("dma_regfile")]
    REG --> TXDMA["dma_tx_engine"]
    REG --> IV[("IV0..IV3")]
    TXDMA --> DMEMR[/"DMEM Port B read"/]
    TXDMA --> TXAPB[/"private APB master"/]
    TXAPB --> TXTOP[/"apb_huffman_aes_tx_top"/]
    TXTOP --> TXFIFO[("TX output FIFO")]
    TXFIFO --> TXDMA
    TXDMA --> DMEMW[/"DMEM Port B write"/]
```

## 4. Modules And Roles

### 4.0 Module to spec map

| TX module | Spec |
|---|---|
| `top_rv32_sync` | [00_current_system_spec.md](./00_current_system_spec.md) |
| `cpu_mmio_to_apb_bridge` | [cpu_mmio_to_apb_bridge_spec.md](./cpu_mmio_to_apb_bridge_spec.md) |
| `dma_regfile` | [dma_regfile_spec.md](./dma_regfile_spec.md) |
| `dma_tx_engine` | [dma_tx_engine_spec.md](./dma_tx_engine_spec.md) |
| `dmem_ip_wrapper` / `DMEM_ip` | [bram_port_usage_spec.md](./bram_port_usage_spec.md) |
| `apb_huffman_aes_tx_top` | [apb_huffman_aes_tx_top_spec.md](./apb_huffman_aes_tx_top_spec.md) |
| `apb_huffman_tx_if` | [apb_huffman_aes_tx_top_spec.md](./apb_huffman_aes_tx_top_spec.md) |
| `huffman_aes_tx_top` | [apb_huffman_aes_tx_top_spec.md](./apb_huffman_aes_tx_top_spec.md) |
| `dynamic_huffman_encoder` | [dynamic_huffman_encoder_spec.md](./dynamic_huffman_encoder_spec.md) |
| `bit_packer_128` | [bit_packer_128_spec.md](./bit_packer_128_spec.md) |
| `aes128_cipher_top` | [apb_huffman_aes_tx_top_spec.md](./apb_huffman_aes_tx_top_spec.md) |
| whole-file Huffman policy | [14_dynamic_whole_file_huffman_spec.md](./14_dynamic_whole_file_huffman_spec.md) |
| IV/CBC contract | [iv_generation_and_cbc_contract_spec.md](./iv_generation_and_cbc_contract_spec.md) |

### 4.1 Control plane modules

| Module | Role |
|---|---|
| `top_rv32_sync` | Chay chuong trinh RV32I de cau hinh DMA |
| `cpu_mmio_to_apb_bridge` | Chuyen CPU MMIO read/write thanh APB transaction |
| `dma_regfile` | Giu config TX: `SRC_ADDR`, `DST_ADDR`, `LEN_BYTES`, `MODE`, `BLOCK_CFG`, `IV0..IV3` |

### 4.2 Data plane modules

| Module | Role |
|---|---|
| `DMEM_ip` / `dmem_ip_wrapper` | Noi luu plaintext input va ciphertext output |
| `dma_tx_engine` | Data mover TX, doc DMEM, lap trinh TX APB, drain output FIFO, ghi DMEM |
| `apb_huffman_aes_tx_top` | TX accelerator top |
| `apb_huffman_tx_if` | APB slave wrapper ben trong TX |
| `huffman_aes_tx_top` | Input adapter + Huffman TX + bit packer |
| `dynamic_huffman_encoder` | [dynamic_huffman_encoder_spec.md](./dynamic_huffman_encoder_spec.md) |
| `bit_packer_128` | [bit_packer_128_spec.md](./bit_packer_128_spec.md) |
| `aes128_cipher_top` | AES encrypt core active |

## 5. Key Connections

### 5.1 CPU to DMA register file

CPU ghi MMIO vao:

- `SRC_ADDR`
- `DST_ADDR`
- `LEN_BYTES`
- `MODE`
- `BLOCK_CFG`
- `IV0..IV3`
- `CONTROL.start`

### 5.2 `dma_regfile` to `dma_tx_engine`

`dma_regfile` xuat:

- `src_addr_o`
- `dst_addr_o`
- `len_bytes_o`
- `direction_o`
- `compress_only_o`
- `whole_file_o`
- `block_size_o`
- `start_pulse_o`

`dma_tx_engine` nhan bo config nay de chay transfer.

### 5.3 `dma_regfile` to TX CBC path

`dma_regfile` xuat:

```text
iv_o = {IV3, IV2, IV1, IV0}
```

Trong [rv32_soc_top.v](/mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/rtl/rv32_soc_top.v), `iv_o` duoc noi vao:

- `apb_huffman_aes_tx_top.cbc_iv_i`

### 5.4 `dma_tx_engine` to DMEM

`dma_tx_engine` dung `DMEM` Port B de:

- doc plaintext tu `SRC_ADDR`
- ghi ciphertext hoac compressed transport stream ve `DST_ADDR`

### 5.5 `dma_tx_engine` to `apb_huffman_aes_tx_top`

`dma_tx_engine` la private APB master cua TX:

- `tx_psel_o`
- `tx_penable_o`
- `tx_pwrite_o`
- `tx_paddr_o`
- `tx_pwdata_o`

TX top la APB slave tra:

- `tx_prdata_i`
- `tx_pready_i`
- `tx_pslverr_i`

## 6. Internal TX Structure

So do duoi day bam theo dung instance trong RTL:

- [rtl/apb_huffman_aes_tx_top.v](/mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/rtl/apb_huffman_aes_tx_top.v)
- [rtl/huffman_aes_tx_top.v](/mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/rtl/huffman_aes_tx_top.v)
- [rtl/dynamic_huffman_encoder.v](/mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/rtl/dynamic_huffman_encoder.v)

### 6.1 Top-level TX RTL wiring

```mermaid
flowchart LR
    DMA[/"dma_tx_engine<br/>APB master"/] --> APBIF["u_apb_huffman_tx_if
    apb_huffman_tx_if"]

    APBIF -->|"start_block_o, continue_frame_o,
    block_size_o, word_in_o,
    word_valid_o"| TXCORE["u_huffman_aes_tx_top
    huffman_aes_tx_top"]

    TXCORE -->|"word_ready"| APBIF

    TXCORE -->|"cipher_en, data_in,
    key, mode, init_vector,
    segment_len"| POLICY{"compress_only?"}

    POLICY -->|"0: COMPRESS_AES"| CBC["CBC XOR in
    apb_huffman_aes_tx_top
    tx_aes_plain_w = data_in_w XOR prev"]
    CBC --> AES["u_AES_top_tx
    aes128_cipher_top"]
    AES -->|"aes_data_out,
    aes_ready_core_w"| EMIT["AES/output capture
    aes_emit_block_r"]

    POLICY -->|"1: COMPRESS_ONLY"| BYPASS[/"bypass capture<br/>emit_capture_data_w = data_in_w"/]
    BYPASS --> EMIT

    EMIT -->|"aes_out_word_w,
    aes_out_word_valid_w,
    aes_out_word_last_w"| APBIF
    APBIF -->|"PRDATA/PREADY readback"| DMA
```

Trong `apb_huffman_aes_tx_top`, `u_apb_huffman_tx_if` la cua vao/ra APB.
`u_huffman_aes_tx_top` tao transport word 128-bit va phat `cipher_en`.
Neu `compress_only = 0`, parent top tu XOR CBC voi `cbc_iv_i`/ciphertext truoc
roi dua vao `u_AES_top_tx`. Neu `compress_only = 1`, parent top bo qua AES va
serialize transport word truc tiep ve APB output FIFO.

### 6.2 `huffman_aes_tx_top` RTL wiring

```mermaid
flowchart LR
    APBWORDS[/"APB 32-bit words<br/>word_in/word_valid"/] --> ADAPTER["input adapter
    inside huffman_aes_tx_top
    word -> byte"]

    ADAPTER -->|"count_byte_fire_w,
    current_byte_w"| GCOUNT[("u_file_frequency_counter<br/>frequency_counter")]
    GCOUNT -->|"file_freq_read_count_w"| GBUILD["u_file_huffman_builder
    huffman_builder"]
    GBUILD -->|"symbol/code length/code tables"| EXTBOOK[("external codebook wires<br/>file_symbol_*, file_code_len_*,<br/>file_code_*")]

    ADAPTER -->|"enc_start_block_w,
    enc_byte_in_w,
    enc_byte_valid_w,
    enc_block_start_w,
    enc_block_end_w"| ENC["u_dynamic_huffman_encoder
    dynamic_huffman_encoder"]

    EXTBOOK -->|"external_symbol_*,
    external_code_len_*,
    external_code_*"| ENC

    ENC -->|"encoder_stream_data,
    encoder_stream_len,
    encoder_stream_valid,
    encoder_stream_last"| PACK["u_bit_packer_128
    bit_packer_128"]
    PACK -->|"encoder_stream_ready"| ENC

    PACK -->|"packer_transport_word,
    packer_transport_valid"| WRAP[("u_aes_input_wrapper<br/>wrapper")]
    WRAP -->|"block_accept"| PACK

    WRAP -->|"cipher_en, data_in,
    key, mode, init_vector,
    segment_len"| PARENT[/"parent:<br/>apb_huffman_aes_tx_top<br/>CBC/AES/bypass"/]
```

Duong whole-file Huffman co 2 pha:

1. Count/build phase:
   `input adapter -> u_file_frequency_counter -> u_file_huffman_builder`.
   Firmware/DMA nap toan file de dem tan suat, sau do pulse `global_build_start`.
2. Emit phase:
   `input adapter -> u_dynamic_huffman_encoder`, trong do encoder doc codebook
   tu `u_file_huffman_builder` qua cac port `external_*`, roi emit bitstream
   sang `u_bit_packer_128`.

Trong synthesis, `dynamic_huffman_encoder` ep `whole_file_mode_w = 1'b1`, nen
codebook active la codebook whole-file tu `u_file_huffman_builder` ben ngoai.
Nhanh `huffman_builder` noi bo trong `dynamic_huffman_encoder` chi con dung cho
mo phong/per-block legacy khi khong define `SYNTHESIS`.

### 6.3 `dynamic_huffman_encoder` RTL wiring

```mermaid
flowchart LR
    FSM["u_control_fsm
    control_fsm"] -->|"start_collect"| ICU["u_input_collect_unit
    input_collect_unit"]
    ICU -->|"collect_done/error"| FSM

    BYTE[/"byte_in/byte_valid<br/>from huffman_aes_tx_top adapter"/] --> ICU

    ICU --> BUF[("u_block_buffer<br/>inside input_collect_unit")]
    ICU --> LFREQ[("u_frequency_counter<br/>inside input_collect_unit")]

    FSM -->|"start_emit"| EMIT["u_emit_backend
    emit_backend"]
    BUF -->|"buffer_read_data"| EMIT

    EXT[("external whole-file codebook<br/>from u_file_huffman_builder")] -->|"symbol/code tables"| EMIT

    EMIT --> HDR["u_header_formatter
    header_formatter"]
    EMIT --> PAY["u_payload_emitter
    payload_emitter"]
    HDR --> STREAM["u_stream_output_interface
    stream_output_interface"]
    PAY --> STREAM

    STREAM -->|"stream_data,
    stream_len,
    stream_valid,
    stream_last"| PACKER[("u_bit_packer_128")]
```

`u_input_collect_unit` giu lai byte cua block trong `u_block_buffer`. Khi emit,
`u_emit_backend` doc:

- payload byte tu `u_block_buffer`;
- symbol/code length/code tu codebook whole-file ben ngoai;
- header chunk tu `u_header_formatter`;
- payload chunk tu `u_payload_emitter`.

`u_stream_output_interface` hop nhat header va payload thanh stream chung
`stream_data/stream_len/stream_valid/stream_last` de dua sang `u_bit_packer_128`.

### 6.4 TX module connection table

| From | To | Main signals | Meaning |
|---|---|---|---|
| `dma_tx_engine` | `u_apb_huffman_tx_if` | APB `PSEL/PENABLE/PWRITE/PADDR/PWDATA` | DMA ghi control va input words vao TX |
| `u_apb_huffman_tx_if` | `u_huffman_aes_tx_top` | `start_block_o`, `continue_frame_o`, `block_size_o`, `word_in_o`, `word_valid_o` | Bat dau block va dua word 32-bit vao TX core |
| `u_huffman_aes_tx_top` | `u_apb_huffman_tx_if` | `word_ready`, `tx_busy`, `tx_done`, `tx_error`, global build status | Backpressure va status |
| Input adapter | `u_file_frequency_counter` | `count_byte_fire_w`, `current_byte_w` | Dem tan suat whole-file |
| `u_file_frequency_counter` | `u_file_huffman_builder` | `file_freq_read_index_w`, `file_freq_read_count_w` | Builder doc bang tan suat |
| `u_file_huffman_builder` | `u_dynamic_huffman_encoder` | `external_symbol_*`, `external_code_len_*`, `external_code_*` | Cap codebook canonical whole-file |
| Input adapter | `u_dynamic_huffman_encoder` | `enc_byte_in_w`, `enc_byte_valid_w`, `enc_block_start_w`, `enc_block_end_w` | Dua byte payload vao encoder |
| `u_dynamic_huffman_encoder` | `u_bit_packer_128` | `encoder_stream_*` | Stream bit Huffman dang chunk 32-bit |
| `u_bit_packer_128` | `u_aes_input_wrapper` | `packer_transport_word`, `packer_transport_valid`, `block_accept` | Gom thanh transport word 128-bit |
| `u_aes_input_wrapper` | parent top | `cipher_en_w`, `data_in_w`, `key_w` | Yeu cau encrypt/bypass 1 transport block |
| parent CBC logic | `u_AES_top_tx` | `tx_aes_plain_w`, `cipher_en_w`, `key_w` | AES-CBC encrypt |
| parent output serializer | `u_apb_huffman_tx_if` | `aes_out_word_w`, `aes_out_word_valid_w`, `aes_out_word_last_w` | Cat 128-bit output thanh 4 word 32-bit cho DMA doc |

## 7. Function Of Each TX Stage

### 7.1 `apb_huffman_tx_if`

Chuc nang:

- nhan `BLOCK_SIZE`
- nhan `WORD_IN`
- nhan `START_BLOCK`
- giu FIFO input APB
- expose output FIFO cua TX de DMA doc
- giu sticky status / error

### 7.2 Input adapter

Chuyen tung word 32-bit thanh byte stream theo thu tu byte noi bo cua TX.

### 7.3 `dynamic_huffman_encoder`

Chuc nang:

- collect byte cua block
- dung codebook global whole-file trong synthesis
- codebook per-block chi la nhanh legacy/mo phong khi khong define `SYNTHESIS`
- active TX hien emit mode `COMPRESSED` co dinh
- emit header + payload bitstream

TX RTL giu 2 kha nang, nhung flow FPGA/synthesis hien tai dung whole-file:

- whole-file dynamic Huffman: datapath active tren FPGA;
- per-block dynamic Huffman: nhanh legacy/mo phong, khong phai flow bao cao chinh.

Trong `whole_file` mode, "whole-file" nghia la codebook/frequency table duoc
tinh tren toan input. Du lieu van duoc DMA feed vao TX theo cac block payload
toi da 32 byte de giu adapter, packer, AES-CBC va RX parser khop voi RTL hien
tai.

### 7.4 `bit_packer_128`

Gop bitstream thanh `transport_word` 128-bit.

Neu transfer con block tiep theo trong cung frame:

- packer giu frame lien tuc
- chi flush o block cuoi

### 7.5 CBC + AES

Neu `compress_only = 0`:

```text
C0 = AES_encrypt(P0 XOR IV)
Cn = AES_encrypt(Pn XOR Cn-1)
```

Neu `compress_only = 1`:

- bo qua AES
- output la compressed transport stream

### 7.6 Output FIFO

Luu output 32-bit word de `dma_tx_engine` drain qua APB:

- `AES_OUT_STATUS`
- `AES_OUT_META`
- `AES_OUT_DATA`

Area-optimized implementation notes:

- Global frequency, Huffman tree, code-length, canonical-code, block-buffer,
  and APB FIFO tables infer distributed RAM in `rv32_soc_synth_tx_opt4`.
- Large table contents are not reset entry-by-entry in synthesis; reset clears
  control state and validity only.
- `code_length_builder` separates parent/weight/order table writes into
  one-write-port memory processes, which removes the previous LUT/FF explosion.
- Latest TX-only implementation at 50 MHz: `11933` LUTs, `5469` FFs,
  `3979` slices, `208` control sets, WNS `+1.277 ns`.
- Latest full ZCU102 TX+RX implementation and bitstream pass:
  `37069` LUTs, `19794` FFs, `7360` CLBs, `1794` control sets, WNS
  `+7.871 ns`, WHS `+0.015 ns`, vectorless power `0.793 W`.

## 8. TX Software Flow

### 8.1 CPU steps

1. nap plaintext vao `DMEM`
2. ghi `SRC_ADDR`
3. ghi `DST_ADDR`
4. ghi `LEN_BYTES = plaintext_len`
5. ghi `MODE`
6. ghi `BLOCK_CFG`
7. neu dung AES, ghi `IV0..IV3`
8. ghi `CONTROL.start`
9. poll `STATUS`
10. doc `CIPHERTEXT_BYTES_PRODUCED`

### 8.2 Main TX mode currently used

Mode regression chinh hien tai:

- `MODE = 0x9`
- nghia la `TX + COMPRESS_AES + whole_file`
- `BLOCK_CFG = 32`

## 9. TX DMA Flow

### 9.1 Start and config

`dma_tx_engine`:

1. doi `start_i`
2. check:
   - `direction_i == TX`
   - `len_bytes_i != 0`
   - `block_size_i` hop le
   - `src/dst` aligned
3. snapshot config
4. soft reset TX wrapper
5. lap trinh `TX_POLICY`

Neu `whole_file_i = 1`, engine chay them pha global-count/global-build truoc pha emit.

### 9.2 Block chunk load

Voi moi block:

1. tinh `current_block_bytes = min(bytes_remaining, block_size)`
2. tinh `words_remaining = ceil(current_block_bytes / 4)`
3. ghi `BLOCK_SIZE`
4. doc tung word tu `DMEM`
5. ghi tung `WORD_IN`
6. poll `TX STATUS.can_start`
7. ghi `START_BLOCK`

Trinh tu nay van xay ra trong `whole_file` mode. Khac biet la count pass dung
cac block nay chi de dem tan suat, con emit pass dung global codebook da build
tu toan file thay vi build codebook moi cho tung block.

### 9.3 Continue-frame policy

Neu transfer con block nua:

- `START_BLOCK = 0x3`
- bit `continue_frame = 1`

Neu la block cuoi:

- `START_BLOCK = 0x1`
- bit `continue_frame = 0`

### 9.4 Output drain

Sau khi block da duoc TX xu ly:

1. poll `AES_OUT_STATUS`
2. neu FIFO nonempty:
   - doc `AES_OUT_META`
   - doc `AES_OUT_DATA`
   - ghi word output ve `DMEM`
3. lap lai cho toi khi output FIFO rong

### 9.5 Completion

Transfer TX complete khi:

- khong con plaintext input
- output FIFO da duoc drain
- TX wrapper da idle on dinh

Luc do:

- `dma_done_o` pulse
- `bytes_done_o` chua so byte output da ghi ve `DMEM`
- `CIPHERTEXT_BYTES_PRODUCED` mirror gia tri nay cho software

## 10. Active Data Meaning

### 10.1 TX input

- `SRC_ADDR` tro vao plaintext trong `DMEM`
- `LEN_BYTES` la so plaintext byte

### 10.2 TX output

Neu `COMPRESS_AES`:

- output la ciphertext stream sau Huffman + CBC + AES

Neu `COMPRESS_ONLY`:

- output la compressed transport stream, chua encrypt

## 11. Current Main Regression Flow

```text
CPU writes MODE=0x9, BLOCK_CFG=32, IV0..IV3
-> start TX
-> DMA TX reads plaintext from DMEM
-> whole-file Huffman encode
-> bit_packer_128
-> CBC XOR
-> aes128_cipher_top
-> output FIFO
-> DMA TX drains output
-> ciphertext written back to DMEM
-> CPU reads CIPHERTEXT_BYTES_PRODUCED
```

## 12. Current Limitations

- `COMPRESS_ONLY` TX da chay duoc, nhung RX symmetric bypass path chua la flow chinh
- key AES hien tai la fixed key trong RTL
- IV hien tai do firmware RV32I tao va luu trong metadata, chua phai entropy manh
- TX top khong dung `AES_top.v` da-mode; chi dung `aes128_cipher_top` + CBC wrapper nho
- raw full coverage cua TX-related logic van bi keo boi toggle va mot so condition/expression hiem; functional branch/statement closure da dat trong regression chung

## 13. Source Files

- [rv32_soc_top.v](/mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/rtl/rv32_soc_top.v)
- [dma_tx_engine.v](/mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/rtl/dma_tx_engine.v)
- [apb_huffman_aes_tx_top.v](/mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/rtl/apb_huffman_aes_tx_top.v)
- [dma_regfile.v](/mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/rtl/dma_regfile.v)
- [dynamic_huffman_encoder_spec.md](/mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/docs/dynamic_huffman_encoder_spec.md)
- [bit_packer_128_spec.md](/mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/docs/bit_packer_128_spec.md)
- [test_mmio_dma.c](/mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/testcase/test_mmio_dma.c)
