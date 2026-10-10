"""
render_eggs.py — zeichnet jedes Ei aus EggConfig als 512-px-PNG (Blender).

    python tools/art/render_eggs.py            # alle Eier
    python tools/art/render_eggs.py GoldenEgg  # nur dieses (zum Ausprobieren)

Ausgabe: assets/ui/eggs/<EggId>.png (mit Bodenschatten) und
assets/ui/eggs/egg_mask.png (weisse Silhouette ohne Rand/Schatten — fuer
Aufblitzen und Schimmer im UI; alle Eier teilen dieselbe Form).

Form: EINE durchgehende Eiform (Kugel, oben schmaler, unten voll, keine
Taille), leicht nach rechts geneigt. Muster je Pfad wie in
Modules/EggLook (Stamm Punkte, Gold Guertel, Kristall Facetten-Streifen,
Void leuchtende Tupfen, Kosmos/Ascension/Event Funken und Sterne).
Farben und Pfade liest das Skript direkt aus Config/EggConfig.luau, damit
Bild und Spiel nicht auseinanderlaufen.
"""

import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bl  # noqa: E402
from mathutils import Vector  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SIZE = 512
HALF_H = 1.28      # halbe Eihoehe
TAPER = 0.17       # oben schmaler, unten voller (keine Taille: linear)
TILT = 9.0         # Grad, Spitze leicht nach rechts
OUTLINE_W = 0.07   # ~11 px bei 512


def read_eggs():
    text = open(os.path.join(ROOT, "src/shared/Config/EggConfig.luau"), encoding="utf-8").read()
    eggs = []
    pat = re.compile(r'id = "(\w+)".*?path = "(\w+)".*?tier = (\d+)[^}]*?color = Color3\.fromRGB\((\d+),\s*(\d+),\s*(\d+)\)')
    for m in pat.finditer(text):
        eggs.append({
            "id": m.group(1), "path": m.group(2), "tier": int(m.group(3)),
            "color": (int(m.group(4)), int(m.group(5)), int(m.group(6))),
        })
    return eggs


# --- EggLook nachgebaut (gleiche Regeln wie Modules/EggLook.luau) -----------

PATH_PATTERN = {"Stamm": "spots", "Gold": "band", "Kristall": "stripes", "Void": "swirl",
                "Kosmos": "stars", "Ascension": "stars", "Event": "stars"}
PATH_ACCENT = {"Void": (190, 120, 255), "Ascension": (255, 232, 140), "Event": (255, 255, 255)}


def lum(c):
    return (c[0] * 0.299 + c[1] * 0.587 + c[2] * 0.114) / 255


