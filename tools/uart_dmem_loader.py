#!/usr/bin/env python3
"""UART host utility for the FPGA DMEM loader/readback protocol."""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path


ACK_OK = 0x79
ACK_ERR = 0x1F
SIG_DMA_TX_RX = 0x44525831
SIG_TX_ONLY = 0x44545843
SIG_STORAGE = 0x53544F52
BOARD_STATUS_ADDR = 0x50
BOARD_FILE_ID_ADDR = 0x54
BOARD_EVENT_ADDR = 0x58
CPU_DEBUG_BASE_ADDR = 0x7F80
CPU_DEBUG_LEN = 96
CPU_DEBUG_SIGNATURE = 0x31555043
CPU_PERF_SIGNATURE = 0x31465250
CPU_RESET_PC = 0x00000000
CPU_STACK_POINTER_INIT = 0x00007F00
STORAGE_REPORT_BASE_ADDR = 0x00000280
STORAGE_REPORT_LEN = 160
STORAGE_REPORT_SIGNATURE = 0x31545052
STORAGE_META_BASE_ADDR = 0x00000100
STORAGE_META_RECORD_COUNT = 3
STORAGE_META_RECORD_WORDS = 16
STORAGE_META_RECORD_SHIFT = 6
STORAGE_META_LEN = STORAGE_META_RECORD_COUNT * (1 << STORAGE_META_RECORD_SHIFT)
STORAGE_META_VALID = 0
STORAGE_META_FILE_ID = 1
STORAGE_META_PLAIN_ADDR = 2
STORAGE_META_CIPHER_ADDR = 3
STORAGE_META_PLAIN_LEN = 4
STORAGE_META_CIPHER_LEN = 5
STORAGE_META_MODE = 6
STORAGE_META_IV0 = 7
STORAGE_META_VERSION = 11
STORAGE_META_FLAGS = 12
STORAGE_BUNDLE_BASE_ADDR = 0x00000800
STORAGE_BUNDLE_HEADER_LEN = 64
STORAGE_BUNDLE_SIGNATURE = 0x31444E42
STORAGE_BUNDLE_MAX_BYTES = 12288
AES_CORE_CYCLES_PER_BLOCK = 11


def parse_int(value: str) -> int:
    return int(value, 0)


def require_pyserial():
    try:
        import serial  # type: ignore
    except ImportError as exc:
        raise SystemExit(
            "Missing pyserial. Install it with: python3 -m pip install pyserial"
        ) from exc
    return serial


def read_exact(port, count: int) -> bytes:
    data = port.read(count)
    if len(data) != count:
        raise TimeoutError(f"UART timeout: expected {count} bytes, got {len(data)}")
    return data


def expect_ack(port, action: str, resync: bool = False, scan_bytes: int = 32) -> None:
    stray = []
    limit = max(1, scan_bytes if resync else 1)
    for _ in range(limit):
        ack = read_exact(port, 1)[0]
        if ack == ACK_OK:
            if stray:
                log(
                    "[WARN] discarded bytes before ACK for "
                    f"{action}: {' '.join(f'0x{byte:02x}' for byte in stray)}"
                )
            return
        if ack == ACK_ERR:
            raise RuntimeError(f"FPGA rejected {action}: ACK_ERR 0x1f")
        stray.append(ack)
        if not resync:
            break
    raise RuntimeError(
        f"Unexpected ACK for {action}: "
        + " ".join(f"0x{byte:02x}" for byte in stray)
    )


def send_load(port, payload: bytes, resync_ack: bool = False, ack_scan_bytes: int = 32) -> None:
    if not payload:
        raise ValueError("LOAD payload must not be empty")
    frame = b"LOAD" + len(payload).to_bytes(4, "little") + payload
    port.write(frame)
    port.flush()
    expect_ack(port, "LOAD", resync_ack, ack_scan_bytes)


def send_read(
    port,
    addr: int,
    length: int,
    legacy_no_ack: bool = False,
    resync_ack: bool = False,
    ack_scan_bytes: int = 32,
) -> bytes:
    if addr < 0 or addr > 0xFFFFFFFF:
        raise ValueError("READ address is out of 32-bit range")
    if length <= 0 or length > 0xFFFFFFFF:
        raise ValueError("READ length must be positive")
    frame = b"READ" + addr.to_bytes(4, "little") + length.to_bytes(4, "little")
    port.write(frame)
    port.flush()
    if legacy_no_ack:
        return read_exact(port, length)
    expect_ack(port, "READ", resync_ack, ack_scan_bytes)
    return read_exact(port, length)


def print_words(data: bytes, base_addr: int) -> None:
    for offset in range(0, len(data), 4):
        chunk = data[offset : offset + 4]
        if len(chunk) < 4:
            chunk = chunk + bytes(4 - len(chunk))
        word = int.from_bytes(chunk, "little")
        print(f"0x{base_addr + offset:08x}: 0x{word:08x}")


def words_from_data(data: bytes, base_addr: int) -> dict[int, int]:
    words = {}
    for offset in range(0, len(data), 4):
        chunk = data[offset : offset + 4]
        if len(chunk) < 4:
            break
        words[base_addr + offset] = int.from_bytes(chunk, "little")
    return words


def word_at(word_map: dict[int, int], addr: int) -> int | None:
    return word_map.get(addr)


def pct(numer: int, denom: int) -> str:
    if denom == 0:
        return "n/a"
    return f"{(100.0 * numer / denom):.2f}%"


def signed_saving(numer: int, denom: int) -> str:
    if denom == 0:
        return "n/a"
    return f"{(100.0 * numer / denom):.2f}%"


