"""Generates the mynote app icon (1024x1024) with Pillow.

Design: a warm off-white note card on a charcoal background (the Serika Dark
palette), holding a short checklist with yellow checkboxes and a blinking caret.
"""
from PIL import Image, ImageDraw, ImageFilter
import sys

S = 4096  # supersample, then downscale for smooth edges
BG_TOP = (52, 54, 58)
BG_BOTTOM = (30, 31, 34)
CARD = (232, 230, 220)
INK = (50, 52, 55)
INK_SOFT = (160, 158, 150)
YELLOW = (226, 183, 20)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def make(path, size=1024):
    img = Image.new("RGB", (S, S), BG_BOTTOM)
    d = ImageDraw.Draw(img)
    for y in range(S):
        d.line([(0, y), (S, y)], fill=lerp(BG_TOP, BG_BOTTOM, y / S))

    # card geometry
    cw, ch = int(S * 0.64), int(S * 0.64)
    cx0 = (S - cw) // 2
    cy0 = (S - ch) // 2 + int(S * 0.01)
    radius = int(S * 0.115)

    # soft shadow
    shadow = Image.new("L", (S, S), 0)
    sd = ImageDraw.Draw(shadow)
    off = int(S * 0.028)
    sd.rounded_rectangle([cx0, cy0 + off, cx0 + cw, cy0 + ch + off], radius=radius, fill=150)
    shadow = shadow.filter(ImageFilter.GaussianBlur(S * 0.03))
    black = Image.new("RGB", (S, S), (8, 8, 10))
    img = Image.composite(black, img, shadow)
    d = ImageDraw.Draw(img)

    d.rounded_rectangle([cx0, cy0, cx0 + cw, cy0 + ch], radius=radius, fill=CARD)

    # rows
    pad_x = int(cw * 0.15)
    box = int(cw * 0.135)
    row_gap = int(ch * 0.235)
    first_y = cy0 + int(ch * 0.19)
    bar_h = int(box * 0.36)
    bar_r = bar_h // 2
    stroke = int(box * 0.13)

    rows = [(True, 0.50), (True, 0.38), (False, 0.30)]
    for i, (checked, bar_frac) in enumerate(rows):
        y = first_y + i * row_gap
        bx = cx0 + pad_x
        br = int(box * 0.24)
        if checked:
            d.rounded_rectangle([bx, y, bx + box, y + box], radius=br, fill=YELLOW)
            # check mark
            pts = [
                (bx + box * 0.24, y + box * 0.52),
                (bx + box * 0.43, y + box * 0.71),
                (bx + box * 0.77, y + box * 0.31),
            ]
            d.line(pts, fill=CARD, width=int(box * 0.15), joint="curve")
            for p in (pts[0], pts[2]):
                r = int(box * 0.075)
                d.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=CARD)
            bar_color = INK_SOFT
        else:
            d.rounded_rectangle([bx, y, bx + box, y + box], radius=br, outline=YELLOW, width=stroke)
            bar_color = INK
        tx = bx + box + int(box * 0.42)
        ty = y + (box - bar_h) // 2
        bw = int(cw * bar_frac)
        d.rounded_rectangle([tx, ty, tx + bw, ty + bar_h], radius=bar_r, fill=bar_color)
        if not checked:
            # caret
            caret_x = tx + bw + int(box * 0.28)
            cw_ = int(box * 0.14)
            d.rounded_rectangle([caret_x, y - int(box * 0.08), caret_x + cw_, y + box + int(box * 0.08)],
                                radius=cw_ // 2, fill=YELLOW)

    img = img.resize((size, size), Image.LANCZOS)
    img.save(path)


if __name__ == "__main__":
    make(sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 1024)
