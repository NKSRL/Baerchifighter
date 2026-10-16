// synth.js — erzeugt Musik (3 nahtlose Schleifen) und Effekte fuer Honey Bear Brawl.
// Alles selbst berechnet (Sinus-/Rauschen-Synthese), keine fremden Samples, kein KI-Dienst.
// Aufruf: node tools/audio/synth.js [ausgabeordner]   (Standard: tools/audio/out)
// Ergebnis: out/music/*.wav (Stereo, 32 kHz) und out/sfx/*.wav (Mono, 32 kHz).
// Weich gehalten: Tiefpass ~5-6 kHz, keine scharfen Anschlaege, Hall nur ueber
// Ringpuffer-Rendering (Schleife wird zweimal gerendert, die zweite Haelfte
// genommen -> Anfang und Ende passen sample-genau ineinander).
"use strict";
const fs = require("fs");
const path = require("path");

const SR = 32000;
const OUT = process.argv[2] || path.join(__dirname, "out");

// ---------------------------------------------------------------- Hilfen
function rng(seed) { // mulberry32, damit jeder Lauf gleich klingt
  let a = seed >>> 0;
  return () => { a = (a + 0x6D2B79F5) >>> 0; let t = a; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}
const mtof = m => 440 * Math.pow(2, (m - 69) / 12);
const buf = n => new Float32Array(Math.max(1, Math.floor(n)));

function lowpass(x, fc, passes = 1) { // Ein-Pol-Tiefpass, mehrfach = steiler
  const a = 1 - Math.exp(-2 * Math.PI * fc / SR);
  for (let p = 0; p < passes; p++) { let y = 0; for (let i = 0; i < x.length; i++) { y += a * (x[i] - y); x[i] = y; } }
  return x;
}
function highpass(x, fc) { const lo = lowpass(Float32Array.from(x), fc); for (let i = 0; i < x.length; i++) x[i] -= lo[i]; return x; }

// Stereo-Hall (Comb + Allpass), arbeitet linear, daher fuer den Zwei-Durchlauf-Trick geeignet
function reverb(L, R, mix, size = 1, fb = 0.8, damp = 4500) {
  const combD = [1687, 1601, 2053, 2251, 1877, 2131].map(d => Math.floor(d * size * SR / 44100));
  const out = [new Float32Array(L.length), new Float32Array(R.length)];
  [L, R].forEach((src, ch) => {
    const wet = out[ch];
    combD.forEach((d0, k) => {
      const d = d0 + (ch ? 23 * (k + 1) : 0);
      const line = new Float32Array(d); let idx = 0, lpState = 0;
      const dA = 1 - Math.exp(-2 * Math.PI * damp / SR);
      for (let i = 0; i < src.length; i++) {
        const y = line[idx]; lpState += dA * (y - lpState);
        line[idx] = src[i] + lpState * fb; idx = (idx + 1) % d; wet[i] += y / combD.length * 1.6;
      }
    });
    for (const d of [225, 556].map(v => Math.floor(v * SR / 44100))) { // Allpass
      const line = new Float32Array(d); let idx = 0;
      for (let i = 0; i < wet.length; i++) { const z = line[idx]; const v = wet[i] + z * 0.5; line[idx] = v; wet[i] = z - v * 0.5; idx = (idx + 1) % d; }
    }
  });
  for (let i = 0; i < L.length; i++) { L[i] = L[i] * (1 - mix) + out[0][i] * mix; R[i] = R[i] * (1 - mix) + out[1][i] * mix; }
}

function writeWav(file, chans, sr = SR) { // 16 Bit PCM
  const n = chans[0].length, nc = chans.length, data = Buffer.alloc(n * nc * 2);
  for (let i = 0; i < n; i++) for (let c = 0; c < nc; c++) {
    const v = Math.max(-1, Math.min(1, chans[c][i])); data.writeInt16LE(Math.round(v * 32767), (i * nc + c) * 2);
  }
  const h = Buffer.alloc(44);
  h.write("RIFF", 0); h.writeUInt32LE(36 + data.length, 4); h.write("WAVEfmt ", 8); h.writeUInt32LE(16, 16); h.writeUInt16LE(1, 20);
  h.writeUInt16LE(nc, 22); h.writeUInt32LE(sr, 24); h.writeUInt32LE(sr * nc * 2, 28); h.writeUInt16LE(nc * 2, 32); h.writeUInt16LE(16, 34);
  h.write("data", 36); h.writeUInt32LE(data.length, 40);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, Buffer.concat([h, data]));
}
function peak(x) { let p = 0; for (const v of x) p = Math.max(p, Math.abs(v)); return p; }
function softClip(x, drive = 1) { for (let i = 0; i < x.length; i++) x[i] = Math.tanh(x[i] * drive) / Math.tanh(drive); }

