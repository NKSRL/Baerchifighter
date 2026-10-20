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
        spikes(bm, c, r, n, L, w, seed + 50 + i, TIPS, tips=tips)
    return finish(name, bm, crown_color(zbot, ztop, tips, stem))

def build_all():
    A = baum("Map_Baum_A", 7.6, 1.0, 0.55, (0.4, 0),
             [((0.4, 0, 10.0), (5.2, 5.2, 4.4), 2, 0.22), ((-2.6, 1.2, 8.6), (2.8, 2.8, 2.4), 1, 0.25), ((2.8, -1.4, 8.8), (2.6, 2.6, 2.3), 1, 0.25)],
             [((0.4, 0, 10.0), (5.2, 5.2, 4.4), 30, 2.1, 0.55), ((-2.6, 1.2, 8.6), (2.8, 2.8, 2.4), 10, 1.5, 0.45), ((2.8, -1.4, 8.8), (2.6, 2.6, 2.3), 10, 1.5, 0.45)],
             5.0, 15.6, 100)
    B = baum("Map_Baum_B", 10.0, 0.85, 0.45, (-0.4, 0.2),
             [((-0.4, 0.2, 13.6), (3.3, 3.3, 6.0), 2, 0.22), ((-0.6, 0.3, 10.8), (2.6, 2.6, 2.2), 1, 0.25)],
             [((-0.4, 0.2, 13.6), (3.3, 3.3, 6.0), 36, 1.9, 0.5), ((-0.6, 0.3, 10.8), (2.6, 2.6, 2.2), 8, 1.4, 0.42)],
             7.5, 20.0, 200)
    C = baum("Map_Baum_C", 6.8, 1.05, 0.6, (0.5, 0),
             [((0.5, 0, 8.7), (4.8, 4.8, 3.4), 2, 0.22), ((0.9, 0.3, 13.0), (3.6, 3.6, 3.2), 1, 0.25), ((-2.2, 0.8, 8.8), (2.4, 2.4, 2.0), 1, 0.25)],
             [((0.5, 0, 8.7), (4.8, 4.8, 3.4), 23, 2.0, 0.55), ((0.9, 0.3, 13.0), (3.6, 3.6, 3.2), 18, 1.7, 0.5), ((-2.2, 0.8, 8.8), (2.4, 2.4, 2.0), 7, 1.3, 0.4)],
             5.0, 16.6, 300)
    D = baum("Map_Baum_D", 3.6, 0.55, 0.32, (0.15, 0), 
             [((0.15, 0, 5.4), (3.0, 3.0, 2.8), 2, 0.22), ((-1.3, 0.5, 4.4), (1.6, 1.6, 1.4), 1, 0.25)],
             [((0.15, 0, 5.4), (3.0, 3.0, 2.8), 22, 1.5, 0.42), ((-1.3, 0.5, 4.4), (1.6, 1.6, 1.4), 6, 1.1, 0.35)],
             2.6, 8.2, 400, sides=5)
    # Stumpf: kantig, Blueten als farbige Spitzen
    bm = bmesh.new(); tips = {}
    trunk(bm, 2.3, 1.4, 0.95, sides=7, rings=2, flare=1.15)
    spikes(bm, (0, 0, 0.35), (2.2, 2.2, 0.5), 9, 0.9, 0.3, 500, [HONIG, PINK, WEISS], zmin=-0.1, up=0.9, tips=tips)
    spikes(bm, (0, 0, 2.2), (0.9, 0.9, 0.3), 4, 0.9, 0.28, 501, [LAUB_HELL], zmin=0.3, up=1.2, tips=tips)
    def fs(co):
        k = key(co)
        if k in tips: return tips[k]
        return tint(mix(STAMM_DUNKEL, STAMM_HELL, smoothstep(co.z / 2.4)), co, 0.1)
    E = finish("Map_Stumpf_A", bm, fs)
    # Blumengruppe: Gras-Spitzen + Bluetenspitzen
    bm = bmesh.new(); tips = {}
    lobe(bm, (0, 0, 0.0), (2.4, 2.4, 0.6), 600, 0.15, 1)
    spikes(bm, (0, 0, 0.1), (2.2, 2.2, 0.5), 16, 1.5, 0.22, 601, [LAUB_HELL, LAUB_MITTE], zmin=-0.1, up=1.4, tips=tips)
    spikes(bm, (0, 0, 0.3), (1.6, 1.6, 0.5), 7, 2.0, 0.3, 602, [HONIG, PINK, WEISS], zmin=0.0, up=1.8, tips=tips)
    def fb(co):
        k = key(co)
        if k in tips: return tips[k]
        return tint(mix(LAUB_TIEF, LAUB_MITTE, smoothstep(co.z / 1.2 + 0.3)), co, 0.1)
    F = finish("Map_Blumen_A", bm, fb)
    return [A, B, C, D, E, F]

sc = bpy.data.scenes.get("MAP_TREES") or bpy.data.scenes.new("MAP_TREES")
for o in list(sc.objects): bpy.data.objects.remove(o, do_unlink=True)
result = {"report": export_set(sc, build_all(), "Map_Baeume.fbx")}
