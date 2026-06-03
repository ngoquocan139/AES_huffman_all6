# Paper Comparison: ECG Huffman + CBC-AES, Reframed By Component

## 1. Reference Paper

Referenced paper:

```text
A lossless compression and encryption mechanism for remote monitoring of ECG
data using Huffman coding and CBC-AES
```

Local PDF:

```text
H:\Academic\senior_project\DATN\refs\nén_aes\huffman_AES_CBC (1).pdf
```

Reported paper result:

| Item | Paper value |
|---|---:|
| Dataset | MIT-BIH ECG, five records |
| Records used | `100`, `106`, `112`, `117`, `213` |
| Processing | ECG preprocessing + Huffman compression + CBC-AES |
| AES key size | 256-bit key |
| Compression ratio | `35.015%` |
| Space saving | `64.985%` |
| PRD | `0.411` |

Note: one table in the PDF lists record `123`, but the experiment text and
result tables list `213`. The comparison here uses `100/106/112/117/213`.

**Conclusion.** This paper is useful for two separate comparisons: ECG final
storage ratio and Huffman/CBC-AES system motivation. It should not be presented
as having the same SoC architecture as this project.

## 2. Current SoC Comparison Condition

The SoC does not implement ECG signal preprocessing in RTL. For paper
comparison, the input to the SoC is an already-preprocessed byte stream:

```text
MIT-BIH ECG record
-> external preprocessing outside the SoC
-> delta2 + ZigZag + variable-length byte stream
-> RV32I SoC dynamic Huffman + AES-128-CBC secure storage
-> RX loopback restores the processed byte stream
```

Scope:

| Item | Meaning |
|---|---|
| What is measured | SoC storage ratio after external ECG-oriented preprocessing |
| What RTL implements | RV32I control, MMIO/APB, DMA, dynamic Huffman, AES-128-CBC TX/RX |
| What RTL does not implement | ECG preprocessing / inverse ECG reconstruction |
| RX correctness | RX output byte stream equals SoC input byte stream |

**Conclusion.** The fair statement is: the SoC performs secure storage on an
already-preprocessed ECG byte stream. It does not claim to reproduce the
paper's full ECG signal-processing chain inside RTL.

## 3. Input Files And Commands

The active input files are binary streams in `sim/`:

| MIT-BIH record | SoC input file | SoC input bytes |
|---:|---|---:|
| 100 | `mitdb_100_mlii_10s_delta2_var.bin` | 3601 |
| 106 | `mitdb_106_mlii_10s_delta2_var.bin` | 3614 |
| 112 | `mitdb_112_mlii_10s_delta2_var.bin` | 3601 |
| 117 | `mitdb_117_mlii_10s_delta2_var.bin` | 3602 |
| 213 | `mitdb_213_mlii_10s_delta2_var.bin` | 3601 |

Raw reference length:

```text
3600 samples * 2 bytes/sample = 7200 bytes
```

Example command for record `100`:

```bash
cd sim
make compile C_SRC=test_mmio_dma.c
make all TESTNAME=dma_mitdb_100_delta2_var_e2e \
  RUN_ARGS="+CASE_NAME=dma_mitdb_100_delta2_var_e2e +INPUT_FILE=mitdb_100_mlii_10s_delta2_var.bin +INPUT_BINARY"
```

**Conclusion.** The comparison input set is explicit and repeatable: five
MIT-BIH records, fixed raw byte reference, and one `make all` command pattern.

## 4. Huffman-Only Compression Comparison

This comparison ignores AES-CBC and only compares compressed payload size.
For the SoC, the relevant field is `PAYLOAD compressed_bytes_ceil`, not final
AES-aligned `tx_cipher_bytes`.