// ---------------------------------------------------------------- Stimmen (addieren in buf ab Sekunde t)
function add(dst, t, src, gain = 1, pan = 0) { // pan -1..1 nur fuer Stereo-Paare (dst = [L,R])
  const s0 = Math.floor(t * SR);
  const targets = Array.isArray(dst) ? dst : [dst];
  targets.forEach((d, ch) => {
    const g = gain * (targets.length === 2 ? (ch === 0 ? Math.cos((pan + 1) * Math.PI / 4) : Math.sin((pan + 1) * Math.PI / 4)) * Math.SQRT2 : 1);
    for (let i = 0; i < src.length; i++) { const j = s0 + i; if (j >= d.length) break; d[j] += src[i] * g; }
  });
}
function tone(freq, dur, { a = 0.01, d = dur, harm = [[1, 1]], sweep = 0, vib = 0, curve = 3 } = {}) { // exponentiell abklingender Klang
  const n = Math.floor(dur * SR), o = buf(n), ph = harm.map(() => 0);
  for (let i = 0; i < n; i++) {
    const t = i / SR; const f = freq * (1 + sweep * Math.exp(-t * 14)) * (1 + vib * Math.sin(2 * Math.PI * 5 * t));
    let s = 0; harm.forEach((h, k) => { ph[k] += 2 * Math.PI * f * h[0] / SR; s += Math.sin(ph[k]) * h[1] * (h[2] ? Math.exp(-t * h[2]) : 1); });
    const att = Math.min(1, t / a), dec = Math.exp(-curve * t / d), rel = Math.min(1, (dur - t) / 0.02);
    o[i] = s * att * dec * Math.max(0, rel);
  }
  return o;
}
function padVoice(freq, dur, vel = 1) { // warm: 3 leicht verstimmte Sinus + Oktave, langsames An/Abschwellen
  const n = Math.floor(dur * SR), o = buf(n), det = [0.997, 1, 1.003, 0.5];
  const att = Math.min(1.1, dur * 0.35), rel = Math.min(1.4, dur * 0.4);
  for (let i = 0; i < n; i++) {
    const t = i / SR; let s = 0;
    det.forEach((dv, k) => { s += Math.sin(2 * Math.PI * freq * dv * t + k) * (k === 3 ? 0.35 : 0.5) + Math.sin(2 * Math.PI * freq * 2 * dv * t) * 0.07; });
    o[i] = s * vel * Math.min(1, t / att) * Math.min(1, (dur - t) / rel);
  }
  return o;
}
const epiano = (f, d = 1.6) => tone(f, d, { a: 0.008, d: d * 0.55, harm: [[1, 1], [2, 0.28, 7], [4, 0.06, 14], [0.5, 0.08]], curve: 3.2 });
const kalimba = (f, d = 1.1) => tone(f, d, { a: 0.004, d: d * 0.4, harm: [[1, 1], [5.4, 0.1, 18], [2, 0.12, 10]], curve: 4 });
const marimba = (f, d = 0.7) => tone(f, d, { a: 0.003, d: d * 0.3, harm: [[1, 1], [3.9, 0.12, 20], [10, 0.02, 40]], curve: 4 });
const bassVoice = (f, d = 0.9) => tone(f, d, { a: 0.012, d: d * 0.6, harm: [[1, 1], [2, 0.22, 4]], curve: 3 });
function kick(vel = 1) { const n = Math.floor(0.3 * SR), o = buf(n); let ph = 0; for (let i = 0; i < n; i++) { const t = i / SR; ph += 2 * Math.PI * (44 + 70 * Math.exp(-t * 28)) / SR; o[i] = Math.sin(ph) * Math.exp(-t * 11) * Math.min(1, t / 0.003) * vel; } return o; }
function shaker(rand, vel = 1, len = 0.07) { const n = Math.floor(len * SR), o = buf(n); for (let i = 0; i < n; i++) o[i] = (rand() * 2 - 1) * Math.sin(Math.PI * Math.min(1, i / n * 1.0)) ** 2 * vel; highpass(o, 2500); lowpass(o, 6000, 2); return o; }
function noise(rand, dur) { const o = buf(dur * SR); for (let i = 0; i < o.length; i++) o[i] = rand() * 2 - 1; return o; }
function finish(o, fadeIn = 0.003, fadeOut = 0.03) { const a = Math.floor(fadeIn * SR), b = Math.floor(fadeOut * SR); for (let i = 0; i < a && i < o.length; i++) o[i] *= i / a; for (let i = 0; i < b && i < o.length; i++) o[o.length - 1 - i] *= i / b; return o; }

