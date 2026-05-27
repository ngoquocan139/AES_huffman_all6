#!/usr/bin/env python3
"""UART host utility for the FPGA DMEM loader/readback protocol."""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path


ACK_OK = 0x79
ACK_ERR = 0x1F


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


def expect_ack(port, action: str) -> None:
    ack = read_exact(port, 1)[0]
    if ack == ACK_OK:
        return
    if ack == ACK_ERR:
        raise RuntimeError(f"FPGA rejected {action}: ACK_ERR 0x1f")
    raise RuntimeError(f"Unexpected ACK for {action}: 0x{ack:02x}")


def send_load(port, payload: bytes) -> None:
    if not payload:
        raise ValueError("LOAD payload must not be empty")
    frame = b"LOAD" + len(payload).to_bytes(4, "little") + payload
    port.write(frame)
    port.flush()
    expect_ack(port, "LOAD")


def send_read(port, addr: int, length: int) -> bytes:
    if addr < 0 or addr > 0xFFFFFFFF:
        raise ValueError("READ address is out of 32-bit range")
    if length <= 0 or length > 0xFFFFFFFF:
        raise ValueError("READ length must be positive")
    frame = b"READ" + addr.to_bytes(4, "little") + length.to_bytes(4, "little")
    port.write(frame)
    port.flush()
    expect_ack(port, "READ")
    return read_exact(port, length)


def print_words(data: bytes, base_addr: int) -> None:
    for offset in range(0, len(data), 4):
        chunk = data[offset : offset + 4]
        if len(chunk) < 4:
            chunk = chunk + bytes(4 - len(chunk))
        word = int.from_bytes(chunk, "little")
        print(f"0x{base_addr + offset:08x}: 0x{word:08x}")


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
    parser.add_argument("--post-load-delay", type=float, default=0.0)
    args = parser.parse_args()

    if not args.input and not args.read:
        parser.error("nothing to do: pass --input and/or --read ADDR LEN")

    serial = require_pyserial()

    with serial.Serial(args.port, args.baud, timeout=args.timeout, write_timeout=args.timeout) as port:
        # Drop stale bytes from previous attempts before starting a new frame.
        port.reset_input_buffer()
        port.reset_output_buffer()

        if args.input:
            payload = Path(args.input).read_bytes()
            send_load(port, payload)
            log(f"[PASS] loaded {len(payload)} bytes from {args.input}")
            if args.post_load_delay > 0.0:
                time.sleep(args.post_load_delay)

        if args.read:
            addr = parse_int(args.read[0])
            length = parse_int(args.read[1])
            data = send_read(port, addr, length)
            log(f"[PASS] read {len(data)} bytes from 0x{addr:08x}")
            if args.output:
                Path(args.output).write_bytes(data)
                log(f"[PASS] wrote {args.output}")
            if args.words:
                print_words(data, addr)
            elif not args.output:
                sys.stdout.buffer.write(data)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
