# 00. Current SoC System Specification

## 1. Purpose

Tai lieu nay la spec tong cua SoC hien tai trong repo. Day la file doc dau
tien can doc truoc khi di vao TX, RX, DMA, MMIO, UART loader hoac Vivado.

Muc tieu he thong:

```text
Plaintext in DMEM
-> TX DMA
-> dynamic Huffman compression
-> AES-128 CBC encrypt, or AES bypass for COMPRESS_ONLY
-> output back to DMEM

Ciphertext/transport stream in DMEM
-> RX DMA
-> AES-128 CBC decrypt
-> Huffman decode
-> plaintext back to DMEM
```

`RV32I` la control plane. CPU cau hinh DMA qua MMIO va polling status. CPU
khong phai khoi di chuyen du lieu toc do cao.

## 2. Top-Level System Diagram

```mermaid
flowchart LR
  HOST["Host PC"]
  UART["uart_dmem_loader"]
  TOP["rv32_soc_fpga_demo_top"]
  CPU["top_rv32_sync\nRV32I CPU"]
  IMEM["IMEM_ip / imem_sync\ninstruction.mem"]
  DMEM["DMEM_ip / dmem_ip_wrapper\n32 KiB data memory"]
  BRIDGE["cpu_mmio_to_apb_bridge"]
  REG["dma_regfile\nDMA MMIO registers"]
  TXDMA["dma_tx_engine"]
  RXDMA["dma_rx_engine"]
  TXTOP["apb_huffman_aes_tx_top"]
  RXTOP["apb_huffman_aes_rx_top"]

  HOST -->|"UART LOAD frame"| UART
  UART -->|"aux Port B preload"| DMEM
  UART -->|"release reset after load"| TOP
  TOP --> CPU

  CPU -->|"fetch"| IMEM
  CPU <-->|"load/store"| DMEM
  CPU -->|"MMIO access"| BRIDGE
  BRIDGE -->|"APB"| REG

  REG -->|"config/start/status"| TXDMA
  REG -->|"config/start/status"| RXDMA
  REG -->|"IV0..IV3"| TXTOP
  REG -->|"IV0..IV3"| RXTOP

  TXDMA <-->|"Port B read/write"| DMEM
  RXDMA <-->|"Port B read/write"| DMEM

  TXDMA -->|"private APB write/read"| TXTOP
  TXTOP -->|"output FIFO readback"| TXDMA

  RXDMA -->|"128-bit ciphertext stream"| RXTOP
  RXTOP -->|"APB output readback"| RXDMA
```

## 3. Active Module List

| Module | Role | Active use |
|---|---|---|
| `rv32_soc_top` | SoC integration top for simulation/core integration | Active |
| `rv32_soc_fpga_demo_top` | FPGA wrapper with UART loader and LEDs | Active FPGA demo top |
| `top_rv32_sync` | RV32I CPU core | Active |
| `IMEM_ip` / `imem_sync` | Instruction memory | Active |
| `DMEM_ip` / `dmem_ip_wrapper` | Data memory with CPU/DMA/aux access | Active |
| `cpu_mmio_to_apb_bridge` | CPU MMIO to APB master bridge | Active |
| `dma_regfile` | CPU-visible DMA control/status registers | Active |
| `dma_tx_engine` | `DMEM -> TX accelerator -> DMEM` data mover | Active |
| `dma_rx_engine` | `DMEM -> RX accelerator -> DMEM` data mover | Active |
| `apb_huffman_aes_tx_top` | TX Huffman compress + AES-CBC encrypt/bypass | Active |
| `apb_huffman_aes_rx_top` | RX AES-CBC decrypt + Huffman decode | Active |
| `uart_dmem_loader` | Runtime FPGA input loader into DMEM | Active in FPGA demo top |

## 4. Control Plane

