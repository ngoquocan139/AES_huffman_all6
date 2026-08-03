from pathlib import Path
import re
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
UTIL = ROOT / "vivado/build/rv32_soc_synth_full_zcu102/reports/post_impl_utilization.rpt"
HIER = ROOT / "vivado/build/rv32_soc_synth_full_zcu102/reports/post_impl_utilization_hier.rpt"
OUT = ROOT / "docs/generated_figures/resource_table_like_sample.png"
DOCS_COPY = ROOT.parents[2] / "docs/resource_table_like_sample.png"

W, H = 1920, 1080
BG = "#F6F9FF"
WHITE = "#FFFFFF"
BLUE = "#0B3EA8"
BLUE_D = "#082D78"
HEAD = "#DCEBFF"
ROW = "#EEF5FF"
GRID = "#6B7FA5"
TEXT = "#102033"
MUTED = "#40516C"
GREEN = "#05834F"
RED = "#C93348"


def font(size, bold=False):
    paths = [
        "C:/Windows/Fonts/arialbd.ttf" if bold else "C:/Windows/Fonts/arial.ttf",
        "C:/Windows/Fonts/calibrib.ttf" if bold else "C:/Windows/Fonts/calibri.ttf",
    ]
    for p in paths:
        if Path(p).exists():
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


F_TITLE = font(40, True)
F_GROUP = font(27, True)
F_HEAD = font(24, True)
F_CELL = font(23)
F_CELL_B = font(24, True)
F_FOOT = font(20)


def read_lines(path):
    return path.read_text(encoding="utf-8", errors="ignore").splitlines()


def parse_site_table():
    out = {}
    for line in read_lines(UTIL):
        if not line.startswith("|"):
            continue
        parts = [p.strip() for p in line.split("|")[1:-1]]
        if len(parts) < 5 or not parts[1].replace(".", "").isdigit():
            continue
        name = re.sub(r"\s+", " ", parts[0])
        used = int(float(parts[1]))
        avail = int(float(parts[4])) if parts[4].replace(".", "").isdigit() else None
        util = float(parts[5]) if len(parts) > 5 and parts[5].replace(".", "").isdigit() else None
        out[name] = {"used": used, "avail": avail, "util": util}
    return out


def parse_hier():
    out = {}
    for line in read_lines(HIER):
        if not line.startswith("|"):
            continue
        parts = [p.strip() for p in line.split("|")[1:-1]]
        if len(parts) != 11 or not parts[2].isdigit():
            continue
        inst = re.sub(r"\s+", " ", parts[0]).strip()
        out[inst] = {
            "lut": int(parts[2]),
            "ff": int(parts[6]),
            "bram": int(parts[7]),
        }
    return out


site = parse_site_table()
hier = parse_hier()

cap_lut = site["CLB LUTs"]["avail"]
cap_ff = site["CLB Registers"]["avail"]
cap_lutram = site["LUT as Memory"]["avail"]
cap_f7 = site["F7 Muxes"]["avail"]
cap_f8 = site["F8 Muxes"]["avail"]
cap_bram = site["Block RAM Tile"]["avail"]
cap_dsp = site["DSPs"]["avail"]

soc_lut = site["CLB LUTs"]["used"]
soc_ff = site["CLB Registers"]["used"]
soc_lutram = site["LUT as Memory"]["used"]
soc_f7 = site["F7 Muxes"]["used"]
soc_f8 = site["F8 Muxes"]["used"]
soc_bram = site["Block RAM Tile"]["used"]
soc_dsp = site["DSPs"]["used"]

aes_lut = hier["u_AES_top_tx"]["lut"] + hier["u_AES_top_rx"]["lut"]
aes_ff = hier["u_AES_top_tx"]["ff"] + hier["u_AES_top_rx"]["ff"]
huff_bram = hier["u_huffman_aes_tx_top"]["bram"] + hier["u_huffman_block_decoder"]["bram"]
cpu_lut = hier["u_cpu"]["lut"]
cpu_ff = hier["u_cpu"]["ff"]

# Visconti et al. report AES encryption block and decryption block on ZCU102.
ref_aes_lut = 13043 + 27713
ref_aes_ff = 3877 + 3912
# Matai et al. ASAP14 throughput-optimized canonical Huffman encoder.
ref_huff_bram = 62


def pct(used, avail):
    if avail in (None, 0) or used is None:
        return "-"
    return f"{used / avail * 100:.2f}"


def gain(ref, ours):
    if not ref or ref == "-":
        return "-"
    value = (ref - ours) / ref * 100
    return f"{value:+.1f}%"


rows = [
    ["AES LUT", cap_lut, "40,756 [2]", pct(ref_aes_lut, cap_lut), aes_lut, pct(aes_lut, cap_lut), gain(ref_aes_lut, aes_lut)],
    ["AES FF", cap_ff, "7,789 [2]", pct(ref_aes_ff, cap_ff), aes_ff, pct(aes_ff, cap_ff), gain(ref_aes_ff, aes_ff)],
    ["Huffman BRAM", cap_bram, "62 [3]", pct(ref_huff_bram, cap_bram), huff_bram, pct(huff_bram, cap_bram), gain(ref_huff_bram, huff_bram)],
    ["RV32I CPU LUT", cap_lut, "3,614 [4]", pct(3614, cap_lut), cpu_lut, pct(cpu_lut, cap_lut), gain(3614, cpu_lut)],
    ["RV32I CPU FF", cap_ff, "1,642 [4]", pct(1642, cap_ff), cpu_ff, pct(cpu_ff, cap_ff), gain(1642, cpu_ff)],
    ["SoC LUT", cap_lut, "N/C", "N/C", soc_lut, pct(soc_lut, cap_lut), "N/C"],
    ["SoC FF", cap_ff, "N/C", "N/C", soc_ff, pct(soc_ff, cap_ff), "N/C"],
    ["SoC LUTRAM", cap_lutram, "N/R", "N/R", soc_lutram, pct(soc_lutram, cap_lutram), "N/C"],
    ["SoC F7 Mux", cap_f7, "N/R", "N/R", soc_f7, pct(soc_f7, cap_f7), "N/C"],
    ["SoC F8 Mux", cap_f8, "N/R", "N/R", soc_f8, pct(soc_f8, cap_f8), "N/C"],
    ["SoC DSP", cap_dsp, "N/R", "N/R", soc_dsp, pct(soc_dsp, cap_dsp), "N/C"],
    ["SoC Block RAM", cap_bram, "3% [4]", "3.00 [4]", soc_bram, pct(soc_bram, cap_bram), "N/C"],
]


