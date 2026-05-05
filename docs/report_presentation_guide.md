# Report Presentation Guide

## 1. Specs Review Summary

Dung cac spec theo thu tu nay khi on bao cao:

| Priority | Document | Use in report |
|---:|---|---|
| 1 | `00_current_system_spec.md` | Source of truth cho kien truc SoC hien tai |
| 2 | `soc_4_5_end_to_end_report.md` | Ket qua testcase end-to-end chinh |
| 3 | `coverage_regression_report.md` | Coverage/testplan va cac testcase da chay |
| 4 | `soc_usage_and_fpga_guide.md` | Lenh chay, cach doi input/C file, FPGA next step |
| 5 | `tx_path_end_to_end_spec.md` | Giai thich rieng TX khi bi hoi sau |
| 6 | `rx_path_end_to_end_spec.md` | Giai thich rieng RX khi bi hoi sau |
| 7 | `memory_map_dma_software_contract.md` | Bang dia chi MMIO/DMEM |
| 8 | `iv_generation_and_cbc_contract_spec.md` | Giai thich IV va AES-CBC |

Khong can trinh bay tung spec module con tren slide. Cac file nhu
`dma_tx_engine_spec.md`, `dynamic_huffman_encoder_spec.md`,
`huffman_block_decoder_spec.md`, `apb_huffman_rx_if_spec.md` chi dung de tra
loi cau hoi chi tiet.

## 2. Main Story To Tell

Ten de tai:

```text
Design of a RISC-V RV32I System Integrating Huffman Compression and AES-128
for Secure Data Storage
```

Nen bao cao theo cau chuyen nay:

1. He thong la mot SoC RV32I nho, CPU dong vai tro control plane.
2. Du lieu nam trong DMEM, CPU khong tu copy tung byte ma cau hinh DMA qua MMIO.
3. TX DMA doc plaintext tu DMEM, dua qua Huffman dynamic whole-file va AES-128
   CBC, roi ghi ciphertext/transport stream ve DMEM.
4. RX DMA doc ciphertext tu DMEM, AES-CBC decrypt, Huffman decode, roi ghi
   plaintext phuc hoi ve DMEM.
5. Testbench kiem tra loopback bang cach so sanh RX output voi input goc, dong
   thoi dump source/TX/RX DMEM va tinh compression/throughput.
6. FPGA demo thuc dung hien tai tach TX-only va RX-only de vua tai nguyen va
   timing tren Zynq-7020.

## 3. Architecture Points To Present

### 3.1 Top-level SoC

Nen ve mot hinh gom:

```text
RV32I CPU
  -> cpu_mmio_to_apb_bridge
  -> dma_regfile
  -> dma_tx_engine / dma_rx_engine
  -> TX accelerator / RX accelerator
  -> DMEM
```

Them cac khoi phu:

- IMEM chua `instruction.mem`.
- DMEM 32 KiB chua input, ciphertext va output.
- UART DMEM loader cho FPGA demo.
- IV registers `IV0..IV3` cho AES-CBC.

### 3.2 Control plane

CPU dung instruction RV32I co ban:

- `lw/sw` de doc/ghi DMEM va MMIO.
- `addi/and/or/xor/sll/srl` de tinh config va demo IV.
- `beq/bne/jal` de polling status.

CPU cau hinh DMA bang MMIO:

```text
SRC_ADDR, DST_ADDR, LEN_BYTES, MODE, BLOCK_CFG, IV0..IV3, CONTROL.start
```

CPU polling `STATUS.done_sticky` / `STATUS.error_sticky`.

### 3.3 Data plane

Data plane moi la phan xu ly toc do cao:

```text
DMEM -> DMA -> Huffman/AES accelerator -> DMA -> DMEM
```

CPU khong bi stall trong suot DMA transfer. CPU chi bi hold khi dang thuc hien
mot MMIO APB transaction hoac memory pipeline can hold.

## 4. TX/RX Flow To Explain

### TX flow

```text
DMEM plaintext
-> dma_tx_engine
-> dynamic whole-file Huffman encoder
-> bit_packer_128
-> AES-128 CBC encrypt, hoac AES bypass neu COMPRESS_ONLY
-> TX output FIFO
-> DMEM ciphertext/transport region
```

Mode nen noi:

| Mode | Meaning |
|---:|---|
| `0x9` | Main secure-storage TX: whole-file Huffman + AES-CBC |
| `0xD` | TX-only compression benchmark: whole-file Huffman, AES bypass |
| `0x2` | RX decrypt + Huffman decode |

### RX flow

```text
DMEM ciphertext
-> dma_rx_engine
-> AES-128 CBC decrypt
-> bit_depacker_128
-> huffman_block_parser
-> huffman_block_decoder
-> rx_byte_packer_32
-> DMEM plaintext output
```

RX can cung IV voi TX va `LEN_BYTES` cua RX bang
`CIPHERTEXT_BYTES_PRODUCED` tu TX.

## 5. Main Results To Report

### 5.1 SoC end-to-end testcase group 4.5

Day la nhom testcase chinh nen dua vao bao cao:

