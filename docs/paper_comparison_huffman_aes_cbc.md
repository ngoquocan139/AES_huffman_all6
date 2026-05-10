# Paper Comparison: Huffman + CBC-AES ECG Design

## 1. Reference

Referenced paper:

```text
A lossless compression and encryption mechanism for remote monitoring of ECG
data using Huffman coding and CBC-AES
```

Local PDF:

```text
H:\Academic\senior_project\DATN\refs\nén_aes\huffman_AES_CBC (1).pdf
```

The paper reports:

| Item | Paper value |
|---|---:|
| Dataset | MIT-BIH ECG, five records |
| Processing | ECG denoising/filtering/blocking, Huffman compression, AES-CBC |
| AES key size | 256-bit key |
| Reported compression ratio | 35.015% |
| Equivalent space saving | 64.985% |
| Reported PRD | 0.411 |

Note: Table 1 in the PDF has a typo/inconsistency: it lists record `123`, but
the experiment text and Tables 5-7 list `213`. The runs below use
`100, 106, 112, 117, 213`, matching the result tables in the paper.

## 2. Current SoC Result

Current RTL status after increasing the dynamic Huffman codebook to 256
byte-symbols:

| Testcase | Input | Mode | Payload ratio | Final storage ratio | Final space saving |
|---|---|---|---:|---:|---:|
| `dma_compress_aes_input1` | `input1.txt`, 2551 bytes | Huffman + AES-128-CBC | 37.50% | 40.14% | 59.86% |
| `dma_compress_aes_input3` | `input3.txt`, 242 bytes | Huffman + AES-128-CBC | 42.05% | 46.28% | 53.72% |
| `dma_compress_aes_alnum63_cov` | 63-symbol stress, 504 bytes | Huffman + AES-128-CBC | 101.86% | 111.11% | -11.11% |
| `tx_compress_only_input4_cov` | `input4_cov.txt`, 6000 bytes | Huffman only, AES bypass | 63.40% | 67.73% | 32.27% |

Main implementation results at 50 MHz:

| Build | WNS | LUT | BRAM | Power |
|---|---:|---:|---:|---:|
| TX-only | +0.217 ns | 45501 | 10 | 0.239 W |
| RX-only | +0.341 ns | 22730 | 11 | 0.193 W |

Coverage:

| Metric | Value |
|---|---:|
| Active testcase | 34 |
| Passed testcase | 34 |
| Raw DUT `bcesft` | 93.52% |
| Closed DUT coverage | 95.90% |

## 3. Generic SoC Compression Results

These generic text testcases are useful to show that the SoC secure-storage
path works on normal byte streams. They are not the main paper comparison.

| Design | Compression ratio | Space saving | Comment |
|---|---:|---:|---|
| Paper proposed model | 35.015% | 64.985% | ECG-specific signal chain before/around Huffman |
| This SoC, `input1.txt` | 40.14% | 59.86% | Best current secure-storage testcase |
| Gap versus paper | +5.125 percentage points ratio | -5.125 percentage points saving | Lower is better for ratio |

Interpretation:

- `input1.txt` is a generic byte-stream test, not the selected MIT-BIH paper
  comparison path.
- The `input1.txt` result is close: `40.14%` final storage ratio versus paper
  `35.015%`.
- The comparison is not apples-to-apples because the paper is ECG-specific and
  includes denoising/filtering/DWT-style processing before Huffman, while this
  SoC currently compresses byte streams losslessly with dynamic whole-file
  Huffman.
- The SoC contribution is architectural: RV32I control plane, MMIO/APB DMA
  contract, TX/RX accelerators, AES-CBC integration, DMEM storage, FPGA
  synthesis/implementation, and coverage regression.

## 3.1 Same MIT-BIH Input With External Host Preprocessing

This is the MIT-BIH comparison path used for the thesis report. The SoC input
is already-processed data. The preprocessing is outside the SoC and outside the
RTL verification scope:

```text
MIT-BIH ECG sample files
-> second-order delta residual
-> ZigZag mapping
-> variable-length unsigned integer byte stream
-> RV32I SoC Huffman + AES-CBC secure-storage path
```

For this project, the already-processed byte streams are kept as `.bin` test
inputs in `sim/`:

| MITDB record | SoC input file |
|---:|---|
| 100 | `mitdb_100_mlii_10s_delta2_var.bin` |
| 106 | `mitdb_106_mlii_10s_delta2_var.bin` |
| 112 | `mitdb_112_mlii_10s_delta2_var.bin` |
| 117 | `mitdb_117_mlii_10s_delta2_var.bin` |
| 213 | `mitdb_213_mlii_10s_delta2_var.bin` |

This means the reported RTL result measures the SoC secure-storage path for an
already-processed ECG byte stream.

Command pattern:

