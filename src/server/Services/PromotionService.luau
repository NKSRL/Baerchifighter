--!strict
-- PromotionService.luau
-- ServerScriptService/Services/PromotionService.luau
--
-- Einzige Zustaendigkeit:
--   - Einen Baerchi mit DUPLIKATEN desselben configId befoerdern
--
-- ============================================================
-- PROMOTIONS-REGEL (verbindlich, hier dokumentiert — wie die Fusions-Regel
-- im Kopf von FusionService)
-- ============================================================
--   1. Ein Baerchi laesst sich befoerdern, solange sein promotionLevel unter
--      PromotionConfig.MAX_PROMOTION (10) liegt.
--   2. Eine Stufe kostet N Duplikate desselben configId. N haengt von der
--      Rarity UND von der Zielstufe ab (PromotionConfig.getDuplicateCost) —
--      seltenere Baerchis kosten durchgehend weniger, hoehere Stufen mehr.
--   3. Verbraucht werden ausschliesslich ANDERE Baerchi-Instanzen mit
--      demselben configId. Der ausgeruestete Baerchi wird NIE verbraucht,
--      auch nicht als Material — er steht als Figur in der Welt.
--   4. Die Duplikate verschwinden ersatzlos. KEINE Gummy-Rueckzahlung wie beim
--      Recyceln: das hier ist Material, kein Verwerten. Wer Gummies will,
--      benutzt weiterhin RecycleService.
--   5. Verbraucht wird von SCHWACH nach STARK (niedrigstes Level zuerst, bei
--      Gleichstand nach uid) — der Spieler soll nicht aus Versehen seinen
--      besten Zweit-Baerchi verlieren.
--   6. Effekt: +PROMOTION_STAT_BONUS_PER_LEVEL auf HP/ATK (siehe
--      CombatCalculator) UND das Freischalten weiterer Charm-Slots (siehe
--      CharmConfig.SLOT_UNLOCK_PROMOTION).
--
-- ============================================================
-- WARUM HIER KEINE ActivityLock-PRUEFUNG STEHT
-- ============================================================
-- RecycleService prueft das Schloss, weil er die Figur des ausgeruesteten
-- Baerchis mitten aus einer Laufbewegung loeschen koennte. Hier kann das nicht
-- passieren: Regel 3 schliesst den ausgeruesteten Baerchi als Material aus, es
-- verschwindet also nie eine Figur. Die einzige sichtbare Aenderung ist die
-- HP-Beschriftung ueber der Figur, und die zieht markDirty ohnehin gefahrlos
-- nach.
--
-- Eine Pruefung waere hier sogar aktiv schaedlich: der Autopilot haelt das
-- Schloss fast durchgehend (er schickt den Baerchi bei jedem verfuegbaren
-- Honig zum Teich), der Promote-Knopf waere also die meiste Zeit tot.

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types            = require(ReplicatedStorage.Network.Types)
local Remotes          = require(ReplicatedStorage.Network.Remotes)
local Loc           = require(ReplicatedStorage.Localization.Loc)
local BaerchiConfig    = require(ReplicatedStorage.Config.BaerchiConfig)
local PromotionConfig  = require(ReplicatedStorage.Config.PromotionConfig)
local CharmConfig      = require(ReplicatedStorage.Config.CharmConfig)
local CombatCalculator = require(ReplicatedStorage.Modules.CombatCalculator)

local PlayerService = require(ServerScriptService.Services.PlayerService)
local MapService     = require(ServerScriptService.Services.MapService)
local RateLimiter   = require(ServerScriptService.Util.RateLimiter)

-- Feier-Farbe fuer eine Befoerderung (siehe MapService.celebrateBaerchi) —
-- Violett, derselbe Ton wie Theme.COLORS.growth ("Wachstum") auf dem Client.
-- Bewusst anders als Gold beim Level-Up: die beiden Ereignisse sollen sich
-- auch optisch unterscheiden.
local PROMOTION_CELEBRATE_COLOR = Color3.fromRGB(178, 148, 255)

local PromotionService = {}

local function fail(player: Player, reason: Types.LocMsg?)
	Remotes.ActionFailed:FireClient(player, "RequestPromoteBaerchi", reason or Loc.msg("err.unknown"))
end

--------------------------------------------------------------------------------
-- Lesende Hilfen (auch fuer die UI-Vorschau gedacht)
--------------------------------------------------------------------------------

