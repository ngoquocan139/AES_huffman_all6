# Huffman, AES, And RISC-V DMA Flowchart Specification

Status: current RTL/software flowchart note for report drawing.

## 1. Purpose

Tai lieu nay gom cac flowchart can ve khi trinh bay TX secure-storage path:

- `huffman_aes_tx_top`
- `dynamic_huffman_encoder`
- luong nen Huffman
- luong ma hoa AES-128-CBC
- RV32I doc instruction va cau hinh DMA bang software

Flowchart trong tai lieu nay bam theo implementation hien tai. Control plane dung
RV32I load/store MMIO, khong dung custom RISC-V instruction.

## 2. Source Files

| Area | Source |
|---|---|
| TX Huffman/AES core | `rtl/huffman_aes_tx_top.v` |
| Dynamic Huffman encoder | `rtl/dynamic_huffman_encoder.v` |
| TX APB wrapper and CBC chaining | `rtl/apb_huffman_aes_tx_top.v` |
| RV32I pipeline | `rtl/top_rv32_sync.v` |
| MMIO to APB bridge | `rtl/cpu_mmio_to_apb_bridge.v` |
| DMA register file | `rtl/dma_regfile.v` |
| SoC wiring | `rtl/rv32_soc_top.v` |
| Firmware DMA helper | `testcase/secure_storage_fw.h` |

## 3. Overall TX Flow

```mermaid
flowchart LR
    FW["Firmware secure_write()"] --> MMIO["RV32I MMIO stores"]
    MMIO --> REG["dma_regfile config"]
    REG --> DMA["dma_tx_engine"]
    DMA --> READ["Read plaintext from DMEM"]
    READ --> TX["apb_huffman_aes_tx_top"]
    TX --> HUFFAES["huffman_aes_tx_top"]
    HUFFAES --> PACKED["128-bit Huffman transport blocks"]
    PACKED --> POLICY{"compress_only?"}
    POLICY -->|"no"| CBCAES["CBC XOR + AES encrypt"]
    POLICY -->|"yes"| BYPASS["Bypass AES"]
    CBCAES --> OUT["32-bit output FIFO words"]
    BYPASS --> OUT
    OUT --> WRITE["DMA writes result to DMEM"]
    WRITE --> STATUS["dma_regfile done/error/status"]
    STATUS --> FW
```

## 4. Flowchart: `huffman_aes_tx_top`

`huffman_aes_tx_top` la TX datapath core ben trong `apb_huffman_aes_tx_top`.
Module nay nhan word 32-bit tu APB-side TX interface, chuyen thanh byte stream,
build hoac dung whole-file Huffman codebook, nen stream, pack thanh block 128-bit,
roi phat `cipher_en/data_in` cho parent wrapper.

```mermaid
flowchart TD
    A["Idle"] --> B{"start_block?"}
    B -->|"no"| A
    B -->|"yes"| C["Latch policy: block_size, continue_frame, whole_file flags"]

    C --> D{"whole_file_count_mode?"}
    D -->|"yes"| E["Accept input words"]
    E --> F["Word adapter: 32-bit word to byte stream"]
    F --> G["frequency_counter counts file bytes"]
    G --> H{"all count bytes received?"}
    H -->|"no"| E
    H -->|"yes"| Z["tx_done for count phase"]
    Z --> I{"global_build_start from wrapper?"}
    I -->|"no"| I
    I -->|"yes"| J["Run file huffman_builder"]
    J --> K{"global_build_done?"}
    K -->|"no"| J
    K -->|"yes"| AA["Mark global table valid"]
    AA --> AB["global_build_done visible to wrapper"]

    D -->|"no"| L["Accept input words for emit phase"]
    L --> M["Word adapter queues bytes"]
    M --> N["dynamic_huffman_encoder"]
    N --> O["Huffman chunks: stream_data, stream_len, stream_last"]
    O --> P["bit_packer_128"]
    P --> Q{"128-bit transport valid?"}
    Q -->|"no"| L
    Q -->|"yes"| R{"AES wrapper ready?"}
    R -->|"no"| Q
    R -->|"yes"| S["Drive cipher_en and data_in"]
    S --> T{"last packed block accepted?"}
    T -->|"no"| L
    T -->|"yes"| U["tx_done for emit phase"]

    U --> A
    AB --> A
```

Key notes:

- `tx_done` cua core bao giai doan TX core da xong; parent wrapper van phai
  drain AES/bypass output FIFO ve DMA.
