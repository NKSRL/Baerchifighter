# Einzige Zustaendigkeit: baut den Blender-Prototyp der Pulsar-Show "Pulsstoss"
# (Meshes, Materialien, Animation, Kamera, Impact-Frames) in der offenen .blend-Datei neu auf.
# Vorbild: Video vom 22.10. (Ring -> Sternbruch mit fliegenden Funken -> pulsierende Kugel
# -> Impact-Frames -> riesige Feuerkuppel mit Flammenstreifen -> Weissblende -> Nachgluehen).
# Umsetzung fuer den Kampf: Ring bildet sich um den eigenen Baerchi (S), steigt zum Halo,
# bricht zur Kugel, die Kugel fliegt zum Gegner (T), dort platzt die Kuppel auf.
# 1 Blender-Einheit = 1 Stud, Z oben. 30 fps, Show 5,8 s, Einschlag bei 2,50 s.
# Aufruf in Blender: exec(open(<diese Datei>).read(), {"__name__": "scene"})
import bpy, bmesh, math, random
from mathutils import Vector

ROOT = r"C:\Users\admin\Documents\Claude Downloads\RBL"
TEXPY = ROOT + r"\tools\vfx\pulsar_pulsstoss_tex.py"
FPS = 30
DUR = 5.8
IMPACT = 2.50
S = Vector((-9, 0, 0))   # eigener Baerchi (MapConfig.FIGHT_SPACING = 9)
T = Vector((9, 0, 0))    # Gegner
HALO = S + Vector((0, 0, 4.2))        # Punkt ueber dem Kopf, an dem Ring -> Kugel wird
HIT = T + Vector((0, 0, 1.6))         # Treffpunkt der Kugel
CAM_POS = Vector((0, -26, 12.5)); CAM_AIM = Vector((0, 0, 5.0))
rnd = random.Random(777)

ORANGE = (1.0, 0.42, 0.06)
GELB = (1.0, 0.8, 0.3)
WEISS = (1.0, 1.0, 1.0)
PINK = (1.0, 0.45, 0.62)
MAGENTA = (1.0, 0.2, 0.45)

def F(t):
    return 1 + round(t * FPS)

# ---------------------------------------------------------------- Aufraeumen
def reset():
    col = bpy.data.collections.get("PS_VFX")
    if col:
        for o in list(col.objects):
            bpy.data.objects.remove(o, do_unlink=True)
    else:
        col = bpy.data.collections.new("PS_VFX"); bpy.context.scene.collection.children.link(col)
    for m in list(bpy.data.materials):
        if m.name.startswith("PS_") and m.users == 0:
            bpy.data.materials.remove(m)
    for me in list(bpy.data.meshes):
        if me.name.startswith("PS_") and me.users == 0:
            bpy.data.meshes.remove(me)
    return col

COL = None

def link(o):
    COL.objects.link(o); return o

# ---------------------------------------------------------------- Materialien
def make_mat(name, img=None, color=WEISS, strength=2.0, mode="ADD", fresnel=0.0, rim=0.0, urep=1.0, vrep=1.0, hot=0.0, opaque=False):
    # fresnel: Alpha * (1-Facing)^p (Mitte sichtbar), rim: Alpha * Facing^p (nur Rand sichtbar),
    # hot: Farbe in der Mitte heller (Kuppel: weissgluehender Kern, roter Rand)
    # opaque: schreibt Tiefe (DITHERED), damit Dinge im Inneren (Glut, Gegner) verdeckt werden;
    # BLENDED sortiert nur nach Objektmitte und wuerde die Bodenglut ueber die Kuppel malen
    m = bpy.data.materials.new("PS_" + name)
    m.use_nodes = True
    nt = m.node_tree; N = nt.nodes; L = nt.links
    N.clear()
    out = N.new("ShaderNodeOutputMaterial")
    fade = N.new("ShaderNodeValue"); fade.name = "Fade"; fade.outputs[0].default_value = 1.0
    strn = N.new("ShaderNodeValue"); strn.name = "Str"; strn.outputs[0].default_value = strength
    if img:
        tex = N.new("ShaderNodeTexImage"); tex.image = bpy.data.images[img]; tex.extension = "REPEAT"
        tc = N.new("ShaderNodeTexCoord"); mp = N.new("ShaderNodeMapping"); mp.name = "Scroll"
        mp.inputs["Scale"].default_value = (urep, vrep, 1)
        L.new(tc.outputs["UV"], mp.inputs["Vector"]); L.new(mp.outputs["Vector"], tex.inputs["Vector"])
        mul = N.new("ShaderNodeVectorMath"); mul.operation = "MULTIPLY"
        L.new(tex.outputs["Color"], mul.inputs[0]); mul.inputs[1].default_value = color
        col_out = mul.outputs[0]; a_out = tex.outputs["Alpha"]
    else:
        rgb = N.new("ShaderNodeRGB"); rgb.outputs[0].default_value = (*color, 1)
        one = N.new("ShaderNodeValue"); one.outputs[0].default_value = 1.0
        col_out = rgb.outputs[0]; a_out = one.outputs[0]
    lw = None
    if fresnel > 0 or rim > 0 or hot > 0:
        lw = N.new("ShaderNodeLayerWeight"); lw.inputs["Blend"].default_value = 0.4
    # LayerWeight "Facing": 0 mit Blick senkrecht auf die Flaeche (Mitte), 1 am streifenden Rand
    if hot > 0:
        mr = N.new("ShaderNodeMapRange"); mr.inputs["To Min"].default_value = 1.0 + hot; mr.inputs["To Max"].default_value = 1.0 - hot * 0.5
        L.new(lw.outputs["Facing"], mr.inputs["Value"])
        hm = N.new("ShaderNodeVectorMath"); hm.operation = "SCALE"
        L.new(col_out, hm.inputs[0]); L.new(mr.outputs["Result"], hm.inputs["Scale"]); col_out = hm.outputs[0]
    am = N.new("ShaderNodeMath"); am.operation = "MULTIPLY"
    L.new(a_out, am.inputs[0]); L.new(fade.outputs[0], am.inputs[1]); alpha = am.outputs[0]
    if fresnel > 0 or rim > 0:
        src = lw.outputs["Facing"]          # rim: Facing^p -> nur der Rand leuchtet
        if fresnel > 0:                     # fresnel: (1-Facing)^p -> nur die Mitte
            iv = N.new("ShaderNodeMath"); iv.operation = "SUBTRACT"; iv.inputs[0].default_value = 1.0
            L.new(lw.outputs["Facing"], iv.inputs[1]); src = iv.outputs[0]
        pw = N.new("ShaderNodeMath"); pw.operation = "POWER"; pw.inputs[1].default_value = fresnel if fresnel > 0 else rim
        L.new(src, pw.inputs[0])
        am2 = N.new("ShaderNodeMath"); am2.operation = "MULTIPLY"
        L.new(alpha, am2.inputs[0]); L.new(pw.outputs[0], am2.inputs[1]); alpha = am2.outputs[0]
    em = N.new("ShaderNodeEmission"); L.new(col_out, em.inputs["Color"])
    tr = N.new("ShaderNodeBsdfTransparent")
    if mode == "ADD":
        sm = N.new("ShaderNodeMath"); sm.operation = "MULTIPLY"
        L.new(alpha, sm.inputs[0]); L.new(strn.outputs[0], sm.inputs[1]); L.new(sm.outputs[0], em.inputs["Strength"])
        ad = N.new("ShaderNodeAddShader"); L.new(tr.outputs[0], ad.inputs[0]); L.new(em.outputs[0], ad.inputs[1])
        L.new(ad.outputs[0], out.inputs["Surface"])
    else:  # ALPHA: deckend gemischt (Kuppel, Rauch, Truemmer, Blitze)
        L.new(strn.outputs[0], em.inputs["Strength"])
        mx = N.new("ShaderNodeMixShader"); L.new(alpha, mx.inputs[0])
        L.new(tr.outputs[0], mx.inputs[1]); L.new(em.outputs[0], mx.inputs[2])
        L.new(mx.outputs[0], out.inputs["Surface"])
    m.surface_render_method = "DITHERED" if opaque else "BLENDED"
    m.use_backface_culling = False
    return m

