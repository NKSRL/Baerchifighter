# Gemeinsame Helfer fuer die Map-Meshes (Kanten-Stil V2). Wird per exec() in den Namensraum der Bauskripte geladen.
import bpy, bmesh, math, random, os
from mathutils import Vector

OUT = r"C:\Users\admin\Documents\Claude Downloads\RBL\assets\map"

def s2l(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
def col(r, g, b): return (s2l(r), s2l(g), s2l(b), 1.0)
def mix(a, b, t): return tuple(a[i] + (b[i] - a[i]) * t for i in range(4))
def smoothstep(t): t = max(0.0, min(1.0, t)); return t * t * (3 - 2 * t)
def key(co): return (round(co.x, 3), round(co.y, 3), round(co.z, 3))
def tint(c, co, amt=0.10):
    h = (math.sin(co.x * 12.9898 + co.y * 78.233 + co.z * 37.719) * 43758.5453) % 1.0
    k = 1 + (h - 0.5) * 2 * amt
    return (min(1, c[0] * k), min(1, c[1] * k), min(1, c[2] * k), 1.0)

STAMM_DUNKEL = col(84, 54, 38)
STAMM_HELL   = col(148, 102, 66)
LAUB_TIEF    = col(26, 92, 46)
LAUB_MITTE   = col(66, 162, 58)
LAUB_HELL    = col(176, 226, 84)
LAUB_GELB    = col(236, 214, 84)
HONIG        = col(255, 205, 80)
PINK         = col(255, 140, 186)
WEISS        = col(255, 244, 226)
BEERE        = col(232, 80, 84)

def lobe(bm, center, radii, seed, noise=0.2, sub=2):
    """Kantiger Klumpen: Ikosphaere, stark verbeult (Flat-Shading macht die Facetten)."""
    rnd = random.Random(seed)
    vs = bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=1.0)["verts"]
    for v in vs:
        n = v.co.normalized(); k = 1 + rnd.uniform(-noise, noise)
        v.co = Vector((n.x * radii[0] * k + center[0], n.y * radii[1] * k + center[1], n.z * radii[2] * k + center[2]))
    return vs

def spikes(bm, center, radii, count, length, width, seed, tipcolors, zmin=-0.3, up=0.35, tips=None):
    """Abstehende Blattspitzen: flache Dreiecks-Pyramiden (3 Tris), von der Klumpen-Oberflaeche nach aussen/oben.
    tipcolors: Liste von Farben (zyklisch); tips: dict {key(tip): farbe} wird gefuellt."""
    rnd = random.Random(seed)
    placed = 0
    golden = math.pi * (3 - math.sqrt(5))
    tries = count * 4
    for i in range(tries):
        if placed >= count: break
        z = 1 - 2 * (i + 0.5) / tries
        if z < zmin: continue
        r = math.sqrt(max(0, 1 - z * z)); a = golden * i + rnd.uniform(-0.3, 0.3)
        n = Vector((r * math.cos(a), r * math.sin(a), z))
        p = Vector((center[0] + n.x * radii[0] * 0.9, center[1] + n.y * radii[1] * 0.9, center[2] + n.z * radii[2] * 0.9))
        d = (n * 0.8 + Vector((0, 0, up)) + Vector((rnd.uniform(-.25, .25), rnd.uniform(-.25, .25), rnd.uniform(-.1, .2)))).normalized()
        u = d.cross(Vector((0, 0, 1)))
        if u.length < 1e-3: u = Vector((1, 0, 0))
        u.normalize(); v2 = d.cross(u).normalized()
        L = length * rnd.uniform(0.75, 1.25); w = width * rnd.uniform(0.8, 1.2)
        base = [bm.verts.new(p + (u * math.cos(k * 2.094) + v2 * math.sin(k * 2.094)) * w) for k in range(3)]
        tip = bm.verts.new(p + d * L)
        for k in range(3): bm.faces.new((base[k], base[(k + 1) % 3], tip))
        if tips is not None: tips[key(tip.co)] = tipcolors[placed % len(tipcolors)]
        placed += 1

LEAVES_ON = False
PENDING = []   # Blaetter: werden erst NACH recalc_face_normals gebaut, damit die Windung (Vorder-/Rueckseite) stimmt

def leaves(bm, center, radii, count, length, width, seed, tipcolors, tips, zmin=-0.5, droop=-0.02, up=0.35):
    """Abstehende Blaetter ringsum (auch seitlich/unten haengend): flache Rauten, doppelseitig (4 Tris je Blatt)."""
    if not LEAVES_ON: return   # Wunsch 20.10.: keine abstehenden Blattspitzen, nur kantige Klumpen
    rnd = random.Random(seed)
    golden = math.pi * (3 - math.sqrt(5))
    tries = count * 3
    placed = 0
    for i in range(tries):
        if placed >= count: break
        z = 1 - 2 * (i + 0.5) / tries
        if z < zmin: continue
        r = math.sqrt(max(0, 1 - z * z)); a = golden * i + rnd.uniform(-0.25, 0.25)
        n = Vector((r * math.cos(a), r * math.sin(a), z))
        p = Vector((center[0] + n.x * radii[0] * 0.88, center[1] + n.y * radii[1] * 0.88, center[2] + n.z * radii[2] * 0.88))
        vz = up if z > 0.25 else droop
        d = (n * 1.0 + Vector((0, 0, vz)) + Vector((rnd.uniform(-.3, .3), rnd.uniform(-.3, .3), rnd.uniform(-.15, .15)))).normalized()
        u = d.cross(Vector((0, 0, 1)))
        if u.length < 1e-3: u = Vector((1, 0, 0))
        u.normalize()
        L = length * 1.15 * rnd.uniform(0.8, 1.2); w = width * 1.7 * rnd.uniform(0.85, 1.15)
        PENDING.append((bm, p, p + d * L, p + d * (0.45 * L) + u * (w / 2), p + d * (0.45 * L) - u * (w / 2), n, tipcolors[placed % len(tipcolors)]))
        placed += 1

