from pathlib import Path
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "docs" / "generated_figures"
OUT_DIR.mkdir(parents=True, exist_ok=True)

W, H = 1600, 900
BLUE = "#0b3f98"
GREEN = "#15915c"
ORANGE = "#f28c22"
PURPLE = "#7137d8"
TEXT = "#111827"
MUTED = "#5f6f89"
BG = "#f7f9fd"
BORDER = "#c7d3e6"
LIGHT_BLUE = "#eaf2ff"
LIGHT_GREEN = "#ecfff5"
LIGHT_ORANGE = "#fff4df"
LIGHT_PURPLE = "#f0e8ff"
WHITE = "#ffffff"


def font(size, bold=False):
    name = "arialbd.ttf" if bold else "arial.ttf"
    return ImageFont.truetype(str(Path("C:/Windows/Fonts") / name), size)


F_TITLE = font(54, True)
F_SUB = font(27)
F_PANEL = font(30, True)
F_BODY = font(25)
F_BODY_B = font(25, True)
F_SMALL = font(19)
F_MONO = ImageFont.truetype("C:/Windows/Fonts/consola.ttf", 24)
F_MONO_B = ImageFont.truetype("C:/Windows/Fonts/consolab.ttf", 25)


def rect(draw, box, fill, outline=BORDER, width=2, radius=0):
    if radius:
        draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)
    else:
        draw.rectangle(box, fill=fill, outline=outline, width=width)


def text(draw, xy, content, fnt, fill=TEXT, anchor="la", align="left"):
    draw.text(xy, content, font=fnt, fill=fill, anchor=anchor, align=align)


def centered(draw, box, content, fnt, fill=TEXT, align="center"):
    x0, y0, x1, y1 = box
    bbox = draw.multiline_textbbox((0, 0), content, font=fnt, spacing=5, align=align)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    draw.multiline_text(
        (x0 + (x1 - x0 - tw) / 2, y0 + (y1 - y0 - th) / 2),
        content,
        font=fnt,
        fill=fill,
        spacing=5,
        align=align,
    )


def arrow(draw, x1, y1, x2, y2, color=BLUE, width=5):
    draw.line((x1, y1, x2, y2), fill=color, width=width)
    dx = x2 - x1
    dy = y2 - y1
    if abs(dx) >= abs(dy):
        if dx >= 0:
            pts = [(x2, y2), (x2 - 22, y2 - 13), (x2 - 22, y2 + 13)]
        else:
            pts = [(x2, y2), (x2 + 22, y2 - 13), (x2 + 22, y2 + 13)]
    else:
        if dy >= 0:
            pts = [(x2, y2), (x2 - 13, y2 - 22), (x2 + 13, y2 - 22)]
        else:
            pts = [(x2, y2), (x2 - 13, y2 + 22), (x2 + 13, y2 + 22)]
    draw.polygon(pts, fill=color)


def node(draw, box, label, fill, outline, fnt=F_BODY_B, color=TEXT, radius=10):
    rect(draw, box, fill, outline, 3, radius)
    centered(draw, box, label, fnt, color)


def xor_node(draw, cx, cy, r=38):
    draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=WHITE, outline=TEXT, width=3)
    draw.line((cx - r + 10, cy, cx + r - 10, cy), fill=TEXT, width=3)
    draw.line((cx, cy - r + 10, cx, cy + r - 10), fill=TEXT, width=3)
    text(draw, (cx + r + 10, cy - 13), "XOR", F_BODY_B, TEXT)


def add_header(draw, title, subtitle):
    text(draw, (70, 42), title, F_TITLE, BLUE)
    text(draw, (72, 105), subtitle, F_SUB, TEXT)
    draw.line((0, 145, W, 145), fill=BLUE, width=8)


def add_formula_box(draw, title, lines):
    rect(draw, (1050, 595, 1510, 790), WHITE, BORDER, 2, 8)
    rect(draw, (1050, 595, 1510, 642), BLUE, BLUE, 0)
    text(draw, (1075, 607), title, F_PANEL, WHITE)
    y = 668
    for line in lines:
        text(draw, (1080, y), line, F_MONO_B, TEXT)
        y += 45


def add_footer(draw, content):
    rect(draw, (70, 825, 1530, 868), LIGHT_BLUE, "#3b7cff", 2)
    centered(draw, (70, 825, 1530, 868), content, F_BODY_B, BLUE)


