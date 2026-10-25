# Einzige Zustaendigkeit: zeichnet die Texturen der Teufel-Show "Hoellensiegel"
# (PNG, 512 px, gerade Alpha) nach assets/vfx/teufel_hoellensiegel/tex.
# Laeuft in Blender (bpy + numpy), damit die Bilder sofort als Material-Bilder
# im Prototyp liegen. Aufruf: exec(open(<diese Datei>).read()) in Blender.
# Die Bilder sind meist WEISS/grau gehalten, wo Roblox sie einfaerben kann
# (Beam, ParticleEmitter, Decal, SpecialMesh.VertexColor); farbig nur, wo die
# Farbe Teil des Motivs ist (Siegel, Feuer, Sonnenkern).
import bpy, numpy as np, os

BASE = r"C:\Users\admin\Documents\Claude Downloads\RBL\assets\vfx\teufel_hoellensiegel\tex"
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

def up(a, n):
    # Wertrauschen: kleines Zufallsgitter weich (smoothstep) und periodisch hochskalieren
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
        gy_ = g * 2 ** i; gx_ = (gx or g) * 2 ** i
        out += amp * up_rect(r.random((gy_, gx_)), n); tot += amp; amp *= 0.5
    return out / tot

def up_rect(a, n):
    gh, gw = a.shape
    y = np.linspace(0, gh, n, endpoint=False); x = np.linspace(0, gw, n, endpoint=False)
    y0 = np.floor(y).astype(int); x0 = np.floor(x).astype(int)
    fy = (y - y0)[:, None]; fx = (x - x0)[None, :]
    fy = fy * fy * (3 - 2 * fy); fx = fx * fx * (3 - 2 * fx)
    y1 = (y0 + 1) % gh; x1 = (x0 + 1) % gw
    a00 = a[y0][:, x0]; a01 = a[y0][:, x1]; a10 = a[y1][:, x0]; a11 = a[y1][:, x1]
    return (a00 * (1 - fx) + a01 * fx) * (1 - fy) + (a10 * (1 - fx) + a11 * fx) * fy

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

_PN = {}
def polar_noise(seed=1, rscale=0.5):
    # Rauschen in (Winkel, Radius) abtasten -> nahtlos im Winkel
    if seed not in _PN:
        _PN[seed] = fbm(256, 4, 4, seed)
    n = _PN[seed]
    u = ((TH / (2 * np.pi)) % 1.0) * 256
    v = np.clip(R, 0, 0.999) * 256 * rscale
    return n[v.astype(int) % 256, u.astype(int) % 256]

def white(a):
    return np.dstack([np.ones_like(a), np.ones_like(a), np.ones_like(a), np.clip(a, 0, 1)])

# 1) Siegel-Flammenring (Boden): dunkelroter Grund, Flammenzacken aussen, feine Kreise innen
def siegel():
    pn = polar_noise(3); pn2 = polar_noise(11, 1.0); pn3 = polar_noise(13, 2.0)
    # Zungen: hochfrequentes Winkelrauschen, nach aussen gezogen (Radius flach abgetastet)
    tongues = np.clip((pn3 - 0.45) * 3.0, 0, 1)
    edge = 0.76 + 0.08 * pn + 0.18 * tongues
    flame = sstep(edge, edge - 0.16, R) * sstep(0.44, 0.60, R)
    flame = flame * (0.8 + 0.2 * np.clip((pn2 - 0.3) * 2, 0, 1))
    lines = np.zeros_like(R)
    for rr, wid in [(0.50, 0.012), (0.58, 0.006), (0.66, 0.010), (0.95, 0.006)]:
        lines = np.maximum(lines, np.exp(-((R - rr) / wid) ** 2))
    ticks = (np.abs(np.sin(TH * 24)) > 0.985) * sstep(0.5, 0.52, R) * sstep(0.58, 0.56, R)
    lines = np.maximum(lines, ticks)
    heat = np.clip(flame * (0.8 + 0.5 * pn2) + lines * 0.9, 0, 1.4) / 1.4
    col = ramp(heat, [(0, (0.25, 0, 0)), (0.35, (0.85, 0.05, 0.02)), (0.7, (1, 0.35, 0.08)), (1, (1, 0.85, 0.6))])
    a = np.clip(flame * 0.95 + lines + 0.15 * sstep(0.62, 0.3, R), 0, 1) * (R < 1)
    save("Teufel_SiegelRing", np.dstack([col, a]))

