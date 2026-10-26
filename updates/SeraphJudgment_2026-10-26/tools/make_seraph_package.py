# Baut das Code-Paket fuer das Himmelsgericht:
#   <out>/Einfuegen_Befehl.lua         Studio-Befehlsleiste (Edit-Modus) ODER MCP execute_luau:
#                                      Backup, Anker 1x / neue Namen 0x auf dem LIVE-Quelltext,
#                                      loadstring, UpdateSourceAsync; bei MISS/DUP nichts gespeichert.
#   <out>/HBBUpdate_Himmelsgericht_2026-10-26.rbxmx + _Befehl.lua
#                                      Rueckfall: ganze Quelltexte (Studio-Stand 26.10. 00:11 + Himmelsgericht),
#                                      ersetzt nur Skripte, deren Live-Hash dem Ausgangsstand entspricht.
#   <out>/pieces/*                     die eingefuegten Stuecke als Dateien (Beleg fuers Repo)
# Aufruf: python -I make_seraph_package.py <studio_src> <studio_mod> <pkg> <out>
import sys, os, json, shutil, hashlib

SRC, MOD, PKG, OUT = sys.argv[1:5]
os.makedirs(os.path.join(OUT, "pieces"), exist_ok=True)

FILES = {
    "controller": "StarterPlayer/StarterPlayerScripts/Controllers/SkillFXController.luau",
    "fxconfig": "ReplicatedStorage/Config/SkillFXConfig.luau",
    "skillconfig": "ReplicatedStorage/Config/SkillConfig.luau",
    "baerchiconfig": "ReplicatedStorage/Config/BaerchiConfig.luau",
    "de": "ReplicatedStorage/Localization/Strings/de.luau",
    "en": "ReplicatedStorage/Localization/Strings/en.luau",
    "es": "ReplicatedStorage/Localization/Strings/es.luau",
    "fr": "ReplicatedStorage/Localization/Strings/fr.luau",
}
# Instanzpfad in Studio (Lua) je Schluessel
LUA_PATH = {
    "controller": 'game:GetService("StarterPlayer").StarterPlayerScripts.Controllers.SkillFXController',
    "fxconfig": 'game:GetService("ReplicatedStorage").Config.SkillFXConfig',
    "skillconfig": 'game:GetService("ReplicatedStorage").Config.SkillConfig',
    "baerchiconfig": 'game:GetService("ReplicatedStorage").Config.BaerchiConfig',
    "de": 'game:GetService("ReplicatedStorage").Localization.Strings.de',
    "en": 'game:GetService("ReplicatedStorage").Localization.Strings.en',
    "es": 'game:GetService("ReplicatedStorage").Localization.Strings.es',
    "fr": 'game:GetService("ReplicatedStorage").Localization.Strings.fr',
}
BACKUP_NAME = {
    "controller": "Controllers_SkillFXController", "fxconfig": "Config_SkillFXConfig", "skillconfig": "Config_SkillConfig",
    "baerchiconfig": "Config_BaerchiConfig", "de": "Strings_de", "en": "Strings_en", "es": "Strings_es", "fr": "Strings_fr",
}

def rd(p):
    with open(p, encoding="utf-8") as f:
        return f.read()

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
# EDITS und NEW_NAMES aus apply_seraph.py uebernehmen (gleiche Quelle der Wahrheit)
apply_src = rd(os.path.join(os.path.dirname(os.path.abspath(__file__)), "apply_seraph.py"))
ns = {"__name__": "pkgimport", "sys": sys, "os": os, "json": json}
# apply_seraph erwartet argv; wir fuettern es mit Dummy-Werten und ueberspringen den Schreibteil
code = apply_src.split("sources = {k: rd")[0]
ns_globals = {"os": os, "json": json}
_argv = sys.argv
sys.argv = ["apply_seraph.py", SRC, PKG, OUT]   # das exec-te Stueck liest sys.argv[1..3] = SRC, PKG, OUT
try:
    exec(code, ns_globals)
finally:
    sys.argv = _argv
EDITS = ns_globals["EDITS"]
NEW_NAMES = ns_globals["NEW_NAMES"]

def lua_str(s: str) -> str:
    out = ['"']
    for ch in s:
        o = ord(ch)
        if ch == "\\": out.append("\\\\")
        elif ch == '"': out.append('\\"')
        elif ch == "\n": out.append("\\n")
        elif ch == "\t": out.append("\\t")
        elif ch == "\r": out.append("\\r")
        elif o < 32 or o > 126: out.append("\\u{%04X}" % o)
        else: out.append(ch)
    out.append('"')
    return "".join(out)

