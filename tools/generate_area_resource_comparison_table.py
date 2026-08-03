from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import textwrap


OUT_DIR = Path("docs/generated_figures")
OUT_DIR.mkdir(parents=True, exist_ok=True)
OUT_PATH = OUT_DIR / "area_resource_comparison_table.png"


W, H = 1920, 1080
BG = "#F5F8FC"
BLUE = "#0B3EA8"
DARK_BLUE = "#06327D"
HEADER = "#0B4F8A"
LIGHT = "#EAF2FF"
WHITE = "#FFFFFF"
GRID = "#B8C7D9"
TEXT = "#162234"
MUTED = "#4A5A70"
ORANGE = "#F28C28"
GREEN = "#158A5B"


def font(size, bold=False):
    candidates = [
        "C:/Windows/Fonts/arialbd.ttf" if bold else "C:/Windows/Fonts/arial.ttf",
        "C:/Windows/Fonts/calibrib.ttf" if bold else "C:/Windows/Fonts/calibri.ttf",
    ]
    for p in candidates:
        if Path(p).exists():
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


F_TITLE = font(40, True)
F_SUB = font(24, False)
F_HEADER = font(22, True)
F_CELL = font(20, False)
F_CELL_BOLD = font(20, True)
F_SMALL = font(17, False)
F_REF = font(15, False)
F_BADGE = font(18, True)


