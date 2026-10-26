--!strict
-- PotionService.luau
-- ServerScriptService/Services/PotionService.luau
--
-- Einzige Zustaendigkeit:
--   - Traenke (26.10., FeatureFlags.POTIONS_V1): das Regal am Ei-Haendler in
--     der Mitte mit eigenem Prompt, das wechselnde Sortiment (alle 5 Minuten,
--     Basis-Ei + 3-5 Traenke = bis zu 6 Angebote), der Kauf (Entfernung,
--     Angebot, Stapel-Regel, Preis), das Austragen abgelaufener Effekte und
--     die Laufgeschwindigkeit des Spielers (Tempo-Trank).
--
-- Wo die Boni greifen, steht im Kopf von Config/PotionConfig; die Systeme
-- (EconomyService, CombatService, HoneyService, EggService, CombService)
-- fragen dafuer nur PotionRules.multiplier auf dem Spielstand — sie kennen
-- diesen Service nicht. Die Regeln rechnet Modules/PotionRules (rein,
-- getestet); hier ist nur die Anbindung an Spieler, Welt und Remotes.
-- Muenzen bucht ausschliesslich EconomyService.
--
-- ============================================================
-- SORTIMENT: EIN LOS JE 5-MINUTEN-FENSTER DER WELTZEIT
-- ============================================================
-- PotionRules.rollAssortment(window) ist deterministisch: jeder Server zeigt
-- zur selben Zeit dasselbe Regal, der Wechsel faellt auf volle fuenf Minuten,
-- und ein Kauf nennt das Fenster mit — ein Angebot aus dem alten Fenster
-- wird abgelehnt. Die Sicht (Preise, Stapel-Stand) ist je Spieler und wird
-- beim Druecken am Regal, auf Anfrage und bei jedem Wechsel geschickt.
--
-- ============================================================
-- TEMPO
-- ============================================================
-- WalkSpeed gehoert sonst CombService (Waben bremsen im Pit). Abstimmung ueber
-- das Spieler-Attribut "PotionSpeed": CombService multipliziert damit seine
-- Werte; dieser Service setzt WalkSpeed nur, solange der Spieler KEINE Waben
-- traegt (Attribut CombsCarried == 0), und nur fuer Spieler, denen er selbst
-- einmal Tempo gegeben hat (_boosted) — alle anderen behalten, was sie haben.

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types        = require(ReplicatedStorage.Network.Types)
local Remotes      = require(ReplicatedStorage.Network.Remotes)
local Loc          = require(ReplicatedStorage.Localization.Loc)
local WorldText    = require(ReplicatedStorage.Localization.WorldText)
local FeatureFlags = require(ReplicatedStorage.Config.FeatureFlags)
local PotionConfig = require(ReplicatedStorage.Config.PotionConfig)
local PotionRules  = require(ReplicatedStorage.Modules.PotionRules)
local TowerConfig  = require(ReplicatedStorage.Config.TowerConfig)
local CombConfig   = require(ReplicatedStorage.Config.CombConfig)
local EggConfig    = require(ReplicatedStorage.Config.EggConfig)

local PlayerService      = require(ServerScriptService.Services.PlayerService)
local EconomyService     = require(ServerScriptService.Services.EconomyService)
local EggMerchantService = require(ServerScriptService.Services.EggMerchantService)
local RateLimiter        = require(ServerScriptService.Util.RateLimiter)

local PotionService = {}

local SHELF_NAME = "PotionShelf"

-- Aktuelles Los: Fenster und Trank-Ids in Ziehreihenfolge
local _window: number = -1
local _assortment: { string } = {}
-- Nur Studio (DebugPotions): verschiebt das Fenster, um den Wechsel zu testen
local _debugWindowOffset = 0

-- Spieler, denen dieser Service WalkSpeed gesetzt hat (siehe Kopf)
local _boosted: { [Player]: boolean } = {}

local function enabled(): boolean
	return FeatureFlags.isOn("POTIONS_V1")
end

local function fail(player: Player, reason: Types.LocMsg | string)
	Remotes.ActionFailed:FireClient(player, "RequestMerchantBuy", reason)
end

--------------------------------------------------------------------------------
-- Preis
--------------------------------------------------------------------------------

-- Bezugsgroesse der Preisformel (PotionConfig, Abschnitt PREIS): Pfotenmuenzen
-- je Stage auf der besten Stage dieses Lebens im hoechsten Tower, in dem der
-- Spieler schon eine Stage geschafft hat — mal rebirthMult, wie das Einkommen.
-- 0 fuer Neulinge ohne Kampf (dann gilt minPrice).
function PotionService.priceReference(data: Types.PlayerData): number
	local best = 0
	local stageBest = data.island.stageBest
	if typeof(stageBest) == "table" then
		for _, def in TowerConfig.TOWERS do
			local stage = stageBest[def.id]
			if typeof(stage) == "number" and stage >= 1 then
				best = math.max(best, TowerConfig.getStageReward(def.id, math.min(math.floor(stage), def.stages)))
			end
		end
	end
	return best * math.max(1, data.rebirthMult or 1)
