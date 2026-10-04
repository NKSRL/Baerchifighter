// run.mjs — fuehrt einen Lua-Test gegen den echten Quellcode aus.
//
//   node run.mjs loc.test.lua       Tests fuer Localization/Loc
//   node run.mjs client.test.lua    Rauchtest der Client-UI mit Mock-Roblox
//   node run.mjs migration.test.lua alte Spielstaende durch die Migration
//
// Exit-Code 1, wenn ein Test mit "FAIL" meldet oder eine Ausnahme fliegt.
import { makeWorld, buildTree } from './harness.mjs';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const here = path.dirname(fileURLToPath(import.meta.url));
const SRC = path.resolve(here, '..', '..', 'src');
const testFile = process.argv[2];
if (!testFile) { console.log('Aufruf: node run.mjs <test.lua>'); process.exit(2); }

const w = await makeWorld(SRC);
await w.s.loadstring(fs.readFileSync(path.join(here, 'mock_roblox.lua'), 'utf8'), 'mock', true)();

// shared → ReplicatedStorage (Remotes durch Mock ersetzt), client → eigener Baum "CL"
await buildTree(w, 'ReplicatedStorage', path.join(SRC, 'shared'), {
  'Network/Remotes': fs.readFileSync(path.join(here, 'mock_remotes.lua'), 'utf8'),
});
await w.s.loadstring('SAVED_RS = RS', 'a', true)();
await buildTree(w, 'client', path.join(SRC, 'client'), {});
await w.s.loadstring('CL = RS; RS = SAVED_RS', 'b', true)();
// server → eigener Baum "SSS". Nur geladen, nicht gestartet: Tests requiren
// daraus reine Module (z. B. Util/PlayerMigration), keine Services.
await buildTree(w, 'server', path.join(SRC, 'server'), {});
await w.s.loadstring('SSS = RS; RS = SAVED_RS', 'c', true)();

let failed = false;
try {
  await w.s.loadstring(fs.readFileSync(path.resolve(testFile), 'utf8'), 'test', true)();
} catch (e) {
  console.log('AUSNAHME', e.message);
  failed = true;
}
const out = w.logs.join('\n');
console.log(out);
if (/^FAIL/m.test(out)) failed = true;
process.exit(failed ? 1 : 0);
