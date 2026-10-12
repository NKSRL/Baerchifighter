"""
bl.py — gemeinsame Blender-Helfer fuer die UI-Texturen (Ei-Menue, Ei-Baum).

Laeuft mit Blender als Python-Modul (`pip install bpy`, Blender 5.x) oder
in Blender selbst (`blender -b -P tools/art/render_eggs.py`).

Stil (passend zu assets/icons): dicker dunkler Umriss (Theme.outline
24/20/38), weiches Licht von oben links, scharfer weisser Glanzpunkt,
kraeftiger Lichtsaum an der Schattenkante. Alles ist "gemalt" mit
Emissions-Shadern (keine echten Lampen) — so ist jedes Bild exakt
reproduzierbar und rendert in Sekunden auf der CPU.
"""

import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector

OUTLINE = (24, 20, 38)

# Licht kommt von oben links und etwas von vorne (Kamera blickt entlang +Y).
LIGHT = Vector((-0.55, -0.62, 0.62)).normalized()
VIEW = Vector((0.0, -1.0, 0.0))


def out_dir(*parts):
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.abspath(os.path.join(here, "..", ".."))
    path = os.path.join(root, "assets", "ui", *parts)
    os.makedirs(path, exist_ok=True)
    return path


def srgb(c):
    """0..255-sRGB → lineare RGBA fuer Blender."""
    def ch(v):
        v = v / 255.0
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return (ch(c[0]), ch(c[1]), ch(c[2]), 1.0)


def lerp(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = False
    scene.cycles.max_bounces = 0
    scene.cycles.transparent_max_bounces = 16
    scene.render.film_transparent = True
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    scene.render.filter_size = 1.2
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[1].default_value = 0.0
    scene.world = world
    return scene


def camera(scene, width, height, ortho_scale, z=0.0, x=0.0):
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = ortho_scale
    cam = bpy.data.objects.new("Cam", cam_data)
    cam.location = (x, -20.0, z)
    cam.rotation_euler = (math.radians(90), 0, 0)
    scene.collection.objects.link(cam)
    scene.camera = cam
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = 100
    return cam


def render(scene, path):
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("  →", os.path.relpath(path))


def clear_objects():
    for obj in list(bpy.data.objects):
        if obj.type != "CAMERA":
            bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)
    for mat in list(bpy.data.materials):
        if mat.users == 0:
            bpy.data.materials.remove(mat)


# --------------------------------------------------------------------------
# Knoten-Baukasten
# --------------------------------------------------------------------------

