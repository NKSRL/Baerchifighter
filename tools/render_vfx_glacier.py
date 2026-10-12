#!/usr/bin/env python3
"""
render_vfx_glacier.py — zeichnet die Texturen der Gletscher-Show (GlacierFrost)

Ersatz fuer Blender (auf dem Laptop/in der Cloud nicht vorhanden): die sechs
Bilder werden prozedural mit Pillow gezeichnet. Alle sind weiss bzw. hell auf
transparentem Grund, damit Roblox sie ueber Decal.Color3 bzw.
ParticleEmitter.Color einfaerben kann (Gletscherblau, Eisweiss, Tuerkis).

Aufruf:  python3 tools/render_vfx_glacier.py
Ausgabe: assets/vfx/glacier_frost/{breath,veins,crack,spike,frostring,flake}.png
         und eine Kontaktbogen-Vorschau preview.png (auf dunklem Grund).

Die Zufallszahlen haben einen festen Startwert: gleicher Aufruf, gleiche Bilder.
"""

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parent.parent / "assets" / "vfx" / "glacier_frost"
WHITE = (255, 255, 255)
ICE = (225, 245, 255)


def rgba(size):
    return Image.new("RGBA", size, (0, 0, 0, 0))


def glow(img, radius):
    """weicher Schein unter den scharfen Linien (wie Bloom)"""
    soft = img.filter(ImageFilter.GaussianBlur(radius))
    return Image.alpha_composite(soft, img)


def breath():
    # Atemwolke: mehrere weiche Kreise, Rand ausgefranst.
    rnd = random.Random(1)
    s = 256
    img = rgba((s, s))
    d = ImageDraw.Draw(img)
    for _ in range(14):
        r = rnd.uniform(28, 62)
        a = rnd.uniform(0, math.tau)
        dist = rnd.uniform(0, 48)
        cx, cy = s / 2 + math.cos(a) * dist, s / 2 + math.sin(a) * dist
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(255, 255, 255, 70))
    img = img.filter(ImageFilter.GaussianBlur(14))
    return img


def branch(d, rnd, x, y, ang, length, width, depth):
    """eine Reif-Ader, die sich verzweigt"""
    if depth == 0 or length < 6:
        return
    steps = 6
    px, py = x, y
    for i in range(steps):
        ang += rnd.uniform(-0.25, 0.25)
        nx = px + math.cos(ang) * length / steps
        ny = py + math.sin(ang) * length / steps
        w = max(1, int(width * (1 - i / steps * 0.6)))
        d.line((px, py, nx, ny), fill=WHITE + (255,), width=w)
        if i in (2, 4) and rnd.random() < 0.8:
            side = rnd.choice((-1, 1))
            branch(d, rnd, nx, ny, ang + side * rnd.uniform(0.5, 0.9), length * 0.45, width * 0.6, depth - 1)
        px, py = nx, ny


def veins():
    # Gefrorener Kreis mit Reif-Adern (Bodenbild fuer `groundmark`).
    rnd = random.Random(2)
    s = 512
    c = s / 2
    img = rgba((s, s))
    base = rgba((s, s))
    bd = ImageDraw.Draw(base)
    # blasser Eisgrund, zum Rand hin auslaufend
    for r in range(int(c * 0.62), 0, -4):
        alpha = int(70 * (1 - r / (c * 0.62)) + 25)
        bd.ellipse((c - r, c - r, c + r, c + r), fill=ICE + (alpha,))
    base = base.filter(ImageFilter.GaussianBlur(10))
    lines = rgba((s, s))
    ld = ImageDraw.Draw(lines)
    n = 9
    for i in range(n):
        ang = i / n * math.tau + rnd.uniform(-0.2, 0.2)
        branch(ld, rnd, c, c, ang, c * rnd.uniform(0.75, 0.95), 5, 3)
    lines = glow(lines, 4)
    img = Image.alpha_composite(base, lines)
    return img


def crack():
    # Zickzack-Riss, laeuft ueber die ganze Laenge (wird auf jedes Riss-Stueck
    # gespannt). Heller Kern, ausgefranste Kanten.
    rnd = random.Random(3)
    w, h = 128, 512
    img = rgba((w, h))
    d = ImageDraw.Draw(img)
    pts = []
    y = 0
    while y <= h:
        pts.append((w / 2 + rnd.uniform(-22, 22), y))
        y += rnd.uniform(18, 34)
    pts.append((w / 2, h))
    d.line(pts, fill=ICE + (200,), width=18, joint="curve")
    d.line(pts, fill=WHITE + (255,), width=6, joint="curve")
    # feine Seitensplitter
    for (x, y) in pts[1:-1:2]:
        side = rnd.choice((-1, 1))
        d.line((x, y, x + side * rnd.uniform(14, 34), y + rnd.uniform(-14, 14)), fill=WHITE + (220,), width=3)
    return glow(img, 5)