def align_up(value: int, alignment: int) -> int:
    return (value + alignment - 1) & ~(alignment - 1)


def storage_label(file_id: int) -> str:
    labels = {
        1: "SpO2/HR",
        2: "secure sensor log",
        3: "ECG waveform",
    }
    return labels.get(file_id, f"file_id={file_id}")


def build_storage_bundle(paths: list[str]) -> tuple[bytes, list[dict[str, int | str]]]:
    if not paths:
        raise ValueError("--bundle requires at least one input file")
    if len(paths) > 3:
        raise ValueError("secure-storage bundle supports at most 3 files")

    payloads = []
    for idx, item in enumerate(paths):
        data = Path(item).read_bytes()
        if not data:
            raise ValueError(f"bundle input is empty: {item}")
        payloads.append((idx + 1, item, data))

    header_len = align_up(8 + (len(payloads) * 16), 16)
    bundle = bytearray(header_len)
    bundle[0:4] = STORAGE_BUNDLE_SIGNATURE.to_bytes(4, "little")
    bundle[4:8] = len(payloads).to_bytes(4, "little")

    info: list[dict[str, int | str]] = []
    offset = header_len
    for idx, (file_id, item, data) in enumerate(payloads):
        offset = align_up(offset, 16)
        if len(bundle) < offset:
            bundle.extend(b"\x00" * (offset - len(bundle)))
        bundle.extend(data)

        rec_base = 8 + (idx * 16)
        bundle[rec_base + 0 : rec_base + 4] = file_id.to_bytes(4, "little")
        bundle[rec_base + 4 : rec_base + 8] = (0).to_bytes(4, "little")
        bundle[rec_base + 8 : rec_base + 12] = offset.to_bytes(4, "little")
        bundle[rec_base + 12 : rec_base + 16] = len(data).to_bytes(4, "little")
        info.append(
            {
                "file_id": file_id,
                "path": item,
                "offset": offset,
                "length": len(data),
            }
        )
        offset = offset + len(data)

    if len(bundle) > STORAGE_BUNDLE_MAX_BYTES:
        raise ValueError(
            f"bundle is {len(bundle)} bytes, exceeds FPGA UART staging limit "
            f"{STORAGE_BUNDLE_MAX_BYTES} bytes"
        )

    return bytes(bundle), info


def status_text(status: int) -> str:
    busy = status & 0x1
    done = (status >> 1) & 0x1
    error = (status >> 2) & 0x1
    return f"0x{status:08x} (busy={busy}, done={done}, error={error})"


def mode_text(mode: int) -> str:
    known = {
        0x00000002: "RX decrypt + Huffman decode",
        0x00000009: "TX compress + AES-CBC",
        0x0000000D: "TX compress only",
    }
    return known.get(mode, f"unknown/firmware-specific mode 0x{mode:08x}")


def signature_text(signature: int) -> str:
    known = {
        SIG_DMA_TX_RX: "DRX1 / TX+RX loopback firmware",
        SIG_TX_ONLY: "DTXC / TX-only firmware",
        SIG_STORAGE: "STOR / secure-storage firmware",
    }
    return known.get(signature, "unknown firmware signature")


def board_status_fields(status: int) -> dict[str, int]:
    return {
        "run_latched": status & 0x1,
        "busy": (status >> 1) & 0x1,
        "zeroize_done": (status >> 2) & 0x1,
        "snapshot_valid": (status >> 3) & 0x1,
        "selected_file_id": (status >> 8) & 0xFF,
        "zeroize_count": (status >> 16) & 0xFF,
        "snapshot_count": (status >> 24) & 0xFF,
    }


def cpu_debug_status_fields(status: int) -> dict[str, int]:
    return {
        "rst": status & 0x1,
        "hold": (status >> 1) & 0x1,
        "imem_seen": (status >> 2) & 0x1,
        "imem_en": (status >> 3) & 0x1,
        "dmem_en": (status >> 4) & 0x1,
        "mmio_sel": (status >> 5) & 0x1,
        "tx_busy": (status >> 6) & 0x1,
        "rx_busy": (status >> 7) & 0x1,
        "tx_done": (status >> 8) & 0x1,
        "rx_done": (status >> 9) & 0x1,
        "tx_error": (status >> 10) & 0x1,
        "rx_error": (status >> 11) & 0x1,
        "apb_stall": (status >> 12) & 0x1,
        "load_resp_mmio": (status >> 13) & 0x1,
        "dmem_we": (status >> 16) & 0xF,
    }


