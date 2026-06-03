# Architecture, Component, And Software Comparison Report

Date: 2026-06-03

This note is the comparison section for the current RV32I secure-storage SoC.
The comparison is intentionally component-level. A reference does not need to
match the full architecture to be useful: Huffman compression ratio can be
compared with Huffman-only software, AES cost can be compared with AES-only
software/RTL, and firmware can be compared with the active hardware contract.

Local thesis style references checked:

- `/mnt/h/Academic/senior_project/DATN/refs/Graduation_Thesis_Ngoc_Tu_Ton_Luc.pdf`
- `/mnt/h/Academic/senior_project/DATN/refs/CAPSTONE_PROJECT_TRANQUOCTHIEN_NGUYENTUANKIET_FINAL.pdf`

Both reports separate background, design, simulation/evaluation, performance
comparison, and final conclusion. Following that style, every comparison item
below ends with an explicit conclusion.

## 1. Measured Results In This Repo

All SoC numbers below are from current Questa logs in `sim/log`.

| Case | Input | Plain bytes | TX output bytes | TX cycles | RX cycles | TX cycles/byte | Total cycles/byte | Storage ratio | Result |
|---|---|---:|---:|---:|---:|---:|---:|---:|---|
| Main TX/RX secure storage | `input1.txt` | 2551 | 880 | 32633 | 15132 | 12.79 | 18.72 | 34.50% | PASS=18 FAIL=0 |
| Sensor-log TX/RX secure storage | `input2.txt` | 2839 | 1856 | 43033 | 19636 | 15.16 | 22.78 | 65.38% | PASS=18 FAIL=0 |
| Small TX/RX secure storage | `input3.txt` | 242 | 112 | 10817 | 5226 | 44.70 | 66.29 | 46.28% | PASS=18 FAIL=0 |
| TX-only Huffman benchmark | `input1.txt` | 2551 | 880 expected by same compact header format | not rerun in latest pass | 0 | n/a | n/a | 34.50% expected | Previous PASS=15 baseline; direct TX/RX is the current measured proof |
| TX-only log-like benchmark | `input4_cov.txt` | 6000 | 4064 | 109037 | 0 | 18.17 | 18.17 | 67.73% | PASS=15 FAIL=0 |
| Secure storage API bundle | `input1.txt` + `input2.txt` + ECG 112 | 9088 staged | TX1 880 | 122227 aggregate TX | 15132 selected RX | 13.45 aggregate | selected file_id=1 | 34.50% for file_id=1 | PASS=22 FAIL=0 |
| MIT-BIH average | records 100/106/112/117/213 | 3603.8 avg | 2150.4 avg | 53233 avg | 24182.8 avg | 14.77 | 21.48 | 29.87% vs raw 7200-byte ECG reference | PASS=18 FAIL=0 each |

Interpretation:

- `tx_cycles` and `rx_cycles` are accelerator/DMA busy cycles observed by the
  testbench. They are not retired RV32I instruction counts.
- The reported MB/s in testcase logs assumes 100 MHz simulation timing. The
  ZCU102 demo clock currently runs the SoC at 50 MHz, so FPGA wall-clock
  throughput is approximately half of the 100 MHz log throughput.
- `PAYLOAD ratio` means Huffman payload before 128-bit transport/AES alignment.
  `STORAGE ratio` means final stored TX bytes after transport/AES alignment.

**Conclusion.** The measured system already supports three report views:
Huffman compression quality, secure-storage final size, and TX/RX cycle cost.
Those should be compared separately instead of forcing every reference to
match the whole RV32I + DMA + Huffman + AES-CBC architecture.

## 2. Component-Level Comparison Map

