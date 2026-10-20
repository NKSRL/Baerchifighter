# Map-Stil V2, Phase 2: Boden-Meshes (laeuft im Blender-MCP). Eigene Szene, fasst andere Szenen nicht an.
# 1 Blender-Einheit = 1 Stud, Pivot Mitte-Unterkante, Vertexfarben (Attribut "Col"), keine Textur.
import bpy, bmesh, math, random, os
from mathutils import Vector

OUT = r"C:\Users\admin\Documents\Claude Downloads\RBL\assets\map"

def s2l(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
def col(r, g, b): return (s2l(r), s2l(g), s2l(b), 1.0)
def mix(a, b, t): return tuple(a[i] + (b[i] - a[i]) * t for i in range(4))

GRUEN_HELL  = col(98, 184, 80)
GRUEN_FRISCH= col(112, 196, 84)
GRUEN_TIEF  = col(46, 120, 52)
SAND        = col(226, 200, 150)
SAND_HELL   = col(240, 220, 170)
FELS_WARM   = col(214, 170, 120)
FELS_DUNKEL = col(132, 98, 92)
TUERKIS     = col(80, 224, 204)
FLIEDER     = col(184, 146, 238)

def new_obj(name, bm):
    me = bpy.data.meshes.new(name)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.to_mesh(me); bm.free()
    me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    ob = bpy.data.objects.new(name, me)
    return ob

def paint(ob, fn):
    """fn(co: Vector, normal: Vector) -> RGBA (linear). Vertexfarbe pro Ecke."""
    me = ob.data
    ca = me.color_attributes.new("Col", 'BYTE_COLOR', 'CORNER')
    for poly in me.polygons:
        for li in poly.loop_indices:
            v = me.vertices[me.loops[li].vertex_index]
            ca.data[li].color = fn(v.co, v.normal)

def tris(ob):
    ob.data.calc_loop_triangles(); return len(ob.data.loop_triangles)

def smoothstep(t): t = max(0.0, min(1.0, t)); return t * t * (3 - 2 * t)

# ---- Wiese: 24x24, Kuppel max 0.14 hoch, Randring faellt weich auf 0 ----
def wiese(name, seed, size=24.0, n=6, hmax=0.14):
    rnd = random.Random(seed)
    bm = bmesh.new()
    half = size / 2
    inset = 0.9
    grid = [[None] * (n + 1) for _ in range(n + 1)]
    for i in range(n + 1):
        for j in range(n + 1):
            x = -half + inset + (size - 2 * inset) * i / n
            y = -half + inset + (size - 2 * inset) * j / n
            d = max(abs(x), abs(y)) / (half - inset)
            z = 0.04 + hmax * (1 - smoothstep(d) ** 2) * 0.9 + rnd.uniform(-0.012, 0.012)
            grid[i][j] = bm.verts.new((x, y, z))
    for i in range(n):
        for j in range(n):
            bm.faces.new((grid[i][j], grid[i+1][j], grid[i+1][j+1], grid[i][j+1]))
    # Randring (Boden z=0) -> weiche Kante
    ring = []
    for i in range(n + 1): ring.append((i, 0))
    for j in range(1, n + 1): ring.append((n, j))
    for i in range(n - 1, -1, -1): ring.append((i, n))
    for j in range(n - 1, 0, -1): ring.append((0, j))
    outer = []
    for (i, j) in ring:
        v = grid[i][j].co
        dx = -half if v.x < 0 else half
        dy = -half if v.y < 0 else half
        ox = v.x if abs(v.x) < half - inset - 1e-4 else dx
        oy = v.y if abs(v.y) < half - inset - 1e-4 else dy
        outer.append(bm.verts.new((ox, oy, 0.0)))
    m = len(ring)
    for k in range(m):
        a, b = ring[k], ring[(k + 1) % m]
        bm.faces.new((grid[a[0]][a[1]], outer[k], outer[(k + 1) % m], grid[b[0]][b[1]]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    ob = new_obj(name, bm)
    prnd = random.Random(seed * 7 + 1)
    blobs = [(prnd.uniform(-9, 9), prnd.uniform(-9, 9), prnd.uniform(3.5, 6.5), prnd.random()) for _ in range(5)]
    def f(co, nrm):
        d = max(abs(co.x), abs(co.y)) / half
        c = mix(GRUEN_HELL, GRUEN_FRISCH, smoothstep(1 - d))
        for (bx, by, br, bt) in blobs:
            w = max(0.0, 1 - math.hypot(co.x - bx, co.y - by) / br)
            c = mix(c, GRUEN_FRISCH if bt > 0.5 else GRUEN_TIEF, w * 0.35)
        return mix(c, GRUEN_TIEF, smoothstep((d - 0.8) / 0.2) * 0.35)
    paint(ob, f)
    return ob

# ---- Ufer: gerade 24 lang x 6 breit, Sandband mit weichem Wulst; Y(Blender) = quer, +Y = Inselmitte ----
def ufer(name, length=24.0, width=6.0, seg=6):
    bm = bmesh.new()
    prof = [(-3.0, 0.0), (-2.6, 0.10), (-1.2, 0.17), (0.6, 0.14), (2.2, 0.10), (3.0, 0.0)]
    rows = []
    for s in range(seg + 1):
        x = -length / 2 + length * s / seg
        rows.append([bm.verts.new((x, py * width / 6.0, pz)) for (py, pz) in prof])
    for s in range(seg):
        for p in range(len(prof) - 1):
            bm.faces.new((rows[s][p], rows[s+1][p], rows[s+1][p+1], rows[s][p+1]))
    ob = new_obj(name, bm)
    def f(co, nrm):
        t = (co.y / (width / 2) + 1) / 2   # 0 Wasserseite .. 1 Wiesenseite
        c = mix(SAND_HELL, SAND, smoothstep(t * 1.4))
        return mix(c, GRUEN_HELL, smoothstep((t - 0.72) / 0.28) * 0.8)
    paint(ob, f)
    return ob

# ---- Ecke: Viertelscheibe r=6, Pivot an der Ecke ----
def ecke(name, r=6.0, arc=6):
    bm = bmesh.new()
    mid = bm.verts.new((0, 0, 0.14))
    rings = [(0.45, 0.13), (0.8, 0.10), (1.0, 0.0)]
    prev = None
    layers = []
    for (rf, z) in rings:
        layers.append([bm.verts.new((r * rf * math.cos(math.radians(90 * a / arc)), r * rf * math.sin(math.radians(90 * a / arc)), z)) for a in range(arc + 1)])
    for a in range(arc):
        bm.faces.new((mid, layers[0][a], layers[0][a+1]))
    for k in range(len(layers) - 1):
        for a in range(arc):
            bm.faces.new((layers[k][a], layers[k+1][a], layers[k+1][a+1], layers[k][a+1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    ob = new_obj(name, bm)
    def f(co, nrm):
        t = min(1.0, math.hypot(co.x, co.y) / r)
        return mix(mix(GRUEN_HELL, SAND_HELL, smoothstep((t - 0.1) / 0.4)), SAND, smoothstep((t - 0.6) / 0.4))
    paint(ob, f)
    return ob

# ---- Randfels: verbeulte Ikosphaere, Facetten erlaubt (Fels), unten flach ----
def fels(name, seed, radius=2.6):
    rnd = random.Random(seed)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1.0)
    for v in bm.verts:
        n = v.co.normalized()
        k = 1.0 + rnd.uniform(-0.18, 0.18)
        v.co = Vector((n.x * radius * 1.15 * k, n.y * radius * k, n.z * radius * 0.78 * k))
        if v.co.z < -0.1 * radius: v.co.z = -0.1 * radius
    bmesh.ops.translate(bm, vec=(0, 0, 0.1 * radius), verts=bm.verts[:])
    ob = new_obj(name, bm)
    me = ob.data
    me.polygons.foreach_set("use_smooth", [False] * len(me.polygons))
    zmax = max(v.co.z for v in me.vertices)
    def f(co, nrm):
        return mix(FELS_DUNKEL, FELS_WARM, smoothstep(co.z / zmax))
    paint(ob, f)
    return ob

# ---- Kristall-Cluster: 5 sechseckige Spitzen, ein Material/Farbton je Cluster ----
def kristall(name, seed, farbe):
    rnd = random.Random(seed)
    bm = bmesh.new()
    for (ox, oy, h, r, tilt) in [(0, 0, 3.2, 0.62, 0), (0.95, 0.3, 2.2, 0.5, 0.25), (-0.9, 0.4, 1.9, 0.46, -0.3), (0.25, -0.85, 1.5, 0.4, 0.2), (-0.35, 0.95, 1.3, 0.36, -0.15)]:
        base = [bm.verts.new((ox + r * math.cos(math.radians(60 * i)), oy + r * math.sin(math.radians(60 * i)), 0)) for i in range(6)]
        top = [bm.verts.new((ox + r * 0.55 * math.cos(math.radians(60 * i)) + tilt * h * 0.5, oy + r * 0.55 * math.sin(math.radians(60 * i)), h * 0.8)) for i in range(6)]
        tip = bm.verts.new((ox + tilt * h * 0.6, oy, h))
        for i in range(6):
            j = (i + 1) % 6
            bm.faces.new((base[i], base[j], top[j], top[i]))
            bm.faces.new((top[i], top[j], tip))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    ob = new_obj(name, bm)
    ob.data.polygons.foreach_set("use_smooth", [False] * len(ob.data.polygons))
    zmax = max(v.co.z for v in ob.data.vertices)
    dunkel = mix(farbe, col(40, 60, 90), 0.45)
    paint(ob, lambda co, n: mix(dunkel, farbe, smoothstep(co.z / zmax)))
    return ob

def build():
    sc = bpy.data.scenes.get("MAP_ASSETS") or bpy.data.scenes.new("MAP_ASSETS")
    for o in list(sc.objects): bpy.data.objects.remove(o, do_unlink=True)
    objs = [wiese("Map_Wiese_A", 11), wiese("Map_Wiese_B", 29), ufer("Map_Ufer_Gerade"), ecke("Map_Ufer_Ecke"),
            fels("Map_Randfels_A", 3), fels("Map_Randfels_B", 8, 2.0),
            kristall("Map_Kristall_A", 1, TUERKIS), kristall("Map_Kristall_B", 2, FLIEDER)]
    for o in objs: sc.collection.objects.link(o)
    return sc, objs

sc, objs = build()
bpy.context.window.scene = sc
report = {o.name: {"tris": tris(o), "dims": [round(d, 2) for d in o.dimensions]} for o in objs}
os.makedirs(OUT, exist_ok=True)
vl = sc.view_layers[0]
vl.update()
for o in vl.objects: o.select_set(False, view_layer=vl)
for o in objs: o.select_set(True, view_layer=vl)
vl.objects.active = objs[0]
bpy.ops.export_scene.fbx(filepath=os.path.join(OUT, "Map_Boden.fbx"), use_selection=True, apply_scale_options='FBX_SCALE_ALL',
    axis_forward='-Z', axis_up='Y', bake_space_transform=True, mesh_smooth_type='FACE', colors_type='SRGB')
result = {"report": report}