| Record | SoC input bytes | SoC Huffman payload bytes | SoC Huffman ratio | C Huffman bytes | C Huffman ratio |
|---:|---:|---:|---:|---:|---:|
| 100 | 3601 | 1961 | 54.44% | 2080 | 57.76% |
| 106 | 3614 | 2237 | 61.88% | 2403 | 66.49% |
| 112 | 3601 | 1780 | 49.42% | 1821 | 50.57% |
| 117 | 3602 | 1943 | 53.94% | 2007 | 55.72% |
| 213 | 3601 | 2119 | 58.84% | 2236 | 62.09% |
| Average | 18019 total | 10040 total | 55.72% | 10547 total | 58.53% |

The C Huffman baseline is `drichardson/huffman`, built and checked locally.

**Conclusion.** On Huffman-only payload size, the current compact-reuse SoC
format is smaller than the `drichardson/huffman` C baseline by `507` bytes, or
about `2.81` percentage points, across the five ECG streams. The result remains
hardware-decodable by the RX path.

## 5. Final Secure-Storage Ratio Comparison

This comparison includes final stored TX bytes after transport and AES-CBC
alignment.

| Record | Raw bytes reference | SoC input bytes | SoC final TX bytes | Final ratio vs raw | Final saving vs raw | Loopback |
|---:|---:|---:|---:|---:|---:|---|
| 100 | 7200 | 3601 | 2096 | 29.11% | 70.89% | PASS |
| 106 | 7200 | 3614 | 2400 | 33.33% | 66.67% | PASS |
| 112 | 7200 | 3601 | 1904 | 26.44% | 73.56% | PASS |
| 117 | 7200 | 3602 | 2080 | 28.89% | 71.11% | PASS |
| 213 | 7200 | 3601 | 2272 | 31.56% | 68.44% | PASS |
| Average | 7200 | 3603.8 | 2150.4 | 29.87% | 70.13% | PASS |

| Design | Condition | Final storage ratio | Space saving |
|---|---|---:|---:|
| Referenced paper | MIT-BIH ECG, paper processing chain | 35.015% | 64.985% |
| This SoC | Same records, external preprocessing, SoC Huffman + AES-128-CBC | 29.87% | 70.13% |
| Difference | Lower ratio is better | -5.15 percentage points | +5.15 percentage points |

**Conclusion.** On the final stored-size view, the current flow is better than
the paper by `5.15` percentage points. This conclusion is valid only when the
external preprocessing condition is stated.

## 6. Three-Part Comparison Against GitHub And Official Baselines

This section is intentionally split into three parts. A software repository,
an AES-only RTL core, and this SoC do not optimize the same target. Therefore
the comparison must state the metric first, then the winner.

### 6.1 Part 1 - Compression Ratio And Final Storage

Reference sources:

| Source | What it is useful for | Link |
|---|---|---|
| ECG Huffman + CBC-AES paper | Final secure-storage ratio on MIT-BIH ECG | Local PDF `refs/nén_aes/huffman_AES_CBC (1).pdf` |
| `drichardson/huffman` | Same-family Huffman-only C baseline | <https://github.com/drichardson/huffman> |
| `facebook/zstd` | Mature general-purpose software compressor | <https://github.com/facebook/zstd> |
| `ebiggers/libdeflate` | Optimized DEFLATE/zlib/gzip software compressor | <https://github.com/ebiggers/libdeflate> |
| `inikep/lzbench` | In-memory benchmark harness for many compressors | <https://github.com/inikep/lzbench> |

Detailed metric comparison:

