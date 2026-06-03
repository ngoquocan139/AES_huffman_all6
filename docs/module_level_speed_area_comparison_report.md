# Module-Level Speed, Cycle, Area, And Baseline Comparison

Date: 2026-06-02

## 1. Scope

This report compares the current SoC by module or module group, instead of
only comparing the full system.

The comparison is split into:

- cycle and throughput from Questa simulation counters,
- LUT/FF/BRAM/power from Vivado post-implementation reports,
- paper/software/hardware reference comparison.

Important limitation:

- The current testbench exposes TX and RX cycle counters, not isolated
  submodule counters for every Huffman internal stage.
- AES-only encrypt/decrypt is now measured by a direct testcase
  `aes_core_benchmark`, independent of CPU, DMA, TX, RX, and Huffman.
- Therefore, cycle numbers are reliable for AES-only, `DMA TX + TX top`, and
  `DMA RX + RX top`, while LUT/FF/BRAM numbers are reliable per module from
  Vivado hierarchy reports.
- Paper timing is software-style wall-clock seconds and includes ECG
  processing steps that are not all implemented inside the SoC.

## 2. Data Sources

| Source | Used for |
|---|---|
| `docs/architecture_software_comparison_report.md` | TX/RX cycles, software Huffman/AES comparison |
| `docs/paper_comparison_huffman_aes_cbc.md` | MIT-BIH storage ratio and paper compression result |
| `sim/log/aes_core_benchmark.log` | AES-only encrypt/decrypt cycles and throughput |
| `sim/loopback/aes_core_benchmark_aes_core_summary.txt` | Archived AES-only benchmark summary |
| Local PDF `refs/nén_aes/huffman_AES_CBC (1).pdf` | Paper Table 5/6/7 timing values |
| `sim/vivado_reports/rv32_soc_synth_full_zcu102_autorun_ecg/post_impl_utilization_hier.rpt` | Latest full ZCU102 hierarchy LUT/FF/BRAM |
| `sim/vivado_reports/rv32_soc_synth_full_zcu102_autorun_ecg/post_impl_timing_summary.rpt` | Latest full ZCU102 timing |
| `sim/vivado_reports/rv32_soc_synth_full_zcu102_autorun_ecg/post_impl_power.rpt` | Latest full ZCU102 power |
| `sim/vivado_reports/rv32_soc_synth_tx_opt4/*` | TX-only ZedBoard-style implementation |
| `sim/vivado_reports/rv32_soc_synth_rx/*` | Legacy RX-only ZedBoard-style implementation |

The AES-only numbers were generated with:

```bash
cd sim
make all TESTNAME=aes_core_benchmark
```

The testcase uses the FIPS-197 AES-128 known-answer vector:

```text
key        = 000102030405060708090a0b0c0d0e0f
plaintext  = 00112233445566778899aabbccddeeff
ciphertext = 69c4e0d86a7b0430d8cdb78070b4c55a
```

## 3. Full FPGA Build Summary

Latest full build used here:

```text
Project : rv32_soc_synth_full_zcu102_autorun_ecg
Top     : rv32_soc_fpga_zcu102_top
Device  : xczu9eg-ffvb1156-2-e
Clock   : 50 MHz generated SoC clock
```

| Metric | Value |
|---|---:|
| Total LUT | `37069` |
| Logic LUT | `36049` |
| LUTRAM | `1020` |
| FF | `19794` |
| BRAM36 | `11` |
| DSP | `0` |
| WNS | `+7.871 ns` |
| WHS | `+0.015 ns` |
| Total on-chip power | `0.793 W` |
| Dynamic power | `0.149 W` |
| Static power | `0.649 W` |

Conclusion:

- Timing is comfortably closed at 50 MHz.
- Power is vectorless Vivado estimate, confidence low/medium for internal
  activity, so it should be reported as an estimate, not measured board power.

## 4. Module Area From Full ZCU102 Build

Numbers are post-implementation hierarchical utilization. Percentages are
relative to full top LUT count `37069`. Due to cross-hierarchy LUT combining,
child rows do not always sum exactly to parent rows.

