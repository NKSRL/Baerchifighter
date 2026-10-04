--!strict
-- PromotionConfig.luau
-- ReplicatedStorage/Config/PromotionConfig.luau
--
-- Alle Zahlen der ZWEITEN Fortschrittsachse an einer Stelle:
--   1. Promotion  — einen Baerchi mit Duplikaten befoerdern (10 Stufen)
--   2. Stat-Level — jeder einzelne Basiswert waechst durch Event-Teilnahme,
--                   begrenzt durch eine von der Rarity abhaengige Obergrenze
--
-- Kein Service rechnet diese Zahlen selbst aus (Konvention des Projekts:
-- Konfig-Werte nie hartkodiert in Services). PromotionService, CharmService,
-- EventParticipationService, CombatCalculator und das UI lesen alle hier.
--
-- ============================================================
-- WARUM ZWEI FORTSCHRITTSACHSEN
-- ============================================================
-- baerchi.level (Honig/XP, siehe HoneyService) bleibt der Weg, wie ein Baerchi
-- von Level 1 bis MAX_LEVEL waechst. Promotion und Stat-Level sind davon
-- vollkommen unabhaengig: sie kosten keine XP, sondern Duplikate (Promotion)
-- bzw. Event-Teilnahme (Stat-Level). Ein Baerchi kann also auf Level 50 stehen
-- und trotzdem Promotion 0 / Stat-Level 0 haben — und umgekehrt.
--
-- ============================================================
-- DIE FUENF STATS: HP / ATK / SPD / PWR / EGG
-- ============================================================
-- SPD ist die Angriffsgeschwindigkeit, PWR die Ability-Staerke (sie skaliert
-- den Schaden von Skills, Formel siehe SkillConfig, gerechnet in
-- CombatCalculator), EGG das Lege-Tempo. Eine Verteidigung gibt es NICHT — wer
-- einen Tank will, baut einen Baerchi mit viel HP. Genau diese fuenf sind auch
-- die Stats, die durch Event-Teilnahme wachsen.
--
-- ============================================================
-- EGG IST SEIT v10 EIN ECHTER STAT
-- ============================================================
-- Lange war EGG ein Balken ohne Wirkung — das Ei-Legen gab es noch nicht.
-- Jetzt gibt es das (EggLayService), und EGG steuert, wie schnell der
-- ausgeruestete Baerchi Eier legt.
--
-- Damit ist EGG der FUENFTE wachsende Stat: eine Event-Teilnahme kann ihn
-- genauso erhoehen wie HP, ATK, SPD oder PWR. Was eine Stufe konkret bringt,
-- steht NICHT hier, sondern bei EggConfig.LAY_STAT_LEVEL_GAIN — dort, wo auch
-- der Rest des Ei-Systems steht (siehe Kommentar dort).

local Types = require(script.Parent.Parent.Network.Types)

--------------------------------------------------------------------------------
-- 1. Promotion
--------------------------------------------------------------------------------

-- Zehn Stufen, dargestellt als FUENF Sterne: Stufe 1-5 fuellt die Sterne einer
-- nach dem anderen (leer → Silber), Stufe 6-10 faerbt dieselben fuenf Sterne
-- ein zweites Mal um (Silber → Gold). Bei Promotion 10 sind alle fuenf golden.
-- Die Umrechnung macht getStarState weiter unten — kein UI-Modul rechnet das
-- selbst nach.
local MAX_PROMOTION = 10
local STAR_COUNT    = 5

-- Was eine Promotion an Basiswerten bringt (zusaetzlich zu den frei
-- geschalteten Charm-Slots). Vom Projektinhaber bestaetigt: +2% HP und ATK je
-- Stufe, bei Promotion 10 also +20%. Bewusst nur HP/ATK — dieselbe Regel wie
-- beim Fusions-Bonus (siehe CombatCalculator): SPD und PWR bekommen ihren
-- Zuwachs ueber die Stat-Stufen (flach), nicht ueber prozentuale Boni, weil
-- PWR ohnehin schon den ATK-abhaengigen Skill-Schaden multipliziert.
local PROMOTION_STAT_BONUS_PER_LEVEL = 0.02

