# build_w1_pets.py - Welt 1, Paket 4+5d (20.10.2026): Pet_Genesis, Pet_Infinity, Pet_Shade, Pet_Ascendant (Hoffnungs-Pet des Ascension-Eis)
# Laeuft IN Blender (bpy): exec(open(<pfad>).read())
# Vorlage: Pet_Omega aus baerchi_varianten.blend (gleicher Koerper, gleiche Gesichts-Teile, gleiche Materialart:
# Principled, flache Farbe, je Teil ein eigenes Material - keine Texturen, daher keine schwarzen Flaechen).
# Erzeugt eine eigene Szene "W1_PETS" (die geoeffnete Datei bleibt sonst unberuehrt).
import bpy, bmesh, math, os
from mathutils import Vector

SRC = r"C:\Users\admin\Documents\Claude Downloads\RBL\baerchi_varianten.blend"
OUT = r"C:\Users\admin\Documents\Claude Downloads\RBL\Export"

def hexc(h):  # sRGB-Hex -> lineare Farbe (Blender Base Color)
    h = h.lstrip("#"); r, g, b = (int(h[i:i+2], 16) / 255 for i in (0, 2, 4))
    f = lambda c: c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return (f(r), f(g), f(b), 1.0)

# ---- Farben je Teil (sRGB-Hex) + Leuchten (emission strength) -----------------------------------------
# Teil -> (Farbe, Emission). Teile die hier fehlen, behalten die Omega-Farbe nicht, sondern bekommen 'default'.
PETS = {
    "Genesis": {   # urzeitlich, leuchtend, Eierschalen-Motive, warmes Weissgold
        "body": ("FFE7B0", 0.15), "ears": ("FFD98A", 0.1), "feet": ("FFD27A", 0.1), "toes": ("FFF9E8", 0.0),
        "muzzle": ("FFFBF0", 0.0), "nose": ("B8862B", 0.0), "eyes": ("3A2A12", 0.0), "cute_tail": ("FFE7B0", 0.1),
        "cute_innerear": ("FFD9A0", 0.0), "cute_blush": ("FFC9A0", 0.0), "cute_smile": ("8A5A2A", 0.0),
        "cute_hl": ("FFFFFF", 4.0),
    },
    "Infinity": {  # tiefes Indigo mit hellem Verlauf (Akzente heller), Moebius-Schleife schwebt
        "body": ("3F3FA6", 0.1), "ears": ("35358F", 0.1), "feet": ("2C2C78", 0.1), "toes": ("8F8FE8", 0.0),
        "muzzle": ("B7B7FF", 0.0), "nose": ("1B1B4A", 0.0), "eyes": ("151538", 0.0), "cute_tail": ("5656C4", 0.1),
        "cute_innerear": ("8F8FE8", 0.0), "cute_blush": ("9A7DFF", 0.0), "cute_smile": ("1B1B4A", 0.0),
        "cute_hl": ("FFFFFF", 4.0),
    },
    "Ascendant": { # Paket 5d: perlweisses Fell, kuehles Aqua + Gold-Akzente, schwebender Heiligenschein, aufsteigende Lichtpunkte
        "body": ("F4F7FF", 0.12), "ears": ("DDEBFF", 0.1), "feet": ("CFE0FF", 0.1), "toes": ("FFFFFF", 0.0),
        "muzzle": ("FFFFFF", 0.0), "nose": ("D9A93A", 0.0), "eyes": ("1E3A5F", 0.0), "cute_tail": ("F4F7FF", 0.12),
        "cute_innerear": ("BFE9F5", 0.0), "cute_blush": ("FFD9C9", 0.0), "cute_smile": ("3C6E9A", 0.0),
        "cute_hl": ("FFFFFF", 4.0),
    },
    "Shade": {     # Schattenbaer: dunkles Fell, violette Akzente, Augen = einziges Leuchtelement
        "body": ("2B2536", 0.0), "ears": ("241F2E", 0.0), "feet": ("1E1A28", 0.0), "toes": ("5B3A8C", 0.0),
        "muzzle": ("3C3350", 0.0), "nose": ("7A3FD0", 0.0), "eyes": ("C070FF", 2.5), "cute_tail": ("2B2536", 0.0),
        "cute_innerear": ("5B3A8C", 0.0), "cute_blush": ("4A3366", 0.0), "cute_smile": ("C9A8F0", 0.0),
        "cute_hl": ("FFFFFF", 4.0),
    },
}

def part_key(suffix):
    for k in ("cute_innerear", "cute_blush", "cute_smile", "cute_tail"):
        if suffix.startswith(k): return k
    if suffix.startswith("cute_hl"): return "cute_hl"
    return suffix

def new_mat(name, hexcol, emit, rough=0.5):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    n = m.node_tree.nodes.get("Principled BSDF")
    n.inputs["Base Color"].default_value = hexc(hexcol)
    n.inputs["Roughness"].default_value = rough
    if "Emission Color" in n.inputs:
        n.inputs["Emission Color"].default_value = hexc(hexcol)
        n.inputs["Emission Strength"].default_value = emit
    m.diffuse_color = hexc(hexcol)
    return m