| Module / group | LUT | LUT share | FF | BRAM36 | Main meaning |
|---|---:|---:|---:|---:|---|
| Full FPGA top | `37069` | `100.0%` | `19794` | `11` | Complete board-level design |
| `u_soc` / `rv32_soc_top` | `35319` | `96.8%` | `18825` | `11` | Main SoC |
| `u_cpu` / `top_rv32_sync` | `1825` | `5.0%` | `647` | `0` | RV32I control plane |
| `u_cpu_mmio_to_apb_bridge` | `19` | `0.1%` | `103` | `0` | CPU MMIO to APB bridge |
| `u_dma_regfile` | `47` | `0.1%` | `239` | `0` | CPU-visible DMA registers |
| `u_dma_tx_engine` | `566` | `1.6%` | `321` | `0` | TX DMA data mover |
| `u_dma_rx_engine` | `266` | `0.7%` | `303` | `0` | RX DMA data mover |
| `u_dmem` / `DMEM_ip` | `48` | `0.1%` | `0` | `8` | Data memory |
| `u_imem` | `0` | `0.0%` | `0` | `2` | Instruction memory |
| `u_reg_file` | `576` | `1.6%` | `992` | `0` | RV32I register file |
| `u_tx_top` | `11201` | `30.8%` | `2821` | `0` | TX Huffman + AES-CBC/bypass |
| `u_rx_top` | `21042` | `57.8%` | `13110` | `1` | RX AES-CBC + Huffman decode |
| `u_uart_dmem_loader` | `692` | `1.9%` | `510` | `0` | FPGA UART input loader |

Conclusion:

- CPU, DMA, APB, and register control plane are small.
- The dominant resource cost is the accelerator datapath, especially RX.
- RX is larger than TX mainly because the Huffman decoder stores/rebuilds a
  general decode table and fallback logic.

## 5. TX Module Breakdown

From full ZCU102 hierarchy:

| TX submodule | LUT | FF | LUTRAM | BRAM36 | Comment |
|---|---:|---:|---:|---:|---|
| `u_tx_top` | `11201` | `2821` | `778` | `0` | Whole TX wrapper |
| `u_AES_top_tx` | `1614` | `261` | `0` | `0` | AES-128 encrypt |
| `u_apb_huffman_tx_if` | `294` | `51` | `42` | `0` | TX APB/control/FIFO |
| `u_huffman_aes_tx_top` | `9290` | `2117` | `736` | `0` | Adapter + Huffman + packer |
| `u_bit_packer_128` | `2361` | `353` | `0` | `0` | 120-bit payload to 128-bit transport |
| `u_dynamic_huffman_encoder` | `2615` | `482` | `0` | `0` | Block encoder using global/per-block codebook |
| `u_file_frequency_counter` | `608` | `257` | `128` | `0` | Whole-file frequency table |
| `u_file_huffman_builder` | `3429` | `831` | `384` | `0` | Whole-file Huffman builder |
| `u_code_length_builder` | `2763` | `746` | `384` | `0` | Largest TX builder sub-block |

TX-only ZedBoard-style implementation:

| Build | LUT | FF | BRAM36 | WNS | Power |
|---|---:|---:|---:|---:|---:|
| `rv32_soc_synth_tx_opt4` | `11933` | `5469` | `10` | `+1.277 ns` | `0.178 W` |

Conclusion:

- TX is not dominated by AES. AES TX is about `1614` LUT.
- The larger TX costs are Huffman builder, bit packer, and whole-file codebook
  support.
- TX-only implementation already passes timing.

## 6. RX Module Breakdown

From full ZCU102 hierarchy:

| RX submodule | LUT | FF | LUTRAM | BRAM36 | Comment |
|---|---:|---:|---:|---:|---|
| `u_rx_top` | `21042` | `13110` | `242` | `1` | Whole RX wrapper |
| `u_AES_top_rx` | `1667` | `261` | `0` | `0` | AES-128 inverse core |
| `u_apb_huffman_rx_if` | `137` | `29` | `26` | `0` | RX APB output FIFO/status |
| `u_bit_depacker_128` | `875` | `207` | `0` | `0` | 128-bit transport depacker |
| `u_huffman_block_parser` | `1526` | `204` | `0` | `0` | Parse mode/table/payload |
| `u_huffman_block_decoder` | `16805` | `11695` | `216` | `1` | Main RX cost |
| `u_main_decode_table` | `2653` | `0` | `0` | `1` | BRAM-backed short-code decode table |
| `u_rx_byte_packer_32` | `63` | `67` | `0` | `0` | Pack plaintext bytes to 32-bit words |

Legacy RX-only ZedBoard-style implementation:

| Build | LUT | FF | BRAM36 | WNS | Power |
|---|---:|---:|---:|---:|---:|
| `rv32_soc_synth_rx` | `22730` | `27658` | `11` | `+0.341 ns` | `0.193 W` |

