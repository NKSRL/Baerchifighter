-- Rueckfall ohne Anker: ganze Quelltexte (Studio-Stand 26.10.2026 00:11 + Himmelsgericht).
-- Vorher HBBUpdate_Himmelsgericht_2026-10-26.rbxmx in Studio importieren (landet als workspace.HBBUpdate_Himmelsgericht).
-- Ersetzt ein Skript NUR, wenn sein Live-Quelltext noch dem Ausgangsstand entspricht (Hash);
-- sonst wird es uebersprungen und gemeldet (dann Einfuegen_Befehl.lua nehmen). Strg+Z macht es rueckgaengig.
local CHS = game:GetService("ChangeHistoryService")
local SES = game:GetService("ScriptEditorService")
local EXPECTED = {
	["StarterPlayer/StarterPlayerScripts/Controllers/SkillFXController"] = 1818329916,
	["ReplicatedStorage/Config/SkillFXConfig"] = 328562669,
	["ReplicatedStorage/Config/SkillConfig"] = 216536204,
	["ReplicatedStorage/Config/BaerchiConfig"] = 1847942877,
	["ReplicatedStorage/Localization/Strings/de"] = 183910703,
	["ReplicatedStorage/Localization/Strings/en"] = 1378832170,
	["ReplicatedStorage/Localization/Strings/es"] = 1278967327,
	["ReplicatedStorage/Localization/Strings/fr"] = 148189105,
}

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
