# -*- coding: utf-8 -*-
# Einzige Zustaendigkeit: baut den Blender-Prototyp des neuen Kampf-Pits "Honig-Kolosseum"
# (Arena-Meshes, Etagen-Zaun-Vorlage, Vorschau-Szene) in der offenen .blend-Datei neu auf,
# rendert die Abnahme-Bilder und exportiert nach der Abnahme FBX + Manifest fuer Studio.
#
# Koordinaten: 1 Blender-Einheit = 1 Stud, Z oben. Ursprung = Arena-Mitte auf Hoehe der
# Kampfflaechen-Oberkante (Roblox PLATFORM_TOP_Y = 0). +Y = Steg-Tor (Richtung Weltmitte,
# along -), -Y = Raketen-Tor (along +), X = quer. Im Export wird daraus (FBX -Z vorne, Y oben):
# Blender (x, y, z) -> Roblox-Modellraum (x, z, -y).
#
# Masse kommen aus dem Studio-Stand vom 25.10. (MapConfig: PIT_RADIUS 26, PIT_BASE_RADIUS 30,
# PIT_RIM_DROP 0.35, Ufer 38 / -1.35, Etagenhoehe 2.4, Zuschauer-Ring 28.6 auf 4.05;
# WorldFXConfig.TOWER_FLIGHT: Flugfeld along -28 / quer -4.5, Radius 2.2).
# Warum das Steg-Tor KEINEN Sturz hat: die Flugbahn vom Flugfeld steigt so steil, dass jeder
# Querbalken ueber dem Feld je nach Turmhoehe durchflogen wuerde (heute schon beim alten Bogen).
#
# Aufruf in Blender (MODE = "build" | "render:<ansicht>" | "export"):
#   g = {"__name__": "scene", "MODE": "build"}; exec(open(PFAD, encoding="utf-8").read(), g)
#   Ergebnis steht danach in g["RESULT"].
import bpy, bmesh, math, os, json, time
from mathutils import Vector, Matrix

ROOT = r"C:\Users\admin\Documents\Claude Downloads\RBL"
OUT = os.path.join(ROOT, "assets", "pit")
RENDERS = os.path.join(OUT, "renders")
BLEND = os.path.join(OUT, "Pit_Kolosseum.blend")
BEAR_FBX = os.path.join(ROOT, "Export", "Bear_Braunbaer.fbx")
BEAR_HEIGHT = 3.2         # Baerchi auf dem Plot misst 3.4 hoch (Studio 25.10.), Kaempfer etwa 3.2

# ---------------------------------------------------------------- Masse (Studs)
FLOOR_R = 26.0            # MapConfig.PIT_RADIUS (Kampfflaeche, bleibt Roblox-Zylinder "FightFloor")
BASE_R = 30.0             # PIT_BASE_RADIUS (Sockel, bleibt Roblox-Insel)
RIM_Z = -0.35             # Sockel-Oberkante
SHORE_R, SHORE_Z = 38.0, -1.35
WATER_Z = -2.6
STEP_H = 2.4              # PIT_TOWER_STEP_HEIGHT
SEAT_R, SEAT_Z = 28.6, 4.05   # Zuschauer sitzen hier (ArenaLifeController), also Mauerkrone
GATE_HALF = 18.0          # halbe Torbreite in Grad; Flugfeld-Ring (Radius 2.86 bei quer -4.5) passt durch
SEG_DEG = 3.0             # Segmentwinkel der Boegen (sichtbare Low-Poly-Facetten)
GA = 90.0 - GATE_HALF     # 72: Mauer-/Tribuenenbogen enden an den Torpfeilern
ARCS = [(-GA, GA), (180.0 - GA, 180.0 + GA)]

WALL_R0, WALL_R1, WALL_TOP = 28.1, 29.1, 3.75
CAP_R0, CAP_R1 = 27.9, 29.3
TIERS = [(29.1, 31.0, 4.65), (31.0, 32.9, 5.55), (32.9, 35.5, 6.45)]
FACADE_R = 35.5
PYLON_X = SEAT_R * math.sin(math.radians(GATE_HALF))   # 8.84 quer
PYLON_Y = SEAT_R * math.cos(math.radians(GATE_HALF))   # 27.20 laengs
MEDAL_R, MEDAL_RING = 4.2, 4.7
TILE_RC, TILE_GAP, TILE_CLIP = 2.0, 0.24, 22.95

