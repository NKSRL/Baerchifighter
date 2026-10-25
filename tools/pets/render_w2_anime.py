# render_w2_anime.py - Vorschau-Renders (Workbench) der Anime-Baerchis: Vorder-, Rueck- und 3/4-Ansicht -> assets/pets/_preview_w2_*.png
# In Blender nach build_w2_anime.py ausfuehren: exec(open(<pfad>).read())
import bpy, math
from mathutils import Vector
sc = bpy.data.scenes["W2_ANIME"]; bpy.context.window.scene = sc
sc.render.engine = 'BLENDER_WORKBENCH'
sh = sc.display.shading
sh.light = 'STUDIO'; sh.color_type = 'MATERIAL'; sh.show_cavity = False; sh.show_object_outline = True
sc.display.render_aa = '8'
sc.world = bpy.data.worlds.get("World") or bpy.data.worlds.new("World"); sc.world.color = (0.62, 0.72, 0.82)
sc.render.resolution_x = 1800; sc.render.resolution_y = 620
PREV = r"C:\Users\admin\Documents\Claude Downloads\RBL\assets\pets\%s.png"
def shoot(name, cam_loc, tgt, scale=21.0):
    cam = bpy.data.objects.get("AnimeCam") or bpy.data.objects.new("AnimeCam", bpy.data.cameras.new("AnimeCam"))
    if cam.name not in sc.collection.objects: sc.collection.objects.link(cam)
    cam.data.type = 'ORTHO'; cam.data.ortho_scale = scale; cam.location = cam_loc
    cam.rotation_euler = (Vector(tgt) - Vector(cam_loc)).to_track_quat('-Z', 'Y').to_euler()
    sc.camera = cam; sc.render.filepath = PREV % name
    bpy.ops.render.render(write_still=True)
shoot("_preview_w2_front", (7.5, -30, 4), (7.5, 0, 0.3))
shoot("_preview_w2_back", (7.5, 30, 4), (7.5, 0, 0.3))
shoot("_preview_w2_34", (28, -26, 14), (7.5, 0, 0.3), 22.0)
