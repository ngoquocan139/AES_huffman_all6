#!/usr/bin/env python3
"""Generate hardware-only AES/Huffman throughput and cycle comparison charts."""

from __future__ import annotations

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import textwrap


ROOT = Path(__file__).resolve().parents[1]
OUT_PATH = ROOT / "docs" / "generated_figures" / "hardware_throughput_cycle_comparison.png"

W, H = 2200, 1400


def font(size: int, bold: bool = False):
    name = "arialbd.ttf" if bold else "arial.ttf"
    path = Path("C:/Windows/Fonts") / name
    if path.exists():
        return ImageFont.truetype(str(path), size)
    return ImageFont.load_default()


F_TITLE = font(46, True)
F_SECTION = font(31, True)
F_AXIS = font(24)
F_TICK = font(20)
F_LABEL = font(21, True)
F_NOTE = font(20)
F_LEGEND = font(22)

COL_OUR = "#f28c28"
COL_PAPER = "#3f7fcd"
COL_OFFICIAL = "#7b61ff"
COL_GRID = "#d9dee8"
COL_TEXT = "#111827"


def rgb(h: str):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def center(draw, x, y, text, fnt, fill=COL_TEXT):
    box = draw.textbbox((0, 0), text, font=fnt)
    draw.text((x - (box[2] - box[0]) / 2, y), text, font=fnt, fill=rgb(fill))


def label_lines(label: str):
    return label.split("\n")


