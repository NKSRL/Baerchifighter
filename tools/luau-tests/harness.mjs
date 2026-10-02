// harness.mjs — Mini-Roblox-Modulsystem fuer luau-web.
//
// Baut aus den .luau-Dateien einen Baum (Ordner = Knoten, Datei = ModuleScript)
// und stellt require() bereit, damit Module so geladen werden wie in Studio:
//   require(script.Parent.Parent.Network.Types), require(ReplicatedStorage.X.Y)
//
// Es ist KEIN Roblox: Instance, UDim2, Enum usw. kommen aus mock_roblox.lua als
// durchlaessige Proxy-Objekte. Das reicht, um Spiellogik und UI-Aufbau
// auszufuehren und Texte zu pruefen — nicht, um Layout oder Physik zu testen.
// Mini-Roblox-Modulsystem fuer luau-web: baut einen Baum aus Dateien und erlaubt require().
import { LuauState, InternalLuauWasmModule } from 'luau-web';
InternalLuauWasmModule.options.set('LUA_NONSTRICT_READONLY', true);
import fs from 'fs'; import path from 'path';

export async function makeWorld(srcRoot) {
  const s = await LuauState.createAsync();
  const logs = [];
  s.env.set('__log', (...a) => { logs.push(a.join(' ')); }, true);
  s.env.set('__loadmod', (src, name) => {
    const f = s.loadstring(src, '=' + name, false);
    if (typeof f === 'string') throw new Error('COMPILE ' + name + ': ' + f);
    return f;
  }, true);
  const prelude = s.loadstring(`
    local Node = {}
    Node.__index = function(self, k)
      if k == "Parent" then return rawget(self, "_parent") end
      if k == "Name" then return rawget(self, "_name") end
      return rawget(self, "_children")[k]
    end
    __SCRIPTS = {}
    function Node.new(name, parent, source)
      local n = setmetatable({ _children = {}, _parent = parent, _name = name, _source = source }, Node)
      table.insert(__SCRIPTS, n)
      rawset(n, "_id", #__SCRIPTS)
      if parent then rawget(parent, "_children")[name] = n end
      return n
    end
    local cache = {}
    function warn(...) __log("WARN", ...) end
    function require(node)
      if cache[node] ~= nil then return cache[node] end
      local src = rawget(node, "_source")
      assert(src, "require auf Ordner")
      -- script als LOCAL vor den Chunk setzen: Luau cached globale Zugriffe pro
      -- Chunk, ein globales script waere im zweiten Modul veraltet.
      local f = __loadmod("local script = __SCRIPTS[" .. rawget(node, "_id") .. "] " .. src, rawget(node, "_name"))
      local result = f()
      cache[node] = result
      return result
    end
    function __node(name, parent, source) return Node.new(name, parent, source) end
    return true
  `, 'prelude', true);
  prelude();
  return { s, logs };
}


// Baut den Baum als Lua-Code (lange Klammern → keine Escape-Probleme) und fuehrt ihn aus.
export function buildTree(world, rootName, dir, overrides = {}) {
  let code = `local R = __node(${JSON.stringify(rootName)}, nil, nil)\n`;
  let n = 0;
  function rec(d, parentVar) {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const p = path.join(d, e.name);
      if (e.isDirectory()) {
        const v = 'n' + (n++);
        code += `local ${v} = __node(${JSON.stringify(e.name)}, ${parentVar}, nil)\n`;
        rec(p, v);
      } else if (e.name.endsWith('.luau')) {
        const name = e.name.replace(/(\.server|\.client)?\.luau$/, '');
        const rel = path.relative(dir, p).replace(/\\/g, '/').replace(/\.luau$/, '');
        const src = overrides[rel] ?? fs.readFileSync(p, 'utf8');
        code += `__node(${JSON.stringify(name)}, ${parentVar}, [======[${src}]======])\n`;
      }
    }
  }
  rec(dir, 'R');
  code += 'RS = R\n';
  return world.s.loadstring(code, 'tree', true)();
}
