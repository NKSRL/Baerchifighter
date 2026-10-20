# Map-Stil V2, Phase 4: 5 Buesche, 2 Randbuesche, 2 Gras-Cluster (Blender-MCP).
# 1 Einheit = 1 Stud, Pivot Boden (z=0, Lobes minimal eingesunken), Vertexfarben "Col", Buesche <= 120 Tris.
import bpy, bmesh, math, random, os
from mathutils import Vector

OUT = r"C:\Users\admin\Documents\Claude Downloads\RBL\assets\map"

def s2l(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
def col(r, g, b): return (s2l(r), s2l(g), s2l(b), 1.0)
def mix(a, b, t): return tuple(a[i] + (b[i] - a[i]) * t for i in range(4))
def smoothstep(t): t = max(0.0, min(1.0, t)); return t * t * (3 - 2 * t)

BUSCH_TIEF  = col(30, 98, 44)
BUSCH_MITTE = col(64, 150, 62)
BUSCH_HELL  = col(138, 204, 86)
GRAS_TIEF   = col(60, 140, 56)
GRAS_SPITZE = col(170, 224, 100)
HONIG       = col(255, 205, 80)
PINK        = col(255, 150, 190)
WEISS       = col(255, 244, 226)
BEERE       = col(236, 96, 96)

def lobe(bm, center, radii, seed, noise=0.07, sub=2):
    rnd = random.Random(seed)
    vs = bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=1.0)["verts"]
    for v in vs:
        n = v.co.normalized(); k = 1 + rnd.uniform(-noise, noise)
        v.co = Vector((n.x * radii[0] * k + center[0], n.y * radii[1] * k + center[1], n.z * radii[2] * k + center[2]))
    return vs

def finish(name, bm, colorfn, smooth=True):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    me.polygons.foreach_set("use_smooth", [smooth] * len(me.polygons))
    ca = me.color_attributes.new("Col", 'BYTE_COLOR', 'CORNER')
    for poly in me.polygons:
        for li in poly.loop_indices:
            ca.data[li].color = colorfn(me.vertices[me.loops[li].vertex_index].co)
    return bpy.data.objects.new(name, me)

def foliage_color(ztop, accents=()):
    """Verlauf unten tief -> oben hell; Bluten/Beeren (kleine Lobes) bekommen Akzentfarben ueber (x,y,z)-Naehe."""
    def f(co):
        for (ax, ay, az, ar, ac) in accents:
            if (co.x - ax) ** 2 + (co.y - ay) ** 2 + (co.z - az) ** 2 <= (ar * 1.15) ** 2:
                return ac
        t = smoothstep(co.z / max(ztop, 0.1))
        c = mix(mix(BUSCH_TIEF, BUSCH_MITTE, 0.5), BUSCH_MITTE, smoothstep(t * 1.8))
        return mix(c, BUSCH_HELL, smoothstep((t - 0.55) / 0.45) * 0.85)
    return f

def busch_a():   # rund + kleiner Seiten-Lobe  (100 Tris)
    bm = bmesh.new()
    lobe(bm, (0, 0, 1.55), (2.8, 2.8, 1.9), 1)
    lobe(bm, (1.9, 0.9, 0.95), (1.3, 1.3, 1.0), 2, sub=1)
    return finish("Map_Busch_A", bm, foliage_color(3.4))
def busch_b():   # kuschelig, vier kleine Lobes (80 Tris)
    bm = bmesh.new()
    for k, (x, y, rr) in enumerate([(0, 0, 1.9), (1.8, 0.7, 1.5), (-1.7, 0.5, 1.5), (0.2, -1.5, 1.3)]):
        lobe(bm, (x, y, rr * 0.85), (rr * 1.15, rr * 1.15, rr), 10 + k, 0.09, sub=1)
    return finish("Map_Busch_B", bm, foliage_color(3.2))
def busch_c():   # breit mit Beeren (120 Tris)
    bm = bmesh.new()
    lobe(bm, (0, 0, 1.2), (3.4, 2.6, 1.5), 20)
    pts = [(1.2, -1.2, 2.4), (-1.5, -0.4, 2.3)]
    for k, (x, y, z) in enumerate(pts):
        lobe(bm, (x, y, z), (0.45, 0.45, 0.45), 21 + k, 0.0, sub=1)
    return finish("Map_Busch_C", bm, foliage_color(2.7, [(x, y, z, 0.45, BEERE) for (x, y, z) in pts]))
def busch_d():   # hoch, schmal (100 Tris)
    bm = bmesh.new()
    lobe(bm, (0, 0, 2.2), (2.0, 2.0, 2.7), 30)
    lobe(bm, (-1.1, 0.7, 1.0), (1.2, 1.2, 1.0), 31, sub=1)
    return finish("Map_Busch_D", bm, foliage_color(4.9))