// ---------------------------------------------------------------- Musik
const CH = { // Akkord = Intervalle ab Grundton
  maj7: [0, 4, 7, 11], m7: [0, 3, 7, 10], six: [0, 4, 7, 9], sus: [0, 5, 7, 10], maj: [0, 4, 7, 12], add9: [0, 4, 7, 14], m: [0, 3, 7, 12],
};
const NOTE = { C: 0, D: 2, E: 4, F: 5, G: 7, A: 9, B: 11, Bb: 10 };

function renderMusic(spec) {
  const beat = 60 / spec.bpm, bar = beat * 4, bars = spec.sections.length * 8, total = bars * bar;
  const N = Math.round(total * SR), rand = rng(spec.seed);
  // Zwei Durchlaeufe hintereinander -> zweite Haelfte ist der eingeschwungene, nahtlose Loop
  const L = buf(N * 2), R = buf(N * 2), mono = [L, R];
  for (let pass = 0; pass < 2; pass++) {
    const off = pass * total;
    spec.sections.forEach((sec, si) => {
      const lay = spec.layers[si];
      for (let b = 0; b < 8; b++) {
        const [rootName, type] = spec.progs[sec][b], root = NOTE[rootName], t0 = off + (si * 8 + b) * bar;
        const notes = CH[type].map(iv => 48 + root + iv); // C3-Bereich
        // Pad (immer da, Grundlage)
        if (lay.pad) notes.forEach((m, k) => add(mono, t0, padVoice(mtof(m + (k > 2 ? -12 : 0)), bar + 0.7), 0.075 * lay.pad, k % 2 ? 0.3 : -0.3));
        // Bass
        if (lay.bass) {
          const bm = 36 + root + (root > 7 ? -12 : 0) + (spec.bassUp || 0);
          if (spec.bassStyle === "pulse") for (let e = 0; e < 8; e++) add(mono, t0 + e * beat / 2, bassVoice(mtof(bm + (e % 4 === 3 ? 7 : e % 4 === 2 ? 12 : 0)), beat * 0.45), 0.2 * lay.bass * (e % 2 ? 0.75 : 1), 0);
          else { add(mono, t0, bassVoice(mtof(bm), beat * 3.6), 0.26 * lay.bass, 0); if (lay.bass > 1) add(mono, t0 + beat * 2.5, bassVoice(mtof(bm + 7), beat * 1.3), 0.15, 0); }
        }
        // Akkord-/Arpeggio-Stimme
        if (lay.keys) {
          const pool = notes.map(m => m + 12);
          if (spec.keyStyle === "arp") for (let e = 0; e < 8; e++) add(mono, t0 + e * beat / 2, epiano(mtof(pool[[0, 1, 2, 3, 2, 1, 3, 2][e] % pool.length]), 1.1), 0.075 * lay.keys, ((e % 4) - 1.5) * 0.25);
          else if (spec.keyStyle === "fast") for (let e = 0; e < 16; e++) { if (e % 4 === 3 && b % 2) continue; add(mono, t0 + e * beat / 4, marimba(mtof(pool[[0, 2, 1, 3, 2, 3, 1, 2][e % 8]] ), 0.45), 0.06 * lay.keys, ((e % 8) - 3.5) * 0.12); }
          else { add(mono, t0 + 0.0, epiano(mtof(pool[0]), 3), 0.07 * lay.keys, -0.2); add(mono, t0 + beat * 1.5, epiano(mtof(pool[2]), 2.4), 0.055 * lay.keys, 0.2); if (lay.keys > 1) add(mono, t0 + beat * 3, epiano(mtof(pool[1]), 2), 0.05, 0); }
        }
        // Melodie: Pentatonik, Zufallsgang mit Vorliebe fuer kleine Schritte; Motiv alle 2 Takte leicht wiederholt
        if (lay.melody) {
          const motifSeed = rng(spec.seed * 31 + sec.charCodeAt(0) * 7 + (b >> 1) * 13 + (b & 1));
          const pat = spec.rhythms[Math.floor(motifSeed() * spec.rhythms.length)];
          let idx = Math.floor(spec.scale.length / 2 + (motifSeed() - 0.5) * 3);
          pat.forEach((bt, k) => {
            const r = motifSeed(); idx += r < 0.35 ? -1 : r < 0.7 ? 1 : r < 0.82 ? 2 : r < 0.94 ? -2 : 0;
            idx = Math.max(0, Math.min(spec.scale.length - 1, idx));
            if (rand() < spec.rest * (2 - lay.melody)) return; // Pausen halten es luftig
            const inst = spec.melodyInst === "marimba" ? marimba : kalimba;
            add(mono, t0 + bt * beat, inst(mtof(spec.scale[idx]), 1.2), 0.1 * Math.min(1, lay.melody), 0.25 * Math.sin(k + b));
          });
        }
        // Percussion
        if (lay.perc) {
          if (spec.kick && lay.perc > 0.5) for (const kb of [0, 2]) add(mono, t0 + kb * beat, kick(1), 0.2 * lay.perc, 0);
          for (let e = 0; e < 8; e++) { if (spec.shaker === "off" && e % 2 === 0) continue; add(mono, t0 + e * beat / 2, shaker(rand, 0.5 + 0.5 * (e % 2), 0.06), 0.05 * lay.perc * (e % 2 ? 1 : 0.7), (e % 2 ? 0.35 : -0.35)); }
        }
      }
    });
  }
  lowpass(L, spec.cutoff, 2); lowpass(R, spec.cutoff, 2);
  reverb(L, R, spec.reverb, 1.2, 0.82, 4000);
  const lo = N, outL = L.slice(lo, lo + N), outR = R.slice(lo, lo + N);
  let e = 0; for (let i = 0; i < N; i++) e += outL[i] * outL[i];
  const g = 0.09 / Math.sqrt(e / N); // gleiche Lautheit (RMS ca. -20 dB) fuer alle drei Schleifen; Lautstaerke regelt die Config
  for (let i = 0; i < N; i++) { outL[i] *= g; outR[i] *= g; }
  softClip(outL, 1.1); softClip(outR, 1.1);
  return [outL, outR];
}

