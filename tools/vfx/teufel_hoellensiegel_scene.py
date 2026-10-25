# Einzige Zustaendigkeit: baut den Blender-Prototyp der Teufel-Show "Hoellensiegel"
# (Meshes, Materialien, Animation, Kamera) in der offenen .blend-Datei neu auf.
# Vorbild: Video vom 22.10. (Siegel -> Sternbruch -> Rauch/Mal -> schwarze Sonne
# -> Blitze -> Feuersaeule mit Kronen-Schockwelle -> Flammenfaecher).
# Umsetzung fuer den Kampf: Aufladen am eigenen Baerchi (S), Einschlag am Gegner (T).
# 1 Blender-Einheit = 1 Stud, Z oben. 30 fps, Show 5,6 s.
# Aufruf in Blender: exec(open(<diese Datei>).read(), {"__name__": "scene"})
import bpy, bmesh, math, random
from mathutils import Vector, Euler

ROOT = r"C:\Users\admin\Documents\Claude Downloads\RBL"
TEXPY = ROOT + r"\tools\vfx\teufel_hoellensiegel_tex.py"
FPS = 30
S = Vector((-9, 0, 0))   # eigener Baerchi (MapConfig.FIGHT_SPACING = 9)
T = Vector((9, 0, 0))    # Gegner
CAM_POS = Vector((0, -26, 12.5)); CAM_AIM = Vector((0, 0, 5.0))
rnd = random.Random(666)

def F(t):
    return 1 + round(t * FPS)

# ---------------------------------------------------------------- Aufraeumen
def reset():
    col = bpy.data.collections.get("HS_VFX")
    if col:
        for o in list(col.objects):
            bpy.data.objects.remove(o, do_unlink=True)
    else:
        col = bpy.data.collections.new("HS_VFX"); bpy.context.scene.collection.children.link(col)
    for m in list(bpy.data.materials):
        if m.name.startswith("HS_") and m.users == 0:
            bpy.data.materials.remove(m)
    for me in list(bpy.data.meshes):
        if me.name.startswith("HS_") and me.users == 0:
            bpy.data.meshes.remove(me)
    return col

COL = None

def link(o):
    COL.objects.link(o); return o

# ---------------------------------------------------------------- Materialien
def make_mat(name, img=None, color=(1, 1, 1), strength=2.0, mode="ADD", fresnel=0.0, scroll=False, urep=1.0, vfade=0.0, vaxis="Z"):
    m = bpy.data.materials.new("HS_" + name)
    m.use_nodes = True
    nt = m.node_tree; N = nt.nodes; L = nt.links
    N.clear()
    out = N.new("ShaderNodeOutputMaterial")
    fade = N.new("ShaderNodeValue"); fade.name = "Fade"; fade.outputs[0].default_value = 1.0
    if img:
        tex = N.new("ShaderNodeTexImage"); tex.image = bpy.data.images[img]
        tc = N.new("ShaderNodeTexCoord"); mp = N.new("ShaderNodeMapping"); mp.name = "Scroll"
        mp.inputs["Scale"].default_value = (urep, 1, 1)
        L.new(tc.outputs["UV"], mp.inputs["Vector"]); L.new(mp.outputs["Vector"], tex.inputs["Vector"])
        mul = N.new("ShaderNodeVectorMath"); mul.operation = "MULTIPLY"
        L.new(tex.outputs["Color"], mul.inputs[0]); mul.inputs[1].default_value = color
        col_out = mul.outputs[0]; a_out = tex.outputs["Alpha"]
    else:
        rgb = N.new("ShaderNodeRGB"); rgb.outputs[0].default_value = (*color, 1)
        one = N.new("ShaderNodeValue"); one.outputs[0].default_value = 1.0
        col_out = rgb.outputs[0]; a_out = one.outputs[0]
    am = N.new("ShaderNodeMath"); am.operation = "MULTIPLY"
    L.new(a_out, am.inputs[0]); L.new(fade.outputs[0], am.inputs[1]); alpha = am.outputs[0]
    if fresnel > 0:
        lw = N.new("ShaderNodeLayerWeight"); lw.inputs["Blend"].default_value = 0.35
        pw = N.new("ShaderNodeMath"); pw.operation = "POWER"; pw.inputs[1].default_value = fresnel
        L.new(lw.outputs["Facing"], pw.inputs[0])
        am2 = N.new("ShaderNodeMath"); am2.operation = "MULTIPLY"
        L.new(alpha, am2.inputs[0]); L.new(pw.outputs[0], am2.inputs[1]); alpha = am2.outputs[0]
    if vfade > 0:
        # Ausblenden nach oben ueber die Objekt-Hoehe (Generated Z), unabhaengig vom Textur-Scroll
        gc = N.new("ShaderNodeTexCoord"); sep = N.new("ShaderNodeSeparateXYZ"); L.new(gc.outputs["Generated"], sep.inputs[0])
        mr = N.new("ShaderNodeMapRange"); mr.interpolation_type = "SMOOTHSTEP"
        mr.inputs["From Min"].default_value = 1.0 - vfade; mr.inputs["From Max"].default_value = 1.0
        mr.inputs["To Min"].default_value = 1.0; mr.inputs["To Max"].default_value = 0.0
        L.new(sep.outputs[vaxis], mr.inputs["Value"])
        am3 = N.new("ShaderNodeMath"); am3.operation = "MULTIPLY"
        L.new(alpha, am3.inputs[0]); L.new(mr.outputs["Result"], am3.inputs[1]); alpha = am3.outputs[0]
    em = N.new("ShaderNodeEmission"); L.new(col_out, em.inputs["Color"])
    tr = N.new("ShaderNodeBsdfTransparent")
    if mode == "ADD":
        sm = N.new("ShaderNodeMath"); sm.operation = "MULTIPLY"; sm.inputs[1].default_value = strength
        L.new(alpha, sm.inputs[0]); L.new(sm.outputs[0], em.inputs["Strength"])
        ad = N.new("ShaderNodeAddShader"); L.new(tr.outputs[0], ad.inputs[0]); L.new(em.outputs[0], ad.inputs[1])
        L.new(ad.outputs[0], out.inputs["Surface"])
    else:  # ALPHA: deckend gemischt (Rauch, schwarze Sonne, Blitze)
        em.inputs["Strength"].default_value = strength
        mx = N.new("ShaderNodeMixShader"); L.new(alpha, mx.inputs[0])
        L.new(tr.outputs[0], mx.inputs[1]); L.new(em.outputs[0], mx.inputs[2])
        L.new(mx.outputs[0], out.inputs["Surface"])
    m.surface_render_method = "BLENDED"
    m.use_backface_culling = False
    return m

def mat(o, *a, **k):
    m = make_mat(o.name, *a, **k)
    o.data.materials.clear(); o.data.materials.append(m)
    return m

