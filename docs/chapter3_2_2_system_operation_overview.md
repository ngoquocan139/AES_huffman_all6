# 3.2.2. System Operation Overview

The system operation begins with plaintext data stored in DMEM. The firmware
running on the RV32I processor configures the source address, destination
address, data length, operation mode, block size, and initialization vector
through the memory-mapped DMA control registers. After these parameters have
been written, the processor issues a start command to initiate the TX
operation.

During TX processing, the TX DMA engine reads the plaintext from the source
memory region and transfers it to the TX accelerator. The accelerator first
builds a dynamic canonical Huffman codebook from the complete input and then
compresses the plaintext using this file-level codebook. The compressed
bitstream is packed into 128-bit transport words before being encrypted by the
AES-128-CBC encryption block. The generated ciphertext is subsequently written
by the TX DMA engine to the selected ciphertext region in DMEM.

After the TX operation has completed, the firmware reads the produced
ciphertext length and stores this value together with the plaintext length,
ciphertext address, operation mode, and initialization vector in the metadata
record. The same ciphertext length and initialization vector are then used to
configure the RX operation. The RX DMA engine reads the ciphertext from DMEM
and transfers it to the RX accelerator in 128-bit blocks.

Inside the RX accelerator, the ciphertext is decrypted by the AES-128-CBC
decryption block. The decrypted transport words are then depacked into a
bitstream, parsed to recover the Huffman block information, and decoded by the
canonical Huffman decoder. The recovered plaintext bytes are packed into
32-bit words and written by the RX DMA engine to a separate destination region
in DMEM. During verification, the restored plaintext is compared byte by byte
with the original plaintext to confirm the correctness of the complete TX/RX
data flow.
