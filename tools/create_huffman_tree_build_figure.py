from pathlib import Path
import textwrap

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "docs" / "generated_figures"
OUT_DIR.mkdir(parents=True, exist_ok=True)
OUT_PNG = OUT_DIR / "huffman_tree_build_to_code_length.png"

W, H = 1920, 1080

BLUE = "#0b3f98"
LIGHT_BLUE = "#eaf2ff"
GREEN = "#15915c"
LIGHT_GREEN = "#ecfff5"
ORANGE = "#f28c22"
LIGHT_ORANGE = "#fff4df"
TEXT = "#111827"
MUTED = "#607089"
LINE = "#111827"
GRID = "#d9e3f2"
BORDER = "#b9c8df"
WHITE = "#ffffff"
BG = "#f7f9fd"
YELLOW = "#f6a817"


def font(size, bold=False):
    name = "arialbd.ttf" if bold else "arial.ttf"
    return ImageFont.truetype(str(Path("C:/Windows/Fonts") / name), size)


F_TITLE = font(58, True)
F_SUBTITLE = font(31)
F_PANEL = font(34, True)
F_H2 = font(30, True)
F_BODY = font(27)
F_BODY_B = font(27, True)
F_SMALL = font(21)
F_SMALL_B = font(22, True)
F_MONO = ImageFont.truetype("C:/Windows/Fonts/consolab.ttf", 24)
F_NODE = font(27)
F_NODE_B = font(29, True)


def rect(draw, xy, fill, outline=BORDER, width=2, radius=0):
    if radius:
        draw.rounded_rectangle(xy, radius=radius, fill=fill, outline=outline, width=width)
    else:
        draw.rectangle(xy, fill=fill, outline=outline, width=width)


def centered(draw, xy, text, fnt, fill=TEXT, anchor="mm"):
    draw.text(xy, text, font=fnt, fill=fill, anchor=anchor)


def text_lines(draw, xy, lines, fnt, fill=TEXT, spacing=8):
    x, y = xy
    for line in lines:
        draw.text((x, y), line, font=fnt, fill=fill)
        y += fnt.size + spacing
    return y


def wrapped(draw, xy, text, fnt, width_chars, fill=TEXT, spacing=6):
    lines = textwrap.wrap(text, width=width_chars)
    return text_lines(draw, xy, lines, fnt, fill, spacing)


