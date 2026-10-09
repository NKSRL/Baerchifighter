#!/usr/bin/env python3
"""
make_world_textures.py — zeichnet die Texturen fuer "Welt aufwerten" (Pakete A–C)

Wie die Icons: per Python-Zeichenskript statt Blender (sauberer bei flachen,
weichen Formen, und reproduzierbar). Jede Textur ist PNG, 256 oder 512 Pixel,
mit transparentem Hintergrund, wo noetig. Kachelbare Texturen werden auf einem
Torus gezeichnet (alles, was ueber den Rand ragt, kommt gegenueber wieder
herein) — dadurch gibt es keine Naehte.

Aufruf:  python3 tools/textures/make_world_textures.py
Ausgabe: assets/world/<paket>/*.png  (ueberschreibt, deterministisch: fester Seed)

Hochladen: Studio → Asset Manager → Bulk Import (Typ Image), die IDs kommen in
WorldFXConfig.TEXTURE_IDS. Ohne ID laeuft alles mit dem Rueckfall
(Roblox-Standardpartikel bzw. reine Farbe).
"""
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent.parent / "assets" / "world"
SEED = 20261008


def save(img: Image.Image, paket: str, name: str):
    # Regel: Kantenlaenge 256 oder 512. Kleine Motive werden klein gezeichnet
    # und weich hochskaliert; nicht quadratische (Glanzstreifen) auf 256x256.
    w, h = img.size
    if w < 256 or h < 256:
        side = 256
        if w != h:
            canvas = Image.new("RGBA", (max(w, h), max(w, h)), (255, 255, 255, 0))
            canvas.paste(img, ((max(w, h) - w) // 2, (max(w, h) - h) // 2))
            img = canvas
        img = img.resize((side, side), Image.LANCZOS)
    folder = ROOT / paket
    folder.mkdir(parents=True, exist_ok=True)
    img.save(folder / f"{name}.png")
    print(f"  {paket}/{name}.png  {img.size[0]}x{img.size[1]}")


def radial(size: int, color, inner=0.0, outer=1.0, power=1.6) -> Image.Image:
    """Weicher runder Punkt: voll in der Mitte, nach aussen transparent."""
    img = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    px = img.load()
    c = (size - 1) / 2
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - c, y - c) / c
            if d >= outer:
                continue
            k = 1.0 if d <= inner else 1 - (d - inner) / (outer - inner)
            a = int(255 * (k ** power))
            px[x, y] = (*color, a)
    return img


def tile_draw(size: int, draw_fn):
    """Zeichnet auf einem Torus: draw_fn bekommt (draw, dx, dy) neunmal.
    Hintergrund hell-transparent (nicht schwarz-transparent), sonst zieht
    das Weichzeichnen dunkle Raender in die hellen Formen."""
    img = Image.new("RGBA", (size, size), (255, 252, 244, 0))
    draw = ImageDraw.Draw(img)
    for dx in (-size, 0, size):
        for dy in (-size, 0, size):
            draw_fn(draw, dx, dy)
    return img


def wrap_blur(img: Image.Image, radius: float) -> Image.Image:
    """Weichzeichnen ohne Naht: 3x3 kacheln, blurren, Mitte ausschneiden."""
    s = img.size[0]
    big = Image.new("RGBA", (s * 3, s * 3))
    for i in range(3):
        for j in range(3):
            big.paste(img, (i * s, j * s))
    big = big.filter(ImageFilter.GaussianBlur(radius))
    return big.crop((s, s, 2 * s, 2 * s))


# ---------------------------------------------------------------------------
# Paket A: Himmel
# ---------------------------------------------------------------------------

def cloud_flipbook():
    """Zwei Wolkenpuff-Varianten als Flipbook. Roblox kennt nur Grid2x2,
    4x4 und 8x8, deshalb liegen beide Varianten zweimal im 2x2-Raster
    (Bild 1 = 3, Bild 2 = 4); der Emitter blaettert nicht, er waehlt per
    FlipbookStartRandom eine Zelle (FlipbookMode OneShot mit Framerate 0)."""
    rnd = random.Random(SEED + 1)
    size = 512
    cell = size // 2
    img = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    for idx in range(4):
        variant = idx % 2
        layer = Image.new("RGBA", (cell, cell), (255, 255, 255, 0))
        d = ImageDraw.Draw(layer)
        lumps = 5 if variant == 0 else 7
        for i in range(lumps):
            r = rnd.uniform(34, 58) if variant == 0 else rnd.uniform(26, 46)
            x = cell * (0.25 + 0.5 * i / (lumps - 1)) + rnd.uniform(-8, 8)
            y = cell * 0.55 + rnd.uniform(-22, 10) - (r - 30) * 0.4
            d.ellipse((x - r, y - r * 0.8, x + r, y + r * 0.8), fill=(255, 255, 255, 235))
        layer = layer.filter(ImageFilter.GaussianBlur(9))
        img.paste(layer, ((idx % 2) * cell, (idx // 2) * cell), layer)
    save(img, "paket_a", "cloud_puff_flipbook")


def firefly():
    core = radial(128, (255, 248, 190), inner=0.06, outer=1.0, power=2.4)
    save(core, "paket_a", "firefly")


def star_twinkle():
    size = 128
    img = radial(size, (255, 255, 255), inner=0.0, outer=0.35, power=2.0)
    d = ImageDraw.Draw(img)
    c = size / 2
    # Vier weiche Strahlen
    rays = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    rd = ImageDraw.Draw(rays)
    rd.polygon([(c, 4), (c + 5, c), (c, size - 4), (c - 5, c)], fill=(255, 255, 255, 200))
    rd.polygon([(4, c), (c, c - 5), (size - 4, c), (c, c + 5)], fill=(255, 255, 255, 200))
    rays = rays.filter(ImageFilter.GaussianBlur(2.5))
    img = Image.alpha_composite(rays, img)
    save(img, "paket_a", "star_twinkle")


# ---------------------------------------------------------------------------
# Paket B: Wasser und Kueste
# ---------------------------------------------------------------------------

def water_glitter():
    """Feine Lichtpunkte, kachelbar. Weiss auf transparent; eingefaerbt wird
    in Roblox ueber Texture.Color3."""
    rnd = random.Random(SEED + 2)
    size = 512
    pts = [(rnd.uniform(0, size), rnd.uniform(0, size), rnd.uniform(0.8, 2.6)) for _ in range(150)]

    def draw(d, dx, dy):
        for x, y, r in pts:
            d.ellipse((x + dx - r, y + dy - r * 0.6, x + dx + r, y + dy + r * 0.6), fill=(255, 255, 255, 255))

    img = tile_draw(size, draw)
    img = wrap_blur(img, 0.8)
    save(img, "paket_b", "water_glitter")


def water_waves():
    """Weiche Wellenlinien, kachelbar (Sinus mit ganzzahliger Periode)."""
    rnd = random.Random(SEED + 3)
    size = 512
    img = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    d = ImageDraw.Draw(img)
    rows = 9
    for row in range(rows):
        y0 = (row + rnd.uniform(-0.2, 0.2)) * size / rows
        amp = rnd.uniform(5, 11)
        k = rnd.choice([2, 3, 4])
        phase = rnd.uniform(0, math.tau)
        # Stuecke statt einer durchgehenden Linie: wirkt wie Wellenkaemme
        seg_start = rnd.uniform(0, size)
        seg_len = rnd.uniform(size * 0.25, size * 0.55)
        for dy in (-size, 0, size):
            pts = []
            for i in range(0, int(seg_len), 4):
                x = (seg_start + i) % size
                y = y0 + amp * math.sin(math.tau * k * x / size + phase) + dy
                pts.append((x, y))
            # an der Kante umbrechen: Linie nur zwischen Nachbarn ohne Sprung
            for a, b in zip(pts, pts[1:]):
                if abs(a[0] - b[0]) < 10:
                    d.line([a, b], fill=(255, 255, 255, 200), width=4)
    img = wrap_blur(img, 1.6)
    save(img, "paket_b", "water_waves")


def foam_lace():
    """Schaum als kachelbare Spitze: Blasen und Kraenze in Cremeweiss mit
    Luecken. Auf dem schmalen Saum (3,5 Studs) liest sich der Kreisrand
    dadurch ausgefranst, obwohl die Scheibe rund ist. Ein Ring-Bild passt
    nicht: der sichtbare Saum ist je nach Insel 3–9 % des Radius breit."""
    rnd = random.Random(SEED + 4)
    size = 256
    blobs = [(rnd.uniform(0, size), rnd.uniform(0, size), rnd.uniform(3, 11), rnd.random() < 0.55) for _ in range(120)]

    def draw(d, dx, dy):
        for x, y, r, ring in blobs:
            box = (x + dx - r, y + dy - r, x + dx + r, y + dy + r)
            if ring:
                d.ellipse(box, outline=(255, 250, 236, 235), width=max(2, int(r * 0.35)))
            else:
                d.ellipse(box, fill=(255, 250, 236, 200))

    img = tile_draw(size, draw)
    img = wrap_blur(img, 1.2)
    save(img, "paket_b", "foam_lace")


def splash_flipbook():
    """Spritzer, 4 Bilder im 2x2-Raster (ParticleEmitter Grid2x2)."""
    rnd = random.Random(SEED + 5)
    size = 256
    cell = size // 2
    img = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    drops = [(rnd.uniform(-1.2, 1.2), rnd.uniform(0.6, 1.0), rnd.uniform(6, 11)) for _ in range(9)]
    for frame in range(4):
        t = (frame + 1) / 4
        layer = Image.new("RGBA", (cell, cell), (255, 255, 255, 0))
        d = ImageDraw.Draw(layer)
        cx, base = cell / 2, cell * 0.85
        for vx, vy, r in drops:
            x = cx + vx * 40 * t
            y = base - vy * 90 * t + 70 * t * t
            rr = r * (1 - 0.5 * t)
            alpha = int(255 * (1 - t * 0.5))
            d.ellipse((x - rr, y - rr * 1.3, x + rr, y + rr * 1.3), fill=(255, 255, 255, alpha))
        # Kranz am Boden
        w = 22 + 30 * t
        d.ellipse((cx - w, base - 7, cx + w, base + 7), outline=(255, 255, 255, int(240 * (1 - t * 0.6))), width=5)
        layer = layer.filter(ImageFilter.GaussianBlur(0.8))
        img.paste(layer, ((frame % 2) * cell, (frame // 2) * cell), layer)
    save(img, "paket_b", "splash_flipbook")


def water_ring():
    size = 256
    img = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    px = img.load()
    c = (size - 1) / 2
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - c, y - c) / c
            a = math.exp(-((d - 0.82) / 0.07) ** 2) + 0.35 * math.exp(-((d - 0.6) / 0.05) ** 2)
            if a > 0.01:
                px[x, y] = (255, 255, 255, int(255 * min(1.0, a)))
    save(img, "paket_b", "water_ring")


# ---------------------------------------------------------------------------
# Paket C: Hauptinsel
# ---------------------------------------------------------------------------

def hexagon(cx, cy, r, rot=0.0):
    return [(cx + r * math.cos(rot + i * math.pi / 3), cy + r * math.sin(rot + i * math.pi / 3)) for i in range(6)]


def amber_comb():
    """Leuchtende Bernstein-Wabe (fuer die Mastkrone): heller Kern, dunkler
    Rand. Weiss-basiert waere zu blass, deshalb in Bernstein gemalt."""
    size = 256
    img = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    d = ImageDraw.Draw(img)
    c = size / 2
    d.polygon(hexagon(c, c, 120), fill=(196, 112, 22, 255))
    glow = radial(size, (255, 214, 110), inner=0.1, outer=0.92, power=1.3)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).polygon(hexagon(c, c, 104), fill=255)
    inner = Image.new("RGBA", (size, size), (232, 150, 40, 255))
    inner = Image.alpha_composite(inner, glow)
    img.paste(inner, (0, 0), mask)
    d.line(hexagon(c, c, 104) + [hexagon(c, c, 104)[0]], fill=(150, 80, 16, 255), width=6)
    # Glanzpunkt
    hl = radial(64, (255, 255, 240), inner=0.0, outer=1.0, power=2.0)
    img.alpha_composite(hl, (int(c - 62), int(c - 70)))
    save(img, "paket_c", "amber_comb")


def honey_drop():
    size = 128
    img = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    d = ImageDraw.Draw(img)
    # Tropfen: Kreis unten + Spitze oben
    d.ellipse((30, 46, 98, 114), fill=(240, 160, 30, 255))
    d.polygon([(64, 8), (34, 70), (94, 70)], fill=(240, 160, 30, 255))
    img = img.filter(ImageFilter.GaussianBlur(1.0))
    hl = radial(28, (255, 250, 220), outer=1.0, power=1.5)
    img.alpha_composite(hl, (44, 60))
    save(img, "paket_c", "honey_drop")


def honey_bubble():
    size = 128
    img = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    px = img.load()
    c = (size - 1) / 2
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - c, y - c) / c
            if d > 1:
                continue
            a = 0.18 + 0.82 * (d ** 6)
            px[x, y] = (255, 206, 90, int(255 * a))
    hl = radial(30, (255, 255, 255), outer=1.0, power=1.4)
    img.alpha_composite(hl, (34, 28))
    save(img, "paket_c", "honey_bubble")


def insect_flipbook(name: str, body, stripe, wing_alpha: int):
    """Biene/Wespe von oben, 2 Fluegelbilder (Grid2x2: Bild 1,2,1,2)."""
    size = 256
    cell = size // 2
    img = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    for frame in range(4):
        up = frame % 2 == 0
        layer = Image.new("RGBA", (cell, cell), (255, 255, 255, 0))
        d = ImageDraw.Draw(layer)
        cx, cy = cell / 2, cell / 2 + 8
        # Fluegel
        wy = cy - (26 if up else 14)
        for sx in (-1, 1):
            d.ellipse((cx + sx * 6 - 22 + sx * 14, wy - 14, cx + sx * 6 + 22 + sx * 14, wy + 14),
                      fill=(235, 245, 255, wing_alpha), outline=(120, 130, 150, 200), width=2)
        # Koerper
        d.ellipse((cx - 22, cy - 30, cx + 22, cy + 30), fill=(*body, 255), outline=(40, 30, 20, 255), width=3)
        for k in (-8, 6):
            d.rectangle((cx - 20, cy + k, cx + 20, cy + k + 8), fill=(*stripe, 255))
        d.ellipse((cx - 14, cy - 44, cx + 14, cy - 20), fill=(40, 30, 20, 255))
        layer = layer.filter(ImageFilter.GaussianBlur(0.6))
        img.paste(layer, ((frame % 2) * cell, (frame // 2) * cell), layer)
    save(img, "paket_c", name)


def pennant_fabric():
    """Wimpel-Stoff: Dreieck mit Streifen und Saum (Stoffmuster, Spitze unten)."""
    size = 256
    img = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    d = ImageDraw.Draw(img)
    tri = [(16, 16), (240, 16), (128, 244)]
    d.polygon(tri, fill=(255, 255, 255, 255))
    for i in range(4):
        y = 40 + i * 44
        d.rectangle((0, y, size, y + 14), fill=(255, 228, 236, 255))
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).polygon(tri, fill=255)
    out = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    out.paste(img, (0, 0), mask)
    ImageDraw.Draw(out).line(tri + [tri[0]], fill=(200, 160, 170, 255), width=5)
    save(out, "paket_c", "pennant_fabric")


def stall_stripes():
    """Haendler-Stoffstreifen, kachelbar in U."""
    size = 256
    img = Image.new("RGBA", (size, size), (255, 244, 236, 255))
    d = ImageDraw.Draw(img)
    for i in range(4):
        x = i * 64
        d.rectangle((x, 0, x + 31, size), fill=(240, 130, 160, 255))
    # leichte Stoffstruktur
    rnd = random.Random(SEED + 6)
    for _ in range(1800):
        x, y = rnd.randrange(size), rnd.randrange(size)
        r, g, b, a = img.getpixel((x, y))
        img.putpixel((x, y), (max(0, r - 12), max(0, g - 12), max(0, b - 12), a))
    save(img, "paket_c", "stall_stripes")


def bear_sign():
    """Holzschild in Baerchi-Form: Brett mit zwei runden Ohren."""
    size = 512
    img = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    d = ImageDraw.Draw(img)
    wood = (176, 122, 72, 255)
    dark = (120, 80, 44, 255)
    d.ellipse((70, 40, 190, 160), fill=wood, outline=dark, width=10)
    d.ellipse((322, 40, 442, 160), fill=wood, outline=dark, width=10)
    d.rounded_rectangle((30, 110, 482, 460), radius=90, fill=wood, outline=dark, width=12)
    for y in range(150, 440, 46):
        d.line((70, y, 442, y + 6), fill=(160, 108, 62, 255), width=4)
    d.ellipse((100, 70, 160, 130), fill=(214, 168, 120, 255))
    d.ellipse((352, 70, 412, 130), fill=(214, 168, 120, 255))
    save(img, "paket_c", "bear_sign")


def shine_strip():
    """Glanzstreifen: schmaler, schraeger heller Balken mit weichen Raendern."""
    w, h = 256, 64
    img = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    px = img.load()
    for y in range(h):
        for x in range(w):
            u = (x - (w / 2) - (y - h / 2) * 0.6) / (w * 0.12)
            a = math.exp(-u * u)
            px[x, y] = (255, 255, 255, int(220 * a))
    save(img, "paket_c", "shine_strip")


def main():
    print("Paket A")
    cloud_flipbook(); firefly(); star_twinkle()
    print("Paket B")
    water_glitter(); water_waves(); foam_lace(); splash_flipbook(); water_ring()
    print("Paket C")
    amber_comb(); honey_drop(); honey_bubble()
    insect_flipbook("bee_flipbook", (250, 200, 40), (50, 36, 20), 170)
    insect_flipbook("wasp_flipbook", (214, 128, 26), (22, 16, 12), 150)
    pennant_fabric(); stall_stripes(); bear_sign(); shine_strip()


if __name__ == "__main__":
    main()
