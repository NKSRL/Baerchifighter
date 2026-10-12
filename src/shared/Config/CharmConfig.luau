--!strict
-- CharmConfig.luau
-- ReplicatedStorage/Config/CharmConfig.luau
--
-- Alle Zahlen der Battle-Charms an einer Stelle:
--   - acht Slots und ab welcher Promotions-Stufe jeder freigeschaltet wird
--   - die Rarity-Odds eines Wurfs
--   - der Pool moeglicher Stat-Typen und ihre Wertebereiche je Rarity
--   - was ein Wurf kostet
--
-- ============================================================
-- EIN SLOT IST NICHT AN EINEN STAT-TYP GEBUNDEN
-- ============================================================
-- Wichtigste Regel, vom Projektinhaber ausdruecklich klargestellt: die acht
-- Slots haben KEINEN festen Stat-Typ. Jeder Wurf zieht zweimal unabhaengig —
-- erst eine Rarity (RARITY_ODDS), dann einen Stat-Typ (STAT_POOL) — und zwar
-- fuer jeden Slot gleich, egal welcher Slot-Index es ist.
--
-- Die "Promotion Tiers"-Tabelle aus der Vorlage ist deshalb hier NUR eine
-- Freischalt-Liste (SLOT_UNLOCK_PROMOTION): sie sagt, ab wann ein Slot
-- ueberhaupt benutzbar ist — nicht, was darin sitzt.
--
-- ============================================================
-- KEINE NEUE WAEHRUNG
-- ============================================================
-- Die Vorlage kennt eine eigene Ressource ("Charm Dust"). In Baerchi Fighter
-- gibt es die bewusst NICHT — der Projektinhaber will das Ressourcen-System
-- einfach halten. Ein Wurf kostet direkt GoldGummies, die bereits bestehende
-- zweite Waehrung (seit GOLD_CHARMS_ONLY nur noch aus den Tages-Quests).
--
-- ============================================================
-- WARUM NUR VIER STAT-TYPEN
-- ============================================================
-- Die Vorlage zeigt Boni wie "Crit DMG" oder "Movement Speed" — beides gibt es
-- in Baerchi Fighter gar nicht (keine Krits, die Figuren laufen mit
-- MapConfig.WALK_SPEED). Ein Charm, der auf nichts wirkt, waere ein stiller
-- Fehler, der erst beim Balancing auffaellt. Deshalb enthaelt der Pool
-- ausschliesslich Boni, die CombatCalculator.getEffectiveStats auch wirklich
-- anwendet. Neue Typen sind ein Eintrag in STAT_POOL plus eine Zeile dort —
-- mehr braucht es nicht.

local Types = require(script.Parent.Parent.Network.Types)
local Loc   = require(script.Parent.Parent.Localization.Loc)

--------------------------------------------------------------------------------
-- Slots
--------------------------------------------------------------------------------

local SLOT_COUNT = 8

-- Ab welcher PROMOTIONS-STUFE (0-10, nicht Sterne!) ein Slot benutzbar ist.
-- Die Zahlen kommen 1:1 aus der "Promotion Tiers"-Tabelle der Vorlage:
-- Slot I ist von Anfang an offen, II ab 2, III ab 4, IV ab 6, V und VI ab 8,
-- VII und VIII ab 10.
local SLOT_UNLOCK_PROMOTION: { number } = { 0, 2, 4, 6, 8, 8, 10, 10 }

-- Roemische Ziffern fuer die Slot-Beschriftung (I-VIII), wie in der Vorlage.
local SLOT_NUMERALS: { string } = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII" }

--------------------------------------------------------------------------------
-- Rarity eines Charms
--------------------------------------------------------------------------------

-- Eigene Rarity-Kette, absichtlich NICHT Types.Rarity: ein Charm hat sechs
-- Stufen mit anderen Namen ("Super Rare", "Ascended") als ein Baerchi. Sie in
-- einen Topf zu werfen waere die naechste Stelle, an der eine Baerchi-Aenderung
-- versehentlich die Charm-Odds verschiebt.
local RARITY_ORDER: { Types.CharmRarity } = {
	"Common", "Uncommon", "Rare", "SuperRare", "Legendary", "Ascended",
}

-- Wahrscheinlichkeit je Wurf, in Prozent. Zahlen 1:1 aus der Vorlage
-- (Bild 3: "Each slot rolls a rarity, then a stat").
-- Summe = 100.0 — die Pruefung dazu steht in rollRarity.
local RARITY_ODDS: { [Types.CharmRarity]: number } = {
	Common    = 49.8,
	Uncommon  = 26.9,
	Rare      = 17.9,
	SuperRare =  4.3,
	Legendary =  1.0,
	Ascended  =  0.1,
}

-- Kurzbuchstabe fuer das Slot-Icon (C / U / R / S / L / A), wie in der Vorlage.
local RARITY_LETTER: { [Types.CharmRarity]: string } = {
	Common    = "C",
	Uncommon  = "U",
	Rare      = "R",
	SuperRare = "S",
	Legendary = "L",
	Ascended  = "A",
}