```mermaid
flowchart LR
  C["RV32I program"] -->|"lw/sw MMIO"| D["address decode in rv32_soc_top"]
  D --> B["cpu_mmio_to_apb_bridge"]
  B --> R["dma_regfile"]
  R -->|"snapshot config"| TX["dma_tx_engine"]
  R -->|"snapshot config"| RX["dma_rx_engine"]
```

CPU-visible flow:

1. CPU reads input length from `DMEM[0x00000040]`.
2. CPU writes `SRC_ADDR`, `DST_ADDR`, `LEN_BYTES`, `MODE`, `BLOCK_CFG`.
3. CPU writes `IV0..IV3` before AES-CBC transfers.
4. CPU writes `CONTROL.start = 1`.
5. CPU polls `STATUS.done_sticky` or `STATUS.error_sticky`.
6. CPU reads `BYTES_DONE` and `CIPHERTEXT_BYTES_PRODUCED`.

DMA busy does not globally stall the CPU. CPU stalls only for normal memory
pipeline holds or when an MMIO APB access is in progress.

## 5. Data Memory Layout

Global memory map:

| Region | Address range | Meaning |
|---|---:|---|
| `DMEM` | `0x0000_0000..0x0000_7FFF` | 32 KiB data memory |
| `DMA MMIO` | `0x4000_0000..0x4000_00FF` | CPU-visible `dma_regfile` |

Current software/testbench regions:

| Address | Name | Meaning |
|---:|---|---|
| `0x0000_0040` | `INPUT_LEN_ADDR` | Input byte count written by testbench or UART loader |
| `0x0000_0400` | `SRC_BASE_ADDR` | Source plaintext/input region |
| `0x0000_2000` | `TX_DST_BASE_ADDR` | TX output ciphertext/transport region |
| `0x0000_4000` | `RX_DST_BASE_ADDR` | RX output plaintext region |

## 6. DMA Register Map

Base address:

```text
DMA_BASE = 0x4000_0000
```

| Offset | Name | Access | Meaning |
|---:|---|---|---|
| `0x00` | `CONTROL` | W | start, soft reset, clear sticky flags |
| `0x04` | `STATUS` | R | busy, done, error, cfg valid, mode mirrors |
| `0x08` | `SRC_ADDR` | R/W | DMEM source byte address |
| `0x0C` | `DST_ADDR` | R/W | DMEM destination byte address |
| `0x10` | `LEN_BYTES` | R/W | TX input bytes or RX ciphertext bytes |
| `0x14` | `MODE` | R/W | direction and TX policy |
| `0x18` | `BLOCK_CFG` | R/W | TX block size, current main value `32` |
| `0x1C` | `BYTES_DONE` | R | output bytes produced by active DMA |
| `0x20` | `DEBUG` | R | selected engine state and last error |
| `0x24` | `CIPHERTEXT_BYTES_PRODUCED` | R | TX output byte count for RX LEN_BYTES |
| `0x28` | `IV0` | R/W | CBC IV bits `[31:0]` |
| `0x2C` | `IV1` | R/W | CBC IV bits `[63:32]` |
| `0x30` | `IV2` | R/W | CBC IV bits `[95:64]` |
| `0x34` | `IV3` | R/W | CBC IV bits `[127:96]` |

### 6.1 DMA Register Function Summary

