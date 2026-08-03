from PIL import Image, ImageDraw, ImageFont
from pathlib import Path
import textwrap


OUT_DIR = Path(__file__).resolve().parent
PNG_PATH = OUT_DIR / "architecture_throughput_comparison_table.png"
SVG_PATH = OUT_DIR / "architecture_throughput_comparison_table.svg"


W, H = 1920, 1080
MARGIN = 70


def font(size, bold=False):
    base = Path("C:/Windows/Fonts")
    name = "arialbd.ttf" if bold else "arial.ttf"
    path = base / name
    if path.exists():
        return ImageFont.truetype(str(path), size)
    return ImageFont.load_default()


F_TITLE = font(48, True)
F_SUB = font(27)
F_HEAD = font(27, True)
F_CELL = font(25)
F_CELL_BOLD = font(25, True)
F_SMALL = font(22)
F_FOOT = font(24, True)


COLORS = {
    "bg": "#f3f6fb",
    "slide": "#ffffff",
    "blue": "#0637a6",
    "blue2": "#0b4fb3",
    "green": "#0f8b55",
    "orange": "#f28c20",
    "purple": "#6d35d9",
    "light_blue": "#eaf2ff",
    "light_green": "#e4f7ee",
    "light_orange": "#fff2df",
    "light_red": "#fff0f0",
    "row_a": "#ffffff",
    "row_b": "#eef4fb",
    "grid": "#9aa8bc",
    "text": "#122033",
    "muted": "#475569",
    "red": "#c72535",
}


columns = [
    ("Criterion", 355),
    ("Software baseline", 350),
    ("Standalone HW core", 355),
    ("This work", 410),
    ("Impact / note", 310),
]

rows = [
    [
        "RTL datapath processing",
        "x\nAlgorithm steps run as CPU software loops",
        "Yes\nSingle-purpose hardware IP",
        "Yes\nTX/RX accelerator is implemented in RTL",
        "Higher throughput mainly versus software",
    ],
    [
        "CPU workload",
        "x\nCPU computes and controls data movement",
        "Partial\nExternal controller usually feeds the IP",
        "Yes\nCPU only writes MMIO registers and checks status",
        "Reduces instruction overhead",
    ],
    [
        "Data movement",
        "x\nMany load/store operations in software",
        "Partial\nDepends on integration around the IP",
        "Yes\nDMA moves data between DMEM and accelerator",
        "Fewer memory-access operations",
    ],
    [
        "Data granularity",
        "x\nOften byte-by-byte processing loops",
        "Yes\nBlock-oriented input/output",
        "Yes\n32-bit words and 128-bit AES blocks",
        "Better bus and datapath utilization",
    ],
    [
        "AES-CBC execution",
        "x\nAES rounds and XOR feedback in software",
        "Yes\nOptimized AES datapath can be very fast",
        "Yes\nAES-128-CBC uses a fixed 10-round block flow",
        "Stable block latency",
    ],
    [
        "Huffman execution",
        "x\nTree/table/bit operations handled by loops",
        "Partial\nCompression-only cores may exist",
        "Yes\nFrequency count, canonical code, and bit packing in RTL",
        "Lower bit-management overhead",
    ],
    [
        "Full secure-storage path",
        "x\nCompression and encryption are separate functions",
        "x\nUsually AES-only or Huffman-only IP",
        "Yes\nTX: compress + encrypt; RX: decrypt + decompress",
        "System-level secure storage path",
    ],
    [
        "AES-only top speed",
        "x\nSoftware is normally slower",
        "Yes\nDedicated AES cores can be fastest",
        "x\nNot designed to beat every AES-only core",
        "Strength is integrated secure storage",
    ],
]


def hex_to_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def draw_wrapped(draw, text, box, fnt, fill, line_spacing=5, bold_first=False):
    x, y, w, h = box
    lines_out = []
    for idx, para in enumerate(text.split("\n")):
        para_font = F_CELL_BOLD if bold_first and idx == 0 else fnt
        max_chars = max(8, int(w / (para_font.size * 0.52)))
        wrapped = textwrap.wrap(para, width=max_chars) or [""]
        for item in wrapped:
            lines_out.append((item, para_font))

    total_h = 0
    for line, lf in lines_out:
        bbox = draw.textbbox((0, 0), line, font=lf)
        total_h += (bbox[3] - bbox[1]) + line_spacing
    total_h -= line_spacing

    cy = y + (h - total_h) / 2
    for line, lf in lines_out:
        bbox = draw.textbbox((0, 0), line, font=lf)
        draw.text((x, cy), line, font=lf, fill=fill)
        cy += (bbox[3] - bbox[1]) + line_spacing


