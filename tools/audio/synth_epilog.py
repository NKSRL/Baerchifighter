#!/usr/bin/env python3
"""synth_epilog.py - erzeugt die Klaenge des Final-Epilogs (Prompt 7) komplett selbst.

Alles wird aus Sinus-/Saege-/Rauschen-Synthese berechnet (numpy), keine fremden Samples,
kein KI-Dienst, daher keine Lizenzfragen. Ausgabe wie tools/audio/synth.js:
  tools/audio/out/sfx/epilog_<name>.wav     Mono, 44,1 kHz  (Studio-Vorschau: sfx_epilog_<name>.wav)
  tools/audio/out/music/epilog.wav          Stereo, 44,1 kHz (Studio-Vorschau: music_epilog.wav)
  assets/epilog/sound/epilog_<name>.ogg     zum Hochladen, auf -16 LUFS angehoben, Spitze <= -1,5 dBFS

Aufruf: python tools/audio/synth_epilog.py        (aus dem Projektordner)
Stil: orchestral-cartoonig, warm, glanzvoll; kein Metal, kein Horror.
"""
import tempfile
import json, os, subprocess, sys, wave
import numpy as np

SR = 44100
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "tools", "audio", "out")
OGG = os.path.join(ROOT, "assets", "epilog", "sound")
rng = np.random.default_rng(20261020)

def mtof(m): return 440.0 * 2 ** ((m - 69) / 12)
def t_arr(d): return np.arange(int(d * SR)) / SR

def adsr(n, a, d, s, r):
    e = np.ones(n)
    a_n, d_n, r_n = int(a * SR), int(d * SR), int(r * SR)
    a_n = max(1, min(a_n, n)); r_n = min(r_n, n)
    e[:a_n] = np.linspace(0, 1, a_n)
    d_end = min(n, a_n + d_n)
    if d_end > a_n: e[a_n:d_end] = np.linspace(1, s, d_end - a_n)
    e[d_end:] = s
    if r_n > 0: e[n - r_n:] *= np.linspace(1, 0, r_n)
    return e

def lowpass(x, fc, order=2):
    X = np.fft.rfft(x); f = np.fft.rfftfreq(len(x), 1 / SR)
    return np.fft.irfft(X / (1 + (f / fc) ** (2 * order)), len(x))

def highpass(x, fc, order=2):
    X = np.fft.rfft(x); f = np.fft.rfftfreq(len(x), 1 / SR)
    g = (f / fc) ** (2 * order); return np.fft.irfft(X * g / (1 + g), len(x))

def bandpass(x, lo, hi): return highpass(lowpass(x, hi), lo)

