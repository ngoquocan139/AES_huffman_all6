from pathlib import Path
import re
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / "vivado/build/rv32_soc_synth_full_zcu102/reports/post_impl_utilization_hier.rpt"
OUT = ROOT / "docs/generated_figures/area_resource_matrix_two_refs.png"
DOCS_COPY = ROOT.parents[2] / "docs/area_resource_matrix_two_refs.png"

W, H = 1920, 1080
BG = "#F7FAFF"
WHITE = "#FFFFFF"
BLUE = "#0B3EA8"
BLUE_D = "#072F80"
CYAN = "#BFEFFF"
ROW = "#EAF2FF"
GRID = "#8EAAD0"
TEXT = "#0E1F33"
MUTED = "#46576E"
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


F_TITLE = font(38, True)
F_SUB = font(23)
F_HEAD = font(24, True)
F_CELL = font(24)
F_CELL_B = font(24, True)
F_BIG = font(28, True)
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


def res(d):
    return f'{d["lut"]/1000:.1f}K LUT\n{d["ff"]/1000:.1f}K FF\n{d["bram"]} BRAM'


def center(draw, box, text, fnt, fill=TEXT):
    x0, y0, x1, y1 = box
    lines = str(text).split("\n")
    lh = int(fnt.size * 1.15)
    y = y0 + ((y1 - y0) - lh * len(lines)) / 2
    for line in lines:
        bb = draw.textbbox((0, 0), line, font=fnt)
        draw.text((x0 + ((x1 - x0) - (bb[2] - bb[0])) / 2, y), line, font=fnt, fill=fill)
        y += lh


def left(draw, box, text, fnt, fill=TEXT):
    x0, y0, x1, y1 = box
    lines = str(text).split("\n")
    lh = int(fnt.size * 1.15)
    y = y0 + ((y1 - y0) - lh * len(lines)) / 2
    for line in lines:
        draw.text((x0 + 14, y), line, font=fnt, fill=fill)
        y += lh


r = parse_report()
full = r["rv32_soc_fpga_zcu102_top"]
cpu_reg = {
    "lut": r["u_cpu"]["lut"] + r["u_reg_file"]["lut"],
    "ff": r["u_cpu"]["ff"] + r["u_reg_file"]["ff"],
    "bram": 0,
}
dma_mmio = {
    "lut": r["u_dma_tx_engine"]["lut"] + r["u_dma_rx_engine"]["lut"] + r["u_cpu_mmio_to_apb_bridge"]["lut"] + r["u_dma_regfile"]["lut"],
    "ff": r["u_dma_tx_engine"]["ff"] + r["u_dma_rx_engine"]["ff"] + r["u_cpu_mmio_to_apb_bridge"]["ff"] + r["u_dma_regfile"]["ff"],
    "bram": 0,
}
tx = r["u_tx_top"]
rx = r["u_rx_top"]
aes_pair = {
    "lut": r["u_AES_top_tx"]["lut"] + r["u_AES_top_rx"]["lut"],
    "ff": r["u_AES_top_tx"]["ff"] + r["u_AES_top_rx"]["ff"],
    "bram": 0,
}
huff_pair = {
    "lut": r["u_huffman_aes_tx_top"]["lut"] + r["u_huffman_block_decoder"]["lut"],
    "ff": r["u_huffman_aes_tx_top"]["ff"] + r["u_huffman_block_decoder"]["ff"],
    "bram": r["u_huffman_aes_tx_top"]["bram"] + r["u_huffman_block_decoder"]["bram"],
}

rows = [
    ["Full SoC top", res(full), "-", "-", "-", "100%"],
    ["CPU + register file", res(cpu_reg), "-", "-", "-", "100%"],
    ["DMA + MMIO control", res(dma_mmio), "-", "-", "-", "100%"],
    ["TX accelerator", res(tx), "-", "-", "-", "100%"],
    ["RX accelerator", res(rx), "-", "-", "-", "100%"],
    ["AES TX + RX cores", res(aes_pair), "Visconti ZCU102 [2]\n40.8K LUT\n7.8K FF", "-", "LUT +92.1%\nFF +93.3%", "80%"],
    ["Huffman TX + RX blocks", res(huff_pair), "-", "Matai ASAP14 [3]\n1,836 slices\n62 BRAM", "BRAM +98.4%\nLUT N/C", "55%"],
]

cols = [
    ("Module", 265),
    ("This design [1]", 330),
    ("AES paper [2]", 310),
    ("Huffman paper [3]", 330),
    ("Gain", 290),
    ("Precision", 160),
]

img = Image.new("RGB", (W, H), BG)
draw = ImageDraw.Draw(img)

draw.rectangle((0, 0, W, 92), fill=WHITE)
draw.polygon([(40, 22), (715, 22), (760, 58), (715, 96), (40, 96)], fill=CYAN, outline=BLUE, width=2)
draw.text((62, 37), "AREA / RESOURCE COMPARISON", font=F_TITLE, fill=BLUE_D)
draw.text((80, 109), "Main modules in rows; two closer hardware paper baselines are used.", font=F_SUB, fill=MUTED)

draw.text((646, 154), "FPGA Resource Table", font=font(36, True), fill=BLUE_D)

left_x, top_y = 68, 205
table_w = W - 136
head_h, row_h = 74, 86
scale = table_w / sum(w for _, w in cols)
cols = [(h, int(w * scale)) for h, w in cols]
cols[-1] = (cols[-1][0], table_w - sum(w for _, w in cols[:-1]))

x = left_x
draw.rectangle((left_x, top_y, left_x + table_w, top_y + head_h), fill=BLUE_D)
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
        elif ci == 5:
            pct = int(str(val).replace("%", ""))
            color = GREEN if pct >= 80 else (ORANGE if pct >= 55 else RED)
            center(draw, (x, y, x + cw, y + row_h), val, F_BIG, color)
        elif ci == 4:
            color = GREEN if "+" in str(val) else MUTED
            center(draw, (x, y, x + cw, y + row_h), val, F_CELL_B, color)
        else:
            center(draw, (x, y, x + cw, y + row_h), val, F_CELL)
        x += cw
    y += row_h

note_y = y + 18
draw.rounded_rectangle((68, note_y, W - 68, note_y + 58), radius=8, fill=WHITE, outline=BLUE, width=2)
draw.text((96, note_y + 16), "Precision = comparison confidence, not data-recovery accuracy.", font=F_HEAD, fill=BLUE_D)

src_y = note_y + 78
draw.text((80, src_y), "References:", font=F_HEAD, fill=BLUE_D)
draw.text(
    (80, src_y + 30),
    "[1] Vivado post-implementation utilization report.  [2] Visconti et al., Electronics 2020, ZCU102 AES.  [3] Matai et al., ASAP 2014.",
    font=F_FOOT,
    fill=MUTED,
)
draw.text(
    (80, src_y + 57),
    "Gain is area reduction vs baseline when directly comparable; N/C means resource units or architecture target differ.",
    font=F_FOOT,
    fill=MUTED,
)

OUT.parent.mkdir(parents=True, exist_ok=True)
img.save(OUT)
DOCS_COPY.parent.mkdir(parents=True, exist_ok=True)
img.save(DOCS_COPY)
print(OUT)
print(DOCS_COPY)
