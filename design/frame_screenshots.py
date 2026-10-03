"""Builds the App Store screenshots (1320x2868, 6.9") from raw simulator captures."""
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import os

W, H = 1320, 2868
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "appstore", "raw")
OUT = os.path.join(ROOT, "appstore", "screenshots")


def font(size, weight=b"Bold", mono=False):
    f = ImageFont.truetype("/System/Library/Fonts/SFNSMono.ttf" if mono else "/System/Library/Fonts/SFNS.ttf", size)
    try:
        f.set_variation_by_name(weight)
    except Exception:
        pass
    return f


def hex2rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def gradient(top, bottom):
    img = Image.new("RGB", (W, H), top)
    d = ImageDraw.Draw(img)
    t, b = hex2rgb(top), hex2rgb(bottom)
    for y in range(H):
        k = y / H
        d.line([(0, y), (W, y)], fill=tuple(int(t[i] + (b[i] - t[i]) * k) for i in range(3)))
    return img


def rounded_mask(size, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255)
    return m


framed = []
for folder in (OUT, OUT + "-6.9-jpg", OUT + "-6.5", OUT + "-6.5-jpg"):
    os.makedirs(folder, exist_ok=True)


def compose(raw, out, lines, bg, fg, accent, highlight_line=1, sub=None):
    canvas = gradient(*bg) if isinstance(bg, tuple) else Image.new("RGB", (W, H), bg)
    d = ImageDraw.Draw(canvas)

    # Caption
    title = font(112)
    y = 190
    for i, line in enumerate(lines):
        color = accent if i == highlight_line else fg
        w = d.textlength(line, font=title)
        d.text(((W - w) / 2, y), line, font=title, fill=color)
        y += 132
    if sub:
        sf = font(46, b"Medium")
        w = d.textlength(sub, font=sf)
        d.text(((W - w) / 2, y + 18), sub, font=sf, fill=fg)

    # Device
    shot = Image.open(os.path.join(RAW, raw)).convert("RGB")
    dw = 1040
    dh = int(shot.height * dw / shot.width)
    shot = shot.resize((dw, dh), Image.LANCZOS)
    bezel = 22
    bw, bh = dw + bezel * 2, dh + bezel * 2
    x = (W - bw) // 2
    top = 720 if sub else 660

    shadow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(shadow).rounded_rectangle([x + 10, top + 40, x + bw - 10, top + bh + 40], radius=150, fill=110)
    shadow = shadow.filter(ImageFilter.GaussianBlur(45))
    canvas.paste(Image.new("RGB", (W, H), (0, 0, 0)), (0, 0), shadow)

    frame = Image.new("RGB", (bw, bh), (14, 14, 16))
    canvas.paste(frame, (x, top), rounded_mask((bw, bh), 150))
    canvas.paste(shot, (x + bezel, top + bezel), rounded_mask((dw, dh), 128))
    canvas.save(os.path.join(OUT, out), quality=95)
    # App Store Connect uploads: JPEGs, one at a time. The 6.5" slot is the one it asks for.
    name = os.path.splitext(out)[0]
    canvas.save(os.path.join(OUT + "-6.9-jpg", name + ".jpg"), quality=92, optimize=True)
    small = canvas.resize((1284, 2778), Image.LANCZOS)
    small.save(os.path.join(OUT + "-6.5", out))
    small.save(os.path.join(OUT + "-6.5-jpg", name + ".jpg"), quality=92, optimize=True)
    framed.append(canvas)
    print("wrote", out)


compose("mynote-raw-home.png", "01-home.png", ["One list.", "Always in sight."],
        ("#3A3C40", "#2A2C2F"), hex2rgb("#D1D0C5"), hex2rgb("#E2B714"))
compose("mynote-raw-lock.png", "02-lock-screen.png", ["Lives on your", "Lock Screen"],
        ("#0F2147", "#06122B"), (235, 240, 255), hex2rgb("#E2B714"),
        sub="Tick items off without unlocking.")
compose("mynote-raw-island.png", "03-dynamic-island.png", ["Tick it off", "from anywhere"],
        ("#1B2B4F", "#0B1430"), (235, 240, 255), hex2rgb("#E2B714"),
        sub="In the Dynamic Island, all day.")
compose("mynote-raw-themes.png", "04-themes.png", ["50 themes", "devs love"],
        ("#2C2E3B", "#1F202A"), hex2rgb("#F8F8F2"), hex2rgb("#BD93F9"),
        sub="Try any free. Supporters get all 50.")
compose("mynote-raw-editor.png", "05-editor.png", ["Write it", "your way"],
        ("#FBF6F0", "#F2E9E1"), hex2rgb("#575279"), hex2rgb("#B4637A"),
        sub="Rich text or Markdown, your pick.")
compose("mynote-raw-widget.png", "06-widget.png", ["Widgets that", "stay in sync"],
        ("#E3EEF6", "#C9DCEB"), hex2rgb("#22324A"), hex2rgb("#B4637A"),
        sub="Tappable checkboxes on your Home Screen.")

# Contact sheet to review all six at a glance.
tw, th, gap = 440, 956, 20
sheet = Image.new("RGB", (3 * tw + 2 * gap, 2 * th + gap), (128, 128, 128))
for i, img in enumerate(framed):
    sheet.paste(img.resize((tw, th), Image.LANCZOS), ((i % 3) * (tw + gap), (i // 3) * (th + gap)))
sheet.save(os.path.join(ROOT, "appstore", "mynote-screenshot-sheet.jpg"), quality=85)
print("wrote contact sheet")