| Design component | Best comparison target | Metric to compare | Current design result | Safe claim |
|---|---|---|---|---|
| Huffman compressor | Huffman-only C implementation and compression papers | Payload/storage ratio | `input1.txt` Huffman payload `32.11%`; MIT-BIH payload avg `55.72%` | Comparable as compression ratio, independent of AES-CBC |
| Secure-storage output | ECG Huffman + CBC-AES paper | Final stored bytes after encryption/alignment | MIT-BIH final ratio vs raw ECG `29.87%` avg | Comparable only if preprocessing condition is stated |
| AES datapath | AES-only software/RTL cores | Cycles/byte, cycles/block, LUT/FF | AES-only direct testcase `11` cycles/block and `0.688` cycles/byte; SoC TX `13.21` cycles/byte for Huffman+AES+DMA on `input1.txt` after Huffman build optimization | Shows offload benefit; AES is fast but embedded in a larger secure-storage SoC |
| RV32I firmware | Software-only control/data processing | Responsibility split and code size/function | Firmware controls metadata, IV, mode, DMA; RTL performs data transforms | CPU is a control plane, not a compression/encryption datapath |
| FPGA implementation | FPGA SoC/resource papers | LUT/FF/BRAM/timing/power | Full ZCU102 bitstream passes timing with WNS `+7.871 ns` in latest report set | Design is implementable as a complete FPGA SoC |

**Conclusion.** The strongest report structure is not "my architecture is the
same as the paper." It is "my design matches or is evaluated against each
relevant part: compression, encryption, firmware control, and FPGA
implementation."

## 3. Huffman Compression Ratio Comparison

This section intentionally ignores AES-CBC and compares the compression part.
For the SoC, the fair Huffman-only number is the `PAYLOAD compressed_bytes_ceil`
from logs, not the final AES-aligned `tx_cipher_bytes`.

Reference:

