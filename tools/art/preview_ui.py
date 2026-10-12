"""
preview_ui.py — Vorschau (Mockup) von Ei-Baum, Ei-Fenster und Handy-Ansicht
aus den echten PNGs in assets/ui und den Layout-Daten aus
src/client/UI/EggTreeLayout.luau. KEIN Studio-Screenshot: Schrift und
Feinheiten weichen ab; Lage, Bilder, Zustaende und Groessen stimmen.

    python tools/art/preview_ui.py        (braucht Pillow und den luau-CLI im PATH)

Ausgabe: docs/preview_ei_ui/*.png
"""

import json
import math
import os
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
A = os.path.join(ROOT, "assets", "ui")
OUT = os.path.join(ROOT, "docs", "preview_ei_ui")
FONT = "/usr/share/fonts/opentype/inter/InterDisplay-Bold.otf"
OUTLINE = (24, 20, 38)

PATH_COLOR = {"Stamm": (238, 214, 170), "Gold": (255, 196, 60), "Kristall": (120, 220, 255),
              "Void": (150, 90, 230), "Kosmos": (92, 72, 255), "Ascension": (196, 128, 255)}
HONEY_LIGHT = (255, 206, 96)
TINT = {"locked": (104, 98, 94), "ready": (214, 204, 190), "open": (255, 255, 255)}

_img_cache = {}


def img(name):
    if name not in _img_cache:
        _img_cache[name] = Image.open(os.path.join(A, name + ".png")).convert("RGBA")
    return _img_cache[name]


def font(size):
    try:
        return ImageFont.truetype(FONT, size)
    except OSError:
        return ImageFont.load_default()


def text(draw, xy, s, size, fill=(255, 255, 255), anchor="la", stroke=2):
    draw.text(xy, s, font=font(size), fill=fill, anchor=anchor, stroke_width=stroke, stroke_fill=OUTLINE)


