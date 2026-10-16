// push_server.js — liefert geaenderte Skripte per localhost an Studio (nur Entwicklung).
// node tools/audio/push_server.js <port> <datei...>   (relativ zum Projekt, z.B. src/shared/Audio.luau)
// Studio holt sie mit HttpService:GetAsync("http://localhost:<port>/").
// Mitgeliefert: der Stand von HEAD und die Aenderungen als {old,new}-Paare, damit Studio
// sie auch auf Skripte anwenden kann, die dort schon weiter sind als der letzte Commit.
const http = require("http"), fs = require("fs"), path = require("path"), cp = require("child_process");
const root = path.join(__dirname, "..", "..");
const port = +process.argv[2], files = process.argv.slice(3);
const NL = String.fromCharCode(10);
const lf = s => s.split(String.fromCharCode(13) + NL).join(NL);
function target(rel) {
  let m;
  if ((m = rel.match(/^src\/shared\/(.+)\.luau$/))) return { svc: "ReplicatedStorage", parts: m[1].split("/") };
  if ((m = rel.match(/^src\/server\/(.+)\.luau$/))) return { svc: "ServerScriptService", parts: m[1].replace(/\.server$/, "").split("/") };
  if ((m = rel.match(/^src\/client\/(.+)\.luau$/))) return { svc: "StarterPlayerScripts", parts: m[1].replace(/\.client$/, "").split("/") };
  throw new Error(rel);
}
function head(f) { try { return lf(cp.execSync("git show HEAD:" + f, { cwd: root, maxBuffer: 1e8, stdio: ["ignore", "pipe", "ignore"] }).toString()); } catch (e) { return null; } }
function hunks(f) {
  let d; try { d = lf(cp.execSync("git diff -U3 --no-color HEAD -- " + f, { cwd: root, maxBuffer: 1e8 }).toString()); } catch (e) { return []; }
  const out = []; let cur = null;
  for (const line of d.split(NL)) {
    if (line.startsWith("@@")) { cur = { old: [], new: [] }; out.push(cur); continue; }
    if (!cur || line.startsWith("\\")) continue;
    if (line[0] === " ") { cur.old.push(line.slice(1)); cur.new.push(line.slice(1)); }
    else if (line[0] === "-") cur.old.push(line.slice(1));
    else if (line[0] === "+") cur.new.push(line.slice(1));
  }
  return out.map(h => ({ old: h.old.join(NL), new: h.new.join(NL) }));
}
const payload = JSON.stringify(files.map(f => ({
  ...target(f), file: f,
  class: /\.client\.luau$/.test(f) ? "LocalScript" : /\.server\.luau$/.test(f) ? "Script" : "ModuleScript",
  head: head(f), hunks: hunks(f), source: lf(fs.readFileSync(path.join(root, f), "utf8")),
})));
http.createServer((q, r) => { r.end(q.url === "/ping" ? "pong" : payload); }).listen(port, "127.0.0.1", () => console.log("bereit", port, files.length));