def print_live_cpu_debug(word_map: dict[int, int], force: bool = False) -> None:
    signature = word_at(word_map, CPU_DEBUG_BASE_ADDR)
    if signature != CPU_DEBUG_SIGNATURE:
        if force:
            print("")
            print("CPU live debug")
            print(
                f"  [WARN] CPU debug window not available at "
                f"0x{CPU_DEBUG_BASE_ADDR:08x}; rebuild/program a newer bitstream."
            )
        return

    status = word_at(word_map, CPU_DEBUG_BASE_ADDR + 0x04) or 0
    fetch_pc = word_at(word_map, CPU_DEBUG_BASE_ADDR + 0x08) or 0
    fetch_instr = word_at(word_map, CPU_DEBUG_BASE_ADDR + 0x0C) or 0
    cycle_count = word_at(word_map, CPU_DEBUG_BASE_ADDR + 0x10) or 0
    fetch_count = word_at(word_map, CPU_DEBUG_BASE_ADDR + 0x14) or 0
    dmem_accesses = word_at(word_map, CPU_DEBUG_BASE_ADDR + 0x18) or 0
    mmio_accesses = word_at(word_map, CPU_DEBUG_BASE_ADDR + 0x1C) or 0
    last_dmem_addr = word_at(word_map, CPU_DEBUG_BASE_ADDR + 0x20) or 0
    last_dmem_wdata = word_at(word_map, CPU_DEBUG_BASE_ADDR + 0x24) or 0
    last_dmem_ctrl = word_at(word_map, CPU_DEBUG_BASE_ADDR + 0x28) or 0
    wb_count = word_at(word_map, CPU_DEBUG_BASE_ADDR + 0x2C) or 0
    last_wb_info = word_at(word_map, CPU_DEBUG_BASE_ADDR + 0x30) or 0
    last_wb_data = word_at(word_map, CPU_DEBUG_BASE_ADDR + 0x34) or 0
    loader_bytes = word_at(word_map, CPU_DEBUG_BASE_ADDR + 0x38) or 0
    debug_version = word_at(word_map, CPU_DEBUG_BASE_ADDR + 0x3C) or 0
    perf_signature = word_at(word_map, CPU_DEBUG_BASE_ADDR + 0x40)
    perf_tx_dma = word_at(word_map, CPU_DEBUG_BASE_ADDR + 0x44)
    perf_rx_dma = word_at(word_map, CPU_DEBUG_BASE_ADDR + 0x48)
    perf_tx_huffman = word_at(word_map, CPU_DEBUG_BASE_ADDR + 0x4C)
    perf_tx_aes = word_at(word_map, CPU_DEBUG_BASE_ADDR + 0x50)
    perf_rx_huffman = word_at(word_map, CPU_DEBUG_BASE_ADDR + 0x54)
    perf_rx_aes = word_at(word_map, CPU_DEBUG_BASE_ADDR + 0x58)
    status_fields = cpu_debug_status_fields(status)
    last_wb_rd = last_wb_info & 0x1F
    last_wb_valid = (last_wb_info >> 5) & 0x1
    last_dmem_we = last_dmem_ctrl & 0xF
    last_dmem_mmio = (last_dmem_ctrl >> 4) & 0x1

    print("")
    print("CPU live debug")
    print(f"  window         : 0x{CPU_DEBUG_BASE_ADDR:08x}..0x{CPU_DEBUG_BASE_ADDR + CPU_DEBUG_LEN - 1:08x}")
    print(
        "  status         : "
        f"0x{status:08x} "
        f"(rst={status_fields['rst']}, hold={status_fields['hold']}, "
        f"imem_seen={status_fields['imem_seen']}, imem_en={status_fields['imem_en']}, "
        f"dmem_en={status_fields['dmem_en']}, mmio={status_fields['mmio_sel']}, "
        f"tx_busy={status_fields['tx_busy']}, rx_busy={status_fields['rx_busy']}, "
        f"tx_done={status_fields['tx_done']}, rx_done={status_fields['rx_done']}, "
        f"tx_error={status_fields['tx_error']}, rx_error={status_fields['rx_error']})"
    )
    print(f"  fetch_pc       : 0x{fetch_pc:08x}")
    print(f"  fetch_instr    : 0x{fetch_instr:08x}")
    print(f"  cycles         : {cycle_count} since SoC reset release")
    print(f"  imem_fetches   : {fetch_count}")
    print(f"  dmem_accesses  : {dmem_accesses}")
    print(f"  mmio_accesses  : {mmio_accesses}")
    print(
        "  last_dmem      : "
        f"addr=0x{last_dmem_addr:08x}, wdata=0x{last_dmem_wdata:08x}, "
        f"we=0x{last_dmem_we:x}, mmio={last_dmem_mmio}"
    )
    print(
        "  last_writeback : "
        f"count={wb_count}, valid={last_wb_valid}, rd=x{last_wb_rd}, "
        f"data=0x{last_wb_data:08x}"
    )
    print(f"  loader_bytes   : {loader_bytes}")
    print(f"  debug_version  : 0x{debug_version:08x}")
    if perf_signature == CPU_PERF_SIGNATURE:
        print("")
        print("RTL performance counters")
        print(f"  tx_dma_cycles      : {perf_tx_dma}")
        print(f"  rx_dma_cycles      : {perf_rx_dma}")
        print(f"  tx_huffman_cycles  : {perf_tx_huffman}")
        print(f"  tx_aes_cycles      : {perf_tx_aes}")
        print(f"  rx_huffman_cycles  : {perf_rx_huffman}")
        print(f"  rx_aes_cycles      : {perf_rx_aes}")