def draw_encrypt():
    img = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(img)
    add_header(
        draw,
        "AES-128-CBC Encryption Algorithm",
        "Each plaintext block is XORed with IV or previous ciphertext before AES encryption.",
    )

    node(draw, (105, 305, 275, 395), "Plaintext\nP_i", LIGHT_BLUE, "#3b7cff")
    xor_node(draw, 430, 350)
    node(draw, (560, 300, 780, 400), "AES-128\nEncrypt", LIGHT_ORANGE, ORANGE)
    node(draw, (930, 305, 1100, 395), "Ciphertext\nC_i", LIGHT_PURPLE, PURPLE)

    arrow(draw, 275, 350, 392, 350)
    arrow(draw, 468, 350, 560, 350)
    arrow(draw, 780, 350, 930, 350)

    node(draw, (565, 188, 775, 250), "Secret key K", WHITE, BORDER, F_BODY_B)
    arrow(draw, 670, 250, 670, 298, ORANGE)

    node(draw, (318, 188, 542, 250), "C_0 = IV\nC_{i-1} for i > 1", LIGHT_GREEN, GREEN, F_BODY)
    arrow(draw, 430, 250, 430, 312, GREEN)

    arrow(draw, 1015, 395, 1015, 485, PURPLE)
    arrow(draw, 1015, 485, 430, 485, PURPLE)
    arrow(draw, 430, 485, 430, 389, PURPLE)
    text(draw, (710, 505), "feedback to next block", F_SMALL, MUTED, anchor="mm")

    rect(draw, (120, 585, 940, 790), WHITE, BORDER, 2, 8)
    text(draw, (145, 620), "Block-by-block operation", F_PANEL, BLUE)
    text(draw, (150, 680), "1. Select feedback value: IV for first block, otherwise C_{i-1}.", F_BODY, TEXT)
    text(draw, (150, 720), "2. XOR feedback with plaintext block P_i.", F_BODY, TEXT)
    text(draw, (150, 760), "3. AES encrypt the XOR result to produce C_i.", F_BODY, TEXT)

    add_formula_box(draw, "CBC formula", [
        "C_1 = E_K(P_1 xor IV)",
        "C_i = E_K(P_i xor C_{i-1})",
        "i = 2, 3, ..., n",
    ])
    add_footer(draw, "Encryption chains blocks: changing one ciphertext block changes the feedback for the next block.")
    return img


def draw_decrypt():
    img = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(img)
    add_header(
        draw,
        "AES-128-CBC Decryption Algorithm",
        "Each ciphertext block is AES-decrypted, then XORed with IV or previous ciphertext to recover plaintext.",
    )

    node(draw, (105, 305, 275, 395), "Ciphertext\nC_i", LIGHT_PURPLE, PURPLE)
    node(draw, (405, 300, 625, 400), "AES-128\nDecrypt", LIGHT_ORANGE, ORANGE)
    xor_node(draw, 790, 350)
    node(draw, (1015, 305, 1185, 395), "Plaintext\nP_i", LIGHT_BLUE, "#3b7cff")

    arrow(draw, 275, 350, 405, 350)
    arrow(draw, 625, 350, 752, 350)
    arrow(draw, 828, 350, 1015, 350)

    node(draw, (410, 188, 620, 250), "Secret key K", WHITE, BORDER, F_BODY_B)
    arrow(draw, 515, 250, 515, 298, ORANGE)

    node(draw, (678, 188, 902, 250), "C_0 = IV\nC_{i-1} for i > 1", LIGHT_GREEN, GREEN, F_BODY)
    arrow(draw, 790, 250, 790, 312, GREEN)

    arrow(draw, 190, 395, 190, 485, PURPLE)
    arrow(draw, 190, 485, 790, 485, PURPLE)
    arrow(draw, 790, 485, 790, 389, PURPLE)
    text(draw, (480, 505), "current C_i is saved as feedback for next block", F_SMALL, MUTED, anchor="mm")

    rect(draw, (120, 585, 940, 790), WHITE, BORDER, 2, 8)
    text(draw, (145, 620), "Block-by-block operation", F_PANEL, BLUE)
    text(draw, (150, 680), "1. AES decrypt ciphertext block C_i using key K.", F_BODY, TEXT)
    text(draw, (150, 720), "2. Select feedback value: IV for first block, otherwise C_{i-1}.", F_BODY, TEXT)
    text(draw, (150, 760), "3. XOR decrypted data with feedback to recover P_i.", F_BODY, TEXT)

    add_formula_box(draw, "CBC formula", [
        "P_1 = D_K(C_1) xor IV",
        "P_i = D_K(C_i) xor C_{i-1}",
        "i = 2, 3, ..., n",
    ])
    add_footer(draw, "Decryption uses the previous ciphertext block, not the previous plaintext block, as CBC feedback.")
    return img