def osc(freq, dur, kind="sine", detune=0.0):
    t = t_arr(dur); ph = 2 * np.pi * freq * (1 + detune) * t
    if kind == "sine": return np.sin(ph)
    out = np.zeros_like(t); h = 1; fr = freq * (1 + detune)
    while fr * h < 9000 and h < 40:
        if kind == "saw": out += np.sin(h * ph) / h
        elif kind == "square" and h % 2 == 1: out += np.sin(h * ph) / h
        elif kind == "tri" and h % 2 == 1: out += ((-1) ** ((h - 1) // 2)) * np.sin(h * ph) / (h * h)
        h += 1
    return out * (2 / np.pi if kind != "tri" else 8 / np.pi ** 2)

def noise(dur): return rng.standard_normal(int(dur * SR))

def reverb(x, seconds=1.4, wet=0.25, bright=3500):
    n = int(seconds * SR); t = np.arange(n) / SR
    ir = noise(seconds)[:n] * np.exp(-t * 6.0 / seconds * 1.0)
    ir = lowpass(ir, bright, 1); ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
    L = len(x) + n; N = 1 << (L - 1).bit_length()
    y = np.fft.irfft(np.fft.rfft(x, N) * np.fft.rfft(ir, N), N)[:L]
    out = np.zeros(L); out[:len(x)] += x * (1 - wet); out += y * wet
    return out

def place(buf, sig, start, wrap=False):
    i = int(start * SR); n = len(sig)
    if wrap:
        idx = (np.arange(n) + i) % len(buf); np.add.at(buf, idx, sig); return
    if i >= len(buf): return
    j = min(len(buf), i + n); buf[i:j] += sig[:j - i]

def fit(x, dur=None):
    if dur is None: return x
    n = int(dur * SR); y = np.zeros(n); m = min(n, len(x)); y[:m] = x[:m]; return y

# ----------------------------------------------------------------- Bausteine
def bell(freq, dur=1.4, vel=1.0):
    t = t_arr(dur); y = np.zeros_like(t)
    for k, (r, a, dec) in enumerate([(1, 1.0, 3.0), (2.0, 0.5, 4.5), (2.76, 0.35, 6.0), (4.1, 0.15, 9.0)]):
        y += a * np.sin(2 * np.pi * freq * r * t) * np.exp(-t * dec)
    return y * vel * np.minimum(1, t / 0.004)

def brass(freq, dur, vel=1.0, bright=2600):
    n = int(dur * SR); y = osc(freq, dur, "saw") + 0.6 * osc(freq, dur, "saw", 0.004)
    y = lowpass(y, bright, 2)
    return y * adsr(n, 0.07, 0.12, 0.8, min(0.25, dur * 0.4)) * vel

def pad(freq, dur, vel=1.0, bright=1500):
    n = int(dur * SR); y = sum(osc(freq, dur, "saw", d) for d in (-0.006, 0.0, 0.007))
    y = lowpass(y, bright, 2); return y * adsr(n, min(0.7, dur * 0.4), 0.3, 0.85, min(1.2, dur * 0.5)) * vel / 3

def pizz(freq, dur=0.5, vel=1.0):
    t = t_arr(dur); y = np.sin(2 * np.pi * freq * t) + 0.5 * np.sin(4 * np.pi * freq * t) * np.exp(-t * 18)
    return y * np.exp(-t * 7) * np.minimum(1, t / 0.003) * vel

def kick(vel=1.0):
    t = t_arr(0.35); f = 45 + 90 * np.exp(-t * 30); ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * np.exp(-t * 11) * vel

def shaker(vel=1.0):
    n = noise(0.07); n = highpass(n, 6000); return n * np.exp(-t_arr(0.07) * 55) * vel * 0.4

def thunk(vel=1.0):
    n = noise(0.12); n = lowpass(n, 1200); return n * np.exp(-t_arr(0.12) * 45) * vel

# ----------------------------------------------------------------- SFX
def sfx_hit():  # dumpfer Treffer + Glasbruch, 1,1 s
    d = 1.1; y = np.zeros(int(d * SR))
    t = t_arr(0.5); f = 38 + 120 * np.exp(-t * 22)
    place(y, np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 7) * 1.2, 0)
    place(y, lowpass(noise(0.18), 2500) * np.exp(-t_arr(0.18) * 25) * 0.9, 0)
    for k in range(26):  # Scherben: kurze Pings, Hoehen zufaellig, kaskadiert
        st = 0.02 + rng.random() * 0.5; fr = rng.uniform(2800, 7800)
        tt = t_arr(0.25); place(y, np.sin(2 * np.pi * fr * tt) * np.exp(-tt * rng.uniform(18, 35)) * rng.uniform(0.05, 0.16), st)
    return reverb(y, 0.8, 0.18)[:int(d * SR)]

def sfx_flash():  # Aufwaerts-Sweep, 1,3 s
    d = 1.3; t = t_arr(d); f = 260 * (3600 / 260) ** (t / d) ; ph = 2 * np.pi * np.cumsum(f) / SR
    y = np.sin(ph) * 0.6 + np.sin(ph * 2.01) * 0.25
    y += highpass(noise(d), 3000) * (t / d) ** 2 * 0.25
    y *= np.minimum(1, t / 0.05) * np.where(t > d - 0.35, np.exp(-(t - (d - 0.35)) * 9), 1)
    tail = np.zeros(int((d + 0.5) * SR)); tail[:len(y)] = y
    for k, m in enumerate((88, 91, 95)): place(tail, bell(mtof(m), 0.6, 0.18), d - 0.15 + k * 0.05)
    return reverb(tail, 0.9, 0.25)

def sfx_rise():  # Orchesterflaeche steigt, 3,6 s
    d = 3.6; n = int(d * SR); t = t_arr(d); y = np.zeros(n)
    glide = np.linspace(0.84, 1.0, n)   # Quarte aufwaerts
    for m in (48, 55, 60, 64, 67, 72):
        f0 = mtof(m); ph = 2 * np.pi * np.cumsum(f0 * glide) / SR
        w = sum(np.sin(h * ph * (1 + dt)) / h for h in (1, 2, 3, 4) for dt in (-0.004, 0.004))
        y += w
    y = lowpass(y, 1800, 2) * (t / d) ** 1.6 * 0.18
    y += highpass(noise(d), 1500) * 0.05 * (t / d) ** 2 * (np.sin(np.pi * t / d) ** 0.5)
    y *= np.where(t > d - 0.4, np.exp(-(t - (d - 0.4)) * 7), 1)
    return reverb(y, 1.3, 0.3)

def sfx_run():  # ein Schritt auf Holz, 0,22 s
    d = 0.22; n = int(d * SR); t = t_arr(d)
    knock = np.sin(2 * np.pi * (150 + 90 * np.exp(-t * 60)) * t) * np.exp(-t * 28)
    body = bandpass(noise(d), 400, 2200) * np.exp(-t * 38) * 0.9
    click = highpass(noise(d), 3000) * np.exp(-t * 160) * 0.35
    return (knock * 0.8 + body + click) * np.minimum(1, t / 0.002)

def sfx_reveal():  # 0,4 s Stille, dann Fanfare, 3,6 s
    d = 3.6; y = np.zeros(int(d * SR)); s = 0.4
    for i, (m, tt, dur) in enumerate([(60, 0.0, 0.25), (64, 0.18, 0.25), (67, 0.36, 0.25), (72, 0.54, 1.9)]):
        for dm, v in ((0, 1.0), (-12, 0.5), (4, 0.35) if i == 3 else (7, 0.0)):
            if v: place(y, brass(mtof(m + dm), dur, 0.28 * v), s + tt)
    for k, m in enumerate((84, 88, 91, 96, 100)): place(y, bell(mtof(m), 1.5, 0.3), s + 0.54 + k * 0.07)
    place(y, kick(0.6), s + 0.54); place(y, lowpass(noise(0.9), 6000) * np.exp(-t_arr(0.9) * 4) * 0.25, s + 0.54)
    return reverb(y, 1.6, 0.3)

def sfx_terminal_idle():  # leises Summen, nahtlose Schleife (4 s)
    d = 4.0; t = t_arr(d)
    y = np.sin(2 * np.pi * 110 * t) * 0.5 + np.sin(2 * np.pi * 220 * t) * 0.2 + np.sin(2 * np.pi * 330 * t) * 0.06
    y *= 0.8 + 0.2 * np.sin(2 * np.pi * 0.5 * t)    # ganze Perioden: 110/220/330 Hz und 0,5 Hz passen in 4 s
    return y * 0.5

def sfx_ready():  # zwei Pieptoene
    y = np.zeros(int(0.5 * SR))
    for st, f in ((0.0, 880), (0.14, 1320)):
        tt = t_arr(0.16); place(y, (np.sin(2 * np.pi * f * tt) + 0.2 * np.sin(4 * np.pi * f * tt)) * adsr(len(tt), 0.004, 0.02, 0.7, 0.05), st)
    return y * 0.6

def sfx_press():  # hartes, leicht ironisches Klacken, 0,3 s
    d = 0.3; t = t_arr(d)
    clk = highpass(noise(d), 1800) * np.exp(-t * 90) * 0.9
    ping = np.sin(2 * np.pi * 1100 * t) * np.exp(-t * 55) * 0.35
    thud = np.sin(2 * np.pi * (95 + 60 * np.exp(-t * 50)) * t) * np.exp(-t * 20) * 0.9
    return reverb((clk + ping + thud) * np.minimum(1, t / 0.001), 0.3, 0.12)[:int(d * SR)]

def sfx_countdown():  # ein Zaehlton, 0,45 s
    d = 0.45; t = t_arr(d)
    y = (np.sin(2 * np.pi * 660 * t) + 0.35 * np.sin(2 * np.pi * 1320 * t)) * adsr(len(t), 0.006, 0.05, 0.6, 0.2)
    return reverb(y * 0.6, 0.4, 0.15)[:int(d * SR)]

def sfx_launch():  # Rumpeln -> Zischen, 4,0 s
    d = 4.0; n = int(d * SR); t = t_arr(d); y = np.zeros(n)
    rum = lowpass(noise(d), 160, 2) * 6 + np.sin(2 * np.pi * (42 + 18 * (t / d)) * t) * 0.9
    rum *= np.minimum(1, t / 0.5) * np.where(t > 2.6, np.exp(-(t - 2.6) * 2.2), 1)
    hiss = bandpass(noise(d), 1200 + 0 , 9000) * 0.55
    hiss *= np.clip((t - 0.4) / 1.2, 0, 1) * np.where(t > 2.9, np.exp(-(t - 2.9) * 3.5), 1)
    wob = 0.85 + 0.15 * np.sin(2 * np.pi * 9 * t)
    y = rum * 0.45 * wob + hiss * 0.5
    return y

def sfx_unlock():  # Sieges-Jingle, 3,0 s
    d = 3.0; y = np.zeros(int(d * SR))
    for k, m in enumerate((72, 76, 79, 84, 88, 91, 96)): place(y, bell(mtof(m), 1.2, 0.45), k * 0.1)
    for m in (60, 64, 67, 72): place(y, brass(mtof(m), 1.6, 0.18, 2200), 0.7)
    for m in (55, 59, 62): place(y, pad(mtof(m), 2.2, 0.18), 0.7)
    place(y, kick(0.5), 0.7)
    for k in range(8): place(y, shaker(0.7), 0.7 + k * 0.11)
    return reverb(y, 1.6, 0.3)[:int(d * SR)]

SFX = {"hit": sfx_hit, "flash": sfx_flash, "rise": sfx_rise, "run": sfx_run, "reveal": sfx_reveal,
       "terminal_idle": sfx_terminal_idle, "ready": sfx_ready, "press": sfx_press,
       "countdown": sfx_countdown, "launch": sfx_launch, "unlock": sfx_unlock}

# ----------------------------------------------------------------- Musik (Schleife)
def music():
    bpm = 100; beat = 60 / bpm; bar = 4 * beat; bars = 32; d = bars * bar; n = int(d * SR)
    L = np.zeros(n); R = np.zeros(n)
    prog = [(48, (60, 64, 67)), (45, (57, 60, 64)), (41, (53, 57, 60)), (43, (55, 59, 62))]   # C Am F G
    def add(sig, start, pan=0.0, gain=1.0):
        g_l = gain * np.cos((pan + 1) * np.pi / 4); g_r = gain * np.sin((pan + 1) * np.pi / 4)
        place(L, sig * g_l, start, True); place(R, sig * g_r, start, True)
    scale = (72, 74, 76, 79, 81, 84)   # Pentatonik
    motif = [(0, 0, 1), (1, 1, 1), (2, 2, 2), (4, 0, 1), (5, 2, 1), (6, 3, 2)]   # (Viertel ab Taktbeginn, Skalenindex, Laenge)
    for b in range(bars):
        root, ch = prog[b % 4]; t0 = b * bar
        sec = b // 8   # 0 Intro, 1 Aufbau, 2 Hoehepunkt, 3 ruhiges Finale
        lvl = (0.55, 0.8, 1.0, 0.5)[sec]
        for m in ch: add(pad(mtof(m), bar * 1.05, 0.34 * lvl), t0, (m - 60) / 12 * 0.6)
        for k, off in enumerate((0, 2)):
            add(pizz(mtof(root), beat * 1.5, 0.55 * lvl), t0 + off * beat, -0.2)
        if sec in (1, 2):
            add(kick(0.55 * lvl), t0, 0.0); add(kick(0.4 * lvl), t0 + 2 * beat, 0.0)
            for k in range(8): add(shaker(0.5 * lvl), t0 + k * beat / 2, 0.4 if k % 2 else -0.4)
        # Glockenspiel-Arpeggio
        for k, m in enumerate(ch): add(bell(mtof(m + 24), 1.0, 0.16 * lvl), t0 + k * beat * (0.5 if sec else 1.0), 0.5)
        # Melodie
        if sec == 2 or (sec == 1 and b % 2 == 1) or (sec == 3 and b % 4 == 0):
            off = (b % 4) % 2 * 0
            for (q, si, ln) in motif:
                note = scale[(si + (b % 4)) % len(scale)] + (0 if sec != 3 else 0)
                dur = ln * beat * 0.95
                inst = brass(mtof(note), dur, 0.28 * lvl, 2400) if sec == 2 else bell(mtof(note), 1.2, 0.3 * lvl)
                add(inst, t0 + q * beat * 0.5, -0.15 if sec == 2 else 0.2)
        if sec == 2 and b % 4 == 0:
            for m in (ch[0] - 12, ch[1] - 12): add(brass(mtof(m), bar * 0.9, 0.2, 1800), t0, -0.5)
    for ch_ in (L, R): ch_ *= 1.0
    # Hall auf der Summe, dann zirkulaer fuer die Schleife zusammenfalten
    def fold(x):
        y = reverb(x, 2.0, 0.28)
        out = y[:n].copy(); tail = y[n:]; out[:len(tail)] += tail; return out
    L = fold(L); R = fold(R)
    return np.stack([L, R], axis=1)

# ----------------------------------------------------------------- Ausgabe
def write_wav(path, x, sr=SR):
    x = np.clip(x, -1, 1); d = (x * 32767).astype("<i2")
    ch = 1 if x.ndim == 1 else x.shape[1]
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(ch); w.setsampwidth(2); w.setframerate(sr); w.writeframes(d.tobytes())

def lufs(path):
    r = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", path, "-af", "ebur128=peak=true", "-f", "null", "-"],
                       capture_output=True, text=True).stderr
    i = r.rfind("I:"); s = r[i:i + 30].split()
    return float(s[1]) if len(s) > 1 else -70.0

