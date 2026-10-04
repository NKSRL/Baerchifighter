--!strict
-- EggCalculator.luau
-- ReplicatedStorage/Modules/EggCalculator.luau
--
-- Reine Funktionen fuer das Ei-Legen.
-- Kein State, keine Services — nur Mathe. Genau wie CombatCalculator, nur fuer
-- die andere Haelfte des Spiels.
--
-- ============================================================
-- WARUM DAS EIN EIGENES MODUL IST UND NICHT IN CombatCalculator STEHT
-- ============================================================
-- CombatCalculator beantwortet "wie stark ist dieser Baerchi im Kampf". Das
-- Legeintervall hat damit nichts zu tun: es taucht in keiner Kampfformel auf,
-- und ein Baerchi, der gut legt, ist deswegen nicht besser im PIT.
--
-- Beide Module rechnen aber nach demselben Muster — Basiswert, dann Level,
-- dann Stat-Stufen, dann Mutation. Wer eines von beiden aendert, sollte ins
-- andere schauen.
--
-- ============================================================
-- DIE FORMEL
-- ============================================================
--     Tempo    = 1 + Level-Anteil + Stufen-Anteil
--     Tempo   *= (1 + Mutations-Bonus)         -- 0 ohne Mutation, sonst gestuft
--     Intervall = Grundintervall / Tempo       -- Sekunden pro Ei
--     Intervall = max(Intervall, Untergrenze)
--
-- Level und Stat-Stufen ADDIEREN sich im Tempo, statt sich zu multiplizieren.
-- Das ist bewusst anders als bei den Kampfwerten (dort multipliziert sich
-- alles): beim Kampf soll sich jede Fortschrittsachse mit jeder anderen
-- verstaerken, weil eine mitwachsende Gegenseite existiert. Beim Ei-Legen gibt
-- es die nicht — multiplizierte Achsen wuerden hier nur dafuer sorgen, dass ein
-- ausgebauter Baerchi die Obergrenze in Sekunden fuellt und die Zahlen danach
-- egal sind.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BaerchiConfig = require(ReplicatedStorage.Config.BaerchiConfig)
local EggConfig     = require(ReplicatedStorage.Config.EggConfig)
local Types         = require(ReplicatedStorage.Network.Types)

local EggCalculator = {}

--------------------------------------------------------------------------------
-- Legeintervall
--------------------------------------------------------------------------------

-- Sekunden, die dieser Baerchi fuer EIN Ei braucht.
--
-- `offline = true` rechnet mit der gebremsten Rate (EggConfig.OFFLINE_SLOWDOWN):
-- die Produktion laeuft weiter, waehrend der Spieler weg ist, aber langsamer.
--
-- Gibt nil zurueck, wenn dieser Baerchi ueberhaupt keine Eier legen kann
-- (unbekannter configId oder leere eggTable). Der Aufrufer laesst ihn dann
-- einfach nicht legen — das ist kein Fehler, sondern ein moeglicher Zustand.
function EggCalculator.getLayIntervalSeconds(baerchi: Types.Baerchi, offline: boolean?): number?
	local def = BaerchiConfig.getById(baerchi.configId)
	if not def then
		return nil
	end

	local base = def.layIntervalSeconds
	if not base or base <= 0 then
		return nil
	end

	if not def.eggTable or #def.eggTable == 0 then
		return nil
	end

	-- Level: jedes Level addiert LAY_LEVEL_GAIN des GRUNDTEMPOS.
	-- Warum linear und nicht exponentiell wie HP/ATK: siehe EggConfig,
	-- Kommentar bei LAY_LEVEL_GAIN.
	local level      = math.max(baerchi.level or 1, 1)
	local levelPart  = (level - 1) * EggConfig.LAY_LEVEL_GAIN

	-- EGG-Stat-Stufen (waechst durch Event-Teilnahme, gedeckelt durch die
	-- Rarity — siehe PromotionConfig.STAT_CAP).
	local statLevels = baerchi.statLevels
	local eggLevels  = if statLevels then (statLevels.egg or 0) else 0
	local statPart   = eggLevels * EggConfig.LAY_STAT_LEVEL_GAIN

	local speed = 1 + levelPart + statPart

	-- Mutation zaehlt EGG als vollwertigen Stat (voller Multiplikator-Anteil),
	-- anders als SPD und PWR mit ihrem gedrittelten Anteil. Siehe
	-- BaerchiConfig.getMutationBonus. Fuer baerchi.mutation == nil liefert das
	-- einen Nullbonus, hier also ohne Sonderfall immer korrekt.
	local mutationBonus = BaerchiConfig.getMutationBonus(baerchi.mutation)
	speed *= (1 + mutationBonus.egg)

	local interval = base / math.max(speed, 0.01)

	if offline then
		interval *= EggConfig.OFFLINE_SLOWDOWN
	end

	return math.max(interval, EggConfig.MIN_LAY_INTERVAL_SECONDS)
end

--------------------------------------------------------------------------------
-- Welches Ei
--------------------------------------------------------------------------------

-- Wuerfelt den Typ des naechsten Eis aus der persoenlichen Tabelle dieses
-- Baerchis. Gibt nil zurueck, wenn er keine legen kann.
--
-- Die Tabelle ist pro Baerchi verschieden und haengt ausdruecklich NICHT an
-- der Rarity: ein Common kann eine andere Mischung legen als ein Epic. Siehe
-- BaerchiConfig, Kommentar bei eggTable.
function EggCalculator.rollEggType(baerchi: Types.Baerchi): Types.EggType?
	local def = BaerchiConfig.getById(baerchi.configId)
	if not def or not def.eggTable then
		return nil
	end
	return EggConfig.rollEggType(def.eggTable)
end

-- Die Chancen dieses Baerchis als lesbare Liste, absteigend sortiert.
-- Fuer die Anzeige auf der Detailkarte — der Spieler soll sehen koennen, was
-- sein Baerchi ueberhaupt legen kann, ohne es sich zusammenzuzaehlen.
export type ChanceEntry = {
	eggType : Types.EggType,
	percent : number,
}

function EggCalculator.getChances(baerchi: Types.Baerchi): { ChanceEntry }
	local def = BaerchiConfig.getById(baerchi.configId)
	if not def or not def.eggTable then
		return {}
	end

	local total = 0
	for _, entry in def.eggTable do
		if entry.weight > 0 then
			total += entry.weight
		end
	end
	if total <= 0 then
		return {}
	end

	local result: { ChanceEntry } = {}
	for _, entry in def.eggTable do
		if entry.weight > 0 then
			table.insert(result, {
				eggType = entry.eggType,
				percent = entry.weight / total * 100,
			})
		end
	end

	table.sort(result, function(a, b)
		if a.percent ~= b.percent then
			return a.percent > b.percent
		end
		-- Bei Gleichstand nach Namen: die Iteration ueber die Config-Tabelle
		-- ist stabil, aber eine zweite Sortier-Bedingung kostet nichts und
		-- macht die Anzeige garantiert reproduzierbar.
		return a.eggType < b.eggType
	end)

	return result
end

return EggCalculator