def draw_wrapped(draw, text, box, fnt, fill=TEXT, anchor="la", line_spacing=1.12, align="left"):
    x, y, w, h = box
    if not text:
        return
    # Approximate wrapping by measuring text width.
    words = str(text).split()
    lines = []
    cur = ""
    for word in words:
        test = word if not cur else cur + " " + word
        if draw.textbbox((0, 0), test, font=fnt)[2] <= w:
            cur = test
        else:
            if cur:
                lines.append(cur)
            # split very long words
            if draw.textbbox((0, 0), word, font=fnt)[2] > w:
                max_chars = max(4, int(len(word) * w / max(1, draw.textbbox((0, 0), word, font=fnt)[2])))
                chunks = textwrap.wrap(word, width=max_chars)
                lines.extend(chunks[:-1])
                cur = chunks[-1] if chunks else ""
            else:
                cur = word
    if cur:
        lines.append(cur)
    line_h = int(fnt.size * line_spacing)
    total_h = len(lines) * line_h
    yy = y + max(0, (h - total_h) // 2)
    for line in lines:
        if align == "center":
            tw = draw.textbbox((0, 0), line, font=fnt)[2]
            xx = x + (w - tw) / 2
        else:
            xx = x
        draw.text((xx, yy), line, font=fnt, fill=fill)
        yy += line_h


def pct(used, total):
    return f"{used / total * 100:.2f}%"


rows = [
    {
        "resource": "CLB LUT",
        "available": "274,080",
        "ours": "37,069",
        "util": pct(37069, 274080),
        "reference": "ZCU102 / XCZU9EG capacity from Vivado report [1]",
        "note": "Complete RV32I SoC: CPU + DMA + TX/RX accelerator + UART + memory.",
    },
    {
        "resource": "CLB register / FF",
        "available": "548,160",
        "ours": "19,794",
        "util": pct(19794, 548160),
        "reference": "ZCU102 / XCZU9EG capacity from Vivado report [1]",
        "note": "Low FF utilization; control plane remains small.",
    },
    {
        "resource": "Block RAM tile",
        "available": "912",
        "ours": "11",
        "util": pct(11, 912),
        "reference": "ZCU102 / XCZU9EG capacity from Vivado report [1]",
        "note": "Main use: DMEM, IMEM, and one RX Huffman decode table.",
    },
    {
        "resource": "DSP",
        "available": "2,520",
        "ours": "0",
        "util": "0.00%",
        "reference": "ZCU102 / XCZU9EG capacity from Vivado report [1]",
        "note": "Design uses LUT/BRAM datapath; no multiplier/DSP dependence.",
    },
    {
        "resource": "Full compression HW reference",
        "available": "AMD Vitis GZip Compress: 54K LUT, 48.7K REG, 141 BRAM, 64 URAM [2]",
        "ours": "37.1K LUT, 19.8K FF, 11 BRAM",
        "util": "Lower area memory",
        "reference": "Official AMD Vitis Data Compression Library [2]",
        "note": "Reference is high-throughput GZip on Alveo; ours is a secure-storage SoC, not a GZip engine.",
    },
    {
        "resource": "AES datapath reference",
        "available": "OpenTitan AES: 12-22 kGE core, 136 kGE masked full unit [3]",
        "ours": "TX AES 1,614 LUT / 261 FF; RX AES 1,667 LUT / 261 FF",
        "util": "Not directly convertible",
        "reference": "Official OpenTitan AES HWIP docs [3]",
        "note": "ASIC kGE is used as architectural reference; FPGA LUT comparison is not one-to-one.",
    },
    {
        "resource": "AES FPGA paper reference",
        "available": "CHES 2005: high-speed AES 17,425 slices; low-area AES 124 slices + 2 BRAM [4]",
        "ours": "AES integrated inside TX/RX path",
        "util": "Different target",
        "reference": "Good & Benaissa, CHES 2005 [4]",
        "note": "Paper shows standalone AES extremes; ours prioritizes full SoC integration.",
    },
    {
        "resource": "Canonical Huffman reference",
        "available": "ASAP 2014 throughput-optimized: 1,836 slices, 62 BRAM, 170 MHz [5]",
        "ours": "TX top 11,201 LUT; RX top 21,042 LUT, 1 BRAM",
        "util": "RX dominates area",
        "reference": "Hashemian et al., ASAP 2014 [5]",
        "note": "Reference is Huffman encoder only; ours includes parser, packer, AES-CBC, DMA interface.",
    },
]


img = Image.new("RGB", (W, H), BG)
draw = ImageDraw.Draw(img)

# Title band
draw.rectangle((0, 0, W, 92), fill=WHITE)
draw.rectangle((0, 88, W, 92), fill=BLUE)
draw.text((70, 22), "Area / Resource Comparison", font=F_TITLE, fill=BLUE)
draw.text((70, 70), "Target build: full TX+RX secure-storage RV32I SoC on ZCU102", font=F_SUB, fill=MUTED)

# Summary cards
card_y = 118
card_w = 430
cards = [
    ("Total LUT", "37,069", "13.53% of ZCU102", ORANGE),
    ("Flip-flop", "19,794", "3.61% of ZCU102", "#3778C2"),
    ("BRAM tile", "11", "1.21% of ZCU102", GREEN),
    ("DSP", "0", "No DSP usage", "#6A5ACD"),
]
for i, (label, val, sub, color) in enumerate(cards):
    x = 70 + i * (card_w + 25)
    draw.rounded_rectangle((x, card_y, x + card_w, card_y + 108), radius=14, fill=WHITE, outline=GRID, width=2)
    draw.rectangle((x, card_y, x + 10, card_y + 108), fill=color)
    draw.text((x + 28, card_y + 18), label, font=F_HEADER, fill=MUTED)
    draw.text((x + 28, card_y + 48), val, font=font(34, True), fill=TEXT)
    draw.text((x + 170, card_y + 58), sub, font=F_SMALL, fill=MUTED)

# Table geometry
left, top = 50, 250
table_w = W - 100
header_h = 58
row_h = 70
cols = [
    ("Resource / scope", 245),
    ("Available or baseline", 430),
    ("Our design", 300),
    ("Util. / comparison", 210),
    ("Source and note", 635),
]
scale = table_w / sum(w for _, w in cols)
cols = [(name, int(w * scale)) for name, w in cols]
cols[-1] = (cols[-1][0], table_w - sum(w for _, w in cols[:-1]))

# Header
x = left
draw.rounded_rectangle((left, top, left + table_w, top + header_h), radius=8, fill=HEADER)
for name, cw in cols:
    draw.rectangle((x, top, x + cw, top + header_h), fill=HEADER, outline=WHITE, width=1)
    draw_wrapped(draw, name, (x + 10, top + 4, cw - 20, header_h - 8), F_HEADER, fill=WHITE, align="center")
    x += cw

# Rows
y = top + header_h
for ri, row in enumerate(rows):
    fill = WHITE if ri % 2 == 0 else LIGHT
    x = left
    draw.rectangle((left, y, left + table_w, y + row_h), fill=fill, outline=GRID, width=1)
    vals = [
        row["resource"],
        row["available"],
        row["ours"],
        row["util"],
        f'{row["reference"]}  {row["note"]}',
    ]
    fonts = [F_CELL_BOLD, F_CELL, F_CELL, F_CELL_BOLD, F_SMALL]
    fills = [TEXT, TEXT, TEXT, DARK_BLUE if ri < 4 else GREEN, TEXT]
    for ci, ((_, cw), val) in enumerate(zip(cols, vals)):
        draw.rectangle((x, y, x + cw, y + row_h), outline=GRID, width=1)
        draw_wrapped(draw, val, (x + 10, y + 4, cw - 20, row_h - 8), fonts[ci], fill=fills[ci])
        x += cw
    y += row_h

# Key interpretation strip
strip_y = y + 14
draw.rounded_rectangle((50, strip_y, W - 50, strip_y + 58), radius=10, fill="#E9F3FF", outline="#7AA7E8", width=2)
draw.text((75, strip_y + 16), "Interpretation:", font=F_BADGE, fill=BLUE)
draw.text(
    (218, strip_y + 17),
    "The design fits comfortably on ZCU102. Resource cost is dominated by RX Huffman decode; BRAM and DSP usage remain low.",
    font=F_CELL,
    fill=TEXT,
)

# References
ref_y = strip_y + 74
refs = (
    "References: [1] Local Vivado post-implementation report, rv32_soc_synth_full_zcu102, target ZCU102 / XCZU9EG. "
    "[2] AMD Vitis Data Compression Library, GZip resource utilization, 2023.1. "
    "[3] OpenTitan AES HWIP Theory of Operation. "
    "[4] Good & Benaissa, \"AES on FPGA from the Fastest to the Smallest,\" CHES 2005. "
    "[5] Hashemian et al., \"Energy Efficient Canonical Huffman Encoding,\" ASAP 2014. "
    "Note: FPGA area is platform-dependent; ASIC kGE, slices, LUTs, and BRAM should not be treated as one-to-one equivalent units."
)
draw_wrapped(draw, refs, (55, ref_y, W - 110, H - ref_y - 20), F_REF, fill=MUTED)

img.save(OUT_PATH)
print(OUT_PATH.resolve())
