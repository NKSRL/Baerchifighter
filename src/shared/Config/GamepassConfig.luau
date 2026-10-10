--!strict
-- GamepassConfig.luau
-- ReplicatedStorage/Config/GamepassConfig.luau
--
-- Einzige Zustaendigkeit:
--   - Die Gamepasses des Spiels (08.10., Paket C): Id, Texte, Icon.
--
-- id = 0 heisst "noch nicht angelegt": der Knopf zeigt "Bald", loest keinen
-- Kauf aus, und niemand besitzt den Pass (ausser per Debug "pass on").
-- Anlegen: Creator Dashboard -> Spiel -> Monetization -> Passes -> Pass
-- erstellen -> die Asset-ID hier eintragen. Der Preis steht nur im Dashboard.
--
-- Besitz steht NICHT im Spielstand: GamepassService fragt Roblox
-- (UserOwnsGamePassAsync) beim Join und nach einem Kauf und haelt das
-- Ergebnis im Speicher; der Client liest es am Attribut des Spielers.

local GamepassConfig = {}

export type PassDef = {
	id      : number,   -- Gamepass-Asset-ID, 0 = nicht angelegt
	nameKey : string,   -- Loc-Schluessel Name
	descKey : string,   -- Loc-Schluessel kurze Beschreibung
	icon    : string,   -- Name in UI/Icons
}

GamepassConfig.PASSES = {
	-- Gratis-Skip: der Einstieg ab der letzten Stage kostet immer 0 Gummies
	-- (CombatService fragt GamepassService; der Client zeigt nur an).
	SKIP_PASS = { id = 0, nameKey = "ui.pass.skip.name", descKey = "ui.pass.skip.desc", icon = "crown" },
} :: { [string]: PassDef }

-- Attribut am Player: "Pass_<KEY>" = true/false (Anzeige im Client)
GamepassConfig.ATTRIBUTE_PREFIX = "Pass_"

function GamepassConfig.get(key: string): PassDef?
	return GamepassConfig.PASSES[key]
end

function GamepassConfig.isReady(key: string): boolean
	local def = GamepassConfig.PASSES[key]
	return def ~= nil and def.id > 0
end

function GamepassConfig.attributeName(key: string): string
	return GamepassConfig.ATTRIBUTE_PREFIX .. key
end

return GamepassConfig