def fmt(v):
    if isinstance(v, int):
        return f"{v:,}"
    return str(v)


def center(draw, box, text, fnt, fill=TEXT):
    x0, y0, x1, y1 = box
    lines = str(text).split("\n")
    line_h = int(fnt.size * 1.15)
    y = y0 + ((y1 - y0) - line_h * len(lines)) / 2
    for line in lines:
        bb = draw.textbbox((0, 0), line, font=fnt)
        draw.text((x0 + ((x1 - x0) - (bb[2] - bb[0])) / 2, y), line, font=fnt, fill=fill)
        y += line_h


def left(draw, box, text, fnt, fill=TEXT):
    x0, y0, x1, y1 = box
    lines = str(text).split("\n")
    line_h = int(fnt.size * 1.15)
    y = y0 + ((y1 - y0) - line_h * len(lines)) / 2
    for line in lines:
        draw.text((x0 + 18, y), line, font=fnt, fill=fill)
        y += line_h


img = Image.new("RGB", (W, H), BG)
draw = ImageDraw.Draw(img)

draw.text((105, 58), "HARDWARE RESOURCE EVALUATION", font=F_TITLE, fill=BLUE_D)
draw.line((105, 112, 710, 112), fill=BLUE, width=4)
draw.text((640, 145), "Hardware Resource Comparison", font=font(33, True), fill=BLUE_D)

left_x, top_y = 95, 220
table_w = W - 190
group_h = 54
head_h = 60
row_h = 46

cols = [295, 245, 235, 195, 235, 195, 205]
scale = table_w / sum(cols)
cols = [int(c * scale) for c in cols]
cols[-1] = table_w - sum(cols[:-1])

xs = [left_x]
for c in cols:
    xs.append(xs[-1] + c)

def rect(box, fill, outline=GRID, width=2):
    draw.rectangle(box, fill=fill, outline=outline, width=width)

# Group header row.
y = top_y
rect((xs[0], y + group_h, xs[1], y + group_h + head_h), HEAD)
rect((xs[1], y + group_h, xs[2], y + group_h + head_h), HEAD)
rect((xs[2], y, xs[4], y + group_h), HEAD)
rect((xs[4], y, xs[6], y + group_h), HEAD)
rect((xs[6], y + group_h, xs[7], y + group_h + head_h), HEAD)
center(draw, (xs[2], y, xs[4], y + group_h), "Reference Architecture", F_GROUP, BLUE_D)
center(draw, (xs[4], y, xs[6], y + group_h), "This Work", F_GROUP, BLUE_D)

# Column header row.
headers = ["Resource", "Available", "Used", "Util. (%)", "Used", "Util. (%)", "Gain"]
hy = y + group_h
for i, h in enumerate(headers):
    rect((xs[i], hy, xs[i + 1], hy + head_h), HEAD)
    center(draw, (xs[i], hy, xs[i + 1], hy + head_h), h, F_HEAD, BLUE_D)

y = hy + head_h
for ri, row in enumerate(rows):
    fill = WHITE if ri % 2 == 0 else ROW
    for ci in range(len(cols)):
        rect((xs[ci], y, xs[ci + 1], y + row_h), fill, width=1)
    left(draw, (xs[0], y, xs[1], y + row_h), row[0], F_CELL_B, BLUE_D)
    for ci, val in enumerate(row[1:], start=1):
        color = TEXT
        fnt = F_CELL
        if ci == 6:
            if str(val).startswith("+"):
                color = GREEN
                fnt = F_CELL_B
            elif str(val).startswith("-"):
                color = RED
                fnt = F_CELL_B
        center(draw, (xs[ci], y, xs[ci + 1], y + row_h), fmt(val), fnt, color)
    y += row_h

note_y = y + 16
draw.rounded_rectangle((95, note_y, W - 95, note_y + 54), radius=8, fill=WHITE, outline=BLUE, width=2)
draw.text((125, note_y + 14), "Gain = resource reduction vs reference; N/C = not comparable, N/R = not reported.", font=F_HEAD, fill=BLUE_D)

src_y = note_y + 68
draw.text((105, src_y), "References: [1] Vivado post-implementation report. [2] Visconti et al., Electronics 2020. [3] Matai et al., ASAP 2014. [4] Kalapothas et al., Information 2023.", font=F_FOOT, fill=MUTED)
draw.text((105, src_y + 28), "[2] is used for AES LUT/FF; [3] for Huffman BRAM; [4] uses SiFive E31 as a 32-bit RISC-V CPU reference.", font=F_FOOT, fill=MUTED)

OUT.parent.mkdir(parents=True, exist_ok=True)
img.save(OUT)
DOCS_COPY.parent.mkdir(parents=True, exist_ok=True)
img.save(DOCS_COPY)
print(OUT)
print(DOCS_COPY)
