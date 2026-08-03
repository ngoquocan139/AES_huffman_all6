# -*- coding: utf-8 -*-
"""Create an A1 landscape poster using only thesis-derived content/assets.

Source document:
H:\\Academic\\senior_project\\DATN\\docs\\Graduation_Thesis_an_tan.docx

The script uses images extracted from that thesis under docs/_media_extract and
keeps poster body text at 32-36 px as requested.
"""

from __future__ import annotations

from pathlib import Path
import math

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(r"H:\Academic\senior_project\DATN")
DOCS = ROOT / "docs"
MEDIA = DOCS / "_media_extract"
OUT = DOCS / "poster_a1_canva"

W, H = 4960, 3508

BLUE = (0, 58, 160)
DARK_BLUE = (0, 35, 115)
LIGHT_BLUE = (231, 241, 255)
PALE_BLUE = (248, 251, 255)
ORANGE = (242, 138, 32)
GREEN = (34, 145, 92)
RED = (210, 72, 72)
GRID = (190, 216, 240)
BLACK = (25, 31, 42)
WHITE = (255, 255, 255)


def font_path(*names: str) -> str:
    base = Path(r"C:\Windows\Fonts")
    for name in names:
        p = base / name
        if p.exists():
            return str(p)
    return str(base / "arial.ttf")


def font(size: int, bold: bool = False, serif: bool = False) -> ImageFont.FreeTypeFont:
    if serif:
        return ImageFont.truetype(font_path("timesbd.ttf", "georgiab.ttf", "arialbd.ttf"), size)
    if bold:
        return ImageFont.truetype(font_path("arialbd.ttf", "calibrib.ttf", "Aptos-Bold.ttf"), size)
    return ImageFont.truetype(font_path("arial.ttf", "calibri.ttf", "Aptos.ttf"), size)


F_TITLE = font(36, bold=True, serif=True)
F_HEAD = font(36, bold=True)
F_BODY = font(32)
F_BODY_B = font(32, bold=True)
F_SMALL = font(30)
F_SMALL_B = font(30, bold=True)
F_TINY = font(26)
F_TINY_B = font(26, bold=True)


img = Image.new("RGB", (W, H), WHITE)
d = ImageDraw.Draw(img)


def tsize(text: str, f: ImageFont.FreeTypeFont) -> tuple[int, int]:
    b = d.textbbox((0, 0), text, font=f)
    return b[2] - b[0], b[3] - b[1]


def wrap(text: str, f: ImageFont.FreeTypeFont, width: int) -> list[str]:
    words = text.split()
    lines: list[str] = []
    cur = ""
    for word in words:
        candidate = word if not cur else cur + " " + word
        if tsize(candidate, f)[0] <= width:
            cur = candidate
        else:
            if cur:
                lines.append(cur)
            cur = word
    if cur:
        lines.append(cur)
    return lines


def draw_text(x: int, y: int, width: int, text: str, f: ImageFont.FreeTypeFont, fill=BLACK, gap=8) -> int:
    yy = y
    for line in wrap(text, f, width):
        d.text((x, yy), line, font=f, fill=fill)
        yy += tsize(line, f)[1] + gap
    return yy


def bullets(x: int, y: int, width: int, items: list[str], f: ImageFont.FreeTypeFont = F_BODY, gap: int = 18) -> int:
    yy = y
    for item in items:
        d.ellipse((x, yy + 13, x + 13, yy + 26), fill=BLUE)
        yy = draw_text(x + 30, yy, width - 30, item, f, BLACK, gap=7)
        yy += gap
    return yy


