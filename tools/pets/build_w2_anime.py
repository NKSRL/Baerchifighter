# build_w2_anime.py - Welt 2 (21.10.2026): Anime-Ei, Basis-Satz mit 4 Baerchis (eigene Archetypen, KEINE Original-Kostueme/Logos/Namen)
# Laeuft IN Blender (bpy): exec(open(<pfad>).read())
# Gleiche Konventionen wie build_w1_pets.py: Koerper aus Pet_Omega (baerchi_varianten.blend), je Teil ein eigenes flaches Material,
# Teile-Endungen _body/_ears/_feet/_cute_tail (Mutationen faerben die), Gesicht -Y (FBX-Export -Z), <= 30 Teile.
# Rechtlich: erkennbar am Typ (Strohhut-Pirat, Ninja mit Stirnband, Stachelhaar-Kaempfer, Karo-Umhang-Jaeger), aber eigene Farben,
# eigene Symbole, eigene Namen. Keine Narbe unter dem Auge, kein Blatt-Symbol, keine Kanji, keine Originalfarbkombination.
import bpy, bmesh, math, os
from mathutils import Vector, Matrix

SRC = r"C:\Users\admin\Documents\Claude Downloads\RBL\baerchi_varianten.blend"
OUT = r"C:\Users\admin\Documents\Claude Downloads\RBL\Export"
PFX = "Anime_"

def hexc(h):
    h = h.lstrip("#"); r, g, b = (int(h[i:i+2], 16) / 255 for i in (0, 2, 4))
    f = lambda c: c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return (f(r), f(g), f(b), 1.0)

def fur(body, ears, feet, toes, muzzle, nose, eyes, inner, blush, smile):
    return {"body": (body, 0.0), "ears": (ears, 0.0), "feet": (feet, 0.0), "toes": (toes, 0.0), "muzzle": (muzzle, 0.0),
            "nose": (nose, 0.0), "eyes": (eyes, 0.0), "cute_tail": (body, 0.0), "cute_innerear": (inner, 0.0),
            "cute_blush": (blush, 0.0), "cute_smile": (smile, 0.0), "cute_hl": ("FFFFFF", 4.0)}

PETS = {
    "Pirat":   fur("B9814B", "A9723F", "9A6535", "E8C9A0", "F3DDBA", "3A2410", "2A1A0E", "E8A58A", "F2A07A", "6A3A1E"),
    "Ninja":   fur("F2923A", "E5812B", "D8741F", "FFE0B8", "FFE9CC", "5A2A0A", "1E2A55", "FFC48A", "FF9A6A", "7A3A12"),
    "Krieger": fur("C89A66", "B98A58", "A97A4A", "F0D6B0", "F6E4C8", "3A2410", "1A1A22", "E8B090", "F0A07A", "6A3A1E"),
    "Jaeger":  fur("8A6A58", "7A5A4A", "6A4A3C", "D8BFA8", "E8D2BC", "2A1A12", "7A1F2A", "D8A090", "E8908A", "4A2A1E"),
}

def part_key(s):
    for k in ("cute_innerear", "cute_blush", "cute_smile", "cute_tail"):
        if s.startswith(k): return k
    if s.startswith("cute_hl"): return "cute_hl"
    return s

def new_mat(name, hexcol, emit=0.0, rough=0.55):
    m = bpy.data.materials.new(name); m.use_nodes = True
    n = m.node_tree.nodes.get("Principled BSDF")
    n.inputs["Base Color"].default_value = hexc(hexcol); n.inputs["Roughness"].default_value = rough
    if "Emission Color" in n.inputs:
        n.inputs["Emission Color"].default_value = hexc(hexcol); n.inputs["Emission Strength"].default_value = emit
    m.diffuse_color = hexc(hexcol)
    return m