| Register | Main function | Who writes | Who reads | Side effect / software note |
|---|---|---|---|---|
| `CONTROL` | Start/reset/clear DMA transfer | CPU | none | `start`, `soft_reset`, `clear_done`, `clear_error` are write-one-pulse controls |
| `STATUS` | Poll DMA progress and sticky result | none | CPU | Software waits on `done_sticky` or `error_sticky`; `busy=1` means do not rewrite config/IV |
| `SRC_ADDR` | Source DMEM byte address | CPU | DMA engines | Must point to input plaintext for TX or ciphertext for RX |
| `DST_ADDR` | Destination DMEM byte address | CPU | DMA engines | Must point to TX output buffer or RX plaintext output buffer |
| `LEN_BYTES` | Transfer length | CPU | DMA engines | TX length is plaintext bytes; RX length is ciphertext/transport bytes |
| `MODE` | Select TX/RX and TX policy | CPU | DMA regfile/engines | Current main values: `0x9` TX whole-file AES, `0xD` TX whole-file compress-only, `0x2` RX |
| `BLOCK_CFG` | TX block byte size | CPU | `dma_tx_engine` | Main regression uses `32`; RX ignores this field |
| `BYTES_DONE` | Output byte count from active DMA | none | CPU/testbench | TX reports transport bytes written; RX reports plaintext bytes recovered |
| `DEBUG` | Engine state and last error | none | CPU/testbench | Debug only; not required for normal software flow |
| `CIPHERTEXT_BYTES_PRODUCED` | TX output length for following RX run | none | CPU | Software copies this value into RX `LEN_BYTES` |
| `IV0..IV3` | AES-CBC IV words | CPU | TX/RX CBC path | Must be written before `CONTROL.start` in AES modes and reused by RX |

`dma_regfile.iv_o = {IV3, IV2, IV1, IV0}`.

## 7. DMA Modes

`MODE` layout:

| Bits | Name | Meaning |
|---:|---|---|
| `[1:0]` | `direction` | `01 = TX`, `10 = RX` |
| `[2]` | `compress_only` | TX only: bypass AES |
| `[3]` | `whole_file` | TX only: whole-file dynamic Huffman |
| `[31:4]` | reserved | must be zero |

Common values:

| Value | Meaning | Current use |
|---:|---|---|
| `0x1` | TX `COMPRESS_AES` per-block | Supported |
| `0xD` | TX `COMPRESS_ONLY + whole_file` | TX-only saving benchmark |
| `0x9` | TX `COMPRESS_AES + whole_file` | Main TX/RX loopback |
| `0x2` | RX | Main TX/RX loopback |

## 8. TX Flow

```mermaid
flowchart LR
  SRC["DMEM plaintext\nSRC_ADDR"] --> TXDMA["dma_tx_engine"]
  TXDMA -->|"APB WORD_IN/BLOCK_SIZE/START"| TXIF["apb_huffman_tx_if"]
  TXIF --> ADP["word32 to byte adapter"]
  ADP --> HUF["dynamic_huffman_encoder"]
  HUF --> PACK["bit_packer_128"]
  PACK --> POLICY["TX policy"]
  POLICY -->|"COMPRESS_AES"| CBC["CBC XOR chain"]
  CBC --> AES["aes128_cipher_top"]
  POLICY -->|"COMPRESS_ONLY"| BYP["AES bypass"]
  AES --> FIFO["TX output FIFO"]
  BYP --> FIFO
  FIFO -->|"APB readback"| TXDMA
  TXDMA --> DST["DMEM output\nDST_ADDR"]
```

TX responsibilities:

- read plaintext from `DMEM`
- feed blocks to `apb_huffman_aes_tx_top`
- use dynamic Huffman compression
- pack bitstream into 128-bit transport words
- encrypt with AES-128 CBC for `COMPRESS_AES`
- bypass AES for `COMPRESS_ONLY`
- drain output FIFO and write result back to `DMEM`

Current main regression uses:

```text
MODE      = 0x9
BLOCK_CFG = 32
```

## 9. RX Flow

```mermaid
flowchart LR
  SRC["DMEM ciphertext\nSRC_ADDR"] --> RXDMA["dma_rx_engine"]
  RXDMA -->|"128-bit stream"| RXTOP["apb_huffman_aes_rx_top"]
  RXTOP --> AESD["aes128_cipher_inv_top"]
  AESD --> CBC["CBC XOR chain"]
  CBC --> DEP["bit_depacker_128"]
  DEP --> PAR["huffman_block_parser"]
  PAR --> DEC["huffman_block_decoder"]
  DEC --> PK["rx_byte_packer_32"]
  PK --> APB["apb_huffman_rx_if\nRX_DATA/RX_META/RX_STATUS"]
  APB -->|"APB readback"| RXDMA
  RXDMA --> DST["DMEM plaintext\nDST_ADDR"]
```