local RARITY_LABEL: { [Types.CharmRarity]: string } = {
	Common    = "Common",
	Uncommon  = "Uncommon",
	Rare      = "Rare",
	SuperRare = "Super Rare",
	Legendary = "Legendary",
	Ascended  = "Ascended",
}

local RARITY_COLORS: { [Types.CharmRarity]: Color3 } = {
	Common    = Color3.fromRGB(176, 190, 204),
	Uncommon  = Color3.fromRGB( 76, 217, 100),
	Rare      = Color3.fromRGB( 46, 155, 255),
	SuperRare = Color3.fromRGB(168,  85, 247),
	Legendary = Color3.fromRGB(255, 176,  32),
	Ascended  = Color3.fromRGB(255,  59, 107),
}

-- Wie stark ein Charm dieser Rarity ist, als Faktor auf den Grundwert des
-- Stat-Typs (siehe STAT_POOL). Ein Ascended-Charm ist damit fuenfmal so stark
-- wie ein Common desselben Typs.
local RARITY_POWER: { [Types.CharmRarity]: number } = {
	Common    = 1.0,
	Uncommon  = 1.6,
	Rare      = 2.4,
	SuperRare = 3.4,
	Legendary = 4.4,
	Ascended  = 6.0,
}

--------------------------------------------------------------------------------
-- Stat-Typen
--------------------------------------------------------------------------------

-- `mode`:
--   "percent" — der Wert ist ein Faktor auf den Basiswert (0.014 = +1.4%)
--   "flat"    — der Wert wird direkt addiert
--
-- `base` ist der Wert eines COMMON-Charms dieses Typs; die Rarity
-- multipliziert ihn (RARITY_POWER), und rollValue streut zusaetzlich
-- +/- SPREAD, damit zwei Charms derselben Rarity nicht identisch sind.
export type CharmStatDef = {
	id          : string,
	displayName : string,
	target      : "hp" | "atk" | "spd" | "pwr",
	mode        : "percent" | "flat",
	base        : number,
}

-- Die vier Ziele sind genau die vier Basiswerte des Spiels. Eine
-- Schadensabwehr gibt es NICHT — es gibt keine Verteidigung mehr (siehe
-- BaerchiConfig): wer einen Tank will, wuerfelt auf HP-Boost.
local STAT_POOL: { CharmStatDef } = {
	{ id = "HpBoost",   displayName = "HP-Boost",         target = "hp",  mode = "percent", base = 0.014 },
	{ id = "AtkBoost",  displayName = "ATK-Boost",        target = "atk", mode = "percent", base = 0.012 },
	{ id = "SpdBoost",  displayName = "Angriffs-Tempo",   target = "spd", mode = "flat",    base = 0.020 },

	-- Flach, nicht prozentual: PWR ist selbst schon ein Multiplikator auf den
	-- Skill-Schaden. "+8% auf einen Multiplikator" waere eine Zahl, die
	-- niemand im Kopf nachrechnet — "+2.4 Prozentpunkte Ability-Schaden"
	-- dagegen schon.
	{ id = "PwrBoost",  displayName = "Ability-Staerke",  target = "pwr", mode = "flat",    base = 0.008 },
}

-- Streuung um den errechneten Wert (0.25 = +/- 25%).
local SPREAD = 0.25

--------------------------------------------------------------------------------
-- Kosten
--------------------------------------------------------------------------------

