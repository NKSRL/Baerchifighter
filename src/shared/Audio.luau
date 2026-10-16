--!strict
-- Audio.luau
-- ReplicatedStorage/Audio.luau
--
-- Einzige Zustaendigkeit:
--   - ALLE Klaenge des Spiels an einer Stelle: SoundIds, Lautstaerken,
--     Cooldowns, Tonhoehen-Streuung, Standardwerte der Regler.
--
-- Abgespielt wird nichts hier — das macht Controllers/AudioController (Client).
--
-- ============================================================
-- EINEN KLANG TAUSCHEN = EINE ZEILE
-- ============================================================
--   click = { id = "rbxassetid://123456789", ... },
-- `id` darf auch nur die Zahl sein ("123456789" oder 123456789).
-- Ist `id` leer, gilt:
--   - im Studio: die Vorschau-Datei `file` (rbxasset://sounds/hbb/<file>.wav,
--     kopiert mit tools/audio/install_studio_preview.ps1) — so laeuft alles
--     im Playtest, bevor irgendetwas hochgeladen ist.
--   - im echten Spiel: Stille (kein Fehler, kein Standard-Piepton).
--
-- ============================================================
-- LAUTSTAERKE-HIERARCHIE (Sound.Volume, danach mal Regler 0..1)
-- ============================================================
--   Musik            0.20            ← leiseste Ebene (Dauerbeschallung)
--   Routine-Effekte  0.15 – 0.35     ← Klick, Muenze, Treffer, Upgrade
--   Besondere Momente 0.60 – 0.85    ← seltenes Schluepfen, Level-Up, Rebirth
-- Routine-Effekte haben Cooldown + Tonhoehen-Streuung (pitch = +/- Anteil),
-- besondere Momente nicht (immer derselbe volle Jingle) und senken die Musik
-- kurz ab (duck).

local RunService = game:GetService("RunService")

local Audio = {}

export type MusicDef = { id: string, file: string, volume: number }
export type SfxDef = {
	id       : string,
	file     : string,
	volume   : number,
	cooldown : number,     -- Sekunden Mindestabstand zwischen zwei Abspielungen
	pitch    : number,     -- zufaellige Streuung der Geschwindigkeit, +/- (0.06 = 6 %)
	special  : boolean?,   -- grosser Moment: lauter, kein Limit, senkt die Musik ab
	duck     : number?,    -- Sekunden, die die Musik leiser bleibt (nur special)
}
export type Settings = { music: number, sfx: number, muted: boolean }

--------------------------------------------------------------------------------
-- Musik (drei nahtlose Schleifen, 96 – 112 s)
--------------------------------------------------------------------------------
Audio.MUSIC = {
	main  = { id = "rbxassetid://139380738783087", file = "music_main",  volume = 0.20 },   -- Farm / Lobby, 92 BPM
	menu  = { id = "rbxassetid://138217075818409", file = "music_menu",  volume = 0.20 },   -- Menues / Shops, 86 BPM
	fight = { id = "rbxassetid://70592307088714", file = "music_fight", volume = 0.20 },   -- Kampf / Tower, 100 BPM
} :: { [string]: MusicDef }