def fade(o, t, v):
    n = o.active_material.node_tree.nodes["Fade"]
    n.outputs[0].default_value = v; n.outputs[0].keyframe_insert("default_value", frame=F(t))

def fades(o, pairs):
    for t, v in pairs:
        fade(o, t, v)

def scroll(o, t0, t1, dv):
    n = o.active_material.node_tree.nodes["Scroll"]
    n.inputs["Location"].default_value = (0, 0, 0); n.inputs["Location"].keyframe_insert("default_value", frame=F(t0))
    n.inputs["Location"].default_value = (0, dv, 0); n.inputs["Location"].keyframe_insert("default_value", frame=F(t1))

def key(o, path, t, v):
    setattr(o, path, v); o.keyframe_insert(path, frame=F(t))

def keys(o, path, pairs):
    for t, v in pairs:
        key(o, path, t, v)

# ---------------------------------------------------------------- Mesh-Bausteine
def new_obj(name, bm):
    me = bpy.data.meshes.new("HS_" + name); bm.to_mesh(me); bm.free()
    return link(bpy.data.objects.new(name, me))

def disc(name, r, seg=32):
    bm = bmesh.new(); uv = bm.loops.layers.uv.verify()
    vs = [bm.verts.new((r * math.cos(a), r * math.sin(a), 0)) for a in [2 * math.pi * i / seg for i in range(seg)]]
    f = bm.faces.new(vs)
    for l in f.loops:
        l[uv].uv = (l.vert.co.x / r * 0.5 + 0.5, l.vert.co.y / r * 0.5 + 0.5)
    return new_obj(name, bm)

def quad(name, w, h, pivot="center"):
    bm = bmesh.new(); uv = bm.loops.layers.uv.verify()
    x0 = -w / 2; y0 = -h / 2 if pivot == "center" else 0
    vs = [bm.verts.new(p) for p in [(x0, y0, 0), (x0 + w, y0, 0), (x0 + w, y0 + h, 0), (x0, y0 + h, 0)]]
    f = bm.faces.new(vs)
    for l, u in zip(f.loops, [(0, 0), (1, 0), (1, 1), (0, 1)]):
        l[uv].uv = u
    return new_obj(name, bm)

def torus(name, R, r, seg=40, rseg=8):
    bm = bmesh.new(); uv = bm.loops.layers.uv.verify(); grid = []
    for i in range(seg):
        a = 2 * math.pi * i / seg; row = []
        for j in range(rseg):
            b = 2 * math.pi * j / rseg
            row.append(bm.verts.new(((R + r * math.cos(b)) * math.cos(a), (R + r * math.cos(b)) * math.sin(a), r * math.sin(b))))
        grid.append(row)
    for i in range(seg):
        for j in range(rseg):
            bm.faces.new([grid[i][j], grid[(i + 1) % seg][j], grid[(i + 1) % seg][(j + 1) % rseg], grid[i][(j + 1) % rseg]])
    return new_obj(name, bm)

def wall(name, radius, hfun, seg=48, z0=0.0, urep=1.0, flare=1.0):
    # offener Zylindermantel, Oberkante hfun(theta); UV u rundherum, v hoch
    bm = bmesh.new(); uv = bm.loops.layers.uv.verify(); bot = []; top = []
    for i in range(seg + 1):
        a = 2 * math.pi * i / seg
        c, s = math.cos(a), math.sin(a)
        bot.append(bm.verts.new((radius * c, radius * s, z0)))
        top.append(bm.verts.new((radius * flare * c, radius * flare * s, z0 + hfun(a))))
    for i in range(seg):
        f = bm.faces.new([bot[i], bot[i + 1], top[i + 1], top[i]])
        for l, u in zip(f.loops, [(i / seg, 0), ((i + 1) / seg, 0), ((i + 1) / seg, 1), (i / seg, 1)]):
            l[uv].uv = (u[0] * urep, u[1])
    return new_obj(name, bm)

def arc(name, r, a0, a1, w, seg=28):
    # flaches Band im Bogen (Windhieb): u laeuft den Bogen entlang, v quer
    bm = bmesh.new(); uv = bm.loops.layers.uv.verify(); inn = []; out = []
    for i in range(seg + 1):
        a = a0 + (a1 - a0) * i / seg
        inn.append(bm.verts.new(((r - w / 2) * math.cos(a), (r - w / 2) * math.sin(a), 0)))
        out.append(bm.verts.new(((r + w / 2) * math.cos(a), (r + w / 2) * math.sin(a), 0)))
    for i in range(seg):
        f = bm.faces.new([inn[i], inn[i + 1], out[i + 1], out[i]])
        for l, u in zip(f.loops, [(i / seg, 0), ((i + 1) / seg, 0), ((i + 1) / seg, 1), (i / seg, 1)]):
            l[uv].uv = u
    return new_obj(name, bm)

def blade(name, length, w0, w1):
    # Lichtklinge: schmal an der Wurzel, breit am Ende (Strahl-Textur, Wurzel hell)
    bm = bmesh.new(); uv = bm.loops.layers.uv.verify()
    vs = [bm.verts.new(p) for p in [(0, -w0 / 2, 0), (length, -w1 / 2, 0), (length, w1 / 2, 0), (0, w0 / 2, 0)]]
    f = bm.faces.new(vs)
    for l, u in zip(f.loops, [(0, 0), (1, 0), (1, 1), (0, 1)]):
        l[uv].uv = u
    return new_obj(name, bm)

def spikes(name, count, lmin, lmax, base, zmin, zmax, seed):
    # Sternbruch: duenne dreiseitige Spitzen in alle Richtungen (eher flach)
    r = random.Random(seed); bm = bmesh.new()
    for k in range(count):
        yaw = 2 * math.pi * (k + r.random() * 0.6) / count
        d = Vector((math.cos(yaw), math.sin(yaw), r.uniform(zmin, zmax))).normalized()
        L = r.uniform(lmin, lmax)
        perp = d.cross(Vector((0, 0, 1))).normalized(); perp2 = d.cross(perp).normalized()
        c = d * 0.3
        b = [bm.verts.new(c + (perp * math.cos(q) + perp2 * math.sin(q)) * base) for q in (0, 2.1, 4.2)]
        tip = bm.verts.new(d * L)
        for i in range(3):
            bm.faces.new([b[i], b[(i + 1) % 3], tip])
    return new_obj(name, bm)

def sphere(name, r, hemi=False):
    bm = bmesh.new(); bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=12, radius=r)
    if hemi:
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < -0.01], context="VERTS")
    return new_obj(name, bm)

def billboard(o, cam):
    c = o.constraints.new("TRACK_TO"); c.target = cam; c.track_axis = "TRACK_Z"; c.up_axis = "UP_Y"
    return o

def empty(name, loc):
    e = link(bpy.data.objects.new(name, None)); e.location = loc; return e

