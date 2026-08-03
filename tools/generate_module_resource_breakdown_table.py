from pathlib import Path
import re
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / "vivado/build/rv32_soc_synth_full_zcu102/reports/post_impl_utilization_hier.rpt"
OUT = ROOT / "docs/generated_figures/module_resource_breakdown_from_vivado.png"
DOCS_COPY = ROOT.parents[2] / "docs/module_resource_breakdown_from_vivado.png"


W, H = 1920, 1080
BG = "#F6F9FF"
BLUE = "#0B3EA8"
BLUE_DARK = "#082E78"
BLUE_MID = "#1357B8"
CYAN = "#BFEFFF"
WHITE = "#FFFFFF"
ROW = "#E8F1FF"
GRID = "#9BB6D7"
TEXT = "#102033"
MUTED = "#4B5D78"
ORANGE = "#F28C28"
GREEN = "#0B8A59"
PURPLE = "#6F56E8"
RED = "#D4364A"


def font(size, bold=False):
    for p in [
        "C:/Windows/Fonts/arialbd.ttf" if bold else "C:/Windows/Fonts/arial.ttf",
        "C:/Windows/Fonts/calibrib.ttf" if bold else "C:/Windows/Fonts/calibri.ttf",
    ]:
        if Path(p).exists():
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


F_TITLE = font(38, True)
F_SUB = font(22)
F_HEAD = font(20, True)
F_CELL = font(18)
F_CELL_B = font(18, True)
F_SMALL = font(15)
F_BIG = font(27, True)


def parse_report(path):
    rows = {}
    top = None
    with path.open(encoding="utf-8", errors="ignore") as f:
        for line in f:
            if not line.startswith("|"):
                continue
            parts = [p.strip() for p in line.split("|")[1:-1]]
            if len(parts) != 11:
                continue
            if parts[2] == "Total LUTs" or not parts[2].replace("-", "").isdigit():
                continue
            inst = re.sub(r"\s+", " ", parts[0]).strip()
            mod = parts[1].strip()
            rec = {
                "instance": inst,
                "module": mod,
                "lut": int(parts[2]),
                "logic_lut": int(parts[3]),
                "lutram": int(parts[4]),
                "ff": int(parts[6]),
                "bram": int(parts[7]),
                "dsp": int(parts[10]),
            }
            rows[inst] = rec
            if inst == "rv32_soc_fpga_zcu102_top":
                top = rec
    if top is None:
        raise RuntimeError("Top row not found in Vivado report")
    return rows, top


rows, top = parse_report(REPORT)


def rec(inst):
    return rows[inst]


def pct(v):
    return f"{100 * v / top['lut']:.1f}%"


def sum_rec(label, insts):
    return {
        "label": label,
        "lut": sum(rec(i)["lut"] for i in insts),
        "ff": sum(rec(i)["ff"] for i in insts),
        "bram": sum(rec(i)["bram"] for i in insts),
    }


top_level = [
    {"label": "Full FPGA top", **{k: top[k] for k in ["lut", "ff", "bram"]}},
    {"label": "RV32I SoC core", **{k: rec("u_soc")[k] for k in ["lut", "ff", "bram"]}},
    {"label": "RV32I CPU", **{k: rec("u_cpu")[k] for k in ["lut", "ff", "bram"]}},
    {"label": "CPU register file", **{k: rec("u_reg_file")[k] for k in ["lut", "ff", "bram"]}},
    sum_rec("DMA + MMIO control", ["u_cpu_mmio_to_apb_bridge", "u_dma_regfile", "u_dma_tx_engine", "u_dma_rx_engine"]),
    {"label": "DMEM", **{k: rec("u_dmem")[k] for k in ["lut", "ff", "bram"]}},
    {"label": "IMEM", **{k: rec("u_imem")[k] for k in ["lut", "ff", "bram"]}},
    {"label": "TX accelerator", **{k: rec("u_tx_top")[k] for k in ["lut", "ff", "bram"]}},
    {"label": "RX accelerator", **{k: rec("u_rx_top")[k] for k in ["lut", "ff", "bram"]}},
    {"label": "UART loader", **{k: rec("u_uart_dmem_loader")[k] for k in ["lut", "ff", "bram"]}},
]