const PRG = (c) => c; // nur Lesbarkeit
const P = {
  main: {
    a: [["C", "maj7"], ["A", "m7"], ["F", "maj7"], ["G", "six"], ["C", "add9"], ["A", "m7"], ["F", "six"], ["G", "sus"]],
    b: [["F", "maj7"], ["G", "six"], ["E", "m7"], ["A", "m7"], ["F", "maj7"], ["G", "sus"], ["C", "maj7"], ["C", "six"]],
    c: [["A", "m7"], ["F", "maj7"], ["C", "add9"], ["G", "six"], ["A", "m7"], ["F", "maj7"], ["G", "sus"], ["C", "maj7"]],
  },
  menu: {
    a: [["F", "maj7"], ["D", "m7"], ["Bb", "maj7"], ["C", "six"], ["F", "add9"], ["D", "m7"], ["Bb", "six"], ["C", "sus"]],
    b: [["D", "m7"], ["Bb", "maj7"], ["F", "maj7"], ["C", "six"], ["D", "m7"], ["G", "m7"], ["C", "sus"], ["F", "maj7"]],
  },
  fight: {
    a: [["G", "maj"], ["E", "m7"], ["C", "maj7"], ["D", "six"], ["G", "maj"], ["E", "m7"], ["C", "maj7"], ["D", "sus"]],
    b: [["E", "m7"], ["C", "maj7"], ["G", "six"], ["D", "six"], ["E", "m7"], ["C", "maj7"], ["D", "sus"], ["G", "maj"]],
  },
};
const pent = (root, oct) => [0, 2, 4, 7, 9, 12, 14].map(iv => root + iv + oct); // Dur-Pentatonik ueber 1,3 Oktaven

