--!strict
-- GachaRoller.luau
-- ReplicatedStorage/Modules/GachaRoller.luau
--
-- Zustandslose Hilfsfunktion fuer gewichtetes Zufalls-Hatch.
-- Kein Service, kein Singleton — einfach aufrufen.

local GachaRoller = {}

export type WeightedEntry = {
	configId : string,
	weight   : number,  -- normalisiert (0.0 - 1.0) oder roh (wird intern normalisiert)
}

-- Zieht einen configId aus einer gewichteten Tabelle.
-- Akzeptiert sowohl normalisierte als auch rohe Gewichte.
function GachaRoller.roll(entries: { WeightedEntry }): string
	assert(#entries > 0, "[GachaRoller] Leere Gewichtstabelle")

	-- Summe berechnen (falls nicht normalisiert)
	local total = 0
	for _, entry in entries do
		total += entry.weight
	end

	-- Zufallszahl im Bereich [0, total)
	local roll = math.random() * total

	-- Durch Eintraege iterieren bis wir den Treffer finden
	local cumulative = 0
	for _, entry in entries do
		cumulative += entry.weight
		if roll < cumulative then
			return entry.configId
		end
	end

	-- Fallback (sollte nie passieren bei korrekten Gewichten)
	return entries[#entries].configId
end

return GachaRoller