def print_cpu_info(word_map: dict[int, int], words: list[int], input_len: int | None, input2_len: int | None) -> None:
    signature = words[0]
    error_mask = words[1]
    board_status = word_at(word_map, BOARD_STATUS_ADDR)
    board_file_id = word_at(word_map, BOARD_FILE_ID_ADDR)
    board_event_count = word_at(word_map, BOARD_EVENT_ADDR)

    print("")
    print("CPU / firmware")
    print(f"  reset_pc       : 0x{CPU_RESET_PC:08x}")
    print(f"  boot           : _start sets sp=0x{CPU_STACK_POINTER_INIT:08x}, then jumps to main")
    print(f"  result_block   : DMEM 0x00000000..0x0000003f")
    print(f"  signature      : 0x{signature:08x} ({signature_text(signature)})")
    print(f"  error_mask     : 0x{error_mask:08x}")
    print(f"  cpu_result     : {'PASS' if error_mask == 0 else 'FAIL'}")
    if input_len is not None:
        print(f"  input_len      : {input_len} bytes @ DMEM[0x40]")
    if input2_len is not None:
        print(f"  input2_len     : {input2_len} bytes @ DMEM[0x44]")

    if signature == SIG_DMA_TX_RX:
        print("  firmware_flow  : CPU programs DMA TX, polls done, then programs DMA RX")
        print("  dma_jobs       : 2 (TX compress+AES, RX decrypt+decode)")
        print(f"  cpu_poll_loops : TX={words[6]}, RX={words[11]}, total={words[6] + words[11]}")
        print(f"  dma_bytes      : TX={words[4]}, ciphertext={words[5]}, RX_plain={words[9]}")
    elif signature == SIG_TX_ONLY:
        print("  firmware_flow  : CPU programs DMA TX and polls done")
        print("  dma_jobs       : 1 (TX)")
        print(f"  cpu_poll_loops : TX={words[6]}")
        print(f"  dma_mode       : {mode_text(words[8])}")
        print(f"  dma_bytes      : TX={words[4]}, ciphertext={words[5]}")
    elif signature == SIG_STORAGE:
        total_records = word_at(word_map, STORAGE_REPORT_BASE_ADDR + 12) or words[15]
        tx_total_polls = word_at(word_map, STORAGE_REPORT_BASE_ADDR + 40) or words[6]
        print("  firmware_flow  : secure_write(file_id=1..N), secure_read(selected file_id), then watch button file_id changes")
        print(f"  dma_jobs       : {total_records} TX job(s) + RX selected-file job")
        print(f"  cpu_poll_loops : TX_total={tx_total_polls}, RX_selected={words[11]}, visible_total={tx_total_polls + words[11]}")
        print(f"  storage_state  : selected_file_id={words[14]}, total_records={words[15]}")
        print(f"  dma_bytes      : TX1={words[4]}, CTX1={words[5]}, CTX2={words[12]}, RX_plain={words[9]}")

    if board_status is not None:
        fields = board_status_fields(board_status)
        print("  board_status   : "
              f"0x{board_status:08x} "
              f"(run={fields['run_latched']}, busy={fields['busy']}, "
              f"zeroize_done={fields['zeroize_done']}, snapshot_valid={fields['snapshot_valid']}, "
              f"selected_file_id={fields['selected_file_id']}, "
              f"zeroize_count={fields['zeroize_count']}, snapshot_count={fields['snapshot_count']})")
    if board_file_id is not None:
        print(f"  board_file_id  : {board_file_id}")
    if board_event_count is not None:
        print(f"  board_events   : {board_event_count}")


def first_16_bytes(words: list[int]) -> str:
    data = b"".join(word.to_bytes(4, "little") for word in words)
    return " ".join(f"{byte:02x}" for byte in data[:16])


def report_word(word_map: dict[int, int], index: int) -> int | None:
    return word_at(word_map, STORAGE_REPORT_BASE_ADDR + (index * 4))


def metadata_word(word_map: dict[int, int], slot: int, index: int) -> int | None:
    addr = STORAGE_META_BASE_ADDR + (slot << STORAGE_META_RECORD_SHIFT) + (index * 4)
    return word_at(word_map, addr)


def metadata_records(word_map: dict[int, int]) -> list[dict[str, int]]:
    records = []
    for slot in range(STORAGE_META_RECORD_COUNT):
        valid = metadata_word(word_map, slot, STORAGE_META_VALID) or 0
        file_id = metadata_word(word_map, slot, STORAGE_META_FILE_ID) or 0
        plain_addr = metadata_word(word_map, slot, STORAGE_META_PLAIN_ADDR) or 0
        cipher_addr = metadata_word(word_map, slot, STORAGE_META_CIPHER_ADDR) or 0
        plain_len = metadata_word(word_map, slot, STORAGE_META_PLAIN_LEN) or 0
        cipher_len = metadata_word(word_map, slot, STORAGE_META_CIPHER_LEN) or 0
        mode = metadata_word(word_map, slot, STORAGE_META_MODE) or 0
        iv0 = metadata_word(word_map, slot, STORAGE_META_IV0) or 0
        version = metadata_word(word_map, slot, STORAGE_META_VERSION) or 0
        flags = metadata_word(word_map, slot, STORAGE_META_FLAGS) or 0
        if valid:
            records.append(
                {
                    "slot": slot,
                    "file_id": file_id,
                    "plain_addr": plain_addr,
                    "cipher_addr": cipher_addr,
                    "plain_len": plain_len,
                    "cipher_len": cipher_len,
                    "mode": mode,
                    "iv0": iv0,
                    "version": version,
                    "flags": flags,
                }
            )
    return records


def aes_blocks(byte_count: int) -> int:
    if byte_count <= 0:
        return 0
    return (byte_count + 15) // 16


def aes_cycles(byte_count: int) -> int:
    return aes_blocks(byte_count) * AES_CORE_CYCLES_PER_BLOCK


def print_record_table(records: list[dict[str, int]]) -> None:
    print("Secure storage records")
    print(
        "  id  label              plaintext  ciphertext  storage_ratio  "
        "space_saving  mode"
    )
    for rec in records:
        file_id = rec["file_id"]
        plain_len = rec["plain_len"]
        cipher_len = rec["cipher_len"]
        saving = plain_len - cipher_len
        print(
            f"  {file_id:<3} {storage_label(file_id):<18} "
            f"{plain_len:>9}  {cipher_len:>10}  "
            f"{pct(cipher_len, plain_len):>13}  "
            f"{signed_saving(saving, plain_len):>12}  "
            f"{mode_text(rec['mode'])}"
        )


