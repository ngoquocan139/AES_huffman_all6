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

## 3. Flowchart Symbol Convention

Khi ve lai bang Word/PowerPoint, uu tien dung vai tro cua shape thay vi
chi dung hinh chu nhat va hinh thoi:

| Mermaid form | Meaning in this spec | Suggested Word flowchart shape |
|---|---|---|
| `(["..."])` | start, end, or externally visible phase completion | Terminator |
| `[/.../]` | firmware action, MMIO/APB transaction, DMEM read/write, stream I/O | Data / Input-Output |
| `["..."]` | internal transform or combinational/sequential processing step | Process |
| `[("...")]` | stored state, table, FIFO, register-file content, block buffer | Stored Data or Internal Storage |
| `{{"..."}}` | setup or initialization before the main step | Preparation |
| `{"..."}` | branch or control decision | Decision |

Main report intent:

- firmware, DMEM, and APB-visible transfers should look like I/O shapes;
- buffers, tables, and FIFOs should look like stored-data or internal-storage shapes;
- do not use the database cylinder just because something is "memory"; reserve it for
  a clearly modeled storage repository when that distinction helps;
- only real branch points should use diamonds;
- preparation hexagons should be reserved for setup/init steps, not generic state updates.

## 4. Overall TX Flow

```mermaid
flowchart LR
    FW(["Firmware secure_write()"]) --> MMIO[/"RV32I MMIO stores"/]
    MMIO --> REG[("dma_regfile config")]
    REG --> DMA["dma_tx_engine"]
    DMA --> READ[/"Read plaintext from DMEM"/]
    READ --> TX["apb_huffman_aes_tx_top"]
    TX --> HUFFAES["huffman_aes_tx_top"]
    HUFFAES --> PACKED[("128-bit Huffman transport blocks")]
    PACKED --> POLICY{"compress_only?"}
    POLICY -->|"no"| CBCAES["CBC XOR + AES encrypt"]
    POLICY -->|"yes"| BYPASS["Bypass AES"]
    CBCAES --> OUT[("32-bit output FIFO words")]
    BYPASS --> OUT
    OUT --> WRITE[/"DMA writes result to DMEM"/]
    WRITE --> STATUS[("dma_regfile done/error/status")]
    STATUS --> FW
```

## 5. Flowchart: `huffman_aes_tx_top`

`huffman_aes_tx_top` la TX datapath core ben trong `apb_huffman_aes_tx_top`.
Module nay nhan word 32-bit tu APB-side TX interface, chuyen thanh byte stream,
build hoac dung whole-file Huffman codebook, nen stream, pack thanh block 128-bit,
roi phat `cipher_en/data_in` cho parent wrapper.