# Etagen-Zaun: AUSSERHALB des Etagen-Zylinders (R 26), sonst steckt er in der Etage darueber
STUFE_RAND = (25.5, 27.1, -0.4, 0.06)
STUFE_POST_R, STUFE_POSTS = 26.7, 32
STUFE_RAIL = (26.55, 26.85, 1.50, 1.68)
STUFE_MID = (26.63, 26.77, 0.78, 0.88)
STUFE_SEG = 72

ARENA_OBJS = ["Pit_Sandstein", "Pit_Schiefer", "Pit_Gold", "Pit_Waben", "Pit_Honig", "Pit_Wimpel"]
STUFE_OBJS = ["Pit_Stufe_Rand", "Pit_Stufe_Gold"]
FARBE = {
    "Pit_Sandstein": (238, 223, 192), "Pit_Schiefer": (48, 43, 64), "Pit_Gold": (242, 188, 64),
    "Pit_Waben": (236, 182, 82), "Pit_Honig": (255, 196, 56), "Pit_Wimpel": (215, 60, 75),
    "Pit_Stufe_Rand": (238, 223, 192), "Pit_Stufe_Gold": (242, 188, 64),
}
ROBLOX_MAT = {"Pit_Gold": "Metal", "Pit_Stufe_Gold": "Metal", "Pit_Honig": "Neon"}
TOWER_COLORS = [(196, 168, 62), (140, 108, 58), (150, 173, 95), (196, 210, 205),
                (150, 120, 150), (196, 110, 60), (120, 96, 60), (210, 196, 160)]

VIEWS = {
    "01_gesamt": dict(pos=(50, 76, 44), aim=(0, -3, 0), lens=28),
    "02_steg": dict(pos=(0, 60, 8.5), aim=(0, 0, 3.5), lens=30),
    "03_innen": dict(pos=(-15, 19, 6.5), aim=(5, -18, 4.0), lens=24),
    "04_turm": dict(pos=(48, 60, 30), aim=(0, 0, 9), lens=30, turm=True),
    "05_oben": dict(pos=(0, 0, 120), aim=(0, 0, 0), ortho=84),
}

def V(x, y, z):
    return Vector((x, y, z))

