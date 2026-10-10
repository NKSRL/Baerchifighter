"""
render_ui.py — zeichnet die Texturen fuer Ei-Baum, Ei-Fenster und MenuBar
in Blender (bpy, Blender 5.x).

    python tools/art/render_ui.py               # alles
    python tools/art/render_ui.py trunk cups    # nur einzelne Gruppen

Gruppen und Ausgabe (assets/ui/...):
  trunk     tree/trunk.png               Stamm mit Rinde, Wurzeln, Astgabel
  branches  tree/branch_<pfad>.png       Ast-Texturen (horizontal kachelbar)
            tree/branch_glow.png         Lichtstreifen fuer Honiglicht/Welle
  cups      tree/cup_<zustand>_back/front.png   Kelche: locked/ready/open
  lock      tree/lock.png                kleines Schloss
  fx        fx/ring_rays.png, fx/ring_soft.png, fx/sparkle.png,
            fx/pollen.png, fx/honeylight.png
  bg        tree/tree_bg.png             dunkler, warmer Hintergrund
  frames    frames/frame_panel.png, frame_card.png, frame_tile.png,
            frames/seal.png              (9-Slice, SliceCenter in Icons.luau)
  pedestal  frames/pedestal.png          Sockel unter den Eiern

Wichtige Masse fuer den Luau-Code stehen in src/client/UI/Icons.luau
(SLICES) und src/client/UI/EggTreeLayout.luau (Kelch/Ei-Ausrichtung).
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bl  # noqa: E402
import bmesh  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector, Matrix  # noqa: E402

# Palette (Theme.luau)
HONEY = (255, 186, 52)
HONEY_DEEP = (214, 128, 24)
CREAM = (255, 244, 220)
FOREST = (36, 74, 50)
WALNUT = (92, 58, 36)
WALNUT_DEEP = (52, 32, 22)
OUTLINE = bl.OUTLINE


# --------------------------------------------------------------------------
# Hilfen
# --------------------------------------------------------------------------

def tilted_camera(scene, w, h, ortho, tilt_deg, target_z=0.0):
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = ortho
    cam = bpy.data.objects.new("Cam", cam_data)
    t = math.radians(tilt_deg)
    cam.location = (0, -20 * math.cos(t), target_z + 20 * math.sin(t))
    cam.rotation_euler = (math.radians(90) - t, 0, 0)
    scene.collection.objects.link(cam)
    scene.camera = cam
    scene.render.resolution_x = w
    scene.render.resolution_y = h
    return cam


def fresh(w, h, ortho, z=0.0, tilt=None):
    scene = bl.reset()
    if tilt is None:
        bl.camera(scene, w, h, ortho, z=z)
    else:
        tilted_camera(scene, w, h, ortho, tilt, z)
    return scene


def toon_mat(name, color, **kw):
    mat = bl.material(name)
    g = bl.G(mat)
    base = bl.srgb(color) if isinstance(color[0], int) else color
    g.finish(bl.toon(g, base, **kw))
    return mat


def ellipsoid(name, sx, sy, sz, seg=48, rings=32, pointy=0.0):
    obj = bl.uv_sphere(name, seg, rings)
    for v in obj.data.vertices:
        x, y, z = v.co
        f = 1.0 - pointy * max(0.0, z)  # Spitze oben
        v.co = Vector((x * sx * f, y * sy * f, z * sz))
    return obj


def apply_transform(obj):
    # matrix_world ist erst nach einem Depsgraph-Update aktuell
    bpy.context.view_layer.update()
    mw = obj.matrix_world.copy()
    obj.data.transform(mw)
    obj.matrix_world = Matrix.Identity(4)


def with_hull(obj, t=0.05):
    apply_transform(obj)
    return bl.add_hull(obj, t)


def plane_px(w, h):
    """Flaeche w×h Einheiten = Pixel; Objektkoordinaten in Pixeln, Mitte 0."""
    return bl.plane("Card", w, h)


def rr(g, x, z, hw, hh, r):
    """Abstand zu einem abgerundeten Rechteck (negativ = innen) und die
    Aussen-Normale (nx, nz) des naechsten Randpunkts."""
    qx = g.sub(g.absf(x), hw - r)
    qz = g.sub(g.absf(z), hh - r)
    outside = g.math("SQRT", g.add(g.powf(g.maxi(qx, 0.0), 2.0), g.powf(g.maxi(qz, 0.0), 2.0)))
    inside = g.mini(g.maxi(qx, qz), 0.0)
    d = g.sub(g.add(outside, inside), r)
    # Normale: Richtung vom inneren Kernrechteck zum Punkt
    cx = g.mini(g.maxi(x, -(hw - r)), hw - r)
    cz = g.mini(g.maxi(z, -(hh - r)), hh - r)
    vx = g.sub(x, cx)
    vz = g.sub(z, cz)
    ln = g.add(g.math("SQRT", g.add(g.mul(vx, vx), g.mul(vz, vz))), 0.0001)
    # innerer Kern (v = 0): Normale aus der naechsten Kante
    return d, g.math("DIVIDE", vx, ln), g.math("DIVIDE", vz, ln)


def band(g, d, a, b, soft=0.8):
    """1 fuer a >= d >= b (a > b, beides <= 0), weiche Kanten."""
    return g.mul(g.smooth(d, a + soft, a - soft), g.smooth(d, b - soft, b + soft))


def bevel(g, nx, nz, t):
    """Helligkeit einer gewoelbten Leiste: t 0 = aussen, 1 = innen."""
    lit = g.add(g.mul(nx, -0.62), g.mul(nz, 0.78))
    return g.mul(lit, g.sub(0.5, t))


# --------------------------------------------------------------------------
# Stamm
# --------------------------------------------------------------------------

def bark_material(name, base=WALNUT, dark=WALNUT_DEEP, light=(150, 104, 64), along="z"):
    mat = bl.material(name)
    g = bl.G(mat)
    x, y, z = g.sep(g.obj)
    if along == "z":
        v = g.comb(g.mul(x, 3.2), g.mul(y, 3.2), g.mul(z, 0.55))
    else:
        v = g.comb(g.mul(x, 0.55), g.mul(y, 3.2), g.mul(z, 3.2))
    n = g.noise(v, 2.2, 6.0, 0.62)
    grooves = g.smooth(n, 0.47, 0.40)
    ridges = g.smooth(n, 0.56, 0.66)
    col = g.mix(ridges, bl.srgb(base), bl.srgb(light))
    col = g.mix(grooves, col, bl.srgb(dark))
    g.finish(bl.toon(g, col, rim=(255, 210, 140), rim_strength=0.75, spec=False, sheen=0.12))
    return mat


def tube(name, path, radii, seg=40):
    """Rohr entlang Punkten `path` mit Radien `radii` (gleich lang)."""
    bm = bmesh.new()
    rings = []
    for i, p in enumerate(path):
        p = Vector(p)
        if i < len(path) - 1:
            t = (Vector(path[i + 1]) - p).normalized()
        else:
            t = (p - Vector(path[i - 1])).normalized()
        a = Vector((0, 1, 0)) if abs(t.y) < 0.9 else Vector((1, 0, 0))
        u = t.cross(a).normalized()
        w = t.cross(u).normalized()
        ring = []
        for k in range(seg):
            ang = 2 * math.pi * k / seg
            ring.append(bm.verts.new(p + (u * math.cos(ang) + w * math.sin(ang)) * radii[i]))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for k in range(seg):
            bm.faces.new((rings[i][k], rings[i][(k + 1) % seg], rings[i + 1][(k + 1) % seg], rings[i + 1][k]))
    # Deckel
    for ring, rev in ((rings[0], True), (rings[-1], False)):
        c = sum((v.co for v in ring), Vector()) / len(ring)
        cv = bm.verts.new(c)
        for k in range(seg):
            f = (ring[k], ring[(k + 1) % seg], cv)
            bm.faces.new(tuple(reversed(f)) if rev else f)
    mesh = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bl.link(obj)
    for p in mesh.polygons:
        p.use_smooth = True
    return obj


def bezier(p0, p1, p2, p3, n):
    out = []
    for i in range(n + 1):
        t = i / n
        a = (1 - t) ** 3
        b = 3 * (1 - t) ** 2 * t
        c = 3 * (1 - t) * t * t
        d = t ** 3
        out.append(tuple(a * p0[k] + b * p1[k] + c * p2[k] + d * p3[k] for k in range(3)))
    return out


def render_trunk(out):
    # 512 × 1024; 1 Einheit = 100 px → 5.12 × 10.24
    scene = fresh(512, 1024, 10.24, z=5.12)
    bark = bark_material("Bark")
    pieces = []
    # Hauptstamm: unten breit, leicht geschwungen, oben Gabel
    path = bezier((0, 0, 0.35), (0.12, 0, 3.0), (-0.2, 0, 5.6), (0.0, 0, 8.4), 24)
    radii = [1.3 - 0.62 * (i / 24) ** 0.7 for i in range(25)]
    pieces.append(tube("Trunk", path, radii))
    # Wurzeln
    for sx, lift, ln in ((-1, 0.0, 1.9), (1, 0.05, 2.0), (-0.45, 0.0, 1.2), (0.55, 0.0, 1.25)):
        rp = bezier((0, 0.1, 1.2), (sx * 0.6, 0, 0.6), (sx * ln * 0.8, -0.1, 0.25 + lift), (sx * ln, -0.15 if abs(sx) < 1 else 0.1, 0.18 + lift), 12)
        rr_ = [0.75 - 0.6 * (i / 12) for i in range(13)]
        pieces.append(tube("Root", rp, rr_))
    # Gabel-Stummel oben (dort wachsen die UI-Aeste weiter)
    for sx in (-1, 1):
        bp = bezier((0, 0, 7.4), (sx * 0.4, 0, 8.0), (sx * 1.2, 0, 8.6), (sx * 1.9, 0, 9.1), 10)
        pieces.append(tube("Fork", bp, [0.55 - 0.15 * (i / 10) for i in range(11)]))
    for p in pieces:
        p.data.materials.append(bark)
        bl.add_hull(p, 0.07)
    # Astloch mit Honigglanz
    knot = ellipsoid("Knot", 0.22, 0.1, 0.3)
    knot.location = (0.25, -0.85, 3.4)
    knot.data.materials.append(toon_mat("KnotMat", (60, 34, 20), spec=False))
    with_hull(knot, 0.04)
    drop = ellipsoid("Drop", 0.11, 0.08, 0.16, pointy=0.6)
    drop.location = (0.27, -0.95, 3.18)
    drop.data.materials.append(toon_mat("HoneyMat", HONEY, rim=(255, 240, 200)))
    with_hull(drop, 0.03)
    bl.soft_shadow("Ground", 5.0, 0.7, 0.25, y=2.0, alpha=0.55)
    bl.render(scene, os.path.join(out, "trunk.png"))


# --------------------------------------------------------------------------
# Ast-Texturen (Bildebene, horizontal kachelbar)
# --------------------------------------------------------------------------

def strip_coords(g, w, h):
    """u 0..1 entlang (periodisch), v -1..1 quer."""
    x, _, z = g.sep(g.obj)
    u = g.math("DIVIDE", g.add(x, w / 2), w)
    v = g.math("DIVIDE", z, h / 2)
    ang = g.mul(u, 2 * math.pi)
    cu = g.math("COSINE", ang)
    su = g.math("SINE", ang)
    return u, v, cu, su


def cyl_normal(g, v):
    """Gedachte Rundung quer zum Ast: Normale aus v."""
    nz = v
    ny = g.mul(g.math("SQRT", g.maxi(g.sub(1.0, g.mul(v, v)), 0.0)), -1.0)
    return g.comb(0.0, ny, nz)


def periodic(g, cu, su, v, radius, vscale, w=0.0):
    return g.comb(g.mul(cu, radius), g.mul(su, radius), g.add(g.mul(v, vscale), w))


def render_branches(out):
    W, H = 256, 64
    for name in ("stamm", "gold", "kristall", "void", "kosmos", "ascension", "glow"):
        scene = fresh(W, H, W)
        plane = plane_px(W, H)
        mat = bl.material("Br_" + name)
        g = bl.G(mat)
        u, v, cu, su = strip_coords(g, W, H)
        n = cyl_normal(g, v)
        alpha = 1.0
        if name == "stamm":
            p = periodic(g, cu, su, v, 1.6, 2.4)
            nz = g.noise(p, 1.8, 6.0, 0.6)
            col = g.mix(g.smooth(nz, 0.56, 0.66), bl.srgb(WALNUT), bl.srgb((150, 104, 64)))
            col = g.mix(g.smooth(nz, 0.46, 0.39), col, bl.srgb(WALNUT_DEEP))
            col = bl.toon(g, col, normal=n, spec=False, sheen=0.1, rim=(255, 200, 130))
        elif name == "gold":
            p = periodic(g, cu, su, v, 3.0, 0.6)
            brushed = g.noise(p, 3.0, 4.0, 0.5)
            col = g.mix(g.mul(brushed, 0.35), bl.srgb((240, 170, 40)), bl.srgb((255, 214, 96)))
            col = bl.toon(g, col, normal=n, spec=False, sheen=0.0, shadow_tint=(0.55, 0.38, 0.22))
            # metallische Glanzlinie oben und Reflexkante unten
            hi = g.smooth(g.absf(g.sub(v, 0.42)), 0.13, 0.05)
            col = g.mix(hi, col, (1, 0.98, 0.9, 1))
            lo = g.smooth(g.absf(g.add(v, 0.62)), 0.12, 0.05)
            col = g.mix(g.mul(lo, 0.6), col, bl.srgb((255, 236, 170)))
            # kleine eingravierte Ringe
            ring_d = g.absf(g.sub(g.math("FRACT", g.mul(u, 2.0)), 0.5))
            col = g.mix(g.mul(g.smooth(ring_d, 0.03, 0.012), 0.7), col, bl.srgb((150, 90, 20)))
        elif name == "kristall":
            p = periodic(g, cu, su, v, 1.2, 1.0)
            d, cell = g.voronoi(p, 2.2, randomness=0.85)
            e, _ = g.voronoi(p, 2.2, feature="DISTANCE_TO_EDGE", randomness=0.85)
            facet = g.add(0.82, g.mul(g.bw(cell), 0.36))
            base = g.mix(1.0, bl.srgb((120, 220, 255)), g.comb(facet, facet, facet), "MULTIPLY")
            col = bl.toon(g, base, normal=n, spec=False, sheen=0.25, rim=(220, 250, 255))
            col = g.mix(g.smooth(e, 0.05, 0.015), col, (1, 1, 1, 1))
            col = g.mix(g.smooth(g.absf(g.sub(v, 0.35)), 0.12, 0.04), col, (1, 1, 1, 1))
            alpha = g.add(0.62, g.mul(g.smooth(e, 0.06, 0.015), 0.38))
        elif name == "void":
            p = periodic(g, cu, su, v, 1.4, 1.8)
            nz = g.noise(p, 1.6, 4.0, 0.6)
            col = g.mix(g.smooth(nz, 0.5, 0.65), bl.srgb((38, 24, 56)), bl.srgb((70, 44, 100)))
            col = bl.toon(g, col, normal=n, spec=False, sheen=0.06, rim=(190, 120, 255))
            e, _ = g.voronoi(p, 2.6, feature="DISTANCE_TO_EDGE", randomness=1.0)
            crack = g.smooth(e, 0.045, 0.012)
            glow = g.smooth(e, 0.14, 0.02)
            ember = g.mix(g.smooth(nz, 0.35, 0.7), bl.srgb((255, 120, 40)), bl.srgb((230, 80, 255)))
            col = g.mix(g.mul(glow, 0.45), col, ember)
            col = g.mix(crack, col, g.mix(0.45, ember, (1, 0.9, 0.7, 1)))
        elif name == "kosmos":
            p = periodic(g, cu, su, v, 1.3, 1.2)
            nz = g.noise(p, 1.5, 4.0, 0.62)
            col = g.mix(g.smooth(nz, 0.4, 0.7), bl.srgb((30, 24, 92)), bl.srgb((92, 72, 255)))
            nz2 = g.noise(p, 2.4, 3.0, 0.5, w=4.0)
            col = g.mix(g.mul(g.smooth(nz2, 0.58, 0.78), 0.55), col, bl.srgb((255, 110, 210)))
            col = bl.toon(g, col, normal=n, spec=False, sheen=0.1, rim=(170, 190, 255))
            d1, c1 = g.voronoi(g.comb(g.mul(cu, 5.0), g.mul(su, 5.0), g.mul(v, 1.6)), 1.0)
            star = g.mul(g.smooth(d1, 0.11, 0.04), g.smooth(g.bw(c1), 0.35, 0.45))
            col = g.mix(star, col, (1, 1, 1, 1))
        elif name == "ascension":
            p = periodic(g, cu, su, v, 1.2, 1.0)
            nz = g.noise(p, 1.4, 3.0, 0.5)
            col = g.mix(g.smooth(nz, 0.4, 0.7), bl.srgb((240, 226, 255)), bl.srgb((255, 214, 246)))
            col = bl.toon(g, col, normal=n, spec=False, sheen=0.2, rim=(255, 232, 140))
            d1, c1 = g.voronoi(g.comb(g.mul(cu, 4.0), g.mul(su, 4.0), g.mul(v, 1.4)), 1.0)
            fleck = g.mul(g.smooth(d1, 0.12, 0.05), g.smooth(g.bw(c1), 0.5, 0.6))
            col = g.mix(fleck, col, bl.srgb((255, 200, 70)))
        else:  # glow — weiss, weich, wird im Spiel eingefaerbt
            core = g.smooth(g.absf(v), 0.55, 0.0)
            col = g.mix(g.smooth(g.absf(v), 0.25, 0.0), bl.srgb((255, 236, 190)), (1, 1, 1, 1))
            alpha = g.powf(core, 1.4)
        g.finish(col, alpha)
        plane.data.materials.append(mat)
        bl.render(scene, os.path.join(out, "branch_" + name + ".png"))


# --------------------------------------------------------------------------
# Kelche
# --------------------------------------------------------------------------

CUP_ORTHO = 5.0      # Einheiten im 256-px-Bild (Ei-Bild: 3.3 im 512-px-Bild)
CUP_TILT = 18.0
CUP_ANCHOR_Y = 0.62  # Kelchmitte (Ursprung) von oben im Bild


def petal(name, angle_deg, open_deg, length, width, mat, z0=0.0, r0=0.45):
    p = ellipsoid(name, width, width * 0.32, length / 2, pointy=0.55)
    # Bauch zur Mitte hin woelben (Loeffelform)
    for v in p.data.vertices:
        x, y, z = v.co
        v.co = Vector((x, y - 0.18 * (x / max(width, 0.01)) ** 2 * width, z + length / 2))
    a = math.radians(angle_deg)
    p.rotation_euler = (-math.radians(open_deg), 0, 0)
    apply_transform(p)
    p.rotation_euler = (0, 0, a)
    p.location = (r0 * math.sin(a) * -1, r0 * math.cos(a), z0)
    # Winkel 0 = Blatt hinten (y+), 180 = vorne
    p.data.materials.append(mat)
    apply_transform(p)
    return p


def leaf(name, side, mat, scale=1.0, z=0.05, lift=20):
    lf = ellipsoid(name, 0.32 * scale, 0.07 * scale, 0.75 * scale, pointy=0.7)
    for v in lf.data.vertices:
        x, y, zz = v.co
        v.co = Vector((x, y + 0.1 * (zz / (0.75 * scale)) ** 2, zz + 0.75 * scale))
    lf.rotation_euler = (0, math.radians(side * (90 - lift)), 0)
    lf.location = (side * 0.8, -0.5, z)
    lf.data.materials.append(mat)
    apply_transform(lf)
    return lf


def blossom(name, x, z, y, petal_col, scale=1.0):
    objs = []
    mat = toon_mat(name + "P", petal_col, rim=(255, 255, 240))
    for k in range(5):
        a = 2 * math.pi * k / 5
        pe = ellipsoid(name + str(k), 0.13 * scale, 0.05 * scale, 0.13 * scale)
        pe.location = (x + math.cos(a) * 0.13 * scale, y, z + math.sin(a) * 0.13 * scale)
        pe.data.materials.append(mat)
        apply_transform(pe)
        objs.append(pe)
    c = ellipsoid(name + "C", 0.07 * scale, 0.06 * scale, 0.07 * scale)
    c.location = (x, y - 0.05, z)
    c.data.materials.append(toon_mat(name + "Cm", HONEY))
    apply_transform(c)
    objs.append(c)
    return objs


def render_cups(out):
    target_z = (CUP_ANCHOR_Y - 0.5) * CUP_ORTHO / math.cos(math.radians(CUP_TILT))
    states = {
        # Blattfarbe, Spitzenfarbe, Oeffnung (Grad), Blaetter, Bluetchen, Glut
        "locked": ((112, 100, 92), (88, 78, 72), 22, 0, False, False),
        "ready": ((250, 226, 176), HONEY, 36, 1, False, True),
        "open": ((255, 240, 214), (255, 196, 92), 56, 2, True, False),
    }
    for state, (pcol, tip, open_deg, leaves, blossoms, glow) in states.items():
        for layer in ("back", "front"):
            scene = fresh(256, 256, CUP_ORTHO, tilt=CUP_TILT, z=target_z)
            mat = bl.material("Petal")
            g = bl.G(mat)
            _, _, z = g.sep(g.obj)
            col = g.mix(g.smooth(z, 0.35, 1.2), bl.srgb(pcol), bl.srgb(tip))
            spec = state != "locked"
            g.finish(bl.toon(g, col, spec=spec, sheen=0.18 if spec else 0.0,
                             rim=(255, 236, 190) if spec else (150, 140, 130),
                             rim_strength=0.9 if spec else 0.4))
            objs = []
            n = 8
            for k in range(n):
                ang = 360 * k / n + 180 / n
                back = math.cos(math.radians(ang)) > 0.05
                if (layer == "back") != back:
                    continue
                length = 1.55 if state != "locked" else 1.45
                objs.append(petal("P%d" % k, ang, open_deg + (6 if back else 0), length, 0.62, mat, r0=0.62))
            if layer == "front":
                base = ellipsoid("Base", 0.85, 0.85, 0.4)
                base.location = (0, 0, -0.12)
                bcol = (96, 120, 70) if state != "locked" else (90, 84, 78)
                base.data.materials.append(toon_mat("BaseM", bcol, spec=False))
                apply_transform(base)
                objs.append(base)
                if leaves:
                    lm = toon_mat("Leaf", (78, 160, 82), rim=(220, 255, 170))
                    for side in (-1, 1):
                        objs.append(leaf("L%d" % side, side, lm, 1.0 if leaves == 1 else 1.12))
                if blossoms:
                    objs += blossom("Bl1", -1.35, 0.8, -1.2, (255, 200, 222), 1.3)
                    objs += blossom("Bl2", 1.4, 0.5, -1.2, CREAM, 1.1)
            for o in objs:
                bl.add_hull(o, 0.045)
            if layer == "back" and glow:
                halo = bl.disc("Halo", 1.0)
                halo.scale = (1.6, 1, 1.25)
                halo.location = (0, 2.0, 0.6)
                hm = bl.material("Halo")
                hg = bl.G(hm)
                r = hg.vmath("LENGTH", hg.obj)
                hg.finish(bl.srgb(HONEY), hg.mul(hg.smooth(r, 1.0, 0.0), 0.55))
                halo.data.materials.append(hm)
            bl.render(scene, os.path.join(out, "cup_%s_%s.png" % (state, layer)))


# --------------------------------------------------------------------------
# Schloss, Sockel
# --------------------------------------------------------------------------

def render_lock(out):
    scene = fresh(256, 256, 3.0, z=0.2)
    body = bpy.data.objects.new("Body", bpy.data.meshes.new("Body"))
    bl.link(body)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bm.to_mesh(body.data)
    bm.free()
    body.scale = (1.5, 0.6, 1.15)
    body.location = (0, 0, -0.35)
    bev = body.modifiers.new("Bevel", "BEVEL")
    bev.width = 0.18
    bev.segments = 6
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.modifier_apply(modifier="Bevel")
    for p in body.data.polygons:
        p.use_smooth = True
    body.data.materials.append(toon_mat("Gold", HONEY, shadow_tint=(0.62, 0.42, 0.3)))
    apply_transform(body)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.48, minor_radius=0.13, location=(0, 0.0, 0.3),
                                     rotation=(math.radians(90), 0, 0), major_segments=64, minor_segments=24)
    sh = bpy.context.active_object
    bm = bmesh.new()
    bm.from_mesh(sh.data)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.y < -0.05], context="VERTS")
    bm.to_mesh(sh.data)
    bm.free()
    for p in sh.data.polygons:
        p.use_smooth = True
    sh.data.materials.append(toon_mat("Steel", (176, 168, 190)))
    apply_transform(sh)
    for side in (-1, 1):
        leg = tube("Leg", [(side * 0.48, 0, 0.3), (side * 0.48, 0, 0.0)], [0.13, 0.13], 24)
        leg.data.materials.append(sh.data.materials[0])
        bl.add_hull(leg, 0.06)
    bl.add_hull(sh, 0.06)
    bl.add_hull(body, 0.07)
    hole = ellipsoid("Hole", 0.14, 0.05, 0.14)
    hole.location = (0, -0.33, -0.25)
    hole.data.materials.append(bl.flat_material("Dark", OUTLINE))
    apply_transform(hole)
    slot = ellipsoid("Slot", 0.06, 0.05, 0.2)
    slot.location = (0, -0.33, -0.48)
    slot.data.materials.append(bl.flat_material("Dark2", OUTLINE))
    apply_transform(slot)
    bl.render(scene, os.path.join(out, "lock.png"))


def render_pedestal(out):
    # Sockel: kurzer Baumstumpf mit Honigrand, leicht von oben gesehen
    scene = fresh(256, 160, 3.0, tilt=22, z=-0.32)
    stump = tube("Stump", [(0, 0, -0.5), (0, 0, 0.0)], [1.25, 1.12], 64)
    stump.data.materials.append(bark_material("PBark"))
    bl.add_hull(stump, 0.06)
    top = bl.uv_sphere("Top", 64, 24)
    top.scale = (1.12, 1.12, 0.08)
    top.location = (0, 0, 0.0)
    m = bl.material("Rings")
    g = bl.G(m)
    x, y, _ = g.sep(g.obj)
    r = g.math("SQRT", g.add(g.mul(x, x), g.mul(y, y)))
    rings = g.math("FRACT", g.mul(r, 4.5))
    col = g.mix(g.smooth(rings, 0.75, 0.9), bl.srgb((222, 172, 112)), bl.srgb((180, 124, 72)))
    col = g.mix(g.smooth(r, 0.86, 0.94), col, bl.srgb(HONEY))
    g.finish(bl.toon(g, col, spec=False, sheen=0.25))
    top.data.materials.append(m)
    apply_transform(top)
    bl.add_hull(top, 0.05)
    # Honigtropfen am Rand
    for x0, ln in ((-0.7, 0.32), (0.35, 0.22), (0.85, 0.16)):
        d = ellipsoid("Drip", 0.1, 0.08, ln, pointy=-0.2)
        d.location = (x0, -1.12 + abs(x0) * 0.35, -ln * 0.5)
        d.data.materials.append(toon_mat("DripM", HONEY, rim=(255, 240, 200)))
        apply_transform(d)
        bl.add_hull(d, 0.04)
    bl.render(scene, os.path.join(out, "pedestal.png"))


# --------------------------------------------------------------------------
# Effekte (2D)
# --------------------------------------------------------------------------

def render_fx(out):
    jobs = [("ring_rays", 512), ("ring_soft", 256), ("sparkle", 128), ("pollen", 64), ("honeylight", 128)]
    for name, size in jobs:
        scene = fresh(size, size, size)
        pl = plane_px(size, size)
        m = bl.material(name)
        g = bl.G(m)
        x, _, z = g.sep(g.obj)
        r = g.math("DIVIDE", g.math("SQRT", g.add(g.mul(x, x), g.mul(z, z))), size / 2)
        if name == "ring_rays":
            ang = g.math("ARCTAN2", z, x)
            rays = g.math("COSINE", g.mul(ang, 12.0))
            rays2 = g.math("COSINE", g.add(g.mul(ang, 7.0), 0.6))
            ray = g.maxi(g.smooth(rays, 0.55, 0.98), g.mul(g.smooth(rays2, 0.75, 0.99), 0.6))
            fade = g.mul(g.smooth(r, 0.98, 0.45), g.smooth(r, 0.18, 0.32))
            core = g.mul(g.smooth(r, 0.5, 0.12), 0.55)
            a = g.maxi(g.mul(ray, fade), core)
            g.finish((1, 1, 1, 1), g.mul(a, 0.95))
        elif name == "ring_soft":
            a = g.powf(g.smooth(r, 1.0, 0.0), 1.6)
            g.finish((1, 1, 1, 1), a)
        elif name == "sparkle":
            ax = g.absf(g.math("DIVIDE", x, size / 2))
            az = g.absf(g.math("DIVIDE", z, size / 2))
            star = g.add(g.powf(g.add(ax, 0.0001), 0.5), g.powf(g.add(az, 0.0001), 0.5))
            s = g.smooth(star, 0.98, 0.7)
            halo = g.mul(g.smooth(r, 0.75, 0.0), 0.45)
            g.finish((1, 1, 1, 1), g.maxi(s, halo))
        elif name == "pollen":
            core = g.smooth(r, 0.42, 0.25)
            halo = g.mul(g.powf(g.smooth(r, 1.0, 0.0), 2.0), 0.6)
            col = g.mix(core, bl.srgb((255, 220, 140)), (1, 1, 0.94, 1))
            g.finish(col, g.maxi(core, halo))
        else:  # honeylight
            core = g.smooth(r, 0.3, 0.1)
            halo = g.powf(g.smooth(r, 1.0, 0.0), 2.2)
            col = g.mix(core, bl.srgb(HONEY), bl.srgb((255, 246, 210)))
            g.finish(col, g.maxi(core, g.mul(halo, 0.85)))
        pl.data.materials.append(m)
        bl.render(scene, os.path.join(bl.out_dir("fx"), name + ".png"))


def render_bg(out):
    W, H = 1024, 768
    scene = fresh(W, H, W)
    pl = plane_px(W, H)
    m = bl.material("BG")
    g = bl.G(m)
    x, _, z = g.sep(g.obj)
    nx = g.math("DIVIDE", x, W / 2)
    nz = g.math("DIVIDE", g.add(z, H * 0.42), H / 2)   # Licht unten Mitte
    r = g.math("SQRT", g.add(g.mul(nx, nx), g.mul(g.mul(nz, 0.85), g.mul(nz, 0.85))))
    col = g.mix(g.smooth(r, 0.0, 1.5), bl.srgb((112, 70, 34)), bl.srgb((28, 20, 18)))
    # weit entfernte Laubwolken als weiche dunkle Formen
    leaves = g.noise(g.comb(g.mul(nx, 2.0), 0.0, g.mul(nz, 2.0)), 1.4, 3.0, 0.55)
    top = g.smooth(nz, 0.9, 1.7)
    col = g.mix(g.mul(g.mul(g.smooth(leaves, 0.45, 0.6), top), 0.55), col, bl.srgb((22, 40, 30)))
    # Bokeh-Lichter
    d, c = g.voronoi(g.comb(g.mul(nx, 3.0), 0.0, g.mul(nz, 3.0)), 1.0)
    bok = g.mul(g.smooth(d, 0.13, 0.07), g.smooth(g.bw(c), 0.62, 0.7))
    col = g.mix(g.mul(bok, 0.12), col, bl.srgb((255, 200, 110)))
    # Vignette
    vig = g.smooth(g.math("SQRT", g.add(g.mul(nx, nx), g.mul(g.sub(nz, 1.0), g.sub(nz, 1.0)))), 1.0, 1.9)
    col = g.mix(g.mul(vig, 0.6), col, bl.srgb((12, 8, 8)))
    g.finish(col)
    pl.data.materials.append(m)
    bl.render(scene, os.path.join(out, "tree_bg.png"))


# --------------------------------------------------------------------------
# Rahmen (9-Slice) und Siegel
# --------------------------------------------------------------------------

def frame(out, name, size, outer_r, trim, inner, fill, trim_col, corner, transparent_center=False):
    W, H = size
    scene = fresh(W, H, max(W, H))
    pl = plane_px(W, H)
    m = bl.material(name)
    g = bl.G(m)
    x, _, z = g.sep(g.obj)
    pad = 6
    d, nx, nz = rr(g, x, z, W / 2 - pad, H / 2 - pad, outer_r)
    shape = g.smooth(d, 0.8, -0.8)
    ol = 7.0
    col = bl.srgb(OUTLINE)
    # Zierleiste (gewoelbt) innerhalb des Umrisses
    t_trim = g.math("DIVIDE", g.sub(g.mul(d, -1.0), ol), trim)
    on_trim = band(g, d, -ol, -(ol + trim))
    lit = bevel(g, nx, nz, t_trim)
    tcol = g.mix(g.smooth(lit, -0.3, 0.3), bl.srgb(tuple(int(c * 0.55) for c in trim_col)), bl.srgb(trim_col))
    hi = g.mul(g.smooth(lit, 0.28, 0.38), 1.0)
    tcol = g.mix(hi, tcol, (1, 1, 1, 1))
    col = g.mix(on_trim, col, tcol)
    # duenne dunkle Linie innen, dann zweite feine Goldlinie
    inner_edge = -(ol + trim)
    col = g.mix(band(g, d, inner_edge, inner_edge - 3.0), col, bl.srgb(OUTLINE))
    if inner > 0:
        col = g.mix(band(g, d, inner_edge - 7.0, inner_edge - 7.0 - inner), col, bl.srgb(trim_col))
    # Fuellung
    in_fill = g.smooth(d, inner_edge - 3.0 + 0.8, inner_edge - 3.0 - 0.8)
    if not transparent_center:
        shade = g.smooth(d, inner_edge - 3.0, inner_edge - 26.0)
        fcol = g.mix(shade, bl.srgb(tuple(int(c * 0.6) for c in fill)), bl.srgb(fill))
        line_mask = band(g, d, inner_edge - 7.0, inner_edge - 7.0 - inner) if inner > 0 else 0.0
        col = g.mix(g.mul(in_fill, g.sub(1.0, line_mask)) if inner > 0 else in_fill, col, fcol)
        alpha = shape
    else:
        line_mask = band(g, d, inner_edge - 7.0, inner_edge - 7.0 - inner) if inner > 0 else 0.0
        keep = g.sub(1.0, in_fill)
        alpha = g.mul(shape, g.maxi(keep, line_mask) if inner > 0 else keep)
    # Ecken-Zier: Honigtropfen-Juwel in jeder Ecke
    if corner:
        ox = W / 2 - pad - outer_r * 0.62
        oz = H / 2 - pad - outer_r * 0.62
        ax = g.sub(g.absf(x), ox)
        az = g.sub(g.absf(z), oz)
        cr = g.math("SQRT", g.add(g.mul(ax, ax), g.mul(az, az)))
        gem = g.smooth(cr, corner + 0.8, corner - 0.8)
        ring = g.smooth(cr, corner + 5.0, corner + 3.5)
        gcol = g.mix(g.smooth(g.add(g.mul(ax, -0.6), g.mul(az, 0.8)), -corner, corner),
                     bl.srgb(HONEY_DEEP), bl.srgb((255, 220, 120)))
        spark = g.smooth(g.math("SQRT", g.add(g.powf(g.add(ax, corner * 0.35), 2.0), g.powf(g.sub(az, corner * 0.35), 2.0))), corner * 0.32, corner * 0.2)
        gcol = g.mix(spark, gcol, (1, 1, 1, 1))
        col = g.mix(ring, col, bl.srgb(OUTLINE))
        col = g.mix(gem, col, gcol)
        alpha = g.maxi(alpha, ring)
    g.finish(col, alpha)
    pl.data.materials.append(m)
    bl.render(scene, os.path.join(out, name + ".png"))


def render_seal(out):
    W, H = 256, 128
    scene = fresh(W, H, W)
    pl = plane_px(W, H)
    m = bl.material("Seal")
    g = bl.G(m)
    x, _, z = g.sep(g.obj)
    # Pille mit welligem Wachs-/Honigrand
    ang = g.math("ARCTAN2", z, x)
    wob = g.mul(g.math("SINE", g.mul(ang, 9.0)), 2.2)
    d, nx, nz = rr(g, x, g.add(z, 4.0), W / 2 - 10, H / 2 - 18, 44)
    d = g.add(d, wob)
    # Tropfen unten links/rechts (in den Ecken-Slices, dehnen sich nicht)
    drops = None
    for dx, ln in ((-78, 22), (84, 15)):
        ex = g.sub(x, dx)
        ez = g.math("DIVIDE", g.add(z, H / 2 - 18 - 4 + ln * 0.5 - 4), ln / 9.0)
        dd = g.sub(g.math("SQRT", g.add(g.mul(ex, ex), g.mul(ez, ez))), 9.0)
        drops = dd if drops is None else g.mini(drops, dd)
    d = g.mini(d, drops)
    shape = g.smooth(d, 0.8, -0.8)
    on_body = g.smooth(d, -6.0, -7.5)
    t = g.smooth(nz, -1.0, 1.0)
    body = g.mix(g.smooth(z, -40.0, 34.0), bl.srgb((198, 108, 14)), bl.srgb((255, 196, 64)))
    # eingepraegter Siegelrand
    emb = band(g, d, -14.0, -18.0)
    body = g.mix(g.mul(emb, 0.55), body, bl.srgb((150, 78, 10)))
    emb_hi = band(g, d, -18.0, -20.0)
    body = g.mix(g.mul(emb_hi, 0.6), body, bl.srgb((255, 232, 150)))
    # Glanz oben: weiche Bahn + scharfer weisser Punkt links
    gloss = g.mul(g.smooth(z, 6.0, 30.0), g.smooth(d, -9.0, -16.0))
    body = g.mix(g.mul(gloss, 0.45), body, (1, 0.97, 0.88, 1))
    sx = g.sub(x, -70.0)
    sz = g.math("DIVIDE", g.sub(z, 20.0), 0.55)
    spot = g.smooth(g.math("SQRT", g.add(g.mul(sx, sx), g.mul(sz, sz))), 7.0, 5.5)
    body = g.mix(spot, body, (1, 1, 1, 1))
    col = g.mix(on_body, bl.srgb(OUTLINE), body)
    _ = t
    g.finish(col, shape)
    pl.data.materials.append(m)
    bl.render(scene, os.path.join(out, "seal.png"))


def render_frames(out):
    frame(out, "frame_panel", (256, 256), 56, 16, 3, WALNUT_DEEP, HONEY, 9)
    frame(out, "frame_card", (256, 256), 48, 12, 2, (30, 58, 42), (255, 214, 120), 8)
    frame(out, "frame_tile", (256, 256), 60, 18, 0, (0, 0, 0), HONEY, 10, transparent_center=True)
    render_seal(out)


GROUPS = {
    "trunk": lambda: render_trunk(bl.out_dir("tree")),
    "branches": lambda: render_branches(bl.out_dir("tree")),
    "cups": lambda: render_cups(bl.out_dir("tree")),
    "lock": lambda: render_lock(bl.out_dir("tree")),
    "fx": lambda: render_fx(bl.out_dir("fx")),
    "bg": lambda: render_bg(bl.out_dir("tree")),
    "frames": lambda: render_frames(bl.out_dir("frames")),
    "pedestal": lambda: render_pedestal(bl.out_dir("frames")),
}


def main():
    want = bl.args() or list(GROUPS)
    for name in want:
        print("==", name)
        GROUPS[name]()


if __name__ == "__main__":
    main()