```mermaid
flowchart TD
    A(["Idle"]) --> B{"start_block?"}
    B -->|"no"| A
    B -->|"yes"| C{{"Latch policy: block_size, continue_frame, whole_file flags"}}

    C --> D{"whole_file_count_mode?"}
    D -->|"yes"| E[/"Accept input words"/]
    E --> F["Word adapter: 32-bit word to byte stream"]
    F --> G[("frequency_counter counts file bytes")]
    G --> H{"all count bytes received?"}
    H -->|"no"| E
    H -->|"yes"| Z(["tx_done for count phase"])
    Z --> I{"global_build_start from wrapper?"}
    I -->|"no"| I
    I -->|"yes"| J["Run file huffman_builder"]
    J --> K{"global_build_done?"}
    K -->|"no"| J
    K -->|"yes"| AA["Set global_table_valid"]
    AA --> AB(["global_build_done visible to wrapper"])

    D -->|"no"| L[/"Accept input words for emit phase"/]
    L --> M[("Word adapter queued bytes")]
    M --> N["dynamic_huffman_encoder"]
    N --> O[("Huffman chunks: stream_data, stream_len, stream_last")]
    O --> P["bit_packer_128"]
    P --> Q{"128-bit transport valid?"}
    Q -->|"no"| L
    Q -->|"yes"| R{"AES wrapper ready?"}
    R -->|"no"| Q
    R -->|"yes"| S[/"Drive cipher_en and data_in"/]
    S --> T{"last packed block accepted?"}
    T -->|"no"| L
    T -->|"yes"| U(["tx_done for emit phase"])

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

## 6. Flowchart: `dynamic_huffman_encoder`

`dynamic_huffman_encoder` gom ba khoi chinh:

- `control_fsm`: dieu phoi collect/build/emit
- `input_collect_unit`: nhan byte va luu block buffer
- `emit_backend`: phat header/table/payload Huffman ra stream bit chunks

Trong FPGA synthesis path hien tai, whole-file external codebook la path active.
Local per-block builder chi la legacy/non-synthesis fallback.

```mermaid
flowchart TD
    A(["Idle"]) --> B{"start_block?"}
    B -->|"no"| A
    B -->|"yes"| C["control_fsm enters collect"]

    C --> D[/"input_collect_unit accepts byte_in"/]
    D --> E[("Store byte into block buffer")]
    E --> F[("Update local frequency counters")]
    F --> G{"block_end or block full?"}
    G -->|"no"| D
    G -->|"yes"| H{"whole_file_enable?"}

    H -->|"yes"| I{"whole_file_table_valid?"}
    I -->|"no"| W(["Set encoder error: external table missing"])
    I -->|"yes"| J[("Active symbol / code_len / code table")]

    H -->|"no"| K["Legacy local build path"]
    K --> L[("Build local Huffman table when enabled")]
    L --> J

    J --> M["emit_backend starts"]
    M --> N[/"Emit Huffman frame header or reuse header"/]
    N --> O[("Read buffered symbols")]
    O --> P["Lookup canonical Huffman code"]
    P --> Q[/"Emit stream_data and stream_len"/]
    Q --> R{"last symbol emitted?"}
    R -->|"no"| O
    R -->|"yes"| S[/"Assert stream_last"/]
    S --> T{"downstream ready?"}
    T -->|"no"| S
    T -->|"yes"| U(["Block done"])
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

## 7. Flowchart: Huffman Compression

Day la algorithm-level flow dung de ve slide/report. No tuong ung voi whole-file
dynamic Huffman policy hien tai.

```mermaid
flowchart TD
    A(["Start file encode"]) --> B[/"Pass 1: read plaintext bytes"/]
    B --> C[("Frequency histogram")]
    C --> D["Create symbol list with non-zero frequency"]
    D --> E{"symbol count == 0?"}
    E -->|"yes"| F(["Emit empty frame/status"])
    E -->|"no"| G{"symbol count == 1?"}
    G -->|"yes"| H["Assign one-bit code to the only symbol"]
    G -->|"no"| I["Build Huffman tree from lowest frequencies"]
    I --> J["Compute code length for each symbol"]
    H --> K["Canonical code generation"]
    J --> K
    K --> L[("Canonical codebook")]
    L --> M[/"Emit frame header and code-length table"/]
    M --> N[/"Pass 2: read original bytes again"/]
    N --> O{"more input bytes?"}
    O -->|"yes"| P["Lookup code for current byte"]
    P --> Q[/"Append payload bits to output stream"/]
    Q --> O
    O -->|"no"| R["Pad or flush remaining bitstream"]
    R --> S[("Pack into 128-bit transport blocks")]
```

Mapping to RTL:

| Step | RTL block |
|---|---|
| Count frequencies | `frequency_counter` |
| Build tree/code lengths | `huffman_builder` |
| Canonical lookup and emission | `dynamic_huffman_encoder.emit_backend` |
| 128-bit packing | `bit_packer_128` |

## 8. Flowchart: AES-128-CBC Encryption

AES-CBC encryption for TX nam trong `apb_huffman_aes_tx_top`. Huffman core chi
tao transport block; parent wrapper XOR voi IV/ciphertext truoc va cap block cho
`aes128_cipher_top`.

```mermaid
flowchart TD
    A[/"Huffman transport block data_in_w"/] --> B{"compress_only?"}
    B -->|"yes"| C[/"Bypass AES"/]
    C --> D[("Capture 128-bit output block")]

    B -->|"no"| E{"First AES block in transfer?"}
    E -->|"yes"| F[("prev = cbc_iv_i from dma_regfile")]
    E -->|"no"| G[("prev = previous ciphertext block")]
    F --> H["plain_to_aes = data_in_w XOR prev"]
    G --> H
    H --> I[/"Assert cipher_en_w"/]
    I --> J["aes128_cipher_top encrypts one 128-bit block"]
    J --> K{"aes_ready_core_w?"}
    K -->|"no"| J
    K -->|"yes"| L[("Capture aes_data_out")]
    L --> M["Update CBC chain register"]
    M --> D

    D --> N[/"Serialize 128-bit block into four 32-bit APB words"/]
    N --> O[("TX output FIFO")]
    O --> P[/"dma_tx_engine drains FIFO"/]
    P --> Q[/"Write ciphertext or compressed output to DMEM"/]
```

