#!/usr/bin/env python3
"""
render_vfx_shade.py — zeichnet die Texturen der Schemen-Show (ShadeSlash)

Wie render_vfx_glacier.py: Ersatz fuer Blender, prozedural mit Pillow. Weiss
bzw. hell auf transparentem Grund; Tintenschwarz und Violett kommen in Roblox
ueber Decal.Color3 bzw. ParticleEmitter.Color dazu. Nur die Schnittlinie
bleibt weiss (ihr Decal wird nicht eingefaerbt).

Die Silhouette folgt dem Umriss unseres Baerchis wie im Icon
(assets/icons/bear.png): runder Kopf, zwei runde Ohren, rundlicher Koerper,
kurze Arme und Beine. Das echte Mesh liegt hier nicht vor. Ohne hochgeladenes
Bild nimmt die Show ohnehin einen Klon des echten Modells (exakter Umriss).

Aufruf:  python3 tools/render_vfx_shade.py
Ausgabe: assets/vfx/shade_slash/{silhouette,shred,cut,pool,smoke}.png und preview.png.
"""

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

from render_vfx_glacier import glow, rgba

OUT = Path(__file__).resolve().parent.parent / "assets" / "vfx" / "shade_slash"
WHITE = (255, 255, 255)


def silhouette():
    # Baerchi-Umriss von vorn, Raender rauchig ausgefranst.
    w, h = 384, 512
    shape = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(shape)
    cx = w / 2
    d.ellipse((cx - 120, 250, cx + 120, 480), fill=255)          # Koerper
    d.ellipse((cx - 105, 70, cx + 105, 270), fill=255)           # Kopf
    for sx in (-1, 1):
        d.ellipse((cx + sx * 85 - 40, 50, cx + sx * 85 + 40, 130), fill=255)   # Ohren
        d.ellipse((cx + sx * 120 - 38, 290, cx + sx * 120 + 38, 400), fill=255)  # Arme
        d.ellipse((cx + sx * 60 - 48, 420, cx + sx * 60 + 48, 500), fill=255)    # Fuesse
    # Rauch am Rand: Rand weichzeichnen, dann mit Rauschen ausfransen
    soft = shape.filter(ImageFilter.GaussianBlur(6))
    noise = Image.effect_noise((w, h), 70).filter(ImageFilter.GaussianBlur(3))
    px_s, px_n = soft.load(), noise.load()
    alpha = Image.new("L", (w, h), 0)
    px_a = alpha.load()
    for y in range(h):
        for x in range(w):
            a = px_s[x, y]
            if 0 < a < 255:
                a = max(0, min(255, int(a + (px_n[x, y] - 128) * 1.2)))
            px_a[x, y] = a
    img = Image.new("RGBA", (w, h), WHITE + (0,))
    img.putalpha(alpha)
    return img


def shred():
    # Schattenfetzen: unregelmaessiges, zerrissenes Stueck.
    rnd = random.Random(10)
    s = 128
    img = rgba((s, s))
    d = ImageDraw.Draw(img)
    pts = []
    for i in range(14):
        a = i / 14 * math.tau
        r = rnd.uniform(28, 60)
        pts.append((s / 2 + math.cos(a) * r * 0.7, s / 2 + math.sin(a) * r))
    d.polygon(pts, fill=WHITE + (235,))
    return img.filter(ImageFilter.GaussianBlur(1.5))


def cut():
    # Schnittlinie: duenner heller Kern, Raender ausgefranst (laengs = Bildhoehe).
    rnd = random.Random(11)
    w, h = 64, 512
    img = rgba((w, h))
    d = ImageDraw.Draw(img)
    cx = w / 2
    d.line((cx, 0, cx, h), fill=WHITE + (255,), width=4)
    for y in range(0, h, 6):
        ln = rnd.uniform(2, 10)
        side = rnd.choice((-1, 1))
        d.line((cx, y, cx + side * ln, y + rnd.uniform(-4, 4)), fill=WHITE + (200,), width=1)
    return glow(img, 3)


def pool():
    # Schattenpfuetze als Bodenbild: weicher, leicht unregelmaessiger Fleck.
    rnd = random.Random(12)
    s = 256
    c = s / 2
    img = rgba((s, s))
    d = ImageDraw.Draw(img)
    for _ in range(9):
        r = rnd.uniform(50, 80)
        ox, oy = rnd.uniform(-30, 30), rnd.uniform(-30, 30)
        d.ellipse((c + ox - r, c + oy - r, c + ox + r, c + oy + r), fill=WHITE + (255,))
    return img.filter(ImageFilter.GaussianBlur(10))


def smoke():
    # Rauchschwade: weiche, wolkige Flocke fuer den Emitter.
    rnd = random.Random(13)
    s = 256
    img = rgba((s, s))
    d = ImageDraw.Draw(img)
    for _ in range(18):
        r = rnd.uniform(25, 55)
        x, y = rnd.uniform(70, 186), rnd.uniform(70, 186)
        d.ellipse((x - r, y - r, x + r, y + r), fill=WHITE + (45,))
    return img.filter(ImageFilter.GaussianBlur(14))


TEXTURES = {
    "silhouette": silhouette,
    "shred": shred,
    "cut": cut,
    "pool": pool,
    "smoke": smoke,
}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    images = {}
    for name, fn in TEXTURES.items():
        img = fn()
        img.save(OUT / f"{name}.png")
        images[name] = img
        print(f"{name}.png {img.size[0]}x{img.size[1]}")
    # Vorschau: wie im Spiel eingefaerbt (Tinte/Violett) auf grauem Schleier
    cell = 220
    sheet = Image.new("RGBA", (cell * len(images), cell + 24), (150, 150, 165, 255))
    sd = ImageDraw.Draw(sheet)
    tints = {"silhouette": (18, 14, 26), "shred": (85, 50, 135), "cut": (255, 255, 255),
             "pool": (18, 14, 26), "smoke": (60, 45, 90)}
    for i, (name, img) in enumerate(images.items()):
        im = img.copy()
        im.thumbnail((cell - 20, cell - 20))
        solid = Image.new("RGBA", im.size, tints[name] + (255,))
        solid.putalpha(im.getchannel("A"))
        sheet.alpha_composite(solid, (i * cell + (cell - im.size[0]) // 2, (cell - im.size[1]) // 2))
        sd.text((i * cell + 8, cell + 4), name, fill=(20, 20, 30, 255))
    sheet.save(OUT / "preview.png")
    print(f"preview.png -> {OUT}")


if __name__ == "__main__":
    main()