RX responsibilities:

- read ciphertext from `DMEM`
- feed 128-bit ciphertext words into RX top
- decrypt AES-128 CBC using the same IV as TX
- depack transport words into bit chunks
- parse Huffman block metadata/table/payload
- decode canonical Huffman stream
- pack plaintext bytes into 32-bit words
- write plaintext back to `DMEM`

RX requires:

```text
LEN_BYTES = CIPHERTEXT_BYTES_PRODUCED from TX
LEN_BYTES must be multiple of 16
IV0..IV3 must match the TX IV
```

## 10. Main Loopback Flow

```mermaid
sequenceDiagram
  participant CPU as RV32I CPU
  participant REG as dma_regfile
  participant TX as dma_tx_engine + TX top
  participant MEM as DMEM
  participant RX as dma_rx_engine + RX top

  CPU->>MEM: read INPUT_LEN_ADDR
  CPU->>REG: write TX SRC/DST/LEN/MODE=0x9/BLOCK=32/IV
  CPU->>REG: CONTROL.start
  TX->>MEM: read plaintext
  TX->>TX: dynamic Huffman + AES-CBC
  TX->>MEM: write ciphertext
  CPU->>REG: poll STATUS.done
  CPU->>REG: read CIPHERTEXT_BYTES_PRODUCED
  CPU->>REG: write RX SRC/DST/LEN=tx_cipher_len/MODE=0x2
  CPU->>REG: CONTROL.start
  RX->>MEM: read ciphertext
  RX->>RX: AES-CBC decrypt + Huffman decode
  RX->>MEM: write plaintext
  CPU->>REG: poll STATUS.done
```

## 11. Software Flow Chart

```mermaid
flowchart TD
  A["Start RV32I program"] --> B["Read INPUT_LEN_ADDR from DMEM"]
  B --> C["Generate demo IV in software"]
  C --> D["Write TX config\nSRC=0x400, DST=0x2000, LEN=input_len"]
  D --> E["Write MODE=0x9, BLOCK_CFG=32, IV0..IV3"]
  E --> F["Write CONTROL.start"]
  F --> G{"Poll STATUS"}
  G -->|"busy"| G
  G -->|"error_sticky"| H["Record error result"]
  G -->|"done_sticky"| I["Read CIPHERTEXT_BYTES_PRODUCED"]
  I --> J["Write RX config\nSRC=0x2000, DST=0x4000, LEN=tx_cipher_len"]
  J --> K["Keep same IV0..IV3\nWrite MODE=0x2"]
  K --> L["Write CONTROL.start"]
  L --> M{"Poll STATUS"}
  M -->|"busy"| M
  M -->|"error_sticky"| H
  M -->|"done_sticky"| N["Read BYTES_DONE"]
  N --> O["Testbench compares source and RX output"]
  H --> P["Publish fail signature"]
  O --> Q["Publish pass/fail signature"]
```

## 12. TX DMA Flow Chart

```mermaid
flowchart TD
  A["start_i from dma_regfile"] --> B{"Valid TX config?"}
  B -->|"no"| ERR["Set dma_error_o"]
  B -->|"yes"| C["Snapshot SRC/DST/LEN/MODE/BLOCK"]
  C --> D["Soft reset TX wrapper"]
  D --> E["Program TX_POLICY"]
  E --> F{"whole_file mode?"}
  F -->|"yes"| G["Pass 1: count whole-file frequency"]
  G --> H["Build global Huffman table"]
  F -->|"no"| I["Prepare next block"]
  H --> I
  I --> J["Read plaintext words from DMEM Port B"]
  J --> K["Write BLOCK_SIZE and WORD_IN over TX APB"]
  K --> L["Poll TX can_start"]
  L --> M["Write START_BLOCK"]
  M --> N["Wait TX done_sticky"]
  N --> O["Drain TX output FIFO\nAES_OUT_META/AES_OUT_DATA"]
  O --> P["Write output words to DMEM"]
  P --> Q{"More input blocks?"}
  Q -->|"yes"| I
  Q -->|"no"| R["Wait TX idle and FIFO empty"]
  R --> S["Pulse dma_done_o\nUpdate CIPHERTEXT_BYTES_PRODUCED"]
```