def print_metric_summary(
    records: list[dict[str, int]],
    selected_file_id: int,
    selected_plain_len: int,
    selected_cipher_len: int,
    rx_plain_bytes: int,
    rx_polls: int,
    tx_total_polls: int,
    word_map: dict[int, int],
) -> None:
    total_plain = sum(rec["plain_len"] for rec in records)
    total_cipher = sum(rec["cipher_len"] for rec in records)
    cpu_cycles = word_at(word_map, CPU_DEBUG_BASE_ADDR + 0x10)
    cpu_fetches = word_at(word_map, CPU_DEBUG_BASE_ADDR + 0x14)
    cpu_dmem = word_at(word_map, CPU_DEBUG_BASE_ADDR + 0x18)
    cpu_mmio = word_at(word_map, CPU_DEBUG_BASE_ADDR + 0x1C)
    perf_signature = word_at(word_map, CPU_DEBUG_BASE_ADDR + 0x40)
    perf_tx_dma = word_at(word_map, CPU_DEBUG_BASE_ADDR + 0x44)
    perf_rx_dma = word_at(word_map, CPU_DEBUG_BASE_ADDR + 0x48)
    perf_tx_huffman = word_at(word_map, CPU_DEBUG_BASE_ADDR + 0x4C)
    perf_tx_aes = word_at(word_map, CPU_DEBUG_BASE_ADDR + 0x50)
    perf_rx_huffman = word_at(word_map, CPU_DEBUG_BASE_ADDR + 0x54)
    perf_rx_aes = word_at(word_map, CPU_DEBUG_BASE_ADDR + 0x58)

    print("")
    print("Per-file report metrics")
    print(f"  total_plain    : {total_plain} bytes")
    print(f"  total_cipher   : {total_cipher} bytes")
    print(f"  aggregate_ratio: {pct(total_cipher, total_plain)}")
    print(f"  aggregate_save : {signed_saving(total_plain - total_cipher, total_plain)}")

    print("")
    print("Selected readback")
    print(f"  selected_file  : {selected_file_id} ({storage_label(selected_file_id)})")
    print(f"  plaintext_exp  : {selected_plain_len} bytes")
    print(f"  ciphertext     : {selected_cipher_len} bytes")
    print(f"  rx_plaintext   : {rx_plain_bytes} bytes")
    print(f"  rx_len_match   : {'YES' if rx_plain_bytes == selected_plain_len else 'NO'}")
    print(f"  selected_ratio : {pct(selected_cipher_len, selected_plain_len)}")
    print(f"  selected_save  : {signed_saving(selected_plain_len - selected_cipher_len, selected_plain_len)}")

    print("")
    print("Cycle / counter metrics")
    print(f"  tx_poll_loops  : {tx_total_polls} CPU firmware polling loops")
    print(f"  rx_poll_loops  : {rx_polls} CPU firmware polling loops")
    if cpu_cycles is not None:
        print(f"  cpu_cycles_live: {cpu_cycles} cycles since SoC reset release")
    if cpu_fetches is not None:
        print(f"  cpu_imem_fetch : {cpu_fetches}")
    if cpu_dmem is not None:
        print(f"  cpu_dmem_access: {cpu_dmem}")
    if cpu_mmio is not None:
        print(f"  cpu_mmio_access: {cpu_mmio}")
    if perf_signature == CPU_PERF_SIGNATURE:
        print(f"  tx_dma_cycles  : {perf_tx_dma} RTL cycles")
        print(f"  rx_dma_cycles  : {perf_rx_dma} RTL cycles")
        print(f"  tx_huffman_cyc : {perf_tx_huffman} RTL cycles")
        print(f"  tx_aes_cyc     : {perf_tx_aes} RTL cycles")
        print(f"  rx_huffman_cyc : {perf_rx_huffman} RTL cycles")
        print(f"  rx_aes_cyc     : {perf_rx_aes} RTL cycles")

    print("")
    print("AES core cycles")
    print("  id  aes_blocks_tx  aes_cycles_tx")
    for rec in records:
        print(
            f"  {rec['file_id']:<3} {aes_blocks(rec['cipher_len']):>13}  "
            f"{aes_cycles(rec['cipher_len']):>13}"
        )
    print(
        f"  RX selected    {aes_blocks(selected_cipher_len):>5} blocks, "
        f"{aes_cycles(selected_cipher_len)} AES-core cycles"
    )
    if perf_signature != CPU_PERF_SIGNATURE:
        print(
            "  Huffman cycles : current bitstream does not expose a separate "
            "Huffman-stage cycle counter; rebuild/program the counter bitstream."
        )