--------------------------------------------------------------------------------
-- Effekte
--------------------------------------------------------------------------------
Audio.SFX = {
	-- Routine: klein, kurz, mit Cooldown und Tonhoehen-Streuung
	click      = { id = "rbxassetid://137384001327951", file = "sfx_click",      volume = 0.22, cooldown = 0.08, pitch = 0.06 },
	select     = { id = "rbxassetid://101649499800847", file = "sfx_select",     volume = 0.24, cooldown = 0.08, pitch = 0.05 },
	coin       = { id = "rbxassetid://113713810270124", file = "sfx_coin",       volume = 0.26, cooldown = 0.12, pitch = 0.08 },
	hit        = { id = "rbxassetid://97986078433031", file = "sfx_hit",        volume = 0.24, cooldown = 0.18, pitch = 0.10 },
	hitHeavy   = { id = "rbxassetid://89253108989431", file = "sfx_hitHeavy",   volume = 0.30, cooldown = 0.25, pitch = 0.08 },
	eggCollect = { id = "rbxassetid://95244853971933", file = "sfx_eggCollect", volume = 0.30, cooldown = 0.20, pitch = 0.05 },
	upgrade    = { id = "rbxassetid://124370431438587", file = "sfx_upgrade",    volume = 0.32, cooldown = 0.15, pitch = 0.04 },
	hatchCrack = { id = "rbxassetid://133538706720999", file = "sfx_hatchCrack", volume = 0.32, cooldown = 0.30, pitch = 0.05 },
	hatchCommon = { id = "rbxassetid://83082207989635", file = "sfx_hatchCommon", volume = 0.34, cooldown = 0.50, pitch = 0.04 },

	-- Besonders: lauter, immer gleich, senkt die Musik ab
	upgradeBig = { id = "rbxassetid://108285135632491", file = "sfx_upgradeBig", volume = 0.60, cooldown = 0.60, pitch = 0, special = true, duck = 1.2 },
	unlock     = { id = "rbxassetid://126648326935180", file = "sfx_unlock",     volume = 0.65, cooldown = 0.80, pitch = 0, special = true, duck = 1.6 },
	moment     = { id = "rbxassetid://91877930957071", file = "sfx_moment",     volume = 0.60, cooldown = 0.60, pitch = 0, special = true, duck = 1.4 },
	hatchRare  = { id = "rbxassetid://120793748602490", file = "sfx_hatchRare",  volume = 0.80, cooldown = 1.00, pitch = 0, special = true, duck = 2.4 },
	levelUp    = { id = "rbxassetid://77263554753536", file = "sfx_levelUp",    volume = 0.75, cooldown = 1.00, pitch = 0, special = true, duck = 2.0 },
	rebirth    = { id = "rbxassetid://84575390758630", file = "sfx_rebirth",    volume = 0.85, cooldown = 2.00, pitch = 0, special = true, duck = 3.6 },

	-- Faehigkeits-Bibliothek (SkillFXConfig.SOUND_LIBRARY zeigt auf diese Namen).
	-- Dauerfeuer im Kampf: leise, mit Cooldown, die Zuschauer-Lautstaerke kommt
	-- von SkillFXConfig.SOUND.
	fx_whoosh  = { id = "rbxassetid://82100822363442", file = "sfx_fx_whoosh",  volume = 0.30, cooldown = 0.10, pitch = 0.06 },
	fx_hit     = { id = "rbxassetid://74798327442477", file = "sfx_fx_hit",     volume = 0.30, cooldown = 0.10, pitch = 0.08 },
	fx_ping    = { id = "rbxassetid://138611906473085", file = "sfx_fx_ping",    volume = 0.28, cooldown = 0.10, pitch = 0.06 },
	fx_boom    = { id = "rbxassetid://131675441248062", file = "sfx_fx_boom",    volume = 0.32, cooldown = 0.15, pitch = 0.05 },
	fx_glass   = { id = "rbxassetid://75699795592454", file = "sfx_fx_glass",   volume = 0.22, cooldown = 0.10, pitch = 0.05 },
	fx_splat   = { id = "rbxassetid://136509082871864", file = "sfx_fx_splat",   volume = 0.30, cooldown = 0.10, pitch = 0.08 },
	fx_snap    = { id = "rbxassetid://76259167941846", file = "sfx_fx_snap",    volume = 0.26, cooldown = 0.10, pitch = 0.06 },
	fx_rocket  = { id = "rbxassetid://134985240492241", file = "sfx_fx_rocket",  volume = 0.30, cooldown = 0.12, pitch = 0.05 },
	fx_rumble  = { id = "rbxassetid://122499446691342", file = "sfx_fx_rumble",  volume = 0.30, cooldown = 0.15, pitch = 0.05 },
	fx_slash   = { id = "rbxassetid://77574786989423", file = "sfx_fx_slash",   volume = 0.26, cooldown = 0.10, pitch = 0.06 },
	fx_lunge   = { id = "rbxassetid://114437637946586", file = "sfx_fx_lunge",   volume = 0.26, cooldown = 0.10, pitch = 0.06 },
	fx_thunder = { id = "rbxassetid://81537919466392", file = "sfx_fx_thunder", volume = 0.32, cooldown = 0.20, pitch = 0.04 },
	fx_ghost   = { id = "rbxassetid://104567641454179", file = "sfx_fx_ghost",   volume = 0.22, cooldown = 0.15, pitch = 0.04 },
	fx_bass    = { id = "rbxassetid://74489891016798", file = "sfx_fx_bass",    volume = 0.28, cooldown = 0.15, pitch = 0.04 },
	fx_flash   = { id = "rbxassetid://86716684162177", file = "sfx_fx_flash",   volume = 0.22, cooldown = 0.10, pitch = 0.04 },
} :: { [string]: SfxDef }