## 13. RX DMA Flow Chart

```mermaid
flowchart TD
  A["start_i from dma_regfile"] --> B{"Valid RX config?"}
  B -->|"no"| ERR["Set dma_error_o"]
  B -->|"yes"| C["Snapshot SRC/DST/LEN"]
  C --> D["Soft reset RX wrapper"]
  D --> E["Read W0..W3 from DMEM"]
  E --> F["Pack {W3,W2,W1,W0} into 128-bit ciphertext word"]
  F --> G{"RX stream ready?"}
  G -->|"no"| G
  G -->|"yes"| H["Send ciphertext_word_valid"]
  H --> I["Poll RX_STATUS"]
  I --> J{"RX output FIFO nonempty?"}
  J -->|"yes"| K["Read RX_META"]
  K --> L["Read RX_DATA"]
  L --> M["Write plaintext word to DMEM"]
  M --> I
  J -->|"no"| N{"More ciphertext bytes?"}
  N -->|"yes"| E
  N -->|"no"| O{"frame_done_sticky?"}
  O -->|"no"| I
  O -->|"yes"| P["Pulse dma_done_o\nBYTES_DONE = plaintext bytes"]
```

## 14. Simulation And FPGA Flow Chart

```mermaid
flowchart TD
  A["Choose C program"] --> B["make compile C_SRC=..."]
  B --> C["instruction.mem generated"]
  C --> D{"Target?"}
  D -->|"simulation"| E["Testbench loads input*.txt into DMEM"]
  E --> F["make drc"]
  F --> G["make all RUN_ARGS=+INPUT_FILE=..."]
  G --> H["Check sim.log and loopback/dmem_dump outputs"]
  D -->|"FPGA"| I["make clean"]
  I --> J["make vivado_flow_tx or make vivado_flow_rx"]
  J --> K["Program bitstream to board"]
  K --> L["make uart_load UART_PORT=... UART_INPUT=..."]
  L --> M["UART loader writes DMEM and releases CPU reset"]
```

## 15. AES-CBC And IV Contract

TX:

```text
C0 = AES_encrypt(P0 XOR IV)
Cn = AES_encrypt(Pn XOR Cn-1)
```

RX:

```text
P0 = AES_decrypt(C0) XOR IV
Pn = AES_decrypt(Cn) XOR Cn-1
```

Current policy:

- IV is written by RV32I software to `IV0..IV3`.
- `test_mmio_dma.c` creates a deterministic demo IV using RV32I-friendly
  arithmetic, shift, rotate and XOR operations.
- The AES key is fixed in RTL for the current prototype.
- `AES_top.v` generic mode logic is not the active TX/RX datapath.

For a real secure board demo, IV must be unique per encrypted message and must
be stored or transmitted with the ciphertext so RX can reuse the same IV.

## 16. Simulation Input Loading

In simulation, `DMEM` is not initialized from `input.txt` by the BRAM IP itself.
The testbench does it:

```mermaid
flowchart LR
  TXT["input*.txt"] --> TB["testbench file loader"]
  TB -->|"pack bytes into 32-bit words"| AUX["aux DMEM Port B"]
  AUX --> SRC["DMEM @ 0x00000400"]
  TB --> LEN["DMEM INPUT_LEN_ADDR @ 0x00000040"]
  CPU["RV32I program"] -->|"read input length"| LEN
```

Implication:

- changing `input.txt` does not require editing input length manually
- testbench recomputes `input_len_bytes`
- `make compile` is only needed when the C program changes

## 17. FPGA Demo Loading

On FPGA, there is no testbench. Runtime input loading is handled by
`uart_dmem_loader` in `rv32_soc_fpga_demo_top`.