def mat(o, *a, **k):
    m = make_mat(o.name, *a, **k)
    o.data.materials.clear(); o.data.materials.append(m)
    return m

def node_key(o, node, t, v, frame=None):
    n = o.active_material.node_tree.nodes[node]
    n.outputs[0].default_value = v; n.outputs[0].keyframe_insert("default_value", frame=frame if frame is not None else F(t))

def fade(o, t, v):
    node_key(o, "Fade", t, v)

def fades(o, pairs):
    for t, v in pairs:
        fade(o, t, v)

def fade_f(o, pairs):   # Bildnummern statt Sekunden (Impact-Frames)
    for f, v in pairs:
        node_key(o, "Fade", 0, v, frame=f)

def strength(o, pairs):
    for t, v in pairs:
        node_key(o, "Str", t, v)

def scroll(o, t0, t1, du=0.0, dv=0.0):
    n = o.active_material.node_tree.nodes["Scroll"]
    n.inputs["Location"].default_value = (0, 0, 0); n.inputs["Location"].keyframe_insert("default_value", frame=F(t0))
    n.inputs["Location"].default_value = (du, dv, 0); n.inputs["Location"].keyframe_insert("default_value", frame=F(t1))
    interp(o.active_material.node_tree, "LINEAR", "Scroll")

def key(o, path, t, v):
    setattr(o, path, v); o.keyframe_insert(path, frame=F(t))

def keys(o, path, pairs):
    for t, v in pairs:
        key(o, path, t, v)

def fcurves(action):
    # Blender 5: Actions sind geschichtet (Layer -> Strip -> Channelbag), aeltere haben action.fcurves
    if hasattr(action, "fcurves"):
        return list(action.fcurves)
    out = []
    for layer in action.layers:
        for strip in layer.strips:
            for cb in strip.channelbags:
                out.extend(cb.fcurves)
    return out

def interp(owner, mode, path_filter=None):
    ad = owner.animation_data
    if ad and ad.action:
        for fc in fcurves(ad.action):
            if path_filter and path_filter not in fc.data_path:
                continue
            for kp in fc.keyframe_points:
                kp.interpolation = mode

def stepped(o):
    interp(o, "CONSTANT")

def hide(o, t_show, t_hide=None):
    # Sichtbarkeit hart schalten (zusaetzlich zum Fade), damit unsichtbare Teile nichts kosten
    o.hide_render = True; o.hide_viewport = True
    o.keyframe_insert("hide_render", frame=F(t_show) - 1); o.keyframe_insert("hide_viewport", frame=F(t_show) - 1)
    o.hide_render = False; o.hide_viewport = False
    o.keyframe_insert("hide_render", frame=F(t_show)); o.keyframe_insert("hide_viewport", frame=F(t_show))
    if t_hide is not None:
        o.hide_render = True; o.hide_viewport = True
        o.keyframe_insert("hide_render", frame=F(t_hide)); o.keyframe_insert("hide_viewport", frame=F(t_hide))
    o.hide_render = False; o.hide_viewport = False

# ---------------------------------------------------------------- Mesh-Bausteine
def new_obj(name, bm):
    me = bpy.data.meshes.new("PS_" + name); bm.to_mesh(me); bm.free()
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
    x0 = -w / 2 if pivot != "left" else 0
    y0 = -h / 2
    vs = [bm.verts.new(p) for p in [(x0, y0, 0), (x0 + w, y0, 0), (x0 + w, y0 + h, 0), (x0, y0 + h, 0)]]
    f = bm.faces.new(vs)
    for l, u in zip(f.loops, [(0, 0), (1, 0), (1, 1), (0, 1)]):
        l[uv].uv = u
    return new_obj(name, bm)

def torus(name, R, r, seg=48, rseg=8):
    bm = bmesh.new(); grid = []
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

def wall(name, radius, height, seg=48, urep=1.0, flare=1.0):
    # offener Zylindermantel; UV u rundherum, v hoch
    bm = bmesh.new(); uv = bm.loops.layers.uv.verify(); bot = []; top = []
    for i in range(seg + 1):
        a = 2 * math.pi * i / seg
        c, s = math.cos(a), math.sin(a)
        bot.append(bm.verts.new((radius * c, radius * s, 0)))
        top.append(bm.verts.new((radius * flare * c, radius * flare * s, height)))
    for i in range(seg):
        f = bm.faces.new([bot[i], bot[i + 1], top[i + 1], top[i]])
        for l, u in zip(f.loops, [(i / seg, 0), ((i + 1) / seg, 0), ((i + 1) / seg, 1), (i / seg, 1)]):
            l[uv].uv = (u[0] * urep, u[1])
    return new_obj(name, bm)