def lufs_x(x):
    """Lautheit; sehr kurze Klaenge werden zum Messen wiederholt (ebur128 braucht >= 0,4 s)."""
    reps = int(np.ceil(3 * SR / max(len(x), 1))) if len(x) < SR * 3 else 1
    y = np.concatenate([x] * reps) if x.ndim == 1 else np.concatenate([x] * reps, axis=0)
    t = os.path.join(tempfile.gettempdir(), "hbb_epilog_tmp.wav"); write_wav(t, np.clip(y, -1, 1)); return lufs(t)

def master(x, target=-16.0, name=""):
    """Zielpegel ueber ebur128, Spitze hart auf -1,5 dB begrenzt (weicher Anschlag davor)."""
    peak = 10 ** (-1.5 / 20)
    y = x / (np.max(np.abs(x)) + 1e-9) * 0.5
    for _ in range(3):
        cur = lufs_x(y)
        y = y * 10 ** ((target - cur) / 20)
        y = np.tanh(y / 0.95) * 0.95 if np.max(np.abs(y)) > peak else y
        m = np.max(np.abs(y))
        if m > peak: y = y * (peak / m)
    return y

def to_ogg(wav, ogg, stereo=False):
    os.makedirs(os.path.dirname(ogg), exist_ok=True)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-ar", "44100", "-ac", "2" if stereo else "1",
                    "-c:a", "libvorbis", "-q:a", "5", ogg], check=True)

