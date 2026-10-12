--!strict
-- WorldMoments.luau
-- ReplicatedStorage/Modules/WorldMoments.luau
--
-- Einzige Zustaendigkeit:
--   - Grosse Momente eines Spielers aus seinem Spielstand ERKENNEN und ihre
--     Anzeige DROSSELN (Paket G, "Welt aufwerten") — als reine Rechnung
--
-- Server (WorldMomentService): `snapshot` merkt sich das Noetigste, `diff`
-- vergleicht mit dem neuen Stand und liefert die Momente, `throttle`
-- entscheidet gross/klein je Spieler (hoechstens ein grosser pro 30 s).
-- Client (WorldMomentController): `Queue` zeigt hoechstens EINEN grossen
-- Moment gleichzeitig, weitere warten kurz (Zahlen in WorldFXConfig.MOMENTS).
-- Ohne Instanzen, testbar: tools/luau-tests/world_moments.test.lua.

local Config = script.Parent.Parent.Config
local WorldFXConfig = require(Config.WorldFXConfig)
local BaerchiConfig = require(Config.BaerchiConfig)
local TowerConfig   = require(Config.TowerConfig)

local WorldMoments = {}

export type Kind = "hatch" | "tower" | "record" | "rebirth" | "mutation"
export type Moment = { kind: Kind, value: string, number: number? }
export type Snapshot = {
	baerchis: { [string]: { rarity: string, mutation: string? } },
	highest: string,
	records: { [string]: number },
	rebirths: number,
}

local function rarityIndex(rarity: string): number
	for i, r in BaerchiConfig.RARITY_ORDER do
		if r == rarity then return i end
	end
	return 0
end
WorldMoments.rarityIndex = rarityIndex

-- Das Noetigste aus dem Spielstand (keine Referenzen auf die Daten selbst).
function WorldMoments.snapshot(data: any): Snapshot
	local baerchis = {}
	for uid, b in (data.island and data.island.baerchis) or {} do
		baerchis[uid] = { rarity = b.rarity, mutation = b.mutation }
	end
	local records = {}
	local towers = data.towers or {}
	for id, n in towers.records or {} do
		records[id] = n
	end
	return {
		baerchis = baerchis,
		highest = towers.highestTower or "I",
		records = records,
		rebirths = data.rebirthCount or 0,
	}
end

-- Was ist zwischen `before` und `after` Grosses passiert?
function WorldMoments.diff(before: Snapshot, after: Snapshot): { Moment }
	local cfg = WorldFXConfig.MOMENTS
	local out: { Moment } = {}

	-- Neuer Baerchi ab Mythic (Schluepfen; auch Fusion) — der seltenste zaehlt
	local best: string? = nil
	for uid, b in after.baerchis do
		if not before.baerchis[uid] and rarityIndex(b.rarity) >= rarityIndex(cfg.HATCH_MIN_RARITY) then
			if not best or rarityIndex(b.rarity) > rarityIndex(best) then best = b.rarity end
		end
	end
	if best then
		table.insert(out, { kind = "hatch", value = best })
	end

	-- Seltene Mutation: neu geschluepft mit Mutation oder Mutation geaendert
	for uid, b in after.baerchis do
		local m = b.mutation
		if m and cfg.RARE_MUTATIONS[m] then
			local old = before.baerchis[uid]
			if not old or old.mutation ~= m then
				table.insert(out, { kind = "mutation", value = m })
				break
			end
		end
	end

	-- Neuer Tower geschafft/freigeschaltet
	if TowerConfig.getIndex(after.highest) > TowerConfig.getIndex(before.highest) then
		table.insert(out, { kind = "tower", value = after.highest })
	end

	-- Neuer persoenlicher Rekord (in irgendeinem Tower)
	for id, n in after.records do
		if n > (before.records[id] or 0) and (before.records[id] or 0) > 0 then
			table.insert(out, { kind = "record", value = id, number = n })
			break
		end
	end

	if after.rebirths > before.rebirths then
		table.insert(out, { kind = "rebirth", value = tostring(after.rebirths), number = after.rebirths })
	end
	return out
end

-- Grosser oder kleiner Moment? `lastBig` = Zeit des letzten grossen Moments
-- dieses Spielers. Rueckgabe: big, neues lastBig.
function WorldMoments.throttle(lastBig: number?, now: number): (boolean, number?)
	if lastBig and now - lastBig < WorldFXConfig.MOMENTS.PLAYER_COOLDOWN then
		return false, lastBig
	end
	return true, now
end

--------------------------------------------------------------------------------
-- Warteschlange (Client): hoechstens ein grosser Moment gleichzeitig
--------------------------------------------------------------------------------

export type Entry = { id: number, kind: string, big: boolean, at: number }
export type Queue = { waiting: { Entry }, busyUntil: number }

function WorldMoments.newQueue(): Queue
	return { waiting = {}, busyUntil = -math.huge }
end

-- Kleine Momente laufen sofort (Rueckgabe true = jetzt zeigen). Grosse
-- reihen sich ein; ist die Schlange voll, wird der neue klein gezeigt.
function WorldMoments.push(q: Queue, e: Entry): boolean
	if not e.big then return true end
	if #q.waiting >= WorldFXConfig.MOMENTS.QUEUE_MAX then
		e.big = false
		return true
	end
	table.insert(q.waiting, e)
	return false
end

-- Naechster grosser Moment, falls die Buehne frei ist. Wer zu lange wartete,
-- kommt klein heraus (`big = false`), belegt die Buehne dann aber nicht.
function WorldMoments.pop(q: Queue, now: number): Entry?
	local cfg = WorldFXConfig.MOMENTS
	local first = q.waiting[1]
	if not first then return nil end
	if now - first.at > cfg.MAX_WAIT then
		table.remove(q.waiting, 1)
		first.big = false
		return first
	end
	if now < q.busyUntil then return nil end
	table.remove(q.waiting, 1)
	local duration = (cfg.DURATION :: any)[first.kind] or 2
	q.busyUntil = now + duration + cfg.QUEUE_GAP
	return first
end

return WorldMoments