| Metric | This SoC | External baseline | Better result | Fair report statement |
|---|---:|---:|---|---|
| MIT-BIH final secure-storage ratio | `29.87%` average final TX bytes vs raw 7200-byte ECG reference | Paper reports `35.015%` final ratio | This SoC, by `5.15` percentage points | Valid only because ECG preprocessing is external before entering the SoC |
| MIT-BIH final secure-storage saving | `70.13%` | Paper reports `64.985%` | This SoC, by `5.15` percentage points | The SoC proves hardware secure storage on preprocessed ECG bytes |
| MIT-BIH Huffman-only payload ratio | `55.72%` average | `drichardson/huffman`: `58.53%` average | This SoC | Compact table-reuse headers make the hardware format smaller by `2.81` percentage points |
| `input1.txt` Huffman payload ratio | `32.11%`, payload bytes `819` | `drichardson/huffman`: `32.65%`, output `833` bytes | This SoC | This is a Huffman-only payload comparison; AES is excluded |
| `input1.txt` final storage ratio | `34.50%`, TX bytes `880` | Estimated C Huffman + AES-CBC padding: about `848` bytes, or about `864` bytes if an IV is stored separately | C Huffman + AES software | AES padding and 128-bit transport still affect final stored size |
| `input3.txt` Huffman payload ratio | `42.05%`, payload bytes `102` | `drichardson/huffman`: `42.56%`, output `103` bytes | This SoC by `1` byte | Small repeated input is one case where the SoC format is competitive |
| General software compressor speed | FPGA demo TX input throughput is about `3.786 MB/s` at 50 MHz for `input1.txt` after the Huffman build scan-limit optimization | `zstd` README reports desktop compression examples in hundreds of MB/s on a Core i7-class CPU | Software PC | Not a fair embedded comparison; PC compressors win raw throughput |
| General software compressor ratio | This SoC uses hardware-friendly dynamic Huffman only | `zstd`, `libdeflate`, `lzma`, `bz2` use stronger/general algorithms | Software PC | Do not claim best pure compression ratio against mature desktop compressors |

Interpretation:

- If the question is "which output file is smaller?", software compressors
  usually win.
- If the question is "which design is a verified RV32I-controlled FPGA
  secure-storage datapath?", the SoC wins because software repositories do not
  provide RV32I MMIO, DMA, AES-CBC TX, RX restore, metadata, and FPGA reports.
- AES does not compress data. It only pads to 16-byte blocks for CBC. Therefore
  compression ratio is decided mostly by Huffman/codebook/header/transport.

### 6.2 Part 2 - AES And Execution Speed

Reference sources:

| Source | What it is useful for | Link |
|---|---|---|
| `aadomn/aes` | AES software cycles/byte on RV32I E31 | <https://github.com/aadomn/aes> |
| OpenSSL `speed` documentation | Official PC crypto benchmark command | <https://docs.openssl.org/1.1.1/man1/speed/> |
| `secworks/aes` | Mature AES Verilog RTL baseline | <https://github.com/secworks/aes> |

Detailed metric comparison:

| Metric | This SoC | External baseline | Better result | Fair report statement |
|---|---:|---:|---|---|
| AES mode in current design | AES-128-CBC inside TX/RX path | Paper uses CBC-AES with 256-bit key | Paper has larger key size | Current security scope is AES-128-CBC, not AES-256-CBC |
| IV handling | RV32I firmware writes `IV0..IV3`; RX must reuse the same IV | Software libraries usually accept IV as function argument | Equivalent conceptually | Current IV entropy is a system-level/future-work topic |
| AES-only direct testcase | Encrypt `11 cycles/block`, decrypt `11 cycles/block`; `0.688 cycles/byte`; `145.455 MB/s` at 100 MHz or `72.727 MB/s` at 50 MHz | `secworks/aes`: `46 cycles/block`; `aadomn/aes`: AES-128 RV32I software `78.9 cycles/byte` | This SoC AES core for narrow cycle/byte | Measured by `make all TESTNAME=aes_core_benchmark` with FIPS-197 known-answer vector |
| `input1.txt` TX cycles/input byte | `13.21` cycles/byte for Huffman + AES-CBC + DMA after Huffman build optimization | `aadomn/aes`: fastest listed AES-128 RV32I E31 software is `78.9` cycles/byte for AES-only | This SoC in cycles/byte | Cross-scope comparison; our number includes more than AES, but is accelerator busy cycles, not retired CPU cycles |
| MIT-BIH average TX cycles/input byte | `23.29` cycles/byte for Huffman + AES-CBC + DMA | `aadomn/aes`: `78.9` cycles/byte AES-only RV32I software | This SoC in cycles/byte | Supports the architecture choice to offload data transform work from RV32I to RTL |
| OpenSSL AES PC throughput | Not measured in this repo | Official command: `openssl speed -elapsed -evp aes-128-cbc` | Usually PC/OpenSSL | Use OpenSSL only as a PC upper-bound baseline, not as an embedded FPGA SoC baseline |
| AES-only RTL cycles | Encrypt/decrypt direct testcase: `11 cycles/block` | `secworks/aes`: `46 cycles/block` on published FPGA examples | This SoC AES core for latency | Current core uses a wider round datapath; `secworks/aes` is more general and mature |
| AES-only RTL area | TX AES `1614` LUT, RX AES inverse `1667` LUT inside full SoC; both separate cores total `3281` LUT | `secworks/aes` master lists `3020` LUT, `2992` FF, `125 MHz`; FPGA examples list `46 cycles/block` | Mixed | TX-only or RX-only is smaller; TX+RX separate cores are slightly larger in LUT but much lower FF |
| Full TX speed on `input1.txt` | `32633` cycles, `0.653 ms` at 50 MHz | PC software likely faster in wall-clock on a modern desktop | PC software | The SoC result is valuable for deterministic embedded hardware, not for beating a desktop CPU |
| Full RX speed on `input1.txt` | `15137` cycles, `0.303 ms` at 50 MHz | PC software likely faster in wall-clock on a modern desktop | PC software | RX restore is still fast enough for FPGA secure-storage demo scale |