def spikes(name, count, lmin, lmax, base, seed, flat=0.35):
    # Sternbruch: duenne dreiseitige Spitzen, hauptsaechlich in der Bildebene (XZ), leicht in Y gestreut
    r = random.Random(seed); bm = bmesh.new()
    for k in range(count):
        ang = 2 * math.pi * (k + r.uniform(-0.3, 0.3)) / count
        d = Vector((math.cos(ang), r.uniform(-flat, flat), math.sin(ang))).normalized()
        L = r.uniform(lmin, lmax)
        perp = d.cross(Vector((0, 1, 0))).normalized(); perp2 = d.cross(perp).normalized()
        c = d * 0.2
        b = [bm.verts.new(c + (perp * math.cos(q) + perp2 * math.sin(q)) * base) for q in (0, 2.1, 4.2)]
        tip = bm.verts.new(d * L)
        for i in range(3):
            bm.faces.new([b[i], b[(i + 1) % 3], tip])
    return new_obj(name, bm)

def hemisphere(name, r, useg=48, vseg=24):
    bm = bmesh.new(); bm.loops.layers.uv.verify()
    bmesh.ops.create_uvsphere(bm, u_segments=useg, v_segments=vseg, radius=r, calc_uvs=True)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < -0.01], context="VERTS")
    return new_obj(name, bm)

def chunk(name, r, seed):
    # Truemmerbrocken: kleine Kugel, zufaellig verbeult
    rr = random.Random(seed); bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=r)
    for v in bm.verts:
        v.co *= rr.uniform(0.6, 1.25)
    return new_obj(name, bm)

def billboard(o, cam):
    c = o.constraints.new("TRACK_TO"); c.target = cam; c.track_axis = "TRACK_Z"; c.up_axis = "UP_Y"
    return o

def empty(name, loc):
    e = link(bpy.data.objects.new(name, None)); e.location = loc; return e

def facing_cam(o):
    # flaches Quad in die Bildebene drehen (Kamera blickt entlang +Y)
    o.rotation_euler = (math.pi / 2, 0, 0); return o

def bake_loc(o, t0, t1, fn):
    for f in range(F(t0), F(t1) + 1):
        o.location = fn((f - 1) / FPS); o.keyframe_insert("location", frame=f)

def ease_in(u):
    return u * u

def ease_out(u):
    return 1 - (1 - u) ** 2

def bezier(a, c, b, u):
    return a * (1 - u) ** 2 + c * 2 * u * (1 - u) + b * u * u

# ---------------------------------------------------------------- Buehne
def stage():
    sc = bpy.context.scene
    sc.render.fps = FPS; sc.frame_start = 1; sc.frame_end = F(DUR)
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x = 960; sc.render.resolution_y = 540; sc.render.resolution_percentage = 100
    sc.view_settings.view_transform = "Standard"
    try:
        sc.eevee.taa_render_samples = 16
    except Exception:
        pass
    w = bpy.data.worlds.get("PS_World") or bpy.data.worlds.new("PS_World")
    sc.world = w; w.use_nodes = True
    bg = w.node_tree.nodes.get("Background")
    bg.inputs[0].default_value = (0.035, 0.03, 0.045, 1); bg.inputs[1].default_value = 1.0
    cam = bpy.data.objects.get("PS_Cam")
    if not cam:
        cam = bpy.data.objects.new("PS_Cam", bpy.data.cameras.new("PS_Cam")); sc.collection.objects.link(cam)
    cam.data.lens = 30; cam.location = CAM_POS
    cam.rotation_euler = (CAM_AIM - CAM_POS).to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    sun = bpy.data.objects.get("PS_Sun")
    if not sun:
        sun = bpy.data.objects.new("PS_Sun", bpy.data.lights.new("PS_Sun", "SUN")); sc.collection.objects.link(sun)
    sun.data.energy = 2.5; sun.rotation_euler = (math.radians(50), 0, math.radians(30))
    g = bpy.data.objects.get("PS_Boden")
    if not g:
        bm = bmesh.new(); bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=80)
        me = bpy.data.meshes.new("PS_Boden_me"); bm.to_mesh(me); bm.free()
        g = bpy.data.objects.new("PS_Boden", me); sc.collection.objects.link(g)
        m = bpy.data.materials.new("PS_Boden_mat"); m.use_nodes = True
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

