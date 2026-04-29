#!/usr/bin/env python3
from __future__ import annotations

import struct
import sys
from pathlib import Path

MAGIC_LPR1 = 0x3152504C
RECORD_SIZE_BYTES = 20
HEADER_SIZE_BYTES = 24

FLAG_ABSOLUTE_TS = 0x0001
FLAG_USER_PRESENT = 0x0002
FLAG_CARD_PRESENT = 0x0004
FLAG_SYSTEM_ACTOR = 0x0008

DEVICE_TABLE = {
    "CTRL-01": 0x01,
    "CTRL-02": 0x02,
    "DOOR-A1": 0x03,
    "DOOR-A2": 0x04,
    "GATE-01": 0x05,
    "GATE-02": 0x06,
    "DOOR-B1": 0x07,
}

ZONE_TABLE = {
    "LOBBY": 0x01,
    "WAREHOUSE": 0x02,
    "OFFICE_3F": 0x03,
    "PARKING": 0x04,
    "SERVER_ROOM": 0x05,
    "LAB_A": 0x06,
    "LAB_B": 0x07,
}

EVENT_TABLE = {
    "ACCESS_DENIED": 0x01,
    "ACCESS_GRANTED": 0x02,
    "ACCESS_REQUEST": 0x03,
    "STATUS_UPDATE": 0x04,
    "HEARTBEAT": 0x05,
    "DOOR_OPEN": 0x06,
    "DOOR_CLOSE": 0x07,
    "MOTION_DETECTED": 0x08,
}

RESULT_TABLE = {
    "DENIED": 0x01,
    "GRANTED": 0x02,
    "OK": 0x03,
    "NORMAL": 0x04,
    "SUCCESS": 0x05,
}

REASON_TABLE = {
    "USER_UNAUTHORIZED": 0x01,
    "USER_AUTHORIZED": 0x02,
    "PIN_OK": 0x03,
    "CARD_OK": 0x04,
    "SCHEDULE_OK": 0x05,
    "POWER_OK": 0x06,
    "LOW_BATTERY": 0x07,
    "NETWORK_RESTORED": 0x08,
    "CARD_EXPIRED": 0x09,
    "FORCED_ENTRY": 0x0A,
    "NETWORK_LOST": 0x0B,
}


def parse_seconds_of_day(timestamp: str) -> int:
    hh = int(timestamp[11:13])
    mm = int(timestamp[14:16])
    ss = int(timestamp[17:19])
    return hh * 3600 + mm * 60 + ss


def parse_line(line: str, prev_seconds: int | None) -> tuple[bytes, int]:
    parts = [part.strip() for part in line.split("|")]
    if len(parts) != 10:
        raise ValueError(f"expected 10 fields, got {len(parts)}: {line}")

    timestamp, device, zone, event, actor, card, result, reason, retry, crc = parts
    seconds = parse_seconds_of_day(timestamp)

    if prev_seconds is None:
        delta_seconds = 0
        flags = FLAG_ABSOLUTE_TS
    else:
        delta_seconds = seconds - prev_seconds
        flags = 0

    if actor == "SYSTEM":
        user_num = 0
        flags |= FLAG_SYSTEM_ACTOR
    elif actor.startswith("U"):
        user_num = int(actor[1:])
        flags |= FLAG_USER_PRESENT
    else:
        user_num = 0

    if card == "NA":
        card_num = 0
    elif card.startswith("CARD"):
        card_num = int(card[4:])
        flags |= FLAG_CARD_PRESENT
    else:
        card_num = 0

    retry_value = int(retry.split("=", 1)[1])
    crc_value = int(crc.split("=", 1)[1], 16)

    record = struct.pack(
        "<IBBBBBBHHIH",
        delta_seconds,
        DEVICE_TABLE[device],
        ZONE_TABLE[zone],
        EVENT_TABLE[event],
        RESULT_TABLE[result],
        REASON_TABLE[reason],
        retry_value,
        flags,
        user_num,
        card_num,
        crc_value,
    )
    return record, seconds


def build_blob(lines: list[str]) -> bytes:
    records: list[bytes] = []
    prev_seconds: int | None = None
    base_seconds = 0

    for line in lines:
        if not line.strip():
            continue
        record, seconds = parse_line(line, prev_seconds)
        if prev_seconds is None:
            base_seconds = seconds
        prev_seconds = seconds
        records.append(record)

    header = struct.pack(
        "<IIIIII",
        MAGIC_LPR1,
        len(records),
        RECORD_SIZE_BYTES,
        base_seconds,
        1,
        0,
    )
    return header + b"".join(records)


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: log_preprocess_host.py <input.txt> <output.bin>", file=sys.stderr)
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