def s2l(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

def lin(rgb):
    return (s2l(rgb[0]), s2l(rgb[1]), s2l(rgb[2]), 1.0)

# ---------------------------------------------------------------- Geometrie-Helfer (bmesh)
G = {}

def bm_of(name):
    if name not in G:
        G[name] = bmesh.new()
    return G[name]

def prism_frame(bm, c, u, v, n, pts, d0, d1):
    """Prisma aus 2D-Umriss pts (gegen den Uhrzeigersinn, gesehen von +n) zwischen n*d0 und n*d1.
    u x v muss n ergeben, dann zeigen alle Flaechen nach aussen."""
    lo = [bm.verts.new(c + u * x + v * y + n * d0) for x, y in pts]
    hi = [bm.verts.new(c + u * x + v * y + n * d1) for x, y in pts]
    bm.faces.new(list(reversed(lo)))
    bm.faces.new(hi)
    k = len(pts)
    for i in range(k):
        j = (i + 1) % k
        bm.faces.new((lo[i], lo[j], hi[j], hi[i]))

def prism_z(bm, pts, z0, z1):
    prism_frame(bm, V(0, 0, 0), V(1, 0, 0), V(0, 1, 0), V(0, 0, 1), pts, z0, z1)

def box(bm, cx, cy, sx, sy, z0, z1, rot=0.0):
    a = math.radians(rot)
    u, v = V(math.cos(a), math.sin(a), 0), V(-math.sin(a), math.cos(a), 0)
    hx, hy = sx / 2, sy / 2
    prism_frame(bm, V(cx, cy, 0), u, v, V(0, 0, 1), [(-hx, -hy), (hx, -hy), (hx, hy), (-hx, hy)], z0, z1)

def ngon(r, k, rot=0.0):
    return [(r * math.cos(math.radians(rot + 360.0 * i / k)), r * math.sin(math.radians(rot + 360.0 * i / k)))
            for i in range(k)]

def hexz(bm, cx, cy, r, z0, z1, rot=30.0):
    prism_frame(bm, V(cx, cy, 0), V(1, 0, 0), V(0, 1, 0), V(0, 0, 1), ngon(r, 6, rot), z0, z1)

def hexring(bm, cx, cy, r0, r1, z0, z1, rot=30.0):
    for k in range(6):
        a0, a1 = math.radians(rot + 60 * k), math.radians(rot + 60 * (k + 1))
        prism_z(bm, [(cx + r1 * math.cos(a0), cy + r1 * math.sin(a0)), (cx + r1 * math.cos(a1), cy + r1 * math.sin(a1)),
                     (cx + r0 * math.cos(a1), cy + r0 * math.sin(a1)), (cx + r0 * math.cos(a0), cy + r0 * math.sin(a0))], z0, z1)

def cyl(bm, cx, cy, r, z0, z1, k=48):
    prism_frame(bm, V(cx, cy, 0), V(1, 0, 0), V(0, 1, 0), V(0, 0, 1), ngon(r, k), z0, z1)

def ring(bm, r0, r1, z0, z1, a0=0.0, a1=360.0, n=None):
    """Ringsektor (r0..r1, z0..z1) von a0 bis a1 Grad, voll geschlossen."""
    full = abs(a1 - a0) >= 359.999
    n = n or max(1, int(math.ceil(abs(a1 - a0) / SEG_DEG - 1e-6)))
    m = n if full else n + 1
    angs = [math.radians(a0 + (a1 - a0) * i / n) for i in range(m)]
    def mk(r, z):
        return [bm.verts.new((r * math.cos(a), r * math.sin(a), z)) for a in angs]
    ib, ob, it, ot = mk(r0, z0), mk(r1, z0), mk(r0, z1), mk(r1, z1)
    for i in range(n):
        j = (i + 1) % m
        bm.faces.new((ot[i], ot[j], it[j], it[i]))
        bm.faces.new((ib[i], ib[j], ob[j], ob[i]))
        bm.faces.new((ob[i], ob[j], ot[j], ot[i]))
        bm.faces.new((ib[j], ib[i], it[i], it[j]))
    if not full:
        bm.faces.new((ib[0], ob[0], ot[0], it[0]))
        bm.faces.new((ib[-1], it[-1], ot[-1], ob[-1]))

def radial(theta):
    a = math.radians(theta)
    return V(math.cos(a), math.sin(a), 0), V(-math.sin(a), math.cos(a), 0)

def pyramid(bm, cx, cy, s, z0, z1, rot=0.0):
    a = math.radians(rot)
    u, v = V(math.cos(a), math.sin(a), 0), V(-math.sin(a), math.cos(a), 0)
    h = s / 2
    b = [bm.verts.new(V(cx, cy, z0) + u * x + v * y) for x, y in [(-h, -h), (h, -h), (h, h), (-h, h)]]
    t = bm.verts.new(V(cx, cy, z1))
    bm.faces.new(list(reversed(b)))
    for i in range(4):
        bm.faces.new((b[i], b[(i + 1) % 4], t))

def vhex(bm, c, n, r, d0, d1):
    """Senkrechtes Sechseck (Spitze oben), Flaechennormale n (waagerecht)."""
    up = V(0, 0, 1)
    prism_frame(bm, c, up.cross(n), up, n, ngon(r, 6, 90.0), d0, d1)

def pennant(bm, top, dirv, length, height, thick=0.1):
    n = dirv.cross(V(0, 0, 1))
    prism_frame(bm, top, dirv, V(0, 0, 1), n, [(0, 0), (0, -height), (length, -height / 2)], -thick / 2, thick / 2)

def banner(bm, c, n, w, h, notch):
    """Haengendes Banner mit Schwalbenschwanz; c = Mitte der Unterkante, n = Blickrichtung."""
    up = V(0, 0, 1)
    pts = [(-w / 2, 0), (0, notch), (w / 2, 0), (w / 2, h), (-w / 2, h)]
    prism_frame(bm, c, up.cross(n), up, n, pts, -0.02, 0.08)

def arch_pts(w, h, k=6):
    pts = [(-w / 2, 0.0), (w / 2, 0.0)]
    for i in range(k + 1):
        a = math.pi * i / k
        pts.append((w / 2 * math.cos(a), h + w / 2 * math.sin(a)))
    return pts

def clip_halfplane(poly, nx, ny, d):
    out, k = [], len(poly)
    for i in range(k):
        p, q = poly[i], poly[(i + 1) % k]
        dp, dq = p[0] * nx + p[1] * ny - d, q[0] * nx + q[1] * ny - d
        if dp <= 0:
            out.append(p)
        if (dp < 0 < dq) or (dq < 0 < dp):
            t = dp / (dp - dq)
            out.append((p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t))
    return out

def area(poly):
    return 0.5 * sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1]
                     for i in range(len(poly)))

