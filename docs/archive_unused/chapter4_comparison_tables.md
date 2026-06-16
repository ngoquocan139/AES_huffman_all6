# Chapter 4 Comparison Tables

This file contains thesis-ready comparison tables following the style of the
referenced report by Thien: individual-algorithm throughput, related-work
comparison, and Vivado implementation reports.

Note for the thesis title: the current project is not an ASCON design. If a
template title says "Performance Comparison of ASCON with Related Work", replace
"ASCON" with "the Proposed Huffman-AES Secure-Storage SoC" or "the Proposed
Design".

## Table 4.2: Throughput Results of Individual Algorithms

| Algorithm / datapath | Test condition | Input / output size | Cycle count | Throughput at 100 MHz simulation assumption | Throughput at 50 MHz FPGA clock | Notes |
|---|---|---:|---:|---:|---:|---|
| AES-128 encryption | Direct AES known-answer testcase, no CPU/DMA/Huffman | 16 B/block | 11 cycles/block | 145.455 MB/s | 72.727 MB/s | FIPS-197 vector PASS |
| AES-128 decryption | Direct AES inverse known-answer testcase, no CPU/DMA/Huffman | 16 B/block | 11 cycles/block | 145.455 MB/s | 72.727 MB/s | FIPS-197 vector PASS |
| TX: Huffman + AES-CBC + DMA | `dma_compress_aes_input1`, `input1.txt` | 2551 B input, 880 B stored output | 32633 TX cycles | 7.817 MB/s | 3.909 MB/s | Main secure-storage TX path |
| RX: AES-CBC + Huffman decode + DMA | `dma_compress_aes_input1`, restore `input1.txt` | 2551 B restored plaintext | 15132 RX cycles | 16.858 MB/s | 8.429 MB/s | End-to-end loopback PASS |
| TX: Huffman + AES-CBC + DMA | `dma_compress_aes_input3`, small input | 242 B input, 112 B stored output | 10817 TX cycles | 2.237 MB/s | 1.119 MB/s | Fixed setup/header overhead dominates |
| RX: AES-CBC + Huffman decode + DMA | `dma_compress_aes_input3`, restore small input | 242 B restored plaintext | 5226 RX cycles | 4.631 MB/s | 2.316 MB/s | End-to-end loopback PASS |
| TX: Huffman + AES-CBC + DMA | MIT-BIH five-record average | 3603.8 B input, 2150.4 B stored output | 53233 TX cycles avg | 6.771 MB/s | 3.386 MB/s | ECG preprocessing is external to the SoC |
| RX: AES-CBC + Huffman decode + DMA | MIT-BIH five-record average | 3603.8 B restored plaintext | 24182.8 RX cycles avg | 14.918 MB/s | 7.459 MB/s | RX restores the preprocessed byte stream |

Table 4.2 shows that the AES core itself is not the bottleneck. The full TX
path is slower because it also performs whole-file frequency counting, Huffman
codebook generation, payload emission, transport packing, AES-CBC encryption,
and DMA writeback. The RX path is faster in cycles per byte, but it consumes
more FPGA resources because the Huffman decoder and parser are larger.

## Table 4.3: Performance Comparison of the Proposed Design with Related Work

If the thesis template requires the exact old wording, use:

```text
Table 4.3: Performance Comparison of the Proposed Huffman-AES SoC with Related Work
```