# 2) Feuer-Wirbelscheibe (gestapelte Scheiben ueber dem Siegel, Himmelsscheibe)
def scheibe():
    sn = polar_noise(5)
    sn2 = polar_noise(7, 1.5)
    spiral = (0.5 + 0.5 * np.sin((TH + R * 3.0) * 9 + sn * 7)) ** 1.5 * (0.5 + sn2)
    disc = sstep(1.0, 0.72, R) * (0.35 + 0.65 * spiral * sstep(0.0, 0.5, R))
    hot = np.exp(-(R / 0.3) ** 2)
    heat = np.clip(disc * 0.8 + hot, 0, 1)
    col = ramp(heat, [(0, (0.5, 0, 0)), (0.4, (1, 0.1, 0.03)), (0.75, (1, 0.5, 0.15)), (1, (1, 0.95, 0.75))])
    rim = np.exp(-((R - 0.9) / 0.05) ** 2) * 0.8
    a = np.clip(disc + hot + rim, 0, 1) * (R < 1)
    save("Teufel_FeuerScheibe", np.dstack([col, a]))

# 3) Strahl (Lichtklinge): weiss, Kern hell, Spitze rechts laeuft aus (Beam, einfaerbbar)
def strahl():
    across = np.exp(-((V - 0.5) / 0.22) ** 2)
    core = np.exp(-((V - 0.5) / 0.06) ** 2)
    along = sstep(0.0, 0.08, U) * sstep(1.0, 0.55, U)
    save("Teufel_Strahl", white((across * 0.7 + core) * along))

# 4) Rauchwolke (grau, weich, wird per ParticleEmitter getoent)
def rauch():
    n = fbm(N, 6, 3, 21)
    n2 = fbm(N, 4, 2, 22)
    shape = sstep(0.95, 0.25, R + (n2 - 0.5) * 0.6)
    a = np.clip(shape * (0.2 + 1.6 * (n - 0.35)), 0, 1)
    g = 0.55 + 0.45 * n
    save("Teufel_Rauch", np.dstack([g, g, g, a]))

# 5) Funkelstern: 4 lange Zacken + weicher Hof (das Glitzern im Video)
def funkel():
    ax = np.abs(cx); ay = np.abs(cy)
    spike = np.exp(-(ay / 0.025) ** 2) * sstep(1.0, 0.0, ax) ** 2 + np.exp(-(ax / 0.025) ** 2) * sstep(1.0, 0.0, ay) ** 2
    diag = (np.exp(-((np.abs(cx - cy)) / 0.03) ** 2) + np.exp(-((np.abs(cx + cy)) / 0.03) ** 2)) * sstep(0.5, 0.0, R) * 0.35
    glow = np.exp(-(R / 0.18) ** 2) + 0.35 * np.exp(-(R / 0.45) ** 2)
    save("Teufel_Funkelstern", white(spike + diag + glow))

# 6) Sonnenkern: gluehender Sternbruch mit dunklen Rissen, Rand schwarz (vor die schwarze Kugel)
def sonnenkern():
    pn = polar_noise(31, 1.0)
    rays = np.abs(np.sin(TH * 9 + pn * 3)) ** 6
    rays2 = np.abs(np.sin(TH * 23 + 1.3)) ** 20
    burst = np.clip(np.exp(-(R / 0.25) ** 2) * 1.2 + (rays * 0.9 + rays2 * 0.6) * sstep(0.95, 0.15, R), 0, 1.3)
    cracks = (np.abs(np.sin(TH * 5 + R * 7 + pn * 5)) < 0.06) * sstep(0.2, 0.4, R) * sstep(0.95, 0.7, R)
    heat = np.clip(burst - cracks * 0.8, 0, 1.3) / 1.3
    col = ramp(heat, [(0, (0.02, 0, 0)), (0.25, (0.45, 0.02, 0.0)), (0.55, (1, 0.2, 0.03)), (0.8, (1, 0.6, 0.15)), (1, (1, 0.97, 0.8))])
    ring = np.exp(-((R - 0.97) / 0.03) ** 2)
    col = col * (1 - ring[..., None]) + np.array([1, 0.15, 0.05]) * ring[..., None]
    a = np.clip(sstep(1.0, 0.96, R) + ring, 0, 1)
    save("Teufel_SonnenKern", np.dstack([col, a]))

# 7) Sichel: weisser Halbmond mit weicher Kante, oben auf der schwarzen Sonne
def sichel():
    d1 = np.sqrt(cx ** 2 + (cy + 0.25) ** 2); d2 = np.sqrt(cx ** 2 + (cy + 0.55) ** 2)
    moon = sstep(0.95, 0.88, d1) * sstep(0.78, 0.9, d2)
    streak = 0.6 + 0.4 * up_rect(np.random.default_rng(41).random((4, 64)), N)
    save("Teufel_Sichel", white(moon * streak))