Conclusion:

- RX Huffman decoder is the largest single module in the current SoC.
- AES inverse itself is not the area bottleneck.
- If area must be reduced further, focus first on
  `huffman_block_decoder`, especially canonical table build/sort/fallback
  structures.

## 7. Cycle And Throughput By Module Group

The current testbench measures accelerator/DMA busy cycles:

- `tx_cycles`: `dma_tx_engine + apb_huffman_aes_tx_top + DMEM/APB drain`
- `rx_cycles`: `dma_rx_engine + apb_huffman_aes_rx_top + DMEM/APB drain`

It also has one direct AES-only benchmark that bypasses CPU, DMA, Huffman, and
APB. Huffman-build-only and packer-only counters are still not split out.

### 7.1 Main text inputs

| Case | Plain bytes | TX bytes | TX cycles | RX cycles | TX cycles/input byte | RX cycles/plain byte | Total cycles/plain byte |
|---|---:|---:|---:|---:|---:|---:|---:|
| `input1.txt` TX/RX | `2551` | `880` | `32633` | `15132` | `12.79` | `5.93` | `18.72` |
| `input3.txt` TX/RX | `242` | `112` | `10817` | `5226` | `44.70` | `21.60` | `66.29` |
| MIT-BIH five-record average | `3603.8` | `2150.4` | `53233` | `24182.8` | `14.77` | `6.71` | `21.48` |

At 50 MHz:

| Case | TX time | RX time |
|---|---:|---:|
| `input1.txt` | `0.910 ms` | `0.303 ms` |
| `input3.txt` | `0.216 ms` | `0.105 ms` |
| MIT-BIH average | `1.065 ms` | `0.484 ms` |

At 100 MHz simulation-equivalent timing, these times are half.

Conclusion:

- TX is slower than RX because TX performs whole-file frequency count, codebook
  build, encode, pack, AES-CBC, and output drain.
- RX is area-heavy but cycle-efficient on normal inputs because it consumes a
  built transport stream and decodes sequentially.
- Very small input such as `input3.txt` has worse cycles/byte because fixed
  setup, metadata, header, and drain overhead dominate.

### 7.2 AES-only direct benchmark

Testcase:

```bash
cd sim
make all TESTNAME=aes_core_benchmark
```

Cycle definition:

```text
start pulse accepted -> ready high observed
```

Result:

| AES path | Cycles/block | Cycles/byte | Throughput @100 MHz | Throughput @50 MHz | Correctness |
|---|---:|---:|---:|---:|---|
| Encrypt `aes128_cipher_top` | `11` | `0.688` | `145.455 MB/s` | `72.727 MB/s` | FIPS vector PASS |
| Decrypt `aes128_cipher_inv_top` | `11` | `0.688` | `145.455 MB/s` | `72.727 MB/s` | FIPS vector PASS |

The measured AES-only log shows `PASS=6 FAIL=0`. The known-answer check uses:

```text
key        = 000102030405060708090a0b0c0d0e0f
plaintext  = 00112233445566778899aabbccddeeff
ciphertext = 69c4e0d86a7b0430d8cdb78070b4c55a
```

Conclusion:

- AES itself is not the bottleneck in the full TX/RX flow.
- Full TX cycles/byte are much higher than AES-only because TX also performs
  whole-file frequency count, Huffman codebook generation, payload emission,
  transport packing, AES-CBC chaining, APB/FIFO control, and DMA writes.
- Full RX area is large mostly because of Huffman parsing/decode structures,
  not because of AES inverse.

## 8. Paper Timing Comparison

The referenced ECG Huffman + CBC-AES paper reports timing in seconds in
Table 5/6/7. Averaging the five records across the three noise settings gives:

| Paper operation | Average time |
|---|---:|
| Encryption | `2.7106 s` |
| Compression | `3.8641 s` |
| Decryption | `3.0449 s` |
| Decompression | `0.5818 s` |
| Compression + encryption | `6.5747 s` |
| Decompression + decryption | `3.6267 s` |

Using MIT-BIH average SoC cycles:

| Direction | Paper time | SoC time @50 MHz | SoC time @100 MHz | Speedup @50 MHz | Speedup @100 MHz |
|---|---:|---:|---:|---:|---:|
| TX: compression + encryption | `6.5747 s` | `1.679 ms` | `0.839 ms` | `~3916x` | `~7833x` |
| RX: decompression + decryption | `3.6267 s` | `0.484 ms` | `0.242 ms` | `~7488x` | `~14975x` |

