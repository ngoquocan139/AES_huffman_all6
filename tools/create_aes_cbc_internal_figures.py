from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import math


ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "docs" / "generated_figures"
OUT_DIR.mkdir(parents=True, exist_ok=True)

W, H = 1920, 1080

BG = "#f7f9fd"
TEXT = "#111827"
MUTED = "#5f6f89"
BORDER = "#c7d3e6"
BLUE = "#0b3f98"
GREEN = "#15915c"
ORANGE = "#f28c22"
PURPLE = "#7137d8"
RED = "#dc3d4a"
CYAN = "#0e7490"
LIGHT_BLUE = "#eaf2ff"
LIGHT_GREEN = "#ecfff5"
LIGHT_ORANGE = "#fff4df"
LIGHT_PURPLE = "#f0e8ff"
LIGHT_RED = "#fff0f1"
LIGHT_CYAN = "#e6fbff"
WHITE = "#ffffff"


def font(size, bold=False):
    name = "arialbd.ttf" if bold else "arial.ttf"
    return ImageFont.truetype(str(Path("C:/Windows/Fonts") / name), size)


F_TITLE = font(60, True)
F_SUB = font(29)
F_PANEL = font(33, True)
F_H = font(27, True)
F_BODY = font(25)
F_BODY_B = font(25, True)
F_SMALL = font(19)
F_SMALL_B = font(20, True)
F_TINY_B = font(17, True)
F_MONO = ImageFont.truetype("C:/Windows/Fonts/consola.ttf", 23)
F_MONO_B = ImageFont.truetype("C:/Windows/Fonts/consolab.ttf", 24)