# 8) Feuersaeule: senkrechte Flammenstreifen, nahtlos in U, oben ausfransend
def feuersaeule():
    n = fbm(N, 5, 2, 51, gx=24)       # streifig: viele Spalten, wenige Zeilen
    n2 = fbm(N, 4, 3, 52, gx=40)
    streak = np.clip((n - 0.35) * 2.2, 0, 1)
    dark = np.clip((0.42 - n2) * 4, 0, 1) * 0.7
    heat = np.clip(streak * 0.9 + 0.25 - dark, 0, 1)
    col = ramp(heat, [(0, (0.35, 0.02, 0.0)), (0.3, (0.95, 0.15, 0.03)), (0.6, (1, 0.55, 0.12)), (0.85, (1, 0.85, 0.35)), (1, (1, 1, 0.85))])
    # v2: nahtlos auch in V (Textur laeuft per Scroll/TextureSpeed hoch); das Ausblenden
    # oben macht das Material bzw. die Beam-Transparenz, nicht das Bild.
    a = np.clip(0.35 + 0.8 * heat, 0, 1)
    save("Teufel_Feuersaeule", np.dstack([col, a]))

# 9) Kronenwand: weisser Schleier, unten dichter, an der Oberkante ein heller Saum
def krone():
    n = fbm(N, 4, 2, 61, gx=12)
    a = sstep(1.0, 0.0, V) * 0.55 + 0.25 * np.exp(-((V - 0.93) / 0.04) ** 2) + 0.12 * (n - 0.5)
    a = a * sstep(1.0, 0.97, V)
    save("Teufel_Krone", white(a))

# 10) Flammenfaecher: pinke Strahlen, die von unten Mitte nach aussen schiessen
def faecher():
    px = cx; py = V
    ang = np.arctan2(px, py + 0.05); dist = np.sqrt(px ** 2 + (py + 0.05) ** 2)
    n = up_rect(np.random.default_rng(71).random((8, 48)), N)
    rays = np.abs(np.sin(ang * 9 + n * 1.5 + dist * 2.0)) ** 2 * (0.5 + 0.5 * n)
    body = sstep(1.05, 0.5, dist) * sstep(0.0, 0.25, dist) * sstep(1.4, 0.6, np.abs(ang))
    heat = np.clip(rays * body * 1.3, 0, 1)
    col = ramp(heat, [(0, (0.6, 0.02, 0.2)), (0.5, (1, 0.2, 0.55)), (0.85, (1, 0.6, 0.8)), (1, (1, 0.95, 0.97))])
    save("Teufel_Faecher", np.dstack([col, heat]))

# 11) Hieb-Bogen: weisses Windband, Kante oben scharf, nach unten weich, Enden laufen aus
def hieb():
    n = up_rect(np.random.default_rng(81).random((48, 4)), N)
    band = sstep(0.0, 0.85, V) * sstep(1.0, 0.92, V)
    lines = 0.6 + 0.4 * n
    along = sstep(0.0, 0.3, U) * sstep(1.0, 0.75, U)
    save("Teufel_Hieb", white(band * lines * along))

# 12) Bodenglut: weicher roter Fleck (Decal/Scheibe unter Sonne und Saeule)
def glut():
    pn = polar_noise(91)
    a = sstep(1.0, 0.1, R + (pn - 0.5) * 0.25)
    col = ramp(a, [(0, (0.6, 0, 0)), (0.6, (1, 0.12, 0.05)), (1, (1, 0.6, 0.3))])
    save("Teufel_Glut", np.dstack([col, a ** 1.5]))

# 13) Schwarzflamme: schwarze Zungen mit rotem Rand (Kranz um die schwarze Sonne)
def schwarzflamme():
    n = up_rect(np.random.default_rng(101).random((4, 20)), N)
    n2 = up_rect(np.random.default_rng(102).random((4, 48)), N)
    top = 0.25 + 0.7 * (n * 0.6 + n2 * 0.4) ** 2
    tongue = sstep(top, top - 0.18, V)
    edge = np.exp(-((V - (top - 0.06)) / 0.05) ** 2) * sstep(0.1, 0.3, V)
    col = np.zeros((N, N, 3)); col[..., 0] = edge * 1.0; col[..., 1] = edge * 0.1
    save("Teufel_Schwarzflamme", np.dstack([col, np.clip(tongue * 1.4, 0, 1)]))

# 14) Speedlines fuer den Impact-Frame: duenne Strahlen vom Rand zur Mitte, Mitte frei
def speedlines():
    rng = np.random.default_rng(111)
    k = 90
    ang = np.sort(rng.uniform(-np.pi, np.pi, k)); wid = rng.uniform(0.004, 0.02, k); reach = rng.uniform(0.25, 0.6, k)
    lines = np.zeros_like(R)
    for a0, w0, r0 in zip(ang, wid, reach):
        d = np.abs(np.angle(np.exp(1j * (TH - a0))))
        taper = sstep(r0, r0 + 0.5, R)                    # Linie wird nach innen spitz
        lines = np.maximum(lines, np.exp(-(d / (w0 * taper + 1e-4)) ** 2) * taper)
    save("Teufel_Speedlines", white(lines * sstep(0.2, 0.5, R)))

for f in (speedlines, siegel, scheibe, strahl, rauch, funkel, sonnenkern, sichel, feuersaeule, krone, faecher, hieb, glut, schwarzflamme):
    f()