Interpretation:

- Against RV32I software AES, the RTL datapath is the better architectural
  choice.
- Against OpenSSL on a PC, the PC is normally faster because it uses a high
  frequency CPU and often hardware AES instructions.
- Against AES-only RTL, the current direct AES testcase is faster than the
  `secworks/aes` published `46 cycles/block` baseline, but the comparison is
  narrow. `secworks/aes` supports a reusable AES-128/256 core, while this SoC
  uses separate AES-128 encrypt/decrypt modules embedded in the storage path.

### 6.3 Part 3 - FPGA/SoC Area, Timing, And Integration

Reference sources:

| Source | What it is useful for | Link |
|---|---|---|
| Vivado reports in this repo | Actual implementation numbers for this SoC | `sim/vivado_reports/rv32_soc_synth_full_zcu102_autorun_ecg/` |
| `secworks/aes` | AES-only RTL area/timing baseline | <https://github.com/secworks/aes> |
| `lzbench`/`zstd`/`libdeflate` | Software throughput/ratio baselines, not FPGA area baselines | Links above |

Current implementation summary:

| Build / module | LUT | FF | BRAM36 | WNS / Fmax | Power | Meaning |
|---|---:|---:|---:|---:|---:|---|
| Full ZCU102 SoC | `36049` logic LUT, `37069` total LUT | `19794` | `11` | WNS `+7.871 ns` at 50 MHz generated SoC clock | `0.793 W` vectorless estimate | CPU + DMA + TX + RX + UART + memories |
| RV32I CPU only | `1787` | `648` | `0` | Included in full timing | Included in full power | Control plane |
| DMA regfile + bridge | `46` + `7` LUT | `239` + `103` | `0` | Included in full timing | Included in full power | MMIO/APB control |
| DMA TX/RX engines | TX `567`, RX `266` | TX `321`, RX `303` | `0` | Included in full timing | Included in full power | Data movers |
| TX top | `11201` | `2821` | `0` | Included in full timing | Included in full power | Huffman encode + AES-CBC/bypass |
| RX top | `21042` | `13110` | `1` | Included in full timing | Included in full power | AES-CBC decrypt + Huffman decode |
| RX Huffman decoder | `16805` | `11695` | `1` | Included in full timing | Included in full power | Largest area bottleneck |
| `secworks/aes` standalone AES | README lists `3020` LUT, `2992` FF, `125 MHz`; FPGA examples list `46 cycles/block` | `2992` | Device-dependent | `125 MHz` master summary | Not provided in same way | AES-only reusable core |

Detailed conclusion by comparison target:

