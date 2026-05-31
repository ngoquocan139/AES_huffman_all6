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
| 10 | `paper_comparison_huffman_aes_cbc.md` | So sanh cong bang voi bai bao Huffman + CBC-AES |

Khong can trinh bay tung spec module con tren slide. Cac file nhu
`dma_tx_engine_spec.md`, `dynamic_huffman_encoder_spec.md`,
`huffman_block_decoder_spec.md`, `apb_huffman_rx_if_spec.md` chi dung de tra
loi cau hoi chi tiet.

## 1.1 Current Snapshot For Slides

Dung bang nay de mo dau phan ket qua hien tai:

| Item | Current slide value |
|---|---|
| Main claim | RV32I secure-storage SoC with Huffman + AES-128-CBC accelerators |
| Firmware API | `secure_storage_fw.h`: `secure_write`, `secure_read`, `secure_delete` |
| Metadata | DMEM table at `0x00000100`, 2 records, `0x40` bytes/record |
| IV policy | Firmware-generated deterministic demo IV, counter at `0x000001F0`, seed `0x31415926` |
| Latest focused test | `dma_storage_table_input1_then_input3`, `PASS=22`, `FAIL=0` |
| Storage API result | Stores input1 and input3, then restores input1 by `file_id=1` |
| FPGA claim | Default board target is ZCU102; full TX+RX implementation and bitstream pass; UART `LOAD` auto-starts RV32I |
| TX FPGA | WNS `+1.277 ns`, LUT `11933`, slices `3979`, control sets `208` |
| Full ZCU102 FPGA SoC | WNS `+9.093 ns`, WHS `+0.015 ns`, LUT `36382`, CLB `7281`, control sets `1628`, power `0.796 W` |
| Legacy RX FPGA | WNS `+0.341 ns`, LUT `22730`, control sets `917` |
| Historical regression | `34/34` PASS, raw DUT `93.52%`, closed DUT `95.90%` |

## 2. Main Story To Tell

Ten de tai:

```text
Design of a RISC-V RV32I System Integrating Huffman Compression and AES-128
for Secure Data Storage
```

Nen bao cao theo cau chuyen nay:

1. He thong la mot SoC RV32I secure-storage prototype, CPU dong vai tro control
   plane va storage-management plane.
2. Du lieu nam trong DMEM, CPU khong tu copy tung byte ma cau hinh DMA qua MMIO.
   CPU dong thoi quan ly firmware API, metadata, IV, va object `file_id`.
3. TX DMA doc plaintext tu DMEM, dua qua Huffman dynamic whole-file va AES-128
   CBC, roi ghi ciphertext/transport stream ve DMEM.
4. RX DMA doc ciphertext tu DMEM, AES-CBC decrypt, Huffman decode, roi ghi
   plaintext phuc hoi ve DMEM.
5. Testbench kiem tra loopback bang cach so sanh RX output voi input goc, dong
   thoi dump source/TX/RX DMEM va tinh compression/throughput. Storage-table
   testcase kiem tra them `secure_write`/`secure_read` theo `file_id`.
6. Sau toi uu table/control-set, full TX+RX SoC da implement va write
   bitstream duoc tren ZCU102. Wrapper clock van giu SoC/UART chay 50 MHz.

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
- DMEM 32 KiB chua input, ciphertext, output, metadata table va IV counter.
- UART DMEM loader cho FPGA demo.
- IV registers `IV0..IV3` cho AES-CBC.

### 3.1.1 Secure-storage firmware layer

Nen them mot slide nho giua architecture va TX/RX:

```text
Application request
  -> secure_write(file_id, plain_addr, plain_len)
  -> firmware chooses ciphertext slot
  -> firmware creates IV and metadata
  -> DMA TX: Huffman + AES-CBC
  -> metadata commit valid=1

secure_read(file_id, dst_addr)
  -> firmware scans metadata
  -> firmware restores IV
  -> DMA RX: AES-CBC + Huffman decode
  -> plaintext restored in DMEM
```

Metadata fields can noi tren slide:

```text
valid, file_id, plain_addr, cipher_addr, plain_len, cipher_len,
mode, iv0..iv3, version, flags
```

Day la phan RISC-V dong gop them vao "secure data storage", khong chi la
kick accelerator.

### 3.2 Control plane

CPU dung instruction RV32I co ban:

- `lw/sw` de doc/ghi DMEM va MMIO.
- `addi/and/or/xor/sll/srl` de tinh config va demo IV.
- `secure_storage_fw.h` gom cac ham `secure_write`, `secure_read`,
  `secure_delete`, quan ly metadata va IV.
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

RX can cung IV voi TX. Trong firmware secure-storage hien tai, IV va
`cipher_len` duoc lay tu metadata record; `LEN_BYTES` cua RX bang
`metadata.cipher_len`.

### 4.1 Storage API flow to explain

Neu thầy hỏi "RISC-V tham gia secure storage o dau", tra loi theo flow nay:

