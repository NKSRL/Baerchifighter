# Vorschau der Baum-Meshes (Szene MAP_TREES muss existieren).
import bpy, os
from mathutils import Vector
OUT = r"C:\Users\admin\Documents\Claude Downloads\RBL\docs\map_stilbibel"
src = bpy.data.scenes["MAP_TREES"]; orig = bpy.context.window.scene
pv = bpy.data.scenes.get("TREES_PREVIEW") or bpy.data.scenes.new("TREES_PREVIEW")
for o in list(pv.objects): bpy.data.objects.remove(o, do_unlink=True)
bpy.context.window.scene = pv
names = ["Map_Baum_A", "Map_Baum_B", "Map_Baum_C", "Map_Baum_D", "Map_Stumpf_A", "Map_Blumen_A"]
for i, n in enumerate(names):
    o = bpy.data.objects.new(n, src.objects[n].data); o.location = ((i - 2.5) * 11, 0, 0); pv.collection.objects.link(o)
import bmesh
bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0)
me = bpy.data.meshes.new("Bear"); bm.to_mesh(me); bm.free()
b = bpy.data.objects.new("Bear5", me); b.scale = (3, 3, 5); b.location = (-33, -6, 2.5); pv.collection.objects.link(b)  # Massstab ~ Baerchi (5 Studs)
ca = me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
for d in ca.data: d.color = (0.8, 0.5, 0.1, 1)
g = bpy.data.objects.new("G", bpy.data.meshes.new("G")); 
bm = bmesh.new(); bmesh.ops.create_grid(bm, x_segments=2, y_segments=2, size=45); bm.to_mesh(g.data); bm.free(); pv.collection.objects.link(g)
ca = g.data.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
for d in ca.data: d.color = (0.05, 0.3, 0.06, 1)
pv.render.engine = 'BLENDER_WORKBENCH'; sh = pv.display.shading; sh.light = 'STUDIO'; sh.color_type = 'VERTEX'; sh.show_cavity = False
pv.render.resolution_x = 1400; pv.render.resolution_y = 700
w = bpy.data.worlds.new("TW"); w.use_nodes = False; w.color = (0.6, 0.8, 0.92); pv.world = w
cd = bpy.data.cameras.new("TC"); cam = bpy.data.objects.new("TC", cd); pv.collection.objects.link(cam); pv.camera = cam; cd.lens = 38
for nm, loc, tgt in (("baeume_vorn", (0, -62, 9), (0, 0, 8)), ("baeume_schraeg", (30, -48, 26), (0, 0, 6))):
    cam.location = loc; cam.rotation_euler = (Vector(tgt) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    pv.render.filepath = os.path.join(OUT, "Map_%s.png" % nm); bpy.ops.render.render(write_still=True)
bpy.context.window.scene = orig
result = {"ok": True}