| Target | Does it beat this SoC? | Why |
|---|---|---|
| PC software compressor + AES | Yes for raw speed and usually for compressed file size | It runs on a much faster CPU and can use stronger algorithms or AES acceleration |
| RV32I-only software AES/Huffman | Usually no for datapath cycles | The current RV32I is a control plane; RTL accelerators do byte transformation |
| AES-only RTL core | Depends on the metric | This SoC AES direct testcase is faster at `11 cycles/block`; mature standalone AES IP still wins reuse, configurability, and verification scope |
| Huffman-only software | Usually yes for pure Huffman output size | It can use a simpler file format and does not need hardware transport alignment |
| Current SoC | Wins system integration | It provides verified TX/RX loopback, DMA control, AES-CBC, metadata, FPGA bitstream path, timing closure, and DMEM dumps |

### 6.4 Focused AES/Huffman Metric Tables

The comparison style follows the local graduation-report style used in:

| Local reference | Useful reporting style |
|---|---|
| `refs/CAPSTONE_PROJECT_TRANQUOCTHIEN_NGUYENTUANKIET_FINAL.pdf` | Separate functional testcases, per-algorithm throughput table, related-work comparison table, and Vivado implementation table |
| `refs/Graduation_Thesis_Ngoc_Tu_Ton_Luc.pdf` | Separate memory map/software result, testcase result, and FPGA/RISC-V soft-core comparison table |

This section therefore separates:

- AES metrics: cycles/byte, cycles/block, Fmax, LUT/FF.
- Huffman metrics: throughput/data rate, Fmax, LUT/BRAM, and whether the design
  is pure Huffman or a full compression pipeline.
- SoC metrics: current design numbers from Questa and Vivado reports.

Additional source links used for the metric tables:

| Source | Link |
|---|---|
| AMD/Xilinx Vitis GZip Compression and Decompression results | <https://xilinx.github.io/Vitis_Libraries/data_compression/2022.1/source/L2/gzip.html> |
| Canonical Huffman FPGA paper | Local PDF `refs/nén_aes/1-s2.0-S2590123025011120-main.pdf` |
| ECG Huffman + CBC-AES paper | Local PDF `refs/nén_aes/huffman_AES_CBC (1).pdf` |

#### 6.4.1 AES-Focused Comparison

| Source | Scope | Speed / cycle metric | Fmax | LUT / FF / memory | What it means for this thesis |
|---|---|---:|---:|---:|---|
| This SoC, AES-only direct testcase | `aes128_cipher_top` encrypt and `aes128_cipher_inv_top` decrypt, no CPU/DMA/Huffman | Encrypt `11 cycles/block`, decrypt `11 cycles/block`; `0.688 cycles/byte`; `145.455 MB/s` at `100 MHz`, `72.727 MB/s` at `50 MHz` | Testbench clock `100 MHz`; FPGA demo SoC clock `50 MHz` | TX AES `1614` LUT/`261` FF; RX AES `1667` LUT/`261` FF | Clean AES-only number for defense and module comparison |
| This SoC, `input1.txt` TX | Dynamic Huffman + AES-128-CBC + DMA write | `32633` cycles total, `12.79` cycles/input byte | FPGA demo SoC clock `50 MHz`; log MB/s assumes `100 MHz` | TX AES submodule only: `1614` LUT, `261` FF; full TX top: `11201` LUT, `2821` FF | This is the end-to-end secure-storage TX datapath, not AES-only |
| This SoC, `input1.txt` RX | DMA read + AES-128-CBC decrypt + Huffman decode + DMA writeback | `15137` cycles total, `5.94` cycles/plain byte | FPGA demo SoC clock `50 MHz`; log MB/s assumes `100 MHz` | RX AES inverse submodule only: `1667` LUT, `261` FF; full RX top: `21042` LUT, `13110` FF | RX is faster in cycles/byte than TX, but larger in LUT due to Huffman decode |
| This SoC, MIT-BIH average | Same SoC TX/RX flow on 5 preprocessed ECG streams | TX `53233` cycles avg, `14.77` cycles/input byte; RX `24182.8` cycles avg, `6.71` cycles/plain byte | `50 MHz` FPGA demo clock | Full SoC: `36049` logic LUT, `19794` FF, `11` BRAM36 | Best system-level number for paper comparison |
| `aadomn/aes` GitHub | AES software on RISC-V E31 | AES-128 barrel-shiftrows: `78.9` cycles/byte on E31 | CPU/platform dependent | Software, no FPGA LUT | This supports the claim that RTL offload is much better than RV32I-only AES software |
| OpenSSL official `speed` command | PC AES software benchmark | Command reports bytes/s, not fixed cycles/byte | PC CPU dependent, often AES-NI accelerated | Software, no FPGA LUT | Use only as desktop upper-bound; OpenSSL on PC normally beats the FPGA demo in raw MB/s |
| `secworks/aes` GitHub | Standalone AES RTL core | README lists `46 cycles/block`; AES-only equivalent is `2.875` cycles/byte | README lists `125 MHz` master summary and FPGA examples around `96-106 MHz` | README master summary lists `3020` LUT, `2992` FF | Useful mature AES IP baseline; this SoC AES direct testcase has lower latency, while `secworks/aes` is more reusable/configurable |
| ECG Huffman + CBC-AES paper | MATLAB/software-style AES-256-CBC in ECG chain | Average encryption time `2.7106 s`; decryption time `3.0449 s` across reported tables | Not reported | LUT/FF not reported | Useful for timing motivation, not FPGA resource comparison |

