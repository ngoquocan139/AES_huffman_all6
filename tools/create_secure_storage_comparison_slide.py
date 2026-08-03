from pathlib import Path
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "docs" / "generated_figures"
OUT_DIR.mkdir(parents=True, exist_ok=True)

W, H = 1920, 1080

BLUE = "#0737B8"
BLUE_DARK = "#052A8A"
BLUE_LIGHT = "#EAF1FF"
GRID = "#B9C8E6"
TEXT = "#102033"
MUTED = "#5A6B80"
GREEN = "#159B8A"
RED = "#C93A4A"
ORANGE = "#F28C28"
WHITE = "#FFFFFF"
BG = "#F6F9FF"

FONT_DIR = Path("C:/Windows/Fonts")
FONT_REG = FONT_DIR / "arial.ttf"
FONT_BOLD = FONT_DIR / "arialbd.ttf"
FONT_SYMBOL = FONT_DIR / "seguisym.ttf"


def font(size, bold=False, symbol=False):
    path = FONT_SYMBOL if symbol and FONT_SYMBOL.exists() else (FONT_BOLD if bold else FONT_REG)
    return ImageFont.truetype(str(path), size)


F_NAV = font(28, bold=True)
F_TITLE = font(42, bold=True)
F_HEAD = font(25, bold=True)
F_CELL = font(24)
F_CELL_B = font(24, bold=True)
F_NOTE = font(24)
F_SMALL = font(19)
F_SMALL_B = font(19, bold=True)
F_MARK = font(34, symbol=True)
F_STAR = font(35, symbol=True)


def rounded(draw, xy, r, fill, outline=None, width=1):
    draw.rounded_rectangle(xy, radius=r, fill=fill, outline=outline, width=width)


def text_center(draw, box, value, fnt, fill=TEXT, spacing=4):
    x0, y0, x1, y1 = box
    lines = value.split("\n")
    heights = []
    widths = []
    for line in lines:
        bb = draw.textbbox((0, 0), line, font=fnt)
        widths.append(bb[2] - bb[0])
        heights.append(bb[3] - bb[1])
    total_h = sum(heights) + spacing * (len(lines) - 1)
    y = y0 + (y1 - y0 - total_h) / 2 - 1
    for line, w, h in zip(lines, widths, heights):
        draw.text((x0 + (x1 - x0 - w) / 2, y), line, font=fnt, fill=fill)
        y += h + spacing


def text_left(draw, box, value, fnt, fill=TEXT, spacing=4):
    x0, y0, x1, y1 = box
    lines = value.split("\n")
    heights = []
    for line in lines:
        bb = draw.textbbox((0, 0), line, font=fnt)
        heights.append(bb[3] - bb[1])
    total_h = sum(heights) + spacing * (len(lines) - 1)
    y = y0 + (y1 - y0 - total_h) / 2 - 1
    for line, h in zip(lines, heights):
        draw.text((x0, y), line, font=fnt, fill=fill)
        y += h + spacing


def mark(draw, box, kind):
    if kind == "yes":
        text_center(draw, box, "✓", F_MARK, GREEN)
    elif kind == "no":
        text_center(draw, box, "✕", F_MARK, RED)
    elif kind == "partial":
        text_center(draw, box, "◐", F_MARK, ORANGE)
    elif kind == "star":
        text_center(draw, box, "★", F_STAR, ORANGE)
    elif kind == "dot":
        text_center(draw, box, "●", F_MARK, GREEN)


def draw_nav(draw):
    y = 40
    h = 68
    rounded(draw, (95, y, 1825, y + h), 12, BLUE, BLUE_DARK, 2)
    items = [
        ("I. TỔNG QUAN", True),
        ("II. CƠ SỞ LÝ THUYẾT", False),
        ("III. THIẾT KẾ HỆ THỐNG", False),
        ("IV. KẾT QUẢ", False),
        ("V. KẾT LUẬN", False),
    ]
    x = 120
    widths = [270, 365, 430, 250, 250]
    for (label, active), w in zip(items, widths):
        if active:
            rounded(draw, (x, y + 10, x + w, y + h - 10), 7, WHITE, "#D9E6FF", 1)
            text_center(draw, (x, y + 10, x + w, y + h - 10), label, F_NAV, BLUE_DARK)
        else:
            text_center(draw, (x, y + 10, x + w, y + h - 10), label, F_NAV, WHITE)
        x += w + 18


def draw_title(draw):
    draw.text((120, 160), "4.", font=F_TITLE, fill=BLUE_DARK)
    draw.text((190, 160), "So sánh ứng dụng và tính năng", font=F_TITLE, fill=BLUE_DARK)
    draw.line((190, 222, 345, 222), fill=BLUE, width=5)