# ---------------------------------------------------------------- Buehne
def stage():
    sc = bpy.context.scene
    sc.render.fps = FPS; sc.frame_start = 1; sc.frame_end = F(5.6)
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x = 960; sc.render.resolution_y = 540
    sc.view_settings.view_transform = "Standard"
    try:
        sc.eevee.taa_render_samples = 16
    except Exception:
        pass
    w = bpy.data.worlds.get("HS_World") or bpy.data.worlds.new("HS_World")
    sc.world = w; w.use_nodes = True
    bg = w.node_tree.nodes.get("Background")
    bg.inputs[0].default_value = (0.035, 0.035, 0.04, 1); bg.inputs[1].default_value = 1.0
    cam = bpy.data.objects.get("HS_Cam")
    if not cam:
        cam = bpy.data.objects.new("HS_Cam", bpy.data.cameras.new("HS_Cam")); sc.collection.objects.link(cam)
    cam.data.lens = 30; cam.location = CAM_POS
    cam.rotation_euler = (CAM_AIM - CAM_POS).to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    sun = bpy.data.objects.get("HS_Sun")
    if not sun:
        sun = bpy.data.objects.new("HS_Sun", bpy.data.lights.new("HS_Sun", "SUN")); sc.collection.objects.link(sun)
    sun.data.energy = 2.5; sun.rotation_euler = (math.radians(50), 0, math.radians(30))
    # Boden: dunkles Schachbrett wie die Test-Arena im Video
    g = bpy.data.objects.get("HS_Boden")
    if not g:
        bm = bmesh.new(); bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=80)
        me = bpy.data.meshes.new("HS_Boden_me"); bm.to_mesh(me); bm.free()
        g = bpy.data.objects.new("HS_Boden", me); sc.collection.objects.link(g)
        m = bpy.data.materials.new("HS_Boden_mat"); m.use_nodes = True
        nt = m.node_tree; bsdf = nt.nodes["Principled BSDF"]
        ck = nt.nodes.new("ShaderNodeTexChecker"); ck.inputs["Scale"].default_value = 40
        ck.inputs["Color1"].default_value = (0.05, 0.05, 0.055, 1); ck.inputs["Color2"].default_value = (0.08, 0.08, 0.085, 1)
        nt.links.new(ck.outputs["Color"], bsdf.inputs["Base Color"]); bsdf.inputs["Roughness"].default_value = 0.8
        me.materials.append(m)
    return cam

def import_bear(path, name, loc, yaw):
    o = bpy.data.objects.get(name)
    if not o:
        before = set(bpy.data.objects)
        bpy.ops.import_scene.fbx(filepath=path)
        new = [x for x in bpy.data.objects if x not in before]
        o = [x for x in new if x.parent is None][0]; o.name = name
    o.location = loc + Vector((0, 0, 1.32)); o.rotation_euler = (0, 0, math.radians(yaw))
    return o

# ---------------------------------------------------------------- Phase 1: Siegel (0,00-0,75 s) am eigenen Baerchi
def phase_siegel(cam):
    ring = disc("HS_SiegelRing", 7.5); ring.location = S + Vector((0, 0, 0.06))
    mat(ring, "Teufel_SiegelRing", strength=4.0)
    dunst = disc("HS_SiegelDunst", 10); dunst.location = S + Vector((0, 0, 0.03)); mat(dunst, "Teufel_Glut", (1, 0.5, 0.5), 1.2)
    keys(dunst, "scale", [(0, (0.4,) * 3), (0.2, (1,) * 3)]); fades(dunst, [(0, 0), (0.1, 1), (0.6, 1), (0.85, 0)])
    keys(ring, "scale", [(0, (0.3,) * 3), (0.12, (1.05,) * 3), (0.2, (1,) * 3), (0.55, (1,) * 3), (0.70, (0.45,) * 3)])
    keys(ring, "rotation_euler", [(0, (0, 0, 0)), (0.72, (0, 0, -2.2))])
    fades(ring, [(0, 0), (0.05, 1), (0.6, 1), (0.74, 0)])
    # violetter Wulst + heller Innenring
    for nm, R, r, colr, st, z in [("HS_Wulst", 2.8, 0.42, (0.5, 0.1, 1.0), 1.0, 0.5), ("HS_WulstInnen", 1.8, 0.16, (1.0, 0.4, 0.8), 1.0, 0.7)]:
        t = torus(nm, R, r, 40, 8); t.location = S + Vector((0, 0, z)); mat(t, None, colr, st)
        keys(t, "scale", [(0, (0.2, 0.2, 0.2)), (0.1, (1.1, 1.1, 1.1)), (0.2, (1, 1, 1)), (0.55, (1, 1, 1)), (0.70, (0.55, 0.55, 0.8))])
        keys(t, "rotation_euler", [(0, (0.12, 0, 0)), (0.3, (-0.08, 0.1, 1.5)), (0.7, (0.1, -0.05, 3.2))])
        fades(t, [(0, 0), (0.05, 1), (0.62, 1), (0.76, 0)])
    # Orbit-Linien (weiss/gruen), schnell kreisend und gekippt
    for i, (R, colr, tilt) in enumerate([(4.3, (1, 1, 1), (0.22, 0.05)), (5.0, (0.55, 1, 0.65), (-0.18, 0.1)), (3.6, (1, 0.9, 0.95), (0.1, -0.2))]):
        o = torus("HS_Orbit%d" % i, R, 0.045, 48, 4); o.location = S + Vector((0, 0, 0.9 + 0.3 * i))
        o.scale = (1, 0.82, 1); mat(o, None, colr, 5.0 if colr[1] > 0.95 and colr[0] > 0.95 else 2.0)
        keys(o, "rotation_euler", [(0, (tilt[0], tilt[1], 0)), (0.75, (tilt[0], tilt[1], (-1) ** i * 7.0))])
        fades(o, [(0, 0), (0.08, 1), (0.6, 1), (0.66, 0.4), (0.8, 0)])
    # Lichtklingen: schiessen radial raus und rotieren mit der Gruppe
    rot = empty("HS_KlingenDreh", S + Vector((0, 0, 0.9)))
    keys(rot, "rotation_euler", [(0, (0, 0, 0)), (0.7, (0, 0, 2 * math.pi * 1.15))])
    colors = [(0.45, 1, 0.55), (1, 0.62, 0.42), (0.78, 0.62, 1), (1, 0.7, 0.5), (0.5, 1, 0.6), (1, 0.55, 0.8)]
    for i, c in enumerate(colors):
        b = blade("HS_Klinge%d" % i, 15, 0.25, 2.4); b.parent = rot
        b.rotation_euler = (math.radians(90), -math.radians(rnd.uniform(8, 32)), 2 * math.pi * i / 6 + rnd.uniform(-0.3, 0.3))
        mat(b, "Teufel_Strahl", c, 1.8)
        t0 = 0.02 + 0.06 * i; t1 = 0.45 + 0.04 * i
        keys(b, "scale", [(t0, (0.2, 1, 1)), (t0 + 0.08, (1, 1, 1)), (t1, (0.85, 1, 1)), (t1 + 0.1, (0.3, 0.6, 1))])
        fades(b, [(t0, 0), (t0 + 0.04, 1), (t1, 1), (t1 + 0.1, 0)])
    # Funken (kleine Wuerfel) kreisen mit
    for i in range(10):
        a = rnd.uniform(0, 2 * math.pi); rr = rnd.uniform(2.0, 4.8)
        bm = bmesh.new(); bmesh.ops.create_cube(bm, size=0.18)
        o = new_obj("HS_Funke%d" % i, bm); o.parent = rot
        o.location = (rr * math.cos(a), rr * math.sin(a), rnd.uniform(-0.3, 2.2))
        mat(o, None, rnd.choice([(1, 0.85, 0.2), (1, 0.5, 0.1), (0.6, 1, 0.5)]), 6.0)
        fades(o, [(0, 0), (0.1, 1), (0.6, 1), (0.72, 0)])
    # gestapelte Feuerscheiben und die grosse Himmelsscheibe
    for i, (z, r) in enumerate([(2.4, 4.8), (4.4, 3.8), (6.6, 4.2), (10.8, 7.5)]):
        d = disc("HS_Scheibe%d" % i, r); d.location = S + Vector((0, 0, z)); mat(d, "Teufel_FeuerScheibe", strength=2.6)
        keys(d, "rotation_euler", [(0, (0, 0, 0)), (2.2, (0, 0, -6.0 if i == 3 else -4.0))])
        if i < 3:
            keys(d, "scale", [(0.02 * i, (0.3,) * 3), (0.12 + 0.02 * i, (1,) * 3), (0.6, (1,) * 3), (0.75, (0.4, 0.4, 1))])
            fades(d, [(0.02 * i, 0), (0.08 + 0.02 * i, 1), (0.6, 1), (0.78, 0)])
        else:
            keys(d, "scale", [(0, (0.6,) * 3), (0.3, (1,) * 3), (1.9, (1.05,) * 3), (2.15, (1.2, 1.2, 1))])
            fades(d, [(0, 0), (0.15, 1), (1.9, 1), (2.2, 0)])
    # Kern: senkrechter pinker Lichtstrich im Zentrum
    core = quad("HS_KernStrich", 1.6, 9, "bottom"); core.location = S + Vector((0, 0, 0.2))
    core.rotation_euler = (math.radians(90), 0, 0)  # senkrecht, Kamera schaut von -Y
    fix_core_uv(core)
    mat(core, "Teufel_Strahl", (1, 0.5, 0.85), 1.6)
    keys(core, "scale", [(0, (0.5, 0.2, 1)), (0.15, (1, 1, 1)), (0.6, (1.2, 1, 1)), (0.72, (2.5, 0.5, 1))])
    fades(core, [(0, 0), (0.1, 1), (0.68, 1), (0.8, 0)])

