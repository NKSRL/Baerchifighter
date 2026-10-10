-- einspielen.lua — Einspiel-Befehl fuer die Update-Datei (tools/make_update_rbxmx.py)
--
-- In Studio (NICHT im Play-Modus):
--   1. Datei → Roblox-Modell importieren → HBBUpdate_....rbxmx
--      (der Ordner "HBBUpdate" landet im Workspace)
--   2. Diesen ganzen Text in die Befehlsleiste (Ansicht → Befehlsleiste) kopieren, Enter
--
-- Was er tut: Fuer jedes Skript im Ordner HBBUpdate
--   * gibt es am Zielplatz schon ein Skript gleichen Namens → nur dessen Source
--     wird ersetzt (Instanz, Einstellungen, Verweise bleiben)
--   * sonst → das neue Skript wird an seinen Platz verschoben (fehlende Ordner
--     werden angelegt) und eingeschaltet
-- Danach wird der Ordner HBBUpdate geloescht. Ausgabe im Output-Fenster.
-- Es wird NICHTS sonst geloescht.

local ROOTS = {
	ReplicatedStorage    = game:GetService("ReplicatedStorage"),
	ServerScriptService  = game:GetService("ServerScriptService"),
	StarterPlayerScripts = game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts"),
}

local update = workspace:FindFirstChild("HBBUpdate")
if not update then
	warn("[Einspielen] Kein Ordner 'HBBUpdate' im Workspace — erst die .rbxmx importieren")
	return
end

local replaced, added = 0, 0

local function place(source: Instance, target: Instance)
	for _, child in source:GetChildren() do
		if child:IsA("LuaSourceContainer") then
			local existing = target:FindFirstChild(child.Name)
			if existing and existing.ClassName == child.ClassName then
				(existing :: any).Source = (child :: any).Source
				replaced += 1
			else
				if existing then
					warn("[Einspielen] " .. existing:GetFullName() .. " hat eine andere Klasse (" .. existing.ClassName .. ") — neues Skript daneben gelegt, bitte pruefen")
				end
				if child:IsA("Script") or child:IsA("LocalScript") then
					(child :: any).Disabled = false
				end
				child.Parent = target
				added += 1
				print("[Einspielen] neu:", child:GetFullName())
			end
		else
			-- Ordner: am Ziel suchen oder anlegen, dann hinein
			local folder = target:FindFirstChild(child.Name)
			if not folder then
				folder = Instance.new("Folder")
				folder.Name = child.Name
				folder.Parent = target
				print("[Einspielen] Ordner angelegt:", folder:GetFullName())
			end
			place(child, folder)
		end
	end
end

for name, service in ROOTS do
	local part = update:FindFirstChild(name)
	if part then
		place(part, service)
	end
end

update:Destroy()
print(string.format("[Einspielen] fertig: %d ersetzt, %d neu. Jetzt Play testen, dann Datei → Auf Roblox speichern.", replaced, added))