def busch_e():   # Bluetenbusch (120 Tris)
    bm = bmesh.new()
    lobe(bm, (0, 0, 1.5), (2.7, 2.7, 1.8), 40)
    pts = [(1.0, -1.3, 2.7, PINK), (-1.2, 0.9, 2.8, WEISS)]
    for k, (x, y, z, c) in enumerate(pts):
        lobe(bm, (x, y, z), (0.5, 0.5, 0.4), 41 + k, 0.0, sub=1)
    return finish("Map_Busch_E", bm, foliage_color(3.3, [(x, y, z, 0.5, c) for (x, y, z, c) in pts]))
def rim_a():     # flach, breit (80 Tris)
    bm = bmesh.new()
    lobe(bm, (0, 0, 0.8), (3.0, 2.2, 1.1), 50)
    return finish("Map_RimBusch_A", bm, foliage_color(1.7))
def rim_b():     # Reihe aus drei flachen Lobes (60 Tris)
    bm = bmesh.new()
    for k, (x, y, rx) in enumerate([(-1.9, 0, 1.4), (0.2, 0.2, 1.8), (2.1, -0.1, 1.3)]):
        lobe(bm, (x, y, 0.55), (rx, 1.4, 0.9), 60 + k, 0.08, sub=1)
    return finish("Map_RimBusch_B", bm, foliage_color(1.4))

def halme(bm, n, radius, hmin, hmax, seed, w=0.16):
    rnd = random.Random(seed)
    for k in range(n):
        a = 2 * math.pi * k / n + rnd.uniform(-0.3, 0.3)
        r = radius * rnd.uniform(0.2, 1.0)
        x, y = r * math.cos(a), r * math.sin(a)
        h = rnd.uniform(hmin, hmax)
        lean = rnd.uniform(0.15, 0.5) * h
        bx, by = x * 0.3 + lean * math.cos(a) * 0.6, y * 0.3 + lean * math.sin(a) * 0.6
        # Halm = flache Pyramide (3 Seitenflaechen)
        tip = bm.verts.new((x + bx, y + by, h))
        base = [bm.verts.new((x + w * math.cos(a + k2 * 2.094), y + w * math.sin(a + k2 * 2.094), 0)) for k2 in range(3)]
        for k2 in range(3):
            bm.faces.new((base[k2], base[(k2 + 1) % 3], tip))
def gras_a():    # 14 Halme (42 Tris)
    bm = bmesh.new(); halme(bm, 14, 1.4, 0.9, 1.7, 70)
    return finish("Map_Gras_A", bm, lambda co: mix(GRAS_TIEF, GRAS_SPITZE, smoothstep(co.z / 1.6)))
def gras_b():    # 10 Halme + 3 Bluten (90 Tris)
    bm = bmesh.new(); halme(bm, 10, 1.2, 0.9, 1.5, 71)
    pts = [(0.5, 0.3, 1.5, HONIG), (-0.6, 0.5, 1.2, PINK), (0.1, -0.7, 1.35, WEISS)]
    for k, (x, y, z, c) in enumerate(pts):
        lobe(bm, (x, y, z), (0.3, 0.3, 0.26), 80 + k, 0.0, sub=1)
    def f(co):
        for (x, y, z, c) in pts:
            if (co.x - x) ** 2 + (co.y - y) ** 2 + (co.z - z) ** 2 <= 0.12: return c
        return mix(GRAS_TIEF, GRAS_SPITZE, smoothstep(co.z / 1.5))
    return finish("Map_Gras_B", bm, f)

sc = bpy.data.scenes.get("MAP_BUSHES") or bpy.data.scenes.new("MAP_BUSHES")
for o in list(sc.objects): bpy.data.objects.remove(o, do_unlink=True)
objs = [busch_a(), busch_b(), busch_c(), busch_d(), busch_e(), rim_a(), rim_b(), gras_a(), gras_b()]
for o in objs: sc.collection.objects.link(o)
bpy.context.window.scene = sc
def tris(o): o.data.calc_loop_triangles(); return len(o.data.loop_triangles)
report = {o.name: {"tris": tris(o), "dims": [round(d, 2) for d in o.dimensions]} for o in objs}
vl = sc.view_layers[0]; vl.update()
for o in vl.objects: o.select_set(False, view_layer=vl)
for o in objs: o.select_set(True, view_layer=vl)
vl.objects.active = objs[0]
os.makedirs(OUT, exist_ok=True)
bpy.ops.export_scene.fbx(filepath=os.path.join(OUT, "Map_Buesche.fbx"), use_selection=True, apply_scale_options='FBX_SCALE_ALL',
    axis_forward='-Z', axis_up='Y', bake_space_transform=True, mesh_smooth_type='FACE', colors_type='SRGB')
result = {"report": report}