def fix_core_uv(o):
    # Strahl-Textur laeuft in U aus -> fuer den senkrechten Strich U entlang der Hoehe legen
    uvl = o.data.uv_layers.active.data
    for i, uv in enumerate([(0, 0), (0, 1), (1, 1), (1, 0)]):
        uvl[i].uv = uv

# ---------------------------------------------------------------- Phase 2: Sternbruch (0,68-0,9 s)
def phase_bruch(cam):
    sp = spikes("HS_Sternbruch", 24, 3.0, 8.5, 0.42, -0.35, 0.55, 13); sp.location = S + Vector((0, 0, 1.2))
    mat(sp, None, (1, 0.6, 0.4), 1.4)
    keys(sp, "scale", [(0.68, (0.05,) * 3), (0.74, (1,) * 3), (0.86, (1.25,) * 3)])
    keys(sp, "rotation_euler", [(0.68, (0, 0, 0)), (0.86, (0, 0, 0.25))])
    fades(sp, [(0.68, 0), (0.70, 1), (0.77, 1), (0.87, 0)])
    fl = quad("HS_BruchBlitz", 5, 5); fl.location = S + Vector((0, 0, 1.4)); billboard(fl, cam)
    mat(fl, "Teufel_Funkelstern", (1, 0.85, 0.9), 4.0)
    keys(fl, "scale", [(0.66, (0.3,) * 3), (0.72, (1.8,) * 3), (0.82, (0.6,) * 3)])
    fades(fl, [(0.66, 0), (0.70, 1), (0.84, 0)])
    gr = torus("HS_GruenRing", 3.4, 0.05, 48, 4); gr.location = S + Vector((0, 0, 0.6)); gr.rotation_euler = (0.25, 0, 0)
    mat(gr, None, (0.5, 1, 0.6), 1.6)
    keys(gr, "scale", [(0.66, (0.6,) * 3), (0.86, (1.3,) * 3)]); fades(gr, [(0.66, 0), (0.7, 1), (0.88, 0)])
    # indigo Bodenringe bleiben danach liegen und verglimmen
    for i, (R, r) in enumerate([(3.6, 0.22), (5.2, 0.08)]):
        o = torus("HS_IndigoRing%d" % i, R, r, 48, 6); o.location = S + Vector((0, 0, 0.25)); o.scale = (1, 1, 0.5)
        mat(o, None, (0.2, 0.1, 1.0), 1.1)
        keys(o, "rotation_euler", [(0.55, (0, 0, 0)), (1.9, (0, 0, 1.2 * (-1) ** i))])
        fades(o, [(0.55, 0), (0.66, 1), (1.4, 0.8), (1.9, 0)])
    # Feuerstrahl nach oben direkt nach dem Bruch
    jet = quad("HS_Strahl_hoch", 1.8, 7, "bottom"); jet.location = S + Vector((0, 0, 1.0)); jet.rotation_euler = (math.radians(90), 0, 0)
    mat(jet, "Teufel_Feuersaeule", (1, 0.7, 0.6), 2.5, vfade=0.5, vaxis="Y")
    keys(jet, "scale", [(0.80, (0.6, 0.1, 1)), (0.86, (1, 1, 1)), (1.0, (0.4, 1.3, 1))])
    fades(jet, [(0.80, 0), (0.83, 1), (1.0, 0)]); scroll(jet, 0.8, 1.0, -0.6)