def mesh_obj(name, bm, parent, loc, mat, rot=(0, 0, 0), scale=(1, 1, 1), smooth=True):
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    for p in me.polygons: p.use_smooth = smooth
    o = bpy.data.objects.new(name, me); o.parent = parent
    o.location = loc; o.rotation_euler = tuple(math.radians(a) for a in rot); o.scale = scale
    me.materials.append(mat)
    return o

def sphere(r, seg=12, rings=6):
    bm = bmesh.new(); bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=r); return bm

def box(sx, sy, sz):
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts: v.co.x *= sx; v.co.y *= sy; v.co.z *= sz
    return bm

def cyl(r1, r2, h, seg=12, caps=True):
    bm = bmesh.new(); bmesh.ops.create_cone(bm, cap_ends=caps, segments=seg, radius1=r1, radius2=r2, depth=h); return bm

def band(rx, ry, h, t=0.06, seg=24):
    """Elliptisches Band (z.B. Stirnband, Guertel) mit Dicke t."""
    bm = cyl(1.0, 1.0, h, seg, caps=False)
    for v in bm.verts: v.co.x *= rx; v.co.y *= ry
    bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=t)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])   # sonst zeigen die Aussenwaende nach innen (Roblox culled sie)
    return bm

def add_cone(bm, base, tip, r, seg=6):
    """Kegel von base nach tip (Weltkoordinaten im Wurzel-Raum) in ein vorhandenes bmesh."""
    d = Vector(tip) - Vector(base); h = d.length
    rot = d.to_track_quat('Z', 'Y').to_matrix().to_4x4()
    m = Matrix.Translation((Vector(base) + Vector(tip)) / 2) @ rot
    bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r, radius2=0.0, depth=h, matrix=m)

def cleanup():
    for o in list(bpy.data.objects):
        if o.name.startswith(PFX): bpy.data.objects.remove(o)
    for m in list(bpy.data.meshes):
        if m.users == 0: bpy.data.meshes.remove(m)
    for m in list(bpy.data.materials):
        if m.users == 0 and m.name.startswith("A_"): bpy.data.materials.remove(m)

def build_bodies():
    cleanup()
    sc = bpy.data.scenes.get("W2_ANIME") or bpy.data.scenes.new("W2_ANIME")
    col = sc.collection
    with bpy.data.libraries.load(SRC, link=False) as (src, dst):
        dst.objects = [o for o in src.objects if o.startswith("Pet_Omega_") and "_acc_" not in o]
    tmpl = [o for o in dst.objects if o]
    made = {}
    for idx, (pet, colors) in enumerate(PETS.items()):
        root = bpy.data.objects.new(PFX + pet, None); root.location = (idx * 5.0, 0, 0)
        col.objects.link(root); made[pet] = root
        for t in tmpl:
            suffix = t.name[len("Pet_Omega_"):]
            if suffix == "cute_tail": continue
            o = t.copy(); o.data = t.data.copy(); o.name = "%s%s_%s" % (PFX, pet, suffix); o.parent = root
            hx, em = colors[part_key(suffix)]
            o.data.materials.clear(); o.data.materials.append(new_mat("A_%s_%s" % (pet[:3].lower(), suffix), hx, em))
            col.objects.link(o)
        hx, em = colors["cute_tail"]
        col.objects.link(mesh_obj("%s%s_cute_tail" % (PFX, pet), sphere(0.3, 10, 6), root, (0, 0.8, -0.45), new_mat("A_%s_cute_tail" % pet[:3].lower(), hx, em)))
    for t in tmpl: bpy.data.objects.remove(t)
    return sc, made

def acc(root, col, pet, name, bm, loc, hx, emit=0.0, rot=(0, 0, 0), scale=(1, 1, 1), smooth=True, rough=0.55):
    col.objects.link(mesh_obj("%s%s_acc_%s" % (PFX, pet, name), bm, root, loc, new_mat("A_%s_%s" % (pet[:3].lower(), name), hx, emit, rough), rot, scale, smooth))