def draw_table(draw):
    x0, y0 = 165, 270
    table_w, table_h = 1590, 585
    col_w = [420, 265, 265, 265, 255, 120]
    row_h = [76] + [56] * 9

    headers = [
        "Ứng dụng / tính năng",
        "Software\nAES/Huffman [1]",
        "AES-only\nhardware IP [2]",
        "ECG secure\ncompression [3]",
        "Đề tài này",
        "Nhận\nxét",
    ]
    rows = [
        ("Lưu trữ dữ liệu nhúng bảo mật", "partial", "no", "yes", "yes", "star"),
        ("Nén dữ liệu trước khi lưu", "yes", "no", "yes", "yes", "star"),
        ("Mã hóa AES-CBC bảo vệ dữ liệu", "yes", "partial", "yes", "yes", "star"),
        ("Giải mã và khôi phục plaintext", "yes", "partial", "partial", "yes", "dot"),
        ("Quản lý file_id, metadata và IV", "no", "no", "partial", "yes", "star"),
        ("Phù hợp IoT / data logger", "partial", "no", "yes", "yes", "star"),
        ("Chạy thử trên FPGA board", "no", "yes", "no", "yes", "dot"),
        ("Kiểm chứng đúng dữ liệu RX", "partial", "partial", "partial", "yes", "dot"),
        ("Có số liệu throughput/resource", "partial", "yes", "partial", "yes", "dot"),
    ]

    draw.rounded_rectangle((x0, y0, x0 + table_w, y0 + table_h), radius=8, fill=WHITE, outline=GRID, width=2)

    # Header background
    draw.rectangle((x0, y0, x0 + table_w, y0 + row_h[0]), fill=BLUE)

    # Vertical lines
    xs = [x0]
    for w in col_w:
        xs.append(xs[-1] + w)
    for x in xs:
        draw.line((x, y0, x, y0 + table_h), fill=GRID, width=2)

    # Header text
    for i, header in enumerate(headers):
        text_center(draw, (xs[i], y0, xs[i + 1], y0 + row_h[0]), header, F_HEAD, WHITE)

    # Body rows
    y = y0 + row_h[0]
    for r_idx, row in enumerate(rows):
        fill = "#F7FAFF" if r_idx % 2 == 0 else "#EEF4FF"
        draw.rectangle((x0, y, x0 + table_w, y + row_h[r_idx + 1]), fill=fill)
        draw.line((x0, y, x0 + table_w, y), fill=GRID, width=2)
        text_left(draw, (xs[0] + 24, y, xs[1] - 12, y + row_h[r_idx + 1]), row[0], F_CELL, TEXT)
        for c in range(1, 6):
            mark(draw, (xs[c], y, xs[c + 1], y + row_h[r_idx + 1]), row[c])
        y += row_h[r_idx + 1]
    draw.line((x0, y, x0 + table_w, y), fill=GRID, width=2)

    # Legend / conclusion
    note_y = y0 + table_h + 28
    rounded(draw, (x0, note_y, x0 + table_w, note_y + 72), 6, BLUE_LIGHT, "#97B8F6", 2)
    draw.text((x0 + 28, note_y + 21), "★", font=F_STAR, fill=ORANGE)
    draw.text(
        (x0 + 75, note_y + 22),
        "Điểm mới: hướng tới secure data storage cho thiết bị nhúng, có nén + mã hóa + đọc khôi phục dữ liệu.",
        font=F_NOTE,
        fill=BLUE_DARK,
    )
    legend_x = x0 + 1290
    draw.text((legend_x, note_y + 18), "✓", font=F_MARK, fill=GREEN)
    draw.text((legend_x + 38, note_y + 23), "có", font=F_NOTE, fill=GREEN)
    draw.text((legend_x + 105, note_y + 18), "✕", font=F_MARK, fill=RED)
    draw.text((legend_x + 143, note_y + 23), "không", font=F_NOTE, fill=RED)
    draw.text((legend_x + 245, note_y + 18), "◐", font=F_MARK, fill=ORANGE)
    draw.text((legend_x + 283, note_y + 23), "một phần", font=F_NOTE, fill=ORANGE)

    src_y = note_y + 92
    rounded(draw, (x0, src_y, x0 + table_w, src_y + 94), 6, WHITE, "#C8D6EF", 2)
    draw.text((x0 + 25, src_y + 16), "Nguồn so sánh:", font=F_SMALL_B, fill=BLUE_DARK)
    sources = (
        "[1] GitHub software: aadomn/aes, drichardson/huffman.  "
        "[2] AES RTL/IP: secworks/aes, Rex1110/AES-128, yeshvanth-m/AES-128, OpenTitan AES.  "
        "[3] Paper: ECG Huffman + CBC-AES, Future Generation Computer Systems, 2019."
    )
    # Manual wrap for predictable layout.
    line1 = "[1] GitHub software: aadomn/aes, drichardson/huffman."
    line2 = "[2] AES RTL/IP: secworks/aes, Rex1110/AES-128, yeshvanth-m/AES-128, OpenTitan AES."
    line3 = "[3] Paper: ECG Huffman + CBC-AES, Future Generation Computer Systems, 2019."
    draw.text((x0 + 235, src_y + 16), line1, font=F_SMALL, fill=TEXT)
    draw.text((x0 + 235, src_y + 43), line2, font=F_SMALL, fill=TEXT)
    draw.text((x0 + 235, src_y + 70), line3, font=F_SMALL, fill=TEXT)


def main():
    img = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(img)
    draw_nav(draw)
    draw_title(draw)
    draw_table(draw)

    out = OUT_DIR / "secure_storage_comparison_slide.png"
    img.save(out, quality=95)
    print(out)


if __name__ == "__main__":
    main()