end

function PotionService.priceFor(data: Types.PlayerData, def: PotionConfig.PotionDef): number
	return PotionRules.price(def, PotionService.priceReference(data))
end

--------------------------------------------------------------------------------
-- Sortiment
--------------------------------------------------------------------------------

local function currentWindow(): number
	return PotionRules.windowOf(os.time(), PotionConfig.MERCHANT.ROTATE_SECONDS) + _debugWindowOffset
end

-- Zieht das Los neu, wenn das Fenster gewechselt hat. true = geaendert.
local function refreshAssortment(): boolean
	local window = currentWindow()
	if window == _window then return false end
	_window = window
	_assortment = PotionRules.rollAssortment(window, PotionConfig.POTIONS,
		PotionConfig.MERCHANT.SLOTS_MIN, PotionConfig.MERCHANT.SLOTS_MAX)
	return true
end

-- Fuer Debug und Tests in Studio: Fenster und Ids (Kopie).
function PotionService.getAssortment(): (number, { string })
	refreshAssortment()
	return _window, table.clone(_assortment)
end

local function buildView(data: Types.PlayerData): Types.MerchantView
	refreshAssortment()
	local now = os.time()
	local reference = PotionService.priceReference(data)
	local offers: { Types.MerchantOffer } = {}
	for slot, potionId in _assortment do
		local def = PotionConfig.byId(potionId)
		if def then
			table.insert(offers, {
				slot     = slot,
				potionId = potionId,
				price    = PotionRules.price(def, reference),
				action   = PotionRules.check((data :: any).potions, def, now, PotionConfig.MAX_REMAINING_SECONDS),
			})
		end
	end
	return {
		window    = _window,
		rotatesIn = PotionRules.secondsUntilRotation(now, PotionConfig.MERCHANT.ROTATE_SECONDS),
		offers    = offers,
		eggPrice  = EggConfig.MERCHANT.priceGummies,
		eggType   = EggConfig.MERCHANT.eggType,
	}
end

local function sendView(player: Player, open: boolean)
	local data = PlayerService.getData(player)
	if not data then return end
	Remotes.MerchantViewReceived:FireClient(player, buildView(data), open)
end

local function broadcastViews()
	for _, player in Players:GetPlayers() do
		sendView(player, false)
	end
end

--------------------------------------------------------------------------------
-- Tempo
--------------------------------------------------------------------------------

local function applySpeed(player: Player)
	local data = PlayerService.getData(player)
	if not data then return end
	local factor = if enabled() then PotionRules.multiplier((data :: any).potions, "speed", os.time()) else 1
	player:SetAttribute("PotionSpeed", if factor ~= 1 then factor else nil)

	-- Mit Waben auf dem Kopf fuehrt CombService (es liest das Attribut mit).
	local carried = player:GetAttribute("CombsCarried")
	if typeof(carried) == "number" and carried > 0 then return end

	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not humanoid then return end

	if factor > 1 then
		humanoid.WalkSpeed = CombConfig.BASE_WALK_SPEED * factor
		_boosted[player] = true
	elseif _boosted[player] then
		humanoid.WalkSpeed = CombConfig.BASE_WALK_SPEED
		_boosted[player] = nil
	end
end

--------------------------------------------------------------------------------
-- Kaufen
--------------------------------------------------------------------------------

-- Trank anwenden, ohne zu bezahlen (Kauf nach dem Abbuchen, Debug, spaeter
-- Belohnungen). `seconds` ueberschreibt die Dauer (nur Debug). false = die
-- Stapel-Regel lehnt ab (Grund = PotionRules-Konstante).
function PotionService.grant(player: Player, potionId: string, seconds: number?, action: string?): (boolean, string)
	local data = PlayerService.getData(player)
	local def = PotionConfig.byId(potionId)
	if not data or not def then return false, "unknown" end
	if typeof((data :: any).potions) ~= "table" then
		(data :: any).potions = PotionRules.newState()
	end
	if seconds then
		def = table.clone(def)
		def.durationSeconds = math.max(1, math.floor(seconds))
	end
	local now = os.time()
	local ok, outcome, effect = PotionRules.apply((data :: any).potions, def, now, PotionConfig.MAX_REMAINING_SECONDS)
	if not ok or not effect then return false, outcome end

	if def.kind == "speed" then applySpeed(player) end

	Remotes.PotionActivated:FireClient(player, {
		potionId   = def.id,
		kind       = def.kind,
		multiplier = effect.multiplier,
		remaining  = effect.expiresAt - now,
		action     = action or outcome,
	} :: Types.PotionActivatedResult)
	PlayerService.markDirty(player)
	return true, outcome