def tint(im, color):
    r, g, b, a = im.split()
    r = r.point(lambda v: v * color[0] // 255)
    g = g.point(lambda v: v * color[1] // 255)
    b = b.point(lambda v: v * color[2] // 255)
    return Image.merge("RGBA", (r, g, b, a))


def fade(im, alpha):
    r, g, b, a = im.split()
    a = a.point(lambda v: int(v * alpha))
    return Image.merge("RGBA", (r, g, b, a))


def paste_center(dst, im, cx, cy, anchor=(0.5, 0.5)):
    dst.alpha_composite(im, (int(cx - im.width * anchor[0]), int(cy - im.height * anchor[1])))


def nine(name, w, h, sl, scale):
    """9-Slice wie Roblox (SliceCenter sl = l,t,r,b; SliceScale)."""
    src = img(name)
    W, H = src.size
    l, t, r, b = sl
    L, T, R, B = int(l * scale), int(t * scale), int((W - r) * scale), int((H - b) * scale)
    out = Image.new("RGBA", (w, h))
    cols = [(0, l, 0, L), (l, r, L, w - R), (r, W, w - R, w)]
    rows = [(0, t, 0, T), (t, b, T, h - B), (b, H, h - B, h)]
    for sx0, sx1, dx0, dx1 in cols:
        for sy0, sy1, dy0, dy1 in rows:
            if dx1 <= dx0 or dy1 <= dy0:
                continue
            piece = src.crop((sx0, sy0, sx1, sy1)).resize((dx1 - dx0, dy1 - dy0), Image.LANCZOS)
            out.alpha_composite(piece, (dx0, dy0))
    return out


# --------------------------------------------------------------------------
# Layout aus Luau lesen
# --------------------------------------------------------------------------

def read_layout():
    src = open(os.path.join(ROOT, "src/client/UI/EggTreeLayout.luau"), encoding="utf-8").read()
    script = "local L = (function()\n" + src + "\nend)()\n" + r'''
local function q(s) return '"' .. s .. '"' end
local parts = {}
table.insert(parts, '"size":[' .. L.SIZE.x .. ',' .. L.SIZE.y .. ']')
local n = {}
for id, p in L.NODES do table.insert(n, q(id) .. ':[' .. p.x .. ',' .. p.y .. ']') end
table.insert(parts, '"nodes":{' .. table.concat(n, ',') .. '}')
local e = {}
for _, edge in L.EDGES do
	local pts = {}
	for _, p in L.sample(edge, 26) do table.insert(pts, '[' .. p.x .. ',' .. p.y .. ']') end
	table.insert(e, '{"to":' .. q(edge.to) .. ',"path":' .. q(edge.path) .. ',"width":' .. edge.width
		.. ',"trunk":' .. tostring(edge.trunk == true) .. ',"pts":[' .. table.concat(pts, ',') .. ']}')
end
table.insert(parts, '"edges":[' .. table.concat(e, ',') .. ']')
local t = L.TRUNK
table.insert(parts, '"trunk":[' .. t.x .. ',' .. t.y .. ',' .. t.w .. ',' .. t.h .. ']')
table.insert(parts, '"egg":' .. L.EGG_HEIGHT .. ',"cupScale":' .. L.CUP_SCALE .. ',"cupAnchor":' .. L.CUP_ANCHOR)
print('{' .. table.concat(parts, ',') .. '}')
'''
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False) as f:
        f.write(script.replace("--!strict", ""))
        path = f.name
    out = subprocess.run(["luau", path], capture_output=True, text=True, check=True).stdout
    os.unlink(path)
    return json.loads(out)


# --------------------------------------------------------------------------
# Baum zeichnen
# --------------------------------------------------------------------------

def capsule_mask(w, h):
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, w - 1, h - 1), radius=h // 2, fill=255)
    return m


def segment_image(tex, length, w, color_tint):
    W, H = int(length + w), int(w)
    tile = tex.resize((int(w * 4), H), Image.LANCZOS)
    strip = Image.new("RGBA", (W, H))
    x = 0
    while x < W:
        strip.alpha_composite(tile, (x, 0))
        x += tile.width
    strip = tint(strip, color_tint)
    m = capsule_mask(W, H)
    strip.putalpha(Image.composite(strip.split()[3], Image.new("L", (W, H), 0), m))
    return strip


def draw_rotated(dst, im, cx, cy, deg):
    rot = im.rotate(-deg, expand=True, resample=Image.BICUBIC)
    dst.alpha_composite(rot, (int(cx - rot.width / 2), int(cy - rot.height / 2)))


def egg_image(egg_id, h, silhouette=False):
    im = img("eggs/" + egg_id).resize((h, h), Image.LANCZOS)
    if silhouette:
        im = tint(im, (38, 30, 46))
    return im


def draw_tree(L, states, wave=None, selected=None, glow_t=0.3, bloom=None):
    W, H = L["size"]
    canvas = Image.new("RGBA", (W, H))
    bg = img("tree/tree_bg").resize((W, H), Image.LANCZOS)
    canvas.alpha_composite(bg)
    # Pollen/Honiglicht
    import random
    rnd = random.Random(4)
    for i in range(30):
        honey = i % 3 == 0
        s = rnd.randint(26, 46) if honey else rnd.randint(8, 16)
        p = img("fx/honeylight" if honey else "fx/pollen").resize((s, s), Image.LANCZOS)
        canvas.alpha_composite(fade(p, 0.55), (rnd.randint(0, W), rnd.randint(0, H)))
    # Sternbild-Linien zum Kometen
    sp = img("fx/sparkle").resize((12, 12), Image.LANCZOS)
    comet = L["nodes"]["CometEgg"]
    for src in ("ZenithEgg", "AuroraEgg", "AbyssEgg"):
        a = L["nodes"][src]
        dx, dy = comet[0] - a[0], comet[1] - a[1]
        n = int(math.hypot(dx, dy) / 28)
        on = states.get(src) == "open"
        for i in range(1, n):
            paste_center(canvas, fade(tint(sp, (176, 168, 255)), 0.9 if on else 0.3),
                         a[0] + dx * i / n, a[1] - 30 + (dy + 30) * i / n)
    # Stamm
    tx, ty, tw, th = L["trunk"]
    canvas.alpha_composite(img("tree/trunk").resize((tw, th), Image.LANCZOS), (tx, ty))

    glow_tex = img("tree/branch_glow")
    layers = {"outline": [], "fill": [], "glow": []}
    for e in L["edges"]:
        st = "open" if e["trunk"] else states.get(e["to"], "locked")
        pts = e["pts"]
        tex = img("tree/branch_" + e["path"].lower())
        s = 0
        total = sum(math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1]) for i in range(len(pts) - 1))
        for i in range(len(pts) - 1):
            (ax, ay), (bx, by) = pts[i], pts[i + 1]
            ln = math.hypot(bx - ax, by - ay)
            t = (i + 0.5) / (len(pts) - 1)
            w = e["width"] * (1 - 0.38 * t)
            cx, cy = (ax + bx) / 2, (ay + by) / 2
            deg = math.degrees(math.atan2(by - ay, bx - ax))
            mid = s + ln / 2
            s += ln
            if not e["trunk"]:
                ol = Image.new("RGBA", (int(ln + w + 6), int(w + 7)))
                ImageDraw.Draw(ol).rounded_rectangle((0, 0, ol.width - 1, ol.height - 1), radius=ol.height // 2, fill=OUTLINE + (255,))
                layers["outline"].append((ol, cx, cy, deg))
                layers["fill"].append((segment_image(tex, ln, w, TINT[st]), cx, cy, deg))
            # Glow je Zustand
            if e["trunk"]:
                tr, col = 0.72, HONEY_LIGHT
            elif st == "open":
                tr, col = 0.48, tuple(int(PATH_COLOR[e["path"]][k] * 0.55 + HONEY_LIGHT[k] * 0.45) for k in range(3))
            elif st == "ready":
                head = total * glow_t
                d = (mid - head) / 46
                tr, col = 1 - 0.85 * math.exp(-d * d), HONEY_LIGHT
            else:
                tr, col = 1, HONEY_LIGHT
            if wave and e["to"] in wave["edges"]:
                off = wave["edges"][e["to"]]
                d = (off + mid - wave["head"]) / 70
                b = math.exp(-d * d)
                if off + mid < wave["head"]:
                    b = max(b, 0.35)
                if 1 - b < tr:
                    tr, col = 1 - b, (255, 246, 214)
            if tr < 0.99:
                gw = int(w * (1.4 if e["trunk"] else 0.7))
                g = tint(glow_tex.resize((int(ln + 1), max(2, gw)), Image.LANCZOS), col)
                layers["glow"].append((fade(g, 1 - tr), cx, cy, deg))
    for key in ("outline", "fill", "glow"):
        for im, cx, cy, deg in layers[key]:
            draw_rotated(canvas, im, cx, cy, deg)

    # Knoten
    eh = L["egg"]
    cw = int(eh * L["cupScale"])
    d = ImageDraw.Draw(canvas)
    for egg_id, (x, y) in L["nodes"].items():
        st = states.get(egg_id, "locked")
        cup_scale = 1.0
        if bloom and bloom.get("egg") == egg_id:
            cup_scale = bloom.get("cup", 1.0)
        top = y - cw * L["cupAnchor"]
        if selected == egg_id:
            ring = img("fx/ring_soft").resize((int(cw * 1.15), int(cw * 1.15)), Image.LANCZOS)
            paste_center(canvas, fade(ring, 0.65), x, top + cw * 0.42)
        cs = int(cw * cup_scale)
        back = img("tree/cup_%s_back" % st).resize((cs, cs), Image.LANCZOS)
        front = img("tree/cup_%s_front" % st).resize((cs, cs), Image.LANCZOS)
        paste_center(canvas, back, x, y, (0.5, L["cupAnchor"]))
        # Halo/Kranz fuer seltene Eier (offen)
        lift = bloom.get("lift", 0) if bloom and bloom.get("egg") == egg_id else 0
        egg = egg_image(egg_id, eh, st == "locked")
        if st != "locked":
            tier = TIERS.get(egg_id, 1)
            if tier >= 9:
                rays = tint(img("fx/ring_rays"), (255, 236, 200)).resize((int(eh * 1.9),) * 2, Image.LANCZOS)
                paste_center(canvas, fade(rays, 0.75), x, y + 4 - eh * 0.885 + eh / 2 - lift)
            if tier >= 6:
                halo = img("fx/ring_soft").resize((int(eh * 1.35),) * 2, Image.LANCZOS)
                paste_center(canvas, fade(halo, 0.45), x, y + 4 - eh * 0.885 + eh / 2 - lift)
        if st == "ready":
            s2 = int(eh * 1.04)
            egg = egg_image(egg_id, s2, False)
        canvas.alpha_composite(egg, (int(x - egg.width / 2), int(y + 4 - egg.height * 0.885 - lift)))
        paste_center(canvas, front, x, y, (0.5, L["cupAnchor"]))
        if st == "locked":
            lock = img("tree/lock").resize((34, 34), Image.LANCZOS)
            paste_center(canvas, lock, x - cw / 2 + cw * 0.74, top + cw * 0.34)
        text(d, (x, top + cw * 0.72 + 10), NAMES.get(egg_id, egg_id), 15,
             (188, 182, 210) if st == "locked" else (255, 255, 255), anchor="mm")
    if bloom and bloom.get("sparks"):
        x, y = L["nodes"][bloom["egg"]]
        r = bloom["sparks"]
        ring = tint(img("fx/ring_soft"), HONEY_LIGHT).resize((int(20 + 150 * r), int(10 + 60 * r)), Image.LANCZOS)
        paste_center(canvas, fade(ring, 1 - r * 0.8), x, y - 6)
        for i in range(12):
            a = i / 12 * math.tau
            dist = (58 + (i % 3) * 10) * r
            s = max(6, int(18 - 12 * r))
            spk = tint(img("fx/sparkle"), (255, 246, 214) if i % 2 == 0 else HONEY_LIGHT).resize((s, s), Image.LANCZOS)
            paste_center(canvas, fade(spk, 1 - r * 0.7), x + math.cos(a) * dist, y - 8 + math.sin(a) * dist * 0.5)
    return canvas


NAMES = {"BasicEgg": "Basis-Ei", "SugarEgg": "Zucker-Ei", "GoldenEgg": "Goldenes Ei", "PlatinumEgg": "Platin-Ei",
         "SunEgg": "Sonnen-Ei", "ZenithEgg": "Zenit-Ei", "CrystalEgg": "Kristall-Ei", "PrismEgg": "Prisma-Ei",
         "AuroraEgg": "Aurora-Ei", "MistEgg": "Nebel-Ei", "VoidEgg": "Void-Ei", "ShadowEgg": "Schatten-Ei",
         "AbyssEgg": "Abyss-Ei", "CometEgg": "Kometen-Ei", "NovaEgg": "Nova-Ei", "GalaxyEgg": "Galaxie-Ei",
         "AscensionEgg": "Ascensions-Ei", "TranscendenceEgg": "Transzendenz-Ei", "EternityEgg": "Ewigkeits-Ei",
         "OmegaEgg": "Omega-Ei", "UfoJackpotEgg": "UFO-Jackpot-Ei"}
TIERS = {"BasicEgg": 1, "SugarEgg": 2, "GoldenEgg": 3, "PlatinumEgg": 4, "SunEgg": 5, "ZenithEgg": 6,
         "CrystalEgg": 4, "PrismEgg": 5, "AuroraEgg": 6, "MistEgg": 3, "VoidEgg": 4, "ShadowEgg": 5,
         "AbyssEgg": 6, "CometEgg": 7, "NovaEgg": 8, "GalaxyEgg": 9, "AscensionEgg": 5,
         "TranscendenceEgg": 9, "EternityEgg": 10, "OmegaEgg": 11}

MIXED = {
    "BasicEgg": "open", "SugarEgg": "open", "GoldenEgg": "open", "PlatinumEgg": "open", "SunEgg": "ready",
    "CrystalEgg": "ready", "MistEgg": "open", "VoidEgg": "open", "ShadowEgg": "ready",
    "AscensionEgg": "open", "TranscendenceEgg": "ready",
}


# --------------------------------------------------------------------------
# Fenster-Teile
# --------------------------------------------------------------------------

def dialog(w, h, title):
    im = nine("frames/frame_panel", w, h, (72, 72, 184, 184), 0.5)
    d = ImageDraw.Draw(im)
    band = Image.new("RGBA", (w - 36, 40))
    bd = ImageDraw.Draw(band)
    for yy in range(40):
        t = yy / 39
        c = tuple(int((214, 128, 24)[k] * (1 - 0.25 * t)) for k in range(3))
        bd.line((0, yy, w, yy), fill=c + (255,))
    m = Image.new("L", band.size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, band.width - 1, 39), radius=12, fill=255)
    band.putalpha(m)
    im.alpha_composite(band, (18, 15))
    d.rounded_rectangle((18, 15, w - 18, 55), radius=12, outline=OUTLINE, width=2)
    hl = Image.new("RGBA", im.size)
    ImageDraw.Draw(hl).rounded_rectangle((20, 17, w - 20, 30), radius=8, fill=(255, 255, 255, 50))
    im.alpha_composite(hl)
    text(d, (30, 35), title, 22, anchor="lm")
    d.rounded_rectangle((w - 62, 20, w - 28, 50), radius=10, fill=(255, 82, 82), outline=OUTLINE, width=3)
    text(d, (w - 45, 35), "X", 18, anchor="mm")
    return im


