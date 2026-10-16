// analyze.js — prueft die erzeugten WAVs: Spitze, Lautheit, Anteil hoher Frequenzen, Schleifen-Naht.
const fs = require("fs"), path = require("path");
const dir = process.argv[2] || path.join(__dirname, "out");
function read(f) { const b = fs.readFileSync(f), nc = b.readUInt16LE(22), n = (b.length - 44) / 2 / nc, ch = []; for (let c = 0; c < nc; c++) { const a = new Float32Array(n); for (let i = 0; i < n; i++) a[i] = b.readInt16LE(44 + (i * nc + c) * 2) / 32768; ch.push(a); } return ch; }
for (const sub of ["music", "sfx"]) for (const f of fs.readdirSync(path.join(dir, sub))) {
  const ch = read(path.join(dir, sub, f)), x = ch[0]; let pk = 0, e = 0, eh = 0;
  for (let i = 2; i < x.length; i++) { pk = Math.max(pk, Math.abs(x[i])); e += x[i] * x[i]; const d = x[i] - 2 * x[i - 1] + x[i - 2]; eh += d * d; }
  const rms = Math.sqrt(e / x.length), db = v => (20 * Math.log10(v + 1e-9)).toFixed(1);
  // Naht: Sprung vom letzten zum ersten Sample im Vergleich zum ueblichen Sample-Abstand
  let step = 0; for (let i = 1; i < 2000; i++) step += Math.abs(x[i] - x[i - 1]); step /= 1999;
  const seam = Math.abs(x[0] - x[x.length - 1]);
  console.log(`${sub}/${f}`.padEnd(24), `peak ${db(pk)} dB  rms ${db(rms)} dB  hf ${(eh / (e * 16) * 100).toFixed(2)}%`, sub === "music" ? ` Naht ${seam.toFixed(5)} (ueblich ${step.toFixed(5)})` : "");
}
