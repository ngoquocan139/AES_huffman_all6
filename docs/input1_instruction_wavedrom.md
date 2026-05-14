# input1.txt Instruction/MMIO WaveDrom

## 1. Scope

This diagram illustrates the RV32I software control flow for:

```text
make all TESTNAME=dma_compress_aes_input1 \
  RUN_ARGS="+CASE_NAME=dma_compress_aes_input1 +INPUT_FILE=input1.txt"
```

Source data from `sim/log/dma_compress_aes_input1.log`:

| Item | Value |
|---|---:|
| Input length | `2551` bytes, `0x000009f7` |
| TX mode | `0x9`, whole-file Huffman + AES-128-CBC |
| RX mode | `0x2`, AES-CBC decrypt + Huffman decode |
| TX output bytes | `1024` bytes, `0x00000400` |
| RX restored bytes | `2551` bytes, `0x000009f7` |
| Result signature | `0x44525831` |
| Error mask | `0x00000000` |
| Summary | `PASS=18 FAIL=0` |

This WaveDrom is an event-level instruction/MMIO timeline, not a
cycle-accurate CPU pipeline waveform.

## 2. WaveDrom

```text
{signal: [
  {name: 'clk', wave: 'p.................................'},
  {name: 'rst_n', wave: '01................................'},
  {name: 'phase', wave: 'x=.=.=.=.=.=.=.=.=.=.=.=.=.=.=.x', data:[
    'read len',
    'write IV0..3',
    'cfg TX',
    'start TX',
    'poll TX',
    'read tx bytes',
    'cfg RX',
    'start RX',
    'poll RX',
    'write result'
  ]},
  {name: 'instr', wave: 'x=.=.=.=.=.=.=.=.=.=.=.=.=.=.=.x', data:[
    'lw INPUT_LEN',
    'sw IV0',
    'sw IV1',
    'sw IV2',
    'sw IV3',
    'sw TX SRC/DST/LEN/MODE',
    'sw TX START',
    'lw TX STATUS',
    'lw CIPHERTEXT_BYTES',
    'sw RX SRC/DST/LEN/MODE',
    'sw RX START',
    'lw RX STATUS',
    'sw RESULT[0..15]'
  ]},
  {name: 'mmio_we', wave: '0.1.1.1.1.1.1.0.0.1.1.0.1.0.1.0'},
  {name: 'mmio_addr', wave: 'x.=.=.=.=.=.=.=.=.=.=.=.=.=.=.=x', data:[
    '0x28', '0x2c', '0x30', '0x34',
    '0x08', '0x0c', '0x10', '0x14',
    '0x04', '0x08', '0x0c', '0x10',
    '0x00'
  ]},
  {name: 'mmio_wdata', wave: 'x.=.=.=.=.=.=.=.=.=.=.=.=.=.=.=x', data:[
    'IV0=0x43424331', 'IV1=0x73170285', 'IV2=0x903d9e76', 'IV3=0x23d19959',
    'SRC=0x2000', 'DST=0x4000', 'LEN=0x09f7', 'MODE=0x9',
    'START=1', 'SRC=0x4000', 'DST=0x6000', 'LEN=0x0400',
    'RESULT_SIGNATURE=0x44525831'
  ]},
  {name: 'tx_busy', wave: '0......1.......0.................'},
  {name: 'tx_done', wave: '0..............1................'},
  {name: 'tx_status', wave: 'x..............=................', data:['0x98 -> 0x9a']},
  {name: 'tx_bytes_done', wave: 'x..............=................', data:['0x00000400']},
  {name: 'rx_busy', wave: '0....................1.......0..'},
  {name: 'rx_done', wave: '0..........................1....'},
  {name: 'rx_status', wave: 'x..........................=....', data:['0x28/0x2a']},
  {name: 'rx_bytes_done', wave: 'x..........................=....', data:['0x000009f7']},
  {name: 'result_signature', wave: 'x............................=..', data:['0x44525831']},
  {name: 'error_mask', wave: 'x............................=..', data:['0x00000000']}
],
config: {
  hscale: 2
}}
```

## 3. Meaning

| Timeline phase | What RV32I does | Hardware result |
|---|---|---|
| `load input_len` | `lw` from `INPUT_LEN_ADDR` | gets `0x000009f7` |
| `write IV0..IV3` | `sw` IV registers | AES-CBC IV visible to TX/RX |
| `config TX` | writes `SRC/DST/LEN/MODE` | TX configured for `0x2000 -> 0x4000`, mode `0x9` |
| `start TX` | writes `CONTROL.start` | `dma_tx_engine` starts |
| `poll TX` | loops on `STATUS` | status changes `0x98 -> 0x9a` |
| `read tx_bytes` | reads `CIPHERTEXT_BYTES_PRODUCED` | gets `0x00000400` |
| `config RX` | writes `SRC/DST/LEN/MODE` | RX configured for `0x4000 -> 0x6000`, mode `0x2` |
| `start RX` | writes `CONTROL.start` | `dma_rx_engine` starts |
| `poll RX` | loops on `STATUS` | status reaches `0x2a` |
| `publish result` | writes result words to DMEM | signature `0x44525831`, error mask `0` |

## 4. Detailed Flow

1. `rst_n` goes high, so the testbench releases the SoC.
2. CPU reads `INPUT_LEN_ADDR` and gets `0x000009f7`, meaning `input1.txt` has 2551 bytes.
3. CPU writes `IV0..IV3` to the DMA register file. This IV is used by the AES-CBC path.
4. CPU writes TX config registers:
   - `SRC=0x2000`
   - `DST=0x4000`
   - `LEN=0x09f7`
   - `MODE=0x9`
5. CPU writes `CONTROL.start=1`. TX starts, so `tx_busy` goes high.
6. While TX is running, CPU polls `STATUS`. The status changes from idle-like
   `0x98` to done-like `0x9a` when TX finishes.
7. CPU reads `CIPHERTEXT_BYTES_PRODUCED` and gets `0x00000400`. This is the
   length that RX must use next.
8. CPU writes RX config registers:
   - `SRC=0x4000`
   - `DST=0x6000`
   - `LEN=0x0400`
   - `MODE=0x2`
9. CPU writes `CONTROL.start=1` again. RX starts, so `rx_busy` goes high.
10. CPU polls `STATUS` again until RX reaches done-like `0x2a`.
11. RX writes restored plaintext back to DMEM at `0x6000`.
12. CPU writes `RESULT[0] = 0x44525831` and `RESULT[1] = 0x00000000`.
13. Testbench checks the signature and mismatch counters, then prints `PASS=18 FAIL=0`.