class G:
    """Kleiner Knoten-Baukasten: haelt den Node-Tree und baut Rechenketten."""

    def __init__(self, mat):
        self.nt = mat.node_tree
        self.nodes = self.nt.nodes
        self.links = self.nt.links
        for n in list(self.nodes):
            self.nodes.remove(n)
        self.out = self.nodes.new("ShaderNodeOutputMaterial")
        self.geo_node = self.nodes.new("ShaderNodeNewGeometry")
        self.tc = self.nodes.new("ShaderNodeTexCoord")

    def link(self, a, b):
        self.links.new(a, b)

    def _in(self, node, idx, val):
        sock = node.inputs[idx]
        if hasattr(val, "is_output") or isinstance(val, bpy.types.NodeSocket):
            self.link(val, sock)
        elif isinstance(val, (tuple, list, Vector)):
            v = list(val)
            n = len(sock.default_value)
            sock.default_value = (v + [1.0] * n)[:n]
        else:
            sock.default_value = val

    # Skalare
    def math(self, op, a, b=0.0, c=None, clamp=False):
        n = self.nodes.new("ShaderNodeMath")
        n.operation = op
        n.use_clamp = clamp
        self._in(n, 0, a)
        self._in(n, 1, b)
        if c is not None:
            self._in(n, 2, c)
        return n.outputs[0]

    def add(self, a, b): return self.math("ADD", a, b)
    def sub(self, a, b): return self.math("SUBTRACT", a, b)
    def mul(self, a, b): return self.math("MULTIPLY", a, b)
    def maxi(self, a, b): return self.math("MAXIMUM", a, b)
    def mini(self, a, b): return self.math("MINIMUM", a, b)
    def absf(self, a): return self.math("ABSOLUTE", a)
    def powf(self, a, b): return self.math("POWER", a, b)
    def clamp01(self, a): return self.math("ADD", a, 0.0, clamp=True)

    def smooth(self, x, lo, hi):
        """0 bei lo, 1 bei hi (auch umgekehrt: lo > hi fuer fallend)."""
        n = self.nodes.new("ShaderNodeMapRange")
        n.interpolation_type = "SMOOTHSTEP"
        n.clamp = True
        self._in(n, 0, x)
        self._in(n, 1, lo)
        self._in(n, 2, hi)
        n.inputs[3].default_value = 0.0
        n.inputs[4].default_value = 1.0
        return n.outputs[0]

    # Vektoren
    def vmath(self, op, a, b=None, scale=None):
        n = self.nodes.new("ShaderNodeVectorMath")
        n.operation = op
        self._in(n, 0, a)
        if b is not None:
            self._in(n, 1, b)
        if scale is not None:
            n.inputs[3].default_value = scale
        key = "Value" if op in ("DOT_PRODUCT", "DISTANCE", "LENGTH") else "Vector"
        return n.outputs[key]

    def dot(self, a, b): return self.vmath("DOT_PRODUCT", a, b)
    def dist(self, a, b): return self.vmath("DISTANCE", a, b)

    def sep(self, v):
        n = self.nodes.new("ShaderNodeSeparateXYZ")
        self.link(v, n.inputs[0])
        return n.outputs[0], n.outputs[1], n.outputs[2]

    def comb(self, x, y, z):
        n = self.nodes.new("ShaderNodeCombineXYZ")
        self._in(n, 0, x)
        self._in(n, 1, y)
        self._in(n, 2, z)
        return n.outputs[0]

    # Farben
    def mix(self, fac, a, b, blend="MIX"):
        n = self.nodes.new("ShaderNodeMix")
        n.data_type = "RGBA"
        n.blend_type = blend
        n.clamp_result = False
        self._in(n, 0, fac)
        self._in(n, 6, a)
        self._in(n, 7, b)
        return n.outputs[2]

    def rgb(self, c):
        n = self.nodes.new("ShaderNodeRGB")
        n.outputs[0].default_value = srgb(c) if max(c[:3]) > 1.0 or isinstance(c[0], int) else c
        return n.outputs[0]

    def noise(self, vec, scale, detail=2.0, rough=0.5, w=None):
        n = self.nodes.new("ShaderNodeTexNoise")
        if w is not None:
            n.noise_dimensions = "4D"
            self._in(n, "W", w)
        self._in(n, "Vector", vec)
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = detail
        n.inputs["Roughness"].default_value = rough
        return n.outputs["Fac"]

    def voronoi(self, vec, scale, feature="F1", randomness=1.0, w=None):
        n = self.nodes.new("ShaderNodeTexVoronoi")
        n.feature = feature
        if w is not None:
            n.voronoi_dimensions = "4D"
            self._in(n, "W", w)
        self._in(n, "Vector", vec)
        n.inputs["Scale"].default_value = scale
        n.inputs["Randomness"].default_value = randomness
        return n.outputs["Distance"], (n.outputs["Color"] if "Color" in n.outputs else None)

    def bw(self, color):
        n = self.nodes.new("ShaderNodeRGBToBW")
        self.link(color, n.inputs[0])
        return n.outputs[0]

    # Ausgabe: Farbe + Deckkraft (Emission, kein Licht)
    def finish(self, color, alpha=1.0):
        em = self.nodes.new("ShaderNodeEmission")
        self._in(em, 0, color)
        em.inputs[1].default_value = 1.0
        if alpha == 1.0:
            self.link(em.outputs[0], self.out.inputs[0])
            return
        tr = self.nodes.new("ShaderNodeBsdfTransparent")
        mx = self.nodes.new("ShaderNodeMixShader")
        self._in(mx, 0, alpha)
        self.link(tr.outputs[0], mx.inputs[1])
        self.link(em.outputs[0], mx.inputs[2])
        self.link(mx.outputs[0], self.out.inputs[0])

    @property
    def normal(self): return self.geo_node.outputs["Normal"]
    @property
    def incoming(self): return self.geo_node.outputs["Incoming"]
    @property
    def backfacing(self): return self.geo_node.outputs["Backfacing"]
    @property
    def obj(self): return self.tc.outputs["Object"]
    @property
    def gen(self): return self.tc.outputs["Generated"]
    @property
    def uv(self): return self.tc.outputs["UV"]


def material(name):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    return mat


def toon(g, base, lit_scale=1.0, shadow_tint=(0.52, 0.46, 0.66), rim=(255, 236, 190),
         rim_strength=0.85, spec=True, spec_size=0.993, sheen=0.22, soft=(-0.35, 0.8),
         normal=None):
    """Die Hausbeleuchtung: weiches Licht oben links, kuehler Schatten,
    Lichtsaum an der Schattenkante, scharfer Glanzpunkt. `base` ist ein
    Farb-Socket (linear). Gibt einen Farb-Socket zurueck."""
    n = normal if normal is not None else g.normal
    lam = g.dot(n, tuple(LIGHT))
    light = g.smooth(lam, soft[0], soft[1])
    shadow = g.mix(1.0, base, tuple(shadow_tint) + (1.0,), "MULTIPLY")
    col = g.mix(light, shadow, base)
    if lit_scale != 1.0:
        col = g.mix(g.smooth(lam, 0.2, 0.9), col, g.mix(1.0, col, (lit_scale,) * 3 + (1.0,), "MULTIPLY"))
    # Weicher Schein oben links
    col = g.mix(g.mul(g.smooth(lam, 0.7, 0.98), sheen), col, (1, 1, 1, 1))
    # Lichtsaum: Rand (Fresnel) auf der Schattenseite
    facing = g.absf(g.dot(n, g.incoming))
    edge = g.smooth(facing, 0.42, 0.16)
    dark_side = g.smooth(lam, 0.15, -0.35)
    rim_mask = g.mul(g.mul(edge, dark_side), rim_strength)
    rim_col = g.mix(0.65, base, srgb(rim))
    col = g.mix(rim_mask, col, rim_col)
    if spec:
        h = (LIGHT + Vector((0, -1, 0))).normalized()
        s = g.dot(n, tuple(h))
        col = g.mix(g.smooth(s, spec_size - 0.006, spec_size), col, (1, 1, 1, 1))
        # kleiner zweiter Glanzpunkt etwas tiefer
        h2 = (Vector((-0.62, -0.7, 0.05)) + Vector((0, -1, 0))).normalized()
        s2 = g.dot(n, tuple(h2))
        col = g.mix(g.mul(g.smooth(s2, 0.9982, 0.9992), 0.95), col, (1, 1, 1, 1))
    return col


