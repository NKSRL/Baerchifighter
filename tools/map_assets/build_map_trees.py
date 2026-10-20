# Map-Stil V2 (Kanten-Variante): 4 Baeume + Stumpf + Blumen. Flat-Shading, verbeulte Kronen, abstehende Blattspitzen.
import os
exec(open(os.path.join(r"C:\Users\admin\Documents\Claude Downloads\RBL\tools\map_assets", "map_common.py"), encoding="utf-8").read())

TIPS = [LAUB_HELL, LAUB_HELL, LAUB_MITTE, LAUB_GELB]

def baum(name, stem, r0, r1, bend, lobes, spk, zbot, ztop, seed, sides=6):
    bm = bmesh.new(); tips = {}
    trunk(bm, stem, r0, r1, bend=bend, sides=sides)
    # zwei Aeste ragen sichtbar in die Krone
    for k, ang in enumerate((0.6, 3.4)):
        b = bm.verts.new((bend[0] + 0.25 * math.cos(ang), bend[1] + 0.25 * math.sin(ang), stem - 0.6))
        t = bm.verts.new((bend[0] + 2.4 * math.cos(ang), bend[1] + 2.4 * math.sin(ang), stem + 1.9))
        c = bm.verts.new((bend[0] + 0.25 * math.cos(ang + 2), bend[1] + 0.25 * math.sin(ang + 2), stem - 0.6))
        d = bm.verts.new((bend[0] + 0.25 * math.cos(ang - 2), bend[1] + 0.25 * math.sin(ang - 2), stem - 0.6))
        for (p, q) in ((b, c), (c, d), (d, b)): bm.faces.new((p, q, t))
    for i, (c, r, sub, nz) in enumerate(lobes):
        lobe(bm, c, r, seed + i, nz, sub)
    for i, (c, r, n, L, w) in enumerate(spk):
        leaves(bm, c, r, n, L, w, seed + 50 + i, TIPS, tips)
    return finish(name, bm, crown_color(zbot, ztop, tips, stem))

def build_all():
    A = baum("Map_Baum_A", 7.6, 1.0, 0.55, (0.4, 0),
             [((0.4, 0, 10.0), (5.2, 5.2, 4.4), 2, 0.22), ((-2.6, 1.2, 8.6), (2.8, 2.8, 2.4), 1, 0.25), ((2.8, -1.4, 8.8), (2.6, 2.6, 2.3), 1, 0.25)],
             [((0.4, 0, 10.0), (5.2, 5.2, 4.4), 20, 2.6, 1.3), ((-2.6, 1.2, 8.6), (2.8, 2.8, 2.4), 6, 2.0, 1.0), ((2.8, -1.4, 8.8), (2.6, 2.6, 2.3), 6, 2.0, 1.0)],
             5.0, 15.6, 100)
    B = baum("Map_Baum_B", 10.0, 0.85, 0.45, (-0.4, 0.2),
             [((-0.4, 0.2, 13.6), (3.3, 3.3, 6.0), 2, 0.22), ((-0.6, 0.3, 10.8), (2.6, 2.6, 2.2), 1, 0.25)],
             [((-0.4, 0.2, 13.6), (3.3, 3.3, 6.0), 30, 2.4, 1.2), ((-0.6, 0.3, 10.8), (2.6, 2.6, 2.2), 6, 1.9, 1.0)],
             7.5, 20.0, 200)
    C = baum("Map_Baum_C", 6.8, 1.05, 0.6, (0.5, 0),
             [((0.5, 0, 8.7), (4.8, 4.8, 3.4), 2, 0.22), ((0.9, 0.3, 13.0), (3.6, 3.6, 3.2), 1, 0.25), ((-2.2, 0.8, 8.8), (2.4, 2.4, 2.0), 1, 0.25)],
             [((0.5, 0, 8.7), (4.8, 4.8, 3.4), 18, 2.5, 1.2), ((0.9, 0.3, 13.0), (3.6, 3.6, 3.2), 12, 2.3, 1.1), ((-2.2, 0.8, 8.8), (2.4, 2.4, 2.0), 4, 1.8, 0.9)],
             5.0, 16.6, 300)
    D = baum("Map_Baum_D", 3.6, 0.55, 0.32, (0.15, 0), 
             [((0.15, 0, 5.4), (3.0, 3.0, 2.8), 2, 0.22), ((-1.3, 0.5, 4.4), (1.6, 1.6, 1.4), 1, 0.25)],
             [((0.15, 0, 5.4), (3.0, 3.0, 2.8), 14, 1.9, 1.0), ((-1.3, 0.5, 4.4), (1.6, 1.6, 1.4), 4, 1.5, 0.8)],
             2.6, 8.2, 400, sides=5)
    # Stumpf: kantig, drei Bluetenklumpen am Fuss (Farbe ueber die Naehe zum Klumpen)
    def blueten(bm, spots, rad, seed):
        for k, (x, y, z, cc) in enumerate(spots):
            lobe(bm, (x, y, z), (rad, rad, rad * 0.9), seed + k, 0.2, 1)
        def near(co):
            for (x, y, z, cc) in spots:
                if (co.x - x) ** 2 + (co.y - y) ** 2 + (co.z - z) ** 2 <= (rad * 1.3) ** 2: return cc
            return None
        return near
    bm = bmesh.new()
    trunk(bm, 2.3, 1.4, 0.95, sides=7, rings=2, flare=1.15)
    near = blueten(bm, [(2.0, 0.5, 0.5, HONIG), (-1.7, 1.2, 0.5, PINK), (0.5, -1.9, 0.5, WEISS)], 0.55, 520)
    E = finish("Map_Stumpf_A", bm, lambda co: near(co) or tint(mix(STAMM_DUNKEL, STAMM_HELL, smoothstep(co.z / 2.4)), co, 0.1))
    # Blumengruppe: flache Kuppel + vier Bluetenklumpen
    bm = bmesh.new()
    lobe(bm, (0, 0, 0.0), (2.4, 2.4, 0.7), 600, 0.18, 2)
    near = blueten(bm, [(0.9, 0.4, 0.95, HONIG), (-0.8, 0.8, 0.9, PINK), (0.1, -1.0, 0.9, WEISS), (-0.6, -0.5, 1.0, HONIG)], 0.5, 610)
    F = finish("Map_Blumen_A", bm, lambda co: near(co) or tint(mix(LAUB_TIEF, LAUB_MITTE, smoothstep(co.z / 0.9 + 0.3)), co, 0.1))
    return [A, B, C, D, E, F]

sc = bpy.data.scenes.get("MAP_TREES") or bpy.data.scenes.new("MAP_TREES")
for o in list(sc.objects): bpy.data.objects.remove(o, do_unlink=True)
result = {"report": export_set(sc, build_all(), "Map_Baeume.fbx")}