-- Wie viele Duplikate desselben configId eine einzelne Promotions-Stufe
-- kostet. Je SELTENER die Rarity, desto WENIGER Duplikate — spiegelbildlich
-- dazu, wie viel schwerer ein seltener Baerchi ueberhaupt zu bekommen ist.
--
-- Die beiden Zahlen sind die Endpunkte: `first` gilt fuer den Schritt 0 → 1,
-- `last` fuer den Schritt 9 → 10. Dazwischen wird linear interpoliert und
-- aufgerundet (siehe getDuplicateCost) — hoehere Stufen kosten also spuerbar
-- mehr als die erste, ohne dass hier zehn Zahlen pro Rarity stehen muessen.
--
-- VORLAEUFIGE ANNAHME: der Projektinhaber hat keine exakten Zahlen vorgegeben,
-- nur die Richtung ("je nach Raritaet oefter oder weniger oft").
local DUPLICATE_COST: { [Types.Rarity]: { first: number, last: number } } = {
	Common    = { first = 3, last = 8 },
	Uncommon  = { first = 2, last = 6 },
	Rare      = { first = 2, last = 5 },
	Epic      = { first = 1, last = 4 },
	Legendary = { first = 1, last = 3 },
	Mythic    = { first = 1, last = 2 },
	Divine    = { first = 1, last = 2 },
	Cosmic    = { first = 1, last = 2 },
	Secret    = { first = 1, last = 1 },
	Godly     = { first = 1, last = 1 },
	Eternal   = { first = 1, last = 1 },
	Omega     = { first = 1, last = 1 },
}

--------------------------------------------------------------------------------
-- 2. Stat-Level und ihre Rarity-Obergrenze
--------------------------------------------------------------------------------

-- Die Obergrenze JEDES EINZELNEN Stats, abhaengig von der Rarity.
-- Common bis Legendary sind Vorgabe des Projektinhabers; Mythic = 28 setzt das
-- +4-Muster fort und ist vom Projektinhaber bestaetigt.
local STAT_CAP: { [Types.Rarity]: number } = {
	Common    =  8,
	Uncommon  = 12,
	Rare      = 16,
	Epic      = 20,
	Legendary = 24,
	Mythic    = 28,
	Divine    = 32,
	Cosmic    = 36,
	Secret    = 40,
	Godly     = 46,
	Eternal   = 52,
	Omega     = 60,
}

-- Die Stats, die durch Event-Teilnahme wachsen koennen — die Zufallsauswahl
-- beim Event-Abschluss zieht genau aus dieser Liste. Seit v10 sind es fuenf:
-- `egg` ist dazugekommen, weil das Ei-Legen jetzt existiert.
local GROWABLE_STATS: { string } = { "hp", "atk", "spd", "pwr", "egg" }

-- Alle Stats, die es als Feld/Balken gibt. Seit v10 identisch mit
-- GROWABLE_STATS — die Trennung bleibt trotzdem bestehen, weil ein kuenftiger
-- Stat wieder nur anzeigbar sein koennte. Reihenfolge = Anzeigereihenfolge auf
-- der Baerchi-Karte.
local ALL_STATS: { string } = { "hp", "atk", "spd", "pwr", "egg" }

-- Was EINE Stufe eines Stat-Levels bringt.
--
-- HP und ATK prozentual (dieselbe Logik wie Level/Fusion/Promotion), SPD und
-- PWR flach — genau aus dem Grund, der in BaerchiConfig bei SPD_PER_LEVEL /
-- PWR_PER_LEVEL steht: PWR multipliziert bereits den Skill-Schaden, der
-- seinerseits am exponentiell wachsenden ATK haengt.
--
-- Zur Groessenordnung: ein Legendary am Stat-Cap (24) haette damit +96% HP,
-- +96% ATK, +0.48 SPD und +0.24 PWR — spuerbar, aber kein Ersatz fuer das
-- Level (das auf Stufe 50 das 106-fache bringt). Die +0.24 PWR sind dabei der
-- groesste einzelne PWR-Zuwachs im Spiel: mehr als jeder Baerchi von Haus aus
-- mitbringt. Stat-Stufen sind damit fuer einen Ability-Baerchi das Lohnendste,
-- was Event-Teilnahme bringen kann — genau so gewollt.
local STAT_LEVEL_GAIN = {
	hp  = 0.04,    -- +4% Basis-HP je Stufe
	atk = 0.04,    -- +4% Basis-ATK je Stufe
	spd = 0.02,    -- flach
	pwr = 0.01,    -- flach: +1 Prozentpunkt Ability-Schaden je Stufe
}

