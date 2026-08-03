# -*- coding: utf-8 -*-
from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(r"H:\Academic\senior_project\DATN")
DOCS = ROOT / "docs"
MEDIA = DOCS / "_media_extract"
OUT_DIR = DOCS / "poster_a1_canva"

W, H = 4960, 3508  # A1 landscape, Canva-friendly high-resolution PNG

BLUE = (0, 56, 155)
DARK_BLUE = (0, 38, 115)
MID_BLUE = (0, 92, 185)
LIGHT_BLUE = (229, 241, 255)
PALE_BLUE = (246, 250, 255)
ORANGE = (245, 139, 34)
GREEN = (34, 151, 98)
RED = (216, 76, 76)
GRAY = (76, 84, 96)
GRID = (196, 219, 242)
BLACK = (24, 30, 40)
WHITE = (255, 255, 255)


def font_file(*names: str) -> str:
    font_dir = Path(r"C:\Windows\Fonts")
    for name in names:
        path = font_dir / name
        if path.exists():
            return str(path)
    return str(font_dir / "arial.ttf")


def fnt(size: int, bold: bool = False, serif: bool = False) -> ImageFont.FreeTypeFont:
    if serif:
        return ImageFont.truetype(font_file("timesbd.ttf", "georgiab.ttf", "arialbd.ttf"), size)
    if bold:
        return ImageFont.truetype(font_file("arialbd.ttf", "calibrib.ttf", "Aptos-Bold.ttf"), size)
    return ImageFont.truetype(font_file("arial.ttf", "calibri.ttf", "Aptos.ttf"), size)


F = {
    "title": fnt(78, bold=True, serif=True),
    "uni": fnt(27, bold=True),
    "section": fnt(34, bold=True),
    "section_small": fnt(29, bold=True),
    "body": fnt(28),
    "body_bold": fnt(28, bold=True),
    "small": fnt(23),
    "small_bold": fnt(23, bold=True),
    "tiny": fnt(19),
    "tiny_bold": fnt(19, bold=True),
    "stat": fnt(46, bold=True),
    "stat_label": fnt(22, bold=True),
}


img = Image.new("RGB", (W, H), WHITE)
d = ImageDraw.Draw(img)


def text_size(text: str, font: ImageFont.FreeTypeFont) -> tuple[int, int]:
    box = d.textbbox((0, 0), text, font=font)
    return box[2] - box[0], box[3] - box[1]


def wrap(text: str, font: ImageFont.FreeTypeFont, width: int) -> list[str]:
    words = text.split()
    lines: list[str] = []
    cur = ""
    for word in words:
        test = word if not cur else cur + " " + word
        if text_size(test, font)[0] <= width:
            cur = test
        else:
            if cur:
                lines.append(cur)
            cur = word
    if cur:
        lines.append(cur)
    return lines


def draw_wrapped(
    x: int,
    y: int,
    width: int,
    text: str,
    font: ImageFont.FreeTypeFont,
    fill=BLACK,
    line_gap: int = 7,
    max_lines: int | None = None,
) -> int:
    lines = wrap(text, font, width)
    if max_lines is not None:
        lines = lines[:max_lines]
    yy = y
    for line in lines:
        d.text((x, yy), line, font=font, fill=fill)
        yy += text_size(line, font)[1] + line_gap
    return yy


def draw_bullets(x: int, y: int, width: int, items: list[str], font=F["small"], gap: int = 12) -> int:
    yy = y
    for item in items:
        d.ellipse((x, yy + 10, x + 11, yy + 21), fill=BLUE)
        yy = draw_wrapped(x + 25, yy, width - 25, item, font, BLACK, line_gap=5)
        yy += gap
    return yy


def rounded_rect(x: int, y: int, w: int, h: int, radius: int = 18, fill=WHITE, outline=BLUE, width: int = 4):
    d.rounded_rectangle((x, y, x + w, y + h), radius=radius, fill=fill, outline=outline, width=width)


