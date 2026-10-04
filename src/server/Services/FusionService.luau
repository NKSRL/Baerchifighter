--!strict
-- FusionService.luau
-- ServerScriptService/Services/FusionService.luau
--
-- Einzige Zustaendigkeit:
--   - Fusions-Requests validieren und ausfuehren
--   - Zwei Baerchis verbrauchen, einen hoeherwertigen erzeugen
--
-- ============================================================
-- FUSIONS-REGEL (verbindlich, hier dokumentiert weil sie sich nicht
-- vollstaendig aus den Configs ableiten laesst)
-- ============================================================
-- Seit v3: kein FusionLab-Gebaeude mehr. Fusion ist ein reines GUI-Feature
-- (FusionPanel/BaerchiInventory) und von Anfang an voll freigeschaltet —
-- kein Unlock-Level, kein Mythic-Level, Skill-Transfer immer an.
--   1. Es werden genau ZWEI verschiedene Baerchis derselben Rarity verbraucht.
--   2. v14: Die Rarity steigt NICHT mehr. Fusion fasst nur die Stats zusammen
--      (Wunsch des Projektinhabers: "Fusionen sollen nicht einfach Rarities
--      hochfliegen lassen, die sollen nur die Stats mergen"). Das Ergebnis
--      ist ein Baerchi DERSELBEN Rarity mit der Art (configId) des
--      levelhoeheren Inputs (bei Gleichstand: A). Hoehere Rarities kommen
--      ausschliesslich aus dem Ei-Baum.
--   3. (entfallen seit v14: Legendary + Legendary -> fester Mythic)
--   4. v14: Jede Rarity ist fusionierbar, auch Mythic bis Omega.
--   5. Ergebnis bekommt fusionBonus = EconomyConfig.getFusionStatBonus()
--      (fester Wert) und isFusionResult = true.

-- ============================================================
-- NEU (v8): "DAS BESSERE GEWINNT — STAT FUER STAT"
-- ============================================================
-- Regel A — BASISWERTE.
--   Die vier Basiswerte (hp/atk/spd/pwr) werden nicht mehr von EINEM Input
--   uebernommen, sondern JEDER EINZELN als Maximum ueber beide Inputs UND den
--   ausgewuerfelten Ergebnis-configId. Ein Fusions-Ergebnis ist damit in
--   keinem Stat schlechter als das, was hineingegangen ist.
--
--   Technisch: Basiswerte haengen sonst allein am configId. Das Ergebnis
--   bekommt deshalb ein Baerchi.baseStatOverride, das
--   CombatCalculator.getEffectiveStats bevorzugt. Fuer jeden NICHT fusionierten
--   Baerchi bleibt das Feld nil und die Rechnung ist unveraendert.
--
--   Der Ergebnis-configId zaehlt bewusst mit in das Maximum: sonst koennte ein
--   Legendary-Ergebnis aus zwei schwachen Epics schlechtere Basiswerte haben
--   als jeder andere Baerchi seiner eigenen Rarity.
--
-- Regel B — STAT-LEVEL (Feature 1, Event-Teilnahme).
--   Genauso: pro Stat das Maximum der beiden Inputs. Auch hier NICHT "der
--   weitere Input gewinnt alles" — jeder Stat einzeln. Anschliessend auf die
--   Obergrenze der ERGEBNIS-Rarity geklemmt (die ist immer hoeher, der Clamp
--   ist also reine Vorsorge).
--
-- Regel C — DER SPIELER DARF EINE SACHE SPERREN.
--   Frueher entschied dieser Service allein, welcher Skill und welches Level
--   das Ergebnis bekommt. Jetzt kann der Spieler im Fusions-Menue GENAU EINE
--   von drei Eigenschaften sperren und dabei sagen, von WELCHEM Input sie
--   kommen soll:
--       "ability" → skillId
--       "level"   → Baerchi-Level
--       "eggs"    → statLevels.egg
--   Fuer alles NICHT Gesperrte gilt die Standard-Regel "das Bessere":
--       Level   → das hoehere der beiden (frueher: der Durchschnitt)
--       Ability → Skill des levelhoeheren Inputs (unveraendert)
--       Eier    → der hoehere der beiden Werte
--
--   Wichtig: Sperren ist eine bewusste AUSNAHME von "das Bessere gewinnt". Der
--   Spieler darf damit ausdruecklich auch das SCHLECHTERE Level oder die
--   schwaechere Ability erzwingen — z.B. weil er unbedingt den Skill von A
--   will, obwohl B weiter ist. Genau das ist der Sinn der Regel; hier wird
--   deshalb NICHT stillschweigend auf das Bessere korrigiert.
--
--   Nicht sperrbar sind die Basiswerte (Regel A) und die vier Stat-Level
--   (Regel B) — die mischen sich immer automatisch.
--
-- Regel D — PROMOTION UND CHARMS FANGEN BEI NULL AN.
--   Das Ergebnis ist technisch ein NEUER Baerchi (neue uid). Es erbt weder den
--   Promotions-Stand noch die Charms seiner Eltern. Bestaetigte Entscheidung:
--   sonst liessen sich gut gewuerfelte Charms ueber Fusionen vervielfaeltigen,
--   und Promotion waere kein eigener Fortschritt mehr, sondern ein Nebenprodukt
--   der Fusion.
--
-- Regel E — DIE HOEHERE MUTATION VERERBT SICH (seit v11; vorher binaer
-- "Inverted").
--   Das Ergebnis bekommt die hoehere der beiden Mutations-Stufen
--   (BaerchiConfig.pickHigherMutation, Vergleich ueber MUTATION_ORDER). Das
--   ist dieselbe Linie wie Regel A und B ("das Bessere gewinnt") und macht
--   einen mutierten Baerchi nicht wertlos, sobald man ihn weiterfusionieren
--   will — auch nicht gegen einen Partner mit einer ANDEREN, niedrigeren
--   Mutations-Stufe.
--
--   Es entsteht dadurch KEINE Vermehrung: eine Fusion verbraucht zwei Baerchis
--   und liefert einen. Aus zwei mutierten wird einer — die Zahl der mutierten
--   Baerchis im Spiel kann ueber Fusion also nur sinken.
--
--   ANNAHME, nicht vom Projektinhaber vorgegeben: falls eine Mutation
--   stattdessen ausschliesslich aus dem Ei kommen soll, ist das eine Zeile
--   weiter unten (mutation = nil statt pickHigherMutation).

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types           = require(ReplicatedStorage.Network.Types)
local Remotes         = require(ReplicatedStorage.Network.Remotes)
local Loc           = require(ReplicatedStorage.Localization.Loc)
local BaerchiConfig   = require(ReplicatedStorage.Config.BaerchiConfig)
local EconomyConfig   = require(ReplicatedStorage.Config.EconomyConfig)
local PromotionConfig = require(ReplicatedStorage.Config.PromotionConfig)
local BaerchiFactory  = require(ReplicatedStorage.Modules.BaerchiFactory)

local PlayerService = require(ServerScriptService.Services.PlayerService)
local ActivityLock   = require(ServerScriptService.Util.ActivityLock)
local IslandService = require(ServerScriptService.Services.IslandService)
local RateLimiter   = require(ServerScriptService.Util.RateLimiter)

local FusionService = {}

export type LockedProperty = "ability" | "level" | "eggs"
export type LockedFrom     = "A" | "B"

local function fail(player: Player, reason: Types.LocMsg?)
	Remotes.ActionFailed:FireClient(player, "RequestFuseBaerchis", reason or Loc.msg("err.unknown"))
end

-- v14: Die Art des Ergebnisses — die des levelhoeheren Inputs, bei
-- Gleichstand A. Die Rarity bleibt dieselbe (Regel 2).
local function pickResultConfigId(a: Types.Baerchi, b: Types.Baerchi): string
	if b.level > a.level then
		return b.configId
	end
	return a.configId
end

--------------------------------------------------------------------------------
-- Regel A: Basiswerte Stat fuer Stat mischen
--------------------------------------------------------------------------------

-- Der wirksame Basiswert eines Inputs: sein eigenes Override, wo gesetzt,
-- sonst der Wert seines configId. Damit vererbt sich ein bereits gemischter
-- Basiswert ueber mehrere Fusionen hinweg weiter, statt bei der naechsten
-- Fusion wieder auf den Config-Wert zurueckzufallen.
local function effectiveBase(baerchi: Types.Baerchi, key: string): number
	local override = baerchi.baseStatOverride
	if override and (override :: any)[key] ~= nil then
		return (override :: any)[key]
	end

	local def = BaerchiConfig.getById(baerchi.configId)
	if not def then
		return 0
	end
	return (def.baseStats :: any)[key] or 0
end

local function mergeBaseStats(a: Types.Baerchi, b: Types.Baerchi, resultConfigId: string)
	local resultDef = BaerchiConfig.getById(resultConfigId)
	local merged: { [string]: number } = {}

	for _, key in { "hp", "atk", "spd", "pwr" } do
		local own = if resultDef then ((resultDef.baseStats :: any)[key] or 0) else 0
		merged[key] = math.max(own, effectiveBase(a, key), effectiveBase(b, key))
	end

	return {
		hp  = merged.hp,
		atk = merged.atk,
		spd = merged.spd,
		pwr = merged.pwr,
	}
end

--------------------------------------------------------------------------------
-- Regel B/C: Stat-Level mischen, Sperr-Auswahl anwenden
--------------------------------------------------------------------------------

local function statLevelOf(baerchi: Types.Baerchi, key: string): number
	local levels = baerchi.statLevels
	if not levels then
		return 0
	end
	return ((levels :: any)[key] or 0)
end

local function mergeStatLevels(
	a: Types.Baerchi,
	b: Types.Baerchi,
	resultRarity: Types.Rarity,
	lockedProperty: LockedProperty?,
	lockedFrom: LockedFrom?
): Types.StatLevels

	local cap    = PromotionConfig.getStatCap(resultRarity)
	local merged = PromotionConfig.newStatLevels()

	for _, key in PromotionConfig.ALL_STATS do
		(merged :: any)[key] = math.min(cap, math.max(statLevelOf(a, key), statLevelOf(b, key)))
	end

	-- Regel C: nur "eggs" greift in die Stat-Level ein — und nur dann wird der
	-- automatische Maximum-Wert ueberschrieben, ausdruecklich auch nach unten.
	if lockedProperty == "eggs" and lockedFrom then
		local source = if lockedFrom == "A" then a else b
		merged.egg = math.min(cap, statLevelOf(source, "egg"))
	end

	return merged
end

--------------------------------------------------------------------------------
-- Fusion
--------------------------------------------------------------------------------

function FusionService.fuse(
	player: Player,
	uidA: string,
	uidB: string,
	lockedProperty: LockedProperty?,
	lockedFrom: LockedFrom?
)
	local data = PlayerService.getData(player)
	if not data then return end

	if uidA == uidB then
		fail(player, Loc.msg("err.fuse_self"))
		return
	end

	local a = data.island.baerchis[uidA]
	local b = data.island.baerchis[uidB]
	if not a or not b then
		fail(player, Loc.msg("err.baerchi_not_found"))
		return
	end

	if a.rarity ~= b.rarity then
		fail(player, Loc.msg("err.fuse_rarity_mismatch"))
		return
	end

	-- v12: den ausgeruesteten Baerchi nicht wegfusionieren, waehrend er
	-- unterwegs ist (PIT, Event, Honig-Teich) — die Figur wuerde mitten im
	-- Lauf verschwinden, und ein PIT-Lauf koennte nicht mehr sauber
	-- abgerechnet werden.
	local equipped = data.island.equippedUid
	if (equipped == uidA or equipped == uidB) and not ActivityLock.isFree(player) then
		fail(player, Loc.msg("err.fuse_equipped_away"))
		return
	end

	-- Eine Sperre ohne Quelle (oder umgekehrt) ist keine gueltige Auswahl —
	-- beides zusammen oder gar nichts. Sonst muesste jede Regel unten einen
	-- dritten Fall behandeln.
	if (lockedProperty ~= nil) ~= (lockedFrom ~= nil) then
		lockedProperty = nil
		lockedFrom     = nil
	end

	local resultConfigId = pickResultConfigId(a, b)

	local resultDef = BaerchiConfig.getById(resultConfigId)
	if not resultDef then
		fail(player, Loc.msg("err.fuse_result_failed"))
		return
	end

	-- Regel C — Level.
	-- Standard ist jetzt das HOEHERE der beiden (frueher der Durchschnitt),
	-- damit die Fusion derselben Linie folgt wie die Basiswerte. Sperrt der
	-- Spieler "level", zaehlt ausschliesslich seine Wahl — auch wenn sie
	-- schlechter ist.
	local resultLevel: number
	if lockedProperty == "level" and lockedFrom then
		resultLevel = if lockedFrom == "A" then a.level else b.level
	else
		resultLevel = math.max(a.level, b.level)
	end
	resultLevel = math.clamp(resultLevel, 1, BaerchiConfig.MAX_LEVEL)

	-- Regel C — Ability.
	local skillId: string
	if lockedProperty == "ability" and lockedFrom then
		skillId = if lockedFrom == "A" then a.skillId else b.skillId
	else
		skillId = if a.level >= b.level then a.skillId else b.skillId
	end

	-- Die Rarity des Ergebnisses ist die der Inputs (beide gleich). Sie kann
	-- von der Config-Rarity abweichen, wenn das UFO einen Input schon
	-- aufgewertet hat — dann bleibt die hoehere erhalten.
	local newBaerchi = BaerchiFactory.create(resultConfigId, {
		level            = resultLevel,
		skillId          = skillId,
		isFusionResult   = true,
		fusionBonus      = EconomyConfig.getFusionStatBonus(),
		statLevels       = mergeStatLevels(a, b, a.rarity, lockedProperty, lockedFrom),
		baseStatOverride = mergeBaseStats(a, b, resultConfigId),

		-- Regel E: die hoehere Stufe gewinnt.
		mutation         = BaerchiConfig.pickHigherMutation(a.mutation, b.mutation),
	})

	if not newBaerchi then
		fail(player, Loc.msg("err.fuse_result_failed"))
		return
	end
	newBaerchi.rarity = a.rarity

	-- War einer der beiden Inputs der ausgeruestete Baerchi, uebernimmt das
	-- Ergebnis automatisch seinen Platz — sonst staende der Plot nach der
	-- Fusion ploetzlich leer da, obwohl gerade ein staerkerer Baerchi
	-- entstanden ist.
	local wasEquipped = data.island.equippedUid == uidA or data.island.equippedUid == uidB

	-- Erst jetzt die Inputs verbrauchen — vorher haette ein Fehler
	-- zwei Baerchis geloescht ohne Ergebnis.
	data.island.baerchis[uidA] = nil
	data.island.baerchis[uidB] = nil
	data.island.baerchis[newBaerchi.uid] = newBaerchi
	data.stats.totalFusions += 1

	if wasEquipped then
		data.island.equippedUid = newBaerchi.uid
	else
		-- Sicherheitsnetz: theoretisch kann equippedUid nach dem Entfernen
		-- ins Leere zeigen (sollte durch die Pruefung oben nicht vorkommen,
		-- schadet als Netz aber nicht).
		IslandService.autoEquipIfNone(data)
	end

	local result: Types.FusionResult = {
		resultBaerchi = newBaerchi,
		consumedUids  = { uidA, uidB },
	}

	Remotes.FusionResultReceived:FireClient(player, result)
	PlayerService.markDirty(player)
	PlayerService.saveNow(player)

	print(
		"[FusionService]", player.Name,
		"|", a.configId, "+", b.configId,
		"→", newBaerchi.configId, "(", newBaerchi.rarity, ") Lv.", newBaerchi.level,
		"| Bonus:", newBaerchi.fusionBonus,
		"| gesperrt:", lockedProperty or "nichts", lockedFrom or ""
	)
end

function FusionService.init()
	RateLimiter.connect(Remotes.RequestFuseBaerchis, "RequestFuseBaerchis", function(
		player, uidA: any, uidB: any, lockedProperty: any, lockedFrom: any
	)
		if typeof(uidA) ~= "string" or typeof(uidB) ~= "string" then return end

		-- Client-Eingaben streng pruefen: alles, was nicht genau einer der
		-- erlaubten Werte ist, wird zu nil (= alles automatisch). Ein
		-- erfundener Wert darf hoechstens die Sperre verlieren, nie eine
		-- unbekannte Eigenschaft setzen.
		local property: LockedProperty? = nil
		if lockedProperty == "ability" or lockedProperty == "level" or lockedProperty == "eggs" then
			property = lockedProperty
		end

		local from: LockedFrom? = nil
		if lockedFrom == "A" or lockedFrom == "B" then
			from = lockedFrom
		end

		FusionService.fuse(player, uidA, uidB, property, from)
	end)

	print("[FusionService] Initialisiert")
end

return FusionService
