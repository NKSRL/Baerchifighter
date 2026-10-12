#!/usr/bin/env python3
"""
render_vfx_comet.py — zeichnet die Texturen der Kometen-Show (CometImpact)

Wie render_vfx_glacier.py: Ersatz fuer Blender, prozedural mit Pillow. Hell
auf transparentem Grund; Orange/Violett kommt in Roblox ueber
ImageColor3/Decal.Color3/Trail.Color dazu (der Kometenkopf hat einen weissen
Kern bereits im Bild).

Aufruf:  python3 tools/render_vfx_comet.py
Ausgabe: assets/vfx/comet_impact/{glow,tail,crater,stardust,shockring,debris}.png
         und preview.png.
"""

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

from render_vfx_glacier import glow, rgba

OUT = Path(__file__).resolve().parent.parent / "assets" / "vfx" / "comet_impact"
WHITE = (255, 255, 255)


def glow_head():
    # Glut des Kometenkopfs: weisser Kern, weicher Schein nach aussen.
    s = 256
    c = s / 2
    img = rgba((s, s))
    px = img.load()
    for y in range(s):
        for x in range(s):
            d = math.hypot(x - c, y - c) / c
            a = max(0.0, 1 - d) ** 2.2
            core = max(0.0, 1 - d * 4)
            v = int(200 + 55 * core)
            px[x, y] = (v, v, v, int(255 * min(1.0, a + core)))
    return img


def tail():
    # Schweif-Streifen: laengs vorne hell und schmal-hell, nach hinten
    # ausfransend (Trail streckt das Bild ueber seine Laenge, links = Kopf).
    rnd = random.Random(6)
    w, h = 512, 128
    img = rgba((w, h))
    d = ImageDraw.Draw(img)
    for _ in range(40):
        y = h / 2 + rnd.gauss(0, h * 0.12)
        length = rnd.uniform(w * 0.4, w)
        alpha = rnd.randint(60, 160)
        d.line((0, h / 2, length, y), fill=WHITE + (alpha,), width=rnd.randint(2, 6))
    img = img.filter(ImageFilter.GaussianBlur(3))
    # nach hinten ausblenden
    fade = Image.linear_gradient("L").rotate(90).resize((w, h)).transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    alpha = Image.composite(img.getchannel("A"), Image.new("L", (w, h), 0), fade)
    img.putalpha(alpha)
    return glow(img, 4)


def crater():
    # Krater-Risse als Bodenbild: strahlenfoermig, je Riss ein Knick, Mitte hell.
    rnd = random.Random(7)
    s = 512
    c = s / 2
    img = rgba((s, s))
    d = ImageDraw.Draw(img)
    d.ellipse((c - 46, c - 46, c + 46, c + 46), fill=WHITE + (200,))
    for i in range(14):
        a = i / 14 * math.tau + rnd.uniform(-0.15, 0.15)
        r1 = c * rnd.uniform(0.45, 0.6)
        r2 = c * rnd.uniform(0.75, 0.95)
        bend = a + rnd.uniform(-0.3, 0.3)
        p1 = (c + math.cos(a) * r1, c + math.sin(a) * r1)
        p2 = (c + math.cos(bend) * r2, c + math.sin(bend) * r2)
        d.line(((c, c), p1), fill=WHITE + (255,), width=9)
        d.line((p1, p2), fill=WHITE + (230,), width=5)
    return glow(img, 8)


def stardust():
    # Sternstaub-Funke: kleiner, weicher Stern mit hellem Kern.
    s = 64
    c = s / 2
    img = rgba((s, s))
    d = ImageDraw.Draw(img)
    for ang in (0, math.pi / 2, math.pi / 4, 3 * math.pi / 4):
        ln = 26 if ang in (0, math.pi / 2) else 14
        d.line((c - math.cos(ang) * ln, c - math.sin(ang) * ln, c + math.cos(ang) * ln, c + math.sin(ang) * ln),
               fill=WHITE + (255,), width=2)
    d.ellipse((c - 5, c - 5, c + 5, c + 5), fill=WHITE + (255,))
    return glow(img, 3)


def shockring():
    # Schockwellen-Ring: duenner heller Rand aussen, innen weicher Schleier.
    s = 512
    c = s / 2
    img = rgba((s, s))
    px = img.load()
    for y in range(s):
        for x in range(s):
            d = math.hypot(x - c, y - c) / (c - 6)
            if d > 1:
                continue
            edge = math.exp(-((d - 0.94) ** 2) / 0.0012)
            veil = 0.25 * d ** 3
            px[x, y] = WHITE + (int(255 * min(1.0, edge + veil)),)
    return img


def debris():
    # Truemmerbrocken: grob gesprenkelte Steinflaeche mit hellen Kanten-Rissen.
    rnd = random.Random(8)
    s = 128
    img = Image.new("RGBA", (s, s), (150, 140, 155, 255))
    d = ImageDraw.Draw(img)
    for _ in range(220):
        x, y = rnd.uniform(0, s), rnd.uniform(0, s)
        v = rnd.randint(90, 200)
        r = rnd.uniform(1, 4)
        d.ellipse((x - r, y - r, x + r, y + r), fill=(v, v - 8, v + 6, 255))
    for _ in range(4):
        x, y = rnd.uniform(0, s), rnd.uniform(0, s)
        d.line((x, y, x + rnd.uniform(-40, 40), y + rnd.uniform(-40, 40)), fill=(255, 210, 160, 255), width=2)
    return img


TEXTURES = {
    "glow": glow_head,
    "tail": tail,
    "crater": crater,
    "stardust": stardust,
    "shockring": shockring,
    "debris": debris,
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
    sheet = Image.new("RGBA", (cell * len(images), cell + 24), (14, 16, 40, 255))
    sd = ImageDraw.Draw(sheet)
    tints = {"glow": (255, 160, 70), "tail": (255, 150, 60), "crater": (255, 140, 60),
             "stardust": (200, 170, 255), "shockring": (200, 180, 255), "debris": (255, 255, 255)}
    for i, (name, img) in enumerate(images.items()):
        im = img.copy()
        im.thumbnail((cell - 20, cell - 20))
        tint = Image.new("RGBA", im.size, tints[name] + (255,))
        im = Image.composite(Image.blend(im, tint, 0.35), im, im)
        sheet.alpha_composite(im, (i * cell + (cell - im.size[0]) // 2, (cell - im.size[1]) // 2))
        sd.text((i * cell + 8, cell + 4), name, fill=(220, 220, 255, 255))
    sheet.save(OUT / "preview.png")
    print(f"preview.png -> {OUT}")


if __name__ == "__main__":
    main()
