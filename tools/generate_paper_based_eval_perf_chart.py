#!/usr/bin/env python3
"""Generate a paper/official-source comparison chart without GitHub baselines."""

from __future__ import annotations

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import math
import textwrap


ROOT = Path(__file__).resolve().parents[1]
OUT_PATH = ROOT / "docs" / "generated_figures" / "paper_based_evaluation_performance_comparison.png"

W, H = 2400, 1500


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    name = "arialbd.ttf" if bold else "arial.ttf"
    path = Path("C:/Windows/Fonts") / name
    if path.exists():
        return ImageFont.truetype(str(path), size)
    return ImageFont.load_default()


F_TITLE = font(44, True)
F_SECTION = font(32, True)
F_AXIS = font(26)
F_TICK = font(21)
F_LABEL = font(22, True)
F_NOTE = font(20)
F_LEGEND = font(22)

COL_OUR = "#f28c28"
COL_PAPER = "#3f7fcd"
COL_OFFICIAL = "#7b61ff"
COL_STD = "#2a9d8f"
COL_WARN = "#d9534f"
COL_GRID = "#d9dee8"
COL_TEXT = "#111827"


def rgb(hex_color: str) -> tuple[int, int, int]:
    h = hex_color.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def draw_text_center(draw: ImageDraw.ImageDraw, xy: tuple[int, int], text: str,
                     fnt: ImageFont.FreeTypeFont, fill: str = COL_TEXT) -> None:
    x, y = xy
    box = draw.textbbox((0, 0), text, font=fnt)
    draw.text((x - (box[2] - box[0]) / 2, y), text, font=fnt, fill=rgb(fill))


def wrap_label(label: str, width: int = 13) -> str:
    return "\n".join(textwrap.wrap(label, width=width, break_long_words=False))