# ---------------------------------------------------------------- Arena
def build_floor():
    """Waben-Belag (auf dem Roblox-Zylinder FightFloor, Oberkante 0), Medaillon, Ringe, Honigrinne.
    Abstaende der sichtbaren Oberseiten >= 0.05 (Worldbuilding M07/W02)."""
    W, S, Gd, H = bm_of("Pit_Waben"), bm_of("Pit_Schiefer"), bm_of("Pit_Gold"), bm_of("Pit_Honig")
    rt = TILE_RC - TILE_GAP / math.sqrt(3)
    tiles = 0
    for q in range(-14, 15):
        for r in range(-10, 11):
            x, y = TILE_RC * math.sqrt(3) * (q + r / 2.0), TILE_RC * 1.5 * r
            d = math.hypot(x, y)
            if d - rt > TILE_CLIP or d + rt < MEDAL_RING * math.cos(math.radians(30)):
                continue
            poly = [(x + px, y + py) for px, py in ngon(rt, 6, 30.0)]
            if d + rt > TILE_CLIP:
                for i in range(128):
                    a = 2 * math.pi * i / 128
                    poly = clip_halfplane(poly, math.cos(a), math.sin(a), TILE_CLIP)
                    if len(poly) < 3:
                        break
            if len(poly) < 3 or area(poly) < 0.15:
                continue
            prism_z(W, poly, -0.05, 0.05)
            tiles += 1
    # Medaillon in der Mitte (liegt hoeher, ueberdeckt angeschnittene Waben sauber)
    hexz(S, 0, 0, MEDAL_R, -0.05, 0.12)
    hexring(Gd, 0, 0, MEDAL_R, MEDAL_RING, -0.05, 0.16)
    hexz(Gd, 0, 0, 1.5, 0.05, 0.20)
    for k in range(6):
        a = math.radians(30 + 60 * k)
        hexz(W, 2.65 * math.cos(a), 2.65 * math.sin(a), 0.75, 0.05, 0.17)
    ring(Gd, 22.8, 23.3, -0.05, 0.10)          # Goldring um den Belag
    ring(S, 23.3, 25.9, -0.05, 0.05)           # dunkles Band am Rand der Kampfflaeche
    ring(H, 25.7, 26.6, -0.40, -0.20)          # Honigrinne: einziges Neon der Arena
    return tiles

def build_wall():
    S, Sd, Gd, W = bm_of("Pit_Schiefer"), bm_of("Pit_Sandstein"), bm_of("Pit_Gold"), bm_of("Pit_Waben")
    medals = 0
    for a0, a1 in ARCS:
        ring(S, WALL_R0, WALL_R1, -0.5, WALL_TOP, a0, a1)
        ring(Sd, CAP_R0, CAP_R1, WALL_TOP, SEAT_Z, a0, a1)        # Krone = Sitzhoehe der Zuschauer
        ring(Gd, WALL_R0 - 0.12, WALL_R0, 3.3, 3.5, a0, a1)       # Goldband innen unter der Krone
        th = a0 + 6.0
        while th < a1 - 1.0:
            out, _ = radial(th)
            c = out * WALL_R0 + V(0, 0, 1.9)
            vhex(Gd, c, -out, 0.8, -0.02, 0.12)
            vhex(W, c, -out, 0.45, 0.0, 0.17)
            medals += 1
            th += 12.0
    return medals

