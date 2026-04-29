#!/usr/bin/env python3
from __future__ import annotations

import struct
import sys
from pathlib import Path

MAGIC_SPH1 = 0x31485053
RECORD_SIZE_BYTES = 20
HEADER_SIZE_BYTES = 16


def parse_line(line: str) -> bytes:
    parts = [part.strip() for part in line.split(",")]
    if len(parts) != 11:
        raise ValueError(f"expected 11 fields, got {len(parts)}: {line}")

    delta_ms = int(parts[0])
    patient_id = int(parts[1])
    encounter_id = int(parts[2])
    device_id = int(parts[3])
    bed_id = int(parts[4])
    red = int(parts[5])
    ir = int(parts[6])
    spo2_x10 = int(parts[7])
    hr = int(parts[8])
    rr = int(parts[9])
    alert_flags = int(parts[10])

    return struct.pack(
        "<HHIBBHHHBBH",
        delta_ms,
        patient_id,
        encounter_id,
        device_id,
        bed_id,
        red,
        ir,
        spo2_x10,
        hr,
        rr,
        alert_flags,
    )


def build_blob(lines: list[str]) -> bytes:
    records = [parse_line(line) for line in lines if line.strip()]
    header = struct.pack(
        "<IIII",
        MAGIC_SPH1,
        len(records),
        RECORD_SIZE_BYTES,
        0,
    )
    return header + b"".join(records)


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: sensor_phi_preprocess_host.py <input.txt> <output.bin>", file=sys.stderr)
        return 1

    input_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2])
    lines = input_path.read_text(encoding="utf-8").splitlines()
    blob = build_blob(lines)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(blob)
    print(f"Wrote {len(blob)} byte(s) to {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
