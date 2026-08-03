from pathlib import Path
from PIL import Image, ImageDraw, ImageFont


OUT_DIR = Path("docs/generated_figures")
OUT_DIR.mkdir(parents=True, exist_ok=True)
OUT_PATH = OUT_DIR / "area_resource_comparison_table_compact.png"

W, H = 1920, 1080
BG = "#F7FAFF"
BLUE = "#063A9B"
BLUE2 = "#0C55B8"
CYAN = "#BFEFFF"
WHITE = "#FFFFFF"
GRID = "#9DB5D3"
TEXT = "#102033"
MUTED = "#4B5D78"
RED = "#C83349"
GREEN = "#0B8A59"
ORANGE = "#F28C28"


def font(size, bold=False):
    paths = [
        "C:/Windows/Fonts/arialbd.ttf" if bold else "C:/Windows/Fonts/arial.ttf",
        "C:/Windows/Fonts/calibrib.ttf" if bold else "C:/Windows/Fonts/calibri.ttf",
    ]
    for p in paths:
        if Path(p).exists():
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


F_TITLE = font(38, True)
F_SUB = font(24, False)
F_HEAD = font(25, True)
F_CELL = font(25, False)
F_CELL_B = font(25, True)
F_SMALL = font(18, False)
F_NOTE = font(20, False)


def centered(draw, box, text, fnt, fill=TEXT):
    x0, y0, x1, y1 = box
    lines = str(text).split("\n")
    line_h = int(fnt.size * 1.13)
    total_h = line_h * len(lines)
    y = y0 + (y1 - y0 - total_h) / 2
    for line in lines:
        bb = draw.textbbox((0, 0), line, font=fnt)
        x = x0 + (x1 - x0 - (bb[2] - bb[0])) / 2
        draw.text((x, y), line, font=fnt, fill=fill)
        y += line_h


def wrapped(draw, xy, text, fnt, fill=TEXT, max_width=1700):
    x, y = xy
    words = text.split()
    line = ""
    for word in words:
        test = word if not line else line + " " + word
        if draw.textbbox((0, 0), test, font=fnt)[2] <= max_width:
            line = test
        else:
            draw.text((x, y), line, font=fnt, fill=fill)
            y += int(fnt.size * 1.2)
            line = word
    if line:
        draw.text((x, y), line, font=fnt, fill=fill)


rows = [
    ["LUT", "274K", "35.4K", "37.1K", "13.5%", "5% higher"],
    ["FF / REG", "548K", "31.8K", "19.8K", "3.6%", "38% lower"],
    ["BRAM", "912", "73", "11", "1.2%", "85% lower"],
    ["DSP", "2,520", "N/R", "0", "0%", "No DSP"],
]

img = Image.new("RGB", (W, H), BG)
draw = ImageDraw.Draw(img)

# Simple slide-like header
draw.rectangle((0, 0, W, 92), fill=WHITE)
draw.polygon([(42, 28), (690, 28), (735, 64), (690, 100), (42, 100)], fill=CYAN, outline=BLUE2)
draw.text((64, 43), "HARDWARE RESOURCE EVALUATION", font=F_TITLE, fill=BLUE)
draw.text((76, 112), "Area/resource comparison on ZCU102 PL", font=F_SUB, fill=MUTED)

# Main table title
draw.text((650, 155), "Hardware Resource Comparison", font=font(34, True), fill=BLUE)

left, top = 190, 220
table_w = 1540
head_h = 78
row_h = 92
cols = [
    ("Resource", 210),
    ("ZCU102\navailable [1]", 245),
    ("Reference HW\nused [2]", 285),
    ("This design\nused", 270),
    ("This design\nratio", 230),
    ("Compare\nvs [2]", 300),
]

scale = table_w / sum(w for _, w in cols)
cols = [(h, int(w * scale)) for h, w in cols]
cols[-1] = (cols[-1][0], table_w - sum(w for _, w in cols[:-1]))

# Header
x = left
draw.rectangle((left, top, left + table_w, top + head_h), fill=BLUE)
for label, cw in cols:
    draw.rectangle((x, top, x + cw, top + head_h), outline=WHITE, width=2)
    centered(draw, (x, top, x + cw, top + head_h), label, F_HEAD, WHITE)
    x += cw

# Body
y = top + head_h
for ri, row in enumerate(rows):
    fill = WHITE if ri % 2 == 0 else "#E9F2FF"
    x = left
    draw.rectangle((left, y, left + table_w, y + row_h), fill=fill, outline=GRID, width=2)
    for ci, (val, (_, cw)) in enumerate(zip(row, cols)):
        draw.rectangle((x, y, x + cw, y + row_h), outline=GRID, width=2)
        fnt = F_CELL_B if ci in (0, 5) else F_CELL
        color = RED if ci == 5 and "higher" in val else (GREEN if ci == 5 and "lower" in val else (BLUE if ci == 5 else TEXT))
        centered(draw, (x + 8, y, x + cw - 8, y + row_h), val, fnt, color)
        x += cw
    y += row_h

# Interpretation strip
strip_y = y + 45
draw.rounded_rectangle((190, strip_y, 1730, strip_y + 92), radius=12, fill=WHITE, outline=BLUE2, width=3)
draw.text((230, strip_y + 28), "Summary:", font=F_CELL_B, fill=BLUE)
draw.text(
    (360, strip_y + 30),
    "Comparable LUT, lower FF/BRAM; area is mainly from RX Huffman decode and TX/RX datapaths.",
    font=F_CELL,
    fill=TEXT,
)

# References box
ref_y = strip_y + 135
draw.rounded_rectangle((190, ref_y, 1730, ref_y + 135), radius=10, fill="#F1F6FF", outline=GRID, width=2)
draw.text((220, ref_y + 18), "References:", font=F_CELL_B, fill=BLUE)
wrapped(
    draw,
    (220, ref_y + 55),
    "[1] AMD Zynq UltraScale+ MPSoC Product Selection Guide, ZU9EG PL resources.  "
    "[2] AMD Vitis Data Compression Library 2022.1, GZip Compress resource utilization.",
    F_NOTE,
    fill=MUTED,
    max_width=1460,
)

# Small caveat
draw.text(
    (220, ref_y + 105),
    "N/R = not reported. Reference HW is not the same workload; values are used only as an area baseline.",
    font=F_SMALL,
    fill=RED,
)

img.save(OUT_PATH)
print(OUT_PATH.resolve())
