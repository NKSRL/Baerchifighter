# Einzige Zustaendigkeit: zeichnet die Texturen der Pulsar-Show "Pulsstoss"
# (PNG, 512 px, gerade Alpha) nach assets/vfx/pulsar_pulsstoss/tex.
# Laeuft in Blender (bpy + numpy), damit die Bilder sofort als Material-Bilder
# im Prototyp liegen. Aufruf: exec(open(<diese Datei>).read()) in Blender.
# Weiss/grau, wo Roblox einfaerben kann (Beam, ParticleEmitter, Decal); farbig
# nur, wo zwei Farbtoene zum Motiv gehoeren (Feuerkuppel, Funke, Blitzstern, Glut).
import bpy, numpy as np, os

BASE = r"C:\Users\admin\Documents\Claude Downloads\RBL\assets\vfx\pulsar_pulsstoss\tex"
os.makedirs(BASE, exist_ok=True)
N = 512

def save(name, rgba):
    rgba = np.clip(rgba, 0, 1).astype(np.float32)
    h, w, _ = rgba.shape
    img = bpy.data.images.get(name) or bpy.data.images.new(name, w, h, alpha=True)
    if tuple(img.size) != (w, h):
        img.scale(w, h)
    img.pixels.foreach_set(np.flipud(rgba).ravel())
    img.filepath_raw = os.path.join(BASE, name + ".png")
    img.file_format = 'PNG'
    img.save()
    img.filepath = img.filepath_raw
    img.alpha_mode = 'STRAIGHT'

def up_rect(a, n):
    # Wertrauschen: kleines Zufallsgitter weich (smoothstep) und periodisch hochskalieren -> nahtlos
    gh, gw = a.shape
    y = np.linspace(0, gh, n, endpoint=False); x = np.linspace(0, gw, n, endpoint=False)
    y0 = np.floor(y).astype(int); x0 = np.floor(x).astype(int)
    fy = (y - y0)[:, None]; fx = (x - x0)[None, :]
    fy = fy * fy * (3 - 2 * fy); fx = fx * fx * (3 - 2 * fx)
    y1 = (y0 + 1) % gh; x1 = (x0 + 1) % gw
    a00 = a[y0][:, x0]; a01 = a[y0][:, x1]; a10 = a[y1][:, x0]; a11 = a[y1][:, x1]
    return (a00 * (1 - fx) + a01 * fx) * (1 - fy) + (a10 * (1 - fx) + a11 * fx) * fy

def fbm(n, octs=5, g=4, seed=0, gx=None):
    r = np.random.default_rng(seed); out = np.zeros((n, n)); amp = 1.0; tot = 0.0
    for i in range(octs):
        out += amp * up_rect(r.random((g * 2 ** i, (gx or g) * 2 ** i)), n); tot += amp; amp *= 0.5
    return out / tot

yy, xx = np.mgrid[0:N, 0:N]
U = (xx + 0.5) / N          # 0..1 links->rechts
V = 1 - (yy + 0.5) / N      # 0..1 unten->oben
cx = U * 2 - 1; cy = V * 2 - 1
R = np.sqrt(cx * cx + cy * cy); TH = np.arctan2(cy, cx)

def ramp(t, stops):
    t = np.clip(t, 0, 1); out = np.zeros(t.shape + (3,))
    ps = [s[0] for s in stops]
    for c in range(3):
        out[..., c] = np.interp(t, ps, [s[1][c] for s in stops])
    return out

def sstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t)

def white(a):
    return np.dstack([np.ones_like(a), np.ones_like(a), np.ones_like(a), np.clip(a, 0, 1)])

def polar_noise(seed=1, rscale=0.5):
    n = fbm(256, 4, 4, seed)
    u = ((TH / (2 * np.pi)) % 1.0) * 256
    v = np.clip(R, 0, 0.999) * 256 * rscale
    return n[v.astype(int) % 256, u.astype(int) % 256]

FEUER = [(0, (0.45, 0.0, 0.14)), (0.3, (1.0, 0.12, 0.04)), (0.55, (1.0, 0.55, 0.08)), (0.8, (1.0, 0.95, 0.55)), (1, (1, 1, 1))]

# 1) Ring: duenne helle Linie mit weichem Schein (Boden- und Halo-Ring, einfaerbbar)
def ring():
    d = np.abs(R - 0.78)
    a = np.exp(-(d / 0.018) ** 2) + 0.55 * np.exp(-(d / 0.07) ** 2)
    save("Pulsar_Ring", white(a))

# 2) Scheibe: weicher Lichtfleck (Kugel-Kern, Blitz-Scheibe, Schein)
def scheibe():
    a = np.exp(-(R / 0.28) ** 2) + 0.3 * np.exp(-(R / 0.6) ** 2)
    save("Pulsar_Scheibe", white(a))

# 3) Funke: laengliche "Pille" mit weissem Kern und orangem Rand (die fliegenden Anime-Funken)
def funke():
    d = np.sqrt((cx / 0.95) ** 2 + (cy / 0.3) ** 2)
    a = sstep(1.0, 0.75, d)
    col = ramp(sstep(1.0, 0.25, d), [(0, (1.0, 0.35, 0.02)), (0.5, (1.0, 0.75, 0.2)), (1, (1, 1, 1))])
    save("Pulsar_Funke", np.dstack([col, a]))