# ---------------------------------------------------------------- Phase 3: Rauch + rotes Mal fliegt zum Gegner (0,85-1,85 s)
def phase_rauch(cam):
    spots = [(-3.6, -0.5, 1.4), (-2.6, 0.8, 2.2), (-4.4, 0.6, 0.8), (3.6, -0.5, 1.4), (2.6, 0.8, 2.2), (4.4, 0.6, 0.8)]
    for i, p in enumerate(spots):
        q = quad("HS_Rauch%d" % i, 3, 3); q.location = S + Vector(p); billboard(q, cam)
        mat(q, "Teufel_Rauch", (0.75, 0.75, 0.78), 0.9, mode="ALPHA")
        t0 = 0.82 + 0.04 * i
        keys(q, "scale", [(t0, (0.4,) * 3), (1.4, (1.6,) * 3), (2.3, (2.2,) * 3)])
        keys(q, "location", [(t0, S + Vector(p)), (2.3, S + Vector(p) + Vector((0.6 * math.copysign(1, p[0]), 0, 0.9)))])
        fades(q, [(t0, 0), (t0 + 0.15, 0.85), (1.7, 0.6), (2.3, 0)])
    mal = quad("HS_RotesMal", 3.4, 3.4); billboard(mal, cam)
    mat(mal, "Teufel_Funkelstern", (1, 0.15, 0.08), 5.0)
    hover = S + Vector((0, 0, 3.6)); peak = (S + T) / 2 + Vector((0, 0, 7)); land = T + Vector((0, 0, 2.2))
    keys(mal, "location", [(0.85, hover), (1.45, hover + Vector((0, 0, 0.4))), (1.62, peak), (1.8, land)])
    keys(mal, "scale", [(0.85, (0.1,) * 3), (0.95, (1.2,) * 3), (1.2, (0.9,) * 3), (1.4, (1.15,) * 3), (1.8, (0.8,) * 3)])
    keys(mal, "rotation_euler", [(0.85, (0, 0, 0)), (1.85, (0, 0, 0.6))])
    fades(mal, [(0.85, 0), (0.9, 1), (1.8, 1), (1.9, 0)])

# ---------------------------------------------------------------- Phase 4: rote Kuppel am Gegner schrumpft (1,75-2,3 s)
def phase_kuppel(cam):
    k = sphere("HS_Kuppel", 2.6, hemi=True); k.location = T + Vector((0, 0, 0.02))
    mat(k, None, (1, 0.12, 0.08), 2.5, fresnel=1.2)
    keys(k, "scale", [(1.75, (1.5,) * 3), (1.85, (1.2,) * 3), (2.32, (0.35,) * 3)])
    fades(k, [(1.75, 0), (1.8, 1), (2.25, 1), (2.35, 0)])
    rays = spikes("HS_KuppelZacken", 8, 1.0, 2.6, 0.08, 0.1, 0.6, 21); rays.location = T + Vector((0, 0, 0.6))
    mat(rays, None, (1, 0.25, 0.15), 4.0)
    keys(rays, "scale", [(1.8, (1.4,) * 3), (2.3, (0.4,) * 3)]); keys(rays, "rotation_euler", [(1.8, (0, 0, 0)), (2.3, (0, 0, 1.0))])
    fades(rays, [(1.78, 0), (1.85, 1), (2.2, 0.5), (2.32, 0)])

# ---------------------------------------------------------------- Bildschirm-Blitze (nur Besitzer in Roblox)
def overlay(cam, name, color, pairs, mode="ALPHA", strength=1.0):
    q = quad(name, 3.0, 1.8); q.parent = cam; q.location = (0, 0, -1.0)
    mat(q, None, color, strength, mode=mode); fades(q, pairs)
    return q

# ---------------------------------------------------------------- Phase 6: schwarze Sonne ueber dem Gegner (2,4-3,3 s)
def ease_out(u):
    u = min(1.0, max(0.0, u)); return 1 - (1 - u) ** 3

# Bahn der schwarzen Sonne (v2): erscheint schraeg ueber dem Gegner (zum Teufel hin
# versetzt), schwebt mit leichtem Atmen naeher, holt kurz Schwung (steigt, zieht
# zurueck) und faellt dann beschleunigt im Bogen auf den Gegner. Einschlag 3,40 s.
SUN_HOVER = Vector((-3.0, 0, 8.6))   # relativ zu T
SUN_WIND = Vector((-3.8, 0, 9.8))    # Schwung-Punkt
SUN_CTRL = Vector((-1.4, 0, 9.6))    # Bezier-Kontrollpunkt des Falls (flacher Anfang, steiles Ende)
SUN_HIT = Vector((0, 0, 2.3))        # Mittelpunkt beim Aufprall (Radius 3,9 x Stauchung 0,6)
SUN_T = {"appear": 2.40, "drift": 2.60, "wind": 3.00, "fall": 3.14, "hit": 3.40, "gone": 3.50}

def sun_pos(t):
    s = SUN_T
    if t < s["drift"]:
        return T + SUN_HOVER + Vector((0, 0, 0.5 * (1 - ease_out((t - s["appear"]) / 0.2))))
    if t < s["wind"]:
        u = (t - s["drift"]) / (s["wind"] - s["drift"])
        return T + SUN_HOVER + Vector((0.3 * u, 0, 0.18 * math.sin(u * math.pi)))
    if t < s["fall"]:
        u = ease_out((t - s["wind"]) / (s["fall"] - s["wind"]))
        return (T + SUN_HOVER + Vector((0.3, 0, 0))).lerp(T + SUN_WIND, u)
    if t < s["hit"]:
        u = ((t - s["fall"]) / (s["hit"] - s["fall"])) ** 2.2   # Beschleunigung wie Schwerkraft
        p0, p1, p2 = T + SUN_WIND, T + SUN_CTRL, T + SUN_HIT
        return p0 * (1 - u) ** 2 + p1 * 2 * u * (1 - u) + p2 * u * u
    u = min(1.0, (t - s["hit"]) / (s["gone"] - s["hit"]))
    return T + SUN_HIT - Vector((0, 0, 1.8 * u))                  # versinkt im Boden

def bake_loc(o, t0, t1, fn):
    for f in range(F(t0), F(t1) + 1):
        o.location = fn((f - 1) / FPS); o.keyframe_insert("location", frame=f)

def fade_f(o, pairs):
    # wie fades, aber mit Bild-Nummern (Impact-Frames muessen auf das Bild genau sitzen)
    n = o.active_material.node_tree.nodes["Fade"]
    for f, v in pairs:
        n.outputs[0].default_value = v; n.outputs[0].keyframe_insert("default_value", frame=f)

