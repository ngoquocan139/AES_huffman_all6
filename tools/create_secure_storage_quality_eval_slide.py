from pathlib import Path
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "docs" / "generated_figures"
OUT_DIR.mkdir(parents=True, exist_ok=True)

W, H = 1920, 1080

BG = "#F7FAFF"
BLUE = "#0068D9"
BLUE_DARK = "#003B91"
CYAN = "#5FE8F2"
CYAN_DARK = "#10A6C8"
TEXT = "#132033"
MUTED = "#66758A"
GRID = "#B9C9E6"
WHITE = "#FFFFFF"
BLACK = "#151A20"
GREEN = "#099A82"
RED = "#C93648"
ORANGE = "#F28C28"
LIGHT_BLUE = "#EAF2FF"

FONT_DIR = Path("C:/Windows/Fonts")
FONT_REG = FONT_DIR / "arial.ttf"
FONT_BOLD = FONT_DIR / "arialbd.ttf"
FONT_MONO = FONT_DIR / "consola.ttf"
FONT_MONO_BOLD = FONT_DIR / "consolab.ttf"


def font(size, bold=False, mono=False):
    if mono:
        path = FONT_MONO_BOLD if bold and FONT_MONO_BOLD.exists() else FONT_MONO
    else:
        path = FONT_BOLD if bold else FONT_REG
    return ImageFont.truetype(str(path), size)


F_LOGO = font(24, bold=True)
F_UNI = font(22, bold=True)
F_UNI_SMALL = font(16)
F_BAND = font(36, bold=True)
F_TITLE = font(38, bold=True)
F_BODY = font(25)
F_BODY_B = font(25, bold=True)
F_HEAD = font(19, bold=True)
F_CELL = font(16)
F_CELL_B = font(16, bold=True)
F_FOOT = font(16)
F_FOOT_B = font(18, bold=True)
F_MONO = font(21, mono=True)
F_MONO_B = font(22, bold=True, mono=True)


def text_center(draw, box, text, fnt, fill=TEXT, spacing=4):
    x0, y0, x1, y1 = box
    lines = text.split("\n")
    dims = [draw.textbbox((0, 0), line, font=fnt) for line in lines]
    widths = [bb[2] - bb[0] for bb in dims]
    heights = [bb[3] - bb[1] for bb in dims]
    total_h = sum(heights) + spacing * (len(lines) - 1)
    y = y0 + (y1 - y0 - total_h) / 2 - 1
    for line, w, h in zip(lines, widths, heights):
        draw.text((x0 + (x1 - x0 - w) / 2, y), line, font=fnt, fill=fill)
        y += h + spacing


def text_left(draw, xy, text, fnt, fill=TEXT, spacing=7):
    x, y = xy
    for line in text.split("\n"):
        draw.text((x, y), line, font=fnt, fill=fill)
        bb = draw.textbbox((0, 0), line, font=fnt)
        y += (bb[3] - bb[1]) + spacing


def rounded(draw, xy, r, fill, outline=None, width=1):
    draw.rounded_rectangle(xy, radius=r, fill=fill, outline=outline, width=width)


def draw_header(draw):
    # simple HCMUTE-like header without depending on external logo assets
    cx, cy, rr = 105, 72, 38
    draw.ellipse((cx - rr, cy - rr, cx + rr, cy + rr), fill=WHITE, outline=BLUE, width=5)
    draw.line((cx, cy - 25, cx, cy + 25), fill=RED, width=4)
    draw.arc((cx - 22, cy - 22, cx + 22, cy + 22), 35, 325, fill=BLUE, width=4)
    draw.text((cx - 31, cy + 45), "HCMUTE", font=font(14, bold=True), fill=BLUE_DARK)

    draw.text((165, 38), "HO CHI MINH CITY UNIVERSITY OF TECHNOLOGY", font=F_UNI, fill=BLUE_DARK)
    draw.text((165, 68), "AND EDUCATION", font=F_UNI, fill=BLUE_DARK)
    draw.text((165, 100), "HCMC University of Technology and Education", font=F_UNI_SMALL, fill=MUTED)

    # Decorative corner curve
    draw.arc((1660, -95, 1985, 225), 105, 250, fill=BLUE, width=8)
    draw.arc((1715, -40, 1930, 175), 105, 250, fill=CYAN_DARK, width=6)