def trunk(bm, height, r0, r1, bend=(0.0, 0.0), sides=6, rings=3, flare=1.35):
    rows = []
    for k in range(rings + 1):
        t = k / rings
        r = r0 + (r1 - r0) * t
        if k == 0: r *= flare
        cx, cy = bend[0] * t * t, bend[1] * t * t
        rows.append([bm.verts.new((cx + r * math.cos(2 * math.pi * i / sides + 0.3 * k), cy + r * math.sin(2 * math.pi * i / sides + 0.3 * k), height * t)) for i in range(sides)])
    for k in range(rings):
        for i in range(sides):
            j = (i + 1) % sides
            bm.faces.new((rows[k][i], rows[k][j], rows[k+1][j], rows[k+1][i]))
    top = bm.verts.new((bend[0], bend[1], height))
    for i in range(sides): bm.faces.new((rows[-1][i], rows[-1][(i + 1) % sides], top))

LEAFCOL = {}
def finish(name, bm, colorfn):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    for (b, base, tip, l, r, n, tc) in [x for x in PENDING if x[0] is bm]:
        fn = (l - base).cross(tip - base)
        front = (base, l, tip, r) if fn.dot(n) >= 0 else (base, r, tip, l)
        fnu = fn.normalized() if fn.length > 1e-6 else Vector((0, 0, 1))
        if fn.dot(n) < 0: fnu = -fnu
        cols = [mix(LAUB_MITTE, tc, 0.2), mix(LAUB_MITTE, tc, 0.6), tc, mix(LAUB_MITTE, tc, 0.6)]
        for side, order in ((1.0, front), (-1.0, (front[0], front[3], front[2], front[1]))):
            pts = [c - fnu * 0.04 if side < 0 else c for c in order]   # Rueckseite minimal versetzt: kein Z-Fighting
            vb, vl_, vt, vr = [b.verts.new(c) for c in pts]
            b.faces.new((vb, vl_, vt)); b.faces.new((vb, vt, vr))
            # Farben je Eckpunkt: base, seite, tip, seite
            LEAFCOL[key(pts[0])] = cols[0]; LEAFCOL[key(pts[2])] = cols[2]
            LEAFCOL[key(pts[1])] = cols[1]; LEAFCOL[key(pts[3])] = cols[3]
    PENDING[:] = [x for x in PENDING if x[0] is not bm]
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    me.polygons.foreach_set("use_smooth", [False] * len(me.polygons))   # Kanten-Stil: Flat-Shading
    ca = me.color_attributes.new("Col", 'BYTE_COLOR', 'CORNER')
    for poly in me.polygons:
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            lc = LEAFCOL.get(key(co))
            ca.data[li].color = tint(lc, co, 0.08) if lc else colorfn(co)
    return bpy.data.objects.new(name, me)

def crown_color(zbot, ztop, tips, stem_h=0.0, stem_r=1.3):
    def f(co):
        k = key(co)
        if k in tips: return tint(tips[k], co, 0.06)
        if stem_h > 0 and co.z <= stem_h * 1.001 and math.hypot(co.x, co.y) < stem_r:
            return mix(STAMM_DUNKEL, STAMM_HELL, smoothstep(co.z / stem_h))
        t = smoothstep((co.z - zbot) / max(ztop - zbot, 0.1))
        c = mix(mix(LAUB_TIEF, LAUB_MITTE, 0.45), LAUB_MITTE, smoothstep(t * 1.8))
        return tint(mix(c, LAUB_HELL, smoothstep((t - 0.6) / 0.4) * 0.7), co, 0.10)
    return f

def export_set(sc, objs, fname):
    def tris(o): o.data.calc_loop_triangles(); return len(o.data.loop_triangles)
    for o in objs: sc.collection.objects.link(o)
    bpy.context.window.scene = sc
    report = {o.name: {"tris": tris(o), "dims": [round(d, 2) for d in o.dimensions]} for o in objs}
    vl = sc.view_layers[0]; vl.update()
    for o in vl.objects: o.select_set(False, view_layer=vl)
    for o in objs: o.select_set(True, view_layer=vl)
    vl.objects.active = objs[0]
    os.makedirs(OUT, exist_ok=True)
    bpy.ops.export_scene.fbx(filepath=os.path.join(OUT, fname), use_selection=True, apply_scale_options='FBX_SCALE_ALL',
        axis_forward='-Z', axis_up='Y', bake_space_transform=True, mesh_smooth_type='FACE', colors_type='SRGB')
    return report