# ---------------------------------------------------------------- Phase 1: Ring bildet sich um den Baerchi (0,00-1,05 s)
# Bodenblitz -> Ring am Boden um den Baerchi, Funken stroemen hinein -> Ring steigt, kippt zur
# Kamera und schrumpft zum Halo ueber dem Kopf -> pulsiert zweimal ("tickt").
def phase_ring(cam):
    # Bodenblitz: flache helle Scheibe, die aufploppt und sofort wieder verschwindet (Bild 1-6)
    bl = disc("Bodenblitz", 4.6); bl.location = S + Vector((0, 0, 0.08))
    mat(bl, "Pulsar_Scheibe", GELB, 6.0)
    keys(bl, "scale", [(0.0, (0.2, 0.2, 1)), (0.08, (1.1, 1.1, 1)), (0.2, (1.3, 1.3, 1))])
    fades(bl, [(0.0, 1), (0.08, 1), (0.2, 0)]); hide(bl, 0.0, 0.22)
    # Ring-Traeger: alles, was mit dem Ring steigt und kippt, haengt daran
    rg = empty("RingTraeger", S + Vector((0, 0, 0.1)))
    ring = torus("Ring", 3.6, 0.07); ring.parent = rg; mat(ring, None, ORANGE, 5.0)
    inner = torus("RingInnen", 3.3, 0.035); inner.parent = rg; mat(inner, None, WEISS, 4.0)
    glow = disc("RingSchein", 4.5); glow.parent = rg; mat(glow, "Pulsar_Ring", ORANGE, 2.5)
    for o in (ring, inner, glow):
        hide(o, 0.04, 1.14)
    # Aufploppen mit Ueberschwingen
    keys(rg, "scale", [(0.04, (0.3,) * 3), (0.14, (1.12,) * 3), (0.24, (1.0,) * 3), (0.55, (1.0,) * 3)])
    # Langsames Drehen gegeneinander
    keys(ring, "rotation_euler", [(0.0, (0, 0, 0)), (1.1, (0, 0, 2.0))])
    keys(inner, "rotation_euler", [(0.0, (0, 0, 0)), (1.1, (0, 0, -3.0))])
    fades(glow, [(0.04, 0), (0.14, 1), (0.55, 0.8), (0.85, 0.3), (1.05, 0.0)])
    # Steigen + Kippen + Schrumpfen zum Halo (0,55-0,85), danach Pulsieren (0,85-1,05)
    keys(rg, "location", [(0.55, S + Vector((0, 0, 0.1))), (0.85, HALO)])
    keys(rg, "rotation_euler", [(0.55, (0, 0, 0)), (0.85, (math.pi / 2, 0, 0))])
    keys(rg, "scale", [(0.85, (0.26,) * 3), (0.9, (0.3,) * 3), (0.95, (0.24,) * 3), (1.0, (0.3,) * 3), (1.05, (0.25,) * 3), (1.12, (0.03,) * 3)])
    strength(ring, [(0.84, 5.0), (0.9, 9.0), (0.95, 5.0), (1.0, 10.0), (1.05, 6.0), (1.12, 16.0)])
    # Funken, die in den Ring stroemen (Aufladen): Pillen fliegen von aussen zur Ringmitte
    for i in range(16):
        t0 = 0.25 + rnd.random() * 0.55; life = 0.3 + rnd.random() * 0.15
        ang = rnd.random() * 2 * math.pi; r0 = 6.0 + rnd.random() * 3.0
        start = S + Vector((math.cos(ang) * r0, math.sin(ang) * r0 * 0.6, rnd.uniform(0.2, 3.5)))
        goal = S + Vector((0, 0, 0.4)) if t0 < 0.55 else HALO
        q = quad("Sog%02d" % i, 1.4, 0.45); mat(q, "Pulsar_Funke", WEISS, 3.0)
        d = goal - start; phi = math.atan2(d.z, d.x)
        q.rotation_euler = (math.pi / 2, -phi, 0)
        bake_loc(q, t0, t0 + life, lambda t, a=start, b=goal, t0=t0, life=life: a.lerp(b, ease_in(min(1, max(0, (t - t0) / life)))))
        fades(q, [(t0, 0), (t0 + 0.05, 1), (t0 + life - 0.04, 1), (t0 + life, 0)]); hide(q, t0, t0 + life + 0.02)
    # Violetter Staub, der um den Baerchi aufsteigt (das Flimmern im Vorbild)
    for i in range(12):
        t0 = 0.1 + rnd.random() * 0.4
        p = S + Vector((rnd.uniform(-3.5, 3.5), rnd.uniform(-2, 2), 0.3))
        d = disc("Staub%02d" % i, 0.22); billboard(d, cam); mat(d, "Pulsar_Scheibe", (0.9, 0.3, 1.0), 4.0)
        keys(d, "location", [(t0, p), (t0 + 0.9, p + Vector((rnd.uniform(-0.5, 0.5), 0, rnd.uniform(2.5, 4.5))))])
        fades(d, [(t0, 0), (t0 + 0.15, 1), (t0 + 0.7, 0.6), (t0 + 0.9, 0)]); hide(d, t0, t0 + 0.92)