| Design / reference | Platform / scope | Main metric | Reported result | Proposed design result | Fair comparison statement |
|---|---|---|---:|---:|---|
| Proposed design, AES-only core | RTL AES-128 encrypt/decrypt | AES latency | This work | 11 cycles/block, 0.688 cycles/byte | Clean AES-only module result; independent of DMA/Huffman |
| `aadomn/aes` RISC-V AES software | RISC-V E31 software AES | AES-128 cycles/byte | 78.9 cycles/byte | 0.688 cycles/byte AES-only RTL; 12.79 cycles/input byte for `input1.txt` TX | RTL offload greatly reduces byte-processing work compared with RV32I-only AES software |
| `secworks/aes` | Standalone reusable AES RTL | AES latency and area | 46 cycles/block, 3020 LUT, 2992 FF | 11 cycles/block; TX AES 1614 LUT/261 FF; RX AES 1667 LUT/261 FF | Proposed AES is lower latency for this embedded AES-128 scope; `secworks/aes` is more reusable and supports broader AES configurations |
| ECG Huffman + CBC-AES paper | MIT-BIH ECG software-style chain | Final storage ratio | 35.015% ratio, 64.985% saving | 29.87% ratio, 70.13% saving on same five records after external preprocessing | Proposed flow has better final stored-size result under the stated external-preprocessing condition |
| `drichardson/huffman` | Huffman-only C software baseline | Huffman payload ratio | MIT-BIH average 58.53% | MIT-BIH average 55.72% | Proposed compact table-reuse Huffman payload is smaller on the tested ECG byte streams |
| AMD/Xilinx Vitis GZip library | Hardware GZip compression/decompression | Raw throughput | GZip compression about 1.5 GB/s, decompression about 518 MB/s | `input1.txt` TX 3.909 MB/s and RX 8.429 MB/s at 50 MHz | Vitis GZip wins raw compression throughput; proposed design is a complete RV32I secure-storage SoC with AES-CBC and RX restore |
| Canonical Huffman FPGA paper | Standalone Huffman encoder/decoder | Raw Huffman throughput | Encoder 144 GB/s; decoder up to 991 GB/s | Full secure-storage TX/RX in MB/s range | Standalone Huffman wins raw throughput; proposed design includes RV32I, DMA, metadata, AES-CBC, and full loopback verification |

Table 4.3 should be presented as a component-level comparison. The proposed
design is not claimed to be the fastest desktop compressor or the smallest
standalone AES IP. Its main contribution is the complete FPGA SoC integration:
RV32I firmware control, MMIO/APB, DMA, dynamic Huffman compression,
AES-128-CBC, metadata/IV handling, RX restore, simulation checks, and Vivado
implementation.

## Table 4.4: Vivado Implementation Reports

| Design / build | FPGA target | Clock | LUT | FF | BRAM36 | DSP | WNS | WHS | Power | Implementation status |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| Full proposed SoC, `rv32_soc_synth_full_zcu102` | ZCU102, `xczu9eg-ffvb1156-2-e` | 50 MHz | 37069 | 19794 | 11 | 0 | +7.871 ns | +0.015 ns | 0.793 W | Timing pass, bitstream pass |
| TX-only historical build, `rv32_soc_synth_tx_opt4` | ZedBoard-style implementation target | 50 MHz | 11933 | 5469 | 10 | 0 | +1.277 ns | N/A | 0.178 W | Timing pass |
| RX-only historical build, `rv32_soc_synth_rx` | ZedBoard-style implementation target | 50 MHz | 22730 | 27658 | 11 | 0 | +0.341 ns | N/A | 0.193 W | Timing pass |

Table 4.4 reports post-implementation Vivado results. The full ZCU102 SoC
passes timing with positive WNS at the 50 MHz generated SoC clock. The power
number is a Vivado vectorless estimate, not a board-measured power value.

## Short Thesis Paragraph For These Tables

The throughput results in Table 4.2 show that the AES-128 core has much higher
raw throughput than the complete TX/RX secure-storage paths. This is expected
because the complete paths include Huffman processing, metadata/transport
formatting, CBC chaining, DMA transfer, and output drain. Table 4.3 compares
the proposed design with related software and hardware work at component level.
Software and standalone compression engines may achieve higher raw throughput,
but they do not provide the same integrated RV32I-controlled secure-storage
SoC. Finally, Table 4.4 confirms that the full design is implementable on the
ZCU102 target with positive timing slack and no DSP usage.