def section(x: int, y: int, w: int, h: int, no: int, title: str, header_w: int | None = None) -> int:
    d.rounded_rectangle((x, y, x + w, y + h), radius=18, fill=WHITE, outline=(40, 145, 225), width=4)
    hh = 78
    hw = header_w or min(w - 30, int(w * 0.72))
    d.rounded_rectangle((x, y, x + hw, y + hh), radius=16, fill=BLUE)
    d.rectangle((x, y + hh // 2, x + hw, y + hh), fill=BLUE)
    d.text((x + 34, y + 18), f"{no}. {title}", font=F_HEAD, fill=WHITE)
    return y + hh + 28


def paste_fit(path: Path, box: tuple[int, int, int, int], pad: int = 0, bg=WHITE):
    if not path.exists():
        return
    src = Image.open(path).convert("RGB")
    x, y, w, h = box
    src.thumbnail((w - 2 * pad, h - 2 * pad), Image.Resampling.LANCZOS)
    canvas = Image.new("RGB", (w, h), bg)
    canvas.paste(src, ((w - src.width) // 2, (h - src.height) // 2))
    img.paste(canvas, (x, y))


def stat(x: int, y: int, w: int, h: int, value: str, label: str, color=BLUE):
    d.rounded_rectangle((x, y, x + w, y + h), radius=18, fill=PALE_BLUE, outline=GRID, width=3)
    vf = font(36, bold=True)
    lf = font(30, bold=True)
    tw, _ = tsize(value, vf)
    d.text((x + (w - tw) / 2, y + 24), value, font=vf, fill=color)
    yy = y + 82
    for line in wrap(label, lf, w - 28)[:2]:
        tw, th = tsize(line, lf)
        d.text((x + (w - tw) / 2, yy), line, font=lf, fill=BLACK)
        yy += th + 6


def arrow(x1: int, y1: int, x2: int, y2: int, fill=BLUE, width: int = 5):
    d.line((x1, y1, x2, y2), fill=fill, width=width)
    a = math.atan2(y2 - y1, x2 - x1)
    l = 23
    pts = [
        (x2, y2),
        (x2 - l * math.cos(a - math.pi / 7), y2 - l * math.sin(a - math.pi / 7)),
        (x2 - l * math.cos(a + math.pi / 7), y2 - l * math.sin(a + math.pi / 7)),
    ]
    d.polygon(pts, fill=fill)


def node(x: int, y: int, w: int, h: int, text: str, fill=LIGHT_BLUE, outline=BLUE):
    d.rounded_rectangle((x, y, x + w, y + h), radius=14, fill=fill, outline=outline, width=3)
    lines = wrap(text, F_TINY_B, w - 20)
    total = sum(tsize(line, F_TINY_B)[1] for line in lines) + max(0, len(lines) - 1) * 5
    yy = y + (h - total) / 2
    for line in lines:
        tw, th = tsize(line, F_TINY_B)
        d.text((x + (w - tw) / 2, yy), line, font=F_TINY_B, fill=DARK_BLUE)
        yy += th + 5


# Outer border and header
d.rounded_rectangle((18, 18, W - 18, H - 18), radius=4, fill=WHITE, outline=(45, 45, 45), width=3)

logo = MEDIA / "image1.jpeg"
paste_fit(logo, (75, 58, 305, 250))
d.text((410, 72), "TRƯỜNG ĐẠI HỌC SƯ PHẠM KỸ THUẬT", font=F_TINY_B, fill=DARK_BLUE)
d.text((410, 112), "THÀNH PHỐ HỒ CHÍ MINH", font=F_TINY_B, fill=DARK_BLUE)
d.text((410, 168), "KHOA ĐIỆN - ĐIỆN TỬ", font=F_TINY_B, fill=DARK_BLUE)
d.text((410, 208), "BỘ MÔN KỸ THUẬT MÁY TÍNH - VIỄN THÔNG", font=F_TINY_B, fill=DARK_BLUE)
d.line((1320, 58, 1320, 318), fill=DARK_BLUE, width=5)

title_lines = [
    "DESIGN AND EVALUATION OF AN RV32I-BASED SECURE-STORAGE SOC",
    "INTEGRATING DYNAMIC HUFFMAN COMPRESSION",
    "AND AES-128-CBC ENCRYPTION",
]
yy = 65
for line in title_lines:
    tw, th = tsize(line, F_TITLE)
    d.text(((W - tw) / 2 + 120, yy), line, font=F_TITLE, fill=DARK_BLUE)
    yy += 57

rx = 4065
for y, kind in [(76, "teacher"), (188, "student")]:
    d.ellipse((rx, y, rx + 86, y + 86), fill=DARK_BLUE)
    if kind == "teacher":
        d.ellipse((rx + 30, y + 20, rx + 56, y + 46), fill=WHITE)
        d.rounded_rectangle((rx + 18, y + 50, rx + 68, y + 70), radius=10, fill=WHITE)
    else:
        d.polygon([(rx + 18, y + 35), (rx + 43, y + 20), (rx + 68, y + 35), (rx + 43, y + 50)], fill=WHITE)
        d.rectangle((rx + 28, y + 44, rx + 58, y + 62), fill=WHITE)
d.text((4172, 58), "GVHD:", font=F_TINY_B, fill=DARK_BLUE)
d.text((4172, 96), "PGS.TS. Đỗ Duy Tân", font=F_TINY_B, fill=BLACK)
d.text((4172, 170), "SVTH:", font=F_TINY_B, fill=DARK_BLUE)
d.text((4172, 208), "Ngô Quốc An      - 21161226", font=F_TINY_B, fill=BLACK)
d.text((4172, 242), "Bùi Ngọc Duy Tân - 21161266", font=F_TINY_B, fill=BLACK)


# Layout
M, G, Y0 = 62, 34, 370
c1x, c1w = M, 1390
c2x, c2w = c1x + c1w + G, 1990
c3x, c3w = c2x + c2w + G, W - M - (c2x + c2w + G)
r1y, r1h = Y0, 890
r2y, r2h = r1y + r1h + G, 1320
r3y, r3h = r2y + r2h + G, H - r2y - r2h - G - 70


# 1 Abstract/problem from thesis
cy = section(c1x, r1y, c1w, r1h, 1, "ABSTRACT / PROBLEM", 760)
bullets(
    c1x + 70,
    cy + 25,
    c1w - 140,
    [
        "The thesis designs an RV32I-controlled secure-storage system combining dynamic Huffman compression with AES-128-CBC encryption.",
        "The target flow is compression-to-storage, not data transmission.",
        "The TX path compresses plaintext, packs it into 128-bit transport words, encrypts it, and stores ciphertext in DMEM.",
        "The RX path decrypts and decompresses the selected stored record to recover the original plaintext exactly.",
    ],
)


# 2 Objectives/scope from thesis
cy = section(c1x, r2y, c1w, 630, 2, "OBJECTIVES & SCOPE", 780)
bullets(
    c1x + 70,
    cy + 22,
    c1w - 140,
    [
        "Use RV32I as the control and storage-management processor.",
        "Use DMA and RTL accelerators for compression, encryption, decryption, and decompression.",
        "Manage file identifiers, metadata records, plaintext/ciphertext lengths, and IV values in firmware.",
        "Verify TX-RX loopback, Huffman-only mode, and software-managed multi-record storage.",
    ],
)


# 7 FPGA from thesis
cy = section(c1x, r2y + 630 + G, c1w, r2h - 630 - G, 7, "FPGA IMPLEMENTATION", 760)
stat(c1x + 55, cy + 18, 295, 145, "300", "MHz input clock", BLUE)
stat(c1x + 380, cy + 18, 295, 145, "50", "MHz SoC clock", BLUE)
stat(c1x + 705, cy + 18, 295, 145, "+10.862", "ns setup WNS", GREEN)
stat(c1x + 1030, cy + 18, 295, 145, "0.788W", "estimated power", ORANGE)
x0, y0 = c1x + 65, cy + 205
tw, th = c1w - 130, 300
d.rectangle((x0, y0, x0 + tw, y0 + th), outline=BLUE, width=3)
d.rectangle((x0, y0, x0 + tw, y0 + 58), fill=BLUE)
cols = [0, 360, 660, 930, tw]
for i, label in enumerate(["Design", "LUTs", "FF", "BRAM"]):
    d.text((x0 + cols[i] + 16, y0 + 15), label, font=F_TINY_B, fill=WHITE)
for c in cols[1:-1]:
    d.line((x0 + c, y0, x0 + c, y0 + th), fill=GRID, width=2)
for rr in range(58, th, 60):
    d.line((x0, y0 + rr, x0 + tw, y0 + rr), fill=GRID, width=2)
for idx, row in enumerate(
    [
        ("TX accelerator", "10,734", "2,806", "0"),
        ("RX accelerator", "21,253", "13,163", "1"),
        ("DMEM, IMEM", "56", "0", "10"),
        ("Full FPGA SoC", "36,649", "20,017", "11"),
    ]
):
    yy = y0 + 58 + idx * 60 + 16
    d.text((x0 + 16, yy), row[0], font=F_TINY_B if idx == 3 else F_TINY, fill=BLACK)
    for j in range(1, 4):
        d.text((x0 + cols[j] + 16, yy), row[j], font=F_TINY, fill=BLACK)


# 3 Architecture
cy = section(c2x, r1y, c2w, r1h, 3, "SYSTEM ARCHITECTURE", 900)
node(c2x + 95, cy + 35, 300, 105, "RV32I CPU")
node(c2x + 510, cy + 35, 330, 105, "MMIO/APB\nBridge")
node(c2x + 955, cy + 35, 365, 105, "DMA Register\nFile + IV")
arrow(c2x + 395, cy + 88, c2x + 510, cy + 88)
arrow(c2x + 840, cy + 88, c2x + 955, cy + 88)
node(c2x + 160, cy + 270, 380, 130, "DMEM\ninput / metadata / output", fill=(255, 248, 230), outline=ORANGE)
node(c2x + 720, cy + 240, 310, 105, "TX DMA", fill=(232, 250, 242), outline=GREEN)
node(c2x + 720, cy + 430, 310, 105, "RX DMA", fill=(232, 250, 242), outline=GREEN)
node(c2x + 1185, cy + 235, 385, 110, "TX Accelerator\nHuffman + AES-CBC")
node(c2x + 1185, cy + 425, 385, 110, "RX Accelerator\nAES-CBC + Huffman")
node(c2x + 1655, cy + 333, 275, 120, "Metadata\nfile_id / length / IV", fill=(246, 238, 255), outline=(120, 80, 200))
arrow(c2x + 1135, cy + 88, c2x + 1135, cy + 235)
arrow(c2x + 540, cy + 335, c2x + 720, cy + 292, GREEN)
arrow(c2x + 1030, cy + 292, c2x + 1185, cy + 292, GREEN)
arrow(c2x + 1570, cy + 292, c2x + 540, cy + 335, GREEN)
arrow(c2x + 540, cy + 335, c2x + 720, cy + 482, GREEN)
arrow(c2x + 1030, cy + 482, c2x + 1185, cy + 482, GREEN)
arrow(c2x + 1570, cy + 482, c2x + 540, cy + 335, GREEN)
bullets(
    c2x + 90,
    r1y + r1h - 210,
    c2w - 180,
    [
        "Control plane: RV32I configures DMA registers, writes IV, starts TX/RX, and polls status.",
        "Data plane: DMA and accelerators move data between DMEM, Huffman, and AES blocks.",
    ],
    F_SMALL,
    gap=12,
)


# 4 Accelerator design with thesis flow image
cy = section(c2x, r2y, c2w, r2h, 4, "TX ACCELERATOR DESIGN", 930)
d.rounded_rectangle((c2x + 65, cy + 5, c2x + c2w - 65, cy + 745), radius=16, fill=PALE_BLUE, outline=GRID, width=3)
paste_fit(MEDIA / "image12.png", (c2x + 90, cy + 25, c2w - 180, 690), pad=6, bg=PALE_BLUE)
bullets(
    c2x + 85,
    cy + 780,
    c2w - 160,
    [
        "The current RTL builds one Huffman table for the whole file.",
        "The first emitted block carries the full table; later blocks reuse the same codebook with compact headers.",
        "The packed transport words are encrypted by AES-128-CBC or bypassed in COMPRESS_ONLY mode.",
    ],
    F_SMALL,
    gap=10,
)


# 5 Verification results
cy = section(c3x, r1y, c3w, r1h, 5, "VERIFICATION RESULTS", 800)
node(c3x + 80, cy + 20, 250, 90, "Firmware C")
node(c3x + 390, cy + 20, 255, 90, "Questa RTL\nSimulation")
node(c3x + 710, cy + 20, 250, 90, "DMEM Dump\nCompare")
node(c3x + 1020, cy + 20, 245, 90, "PASS/FAIL\nReport")
for x in (c3x + 330, c3x + 645, c3x + 960):
    arrow(x, cy + 65, x + 55, cy + 65)
card_y = cy + 160
cw = (c3w - 150) // 2
stat(c3x + 60, card_y, cw, 155, "18/0", "TX-RX loopback", GREEN)
stat(c3x + 90 + cw, card_y, cw, 155, "15/0", "Huffman-only input1", GREEN)
stat(c3x + 60, card_y + 180, cw, 155, "22/0", "Storage table", GREEN)
stat(c3x + 90 + cw, card_y + 180, cw, 155, "34/34", "Regression baseline", GREEN)
bullets(
    c3x + 70,
    card_y + 390,
    c3w - 120,
    [
        "RX restored plaintext matches the original source data.",
        "Storage-table test stores multiple records and selects one by file_id.",
        "Closed DUT coverage reported in thesis: 95.90%.",
    ],
    F_SMALL,
)


# 6 Conclusion / future work from thesis
cy = section(c3x, r2y, c3w, r2h, 6, "CONCLUSION & FUTURE WORK", 900)
bullets(
    c3x + 70,
    cy + 25,
    c3w - 120,
    [
        "The thesis presented an RV32I system integrating dynamic Huffman compression and AES-128-CBC encryption for secure data storage.",
        "The secure-storage firmware manages metadata records, file identifiers, plaintext/ciphertext lengths, and IV values.",
        "The design is functionally verified, FPGA-implementable, and suitable for compact embedded secure data storage.",
    ],
    F_BODY,
)
d.rounded_rectangle((c3x + 60, r2y + r2h - 490, c3x + c3w - 60, r2y + r2h - 65), radius=18, fill=PALE_BLUE, outline=GRID, width=3)
d.text((c3x + 95, r2y + r2h - 450), "Future work", font=F_HEAD, fill=DARK_BLUE)
bullets(
    c3x + 95,
    r2y + r2h - 385,
    c3w - 190,
    [
        "Use stronger random or nonce-management mechanism for IV generation.",
        "Add authentication tag to detect malicious ciphertext modification.",
        "Optimize RX decoder resources and extend the number of storage records.",
    ],
    F_SMALL,
)


# 8 Performance chart from thesis
perf_w = c1w + G + 1180
cy = section(c1x, r3y, perf_w, r3h, 8, "PERFORMANCE COMPARISON", 820)
stat(c1x + 55, cy + 25, 360, 155, "145.5", "MB/s AES @100MHz", ORANGE)
stat(c1x + 445, cy + 25, 360, 155, "0.078", "B/cycle TX path", ORANGE)
stat(c1x + 835, cy + 25, 360, 155, "65.50%", "input1 storage saving", GREEN)
stat(c1x + 1225, cy + 25, 360, 155, "70.13%", "raw ECG storage saving", GREEN)
d.rounded_rectangle((c1x + 1625, cy + 20, c1x + perf_w - 55, cy + 555), radius=18, fill=WHITE, outline=GRID, width=3)
paste_fit(MEDIA / "image21.png", (c1x + 1645, cy + 42, perf_w - 1720, 500), pad=5, bg=WHITE)
bullets(
    c1x + 60,
    r3y + r3h - 135,
    perf_w - 120,
    [
        "The proposed design balances hardware speed, compression efficiency, and secure-storage functionality.",
    ],
    F_SMALL_B,
)


# 9 References from thesis scope
cy = section(c1x + perf_w + G, r3y, W - (c1x + perf_w + G) - M, r3h, 9, "THESIS SOURCES", 700)
bullets(
    c1x + perf_w + G + 55,
    cy + 10,
    W - (c1x + perf_w + G) - M - 110,
    [
        "Graduation_Thesis_an_tan.docx: Chapter 1 overview and objectives.",
        "Chapter 3: RV32I secure-storage SoC architecture and TX/RX datapaths.",
        "Chapter 4: verification, performance comparison, and FPGA implementation results.",
        "Chapter 5: conclusion, limitations, and future work.",
    ],
    F_SMALL,
)

d.line((60, H - 54, W - 60, H - 54), fill=BLUE, width=10)
d.text((W - 605, H - 42), "A1 poster draft from thesis content only", font=F_TINY_B, fill=DARK_BLUE)


OUT.mkdir(parents=True, exist_ok=True)
full = OUT / "rv32i_huffman_aes_a1_thesis_only_font32_36.png"
preview = OUT / "rv32i_huffman_aes_a1_thesis_only_font32_36_preview.png"
pdf = OUT / "rv32i_huffman_aes_a1_thesis_only_font32_36.pdf"
img.save(full, quality=95)
small = img.copy()
small.thumbnail((1800, 1272), Image.Resampling.LANCZOS)
small.save(preview, quality=92)
img.save(pdf, "PDF", resolution=150.0)
print(full)
print(preview)
print(pdf)