-- Anzeigenamen der Stat-Zeilen (UI liest nur hier, damit Server und Client
-- dieselbe Beschriftung benutzen).
local STAT_LABELS: { [string]: string } = {
	hp  = "HP",
	atk = "ATK",
	spd = "SPD",
	pwr = "PWR",
	egg = "EGG",
}

--------------------------------------------------------------------------------
-- Hilfsfunktionen
--------------------------------------------------------------------------------

local function getStatCap(rarity: Types.Rarity): number
	return STAT_CAP[rarity] or STAT_CAP.Common
end

-- Frische, vollstaendig genullte Stat-Level-Tabelle. Einzige erlaubte Quelle —
-- BaerchiFactory und die Migration (Util/PlayerMigration) rufen beide dies auf,
-- damit ein neues Feld nur an EINER Stelle nachgetragen werden muss.
local function newStatLevels(): Types.StatLevels
	return { hp = 0, atk = 0, spd = 0, pwr = 0, egg = 0 }
end

-- Wie viele Duplikate der Schritt auf `targetPromotion` kostet
-- (targetPromotion = 1 heisst der Schritt 0 → 1).
-- Gibt 0 zurueck, wenn die Stufe ausserhalb 1..MAX_PROMOTION liegt — der
-- Aufrufer behandelt das als "geht nicht mehr", nicht als "kostenlos".
local function getDuplicateCost(rarity: Types.Rarity, targetPromotion: number): number
	if targetPromotion < 1 or targetPromotion > MAX_PROMOTION then
		return 0
	end

	local curve = DUPLICATE_COST[rarity] or DUPLICATE_COST.Common

	-- t laeuft von 0 (erste Stufe) bis 1 (letzte Stufe).
	local t = (targetPromotion - 1) / (MAX_PROMOTION - 1)
	return math.max(1, math.ceil(curve.first + (curve.last - curve.first) * t))
end

-- Der Stat-Bonus, den `promotionLevel` Stufen auf HP/ATK geben (0.0 = keiner).
local function getPromotionBonus(promotionLevel: number): number
	return math.clamp(promotionLevel or 0, 0, MAX_PROMOTION) * PROMOTION_STAT_BONUS_PER_LEVEL
end

export type StarState = "empty" | "silver" | "gold"

-- Zustand der fuenf Sterne fuer einen Promotion-Stand. Die Umrechnung
-- 10 Stufen → 5 Sterne steht damit an genau einer Stelle.
local function getStarStates(promotionLevel: number): { StarState }
	local level  = math.clamp(promotionLevel or 0, 0, MAX_PROMOTION)
	local states: { StarState } = {}

	for star = 1, STAR_COUNT do
		if level >= STAR_COUNT + star then
			states[star] = "gold"     -- Stufe 6-10: zweite Faerbung
		elseif level >= star then
			states[star] = "silver"   -- Stufe 1-5: erste Fuellung
		else
			states[star] = "empty"
		end
	end

	return states
end

-- Farben der beiden Sterne-Stufen. Stehen hier statt im Client-Theme, weil sie
-- direkt zur Promotion-Mechanik gehoeren und (wie RARITY_COLORS in
-- BaerchiConfig) potenziell auch serverseitig gebraucht werden.
local STAR_COLORS = {
	empty  = Color3.fromRGB( 84,  80, 104),
	silver = Color3.fromRGB(214, 222, 236),
	gold   = Color3.fromRGB(255, 196,  60),
}

return {
	MAX_PROMOTION = MAX_PROMOTION,
	STAR_COUNT    = STAR_COUNT,
	STAR_COLORS   = STAR_COLORS,

	PROMOTION_STAT_BONUS_PER_LEVEL = PROMOTION_STAT_BONUS_PER_LEVEL,
	DUPLICATE_COST = DUPLICATE_COST,

	STAT_CAP        = STAT_CAP,
	GROWABLE_STATS  = GROWABLE_STATS,
	ALL_STATS       = ALL_STATS,
	STAT_LEVEL_GAIN = STAT_LEVEL_GAIN,
	STAT_LABELS     = STAT_LABELS,

	getStatCap        = getStatCap,
	newStatLevels     = newStatLevels,
	getDuplicateCost  = getDuplicateCost,
	getPromotionBonus = getPromotionBonus,
	getStarStates     = getStarStates,
}