AES comparison conclusion:

- Against RV32I-only software AES, the SoC datapath is clearly stronger.
- Against PC/OpenSSL, the PC normally wins raw AES throughput.
- Against standalone AES RTL, the current AES core has better narrow latency
  than the `secworks/aes` published `46 cycles/block` result, but
  `secworks/aes` remains a stronger reusable IP baseline because it supports
  AES-128/256 and has a mature standalone verification scope.

AES LUT comparison:

| AES design/module | Scope | LUT | FF | Cycles/block | Comment |
|---|---|---:|---:|---:|---|
| This SoC `u_AES_top_tx` | AES-128 encrypt only | `1614` | `261` | `11` | Integrated in TX path |
| This SoC `u_AES_top_rx` | AES-128 inverse/decrypt only | `1667` | `261` | `11` | Integrated in RX path |
| This SoC TX+RX AES modules | Separate encrypt and decrypt modules | `3281` | `522` | `11` each direction | Slightly larger LUT than one reusable AES core, but much lower FF |
| `secworks/aes` master | Reusable AES-128/256 encrypt/decrypt core | `3020` | `2992` | `46` | Published Xilinx Kintex-7/Vivado summary; not same device or interface |

#### 6.4.2 Huffman-Focused Comparison

| Source | Scope | Speed / throughput metric | Fmax | LUT / FF / memory | What it means for this thesis |
|---|---|---:|---:|---:|---|
| This SoC, `input1.txt` TX | Whole-file dynamic Huffman + AES-CBC + DMA | TX input throughput `7.817 MB/s` at `100 MHz` log assumption, about `3.909 MB/s` at `50 MHz`; `12.79` cycles/input byte | FPGA demo SoC clock `50 MHz` | TX top `11201` LUT; Huffman builder `3429` LUT; dynamic encoder `2615` LUT; bit packer `2361` LUT | End-to-end secure-storage TX; speed improved by scan limiting and size improved by compact table-reuse headers |
| This SoC, `input1.txt` RX | AES-CBC decrypt + Huffman parse/decode + DMA writeback | RX output throughput `16.853 MB/s` at `100 MHz` log assumption, about `8.426 MB/s` at `50 MHz`; `5.94` cycles/plain byte | FPGA demo SoC clock `50 MHz` | RX top `21042` LUT; Huffman decoder `16805` LUT; parser `1526` LUT; 1 BRAM for decode table | RX Huffman decoder is the largest module |
| This SoC, MIT-BIH average | Same SoC path on five preprocessed ECG streams | TX `1.065 ms`, RX `0.484 ms` at `50 MHz`; TX `14.77` cycles/input byte; RX `6.71` cycles/plain byte | `50 MHz` | Full SoC `36049` logic LUT, `19794` FF, `11` BRAM36 | Best hardware-system number for thesis comparison |
| `drichardson/huffman` GitHub | Huffman-only C software | Throughput/cycles not reported in README; local comparison used compressed byte count | CPU dependent | Software, no FPGA LUT | Good same-family ratio baseline; current SoC output is smaller on the tested report inputs |
| AMD/Xilinx Vitis Data Compression GZip demo | GZip compress/decompress kernels; hardware compression pipeline with Huffman inside GZip/Zlib flow | GZip compression `1.5 GB/s`, decompression `518 MB/s`; average compression ratio `2.67x` on Silesia benchmark | Final Fmax `300 MHz` | Compress `35.4K` LUT, `31.8K` REG, `73` BRAM, `32` URAM; DeCompress `6.7K` LUT, `5K` REG, `8` BRAM | Useful official hardware-compression reference; not directly comparable to this custom Huffman/AES SoC |
| Canonical Huffman FPGA paper, encoder | Pure canonical Huffman encoder on Virtex-5 | Text reports encoder throughput `144 GB/s`; 160-bit input to 90-bit output example | `244.457 MHz` | Table 9 encoder full module: `1529` slice registers, `1529` LUT, `1529` occupied slices | Standalone canonical Huffman wins raw Huffman throughput; it does not include AES-CBC, DMA, RV32I, or file metadata |
| Canonical Huffman FPGA paper, decoder | Pure canonical Huffman decoder on Virtex-5 | Text/table reports decoder data rate up to `991 GB/s` | Not cleanly reported for full decoder in OCR; same paper context uses Virtex-5 | Table 10 full decoder OCR: `290` slice registers, `490` LUT, `200` occupied slices; Table 11 area utilization `490` | Very high raw decoder throughput; not directly comparable to general 256-symbol RX parser/fallback architecture |
| ECG Huffman + CBC-AES paper | ECG preprocessing + Huffman + AES-256-CBC software chain | Average compression time `3.8641 s`; decompression time `0.5818 s`; compression+encryption `6.5747 s` | Not reported | LUT/FF not reported | The SoC is much faster for datapath time, but ECG preprocessing is external to current RTL |

