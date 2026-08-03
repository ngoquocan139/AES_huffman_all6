from pathlib import Path
import re
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / "vivado/build/rv32_soc_synth_full_zcu102/reports/post_impl_utilization_hier.rpt"
OUT = ROOT / "docs/generated_figures/official_area_resource_comparison_table.png"
DOCS_COPY = ROOT.parents[2] / "docs/official_area_resource_comparison_table.png"


W, H = 1920, 1080
BG = "#F7FAFF"
WHITE = "#FFFFFF"
BLUE = "#0B3EA8"
BLUE2 = "#0E4FAF"
CYAN = "#C9F4FF"
ROW = "#E7F1FF"
GRID = "#96B4D8"
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
F_HEAD = font(24, True)
F_CELL = font(23)
F_CELL_B = font(23, True)
F_SMALL = font(18)
F_FOOT = font(16)


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
top = r["rv32_soc_fpga_zcu102_top"]
full = top
rx = r["u_rx_top"]
aes_pair = {
    "lut": r["u_AES_top_tx"]["lut"] + r["u_AES_top_rx"]["lut"],
    "ff": r["u_AES_top_tx"]["ff"] + r["u_AES_top_rx"]["ff"],
    "bram": 0,
    "dsp": 0,
}
tx_huff = r["u_huffman_aes_tx_top"]
rx_huff = r["u_huffman_block_decoder"]
cpu = r["u_cpu"]


def fmt_res(d):
    return f'{d["lut"]/1000:.1f}K LUT\n{d["ff"]/1000:.1f}K FF\n{d["bram"]} BRAM'


def pct_delta(ours, ref):
    return (ours - ref) / ref * 100


def sign_pct(v):
    s = "+" if v >= 0 else ""
    return f"{s}{v:.1f}%"


