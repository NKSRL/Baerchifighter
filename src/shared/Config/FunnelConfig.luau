--!strict
-- FunnelConfig.luau
-- ReplicatedStorage/Config/FunnelConfig.luau
--
-- Einzige Zustaendigkeit:
--   - Namen und Grenzen der Messpunkte (Onboarding-Trichter, UI-Ereignisse)
--
-- Daten statt Code: Schritte, erlaubte UI-Ereignisse und Kontingente stehen
-- hier, damit man sie aendern kann, ohne FunnelService anzufassen.
--
-- Liegt in ReplicatedStorage, weil der Client die erlaubten Ereignis-Arten
-- und Panel-Namen kennen muss, um gar nicht erst Unsinn zu senden. Geprueft
-- wird trotzdem nur auf dem Server.

-- Reihenfolge = Schrittnummer im Trichter. Nie umsortieren, sobald Daten
-- im Dashboard liegen: Roblox ordnet nach der Nummer.
local STEPS: { string } = {
	"F01_Join",
	"F02_FirstMove",
	"F03_FirstEggOpened",
	"F04_BearEquipped",
	"F05_FirstFightStarted",
	"F06_FirstFightEnded",
	"F07_FirstHoneyEaten",
	"F08_EventButtonPressed",
	"F09_FirstEventCompleted",
	"F10_SecondSession",
}

local STEP_INDEX: { [string]: number } = {}
for index, name in STEPS do
	STEP_INDEX[name] = index
end

return {
	STEPS      = STEPS,
	STEP_INDEX = STEP_INDEX,

	-- Nur Konten, die juenger sind, landen im Trichter: er soll den ersten
	-- Eindruck messen, nicht Veteranen.
	NEW_PLAYER_MAX_AGE = 24 * 3600,

	-- F10 ist die Rueckkehr. Ein Kind, das am naechsten Nachmittag wiederkommt,
	-- ist oft schon aelter als 24 h — deshalb ein eigenes, laengeres Fenster
	-- (Annahme: Tag-1-Rueckkehr, Roblox misst D1 bis 48 h).
	SECOND_SESSION_MAX_AGE = 48 * 3600,
	-- Ab diesem Alter des Kontos beim Join gilt ein Join als zweite Sitzung
	-- (eine frische Anlage hat createdAt ≈ jetzt).
	SECOND_SESSION_MIN_AGE = 10 * 60,

	-- F02: so weit muss sich der Charakter vom ersten gemessenen Punkt
	-- entfernen, damit es als Bewegung zaehlt (Studs).
	FIRST_MOVE_DISTANCE = 6,

	-- UI-Ereignisse vom Client (RequestLogUiEvent)
	UI_EVENT_KINDS = {
		PanelOpened = true,
		PanelQuickClose = true,
		IdleStanding = true,
	} :: { [string]: boolean },

	-- Panel-Namen aus PanelManager. Alles andere lehnt der Server ab, damit
	-- ein manipulierter Client keine beliebigen Strings ins Dashboard schreibt.
	UI_PANEL_NAMES = {
		Hatch = true, Inventory = true, Baerchi = true, Fusion = true,
		Charms = true, Combat = true, Rebirth = true, Language = true,
		Quests = true, EggTree = true, Leaderboard = true, Profile = true,
		DailyBonus = true,
		Building_Beehive = true, Building_HoneyRefiner = true,
	} :: { [string]: boolean },

	-- Schliessen unter dieser Zeit = "aus Versehen geoeffnet / nicht verstanden"
	QUICK_CLOSE_SECONDS = 3,
	-- Stillstand bis zum Ereignis IdleStanding
	IDLE_SECONDS = 20,
	-- Hoechstens so viele UI-Ereignisse pro Sitzung und Spieler (Kontingent
	-- der Custom Events schonen)
	MAX_UI_EVENTS_PER_SESSION = 50,
}
