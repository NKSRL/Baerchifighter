#!/usr/bin/env python3
"""
render_vfx_omega.py — zeichnet die Texturen der Omega-Show (OmegaStrike)

Wie render_vfx_glacier.py: Ersatz fuer Blender, prozedural mit Pillow. Weiss
auf transparentem Grund (die vier Pfadfarben kommen in Roblox ueber
ImageColor3/Decal.Color3 dazu). Nur der Spektrum-Verlauf ist farbig, weil er
selbst die Farbe ins Bild zurueckbringt.

Aufruf:  python3 tools/render_vfx_omega.py
Ausgabe: assets/vfx/omega_strike/{omega,spectrum,orb,brand,shockring,column}.png
         und preview.png.
"""

import colorsys
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

from render_vfx_glacier import glow, rgba

OUT = Path(__file__).resolve().parent.parent / "assets" / "vfx" / "omega_strike"
WHITE = (255, 255, 255)

# Pfadfarben (nur fuer die Vorschau): Gold, Kristall-Blau, Void-Violett, Kosmos-Sternweiss
PATH_COLORS = [(255, 200, 60), (110, 200, 255), (150, 80, 255), (235, 235, 255)]


def omega_shape(d, c, r, width, fill):
    """Omega: Kreisbogen mit Luecke unten + zwei waagerechte Fuesse (Bild-y nach unten)."""
    t0, t1 = math.radians(-48), math.radians(228)
    pts = []
    for i in range(61):
        t = t0 + (t1 - t0) * i / 60
        pts.append((c[0] + math.cos(t) * r, c[1] - math.sin(t) * r))
    d.line(pts, fill=fill, width=width, joint="curve")
    first, last = pts[0], pts[-1]
    d.line((first, (first[0] + r * 0.55, first[1])), fill=fill, width=width)
    d.line((last, (last[0] - r * 0.55, last[1])), fill=fill, width=width)


def omega():
    # Leuchtender Omega-Ring am Himmel: heller Strich, breiter weicher Schein.
    s = 512
    img = rgba((s, s))
    d = ImageDraw.Draw(img)
    omega_shape(d, (s / 2, s / 2 - 10), s * 0.33, 22, WHITE + (255,))
    return glow(img, 16)


def spectrum():
    # Spektrum-Verlauf fuer die Welle durchs Bild: waagerecht alle Farben,
    # zu den Raendern weich auslaufend.
    w, h = 512, 64
    img = rgba((w, h))
    px = img.load()
    for x in range(w):
        k = x / (w - 1)
        r, g, b = colorsys.hsv_to_rgb(k * 0.85, 0.75, 1.0)
        edge = math.sin(math.pi * k) ** 0.8
        for y in range(h):
            px[x, y] = (int(r * 255), int(g * 255), int(b * 255), int(230 * edge))
    return img


def orb():
    # Lichtpunkt: heller Kern, weicher Schein (wird je Pfadfarbe eingefaerbt).
    s = 128
    c = s / 2
    img = rgba((s, s))
    px = img.load()
    for y in range(s):
        for x in range(s):
            dd = math.hypot(x - c, y - c) / c
            a = max(0.0, 1 - dd) ** 2.5 + max(0.0, 1 - dd * 5)
            px[x, y] = WHITE + (int(255 * min(1.0, a)),)
    return img


def brand():
    # Omega-Brandzeichen als Bodenbild: Omega mit verbranntem, rissigem Rand.
    rnd = random.Random(14)
    s = 512
    img = rgba((s, s))
    d = ImageDraw.Draw(img)
    c = (s / 2, s / 2 - 10)
    omega_shape(d, c, s * 0.32, 34, (255, 255, 255, 120))      # Brandhof
    img = img.filter(ImageFilter.GaussianBlur(10))
    d = ImageDraw.Draw(img)
    omega_shape(d, c, s * 0.32, 14, WHITE + (255,))
    for _ in range(40):                                         # Glutfunken am Rand
        a = rnd.uniform(0, math.tau)
        r = s * 0.32 + rnd.uniform(-26, 26)
        x, y = c[0] + math.cos(a) * r, c[1] + math.sin(a) * r
        d.ellipse((x - 2, y - 2, x + 2, y + 2), fill=WHITE + (200,))
    return glow(img, 4)


def shockring():
    # Schockwellen-Ring: duenner heller Rand, innen leichter Schleier.
    s = 512
    c = s / 2
    img = rgba((s, s))
    px = img.load()
    for y in range(s):
        for x in range(s):
            dd = math.hypot(x - c, y - c) / (c - 6)
            if dd > 1:
                continue
            edge = math.exp(-((dd - 0.93) ** 2) / 0.0015)
            px[x, y] = WHITE + (int(255 * min(1.0, edge + 0.15 * dd ** 4)),)
    return img


def column():
    # Verlauf fuer die Lichtsaeule: quer weich, unten kraeftig, oben auslaufend.
    w, h = 128, 512
    img = rgba((w, h))
    px = img.load()
    for y in range(h):
        k = y / (h - 1)                     # 0 = oben, 1 = unten
        along = 0.15 + 0.85 * k ** 1.5
        for x in range(w):
            q = (x - w / 2) / (w / 2)
            px[x, y] = WHITE + (int(255 * math.exp(-(q * q) / 0.08) * along),)
    return img


TEXTURES = {
    "omega": omega,
    "spectrum": spectrum,
    "orb": orb,
    "brand": brand,
    "shockring": shockring,
    "column": column,
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
    sheet = Image.new("RGBA", (cell * (len(images) + 3), cell + 24), (12, 12, 14, 255))
    sd = ImageDraw.Draw(sheet)
    items = list(images.items())
    # Lichtpunkt zusaetzlich in allen vier Pfadfarben
    for col in PATH_COLORS[1:]:
        items.append(("orb", images["orb"], col))
    for i, item in enumerate(items):
        name, img = item[0], item[1]
        im = img.copy()
        im.thumbnail((cell - 20, cell - 20))
        if len(item) == 3 or name == "orb":
            col = item[2] if len(item) == 3 else PATH_COLORS[0]
            solid = Image.new("RGBA", im.size, col + (255,))
            solid.putalpha(im.getchannel("A"))
            im = solid
        sheet.alpha_composite(im, (i * cell + (cell - im.size[0]) // 2, (cell - im.size[1]) // 2))
        sd.text((i * cell + 8, cell + 4), name, fill=(230, 230, 230, 255))
    sheet.save(OUT / "preview.png")
    print(f"preview.png -> {OUT}")


if __name__ == "__main__":
    main()