Fairness note:

- This is a hardware datapath vs paper software-style wall-clock comparison.
- The paper includes ECG preprocessing context and AES-256-CBC.
- The SoC currently receives already-preprocessed byte streams and uses
  AES-128-CBC.

Conclusion:

- For datapath speed, the hardware SoC is much faster than the paper-reported
  software timing.
- In the thesis, this should be worded as "hardware datapath acceleration",
  not as an identical algorithm/platform benchmark.

## 9. Software Compression Comparison

Huffman-only comparison against `drichardson/huffman` C baseline:

| Input | C Huffman ratio | SoC Huffman payload ratio | Better ratio |
|---|---:|---:|---|
| `input1.txt` | `32.65%` | `32.11%` | SoC |
| `input3.txt` | `42.56%` | `42.05%` | SoC by `0.51` point |
| MIT-BIH average | `58.53%` | `55.72%` | SoC by `2.81` points |

General compressor comparison from the same report:

| Input class | Best software family | Result |
|---|---|---|
| Text/log-like | `zlib`/`lzma` | Software ratio is much smaller than SoC Huffman |
| MIT-BIH preprocessed bytes | `lzma`/`bz2` often smaller | Software still wins pure compression ratio |

Conclusion:

- For pure Huffman ratio, the current compact-reuse SoC format beats the
  selected `drichardson/huffman` baseline on the report inputs.
- The SoC contribution is not "best compressor"; it is hardware offload,
  deterministic FPGA datapath, AES-CBC protection, and RX restore.
- After the Huffman build scan-limit optimization, the SoC TX datapath is
  faster while the ratio table remains unchanged: `input1.txt` improves from
  `45481` to `32633` TX cycles (`5.609` to `7.817 MB/s` at the 100 MHz log
  assumption), `input2.txt` improves from `70833` to `43033` cycles, and the
  ECG 112 demo improves from `68905` to `46561` cycles.

## 10. AES Software Comparison

Reference `aadomn/aes` reports RISC-V E31 AES software cycles/byte:

| AES software implementation | Cycles/byte |
|---|---:|
| AES-128 barrel-shiftrows, 8 parallel blocks | `78.9` |
| AES-128 fully-fixsliced, 2 parallel blocks | `89.3` |
| AES-128 semi-fixsliced, 2 parallel blocks | `93.4` |
| AES-256 barrel-shiftrows, 8 parallel blocks | `105.7` |

SoC comparison:

| SoC case | Operation measured | SoC cycles/byte | Reference | Ratio |
|---|---|---:|---:|---:|
| AES-only direct testcase | AES-128 encrypt/decrypt RTL only | `0.688` | `78.9` AES-only RV32I software | `~115x` fewer cycles/byte |
| `input1.txt` TX | Huffman + AES-CBC + DMA | `13.21` | `78.9` AES-only software | `6.0x` fewer cycles/byte |
| MIT-BIH average TX | Huffman + AES-CBC + DMA | `23.29` | `78.9` AES-only software | `3.4x` fewer cycles/byte |

Fairness note:

- SoC number is accelerator/DMA busy cycles, not retired RV32I instruction
  cycles.
- Reference number is AES-only software on a RISC-V core.
- AES-only direct testcase is a hardware-core cycle count, so it is the cleanest
  proof that the RTL AES datapath is much faster than RV32I-only AES software.

Conclusion:

- This supports the architectural decision to offload AES/Huffman to RTL.
- It should not be claimed as an exact CPU-to-CPU benchmark.

AES RTL area/latency comparison:

| AES design/module | Scope | LUT | FF | Cycles/block | Reference meaning |
|---|---|---:|---:|---:|---|
| Current `u_AES_top_tx` | AES-128 encrypt only | `1614` | `261` | `11` | Post-implementation full SoC hierarchy plus direct testcase |
| Current `u_AES_top_rx` | AES-128 inverse/decrypt only | `1667` | `261` | `11` | Post-implementation full SoC hierarchy plus direct testcase |
| Current TX+RX AES modules | Separate encrypt and decrypt modules | `3281` | `522` | `11` each direction | Total of the two AES modules used by this SoC |
| `secworks/aes` master | Reusable AES-128/256 encrypt/decrypt core | `3020` | `2992` | `46` | Published GitHub README FPGA summary; different device/interface |

## 11. Hardware Reference Comparison