def rband(wx, wy, h, t=0.05):
    """Rechteckiges Band (der Koerper ist ein abgerundeter Block, elliptische Baender verschwinden darin). Aussenmasse wx*wy."""
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts: v.co.x *= wx; v.co.y *= wy; v.co.z *= h
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if abs(f.normal.z) > 0.5], context="FACES")
    bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=-t)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return bm

BW, BD = 2.25, 1.77   # Koerperbreite/-tiefe + Luft, damit Baender sichtbar ausserhalb liegen

def acc_pirat(r, c):   # Strohhut mit TUERKISEM Band (nicht rot), rotes Hemd, Gummi-Arm mit Faust
    acc(r, c, "Pirat", "hat_crown", sphere(0.52, 14, 7), (0, -0.05, 1.0), "F0CF6E", scale=(1.0, 1.0, 0.65))
    acc(r, c, "Pirat", "hat_brim", cyl(1.08, 1.08, 0.07, 28), (0, -0.05, 0.93), "E5BE55", rot=(-5, 0, 0))
    acc(r, c, "Pirat", "hat_band", band(0.54, 0.54, 0.17, 0.05, 20), (0, -0.05, 0.99), "1FA89A")
    acc(r, c, "Pirat", "shirt", rband(BW, BD, 0.3), (0, 0, -0.76), "D83A34")   # rotes Hemd (Wunsch 21.10.)
    acc(r, c, "Pirat", "shirt_back", box(1.9, 0.07, 1.2), (0, 0.93, -0.3), "D83A34", smooth=False)   # Ruecken, damit es von hinten wie ein Hemd aussieht
    acc(r, c, "Pirat", "gum_arm", cyl(0.17, 0.17, 1.5, 8), (1.55, -0.85, -0.15), "B9814B", rot=(-90, 0, 38))
    acc(r, c, "Pirat", "gum_fist", sphere(0.45, 10, 6), (2.05, -1.5, -0.15), "C28D55")

def acc_ninja(r, c):   # blaues Stirnband mit Metallplatte + eigenem Wirbel-Symbol, Schnurrhaar-Wangen, Schriftrolle, Schal
    acc(r, c, "Ninja", "headband", rband(BW, BD, 0.26), (0, 0, 0.58), "2F5FD0")
    acc(r, c, "Ninja", "plate", box(0.78, 0.07, 0.3), (0, -0.93, 0.58), "C8D0DC", rough=0.3)
    acc(r, c, "Ninja", "swirl", band(0.13, 0.13, 0.05, 0.035, 12), (0, -0.98, 0.58), "27324A", rot=(90, 0, 0))
    for side, sx in (("L", -1), ("R", 1)):
        bm = bmesh.new()
        for dz in (-0.11, 0.0, 0.11):
            b = box(0.4, 0.03, 0.035)
            for v in b.verts: v.co.z += dz
            tmp = bpy.data.meshes.new("t"); b.to_mesh(tmp); b.free(); bm.from_mesh(tmp); bpy.data.meshes.remove(tmp)
        acc(r, c, "Ninja", "whisker" + side, bm, (sx * 0.88, -0.9, -0.2), "3A2410", rot=(0, 0, sx * -14))
    acc(r, c, "Ninja", "scarf", rband(BW, BD, 0.28), (0, 0, -0.77), "E8E2D0")
    acc(r, c, "Ninja", "scroll", cyl(0.14, 0.14, 1.1, 10), (0, 0.98, -0.1), "E9DDB8", rot=(0, 90, 0))
    acc(r, c, "Ninja", "scroll_cap", cyl(0.16, 0.16, 0.12, 10), (0.55, 0.98, -0.1), "C94A3A", rot=(0, 90, 0))