def phase_sonne(cam):
    fa = F(SUN_T["appear"])   # Bild 73: Sonne steht schlagartig da (Impact-Frame)
    grp = empty("HS_Sonne", T + SUN_HOVER)
    bake_loc(grp, SUN_T["appear"], SUN_T["gone"], sun_pos)
    # Skalierung: Pop im Impact-Frame, Nachfedern, Atmen, Schwung (gestreckt), Fall (laenglich), Aufprall (gestaucht)
    for f, sc_ in [(fa - 1, (0.05,) * 3), (fa, (1.25,) * 3), (fa + 2, (1.25,) * 3), (fa + 4, (0.93,) * 3), (fa + 7, (1.0,) * 3)]:
        grp.scale = sc_; grp.keyframe_insert("scale", frame=f)
    keys(grp, "scale", [(2.8, (1.03,) * 3), (3.0, (1.0,) * 3), (3.14, (1.06, 1.06, 1.12)), (3.36, (0.9, 0.9, 1.2)),
                        (3.40, (1.35, 1.35, 0.6)), (3.50, (0.25, 0.25, 0.1))])
    # leichte Neigung in Flugrichtung, beim Aufprall gerade
    keys(grp, "rotation_euler", [(3.0, (0, 0, 0)), (3.14, (0, 0.18, 0)), (3.36, (0, -0.25, 0)), (3.40, (0, 0, 0))])
    ball = sphere("HS_SonneKugel", 3.9); ball.parent = grp
    mat(ball, None, (0.0, 0.0, 0.0), 0.0, mode="ALPHA")
    fade_f(ball, [(fa - 1, 0), (fa, 1)]); fades(ball, [(3.42, 1), (3.50, 0)])
    to_cam = (CAM_POS - (T + Vector((0, 0, 7.5)))).normalized()
    kern = quad("HS_SonneKern", 7.3, 7.3); kern.parent = grp; kern.location = to_cam * 3.95; billboard(kern, cam)
    mat(kern, "Teufel_SonnenKern", strength=2.6)
    fade_f(kern, [(fa - 1, 0), (fa, 1)]); fades(kern, [(3.14, 1), (3.38, 1.4), (3.48, 0)])
    # Kern dreht langsam, im Fall schnell (Schwung sichtbar machen)
    keys(kern, "delta_rotation_euler", [(2.4, (0, 0, 0)), (3.14, (0, 0, 1.2)), (3.40, (0, 0, 4.5))])
    kranz = wall("HS_SonneKranz", 3.3, lambda a: 4.6, seg=32, z0=-3.2, urep=3, flare=1.55)
    kranz.parent = grp; mat(kranz, "Teufel_Schwarzflamme", strength=1.6, mode="ALPHA", urep=3)
    keys(kranz, "rotation_euler", [(2.4, (0, 0, 0)), (3.4, (0, 0, -3.0))])
    # Flammenkranz: waechst an, im Fall nach oben gezogen wie ein Schweif
    keys(kranz, "scale", [(2.4, (1, 1, 0.4)), (2.6, (1.05, 1.05, 1)), (3.14, (1.1, 1.1, 1.1)), (3.36, (1.0, 1.0, 0.55))])
    fade_f(kranz, [(fa - 1, 0), (fa + 2, 1)]); fades(kranz, [(3.14, 1), (3.34, 0.3), (3.42, 0)])
    # Feuerschweif im Fall: Flammenstreifen hinter (ueber) der Sonne, entgegen der Flugrichtung
    schweif = quad("HS_SonneSchweif", 6.5, 9, "bottom"); schweif.parent = grp
    schweif.location = to_cam * 2.0 + Vector((0, 0, 0.5)); schweif.rotation_euler = (math.radians(90), 0, 0)
    mat(schweif, "Teufel_Feuersaeule", (1, 0.55, 0.45), 2.2, vfade=0.7, vaxis="Y"); scroll(schweif, 3.14, 3.42, 1.5)
    keys(schweif, "scale", [(3.14, (0.6, 0.05, 1)), (3.30, (0.9, 0.8, 1)), (3.40, (1.1, 1.3, 1))])
    fades(schweif, [(3.12, 0), (3.2, 1), (3.40, 1), (3.46, 0)])
    # weisse Sichel-Boegen: kommen nach dem Impact-Frame, loesen sich beim Schwungholen
    for i, (r, a0, a1, w, rz) in enumerate([(4.7, 0.45, 2.7, 1.5, 0.0), (5.5, 0.25, 2.2, 0.9, 0.35), (5.3, 0.95, 2.95, 0.8, -0.3)]):
        s_ = arc("HS_Sichel%d" % i, r, a0, a1, w); s_.parent = grp
        s_.location = to_cam * 0.5; billboard(s_, cam); s_.delta_rotation_euler = (0, 0, rz)
        mat(s_, "Teufel_Hieb", (1, 1, 1), 3.0)
        keys(s_, "delta_rotation_euler", [(2.47, (0, 0, rz - 0.4)), (3.2, (0, 0, rz + 0.5))])
        keys(s_, "scale", [(3.0, (1,) * 3), (3.22, (1.3,) * 3)])
        fades(s_, [(2.47 + 0.04 * i, 0), (2.57 + 0.04 * i, 1), (3.05, 1), (3.22, 0)])
    # Bodenglut: Schatten der Sonne, wird beim Fall groesser und heller
    glut = disc("HS_SonneGlut", 6.5); glut.location = T + Vector((0, 0, 0.05)); mat(glut, "Teufel_Glut", strength=2.5)
    keys(glut, "scale", [(2.4, (0.5,) * 3), (2.6, (1,) * 3), (3.14, (1.0,) * 3), (3.40, (1.6,) * 3)])
    fades(glut, [(2.4, 0), (2.5, 1), (3.14, 0.9), (3.38, 1.5), (3.5, 0)])
    for i, (off, colr, t0) in enumerate([((-3.5, -1, 4.5), (1, 0.2, 0.1), 2.55), ((3.6, -1, 6.8), (0.35, 0.45, 1), 2.66),
                                          ((-2.0, -2, 2.0), (1, 0.35, 0.15), 2.8), ((2.4, -2, 3.0), (0.6, 0.3, 1), 2.95)]):
        st = quad("HS_SonneFunkel%d" % i, 2.2, 2.2); st.location = T + Vector(off); billboard(st, cam)
        mat(st, "Teufel_Funkelstern", colr, 2.4)
        keys(st, "scale", [(t0, (0.1,) * 3), (t0 + 0.08, (1.2,) * 3), (t0 + 0.25, (0.1,) * 3)])
        fades(st, [(t0, 0), (t0 + 0.05, 1), (t0 + 0.25, 0)])