```bash
cd sim
make compile C_SRC=test_mmio_dma.c
make all TESTNAME=dma_mitdb_100_delta2_var_e2e \
  RUN_ARGS="+CASE_NAME=dma_mitdb_100_delta2_var_e2e +INPUT_FILE=mitdb_100_mlii_10s_delta2_var.bin +INPUT_BINARY"
```

Result, measured against the original `7200` raw bytes per record:

| MITDB record | Raw bytes | Host-processed bytes | SoC TX bytes | Final ratio vs raw | Final saving vs raw | Loopback |
|---:|---:|---:|---:|---:|---:|---|
| 100 | 7200 | 3601 | 2304 | 32.00% | 68.00% | PASS |
| 106 | 7200 | 3614 | 2608 | 36.22% | 63.78% | PASS |
| 112 | 7200 | 3601 | 2112 | 29.33% | 70.67% | PASS |
| 117 | 7200 | 3602 | 2288 | 31.78% | 68.22% | PASS |
| 213 | 7200 | 3601 | 2480 | 34.44% | 65.56% | PASS |
| Average | 7200 | 3603.8 | 2358.4 | 32.76% | 67.24% | PASS |

Comparison to the paper:

| Design | Dataset/input condition | Final storage ratio | Space saving |
|---|---|---:|---:|
| Paper proposed model | MIT-BIH ECG with paper processing chain | 35.015% | 64.985% |
| This SoC | Same records, external delta2+varuint preprocessing, then SoC Huffman+AES-CBC | 32.76% average | 67.24% average |
| Gap | Lower ratio is better | -2.26 percentage points | +2.26 percentage points |

Interpretation:

- With external ECG-oriented preprocessing, the SoC TX/RX secure-storage path
  beats the paper's reported ratio on this five-record set.
- The correct thesis claim is not that the RTL implements ECG preprocessing.
  The correct claim is: "The SoC can securely store an already-processed ECG
  byte stream, and on the same MIT-BIH records this end-to-end storage ratio is
  32.76% after external preprocessing."
- RX restores the preprocessed byte stream exactly. If the final application
  needs raw ECG samples, an inverse host-side delta2+varuint decoder is required
  outside the current SoC.

## 4. How To Present To The Advisor

Use this wording:

```text
The referenced paper reports a 35.015% compression ratio on MIT-BIH ECG data
with Huffman coding and CBC-AES. In my comparison flow, the same MIT-BIH
records 100/106/112/117/213 are first transformed outside the SoC using
second-order delta residuals and variable-length byte coding. The resulting
byte stream is then stored by the RV32I SoC using dynamic Huffman compression
and AES-128-CBC. Under this input condition, the SoC achieves 32.76% average
final storage ratio, compared with the paper's 35.015%.
```

If asked whether the SoC can beat the paper:

```text
Yes, in the selected comparison flow using externally preprocessed ECG input:
32.76% average final storage ratio versus 35.015% in the paper. The precise
scope is important: the current RTL does not implement ECG preprocessing; it
implements the RV32I-controlled secure-storage path for the processed byte
stream.
```

## 5. Fair Comparison Table For Thesis

| Axis | Paper | This SoC |
|---|---|---|
| Main goal | ECG remote monitoring compression/encryption algorithm | Hardware SoC for secure storage |
| Input domain | MIT-BIH ECG signal records | Generic byte stream in DMEM |
| Compression | Huffman after ECG signal processing | Dynamic whole-file canonical Huffman over 256 byte symbols |
| Encryption | AES-CBC, 256-bit key | AES-128-CBC |
| CPU/control | Algorithm simulation/software flow | RV32I controls DMA through MMIO/APB |
| Hardware implementation | Suggested future embedded testing | RTL implemented, verified, synthesized and implemented |
| Verification | Algorithm metrics such as CR/PRD | RTL loopback, pass/fail self-checks, coverage, Vivado reports |
| Current best ratio on generic testcase | 35.015% | 40.14% on `input1.txt` |
| Same MIT-BIH with external preprocessing | 35.015% | 32.76% |

## 6. Next Improvement If Compression Is The Priority

To improve compression beyond current byte-level Huffman:

| Option | Expected impact | Architecture impact |
|---|---|---|
| Delta coding before Huffman | Good for numeric/sensor streams | Add predictor stage before TX Huffman and inverse stage in RX |
| ECG beat/template coding | High for periodic ECG | Domain-specific, more complex metadata |
| DWT/quantization | Can approach paper-style ratio | May become lossy, requires arithmetic-heavy RTL |
| Adaptive raw/compressed decision per file | Avoid negative saving | Add file-level mode decision and metadata |
| Better transport header packing | Reduces overhead for small files | Smaller RTL change |

For the current thesis scope, the strongest claim is not "best compression
ratio"; it is "verified secure-storage SoC with dynamic Huffman + AES-CBC and
FPGA-ready split TX/RX implementation."