def spike():
    # Eisdorn mit Facetten: Dreieck, in drei Flaechen geteilt, weisse Kanten.
    s = 256
    img = rgba((s, s))
    d = ImageDraw.Draw(img)
    tip, left, right = (s * 0.52, 8), (24, s - 8), (s - 24, s - 8)
    mid = (s * 0.47, s * 0.62)
    d.polygon([tip, left, mid], fill=(200, 235, 255, 230))
    d.polygon([tip, mid, right], fill=(140, 205, 240, 230))
    d.polygon([left, mid, right], fill=(90, 175, 200, 230))
    for a, b in ((tip, left), (tip, right), (tip, mid), (left, mid), (mid, right)):
        d.line((a, b), fill=WHITE + (255,), width=3)
    return glow(img, 3)


def frostring():
    # Flacher Frostring: heller Reif, innen/aussen weich, kleine Kristall-Zacken.
    rnd = random.Random(4)
    s = 512
    c = s / 2
    img = rgba((s, s))
    d = ImageDraw.Draw(img)
    r_out, r_in = c - 12, c - 58
    d.ellipse((c - r_out, c - r_out, c + r_out, c + r_out), fill=ICE + (210,))
    d.ellipse((c - r_in, c - r_in, c + r_in, c + r_in), fill=(0, 0, 0, 0))
    img = img.filter(ImageFilter.GaussianBlur(9))
    d = ImageDraw.Draw(img)
    for i in range(48):
        a = i / 48 * math.tau + rnd.uniform(-0.03, 0.03)
        r0 = c - 40 + rnd.uniform(-6, 6)
        r1 = r0 + rnd.uniform(18, 30)
        d.line((c + math.cos(a) * r0, c + math.sin(a) * r0, c + math.cos(a) * r1, c + math.sin(a) * r1),
               fill=WHITE + (255,), width=3)
    return glow(img, 3)


def flake():
    # Sechsarmige Schneeflocke mit Seitenaesten.
    s = 128
    c = s / 2
    img = rgba((s, s))
    d = ImageDraw.Draw(img)
    arm = c - 8
    for i in range(6):
        a = i / 6 * math.tau - math.pi / 2
        ex, ey = c + math.cos(a) * arm, c + math.sin(a) * arm
        d.line((c, c, ex, ey), fill=WHITE + (255,), width=5)
        for k, ln in ((0.45, 16), (0.7, 11)):
            bx, by = c + math.cos(a) * arm * k, c + math.sin(a) * arm * k
            for side in (-1, 1):
                b = a + side * 0.75
                d.line((bx, by, bx + math.cos(b) * ln, by + math.sin(b) * ln), fill=WHITE + (255,), width=3)
    return glow(img, 3)


TEXTURES = {
    "breath": breath,
    "veins": veins,
    "crack": crack,
    "spike": spike,
    "frostring": frostring,
    "flake": flake,
}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    images = {}
    for name, fn in TEXTURES.items():
        img = fn()
        img.save(OUT / f"{name}.png")
        images[name] = img
        print(f"{name}.png {img.size[0]}x{img.size[1]}")
    # Vorschau: alle Bilder auf dunklem Gletscher-Grund, eingefaerbt wie im Spiel
    cell = 220
    sheet = Image.new("RGBA", (cell * len(images), cell + 24), (20, 32, 48, 255))
    sd = ImageDraw.Draw(sheet)
    for i, (name, img) in enumerate(images.items()):
        im = img.copy()
        im.thumbnail((cell - 20, cell - 20))
        tint = Image.new("RGBA", im.size, (170, 225, 250, 255))
        im = Image.composite(Image.blend(im, tint, 0.25), im, im)
        x = i * cell + (cell - im.size[0]) // 2
        y = (cell - im.size[1]) // 2
        sheet.alpha_composite(im, (x, y))
        sd.text((i * cell + 8, cell + 4), name, fill=(230, 245, 255, 255))
    sheet.save(OUT / "preview.png")
    print(f"preview.png -> {OUT}")


if __name__ == "__main__":
    main()