end

local function buyPotion(player: Player, potionId: string, window: number)
	local data = PlayerService.getData(player)
	if not data then return end
	if not enabled() then
		fail(player, Loc.msg("err.potion_disabled"))
		return
	end
	local def = PotionConfig.byId(potionId)
	if not def then
		fail(player, Loc.msg("err.potion_unknown"))
		return
	end
	-- Nur am Stand: dieselbe Entfernung wie beim Ei (Server prueft selbst).
	if not EggMerchantService.isNear(player) then
		fail(player, Loc.msg("err.merchant_far"))
		return
	end
	-- Nur, was gerade im Regal steht — und aus dem aktuellen Fenster.
	refreshAssortment()
	if window ~= _window or table.find(_assortment, potionId) == nil then
		fail(player, Loc.msg("err.potion_not_offered"))
		sendView(player, false)
		return
	end

	local now = os.time()
	local outcome = PotionRules.check((data :: any).potions, def, now, PotionConfig.MAX_REMAINING_SECONDS)
	if outcome == PotionRules.WEAKER then
		fail(player, Loc.msg("err.potion_weaker"))
		return
	elseif outcome == PotionRules.MAXTIME then
		fail(player, Loc.msg("err.potion_max_time", { time = Loc.formatDuration(PotionConfig.MAX_REMAINING_SECONDS) }))
		return
	end

	-- Erst pruefen (oben), dann bezahlen, dann anwenden: apply kann jetzt
	-- nicht mehr scheitern, also bleibt kein Geld ohne Trank.
	local price = PotionService.priceFor(data, def)
	local paid, reason = EconomyService.spendGummies(player, price)
	if not paid then
		fail(player, reason or Loc.msg("err.unknown"))
		return
	end

	local ok = PotionService.grant(player, def.id, nil, outcome)
	if not ok then
		-- Darf nach dem check oben nicht passieren; falls doch: Geld zurueck.
		EconomyService.awardGummiesFlat(player, price)
		fail(player, Loc.msg("err.unknown"))
		return
	end

	PlayerService.saveNow(player)
	sendView(player, false)
	print("[PotionService]", player.Name, "kauft", def.id, "(", outcome, ") fuer", price, "| Fenster", _window)
end

local function openFor(player: Player)
	if not enabled() then return end
	if not EggMerchantService.isNear(player) then
		fail(player, Loc.msg("err.merchant_far"))
		return
	end
	sendView(player, true)
end

--------------------------------------------------------------------------------
-- Regal am Stand
--------------------------------------------------------------------------------

-- Ein kleines Brett links vom Ei auf der Theke mit drei Flaeschchen (Farben
-- der ersten drei Sorten) und dem Prompt "Traenke" (F / Controller Y, damit
-- es neben dem Ei-Prompt E / X stehen kann). Nur Optik und Ausloeser —
-- das Angebot selbst zeigt das Fenster.
local function buildShelf(counter: BasePart): BasePart
	local model = counter.Parent
	local existing = if model then model:FindFirstChild(SHELF_NAME) else nil
	if existing then existing:Destroy() end

	-- Boden-CFrame des Stands (Theke steht 1,3 ueber dem Boden, siehe EggMerchantService)
	local base = counter.CFrame * CFrame.new(0, -1.3, 0)
	local function at(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x, y, z)
	end
	local function part(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, parent: Instance): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cframe
		p.Color = color
		p.Material = material
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = parent
		return p
	end

	local shelf = part(SHELF_NAME, Vector3.new(2.2, 0.2, 1.0), at(-1.8, 3.0, -0.1), Color3.fromRGB(112, 76, 44), Enum.Material.Wood, model or counter)
	shelf.CanQuery = true
	for index = 1, 3 do
		local kind = PotionConfig.KINDS[index]
		local color = Color3.fromRGB(200, 200, 255)
		for _, def in PotionConfig.POTIONS do
			if def.kind == kind and def.tier == 1 then color = def.color end
		end
		local x = -2.45 + (index - 1) * 0.65
		local body = part("Bottle" .. index, Vector3.new(0.5, 0.6, 0.5), at(x, 3.42, -0.1), color, Enum.Material.Neon, shelf)
		body.Shape = Enum.PartType.Ball
		body.Transparency = 0.15
		part("Cork" .. index, Vector3.new(0.2, 0.22, 0.2), at(x, 3.8, -0.1), Color3.fromRGB(150, 105, 62), Enum.Material.Wood, shelf)
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name                  = "PotionPrompt"
	prompt.ObjectText            = ""
	prompt.KeyboardKeyCode       = Enum.KeyCode.F
	prompt.GamepadKeyCode        = Enum.KeyCode.ButtonY
	prompt.MaxActivationDistance = EggConfig.MERCHANT.promptDistance
	prompt.RequiresLineOfSight   = false
	prompt.HoldDuration          = 0
	-- GamepadController laesst die Taste so (sonst bekaeme sie X wie das Ei)
	prompt:SetAttribute("KeepGamepadKey", true)
	WorldText.set(prompt, Loc.msg("world.merchant.potions"), "ActionText")
	prompt.Parent = shelf
	prompt.Triggered:Connect(openFor)

	return shelf