def draw_bar_chart(draw, img, box, title, labels, values, colors, ylabel, ymax=None,
                   y_min=0.0, fmt="{:.1f}", log_scale=False):
    x0, y0, x1, y1 = box
    left = x0 + 86
    right = x1 - 36
    top = y0 + 66
    bottom = y1 - 105
    width = right - left
    height = bottom - top
    center(draw, (x0 + x1) // 2, y0 + 10, title, F_SECTION)

    draw.line((left, bottom, right, bottom), fill=rgb("#444444"), width=2)
    draw.line((left, top, left, bottom), fill=rgb("#444444"), width=2)
    if ymax is None:
        ymax = max(values) * 1.18

    if log_scale:
        min_pos = min(v for v in values if v > 0)
        y_min_log = max(0.001, min_pos / 2)
        import math
        log_min = math.log10(y_min_log)
        log_max = math.log10(ymax)
        ticks = [0.01, 0.1, 1, 10, 100, 1000, 10000, 100000]
        ticks = [t for t in ticks if y_min_log <= t <= ymax]
        for t in ticks:
            yy = bottom - (math.log10(t) - log_min) / (log_max - log_min) * height
            draw.line((left, yy, right, yy), fill=rgb(COL_GRID), width=1)
            tick = f"{t:g}"
            tb = draw.textbbox((0, 0), tick, font=F_TICK)
            draw.text((left - 12 - (tb[2] - tb[0]), yy - 12), tick, font=F_TICK, fill=rgb("#444444"))

        def value_to_y(v):
            return bottom - (math.log10(v) - log_min) / (log_max - log_min) * height
    else:
        ticks = 5
        for i in range(ticks + 1):
            yy = bottom - i * height / ticks
            val = y_min + i * (ymax - y_min) / ticks
            draw.line((left, yy, right, yy), fill=rgb(COL_GRID), width=1)
            tick = f"{val:.1f}" if ymax >= 10 else f"{val:.2f}"
            tb = draw.textbbox((0, 0), tick, font=F_TICK)
            draw.text((left - 12 - (tb[2] - tb[0]), yy - 12), tick, font=F_TICK, fill=rgb("#444444"))

        def value_to_y(v):
            return bottom - (v - y_min) / (ymax - y_min) * height

    # rotated y label
    lbl = Image.new("RGBA", (440, 34), (255, 255, 255, 0))
    ld = ImageDraw.Draw(lbl)
    ld.text((0, 0), ylabel, font=F_TICK, fill=rgb(COL_TEXT))
    lbl = lbl.rotate(90, expand=True)
    img.paste(lbl, (x0 + 12, top + (height - lbl.height) // 2), lbl)

    n = len(values)
    slot = width / n
    bar_w = min(80, slot * 0.58)
    for i, (label, value, color) in enumerate(zip(labels, values, colors)):
        cx = left + slot * (i + 0.5)
        by = value_to_y(value)
        draw.rectangle((cx - bar_w / 2, by, cx + bar_w / 2, bottom),
                       fill=rgb(color), outline=rgb("#ffffff"), width=2)
        value_text = fmt.format(value)
        tb = draw.textbbox((0, 0), value_text, font=F_LABEL)
        draw.text((cx - (tb[2] - tb[0]) / 2, by - 27), value_text, font=F_LABEL, fill=rgb(COL_TEXT))
        yy = bottom + 13
        for line in label_lines(label):
            tb = draw.textbbox((0, 0), line, font=F_TICK)
            draw.text((cx - (tb[2] - tb[0]) / 2, yy), line, font=F_TICK, fill=rgb(COL_TEXT))
            yy += 23


def main():
    img = Image.new("RGB", (W, H), "white")
    draw = ImageDraw.Draw(img)

    center(draw, W // 2, 24, "Hardware Baselines: Throughput and Cycle Comparison", F_TITLE)

    aes_labels = [
        "Our\nAES-CBC",
        "Good\nlow-area",
        "Chodowiec\n& Gaj",
        "Rouvroy\net al.",
        "OpenTitan\nAES",
    ]
    aes_cycles = [
        11.0,
        16.0 / ((2.2 / 67.0) / 8.0),
        16.0 / ((166.0 / 60.0) / 8.0),
        16.0 / ((208.0 / 71.0) / 8.0),
        12.0,
    ]
    aes_throughput = [
        (16.0 / 11.0) * 100.0,
        ((2.2 / 67.0) / 8.0) * 100.0,
        ((166.0 / 60.0) / 8.0) * 100.0,
        ((208.0 / 71.0) / 8.0) * 100.0,
        (16.0 / 12.0) * 100.0,
    ]
    aes_colors = [COL_OUR, COL_PAPER, COL_PAPER, COL_PAPER, COL_OFFICIAL]

    huff_labels = [
        "Our TX\nHuffman",
        "ASAP14\nLatencyOpt",
        "ASAP14\nThroughputOpt",
    ]
    huff_cycles = [
        27107.0,
        33770.0,
        3186.0,
    ]
    huff_throughput = [
        (2551.0 / 27107.0) * 100.0,
        (704.0 / 33770.0) * 100.0,
        (704.0 / 3186.0) * 100.0,
    ]
    huff_colors = [COL_OUR, COL_PAPER, COL_PAPER]

    # Top row: AES
    center(draw, W // 2, 90, "AES-128 Hardware", F_SECTION, COL_TEXT)
    draw_bar_chart(draw, img, (75, 135, 1065, 645), "AES Throughput at 100 MHz",
                   aes_labels, aes_throughput, aes_colors, "Throughput (MB/s)",
                   ymax=180, fmt="{:.1f}")
    draw_bar_chart(draw, img, (1145, 135, 2135, 645), "AES Cycles per 128-bit Block",
                   aes_labels, aes_cycles, aes_colors, "Cycles / block",
                   ymax=5000, fmt="{:.0f}", log_scale=True)

    # Bottom row: Huffman
    center(draw, W // 2, 685, "Canonical Huffman Hardware", F_SECTION, COL_TEXT)
    draw_bar_chart(draw, img, (75, 730, 1065, 1240), "Huffman Throughput at 100 MHz",
                   huff_labels, huff_throughput, huff_colors, "Input MB/s",
                   ymax=25, fmt="{:.2f}")
    draw_bar_chart(draw, img, (1145, 730, 2135, 1240), "Huffman Cycle Metric",
                   huff_labels, huff_cycles, huff_colors, "Cycles or II",
                   ymax=50000, fmt="{:.0f}")

    # Legend
    lx, ly = 420, 1265
    for label, color in [
        ("Our Design", COL_OUR),
        ("Research paper / cited hardware design", COL_PAPER),
        ("Official hardware IP/spec", COL_OFFICIAL),
    ]:
        draw.rectangle((lx, ly + 6, lx + 32, ly + 28), fill=rgb(color))
        draw.text((lx + 44, ly), label, font=F_LEGEND, fill=rgb(COL_TEXT))
        lx += 520

    note = (
        "Notes: AES throughput is normalized to 100 MHz. AES cycle chart uses a log scale because the "
        "low-area AES reference is much slower. Huffman comparison uses bytes/cycle normalized to 100 MHz; "
        "ASAP14 reports encoder operation latency/II, while this work reports TX Huffman cycles inside the secure-storage path."
    )
    y = 1315
    for line in textwrap.wrap(note, width=170):
        draw.text((90, y), line, font=F_NOTE, fill=rgb("#475569"))
        y += 25

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT_PATH)
    print(OUT_PATH)


if __name__ == "__main__":
    main()