def status_color(text):
    first = text.split("\n", 1)[0].strip()
    if first == "Yes":
        return COLORS["green"]
    if first == "Partial":
        return COLORS["orange"]
    if first == "x":
        return COLORS["red"]
    return COLORS["text"]


def make_png():
    img = Image.new("RGB", (W, H), hex_to_rgb(COLORS["bg"]))
    d = ImageDraw.Draw(img)

    d.rounded_rectangle([MARGIN, 45, W - MARGIN, H - 45], radius=18,
                        fill=hex_to_rgb(COLORS["slide"]),
                        outline=hex_to_rgb("#c7d2e3"), width=2)
    d.rectangle([MARGIN, 45, W - MARGIN, 145], fill=hex_to_rgb(COLORS["blue"]))
    d.text((110, 74), "Architecture-Level Throughput Comparison",
           font=F_TITLE, fill="white")
    d.text((110, 164),
           "The main speed advantage comes from RTL offload, DMA movement, and word/block-based processing.",
           font=F_SUB, fill=hex_to_rgb(COLORS["text"]))

    table_x = 90
    table_y = 225
    table_w = sum(w for _, w in columns)
    head_h = 60
    row_h = 86

    x = table_x
    for i, (label, cw) in enumerate(columns):
        color = COLORS["blue2"]
        if label == "This work":
            color = COLORS["green"]
        if label == "Impact / note":
            color = COLORS["orange"]
        d.rectangle([x, table_y, x + cw, table_y + head_h],
                    fill=hex_to_rgb(color),
                    outline=hex_to_rgb(COLORS["grid"]), width=2)
        draw_wrapped(d, label, (x + 14, table_y, cw - 28, head_h), F_HEAD, "white")
        x += cw

    for r, row in enumerate(rows):
        y = table_y + head_h + r * row_h
        base = COLORS["row_a"] if r % 2 == 0 else COLORS["row_b"]
        x = table_x
        for c, text in enumerate(row):
            _, cw = columns[c]
            fill = base
            if c == 3:
                fill = COLORS["light_green"]
            if c == 4:
                fill = COLORS["light_orange"] if r != len(rows) - 1 else COLORS["light_red"]
            d.rectangle([x, y, x + cw, y + row_h],
                        fill=hex_to_rgb(fill),
                        outline=hex_to_rgb(COLORS["grid"]), width=2)
            if c == 0:
                draw_wrapped(d, text, (x + 16, y, cw - 32, row_h), F_CELL_BOLD,
                             hex_to_rgb(COLORS["text"]))
            elif c in (1, 2, 3):
                first = text.split("\n", 1)[0]
                rest = text.split("\n", 1)[1] if "\n" in text else ""
                d.text((x + 16, y + 12), first, font=F_CELL_BOLD,
                       fill=hex_to_rgb(status_color(text)))
                draw_wrapped(d, rest, (x + 16, y + 36, cw - 32, row_h - 40),
                             F_SMALL, hex_to_rgb(COLORS["text"]))
            else:
                draw_wrapped(d, text, (x + 16, y, cw - 32, row_h), F_CELL_BOLD,
                             hex_to_rgb(COLORS["text"]))
            x += cw

    foot_y = table_y + head_h + len(rows) * row_h + 25
    d.rounded_rectangle([90, foot_y, 1830, foot_y + 70], radius=8,
                        fill=hex_to_rgb("#eaf2ff"),
                        outline=hex_to_rgb("#6ea8fe"), width=2)
    foot = ("Conclusion: this design is strongest against software baselines because compression and encryption "
            "run in hardware. It is not intended to beat every standalone AES-only core.")
    draw_wrapped(d, foot, (115, foot_y, 1690, 70), F_FOOT, hex_to_rgb(COLORS["blue"]))

    img.save(PNG_PATH)


