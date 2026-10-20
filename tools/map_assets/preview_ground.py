# Vorschau-Render der Boden-Meshes (Blender-MCP). Setzt build_map_ground.py voraus (Szene MAP_ASSETS).
import bpy, math, os, bmesh
from mathutils import Vector
OUT = r"C:\Users\admin\Documents\Claude Downloads\RBL\docs\map_stilbibel"
src = bpy.data.scenes["MAP_ASSETS"]
orig = bpy.context.window.scene
pv = bpy.data.scenes.get("MAP_PREVIEW") or bpy.data.scenes.new("MAP_PREVIEW")
for o in list(pv.objects): bpy.data.objects.remove(o, do_unlink=True)
bpy.context.window.scene = pv
def put(n, loc, rot=0.0, sc=(1, 1, 1)):
    o = bpy.data.objects.new(n, src.objects["Map_" + n].data)
    o.location = loc; o.rotation_euler = (0, 0, rot); o.scale = sc; pv.collection.objects.link(o); return o
R = 72.0
bm = bmesh.new(); bmesh.ops.create_cone(bm, cap_ends=True, segments=64, radius1=R, radius2=R, depth=1.0)
me = bpy.data.meshes.new("Ground"); bm.to_mesh(me); bm.free()
g = bpy.data.objects.new("Ground", me); g.location = (0, 0, -0.5); pv.collection.objects.link(g)
ca = me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
def s2l(c): c /= 255; return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
for d in ca.data: d.color = (s2l(58), s2l(140), s2l(62), 1)
for i in range(-4, 4):
    for j in range(-4, 4):
        if (i + j) % 2 == 0:
            x, y = (i + .5) * 24, (j + .5) * 24
            if all(math.hypot(x + cx, y + cy) <= R - 3 for cx in (-12, 12) for cy in (-12, 12)):
                put("Wiese_A" if (i * 3 + j) % 3 else "Wiese_B", (x, y, 0.03), 0)
N = math.ceil(2 * math.pi * (R - 1.5) / 24)
for k in range(N):
    a = 2 * math.pi * k / N
    put("Ufer_Gerade", ((R - 2.6) * math.cos(a), (R - 2.6) * math.sin(a), 0.0), a + math.pi / 2, (2 * math.pi * (R - 2.6) / N / 24 * 1.04, 1, 1))
for k, (a, r, rock) in enumerate([(0.4, 60, "A"), (1.7, 61, "B"), (2.6, 59, "A"), (3.9, 61, "B"), (5.0, 60, "A")]):
    x, y = r * math.cos(a), r * math.sin(a)
    put("Randfels_" + rock, (x, y, 0), a * 3)
    put("Kristall_A" if k % 2 == 0 else "Kristall_B", (x + 0.7, y + 0.4, 1.7 if rock == "A" else 1.3), a, (0.9, 0.9, 0.9))
pv.render.engine = 'BLENDER_WORKBENCH'; sh = pv.display.shading; sh.light = 'STUDIO'; sh.color_type = 'VERTEX'; sh.show_cavity = False
pv.render.resolution_x = 1200; pv.render.resolution_y = 800
w = bpy.data.worlds.new("PW"); w.use_nodes = False; w.color = (0.55, 0.78, 0.9); pv.world = w
cd = bpy.data.cameras.new("PC"); cam = bpy.data.objects.new("PC", cd); pv.collection.objects.link(cam); pv.camera = cam; cd.lens = 35
for name, loc, tgt in (("boden_schraeg", (0, -150, 95), (0, 0, 0)), ("boden_nah", (62, -30, 14), (58, 14, 0))):
    cam.location = loc; cam.rotation_euler = (Vector(tgt) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    pv.render.filepath = os.path.join(OUT, "Map_%s.png" % name); bpy.ops.render.render(write_still=True)
bpy.context.window.scene = orig
result = {"ok": True}
