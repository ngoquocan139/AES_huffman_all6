# SOC 4.5 End-to-End Test Report

## 1. Scope

Tai lieu nay chi tap trung vao nhom testcase **4.5 SoC End-To-End** de dung
cho bao cao:

| ID | Testname | Input | Purpose |
|---|---|---|---|
| SOC-01 | `dma_compress_aes_input1` | `input1.txt` | Main secure-storage loopback |
| SOC-02 | `dma_compress_aes_input3` | `input3.txt` | Small/repeated input loopback |
| SOC-03 | `dma_compress_aes_alnum63_cov` | `input_cov_alnum63.txt` | Alnum63/codebook stress loopback |
| SOC-04 | `dma_storage_table_input1_then_input3` | `input1.txt` + `input3.txt` | Software-managed storage table demo |

Ba testcase loopback dau dung direct-DMA software:

```text
testcase/test_mmio_dma.c
```

`dma_storage_table_input1_then_input3` dung:

```text
testcase/secure_storage_fw.h
testcase/test_mmio_dma_storage_table.c
```

vi no can chung minh secure-storage firmware API, metadata records, IV restore,
va readback theo `file_id`.

`TESTNAME` chon file testcase Verilog trong `testcase/`. `CASE_NAME` la
plusarg de testbench in ten case vao log va gan report/dump voi dung testcase.

## 2. Commands

Chay lai rieng nhom 4.5:

```bash
cd sim
make license
make compile C_SRC=test_mmio_dma.c
make all
make all TESTNAME=dma_compress_aes_input3 RUN_ARGS="+CASE_NAME=dma_compress_aes_input3 +INPUT_FILE=input3.txt"
make all TESTNAME=dma_compress_aes_alnum63_cov RUN_ARGS="+CASE_NAME=dma_compress_aes_alnum63_cov +INPUT_FILE=input_cov_alnum63.txt"
make compile C_SRC=test_mmio_dma_storage_table.c
make all TESTNAME=dma_storage_table_input1_then_input3 RUN_ARGS="+CASE_NAME=dma_storage_table_input1_then_input3 +INPUT_FILE=input1.txt +INPUT_FILE2=input2.txt"
./report.csh
```

Latest focused secure-storage API run:

```text
Date: 2026-05-18
Testcase: dma_storage_table_input1_then_input3
Clock used by TB benchmark: 10 ns period, 100 MHz
Result: PASS=22, FAIL=0
Storage ratio: 34.50%
RX restored: 2551 bytes
```

Historical group result before the secure-storage API refactor remains
`34/34` PASS. Rerun the full regression if a fresh final post-API number is
required.

## 3. Data Flow Under Test

```mermaid
flowchart LR
  TXT["input .txt file"] --> TB["test_bench loader"]
  TB --> SRC["DMEM source @ 0x00002000"]
  CPU["RV32I firmware"] --> REG["DMA regfile via CPU MMIO -> APB bridge"]
  REG --> TXDMA["dma_tx_engine"]
  SRC --> TXDMA
  TXDMA --> TX["TX accelerator\nwhole-file Huffman + AES-CBC"]
  TX --> CT["DMEM ciphertext @ 0x00004000"]
  CPU --> RXDMA["dma_rx_engine"]
  CT --> RXDMA
  RXDMA --> RX["RX accelerator\nAES-CBC decrypt + Huffman decode"]
  RX --> OUT["DMEM plaintext @ 0x00006000"]
  OUT --> CMP["TB compare RX vs input"]
```

Step-by-step:

1. Testbench load input text vao `DMEM` source region `0x00002000`.
2. CPU RV32I doc `input_len` tu DMEM. Trong direct loopback, CPU tao IV demo va
   ghi `DMA_IV0..3`; trong storage-table testcase, `secure_storage_fw.h` tao IV,
   luu IV vao metadata, va restore IV khi doc lai.
