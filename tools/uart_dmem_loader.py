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
CPU_DEBUG_LEN = 64
CPU_DEBUG_SIGNATURE = 0x31555043
CPU_RESET_PC = 0x00000000
CPU_STACK_POINTER_INIT = 0x00007F00


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
        print("  firmware_flow  : secure_write(file_id=1), secure_write(file_id=3), secure_read(selected file)")
        print("  dma_jobs       : 3 (TX file1, TX file3, RX selected file)")
        print(f"  cpu_poll_loops : TX1={words[6]}, RX_selected={words[11]}, visible_total={words[6] + words[11]}")
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
        print("note            : poll_count is firmware polling loops, not true hardware cycles.")
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
        print("note            : poll_count is firmware polling loops, not true hardware cycles.")
    elif signature == SIG_STORAGE:
        input1_len = input_len
        tx1_cipher_bytes = words[5]
        rx_plain_bytes = words[9]
        print("firmware        : test_mmio_dma_storage_table.c, secure storage API")
        print(f"input1_len      : {input1_len if input1_len is not None else 'unknown'} bytes")
        print(f"input2_len      : {input2_len if input2_len is not None else words[13]} bytes")
        print("")
        print("TX record 1")
        print(f"  status_before : {status_text(words[2])}")
        print(f"  status_after  : {status_text(words[3])}")
        print(f"  tx_bytes_done : {words[4]} bytes")
        print(f"  ciphertext    : {tx1_cipher_bytes} bytes")
        print(f"  poll_count    : {words[6]} CPU polling loops")
        print("")
        print("RX selected record")
        print(f"  status_before : {status_text(words[7])}")
        print(f"  status_after  : {status_text(words[8])}")
        print(f"  plaintext     : {rx_plain_bytes} bytes")
        print(f"  debug         : 0x{words[10]:08x}")
        print(f"  poll_count    : {words[11]} CPU polling loops")
        print("")
        print("Storage metadata")
        print(f"  tx2_ciphertext: {words[12]} bytes")
        print(f"  selected_file : {words[14]}")
        print(f"  total_records : {words[15]}")
        if input1_len is not None:
            print(f"  storage_ratio : {pct(tx1_cipher_bytes, input1_len)}")
            print(f"  space_saving  : {pct(input1_len - tx1_cipher_bytes, input1_len)}")
            print(f"  rx_len_match  : {'YES' if rx_plain_bytes == input1_len else 'NO'}")
        print("note            : poll_count is firmware polling loops, not true hardware cycles.")
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

    if not args.input and not args.read and not args.cpu_info:
        parser.error("nothing to do: pass --input, --read ADDR LEN, and/or --cpu-info")

    serial = require_pyserial()

    with serial.Serial(args.port, args.baud, timeout=args.timeout, write_timeout=args.timeout) as port:
        # Drop stale bytes from previous attempts before starting a new frame.
        port.reset_input_buffer()
        port.reset_output_buffer()

        if args.input:
            payload = Path(args.input).read_bytes()
            send_load(port, payload, args.resync_ack, args.ack_scan_bytes)
            log(f"[PASS] loaded {len(payload)} bytes from {args.input}")
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
