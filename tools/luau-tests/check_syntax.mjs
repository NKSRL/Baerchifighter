// check_syntax.mjs — kompiliert jede .luau-Datei mit dem echten Luau-Parser (luau-web).
// Findet Syntaxfehler, bevor Studio sie beim Start meldet. Ersetzt NICHT die
// Typpruefung (--!strict) — die macht nur Studio / luau-analyze.
//
//   node check_syntax.mjs            # prueft ../../src
import { LuauState } from 'luau-web';
import fs from 'fs'; import path from 'path';
import { fileURLToPath } from 'url';
const here = path.dirname(fileURLToPath(import.meta.url));
const root = process.argv[2] ?? path.resolve(here, '..', '..', 'src');
const s = await LuauState.createAsync();
function walk(d){ return fs.readdirSync(d,{withFileTypes:true}).flatMap(e=> e.isDirectory()? walk(path.join(d,e.name)) : e.name.endsWith('.luau')? [path.join(d,e.name)]:[]); }
let bad=0, n=0;
for (const f of walk(root)) {
  n++;
  const r = s.loadstring(fs.readFileSync(f,'utf8'), '='+path.relative(root,f), false);
  if (typeof r === 'string') { bad++; console.log('FAIL', r); }
}
console.log(`${n} files, ${bad} compile errors`);