def print_storage_report(word_map: dict[int, int], legacy_words: list[int]) -> None:
    records_from_meta = metadata_records(word_map)
    if report_word(word_map, 0) != STORAGE_REPORT_SIGNATURE:
        input1_len = word_at(word_map, 0x40)
        tx1_cipher_bytes = legacy_words[5]
        rx_plain_bytes = legacy_words[9]
        selected_file_id = legacy_words[14]
        selected_plain_len = 0
        selected_cipher_len = 0
        tx_total_polls = report_word(word_map, 10) or legacy_words[6]
        selected = None
        for rec in records_from_meta:
            if rec["file_id"] == selected_file_id:
                selected = rec
                selected_plain_len = rec["plain_len"]
                selected_cipher_len = rec["cipher_len"]
                break

        print("firmware        : test_mmio_dma_storage_table.c, secure storage API")
        print(f"input_len       : {input1_len if input1_len is not None else 'unknown'} bytes")
        print("")
        print("Storage metadata")
        if records_from_meta:
            print_record_table(records_from_meta)
            print_metric_summary(
                records_from_meta,
                selected_file_id,
                selected_plain_len,
                selected_cipher_len,
                rx_plain_bytes,
                legacy_words[11],
                tx_total_polls,
                word_map,
            )
        else:
            print(f"  tx1_ciphertext: {tx1_cipher_bytes} bytes")
            print(f"  tx2_ciphertext: {legacy_words[12]} bytes")
            print(f"  selected_file : {selected_file_id}")
            print(f"  total_records : {legacy_words[15]}")
            if input1_len is not None:
                print(f"  storage_ratio : {pct(tx1_cipher_bytes, input1_len)}")
                print(f"  space_saving  : {signed_saving(input1_len - tx1_cipher_bytes, input1_len)}")
                print(f"  rx_len_match  : {'YES' if rx_plain_bytes == input1_len else 'NO'}")
        return

    bundle_mode = report_word(word_map, 2) or 0
    bundle_signature = word_at(word_map, STORAGE_BUNDLE_BASE_ADDR)
    bundle_count = word_at(word_map, STORAGE_BUNDLE_BASE_ADDR + 4)
    total_records = report_word(word_map, 3) or 0
    selected_file_id = report_word(word_map, 4) or legacy_words[14]
    selected_slot = report_word(word_map, 5)
    selected_plain_len = report_word(word_map, 6) or 0
    selected_cipher_len = report_word(word_map, 7) or 0
    rx_plain_bytes = report_word(word_map, 8) or legacy_words[9]
    rx_polls = report_word(word_map, 9) or legacy_words[11]
    tx_total_polls = report_word(word_map, 10) or legacy_words[6]
    total_plain = report_word(word_map, 11) or 0
    total_cipher = report_word(word_map, 12) or 0
    rx_status_before = report_word(word_map, 13) or legacy_words[7]
    rx_status_after = report_word(word_map, 14) or legacy_words[8]
    rx_debug = report_word(word_map, 15) or legacy_words[10]

    print("firmware        : test_mmio_dma_storage_table.c, secure storage API")
    print(f"load_mode       : {'UART bundle' if bundle_mode else 'legacy/direct input'}")
    if bundle_signature is not None:
        print(
            "bundle_header   : "
            f"0x{bundle_signature:08x}, count={bundle_count if bundle_count is not None else 'unknown'}"
        )
        if (bundle_signature == STORAGE_BUNDLE_SIGNATURE) and not bundle_mode:
            print("diagnostic      : bundle is in DMEM but firmware did not consume it; rebuild/reload the fixed bitstream.")
    print(f"total_records   : {total_records}")
    print("")
    records = []
    for idx in range(3):
        base = 16 + (idx * 8)
        valid = report_word(word_map, base + 0) or 0
        file_id = report_word(word_map, base + 1) or 0
        plain_addr = report_word(word_map, base + 2) or 0
        cipher_addr = report_word(word_map, base + 3) or 0
        plain_len = report_word(word_map, base + 4) or 0
        cipher_len = report_word(word_map, base + 5) or 0
        iv0 = report_word(word_map, base + 6) or 0
        version = report_word(word_map, base + 7) or 0
        if not valid:
            continue
        records.append(
            {
                "slot": idx,
                "file_id": file_id,
                "plain_addr": plain_addr,
                "cipher_addr": cipher_addr,
                "plain_len": plain_len,
                "cipher_len": cipher_len,
                "mode": metadata_word(word_map, idx, STORAGE_META_MODE) or 0x00000009,
                "iv0": iv0,
                "version": version,
                "flags": 0,
            }
        )

    if not records and records_from_meta:
        records = records_from_meta
    print_record_table(records)
    print("")
    print("Selected debug")
    print(f"  selected_slot : {selected_slot if selected_slot is not None else 'unknown'}")
    print(f"  rx_status_bef : {status_text(rx_status_before)}")
    print(f"  rx_status_aft : {status_text(rx_status_after)}")
    print(f"  rx_debug      : 0x{rx_debug:08x}")
    if records:
        if selected_plain_len == 0 or selected_cipher_len == 0:
            for rec in records:
                if rec["file_id"] == selected_file_id:
                    selected_plain_len = rec["plain_len"]
                    selected_cipher_len = rec["cipher_len"]
                    break
        if total_plain == 0:
            total_plain = sum(rec["plain_len"] for rec in records)
        if total_cipher == 0:
            total_cipher = sum(rec["cipher_len"] for rec in records)
    print_metric_summary(
        records,
        selected_file_id,
        selected_plain_len,
        selected_cipher_len,
        rx_plain_bytes,
        rx_polls,
        tx_total_polls,
        word_map,
    )