def build_stands():
    Sd, S, Gd = bm_of("Pit_Sandstein"), bm_of("Pit_Schiefer"), bm_of("Pit_Gold")
    for a0, a1 in ARCS:
        for r0, r1, top in TIERS:
            ring(Sd, r0, r1, -1.6, top, a0, a1)
        ring(S, 34.8, FACADE_R, 6.45, 7.35, a0, a1)               # Bruestung
        ring(Gd, 34.7, FACADE_R + 0.1, 7.35, 7.55, a0, a1)        # Goldkante
        # Pilaster und Bogenfenster auf der Aussenfassade
        th = a0 + 6.0
        while th < a1 - 1.0:
            out, _ = radial(th)
            p = out * (FACADE_R + 0.2)
            box(S, p.x, p.y, 0.5, 1.1, -1.6, 6.45, th)
            th += 12.0
        th = a0 + 12.0
        while th < a1 - 1.0:
            if abs(((th + 180.0) % 180.0)) > 1.0:                 # 0 und 180 Grad: dort steht ein Turm
                out, _ = radial(th)
                c = out * FACADE_R + V(0, 0, 0.2)
                up = V(0, 0, 1)
                prism_frame(S, c, up.cross(out), up, out, arch_pts(1.8, 2.4), -0.05, 0.08)
                c2 = out * FACADE_R + V(0, 0, 4.4)
                prism_frame(S, c2, up.cross(out), up, out, [(-0.5, 0), (0.5, 0), (0.5, 1.0), (-0.5, 1.0)], -0.05, 0.08)
            th += 12.0
        # Abschlusswaende an den Tribuenen-Enden (rahmen die Tore)
        for th in (a0, a1):
            out, _ = radial(th)
            p = out * 32.4
            box(S, p.x, p.y, 5.8, 0.6, -1.6, 7.35, th)
            box(Gd, p.x, p.y, 5.9, 0.7, 7.35, 7.55, th)
            q = out * (FACADE_R + 0.1)
            box(S, q.x, q.y, 1.2, 1.4, -1.6, 7.35, th)

def pole_with_pennant(Gd, Wp, x, y, z0, z1, dirv, length, height):
    box(Gd, x, y, 0.2, 0.2, z0, z1)
    pennant(Wp, V(x, y, z1 - 0.15), dirv, length, height)

def build_gates():
    Sd, S, Gd, W, Wp = (bm_of(n) for n in ("Pit_Sandstein", "Pit_Schiefer", "Pit_Gold", "Pit_Waben", "Pit_Wimpel"))
    for sy in (1, -1):
        for sx in (1, -1):
            x, y = sx * PYLON_X, sy * PYLON_Y
            box(Sd, x, y, 2.4, 2.4, -0.5, 0.65)
            box(S, x, y, 1.8, 1.8, 0.65, 9.6)
            box(Gd, x, y, 2.0, 2.0, 4.05, 4.35)
            box(Gd, x, y, 2.1, 2.1, 9.6, 10.0)
            pyramid(S, x, y, 2.0, 10.0, 11.3)
            pole_with_pennant(Gd, Wp, x, y, 11.0, 13.8, V(sx, 0, 0), 1.9, 1.1)
            banner(Wp, V(x, y + sy * 0.9, 4.6), V(0, sy, 0), 1.3, 4.2, 0.55)
    # Raketen-Tor: Sturz mit Wappen (hier fliegt niemand; Abstand zu den Etagen-Zaeunen >= 0.2)
    yc = -(PYLON_Y + 0.6)
    box(Sd, 0, yc, 2 * (PYLON_X + 1.1), 1.0, 8.0, 9.0)
    box(Gd, 0, yc + 0.05, 2 * (PYLON_X - 0.9), 0.9, 7.8, 8.0)
    c = V(0, yc, 10.35)
    vhex(Gd, c, V(0, 1, 0), 1.5, -0.25, 0.25)
    vhex(S, c, V(0, 1, 0), 0.95, -0.32, 0.32)
    vhex(W, c, V(0, 1, 0), 0.45, -0.38, 0.38)

def build_towers():
    Sd, S, Gd, Wp = (bm_of(n) for n in ("Pit_Sandstein", "Pit_Schiefer", "Pit_Gold", "Pit_Wimpel"))
    for th in (0.0, 180.0):
        out, tan = radial(th)
        p = out * 36.4
        box(Sd, p.x, p.y, 3.0, 3.0, -1.6, -0.4, th)
        box(S, p.x, p.y, 2.4, 2.4, -0.4, 9.4, th)
        box(Gd, p.x, p.y, 2.6, 2.6, 7.35, 7.55, th)
        box(Gd, p.x, p.y, 2.7, 2.7, 9.4, 9.8, th)
        pyramid(S, p.x, p.y, 2.6, 9.8, 11.4, th)
        pole_with_pennant(Gd, Wp, p.x, p.y, 11.1, 14.2, tan, 2.2, 1.3)

def build_stage_template():
    R, Gd = bm_of("Pit_Stufe_Rand"), bm_of("Pit_Stufe_Gold")
    ring(R, STUFE_RAND[0], STUFE_RAND[1], STUFE_RAND[2], STUFE_RAND[3], n=STUFE_SEG)
    ring(Gd, *STUFE_RAIL, n=STUFE_SEG)
    ring(Gd, *STUFE_MID, n=STUFE_SEG)
    for i in range(STUFE_POSTS):
        th = 360.0 * i / STUFE_POSTS
        out, _ = radial(th)
        p = out * STUFE_POST_R
        box(Gd, p.x, p.y, 0.28, 0.28, STUFE_RAND[3] - 0.02, STUFE_RAIL[2] + 0.02, th)

