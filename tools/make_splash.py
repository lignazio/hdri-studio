#!/usr/bin/env python3
"""Genera hdri_studio/splash.png (boot splash) : una mappa equirettangolare stilizzata con le forme
delle luci dell'app (rect, ellisse, anello, gradiente) e il titolo. Richiede Pillow.
    python3 tools/make_splash.py
"""
import math, os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1600, 900
BG = (24, 24, 26)
OUT = os.path.join(os.path.dirname(__file__), "..", "hdri_studio", "splash.png")


def font(name, size, index=0):
    for p in ("/System/Library/Fonts/", "/System/Library/Fonts/Supplemental/", "C:/Windows/Fonts/"):
        f = os.path.join(p, name)
        if os.path.exists(f):
            return ImageFont.truetype(f, size, index=index)
    return ImageFont.load_default()


def hdri_map(w, h):
    """Mappa 2:1 con sfondo a gradiente e luci morbide, in float, poi tone-mapped."""
    import numpy as np
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    u, v = xs / w, ys / h
    el = (0.5 - v) * math.pi            # elevazione
    # cielo/terra: gradiente freddo in alto, caldo-scuro in basso
    t = np.clip((el / (math.pi / 2)) * 0.5 + 0.5, 0, 1)[..., None]
    top = np.array([0.10, 0.13, 0.20], np.float32)
    bot = np.array([0.05, 0.035, 0.03], np.float32)
    img = bot + (top - bot) * t
    # orizzonte
    img += np.exp(-((v - 0.5) / 0.012) ** 2)[..., None] * np.array([0.10, 0.08, 0.06], np.float32)

    def soft(mask, rgb, k):
        return np.clip(mask, 0, 1)[..., None] * np.array(rgb, np.float32) * k

    def sdf_rect(cx, cy, hw, hh, r):
        dx, dy = np.abs(u - cx) - hw, np.abs(v - cy) - hh
        return np.hypot(np.maximum(dx + r, 0), np.maximum(dy + r, 0)) - r + np.minimum(np.maximum(dx + r, dy + r), 0)

    def feather(d, s):
        return np.clip(1 - d / s, 0, 1) ** 1.6

    # key: rettangolo grande a sinistra, caldo
    img += soft(feather(sdf_rect(0.30, 0.36, 0.085, 0.12, 0.012), 0.02), (1.0, 0.88, 0.70), 4.0)
    # fill: ellisse a destra, fredda
    d = np.hypot((u - 0.70) / 0.075, (v - 0.44) / 0.10) - 1.0
    img += soft(feather(d * 0.08, 0.05), (0.70, 0.82, 1.0), 1.2)
    # rim: anello alto dietro
    d = np.abs(np.hypot((u - 0.52) / 0.05, (v - 0.22) / 0.075) - 1.0) * 0.05
    img += soft(feather(d, 0.012), (1.0, 0.95, 0.9), 2.2)
    # strip: gradiente sottile in basso a destra
    g = feather(sdf_rect(0.82, 0.68, 0.10, 0.012, 0.006), 0.02) * np.clip((u - 0.72) / 0.20, 0, 1)
    img += soft(g, (1.0, 0.55, 0.35), 1.6)
    # tone map (Reinhard) e gamma
    img = img / (1 + img)
    img = np.clip(img, 0, 1) ** (1 / 2.2)
    return Image.fromarray((img * 255).astype("uint8"), "RGB")


def main():
    im = Image.new("RGB", (W, H), BG)
    # pannello della mappa con angoli arrotondati
    mw, mh = 1180, 590
    mx, my = (W - mw) // 2, 110
    panel = hdri_map(mw, mh)
    mask = Image.new("L", (mw, mh), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, mw - 1, mh - 1), radius=22, fill=255)
    # alone morbido dietro il pannello
    glow = Image.new("RGB", (W, H), BG)
    glow.paste(panel.resize((mw + 40, mh + 40)), (mx - 20, my - 20))
    glow = glow.filter(ImageFilter.GaussianBlur(40))
    im = Image.blend(im, glow, 0.35)
    im.paste(panel, (mx, my), mask)
    # griglia leggera (meridiani/paralleli) come nella mappa dell'app
    d = ImageDraw.Draw(im, "RGBA")
    for i in range(1, 8):
        x = mx + mw * i / 8
        d.line((x, my + 6, x, my + mh - 6), fill=(255, 255, 255, 18), width=1)
    for j in range(1, 4):
        y = my + mh * j / 4
        d.line((mx + 6, y, mx + mw - 6, y), fill=(255, 255, 255, 22 if j == 2 else 14), width=1)
    # titolo
    title = font("Avenir Next.ttc", 74, index=2)  # Demi Bold
    sub = font("Avenir Next.ttc", 24, index=5)  # Medium
    d.text((W / 2, 785), "HDRI Studio", font=title, fill=(238, 238, 240), anchor="mm")
    d.text((W / 2, 845), "LUCE DA STUDIO, FISICAMENTE CORRETTA  ·  LUCENTI STUDIO", font=sub, fill=(150, 150, 158), anchor="mm")
    im.save(OUT, optimize=True)
    print("scritto", os.path.abspath(OUT), im.size)


if __name__ == "__main__":
    main()