# ---------------------------------------------------------------- Impact-Frame beim Erscheinen der Sonne
# Bild 73 dunkel (schwarz/rot/weiss), 74 invertiert (weiss mit schwarzen Formen), 75 wieder dunkel,
# dazu Speedlines. Roblox (nur Besitzer): ColorCorrection (Saturation -1, Contrast 1, Tint),
# Highlight auf den Figuren, ScreenGui-Bild der Speedlines, 3 Bilder ueber RenderStepped.
def impact_frame(cam, f0):
    sc = bpy.context.scene
    ng = bpy.data.node_groups.get("HS_Comp")
    if ng:
        bpy.data.node_groups.remove(ng)
    ng = bpy.data.node_groups.new("HS_Comp", "CompositorNodeTree")
    ng.interface.new_socket("Image", in_out="OUTPUT", socket_type="NodeSocketColor")
    N = ng.nodes; L = ng.links
    rl = N.new("CompositorNodeRLayers"); out = N.new("NodeGroupOutput")
    imp = N.new("ShaderNodeValue"); imp.name = "Impact"
    inv_v = N.new("ShaderNodeValue"); inv_v.name = "Invert"
    inv = N.new("CompositorNodeInvert"); L.new(rl.outputs["Image"], inv.inputs["Color"]); L.new(inv_v.outputs[0], inv.inputs["Factor"])
    bw = N.new("CompositorNodeRGBToBW"); L.new(inv.outputs[0], bw.inputs["Image"])
    def make_ramp(stops):
        rp = N.new("ShaderNodeValToRGB"); L.new(bw.outputs[0], rp.inputs["Factor"])
        cr = rp.color_ramp; cr.interpolation = "CONSTANT"
        cr.elements[0].position = 0.0; cr.elements[0].color = (0, 0, 0, 1)
        cr.elements[1].position = stops[-1][0]; cr.elements[1].color = (*stops[-1][1], 1)
        for pos, col in stops[:-1]:
            e = cr.elements.new(pos); e.color = (*col, 1)
        return rp
    RED = (0.75, 0.02, 0.04)
    ramp_a = make_ramp([(0.11, RED), (0.62, (1, 1, 1))])      # dunkel: Boden schwarz, Figuren rot, Glut weiss
    ramp_b = make_ramp([(0.84, RED), (0.9, (1, 1, 1))])       # invertiert: Grund weiss, Figuren/Kern schwarz
    pick = N.new("ShaderNodeMix"); pick.data_type = "RGBA"
    L.new(inv_v.outputs[0], pick.inputs[0]); L.new(ramp_a.outputs[0], pick.inputs[6]); L.new(ramp_b.outputs[0], pick.inputs[7])
    mix = N.new("ShaderNodeMix"); mix.data_type = "RGBA"
    L.new(imp.outputs[0], mix.inputs[0]); L.new(rl.outputs["Image"], mix.inputs[6]); L.new(pick.outputs[2], mix.inputs[7])
    L.new(mix.outputs[2], out.inputs[0])
    sc.compositing_node_group = ng
    for f, a, b in [(f0 - 1, 0, 0), (f0, 1, 0), (f0 + 1, 1, 1), (f0 + 2, 1, 0), (f0 + 3, 0, 0)]:
        imp.outputs[0].default_value = a; imp.outputs[0].keyframe_insert("default_value", frame=f)
        inv_v.outputs[0].default_value = b; inv_v.outputs[0].keyframe_insert("default_value", frame=f)
    lines = overlay(cam, "HS_Speedlines", (1, 1, 1), [], mode="ADD", strength=3.0)
    m = make_mat("HS_Speedlines_img", "Teufel_Speedlines", (1, 1, 1), 3.0)
    lines.data.materials.clear(); lines.data.materials.append(m)
    fade_f(lines, [(f0 - 1, 0), (f0, 1), (f0 + 2, 1), (f0 + 3, 0)])
    keys(lines, "rotation_euler", [((f0 - 1) / FPS, (0, 0, 0)), ((f0 + 3) / FPS, (0, 0, 0.15))])
    # Bildschirm-Viewport soll den Compositor auch zeigen
    for w in bpy.context.window_manager.windows:
        for a in w.screen.areas:
            if a.type == "VIEW_3D":
                a.spaces.active.shading.use_compositor = "ALWAYS"

# ---------------------------------------------------------------- Phase 8: Feuersaeule + Hiebe + Krone (3,4-5,0 s)
IMPACT = 3.42

def phase_saeule(cam):
    for nm, r, st, dv in [("HS_SaeuleAussen", 2.2, 2.2, -3.0), ("HS_SaeuleInnen", 1.1, 3.6, -4.5)]:
        p = wall(nm, r, lambda a: 30, seg=20, z0=0, urep=2); p.location = T.copy()
        mat(p, "Teufel_Feuersaeule", strength=st, urep=2, vfade=0.45); scroll(p, IMPACT, 5.4, dv)
        keys(p, "scale", [(IMPACT, (0.25, 0.25, 0.04)), (IMPACT + 0.15, (1, 1, 1)), (4.4, (1.05, 1.05, 1)),
                          (4.7, (1.7, 1.7, 1)), (5.3, (1.9, 1.9, 1))])
        keys(p, "rotation_euler", [(IMPACT, (0, 0, 0)), (5.4, (0, 0, 2.0))])
        fades(p, [(IMPACT - 0.02, 0), (IMPACT + 0.03, 1), (4.9, 1), (5.4, 0)])
    # Windhiebe: weisse Baender, die um den Getroffenen fegen
    for i, (r, a0, a1, w, tilt, t0) in enumerate([(5.5, 0.2, 2.9, 1.3, (0.30, 0.08), 0.0), (7.5, 3.4, 5.9, 1.6, (-0.22, 0.12), 0.05),
                                                   (6.4, 1.2, 3.8, 1.0, (0.12, -0.25), 0.12), (9.0, 4.2, 6.2, 1.2, (0.38, 0.0), 0.2)]):
        a = arc("HS_Hieb%d" % i, r * 1.3, a0, a1, w * 1.3); a.location = T + Vector((0, 0, 2.5 + 1.3 * i))
        mat(a, "Teufel_Hieb", (1, 0.96, 0.94), 2.4)
        s0 = IMPACT + t0
        keys(a, "rotation_euler", [(s0, (tilt[0], tilt[1], 0)), (s0 + 0.7, (tilt[0], tilt[1], -2.6))])
        keys(a, "scale", [(s0, (0.6,) * 3), (s0 + 0.7, (1.15,) * 3)])
        fades(a, [(s0, 0), (s0 + 0.06, 1), (s0 + 0.45, 0.8), (s0 + 0.72, 0)])
    # Funkelsterne (weiss, orange, violett) um die Saeule
    pal = [(1, 1, 1), (1, 0.55, 0.2), (0.75, 0.4, 1), (1, 0.85, 0.6), (0.5, 0.55, 1)]
    for i in range(20):
        t0 = IMPACT + 0.05 + 0.055 * i
        pos = T + Vector((rnd.uniform(-5, 5), rnd.uniform(-3.5, -1.0), rnd.uniform(1.5, 12)))
        st = quad("HS_Funkel%d" % i, 4.2, 4.2); st.location = pos; billboard(st, cam)
        mat(st, "Teufel_Funkelstern", pal[i % len(pal)], 3.0)
        m = rnd.uniform(0.7, 1.5)
        keys(st, "scale", [(t0, (0.05,) * 3), (t0 + 0.07, (m,) * 3), (t0 + 0.32, (0.05,) * 3)])
        keys(st, "delta_rotation_euler", [(t0, (0, 0, 0)), (t0 + 0.32, (0, 0, 0.6))])
        fades(st, [(t0, 0), (t0 + 0.04, 1), (t0 + 0.32, 0)])
    # Kronen-Schockwelle: Schleierwand, seitlich zwei hohe Zacken, wellige Kante
    def kronen_kante(a):
        return 3.0 + 4.2 * abs(math.cos(a)) ** 3 + 0.45 * math.sin(6 * a) + 0.6 * abs(math.sin(a)) ** 8
    kr = wall("HS_Krone", 4.5, kronen_kante, seg=64, z0=0.0); kr.location = T + Vector((0, 0, 0.02))
    mat(kr, "Teufel_Krone", (1, 0.93, 0.95), 1.4, mode="ALPHA")
    keys(kr, "scale", [(3.62, (0.4, 0.4, 0.15)), (3.85, (1, 1, 0.9)), (4.3, (1.35, 1.35, 1.05)), (4.75, (1.75, 1.75, 1.1))])
    fades(kr, [(3.6, 0), (3.7, 0.9), (4.4, 0.85), (4.85, 0)])
    glut = disc("HS_SaeuleGlut", 8); glut.location = T + Vector((0, 0, 0.04)); mat(glut, "Teufel_Glut", strength=2.0)
    keys(glut, "scale", [(IMPACT, (0.3,) * 3), (IMPACT + 0.2, (1,) * 3), (4.7, (1.4,) * 3)])
    fades(glut, [(IMPACT, 0), (IMPACT + 0.1, 1), (5.0, 1), (5.5, 0)])

