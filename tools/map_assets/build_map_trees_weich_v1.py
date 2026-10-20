# Map-Stil V2, Phase 3: 4 Baum-Varianten + 2 Stumpf/Blumen-Gruppen (Blender-MCP).
# 1 Einheit = 1 Stud, Pivot Stammfuss (z=0), Vertexfarben "Col", je <= 320 Tris, weiche Normalen.
import bpy, bmesh, math, random, os
from mathutils import Vector

OUT = r"C:\Users\admin\Documents\Claude Downloads\RBL\assets\map"

def s2l(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
def col(r, g, b): return (s2l(r), s2l(g), s2l(b), 1.0)
def mix(a, b, t): return tuple(a[i] + (b[i] - a[i]) * t for i in range(4))
def smoothstep(t): t = max(0.0, min(1.0, t)); return t * t * (3 - 2 * t)

STAMM_DUNKEL = col(92, 60, 40)
STAMM_HELL   = col(150, 106, 68)
KRONE_TIEF   = col(34, 104, 46)
KRONE_MITTE  = col(70, 160, 66)
KRONE_HELL   = col(150, 214, 92)
HONIG        = col(255, 205, 80)
BLUETE_PINK  = col(255, 150, 190)
BLUETE_WEISS = col(255, 244, 226)

def lobe(bm, center, radii, seed, noise=0.07, sub=2):
    """Aufgeblasener Lobe: Ikosphaere (80 Tris), leicht verbeult. Gibt die neuen Verts zurueck."""
    rnd = random.Random(seed)
    g = bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=1.0)
    vs = g["verts"]
    for v in vs:
        n = v.co.normalized(); k = 1 + rnd.uniform(-noise, noise)
        v.co = Vector((n.x * radii[0] * k + center[0], n.y * radii[1] * k + center[1], n.z * radii[2] * k + center[2]))
    return vs

def trunk(bm, height, r0, r1, bend=(0.0, 0.0), sides=8, rings=3):
    rows = []
    for k in range(rings + 1):
        t = k / rings
        r = r0 + (r1 - r0) * t
        if k == 0: r *= 1.0
        cx, cy = bend[0] * t * t, bend[1] * t * t
        rows.append([bm.verts.new((cx + r * math.cos(2 * math.pi * i / sides), cy + r * math.sin(2 * math.pi * i / sides), height * t)) for i in range(sides)])
    for k in range(rings):
        for i in range(sides):
            j = (i + 1) % sides
            bm.faces.new((rows[k][i], rows[k][j], rows[k+1][j], rows[k+1][i]))
    # Kappe oben (schliesst den Stamm im Laub)
    top = bm.verts.new((bend[0], bend[1], height))
    for i in range(sides):
        bm.faces.new((rows[-1][i], rows[-1][(i + 1) % sides], top))
    return rows

def finish(name, bm, colorfn, smooth=True):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    me.polygons.foreach_set("use_smooth", [smooth] * len(me.polygons))
    ca = me.color_attributes.new("Col", 'BYTE_COLOR', 'CORNER')
    for poly in me.polygons:
        for li in poly.loop_indices:
            v = me.vertices[me.loops[li].vertex_index]
            ca.data[li].color = colorfn(v.co)
    return bpy.data.objects.new(name, me)

def tree_colors(zstem, zbot, ztop):
    def f(co):
        if co.z <= zstem * 1.001 and math.hypot(co.x, co.y) < 1.3:
            return mix(STAMM_DUNKEL, STAMM_HELL, smoothstep(co.z / max(zstem, 0.1)))
        t = smoothstep((co.z - zbot) / max(ztop - zbot, 0.1))
        c = mix(mix(KRONE_TIEF, KRONE_MITTE, 0.5), KRONE_MITTE, smoothstep(t * 1.8))
        return mix(c, KRONE_HELL, smoothstep((t - 0.55) / 0.45) * 0.9)
    return f

def baum_rund(name="Map_Baum_A"):
    bm = bmesh.new()
    trunk(bm, 8.0, 0.95, 0.6, bend=(0.35, 0.0))
    lobe(bm, (0.4, 0, 10.2), (5.4, 5.4, 4.6), 1)
    lobe(bm, (-2.6, 1.2, 8.9), (3.2, 3.2, 2.8), 2)
    lobe(bm, (2.8, -1.4, 9.0), (3.0, 3.0, 2.7), 3)
    return finish(name, bm, tree_colors(8.0, 5.2, 14.8))

def baum_hoch(name="Map_Baum_B"):
    bm = bmesh.new()
    trunk(bm, 10.5, 0.8, 0.5, bend=(-0.4, 0.2))
    lobe(bm, (-0.4, 0.2, 13.8), (3.4, 3.4, 6.2), 4)
    lobe(bm, (-0.6, 0.3, 11.0), (2.8, 2.8, 2.4), 5, 0.1)
    return finish(name, bm, tree_colors(10.5, 6.6, 20.0))