| Step | RV32I firmware responsibility | RTL accelerator responsibility |
|---:|---|---|
| 1 | Receive `file_id`, source address, length | none |
| 2 | Allocate metadata slot and ciphertext address | none |
| 3 | Generate IV and write `IV0..IV3` | snapshot IV for CBC |
| 4 | Configure `SRC/DST/LEN/MODE` and start DMA | run Huffman + AES-CBC TX |
| 5 | Store `cipher_len`, `plain_len`, IV, mark `valid=1` | report produced bytes |
| 6 | On read, lookup metadata by `file_id` | none |
| 7 | Restore IV and configure RX with `cipher_len` | decrypt and decode |
| 8 | Check `bytes_done == plain_len` | produce plaintext bytes |

## 5. Main Results To Report

### 5.1 SoC end-to-end testcase group 4.5

Day la nhom testcase chinh nen dua vao bao cao:

| Testcase | Input | Result | Storage saving | Note |
|---|---|---:|---:|---|
| `dma_storage_table_input1_then_input3` | `input1.txt` + `input3.txt` | PASS | 59.86% for selected input1 | Current secure-storage API: 2 metadata records, readback by `file_id` |
| `dma_compress_aes_input1` | `input1.txt`, 2551 bytes | PASS | 59.86% | Legacy direct TX/RX loopback |
| `dma_compress_aes_input3` | `input3.txt`, 242 bytes | PASS | 53.72% | Small/repeated input |
| `dma_compress_aes_alnum63_cov` | 63-symbol stress, 504 bytes | PASS | -11.11% | Functional stress, not compression-optimized |

Can nhan manh:

- `src_mismatch=0`
- `rx_mismatch=0`
- Direct loopback summary: `SUMMARY: PASS=18 FAIL=0`
- Storage API focused summary: `SUMMARY: PASS=22 FAIL=0`
- TX output non-zero, nghia la co tao ciphertext/transport data that.

### 5.2 Throughput benchmark

Theo simulation TB 100 MHz:

| Testcase | TX input throughput | RX output throughput |
|---|---:|---:|
| `dma_compress_aes_input1` | 5.614 MB/s | 17.085 MB/s |
| `dma_compress_aes_input3` | 2.240 MB/s | 4.648 MB/s |
| `dma_compress_aes_alnum63_cov` | 1.134 MB/s | 5.936 MB/s |

Neu noi ve FPGA demo 50 MHz, throughput ly thuyet xap xi mot nua so tren.

### 5.3 Coverage

Bao cao coverage dung so nay nhu historical full-regression baseline:

| Metric | Value |
|---|---:|
| Active testcase | 34 |
| Passed testcase | 34 |
| Raw DUT full `bcesft` | 93.52% |
| Raw DUT branches / statements | 94.22% / 96.33% |
| Closed DUT coverage | 95.90% |

Can noi ro:

- Day la so full regression lich su truoc secure-storage API refactor; neu can
  so cuoi cung moi nhat thi chay lai `./run.csh cov`.
- Khong noi raw full coverage la 100%.
- Closed coverage 95.90% la sau exclusion/closure co reason.
- Neu thay hoi theo goc functional, dua so `Branches 94.22%` va `Statements 96.33%` thay vi co gang gom thanh 1 so duy nhat.

### 5.4 Vivado implementation

Ket qua implementation moi nhat tren ZCU102:

| Build | WNS | WHS | LUT | FF | CLB | Control sets | BRAM | DSP | Power | Status |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| Full `rv32_soc_synth_full_zcu102` | +9.093 ns | +0.015 ns | 36382 | 19382 | 7281 | 1628 | 11 | 0 | 0.796 W | Timing pass, bitstream pass, UART load auto-run |

Ket qua implementation lich su o 50 MHz sau area optimization, truoc khi doi
default board target sang ZCU102:

| Build | WNS | LUT | FF | Slices | Control sets | BRAM | Status |
|---|---:|---:|---:|---:|---:|---:|---|
| TX-only `rv32_soc_synth_tx_opt4` | +1.277 ns | 11933 | 5469 | 3979 | 208 | 10 | Timing pass |
| Full FPGA demo SoC `rv32_soc_synth_full_fpga` | +0.811 ns | 28379 | 18898 | 10165 | 778 | 11 | Timing pass |
| Legacy RX-only | +0.341 ns | 22730 | 27658 | n/a | 917 | 11 | Timing pass |

Can noi ro:

- Loi cu `[Place 30-487]` khong con xuat hien; full ZCU102 SoC da qua
  `place_design`, `route_design`, va `write_bitstream`.
- Giam area chinh den tu viec dua Huffman table/FIFO sang distributed RAM,
  bo reset loop tren memory lon va tach write-port cua `code_length_builder`.
- RX main decode table dung BRAM `2K x 15`; RX fallback/FIFO dung distributed
  RAM. RX local sort table con la diem co the toi uu tiep, nhung full build da
  route pass.
- Power report moi la vectorless estimate: total `0.796 W`, dynamic `0.146 W`,
  static `0.649 W`; Vivado canh bao reset fanout/activity nen day la estimate,
  khong phai do board.