| Testcase | Input | Result | Storage saving | Note |
|---|---|---:|---:|---|
| `dma_compress_aes_input1` | `input1.txt`, 2551 bytes | PASS | 61.11% | Main secure-storage loopback |
| `dma_compress_aes_input3` | `input3.txt`, 242 bytes | PASS | 53.72% | Small/repeated input |
| `dma_compress_aes_alnum63_cov` | 63-symbol stress, 504 bytes | PASS | -7.94% | Functional stress, not compression-optimized |

Can nhan manh:

- `src_mismatch=0`
- `rx_mismatch=0`
- `SUMMARY: PASS=18 FAIL=0`
- TX output non-zero, nghia la co tao ciphertext/transport data that.

### 5.2 Throughput benchmark

Theo simulation TB 100 MHz:

| Testcase | TX input throughput | RX output throughput |
|---|---:|---:|
| `dma_compress_aes_input1` | 7.493 MB/s | 17.116 MB/s |
| `dma_compress_aes_input3` | 5.575 MB/s | 4.652 MB/s |
| `dma_compress_aes_alnum63_cov` | 2.911 MB/s | 5.947 MB/s |

Neu noi ve FPGA demo 50 MHz, throughput ly thuyet xap xi mot nua so tren.

### 5.3 Coverage

Bao cao coverage dung so nay:

| Metric | Value |
|---|---:|
| Active testcase | 32 |
| Passed testcase | 32 |
| Raw DUT full `bcesft` | 86.44% |
| Raw DUT branch+statement | 94.93% |
| Closed DUT coverage | 95.59% |

Can noi ro:

- Khong noi raw full coverage la 100%.
- Closed coverage 95.59% la sau exclusion/closure co reason.
- Branch+statement 94.93% moi la so dep va de giai thich functional hon.

### 5.4 Vivado implementation

Ket qua implementation moi nhat o 50 MHz:

| Build | WNS | Power | LUT | BRAM | Status |
|---|---:|---:|---:|---:|---|
| TX-only | +3.752 ns | 0.202 W | 19781 | 10 | Timing pass |
| RX-only | +0.230 ns | 0.219 W | 12004 | 11 | Timing pass |

Can noi ro:

- Day la split TX/RX implementation, khong phai full TX+RX chung mot bitstream.
- Power report la vectorless, confidence `Medium`, chua co SAIF activity that.
- Neu can nap board thi can regenerate bitstream sau implementation.

## 6. Testcase Groups To Mention

Khong can liet ke ca 32 testcase tren slide. Chi can nhom:

| Group | Purpose | Example |
|---|---|---|
| CPU/MMIO | Kiem tra RV32I read/write register, invalid MMIO, instruction coverage | `mmio_regfile_basic`, `cpu_instruction_cov` |
| DMA/MMIO contract | Kiem tra mode, start, status, wait-state, error path | `mmio_mode_matrix`, `tx_apb_wait_cov` |
| TX | Kiem tra compress-only, compress+AES, error path, max symbols | `tx_compress_only_input1`, `tx_compress_only_input4_cov` |
| RX | Kiem tra decrypt/decode, malformed frame, backpressure | `dma_compress_aes_input1`, `rx_backpressure_cov` |
| SoC E2E | Kiem tra full TX -> RX loopback | `dma_compress_aes_input1`, `dma_compress_aes_input3` |

## 7. What To Study Before Reporting

Can nam chac cac phan nay:

1. RV32I basic instruction: `lw`, `sw`, `addi`, `xor`, branch, polling loop.
2. MMIO/APB: CPU ghi dia chi `0x40000000` de cau hinh DMA nhu the nao.
3. DMA: vi sao CPU khong copy data, DMA doc/ghi DMEM thay CPU.
4. Dynamic Huffman: dem tan suat toan file, tao codebook, nen tot khi du lieu
   co phan bo ky tu lech.
5. AES-128 CBC: IV la gi, TX encrypt va RX decrypt dung IV giong nhau.
6. DMEM layout: source `0x2000`, TX output `0x4000`, RX output `0x6000`.
7. Testbench: load input txt vao DMEM, dump 3 vung DMEM, compare loopback.
8. Coverage: phan biet raw coverage, branch+statement coverage va closed coverage.
9. Vivado: hieu WNS duong la timing pass, power vectorless chi la estimate.

## 8. Suggested Slide Order

1. Problem and goal.
2. Overall SoC architecture diagram.
3. Memory map and DMA/MMIO software contract.
4. TX datapath: Huffman + AES-CBC.
5. RX datapath: AES-CBC decrypt + Huffman decode.
6. RV32I software flow: configure, start, poll, read result.
7. Main end-to-end testcase results.
8. Coverage and testcase strategy.
9. FPGA implementation results.
10. Limitations and future work.

## 9. Limitations / Future Work

Nen noi thang cac diem nay:

- Full TX+RX chung mot FPGA build van nang, huong demo hien tai la split TX-only
  va RX-only.
- Board demo can output readback tot hon de doc ciphertext/plaintext/saving tu
  board that.
- IV hien tai la demo IV do RV32I tao; san pham that can nonce/TRNG/host-provided
  IV va policy luu IV kem ciphertext.
- Power estimate chua dung switching activity that.
- Huffman nen tot voi input co redundancy; input gan uniform co the bi am saving
  do codebook/header overhead.