- GitHub: [drichardson/huffman](https://github.com/drichardson/huffman)

The reference C Huffman project was cloned, built with `make`, checked with
`make check`, and decompression was verified by `cmp`.

| Input | Original bytes | This SoC Huffman payload bytes | This SoC Huffman payload ratio | C Huffman output bytes | C Huffman ratio | Comment |
|---|---:|---:|---:|---:|---:|---|
| `input1.txt` | 2551 | 819 | 32.11% | 833 | 32.65% | SoC is smaller by 14 B / 0.54 points |
| `input3.txt` | 242 | 102 | 42.05% | 103 | 42.56% | Similar compression quality on small repeated input |
| MIT-BIH 100 | 3601 | 1961 | 54.44% | 2080 | 57.76% | SoC is smaller |
| MIT-BIH 106 | 3614 | 2237 | 61.88% | 2403 | 66.49% | SoC is smaller |
| MIT-BIH 112 | 3601 | 1780 | 49.42% | 1821 | 50.57% | SoC is smaller |
| MIT-BIH 117 | 3602 | 1943 | 53.94% | 2007 | 55.72% | SoC is smaller |
| MIT-BIH 213 | 3601 | 2119 | 58.84% | 2236 | 62.09% | SoC is smaller |
| MIT-BIH average | 18019 total | 10040 total | 55.72% | 10547 total | 58.53% | SoC is smaller by 507 B / 2.81 points |

Why the new SoC Huffman payload is now smaller than this C Huffman baseline:

- The first compressed block carries the dynamic Huffman table.
- Later blocks reuse the same table with a compact 3-bit or 9-bit reuse header
  instead of the older 17-bit repeated header.
- RX parser support was updated so the compact format still decodes in hardware.

Why the SoC result is still useful:

- The SoC does compression in RTL under RV32I control.
- The output format is directly decodable by the RX hardware.
- It is compatible with the secure-storage AES-CBC path and metadata API.

**Conclusion.** Against the same-family `drichardson/huffman` baseline, the
current SoC Huffman payload is now smaller on `input1.txt` and on all five
MIT-BIH preprocessed ECG streams tested here. This does not mean it beats
general-purpose compressors such as `zlib`, `bz2`, or `lzma`; it means the
hardware-friendly Huffman format is now competitive against a pure Huffman C
reference while preserving hardware RX decode.

## 4. Secure-Storage Final Ratio Comparison

This section includes the real stored TX output after 128-bit transport and
AES-CBC alignment.

Reference paper:

- Local PDF: `/mnt/h/Academic/senior_project/DATN/refs/nén_aes/huffman_AES_CBC (1).pdf`
- Online index: [ScienceDirect paper](https://www.sciencedirect.com/science/article/pii/S0167739X19313950)

The paper reports MIT-BIH ECG compression ratio `35.015%` and space saving
`64.985%` for an ECG preprocessing + Huffman + CBC-AES flow.

This SoC was tested on the same record IDs, but the ECG preprocessing is
external. The SoC input is already a delta2 + ZigZag + variable-byte stream.

| MIT-BIH record | Raw reference bytes | SoC input bytes | SoC final TX bytes | SoC final ratio vs raw | SoC final saving vs raw | Loopback |
|---:|---:|---:|---:|---:|---:|---|
| 100 | 7200 | 3601 | 2096 | 29.11% | 70.89% | PASS |
| 106 | 7200 | 3614 | 2400 | 33.33% | 66.67% | PASS |
| 112 | 7200 | 3601 | 1904 | 26.44% | 73.56% | PASS |
| 117 | 7200 | 3602 | 2080 | 28.89% | 71.11% | PASS |
| 213 | 7200 | 3601 | 2272 | 31.56% | 68.44% | PASS |
| Average | 7200 | 3603.8 | 2150.4 | 29.87% | 70.13% | PASS |

| Design | Comparison scope | Final ratio | Space saving | Limitation |
|---|---|---:|---:|---|
| ECG Huffman + CBC-AES paper | Full ECG processing chain reported by paper | 35.015% | 64.985% | Includes ECG preprocessing and AES-256-CBC |
| This SoC | External ECG preprocessing + SoC Huffman + AES-128-CBC | 29.87% | 70.13% | ECG preprocessing is outside RTL |
| Difference | Same record IDs, lower ratio is better | -5.15 points | +5.15 points | Not a claim that RTL implements ECG preprocessing |

**Conclusion.** For final secure-storage size on the same MIT-BIH record IDs,
the current flow reaches `29.87%` average ratio versus the paper's `35.015%`.
This is a valid result only with the stated condition that ECG preprocessing is
external to the SoC.

## 5. Software Baseline Versus Current Design

### 5.1 Pure software algorithms versus hardware datapath

This table compares only the compression part. It does not include encryption,
block padding, or secure-storage metadata. For this SoC, the number used is
`PAYLOAD compressed_bytes_ceil` from the log, which is the Huffman payload
before final 128-bit transport alignment.

Same algorithm family, Huffman versus Huffman:

| Input | Their software: `drichardson/huffman` output | Their ratio | This design: SoC Huffman payload | This ratio | Difference | Better ratio |
|---|---:|---:|---:|---:|---:|---|
| `input1.txt` | 833 B | 32.65% | 819 B | 32.11% | SoC smaller by 14 B / 0.54 points | SoC |
| `input3.txt` | 103 B | 42.56% | 102 B | 42.05% | SoC smaller by 1 B / 0.51 points | SoC |
| MIT-BIH 100 | 2080 B | 57.76% | 1961 B | 54.44% | SoC smaller by 119 B / 3.32 points | SoC |
| MIT-BIH 106 | 2403 B | 66.49% | 2237 B | 61.88% | SoC smaller by 166 B / 4.61 points | SoC |
| MIT-BIH 112 | 1821 B | 50.57% | 1780 B | 49.42% | SoC smaller by 41 B / 1.15 points | SoC |
| MIT-BIH 117 | 2007 B | 55.72% | 1943 B | 53.94% | SoC smaller by 64 B / 1.78 points | SoC |
| MIT-BIH 213 | 2236 B | 62.09% | 2119 B | 58.84% | SoC smaller by 117 B / 3.25 points | SoC |
| MIT-BIH average | 10547 B total | 58.53% | 10040 B total | 55.72% | SoC smaller by 507 B / 2.81 points | SoC |

General compression software versus SoC Huffman-only:

| Input | Their best software compressor | Their compressed output | Their ratio | This design: SoC Huffman payload | This ratio | Better ratio |
|---|---|---:|---:|---:|---:|---|
| `input1.txt` | Python `zlib-9` | 232 B | 9.09% | 819 B | 32.11% | Software |
| `input3.txt` | Python `zlib-6/9` | 30 B | 12.40% | 102 B | 42.05% | Software |
| `input4_cov.txt` | Python `lzma-6` | 1052 B | 17.53% | 3805 B | 63.40% | Software |
| MIT-BIH 100 | Python `lzma-6` | 1924 B | 53.43% | 1961 B | 54.44% | Software |
| MIT-BIH 106 | Python `lzma-6` | 2144 B | 59.32% | 2237 B | 61.88% | Software |
| MIT-BIH 112 | Python `bz2-9` | 1839 B | 51.07% | 1780 B | 49.42% | SoC |
| MIT-BIH 117 | Python `lzma-6` | 1960 B | 54.41% | 1943 B | 53.94% | SoC |
| MIT-BIH 213 | Python `lzma-6` | 2044 B | 56.76% | 2119 B | 58.84% | Software |

The general software-compressor table is not an algorithm-equivalence claim:
`zlib`, `bz2`, and `lzma` are mature desktop compression libraries, while this
design implements a hardware-friendly dynamic Huffman transport.

**Conclusion.** For the same Huffman-family comparison, the current SoC now
wins the tested `drichardson/huffman` ratio table. Mature general compressors
can still be smaller on some inputs because they use stronger algorithms than
plain Huffman. The correct claim is therefore: the hardware Huffman format now
beats the chosen pure-Huffman C baseline while remaining an FPGA-decodable
secure-storage datapath.

### 5.1.1 Huffman datapath speed after RTL optimization

The RTL now limits Huffman tree min-node scans to the allocated node range
(`0..next_free_index-1`) instead of scanning the full `MAX_TREE_NODES` array on
every merge. The latest format update also shortens table-reuse headers from
17 bits to 3 or 9 bits, which improves compression ratio while preserving RX
compatibility.

| Test input | TX cycles before | TX cycles after | Reduction | TX input throughput after, 100 MHz log assumption | TX input throughput after, 50 MHz FPGA clock |
|---|---:|---:|---:|---:|---:|
| `input1.txt` | 45481 | 32633 | 28.25% | 7.817 MB/s | 3.909 MB/s |
| `input2.txt` | 70833 | 43033 | 39.25% | 6.597 MB/s | 3.299 MB/s |
| `mitdb_112_mlii_10s_delta2_var.bin` | 68905 | 46561 | 32.43% | 7.734 MB/s | 3.867 MB/s |
| 3-file secure-storage bundle | 185219 | 122227 | 34.01% | 2.087 MB/s aggregate TX measurement | 1.044 MB/s aggregate TX measurement |

**Conclusion.** The latest RTL update improves both size and speed: compact
reuse headers make the Huffman payload smaller than the C Huffman baseline on
the tested report inputs, and the scan-limit optimization keeps TX cycles lower
than the earlier implementation.

### 5.2 Firmware software versus RTL design contract

| Firmware/software file | Software responsibility | Hardware design responsibility | Evidence testcase | Conclusion |
|---|---|---|---|---|
| `test_mmio_dma_storage_table.c` + `secure_storage_fw.h` | Secure write/read API, metadata table, `file_id`, original length, stored length, IV words | `dma_regfile` stores active config and IV; TX/RX datapaths transform bytes | `dma_storage_table_input1_then_input3`, PASS=22 FAIL=0 | File selection is software policy; hardware only sees selected addresses/length/mode/IV |
| `test_mmio_dma.c` | Direct TX/RX loopback, write IV, start TX, read `CIPHERTEXT_BYTES_PRODUCED`, start RX | DMA engines move data; TX does Huffman+AES; RX does AES+Huffman | `dma_compress_aes_input1`, PASS=18 FAIL=0 | This is the cleanest datapath proof without storage-table policy |
| `test_mmio_tx_only.c` | TX-only benchmark setup, select `MODE=0xD` to bypass AES | TX datapath runs whole-file Huffman and writes transport output | `tx_compress_only_input1`, PASS=15 FAIL=0 | This isolates Huffman compression from AES/RX |
| `test_mmio_rx_bad_length.c` | Deliberately programs invalid RX length | `dma_rx_engine` rejects non-16-byte-aligned ciphertext length | `mmio_rx_bad_length`, PASS=9 FAIL=0 | Error policy is enforced in hardware and visible to software |
| Generated `.S` files | Show actual RV32I load/store/branch sequence emitted by compiler | RV32I core executes instructions and MMIO bridge converts stores/loads to APB | All C-based tests compile to `.S/.mem` | The firmware is not pseudo-code; it becomes real RV32I instructions |

**Conclusion.** The software is part of the design, not just a test harness.
It owns metadata, IV/nonce policy, file selection, and sequencing. The RTL owns
the deterministic byte transformation and status/error enforcement.

## 6. AES And RISC-V Software Comparison

Reference:

- GitHub: [aadomn/aes](https://github.com/aadomn/aes)
- Paper: [Fixslicing AES-like Ciphers](https://eprint.iacr.org/2020/1123.pdf)

The GitHub README reports cycles per byte on an E31 RISC-V core:

| AES software implementation | Parallel blocks | E31 RISC-V cycles/byte |
|---|---:|---:|
| AES-128 semi-fixsliced | 2 | 93.4 |
| AES-128 fully-fixsliced | 2 | 89.3 |
| AES-128 barrel-shiftrows | 8 | 78.9 |
| AES-256 barrel-shiftrows | 8 | 105.7 |

Against the fastest AES-128 RISC-V software number in that table:

| This SoC case | Operation measured | SoC TX cycles/byte | Reference AES-128 RISC-V cycles/byte | Ratio |
|---|---|---:|---:|---:|
| `aes_core_benchmark` | AES-128 encrypt/decrypt RTL only | 0.688 | 78.9 | ~115x fewer cycles/byte |
| `input1.txt` | Huffman + AES-CBC + DMA write | 13.21 | 78.9 | 6.0x fewer cycles/byte |
| MIT-BIH avg | Huffman + AES-CBC + DMA write | 23.29 | 78.9 | 3.4x fewer cycles/byte |

This is not an exact CPU-to-CPU comparison. The AES-only number is a hardware
core cycle count. The full TX number is RTL accelerator/DMA busy cycles and
includes Huffman + AES + DMA write, while the reference number is pure AES
software on a RISC-V core.

**Conclusion.** The comparison supports the architectural decision to keep the
RV32I as the control plane and move AES/Huffman bit-level work into hardware.
It should not be described as a direct benchmark against a software-only CPU
implementation.

## 7. FPGA/Hardware Reference Comparison

| Reference | Useful comparison part | Published or measured result | Current design comparison | Conclusion |
|---|---|---|---|---|
| Canonical Huffman FPGA paper | Huffman encoder/decoder throughput | 160-bit input to 90-bit output; very high standalone throughput | This SoC is slower but supports 256-symbol file data, DMA, RX decode, and secure storage | Reference is better for raw Huffman throughput; this design is more system-integrated |
| Microsoft canonical Huffman HLS | Canonical Huffman energy/throughput | FPGA 13-16x ARM throughput and about 230x Core i7 energy efficiency | Current design is RTL integrated with AES-CBC and RV32I firmware | Use as motivation for Huffman acceleration, not direct result equality |
| `secworks/aes` | AES-only RTL maturity/performance | README lists `46 cycles/block`, `3020` LUT, `2992` FF, `125 MHz`; supports AES-128/256 | Current AES direct testcase measures `11 cycles/block`; TX AES is `1614` LUT and RX AES is `1667` LUT | Current core wins narrow latency; `secworks/aes` wins reusable/configurable IP scope |
| RisCO2 RISC-V sensor processor | RISC-V embedded SoC area/energy style | 4889 LUTs, 2354 FFs, 2 DSPs, 0.29 mJ in CO2 sensing task | Current full ZCU102 SoC is larger due to Huffman/AES/DMA | Use as RISC-V evaluation style reference, not same workload |

Latest full ZCU102 implementation status from project reports:

| Build | Timing/resource summary |
|---|---|
| `rv32_soc_synth_full_zcu102` | Timing pass, WNS `+7.871 ns`, `37069` LUTs, `19794` registers, `11` BRAM, `0` DSP, vectorless power about `0.793 W` |

**Conclusion.** Standalone references are better for their narrow target
(Huffman throughput, AES latency, or minimal RISC-V area). The current design's
contribution is a complete and verified FPGA secure-storage SoC.

## 8. Report Input Set

Use these as main report inputs:

| Input | Purpose |
|---|---|
| `sim/input1.txt` | Primary text/log-like secure-storage demo |
| `sim/input3.txt` | Small second file for metadata/file-id demo |
| `sim/mitdb_100_mlii_10s_delta2_var.bin` | ECG record 100 paper comparison |
| `sim/mitdb_106_mlii_10s_delta2_var.bin` | ECG record 106 paper comparison and worst case in current set |
| `sim/mitdb_112_mlii_10s_delta2_var.bin` | ECG record 112 paper comparison and best case in current set |
| `sim/mitdb_117_mlii_10s_delta2_var.bin` | ECG record 117 paper comparison |
| `sim/mitdb_213_mlii_10s_delta2_var.bin` | ECG record 213 paper comparison |

Keep these as regression/debug fixtures, not main report inputs:

| Input | Reason to keep |
|---|---|
| `sim/input2.txt` | Referenced by older run scripts/debug flows |
| `sim/input4_cov.txt` | Active long log-like TX-only coverage benchmark |
| `sim/input_cov_alnum63.txt` | Stress/coverage input where Huffman can expand |
| `sim/input_cov_ascii_sweep.txt` | 256-symbol stress/coverage input |
| `sim/input_cov_one_symbol.txt` | One-symbol stress/coverage input |
| `sim/input_cov_short_raw.txt` | Short-input stress/coverage input |
| `testcase/input_cov_alnum63.txt` | Testcase-local coverage copy |

**Conclusion.** The main report should use a small, defensible input set:
`input1`, `input3`, and five MIT-BIH records. Stress inputs remain useful for
coverage but should not dilute the main comparison.

## 9. References Used

### Local papers and reports from `refs`

- `/mnt/h/Academic/senior_project/DATN/refs/Graduation_Thesis_Ngoc_Tu_Ton_Luc.pdf`
  - Graduation-report structure reference: design, firmware/hardware
    verification, evaluation, comparison, summary.
- `/mnt/h/Academic/senior_project/DATN/refs/CAPSTONE_PROJECT_TRANQUOCTHIEN_NGUYENTUANKIET_FINAL.pdf`
  - Graduation-report structure reference: software golden result, simulation
    result, FPGA result, performance comparison, conclusion.
- `/mnt/h/Academic/senior_project/DATN/refs/nén_aes/huffman_AES_CBC (1).pdf`
  - ECG Huffman + CBC-AES comparison.
- `/mnt/h/Academic/senior_project/DATN/refs/nén_aes/1-s2.0-S2590123025011120-main.pdf`
  - Canonical Huffman FPGA encoder/decoder comparison.
- `/mnt/h/Academic/senior_project/DATN/refs/nén_aes/Secure and Efficient NVM Usage for Embedded SystemsUsing AES-128 and Huffman Compression.pdf`
  - Secure NVM/storage motivation.
- `/mnt/h/Academic/senior_project/DATN/refs/nén_aes/Huffman Tree and Binary Conversion for Decryption.pdf`
  - Huffman metadata/tree overhead and encrypted structure discussion.
- `/mnt/h/Academic/senior_project/DATN/refs/riscV/RisCO2 Implementation and Performance Evaluation of RISC-V Processors for Low-Power CO2 Concentration Sensing.pdf`
  - RISC-V sensor-processor area/energy comparison style.

### Online papers and GitHub

- [A lossless compression and encryption mechanism for remote monitoring of ECG data using Huffman coding and CBC-AES](https://www.sciencedirect.com/science/article/pii/S0167739X19313950)
- [FPGA implementation of high throughput encoder and decoder design of lossless canonical Huffman machine](https://www.sciencedirect.com/science/article/pii/S2590123025011120)
- [High-Throughput and Energy-Efficient Canonical Huffman Encoding](https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/asap14-canonical_huffman.pdf)
- [Fixslicing AES-like Ciphers](https://eprint.iacr.org/2020/1123.pdf)
- [aadomn/aes](https://github.com/aadomn/aes)
- [secworks/aes](https://github.com/secworks/aes)
- [drichardson/huffman](https://github.com/drichardson/huffman)
- [RisCO2: Implementation and Performance Evaluation of RISC-V Processors for Low-Power CO2 Concentration Sensing](https://www.mdpi.com/2072-666X/14/7/1371/html)

**Conclusion.** The reference set now supports the report in the same style as
the local graduation reports: references are used for the part they can fairly
validate, and each comparison states its scope and limitation.

## 10. Reproduce The Key Measurements

SoC:

```sh
cd sim
make compile C_SRC=test_mmio_dma.c
make all TESTNAME=dma_compress_aes_input1 RUN_ARGS="+CASE_NAME=dma_compress_aes_input1 +INPUT_FILE=input1.txt"
make all TESTNAME=dma_compress_aes_input3 RUN_ARGS="+CASE_NAME=dma_compress_aes_input3 +INPUT_FILE=input3.txt"
make all TESTNAME=dma_mitdb_100_delta2_var_e2e RUN_ARGS="+CASE_NAME=dma_mitdb_100_delta2_var_e2e +INPUT_FILE=mitdb_100_mlii_10s_delta2_var.bin +INPUT_BINARY"
make all TESTNAME=dma_mitdb_106_delta2_var_e2e RUN_ARGS="+CASE_NAME=dma_mitdb_106_delta2_var_e2e +INPUT_FILE=mitdb_106_mlii_10s_delta2_var.bin +INPUT_BINARY"
make all TESTNAME=dma_mitdb_112_delta2_var_e2e RUN_ARGS="+CASE_NAME=dma_mitdb_112_delta2_var_e2e +INPUT_FILE=mitdb_112_mlii_10s_delta2_var.bin +INPUT_BINARY"
make all TESTNAME=dma_mitdb_117_delta2_var_e2e RUN_ARGS="+CASE_NAME=dma_mitdb_117_delta2_var_e2e +INPUT_FILE=mitdb_117_mlii_10s_delta2_var.bin +INPUT_BINARY"
make all TESTNAME=dma_mitdb_213_delta2_var_e2e RUN_ARGS="+CASE_NAME=dma_mitdb_213_delta2_var_e2e +INPUT_FILE=mitdb_213_mlii_10s_delta2_var.bin +INPUT_BINARY"
make compile C_SRC=test_mmio_tx_only.c
make all TESTNAME=tx_compress_only_input1 RUN_ARGS="+CASE_NAME=tx_compress_only_input1 +INPUT_FILE=input1.txt"
make all TESTNAME=tx_compress_only_input4_cov RUN_ARGS="+CASE_NAME=tx_compress_only_input4_cov +INPUT_FILE=input4_cov.txt"
make compile C_SRC=test_mmio_dma_storage_table.c
make all TESTNAME=dma_storage_table_input1_then_input3 RUN_ARGS="+CASE_NAME=dma_storage_table_input1_then_input3 +INPUT_FILE=input1.txt +INPUT_FILE2=input2.txt"
make compile C_SRC=test_mmio_dma.c
```

External Huffman baseline:

```sh
git clone --depth 1 https://github.com/drichardson/huffman /tmp/aes_huffman_compare_drichardson_huffman
cd /tmp/aes_huffman_compare_drichardson_huffman
make
make check
./huffcode -m -c -i /path/to/input1.txt -o /tmp/input1.huff
./huffcode -m -d -i /tmp/input1.huff -o /tmp/input1.dec
cmp /path/to/input1.txt /tmp/input1.dec
```

AES RTL baseline:

```sh
git clone --depth 1 https://github.com/secworks/aes /tmp/aes_huffman_compare_secworks_aes
cd /tmp/aes_huffman_compare_secworks_aes/toolruns
make lint
```

**Conclusion.** The comparison can be reproduced from current project
testcases plus two external GitHub baselines. The report should cite the
commands only for the selected final inputs, not every coverage stress case.

## 11. Overall Architecture Conclusion

The current SoC should be positioned as a complete secure-storage architecture,
not as the best standalone compressor, best standalone AES core, or smallest
RISC-V processor.

| Architecture type | Strength of that architecture | Current SoC compared to it | Overall conclusion |
|---|---|---|---|
| Pure software compression | Best compression ratio and mature algorithms such as `zlib`, `bz2`, `lzma`, or optimized C Huffman | The SoC Huffman payload now beats the selected C Huffman baseline: MIT-BIH avg `55.72%` versus C Huffman `58.53%`; mature general compressors can still beat it on some inputs | SoC wins the chosen Huffman baseline; general compressors are a different algorithm class |
| Huffman-only FPGA accelerator | Very high compression/decompression throughput for a narrow Huffman workload | This SoC is slower and carries DMA/APB/RV32I overhead, but supports full file movement, TX/RX loopback, metadata, and secure-storage flow | Huffman-only FPGA wins raw throughput; this SoC wins system integration |
| AES-only RTL core | Reusable crypto IP, often with AES-128/AES-256 options and deeper standalone verification | This SoC AES direct testcase measures `11 cycles/block`, better than the `secworks/aes` published `46 cycles/block`, but it is AES-128-specific and embedded in Huffman + CBC + DMA + storage | Current SoC wins measured AES latency for this core; standalone AES IP wins reuse/configurability |
| Minimal RISC-V sensor SoC | Smaller LUT/FF/power footprint for sensing or control tasks | This SoC is larger because it includes DMA, Huffman TX/RX, AES-CBC, metadata support, UART/FPGA demo logic | Minimal RISC-V SoCs win area; this SoC wins secure-storage functionality |
| ECG Huffman + CBC-AES paper architecture | Better ECG-specific algorithm scope because preprocessing and PRD are part of the paper method | With external ECG preprocessing, this SoC reaches `29.87%` final ratio vs paper `35.015%`, but preprocessing is not inside RTL | This SoC has competitive final storage ratio, but the fair claim must state preprocessing is external |
| Current RV32I secure-storage SoC | Integrated firmware + DMA + Huffman + AES-CBC + RX restore + FPGA bitstream | Verified by TX/RX loopback, secure storage API test, coverage tests, and ZCU102 implementation | Best described as a verified FPGA secure-storage SoC, where RV32I is the control plane and accelerators are the data plane |

Final thesis statement:

```text
Compared with pure software compressors, the proposed SoC does not achieve the
best general-compressor ratio. Compared with Huffman-only hardware, it is not the raw
throughput or area winner because those designs specialize in one module.
Compared with AES-only RTL, the direct AES testcase is strong in latency, but
AES is still one stage inside the larger contribution: RV32I firmware, DMA,
metadata/file-id management, IV management, whole-file Huffman compression,
AES-128-CBC protection, RX restoration, simulation verification, and FPGA
implementation in one secure-storage SoC.
```

**Overall conclusion.** The correct high-level claim is: this project proves a
complete RV32I-controlled secure-storage SoC. Other architectures may be better
at one isolated task, but this design combines the required tasks into a
working hardware/software system.