def draw_bar_chart(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], title: str,
                   labels: list[str], values: list[float], colors: list[str],
                   ylabel: str, ymax: float | None = None, fmt: str = "{:.2f}",
                   y_min: float = 0.0, log_scale: bool = False) -> None:
    x0, y0, x1, y1 = box
    left = x0 + (124 if log_scale else 86)
    right = x1 - 28
    top = y0 + 62
    bottom = y1 - 100
    width = right - left
    height = bottom - top

    draw_text_center(draw, ((x0 + x1) // 2, y0 + 8), title, F_AXIS, COL_TEXT)
    draw.line((left, bottom, right, bottom), fill=rgb("#333333"), width=2)
    draw.line((left, top, left, bottom), fill=rgb("#333333"), width=2)

    if ymax is None:
        ymax = max(values) * 1.18 if values else 1.0
    if ymax <= y_min:
        ymax = y_min + 1.0

    if log_scale:
        log_min = math.log10(max(y_min, 0.001))
        log_max = math.log10(ymax)
        ticks = [0.001, 0.01, 0.1, 1, 10, 100, 1000, 10000, 100000]
        for tick in ticks:
            if tick < y_min or tick > ymax:
                continue
            yy = bottom - (math.log10(tick) - log_min) / (log_max - log_min) * height
            draw.line((left, yy, right, yy), fill=rgb(COL_GRID), width=1)
            tick_text = f"{tick:g}"
            box_t = draw.textbbox((0, 0), tick_text, font=F_TICK)
            draw.text((left - 12 - (box_t[2] - box_t[0]), yy - 12), tick_text, font=F_TICK, fill=rgb("#333333"))

        def value_to_y(value: float) -> float:
            return bottom - (math.log10(max(value, y_min)) - log_min) / (log_max - log_min) * height
    else:
        ticks = 5
        for i in range(ticks + 1):
            yy = bottom - i * height / ticks
            val = y_min + i * (ymax - y_min) / ticks
            draw.line((left, yy, right, yy), fill=rgb(COL_GRID), width=1)
            tick_text = f"{val:.1f}" if ymax >= 10 else f"{val:.2f}"
            box_t = draw.textbbox((0, 0), tick_text, font=F_TICK)
            draw.text((left - 12 - (box_t[2] - box_t[0]), yy - 12), tick_text, font=F_TICK, fill=rgb("#333333"))

        def value_to_y(value: float) -> float:
            return bottom - (value - y_min) / (ymax - y_min) * height

    # y-axis label, rotated using a tight image so the title is centered on the axis.
    label_box = draw.textbbox((0, 0), ylabel, font=F_TICK)
    label_w = label_box[2] - label_box[0]
    label_h = label_box[3] - label_box[1]
    label_img = Image.new("RGBA", (label_w + 6, label_h + 6), (255, 255, 255, 0))
    ld = ImageDraw.Draw(label_img)
    ld.text((3, 3), ylabel, font=F_TICK, fill=rgb(COL_TEXT))
    label_img = label_img.rotate(90, expand=True)
    draw._image.paste(label_img, (x0, top + (height - label_img.height) // 2), label_img)

    n = len(values)
    slot = width / n
    bar_w = min(92, slot * 0.62)
    for i, (lab, val, col) in enumerate(zip(labels, values, colors)):
        cx = left + slot * (i + 0.5)
        bx0 = cx - bar_w / 2
        bx1 = cx + bar_w / 2
        by0 = value_to_y(val)
        draw.rectangle((bx0, by0, bx1, bottom), fill=rgb(col), outline=rgb("#ffffff"), width=2)
        value_text = fmt.format(val)
        tb = draw.textbbox((0, 0), value_text, font=F_LABEL)
        draw.text((cx - (tb[2] - tb[0]) / 2, by0 - 28), value_text, font=F_LABEL, fill=rgb(COL_TEXT))

        wrapped = wrap_label(lab, 12)
        lines = wrapped.splitlines()
        yy = bottom + 12
        for line in lines:
            lb = draw.textbbox((0, 0), line, font=F_TICK)
            draw.text((cx - (lb[2] - lb[0]) / 2, yy), line, font=F_TICK, fill=rgb(COL_TEXT))
            yy += 24


def draw_legend(draw: ImageDraw.ImageDraw, items: list[tuple[str, str]], x: int, y: int) -> None:
    xx = x
    yy = y
    for label, col in items:
        draw.rectangle((xx, yy + 5, xx + 28, yy + 25), fill=rgb(col))
        draw.text((xx + 38, yy), label, font=F_LEGEND, fill=rgb(COL_TEXT))
        xx += 520
        if xx > W - 520:
            xx = x
            yy += 34


def main() -> None:
    img = Image.new("RGB", (W, H), "white")
    draw = ImageDraw.Draw(img)
    draw._image = img

    draw_text_center(draw, (W // 2, 28), "Evaluation and Performance Comparison", F_TITLE)
    draw_text_center(draw, (W // 2, 92), "Hardware Baselines", F_SECTION)

    # AES values derived from reported throughput/frequency in Good and Benaissa CHES 2005
    # and from the local AES core cycle count.
    aes_labels = [
        "Ours",
        "Good\nlow",
        "C&G",
        "Rouv.",
        "OT",
    ]
    aes_eff_values = [
        16.0 / 11.0,
        (2.2 / 67.0) / 8.0,
        (166.0 / 60.0) / 8.0,
        (208.0 / 71.0) / 8.0,
        16.0 / 12.0,
    ]
    aes_colors = [COL_OUR, COL_PAPER, COL_PAPER, COL_PAPER, COL_OFFICIAL]

    aes100_values = [v * 100.0 for v in aes_eff_values]
    draw_bar_chart(
        draw,
        (55, 145, 620, 610),
        "AES Throughput at 100 MHz",
        aes_labels,
        aes100_values,
        aes_colors,
        "Throughput (MB/s)",
        ymax=180.0,
        fmt="{:.1f}",
    )

    draw_bar_chart(
        draw,
        (650, 145, 1215, 610),
        "AES Efficiency",
        aes_labels,
        aes_eff_values,
        aes_colors,
        "Bytes/cycle",
        ymax=1.75,
        fmt="{:.3f}",
    )

    huff_hw_labels = [
        "Ours",
        "ASAP14-L",
        "ASAP14-T",
        "Gug25",
    ]
    huff_eff_values = [
        2551.0 / 27107.0,
        704.0 / 33770.0,
        704.0 / 3186.0,
    ]
    huff100_values = [v * 100.0 for v in huff_eff_values] + [144000.0]
    draw_bar_chart(
        draw,
        (1245, 145, 1810, 610),
        "Huffman Throughput",
        huff_hw_labels,
        huff100_values,
        [COL_OUR, COL_PAPER, COL_PAPER, COL_PAPER],
        "Input MB/s",
        y_min=0.1,
        ymax=200000.0,
        fmt="{:.1f}",
        log_scale=True,
    )
    draw_bar_chart(
        draw,
        (1840, 145, 2350, 610),
        "Huffman Efficiency",
        huff_hw_labels,
        huff_eff_values,
        [COL_OUR, COL_PAPER, COL_PAPER],
        "Bytes/cycle",
        ymax=0.25,
        fmt="{:.3f}",
    )

    draw_text_center(draw, (W // 2, 650), "Software and Paper Baselines", F_SECTION)

    throughput_labels = [
        "Our Design\nTX",
        "FGCS20\nC+E",
    ]
    # Hameed paper: 36,000 bytes / 6.5747 s = 0.00548 MB/s.
    throughput_values = [
        4.531,
        36000.0 / 1_000_000.0 / 6.5747,
    ]
    draw_bar_chart(
        draw,
        (70, 700, 760, 1195),
        "Compression + Encryption Input Throughput",
        throughput_labels,
        throughput_values,
        [COL_OUR, COL_WARN],
        "Input MB/s",
        ymax=5.0,
        fmt="{:.4f}",
    )

    payload_labels = [
        "Ours",
        "IJETT24\nECG",
        "zlib-9",
        "bz2-9",
        "lzma-6",
    ]
    payload_values = [
        44.28,
        42.0,
        41.16210666518675,
        42.88806260058827,
        44.991397968810695,
    ]
    draw_bar_chart(
        draw,
        (845, 700, 1580, 1195),
        "Payload Saving on 18,019 Preprocessed ECG Bytes",
        payload_labels,
        payload_values,
        [COL_OUR, COL_WARN, COL_STD, COL_STD, COL_STD],
        "Saving (%)",
        y_min=38.0,
        ymax=46.5,
        fmt="{:.2f}%",
    )

    saving_labels = [
        "Ours",
        "FGCS20\npaper",
        "zlib-9",
        "bz2-9",
        "lzma-6",
    ]
    saving_values = [
        70.13,
        64.985,
        (1.0 - 10602.0 / 36000.0) * 100.0,
        (1.0 - 10291.0 / 36000.0) * 100.0,
        (1.0 - 9912.0 / 36000.0) * 100.0,
    ]
    draw_bar_chart(
        draw,
        (1660, 700, 2330, 1195),
        "Saved vs 36,000 Raw ECG Bytes",
        saving_labels,
        saving_values,
        [COL_OUR, COL_WARN, COL_STD, COL_STD, COL_STD],
        "Saving (%)",
        y_min=62.0,
        ymax=74.0,
        fmt="{:.2f}%",
    )

    draw_legend(
        draw,
        [
            ("Our Design (local)", COL_OUR),
            ("Hardware papers [1][3][4]", COL_PAPER),
            ("Official AES IP [2]", COL_OFFICIAL),
            ("Standard compressors (local)", COL_STD),
            ("ECG papers [5][6]", COL_WARN),
        ],
        280,
        1240,
    )

    foot = (
        "References: [1] Good & Benaissa, CHES 2005. [2] OpenTitan AES HWIP. "
        "[3] Matai et al., ASAP 2014. [4] Guguloth et al., Results in Engineering, 2025. "
        "[5] Hameed et al., FGCS 2020. [6] Zarate Segura et al., IJETT 2024. "
        "Note: Throughput is normalized to 100 MHz where possible; efficiency is reported as bytes/cycle. "
        "FPGA/platform and input size differ across references."
    )
    yy = 1360
    for line in textwrap.wrap(foot, width=185):
        draw.text((95, yy), line, font=F_NOTE, fill=rgb("#3b4454"))
        yy += 25

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT_PATH)
    print(OUT_PATH)


if __name__ == "__main__":
    main()