def svg_escape(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def make_svg():
    # The SVG mirrors the PNG layout in editable text boxes.
    table_x = 90
    table_y = 225
    head_h = 60
    row_h = 86
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
        "<style>",
        "text{font-family:Arial,Helvetica,sans-serif;fill:#122033}",
        ".title{font-size:48px;font-weight:700;fill:#fff}",
        ".sub{font-size:27px}",
        ".head{font-size:27px;font-weight:700;fill:#fff}",
        ".cell{font-size:25px;font-weight:700}",
        ".small{font-size:22px}",
        ".yes{fill:#0f8b55}.no{fill:#c72535}.partial{fill:#f28c20}",
        "</style>",
        f'<rect width="{W}" height="{H}" fill="{COLORS["bg"]}"/>',
        f'<rect x="{MARGIN}" y="45" width="{W - 2 * MARGIN}" height="{H - 90}" rx="18" fill="#fff" stroke="#c7d2e3" stroke-width="2"/>',
        f'<rect x="{MARGIN}" y="45" width="{W - 2 * MARGIN}" height="100" fill="{COLORS["blue"]}"/>',
        '<text x="110" y="108" class="title">Architecture-Level Throughput Comparison</text>',
        '<text x="110" y="192" class="sub">The main speed advantage comes from RTL offload, DMA movement, and word/block-based processing.</text>',
    ]
    x = table_x
    for label, cw in columns:
        color = COLORS["blue2"]
        if label == "This work":
            color = COLORS["green"]
        if label == "Impact / note":
            color = COLORS["orange"]
        parts.append(f'<rect x="{x}" y="{table_y}" width="{cw}" height="{head_h}" fill="{color}" stroke="{COLORS["grid"]}" stroke-width="2"/>')
        parts.append(f'<text x="{x+16}" y="{table_y+38}" class="head">{svg_escape(label)}</text>')
        x += cw
    for r, row in enumerate(rows):
        y = table_y + head_h + r * row_h
        base = COLORS["row_a"] if r % 2 == 0 else COLORS["row_b"]
        x = table_x
        for c, text in enumerate(row):
            cw = columns[c][1]
            fill = base
            if c == 3:
                fill = COLORS["light_green"]
            if c == 4:
                fill = COLORS["light_orange"] if r != len(rows) - 1 else COLORS["light_red"]
            parts.append(f'<rect x="{x}" y="{y}" width="{cw}" height="{row_h}" fill="{fill}" stroke="{COLORS["grid"]}" stroke-width="2"/>')
            if c == 0:
                parts.append(f'<text x="{x+16}" y="{y+49}" class="cell">{svg_escape(text)}</text>')
            elif c in (1, 2, 3):
                first, _, rest = text.partition("\n")
                klass = "yes" if first == "Yes" else "partial" if first == "Partial" else "no" if first == "x" else ""
                parts.append(f'<text x="{x+16}" y="{y+31}" class="cell {klass}">{svg_escape(first)}</text>')
                max_chars = int((cw - 32) / 12)
                for i, line in enumerate(textwrap.wrap(rest, width=max_chars)[:2]):
                    parts.append(f'<text x="{x+16}" y="{y+59+i*24}" class="small">{svg_escape(line)}</text>')
            else:
                max_chars = int((cw - 32) / 13)
                for i, line in enumerate(textwrap.wrap(text, width=max_chars)[:3]):
                    parts.append(f'<text x="{x+16}" y="{y+32+i*25}" class="cell">{svg_escape(line)}</text>')
            x += cw
    foot_y = table_y + head_h + len(rows) * row_h + 25
    parts.append(f'<rect x="90" y="{foot_y}" width="1740" height="70" rx="8" fill="#eaf2ff" stroke="#6ea8fe" stroke-width="2"/>')
    parts.append(f'<text x="115" y="{foot_y+44}" style="font-size:24px;font-weight:700;fill:{COLORS["blue"]}">Conclusion: strongest against software baselines; standalone optimized AES-only cores can still be faster.</text>')
    parts.append("</svg>")
    SVG_PATH.write_text("\n".join(parts), encoding="utf-8")


if __name__ == "__main__":
    make_png()
    make_svg()
    print(PNG_PATH)
    print(SVG_PATH)