# ---------------------------------------------------------------- Szene
def reset_scene():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for c in list(bpy.data.collections):
        bpy.data.collections.remove(c)
    for blocks in (bpy.data.meshes, bpy.data.materials, bpy.data.cameras, bpy.data.lights,
                   bpy.data.armatures, bpy.data.actions, bpy.data.images):
        for b in list(blocks):
            if b.users == 0:
                blocks.remove(b)
    G.clear()

def coll(name, parent=None):
    c = bpy.data.collections.new(name)
    (parent or bpy.context.scene.collection).children.link(c)
    return c

def material(name, rgb, kind="SmoothPlastic"):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = lin(rgb)
    b.inputs["Roughness"].default_value = 0.35 if kind == "Metal" else (0.15 if kind == "Water" else 0.8)
    b.inputs["Metallic"].default_value = 0.65 if kind == "Metal" else 0.0
    if kind == "Neon":
        b.inputs["Emission Color"].default_value = lin(rgb)
        b.inputs["Emission Strength"].default_value = 2.5
    return m

def finish(name, bm, mat, c):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.polygons.foreach_set("use_smooth", [False] * len(me.polygons))
    me.materials.append(mat)
    o = bpy.data.objects.new(name, me)
    c.objects.link(o)
    return o

def simple(name, c, rgb, fn, kind="SmoothPlastic"):
    bm = bmesh.new()
    fn(bm)
    return finish(name, bm, material(name + "_mat", rgb, kind), c)

BEAR = {"scale": 1.0}

def bear_template():
    """Echtes Baerchi-Modell als Massstab. Die Vorlage wird nur zum Messen kurz in die Szene gehaengt
    und danach wieder ausgehaengt, damit nur die Instanzen gerendert werden."""
    if not os.path.exists(BEAR_FBX):
        return None
    tmpl = bpy.data.collections.new("Baer_Vorlage")
    bpy.context.scene.collection.children.link(tmpl)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=BEAR_FBX)
    new = [o for o in bpy.data.objects if o not in before]
    for o in new:
        for c in list(o.users_collection):
            c.objects.unlink(o)
        tmpl.objects.link(o)
        if o.parent is None:
            o.location = (0, 0, 1.32)                      # Fuesse auf 0 (wie Pulsar-Prototyp)
            o.rotation_euler = (0, 0, 0)
    bpy.context.view_layer.update()
    zs = [(o.matrix_world @ Vector(c)).z for o in new if o.type == 'MESH' for c in o.bound_box]
    if zs and max(zs) - min(zs) > 0.1:
        BEAR["scale"] = BEAR_HEIGHT / (max(zs) - min(zs))
        BEAR["roh"] = round(max(zs) - min(zs), 2)
    bpy.context.scene.collection.children.unlink(tmpl)
    return tmpl

def bear(c, tmpl, x, y, z, face_deg):
    if tmpl is None:
        return
    e = bpy.data.objects.new("Baer", None)
    e.instance_type = 'COLLECTION'
    e.instance_collection = tmpl
    e.location = (x, y, z)
    e.rotation_euler = (0, 0, math.radians(face_deg + 90.0))   # yaw 0 blickt nach -Y
    e.scale = (BEAR["scale"],) * 3
    c.objects.link(e)