Huffman comparison conclusion:

- Software Huffman is usually better for pure output size because it has less
  hardware transport/header overhead.
- Standalone FPGA Huffman/GZip references are far faster in raw throughput, but
  they are specialized compression engines and often much larger.
- The current SoC's contribution is the integrated secure-storage chain:
  RV32I control, DMA, dynamic Huffman, AES-CBC, RX restore, metadata, waveform,
  logs, and Vivado implementation.

#### 6.4.3 Compact Slide Table

Use this shorter table in presentation slides:

| Metric group | Best external number | This SoC number | Winner by metric | Thesis-safe interpretation |
|---|---:|---:|---|---|
| AES software on RV32I | `aadomn/aes`: AES-128 `78.9` cycles/byte on E31 | AES-only RTL `0.688` cycles/byte; TX full path `13.21` cycles/input byte on `input1.txt` | This SoC for RV32I offload | RTL accelerator is justified |
| AES-only RTL | `secworks/aes`: `46` cycles/block, `3020` LUT, `125 MHz` | AES-only direct testcase `11` cycles/block; TX AES `1614` LUT, RX AES `1667` LUT | This SoC for latency; mixed for area/reuse | Our AES is fast but embedded and AES-128-specific |
| Huffman software ratio | `drichardson/huffman`: MIT-BIH avg `58.53%` payload ratio | SoC Huffman payload MIT-BIH avg `55.72%` | This SoC by ratio | Compact table-reuse headers make the SoC payload smaller on the report ECG set |
| Hardware GZip/Huffman throughput | Vitis GZip demo `1.5 GB/s` compression; canonical Huffman paper up to `144/991 GB/s` | `input1` TX about `3.786 MB/s`, RX output about `8.426 MB/s` at `50 MHz` | External specialized hardware | They are compression engines; this is a complete RV32I secure-storage SoC |
| FPGA integration | External repos are standalone AES/Huffman/compression | Full SoC passes implementation: `36049` logic LUT, `19794` FF, `11` BRAM36, WNS `+7.871 ns` | This SoC for integration | Complete verified system is the contribution |