-- Ein Wurf wuerfelt ALLE freigeschalteten und nicht gesperrten Slots des
-- Baerchis auf einmal neu — genau wie in der Vorlage ("rerolls every slot you
-- have not locked"). Deshalb ist der Preis pro WURF, nicht pro Slot.
local ROLL_COST_GOLD_GUMMIES = 25

-- "Auto Roll" ist serverseitig einfach ein Wurf-Paket: der Client schickt eine
-- Anzahl, der Server wuerfelt so oft hintereinander, bis die Anzahl erreicht
-- ist ODER die GoldGummies nicht mehr reichen, und meldet das Ergebnis
-- gesammelt zurueck.
--
-- Bewusst so statt eines Dauer-Timers auf dem Client: ein Auto-Roll, der pro
-- Wurf ein Remote feuert, laeuft sofort in den RateLimiter (siehe
-- NetworkConfig) und wuerde entweder haengen oder halb durchlaufen. Ein Paket
-- ist eine Anfrage, eine Abrechnung, ein Ergebnis.
local AUTO_ROLL_COUNT = 20

--------------------------------------------------------------------------------
-- Hilfsfunktionen
--------------------------------------------------------------------------------

local function getUnlockPromotion(slot: number): number
	return SLOT_UNLOCK_PROMOTION[slot] or math.huge
end

local function isSlotUnlocked(slot: number, promotionLevel: number): boolean
	if slot < 1 or slot > SLOT_COUNT then
		return false
	end
	return (promotionLevel or 0) >= getUnlockPromotion(slot)
end

-- Wie viele Slots bei diesem Promotions-Stand offen sind.
local function countUnlockedSlots(promotionLevel: number): number
	local count = 0
	for slot = 1, SLOT_COUNT do
		if isSlotUnlocked(slot, promotionLevel) then
			count += 1
		end
	end
	return count
end

local function getStatDef(statId: string): CharmStatDef?
	for _, def in STAT_POOL do
		if def.id == statId then
			return def
		end
	end
	return nil
end

-- Wuerfelt eine Rarity anhand von RARITY_ODDS.
--
-- Geht die Kette bewusst von der SELTENSTEN zur haeufigsten durch und
-- vergleicht gegen die aufsummierte Wahrscheinlichkeit: so faellt ein
-- Rundungsrest (die Odds summieren sich auf exakt 100.0, aber math.random gibt
-- Werte bis knapp darunter) immer auf Common zurueck und nie auf einen
-- Ascended.
local function rollRarity(): Types.CharmRarity
	local roll        = math.random() * 100
	local accumulated = 0

	for i = #RARITY_ORDER, 1, -1 do
		local rarity = RARITY_ORDER[i]
		accumulated += RARITY_ODDS[rarity] or 0
		if roll < accumulated then
			return rarity
		end
	end

	return "Common"
end

local function rollStatDef(): CharmStatDef
	return STAT_POOL[math.random(1, #STAT_POOL)]
end

-- Der konkrete Bonus-Wert eines Charms: Grundwert des Typs, mal Rarity-Staerke,
-- plus/minus SPREAD.
local function rollValue(statDef: CharmStatDef, rarity: Types.CharmRarity): number
	local power  = RARITY_POWER[rarity] or 1
	local center = statDef.base * power
	local factor = 1 + (math.random() * 2 - 1) * SPREAD

	-- Auf vier Nachkommastellen runden: sonst stehen im Spielstand Zahlen mit
	-- fuenfzehn Stellen, die kein Mensch und keine Anzeige braucht.
	return math.floor(center * factor * 10000 + 0.5) / 10000
end

-- Wuerfelt einen kompletten Charm fuer einen Slot.
local function rollCharm(slot: number): Types.Charm
	local rarity  = rollRarity()
	local statDef = rollStatDef()

	return {
		slot   = slot,
		rarity = rarity,
		statId = statDef.id,
		value  = rollValue(statDef, rarity),
		locked = false,
	}
end

-- Lesbarer Effekt-Text ("+3.4% HP-Boost"). Server und Client benutzen
-- denselben, damit die Anzeige nicht zweimal formatiert wird. Text in der
-- aktiven Sprache (Client: Spielersprache); der Name des Werts kommt aus
-- `charm.<id>.name`, `displayName` ist nur der deutsche Rueckfall.
local function describe(charm: Types.Charm): string
	local statDef = getStatDef(charm.statId)
	if not statDef then
		return charm.statId
	end

	-- Als Prozent anzuzeigen sind zwei Faelle: echte Prozent-Charms (HP/ATK)
	-- und PWR. PWR ist zwar technisch ein FLACHER Zuschlag, aber der Wert
	-- selbst ist ein Anteil (0.05 = 5% mehr Ability-Schaden) — als "+0.048"
	-- koennte ihn niemand einordnen.
	local stat = Loc.name("charm." .. statDef.id .. ".name", statDef.displayName) -- ui-ok: Rueckfall hinter Loc
	if statDef.mode == "percent" or statDef.target == "pwr" then
		return Loc.t("charm.effect_pct", { value = Loc.formatDecimal(charm.value * 100, 1), stat = stat })
	end
	return Loc.t("charm.effect_flat", { value = Loc.formatDecimal(charm.value, 3), stat = stat })
end

return {
	SLOT_COUNT            = SLOT_COUNT,
	SLOT_UNLOCK_PROMOTION = SLOT_UNLOCK_PROMOTION,
	SLOT_NUMERALS         = SLOT_NUMERALS,

	RARITY_ORDER   = RARITY_ORDER,
	RARITY_ODDS    = RARITY_ODDS,
	RARITY_LETTER  = RARITY_LETTER,
	RARITY_LABEL   = RARITY_LABEL,
	RARITY_COLORS  = RARITY_COLORS,
	RARITY_POWER   = RARITY_POWER,

	STAT_POOL = STAT_POOL,
	SPREAD    = SPREAD,

	ROLL_COST_GOLD_GUMMIES = ROLL_COST_GOLD_GUMMIES,
	AUTO_ROLL_COUNT        = AUTO_ROLL_COUNT,

	getUnlockPromotion = getUnlockPromotion,
	isSlotUnlocked     = isSlotUnlocked,
	countUnlockedSlots = countUnlockedSlots,
	getStatDef         = getStatDef,
	rollRarity         = rollRarity,
	rollCharm          = rollCharm,
	describe           = describe,
}