def draw_arrow_band(draw):
    x, y, h = 45, 155, 70
    w = 890
    pts = [(x, y), (x + w, y), (x + w + 55, y + h // 2), (x + w, y + h), (x, y + h)]
    draw.polygon(pts, fill="#C9FAFF", outline=CYAN_DARK)
    draw.line((x, y, x + w, y), fill=CYAN_DARK, width=3)
    draw.line((x, y + h, x + w, y + h), fill=CYAN_DARK, width=3)
    draw.text((65, 172), "DESIGN QUALITY EVALUATION", font=F_BAND, fill=BLUE_DARK)


def draw_log_box(draw):
    draw.text((85, 265), "Performance Evaluation", font=F_TITLE, fill=TEXT)
    draw.text((85, 328), "Direct RTL/FPGA verification on ECG secure-storage workload", font=F_BODY, fill=TEXT)

    x0, y0, x1, y1 = 85, 395, 760, 705
    rounded(draw, (x0, y0, x1, y1), 8, BLACK, "#353D48", 2)
    draw.rectangle((x0, y0, x1, y0 + 42), fill="#11161D")
    draw.text((x0 + 22, y0 + 11), "[Secure-storage SoC Run Statistics]", font=F_MONO_B, fill=WHITE)

    lines = [
        ("Target FPGA", "ZCU102 / xczu9eg"),
        ("SoC clock", "50 MHz demo clock"),
        ("Dataset", "MIT-BIH ECG, 5 records"),
        ("Secure mode", "Huffman + AES-128-CBC"),
        ("Avg input", "3603.8 bytes / record"),
        ("Avg stored", "2150.4 bytes / record"),
        ("Final ratio", "29.87 %"),
        ("Space saving", "70.13 %"),
        ("Correctness", "100 % byte match"),
        ("Mismatch", "0"),
    ]
    y = y0 + 62
    for k, v in lines:
        draw.text((x0 + 26, y), f"{k:<16}: ", font=F_MONO, fill="#D7E2EF")
        draw.text((x0 + 265, y), v, font=F_MONO, fill="#8CF7CB" if k in ("Precision", "Mismatch") else "#F4F8FF")
        y += 24

    # small stat cards
    cards = [
        ("29.87%", "final ratio"),
        ("70.13%", "raw ECG saving"),
        ("100%", "byte match"),
    ]
    cx = 85
    for value, label in cards:
        rounded(draw, (cx, 745, cx + 205, 835), 10, WHITE, GRID, 2)
        text_center(draw, (cx, 752, cx + 205, 790), value, font(31, bold=True), BLUE_DARK)
        text_center(draw, (cx, 790, cx + 205, 830), label, font(18, bold=True), MUTED)
        cx += 235

    # Comparison input summary.
    px0, py0, px1, py1 = 85, 850, 760, 972
    rounded(draw, (px0, py0, px1, py1), 8, WHITE, GRID, 2)
    draw.text((px0 + 20, py0 + 12), "Comparison input set:", font=F_FOOT_B, fill=BLUE_DARK)
    draw.text((px0 + 20, py0 + 36), "MIT-BIH records: 100, 106, 112, 117, 213", font=F_FOOT, fill=TEXT)
    draw.text((px0 + 20, py0 + 58), "Raw reference: 7200 B/record = 3600 samples x 2 B", font=F_FOOT, fill=TEXT)
    draw.text((px0 + 20, py0 + 80), "SoC input avg 3603.8 B; stored avg 2150.4 B", font=F_FOOT, fill=TEXT)
    draw.text((px0 + 20, py0 + 102), "Paper platform: MATLAB 2018a, Win7 64-bit, i5 2nd Gen, 8 GB RAM", font=font(15), fill=MUTED)


def draw_comparison_table(draw):
    draw.text((820, 300), "Comparison with ECG Huffman + CBC-AES Paper", font=F_BODY_B, fill=TEXT)

    x0, y0 = 820, 342
    col_w = [230, 275, 250, 130, 210]
    row_h = [48] + [42] * 10
    table_w = sum(col_w)
    table_h = sum(row_h)

    draw.rectangle((x0, y0, x0 + table_w, y0 + table_h), fill=WHITE, outline=GRID, width=2)
    draw.rectangle((x0, y0, x0 + table_w, y0 + row_h[0]), fill=LIGHT_BLUE, outline=GRID)

    xs = [x0]
    for w in col_w:
        xs.append(xs[-1] + w)
    for x in xs:
        draw.line((x, y0, x, y0 + table_h), fill=GRID, width=2)

    heads = ["Metric", "ECG CBC-AES Paper [1]", "This Work", "Correctness", "Improvement (%)"]
    for i, head in enumerate(heads):
        text_center(draw, (xs[i], y0, xs[i + 1], y0 + row_h[0]), head, F_HEAD, BLUE_DARK)

    rows = [
        ("Compression\nratio", "35.015%", "29.87%", "100%", "+14.69%"),
        ("Space\nsaving", "64.985%", "70.13%", "100%", "+7.92%"),
        ("PRD / byte\nmatch", "0.411", "0 mismatch\nbyte-exact RX", "100%", "0%"),
        ("Compression\ntime", "~3.8641 s", "1.056 ms\nTX comp-only", "100%", "+99.97%"),
        ("Decompression\ntime", "~0.5818 s", "0.483 ms\nRX Huffman", "100%", "+99.92%"),
        ("Encryption\ntime", "~2.7106 s", "29.6 us\nTX AES", "100%", "+99.999%"),
        ("Decryption\ntime", "~3.0449 s", "69.2 us\nRX AES", "100%", "+99.998%"),
        ("Compression +\nencryption", "~6.5747 s", "1.065 ms\nTX path", "100%", "+99.98%"),
        ("TX/RX cycles", "N/R", "53233 TX\n24222 RX", "100%", "0%"),
        ("TX/RX throughput", "N/R", "6.828 MB/s TX-in\n15.072 MB/s RX-out", "100%", "0%"),
    ]

    y = y0 + row_h[0]
    for idx, row in enumerate(rows):
        fill = "#FFFFFF" if idx % 2 == 0 else "#F3F7FF"
        draw.rectangle((x0, y, x0 + table_w, y + row_h[idx + 1]), fill=fill)
        draw.line((x0, y, x0 + table_w, y), fill=GRID, width=2)
        for i, val in enumerate(row):
            fnt = font(15, bold=(i in (3, 4)))
            color = GREEN if i in (3, 4) and val not in ("-", "0%") else TEXT
            text_center(draw, (xs[i] + 8, y, xs[i + 1] - 8, y + row_h[idx + 1]), val, fnt, color, spacing=2)
        y += row_h[idx + 1]
    draw.line((x0, y, x0 + table_w, y), fill=GRID, width=2)

    # Source note
    sx, sy = 820, y0 + table_h + 14
    rounded(draw, (sx, sy, sx + table_w, sy + 128), 8, WHITE, GRID, 2)
    draw.text((sx + 25, sy + 18), "Source:", font=F_CELL_B, fill=BLUE_DARK)
    src = (
        "[1] A lossless compression and encryption mechanism for remote monitoring of ECG data\n"
        "    using Huffman coding and CBC-AES, FGCS 2019; simulated in MATLAB 2018a on Windows 7,\n"
        "    i5 2nd Gen, 8 GB RAM. N/R = not reported.\n"
        "Note: ML precision is TP/(TP+FP); this slide uses byte-match correctness = matched bytes/total bytes.\n"
        "RTL timing is measured from perf counters at 50 MHz on the five MIT-BIH records."
    )
    text_left(draw, (sx + 125, sy + 16), src, F_FOOT, TEXT, spacing=5)


def draw_footer(draw):
    draw.rounded_rectangle((50, 1000, 1780, 1060), radius=14, fill=BLUE, outline=BLUE_DARK, width=2)
    draw.rectangle((1780, 1000, 1870, 1060), fill="#F22D3A")
    draw.text((75, 1017), "Application target: embedded secure data storage with compression, encryption, and byte-exact readback.", font=font(25, bold=True), fill=WHITE)


def main():
    img = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(img)
    draw_header(draw)
    draw_arrow_band(draw)
    draw_log_box(draw)
    draw_comparison_table(draw)
    draw_footer(draw)
    out = OUT_DIR / "secure_storage_ecg_paper_comparison_slide.png"
    img.save(out, quality=95)
    print(out)


if __name__ == "__main__":
    main()