# 4) Stern: Vierzack mit Schein (Glanzpunkt der Kugel, kleine Funkelsterne)
def stern():
    ax = np.abs(cx); ay = np.abs(cy)
    spike = np.exp(-(ay / 0.022) ** 2) * sstep(1.0, 0.0, ax) ** 2 + np.exp(-(ax / 0.022) ** 2) * sstep(1.0, 0.0, ay) ** 2
    glow = np.exp(-(R / 0.16) ** 2) + 0.3 * np.exp(-(R / 0.4) ** 2)
    save("Pulsar_Stern", white(spike + glow))

# 5) Kuppel: waagerechte Flammenstreifen mit dunklen Loechern, nahtlos in u und v (laeuft um die Halbkugel)
def kuppel():
    # fbm(g=Zeilen, gx=Spalten): viele Zeilen + wenige Spalten = waagerecht gestreckte Streifen
    n1 = fbm(N, 4, 20, 21, gx=2)                 # breite Streifen
    n2 = fbm(N, 3, 14, 22)                       # Blasen -> kleine Loecher
    n3 = fbm(N, 4, 48, 23, gx=6)                 # feine Fasern
    streak = sstep(0.42, 0.6, n1) * 0.65 + sstep(0.5, 0.56, n3) * 0.35
    holes = sstep(0.68, 0.76, n2)
    # weisser Koerper, orange Streifen, dunkelrote Loecher (wie im Vorbild)
    v = 0.95 - 0.45 * streak - 0.9 * holes
    col = ramp(v, FEUER)
    save("Pulsar_Kuppel", np.dstack([col, np.ones_like(v)]))

# 6) Saum: Flammenzungen von unten (Kuppelfuss, der am Boden "kocht")
def saum():
    n = up_rect(np.random.default_rng(31).random((4, 24)), N)
    n2 = up_rect(np.random.default_rng(32).random((4, 56)), N)
    top = 0.25 + 0.7 * (n * 0.6 + n2 * 0.4) ** 1.6
    tongue = sstep(top, top - 0.2, V)
    heat = sstep(top, 0.0, V)
    col = ramp(0.35 + 0.65 * heat, FEUER)
    save("Pulsar_Saum", np.dstack([col, np.clip(tongue * 1.3, 0, 1)]))

# 7) Speedlines: dicke Keile + duenne Strahlen bis zur Mitte (dunkle Strahlen im invertierten Impact-Frame)
def speedlines():
    rng = np.random.default_rng(41)
    lines = np.zeros_like(R)
    for k, (w0, r0) in enumerate(zip(rng.uniform(0.05, 0.12, 14), rng.uniform(0.08, 0.2, 14))):
        a0 = 2 * np.pi * k / 14 + rng.uniform(-0.1, 0.1)
        d = np.abs(np.angle(np.exp(1j * (TH - a0))))
        lines = np.maximum(lines, sstep(w0 * (0.3 + R), w0 * (0.3 + R) - 0.02, d) * sstep(r0, r0 + 0.15, R))
    for a0, w0, r0 in zip(rng.uniform(-np.pi, np.pi, 50), rng.uniform(0.004, 0.015, 50), rng.uniform(0.15, 0.5, 50)):
        d = np.abs(np.angle(np.exp(1j * (TH - a0))))
        lines = np.maximum(lines, np.exp(-(d / (w0 + 1e-4)) ** 2) * sstep(r0, r0 + 0.3, R))
    save("Pulsar_Speedlines", white(lines))

# 8) Rauch: weicher grauer Ballen
def rauch():
    n = fbm(N, 4, 3, 51)
    a = sstep(0.95, 0.35, R + (n - 0.5) * 0.5) * (0.6 + 0.4 * n)
    g = 0.55 + 0.3 * n
    save("Pulsar_Rauch", np.dstack([g, g, g, a * 0.85]))

# 9) Glut: verkohlter Boden, aussen gluehender Rand
def glut():
    pn = polar_noise(61)
    a = sstep(1.0, 0.15, R + (pn - 0.5) * 0.3)
    rim = np.exp(-((R - 0.62 + (pn - 0.5) * 0.2) / 0.12) ** 2)
    col = ramp(0.08 + 0.55 * rim, FEUER)
    save("Pulsar_Glut", np.dstack([col, a ** 1.3]))

# 10) Schweif: Lichtstreif der fliegenden Kugel, vorn breit und hell, hinten spitz
def schweif():
    a = (1 - U) ** 1.6 * np.exp(-(cy / (0.4 * (1 - U) + 0.05)) ** 2)
    save("Pulsar_Schweif", white(a))

# 11) Blitzstern: unregelmaessiger Zackenstern mit weissem Kern und orangem Saum (Sternbruch-Blitz, Kuppel-Aufplatzen)
def blitzstern():
    rng = np.random.default_rng(71)
    edge = np.full_like(R, 0.28)
    for a0, ln, w0 in zip(rng.uniform(-np.pi, np.pi, 14), rng.uniform(0.45, 0.98, 14), rng.uniform(0.08, 0.2, 14)):
        d = np.abs(np.angle(np.exp(1j * (TH - a0))))
        edge = np.maximum(edge, 0.28 + (ln - 0.28) * np.exp(-(d / w0) ** 2))
    a = sstep(edge, edge - 0.06, R)
    col = ramp(sstep(edge, edge * 0.35, R), [(0, (1.0, 0.4, 0.03)), (0.4, (1.0, 0.85, 0.3)), (1, (1, 1, 1))])
    save("Pulsar_Blitzstern", np.dstack([col, a]))

for f in (ring, scheibe, funke, stern, kuppel, saum, speedlines, rauch, glut, schweif, blitzstern):
    f()