--------------------------------------------------------------------------------
-- Feineinstellung
--------------------------------------------------------------------------------
Audio.TUNING = {
	START_DELAY_SECONDS = 2,     -- Wartezeit nach dem Laden, bevor die Musik beginnt
	START_FADE_SECONDS  = 8,     -- Einblenden der allerersten Musik (leise, langsam)
	CROSSFADE_SECONDS   = 2,     -- Zonenwechsel
	ZONE_SETTLE_SECONDS = 0.6,   -- Wechsel erst nach so langer Ruhe (kein Flackern)
	DUCK_LEVEL          = 0.35,  -- Musik waehrend eines grossen Moments (Faktor)
	DUCK_ATTACK         = 0.25,
	DUCK_RELEASE        = 1.2,
	-- Routine-Effekte insgesamt: hoechstens MAX_ROUTINE in ROUTINE_WINDOW Sekunden.
	-- Alles darueber wird verworfen, damit viele Ereignisse nie zu Rauschen werden.
	MAX_ROUTINE         = 4,
	ROUTINE_WINDOW      = 0.35,
	-- Fahigkeiten / Weltklaenge anderer Spieler: gleiche Idee, eigenes Fenster
	MAX_WORLD           = 3,
	WORLD_WINDOW        = 0.30,
	-- Das Pitch-Fenster fuer Faehigkeiten (SkillFXConfig-Werte 0.45 – 1.6 klingen
	-- sonst verzerrt)
	WORLD_PITCH_MIN     = 0.85,
	WORLD_PITCH_MAX     = 1.2,
	-- Speichern: erst nach so langer Ruhe senden (Regler ziehen = viele Werte)
	SAVE_DELAY_SECONDS  = 0.8,
}

-- Zuordnung "Moment"-Art (UI/Moment) → Klang
Audio.MOMENT_SFX = {
	rebirth        = "rebirth",
	rarity         = "hatchRare",
	mutation       = "hatchRare",
	chest          = "hatchRare",
	milestone      = "levelUp",
	record         = "levelUp",
	unlock         = "unlock",
	tower_unlocked = "unlock",
} :: { [string]: string }
Audio.MOMENT_DEFAULT = "moment"

Audio.DEFAULTS = { music = 0.7, sfx = 0.8, muted = false } :: Settings

--------------------------------------------------------------------------------
-- Hilfen
--------------------------------------------------------------------------------

-- Vorschau-Ordner im Studio-Content (siehe tools/audio/install_studio_preview.ps1)
local PREVIEW_ROOT = "rbxasset://sounds/hbb/"
Audio.USE_STUDIO_PREVIEW = true

local function normalize(id: any): string
	if typeof(id) == "number" then return "rbxassetid://" .. tostring(math.floor(id)) end
	if typeof(id) ~= "string" or id == "" then return "" end
	if string.match(id, "^%d+$") then return "rbxassetid://" .. id end
	return id
end

-- Die abspielbare Id eines Eintrags; "" = stumm.
function Audio.resolve(def: { id: any, file: string }): string
	local id = normalize(def.id)
	if id ~= "" then return id end
	if Audio.USE_STUDIO_PREVIEW and RunService:IsStudio() then
		return PREVIEW_ROOT .. def.file .. ".wav"
	end
	return ""
end

-- SoundId eines Effekts nach Name ("" wenn unbekannt/stumm) — fuer Stellen, die
-- einen Sound selbst bauen (3D-Klaenge in der Welt).
function Audio.sfxId(name: string): string
	local def = Audio.SFX[name]
	return if def then Audio.resolve(def) else ""
end

local function clamp01(value: any, fallback: number): number
	if typeof(value) ~= "number" or value ~= value then return fallback end
	return math.floor(math.clamp(value, 0, 1) * 100 + 0.5) / 100
end

-- Macht aus beliebigen (auch gespeicherten oder vom Client geschickten) Werten
-- gueltige Einstellungen. Server und Client benutzen dieselbe Funktion.
function Audio.sanitize(raw: any): Settings
	local d = Audio.DEFAULTS
	if typeof(raw) ~= "table" then
		return { music = d.music, sfx = d.sfx, muted = d.muted }
	end
	return {
		music = clamp01(raw.music, d.music),
		sfx   = clamp01(raw.sfx, d.sfx),
		muted = raw.muted == true,
	}
end

-- Abspielen aus gemeinsamem Code (z.B. ReplicatedStorage/VFX), der den
-- AudioController nicht erreicht: der Controller meldet sich beim Start an.
-- Vor dem Start oder auf dem Server passiert nichts.
local _player: ((string, number?) -> Sound?)? = nil

function Audio.setPlayer(player: (string, number?) -> Sound?)
	_player = player
end

function Audio.play(name: string, volumeScale: number?): Sound?
	local player = _player
	if player then return player(name, volumeScale) end
	return nil
end

return Audio