def acc_krieger(r, c):  # Stachelhaar (1 Teil), Kampfanzug-Band in Rot-Orange, blaue Schaerpe
    bm = bmesh.new()
    for base, tip, rr in (((0, -0.15, 0.85), (0, -0.2, 1.95), 0.3), ((-0.45, -0.1, 0.8), (-0.95, -0.25, 1.7), 0.26),
                          ((0.45, -0.1, 0.8), (0.95, -0.25, 1.7), 0.26), ((-0.25, 0.2, 0.8), (-0.55, 0.45, 1.65), 0.24),
                          ((0.25, 0.2, 0.8), (0.55, 0.45, 1.65), 0.24), ((0, 0.4, 0.75), (0, 0.8, 1.5), 0.22)):
        add_cone(bm, base, tip, rr, 6)
    acc(r, c, "Krieger", "hair", bm, (0, 0, 0), "17171F", smooth=False)
    acc(r, c, "Krieger", "gi", rband(BW, BD, 0.32), (0, 0, -0.76), "E4572A")
    acc(r, c, "Krieger", "sash", rband(BW + 0.06, BD + 0.06, 0.1), (0, 0, -0.86), "2B50B0")

def acc_jaeger(r, c):   # Karo-Umhang (gruen/schwarz), Schwert auf dem Ruecken, Stirn-Mal in Rot, schwarzer Guertel
    acc(r, c, "Jaeger", "cape", box(1.9, 0.08, 1.5), (0, 0.98, -0.1), "15201A", smooth=False)
    bm = bmesh.new()
    for ix in range(3):
        for iz in range(4):
            if (ix + iz) % 2 == 0:
                b = box(0.62, 0.02, 0.36)
                for v in b.verts: v.co.x += (ix - 1) * 0.62; v.co.z += (iz - 1.5) * 0.36
                tmp = bpy.data.meshes.new("t"); b.to_mesh(tmp); b.free(); bm.from_mesh(tmp); bpy.data.meshes.remove(tmp)
    acc(r, c, "Jaeger", "checks", bm, (0, 1.04, -0.1), "2E9A63", smooth=False)
    acc(r, c, "Jaeger", "blade", box(0.08, 0.04, 1.7), (0, 1.12, 0.0), "AEB8C6", rot=(0, 38, 0), rough=0.3, smooth=False)
    acc(r, c, "Jaeger", "guard", cyl(0.2, 0.2, 0.04, 12), (-0.36, 1.12, -0.5), "D6A93C", rot=(90, 0, 0), rough=0.35)
    acc(r, c, "Jaeger", "hilt", box(0.1, 0.07, 0.5), (-0.48, 1.12, -0.74), "1B1B22", rot=(0, 38, 0), smooth=False)
    acc(r, c, "Jaeger", "scar", box(0.14, 0.03, 0.34), (-0.4, -0.88, 0.55), "D0383A", smooth=False)
    acc(r, c, "Jaeger", "belt", rband(BW, BD, 0.3), (0, 0, -0.77), "1B1B22")

def run():
    sc, made = build_bodies(); col = sc.collection
    acc_pirat(made["Pirat"], col); acc_ninja(made["Ninja"], col); acc_krieger(made["Krieger"], col); acc_jaeger(made["Jaeger"], col)
    return sc, made

SC, MADE = run()

def export_all():
    sc = bpy.data.scenes["W2_ANIME"]; prev = bpy.context.window.scene; bpy.context.window.scene = sc
    out = {}
    for pet in PETS:
        root = bpy.data.objects[PFX + pet]; kids = [o for o in bpy.data.objects if o.parent == root]
        for o in bpy.context.view_layer.objects: o.select_set(False)
        old = root.location.copy(); root.location = (0, 0, 0); root.select_set(True)
        for o in kids: o.select_set(True)
        bpy.context.view_layer.objects.active = root
        path = os.path.join(OUT, PFX + pet + ".fbx")
        bpy.ops.export_scene.fbx(filepath=path, use_selection=True, object_types={"EMPTY", "MESH"}, add_leaf_bones=False,
                                 bake_anim=False, path_mode="AUTO", axis_forward="-Z", axis_up="Y")
        root.location = old; out[pet] = os.path.getsize(path)
    bpy.context.window.scene = prev
    return out