def mesh_obj(name, bm, parent, loc, mat, rot=(0, 0, 0), scale=(1, 1, 1)):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    for p in me.polygons: p.use_smooth = True
    o = bpy.data.objects.new(name, me)
    o.parent = parent
    o.location = loc; o.rotation_euler = rot; o.scale = scale
    me.materials.append(mat)
    return o

def sphere(r, seg=12, rings=6):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=r)
    return bm

def cleanup():
    """Alte Teile der drei Pets entfernen (Skript ist wiederholbar)."""
    for o in list(bpy.data.objects):
        if o.name.startswith(("Pet_Genesis", "Pet_Infinity", "Pet_Shade", "Pet_Ascendant")): bpy.data.objects.remove(o)
    for m in list(bpy.data.meshes):
        if m.users == 0: bpy.data.meshes.remove(m)
    for m in list(bpy.data.materials):
        if m.users == 0 and m.name.startswith(("P_gen", "P_inf", "P_sha", "P_asc")): bpy.data.materials.remove(m)

def build():
    cleanup()
    # eigene Szene, bestehende Szenen bleiben unberuehrt
    sc = bpy.data.scenes.get("W1_PETS") or bpy.data.scenes.new("W1_PETS")
    col = sc.collection
    # Vorlage (Omega) anhaengen
    with bpy.data.libraries.load(SRC, link=False) as (src, dst):
        dst.objects = [o for o in src.objects if o.startswith("Pet_Omega_") and "_acc_" not in o]
    tmpl = [o for o in dst.objects if o]
    made = {}
    for idx, (pet, colors) in enumerate(PETS.items()):
        root = bpy.data.objects.new("Pet_" + pet, None)
        root.location = (idx * 5.0, 0, 0)
        col.objects.link(root)
        made[pet] = root
        for t in tmpl:
            suffix = t.name[len("Pet_Omega_"):]
            if suffix == "cute_tail": continue
            o = t.copy(); o.data = t.data.copy()
            o.name = "Pet_%s_%s" % (pet, suffix)
            o.parent = root
            key = part_key(suffix)
            hx, em = colors[key]
            o.data.materials.clear()
            o.data.materials.append(new_mat("P_%s_%s" % (pet[:3].lower(), suffix), hx, em, 0.5))
            col.objects.link(o)
        # kleiner Schwanz (Mutationen faerben "_cute_tail" mit)
        bm = sphere(0.3, 10, 6)
        hx, em = colors["cute_tail"]
        tail = mesh_obj("Pet_%s_cute_tail" % pet, bm, root, (0, 0.8, -0.45), new_mat("P_%s_cute_tail" % pet[:3].lower(), hx, em))
        col.objects.link(tail)
    for t in tmpl: bpy.data.objects.remove(t)
    return sc, made

def acc_genesis(root, col):
    # Eierschale als Kappe: Halbkugel mit Zackenrand, dazu 3 leuchtende Samen und ein duenner Gold-Ring
    bm = sphere(0.62, 16, 8)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < -0.02], context="VERTS")
    zig = [v for v in bm.verts if abs(v.co.z) <= 0.05]
    zig.sort(key=lambda v: math.atan2(v.co.y, v.co.x))
    for i, v in enumerate(zig):
        v.co.z = -0.02 + (0.22 if i % 2 == 0 else -0.12)
    bm.verts.ensure_lookup_table()
    shell = mesh_obj("Pet_Genesis_acc_shell", bm, root, (0, 0.0, 0.84), new_mat("P_gen_shell", "FAF6EC", 0.0, 0.6), scale=(1.0, 0.98, 0.95))
    col.objects.link(shell)
    for i, ang in enumerate((20, 140, 260)):
        a = math.radians(ang)
        s = mesh_obj("Pet_Genesis_acc_seed%d" % i, sphere(0.11, 8, 4), root, (math.cos(a) * 1.15, math.sin(a) * 1.15, 0.95 + 0.18 * i),
                     new_mat("P_gen_seed%d" % i, "FFD86B", 2.0, 0.3))
        col.objects.link(s)
    bm = bmesh.new()
    bmesh.ops.create_circle(bm, cap_ends=False, radius=0.5, segments=18)
    ring = mesh_obj("Pet_Genesis_acc_ring", bm, root, (0, 0, 1.55), new_mat("P_gen_ring", "FFD86B", 1.5, 0.3))
    # duenner Ring: Kreis extrudieren zu Band
    me = ring.data; bm = bmesh.new(); bm.from_mesh(me)
    ext = bmesh.ops.extrude_edge_only(bm, edges=bm.edges[:])
    for v in [e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)]: v.co.z += 0.06
    bm.to_mesh(me); bm.free()
    col.objects.link(ring)

