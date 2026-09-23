#!/usr/bin/env python3
"""Genera l'icona dell'app: la sfera cromata del preview con il riflesso di un softbox, sulla stessa
tavolozza dello splash. Scrive hdri_studio/icon.png (1024, per Godot), icon.icns (macOS) e icon.ico
(Windows). Richiede Pillow, numpy e — solo per l'icns — iconutil (macOS).
    python3 tools/make_icon.py
"""
import math, os, shutil, subprocess, sys, tempfile

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "hdri_studio")
ICNS_SIZES = [16, 32, 64, 128, 256, 512, 1024]
ICO_SIZES = [16, 24, 32, 48, 64, 128, 256]


def _norm(v):
    return np.asarray(v, np.float32) / np.linalg.norm(v)


def _rect_light(rdir, center, half_w, half_h, soft):
    """Quanto il raggio riflesso `rdir` cade dentro un softbox rettangolare: 1 dentro, 0 fuori,
    con i bordi sfumati di `soft` radianti (le sfumature della luce dell'app)."""
    f = _norm(center)
    up = _norm(np.cross(np.cross(f, [0.0, 1.0, 0.0]), f))
    right = np.cross(up, f)
    x = rdir @ right
    y = rdir @ up
    z = np.clip(rdir @ f, 1e-4, None)
    # angoli dal centro della luce, con la stessa smoothstep sui bordi
    ax, ay = np.abs(np.arctan2(x, z)), np.abs(np.arctan2(y, z))
    t = np.clip((half_w + soft - ax) / soft, 0, 1) * np.clip((half_h + soft - ay) / soft, 0, 1)
    return np.where(rdir @ f > 0, t * t * (3 - 2 * t), 0.0)


def sphere(size):
    """Sfera illuminata da key (softbox caldo in alto a sinistra), fill freddo e rim, in float."""
    ss = 2  # supersampling
    n = size * ss
    ys, xs = np.mgrid[0:n, 0:n].astype(np.float32)
    u = (xs + 0.5) / n * 2 - 1
    v = 1 - (ys + 0.5) / n * 2
    cx, cy, rad = 0.0, 0.0, 0.62
    px, py = (u - cx) / rad, (v - cy) / rad
    rr = px * px + py * py
    inside = rr <= 1.0
    pz = np.sqrt(np.clip(1.0 - rr, 0, None))
    nrm = np.stack([px, py, pz], -1)

    view = np.array([0.0, 0.0, 1.0], np.float32)
    ndv = nrm @ view
    refl = 2.0 * ndv[..., None] * nrm - view

    key_dir = [-0.55, 0.62, 0.56]
    fill_dir = [0.80, 0.05, 0.55]
    rim_dir = [0.15, 0.75, -0.62]
    key_rgb = np.array([1.00, 0.86, 0.64], np.float32)
    fill_rgb = np.array([0.55, 0.70, 1.00], np.float32)
    rim_rgb = np.array([1.00, 0.96, 0.90], np.float32)

    lam = lambda d: np.clip(nrm @ _norm(d), 0, None)
    # sfera scura e lucida: il contrasto lo fanno i riflessi, non il diffuso (si legge a 16 px)
    col = (lam(key_dir)[..., None] * key_rgb * 0.10
           + lam(fill_dir)[..., None] * fill_rgb * 0.035
           + np.clip(lam(rim_dir) - 0.45, 0, None)[..., None] ** 1.3 * rim_rgb * 2.4)
    # riflesso del softbox e della sua controparte fredda: è questo che fa "studio"
    col += _rect_light(refl, key_dir, 0.46, 0.34, 0.13)[..., None] * key_rgb * 5.0
    col += _rect_light(refl, fill_dir, 0.26, 0.40, 0.20)[..., None] * fill_rgb * 1.6
    col += np.array([0.008, 0.008, 0.011], np.float32)
    col = np.where(inside[..., None], col, 0.0)

    col = col / (1.0 + col)                       # tone map come nello splash
    col = np.clip(col, 0, 1) ** (1 / 2.2)
    rgb = Image.fromarray((col * 255).astype("uint8"), "RGB").resize((size, size), Image.LANCZOS)
    alpha = Image.fromarray((np.clip((1.0 - rr) * n * 0.02, 0, 1) * 255).astype("uint8"), "L")
    return rgb, alpha.resize((size, size), Image.LANCZOS)