- Bitstream hien co tai `sim/vivado_bitstreams/rv32_soc_synth_full_zcu102.bit`.

### 5.5 Component-level comparison

Khong can ep reference phai giong toan bo kien truc SoC. Nen tach thanh cac
bang nho theo tung phan:

| Comparison item | Compare against | Metric | This design | Conclusion |
|---|---|---|---|---|
| Huffman compression only | C Huffman baseline `drichardson/huffman` | Payload ratio | `input1.txt` `37.50%`; MIT-BIH avg `61.13%` | C Huffman nho hon, nhung SoC co hardware transport/RX decode |
| Secure-storage final size | ECG Huffman + CBC-AES paper | Final storage ratio | MIT-BIH avg `32.76%` vs paper `35.015%` | Tot hon `2.26` diem phan tram neu noi ro preprocessing nam ngoai SoC |
| AES/RISC-V software | `aadomn/aes` RISC-V AES | cycles/byte | SoC TX `17.83` cycles/byte on `input1.txt` vs AES software `78.9` cycles/byte | Chung minh gia tri offload, khong phai benchmark CPU-to-CPU tuyet doi |
| Software/firmware contract | Current C files vs RTL | Responsibility split | Software quan ly metadata/IV/file_id; RTL xu ly Huffman/AES/DMA | RV32I la control plane, accelerator la data plane |

Ket luan nen noi tren slide: phan so sanh duoc trinh bay theo tung lop. Ve
Huffman-only, software C reference co ratio nho hon. Ve secure-storage final
size tren nam MIT-BIH records, flow hien tai dat `32.76%`, tot hon bai bao
`35.015%` trong dieu kien ECG preprocessing da lam ben ngoai SoC. Ve software,
bang doi chieu phai noi ro firmware lam metadata/IV/file_id, con RTL lam DMA,
Huffman va AES-CBC.

Ket luan tong ve kien truc:

| Architecture type | Better at | This SoC position |
|---|---|---|
| Pure software compression | Compression ratio | SoC khong thang pure ratio; SoC thang o hardware offload va verified datapath |
| Huffman-only FPGA | Raw Huffman throughput | SoC cham hon nhung co DMA, RV32I control, RX restore va storage flow |
| AES-only RTL | AES latency/area | SoC khong phai AES core nhanh nhat; AES la mot phan cua secure-storage path |
| Minimal RISC-V SoC | Area/power | SoC lon hon vi co Huffman, AES, DMA, UART/FPGA demo |
| This design | End-to-end secure storage | RV32I lam control plane; accelerator lam data plane; metadata/IV/file_id duoc firmware quan ly |

Cau ket luan nen dung:

```text
Thiet ke nay khong nham toi viec la bo nen tot nhat, AES core nhanh nhat, hay
RISC-V SoC nho nhat. Dong gop chinh la tich hop RV32I firmware, DMA, metadata,
IV, Huffman, AES-128-CBC, RX restore va FPGA implementation thanh mot
secure-storage SoC hoat dong duoc.
```

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
| `result_signature` | Xac nhan dung chuong trinh da hoan tat; `0x44525831` la testcase TX->RX loopback, `0x53544f52` la storage-table API testcase. |
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
7. Secure metadata: `file_id`, `cipher_addr`, `cipher_len`, `plain_len`, IV,
   `valid` commit.
8. Testbench: load input txt vao DMEM, dump 3 vung DMEM, compare loopback.
9. Coverage: phan biet raw coverage, branch+statement coverage va closed coverage.
10. Vivado: hieu WNS duong la timing pass, power vectorless chi la estimate.
11. Software storage table: cach RV32I luu metadata de lay lai du lieu da luu.

## 8. Suggested Slide Order

1. Problem and goal.
2. Overall SoC architecture diagram.
3. RV32I secure-storage firmware API: write/read/delete, metadata, IV.
4. Memory map and DMA/MMIO software contract.
5. TX datapath: Huffman + AES-CBC.
6. RX datapath: AES-CBC decrypt + Huffman decode.
7. RV32I software flow: configure, start, poll, read result.
8. Main end-to-end testcase results.
9. Coverage and testcase strategy.
10. FPGA implementation results.
11. Limitations and future work.

## 9. Limitations / Future Work

Nen noi thang cac diem nay:

- Full TX+RX SoC da route va write bitstream pass tren ZCU102. Van nen giu
  split TX-only/RX-only khi can demo nhe va debug nhanh.
- Board demo da co DMEM READ qua UART; viec can lam tiep la host script cap cao
  de tu dong dump ciphertext/plaintext/saving va poll firmware-done.
- IV hien tai la demo IV do firmware RV32I tao va luu trong metadata; san pham
  that can nonce/TRNG/host-provided IV va authentication policy.
- Power estimate chua dung switching activity that.
- Huffman nen tot voi input co redundancy; input gan uniform co the bi am saving
  do codebook/header overhead.
