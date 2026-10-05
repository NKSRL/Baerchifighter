// run_local.mjs - Node-Ersatz fuer run_local.py (gleiche Wirkung, ohne Python)
//
// Aufruf (im Repo-Hauptordner):
//   $env:LUAU="C:\Pfad\zu\luau.exe"
//   node tools/luau-tests/run_local.mjs tools/luau-tests/migration_hbb.test.lua
//
// Den Roblox-Attrappen-Teil (SHIM/TRAILER) liest das Skript zur Laufzeit aus
// run_local.py, damit es nur eine Quelle gibt.

import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(here, "..", "..");
const MAPS = { "src/shared": "ReplicatedStorage", "src/server": "ServerScriptService" };

const py = fs.readFileSync(path.join(here, "run_local.py"), "utf8");
const grab = (name) => {
	const m = py.match(new RegExp(name + " = r?'''([\\s\\S]*?)'''"));
	if (!m) throw new Error(name + " nicht in run_local.py gefunden");
	return m[1];
};
const SHIM = grab("SHIM");
const TRAILER = grab("TRAILER");

function longString(text) {
	let level = 1;
	while (text.includes("]" + "=".repeat(level) + "]")) level++;
	const eq = "=".repeat(level);
	return "[" + eq + "[\n" + text + "]" + eq + "]";
}

function* walk(dir) {
	for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
		const full = path.join(dir, entry.name);
		if (entry.isDirectory()) yield* walk(full);
		else yield full;
	}
}

const tests = process.argv.slice(2);
if (tests.length === 0) {
	console.error("Aufruf: node run_local.mjs <test.lua> [weitere.lua ...]");
	process.exit(2);
}

const parts = ["local __SOURCES = {}"];
for (const [rel, root] of Object.entries(MAPS)) {
	const base = path.join(ROOT, rel);
	for (const full of walk(base)) {
		if (!full.endsWith(".luau")) continue;
		let inner = path.relative(base, full).split(path.sep).join("/");
		for (const suffix of [".server.luau", ".client.luau", ".luau"]) {
			if (inner.endsWith(suffix)) {
				inner = inner.slice(0, -suffix.length);
				break;
			}
		}
		const key = root + "/" + inner;
		parts.push(`__SOURCES[${JSON.stringify(key)}] = ${longString(fs.readFileSync(full, "utf8"))}`);
	}
}

const bundle =
	parts.join("\n") + "\n" + SHIM + "\n" +
	tests.map((t) => fs.readFileSync(t, "utf8")).join("\n") + "\n" + TRAILER;

const tmp = path.join(os.tmpdir(), `bundle_${Date.now()}.luau`);
fs.writeFileSync(tmp, bundle, "utf8");
const luau = process.env.LUAU || "luau";
const result = spawnSync(luau, [tmp], { stdio: "inherit" });
fs.rmSync(tmp, { force: true });
if (result.error) {
	console.error("luau konnte nicht gestartet werden:", result.error.message);
	process.exit(1);
}
process.exit(result.status ?? 1);