| Reference type | Reference strength | Current SoC compared to it | Fair conclusion |
|---|---|---|---|
| Standalone Huffman FPGA encoder/decoder | Better raw Huffman throughput for a narrow datapath | Current SoC is slower per raw Huffman operation but includes RV32I, DMA, metadata, AES-CBC, RX restore | Standalone Huffman wins raw throughput; SoC wins integration |
| AES-only RTL core such as `secworks/aes` | Mature reusable AES IP with AES-128/256 support | Current AES direct testcase is faster at `11 cycles/block`, but embedded and AES-128-specific | Current SoC wins narrow latency; standalone AES IP wins reuse/configurability |
| Minimal RISC-V sensor SoC such as RisCO2 | Smaller system area for sensing/control task | Current full SoC is much larger due to Huffman/AES/DMA/RX | Minimal RISC-V wins area; current SoC wins secure storage functionality |

Useful numeric comparison:

| Design | LUT | FF | DSP | Meaning |
|---|---:|---:|---:|---|
| Current RV32I CPU only | `1787` | `648` | `0` | Control processor inside this SoC |
| Current full SoC | `37069` | `19794` | `0` | CPU + DMA + TX/RX + UART + memories |
| RisCO2 reference | `4889` | `2354` | `2` | Different low-power CO2 sensing SoC |

Conclusion:

- The RV32I control core itself is small.
- The full project area is dominated by secure-storage accelerators, not the
  CPU.

## 12. Module-Level Conclusions

| Module / group | Speed conclusion | Area conclusion | Best comparison statement |
|---|---|---|---|
| RV32I CPU | Not used for byte-by-byte compression/encryption; controls DMA/MMIO | Small: `1787` LUT | CPU is control plane, not data plane |
| CPU MMIO bridge + DMA regfile | Per transaction overhead only; not dominant in full TX/RX time | Very small: bridge `7` LUT, regfile `46` LUT | Control interface overhead is negligible |
| DMA TX/RX engines | Included in TX/RX cycle counters; not main area cost | TX DMA `567` LUT, RX DMA `266` LUT | DMA is small but enables CPU offload |
| TX Huffman + AES | MIT-BIH TX avg `83940` cycles, `1.679 ms` @50 MHz | TX top `11201` LUT | Much faster than paper software timing; larger than pure AES |
| TX AES core | AES-only direct testcase: `11` cycles/block, `0.688` cycles/byte | `1614` LUT | AES is not the TX bottleneck |
| RX AES inverse core | AES-only direct testcase: `11` cycles/block, `0.688` cycles/byte | `1667` LUT | AES inverse is not the RX area bottleneck |
| TX Huffman builder/packer | Dominates TX logic after AES | builder `3429` LUT, packer `2361` LUT | Main TX optimization target |
| RX AES + Huffman | MIT-BIH RX avg `24219` cycles, `0.484 ms` @50 MHz | RX top `21042` LUT | Fast but largest area group |
| RX Huffman decoder | Included in RX cycles | `16805` LUT, `11695` FF | Largest single area target |
| BRAM memories | Cycle cost hidden in CPU/DMA access | DMEM `8` BRAM36, IMEM `2`, RX decode table `1` | BRAM use is low on ZCU102 |
| UART loader | Outside compression datapath | `692` LUT | FPGA bring-up feature, not compression core |

## 13. Recommended Report Wording

Use this wording:

```text
At module level, the RV32I CPU, MMIO bridge, DMA register file, and DMA engines
are small; the area is dominated by TX/RX accelerators. The largest single
module is the RX Huffman decoder at about 16805 LUTs, while the TX path is
dominated by the whole-file Huffman builder and 128-bit bit packer. In speed,
the measured datapath counters show MIT-BIH average TX takes about 83940 cycles
and RX about 24219 cycles. At the 50 MHz FPGA demo clock this is about 1.679 ms
for TX and 0.484 ms for RX. Compared with the referenced paper's software-style
timing, this is thousands of times faster, but the comparison is cross-platform
and the ECG preprocessing step is outside the current RTL.
```

Short conclusion:

```text
General-purpose software compressors can still win pure compression ratio.
The selected pure-Huffman C baseline is now beaten by the compact-reuse SoC
format on the report inputs. Standalone Huffman/AES
cores may win narrow raw throughput or area. The current design wins as an
integrated RV32I-controlled secure-storage SoC with verified DMA, Huffman,
AES-CBC, RX restore, metadata, FPGA implementation, and timing closure.
```