details = [
    ("AES encrypt TX", "u_AES_top_tx", ORANGE),
    ("AES decrypt RX", "u_AES_top_rx", ORANGE),
    ("TX APB/FIFO IF", "u_apb_huffman_tx_if", BLUE_MID),
    ("TX Huffman top", "u_huffman_aes_tx_top", GREEN),
    ("TX bit packer", "u_bit_packer_128", GREEN),
    ("TX dynamic encoder", "u_dynamic_huffman_encoder", GREEN),
    ("TX freq counter", "u_file_frequency_counter", GREEN),
    ("TX Huffman builder", "u_file_huffman_builder", GREEN),
    ("RX APB/FIFO IF", "u_apb_huffman_rx_if", BLUE_MID),
    ("RX bit depacker", "u_bit_depacker_128", PURPLE),
    ("RX Huffman parser", "u_huffman_block_parser", PURPLE),
    ("RX Huffman decoder", "u_huffman_block_decoder", PURPLE),
    ("RX decode table", "u_main_decode_table", PURPLE),
]
detail_rows = []
for label, inst, color in details:
    r = rec(inst)
    detail_rows.append({"label": label, "lut": r["lut"], "ff": r["ff"], "bram": r["bram"], "color": color})


def draw_center(draw, box, text, fnt, fill=TEXT):
    x0, y0, x1, y1 = box
    lines = str(text).split("\n")
    lh = int(fnt.size * 1.15)
    y = y0 + ((y1 - y0) - lh * len(lines)) / 2
    for line in lines:
        bb = draw.textbbox((0, 0), line, font=fnt)
        draw.text((x0 + ((x1 - x0) - (bb[2] - bb[0])) / 2, y), line, font=fnt, fill=fill)
        y += lh


