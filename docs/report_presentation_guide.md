# Report Presentation Guide

## 1. Specs Review Summary

Dung cac spec theo thu tu nay khi on bao cao:

| Priority | Document | Use in report |
|---:|---|---|
| 1 | `00_current_system_spec.md` | Source of truth cho kien truc SoC hien tai |
| 2 | `soc_4_5_end_to_end_report.md` | Ket qua testcase end-to-end chinh |
| 3 | `coverage_regression_report.md` | Coverage/testplan va cac testcase da chay |
| 4 | `soc_usage_and_fpga_guide.md` | Lenh chay, cach doi input/C file, FPGA next step |
| 5 | `29_defense_qa_code_focus_spec.md` | Ban on nhanh de tra loi luc bi hoi code |
| 6 | `tx_path_end_to_end_spec.md` | Giai thich rieng TX khi bi hoi sau |
| 7 | `rx_path_end_to_end_spec.md` | Giai thich rieng RX khi bi hoi sau |
| 8 | `memory_map_dma_software_contract.md` | Bang dia chi MMIO/DMEM |
| 9 | `iv_generation_and_cbc_contract_spec.md` | Giai thich IV va AES-CBC |

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
| `dma_compress_aes_input3` | 5.320 MB/s | 4.652 MB/s |
| `dma_compress_aes_alnum63_cov` | 2.780 MB/s | 5.947 MB/s |

Neu noi ve FPGA demo 50 MHz, throughput ly thuyet xap xi mot nua so tren.

### 5.3 Coverage

Bao cao coverage dung so nay:

| Metric | Value |
|---|---:|
| Active testcase | 34 |
| Passed testcase | 34 |
| Raw DUT full `bcesft` | 93.72% |
| Raw DUT branches / statements | 93.85% / 96.39% |
| Closed DUT coverage | 95.90% |

Can noi ro:

- Khong noi raw full coverage la 100%.
- Closed coverage 95.90% la sau exclusion/closure co reason.
- Neu thay hoi theo goc functional, dua so `Branches 93.85%` va `Statements 96.39%` thay vi co gang gom thanh 1 so duy nhat.

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

Khong can liet ke ca 34 testcase tren slide. Chi can nhom:

| Group | Purpose | Example |
|---|---|---|
| CPU/MMIO | Kiem tra RV32I read/write register, invalid MMIO, instruction coverage | `mmio_regfile_basic`, `cpu_instruction_cov` |
| DMA/MMIO contract | Kiem tra mode, start, status, wait-state, error path | `mmio_mode_matrix`, `tx_apb_wait_cov` |
| TX | Kiem tra compress-only, compress+AES, error path, max symbols | `tx_compress_only_input1`, `tx_compress_only_input4_cov` |
| RX | Kiem tra decrypt/decode, malformed frame, backpressure | `dma_compress_aes_input1`, `rx_backpressure_cov` |
| SoC E2E | Kiem tra full TX -> RX loopback | `dma_compress_aes_input1`, `dma_compress_aes_input3` |
| Storage table | Kiem tra RV32I quan ly nhieu ciphertext record va chon lai file cu de RX | `dma_storage_table_input1_then_input3` |

### 6.1 CPU Instruction Coverage Log

Neu thầy hỏi CPU RV32I đã cover instruction nào, dùng `cpu_instruction_cov`.
Log nay khong phai DMA test; no la CPU program rieng ghi signature `CPUC` vao
DMEM:

| Result word | Expected | Meaning |
|---:|---:|---|
| `word0` | `0x43505543` | signature `CPUC` |
| `word1` | `0x00000000` | error mask, bit0..5 tuong ung R-type/I-type/branch/memory/LUI/JALR |
| `word2` | `0xcd79bdff` | R-type ALU mix |
| `word3` | `0x0000e595` | memory load/store mix |
| `word4` | `0x0000003f` | 6 branch types all hit |
| `word5` | `0x00000874` | I-type ALU mix |

Ket qua moi nhat: `SUMMARY: PASS=8 FAIL=0`.

### 6.2 How To Explain The PASS Lines

Co the dua bang nay vao phu luc hoac 1 slide backup de giai thich log
end-to-end:

| Check name | Y nghia bao cao |
|---|---|
| `mem_err_o_should_be_zero` | Toan he thong khong phat sinh loi truy cap memory/bus trong suot testcase. |
| `cpu_should_publish_known_signature` | CPU da chay den cuoi chuong trinh test va ghi ket qua ra vung result trong DMEM. |
| `result_signature` | Xac nhan dung chuong trinh `test_mmio_dma.c` da hoan tat; `0x44525831` la ma nhan dang cua testcase TX->RX loopback. |
| `cpu_error_mask_should_be_zero` | Tu goc nhin phan mem RV32I, khong co loi nao trong flow cau hinh DMA, polling status, kiem tra TX/RX. |
| `tx_status_before_start` | Truoc khi start, TX dang o trang thai idle hop le va cau hinh mode da dung. |
| `tx_status_after_done` | Sau khi hoan tat, TX set `done_sticky` dung va khong bao loi. |
| `tx_bytes_done_should_be_transport_aligned` | Dau ra TX duoc can chinh dung theo transport/AES block, tuc chieu dai output hop le ve mat giao thuc. |
| `tx_ciphertext_bytes_produced_should_match_tx_bytes_done` | Hai nguon bao cao do dai ciphertext cua TX khop nhau, chung to DMA TX va DMA regfile dong bo. |
| `tx_poll_count_should_be_nonzero` | CPU thuc su polling trang thai TX, dung voi co che dieu khien polling da thiet ke. |
| `rx_status_before_start_should_be_idle_or_done_sticky` | RX bat dau tu trang thai hop le, khong bi loi hoac trang thai rac truoc khi nhan du lieu. |
| `rx_status_after_done` | Sau khi hoan tat, RX set `done_sticky` dung va khong bao loi. |
| `rx_bytes_done_should_match_input_len` | So byte plaintext sau RX dung bang so byte input ban dau. |
| `rx_debug_after_done` | Khong co loi noi bo nao o path RX nhu depacker, parser, decoder hoac AES path. |
| `rx_poll_count_should_be_nonzero` | CPU thuc su polling trang thai RX, dung voi software contract. |
| `source_dmem_should_match_input_file` | Vung source DMEM sau khi loader nap khop tuyet doi voi file input. |
| `loopback_rx_should_match_input_file` | Du lieu plaintext sau RX khop tuyet doi voi input goc, xac nhan loopback end-to-end chinh xac. |
| `tx_ciphertext_region_should_not_be_all_zero` | TX thuc su sinh ciphertext/transport data va DMA thuc su ghi du lieu ra vung dich. |
| `dma_start_pulse_count` | Co dung 2 lan start DMA: mot lan cho TX va mot lan cho RX, dung flow kien truc. |
| `SUMMARY: PASS=18 FAIL=0` | Tat ca dieu kien kiem tra o muc software, DMA, TX, RX va data integrity deu dat. |

Mot cau noi gon co the dung khi trinh bay:

```text
Bo self-check nay chung minh SoC khong chi chay het mo phong, ma con thoa
toan bo hop dong kien truc: CPU cau hinh dung DMA, TX tao ciphertext hop le,
RX khoi phuc dung du lieu, va plaintext cuoi cung khop tuyet doi voi input ban
dau.
```

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
10. Software storage table: cach RV32I luu metadata `file_id/cipher_addr/cipher_len/IV` de lay lai du lieu da luu.

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