- Whole-file flow co ba buoc control: count bytes, wrapper pulses
  `global_build_start` de build codebook, sau do emit compressed data.
- `data_in` la Huffman transport block 128-bit; AES-CBC XOR nam o parent
  `apb_huffman_aes_tx_top`, khong nam trong `huffman_aes_tx_top`.

## 5. Flowchart: `dynamic_huffman_encoder`

`dynamic_huffman_encoder` gom ba khoi chinh:

- `control_fsm`: dieu phoi collect/build/emit
- `input_collect_unit`: nhan byte va luu block buffer
- `emit_backend`: phat header/table/payload Huffman ra stream bit chunks

Trong FPGA synthesis path hien tai, whole-file external codebook la path active.
Local per-block builder chi la legacy/non-synthesis fallback.

```mermaid
flowchart TD
    A["Idle"] --> B{"start_block?"}
    B -->|"no"| A
    B -->|"yes"| C["control_fsm enters collect"]

    C --> D["input_collect_unit accepts byte_in"]
    D --> E["Store byte into block buffer"]
    E --> F["Update local frequency counters"]
    F --> G{"block_end or block full?"}
    G -->|"no"| D
    G -->|"yes"| H{"whole_file_enable?"}

    H -->|"yes"| I{"whole_file_table_valid?"}
    I -->|"no"| W["Set encoder error: external table missing"]
    I -->|"yes"| J["Select external symbol/code_len/code table"]

    H -->|"no"| K["Legacy local build path"]
    K --> L["Build local Huffman table when enabled"]
    L --> J

    J --> M["emit_backend starts"]
    M --> N["Emit Huffman frame header/table"]
    N --> O["Read buffered symbols"]
    O --> P["Lookup canonical Huffman code"]
    P --> Q["Emit stream_data/stream_len"]
    Q --> R{"last symbol emitted?"}
    R -->|"no"| O
    R -->|"yes"| S["Assert stream_last"]
    S --> T{"downstream ready?"}
    T -->|"no"| S
    T -->|"yes"| U["Block done"]
    U --> A
    W --> A
```

Important handshake points:

- `byte_ready` comes from collect capacity and FSM state.
- `stream_valid/stream_ready` protects the output bit-chunk stream.
- External codebook read addresses are generated by the encoder and served by
  the whole-file builder in `huffman_aes_tx_top`.
- In whole-file mode, `whole_file_table_valid` must already be high when
  collection finishes; otherwise `control_fsm` raises encoder error.

## 6. Flowchart: Huffman Compression

Day la algorithm-level flow dung de ve slide/report. No tuong ung voi whole-file
dynamic Huffman policy hien tai.

```mermaid
flowchart TD
    A["Input plaintext bytes"] --> B["Count frequency for each byte value"]
    B --> C["Create symbol list with non-zero frequency"]
    C --> D{"symbol count == 0?"}
    D -->|"yes"| E["Emit empty frame/status"]
    D -->|"no"| F{"symbol count == 1?"}
    F -->|"yes"| G["Assign one-bit code to the only symbol"]
    F -->|"no"| H["Build Huffman tree from lowest frequencies"]
    H --> I["Compute code length for each symbol"]
    G --> J["Canonical code generation"]
    I --> J
    J --> K["Emit frame header and code-length table"]
    K --> L["Read original bytes again"]
    L --> M["Replace each byte by its Huffman code"]
    M --> N["Append variable-length bits to output stream"]
    N --> O{"all bytes encoded?"}
    O -->|"no"| L
    O -->|"yes"| P["Pad/flush bitstream"]
    P --> Q["Pack into 128-bit transport blocks"]
```

Mapping to RTL:

| Step | RTL block |
|---|---|
| Count frequencies | `frequency_counter` |
| Build tree/code lengths | `huffman_builder` |
| Canonical lookup and emission | `dynamic_huffman_encoder.emit_backend` |
| 128-bit packing | `bit_packer_128` |

## 7. Flowchart: AES-128-CBC Encryption

AES-CBC encryption for TX nam trong `apb_huffman_aes_tx_top`. Huffman core chi
tao transport block; parent wrapper XOR voi IV/ciphertext truoc va cap block cho
`aes128_cipher_top`.

