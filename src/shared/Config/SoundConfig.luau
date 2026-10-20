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
	-- R6 (Ei-Schluepf-Animation): PLATZHALTER ohne Klang (leere ID = stumm). Eigene Klaenge
	-- hochladen und hier als "rbxassetid://<id>" eintragen.
	hatchAppear     = { id = "", volume = 0.4 },
	hatchWobble     = { id = "", volume = 0.4 },
	hatchCrack      = { id = "", volume = 0.5 },
	hatchBurst      = { id = "", volume = 0.6 },
	hatchBurstHigh  = { id = "", volume = 0.7 },
	hatchReveal     = { id = "", volume = 0.5 },
	hatchRevealHigh = { id = "", volume = 0.7 },
	-- 20.10. Final-Epilog (Prompt 5-7). Eigene Klaenge (tools/audio/synth_epilog.py -> assets/epilog/sound/*.ogg).
	-- Hier die hochgeladene Asset-Id eintragen ("rbxassetid://<id>"). Leer = im Studio die Vorschau-Datei
	-- (rbxasset://sounds/hbb/sfx_<name>.wav), im Spiel stumm. Abgespielt ueber Audio.SFX / AudioController.play.
	epilog_hit           = { id = "", volume = 0.8 },   -- letzter Treffer + Glasbruch
	epilog_flash         = { id = "", volume = 0.7 },   -- Aufwaerts-Sweep
	epilog_rise          = { id = "", volume = 0.6 },   -- Orchesterflaeche steigt
	epilog_run           = { id = "", volume = 0.5 },   -- ein Schritt auf Holz (Takt 0,28 s)
	epilog_reveal        = { id = "", volume = 0.7 },   -- 0,4 s Stille, dann Fanfare
	epilog_terminal_idle = { id = "", volume = 0.25 },  -- leises Summen (Schleife)
	epilog_ready         = { id = "", volume = 0.5 },   -- Piepton, Terminal bereit
	epilog_press         = { id = "", volume = 0.9 },   -- hartes Klacken
	epilog_countdown     = { id = "", volume = 0.7 },   -- je Zahl 3 / 2 / 1
	epilog_launch        = { id = "", volume = 0.9 },   -- Rumpeln -> Zischen
	epilog_unlock        = { id = "", volume = 0.8 },   -- Sieges-Jingle
	epilog_music         = { id = "", volume = 0.22 },  -- Musik 76,8 s (Schleife), Spur "epilog" in Audio.MUSIC
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