def svg_escape(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def make_svg(kind):
    is_enc = kind == "encrypt"
    title = "AES-128-CBC Encryption Algorithm" if is_enc else "AES-128-CBC Decryption Algorithm"
    subtitle = (
        "Each plaintext block is XORed with IV or previous ciphertext before AES encryption."
        if is_enc
        else "Each ciphertext block is AES-decrypted, then XORed with IV or previous ciphertext to recover plaintext."
    )
    formula = (
        ["C_1 = E_K(P_1 xor IV)", "C_i = E_K(P_i xor C_{i-1})", "i = 2, 3, ..., n"]
        if is_enc
        else ["P_1 = D_K(C_1) xor IV", "P_i = D_K(C_i) xor C_{i-1}", "i = 2, 3, ..., n"]
    )

    def svg_text(x, y, content, size=25, weight=400, fill=TEXT, anchor="start", family="Arial"):
        return (
            f'<text x="{x}" y="{y}" text-anchor="{anchor}" font-family="{family}" '
            f'font-size="{size}" font-weight="{weight}" fill="{fill}">{svg_escape(content)}</text>'
        )

    def svg_multiline(cx, y, content, size=25, weight=700, fill=TEXT, anchor="middle", family="Arial", dy=28):
        out = []
        for i, part in enumerate(content.split("\\n")):
            out.append(svg_text(cx, y + i * dy, part, size, weight, fill, anchor, family))
        return out

    def svg_rect(x, y, w, h, fill, stroke=BORDER, sw=2, rx=8):
        return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}"/>'

    def svg_node(x, y, w, h, label, fill, stroke):
        out = [svg_rect(x, y, w, h, fill, stroke, 3, 10)]
        out.extend(svg_multiline(x + w / 2, y + h / 2 - 7, label, 25, 700))
        return out

    def svg_arrow(x1, y1, x2, y2, color=BLUE, width=5):
        return (
            f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" '
            f'stroke="{color}" stroke-width="{width}" marker-end="url(#{color[1:]}Arrow)"/>'
        )

    def svg_polyline(points, color=PURPLE, width=5):
        point_text = " ".join(f"{x},{y}" for x, y in points)
        return (
            f'<polyline points="{point_text}" fill="none" stroke="{color}" stroke-width="{width}" '
            f'marker-end="url(#{color[1:]}Arrow)"/>'
        )

    def svg_xor(cx, cy):
        return "\n".join(
            [
                f'<circle cx="{cx}" cy="{cy}" r="38" fill="{WHITE}" stroke="{TEXT}" stroke-width="3"/>',
                f'<line x1="{cx - 28}" y1="{cy}" x2="{cx + 28}" y2="{cy}" stroke="{TEXT}" stroke-width="3"/>',
                f'<line x1="{cx}" y1="{cy - 28}" x2="{cx}" y2="{cy + 28}" stroke="{TEXT}" stroke-width="3"/>',
                svg_text(cx + 48, cy + 9, "XOR", 25, 700),
            ]
        )

    def svg_formula_box():
        out = [
            svg_rect(1050, 595, 460, 195, WHITE, BORDER, 2, 8),
            f'<rect x="1050" y="595" width="460" height="47" fill="{BLUE}"/>',
            svg_text(1075, 628, "CBC formula", 30, 700, WHITE),
        ]
        for idx, line in enumerate(formula):
            out.append(svg_text(1080, 692 + idx * 45, line, 25, 700, TEXT, "start", "Consolas"))
        return out

    def svg_operation_box():
        lines_text = (
            [
                "1. Select feedback value: IV for first block, otherwise C_{i-1}.",
                "2. XOR feedback with plaintext block P_i.",
                "3. AES encrypt the XOR result to produce C_i.",
            ]
            if is_enc
            else [
                "1. AES decrypt ciphertext block C_i using key K.",
                "2. Select feedback value: IV for first block, otherwise C_{i-1}.",
                "3. XOR decrypted data with feedback to recover P_i.",
            ]
        )
        out = [
            svg_rect(120, 585, 820, 205, WHITE, BORDER, 2, 8),
            svg_text(145, 648, "Block-by-block operation", 30, 700, BLUE),
        ]
        for idx, line in enumerate(lines_text):
            out.append(svg_text(150, 703 + idx * 40, line, 25, 400, TEXT))
        return out

    def svg_footer():
        footer = (
            "Encryption chains blocks: changing one ciphertext block changes the feedback for the next block."
            if is_enc
            else "Decryption uses the previous ciphertext block, not the previous plaintext block, as CBC feedback."
        )
        return [
            f'<rect x="70" y="825" width="1460" height="43" fill="{LIGHT_BLUE}" stroke="#3b7cff" stroke-width="2"/>',
            svg_text(800, 856, footer, 25, 700, BLUE, "middle"),
        ]

    lines = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
        "<defs>",
        f'<marker id="{BLUE[1:]}Arrow" markerWidth="10" markerHeight="10" refX="8" refY="3" orient="auto" markerUnits="strokeWidth"><path d="M0,0 L0,6 L9,3 z" fill="{BLUE}"/></marker>',
        f'<marker id="{GREEN[1:]}Arrow" markerWidth="10" markerHeight="10" refX="8" refY="3" orient="auto" markerUnits="strokeWidth"><path d="M0,0 L0,6 L9,3 z" fill="{GREEN}"/></marker>',
        f'<marker id="{ORANGE[1:]}Arrow" markerWidth="10" markerHeight="10" refX="8" refY="3" orient="auto" markerUnits="strokeWidth"><path d="M0,0 L0,6 L9,3 z" fill="{ORANGE}"/></marker>',
        f'<marker id="{PURPLE[1:]}Arrow" markerWidth="10" markerHeight="10" refX="8" refY="3" orient="auto" markerUnits="strokeWidth"><path d="M0,0 L0,6 L9,3 z" fill="{PURPLE}"/></marker>',
        "</defs>",
        f'<rect width="{W}" height="{H}" fill="{BG}"/>',
        svg_text(70, 82, title, 54, 700, BLUE),
        svg_text(72, 124, subtitle, 27, 400, TEXT),
        f'<rect x="0" y="145" width="{W}" height="8" fill="{BLUE}"/>',
    ]

    if is_enc:
        lines.extend(svg_node(105, 305, 170, 90, "Plaintext\\nP_i", LIGHT_BLUE, "#3b7cff"))
        lines.append(svg_xor(430, 350))
        lines.extend(svg_node(560, 300, 220, 100, "AES-128\\nEncrypt", LIGHT_ORANGE, ORANGE))
        lines.extend(svg_node(930, 305, 170, 90, "Ciphertext\\nC_i", LIGHT_PURPLE, PURPLE))
        lines.append(svg_arrow(275, 350, 392, 350, BLUE))
        lines.append(svg_arrow(468, 350, 560, 350, BLUE))
        lines.append(svg_arrow(780, 350, 930, 350, BLUE))
        lines.extend(svg_node(565, 188, 210, 62, "Secret key K", WHITE, BORDER))
        lines.append(svg_arrow(670, 250, 670, 298, ORANGE))
        lines.extend(svg_node(318, 188, 224, 62, "C_0 = IV\\nC_{i-1} for i > 1", LIGHT_GREEN, GREEN))
        lines.append(svg_arrow(430, 250, 430, 312, GREEN))
        lines.append(svg_polyline([(1015, 395), (1015, 485), (430, 485), (430, 389)], PURPLE))
        lines.append(svg_text(710, 512, "feedback to next block", 19, 400, MUTED, "middle"))
    else:
        lines.extend(svg_node(105, 305, 170, 90, "Ciphertext\\nC_i", LIGHT_PURPLE, PURPLE))
        lines.extend(svg_node(405, 300, 220, 100, "AES-128\\nDecrypt", LIGHT_ORANGE, ORANGE))
        lines.append(svg_xor(790, 350))
        lines.extend(svg_node(1015, 305, 170, 90, "Plaintext\\nP_i", LIGHT_BLUE, "#3b7cff"))
        lines.append(svg_arrow(275, 350, 405, 350, BLUE))
        lines.append(svg_arrow(625, 350, 752, 350, BLUE))
        lines.append(svg_arrow(828, 350, 1015, 350, BLUE))
        lines.extend(svg_node(410, 188, 210, 62, "Secret key K", WHITE, BORDER))
        lines.append(svg_arrow(515, 250, 515, 298, ORANGE))
        lines.extend(svg_node(678, 188, 224, 62, "C_0 = IV\\nC_{i-1} for i > 1", LIGHT_GREEN, GREEN))
        lines.append(svg_arrow(790, 250, 790, 312, GREEN))
        lines.append(svg_polyline([(190, 395), (190, 485), (790, 485), (790, 389)], PURPLE))
        lines.append(svg_text(480, 512, "current C_i is saved as feedback for next block", 19, 400, MUTED, "middle"))

    lines.extend(svg_operation_box())
    lines.extend(svg_formula_box())
    lines.extend(svg_footer())
    lines.append("</svg>")
    return "\n".join(lines)


def main():
    outputs = [
        ("aes_cbc_encryption_algorithm", draw_encrypt()),
        ("aes_cbc_decryption_algorithm", draw_decrypt()),
    ]
    for name, img in outputs:
        img.save(OUT_DIR / f"{name}.png", quality=95)
    (OUT_DIR / "aes_cbc_encryption_algorithm.svg").write_text(make_svg("encrypt"), encoding="utf-8")
    (OUT_DIR / "aes_cbc_decryption_algorithm.svg").write_text(make_svg("decrypt"), encoding="utf-8")
    print(OUT_DIR)


if __name__ == "__main__":
    main()
