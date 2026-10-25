-- studio_recolor_w1.lua - Welt 1, Paket 4: Farben der vier neuen Pets (Genesis, Infinity, Shade, Ascendant) nach dem FBX-Import wieder setzen.
-- Der Studio-Import verwirft Materialfarben (alles kommt grau an). Dieses Skript in der Befehlsleiste (Edit-Modus)
-- ausfuehren, NACHDEM Pet_Genesis, Pet_Infinity und Pet_Shade nach ReplicatedStorage.Assets.BaerchiModels importiert
-- wurden. Wiederholbar. Quelle der Farben: tools/pets/build_w1_pets.py (PETS) - hier als Hex.
local folder = game:GetService("ReplicatedStorage").Assets.BaerchiModels

local function hex(h) return Color3.fromRGB(tonumber(h:sub(1, 2), 16), tonumber(h:sub(3, 4), 16), tonumber(h:sub(5, 6), 16)) end

-- Teil-Endung -> { Hex, Material, Transparenz }
local COLORS = {
	Genesis = {
		body = { "FFE7B0" }, ears = { "FFD98A" }, feet = { "FFD27A" }, toes = { "FFF9E8" }, muzzle = { "FFFBF0" },
		nose = { "B8862B" }, eyes = { "3A2A12" }, cute_tail = { "FFE7B0" },
		cute_innerear_1 = { "FFD9A0" }, ["cute_innerear_-1"] = { "FFD9A0" }, cute_blush_1 = { "FFC9A0" }, ["cute_blush_-1"] = { "FFC9A0" },
		cute_smile = { "8A5A2A" }, acc_shell = { "FAF6EC" }, acc_seed0 = { "FFD86B", "Neon" }, acc_seed1 = { "FFD86B", "Neon" },
		acc_seed2 = { "FFD86B", "Neon" }, acc_ring = { "FFD86B", "Neon" },
	},
	Infinity = {
		body = { "3F3FA6" }, ears = { "35358F" }, feet = { "2C2C78" }, toes = { "8F8FE8" }, muzzle = { "B7B7FF" },
		nose = { "1B1B4A" }, eyes = { "151538" }, cute_tail = { "5656C4" },
		cute_innerear_1 = { "8F8FE8" }, ["cute_innerear_-1"] = { "8F8FE8" }, cute_blush_1 = { "9A7DFF" }, ["cute_blush_-1"] = { "9A7DFF" },
		cute_smile = { "1B1B4A" }, acc_loop = { "B9B2FF", "Neon" }, acc_star0 = { "FFFFFF", "Neon" }, acc_star1 = { "FFFFFF", "Neon" },
	},
	Ascendant = {
		body = { "F4F7FF" }, ears = { "DDEBFF" }, feet = { "CFE0FF" }, toes = { "FFFFFF" }, muzzle = { "FFFFFF" },
		nose = { "D9A93A" }, eyes = { "1E3A5F" }, cute_tail = { "F4F7FF" },
		cute_innerear_1 = { "BFE9F5" }, ["cute_innerear_-1"] = { "BFE9F5" }, cute_blush_1 = { "FFD9C9" }, ["cute_blush_-1"] = { "FFD9C9" },
		cute_smile = { "3C6E9A" }, acc_halo = { "FFD86B", "Neon" }, acc_orb0 = { "9FE8FF", "Neon" }, acc_orb1 = { "9FE8FF", "Neon" }, acc_orb2 = { "9FE8FF", "Neon" },
	},
	Shade = {
		body = { "2B2536" }, ears = { "241F2E" }, feet = { "1E1A28" }, toes = { "5B3A8C" }, muzzle = { "3C3350" },
		nose = { "7A3FD0" }, eyes = { "C070FF", "Neon" }, cute_tail = { "2B2536" },
		cute_innerear_1 = { "5B3A8C" }, ["cute_innerear_-1"] = { "5B3A8C" }, cute_blush_1 = { "4A3366" }, ["cute_blush_-1"] = { "4A3366" },
		cute_smile = { "C9A8F0" }, acc_wisp0 = { "7A3FD0", "Neon", 0.25 }, acc_wisp1 = { "7A3FD0", "Neon", 0.25 }, acc_wisp2 = { "7A3FD0", "Neon", 0.25 },
	},
}

local report = {}
for pet, table_ in COLORS do
	local model = folder:FindFirstChild("Pet_" .. pet)
	if not model then table.insert(report, "FEHLT: Pet_" .. pet) continue end
	local n, missing = 0, {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local suffix = part.Name:sub(#("Pet_" .. pet .. "_") + 1)
			local spec = table_[suffix]
			if not spec and suffix:sub(1, 7) == "cute_hl" then spec = { "FFFFFF" } end
			if spec then
				part.Color = hex(spec[1])
				part.Material = if spec[2] == "Neon" then Enum.Material.Neon else Enum.Material.Plastic
				part.Transparency = spec[3] or 0
				n += 1
			else
				table.insert(missing, part.Name)
			end
		end
	end
	table.insert(report, string.format("Pet_%s: %d Teile gefaerbt%s", pet, n, if #missing > 0 then " | ohne Farbe: " .. table.concat(missing, ",") else ""))
end
print(table.concat(report, "\n"))
