"""run_local.py - Luau-Tests ohne Roblox und ohne Node (HBB-Hilfswerkzeug)

Baut aus src/shared und src/server ein Buendel (Quelltexte als Strings plus
eine kleine Roblox-Attrappe: game:GetService, script.Parent, require auf
Instanz-Pfade, Color3/Vector3/Enum-Stubs) und fuehrt den Test mit dem
`luau`-CLI aus.

Aufruf:  python tools/luau-tests/run_local.py tools/luau-tests/combat_rating.test.lua
         python tools/luau-tests/run_local.py <vorspann.lua> tools/sim/progression_pacing.lua
         (mehrere Dateien laufen hintereinander im selben Buendel, z.B. ein
         Wert-Vorschlag vor einer Simulation)
Umgebung: LUAU=/pfad/zu/luau (Standard: "luau" im PATH)

Im Test steht `rbxRequire("ReplicatedStorage/Modules/CombatRating")` statt
eines normalen require. Die Simulationen unter tools/sim (geschrieben fuer
`node run.mjs` auf dem Heim-PC) laufen ebenfalls: `RS`/`SSS` sind die
Instanz-Pfade, und `require(RS.Config.X)` geht ueber rbxRequire.
"""
import os, sys, subprocess, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MAPS = {"src/shared": "ReplicatedStorage", "src/server": "ServerScriptService"}

def long_string(text):
    level = 1
    while ("]" + "=" * level + "]") in text:
        level += 1
    eq = "=" * level
    return "[" + eq + "[\n" + text + "]" + eq + "]"

SHIM = r'''
local SOURCES = __SOURCES
local cache = {}
local proxies = {}

local function stub(name)
	return setmetatable({ __stub = name }, {
		__index = function(t, k) return stub(name .. "." .. tostring(k)) end,
		__call = function() return stub(name .. "()") end,
	})
end

Color3 = { fromRGB = function(r, g, b) return { R = r / 255, G = g / 255, B = b / 255 } end,
	new = function(r, g, b) return { R = r, G = g, B = b } end }
Vector3 = { new = function(x, y, z) return { X = x or 0, Y = y or 0, Z = z or 0 } end }
Vector3.zero = Vector3.new(0, 0, 0)
Vector3.one = Vector3.new(1, 1, 1)
Vector2 = { new = function(x, y) return { X = x or 0, Y = y or 0 } end }
UDim2 = { new = function() return {} end, fromScale = function() return {} end, fromOffset = function() return {} end }
ColorSequence = { new = function() return {} end }
NumberSequence = { new = function() return {} end }
NumberRange = { new = function() return {} end }
CFrame = { new = function() return {} end, Angles = function() return {} end }
Enum = stub("Enum")
workspace = stub("workspace")

local SERVICES = {
	RunService = { IsStudio = function() return true end, IsServer = function() return true end,
		IsClient = function() return false end },
	HttpService = { JSONEncode = function() return "" end, GenerateGUID = function() return "guid" end },
}

local function proxy(path)
	if proxies[path] then return proxies[path] end
	local p = setmetatable({ __path = path }, {
		__index = function(t, k)
			if k == "Parent" then
				local parent = string.match(path, "^(.*)/[^/]+$")
				return if parent then proxy(parent) else nil
			elseif k == "Name" then
				return string.match(path, "([^/]+)$")
			elseif k == "WaitForChild" or k == "FindFirstChild" then
				return function(self, name) return proxy(path .. "/" .. name) end
			end
			return proxy(path .. "/" .. k)
		end,
	})
	proxies[path] = p
	return p
end

game = { GetService = function(_, name) return SERVICES[name] or proxy(name) end }

function rbxRequire(target)
	local path = if type(target) == "string" then target else rawget(target, "__path")
	if cache[path] ~= nil then return cache[path] end
	local source = SOURCES[path]
	if not source then error("Modul nicht gefunden: " .. tostring(path)) end
	local chunk, err = loadstring(source, "=" .. path)
	if not chunk then error(err) end
	local env = setmetatable({ script = proxy(path), require = rbxRequire, game = game,
		Color3 = Color3, Vector3 = Vector3, Vector2 = Vector2, UDim2 = UDim2, ColorSequence = ColorSequence,
		NumberSequence = NumberSequence, NumberRange = NumberRange, CFrame = CFrame, Enum = Enum,
		workspace = workspace }, { __index = _G })
	setfenv(chunk, env)
	local result = chunk()
	cache[path] = result
	return result
end

-- Wie run.mjs: __log, REAL_CLOCK, Kurzpfade fuer tools/sim, require nimmt auch
-- Instanz-Pfade. Eine Zeile "FAIL ..." der Sims macht den Exit-Code 1 (TRAILER).
__failed = false
__log = function(first, ...)
	if first == "FAIL" then __failed = true end
	print(first, ...)
end
REAL_CLOCK = os.clock
RS  = proxy("ReplicatedStorage")
SSS = proxy("ServerScriptService")
local __builtinRequire = require
require = function(target)
	if type(target) == "table" and rawget(target, "__path") then return rbxRequire(target) end
	return __builtinRequire(target)
end
'''

TRAILER = '''
if __failed then error("mindestens ein FAIL (siehe oben)", 0) end
'''

def main():
    tests = sys.argv[1:]
    parts = ["local __SOURCES = {}"]
    for rel, root in MAPS.items():
        base = os.path.join(ROOT, rel)
        for dirpath, _, files in os.walk(base):
            for name in files:
                if not name.endswith(".luau"):
                    continue
                full = os.path.join(dirpath, name)
                inner = os.path.relpath(full, base).replace(os.sep, "/")
                for suffix in (".server.luau", ".client.luau", ".luau"):
                    if inner.endswith(suffix):
                        inner = inner[: -len(suffix)]
                        break
                key = root + "/" + inner
                parts.append("__SOURCES[%s] = %s" % (repr(key).replace("'", '"'), long_string(open(full, encoding="utf-8").read())))
    bundle = "\n".join(parts) + "\n" + SHIM + "\n" + "\n".join(open(t, encoding="utf-8").read() for t in tests) + "\n" + TRAILER
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as handle:
        handle.write(bundle)
        path = handle.name
    luau = os.environ.get("LUAU", "luau")
    sys.exit(subprocess.call([luau, path]))

if __name__ == "__main__":
    main()