def mixc(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def accent_of(base, path):
    if path in PATH_ACCENT:
        return PATH_ACCENT[path]
    if path in ("Gold", "Kristall"):
        return mixc(base, (255, 255, 255), 0.65)
    if lum(base) > 0.62:
        return mixc(base, (96, 56, 36), 0.38)
    return mixc(base, (255, 255, 255), 0.5)


def look(egg):
    base, path, tier = egg["color"], egg["path"], egg["tier"]
    return {
        "base": base,
        "accent": accent_of(base, path),
        "pattern": PATH_PATTERN.get(path, "spots"),
        "glow": tier >= 6 or path in ("Ascension", "Event"),
        "neon": path in ("Void", "Kosmos", "Ascension", "Event"),
        "tier": tier,
        "path": path,
    }


# --- Geometrie ---------------------------------------------------------------

def deform(x, y, z):
    f = 1.0 - TAPER * z
    return x * f, y * f, z * HALF_H + HALF_H


def surface(u_deg, v):
    """Punkt auf der Eioberflaeche im Objektraum. u: Grad um die Hochachse
    (0 = zur Kamera, + = rechts), v: -1 unten .. 1 oben."""
    u = math.radians(u_deg)
    r = math.sqrt(max(0.0, 1 - v * v))
    return Vector(deform(r * math.sin(u), -r * math.cos(u), v))


def make_egg():
    obj = bl.uv_sphere("Egg", 128, 96)
    for v in obj.data.vertices:
        v.co = Vector(deform(*v.co))
    obj.rotation_euler = (0, math.radians(TILT), 0)
    return obj


# --- Muster ------------------------------------------------------------------

def spot_mask(g, centers, soft=0.025):
    """Max ueber weiche Kreise (Mittelpunkt, Radius) im Objektraum."""
    m = None
    for c, r in centers:
        d = g.dist(g.obj, tuple(c))
        s = g.smooth(d, r + soft, r - soft)
        m = s if m is None else g.maxi(m, s)
    return m


def star_mask(g, centers):
    """Vierzackige Funken (Astroide) in der Bildebene (x/z) auf der Vorderseite."""
    x, y, z = g.sep(g.obj)
    front = g.smooth(y, 0.1, -0.35)
    m = None
    for c, r in centers:
        dx = g.absf(g.sub(x, c[0]))
        dz = g.absf(g.sub(z, c[2]))
        a = g.add(g.powf(g.add(dx, 0.0001), 0.5), g.powf(g.add(dz, 0.0001), 0.5))
        s = g.smooth(a, math.sqrt(r) * 1.02, math.sqrt(r) * 0.9)
        m = s if m is None else g.maxi(m, s)
    return g.mul(m, front)


def tiny_stars(g, scale, size, seed_w):
    d, col = g.voronoi(g.obj, scale, w=seed_w)
    keep = g.smooth(g.bw(col), 0.45, 0.55)
    dot = g.smooth(d, size, size * 0.4)
    return g.mul(dot, keep)


def build_material(lk):
    mat = bl.material("EggMat")
    g = bl.G(mat)
    base = bl.srgb(lk["base"])
    acc = bl.srgb(lk["accent"])
    white = (1, 1, 1, 1)
    neon_mask = None
    neon_col = acc
    col = base
    normal = None
    pattern = lk["pattern"]

    if pattern == "spots":
        spots = [
            (surface(-28, -0.25), 0.30), (surface(30, -0.55), 0.22), (surface(22, 0.30), 0.17),
            (surface(-46, 0.42), 0.12), (surface(62, 0.05), 0.15), (surface(-8, 0.72), 0.10),
            (surface(-70, -0.62), 0.14),
        ]
        m = spot_mask(g, spots)
        col = g.mix(m, base, acc)

    elif pattern == "band":
        x, y, z = g.sep(g.obj)
        zc, half = HALF_H * 0.88, 0.2
        dz = g.absf(g.sub(z, zc))
        band = g.smooth(dz, half + 0.012, half - 0.012)
        edge_line = g.mul(g.smooth(dz, half + 0.012, half - 0.012), g.smooth(dz, half - 0.07, half - 0.045))
        dark = bl.lerp(acc, (0, 0, 0), 0.0)
        deep = tuple(c * 0.42 for c in base[:3]) + (1.0,)
        col = g.mix(band, base, acc)
        col = g.mix(edge_line, col, deep)
        studs = [(surface(u, (zc - HALF_H) / HALF_H), 0.065) for u in (-48, -16, 16, 48)]
        sm = spot_mask(g, studs, 0.012)
        col = g.mix(sm, col, white)
        # Facettenhafte Kopfseite des Guertels: etwas mehr Glanz im Band
        _ = dark

    elif pattern == "stripes":
        # Facetten: grosse Voronoi-Zellen mit flachen, leicht unterschiedlichen
        # Helligkeiten — das Ei wirkt wie geschliffen.
        d, cell = g.voronoi(g.obj, 2.0, randomness=0.9)
        jitter = g.sub(g.bw(cell), 0.5)
        facet = g.add(1.0, g.mul(jitter, 0.28))
        col = g.mix(1.0, base, g.comb(facet, facet, facet), "MULTIPLY")
        edges_d, _ = g.voronoi(g.obj, 2.0, feature="DISTANCE_TO_EDGE", randomness=0.9)
        edge = g.smooth(edges_d, 0.035, 0.012)
        col = g.mix(g.mul(edge, 0.55), col, white)
        # zwei schraege Streifen
        x, y, z = g.sep(g.obj)
        s = g.add(g.mul(x, 0.62), g.mul(z, 0.78))
        st = g.maxi(g.smooth(g.absf(g.sub(s, 1.05)), 0.085, 0.06), g.smooth(g.absf(g.sub(s, 1.55)), 0.06, 0.04))
        col = g.mix(st, col, acc)

    elif pattern == "swirl":
        nz = g.noise(g.obj, 1.6, 3.0, 0.6)
        col = g.mix(g.mul(g.smooth(nz, 0.45, 0.75), 0.55), base, tuple(c * 0.45 for c in base[:3]) + (1.0,))
        dots = [
            (surface(-26, -0.28), 0.20), (surface(28, -0.58), 0.15), (surface(24, 0.30), 0.12),
            (surface(-48, 0.40), 0.09), (surface(58, 0.02), 0.10), (surface(-6, 0.70), 0.07),
        ]
        core = spot_mask(g, dots, 0.02)
        halo = spot_mask(g, [(c, r * 1.9) for c, r in dots], 0.16)
        neon_mask = g.maxi(core, g.mul(halo, 0.45))
        neon_col = g.mix(core, acc, bl.lerp(acc, (1, 1, 1), 0.55) + (1.0,))

    else:  # stars
        if lk["path"] == "Kosmos":
            nz = g.noise(g.obj, 1.3, 4.0, 0.62)
            neb = bl.lerp(base, bl.srgb((92, 72, 255)), 0.55) + (1.0,)
            col = g.mix(g.mul(g.smooth(nz, 0.42, 0.72), 0.75), base, neb)
            nz2 = g.noise(g.obj, 2.4, 3.0, 0.5, w=3.0)
            col = g.mix(g.mul(g.smooth(nz2, 0.6, 0.8), 0.45), col, bl.srgb((255, 120, 210)))
        x, y, z = g.sep(g.obj)
        if lk["path"] == "Ascension":
            # Perlmutt: weiche Pastell-Wolken (rosa, himmelblau, honig)
            p1 = g.noise(g.obj, 1.1, 2.0, 0.5, w=7.0)
            col = g.mix(g.mul(g.smooth(p1, 0.35, 0.7), 0.35), col, bl.srgb((255, 170, 230)))
            p2 = g.noise(g.obj, 1.1, 2.0, 0.5, w=11.0)
            col = g.mix(g.mul(g.smooth(p2, 0.45, 0.75), 0.3), col, bl.srgb((150, 210, 255)))
        star_col = acc if (lk["path"] in ("Ascension", "Event") or lum(lk["accent"]) >= lum(lk["base"])) else bl.lerp(base, (1, 1, 1), 0.85) + (1.0,)
        c = lambda u, v, r: (surface(u, v), r)  # noqa: E731
        big = star_mask(g, [c(-24, -0.2, 0.24), c(26, 0.32, 0.17), c(30, -0.6, 0.12), c(-40, 0.55, 0.09)])
        tiny = tiny_stars(g, 7.0, 0.055, 1.7)
        neon_mask = g.maxi(big, g.mul(tiny, 0.9))
        neon_col = star_col

    col = bl.toon(g, col, normal=normal,
                  rim=(255, 236, 190) if not lk["glow"] else bl.lerp(lk["accent"], (255, 255, 255), 0.5),
                  rim_strength=0.9)

    if neon_mask is not None:
        col = g.mix(neon_mask, col, neon_col)

    if lk["glow"]:
        # Innerer Schimmer: Mitte leuchtet in der Akzentfarbe
        facing = g.absf(g.dot(g.normal, g.incoming))
        inner = g.mul(g.powf(facing, 3.0), 0.32 if lk["tier"] < 9 else 0.45)
        glow_col = bl.lerp(acc, (1, 1, 1), 0.35) + (1.0,)
        col = g.mix(inner, col, glow_col, "SCREEN")

    g.finish(col)
    return mat


def render_egg(scene, egg, out):
    bl.clear_objects()
    lk = look(egg)
    obj = make_egg()
    obj.data.materials.append(build_material(lk))
    bl.add_hull(obj, OUTLINE_W).rotation_euler = obj.rotation_euler
    bl.soft_shadow("Shadow", 1.75, 0.38, 0.06, alpha=0.5, x=0.05)
    bl.render(scene, os.path.join(out, egg["id"] + ".png"))


def render_mask(scene, out):
    bl.clear_objects()
    obj = make_egg()
    obj.data.materials.append(bl.flat_material("White", (255, 255, 255)))
    bl.render(scene, os.path.join(out, "egg_mask.png"))


def main():
    only = set(bl.args())
    eggs = read_eggs()
    out = bl.out_dir("eggs")
    scene = bl.reset()
    bl.camera(scene, SIZE, SIZE, 3.3, z=1.27)
    for egg in eggs:
        if only and egg["id"] not in only:
            continue
        render_egg(scene, egg, out)
    if not only or "mask" in only:
        render_mask(scene, out)


if __name__ == "__main__":
    main()
