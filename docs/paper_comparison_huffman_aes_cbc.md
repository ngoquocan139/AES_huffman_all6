# Paper Comparison: Huffman + CBC-AES ECG Design

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
| Records used in result tables | `100`, `106`, `112`, `117`, `213` |
| Processing | ECG preprocessing + Huffman compression + CBC-AES |
| AES key size | 256-bit key |
| Compression ratio | `35.015%` |
| Space saving | `64.985%` |
| PRD | `0.411` |

Note: one table in the PDF lists record `123`, but the experiment text and
result tables list `213`. The comparison here uses `100/106/112/117/213`.

## 2. This SoC Comparison Condition

The SoC does not implement ECG signal preprocessing in RTL. For paper
comparison, the input to the SoC is an already-preprocessed byte stream:

```text
MIT-BIH ECG record
-> external preprocessing outside the SoC
-> delta2 + ZigZag + variable-length byte stream
-> RV32I SoC dynamic Huffman + AES-128-CBC secure storage
-> RX loopback restores the processed byte stream
```

This is the correct scope of the comparison:

| Item | Meaning |
|---|---|
| What is measured | SoC secure-storage ratio after external ECG-oriented preprocessing |
| What RTL implements | RV32I control, MMIO/APB, DMA, dynamic Huffman, AES-128-CBC TX/RX |
| What RTL does not implement | ECG preprocessing / inverse ECG reconstruction |
| RX correctness | RX output byte stream equals SoC input byte stream |

## 3. Input Files

The active input files are binary streams in `sim/`:

| MIT-BIH record | SoC input file | SoC input bytes |
|---:|---|---:|
| 100 | `mitdb_100_mlii_10s_delta2_var.bin` | 3601 |
| 106 | `mitdb_106_mlii_10s_delta2_var.bin` | 3614 |
| 112 | `mitdb_112_mlii_10s_delta2_var.bin` | 3601 |
| 117 | `mitdb_117_mlii_10s_delta2_var.bin` | 3602 |
| 213 | `mitdb_213_mlii_10s_delta2_var.bin` | 3601 |

The raw reference length is `7200` bytes per record:

```text
3600 samples * 2 bytes/sample = 7200 bytes
```

## 4. Command Pattern

Example for record `100`:

```bash
cd sim
make compile C_SRC=test_mmio_dma.c
make all TESTNAME=dma_mitdb_100_delta2_var_e2e \
  RUN_ARGS="+CASE_NAME=dma_mitdb_100_delta2_var_e2e +INPUT_FILE=mitdb_100_mlii_10s_delta2_var.bin +INPUT_BINARY"
```

Change the record number in both `TESTNAME` and `INPUT_FILE` to run
`106`, `112`, `117`, or `213`.

## 5. Results

| Record | Raw bytes reference | SoC input bytes | SoC TX bytes | Final ratio vs raw | Final saving vs raw | Loopback |
|---:|---:|---:|---:|---:|---:|---|
| 100 | 7200 | 3601 | 2304 | 32.00% | 68.00% | PASS |
| 106 | 7200 | 3614 | 2608 | 36.22% | 63.78% | PASS |
| 112 | 7200 | 3601 | 2112 | 29.33% | 70.67% | PASS |
| 117 | 7200 | 3602 | 2288 | 31.78% | 68.22% | PASS |
| 213 | 7200 | 3601 | 2480 | 34.44% | 65.56% | PASS |
| Average | 7200 | 3603.8 | 2358.4 | 32.76% | 67.24% | PASS |

Comparison:

| Design | Condition | Final storage ratio | Space saving |
|---|---|---:|---:|
| Referenced paper | MIT-BIH ECG, paper processing chain | 35.015% | 64.985% |
| This SoC | Same records, externally preprocessed input, SoC Huffman + AES-128-CBC | 32.76% | 67.24% |
| Difference | Lower ratio is better | -2.26 percentage points | +2.26 percentage points |

## 6. Interpretation

Main conclusion:

```text
With externally preprocessed MIT-BIH input, the SoC secure-storage path reaches
32.76% average final storage ratio, better than the paper's 35.015%.
```

Important limitation:

```text
The current RTL does not implement ECG preprocessing. It stores and restores
the already-preprocessed byte stream. If raw ECG reconstruction is required,
the inverse preprocessing step must exist outside the current SoC or be added
as future RTL/software work.
```

## 7. Suggested Thesis Wording

Use this wording:

```text
The referenced paper reports a 35.015% compression ratio for MIT-BIH ECG data
using Huffman coding and CBC-AES. In my evaluation, the same record set
100/106/112/117/213 is first transformed outside the SoC into a delta2,
ZigZag, variable-length byte stream. The RV32I SoC then performs dynamic
Huffman compression and AES-128-CBC secure storage. Under this input condition,
the average final storage ratio is 32.76%, which is 2.26 percentage points
better than the paper's reported ratio.
```

If asked whether this is a fair comparison:

```text
It is fair only under the stated input condition: both designs are evaluated
on the same MIT-BIH records, but my SoC receives an already-preprocessed byte
stream. I do not claim that the RTL performs ECG preprocessing. The hardware
contribution is the verified RV32I-controlled Huffman + AES-CBC secure-storage
SoC.
```

## 8. Architecture Comparison

| Axis | Paper | This SoC |
|---|---|---|
| Main goal | ECG compression/encryption algorithm | Hardware SoC for secure storage |
| Input domain | MIT-BIH ECG signal | Already-preprocessed byte stream in DMEM |
| Compression | Huffman after ECG-oriented processing | Dynamic whole-file canonical Huffman over 256 byte symbols |
| Encryption | CBC-AES, 256-bit key | AES-128-CBC |
| Control | Algorithm/software experiment | RV32I software controls DMA through MMIO/APB |
| Hardware status | Not the main contribution | RTL implemented, verified, synthesized, implemented |
| Verification | Compression metrics and PRD | RTL loopback, pass/fail, coverage, Vivado reports |

## 9. Future Work

If the project needs to own the complete ECG compression chain, add one of:

| Improvement | Effect | Cost |
|---|---|---|
| RTL delta/predictor stage | Makes preprocessing part of SoC | Adds TX predictor and RX inverse predictor |
| RV32I preprocessing software | Keeps hardware smaller | Slower, CPU does more data work |
| Beat/template ECG coding | Better ECG-specific compression | More algorithm and metadata complexity |
| DWT/quantization | Can approach ECG paper methods | May become lossy and arithmetic-heavy |