def lua_long(s: str, width: int = 3000) -> str:
    # langer Text als Verkettung kurzer Literale (Zeilen <= ~3 KB)
    chunks = [s[i:i + width] for i in range(0, len(s), width)] or [""]
    return "table.concat({\n" + ",\n".join("\t" + lua_str(c) for c in chunks) + "\n})"

def lua_hash(data: bytes) -> int:
    h = 0
    for b in data:
        h = (h * 31 + b) % 2147483648
    return h

# ---- 1) Stuecke als Dateien ----
PIECE_FILES = {
    "blocks.luau": rd(os.path.join(PKG, "blocks_part1.luau")) + rd(os.path.join(PKG, "blocks_part2.luau")),
    "ctxfields.luau": rd(os.path.join(PKG, "patch_ctx.luau")),
    "cinematic.luau": rd(os.path.join(PKG, "patch_cinematic.luau")),
    "impactframe_palette.luau": rd(os.path.join(PKG, "patch_impactframe.luau")),
    "fxdoc.txt": rd(os.path.join(PKG, "fxdoc.txt")),
    "textures.luau": rd(os.path.join(PKG, "textures.luau")),
    "fxentry.luau": rd(os.path.join(PKG, "fxentry.luau")),
    "skillentry.luau": rd(os.path.join(PKG, "skillentry.luau")),
    "strings_de.txt": rd(os.path.join(PKG, "strings_de.txt")),
    "strings_en.txt": rd(os.path.join(PKG, "strings_en.txt")),
    "strings_es.txt": rd(os.path.join(PKG, "strings_es.txt")),
    "strings_fr.txt": rd(os.path.join(PKG, "strings_fr.txt")),
    "baerchiconfig_defaultskill.txt": 'SeraphBaerchi: defaultSkill = "SeraphJudgment", eggSource = {}, -- 26.10.2026 Himmelsgericht (vorher SeraphGrace)\n',
}
for name, text in PIECE_FILES.items():
    with open(os.path.join(OUT, "pieces", name), "w", encoding="utf-8", newline="\n") as f:
        f.write(text)

# ---- 2) Einfuegen_Befehl.lua ----
lines = []
lines.append("-- Himmelsgericht (SeraphJudgment) einfuegen - Studio-Befehlsleiste im EDIT-Modus (oder MCP execute_luau).")
lines.append("-- Prueft auf dem LIVE-Quelltext: jeder Anker genau 1x, jeder neue Name 0x; dann loadstring-Probe;")
lines.append("-- erst dann wird gespeichert (ScriptEditorService:UpdateSourceAsync). Vorher Backup nach")
lines.append("-- ServerStorage/Backup_vor_Himmelsgericht_2026-10-26. Strg+Z macht alles rueckgaengig (Waypoint).")
lines.append("local SES = game:GetService(\"ScriptEditorService\")")
lines.append("local CHS = game:GetService(\"ChangeHistoryService\")")
lines.append("local SS = game:GetService(\"ServerStorage\")")
lines.append("local SCRIPTS = {")
for k, p in LUA_PATH.items():
    lines.append("\t%s = %s," % (k, p))
lines.append("}")
lines.append("local BACKUP_NAME = {")
for k, n in BACKUP_NAME.items():
    lines.append("\t%s = %s," % (k, lua_str(n)))
lines.append("}")
lines.append("local NEW_NAMES = {")
for k, names in NEW_NAMES.items():
    lines.append("\t%s = { %s }," % (k, ", ".join(lua_str(n) for n in names)))
lines.append("}")
lines.append("local EDITS = {")
for key, name, anchor, mode, text in EDITS:
    lines.append("\t{ key = %s, name = %s, mode = %s," % (lua_str(key), lua_str(name), lua_str(mode)))
    lines.append("\t\tanchor = %s," % lua_str(anchor))
    lines.append("\t\ttext = %s }," % (lua_long(text) if len(text) > 3000 else lua_str(text)))