def build_preview(stufe_objs):
    pv = coll("Vorschau")
    simple("Vorschau_Wasser", pv, (64, 150, 200), lambda b: box(b, 0, 0, 420, 420, WATER_Z - 0.2, WATER_Z), "Water")
    simple("Vorschau_Ufer", pv, (238, 214, 158), lambda b: cyl(b, 0, 0, SHORE_R, -10, SHORE_Z, 96))
    simple("Vorschau_Sockel", pv, (234, 212, 166), lambda b: cyl(b, 0, 0, BASE_R, -10, RIM_Z, 96))
    simple("Vorschau_Kampfboden", pv, (247, 236, 212), lambda b: cyl(b, 0, 0, FLOOR_R, -2, 0, 96))
    def bridges(b):
        for sy in (1, -1):
            box(b, 0, sy * 47, 12, 38, -1.55, -0.05)
    def rails(b):
        for sy in (1, -1):
            for sx in (1, -1):
                box(b, sx * 6.5, sy * 47, 1, 38, -0.05, 2.95)
    simple("Vorschau_Stege", pv, (170, 120, 70), bridges)
    simple("Vorschau_Gelaender", pv, (140, 95, 55), rails)
    def posts(b):
        for y in (33, 61):
            for sx in (1, -1):
                cyl(b, sx * 6.5, y, 0.7, -0.05, 5.75, 12)
    def flames(b):
        for y in (33, 61):
            for sx in (1, -1):
                bmesh.ops.create_uvsphere(b, u_segments=10, v_segments=6, radius=1.1,
                                          matrix=Matrix.Translation((sx * 6.5, y, 6.15)))
    simple("Vorschau_Kohlenpfannen", pv, (255, 205, 70), posts, "Metal")
    simple("Vorschau_Glut", pv, (255, 175, 45), flames, "Neon")
    simple("Vorschau_Flugfeld", pv, (255, 214, 90), lambda b: cyl(b, -4.5, 28, 2.2, -0.35, -0.15, 24), "Neon")
    # Turm mit 6 Etagen samt Zaun (verlinkte Kopien der Vorlage)
    tw = coll("Vorschau_Turm")
    for lv in range(1, 7):
        rgb = TOWER_COLORS[(lv - 1) % len(TOWER_COLORS)]
        simple("Vorschau_Ring_%d" % lv, tw, rgb, lambda b, lv=lv: cyl(b, 0, 0, FLOOR_R, (lv - 1) * STEP_H, lv * STEP_H, 96))
        for o in stufe_objs:
            d = o.copy()
            d.name = "%s_E%d" % (o.name, lv)
            d.location = (0, 0, lv * STEP_H)
            tw.objects.link(d)
    tmpl = bear_template()
    kb, kt, zs = coll("Vorschau_Kaempfer_Boden"), coll("Vorschau_Kaempfer_Turm"), coll("Vorschau_Zuschauer")
    for c, z in ((kb, 0.0), (kt, 6 * STEP_H)):
        bear(c, tmpl, -9, 0, z, 0)
        bear(c, tmpl, 9, 0, z, 180)
    for a in (-120, -75, -30, 30, 75, 120):           # ArenaLifeController.SPECTATOR_ANGLES (0 = Raketen-Seite)
        th = 270.0 + a
        out, _ = radial(th)
        bear(zs, tmpl, out.x * SEAT_R, out.y * SEAT_R, SEAT_Z, th + 180.0)
    return tmpl is not None

def setup_render():
    sc = bpy.context.scene
    for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            sc.render.engine = eng
            break
        except Exception:
            pass
    sc.render.resolution_x, sc.render.resolution_y, sc.render.resolution_percentage = 1280, 720, 100
    sc.view_settings.view_transform = "Standard"
    try:
        sc.eevee.taa_render_samples = 32
    except Exception:
        pass
    w = bpy.data.worlds.get("Pit_Himmel") or bpy.data.worlds.new("Pit_Himmel")
    sc.world = w
    w.use_nodes = True
    bg = w.node_tree.nodes.get("Background")
    bg.inputs[0].default_value = (0.50, 0.70, 0.95, 1)
    bg.inputs[1].default_value = 0.6
    sun = bpy.data.objects.new("Pit_Sonne", bpy.data.lights.new("Pit_Sonne", "SUN"))
    sc.collection.objects.link(sun)
    sun.data.energy = 2.8
    sun.data.angle = math.radians(3)
    sun.rotation_euler = (math.radians(40), 0, math.radians(72))
    cam = bpy.data.objects.new("Pit_Cam", bpy.data.cameras.new("Pit_Cam"))
    sc.collection.objects.link(cam)
    cam.data.clip_end = 1000
    sc.camera = cam

def set_visible(name, on):
    c = bpy.data.collections.get(name)
    if c:
        c.hide_render = not on
        c.hide_viewport = not on