def tile(size):
    """Sfondo: tessera con angoli arrotondati alla macOS, gradiente scuro e alone caldo."""
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float32)
    u, v = xs / size, ys / size
    # valori già in sRGB, come lo sfondo dello splash (24, 24, 26)
    top = np.array([0.125, 0.130, 0.145], np.float32)
    bot = np.array([0.030, 0.030, 0.035], np.float32)
    img = bot + (top - bot) * np.clip(1 - v, 0, 1)[..., None]
    glow = np.exp(-(((u - 0.28) ** 2 + (v - 0.26) ** 2) / 0.085))
    img += glow[..., None] * np.array([0.115, 0.090, 0.060], np.float32)
    return Image.fromarray((np.clip(img, 0, 1) * 255).astype("uint8"), "RGB")


def render(size=SIZE):
    im = tile(size).convert("RGBA")
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size - 1, size - 1), radius=int(size * 0.225), fill=255)
    im.putalpha(mask)

    d = int(size * 0.66)
    ball, ball_a = sphere(d)
    pos = ((size - d) // 2, int(size * 0.17))
    # ombra morbida sotto la sfera
    shadow = Image.new("L", (size, size), 0)
    ImageDraw.Draw(shadow).ellipse((pos[0] + d * 0.14, pos[1] + d * 0.90, pos[0] + d * 0.86, pos[1] + d * 1.08), fill=165)
    shadow = shadow.filter(ImageFilter.GaussianBlur(size * 0.028))
    im.alpha_composite(Image.merge("RGBA", (*[Image.new("L", (size, size), 0)] * 3, shadow)))
    im.paste(ball, pos, ball_a)

    # bordo interno chiaro, come i pannelli dell'app
    edge = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle(
        (1, 1, size - 2, size - 2), radius=int(size * 0.225) - 1, outline=(255, 255, 255, 26), width=max(2, size // 340))
    im.alpha_composite(edge)
    im.putalpha(Image.fromarray(np.minimum(np.array(im.getchannel("A")), np.array(mask))))
    return im


def write_icns(master, path):
    if not shutil.which("iconutil"):
        print("iconutil non disponibile: .icns saltata")
        return False
    with tempfile.TemporaryDirectory() as tmp:
        iconset = os.path.join(tmp, "icon.iconset")
        os.makedirs(iconset)
        for s in ICNS_SIZES:
            master.resize((s, s), Image.LANCZOS).save(os.path.join(iconset, "icon_%dx%d.png" % (s, s)))
            if s * 2 <= SIZE:
                master.resize((s * 2, s * 2), Image.LANCZOS).save(os.path.join(iconset, "icon_%dx%d@2x.png" % (s, s)))
        subprocess.run(["iconutil", "-c", "icns", iconset, "-o", path], check=True)
    return True


def main():
    master = render()
    png = os.path.abspath(os.path.join(OUT_DIR, "icon.png"))
    master.save(png)
    print("scritto", png, master.size)
    ico = os.path.abspath(os.path.join(OUT_DIR, "icon.ico"))
    master.save(ico, sizes=[(s, s) for s in ICO_SIZES])
    print("scritto", ico)
    icns = os.path.abspath(os.path.join(OUT_DIR, "icon.icns"))
    if write_icns(master, icns):
        print("scritto", icns)
    if "--preview" in sys.argv:  # provino con le dimensioni piccole affiancate
        strip = Image.new("RGBA", (16 + sum(s + 16 for s in (512, 128, 64, 32, 16)), 560), (40, 40, 44, 255))
        x = 16
        for s in (512, 128, 64, 32, 16):
            strip.alpha_composite(master.resize((s, s), Image.LANCZOS), (x, (560 - s) // 2))
            x += s + 16
        p = os.path.abspath(os.path.join(OUT_DIR, "out", "icon_preview.png"))
        strip.save(p)
        print("scritto", p)


if __name__ == "__main__":
    main()
