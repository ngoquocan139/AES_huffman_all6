from pathlib import Path
import re
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / "vivado/build/rv32_soc_synth_full_zcu102/reports/post_impl_utilization_hier.rpt"
OUT = ROOT / "docs/generated_figures/main_module_area_comparison_table.png"
DOCS_COPY = ROOT.parents[2] / "docs/main_module_area_comparison_table.png"


W, H = 1920, 1080
BG = "#F7FAFF"
WHITE = "#FFFFFF"
BLUE = "#0B3EA8"
BLUE2 = "#0E4FAF"
CYAN = "#C9F4FF"
ROW = "#E7F1FF"
GRID = "#94B2D8"
TEXT = "#102033"
MUTED = "#4B5D78"
GREEN = "#078A56"
RED = "#C7354B"
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


F_TITLE = font(39, True)
F_SUB = font(24)
F_HEAD = font(25, True)
F_CELL = font(25)
F_CELL_B = font(25, True)
F_PREC = font(31, True)
F_FOOT = font(18)


def parse_report():
    rows = {}
    with REPORT.open(encoding="utf-8", errors="ignore") as f:
        for line in f:
            if not line.startswith("|"):
                continue
            parts = [p.strip() for p in line.split("|")[1:-1]]
            if len(parts) != 11 or not parts[2].isdigit():
                continue
            inst = re.sub(r"\s+", " ", parts[0]).strip()
            rows[inst] = {
                "lut": int(parts[2]),
                "ff": int(parts[6]),
                "bram": int(parts[7]),
                "dsp": int(parts[10]),
            }
    return rows


r = parse_report()
full = r["rv32_soc_fpga_zcu102_top"]
cpu = r["u_cpu"]
tx = r["u_tx_top"]
rx = r["u_rx_top"]
aes = {
    "lut": r["u_AES_top_tx"]["lut"] + r["u_AES_top_rx"]["lut"],
    "ff": r["u_AES_top_tx"]["ff"] + r["u_AES_top_rx"]["ff"],
    "bram": 0,
}
huffman = {
    "lut": r["u_huffman_aes_tx_top"]["lut"] + r["u_huffman_block_decoder"]["lut"],
    "ff": r["u_huffman_aes_tx_top"]["ff"] + r["u_huffman_block_decoder"]["ff"],
    "bram": r["u_huffman_aes_tx_top"]["bram"] + r["u_huffman_block_decoder"]["bram"],
}


def res(d):
    return f'{d["lut"]/1000:.1f}K LUT\n{d["ff"]/1000:.1f}K FF\n{d["bram"]} BRAM'


def pct_delta(ours, ref):
    return (ours - ref) / ref * 100


def spct(v):
    return f"{'+' if v >= 0 else ''}{v:.1f}%"


rows = [
    ["Full SoC", res(full), "GZip C+D\n42.1K LUT / 36.8K REG\n81 BRAM",
     f"LUT {spct(pct_delta(full['lut']/1000, 42.1))}\nFF {spct(pct_delta(full['ff']/1000, 36.8))}\nBRAM {spct(pct_delta(full['bram'], 81))}", "75%", "[1][2]"],
    ["RV32I CPU", res(cpu), "Full SoC\nresource share", "5.0% of LUT\n3.2% of FF", "100%", "[1]"],
    ["TX accelerator", res(tx), "GZip-C\n35.4K LUT / 31.8K REG\n73 BRAM",
     f"LUT {spct(pct_delta(tx['lut']/1000, 35.4))}\nFF {spct(pct_delta(tx['ff']/1000, 31.8))}\nBRAM -100%", "75%", "[2]"],
    ["RX accelerator", res(rx), "GZip-D\n6.7K LUT / 5.0K REG\n8 BRAM",
     f"LUT {spct(pct_delta(rx['lut']/1000, 6.7))}\nFF {spct(pct_delta(rx['ff']/1000, 5.0))}\nBRAM {spct(pct_delta(rx['bram'], 8))}", "65%", "[2]"],
    ["AES cores", res(aes), "CHES AES\n17,425 slices", "N/C\nslice unit", "45%", "[3]"],
    ["Huffman blocks", res(huffman), "ASAP14\n1,836 slices / 62 BRAM", "BRAM -98.4%\nLUT N/C", "55%", "[4]"],
]