end

--------------------------------------------------------------------------------
-- Start
--------------------------------------------------------------------------------

local function hookCharacter(player: Player, character: Model)
	-- Neuer Charakter startet mit Roblox-Standard; laeuft ein Tempo-Trank,
	-- bekommt er ihn gleich wieder (Daten koennen beim Spawn des ersten
	-- Charakters noch fehlen — dann holt es onDataLoaded nach).
	_boosted[player] = nil
	task.spawn(function()
		character:WaitForChild("Humanoid", 10)
		if player.Parent and PlayerService.getData(player) then
			applySpeed(player)
		end
	end)
end

function PotionService.init()
	if not enabled() then
		print("[PotionService] Aus (POTIONS_V1 = false)")
		return
	end

	RateLimiter.connect(Remotes.RequestMerchantView, "RequestMerchantView", function(player)
		sendView(player, false)
	end)

	RateLimiter.connect(Remotes.RequestMerchantBuy, "RequestMerchantBuy", function(player, what: any, potionId: any, window: any)
		if what == "egg" then
			EggMerchantService.buyEgg(player)
			return
		end
		if what ~= "potion" or typeof(potionId) ~= "string" or typeof(window) ~= "number" or window ~= window then
			return
		end
		buyPotion(player, potionId, math.floor(window))
	end)

	PlayerService.onDataLoaded(function(player, data)
		-- Abgelaufene Effekte aus der letzten Sitzung austragen, Tempo setzen
		PotionRules.prune((data :: any).potions, os.time())
		applySpeed(player)
	end)

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			hookCharacter(player, character)
		end)
	end)
	for _, player in Players:GetPlayers() do
		player.CharacterAdded:Connect(function(character)
			hookCharacter(player, character)
		end)
	end
	Players.PlayerRemoving:Connect(function(player)
		_boosted[player] = nil
	end)

	print("[PotionService] Initialisiert |", #PotionConfig.POTIONS, "Traenke | Wechsel alle",
		PotionConfig.MERCHANT.ROTATE_SECONDS, "s")
end

function PotionService.start()
	if not enabled() then return end

	-- Regal an den Stand haengen (EggMerchantService.init hat ihn gebaut —
	-- start() laeuft nach ALLEN init(), die Reihenfolge der Liste ist egal).
	local counter = EggMerchantService.getCounter()
	if counter then
		buildShelf(counter)
	else
		warn("[PotionService] Kein Ei-Haendler in der Welt — Regal entfaellt, Kauf nur per Debug")
	end

	refreshAssortment()
	print("[PotionService] Sortiment Fenster", _window, ":", table.concat(_assortment, ", "))

	-- Wechsel auf volle fuenf Minuten (Weltzeit), danach an alle melden
	task.spawn(function()
		while true do
			local wait = PotionRules.secondsUntilRotation(os.time(), PotionConfig.MERCHANT.ROTATE_SECONDS)
			task.wait(math.max(1, wait) + 0.2)
			if refreshAssortment() then
				print("[PotionService] Neues Sortiment Fenster", _window, ":", table.concat(_assortment, ", "))
				broadcastViews()
			end
		end
	end)

	-- Abgelaufene Effekte austragen (Client zaehlt selbst herunter; hier
	-- faellt der Bonus wirklich weg und der Stand wird gesynct)
	task.spawn(function()
		while true do
			task.wait(PotionConfig.TICK_SECONDS)
			local now = os.time()
			for _, player in Players:GetPlayers() do
				local data = PlayerService.getData(player)
				if data then
					local removed = PotionRules.prune((data :: any).potions, now)
					if #removed > 0 then
						if table.find(removed, "speed") then applySpeed(player) end
						PlayerService.markDirty(player)
					end
				end
			end
		end
	end)
end

-- Nur Studio (DebugPotions): Fenster um n verschieben, Los neu ziehen, melden.
function PotionService.debugShiftWindow(n: number): (number, { string })
	_debugWindowOffset += math.floor(n)
	if refreshAssortment() then broadcastViews() end
	return _window, table.clone(_assortment)
end

-- Nur Studio: Sicht eines Spielers (Preise, Stapel-Stand)
function PotionService.debugView(player: Player): Types.MerchantView?
	local data = PlayerService.getData(player)
	return if data then buildView(data) else nil
end

return PotionService