def stats(objs):
    rep = {}
    for o in objs:
        o.data.calc_loop_triangles()
        xs = [v.co.x for v in o.data.vertices]; ys = [v.co.y for v in o.data.vertices]; zs = [v.co.z for v in o.data.vertices]
        lo, hi = (min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs))
        c = [(lo[i] + hi[i]) / 2 for i in range(3)]
        s = [hi[i] - lo[i] for i in range(3)]
        rep[o.name] = {
            "tris": len(o.data.loop_triangles),
            "roblox_center": [round(c[0], 3), round(c[2], 3), round(-c[1], 3)],
            "roblox_size": [round(s[0], 3), round(s[2], 3), round(s[1], 3)],
            "color": list(FARBE[o.name]),
            "material": ROBLOX_MAT.get(o.name, "SmoothPlastic"),
        }
    return rep

def build():
    t0 = time.time()
    reset_scene()
    tiles = build_floor()
    medals = build_wall()
    build_stands()
    build_gates()
    build_towers()
    build_stage_template()
    ca, cs = coll("Pit_Export_Arena"), coll("Pit_Export_Stufe")
    arena = [finish(n, G.pop(n), material(n + "_mat", FARBE[n], ROBLOX_MAT.get(n, "SmoothPlastic")), ca) for n in ARENA_OBJS]
    stufe = [finish(n, G.pop(n), material(n + "_mat", FARBE[n], ROBLOX_MAT.get(n, "SmoothPlastic")), cs) for n in STUFE_OBJS]
    cs.hide_render = True                    # Vorlage liegt im Ursprung; gezeigt werden die Kopien im Turm
    has_bear = build_preview(stufe)
    setup_render()
    os.makedirs(RENDERS, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND)
    return {"ok": True, "sek": round(time.time() - t0, 1), "waben": tiles, "medaillons": medals,
            "baer": has_bear, "baer_skala": round(BEAR["scale"], 3), "baer_roh": BEAR.get("roh"),
            "objekte": stats(arena + stufe)}

def render(view):
    sc = bpy.context.scene
    v = VIEWS[view]
    cam = bpy.data.objects["Pit_Cam"]
    cam.location = V(*v["pos"])
    if v.get("ortho"):
        cam.data.type = 'ORTHO'
        cam.data.ortho_scale = v["ortho"]
        cam.rotation_euler = (0, 0, 0)
    else:
        cam.data.type = 'PERSP'
        cam.data.lens = v.get("lens", 30)
        cam.rotation_euler = (V(*v["aim"]) - cam.location).to_track_quat('-Z', 'Y').to_euler()
    turm = v.get("turm", False)
    set_visible("Vorschau_Turm", turm)
    set_visible("Vorschau_Kaempfer_Turm", turm)
    set_visible("Vorschau_Kaempfer_Boden", not turm)
    path = os.path.join(RENDERS, "pit_kolosseum_%s.png" % view)
    sc.render.filepath = path
    t0 = time.time()
    bpy.ops.render.render(write_still=True)
    return {"ok": True, "bild": path, "sek": round(time.time() - t0, 1)}

def export():
    vl = bpy.context.view_layer
    rep = {}
    for c in ("Pit_Export_Arena", "Pit_Export_Stufe"):
        set_visible(c, True)
    vl.update()
    for fname, names in (("Pit_Kolosseum.fbx", ARENA_OBJS), ("Pit_Stufe.fbx", STUFE_OBJS)):
        objs = [bpy.data.objects[n] for n in names]
        for o in vl.objects:
            try:
                o.select_set(False)
            except RuntimeError:
                pass
        for o in objs:
            o.select_set(True)
        vl.objects.active = objs[0]
        bpy.ops.export_scene.fbx(filepath=os.path.join(OUT, fname), use_selection=True,
                                 apply_scale_options='FBX_SCALE_ALL', axis_forward='-Z', axis_up='Y',
                                 bake_space_transform=True, mesh_smooth_type='FACE', colors_type='SRGB')
        rep[fname] = stats(objs)
    bpy.data.collections["Pit_Export_Stufe"].hide_render = True
    manifest = {"quelle": "tools/pit/pit_kolosseum_scene.py", "achsen": "Blender (x,y,z) -> Roblox (x,z,-y)",
                "ursprung": "Arena-Mitte auf Kampfflaechen-Oberkante; Modell -Z zeigt zum Steg",
                "dateien": rep}
    with open(os.path.join(OUT, "Pit_Kolosseum_manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)
    return {"ok": True, "manifest": manifest}

_mode = globals().get("MODE", "build")
if _mode == "build":
    RESULT = build()
elif _mode.startswith("render:"):
    RESULT = render(_mode.split(":", 1)[1])
elif _mode == "export":
    RESULT = export()
else:
    RESULT = {"ok": False, "fehler": "unbekannter MODE " + _mode}