def acc_infinity(root, col):
    # liegende Acht (Lemniskate) als Roehre, schwebt ueber dem Kopf + zwei Stern-Splitter in den Schleifen
    steps, sides, R, r = 36, 5, 0.85, 0.1
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        d = 1 + math.sin(t) ** 2
        pts.append(Vector((R * math.cos(t) / d * 1.6, R * math.sin(t) * math.cos(t) / d * 1.6, 0.0)))
    bm = bmesh.new()
    rings_v = []
    for i, p in enumerate(pts):
        nxt = pts[(i + 1) % steps] - pts[i - 1]
        tangent = nxt.normalized()
        side = tangent.cross(Vector((0, 0, 1))).normalized()
        up = Vector((0, 0, 1))
        ring = []
        for k in range(sides):
            a = 2 * math.pi * k / sides
            ring.append(bm.verts.new(p + side * math.cos(a) * r + up * math.sin(a) * r))
        rings_v.append(ring)
    for i in range(steps):
        a, b = rings_v[i], rings_v[(i + 1) % steps]
        for k in range(sides):
            bm.faces.new((a[k], a[(k + 1) % sides], b[(k + 1) % sides], b[k]))
    o = mesh_obj("Pet_Infinity_acc_loop", bm, root, (0, 0, 1.75), new_mat("P_inf_loop", "B9B2FF", 2.2, 0.25))
    col.objects.link(o)
    for i, sx in enumerate((-0.7, 0.7)):
        bm2 = bmesh.new()
        bmesh.ops.create_icosphere(bm2, subdivisions=1, radius=0.13)
        s = mesh_obj("Pet_Infinity_acc_star%d" % i, bm2, root, (sx, 0, 1.75), new_mat("P_inf_star%d" % i, "FFFFFF", 3.0, 0.2))
        col.objects.link(s)

def acc_shade(root, col):
    # drei Schatten-Wisps (Tropfen) um den Baeren, violett, schwebend
    for i, (ang, h) in enumerate(((35, 1.25), (155, 0.85), (275, 1.45))):
        a = math.radians(ang)
        bm = sphere(0.18, 8, 6)
        s = mesh_obj("Pet_Shade_acc_wisp%d" % i, bm, root, (math.cos(a) * 1.2, math.sin(a) * 1.2, h),
                     new_mat("P_sha_wisp%d" % i, "7A3FD0", 1.0, 0.4), scale=(1.0, 1.0, 1.9))
        col.objects.link(s)

def acc_ascendant(root, col):
    # Heiligenschein (duenner Ring, leuchtet gold) ueber dem Kopf + drei aufsteigende Lichtpunkte (Aqua)
    bm = bmesh.new()
    bmesh.ops.create_circle(bm, cap_ends=False, radius=0.55, segments=20)
    ring = mesh_obj("Pet_Ascendant_acc_halo", bm, root, (0, 0, 1.6), new_mat("P_asc_halo", "FFD86B", 2.0, 0.3))
    me = ring.data; bm = bmesh.new(); bm.from_mesh(me)
    ext = bmesh.ops.extrude_edge_only(bm, edges=bm.edges[:])
    for v in [e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)]: v.co.z += 0.07
    bm.to_mesh(me); bm.free()
    col.objects.link(ring)
    for i, (ang, h, r) in enumerate(((30, 1.0, 0.13), (150, 1.35, 0.10), (265, 0.8, 0.09))):
        a = math.radians(ang)
        orb = mesh_obj("Pet_Ascendant_acc_orb%d" % i, sphere(r, 8, 4), root, (math.cos(a) * 1.2, math.sin(a) * 1.2, h),
                       new_mat("P_asc_orb%d" % i, "9FE8FF", 2.5, 0.3))
        col.objects.link(orb)

def run():
    sc, made = build()
    col = sc.collection
    acc_genesis(made["Genesis"], col)
    acc_infinity(made["Infinity"], col)
    acc_shade(made["Shade"], col)
    acc_ascendant(made["Ascendant"], col)
    return sc, made

if __name__ == "__main__" or True:
    SC, MADE = run()


def export_all():
    """Je Pet eine FBX in Export/ (Wurzel-Empty + alle Teile)."""
    sc = bpy.data.scenes["W1_PETS"]
    prev = bpy.context.window.scene
    bpy.context.window.scene = sc
    out = {}
    for pet in PETS:
        root = bpy.data.objects["Pet_" + pet]
        kids = [o for o in bpy.data.objects if o.parent == root]
        for o in bpy.context.view_layer.objects: o.select_set(False)
        old = root.location.copy(); root.location = (0, 0, 0)   # Ursprung = Mitte des Baeren
        root.select_set(True)
        for o in kids: o.select_set(True)
        bpy.context.view_layer.objects.active = root
        path = os.path.join(OUT, "Pet_%s.fbx" % pet)
        bpy.ops.export_scene.fbx(filepath=path, use_selection=True, object_types={"EMPTY", "MESH"},
                                 add_leaf_bones=False, bake_anim=False, path_mode="AUTO", axis_forward="-Z", axis_up="Y")
        root.location = old
        out[pet] = os.path.getsize(path)
    bpy.context.window.scene = prev
    return out
