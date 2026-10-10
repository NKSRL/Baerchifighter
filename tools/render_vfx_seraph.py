#!/usr/bin/env python3
"""
render_vfx_seraph.py — zeichnet die Texturen der Seraph-Show (SeraphGrace)

Wie render_vfx_glacier.py: Ersatz fuer Blender, prozedural mit Pillow. Alle
Bilder hell (Elfenbeinweiss) auf transparentem Grund; die Farbe (Honiggold,
Bernstein) kommt in Roblox ueber Decal.Color3, Beam.Color bzw.
ParticleEmitter.Color.

Aufruf:  python3 tools/render_vfx_seraph.py
Ausgabe: assets/vfx/seraph_grace/{feather,halo,comb,column,cloudrim,spark}.png
         und preview.png (Kontaktbogen, eingefaerbt wie im Spiel).
"""

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

from render_vfx_glacier import glow, rgba

OUT = Path(__file__).resolve().parent.parent / "assets" / "vfx" / "seraph_grace"
IVORY = (255, 250, 238)


def feather():
    # Lange, weiche Lichtfeder: Kiel in der Mitte, Fahne mit feinen Aesten,
    # zur Spitze heller (fuer die Fluegel ueber die Laenge gespannt).
    w, h = 128, 512
    img = rgba((w, h))
    d = ImageDraw.Draw(img)
    cx = w / 2
    for y in range(8, h - 8, 3):
        k = y / h
        half = (w * 0.42) * math.sin(math.pi * min(1.0, k * 1.15)) ** 0.7
        alpha = int(70 + 120 * (1 - k))
        d.line((cx - half, y + 6, cx, y), fill=IVORY + (alpha,), width=2)
        d.line((cx, y, cx + half, y + 6), fill=IVORY + (alpha,), width=2)
    d.line((cx, 4, cx, h - 4), fill=(255, 255, 255, 255), width=4)
    img = img.filter(ImageFilter.GaussianBlur(1.2))
    return glow(img, 6)


def halo():
    # Heiligenschein: schmaler, heller Ring mit weichem Schein, oben hellster Punkt.
    s = 512
    c = s / 2
    img = rgba((s, s))
    d = ImageDraw.Draw(img)
    r_out, r_in = c - 40, c - 64
    d.ellipse((c - r_out, c - r_out, c + r_out, c + r_out), fill=IVORY + (255,))
    d.ellipse((c - r_in, c - r_in, c + r_in, c + r_in), fill=(0, 0, 0, 0))
    return glow(img, 14)


def comb():
    # Waben-Glanzmuster: eine Wabe mit hellem Rand und Glanzlicht oben links
    # (wird je Waben-Kachel einmal verwendet).
    s = 256
    c = s / 2
    img = rgba((s, s))
    d = ImageDraw.Draw(img)
    r = s * 0.44
    pts = [(c + r * math.cos(math.pi / 6 + i * math.pi / 3), c + r * math.sin(math.pi / 6 + i * math.pi / 3)) for i in range(6)]
    d.polygon(pts, fill=IVORY + (90,))
    d.line(pts + [pts[0]], fill=(255, 255, 255, 255), width=10, joint="curve")
    d.ellipse((c - r * 0.55, c - r * 0.6, c - r * 0.1, c - r * 0.25), fill=(255, 255, 255, 170))
    return glow(img, 5)


def column():
    # Lichtsaeule mit weichem Verlauf: quer weich (Gauss), laengs oben hell,
    # unten etwas kraeftiger (Licht trifft auf den Baerchi).
    w, h = 256, 512
    img = rgba((w, h))
    px = img.load()
    for y in range(h):
        k = y / (h - 1)
        along = 0.55 + 0.45 * k
        for x in range(w):
            q = (x - w / 2) / (w / 2)
            a = math.exp(-(q * q) / 0.18) * along
            px[x, y] = IVORY + (int(255 * a),)
    return img


def cloudrim():
    # Rand des Wolkenlochs: innen leer, heller Rand, nach aussen wolkig auslaufend.
    rnd = random.Random(5)
    s = 512
    c = s / 2
    img = rgba((s, s))
    d = ImageDraw.Draw(img)
    for _ in range(70):
        a = rnd.uniform(0, math.tau)
        rr = rnd.uniform(c * 0.62, c * 0.78)
        br = rnd.uniform(18, 36)
        x, y = c + math.cos(a) * rr, c + math.sin(a) * rr
        d.ellipse((x - br, y - br, x + br, y + br), fill=(255, 255, 255, 60))
    img = img.filter(ImageFilter.GaussianBlur(12))
    d = ImageDraw.Draw(img)
    r = c * 0.6
    d.ellipse((c - r, c - r, c + r, c + r), outline=IVORY + (255,), width=10)
    inner = rgba((s, s))
    ImageDraw.Draw(inner).ellipse((c - r + 6, c - r + 6, c + r - 6, c + r - 6), fill=(0, 0, 0, 255))
    # Mitte wirklich leer (das Loch)
    img.putalpha(Image.composite(Image.new("L", (s, s), 0), img.getchannel("A"), inner.getchannel("A")))
    return glow(img, 8)


def spark():
    # Kleiner Lichtfunke: vierstrahliger Stern mit Kern.
    s = 64
    c = s / 2
    img = rgba((s, s))
    d = ImageDraw.Draw(img)
    d.line((c, 4, c, s - 4), fill=(255, 255, 255, 255), width=3)
    d.line((4, c, s - 4, c), fill=(255, 255, 255, 255), width=3)
    d.ellipse((c - 6, c - 6, c + 6, c + 6), fill=(255, 255, 255, 255))
    return glow(img, 4)


TEXTURES = {
    "feather": feather,
    "halo": halo,
    "comb": comb,
    "column": column,
    "cloudrim": cloudrim,
    "spark": spark,
}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    images = {}
    for name, fn in TEXTURES.items():
        img = fn()
        img.save(OUT / f"{name}.png")
        images[name] = img
        print(f"{name}.png {img.size[0]}x{img.size[1]}")
    cell = 220
    sheet = Image.new("RGBA", (cell * len(images), cell + 24), (44, 34, 24, 255))
    sd = ImageDraw.Draw(sheet)
    for i, (name, img) in enumerate(images.items()):
        im = img.copy()
        im.thumbnail((cell - 20, cell - 20))
        tint = Image.new("RGBA", im.size, (255, 200, 90, 255))
        im = Image.composite(Image.blend(im, tint, 0.35), im, im)
        sheet.alpha_composite(im, (i * cell + (cell - im.size[0]) // 2, (cell - im.size[1]) // 2))
        sd.text((i * cell + 8, cell + 4), name, fill=(255, 240, 210, 255))
    sheet.save(OUT / "preview.png")
    print(f"preview.png -> {OUT}")


if __name__ == "__main__":
    main()