```mermaid
flowchart LR
  PC["Host PC"] -->|"LOAD + len_le32 + payload"| UART["UART pins"]
  UART --> LDR["uart_dmem_loader"]
  LDR -->|"write payload"| SRC["DMEM @ 0x00000400"]
  LDR -->|"write payload length"| LEN["DMEM @ 0x00000040"]
  LDR -->|"loader_done"| RST["release SoC reset"]
  RST --> CPU["RV32I starts program"]
```

Current UART loader:

- protocol: `"LOAD" + payload_len_le32 + payload`
- baud: `115200`
- max payload follows the current source buffer limit
- LED status is exported by `rv32_soc_fpga_demo_top`

`make uart_load` is a host-side command used after programming the bitstream.
It is not a simulation command.

## 18. FPGA Build Status

Current practical FPGA direction is split bitstreams:

| Build | Purpose | Status |
|---|---|---|
| TX-only | compression/encryption demo | Practical FPGA demo path |
| RX-only | decryption/decompression demo | Practical FPGA demo path |
| Full TX+RX | integration reference | Too large/risky for current target |

Generated bitstreams are placed under:

```text
sim/vivado_bitstreams/rv32_soc_synth_tx.bit
sim/vivado_bitstreams/rv32_soc_synth_rx.bit
```

Use `make vivado_report VIVADO_PROJECT=...` to open the current report folder.

## 19. Main Commands

Simulation:

```bash
cd sim
make compile C_SRC=test_mmio_dma.c
make drc
make all RUN_ARGS="+INPUT_FILE=input1.txt"
```

TX-only simulation:

```bash
cd sim
make compile C_SRC=test_mmio_tx_only.c
make drc
make all TB_NAME=tb_rv32_soc_tx_only RUN_ARGS="+INPUT_FILE=input4.txt"
```

FPGA TX build and runtime load:

```bash
cd sim
make compile C_SRC=test_mmio_tx_only.c
make clean
make vivado_flow_tx
make uart_load UART_PORT=/dev/ttyUSB0 UART_INPUT=input1.txt
```

## 20. Current Limits

| Item | Current limit/status |
|---|---|
| DMEM size | 32 KiB |
| Main source buffer | `0x00000400..0x00001FFF`, 7168 bytes practical limit |
| TX output buffer | starts at `0x00002000` |
| RX output buffer | starts at `0x00004000` |
| TX block size | current main software uses `32` |
| RX input length | must be ciphertext length and 16-byte aligned |
| Huffman alphabet | newline + printable ASCII |
| AES key | fixed RTL key in prototype |
| IV source | RV32I software demo IV |
| FPGA runtime output readback | not complete yet |

## 21. Detailed Specs

Use this file as the summary. For module-level details, read:

| Area | Spec |
|---|---|
| Memory map/software contract | [memory_map_dma_software_contract.md](./memory_map_dma_software_contract.md) |
| BRAM/port ownership | [bram_port_usage_spec.md](./bram_port_usage_spec.md) |
| CPU stall policy | [cpu_dma_stall_policy_spec.md](./cpu_dma_stall_policy_spec.md) |
| MMIO bridge | [cpu_mmio_to_apb_bridge_spec.md](./cpu_mmio_to_apb_bridge_spec.md) |
| DMA register file | [dma_regfile_spec.md](./dma_regfile_spec.md) |
| IV/CBC | [iv_generation_and_cbc_contract_spec.md](./iv_generation_and_cbc_contract_spec.md) |
| TX end-to-end | [tx_path_end_to_end_spec.md](./tx_path_end_to_end_spec.md) |
| RX end-to-end | [rx_path_end_to_end_spec.md](./rx_path_end_to_end_spec.md) |
| FPGA usage | [soc_usage_and_fpga_guide.md](./soc_usage_and_fpga_guide.md) |
| UART loader | [fpga_uart_dmem_loader_spec.md](./fpga_uart_dmem_loader_spec.md) |