def print_result_decode(word_map: dict[int, int]) -> None:
    result_words = [word_at(word_map, idx * 4) for idx in range(16)]
    if any(word is None for word in result_words):
        print("")
        print("===== UART RESULT DECODE =====")
        print("[WARN] Result block incomplete. Read at least 64 bytes from 0x00000000.")
        return

    words = [int(word) for word in result_words]
    signature = words[0]
    error_mask = words[1]
    input_len = word_at(word_map, 0x40)
    input2_len = word_at(word_map, 0x44)
    pass_fail = "PASS" if error_mask == 0 else "FAIL"

    print("")
    print("===== UART RESULT DECODE =====")
    print(f"signature       : 0x{signature:08x}")
    print(f"summary         : {pass_fail} (error_mask=0x{error_mask:08x})")
    print_cpu_info(word_map, words, input_len, input2_len)

    if signature == SIG_DMA_TX_RX:
        tx_cipher_bytes = words[5]
        rx_plain_bytes = words[9]
        print("firmware        : test_mmio_dma.c, TX compress+AES then RX decrypt+decode")
        print(f"input_len       : {input_len if input_len is not None else 'unknown'} bytes")
        print("")
        print("TX")
        print(f"  status_before : {status_text(words[2])}")
        print(f"  status_after  : {status_text(words[3])}")
        print(f"  tx_bytes_done : {words[4]} bytes")
        print(f"  ciphertext    : {tx_cipher_bytes} bytes")
        print(f"  poll_count    : {words[6]} CPU polling loops")
        print("")
        print("RX")
        print(f"  status_before : {status_text(words[7])}")
        print(f"  status_after  : {status_text(words[8])}")
        print(f"  plaintext     : {rx_plain_bytes} bytes")
        print(f"  debug         : 0x{words[10]:08x}")
        print(f"  poll_count    : {words[11]} CPU polling loops")
        print("")
        if input_len is not None:
            print("Ratios")
            print(f"  storage_ratio : {pct(tx_cipher_bytes, input_len)}")
            print(f"  space_saving  : {pct(input_len - tx_cipher_bytes, input_len)}")
            print(f"  rx_len_match  : {'YES' if rx_plain_bytes == input_len else 'NO'}")
        print(f"rx_first_16B    : {first_16_bytes(words[12:16])}")
    elif signature == SIG_TX_ONLY:
        input_len = words[9] if words[9] != 0 else input_len
        tx_cipher_bytes = words[5]
        print("firmware        : test_mmio_tx_only.c, TX only")
        print(f"mode            : {mode_text(words[8])}")
        print(f"input_len       : {input_len if input_len is not None else 'unknown'} bytes")
        print(f"status_before   : {status_text(words[2])}")
        print(f"status_after    : {status_text(words[3])}")
        print(f"tx_bytes_done   : {words[4]} bytes")
        print(f"ciphertext      : {tx_cipher_bytes} bytes")
        print(f"poll_count      : {words[6]} CPU polling loops")
        print(f"debug           : 0x{words[7]:08x}")
        if input_len is not None:
            print(f"storage_ratio   : {pct(tx_cipher_bytes, input_len)}")
            print(f"space_saving    : {pct(input_len - tx_cipher_bytes, input_len)}")
        print(f"tx_first_16B    : {first_16_bytes(words[10:14])}")
    elif signature == SIG_STORAGE:
        print_storage_report(word_map, words)
        print("")
        print("TX record 1 raw")
        print(f"  status_before : {status_text(words[2])}")
        print(f"  status_after  : {status_text(words[3])}")
        print(f"  tx_bytes_done : {words[4]} bytes")
        print(f"  ciphertext    : {words[5]} bytes")
        print(f"  poll_count    : {words[6]} CPU polling loops")
        print("")
        print("RX selected raw")
        print(f"  status_before : {status_text(words[7])}")
        print(f"  status_after  : {status_text(words[8])}")
        print(f"  plaintext     : {words[9]} bytes")
        print(f"  debug         : 0x{words[10]:08x}")
        print(f"  poll_count    : {words[11]} CPU polling loops")
    else:
        print("firmware        : unknown result signature")
        for idx, word in enumerate(words):
            print(f"result[{idx:02d}]      : 0x{word:08x}")

    print_live_cpu_debug(word_map)