# ---------------------------------------------------------------- Phase 9: Flammenfaecher + Nachrauch (4,6-5,6 s)
def phase_faecher(cam):
    for i, (w, h, dz, t0, colr) in enumerate([(30, 18, -0.5, 4.62, (1, 0.6, 0.8)), (22, 14, 0.5, 4.7, (1, 0.85, 0.9))]):
        f = quad("HS_Faecher%d" % i, w, h, "bottom"); f.location = T + Vector((0, 1.5 - i, dz)); billboard(f, cam)
        mat(f, "Teufel_Faecher", colr, 2.6)
        keys(f, "scale", [(t0, (0.2, 0.1, 1)), (t0 + 0.12, (1, 1, 1)), (5.3, (1.25, 1.15, 1))])
        fades(f, [(t0, 0), (t0 + 0.08, 1), (5.0, 0.8), (5.45, 0)])
    for i in range(6):
        p = T + Vector((rnd.uniform(-6, 6), rnd.uniform(-2, 2), rnd.uniform(0.5, 5)))
        q = quad("HS_NachRauch%d" % i, 5, 5); q.location = p; billboard(q, cam)
        mat(q, "Teufel_Rauch", (0.6, 0.55, 0.58), 0.8, mode="ALPHA")
        t0 = 4.85 + 0.05 * i
        keys(q, "scale", [(t0, (0.5,) * 3), (5.6, (1.8,) * 3)]); keys(q, "location", [(t0, p), (5.6, p + Vector((0, 0, 1.2)))])
        fades(q, [(t0, 0), (t0 + 0.2, 0.7), (5.6, 0)])

# ---------------------------------------------------------------- Figuren + Kamera
def figuren(cam):
    me = import_bear(ROOT + r"\Export\Excl_Teufel.fbx", "Teufel_Baerchi", S, 90)
    en = import_bear(ROOT + r"\Export\Bear_Braunbaer.fbx", "Gegner_Baerchi", T, -90)
    base_s = S + Vector((0, 0, 1.32)); base_t = T + Vector((0, 0, 1.32))
    # Teufel schwebt beim Aufladen kurz an, landet nach dem Bruch
    keys(me, "location", [(0, base_s), (0.5, base_s + Vector((0, 0, 0.8))), (0.9, base_s + Vector((0, 0, 0.8))), (1.1, base_s)])
    # Gegner: Rueckstoss im Einschlag, kippt nach hinten, trottet zurueck
    keys(en, "location", [(IMPACT - 0.01, base_t), (IMPACT + 0.25, base_t + Vector((3.5, 0, 0.8))), (IMPACT + 0.45, base_t + Vector((4.2, 0, 0))),
                          (5.6, base_t + Vector((1.0, 0, 0)))])
    keys(en, "rotation_euler", [(IMPACT - 0.01, (0, 0, math.radians(-90))), (IMPACT + 0.25, (0, math.radians(25), math.radians(-90))),
                                (4.4, (0, 0, math.radians(-90)))])
    # Kamerawackeln beim Bruch und beim Einschlag
    def shake(t0, dur, power):
        n = int(dur * FPS)
        for k in range(n + 1):
            f = t0 + k / FPS; damp = 1 - k / max(1, n)
            key(cam, "location", f, CAM_POS + Vector((rnd.uniform(-1, 1), 0, rnd.uniform(-1, 1))) * power * damp)
    key(cam, "location", 0, CAM_POS); key(cam, "location", 0.68, CAM_POS)
    shake(0.70, 0.18, 0.25); key(cam, "location", 1.0, CAM_POS); key(cam, "location", 2.38, CAM_POS)
    shake(2.40, 0.25, 0.45); key(cam, "location", 2.7, CAM_POS); key(cam, "location", IMPACT - 0.04, CAM_POS)
    shake(IMPACT - 0.02, 0.45, 0.6); key(cam, "location", 5.6, CAM_POS)

def build():
    global COL
    exec(open(TEXPY, encoding="utf-8").read(), {"__name__": "tex"})
    COL = reset()
    cam = stage()
    phase_siegel(cam); phase_bruch(cam); phase_rauch(cam); phase_kuppel(cam)
    rot = overlay(cam, "HS_BlitzRot", (0.85, 0.02, 0.03), [])
    fade_f(rot, [(F(2.28), 0), (F(2.32), 0.92), (F(2.4) - 1, 0.85), (F(2.4), 0)])  # endet genau vor dem Impact-Frame
    phase_sonne(cam)
    impact_frame(cam, F(SUN_T["appear"]))
    overlay(cam, "HS_BlitzPink", (1, 0.35, 0.48), [(3.38, 0), (3.40, 0.9), (3.44, 0.9), (3.46, 0)])
    overlay(cam, "HS_BlitzWeiss", (1, 1, 1), [(3.43, 0), (3.45, 1), (3.5, 0.95), (3.62, 0)])
    overlay(cam, "HS_TintRot", (0.9, 0.08, 0.06), [(3.42, 0), (3.5, 0.24), (5.0, 0.22), (5.6, 0)])
    overlay(cam, "HS_BlitzFaecher", (1, 0.75, 0.85), [(4.58, 0), (4.62, 0.6), (4.76, 0)])
    phase_saeule(cam); phase_faecher(cam)
    figuren(cam)
    for o in COL.objects:
        o.visible_shadow = False  # Roblox: Effekte ohne Schatten
    bpy.context.scene.frame_set(F(0.3))
    return {"objects": len(COL.objects)}

RESULT = build()