CBC contract:

- First block uses `cbc_iv_i`.
- Later blocks use the previous ciphertext block.
- Firmware writes IV words into `dma_regfile` before starting TX.
- RX must restore the same IV before AES-CBC decrypt.

## 9. Flowchart: RV32I Instruction Fetch And Software DMA Config

Software controls DMA with normal RV32I instructions:

- instruction fetch reads IMEM through `if_stage_sync`
- decode/execute computes addresses and values
- store instructions to DMA MMIO become APB writes through
  `cpu_mmio_to_apb_bridge`
- load instructions from DMA MMIO poll status/result registers

```mermaid
flowchart TD
    A(["Reset PC"]) --> B[/"IF: request IMEM at PC"/]
    B --> C[/"IMEM returns instruction"/]
    C --> D["ID: decode RV32I instruction"]
    D --> E{"Instruction type?"}

    E -->|"ALU/branch"| F["EX updates register/PC state"]
    F --> B

    E -->|"store to normal DMEM"| G[/"MEM writes DMEM"/]
    G --> B

    E -->|"load from normal DMEM"| H[/"MEM reads DMEM"/]
    H --> I[("CPU writes value to rd")]
    I --> B

    E -->|"store to DMA MMIO"| J{"Address hits 0x4000_0000 DMA range?"}
    J -->|"yes"| K[/"cpu_mmio_to_apb_bridge creates APB write"/]
    K --> L[("dma_regfile captures register write")]
    L --> M{"CONTROL.start written?"}
    M -->|"no"| B
    M -->|"yes"| N["dma_regfile emits start_pulse_o"]

    N --> O["DMA engine runs configured transfer"]
    O --> P["TX/RX accelerator processes data"]
    P --> Q[("DMA busy/done/error/bytes counters")]

    E -->|"load from DMA MMIO"| R{"Address hits DMA status/result register?"}
    R -->|"yes"| S[/"cpu_mmio_to_apb_bridge creates APB read"/]
    S --> T[("dma_regfile returns PRDATA")]
    T --> U[("CPU writes value to rd")]
    U --> V{"done or error sticky set?"}
    V -->|"no"| B
    V -->|"yes"| W[/"Firmware reads result counters/debug"/]
```

Firmware configuration order in `secure_run_dma()`:

```mermaid
flowchart TD
    A(["secure_run_dma(src, dst, len, mode)"]) --> B[("Clear result struct")]
    B --> C[/"Write CONTROL clear sticky flags"/]
    C --> D[/"Write SRC_ADDR"/]
    D --> E[/"Write DST_ADDR"/]
    E --> F[/"Write LEN_BYTES"/]
    F --> G[/"Write MODE"/]
    G --> H[/"Write BLOCK_CFG"/]
    H --> I[/"Read STATUS"/]
    I --> J{"config valid?"}
    J -->|"no"| I
    J -->|"yes"| K[/"Write CONTROL.start"/]
    K --> L[/"Read STATUS"/]
    L --> M{"done?"}
    M -->|"no"| N{"error or timeout?"}
    N -->|"no"| L
    N -->|"yes"| O(["Return failure code"])
    M -->|"yes"| P[/"Read BYTES_DONE, CIPHERTEXT_BYTES_PRODUCED, DEBUG"/]
    P --> Q(["Return success code"])
```

## 10. Suggested Figure Set For Report

| Figure | Use |
|---|---|
| Overall TX Flow | High-level architecture slide |
| `huffman_aes_tx_top` Flowchart | RTL datapath explanation |
| `dynamic_huffman_encoder` Flowchart | Huffman encoder internal explanation |
| Huffman Compression Flow | Algorithm explanation |
| AES-128-CBC Encryption Flow | Security/encryption explanation |
| RV32I Instruction Fetch And DMA Config | Software-controlled accelerator explanation |
