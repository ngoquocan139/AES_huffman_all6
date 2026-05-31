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
| 100 | 3601 | 2156 | 59.87% | 2080 | 57.76% |
| 106 | 3614 | 2432 | 67.29% | 2403 | 66.49% |
| 112 | 3601 | 1975 | 54.84% | 1821 | 50.57% |
| 117 | 3602 | 2138 | 59.36% | 2007 | 55.72% |
| 213 | 3601 | 2314 | 64.26% | 2236 | 62.09% |
| Average | 18019 total | 11015 total | 61.13% | 10547 total | 58.53% |

The C Huffman baseline is `drichardson/huffman`, built and checked locally.

**Conclusion.** On Huffman-only payload size, the software Huffman baseline is
smaller by about `2.60` percentage points on the five ECG streams. The SoC's
value is hardware offload plus a hardware-decodable transport format.

## 5. Final Secure-Storage Ratio Comparison

This comparison includes final stored TX bytes after transport and AES-CBC
alignment.

| Record | Raw bytes reference | SoC input bytes | SoC final TX bytes | Final ratio vs raw | Final saving vs raw | Loopback |
|---:|---:|---:|---:|---:|---:|---|
| 100 | 7200 | 3601 | 2304 | 32.00% | 68.00% | PASS |
| 106 | 7200 | 3614 | 2608 | 36.22% | 63.78% | PASS |
| 112 | 7200 | 3601 | 2112 | 29.33% | 70.67% | PASS |
| 117 | 7200 | 3602 | 2288 | 31.78% | 68.22% | PASS |
| 213 | 7200 | 3601 | 2480 | 34.44% | 65.56% | PASS |
| Average | 7200 | 3603.8 | 2358.4 | 32.76% | 67.24% | PASS |

| Design | Condition | Final storage ratio | Space saving |
|---|---|---:|---:|
| Referenced paper | MIT-BIH ECG, paper processing chain | 35.015% | 64.985% |
| This SoC | Same records, external preprocessing, SoC Huffman + AES-128-CBC | 32.76% | 67.24% |
| Difference | Lower ratio is better | -2.26 percentage points | +2.26 percentage points |

**Conclusion.** On the final stored-size view, the current flow is better than
the paper by `2.26` percentage points. This conclusion is valid only when the
external preprocessing condition is stated.

## 6. Software Versus Hardware Design Responsibility

| Layer | Software responsibility | Hardware responsibility | Proof |
|---|---|---|---|
| File selection | Choose `file_id`, locate metadata record | Hardware does not know file names or file IDs | `dma_storage_table_input1_then_input3` |
| IV management | Generate/store/write `IV0..IV3` | TX/RX consume `cbc_iv_i` for CBC chain | `dma_compress_aes_input1` |
| TX start | Program `SRC/DST/LEN/MODE`, assert start | DMA TX reads DMEM, runs Huffman/AES, writes TX buffer | `dma_compress_aes_input1`, `tx_compress_only_input1` |
| RX start | Use `CIPHERTEXT_BYTES_PRODUCED` as RX length | DMA RX feeds AES decrypt/Huffman decode and writes plaintext | `dma_compress_aes_input1` |
| Error handling | Poll status and read error/debug registers | DMA/RX reject bad alignment and internal errors | `mmio_rx_bad_length` |

**Conclusion.** The software is not just a driver. It is the secure-storage
policy layer. The hardware is the deterministic acceleration layer.

## 7. Suggested Thesis Wording

Use this wording:

```text
The referenced ECG paper reports a 35.015% final compression ratio using
Huffman coding and CBC-AES. My comparison separates the result into two
levels. At the Huffman-only level, the SoC payload ratio on the same five
preprocessed ECG byte streams is 61.13%, while a C Huffman reference reaches
58.53%. At the secure-storage level, after external ECG preprocessing and SoC
Huffman + AES-128-CBC storage, the final average ratio is 32.76% versus the
paper's 35.015%. Therefore, the SoC demonstrates a verified hardware
secure-storage datapath, while ECG-specific preprocessing remains outside the
current RTL scope.
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

## 8. Future Work

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