-- Alle Baerchis, die als Material fuer `target` in Frage kommen: gleicher
-- configId, andere uid, nicht der ausgeruestete.
--
-- Reihenfolge = Verbrauchsreihenfolge (Regel 5): niedrigstes Level zuerst, bei
-- Gleichstand nach uid — deterministisch, damit zweimal dasselbe passiert.
function PromotionService.getMaterials(data: Types.PlayerData, target: Types.Baerchi): { Types.Baerchi }
	local materials: { Types.Baerchi } = {}

	for uid, baerchi in data.island.baerchis do
		if uid ~= target.uid
			and baerchi.configId == target.configId
			and uid ~= data.island.equippedUid
		then
			table.insert(materials, baerchi)
		end
	end

	table.sort(materials, function(a, b)
		if a.level ~= b.level then
			return a.level < b.level
		end
		return a.uid < b.uid
	end)

	return materials
end

--------------------------------------------------------------------------------
-- Befoerdern
--------------------------------------------------------------------------------

function PromotionService.promote(player: Player, baerchiUid: string)
	local data = PlayerService.getData(player)
	if not data then return end

	local baerchi = data.island.baerchis[baerchiUid]
	if not baerchi then
		fail(player, Loc.msg("err.baerchi_not_found"))
		return
	end

	local current = baerchi.promotionLevel or 0
	if current >= PromotionConfig.MAX_PROMOTION then
		fail(player, Loc.msg("err.promo_maxed"))
		return
	end

	local nextLevel = current + 1
	local cost      = PromotionConfig.getDuplicateCost(baerchi.rarity, nextLevel)
	local materials = PromotionService.getMaterials(data, baerchi)

	if #materials < cost then
		-- Der Name geht als Nachricht mit: der Client setzt ihn in SEINER Sprache ein
		fail(player, Loc.msg("err.promo_need_material", {
			cost = cost,
			name = Loc.msg("baerchi." .. baerchi.configId .. ".name"),
			have = #materials,
		}))
		return
	end

	-- maxHp VOR der Aenderung merken: der Promotions-Bonus hebt sie an, und die
	-- Differenz wird gutgeschrieben. Ohne das haette ein frisch befoerderter
	-- Baerchi mehr maxHp bei gleichen currentHp — sein HP-Balken saehe nach der
	-- Befoerderung LEERER aus als davor.
	local def      = BaerchiConfig.getById(baerchi.configId)
	local beforeHp = if def then CombatCalculator.getEffectiveStats(baerchi, def.baseStats).maxHp else 0

	-- Erst jetzt verbrauchen: bis hierher konnte noch etwas scheitern, und
	-- geloeschte Baerchis ohne Gegenleistung waeren der schlimmste Ausgang.
	local consumedUids: { string } = {}
	for i = 1, cost do
		local material = materials[i]
		data.island.baerchis[material.uid] = nil
		table.insert(consumedUids, material.uid)
	end

	baerchi.promotionLevel = nextLevel

	if def then
		local afterHp = CombatCalculator.getEffectiveStats(baerchi, def.baseStats).maxHp
		baerchi.currentHp = math.clamp(
			(baerchi.currentHp or 0) + math.max(0, afterHp - beforeHp),
			0,
			afterHp
		)
	end

	-- Welche Charm-Slots genau durch DIESE Stufe dazukamen — der Client zeigt
	-- das als "Slot IV freigeschaltet" an, statt den Spieler die Tabelle selbst
	-- vergleichen zu lassen.
	local unlockedSlots: { number } = {}
	for slot = 1, CharmConfig.SLOT_COUNT do
		if CharmConfig.getUnlockPromotion(slot) == nextLevel then
			table.insert(unlockedSlots, slot)
		end
	end

	local result: Types.PromotionResult = {
		baerchiUid    = baerchiUid,
		newPromotion  = nextLevel,
		consumedUids  = consumedUids,
		unlockedSlots = unlockedSlots,
	}

	Remotes.PromotionResultReceived:FireClient(player, result)

	-- Sichtbar auf dem Plot feiern — siehe HoneyService fuer dieselbe
	-- Begruendung (Toast allein wird von den anderen 7 Spielern nicht gesehen).
	MapService.celebrateBaerchi(player, baerchiUid, PROMOTION_CELEBRATE_COLOR)

	PlayerService.markDirty(player)
	PlayerService.saveNow(player)

	print(
		"[PromotionService]", player.Name,
		"|", baerchi.configId, "→ Promotion", nextLevel, "/", PromotionConfig.MAX_PROMOTION,
		"| verbraucht:", cost,
		"| neue Slots:", #unlockedSlots
	)
end

function PromotionService.init()
	RateLimiter.connect(Remotes.RequestPromoteBaerchi, "RequestPromoteBaerchi", function(player, baerchiUid: any)
		if typeof(baerchiUid) ~= "string" then return end
		PromotionService.promote(player, baerchiUid)
	end)

	print("[PromotionService] Initialisiert |", PromotionConfig.MAX_PROMOTION, "Stufen")
end

return PromotionService