Recommended wording for defense:

```text
Compared with GitHub software compressors and OpenSSL on a PC, the proposed
SoC is not the best pure compressor and is not the fastest desktop crypto
implementation. Compared with RV32I-only software, however, the RTL datapath
reduces byte-processing work dramatically. Compared with AES-only or
Huffman-only hardware, the proposed design is larger because it is a complete
secure-storage SoC: RV32I control, MMIO/APB, DMA, dynamic Huffman, AES-CBC,
RX restore, metadata handling, UART loader, simulation logs, and Vivado
implementation reports.
```

**Conclusion.** The clean claim is not "our design beats all GitHub software."
The clean claim is "our design is a complete FPGA SoC secure-storage datapath;
software baselines win pure ratio/raw PC speed, while this design wins
embedded hardware integration and RV32I offload."

## 7. Software Versus Hardware Design Responsibility

| Layer | Software responsibility | Hardware responsibility | Proof |
|---|---|---|---|
| File selection | Choose `file_id`, locate metadata record | Hardware does not know file names or file IDs | `dma_storage_table_input1_then_input3` |
| IV management | Generate/store/write `IV0..IV3` | TX/RX consume `cbc_iv_i` for CBC chain | `dma_compress_aes_input1` |
| TX start | Program `SRC/DST/LEN/MODE`, assert start | DMA TX reads DMEM, runs Huffman/AES, writes TX buffer | `dma_compress_aes_input1`, `tx_compress_only_input1` |
| RX start | Use `CIPHERTEXT_BYTES_PRODUCED` as RX length | DMA RX feeds AES decrypt/Huffman decode and writes plaintext | `dma_compress_aes_input1` |
| Error handling | Poll status and read error/debug registers | DMA/RX reject bad alignment and internal errors | `mmio_rx_bad_length` |

**Conclusion.** The software is not just a driver. It is the secure-storage
policy layer. The hardware is the deterministic acceleration layer.

## 8. Suggested Thesis Wording

Use this wording:

```text
The referenced ECG paper reports a 35.015% final compression ratio using
Huffman coding and CBC-AES. My comparison separates the result into two
levels. At the Huffman-only level, the SoC payload ratio on the same five
preprocessed ECG byte streams is 55.72%, while a C Huffman reference reaches
58.53%. At the secure-storage level, after external ECG preprocessing and SoC
Huffman + AES-128-CBC storage, the final average ratio is 29.87% versus the
paper's 35.015%. Therefore, the SoC demonstrates a verified hardware
secure-storage datapath with a compact hardware-decodable Huffman format, while
ECG-specific preprocessing remains outside the current RTL scope.
```

If asked whether this is fair:

```text
It is fair as a scoped comparison, not as a claim of identical architecture.
The paper is used for ECG final-ratio comparison; C Huffman is used for
Huffman-only comparison; AES software/RTL references are used for AES cost and
offload motivation.
```

**Conclusion.** The report should explicitly say "component-level comparison."
That wording avoids overclaiming while still showing the project result clearly.

## 9. Future Work

If the project needs to own the complete ECG compression chain, add one of:

| Improvement | Effect | Cost |
|---|---|---|
| RTL delta/predictor stage | Makes preprocessing part of SoC | Adds TX predictor and RX inverse predictor |
| RV32I preprocessing software | Keeps hardware smaller | Slower, CPU does more data work |
| Beat/template ECG coding | Better ECG-specific compression | More algorithm and metadata complexity |
| DWT/quantization | Can approach ECG paper methods | May become lossy and arithmetic-heavy |

**Conclusion.** The most realistic next step is RV32I-side or lightweight RTL
preprocessing. That would make the ECG comparison more direct without changing
the verified Huffman/AES storage core.