def outline_material(color=OUTLINE):
    """Inverted Hull: Vorderseiten durchsichtig, Rueckseiten dunkel →
    nur der Rand ausserhalb des Objekts bleibt als Umriss stehen."""
    mat = material("Outline")
    g = G(mat)
    em = g.nodes.new("ShaderNodeEmission")
    em.inputs[0].default_value = srgb(color)
    tr = g.nodes.new("ShaderNodeBsdfTransparent")
    mx = g.nodes.new("ShaderNodeMixShader")
    g.link(g.backfacing, mx.inputs[0])
    g.link(tr.outputs[0], mx.inputs[1])
    g.link(em.outputs[0], mx.inputs[2])
    g.link(mx.outputs[0], g.out.inputs[0])
    return mat


def flat_material(name, color, alpha=1.0):
    mat = material(name)
    g = G(mat)
    g.finish(srgb(color) if isinstance(color[0], int) else color, alpha)
    return mat


def add_hull(obj, thickness, color=OUTLINE):
    """Dunkler Umriss um `obj` (Kopie, entlang der Normalen aufgeblasen)."""
    hull = obj.copy()
    hull.data = obj.data.copy()
    hull.name = obj.name + "_Hull"
    for mod in list(hull.modifiers):
        hull.modifiers.remove(mod)
    bpy.context.scene.collection.objects.link(hull)
    bm = bmesh.new()
    bm.from_mesh(hull.data)
    bm.normal_update()
    for v in bm.verts:
        v.co += v.normal * thickness
    bm.to_mesh(hull.data)
    bm.free()
    hull.data.materials.clear()
    hull.data.materials.append(outline_material(color))
    for poly in hull.data.polygons:
        poly.use_smooth = True
    return hull


def link(obj):
    bpy.context.scene.collection.objects.link(obj)
    return obj


def mesh_obj(name, verts, faces, smooth=True):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    link(obj)
    if smooth:
        for p in mesh.polygons:
            p.use_smooth = True
    return obj


def uv_sphere(name, segments=96, rings=64):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=1.0)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    link(obj)
    for p in mesh.polygons:
        p.use_smooth = True
    return obj


def disc(name, radius=1.0, segments=96):
    """Kreisflaeche in der XZ-Ebene (zeigt zur Kamera)."""
    verts = [(0, 0, 0)] + [(math.cos(2 * math.pi * i / segments) * radius, 0,
                            math.sin(2 * math.pi * i / segments) * radius) for i in range(segments)]
    faces = [(0, i + 1, (i + 1) % segments + 1) for i in range(segments)]
    return mesh_obj(name, verts, faces, smooth=False)


def plane(name, w, h, x=0.0, z=0.0, y=0.0):
    verts = [(x - w / 2, y, z - h / 2), (x + w / 2, y, z - h / 2), (x + w / 2, y, z + h / 2), (x - w / 2, y, z + h / 2)]
    obj = mesh_obj(name, verts, [(0, 1, 2, 3)], smooth=False)
    me = obj.data
    uv = me.uv_layers.new(name="UV")
    for i, loop in enumerate(me.loops):
        vi = loop.vertex_index
        uv.data[i].uv = ((verts[vi][0] - (x - w / 2)) / w, (verts[vi][2] - (z - h / 2)) / h)
    return obj


def soft_shadow(name, width, height, z, y=1.5, alpha=0.42, x=0.0):
    """Kleiner ovaler Bodenschatten mit weichem Rand."""
    obj = disc(name, 1.0)
    obj.scale = (width / 2, 1, height / 2)
    obj.location = (x, y, z)
    mat = material(name)
    g = G(mat)
    r = g.vmath("LENGTH", g.obj)
    a = g.mul(g.smooth(r, 1.0, 0.45), alpha)
    g.finish(srgb(OUTLINE), a)
    obj.data.materials.append(mat)
    return obj


def args():
    """Argumente nach `--` (Blender-Stil) bzw. sys.argv[1:]."""
    if "--" in sys.argv:
        return sys.argv[sys.argv.index("--") + 1:]
    return sys.argv[1:]