# ---------------------------------------------------------------- Phase 2: Sternbruch (1,12-1,75 s) am Halo
# Der Halo kollabiert zum Punkt und platzt als Anime-Stern auf: Kern, zwei abwechselnd
# sichtbare Zackensaetze (Flackern in 2-Bild-Schritten), Funken-Pillen fliegen in Boegen raus,
# bei 1,60 s ein grosser Zackenstern-Blitz, danach schrumpft alles in die Kugel.
def phase_bruch(cam):
    # Kollaps-Blitz (Bild F(1.12))
    fl = disc("KollapsBlitz", 2.2); billboard(fl, cam); fl.location = HALO; mat(fl, "Pulsar_Scheibe", WEISS, 10.0)
    keys(fl, "scale", [(1.10, (0.2,) * 3), (1.14, (1.0,) * 3), (1.2, (0.4,) * 3)])
    fades(fl, [(1.10, 1), (1.14, 1), (1.2, 0)]); hide(fl, 1.10, 1.22)
    # Kern: Vierzack-Stern + weisse Scheibe, flackert
    core = disc("BruchKern", 1.6); billboard(core, cam); core.location = HALO; mat(core, "Pulsar_Stern", WEISS, 6.0)
    halo = disc("BruchSchein", 2.6); billboard(halo, cam); halo.location = HALO; mat(halo, "Pulsar_Scheibe", ORANGE, 3.5)
    for o in (core, halo):
        hide(o, 1.12, 1.78)
    for f in range(F(1.12), F(1.75) + 1, 2):
        s = rnd.uniform(0.75, 1.3)
        core.scale = (s,) * 3; core.keyframe_insert("scale", frame=f)
        core.rotation_euler = (0, 0, rnd.uniform(-0.5, 0.5)); core.keyframe_insert("rotation_euler", frame=f)
        halo.scale = (s * 0.9 + 0.2,) * 3; halo.keyframe_insert("scale", frame=f)
    stepped(core); stepped(halo)
    keys(core, "scale", [(1.76, (0.25,) * 3)]); keys(halo, "scale", [(1.76, (0.4,) * 3)])
    # Zacken: Satz A auf geraden 2-Bild-Schritten, Satz B auf ungeraden -> kocht
    for n, (seed, off) in enumerate([(11, 0), (12, 2)]):
        z = spikes("Zacken%d" % n, 13, 1.6, 4.8, 0.14, seed); z.location = HALO
        mat(z, None, GELB, 7.0); hide(z, 1.12, 1.78)
        for f in range(F(1.12), F(1.75) + 1, 2):
            on = ((f - F(1.12)) // 2) % 2 == (off // 2)
            s = rnd.uniform(0.7, 1.25) if on else 0.001
            z.scale = (s, s * 0.8, s); z.keyframe_insert("scale", frame=f)
            z.rotation_euler = (0, rnd.uniform(-0.3, 0.3), 0); z.keyframe_insert("rotation_euler", frame=f)
        stepped(z)
        keys(z, "scale", [(1.74, (0.6, 0.5, 0.6)), (1.78, (0.001,) * 3)])
    # Fliegende Funken-Pillen in Boegen (Schwerkraft), in Flugrichtung gedreht
    for i in range(22):
        t0 = 1.12 + rnd.random() * 0.25; life = 0.35 + rnd.random() * 0.3
        ang = rnd.uniform(-0.3, math.pi + 0.3)   # eher nach oben und zur Seite
        sp = rnd.uniform(12, 24)
        v = Vector((math.cos(ang) * sp, rnd.uniform(-3, 3), math.sin(ang) * sp))
        g = Vector((0, 0, -32))
        q = quad("Funke%02d" % i, rnd.uniform(1.1, 2.0), 0.5); mat(q, "Pulsar_Funke", WEISS, 3.5)
        def pos(t, t0=t0, v=v):
            dt = max(0, t - t0); return HALO + v * dt + g * (0.5 * dt * dt)
        for f in range(F(t0), F(t0 + life) + 1):
            t = (f - 1) / FPS; vel = v + g * max(0, t - t0)
            q.location = pos(t); q.keyframe_insert("location", frame=f)
            q.rotation_euler = (math.pi / 2, -math.atan2(vel.z, vel.x), 0); q.keyframe_insert("rotation_euler", frame=f)
        fades(q, [(t0, 1), (t0 + life * 0.7, 1), (t0 + life, 0)])
        keys(q, "scale", [(t0, (1, 1, 1)), (t0 + life, (0.6, 0.3, 1))]); hide(q, t0, t0 + life + 0.02)
    # Grosser Zackenstern-Blitz (1,60-1,66 s), dazu kurzer Pink-Blitz und Wackeln
    bs = quad("Blitzstern", 11, 11); facing_cam(bs); bs.location = HALO; mat(bs, "Pulsar_Blitzstern", WEISS, 4.0, mode="ALPHA")
    keys(bs, "scale", [(1.60, (0.5,) * 3), (1.63, (1.25,) * 3), (1.66, (1.4,) * 3)])
    fades(bs, [(1.60, 1), (1.63, 1), (1.66, 0)]); hide(bs, 1.60, 1.67)

# ---------------------------------------------------------------- Phase 3: Kugel pulsiert und fliegt zum Gegner (1,72-2,50 s)
# Kugel = Halo-Scheibe + weisser Kern + Glanzstern. Drei Pulse, jeder groesser (Pulsar tickt),
# jeder Puls schickt einen duennen Ring raus. Dann Flug im Bogen mit Schweif und Nachbildern.
def kugel_pos(t):
    if t <= 2.25:
        return HALO
    u = min(1, (t - 2.25) / (IMPACT - 2.25))
    return bezier(HALO, Vector((0, 0, 7.5)), HIT, ease_in(u) * 0.75 + u * 0.25)

def phase_kugel(cam):
    k = empty("Kugel", HALO)
    glow = disc("KugelSchein", 1.5); billboard(glow, cam); glow.parent = k; mat(glow, "Pulsar_Scheibe", ORANGE, 4.0)
    core = disc("KugelKern", 0.75); billboard(core, cam); core.parent = k; mat(core, "Pulsar_Scheibe", WEISS, 6.0)
    star = disc("KugelStern", 1.3); billboard(star, cam); star.parent = k; mat(star, "Pulsar_Stern", GELB, 3.0)
    for o in (glow, core, star):
        hide(o, 1.72, IMPACT + 0.02)
    keys(star, "rotation_euler", [(1.72, (0, 0, 0)), (IMPACT, (0, 0, 3.0))])
    pulses = [(1.88, 1.25), (2.05, 1.4), (2.2, 1.6)]
    sk = [(1.72, (0.6,) * 3), (1.8, (1.0,) * 3)]
    for tp, amp in pulses:
        sk += [(tp - 0.04, (1.0,) * 3), (tp, (amp,) * 3), (tp + 0.08, (1.0,) * 3)]
    sk += [(IMPACT - 0.02, (1.3,) * 3)]
    keys(k, "scale", sk)
    for n, (tp, amp) in enumerate(pulses):
        r = torus("Puls%d" % n, 1.0, 0.05); billboard(r, cam); r.location = HALO; mat(r, None, ORANGE, 6.0)
        keys(r, "scale", [(tp, (0.4,) * 3), (tp + 0.22, (2.2 + n * 0.8,) * 3)])
        fades(r, [(tp, 1), (tp + 0.22, 0)]); hide(r, tp, tp + 0.24)
    # Flug: Position pro Bild, Schweif zeigt entgegen der Flugrichtung
    bake_loc(k, 1.72, IMPACT, kugel_pos)
    tail = quad("Schweif", 5.0, 1.6, pivot="left"); mat(tail, "Pulsar_Schweif", ORANGE, 4.0)
    tail2 = quad("SchweifKern", 3.2, 0.7, pivot="left"); mat(tail2, "Pulsar_Schweif", WEISS, 5.0)
    for q in (tail, tail2):
        hide(q, 2.27, IMPACT + 0.01)
        for f in range(F(2.27), F(IMPACT) + 1):
            t = (f - 1) / FPS; p = kugel_pos(t); pp = kugel_pos(t - 1 / FPS); d = p - pp
            sp = d.length * FPS
            q.location = p; q.keyframe_insert("location", frame=f)
            q.rotation_euler = (math.pi / 2, -math.atan2(-d.z, -d.x) if d.length > 1e-4 else 0, 0); q.keyframe_insert("rotation_euler", frame=f)
            q.scale = (min(2.2, 0.3 + sp / 40), 1, 1); q.keyframe_insert("scale", frame=f)
    # Nachbilder: drei Kopien des Scheins, die 1/2/3 Bilder hinterherhaengen
    for n in range(1, 4):
        a = disc("Nachbild%d" % n, 1.2 - n * 0.2); billboard(a, cam); mat(a, "Pulsar_Scheibe", ORANGE, 2.5 - n * 0.6)
        hide(a, 2.30, IMPACT)
        for f in range(F(2.30), F(IMPACT) + 1):
            a.location = kugel_pos((f - 1 - n) / FPS); a.keyframe_insert("location", frame=f)

# ---------------------------------------------------------------- Bildschirm-Blitze (nur Besitzer in Roblox)
def overlay(cam, name, color, pairs, mode="ALPHA", strength=1.0, img=None):
    q = quad(name, 3.0, 1.8); q.parent = cam; q.location = (0, 0, -1.0)
    mat(q, img, color, strength, mode=mode); fades(q, pairs)
    return q

# ---------------------------------------------------------------- Phase 4: Impact-Frames beim Einschlag (Bild F(2.50) .. +4)
# Bild 76: kleine gelbweisse Halbkuppel am Gegner (das erste Aufplatzen).
# Bild 77: invertiert: rosa-weisser Grund, Figuren/Kuppel/Speedlines schwarz.
# Bild 78-79: ganz weiss. Bild 80-82: Weiss klingt ab, die grosse Kuppel steht schon.
# Roblox (nur Besitzer): ColorCorrection (Saturation -1, Contrast 1, Tint rosa), Highlight schwarz
# auf beiden Figuren, ScreenGui-Bild der Speedlines, Bilder ueber RenderStepped zaehlen.
def impact_frames(cam):
    f0 = F(IMPACT)
    sc = bpy.context.scene
    ng = bpy.data.node_groups.get("PS_Comp")
    if ng:
        bpy.data.node_groups.remove(ng)
    ng = bpy.data.node_groups.new("PS_Comp", "CompositorNodeTree")
    ng.interface.new_socket("Image", in_out="OUTPUT", socket_type="NodeSocketColor")
    N = ng.nodes; L = ng.links
    rl = N.new("CompositorNodeRLayers"); out = N.new("NodeGroupOutput")
    imp = N.new("ShaderNodeValue"); imp.name = "Impact"
    inv = N.new("CompositorNodeInvert"); L.new(rl.outputs["Image"], inv.inputs["Color"])
    bw = N.new("CompositorNodeRGBToBW"); L.new(inv.outputs[0], bw.inputs["Image"])
    rp = N.new("ShaderNodeValToRGB"); L.new(bw.outputs[0], rp.inputs["Factor"])
    cr = rp.color_ramp; cr.interpolation = "CONSTANT"
    cr.elements[0].position = 0.0; cr.elements[0].color = (0.04, 0.01, 0.05, 1)       # helle Dinge -> schwarz
    cr.elements[1].position = 0.9; cr.elements[1].color = (1.0, 0.86, 0.95, 1)        # dunkler Grund -> rosa-weiss (Figuren bleiben schwarz)
    mix = N.new("ShaderNodeMix"); mix.data_type = "RGBA"
    L.new(imp.outputs[0], mix.inputs[0]); L.new(rl.outputs["Image"], mix.inputs[6]); L.new(rp.outputs[0], mix.inputs[7])
    L.new(mix.outputs[2], out.inputs[0])
    sc.compositing_node_group = ng
    for f, a in [(f0, 0), (f0 + 1, 1), (f0 + 2, 0)]:
        imp.outputs[0].default_value = a; imp.outputs[0].keyframe_insert("default_value", frame=f)
    # Bild 76: kleine Halbkuppel, flach gelbweiss
    d0 = hemisphere("Vorkuppel", 3.6, 24, 12); d0.location = T; mat(d0, None, (1.0, 0.92, 0.55), 2.5, mode="ALPHA", hot=0.6, opaque=True)
    d1 = hemisphere("VorkuppelRand", 3.75, 24, 12); d1.location = T; mat(d1, None, ORANGE, 5.0, rim=1.5)
    for o in (d0, d1):
        hide(o, (f0 - 1) / FPS, (f0 + 1) / FPS)
    # Speedlines liegen nur im invertierten Bild drauf (weiss gerendert -> nach Invertierung schwarz)
    lines = overlay(cam, "Speedlines", WEISS, [], mode="ADD", strength=4.0, img="Pulsar_Speedlines")
    fade_f(lines, [(f0, 0), (f0 + 1, 1), (f0 + 2, 0)])
    hide(lines, f0 / FPS, (f0 + 2) / FPS)
    # Weissblende Bild 78-79, dann schnell runter
    w = overlay(cam, "BlitzWeissImpact", WEISS, [])
    fade_f(w, [(f0 + 1, 0), (f0 + 2, 1), (f0 + 3, 1), (f0 + 4, 0.6), (f0 + 6, 0)])
    hide(w, (f0 + 1) / FPS, (f0 + 7) / FPS)
    for win in bpy.context.window_manager.windows:
        for a in win.screen.areas:
            if a.type == "VIEW_3D":
                a.spaces.active.shading.use_compositor = "ALWAYS"

# ---------------------------------------------------------------- Phase 5: Feuerkuppel am Gegner (2,53-4,40 s)
# Halbkugel mit Flammenstreifen (Textur laeuft um die Kuppel und nach oben), weissgluehender
# Kern, pinker Fresnel-Rand, kochender Flammensaum am Fuss, Truemmer, Glut, Schockwelle,
# aufsteigende Funken. Zwei Pulse (3,3 / 3,9 s) mit Pink-Blitz. Waechst langsam weiter.
DOME_R = 7.8

def phase_kuppel(cam):
    t0 = IMPACT + 0.03
    dome = hemisphere("Kuppel", DOME_R); dome.location = T
    # Emission knapp unter 1, sonst clippt das Standard-Farbmanagement die orangen Streifen zu Weiss
    mat(dome, "Pulsar_Kuppel", WEISS, 0.95, mode="ALPHA", hot=0.7, urep=2.0, vrep=1.5, opaque=True)
    scroll(dome, t0, 4.5, du=0.6, dv=-1.1)
    rim = hemisphere("KuppelRand", DOME_R * 1.03); rim.location = T; mat(rim, None, MAGENTA, 2.0, rim=2.6)
    aura = hemisphere("KuppelAura", DOME_R * 1.12); aura.location = T; mat(aura, None, (1.0, 0.3, 0.25), 0.6, rim=2.0)
    grow = [(t0, (0.25,) * 3), (t0 + 0.07, (1.12,) * 3), (t0 + 0.13, (0.96,) * 3), (t0 + 0.2, (1.0,) * 3),
            (3.26, (1.08,) * 3), (3.3, (1.14,) * 3), (3.4, (1.1,) * 3), (3.86, (1.16,) * 3), (3.9, (1.23,) * 3), (4.0, (1.19,) * 3),
            (4.3, (1.22,) * 3), (4.36, (1.3,) * 3), (4.5, (1.34,) * 3)]
    for o in (dome, rim, aura):
        keys(o, "scale", grow); hide(o, t0, 4.52)
        fades(o, [(4.36, 1), (4.5, 0)])
    # Pulse: Kuppel wird weissgluehend, Rand pink, dazu Bildschirm-Pink
    strength(dome, [(t0, 0.95), (t0 + 0.05, 2.4), (t0 + 0.25, 0.95), (3.26, 0.95), (3.3, 2.6), (3.45, 0.95), (3.86, 0.95), (3.9, 3.0), (4.05, 0.95),
                    (4.3, 1.1), (4.36, 8.0)])
    strength(rim, [(t0, 2.0), (3.3, 5.0), (3.45, 2.0), (3.9, 6.0), (4.05, 2.0)])
    # Hintergrund bleibt dunkel, nur die Pulse kippen das Bild kurz ins Rosa (wie im Vorbild)
    overlay(cam, "BlitzPink1", PINK, [(3.28, 0), (3.3, 0.45), (3.36, 0.4), (3.46, 0)])
    overlay(cam, "BlitzPink2", PINK, [(3.88, 0), (3.9, 0.55), (3.96, 0.5), (4.08, 0)])
    # Flammensaum am Fuss: Zylindermantel, Textur laeuft nach oben
    saum = wall("Saum", DOME_R * 1.02, 3.2, urep=3.0, flare=1.18); saum.location = T
    # Textur laeuft nur seitlich (senkrecht waere die Kante beim Wrap sichtbar); das Kochen kommt
    # aus Hoehen-Flackern in 2-Bild-Schritten
    mat(saum, "Pulsar_Saum", WEISS, 3.0, urep=1.0); scroll(saum, t0, 4.5, du=0.6)
    hide(saum, t0, 4.52); fades(saum, [(t0, 0), (t0 + 0.08, 1), (4.3, 1), (4.42, 0)])
    sz = dict(grow)
    for f in range(F(t0), F(4.5) + 1, 2):
        t = (f - 1) / FPS
        # Grundgroesse aus der Kuppel-Kurve (lineare Naeherung zwischen den Stuetzstellen)
        ks = sorted(sz.items()); base = ks[-1][1][0]
        for (ta, sa), (tb, sb) in zip(ks, ks[1:]):
            if ta <= t <= tb:
                base = sa[0] + (sb[0] - sa[0]) * (t - ta) / max(1e-6, tb - ta); break
        if t < ks[0][0]:
            base = ks[0][1][0]
        saum.scale = (base, base, base * rnd.uniform(0.8, 1.2)); saum.keyframe_insert("scale", frame=f)
    stepped(saum)
    # Bodenschockwelle + Glut
    sw = disc("Schockwelle", 3.0); sw.location = T + Vector((0, 0, 0.06)); mat(sw, "Pulsar_Ring", ORANGE, 5.0)
    keys(sw, "scale", [(IMPACT, (0.5, 0.5, 1)), (IMPACT + 0.3, (5.0, 5.0, 1))])
    fades(sw, [(IMPACT, 1), (IMPACT + 0.12, 0.7), (IMPACT + 0.3, 0)]); hide(sw, IMPACT, IMPACT + 0.32)
    gl = disc("Glut", 11.0); gl.location = T + Vector((0, 0, 0.04)); mat(gl, "Pulsar_Glut", WEISS, 2.5, mode="ALPHA")
    keys(gl, "scale", [(IMPACT, (0.4, 0.4, 1)), (IMPACT + 0.3, (1.0, 1.0, 1)), (4.5, (1.15, 1.15, 1))])
    fades(gl, [(IMPACT, 0), (IMPACT + 0.1, 1), (5.0, 1), (DUR, 0)]); hide(gl, IMPACT)
    strength(gl, [(4.3, 2.5), (4.36, 6.0), (4.9, 1.6), (DUR, 0.6)])
    # Truemmer: dunkle Brocken fliegen vom Fuss der Kuppel in Boegen weg
    for i in range(12):
        ang = rnd.uniform(0, 2 * math.pi); sp = rnd.uniform(9, 20); up = rnd.uniform(10, 22)
        v = Vector((math.cos(ang) * sp, math.sin(ang) * sp * 0.5, up)); g = Vector((0, 0, -40))
        p0 = T + Vector((math.cos(ang), math.sin(ang) * 0.5, 0)) * rnd.uniform(1.0, 3.0)
        c = chunk("Brocken%02d" % i, rnd.uniform(0.35, 0.8), 500 + i); mat(c, None, (0.06, 0.03, 0.05), 1.0, mode="ALPHA", opaque=True)
        ts = IMPACT + rnd.uniform(0.0, 0.08); life = rnd.uniform(0.7, 1.1)
        rot = Vector((rnd.uniform(-6, 6), rnd.uniform(-6, 6), rnd.uniform(-6, 6)))
        for f in range(F(ts), F(ts + life) + 1):
            dt = (f - 1) / FPS - ts
            c.location = p0 + v * dt + g * (0.5 * dt * dt); c.keyframe_insert("location", frame=f)
            c.rotation_euler = rot * dt; c.keyframe_insert("rotation_euler", frame=f)
        hide(c, ts, ts + life)
    # Funken, die aus der Kuppel nach oben treiben
    for i in range(24):
        ts = t0 + 0.1 + rnd.random() * 1.4; life = rnd.uniform(0.5, 0.9)
        az = rnd.uniform(0, 2 * math.pi); el = rnd.uniform(0.25, 1.3)
        n = Vector((math.cos(az) * math.cos(el), math.sin(az) * math.cos(el), math.sin(el)))
        p0 = T + n * DOME_R * 1.0
        d = disc("Glimmer%02d" % i, rnd.uniform(0.18, 0.4)); billboard(d, cam); mat(d, "Pulsar_Scheibe", (1.0, 0.6, 0.15), 6.0)
        keys(d, "location", [(ts, p0), (ts + life, p0 + n * rnd.uniform(2, 5) + Vector((0, 0, rnd.uniform(2, 5))))])
        fades(d, [(ts, 0), (ts + 0.08, 1), (ts + life * 0.6, 0.8), (ts + life, 0)]); hide(d, ts, ts + life + 0.02)

# ---------------------------------------------------------------- Phase 6: Weissblende (4,30-5,15 s)
# Die Kuppel flammt weiss auf, das Bild wird ganz weiss, kippt ins Rosa und gibt die Szene frei.
def phase_blende(cam):
    overlay(cam, "BlitzPinkEnde", PINK, [(4.30, 0), (4.33, 0.8), (4.40, 0.3), (4.46, 0)])
    overlay(cam, "BlitzWeissEnde", WEISS, [(4.34, 0), (4.40, 1.0), (4.76, 1.0), (4.9, 0.7), (5.15, 0)])
    overlay(cam, "NachRosa", (1.0, 0.75, 0.88), [(4.76, 0), (4.9, 0.45), (5.3, 0.25), (DUR, 0)])

# ---------------------------------------------------------------- Phase 7: Nachgluehen (4,8-5,8 s)
# Am Krater schwebt ein kleiner Ring (der Pulsar-Rest), Rauch steigt, Funken rieseln.
def phase_rest(cam):
    rg = empty("RestTraeger", T + Vector((0, 0, 2.2)))
    ring = torus("RestRing", 2.0, 0.06); ring.parent = rg; mat(ring, None, ORANGE, 5.0)
    inner = torus("RestRingInnen", 1.8, 0.03); inner.parent = rg; mat(inner, None, WEISS, 3.0)
    for o in (ring, inner):
        hide(o, 4.5, DUR); fades(o, [(4.5, 1), (5.2, 1), (DUR, 0)])
    keys(rg, "rotation_euler", [(4.5, (math.pi / 2, 0, 0)), (DUR, (math.pi / 2, 0, 2.4))])
    keys(rg, "location", [(4.5, T + Vector((0, 0, 2.2))), (DUR, T + Vector((0, 0, 4.5)))])
    keys(rg, "scale", [(4.5, (1.0,) * 3), (DUR, (0.35,) * 3)])
    strength(ring, [(4.8, 5.0), (5.0, 9.0), (5.2, 5.0), (5.4, 8.0), (5.6, 4.0)])
    for i in range(7):
        p = T + Vector((rnd.uniform(-5, 5), rnd.uniform(-2, 2), rnd.uniform(0.5, 2.5)))
        r = disc("Rauch%d" % i, rnd.uniform(2.2, 3.6)); billboard(r, cam); mat(r, "Pulsar_Rauch", (0.5, 0.42, 0.5), 1.0, mode="ALPHA")
        ts = 4.4 + rnd.random() * 0.3
        keys(r, "location", [(ts, p), (DUR, p + Vector((rnd.uniform(-1, 1), 0, rnd.uniform(3, 6))))])
        keys(r, "scale", [(ts, (0.6,) * 3), (DUR, (1.6,) * 3)])
        keys(r, "rotation_euler", [(ts, (0, 0, 0)), (DUR, (0, 0, rnd.uniform(-1, 1)))])
        fades(r, [(ts, 0.0), (ts + 0.3, 0.85), (5.3, 0.6), (DUR, 0)]); hide(r, ts, DUR)
    for i in range(14):
        ts = 4.6 + rnd.random() * 0.6; p = T + Vector((rnd.uniform(-7, 7), rnd.uniform(-3, 3), rnd.uniform(5, 10)))
        d = disc("Asche%02d" % i, rnd.uniform(0.12, 0.25)); billboard(d, cam); mat(d, "Pulsar_Scheibe", (1.0, 0.5, 0.1), 5.0)
        keys(d, "location", [(ts, p), (DUR, p + Vector((rnd.uniform(-1.5, 1.5), 0, -rnd.uniform(3, 6))))])
        fades(d, [(ts, 0), (ts + 0.1, 1), (DUR - 0.2, 0.7), (DUR, 0)]); hide(d, ts, DUR)

# ---------------------------------------------------------------- Figuren + Kamera
def figuren(cam):
    me = import_bear(ROOT + r"\Export\Pet_Pulsar.fbx", "Pulsar_Baerchi", S, 90)
    en = import_bear(ROOT + r"\Export\Bear_Braunbaer.fbx", "Gegner_Baerchi", T, -90)
    base_s = S + Vector((0, 0, 1.32)); base_t = T + Vector((0, 0, 1.32))
    # Pulsar: duckt sich beim Aufladen, stoesst sich beim Bruch hoch, landet beim Flug der Kugel
    keys(me, "location", [(0, base_s), (0.5, base_s - Vector((0, 0, 0.25))), (0.85, base_s - Vector((0, 0, 0.25))),
                          (1.12, base_s + Vector((0, 0, 1.0))), (1.7, base_s + Vector((0, 0, 1.0))), (2.0, base_s)])
    b = me.scale.copy()   # FBX-Import kann eine eigene Grundskalierung haben, nur relativ stauchen
    sq = lambda x, y, z: (b.x * x, b.y * y, b.z * z)
    keys(me, "scale", [(0.5, sq(1, 1, 1)), (0.85, sq(1.1, 1.1, 0.85)), (1.12, sq(0.9, 0.9, 1.2)), (1.4, sq(1, 1, 1))])
    # Gegner: Rueckstoss im Einschlag (unter der Kuppel), liegt, trottet nach der Blende zurueck
    # Rueckstoss bleibt im Bild (Kamera-Halbbreite ~15,6 bei y=0)
    keys(en, "location", [(IMPACT - 0.01, base_t), (IMPACT + 0.25, base_t + Vector((3.0, 0, 1.5))), (IMPACT + 0.5, base_t + Vector((3.8, 0, 0))),
                          (4.8, base_t + Vector((3.8, 0, 0))), (5.6, base_t + Vector((0.8, 0, 0)))])
    keys(en, "rotation_euler", [(IMPACT - 0.01, (0, 0, math.radians(-90))), (IMPACT + 0.3, (0, math.radians(35), math.radians(-90))),
                                (4.8, (0, math.radians(35), math.radians(-90))), (5.15, (0, 0, math.radians(-90)))])
    def shake(t0, dur, power):
        n = int(dur * FPS)
        for k in range(n + 1):
            f = t0 + k / FPS; damp = 1 - k / max(1, n)
            key(cam, "location", f, CAM_POS + Vector((rnd.uniform(-1, 1), 0, rnd.uniform(-1, 1))) * power * damp)
    key(cam, "location", 0, CAM_POS); key(cam, "location", 1.1, CAM_POS)
    shake(1.12, 0.15, 0.18); key(cam, "location", 1.4, CAM_POS); key(cam, "location", 1.58, CAM_POS)
    shake(1.60, 0.12, 0.25); key(cam, "location", 1.8, CAM_POS); key(cam, "location", IMPACT - 0.04, CAM_POS)
    shake(IMPACT, 0.5, 0.7); key(cam, "location", 3.2, CAM_POS)
    shake(3.3, 0.15, 0.2); key(cam, "location", 3.6, CAM_POS)
    shake(3.9, 0.15, 0.25); key(cam, "location", 4.28, CAM_POS)
    shake(4.33, 0.25, 0.35); key(cam, "location", DUR, CAM_POS)

def build():
    global COL
    exec(open(TEXPY, encoding="utf-8").read(), {"__name__": "tex"})
    COL = reset()
    cam = stage()
    phase_ring(cam); phase_bruch(cam)
    overlay(cam, "BlitzPinkBruch", PINK, [(1.60, 0), (1.62, 0.5), (1.66, 0)])
    phase_kugel(cam)
    impact_frames(cam)
    phase_kuppel(cam); phase_blende(cam); phase_rest(cam)
    figuren(cam)
    for o in COL.objects:
        o.visible_shadow = False  # Roblox: Effekte ohne Schatten
    bpy.context.scene.frame_set(F(0.4))
    return {"objects": len(COL.objects)}

RESULT = build()