const TRACKS = {
  main: { // Farm/Lobby: ruhig, waechst langsam (≈104 s)
    bpm: 92, seed: 11, cutoff: 5200, reverb: 0.28, keyStyle: "arp", bassStyle: "long", shaker: "light", kick: false, rest: 0.3,
    progs: P.main, sections: ["a", "b", "a", "c", "a"],
    layers: [{ pad: 1, bass: 1 }, { pad: 1, bass: 1, keys: 1, perc: 0.5 }, { pad: 1, bass: 1.2, keys: 1, melody: 1, perc: 0.6 }, { pad: 1, bass: 1.2, keys: 1.1, melody: 1.2, perc: 0.8 }, { pad: 1, bass: 1, keys: 0.8, melody: 0.6 }],
    scale: pent(72, 0), rhythms: [[0, 1.5, 2, 3], [0.5, 1, 2.5], [0, 2, 3.5], [1, 2, 3], [0, 1, 1.5, 3]],
  },
  menu: { // Menues/Shops: sehr ruhig, keine Percussion (≈100 s bei 86 BPM)
    bpm: 86, seed: 23, cutoff: 4600, reverb: 0.36, keyStyle: "long", bassStyle: "long", shaker: "off", kick: false, rest: 0.45,
    progs: P.menu, sections: ["a", "b", "a", "b", "a"].slice(0, 4).concat(["a"]),
    layers: [{ pad: 1, bass: 0.8 }, { pad: 1, bass: 1, keys: 1 }, { pad: 1, bass: 1, keys: 1.2, melody: 0.8 }, { pad: 1, bass: 1, keys: 1, melody: 1 }, { pad: 1, bass: 0.8, keys: 0.8 }],
    scale: pent(65, 0), rhythms: [[0, 2.5], [1, 3], [0.5, 2], [1.5, 3.5]],
  },
  fight: { // Kampf/Tower: etwas treibend, weicher Kick (≈96 s bei 100 BPM)
    bpm: 100, seed: 37, cutoff: 5600, reverb: 0.2, keyStyle: "fast", bassStyle: "pulse", shaker: "full", kick: true, rest: 0.2, melodyInst: "marimba",
    progs: P.fight, sections: ["a", "b", "a", "b", "a"],
    layers: [{ pad: 0.8, bass: 1, perc: 0.4 }, { pad: 0.8, bass: 1, keys: 1, perc: 0.8 }, { pad: 0.8, bass: 1, keys: 1, melody: 1, perc: 1 }, { pad: 0.9, bass: 1.1, keys: 1.1, melody: 1.2, perc: 1 }, { pad: 0.8, bass: 1, keys: 0.8, melody: 0.6, perc: 0.6 }],
    scale: pent(67, 0), rhythms: [[0, 0.5, 1.5, 2, 3], [0, 1, 1.5, 2.5, 3.5], [0.5, 1, 2, 3, 3.5], [0, 1.5, 2, 2.5]],
  },
};