def center(draw, box, text, fnt, fill=TEXT):
    x0, y0, x1, y1 = box
    lines = str(text).split("\n")
    lh = int(fnt.size * 1.12)
    y = y0 + ((y1 - y0) - lh * len(lines)) / 2
    for line in lines:
        bb = draw.textbbox((0, 0), line, font=fnt)
        draw.text((x0 + ((x1 - x0) - (bb[2] - bb[0])) / 2, y), line, font=fnt, fill=fill)
        y += lh


def left(draw, box, text, fnt, fill=TEXT):
    x0, y0, x1, y1 = box
    lines = str(text).split("\n")
    lh = int(fnt.size * 1.12)
    y = y0 + ((y1 - y0) - lh * len(lines)) / 2
    for line in lines:
        draw.text((x0 + 14, y), line, font=fnt, fill=fill)
        y += lh


def delta_fill(text):
    if "free" in text or "-100" in text or "-98" in text:
        return GREEN
    if "-" in text and "+" not in text:
        return GREEN
    if "+217" in text or "+163" in text:
        return RED
    if "+3.5" in text:
        return RED
    return TEXT


img = Image.new("RGB", (W, H), BG)
draw = ImageDraw.Draw(img)

draw.rectangle((0, 0, W, 88), fill=WHITE)
draw.polygon([(40, 24), (690, 24), (730, 62), (690, 100), (40, 100)], fill=CYAN, outline=BLUE2)
draw.text((62, 39), "MAIN MODULE AREA COMPARISON", font=F_TITLE, fill=BLUE)
draw.text((76, 106), "Vivado post-implementation vs selected official / paper baselines", font=F_SUB, fill=MUTED)

draw.text((610, 154), "Area / Resource Summary", font=font(36, True), fill=BLUE)

left_x, top_y = 70, 205
table_w = W - 140
head_h = 76
row_h = 96
cols = [
    ("Module", 260),
    ("This design", 335),
    ("Baseline", 360),
    ("Delta", 330),
    ("Precision", 190),
    ("Ref.", 110),
]
scale = table_w / sum(w for _, w in cols)
cols = [(h, int(w * scale)) for h, w in cols]
cols[-1] = (cols[-1][0], table_w - sum(w for _, w in cols[:-1]))

x = left_x
draw.rectangle((left_x, top_y, left_x + table_w, top_y + head_h), fill=BLUE)
for h, cw in cols:
    draw.rectangle((x, top_y, x + cw, top_y + head_h), outline=WHITE, width=2)
    center(draw, (x, top_y, x + cw, top_y + head_h), h, F_HEAD, WHITE)
    x += cw

y = top_y + head_h
for i, row in enumerate(rows):
    fill = WHITE if i % 2 == 0 else ROW
    draw.rectangle((left_x, y, left_x + table_w, y + row_h), fill=fill, outline=GRID, width=1)
    x = left_x
    for ci, ((_, cw), val) in enumerate(zip(cols, row)):
        draw.rectangle((x, y, x + cw, y + row_h), outline=GRID, width=1)
        if ci == 0:
            left(draw, (x, y, x + cw, y + row_h), val, F_CELL_B)
        elif ci == 3:
            center(draw, (x, y, x + cw, y + row_h), val, F_CELL_B, delta_fill(val))
        elif ci == 4:
            num = int(val.strip("%"))
            color = GREEN if num >= 80 else (ORANGE if num >= 60 else RED)
            center(draw, (x, y, x + cw, y + row_h), val, F_PREC, color)
        else:
            center(draw, (x, y, x + cw, y + row_h), val, F_CELL)
        x += cw
    y += row_h

note_y = y + 20
draw.rounded_rectangle((70, note_y, W - 70, note_y + 60), radius=10, fill=WHITE, outline=BLUE2, width=3)
draw.text((100, note_y + 17), "Precision:", font=F_HEAD, fill=BLUE)
draw.text((240, note_y + 18), "confidence of resource comparison, not data accuracy.", font=F_HEAD, fill=TEXT)

src_y = note_y + 86
draw.text((80, src_y), "Sources:", font=F_HEAD, fill=BLUE)
src = (
    "[1] Vivado post-implementation report. "
    "[2] AMD Vitis Data Compression Library 2022.1. "
    "[3] Good & Benaissa, CHES 2005. "
    "[4] Matai et al., ASAP 2014."
)
draw.text((80, src_y + 32), src, font=F_FOOT, fill=MUTED)

OUT.parent.mkdir(parents=True, exist_ok=True)
img.save(OUT)
DOCS_COPY.parent.mkdir(parents=True, exist_ok=True)
img.save(DOCS_COPY)
print(OUT)
print(DOCS_COPY)