3. CPU cau hinh TX: `SRC=0x00002000`, `DST=0x00004000`, `LEN=input_len`, `MODE=0x9`, `BLOCK=0x20`, roi start DMA.
4. `dma_tx_engine` doc plaintext tu DMEM, nap TX accelerator qua private APB.
5. TX accelerator tao dynamic Huffman codebook cho whole file, pack thanh transport word 128-bit, AES-CBC encrypt, va ghi ciphertext ve DMEM TX region.
6. CPU polling TX done, doc `tx_bytes_done`, sau do cau hinh RX: `SRC=0x00004000`, `DST=0x00006000`, `LEN=tx_bytes_done`, `MODE=0x2`.
7. `dma_rx_engine` doc ciphertext, feed RX accelerator.
8. RX accelerator AES-CBC decrypt, depack transport, parse Huffman header/codebook, decode plaintext, va ghi RX plaintext ve DMEM.
9. Testbench dump 3 vung DMEM va compare:
   - source DMEM vs input file
   - RX DMEM vs input file
   - TX region must not be all zero

## 4. Pass/Fail Criteria

Moi SOC testcase pass khi:

| Check | Meaning |
|---|---|
| `cpu_error_mask_should_be_zero` | CPU software khong thay loi MMIO/DMA |
| `tx_status_before_start` / `tx_status_after_done` | TX status dung truoc va sau DMA |
| `tx_bytes_done_should_be_transport_aligned` | Ciphertext/transport output align 16 byte |
| `rx_status_after_done` | RX done sticky set dung |
| `rx_bytes_done_should_match_input_len` | RX restore dung so byte plaintext ban dau |
| `source_dmem_should_match_input_file` | Loader nap dung input vao DMEM |
| `loopback_rx_should_match_input_file` | End-to-end TX->RX khop input goc |
| `tx_ciphertext_region_should_not_be_all_zero` | TX thuc su tao ciphertext/transport data |
| `dma_start_pulse_count == 2` | Co dung 2 DMA transfer: TX roi RX |

## 5. Latest Results

| Testname | PASS/FAIL | Input bytes | TX bytes | RX bytes | Payload ratio | Payload saving | Storage ratio | Storage saving |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `dma_compress_aes_input1` | PASS | 2551 | 880 | 2551 | 32.11% | 67.89% | 34.50% | 65.50% |
| `dma_compress_aes_input3` | PASS | 242 | 112 | 242 | 42.05% | 57.95% | 46.28% | 53.72% |
| `dma_compress_aes_alnum63_cov` | PASS | 504 | 560 | 504 | 101.86% | -1.86% | 111.11% | -11.11% |
| `dma_storage_table_bundle3` | PASS | input1 + input2 + ECG 112 | TX1 880 | RX selected 2551 | 32.11% for file_id=1 | 67.89% | 34.50% | 65.50% |

Interpretation:

| Testname | Note |
|---|---|
| `dma_compress_aes_input1` | Nen tot, storage saving `59.86%`, loopback dung. |
| `dma_compress_aes_input3` | Input ngan/lap lai cao, storage saving `53.72%`, loopback dung. |
| `dma_compress_aes_alnum63_cov` | Input gan uniform voi 63 symbol, header/codebook overhead lon hon payload saving, nen storage saving am. Day la stress functional, khong phai case toi uu nen. |
| `dma_storage_table_input1_then_input3` | Chung minh `secure_write` luu 2 ciphertext record, metadata giu `file_id/cipher_addr/cipher_len/plain_len/IV`, va `secure_read(file_id=1)` restore lai input1 dung. |

## 6. Throughput Benchmark

Throughput duoc TB tinh theo:

```text
bytes_per_cycle = bytes / busy_cycles
MB/s = bytes_per_cycle * (1000 / CLOCK_PERIOD_NS)
```

Voi `CLOCK_PERIOD_NS = 10 ns`, tuc benchmark simulation dang quy doi theo
`100 MHz`. Neu demo FPGA chay `50 MHz`, throughput xap xi bang mot nua bang
duoi.