def draw_text_fit(draw, box, text, fnt, fill=TEXT):
    x0, y0, x1, y1 = box
    txt = str(text)
    bb = draw.textbbox((0, 0), txt, font=fnt)
    if bb[2] - bb[0] <= x1 - x0 - 10:
        draw.text((x0 + 8, y0 + (y1 - y0 - fnt.size) / 2 - 2), txt, font=fnt, fill=fill)
        return
    # simple two-line split
    words = txt.split()
    mid = max(1, len(words) // 2)
    lines = [" ".join(words[:mid]), " ".join(words[mid:])]
    lh = int(fnt.size * 1.05)
    yy = y0 + (y1 - y0 - 2 * lh) / 2
    for line in lines:
        draw.text((x0 + 8, yy), line, font=fnt, fill=fill)
        yy += lh


def draw_table(draw, title, rows_data, x, y, w, h, detail=False):
    draw.text((x, y - 44), title, font=F_BIG, fill=BLUE)
    headers = ["Module", "LUT", "FF", "BRAM", "LUT share"]
    colw = [0.40, 0.16, 0.16, 0.13, 0.15]
    colw = [int(w * c) for c in colw]
    colw[-1] = w - sum(colw[:-1])
    head_h = 46
    row_h = int((h - head_h) / len(rows_data))
    xx = x
    draw.rectangle((x, y, x + w, y + head_h), fill=BLUE, outline=BLUE)
    for i, hd in enumerate(headers):
        draw.rectangle((xx, y, xx + colw[i], y + head_h), outline=WHITE, width=2)
        draw_center(draw, (xx, y, xx + colw[i], y + head_h), hd, F_HEAD, WHITE)
        xx += colw[i]

    yy = y + head_h
    for idx, r in enumerate(rows_data):
        fill = WHITE if idx % 2 == 0 else ROW
        xx = x
        draw.rectangle((x, yy, x + w, yy + row_h), fill=fill, outline=GRID, width=1)
        color = r.get("color", BLUE_MID)
        # Module
        draw.rectangle((xx, yy, xx + colw[0], yy + row_h), outline=GRID, width=1)
        if detail:
            draw.rectangle((xx + 8, yy + 12, xx + 17, yy + row_h - 12), fill=color)
            draw_text_fit(draw, (xx + 20, yy, xx + colw[0], yy + row_h), r["label"], F_CELL_B)
        else:
            draw_text_fit(draw, (xx, yy, xx + colw[0], yy + row_h), r["label"], F_CELL_B)
        xx += colw[0]
        # LUT / FF / BRAM
        for key, cw in zip(["lut", "ff", "bram"], colw[1:4]):
            draw.rectangle((xx, yy, xx + cw, yy + row_h), outline=GRID, width=1)
            draw_center(draw, (xx, yy, xx + cw, yy + row_h), f"{r[key]:,}", F_CELL)
            xx += cw
        # Share with bar
        cw = colw[4]
        draw.rectangle((xx, yy, xx + cw, yy + row_h), outline=GRID, width=1)
        share = pct(r["lut"])
        bar_w = int((cw - 56) * r["lut"] / top["lut"])
        draw.rectangle((xx + 8, yy + row_h - 18, xx + 8 + bar_w, yy + row_h - 8), fill=color)
        draw.text((xx + 12, yy + 8), share, font=F_CELL, fill=TEXT)
        yy += row_h


img = Image.new("RGB", (W, H), BG)
draw = ImageDraw.Draw(img)

# Header shape
draw.rectangle((0, 0, W, 84), fill=WHITE)
draw.polygon([(42, 26), (720, 26), (760, 62), (720, 98), (42, 98)], fill=CYAN, outline=BLUE_MID)
draw.text((64, 39), "MODULE AREA / RESOURCE BREAKDOWN", font=F_TITLE, fill=BLUE)
draw.text((78, 110), "Source: Vivado 2024.2 postRoute utilization hierarchy report", font=F_SUB, fill=MUTED)

# Summary cards
cards = [
    ("Total LUT", f"{top['lut']:,}", ORANGE),
    ("FF", f"{top['ff']:,}", BLUE_MID),
    ("BRAM36", f"{top['bram']}", GREEN),
    ("DSP", f"{top['dsp']}", PURPLE),
]
card_y, card_w = 145, 395
for i, (label, value, color) in enumerate(cards):
    x = 140 + i * (card_w + 35)
    draw.rounded_rectangle((x, card_y, x + card_w, card_y + 86), radius=10, fill=WHITE, outline=GRID, width=2)
    draw.rectangle((x, card_y, x + 10, card_y + 86), fill=color)
    draw.text((x + 28, card_y + 14), label, font=F_HEAD, fill=MUTED)
    draw.text((x + 28, card_y + 42), value, font=F_BIG, fill=TEXT)

draw_table(draw, "Top-level SoC Modules", top_level, 60, 310, 860, 570, detail=False)
draw_table(draw, "AES / Huffman Accelerator Details", detail_rows, 1000, 310, 860, 570, detail=True)

# Bottom conclusion and reference
draw.rounded_rectangle((60, 915, 1860, 975), radius=10, fill=WHITE, outline=BLUE_MID, width=3)
draw.text((90, 934), "Conclusion:", font=F_HEAD, fill=BLUE)
draw.text(
    (218, 935),
    "RX Huffman decoder is the largest block; AES cores are small compared with Huffman and full TX/RX datapaths.",
    font=F_HEAD,
    fill=TEXT,
)

draw.text(
    (70, 1005),
    f"Report: {REPORT.relative_to(ROOT)} | Design state: Physopt postRoute | Device: xczu9eg-ffvb1156-2-e.",
    font=F_SMALL,
    fill=MUTED,
)
draw.text(
    (70, 1030),
    "Note: lower-level rows may not sum exactly to parent rows because Vivado performs cross-hierarchy LUT combining.",
    font=F_SMALL,
    fill=RED,
)

OUT.parent.mkdir(parents=True, exist_ok=True)
img.save(OUT)
try:
    DOCS_COPY.parent.mkdir(parents=True, exist_ok=True)
    img.save(DOCS_COPY)
except Exception:
    pass

print(OUT)
print(DOCS_COPY)