lines.append("}")
lines.append(r'''
local function countPlain(hay, needle)
	local n, pos = 0, 1
	while true do
		local a, b = string.find(hay, needle, pos, true)
		if not a then return n end
		n += 1
		pos = b + 1
	end
end

-- 1) Lesen + pruefen
local sources, report, ok = {}, {}, true
for key, inst in SCRIPTS do
	sources[key] = inst.Source
end
for key, names in NEW_NAMES do
	for _, n in names do
		local c = countPlain(sources[key], n)
		if c ~= 0 then ok = false; table.insert(report, ("DUP  %s: '%s' schon %dx"):format(key, n, c)) end
	end
end
for _, e in EDITS do
	local c = countPlain(sources[e.key], e.anchor)
	if c ~= 1 then ok = false; table.insert(report, ("MISS %s/%s: Anker %dx (erwartet 1)"):format(e.key, e.name, c)) end
end
if not ok then
	print(table.concat(report, "\n"))
	error("Himmelsgericht: Anker/Namen passen nicht - NICHTS geaendert", 0)
end

-- 2) Neue Quelltexte bauen
for _, e in EDITS do
	local src = sources[e.key]
	local a, b = string.find(src, e.anchor, 1, true)
	if e.mode == "before" then
		src = src:sub(1, a - 1) .. e.text .. src:sub(a)
	elseif e.mode == "after" then
		src = src:sub(1, b) .. e.text .. src:sub(b + 1)
	elseif e.mode == "after_line1" then
		local nl = string.find(e.anchor, "\n", 1, true)
		src = src:sub(1, a - 1 + nl) .. e.text .. src:sub(a + nl)
	elseif e.mode == "replace" then
		src = src:sub(1, a - 1) .. e.text .. src:sub(b + 1)
	end
	sources[e.key] = src
	table.insert(report, ("ok   %s/%s (%s, +%d Zeichen)"):format(e.key, e.name, e.mode, #e.text))
end

-- 3) Kompilier-Probe
for key, src in sources do
	local fn, err = loadstring(src)
	if not fn then
		print(table.concat(report, "\n"))
		error(("Himmelsgericht: %s kompiliert nicht: %s - NICHTS geaendert"):format(key, tostring(err)), 0)
	end
end

-- 4) Backup + Speichern
CHS:SetWaypoint("vor Himmelsgericht")
local backup = Instance.new("Folder")
backup.Name = "Backup_vor_Himmelsgericht_2026-10-26"
for key, inst in SCRIPTS do
	local c = inst:Clone()
	c.Name = BACKUP_NAME[key]
	c.Parent = backup
end
backup.Parent = SS
for key, inst in SCRIPTS do
	local new = sources[key]
	local okU = pcall(function()
		SES:UpdateSourceAsync(inst, function() return new end)
	end)
	if not okU then inst.Source = new end
end
CHS:SetWaypoint("Himmelsgericht eingespielt")
print(table.concat(report, "\n"))
print(("Himmelsgericht eingefuegt: %d Stuecke in %d Skripten, Backup in ServerStorage/%s"):format(#EDITS, 8, backup.Name))
''')
with open(os.path.join(OUT, "Einfuegen_Befehl.lua"), "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(lines))

# ---- 3) rbxmx-Rueckfall (ganze Quelltexte) + Befehl mit Hash-Schutz ----
def xml_escape(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;")

def cdata(s):
    return "<![CDATA[" + s.replace("]]>", "]]]]><![CDATA[>") + "]]>"

tree = {}
hashes = {}
for key, rel in FILES.items():
    parts = rel.split("/")
    node = tree
    for p in parts[:-1]:
        node = node.setdefault(p, {})
    name = parts[-1][:-5]
    node[name] = ("ModuleScript", rd(os.path.join(MOD, rel)))
    hashes[rel] = lua_hash(open(os.path.join(SRC, rel), "rb").read())

ref = [0]
def emit(name, node, depth):
    pad = "  " * depth
    ref[0] += 1
    if isinstance(node, tuple):
        cls, src = node
        return (f'{pad}<Item class="{cls}" referent="RBX{ref[0]}">\n{pad}  <Properties>\n{pad}    <string name="Name">{xml_escape(name)}</string>\n'
                f'{pad}    <ProtectedString name="Source">{cdata(src)}</ProtectedString>\n{pad}  </Properties>\n{pad}</Item>\n')
    out = f'{pad}<Item class="Folder" referent="RBX{ref[0]}">\n{pad}  <Properties>\n{pad}    <string name="Name">{xml_escape(name)}</string>\n{pad}  </Properties>\n'
    for child, sub in node.items():
        out += emit(child, sub, depth + 1)
    out += f"{pad}</Item>\n"
    return out

xml = ('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
       'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">\n')
xml += emit("HBBUpdate_Himmelsgericht", tree, 1)
xml += "</roblox>\n"
with open(os.path.join(OUT, "HBBUpdate_Himmelsgericht_2026-10-26.rbxmx"), "w", encoding="utf-8", newline="\n") as f:
    f.write(xml)

befehl = ['-- Rueckfall ohne Anker: ganze Quelltexte (Studio-Stand 26.10.2026 00:11 + Himmelsgericht).',
          '-- Vorher HBBUpdate_Himmelsgericht_2026-10-26.rbxmx in Studio importieren (landet als workspace.HBBUpdate_Himmelsgericht).',
          '-- Ersetzt ein Skript NUR, wenn sein Live-Quelltext noch dem Ausgangsstand entspricht (Hash);',
          '-- sonst wird es uebersprungen und gemeldet (dann Einfuegen_Befehl.lua nehmen). Strg+Z macht es rueckgaengig.',
          'local CHS = game:GetService("ChangeHistoryService")',
          'local SES = game:GetService("ScriptEditorService")',
          'local EXPECTED = {']
for rel, h in hashes.items():
    befehl.append('\t[%s] = %d,' % (lua_str(rel[:-5]), h))
befehl.append('}')
befehl.append(r'''
local function hashOf(s)
	local h = 0
	for i = 1, #s do h = (h * 31 + string.byte(s, i)) % 2147483648 end
	return h
end
local root = workspace:FindFirstChild("HBBUpdate_Himmelsgericht")
if not root then error("workspace.HBBUpdate_Himmelsgericht fehlt - zuerst die rbxmx importieren", 0) end
local MAP = { ReplicatedStorage = game:GetService("ReplicatedStorage"), StarterPlayer = game:GetService("StarterPlayer") }
CHS:SetWaypoint("vor HBBUpdate_Himmelsgericht")
local replaced, skipped = 0, 0
local function walk(node, target, path)
	for _, child in node:GetChildren() do
		local p = path .. "/" .. child.Name
		if child:IsA("LuaSourceContainer") then
			local existing = target and target:FindFirstChild(child.Name)
			local key = p:sub(2)
			if not existing then
				warn("fehlt in Studio, uebersprungen: " .. key)
				skipped += 1
			elseif EXPECTED[key] and hashOf(existing.Source) ~= EXPECTED[key] then
				warn("GEAENDERT seit 26.10. 00:11, uebersprungen (Einfuegen_Befehl.lua nehmen): " .. key)
				skipped += 1
			else
				local new = child.Source
				local okU = pcall(function() SES:UpdateSourceAsync(existing, function() return new end) end)
				if not okU then existing.Source = new end
				replaced += 1
			end
		else
			local sub = if path == "" then MAP[child.Name] else (target and target:FindFirstChild(child.Name))
			walk(child, sub, p)
		end
	end
end
walk(root, nil, "")
root:Destroy()
CHS:SetWaypoint("HBBUpdate_Himmelsgericht eingespielt")
print(("Himmelsgericht (rbxmx): %d Skripte ersetzt, %d uebersprungen, nichts geloescht"):format(replaced, skipped))
''')
with open(os.path.join(OUT, "HBBUpdate_Himmelsgericht_2026-10-26_Befehl.lua"), "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(befehl))

# ---- 4) Pruefsummen ----
sums = {}
for key, rel in FILES.items():
    sums[rel] = {"md5_vorher": hashlib.md5(open(os.path.join(SRC, rel), "rb").read()).hexdigest(),
                 "md5_nachher": hashlib.md5(open(os.path.join(MOD, rel), "rb").read()).hexdigest(),
                 "hash_vorher": hashes[rel],
                 "bytes_nachher": os.path.getsize(os.path.join(MOD, rel))}
with open(os.path.join(OUT, "_pruefsummen.json"), "w", encoding="utf-8") as f:
    json.dump(sums, f, indent=1)
print("Paket geschrieben:", OUT)
print("Einfuegen_Befehl.lua:", os.path.getsize(os.path.join(OUT, "Einfuegen_Befehl.lua")), "Bytes")
print("rbxmx:", os.path.getsize(os.path.join(OUT, "HBBUpdate_Himmelsgericht_2026-10-26.rbxmx")), "Bytes")
