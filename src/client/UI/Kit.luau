--!strict
-- Kit.luau
-- StarterPlayerScripts/UI/Kit.luau
--
-- Einzige Zustaendigkeit:
--   - Die Bausteine des neuen UI-Looks (Theme.v2): Panel, Kopf, X, Karte,
--     Chip, Abzeichen, Balken, drei Knopf-Arten, Schloss, Konfetti, Klang.
--
-- (Wird in Paket D ausgebaut; hier zuerst nur der Klang fuer Paket G.)

local SoundService      = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoundConfig = require(ReplicatedStorage.Config.SoundConfig)

local Kit = {}

-- Ein Sound-Objekt je Name, einmal angelegt und wiederverwendet: kein
-- Instance.new pro Klick.
local _sounds: { [string]: Sound } = {}

-- Spielt einen UI-Klang aus SoundConfig. Stumm-sicher: unbekannt, leer oder
-- nicht ladbar → es passiert nichts.
function Kit.playSound(name: string)
	local def = SoundConfig.get(name)
	if not def then return end
	local sound = _sounds[name]
	if not sound then
		local created = Instance.new("Sound")
		created.Name    = "UiSound_" .. name
		created.SoundId = def.id
		created.Parent  = SoundService
		_sounds[name] = created
		sound = created
	end
	sound.Volume = def.volume * SoundConfig.MASTER_VOLUME
	pcall(function()
		SoundService:PlayLocalSound(sound)
	end)
end

return Kit
