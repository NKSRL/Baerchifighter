-- studio_recolor_w2_anime.lua - Welt 2: Farben der vier Anime-Baerchis nach dem FBX-Import setzen (Studio verwirft Materialfarben).
-- Edit-Modus, NACH dem Import von Anime_Pirat/Ninja/Krieger/Jaeger. Wiederholbar. Quelle der Farben: tools/pets/build_w2_anime.py.
-- Die Modelle liegen danach in ReplicatedStorage.Assets.BaerchiModels. Keine Neon-Teile (flache Farben).
local folder = game:GetService("ReplicatedStorage").Assets.BaerchiModels
local function hex(h) return Color3.fromRGB(tonumber(h:sub(1, 2), 16), tonumber(h:sub(3, 4), 16), tonumber(h:sub(5, 6), 16)) end
local COLORS = {
	Pirat = {
		["body"] = "B9814B",
		["ears"] = "A9723F",
		["feet"] = "9A6535",
		["toes"] = "E8C9A0",
		["muzzle"] = "F3DDBA",
		["nose"] = "3A2410",
		["eyes"] = "2A1A0E",
		["cute_innerear_1"] = "E8A58A",
		["cute_innerear_-1"] = "E8A58A",
		["cute_blush_1"] = "F2A07A",
		["cute_blush_-1"] = "F2A07A",
		["cute_smile"] = "6A3A1E",
		["cute_tail"] = "B9814B",
		["acc_hat_crown"] = "F0CF6E",
		["acc_hat_brim"] = "E5BE55",
		["acc_hat_band"] = "1FA89A",
		["acc_shirt"] = "D83A34",
		["acc_shirt_back"] = "D83A34",
		["acc_gum_arm"] = "B9814B",
		["acc_gum_fist"] = "C28D55",
	},
	Ninja = {
		["body"] = "F2923A",
		["ears"] = "E5812B",
		["feet"] = "D8741F",
		["toes"] = "FFE0B8",
		["muzzle"] = "FFE9CC",
		["nose"] = "5A2A0A",
		["eyes"] = "1E2A55",
		["cute_innerear_1"] = "FFC48A",
		["cute_innerear_-1"] = "FFC48A",
		["cute_blush_1"] = "FF9A6A",
		["cute_blush_-1"] = "FF9A6A",
		["cute_smile"] = "7A3A12",
		["cute_tail"] = "F2923A",
		["acc_whiskerL"] = "3A2410",
		["acc_whiskerR"] = "3A2410",
		["acc_headband"] = "2F5FD0",
		["acc_plate"] = "C8D0DC",
		["acc_swirl"] = "27324A",
		["acc_scarf"] = "E8E2D0",
		["acc_scroll"] = "E9DDB8",
		["acc_scroll_cap"] = "C94A3A",
	},
	Krieger = {
		["body"] = "C89A66",
		["ears"] = "B98A58",
		["feet"] = "A97A4A",
		["toes"] = "F0D6B0",
		["muzzle"] = "F6E4C8",
		["nose"] = "3A2410",
		["eyes"] = "1A1A22",
		["cute_innerear_1"] = "E8B090",
		["cute_innerear_-1"] = "E8B090",
		["cute_blush_1"] = "F0A07A",
		["cute_blush_-1"] = "F0A07A",
		["cute_smile"] = "6A3A1E",
		["cute_tail"] = "C89A66",
		["acc_hair"] = "17171F",
		["acc_gi"] = "E4572A",
		["acc_sash"] = "2B50B0",
	},
	Jaeger = {
		["body"] = "8A6A58",
		["ears"] = "7A5A4A",
		["feet"] = "6A4A3C",
		["toes"] = "D8BFA8",
		["muzzle"] = "E8D2BC",
		["nose"] = "2A1A12",
		["eyes"] = "7A1F2A",
		["cute_innerear_1"] = "D8A090",
		["cute_innerear_-1"] = "D8A090",
		["cute_blush_1"] = "E8908A",
		["cute_blush_-1"] = "E8908A",
		["cute_smile"] = "4A2A1E",
		["cute_tail"] = "8A6A58",
		["acc_cape"] = "15201A",
		["acc_checks"] = "2E9A63",
		["acc_blade"] = "AEB8C6",
		["acc_guard"] = "D6A93C",
		["acc_hilt"] = "1B1B22",
		["acc_scar"] = "D0383A",
		["acc_belt"] = "1B1B22",
	},
}

local report = {}
for pet, t in COLORS do
	local model = folder:FindFirstChild("Anime_" .. pet) or game.Workspace:FindFirstChild("Anime_" .. pet)
	if not model then table.insert(report, "FEHLT: Anime_" .. pet) continue end
	if model.Parent ~= folder then model.Parent = folder end
	local n, missing = 0, {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local suffix = part.Name:sub(#("Anime_" .. pet .. "_") + 1)
			local h = t[suffix]
			if not h and suffix:sub(1, 7) == "cute_hl" then h = "FFFFFF" end
			if h then part.Color = hex(h) part.Material = Enum.Material.Plastic part.Transparency = 0 n += 1
			else table.insert(missing, part.Name) end
		end
	end
	table.insert(report, string.format("Anime_%s: %d gefaerbt%s", pet, n, #missing > 0 and (" | ohne Farbe: " .. table.concat(missing, ",")) or ""))
end
print(table.concat(report, "\n"))
return table.concat(report, "\n")
