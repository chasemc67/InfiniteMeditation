#!/usr/bin/env python3
"""Composite App Store screenshots for Boundless Meditation.

Reads raw Simulator captures from raw/ and writes App Store Connect-sized PNGs to final/:
  final/iphone-6.9/  1320 x 2868  (iPhone 6.9" display)
  final/watch-ultra/  422 x 514   (Apple Watch Ultra)

Usage:  python3 make_screenshots.py      (needs Pillow: pip install Pillow)
Raw captures come from the Debug build launched with -screenshotState (see Shared/ScreenshotSeed.swift).
"""
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent
RAW = HERE / "raw"
OUT = HERE / "final"

TOP = (6, 16, 38)        # deep blue
BOTTOM = (12, 84, 92)    # teal
GLOW = (90, 200, 200)

IPHONE = [
    ("iphone-1-idle", "An open-ended timer\nfor meditation", "Sit for as long as you like"),
    ("iphone-2-running", "Calm chime on iPhone", "Keeps chiming with your phone locked"),
    ("iphone-3-running-major", "A deeper bowl\nat every 10", "Feel the time pass without counting"),
    ("iphone-4-settings", "Make it yours", "Intervals, chimes and Apple Watch taps"),
]
WATCH = [
    ("watch-1-idle", "Gentle taps\nevery 5 minutes"),
    ("watch-2-running", "Keeps tapping with\nyour wrist down"),
    ("watch-3-settings", "A different tap\nat every 10"),
    ("watch-4-long-session", "Long sessions,\nno time limit"),
]

FONT_PATHS = [
    "/System/Library/Fonts/SFNSRounded.ttf",
    "/System/Library/Fonts/SFNS.ttf",
    "/System/Library/Fonts/Avenir Next.ttc",
]


def font(size, weight="Bold"):
    for path in FONT_PATHS:
        try:
            f = ImageFont.truetype(path, size)
            try:
                f.set_variation_by_name(weight)
            except Exception:
                pass
            return f
        except OSError:
            continue
    return ImageFont.load_default()


def background(w, h, seed):
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        t = y / (h - 1)
        t = t * t * (3 - 2 * t)  # smoothstep
        row = tuple(round(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3))
        for x in range(w):
            px[x, y] = row
    # soft teal glow behind the device
    glow = Image.new("L", (w, h), 0)
    gd = ImageDraw.Draw(glow)
    r = int(w * 0.55)
    cx, cy = w // 2, int(h * 0.62)
    gd.ellipse((cx - r, cy - r, cx + r, cy + r), fill=70)
    glow = glow.filter(ImageFilter.GaussianBlur(w * 0.18))
    img = Image.composite(Image.new("RGB", (w, h), GLOW), img, glow)
    # sparse stars, denser near the top
    stars = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    sd = ImageDraw.Draw(stars)
    rng = random.Random(seed)
    for _ in range(int(w * h / 9000)):
        x = rng.uniform(0, w)
        y = h * (rng.random() ** 1.8)
        s = rng.choice([0.6, 0.8, 1.0, 1.0, 1.4, 2.0]) * w / 1320 * 2.2
        a = rng.randint(60, 200)
        sd.ellipse((x - s, y - s, x + s, y + s), fill=(255, 255, 255, a))
    img = Image.alpha_composite(img.convert("RGBA"), stars)
    return img


def rounded(im, radius):
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, im.size[0] - 1, im.size[1] - 1), radius, fill=255)
    out = im.convert("RGBA")
    out.putalpha(mask)
    return out


def framed(shot, scale, radius, bezel, bezel_color=(14, 18, 26)):
    w, h = round(shot.width * scale), round(shot.height * scale)
    screen = rounded(shot.resize((w, h), Image.LANCZOS), radius)
    fw, fh = w + 2 * bezel, h + 2 * bezel
    frame = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
    d = ImageDraw.Draw(frame)
    d.rounded_rectangle((0, 0, fw - 1, fh - 1), radius + bezel, fill=bezel_color + (255,))
    # thin highlight edge
    d.rounded_rectangle((1, 1, fw - 2, fh - 2), radius + bezel - 1, outline=(255, 255, 255, 40), width=max(1, bezel // 8))
    frame.alpha_composite(screen, (bezel, bezel))
    return frame


def shadow_paste(canvas, layer, pos, blur, opacity=120):
    sh = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    alpha = layer.getchannel("A").point(lambda a: a * opacity // 255)
    sh.paste((0, 0, 0, 255), (pos[0], pos[1] + blur // 2), alpha)
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    canvas.alpha_composite(sh)
    canvas.alpha_composite(layer, pos)


def draw_centered(d, text, y, fnt, fill, width, spacing):
    d.multiline_text((width // 2, y), text, font=fnt, fill=fill, anchor="ma", align="center", spacing=spacing)
    bbox = d.multiline_textbbox((width // 2, y), text, font=fnt, anchor="ma", align="center", spacing=spacing)
    return bbox[3]


def make_iphone(name, title, subtitle, index):
    W, H = 1320, 2868
    canvas = background(W, H, seed=100 + index)
    d = ImageDraw.Draw(canvas)
    y = draw_centered(d, title, 190, font(104, "Bold"), (255, 255, 255, 255), W, 18)
    draw_centered(d, subtitle, y + 40, font(50, "Medium"), (190, 230, 228, 255), W, 10)
    shot = Image.open(RAW / f"{name}.png").convert("RGB")
    top = 640
    bezel = 26
    scale = (H - top - 90 - 2 * bezel) / shot.height
    device = framed(shot, scale, radius=round(165 * scale), bezel=bezel)
    shadow_paste(canvas, device, ((W - device.width) // 2, top), blur=50)
    return canvas.convert("RGB")


def make_watch(name, title, index):
    W, H = 422, 514
    canvas = background(W, H, seed=200 + index)
    d = ImageDraw.Draw(canvas)
    draw_centered(d, title, 20, font(31, "Bold"), (255, 255, 255, 255), W, 4)
    shot = Image.open(RAW / f"{name}.png").convert("RGB")
    top = 118
    bezel = 9
    scale = (H - top - 18 - 2 * bezel) / shot.height
    device = framed(shot, scale, radius=round(110 * scale), bezel=bezel, bezel_color=(20, 22, 28))
    shadow_paste(canvas, device, ((W - device.width) // 2, top), blur=14)
    return canvas.convert("RGB")


def main():
    (OUT / "iphone-6.9").mkdir(parents=True, exist_ok=True)
    (OUT / "watch-ultra").mkdir(parents=True, exist_ok=True)
    for i, (name, title, subtitle) in enumerate(IPHONE, 1):
        img = make_iphone(name, title, subtitle, i)
        assert img.size == (1320, 2868)
        img.save(OUT / "iphone-6.9" / f"{i:02d}-{name.split('-', 2)[2]}.png", optimize=True)
    for i, (name, title) in enumerate(WATCH, 1):
        img = make_watch(name, title, i)
        assert img.size == (422, 514)
        img.save(OUT / "watch-ultra" / f"{i:02d}-{name.split('-', 2)[2]}.png", optimize=True)
    for p in sorted(OUT.rglob("*.png")):
        with Image.open(p) as im:
            print(p.relative_to(HERE), im.size, im.mode)


if __name__ == "__main__":
    main()