def log(message: str) -> None:
    print(message, file=sys.stderr)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Send LOAD frames and READ DMEM data over the FPGA UART loader."
    )
    parser.add_argument("--port", required=True, help="Serial port, e.g. /dev/ttyUSB0")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--timeout", type=float, default=5.0)
    parser.add_argument("--input", help="Payload file to send with LOAD")
    parser.add_argument(
        "--bundle",
        nargs="+",
        metavar="FILE",
        help="Build and LOAD a secure-storage bundle. Files become file_id 1, 2, and 3 in order.",
    )
    parser.add_argument(
        "--read",
        nargs=2,
        metavar=("ADDR", "LEN"),
        help="Read LEN bytes from DMEM byte address ADDR after optional LOAD",
    )
    parser.add_argument("--output", help="Write READ data to this binary file")
    parser.add_argument("--words", action="store_true", help="Print READ data as 32-bit words")
    parser.add_argument(
        "--decode-result",
        action="store_true",
        help="Decode RESULT_WORD(0..15), related length words, and CPU debug words into a detailed summary",
    )
    parser.add_argument(
        "--cpu-info",
        action="store_true",
        help="Read and print the live CPU debug window at 0x7f80",
    )
    parser.add_argument("--post-load-delay", type=float, default=0.0)
    parser.add_argument(
        "--legacy-read-no-ack",
        action="store_true",
        help="For older FPGA bitstreams that return READ data directly without an ACK byte",
    )
    parser.add_argument(
        "--resync-ack",
        action="store_true",
        help="Scan past stray UART bytes until ACK 0x79 is found",
    )
    parser.add_argument(
        "--ack-scan-bytes",
        type=int,
        default=32,
        help="Maximum bytes to scan when --resync-ack is used",
    )
    args = parser.parse_args()

    if args.input and args.bundle:
        parser.error("--input and --bundle are mutually exclusive")
    if not args.input and not args.bundle and not args.read and not args.cpu_info:
        parser.error("nothing to do: pass --input, --bundle, --read ADDR LEN, and/or --cpu-info")

    serial = require_pyserial()

    with serial.Serial(args.port, args.baud, timeout=args.timeout, write_timeout=args.timeout) as port:
        # Drop stale bytes from previous attempts before starting a new frame.
        port.reset_input_buffer()
        port.reset_output_buffer()

        if args.input or args.bundle:
            bundle_info = None
            if args.bundle:
                payload, bundle_info = build_storage_bundle(args.bundle)
            else:
                payload = Path(args.input).read_bytes()
            send_load(port, payload, args.resync_ack, args.ack_scan_bytes)
            if bundle_info is None:
                log(f"[PASS] loaded {len(payload)} bytes from {args.input}")
            else:
                log(f"[PASS] loaded secure-storage bundle ({len(payload)} bytes)")
                for item in bundle_info:
                    log(
                        "[INFO] bundle "
                        f"file_id={item['file_id']} "
                        f"label={storage_label(int(item['file_id']))} "
                        f"len={item['length']} offset=0x{int(item['offset']):x} "
                        f"path={item['path']}"
                    )
            if args.post_load_delay > 0.0:
                time.sleep(args.post_load_delay)

        if args.read:
            # Drop bytes left by an earlier aborted READ before starting a new READ frame.
            port.reset_input_buffer()
            addr = parse_int(args.read[0])
            length = parse_int(args.read[1])
            data = send_read(
                port,
                addr,
                length,
                args.legacy_read_no_ack,
                args.resync_ack,
                args.ack_scan_bytes,
            )
            log(f"[PASS] read {len(data)} bytes from 0x{addr:08x}")
            if args.output:
                Path(args.output).write_bytes(data)
                log(f"[PASS] wrote {args.output}")

            word_map = words_from_data(data, addr)
            should_decode = args.decode_result or (
                args.words and addr <= 0 and (addr + length) >= 64 and not args.output
            )
            if should_decode and not args.legacy_read_no_ack:
                if 0x40 not in word_map:
                    try:
                        extra = send_read(
                            port,
                            0x40,
                            28,
                            False,
                            args.resync_ack,
                            args.ack_scan_bytes,
                        )
                        word_map.update(words_from_data(extra, 0x40))
                    except Exception as exc:  # Keep the requested READ result usable.
                        log(f"[WARN] could not read CPU/board info words for decode: {exc}")
                if STORAGE_REPORT_BASE_ADDR not in word_map:
                    try:
                        report = send_read(
                            port,
                            STORAGE_REPORT_BASE_ADDR,
                            STORAGE_REPORT_LEN,
                            False,
                            args.resync_ack,
                            args.ack_scan_bytes,
                        )
                        word_map.update(words_from_data(report, STORAGE_REPORT_BASE_ADDR))
                    except Exception as exc:
                        log(f"[WARN] could not read secure-storage report window: {exc}")
                if STORAGE_META_BASE_ADDR not in word_map:
                    try:
                        meta = send_read(
                            port,
                            STORAGE_META_BASE_ADDR,
                            STORAGE_META_LEN,
                            False,
                            args.resync_ack,
                            args.ack_scan_bytes,
                        )
                        word_map.update(words_from_data(meta, STORAGE_META_BASE_ADDR))
                    except Exception as exc:
                        log(f"[WARN] could not read secure-storage metadata window: {exc}")
                if CPU_DEBUG_BASE_ADDR not in word_map:
                    try:
                        debug = send_read(
                            port,
                            CPU_DEBUG_BASE_ADDR,
                            CPU_DEBUG_LEN,
                            False,
                            args.resync_ack,
                            args.ack_scan_bytes,
                        )
                        word_map.update(words_from_data(debug, CPU_DEBUG_BASE_ADDR))
                    except Exception as exc:
                        log(f"[WARN] could not read live CPU debug window: {exc}")
                if STORAGE_BUNDLE_BASE_ADDR not in word_map:
                    try:
                        bundle_header = send_read(
                            port,
                            STORAGE_BUNDLE_BASE_ADDR,
                            STORAGE_BUNDLE_HEADER_LEN,
                            False,
                            args.resync_ack,
                            args.ack_scan_bytes,
                        )
                        word_map.update(words_from_data(bundle_header, STORAGE_BUNDLE_BASE_ADDR))
                    except Exception as exc:
                        log(f"[WARN] could not read secure-storage bundle header: {exc}")

            if args.words:
                print_words(data, addr)
            if should_decode:
                print_result_decode(word_map)
            elif args.cpu_info:
                if CPU_DEBUG_BASE_ADDR not in word_map:
                    try:
                        debug = send_read(
                            port,
                            CPU_DEBUG_BASE_ADDR,
                            CPU_DEBUG_LEN,
                            False,
                            args.resync_ack,
                            args.ack_scan_bytes,
                        )
                        word_map.update(words_from_data(debug, CPU_DEBUG_BASE_ADDR))
                    except Exception as exc:
                        log(f"[WARN] could not read live CPU debug window: {exc}")
                print_live_cpu_debug(word_map, force=True)
            elif not args.output:
                sys.stdout.buffer.write(data)

        elif args.cpu_info:
            data = send_read(
                port,
                CPU_DEBUG_BASE_ADDR,
                CPU_DEBUG_LEN,
                args.legacy_read_no_ack,
                args.resync_ack,
                args.ack_scan_bytes,
            )
            log(f"[PASS] read {len(data)} bytes from 0x{CPU_DEBUG_BASE_ADDR:08x}")
            print_live_cpu_debug(words_from_data(data, CPU_DEBUG_BASE_ADDR), force=True)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