def leaf(draw, x, y, weight, sym, scale=1.0, label=None):
    bw, bh = int(83 * scale), int(75 * scale)
    rect(draw, (x - bw // 2, y - bh // 2, x + bw // 2, y + bh // 2), YELLOW, LINE, 2)
    centered(draw, (x, y - int(13 * scale)), str(weight), font(int(23 * scale)), TEXT)
    centered(draw, (x, y + int(18 * scale)), sym, font(int(28 * scale), True), TEXT)
    if label:
        centered(draw, (x, y + bh // 2 + int(24 * scale)), label, font(int(20 * scale), True), BLUE)


def internal(draw, x, y, weight, r=31):
    draw.ellipse((x - r, y - r, x + r, y + r), fill=WHITE, outline=LINE, width=2)
    centered(draw, (x, y), str(weight), F_NODE, TEXT)


def edge(draw, a, b):
    draw.line((a[0], a[1], b[0], b[1]), fill=LINE, width=3)


def arrow(draw, x1, y1, x2, y2, color=MUTED):
    draw.line((x1, y1, x2, y2), fill=color, width=4)
    if x2 >= x1:
        pts = [(x2, y2), (x2 - 17, y2 - 10), (x2 - 17, y2 + 10)]
    else:
        pts = [(x2, y2), (x2 + 17, y2 - 10), (x2 + 17, y2 + 10)]
    draw.polygon(pts, fill=color)


def panel(draw, xy, title, color):
    x0, y0, x1, y1 = xy
    rect(draw, xy, WHITE, BORDER, 2)
    draw.rectangle((x0, y0, x1, y0 + 55), fill=color)
    draw.text((x0 + 22, y0 + 12), title, font=F_PANEL, fill=WHITE)


def draw_initial_panel(draw):
    box = (60, 150, 560, 1010)
    panel(draw, box, "1. Initial partial trees", BLUE)
    draw.text((100, 235), "Start with one leaf per symbol", font=F_BODY, fill=TEXT)

    items = [(2, "Z"), (7, "K"), (24, "M"), (32, "C"), (37, "U"), (42, "D"), (42, "L"), (120, "E")]
    xs = [142, 255, 368, 481]
    ys = [335, 470]
    for i, (w, s) in enumerate(items):
        leaf(draw, xs[i % 4], ys[i // 4], w, s, 1.0, "leaf")

    rect(draw, (94, 615, 500, 842), LIGHT_BLUE, "#4b83e6", 2)
    draw.text((128, 650), "Priority queue rule", font=F_H2, fill=BLUE)
    text_lines(
        draw,
        (128, 705),
        [
            "Merge two lowest weights.",
            "Parent weight is the sum.",
        ],
        F_BODY,
        TEXT,
        9,
    )
    draw.text((128, 793), "parent = w1 + w2", font=F_MONO, fill=TEXT)


def draw_merge_panel(draw):
    box = (590, 150, 1060, 1010)
    panel(draw, box, "2. Merge until one root", GREEN)
    draw.text((630, 235), "Each row summarizes one merge.", font=F_BODY, fill=TEXT)

    rows = [
        ("1", "Z2 + K7", "9"),
        ("2", "9 + M24", "33"),
        ("3", "C32 + 33", "65"),
        ("4", "U37 + D42", "79"),
        ("5", "L42 + 65", "107"),
        ("6", "79 + 107", "186"),
        ("7", "E120 + 186", "306"),
    ]
    y = 300
    for n, lhs, rhs in rows:
        rect(draw, (635, y - 17, 684, y + 32), LIGHT_GREEN, "#0fab5f", 2)
        centered(draw, (659, y + 7), n, F_BODY_B, TEXT)
        rect(draw, (702, y - 17, 882, y + 32), "#f8fbff", "#cbd6e5", 2)
        centered(draw, (792, y + 7), lhs, F_MONO, TEXT)
        arrow(draw, 895, y + 7, 934, y + 7)
        rect(draw, (946, y - 17, 1032, y + 32), LIGHT_ORANGE, ORANGE, 2)
        centered(draw, (989, y + 7), rhs, F_BODY_B, TEXT)
        y += 85

    rect(draw, (630, 905, 1002, 978), LIGHT_GREEN, "#0fab5f", 2)
    centered(draw, (816, 941), "Stop: one tree remains, root = 306", F_BODY_B, TEXT)


def draw_tree_panel(draw):
    box = (1090, 150, 1860, 1010)
    panel(draw, box, "3. Final tree and code length", ORANGE)
    x0, y0, x1, y1 = box

    depths = [0, 1, 2, 3, 4, 5, 6]
    ys = {0: 265, 1: 365, 2: 465, 3: 565, 4: 665, 5: 765, 6: 875}
    for d in depths:
        y = ys[d]
        draw.line((1130, y, 1830, y), fill=GRID, width=1)
        draw.text((1140, y - 15), f"d{d}", font=F_SMALL, fill="#7891b9")

    p = {
        "306": (1420, ys[0]),
        "E": (1245, ys[1]),
        "186": (1590, ys[1]),
        "79": (1465, ys[2]),
        "107": (1695, ys[2]),
        "U": (1395, ys[3]),
        "D": (1543, ys[3]),
        "L": (1650, ys[3]),
        "65": (1780, ys[3]),
        "C": (1715, ys[4]),
        "33": (1815, ys[4] + 15),
        "9": (1768, ys[5] - 5),
        "M": (1840, ys[5] + 10),
        "Z": (1705, ys[6] - 5),
        "K": (1780, ys[6] - 5),
    }

    edges = [
        ("306", "E"), ("306", "186"), ("186", "79"), ("186", "107"),
        ("79", "U"), ("79", "D"), ("107", "L"), ("107", "65"),
        ("65", "C"), ("65", "33"), ("33", "9"), ("33", "M"),
        ("9", "Z"), ("9", "K"),
    ]
    for a, b in edges:
        edge(draw, p[a], p[b])

    internal(draw, *p["306"], 306)
    internal(draw, *p["186"], 186)
    internal(draw, *p["79"], 79)
    internal(draw, *p["107"], 107)
    internal(draw, *p["65"], 65)
    internal(draw, *p["33"], 33)
    internal(draw, *p["9"], 9)

    leaf(draw, *p["E"], 120, "E", 0.95, "len=1")
    leaf(draw, *p["U"], 37, "U", 0.88, "len=3")
    leaf(draw, *p["D"], 42, "D", 0.88, "len=3")
    leaf(draw, *p["L"], 42, "L", 0.88, "len=3")
    leaf(draw, *p["C"], 32, "C", 0.88, "len=4")
    leaf(draw, *p["M"], 24, "M", 0.84, "len=5")
    leaf(draw, *p["Z"], 2, "Z", 0.78, "len=6")
    leaf(draw, *p["K"], 7, "K", 0.78, "len=6")

    rect(draw, (1130, 936, 1806, 994), "#fff9f0", ORANGE, 2)
    centered(draw, (1468, 965), "code_len = leaf depth: E=1, U/D/L=3, C=4, M=5, Z/K=6", F_BODY_B, TEXT)


def main():
    img = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(img)

    draw.text((72, 30), "Huffman Tree Construction to Code Length", font=F_TITLE, fill=BLUE)
    draw.text(
        (72, 94),
        "Repeatedly merge the two minimum-weight trees until one root remains.",
        font=F_SUBTITLE,
        fill=TEXT,
    )
    draw.line((0, 134, W, 134), fill=BLUE, width=7)

    draw_initial_panel(draw)
    draw_merge_panel(draw)
    draw_tree_panel(draw)

    draw.text(
        (60, 1042),
        "Source idea: OpenDSA Huffman coding tree construction. Project step: use leaf depth as code_len before canonical code generation.",
        font=F_SMALL,
        fill=MUTED,
    )

    img.save(OUT_PNG, quality=95)
    print(OUT_PNG)


if __name__ == "__main__":
    main()
