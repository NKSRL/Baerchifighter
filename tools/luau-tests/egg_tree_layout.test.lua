-- egg_tree_layout.test.lua — Ei-Baum: Layout passt zu EggConfig
-- python tools/luau-tests/run_local.py tools/luau-tests/egg_tree_layout.test.lua
--
-- UI/EggTreeLayout ist reine Daten. Hier steht, was der Baum einhalten muss,
-- damit jeder Knoten einen Kelch, genau einen Ast und einen Weg zum Stamm
-- hat (die Lichtwelle laeuft diesen Weg).

local EggConfig = rbxRequire("ReplicatedStorage/Config/EggConfig")
local Layout    = rbxRequire("StarterPlayerScripts/UI/EggTreeLayout")

local failures = 0
local function check(name, ok)
	if ok then print("ok   " .. name) else failures += 1; print("FAIL " .. name) end
end

-- 1. Jedes Baum-Ei hat einen Knoten, Sonder-Eier keinen
for id, egg in EggConfig.data do
	if egg.special then
		check(id .. " (Sonder-Ei) ohne Knoten", Layout.NODES[id] == nil)
	else
		check(id .. " hat einen Knoten", Layout.NODES[id] ~= nil)
	end
end
for id in Layout.NODES do
	check(id .. " existiert in EggConfig", EggConfig.data[id] ~= nil)
end

-- 2. Genau ein Ast in jeden Knoten (ausser dem Basis-Ei am Stammfuss)
for id in Layout.NODES do
	local n = 0
	for _, e in Layout.EDGES do
		if e.to == id then n += 1 end
	end
	check(id .. ": " .. n .. " eingehende Aeste", n == (if id == "BasicEgg" then 0 else 1))
end

-- 3. Aeste: Eltern wie in EggConfig, Farbe des Ziel-Pfads
for _, e in Layout.EDGES do
	local def = EggConfig.data[e.to]
	if def and def.parent then
		check(e.to .. ": Ast kommt vom Elternei", e.from == def.parent)
	end
	if def then
		check(e.to .. ": Astfarbe = Pfad", e.path == def.path)
	end
end

-- 4. Jede Kette endet am Stamm, die Welle hat Punkte
for id in Layout.NODES do
	local chain = Layout.chain(id)
	local ok = id == "BasicEgg" or (#chain > 0 and chain[#chain].to == id)
	check(id .. ": Weg vom Stamm", ok)
	for _, e in chain do
		if #Layout.sample(e, 24) < 4 then ok = false end
	end
	check(id .. ": Aeste abtastbar", ok)
end

-- 5. Kelche ueberlappen nicht und bleiben im Bild
local cupW = Layout.EGG_HEIGHT * Layout.CUP_SCALE
local ids = {}
for id in Layout.NODES do table.insert(ids, id) end
table.sort(ids)
for i, a in ids do
	local pa = Layout.NODES[a]
	check(a .. " im Bild", pa.x - cupW / 2 >= 0 and pa.x + cupW / 2 <= Layout.SIZE.x
		and pa.y - Layout.EGG_HEIGHT >= 0 and pa.y + 60 <= Layout.SIZE.y)
	for j = i + 1, #ids do
		local pb = Layout.NODES[ids[j]]
		local d = math.sqrt((pa.x - pb.x) ^ 2 + (pa.y - pb.y) ^ 2)
		if d < cupW * 0.82 then
			check(a .. " / " .. ids[j] .. " zu nah (" .. math.floor(d) .. ")", false)
		end
	end
end

if failures > 0 then error(failures .. " Fehler", 0) end
print("egg_tree_layout: alle Tests gruen")
