# Map-Stil V2 (Kanten-Variante): 5 Buesche, 2 Randbuesche, 2 Gras-Cluster. Flat-Shading, abstehende Blattspitzen.
import os
exec(open(os.path.join(r"C:\Users\admin\Documents\Claude Downloads\RBL\tools\map_assets", "map_common.py"), encoding="utf-8").read())

def busch(name, lobes, spk, ztop, seed):
    bm = bmesh.new(); tips = {}
    for i, (c, r, sub, nz) in enumerate(lobes): lobe(bm, c, r, seed + i, nz, sub)
    for i, (c, r, n, L, w, cols) in enumerate(spk):
        leaves(bm, c, r, n, L, w, seed + 40 + i, cols, tips)
    return finish(name, bm, crown_color(0.0, ztop, tips))

G = [LAUB_HELL, LAUB_HELL, LAUB_MITTE, LAUB_GELB]
def halme(bm, n, radius, hmin, hmax, seed, w=0.3, tips=None, cols=None):
    rnd = random.Random(seed)
    for k in range(n):
        a = 2 * math.pi * k / n + rnd.uniform(-0.3, 0.3); r = radius * rnd.uniform(0.2, 1.0)
        x, y = r * math.cos(a), r * math.sin(a); h = rnd.uniform(hmin, hmax); lean = rnd.uniform(0.2, 0.6) * h
        tip = bm.verts.new((x + lean * math.cos(a) * 0.7, y + lean * math.sin(a) * 0.7, h))
        base = [bm.verts.new((x + w * math.cos(a + k2 * 2.094), y + w * math.sin(a + k2 * 2.094), 0)) for k2 in range(3)]
        for k2 in range(3): bm.faces.new((base[k2], base[(k2 + 1) % 3], tip))
        if tips is not None: tips[key(tip.co)] = cols[k % len(cols)]

def build_all():
    out = []
    out.append(busch("Map_Busch_A", [((0, 0, 1.4), (2.0, 2.0, 1.6), 2, 0.3), ((1.2, 0.8, 1.1), (1.5, 1.5, 1.2), 1, 0.3)],
        [((0, 0, 1.4), (2.0, 2.0, 1.6), 12, 2.0, 1.0, G), ((1.2, 0.8, 1.1), (1.5, 1.5, 1.2), 7, 1.7, 0.9, G)], 3.6, 1000))
    out.append(busch("Map_Busch_B", [((0, 0, 1.6), (2.0, 2.0, 1.8), 2, 0.3), ((1.9, 0.7, 1.2), (1.6, 1.6, 1.3), 1, 0.3), ((-1.7, 0.5, 1.2), (1.6, 1.6, 1.3), 1, 0.3)],
        [((0, 0, 1.6), (2.0, 2.0, 1.8), 6, 2.0, 1.0, G), ((1.9, 0.7, 1.2), (1.6, 1.6, 1.3), 4, 1.7, 0.9, G), ((-1.7, 0.5, 1.2), (1.6, 1.6, 1.3), 4, 1.7, 0.9, G)], 3.4, 1100))
    out.append(busch("Map_Busch_C", [((0, 0, 1.2), (3.4, 2.6, 1.5), 2, 0.3), ((0.8, 0.3, 1.9), (2.0, 1.8, 1.1), 1, 0.3)],
        [((0, 0, 1.2), (3.4, 2.6, 1.5), 14, 2.0, 1.0, G + [BEERE]), ((0.8, 0.3, 1.9), (2.0, 1.8, 1.1), 5, 1.6, 0.8, [BEERE, LAUB_HELL])], 3.0, 1200))
    out.append(busch("Map_Busch_D", [((0, 0, 2.3), (2.0, 2.0, 2.7), 2, 0.28), ((-1.1, 0.6, 1.1), (1.3, 1.3, 1.1), 1, 0.3)],
        [((0, 0, 2.3), (2.0, 2.0, 2.7), 13, 2.0, 1.0, G), ((-1.1, 0.6, 1.1), (1.3, 1.3, 1.1), 6, 1.5, 0.8, G)], 5.6, 1300))
    out.append(busch("Map_Busch_E", [((0, 0, 1.5), (2.2, 2.2, 1.6), 2, 0.28), ((1.2, -0.6, 1.1), (1.5, 1.5, 1.2), 1, 0.3)],
        [((0, 0, 1.5), (2.2, 2.2, 1.6), 13, 2.0, 1.0, G), ((0, 0, 1.7), (1.9, 1.9, 1.4), 6, 1.8, 0.9, [PINK, WEISS, HONIG])], 3.7, 1400))
    out.append(busch("Map_RimBusch_A", [((0, 0, 0.8), (3.0, 2.2, 1.1), 2, 0.3)],
        [((0, 0, 0.8), (3.0, 2.2, 1.1), 14, 1.9, 0.9, G)], 2.0, 1500))
    out.append(busch("Map_RimBusch_B", [((-1.9, 0, 0.6), (1.5, 1.4, 0.9), 1, 0.3), ((0.2, 0.2, 0.7), (1.9, 1.4, 1.0), 1, 0.3), ((2.1, -0.1, 0.6), (1.4, 1.3, 0.9), 1, 0.3)],
        [((-1.9, 0, 0.6), (1.5, 1.4, 0.9), 3, 1.5, 0.8, G), ((0.2, 0.2, 0.7), (1.9, 1.4, 1.0), 5, 1.7, 0.9, G), ((2.1, -0.1, 0.6), (1.4, 1.3, 0.9), 3, 1.5, 0.8, G)], 1.8, 1600))
    bm = bmesh.new(); tips = {}; halme(bm, 14, 1.5, 1.1, 2.2, 1700, tips=tips, cols=[LAUB_HELL, LAUB_MITTE, LAUB_GELB])
    out.append(finish("Map_Gras_A", bm, lambda co: tips.get(key(co)) or mix(LAUB_TIEF, LAUB_MITTE, smoothstep(co.z / 1.4))))
    bm = bmesh.new(); tips = {}; halme(bm, 10, 1.3, 1.1, 1.9, 1710, tips=tips, cols=[LAUB_HELL, LAUB_MITTE])
    for k, (x, y, z, c) in enumerate([(0.5, 0.3, 1.9, HONIG), (-0.6, 0.5, 1.6, PINK), (0.1, -0.7, 1.75, WEISS)]):
        spikes(bm, (x, y, z - 0.5), (0.2, 0.2, 0.2), 2, 0.7, 0.3, 1720 + k, [c], zmin=0.2, up=1.6, tips=tips)
    out.append(finish("Map_Gras_B", bm, lambda co: tips.get(key(co)) or mix(LAUB_TIEF, LAUB_MITTE, smoothstep(co.z / 1.4))))
    return out

sc = bpy.data.scenes.get("MAP_BUSHES") or bpy.data.scenes.new("MAP_BUSHES")
for o in list(sc.objects): bpy.data.objects.remove(o, do_unlink=True)
result = {"report": export_set(sc, build_all(), "Map_Buesche.fbx")}