rows = [
    {
        "scope": "Full SoC\nvs ZCU102",
        "ours": f'{full["lut"]/1000:.1f}K LUT\n{full["ff"]/1000:.1f}K FF\n{full["bram"]} BRAM',
        "ref": "274K LUT\n548K FF\n912 BRAM",
        "delta": "13.4% used\n86.6% free",
        "precision": "100%",
        "refno": "[1]",
    },
    {
        "scope": "Full SoC\nvs GZip-C",
        "ours": fmt_res(full),
        "ref": "35.4K LUT\n31.8K REG\n73 BRAM",
        "delta": f"LUT {sign_pct(pct_delta(full['lut']/1000, 35.4))}\nFF {sign_pct(pct_delta(full['ff']/1000, 31.8))}\nBRAM {sign_pct(pct_delta(full['bram'], 73))}",
        "precision": "75%",
        "refno": "[2]",
    },
    {
        "scope": "RX accel.\nvs GZip-D",
        "ours": fmt_res(rx),
        "ref": "6.7K LUT\n5.0K REG\n8 BRAM",
        "delta": f"LUT {sign_pct(pct_delta(rx['lut']/1000, 6.7))}\nFF {sign_pct(pct_delta(rx['ff']/1000, 5.0))}\nBRAM {sign_pct(pct_delta(rx['bram'], 8))}",
        "precision": "65%",
        "refno": "[2]",
    },
    {
        "scope": "AES TX+RX\nvs AES paper",
        "ours": fmt_res(aes_pair),
        "ref": "17,425 slices\nhigh-speed AES",
        "delta": "N/C\nslice unit",
        "precision": "45%",
        "refno": "[4]",
    },
    {
        "scope": "TX Huffman\nvs ASAP14",
        "ours": fmt_res(tx_huff),
        "ref": "1,836 slices\n62 BRAM\n170 MHz",
        "delta": "BRAM -100%\nLUT N/C",
        "precision": "55%",
        "refno": "[5]",
    },
    {
        "scope": "RX Huffman\nvs ASAP14",
        "ours": fmt_res(rx_huff),
        "ref": "Canonical\nHuffman HW",
        "delta": "N/C\ndiff. path",
        "precision": "40%",
        "refno": "[5]",
    },
    {
        "scope": "RV32I CPU\ncontrol",
        "ours": fmt_res(cpu),
        "ref": "Ibex RV32\ncore ref.",
        "delta": "5.0% of\nSoC LUT",
        "precision": "70%",
        "refno": "[6]",
    },
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


def left_text(draw, box, text, fnt, fill=TEXT):
    x0, y0, x1, y1 = box
    lines = str(text).split("\n")
    lh = int(fnt.size * 1.12)
    y = y0 + ((y1 - y0) - lh * len(lines)) / 2
    for line in lines:
        draw.text((x0 + 10, y), line, font=fnt, fill=fill)
        y += lh


def delta_color(text):
    if "+2" in text or "+1" in text or "+3" in text or "+4" in text:
        return RED
    if "-" in text or "free" in text:
        return GREEN
    return TEXT


img = Image.new("RGB", (W, H), BG)
draw = ImageDraw.Draw(img)

# Header
draw.rectangle((0, 0, W, 88), fill=WHITE)
draw.polygon([(40, 24), (710, 24), (750, 62), (710, 100), (40, 100)], fill=CYAN, outline=BLUE2)
draw.text((62, 39), "AREA / RESOURCE COMPARISON", font=F_TITLE, fill=BLUE)
draw.text((76, 104), "Vivado post-implementation vs official / paper baselines", font=F_SUB, fill=MUTED)

# Title
draw.text((640, 145), "Module-level Area Comparison", font=font(34, True), fill=BLUE)

left, top_y = 70, 198
table_w = W - 140
head_h = 72
row_h = 82
cols = [
    ("Scope", 250),
    ("This design", 300),
    ("Baseline", 310),
    ("Delta", 300),
    ("Precision", 170),
    ("Ref.", 120),
]
scale = table_w / sum(w for _, w in cols)
cols = [(h, int(w * scale)) for h, w in cols]
cols[-1] = (cols[-1][0], table_w - sum(w for _, w in cols[:-1]))

# Header row
x = left
draw.rectangle((left, top_y, left + table_w, top_y + head_h), fill=BLUE)
for htxt, cw in cols:
    draw.rectangle((x, top_y, x + cw, top_y + head_h), outline=WHITE, width=2)
    center(draw, (x, top_y, x + cw, top_y + head_h), htxt, F_HEAD, WHITE)
    x += cw

y = top_y + head_h
for i, row in enumerate(rows):
    fill = WHITE if i % 2 == 0 else ROW
    draw.rectangle((left, y, left + table_w, y + row_h), fill=fill, outline=GRID, width=1)
    values = [row["scope"], row["ours"], row["ref"], row["delta"], row["precision"], row["refno"]]
    x = left
    for ci, ((_, cw), val) in enumerate(zip(cols, values)):
        draw.rectangle((x, y, x + cw, y + row_h), outline=GRID, width=1)
        if ci == 0:
            left_text(draw, (x, y, x + cw, y + row_h), val, F_CELL_B)
        elif ci == 3:
            center(draw, (x, y, x + cw, y + row_h), val, F_CELL_B, delta_color(val))
        elif ci == 4:
            num = int(val.strip("%"))
            color = GREEN if num >= 80 else (ORANGE if num >= 60 else RED)
            center(draw, (x, y, x + cw, y + row_h), val, font(28, True), color)
        else:
            center(draw, (x, y, x + cw, y + row_h), val, F_CELL)
        x += cw
    y += row_h

# Bottom note
note_y = y + 16
draw.rounded_rectangle((70, note_y, W - 70, note_y + 52), radius=10, fill=WHITE, outline=BLUE2, width=3)
draw.text((100, note_y + 15), "Precision:", font=F_HEAD, fill=BLUE)
draw.text((235, note_y + 16), "comparison confidence for area/resource units and workload.", font=F_HEAD, fill=TEXT)

# Sources
src_y = note_y + 64
sources = (
    "[1] AMD Zynq UltraScale+ MPSoC Product Selection Guide. "
    "[2] AMD Vitis Data Compression Library 2022.1. "
    "[4] Good & Benaissa, CHES 2005. "
    "[5] Matai et al., ASAP 2014. "
    "[6] OpenTitan / lowRISC Ibex."
)
draw.text((80, src_y), "Sources:", font=F_HEAD, fill=BLUE)
words = sources.split()
line = ""
yy = src_y + 28
for word in words:
    test = word if not line else line + " " + word
    if draw.textbbox((0, 0), test, font=F_FOOT)[2] <= W - 160:
        line = test
    else:
        draw.text((80, yy), line, font=F_FOOT, fill=MUTED)
        yy += 20
        line = word
if line:
    draw.text((80, yy), line, font=F_FOOT, fill=MUTED)

OUT.parent.mkdir(parents=True, exist_ok=True)
img.save(OUT)
DOCS_COPY.parent.mkdir(parents=True, exist_ok=True)
img.save(DOCS_COPY)
print(OUT)
print(DOCS_COPY)
