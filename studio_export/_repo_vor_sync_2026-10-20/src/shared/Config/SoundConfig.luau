--!strict
-- SoundConfig.luau
-- ReplicatedStorage/Config/SoundConfig.luau
--
-- Einzige Zustaendigkeit:
--   - Die kleinen UI-Klaenge (Klick, Erfolg, Ausbau, Freischalten) an EINER
--     Stelle: Name → Asset und Lautstaerke.
--
-- Platzhalter: es sind eingebaute Studio-Klaenge (rbxasset://sounds/...), die
-- es ohne Upload gibt. Wer eigene hochlaedt, traegt hier "rbxassetid://<id>"
-- ein. Ein leerer String schaltet einen Klang stumm — der Aufrufer
-- (UI/Kit.playSound) prueft das und spielt dann nichts, statt zu fehlen.

local SoundConfig = {}

export type SoundDef = { id: string, volume: number }

SoundConfig.SOUNDS = {
	click   = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.15 },
	select  = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.25 },
	success = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.4 },
	upgrade = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.45 },
	lookUp  = { id = "rbxasset://sounds/bass.wav",                volume = 0.5 },
	unlock  = { id = "rbxasset://sounds/bass.wav",                volume = 0.45 },
	-- 20.10. Final-Epilog Prompt 5: Platzhalter (leer = stumm), Prompt 7 fuellt sie.
	epilog_hit    = { id = "", volume = 0.8 },   -- letzter Treffer, Hit-Freeze
	epilog_flash  = { id = "", volume = 0.8 },   -- Flash
	epilog_rise   = { id = "", volume = 0.6 },   -- Aufstieg / Wind
	epilog_run    = { id = "", volume = 0.5 },   -- Lauf ueber die Bruecke
	epilog_reveal = { id = "", volume = 0.7 },   -- Insel-Reveal, Musik-Aufbau
	-- Prompt 6: Knopf-Finale (Platzhalter, Prompt 7 fuellt sie)
	epilog_press     = { id = "", volume = 0.9 },   -- Knopf gedrueckt (harter Klack)
	epilog_countdown = { id = "", volume = 0.7 },   -- je Zahl 3 / 2 / 1
	epilog_launch    = { id = "", volume = 0.9 },   -- Raketenstart
	epilog_unlock    = { id = "", volume = 0.8 },   -- Welt 2 freigeschaltet (Banner)
} :: { [string]: SoundDef }

-- Gesamt-Lautstaerke der UI-Klaenge (0 = alles stumm)
SoundConfig.MASTER_VOLUME = 1

function SoundConfig.get(name: string): SoundDef?
	local def = SoundConfig.SOUNDS[name]
	if not def or def.id == "" or SoundConfig.MASTER_VOLUME <= 0 then
		return nil
	end
	return def
end

return SoundConfig