def main():
    report = {}
    for name, fn in SFX.items():
        x = fn(); x = x - np.mean(x) if name != "terminal_idle" else x
        y = master(x, -16.0)
        p = os.path.join(OUT, "sfx", f"epilog_{name}.wav"); write_wav(p, y)
        to_ogg(p, os.path.join(OGG, f"epilog_{name}.ogg"))
        report[f"sfx/epilog_{name}"] = {"s": round(len(y) / SR, 2), "peak_db": round(20 * np.log10(np.max(np.abs(y))), 1), "lufs": round(lufs_x(y), 1)}
    m = music(); y = master(m, -16.0)
    p = os.path.join(OUT, "music", "epilog.wav"); write_wav(p, y)
    to_ogg(p, os.path.join(OGG, "epilog_music.ogg"), True)
    seam = float(np.max(np.abs(y[0] - y[-1])))
    report["music/epilog"] = {"s": round(len(y) / SR, 1), "peak_db": round(20 * np.log10(np.max(np.abs(y))), 1), "lufs": round(lufs_x(y), 1), "naht": round(seam, 5)}
    json.dump(report, open(os.path.join(OUT, "epilog_report.json"), "w"), indent=1)
    for k, v in report.items(): print(k.ljust(26), v)

if __name__ == "__main__":
    main()