class Figure:
    def __init__(self):
        self.img = Image.new("RGB", (W, H), BG)
        self.draw = ImageDraw.Draw(self.img)
        self.svg = [
            f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
            "<defs>",
            *[
                f'<marker id="{color[1:]}Arrow" markerWidth="10" markerHeight="10" refX="8" refY="3" orient="auto" markerUnits="strokeWidth"><path d="M0,0 L0,6 L9,3 z" fill="{color}"/></marker>'
                for color in (BLUE, GREEN, ORANGE, PURPLE, RED, CYAN, MUTED)
            ],
            "</defs>",
            f'<rect width="{W}" height="{H}" fill="{BG}"/>',
        ]

    @staticmethod
    def esc(value):
        return str(value).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

    def rect(self, box, fill, outline=BORDER, width=2, radius=0):
        if radius:
            self.draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)
            rx = radius
        else:
            self.draw.rectangle(box, fill=fill, outline=outline, width=width)
            rx = 0
        x0, y0, x1, y1 = box
        self.svg.append(
            f'<rect x="{x0}" y="{y0}" width="{x1-x0}" height="{y1-y0}" rx="{rx}" fill="{fill}" stroke="{outline}" stroke-width="{width}"/>'
        )

    def line(self, x1, y1, x2, y2, color=TEXT, width=3):
        self.draw.line((x1, y1, x2, y2), fill=color, width=width)
        self.svg.append(f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{color}" stroke-width="{width}"/>')

    def arrow(self, x1, y1, x2, y2, color=BLUE, width=5):
        self.draw.line((x1, y1, x2, y2), fill=color, width=width)
        angle = math.atan2(y2 - y1, x2 - x1)
        size = 18
        p1 = (x2, y2)
        p2 = (x2 - size * math.cos(angle - 0.55), y2 - size * math.sin(angle - 0.55))
        p3 = (x2 - size * math.cos(angle + 0.55), y2 - size * math.sin(angle + 0.55))
        self.draw.polygon([p1, p2, p3], fill=color)
        self.svg.append(
            f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{color}" stroke-width="{width}" marker-end="url(#{color[1:]}Arrow)"/>'
        )

    def poly_arrow(self, points, color=PURPLE, width=5):
        self.draw.line(points, fill=color, width=width, joint="curve")
        x1, y1 = points[-2]
        x2, y2 = points[-1]
        angle = math.atan2(y2 - y1, x2 - x1)
        size = 18
        p1 = (x2, y2)
        p2 = (x2 - size * math.cos(angle - 0.55), y2 - size * math.sin(angle - 0.55))
        p3 = (x2 - size * math.cos(angle + 0.55), y2 - size * math.sin(angle + 0.55))
        self.draw.polygon([p1, p2, p3], fill=color)
        pt = " ".join(f"{x},{y}" for x, y in points)
        self.svg.append(
            f'<polyline points="{pt}" fill="none" stroke="{color}" stroke-width="{width}" marker-end="url(#{color[1:]}Arrow)"/>'
        )

    def text(self, x, y, content, fnt, fill=TEXT, anchor="la", align="left", svg_anchor="start", family="Arial", weight=None):
        self.draw.multiline_text((x, y), content, font=fnt, fill=fill, anchor=anchor, spacing=5, align=align)
        lines = str(content).split("\n")
        if weight is None:
            weight = 700 if fnt in (F_TITLE, F_PANEL, F_H, F_BODY_B, F_SMALL_B, F_MONO_B) else 400
        size = fnt.size
        for idx, line in enumerate(lines):
            self.svg.append(
                f'<text x="{x}" y="{y + idx*(size+5)}" text-anchor="{svg_anchor}" font-family="{family}" font-size="{size}" font-weight="{weight}" fill="{fill}">{self.esc(line)}</text>'
            )

    def centered_text(self, box, content, fnt, fill=TEXT, family="Arial"):
        x0, y0, x1, y1 = box
        bbox = self.draw.multiline_textbbox((0, 0), content, font=fnt, spacing=5, align="center")
        tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
        x = x0 + (x1 - x0) / 2
        y = y0 + (y1 - y0 - th) / 2
        self.draw.multiline_text((x, y), content, font=fnt, fill=fill, anchor="ma", spacing=5, align="center")
        size = fnt.size
        weight = 700 if fnt in (F_TITLE, F_PANEL, F_H, F_BODY_B, F_SMALL_B, F_MONO_B) else 400
        for idx, line in enumerate(str(content).split("\n")):
            self.svg.append(
                f'<text x="{x}" y="{y + idx*(size+5)}" text-anchor="middle" font-family="{family}" font-size="{size}" font-weight="{weight}" fill="{fill}">{self.esc(line)}</text>'
            )

    def node(self, box, label, fill, outline, fnt=F_BODY_B, radius=12):
        self.rect(box, fill, outline, 3, radius)
        self.centered_text(box, label, fnt)

    def pill(self, x, y, w, h, label, fill, outline, fnt=F_SMALL_B):
        self.rect((x, y, x + w, y + h), fill, outline, 2, 12)
        self.centered_text((x, y, x + w, y + h), label, fnt)

    def xor(self, cx, cy, r=42):
        self.draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=WHITE, outline=TEXT, width=3)
        self.svg.append(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{WHITE}" stroke="{TEXT}" stroke-width="3"/>')
        self.line(cx - r + 11, cy, cx + r - 11, cy, TEXT, 3)
        self.line(cx, cy - r + 11, cx, cy + r - 11, TEXT, 3)
        self.text(cx + r + 13, cy - 15, "XOR", F_BODY_B, TEXT)

    def matrix(self, x, y, cell=25):
        for r in range(4):
            for c in range(4):
                fill = "#eef5ff" if (r + c) % 2 == 0 else WHITE
                self.rect((x + c * cell, y + r * cell, x + (c + 1) * cell, y + (r + 1) * cell), fill, "#8fb3e8", 1)
        self.text(x - 4, y + 4 * cell + 13, "128-bit state\n4 x 4 bytes", F_SMALL, MUTED)

    def panel(self, box, title, color):
        self.rect(box, WHITE, BORDER, 2, 8)
        x0, y0, x1, _ = box
        self.rect((x0, y0, x1, y0 + 50), color, color, 0)
        self.text(x0 + 22, y0 + 11, title, F_PANEL, WHITE)

    def header(self, title, subtitle):
        self.text(72, 45, title, F_TITLE, BLUE)
        self.text(74, 112, subtitle, F_SUB, TEXT)
        self.rect((0, 150, W, 158), BLUE, BLUE, 0)

    def save(self, png_path, svg_path):
        self.svg.append("</svg>")
        self.img.save(png_path, quality=95)
        Path(svg_path).write_text("\n".join(self.svg), encoding="utf-8")


def draw_round_strip(fig, x, y, steps, repeat_label, no_mix_text=None, step_w=None, gap=None, fnt=F_SMALL_B):
    step_w = step_w or (142 if len(steps) == 4 else 170)
    gap = gap or 16
    colors = [
        (LIGHT_CYAN, CYAN),
        (LIGHT_GREEN, GREEN),
        (LIGHT_ORANGE, ORANGE),
        (LIGHT_BLUE, BLUE),
    ]
    last_x = x
    for idx, step in enumerate(steps):
        fill, stroke = colors[idx % len(colors)]
        fig.pill(last_x, y, step_w, 58, step, fill, stroke, fnt)
        if idx < len(steps) - 1:
            fig.arrow(last_x + step_w, y + 29, last_x + step_w + gap - 4, y + 29, MUTED, 3)
        last_x += step_w + gap
    strip_w = len(steps) * step_w + (len(steps) - 1) * gap
    fig.rect((x - 14, y - 38, x + strip_w + 14, y + 84), "#ffffff00" if False else WHITE, "#d6e1ef", 1, 10)
    # Redraw pills over the outline because PIL has no transparent fill for RGB.
    last_x = x
    for idx, step in enumerate(steps):
        fill, stroke = colors[idx % len(colors)]
        fig.pill(last_x, y, step_w, 58, step, fill, stroke, fnt)
        if idx < len(steps) - 1:
            fig.arrow(last_x + step_w, y + 29, last_x + step_w + gap - 4, y + 29, MUTED, 3)
        last_x += step_w + gap
    fig.text(x + strip_w / 2, y - 17, repeat_label, F_SMALL_B, BLUE, anchor="mm", svg_anchor="middle")
    if no_mix_text:
        compact = no_mix_text.replace("\nin final round", " in final round")
        fig.text(x + strip_w / 2, y + 85, compact, F_SMALL_B, RED, anchor="mm", svg_anchor="middle")


def draw_key_schedule(fig, x, y, reverse=False):
    fig.node((x, y, x + 175, y + 60), "Secret key K", WHITE, BORDER, F_BODY_B)
    fig.arrow(x + 175, y + 30, x + 235, y + 30, ORANGE, 4)
    fig.node((x + 245, y, x + 455, y + 60), "AES key\nexpansion", LIGHT_ORANGE, ORANGE, F_BODY_B)
    label = "round keys\nK10 ... K0" if reverse else "round keys\nK0 ... K10"
    fig.arrow(x + 455, y + 30, x + 515, y + 30, ORANGE, 4)
    fig.node((x + 525, y, x + 715, y + 60), label, "#fff9f0", ORANGE, F_BODY)


def draw_encrypt():
    fig = Figure()
    fig.header(
        "AES-128-CBC Encryption with AES Round Details",
        "CBC adds XOR feedback outside AES; AES-128 then transforms the 128-bit state through 10 rounds.",
    )

    fig.panel((70, 185, 1850, 410), "CBC encryption chaining", BLUE)
    fig.node((110, 285, 285, 375), "Plaintext\nP_i", LIGHT_BLUE, "#3b7cff")
    fig.xor(430, 330)
    fig.node((570, 275, 815, 385), "AES-128\nEncrypt core", LIGHT_ORANGE, ORANGE)
    fig.node((995, 285, 1170, 375), "Ciphertext\nC_i", LIGHT_PURPLE, PURPLE)
    fig.arrow(285, 330, 385, 330, BLUE)
    fig.arrow(475, 330, 570, 330, BLUE)
    fig.arrow(815, 330, 995, 330, BLUE)
    fig.node((305, 238, 555, 280), "C_0 = IV\nC_{i-1} for i > 1", LIGHT_GREEN, GREEN, F_BODY)
    fig.poly_arrow([(1082, 375), (1082, 392), (430, 392), (430, 372)], PURPLE, 4)
    fig.text(745, 394, "feedback to next block", F_SMALL, MUTED, anchor="ma", svg_anchor="middle")

    fig.panel((70, 445, 1260, 995), "Inside AES-128 encryption core", ORANGE)
    fig.matrix(110, 532, 26)
    fig.text(110, 490, "Input to AES core: P_i xor feedback", F_BODY_B, TEXT)
    fig.arrow(240, 585, 332, 585, BLUE, 4)
    fig.pill(350, 556, 190, 62, "Initial\nAddRoundKey K0", LIGHT_BLUE, BLUE, F_SMALL_B)
    fig.arrow(540, 587, 608, 587, BLUE, 4)
    draw_round_strip(
        fig,
        630,
        534,
        ["SubBytes", "ShiftRows", "MixColumns", "AddRoundKey"],
        "Rounds 1 to 9",
        step_w=142,
        gap=16,
    )
    fig.arrow(1220, 587, 1220, 690, BLUE, 4)
    draw_round_strip(
        fig,
        350,
        700,
        ["SubBytes", "ShiftRows", "AddRoundKey"],
        "Final round 10",
        "No MixColumns\nin final round",
    )
    fig.arrow(900, 730, 1070, 730, BLUE, 4)
    fig.node((1085, 688, 1220, 772), "C_i", LIGHT_PURPLE, PURPLE, F_BODY_B)
    draw_key_schedule(fig, 240, 875, reverse=False)
    fig.text(980, 895, "keys -> AddRoundKey", F_SMALL_B, ORANGE)

    fig.panel((1300, 445, 1850, 995), "What each AES step does", BLUE)
    bullets = [
        ("SubBytes", "byte substitution using S-box"),
        ("ShiftRows", "cyclic row shifts in the 4 x 4 state"),
        ("MixColumns", "column mixing over GF(2^8)"),
        ("AddRoundKey", "XOR state with round key"),
    ]
    y = 520
    for title, body in bullets:
        fig.text(1330, y, title, F_BODY_B, BLUE)
        fig.text(1330, y + 31, body, F_BODY, TEXT)
        y += 62
    fig.rect((1330, 775, 1815, 930), LIGHT_BLUE, "#3b7cff", 2, 8)
    fig.text(1360, 805, "CBC formula", F_H, BLUE)
    fig.text(1360, 850, "C_1 = E_K(P_1 xor IV)\nC_i = E_K(P_i xor C_{i-1})", F_MONO_B, TEXT)

    fig.save(
        OUT_DIR / "aes_cbc_encrypt_internal_algorithm.png",
        OUT_DIR / "aes_cbc_encrypt_internal_algorithm.svg",
    )


def draw_decrypt():
    fig = Figure()
    fig.header(
        "AES-128-CBC Decryption with AES Round Details",
        "AES-128 inverse rounds first recover the XORed state; CBC feedback then restores plaintext.",
    )

    fig.panel((70, 185, 1850, 410), "CBC decryption chaining", BLUE)
    fig.node((110, 285, 285, 375), "Ciphertext\nC_i", LIGHT_PURPLE, PURPLE)
    fig.node((430, 275, 675, 385), "AES-128\nDecrypt core", LIGHT_ORANGE, ORANGE)
    fig.xor(875, 330)
    fig.node((1050, 285, 1225, 375), "Plaintext\nP_i", LIGHT_BLUE, "#3b7cff")
    fig.arrow(285, 330, 430, 330, BLUE)
    fig.arrow(675, 330, 830, 330, BLUE)
    fig.arrow(920, 330, 1050, 330, BLUE)
    fig.node((750, 238, 1000, 280), "C_0 = IV\nC_{i-1} for i > 1", LIGHT_GREEN, GREEN, F_BODY)
    fig.poly_arrow([(197, 375), (197, 392), (875, 392), (875, 372)], PURPLE, 4)
    fig.text(530, 394, "current C_i is saved as next feedback", F_SMALL, MUTED, anchor="ma", svg_anchor="middle")

    fig.panel((70, 445, 1260, 995), "Inside AES-128 decryption core", ORANGE)
    fig.matrix(110, 532, 26)
    fig.text(110, 490, "Input to AES core: ciphertext block C_i", F_BODY_B, TEXT)
    fig.arrow(240, 585, 332, 585, BLUE, 4)
    fig.pill(350, 556, 190, 62, "Initial\nAddRoundKey K10", LIGHT_BLUE, BLUE, F_SMALL_B)
    fig.arrow(540, 587, 608, 587, BLUE, 4)
    draw_round_strip(
        fig,
        630,
        534,
        ["InvShiftRows", "InvSubBytes", "AddRoundKey", "InvMixColumns"],
        "Rounds 9 down to 1",
        step_w=142,
        gap=16,
        fnt=F_TINY_B,
    )
    fig.arrow(1220, 587, 1220, 690, BLUE, 4)
    draw_round_strip(
        fig,
        350,
        700,
        ["InvShiftRows", "InvSubBytes", "AddRoundKey"],
        "Final inverse round",
        "No InvMixColumns\nin final round",
        step_w=170,
        gap=24,
        fnt=F_TINY_B,
    )
    fig.arrow(900, 730, 1060, 730, BLUE, 4)
    fig.node((1075, 688, 1228, 772), "P_i xor\nfeedback", LIGHT_GREEN, GREEN, F_BODY_B)
    draw_key_schedule(fig, 240, 875, reverse=True)
    fig.text(980, 895, "keys used in reverse", F_SMALL_B, ORANGE)

    fig.panel((1300, 445, 1850, 995), "What each inverse step does", BLUE)
    bullets = [
        ("InvShiftRows", "undo cyclic row shifts"),
        ("InvSubBytes", "inverse S-box substitution"),
        ("AddRoundKey", "XOR with round key"),
        ("InvMixColumns", "undo column mixing over GF(2^8)"),
    ]
    y = 520
    for title, body in bullets:
        fig.text(1330, y, title, F_BODY_B, BLUE)
        fig.text(1330, y + 31, body, F_BODY, TEXT)
        y += 62
    fig.rect((1330, 775, 1815, 930), LIGHT_BLUE, "#3b7cff", 2, 8)
    fig.text(1360, 805, "CBC formula", F_H, BLUE)
    fig.text(1360, 850, "P_1 = D_K(C_1) xor IV\nP_i = D_K(C_i) xor C_{i-1}", F_MONO_B, TEXT)

    fig.save(
        OUT_DIR / "aes_cbc_decrypt_internal_algorithm.png",
        OUT_DIR / "aes_cbc_decrypt_internal_algorithm.svg",
    )


def main():
    draw_encrypt()
    draw_decrypt()
    print(OUT_DIR)


if __name__ == "__main__":
    main()