| Testname | TX cycles | RX cycles | TX input MB/s | TX output MB/s | RX input MB/s | RX output MB/s |
|---|---:|---:|---:|---:|---:|---:|
| `dma_compress_aes_input1` | 45441 | 14931 | 5.614 | 2.253 | 6.858 | 17.085 |
| `dma_compress_aes_input3` | 10805 | 5206 | 2.240 | 1.037 | 2.151 | 4.648 |
| `dma_compress_aes_alnum63_cov` | 44457 | 8491 | 1.134 | 1.260 | 6.595 | 5.936 |

## 7. Output Files

Per-test logs:

| Testname | Log |
|---|---|
| `dma_compress_aes_input1` | `sim/log/dma_compress_aes_input1.log` |
| `dma_compress_aes_input3` | `sim/log/dma_compress_aes_input3.log` |
| `dma_compress_aes_alnum63_cov` | `sim/log/dma_compress_aes_alnum63_cov.log` |
| `dma_storage_table_input1_then_input3` | `sim/log/dma_storage_table_input1_then_input3.log` |

Per-test loopback summaries:

| Testname | Summary | Compare |
|---|---|---|
| `dma_compress_aes_input1` | `sim/loopback/dma_compress_aes_input1_summary.txt` | `sim/loopback/dma_compress_aes_input1_compare.txt` |
| `dma_compress_aes_input3` | `sim/loopback/dma_compress_aes_input3_summary.txt` | `sim/loopback/dma_compress_aes_input3_compare.txt` |
| `dma_compress_aes_alnum63_cov` | `sim/loopback/dma_compress_aes_alnum63_cov_summary.txt` | `sim/loopback/dma_compress_aes_alnum63_cov_compare.txt` |
| `dma_storage_table_input1_then_input3` | `sim/loopback/dma_storage_table_input1_then_input3_summary.txt` | `sim/loopback/dma_storage_table_input1_then_input3_compare.txt` |

Per-test DMEM dumps:

| Testname | Source dump | TX dump | RX dump |
|---|---|---|---|
| `dma_compress_aes_input1` | `sim/dmem_dump/dma_compress_aes_input1_src.txt` | `sim/dmem_dump/dma_compress_aes_input1_tx.txt` | `sim/dmem_dump/dma_compress_aes_input1_rx.txt` |
| `dma_compress_aes_input3` | `sim/dmem_dump/dma_compress_aes_input3_src.txt` | `sim/dmem_dump/dma_compress_aes_input3_tx.txt` | `sim/dmem_dump/dma_compress_aes_input3_rx.txt` |
| `dma_compress_aes_alnum63_cov` | `sim/dmem_dump/dma_compress_aes_alnum63_cov_src.txt` | `sim/dmem_dump/dma_compress_aes_alnum63_cov_tx.txt` | `sim/dmem_dump/dma_compress_aes_alnum63_cov_rx.txt` |
| `dma_storage_table_input1_then_input3` | `sim/dmem_dump/dma_storage_table_input1_then_input3_src.txt` | `sim/dmem_dump/dma_storage_table_input1_then_input3_tx.txt` | `sim/dmem_dump/dma_storage_table_input1_then_input3_rx.txt` |

`sim/rep.log` also has a dedicated section:

```text
SOC 4.5 END-TO-END MAIN TESTCASES
```

## 8. Report Wording

Suggested wording:

```text
The SoC end-to-end tests validate the complete secure-storage data path.
The testbench first loads a text input into DMEM. The RV32I software configures
the DMA register file through MMIO/APB, starts the TX DMA transfer, and the TX
accelerator performs whole-file dynamic Huffman compression followed by AES-CBC
encryption. The ciphertext is stored back into DMEM. The CPU then configures the
RX DMA transfer, which reads the ciphertext from DMEM, performs AES-CBC
decryption and Huffman decoding, and writes the restored plaintext to another
DMEM region. The testbench compares the restored plaintext byte-by-byte with
the original input and dumps the source, TX, and RX memory regions for review.
```