def section_box(x: int, y: int, w: int, h: int, number: int, title: str, header_w: int | None = None) -> int:
    rounded_rect(x, y, w, h, radius=18, fill=WHITE, outline=(39, 145, 225), width=4)
    header_h = 78
    hw = header_w or min(w - 28, int(w * 0.72))
    d.rounded_rectangle((x, y, x + hw, y + header_h), radius=16, fill=BLUE)
    d.rectangle((x, y + header_h // 2, x + hw, y + header_h), fill=BLUE)
    label = f"{number}. {title}"
    font = F["section"] if len(label) <= 34 else F["section_small"]
    d.text((x + 34, y + 18), label, font=font, fill=WHITE)
    return y + header_h + 25


def arrow(x1: int, y1: int, x2: int, y2: int, fill=BLUE, width: int = 6):
    d.line((x1, y1, x2, y2), fill=fill, width=width)
    angle = math.atan2(y2 - y1, x2 - x1)
    length = 24
    pts = [
        (x2, y2),
        (x2 - length * math.cos(angle - math.pi / 7), y2 - length * math.sin(angle - math.pi / 7)),
        (x2 - length * math.cos(angle + math.pi / 7), y2 - length * math.sin(angle + math.pi / 7)),
    ]
    d.polygon(pts, fill=fill)


def flow_node(x: int, y: int, w: int, h: int, text: str, fill=LIGHT_BLUE, outline=BLUE):
    d.rounded_rectangle((x, y, x + w, y + h), radius=14, fill=fill, outline=outline, width=3)
    lines = wrap(text, F["small_bold"], w - 28)
    total_h = sum(text_size(line, F["small_bold"])[1] for line in lines) + max(0, len(lines) - 1) * 5
    yy = y + (h - total_h) / 2
    for line in lines:
        tw, th = text_size(line, F["small_bold"])
        d.text((x + (w - tw) / 2, yy), line, font=F["small_bold"], fill=DARK_BLUE)
        yy += th + 5


def paste_fit(path: Path, box: tuple[int, int, int, int], pad: int = 0, bg=WHITE):
    if not path.exists():
        return
    source = Image.open(path).convert("RGB")
    x, y, w, h = box
    source.thumbnail((w - 2 * pad, h - 2 * pad), Image.Resampling.LANCZOS)
    canvas = Image.new("RGB", (w, h), bg)
    canvas.paste(source, ((w - source.width) // 2, (h - source.height) // 2))
    img.paste(canvas, (x, y))


def stat_card(x: int, y: int, w: int, h: int, value: str, label: str, color=BLUE):
    d.rounded_rectangle((x, y, x + w, y + h), radius=18, fill=PALE_BLUE, outline=GRID, width=3)
    tw, _ = text_size(value, F["stat"])
    d.text((x + (w - tw) / 2, y + 22), value, font=F["stat"], fill=color)
    yy = y + 92
    for line in wrap(label, F["stat_label"], w - 28)[:2]:
        tw, th = text_size(line, F["stat_label"])
        d.text((x + (w - tw) / 2, yy), line, font=F["stat_label"], fill=BLACK)
        yy += th + 5


# Outer frame
rounded_rect(18, 18, W - 36, H - 36, radius=4, fill=WHITE, outline=(40, 40, 40), width=3)

# Header
logo_path = MEDIA / "image1.jpeg"
if logo_path.exists():
    logo = Image.open(logo_path).convert("RGB")
    logo.thumbnail((310, 250), Image.Resampling.LANCZOS)
    img.paste(logo, (78, 62))

d.text((410, 70), "TRƯỜNG ĐẠI HỌC SƯ PHẠM KỸ THUẬT", font=F["uni"], fill=DARK_BLUE)
d.text((410, 112), "THÀNH PHỐ HỒ CHÍ MINH", font=F["uni"], fill=DARK_BLUE)
d.text((410, 166), "KHOA ĐIỆN - ĐIỆN TỬ", font=F["small_bold"], fill=DARK_BLUE)
d.text((410, 205), "BỘ MÔN KỸ THUẬT MÁY TÍNH - VIỄN THÔNG", font=F["small_bold"], fill=DARK_BLUE)
d.line((1325, 58, 1325, 318), fill=DARK_BLUE, width=5)

title = [
    "THIẾT KẾ VÀ ĐÁNH GIÁ HỆ THỐNG LƯU TRỮ AN TOÀN",
    "TRÊN RV32I TÍCH HỢP NÉN HUFFMAN ĐỘNG",
    "VÀ MÃ HÓA AES-128-CBC",
]
yy = 50
for line in title:
    tw, th = text_size(line, F["title"])
    d.text(((W - tw) / 2 + 115, yy), line, font=F["title"], fill=DARK_BLUE)
    yy += 83

right_x = 4070
for y, label in [(78, "GVHD"), (190, "SVTH")]:
    d.ellipse((right_x, y, right_x + 86, y + 86), fill=DARK_BLUE)
    if label == "GVHD":
        d.ellipse((right_x + 31, y + 19, right_x + 55, y + 43), fill=WHITE)
        d.rounded_rectangle((right_x + 19, y + 49, right_x + 67, y + 70), radius=10, fill=WHITE)
    else:
        d.polygon([(right_x + 18, y + 34), (right_x + 43, y + 20), (right_x + 68, y + 34), (right_x + 43, y + 50)], fill=WHITE)
        d.rectangle((right_x + 28, y + 44, right_x + 58, y + 62), fill=WHITE)

d.text((4180, 58), "GVHD:", font=F["small_bold"], fill=DARK_BLUE)
d.text((4180, 98), "PGS.TS. Đỗ Duy Tân", font=F["small_bold"], fill=BLACK)
d.text((4180, 170), "SVTH:", font=F["small_bold"], fill=DARK_BLUE)
d.text((4180, 208), "Ngô Quốc An      - 21161226", font=F["tiny_bold"], fill=BLACK)
d.text((4180, 242), "Bùi Ngọc Duy Tân - 21161266", font=F["tiny_bold"], fill=BLACK)


# Grid
M, G = 60, 34
Y0 = 370
col1_x, col1_w = M, 1392
col2_x, col2_w = col1_x + col1_w + G, 1990
col3_x, col3_w = col2_x + col2_w + G, W - M - (col2_x + col2_w + G)
row1_y, row1_h = Y0, 900
row2_y, row2_h = row1_y + row1_h + G, 1320
row3_y, row3_h = row2_y + row2_h + G, H - row2_y - row2_h - G - 70


# 1. Abstract / problem
cy = section_box(col1_x, row1_y, col1_w, row1_h, 1, "TÓM TẮT / ĐẶT VẤN ĐỀ", header_w=850)
cx, sy = col1_x + 190, cy + 130
d.ellipse((cx - 118, sy - 118, cx + 118, sy + 118), outline=(190, 223, 248), width=6)
d.polygon([(cx, sy - 94), (cx + 82, sy - 50), (cx + 63, sy + 76), (cx, sy + 118), (cx - 63, sy + 76), (cx - 82, sy - 50)], fill=LIGHT_BLUE, outline=BLUE)
d.rounded_rectangle((cx - 45, sy - 12, cx + 45, sy + 65), radius=12, fill=BLUE)
d.rectangle((cx - 33, sy - 36, cx + 33, sy + 8), outline=BLUE, width=12)
d.ellipse((cx - 8, sy + 16, cx + 8, sy + 32), fill=WHITE)
d.rectangle((cx - 4, sy + 30, cx + 4, sy + 50), fill=WHITE)
draw_bullets(
    col1_x + 395,
    cy + 35,
    col1_w - 455,
    [
        "Hệ thống nhúng cần lưu trữ dữ liệu cảm biến an toàn nhưng bộ nhớ và tài nguyên phần cứng bị giới hạn.",
        "Nén Huffman giảm kích thước dữ liệu trước khi mã hóa, giúp tiết kiệm vùng lưu trữ.",
        "AES-128-CBC bảo vệ dữ liệu sau nén trước khi ghi vào DMEM.",
        "RV32I được dùng làm control plane để cấu hình DMA, IV, metadata và đọc lại file theo file_id.",
    ],
    F["small"],
    gap=14,
)


# 2. Objectives
sec2_h = 650
cy = section_box(col1_x, row2_y, col1_w, sec2_h, 2, "MỤC TIÊU & CƠ SỞ", header_w=650)
d.text((col1_x + 70, cy + 5), "CƠ SỞ LÝ THUYẾT", font=F["small_bold"], fill=DARK_BLUE)
draw_bullets(
    col1_x + 70,
    cy + 55,
    col1_w - 140,
    [
        "Dynamic Huffman: nén lossless dựa trên tần suất byte.",
        "AES-128-CBC: mã hóa block 128-bit với IV và chuỗi ciphertext.",
        "MMIO/APB + DMA: CPU cấu hình, DMA di chuyển dữ liệu giữa DMEM và accelerator.",
    ],
    F["tiny"],
    gap=9,
)
d.text((col1_x + 70, cy + 292), "MỤC TIÊU THIẾT KẾ", font=F["small_bold"], fill=DARK_BLUE)
draw_bullets(
    col1_x + 70,
    cy + 342,
    col1_w - 140,
    [
        "Thiết kế SoC RV32I có luồng TX secure-write và RX secure-read.",
        "Tích hợp Huffman compression, bit packing và AES-128-CBC trong RTL.",
        "Quản lý metadata: file_id, địa chỉ, độ dài plaintext/ciphertext và IV.",
        "Đánh giá bằng Questa simulation và triển khai FPGA ZCU102.",
    ],
    F["tiny"],
    gap=9,
)


# 7. FPGA summary
cy = section_box(col1_x, row2_y + sec2_h + G, col1_w, row2_h - sec2_h - G, 7, "THÔNG SỐ HIỆN THỰC FPGA", header_w=860)
stat_card(col1_x + 55, cy + 10, 295, 150, "300", "MHz external clock", BLUE)
stat_card(col1_x + 380, cy + 10, 295, 150, "50", "MHz SoC clock", BLUE)
stat_card(col1_x + 705, cy + 10, 295, 150, "+10.862", "ns setup WNS", GREEN)
stat_card(col1_x + 1030, cy + 10, 295, 150, "~0.78W", "estimated power", ORANGE)
x0, y0 = col1_x + 65, cy + 210
table_w, table_h = col1_w - 130, 300
cols = [0, 330, 620, 890, table_w]
d.rectangle((x0, y0, x0 + table_w, y0 + table_h), outline=BLUE, width=3)
d.rectangle((x0, y0, x0 + table_w, y0 + 60), fill=BLUE)
for i, label in enumerate(["Block", "LUTs", "FF", "BRAM"]):
    d.text((x0 + cols[i] + 18, y0 + 17), label, font=F["tiny_bold"], fill=WHITE)
for c in cols[1:-1]:
    d.line((x0 + c, y0, x0 + c, y0 + table_h), fill=GRID, width=2)
for r in range(60, table_h, 60):
    d.line((x0, y0 + r, x0 + table_w, y0 + r), fill=GRID, width=2)
rows = [
    ("TX accelerator", "10,734", "2,806", "0"),
    ("RX accelerator", "21,253", "13,163", "1"),
    ("DMEM/IMEM", "56", "0", "10"),
    ("Full FPGA SoC", "36,649", "20,017", "11"),
]
for idx, row in enumerate(rows):
    yy = y0 + 60 * (idx + 1) + 16
    d.text((x0 + 18, yy), row[0], font=F["tiny_bold"] if idx == 3 else F["tiny"], fill=BLACK)
    for cidx in range(1, 4):
        d.text((x0 + cols[cidx] + 18, yy), row[cidx], font=F["tiny"], fill=BLACK)


# 3. System architecture
cy = section_box(col2_x, row1_y, col2_w, row1_h, 3, "KIẾN TRÚC HỆ THỐNG RV32I SECURE-STORAGE SOC", header_w=1320)
base_y = cy + 45
flow_node(col2_x + 70, base_y + 25, 310, 115, "RV32I CPU")
flow_node(col2_x + 500, base_y + 25, 340, 115, "MMIO/APB Bridge")
flow_node(col2_x + 960, base_y + 25, 380, 115, "DMA Register File + IV")
arrow(col2_x + 380, base_y + 82, col2_x + 500, base_y + 82)
arrow(col2_x + 840, base_y + 82, col2_x + 960, base_y + 82)
flow_node(col2_x + 150, base_y + 270, 380, 135, "DMEM\nInput / Cipher / Output", fill=(255, 248, 230), outline=ORANGE)
flow_node(col2_x + 720, base_y + 240, 310, 110, "TX DMA", fill=(232, 250, 242), outline=GREEN)
flow_node(col2_x + 720, base_y + 430, 310, 110, "RX DMA", fill=(232, 250, 242), outline=GREEN)
flow_node(col2_x + 1180, base_y + 230, 390, 120, "TX Accelerator\nHuffman + AES-CBC")
flow_node(col2_x + 1180, base_y + 425, 390, 120, "RX Accelerator\nAES-CBC + Huffman")
flow_node(col2_x + 1650, base_y + 330, 280, 125, "Metadata\nfile_id / length / IV", fill=(246, 238, 255), outline=(120, 80, 200))
arrow(col2_x + 1150, base_y + 82, col2_x + 1150, base_y + 230)
arrow(col2_x + 530, base_y + 337, col2_x + 720, base_y + 295, fill=GREEN)
arrow(col2_x + 1030, base_y + 295, col2_x + 1180, base_y + 290, fill=GREEN)
arrow(col2_x + 1570, base_y + 290, col2_x + 530, base_y + 337, fill=GREEN)
arrow(col2_x + 530, base_y + 337, col2_x + 720, base_y + 485, fill=GREEN)
arrow(col2_x + 1030, base_y + 485, col2_x + 1180, base_y + 485, fill=GREEN)
arrow(col2_x + 1570, base_y + 485, col2_x + 530, base_y + 337, fill=GREEN)
arrow(col2_x + 1340, base_y + 140, col2_x + 1695, base_y + 330, fill=(120, 80, 200))
d.text((col2_x + 85, row1_y + row1_h - 190), "Luồng ghi:", font=F["small_bold"], fill=DARK_BLUE)
draw_wrapped(col2_x + 230, row1_y + row1_h - 193, 820, "Plaintext → Huffman compression → Bit packing → AES-128-CBC → Ciphertext", F["small"], fill=BLACK)
d.text((col2_x + 85, row1_y + row1_h - 108), "Luồng đọc:", font=F["small_bold"], fill=DARK_BLUE)
draw_wrapped(col2_x + 230, row1_y + row1_h - 111, 850, "Ciphertext → AES-CBC decrypt → Huffman decode → Restored plaintext", F["small"], fill=BLACK)
d.text((col2_x + 1190, row1_y + row1_h - 150), "CPU quản lý storage policy; RTL xử lý dữ liệu.", font=F["small_bold"], fill=ORANGE)


# 4. Accelerator architecture from thesis figures
cy = section_box(col2_x, row2_y, col2_w, row2_h, 4, "KIẾN TRÚC BỘ TĂNG TỐC HUFFMAN + AES", header_w=1230)
px, py = col2_x + 90, cy + 5
node_w, node_h, gap = 246, 82, 50
for i, label in enumerate(["Plaintext", "Huffman\nCompression", "Bit Packer", "AES-CBC\nEncryption", "Ciphertext"]):
    flow_node(px + i * (node_w + gap), py, node_w, node_h, label, fill=BLUE if i in (0, 4) else LIGHT_BLUE)
    if i < 4:
        arrow(px + i * (node_w + gap) + node_w, py + node_h // 2, px + (i + 1) * (node_w + gap) - 8, py + node_h // 2, width=5)

d.rounded_rectangle((col2_x + 70, cy + 145, col2_x + 1918, cy + 780), radius=16, fill=PALE_BLUE, outline=GRID, width=3)
paste_fit(MEDIA / "image12.png", (col2_x + 95, cy + 165, 1800, 585), pad=8, bg=PALE_BLUE)
d.text((col2_x + 120, cy + 790), "Hình từ thesis: whole-file Huffman + AES-CBC compression flow implemented by TX RTL.", font=F["tiny_bold"], fill=DARK_BLUE)
d.text((col2_x + 85, cy + 850), "Vai trò các khối chính", font=F["small_bold"], fill=DARK_BLUE)
draw_bullets(
    col2_x + 85,
    cy + 902,
    col2_w - 160,
    [
        "Pass 1 đọc toàn bộ file để xây dựng frequency table và canonical Huffman codebook.",
        "Pass 2 tái sử dụng codebook để phát payload bits, pack thành 128-bit transport words.",
        "AES-CBC mã hóa transport words; COMPRESS_ONLY có thể bypass AES để đánh giá riêng Huffman.",
    ],
    F["small"],
    gap=10,
)


# 5. Verification
cy = section_box(col3_x, row1_y, col3_w, row1_h, 5, "KIỂM CHỨNG & KẾT QUẢ MÔ PHỎNG", header_w=990)
flow_node(col3_x + 70, cy + 15, 250, 90, "Firmware C", fill=PALE_BLUE)
flow_node(col3_x + 380, cy + 15, 255, 90, "Questa RTL\nSimulation", fill=PALE_BLUE)
flow_node(col3_x + 700, cy + 15, 250, 90, "DMEM Dump\nCompare", fill=PALE_BLUE)
flow_node(col3_x + 1010, cy + 15, 245, 90, "PASS/FAIL\nReport", fill=PALE_BLUE)
for x in [col3_x + 320, col3_x + 635, col3_x + 950]:
    arrow(x, cy + 60, x + 55, cy + 60, width=5)
card_y = cy + 150
card_w = (col3_w - 150) // 2
stat_card(col3_x + 60, card_y, card_w, 165, "18/0", "TX-RX loopback PASS/FAIL", GREEN)
stat_card(col3_x + 90 + card_w, card_y, card_w, 165, "15/0", "Huffman-only input1", GREEN)
stat_card(col3_x + 60, card_y + 190, card_w, 165, "22/0", "Storage table PASS/FAIL", GREEN)
stat_card(col3_x + 90 + card_w, card_y + 190, card_w, 165, "34/34", "Regression baseline", GREEN)
draw_bullets(
    col3_x + 70,
    card_y + 410,
    col3_w - 120,
    [
        "RX output khớp dữ liệu nguồn: src_mismatch=0 và rx_mismatch=0.",
        "Storage table lưu nhiều record và đọc đúng file theo file_id.",
        "Closed DUT coverage trong regression report đạt 95.90%.",
    ],
    F["small"],
    gap=14,
)


# 6. Conclusion/future work
cy = section_box(col3_x, row2_y, col3_w, row2_h, 6, "KẾT LUẬN & HƯỚNG PHÁT TRIỂN", header_w=935)
items = [
    "Hoàn thành SoC RV32I secure-storage với đầy đủ TX/RX path.",
    "Firmware quản lý file_id, metadata, IV và DMA polling.",
    "Các testcase chính xác nhận dữ liệu khôi phục khớp input ban đầu.",
    "Thiết kế triển khai được trên FPGA ZCU102 và thỏa timing constraints.",
]
yy = cy + 22
for text in items:
    d.ellipse((col3_x + 70, yy, col3_x + 128, yy + 58), fill=GREEN)
    d.text((col3_x + 88, yy + 8), "✓", font=F["body_bold"], fill=WHITE)
    yy = draw_wrapped(col3_x + 155, yy + 5, col3_w - 220, text, F["small"], BLACK)
    yy += 26
d.rounded_rectangle((col3_x + 60, row2_y + row2_h - 455, col3_x + col3_w - 60, row2_y + row2_h - 60), radius=18, fill=PALE_BLUE, outline=GRID, width=3)
d.text((col3_x + 95, row2_y + row2_h - 422), "Hướng phát triển", font=F["small_bold"], fill=DARK_BLUE)
draw_bullets(
    col3_x + 95,
    row2_y + row2_h - 360,
    col3_w - 190,
    [
        "Bổ sung TRNG/nonce policy và cơ chế quản lý khóa an toàn hơn.",
        "Thêm authentication tag để phát hiện chỉnh sửa ciphertext.",
        "Mở rộng số record lưu trữ và tối ưu tài nguyên RX decoder.",
    ],
    F["tiny"],
    gap=10,
)


# 8. Performance comparison with thesis chart
perf_w = col1_w + G + 1180
cy = section_box(col1_x, row3_y, perf_w, row3_h, 8, "HIỆU NĂNG & SO SÁNH", header_w=760)
stat_card(col1_x + 55, cy + 20, 360, 165, "145.5", "MB/s AES @100MHz", ORANGE)
stat_card(col1_x + 445, cy + 20, 360, 165, "0.078", "B/cycle TX secure-storage", ORANGE)
stat_card(col1_x + 835, cy + 20, 360, 165, "65.50%", "input1 storage saving", GREEN)
stat_card(col1_x + 1225, cy + 20, 360, 165, "70.13%", "raw ECG storage saving", GREEN)
d.rounded_rectangle((col1_x + 1625, cy + 20, col1_x + perf_w - 55, cy + 555), radius=18, fill=WHITE, outline=GRID, width=3)
paste_fit(MEDIA / "image21.png", (col1_x + 1640, cy + 38, perf_w - 1700, 510), pad=8, bg=WHITE)
draw_wrapped(
    col1_x + 60,
    row3_y + row3_h - 118,
    perf_w - 120,
    "Kết quả cho thấy thiết kế đạt cân bằng giữa tốc độ phần cứng, hiệu quả nén và khả năng lưu trữ bảo mật trên FPGA.",
    F["small_bold"],
    fill=DARK_BLUE,
)


# 9. References
cy = section_box(col1_x + perf_w + G, row3_y, W - (col1_x + perf_w + G) - M, row3_h, 9, "TÀI LIỆU THAM KHẢO", header_w=690)
refs = [
    "[1] RISC-V Unprivileged ISA Specification, RV32I base integer ISA.",
    "[2] NIST FIPS-197, Advanced Encryption Standard (AES).",
    "[3] D. Salomon, Data Compression: The Complete Reference.",
    "[4] M. E. Hameed et al., ECG Huffman Coding and CBC-AES, 2019.",
    "[5] Graduation_Thesis_an_tan.docx and project RTL/docs.",
]
yy = cy + 10
for ref in refs:
    yy = draw_wrapped(col1_x + perf_w + G + 55, yy, W - (col1_x + perf_w + G) - M - 110, ref, F["tiny"], BLACK, line_gap=5)
    yy += 20


d.line((60, H - 54, W - 60, H - 54), fill=BLUE, width=10)
d.text((W - 635, H - 42), "Graduation Project Poster - A1 Landscape", font=F["tiny_bold"], fill=DARK_BLUE)


OUT_DIR.mkdir(parents=True, exist_ok=True)
full = OUT_DIR / "rv32i_huffman_aes_a1_poster_from_thesis.png"
preview = OUT_DIR / "rv32i_huffman_aes_a1_poster_from_thesis_preview.png"
pdf = OUT_DIR / "rv32i_huffman_aes_a1_poster_from_thesis.pdf"
img.save(full, quality=95)
small = img.copy()
small.thumbnail((1800, 1272), Image.Resampling.LANCZOS)
small.save(preview, quality=92)
img.save(pdf, "PDF", resolution=150.0)
print("done")