def baum_doppel(name="Map_Baum_C"):
    bm = bmesh.new()
    trunk(bm, 7.2, 1.0, 0.65, bend=(0.5, 0.0))
    lobe(bm, (0.5, 0, 9.0), (4.9, 4.9, 3.6), 6)
    lobe(bm, (0.9, 0.3, 13.6), (3.7, 3.7, 3.4), 7)
    lobe(bm, (-2.3, 0.8, 9.2), (2.6, 2.6, 2.2), 8)
    return finish(name, bm, tree_colors(7.2, 5.4, 17.2))

def baum_jung(name="Map_Baum_D"):
    bm = bmesh.new()
    trunk(bm, 3.8, 0.5, 0.32, bend=(0.15, 0.0), sides=6, rings=2)
    lobe(bm, (0.15, 0, 5.4), (3.0, 3.0, 2.8), 9, 0.1)
    lobe(bm, (-1.2, 0.5, 4.5), (1.7, 1.7, 1.5), 10, 0.1)
    return finish(name, bm, tree_colors(3.8, 2.6, 8.2))

def stumpf(name="Map_Stumpf_A"):
    bm = bmesh.new()
    sides = 10
    prof = [(1.5, 0.0), (1.2, 0.9), (1.05, 1.9), (1.15, 2.2), (0.85, 2.3)]
    rows = [[bm.verts.new((r * math.cos(2 * math.pi * i / sides), r * math.sin(2 * math.pi * i / sides), z)) for i in range(sides)] for (r, z) in prof]
    for k in range(len(prof) - 1):
        for i in range(sides):
            j = (i + 1) % sides
            bm.faces.new((rows[k][i], rows[k][j], rows[k+1][j], rows[k+1][i]))
    c = bm.verts.new((0, 0, 2.2))
    for i in range(sides): bm.faces.new((rows[-1][i], rows[-1][(i + 1) % sides], c))
    # kleiner Pilz-/Blumenkranz: drei Bluetenkoepfchen am Fuss
    for k, (x, y, cc) in enumerate([(2.1, 0.4, 0), (-1.8, 1.2, 1), (0.6, -2.0, 2)]):
        lobe(bm, (x, y, 0.45), (0.45, 0.45, 0.4), 20 + k, 0.0, sub=1)
    def f(co):
        if math.hypot(co.x, co.y) > 1.6 and co.z < 1.0:
            return [HONIG, BLUETE_PINK, BLUETE_WEISS][int(abs(co.x * 3 + co.y * 5)) % 3]
        return mix(STAMM_DUNKEL, STAMM_HELL, smoothstep(co.z / 2.3))
    return finish(name, bm, f)

def blumen(name="Map_Blumen_A"):
    bm = bmesh.new()
    pts = [(0, 0, 1.5), (1.4, 0.6, 1.1), (-1.2, 0.9, 1.3), (0.4, -1.3, 1.0), (-0.6, -0.9, 0.8)]
    # Gras-Insel als flache Kuppel
    lobe(bm, (0, 0, 0.0), (2.4, 2.4, 0.5), 30, 0.05)
    for k, (x, y, h) in enumerate(pts):
        trunk(bm, h, 0.07, 0.05, bend=(0.0, 0.0), sides=4, rings=1)
        for v in bm.verts[-5:]: v.co.x += x; v.co.y += y
        lobe(bm, (x, y, h + 0.15), (0.35, 0.35, 0.3), 40 + k, 0.0, sub=1)
    def f(co):
        if co.z < 0.3 and math.hypot(co.x, co.y) < 2.6: return mix(KRONE_TIEF, KRONE_MITTE, smoothstep(co.z / 0.5 + 0.4))
        if co.z > 0.7: return [HONIG, BLUETE_PINK, BLUETE_WEISS][int(abs(co.x * 4 + co.y * 7)) % 3]
        return mix(KRONE_TIEF, KRONE_MITTE, 0.6)
    return finish(name, bm, f)

sc = bpy.data.scenes.get("MAP_TREES") or bpy.data.scenes.new("MAP_TREES")
for o in list(sc.objects): bpy.data.objects.remove(o, do_unlink=True)
objs = [baum_rund(), baum_hoch(), baum_doppel(), baum_jung(), stumpf(), blumen()]
for o in objs: sc.collection.objects.link(o)
bpy.context.window.scene = sc
def tris(o): o.data.calc_loop_triangles(); return len(o.data.loop_triangles)
report = {o.name: {"tris": tris(o), "dims": [round(d, 2) for d in o.dimensions]} for o in objs}
vl = sc.view_layers[0]; vl.update()
for o in vl.objects: o.select_set(False, view_layer=vl)
for o in objs: o.select_set(True, view_layer=vl)
vl.objects.active = objs[0]
os.makedirs(OUT, exist_ok=True)
bpy.ops.export_scene.fbx(filepath=os.path.join(OUT, "Map_Baeume.fbx"), use_selection=True, apply_scale_options='FBX_SCALE_ALL',
    axis_forward='-Z', axis_up='Y', bake_space_transform=True, mesh_smooth_type='FACE', colors_type='SRGB')
result = {"report": report}