def seal(w, h, label):
    s = nine("frames/seal", w + 8, h + 10, (76, 44, 180, 84), 0.42)
    d = ImageDraw.Draw(s)
    text(d, (s.width / 2, s.height / 2 - 4), label, 17, anchor="mm")
    return s


def progress(d, x, y, w, h, frac, label, color=(255, 186, 52)):
    d.rounded_rectangle((x, y, x + w, y + h), radius=h // 2, fill=(38, 34, 58), outline=OUTLINE, width=3)
    if frac > 0:
        d.rounded_rectangle((x + 2, y + 2, x + 2 + int((w - 4) * frac), y + h - 2), radius=(h - 4) // 2, fill=color)
    text(d, (x + w / 2, y + h / 2), label, 13, anchor="mm")


def egg_on_pedestal(dst, egg_id, h, x, y):
    ped = img("frames/pedestal").resize((int(h * 1.05), int(h * 1.05 * 160 / 256)), Image.LANCZOS)
    dst.alpha_composite(ped, (int(x + h * 0.4 - ped.width / 2), int(y + h * (0.885 - 0.2))))
    e = egg_image(egg_id, h)
    dst.alpha_composite(e, (int(x + h * 0.4 - h / 2), int(y)))


def info_card(egg_id, state, frac, drops):
    w, h = 270, 176 + 18 * len(drops) + 18
    card = nine("frames/frame_card", w, h, (64, 64, 192, 192), 0.45)
    d = ImageDraw.Draw(card)
    egg_on_pedestal(card, egg_id, 96, 18, 16)
    text(d, (112, 30), NAMES[egg_id], 20, anchor="lm")
    path = PATH_OF[egg_id]
    d.rounded_rectangle((112, 50, 222, 70), radius=10, fill=PATH_COLOR[path], outline=OUTLINE, width=2)
    text(d, (167, 60), path, 13, anchor="mm", stroke=1)
    text(d, (112, 85), state, 14, (255, 186, 52), anchor="lm", stroke=1)
    progress(d, 16, 128, w - 32, 22, frac, "Fortschritt %d %%" % round(frac * 100))
    text(d, (18, 166), "WAS RAUSKOMMT", 13, (255, 186, 52), anchor="lm", stroke=1)
    yy = 176
    for pct, name, col in drops:
        d.text((18, yy), "%s  •  %s" % (pct, name), font=font(13), fill=col)
        yy += 18
    return card


PATH_OF = {"BasicEgg": "Stamm", "SugarEgg": "Stamm", "GoldenEgg": "Gold", "PlatinumEgg": "Gold", "SunEgg": "Gold",
           "ZenithEgg": "Gold", "CrystalEgg": "Kristall", "PrismEgg": "Kristall", "AuroraEgg": "Kristall",
           "MistEgg": "Void", "VoidEgg": "Void", "ShadowEgg": "Void", "AbyssEgg": "Void", "CometEgg": "Kosmos",
           "NovaEgg": "Kosmos", "GalaxyEgg": "Kosmos", "AscensionEgg": "Ascension",
           "TranscendenceEgg": "Ascension", "EternityEgg": "Ascension", "OmegaEgg": "Ascension"}


def zoom_buttons(d, x, y):
    for i, s in enumerate(["+", "−", "↺"]):
        bx = x + i * 44
        d.rounded_rectangle((bx, y, bx + 38, y + 38), radius=12, fill=(255, 186, 52), outline=OUTLINE, width=3)
        d.text((bx + 19, y + 19), s, font=font(20), fill=OUTLINE, anchor="mm")


# --------------------------------------------------------------------------
# Szenen
# --------------------------------------------------------------------------

def scene_tree_pc(L):
    """PC 1600×900: Baum (gemischte Zustaende) + Detail rechts + Hover-Karte."""
    W, H = 1600, 900
    screen = Image.new("RGBA", (W, H), (110, 150, 90, 255))
    dw, dh = int(W * 0.94), int(H * 0.9)
    dw, dh = min(dw, 1280), min(dh, 780)
    dlg = dialog(dw, dh, "Ei-Baum  —  Blaupausen: 1")
    body = (22, 62, dw - 44, dh - 82)
    vpw = body[2] - 290 - 10
    tree = draw_tree(L, MIXED, selected="GoldenEgg", glow_t=0.55)
    z = 0.72
    tz = tree.resize((int(tree.width * z), int(tree.height * z)), Image.LANCZOS)
    ox = int(tz.width / 2 - vpw / 2 + 40)
    oy = tz.height - body[3]
    view = tz.crop((ox, oy, ox + vpw, oy + body[3]))
    m = Image.new("L", view.size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, vpw - 1, body[3] - 1), radius=12, fill=255)
    view.putalpha(m)
    dlg.alpha_composite(view, (body[0], body[1]))
    d = ImageDraw.Draw(dlg)
    zoom_buttons(d, body[0] + 10, body[1] + body[3] - 48)
    # Detail
    det = nine("frames/frame_card", 290, body[3], (64, 64, 192, 192), 0.45)
    dd = ImageDraw.Draw(det)
    egg_on_pedestal(det, "SunEgg", 76, 24, 14)
    text(dd, (104, 30), "Sonnen-Ei", 22, (255, 196, 110), anchor="lm")
    dd.rounded_rectangle((104, 52, 214, 72), radius=10, fill=PATH_COLOR["Gold"], outline=OUTLINE, width=2)
    text(dd, (159, 62), "Gold", 13, anchor="mm", stroke=1)
    text(dd, (104, 88), "Freischaltbar", 15, (255, 186, 52), anchor="lm", stroke=1)
    dd.text((18, 122), "Pfad Gold — Das stärkste Pet\nØ Rarity 5,47", font=font(13), fill=(255, 244, 220))
    progress(dd, 16, 162, 258, 22, 0.58, "Fortschritt 58 %")
    text(dd, (18, 198), "NOCH NÖTIG", 13, (255, 186, 52), anchor="lm", stroke=1)
    progress(dd, 16, 210, 258, 24, 0.72, "Platin-Ei öffnen: 18/25", (120, 190, 255))
    progress(dd, 16, 240, 258, 24, 1.0, "Legendary im Index: 2/2", (76, 217, 100))
    progress(dd, 16, 270, 258, 24, 0.0, "Rebirth: 2/3", (120, 190, 255))
    text(dd, (18, 312), "Im Lager: 3", 17, (76, 217, 100), anchor="lm")
    det.alpha_composite(seal(258, 34, "Öffnen"), (12, 326))
    text(dd, (18, 390), "WAS RAUSKOMMT", 13, (255, 186, 52), anchor="lm", stroke=1)
    for i, (p, n, c) in enumerate([("60%", "Honigtatze", (255, 176, 32)), ("33%", "???", (168, 85, 247)), ("7,0%", "???", (255, 70, 110))]):
        dd.text((18, 404 + i * 20), "%s  •  %s" % (p, n), font=font(13), fill=c)
    dlg.alpha_composite(det, (body[0] + body[2] - 290, body[1]))
    # Hover-Karte am Goldenen Ei
    card = info_card("CrystalEgg", "Freischaltbar", 0.4, [("55%", "???", (168, 85, 247)), ("40%", "Glitzerbär", (255, 176, 32)), ("5,0%", "???", (255, 70, 110))])
    dlg.alpha_composite(card, (420, 120))
    screen.alpha_composite(dlg, ((W - dw) // 2, (H - dh) // 2))
    return screen


def scene_states(L):
    """Ein Knoten in allen drei Zustaenden + Ast."""
    tiles = []
    for st, title in (("locked", "Gesperrt"), ("ready", "Freischaltbar"), ("open", "Freigeschaltet")):
        states = dict(MIXED)
        states["PlatinumEgg"] = st
        tree = draw_tree(L, states, glow_t=0.62)
        x, y = L["nodes"]["PlatinumEgg"]
        crop = tree.crop((x - 190, y - 170, x + 210, y + 110)).resize((600, 420), Image.LANCZOS)
        d = ImageDraw.Draw(crop)
        text(d, (300, 26), title, 28, anchor="mm")
        tiles.append(crop)
    out = Image.new("RGBA", (1830, 420), (40, 26, 18, 255))
    for i, t in enumerate(tiles):
        out.alpha_composite(t, (i * 615, 0))
    return out


def scene_unlock(L):
    """Freischalt-Animation als Bildfolge (Sonnen-Ei)."""
    states = dict(MIXED)
    states["SunEgg"] = "ready"
    chain = ["SugarEgg", "GoldenEgg", "PlatinumEgg", "SunEgg"]
    offs, total = {}, 0
    for e in L["edges"]:
        pass
    by_to = {e["to"]: e for e in L["edges"]}
    for eid in chain:
        e = by_to[eid]
        offs[eid] = total
        pts = e["pts"]
        total += sum(math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1]) for i in range(len(pts) - 1))
    frames = []
    labels = ["1 Lichtwelle im Stamm", "2 Welle am Ast", "3 Kelch blüht auf", "4 Sprung + Funkenring"]
    cfgs = [
        (dict(states), {"edges": offs, "head": total * 0.15}, None),
        (dict(states), {"edges": offs, "head": total * 0.8}, None),
        (dict(states, SunEgg="open"), None, {"egg": "SunEgg", "cup": 0.75, "lift": 30}),
        (dict(states, SunEgg="open"), None, {"egg": "SunEgg", "cup": 1.0, "lift": 0, "sparks": 0.55}),
    ]
    for (st, wave, bloom), lab in zip(cfgs, labels):
        tree = draw_tree(L, st, wave=wave, bloom=bloom, glow_t=0.3)
        crop = tree.crop((60, 230, 880, 1100)).resize((450, 477), Image.LANCZOS)
        d = ImageDraw.Draw(crop)
        text(d, (225, 22), lab, 20, anchor="mm")
        frames.append(crop)
    out = Image.new("RGBA", (1860, 477), (40, 26, 18, 255))
    for i, f in enumerate(frames):
        out.alpha_composite(f, (i * 470, 0))
    return out


def scene_hatch():
    W, H = 1280, 720
    screen = Image.new("RGBA", (W, H), (110, 150, 90, 255))
    dw, dh = 560, 600
    dlg = dialog(dw, dh, "Eier")
    d = ImageDraw.Draw(dlg)
    d.rounded_rectangle((dw - 160, 22, dw - 68, 48), radius=10, fill=(178, 148, 255), outline=OUTLINE, width=3)
    text(d, (dw - 114, 35), "Ei-Baum", 15, OUTLINE, anchor="mm", stroke=0)
    rows = [("BasicEgg", 12, "Ein ganz normales Ei."), ("SugarEgg", 5, "Süß und klebrig."),
            ("GoldenEgg", 2, "Glänzt im Sonnenlicht."), ("VoidEgg", 1, "Flüstert im Dunkeln."),
            ("GalaxyEgg", 1, "Voller Sterne.")]
    y = 64
    for egg_id, n, desc in rows:
        card = nine("frames/frame_card", dw - 52, 92, (64, 64, 192, 192), 0.4)
        cd = ImageDraw.Draw(card)
        if TIERS.get(egg_id, 1) >= 9:
            rays = tint(img("fx/ring_rays"), (220, 200, 255)).resize((110, 110), Image.LANCZOS)
            card.alpha_composite(fade(rays, 0.6), (-8, -10))
        egg_on_pedestal(card, egg_id, 58, 16, 7)
        text(cd, (76, 22), NAMES[egg_id], 19, anchor="lm")
        cd.text((76, 40), desc, font=font(13), fill=(255, 244, 220))
        text(cd, (card.width - 20, 22), "x%d" % n, 19, (255, 186, 52), anchor="rm")
        card.alpha_composite(seal(120, 36, "Öffnen"), (card.width - 142, 37))
        dlg.alpha_composite(card, (22, y))
        y += 98
    screen.alpha_composite(dlg, ((W - dw) // 2, (H - dh) // 2))
    # MenuBar-Kachel
    tile = Image.new("RGBA", (54, 54))
    td = ImageDraw.Draw(tile)
    for yy in range(54):
        t = yy / 53
        c = tuple(int((255, 244, 220)[k] * (1 - t) + (242, 176, 48)[k] * t) for k in range(3))
        td.line((0, yy, 54, yy), fill=c + (255,))
    m = Image.new("L", (54, 54), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, 53, 53), radius=12, fill=255)
    tile.putalpha(m)
    tile.alpha_composite(nine("frames/frame_tile", 54, 54, (76, 76, 180, 180), 0.3))
    egg_on_pedestal(tile, "BasicEgg", 38, 27 - 38 * 0.4, 2)
    big = tile.resize((108, 108), Image.LANCZOS)
    screen.alpha_composite(big, (W - 140, H // 2 - 120))
    sd = ImageDraw.Draw(screen)
    text(sd, (W - 86, H // 2 - 2), "Eier", 22, anchor="mm")
    text(sd, (W - 86, H // 2 + 24), "(MenuBar, 2×)", 13, anchor="mm", stroke=1)
    return screen


def scene_phone(L):
    """Handy quer 844×390: Baum voll, Detail als Karte (nach Antippen)."""
    W, H = 844, 390
    screen = Image.new("RGBA", (W, H), (110, 150, 90, 255))
    dw, dh = int(W * 0.94), int(H * 0.9)
    dlg = dialog(dw, dh, "Ei-Baum")
    body = (22, 62, dw - 44, dh - 82)
    tree = draw_tree(L, MIXED, selected="MistEgg", glow_t=0.5)
    z = 0.55
    tz = tree.resize((int(tree.width * z), int(tree.height * z)), Image.LANCZOS)
    ox = int(tz.width / 2 - body[2] / 2 + 60)
    oy = int(tz.height - body[3] - 60)
    view = tz.crop((ox, oy, ox + body[2], oy + body[3]))
    m = Image.new("L", view.size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, body[2] - 1, body[3] - 1), radius=12, fill=255)
    view.putalpha(m)
    dlg.alpha_composite(view, (body[0], body[1]))
    d = ImageDraw.Draw(dlg)
    zoom_buttons(d, body[0] + 10, body[1] + body[3] - 48)
    det_w = min(290, int(dw * 0.62))
    det = nine("frames/frame_card", det_w, body[3], (64, 64, 192, 192), 0.45)
    dd = ImageDraw.Draw(det)
    egg_on_pedestal(det, "MistEgg", 80, 16, 12)
    text(dd, (96, 28), "Nebel-Ei", 20, (220, 222, 240), anchor="lm")
    dd.rounded_rectangle((96, 46, 186, 64), radius=9, fill=PATH_COLOR["Void"], outline=OUTLINE, width=2)
    text(dd, (141, 55), "Void", 12, anchor="mm", stroke=1)
    text(dd, (96, 78), "Freigeschaltet", 14, (76, 217, 100), anchor="lm", stroke=1)
    dd.rounded_rectangle((det_w - 40, 10, det_w - 10, 38), radius=9, fill=(255, 82, 82), outline=OUTLINE, width=3)
    text(dd, (det_w - 25, 24), "X", 15, anchor="mm")
    text(dd, (18, 120), "Im Lager: 4", 16, (76, 217, 100), anchor="lm")
    det.alpha_composite(seal(det_w - 36, 34, "Öffnen"), (14, 134))
    text(dd, (18, 196), "WAS RAUSKOMMT", 12, (255, 186, 52), anchor="lm", stroke=1)
    dd.text((18, 208), "65%  •  ???\n35%  •  Nebelbär", font=font(12), fill=(168, 85, 247))
    dlg.alpha_composite(det, (body[0] + body[2] - det_w, body[1]))
    screen.alpha_composite(dlg, ((W - dw) // 2, (H - dh) // 2))
    return screen


def main():
    os.makedirs(OUT, exist_ok=True)
    L = read_layout()
    jobs = {
        "1_eibaum_pc.png": lambda: scene_tree_pc(L),
        "2_knoten_drei_zustaende.png": lambda: scene_states(L),
        "3_freischalt_animation.png": lambda: scene_unlock(L),
        "4_ei_fenster_und_kachel.png": scene_hatch,
        "5_handy_844x390.png": lambda: scene_phone(L),
        "6_ganzer_baum.png": lambda: draw_tree(L, MIXED, glow_t=0.5).resize((1125, 832), Image.LANCZOS),
    }
    only = sys.argv[1:]
    for name, fn in jobs.items():
        if only and not any(o in name for o in only):
            continue
        fn().convert("RGB").save(os.path.join(OUT, name))
        print("  →", os.path.relpath(os.path.join(OUT, name), ROOT))


if __name__ == "__main__":
    main()