```mermaid
flowchart TD
    A["Huffman transport block data_in_w"] --> B{"compress_only?"}
    B -->|"yes"| C["Bypass AES"]
    C --> D["Capture 128-bit output block"]

    B -->|"no"| E{"First AES block in transfer?"}
    E -->|"yes"| F["prev = cbc_iv_i from dma_regfile"]
    E -->|"no"| G["prev = previous ciphertext block"]
    F --> H["plain_to_aes = data_in_w XOR prev"]
    G --> H
    H --> I["Assert cipher_en_w"]
    I --> J["aes128_cipher_top encrypts one 128-bit block"]
    J --> K{"aes_ready_core_w?"}
    K -->|"no"| J
    K -->|"yes"| L["Capture aes_data_out"]
    L --> M["Update CBC chain = aes_data_out"]
    M --> D

    D --> N["Serialize 128-bit block into four 32-bit APB words"]
    N --> O["TX output FIFO"]
    O --> P["dma_tx_engine drains FIFO"]
    P --> Q["Write ciphertext/compressed output to DMEM"]
```

CBC contract:

- First block uses `cbc_iv_i`.
- Later blocks use the previous ciphertext block.
- Firmware writes IV words into `dma_regfile` before starting TX.
- RX must restore the same IV before AES-CBC decrypt.

## 8. Flowchart: RV32I Instruction Fetch And Software DMA Config

Software controls DMA with normal RV32I instructions:

- instruction fetch reads IMEM through `if_stage_sync`
- decode/execute computes addresses and values
- store instructions to DMA MMIO become APB writes through
  `cpu_mmio_to_apb_bridge`
- load instructions from DMA MMIO poll status/result registers

```mermaid
flowchart TD
    A["Reset PC"] --> B["IF: request IMEM at PC"]
    B --> C["IMEM returns instruction"]
    C --> D["ID: decode RV32I instruction"]
    D --> E{"Instruction type?"}

    E -->|"ALU/branch"| F["EX updates register/PC state"]
    F --> B

    E -->|"store to normal DMEM"| G["MEM writes DMEM"]
    G --> B

    E -->|"load from normal DMEM"| H["MEM reads DMEM"]
    H --> B

    E -->|"store to DMA MMIO"| I["Address hits 0x4000_0000 DMA range"]
    I --> J["cpu_mmio_to_apb_bridge creates APB write"]
    J --> K["dma_regfile captures register write"]
    K --> L{"CONTROL.start written?"}
    L -->|"no"| B
    L -->|"yes"| M["dma_regfile emits start_pulse_o"]

    M --> N["DMA engine runs configured transfer"]
    N --> O["TX/RX accelerator processes data"]
    O --> P["DMA updates busy/done/error/bytes counters"]

    E -->|"load from DMA MMIO"| Q["Address hits DMA status/result register"]
    Q --> R["cpu_mmio_to_apb_bridge creates APB read"]
    R --> S["dma_regfile returns PRDATA"]
    S --> T["CPU writes value to rd"]
    T --> U{"done or error sticky set?"}
    U -->|"no"| B
    U -->|"yes"| V["Firmware reads result counters/debug"]
```

Firmware configuration order in `secure_run_dma()`:

```mermaid
flowchart TD
    A["secure_run_dma(src, dst, len, mode)"] --> B["Clear result struct"]
    B --> C["Write CONTROL clear sticky flags"]
    C --> D["Write SRC_ADDR"]
    D --> E["Write DST_ADDR"]
    E --> F["Write LEN_BYTES"]
    F --> G["Write MODE"]
    G --> H["Write BLOCK_CFG"]
    H --> I["Poll STATUS until config valid"]
    I --> J["Write CONTROL.start"]
    J --> K["Poll STATUS"]
    K --> L{"done?"}
    L -->|"no"| M{"error or timeout?"}
    M -->|"no"| K
    M -->|"yes"| N["Return failure code"]
    L -->|"yes"| O["Read BYTES_DONE, CIPHERTEXT_BYTES_PRODUCED, DEBUG"]
    O --> P["Return success code"]
```

## 9. Suggested Figure Set For Report

| Figure | Use |
|---|---|
| Overall TX Flow | High-level architecture slide |
| `huffman_aes_tx_top` Flowchart | RTL datapath explanation |
| `dynamic_huffman_encoder` Flowchart | Huffman encoder internal explanation |
| Huffman Compression Flow | Algorithm explanation |
| AES-128-CBC Encryption Flow | Security/encryption explanation |
| RV32I Instruction Fetch And DMA Config | Software-controlled accelerator explanation |