// ---------------------------------------------------------------- Effekte (Mono, kurz, weich)
function sfx() {
  const S = {}, rand = rng(5), mono = (len) => buf(len * SR);
  const mk = (name, len, fn, cut = 5500, gain = 0.8) => { const o = mono(len); fn(o); lowpass(o, cut, 2); finish(o); const p = peak(o); for (let i = 0; i < o.length; i++) o[i] *= gain / (p || 1); S[name] = o; };
  const note = (o, t, f, d, inst, g = 1) => add(o, t, inst(f, d), g);
  const bell = (f, d) => tone(f, d, { a: 0.004, d: d * 0.45, harm: [[1, 1], [2.76, 0.18, 6], [4, 0.06, 10]], curve: 4 });
  const chord = (o, t, ms, d, g = 0.4) => ms.forEach((m, k) => add(o, t + k * 0.012, padVoice(mtof(m), d), g));

  // Routine: klein, kurz, leise genug fuer Dauerfeuer
  mk("click", 0.09, o => add(o, 0, tone(520, 0.09, { a: 0.002, d: 0.03, harm: [[1, 1], [2, 0.2, 40]], sweep: 0.25 })), 3800, 0.7);
  mk("select", 0.14, o => { note(o, 0, mtof(72), 0.1, marimba); note(o, 0.05, mtof(76), 0.09, marimba, 0.8); }, 4200, 0.7);
  mk("coin", 0.28, o => { note(o, 0, mtof(79), 0.18, kalimba); note(o, 0.07, mtof(84), 0.2, kalimba, 0.9); }, 5000, 0.7);
  mk("hit", 0.16, o => { add(o, 0, tone(150, 0.14, { a: 0.002, d: 0.05, harm: [[1, 1], [2, 0.25, 30]], sweep: 0.8 })); add(o, 0, lowpass(noise(rand, 0.06), 1800, 2), 0.25); }, 2200, 0.75);
  mk("hitHeavy", 0.3, o => { add(o, 0, tone(95, 0.28, { a: 0.003, d: 0.1, harm: [[1, 1], [2, 0.3, 20]], sweep: 1.0 })); add(o, 0, lowpass(noise(rand, 0.1), 1200, 2), 0.35); }, 1800, 0.8);
  mk("eggCollect", 0.3, o => { note(o, 0, mtof(67), 0.2, marimba); note(o, 0.08, mtof(74), 0.2, marimba, 0.9); note(o, 0.16, mtof(79), 0.14, marimba, 0.8); }, 4600, 0.75);
  // Fortschritt
  mk("upgrade", 0.55, o => { [72, 76, 79].forEach((m, k) => note(o, k * 0.09, mtof(m), 0.4, bell, 0.9)); }, 5200, 0.8);
  mk("upgradeBig", 0.95, o => { [67, 72, 76, 79, 84].forEach((m, k) => note(o, k * 0.1, mtof(m), 0.7, bell, 0.85)); chord(o, 0.1, [48, 55, 64], 0.8, 0.12); }, 5200, 0.85);
  mk("unlock", 1.2, o => { chord(o, 0, [55, 62, 67, 71], 1.1, 0.25); [74, 79, 83].forEach((m, k) => note(o, 0.15 + k * 0.12, mtof(m), 0.8, bell, 0.7)); }, 4800, 0.85);
  mk("hatchCrack", 0.4, o => { for (const t of [0, 0.09]) add(o, t, lowpass(noise(rand, 0.05), 2500, 2), 0.6); add(o, 0.0, tone(220, 0.12, { a: 0.002, d: 0.04, sweep: 0.5 }), 0.4); add(o, 0.2, tone(330, 0.2, { a: 0.003, d: 0.08, sweep: 0.8 }), 0.3); }, 3600, 0.75);
  mk("hatchCommon", 0.7, o => { note(o, 0, mtof(72), 0.5, bell, 0.8); note(o, 0.1, mtof(79), 0.5, bell, 0.7); chord(o, 0, [60, 67], 0.6, 0.15); }, 5000, 0.8);
  // Selten & gross: deutlich belohnender, laenger (1.4-3.2 s)
  mk("hatchRare", 2.0, o => { chord(o, 0, [57, 64, 69, 72], 1.8, 0.28); [76, 79, 81, 84, 88].forEach((m, k) => note(o, 0.12 + k * 0.11, mtof(m), 1.1, bell, 0.8)); [91, 88, 84].forEach((m, k) => note(o, 0.8 + k * 0.1, mtof(m), 0.9, bell, 0.5)); }, 5800, 0.9);
  mk("levelUp", 1.6, o => { [60, 64, 67, 72, 76, 79].forEach((m, k) => note(o, k * 0.08, mtof(m), 0.7, marimba, 0.9)); chord(o, 0.45, [60, 67, 72, 76], 1.2, 0.3); note(o, 0.5, mtof(84), 1.0, bell, 0.8); }, 5600, 0.9);
  mk("moment", 1.2, o => { [67, 72, 76].forEach((m, k) => note(o, k * 0.1, mtof(m), 0.6, bell, 0.8)); chord(o, 0.2, [55, 64, 67], 0.9, 0.2); }, 5200, 0.8);
  mk("rebirth", 3.2, o => { chord(o, 0, [48, 55, 60, 64], 3.0, 0.35); chord(o, 0.9, [55, 62, 67, 71], 2.2, 0.28); [60, 64, 67, 72, 76, 79, 84, 88].forEach((m, k) => note(o, 0.3 + k * 0.17, mtof(m), 1.4, bell, 0.7)); add(o, 1.8, bell(mtof(91), 1.4), 0.6); }, 5600, 0.95);
  // Faehigkeits-Bibliothek (gleiche Namen wie SkillFXConfig.SOUND_LIBRARY), alle gerundet
  const sw = (o, t, dur, f0, f1, g) => { const n = noise(rand, dur); lowpass(n, f1, 2); const env = n.map((v, i) => v * Math.sin(Math.PI * (i / n.length)) ** 1.5); add(o, t, env, g); };
  mk("fx_whoosh", 0.45, o => sw(o, 0, 0.4, 400, 1800, 1), 1800, 0.55);
  mk("fx_hit", 0.2, o => { add(o, 0, tone(170, 0.18, { a: 0.002, d: 0.06, sweep: 0.7 })); }, 2000, 0.65);
  mk("fx_ping", 0.4, o => note(o, 0, mtof(79), 0.35, bell), 4200, 0.6);
  mk("fx_boom", 0.7, o => { add(o, 0, tone(70, 0.65, { a: 0.004, d: 0.22, sweep: 1.2 })); add(o, 0, lowpass(noise(rand, 0.18), 800, 2), 0.3); }, 1200, 0.8);
  mk("fx_glass", 0.5, o => { [88, 91, 95].forEach((m, k) => note(o, k * 0.03, mtof(m), 0.35, bell, 0.6)); }, 4800, 0.5);
  mk("fx_splat", 0.3, o => { add(o, 0, lowpass(noise(rand, 0.22), 1500, 2).map((v, i, a) => v * Math.exp(-i / SR * 14)), 1); add(o, 0, tone(140, 0.2, { a: 0.003, d: 0.07, sweep: 1 }), 0.5); }, 1800, 0.65);
  mk("fx_snap", 0.18, o => { add(o, 0, tone(900, 0.12, { a: 0.001, d: 0.03, sweep: -0.4, harm: [[1, 1], [1.5, 0.3, 30]] })); }, 3000, 0.55);
  mk("fx_rocket", 0.7, o => { sw(o, 0, 0.6, 300, 1400, 0.9); add(o, 0, tone(260, 0.5, { a: 0.05, d: 0.3, sweep: 1.4 }), 0.35); }, 1600, 0.65);
  mk("fx_rumble", 0.9, o => { add(o, 0, tone(55, 0.85, { a: 0.1, d: 0.5, harm: [[1, 1], [1.5, 0.3]] })); sw(o, 0, 0.8, 200, 700, 0.35); }, 900, 0.7);
  mk("fx_slash", 0.3, o => sw(o, 0, 0.25, 800, 2600, 1), 2600, 0.5);
  mk("fx_lunge", 0.35, o => { sw(o, 0, 0.3, 500, 1800, 0.8); add(o, 0.15, tone(130, 0.18, { a: 0.003, d: 0.06 }), 0.4); }, 2000, 0.55);
  mk("fx_thunder", 1.3, o => { add(o, 0, tone(48, 1.2, { a: 0.05, d: 0.5, harm: [[1, 1], [1.7, 0.3]] })); sw(o, 0, 1.0, 150, 600, 0.45); }, 800, 0.7);
  mk("fx_ghost", 1.0, o => { add(o, 0, tone(330, 0.95, { a: 0.3, d: 0.6, vib: 0.02, harm: [[1, 1], [1.5, 0.4]] })); add(o, 0, tone(247, 0.95, { a: 0.3, d: 0.6, vib: 0.02 }), 0.7); }, 2200, 0.45);
  mk("fx_bass", 0.6, o => add(o, 0, tone(65, 0.55, { a: 0.01, d: 0.25, harm: [[1, 1], [2, 0.2]] })), 700, 0.7);
  mk("fx_flash", 0.4, o => { note(o, 0, mtof(86), 0.3, bell, 0.7); note(o, 0.05, mtof(91), 0.3, bell, 0.5); }, 4800, 0.45);
  // Ein Hauch Raum auf den grossen Jingles
  for (const k of ["hatchRare", "levelUp", "rebirth", "unlock", "upgradeBig", "moment"]) { const a = S[k], b = Float32Array.from(a); reverb(a, b, 0.18, 0.8, 0.7, 4500); }
  return S;
}

// ---------------------------------------------------------------- Lauf
for (const [name, spec] of Object.entries(TRACKS)) {
  const st = renderMusic(spec);
  writeWav(path.join(OUT, "music", name + ".wav"), st);
  console.log(`music/${name}.wav  ${(st[0].length / SR).toFixed(1)} s  ${spec.bpm} BPM`);
}
for (const [name, data] of Object.entries(sfx())) {
  writeWav(path.join(OUT, "sfx", name + ".wav"), [data]);
  console.log(`sfx/${name}.wav  ${(data.length / SR).toFixed(2)} s`);
}
