"""Generates the "my" mynote app icon (1024x1024) with Pillow.

Design: a warm off-white note card with a folded corner on a charcoal
background (the Serika Dark palette). On the card is a monoline "my" wordmark
whose yellow "y" doubles as a checkmark, above two ruled note lines.
"""
from PIL import Image, ImageDraw, ImageFilter
import math
import sys

S = 4096  # supersample, then downscale for smooth edges
BG_TOP = (52, 54, 58)
BG_BOTTOM = (30, 31, 34)
CARD = (232, 230, 220)
FOLD = (204, 201, 189)
INK = (50, 52, 55)
INK_SOFT = (176, 173, 163)
YELLOW = (226, 183, 20)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def stroke(d, pts, width, fill):
    """Strokes a polyline with round caps and joins by stamping discs."""
    r = width / 2
    step = max(1.0, width / 24)
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        n = max(1, int(math.hypot(x1 - x0, y1 - y0) / step))
        for i in range(n + 1):
            t = i / n
            x, y = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
            d.ellipse([x - r, y - r, x + r, y + r], fill=fill)


def arc_pts(cx, cy, r, a0, a1, n=120):
    return [(cx + r * math.cos(math.radians(a0 + (a1 - a0) * i / n)),
             cy + r * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)]


def make(path, size=1024):
    img = Image.new("RGB", (S, S), BG_BOTTOM)
    d = ImageDraw.Draw(img)
    for y in range(S):
        d.line([(0, y), (S, y)], fill=lerp(BG_TOP, BG_BOTTOM, y / S))

    # card geometry
    cw = ch = int(S * 0.66)
    cx0 = (S - cw) // 2
    cy0 = (S - ch) // 2 + int(S * 0.01)
    cx1, cy1 = cx0 + cw, cy0 + ch
    radius = int(S * 0.115)
    fold = int(cw * 0.19)

    # card silhouette with the top-right corner clipped for the fold
    mask = Image.new("L", (S, S), 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle([cx0, cy0, cx1, cy1], radius=radius, fill=255)
    md.polygon([(cx1 - fold, cy0 - 2), (cx1 + 2, cy0 - 2), (cx1 + 2, cy0 + fold)], fill=0)

    shadow = Image.new("L", (S, S), 0)
    shadow.paste(mask.point(lambda v: v * 150 // 255), (0, int(S * 0.028)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(S * 0.03))
    img = Image.composite(Image.new("RGB", (S, S), (8, 8, 10)), img, shadow)
    img = Image.composite(Image.new("RGB", (S, S), CARD), img, mask)
    d = ImageDraw.Draw(img)

    # dog-ear: the folded-over flap, with a softly rounded inner corner
    fr = int(fold * 0.16)
    flap = Image.new("L", (S, S), 0)
    fd = ImageDraw.Draw(flap)
    fd.rounded_rectangle([cx1 - fold, cy0 - fold, cx1 + fold, cy0 + fold], radius=fr, fill=255)
    fd.polygon([(cx1 - fold - 2, cy0 - 2), (cx1 + fold, cy0 - 2), (cx1 + fold, cy0 + fold + 2),
                (cx1 + 2, cy0 + fold + 2)], fill=0)
    fd.rectangle([cx0, cy0 - fold - 2, cx1 + fold, cy0 - 1], fill=0)
    img = Image.composite(Image.new("RGB", (S, S), FOLD), img, flap)
    d = ImageDraw.Draw(img)

    # wordmark metrics, in card units
    u = cw
    w = u * 0.085            # stroke weight
    xh = u * 0.27            # x-height (stroke centerline)
    mw = u * 0.36            # width of "m" between outer stems
    gap = u * 0.105          # space between "m" and "y"
    yw = u * 0.215           # width of the "y" arms at x-height
    desc = u * 0.17          # descender depth below baseline

    line_gap = u * 0.085     # baseline stroke edge to first note line
    line_step = u * 0.105
    bar_h = int(u * 0.05)

    total = mw + gap + yw + w
    x0 = cx0 + (cw - total) / 2 + w / 2
    block = w + xh + line_gap + line_step + bar_h
    top = cy0 + (ch - block) / 2 + w / 2 + u * 0.04
    base = top + xh

    # m: first stem, then two arches dropping into stems
    ar = mw / 4
    stroke(d, [(x0, top - w * 0.05), (x0, base)], w, INK)
    for k in range(2):
        cx = x0 + ar * (2 * k + 1)
        pts = [(x0 + ar * 2 * k, top + ar)] + arc_pts(cx, top + ar, ar, 180, 360) + [(cx + ar, base)]
        stroke(d, pts, w, INK)

    # y as a checkmark: short left arm, long right arm running into the descender
    yx = x0 + mw + gap
    vx, vy = yx + yw * 0.42, base                    # where the arms meet
    rx, ry = yx + yw, top - xh * 0.06                 # right arm tips just above x-height
    lx, ly = yx, base - xh * 0.52                     # left arm starts low, like a tick
    dx, dy = vx - rx, vy - ry
    t = desc / dy
    ex, ey = vx + dx * t, vy + desc
    stroke(d, [(lx, ly), (vx, vy)], w, YELLOW)
    stroke(d, [(rx, ry), (ex, ey)], w, YELLOW)

    # ruled note lines under the word
    lx0 = x0 - w / 2
    ly0 = base + w / 2 + line_gap
    for i, frac in enumerate((0.44, 0.30)):
        yy = ly0 + i * line_step
        d.rounded_rectangle([lx0, yy, lx0 + u * frac, yy + bar_h], radius=bar_h // 2, fill=INK_SOFT)

    img = img.resize((size, size), Image.LANCZOS)
    img.save(path)


if __name__ == "__main__":
    make(sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 1024)
