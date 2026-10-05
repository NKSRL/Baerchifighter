--!strict
-- WaspQueenEvent.luau
-- ServerScriptService/Util/WaspQueenEvent.luau
--
-- Einzige Zustaendigkeit:
--   - Den Ablauf des Boss-Events "Wespenkoenigin" spielen: Ankuendigung,
--     Kampf in zwei Phasen, Attacken als Telegraph, Schaden im Takt,
--     Belohnung nach Schadensanteil (als Ergebnis fuer EventParticipationService).
--
-- Das ist der Handler EventHandlers.WaspQueen (gleiche Signatur wie alle
-- Handler: run(api, def) -> session, session.stop() -> results). Er steht in
-- einer eigenen Datei, weil er so gross ist wie zwei andere Events zusammen.
--
-- PERFORMANCE: Die Koenigin ist EIN Model, das der Server nie bewegt. Ihre
-- Bahn ist eine reine Funktion der Serverzeit (Modules/EventMotion); der
-- Server schreibt Start- und Phasenzeit als Attribute, der Client
-- (EventFXController) bewegt die Optik. Wespen und Stacheln gibt es nur als
-- Daten: der Server schickt pro Attacke einen Telegraph (Remotes.EventTelegraph),
-- der Client zeichnet die Warnflaeche, der Server rechnet bei hitAt aus, wer
-- getroffen ist. Schaden laeuft in EINEM Takt (TICK_SECONDS) fuer alle.
--
-- REGELN (siehe EventConfig.WASP_QUEEN):
--   * Baerchis am Event kaempfen automatisch. Ihr Schaden pro Sekunde kommt
--     aus dem echten Kampfmodell (Modules/BossBalance), keine eigene Formel.
--   * Spieler-Charaktere im Pit feuern an (CHEER_FACTOR) und muessen den
--     Telegraphen ausweichen. Ein Treffer stoesst zurueck und bremst (das
--     fuehrt der Client an seinem eigenen Charakter aus) und setzt den Schaden
--     des eigenen Baerchis HIT_STUN_SECONDS aus. Niemand stirbt.
--   * Phase 2 unter PHASE2_AT: schnellere Attacken, Waben-Regen mit dem
--     Wabenthema "Koenigsgelee" (CombService).
--   * Besiegt: Event endet sofort (api.finishEarly), Belohnung fuer alle ueber
--     MIN_DAMAGE_SHARE. Zeit abgelaufen: die Koenigin flieht, Teilbelohnung.

local Players             = game:GetService("Players")
local Workspace           = game:GetService("Workspace")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local EventConfig = require(ReplicatedStorage.Config.EventConfig)
local Types       = require(ReplicatedStorage.Network.Types)
local Remotes     = require(ReplicatedStorage.Network.Remotes)
local EventMotion = require(ReplicatedStorage.Modules.EventMotion)
local BossBalance = require(ReplicatedStorage.Modules.BossBalance)
local Loc         = require(ReplicatedStorage.Localization.Loc)
-- HBB Paket 7: Belohnungsstufen
local BossTiers    = require(ReplicatedStorage.Modules.BossTiers)
local FeatureFlags = require(ReplicatedStorage.Config.FeatureFlags)

local EventKit    = require(ServerScriptService.Util.EventKit)
local CombService = require(ServerScriptService.Services.CombService)

local WaspQueenEvent = {}

--------------------------------------------------------------------------------
-- Optik (keine Balance)
--------------------------------------------------------------------------------

local QUEEN_YELLOW   = Color3.fromRGB(255, 196,  40)
local QUEEN_BLACK    = Color3.fromRGB( 40,  32,  28)
local QUEEN_WING     = Color3.fromRGB(210, 235, 255)
local QUEEN_CROWN    = Color3.fromRGB(255, 225,  90)
local QUEEN_SCALE    = 1.6

-- Reihenfolge der Attacken (Phase 2 nimmt dieselbe Reihenfolge, nur schneller).
local ATTACK_ORDER: { "ring" | "circles" | "lane" } = { "ring", "circles", "lane", "circles" }

-- Bahn des Schwarms: so weit vor und hinter dem Zielpunkt (Studs).
local SWARM_HALF_LENGTH = 55

--------------------------------------------------------------------------------
-- Hilfen
--------------------------------------------------------------------------------

local flatDist = EventKit.flatDist

local function rootOfPlayer(player: Player): BasePart?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- Abstand eines Punkts zur Strecke a→b (waagerecht).
local function distToSegment(p: Vector3, a: Vector3, b: Vector3): number
	local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local ap = Vector3.new(p.X - a.X, 0, p.Z - a.Z)
	local len2 = ab:Dot(ab)
	if len2 < 1e-6 then return ap.Magnitude end
	local k = math.clamp(ap:Dot(ab) / len2, 0, 1)
	return (ap - ab * k).Magnitude
end

local function flatUnit(v: Vector3): Vector3
	local flat = Vector3.new(v.X, 0, v.Z)
	if flat.Magnitude < 1e-3 then
		return Vector3.new(1, 0, 0)
	end
	return flat.Unit
end

-- Baut die Koenigin als EIN Model, Drehpunkt = ihre Pose zu `pose`.
local function buildQueen(parent: Instance, pose: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "WaspQueen"

	local s = QUEEN_SCALE
	local function piece(props: { [string]: any }, offset: CFrame)
		props.CFrame = pose * offset
		EventKit.fxPart(props, model)
	end

	-- Hinterleib (gelb, zwei schwarze Streifen, Stachel), Brust, Kopf, Krone, Fluegel
	piece({ Name = "Abdomen", Shape = Enum.PartType.Ball, Material = Enum.Material.SmoothPlastic,
		Color = QUEEN_YELLOW, Size = Vector3.new(6, 6, 9) * s }, CFrame.new(0, 0, 5 * s))
	piece({ Name = "Stripe1", Shape = Enum.PartType.Cylinder, Material = Enum.Material.SmoothPlastic,
		Color = QUEEN_BLACK, Size = Vector3.new(1, 6.2, 6.2) * s }, CFrame.new(0, 0, 4 * s) * CFrame.Angles(0, math.rad(90), 0))
	piece({ Name = "Stripe2", Shape = Enum.PartType.Cylinder, Material = Enum.Material.SmoothPlastic,
		Color = QUEEN_BLACK, Size = Vector3.new(1, 5.4, 5.4) * s }, CFrame.new(0, 0, 6.6 * s) * CFrame.Angles(0, math.rad(90), 0))
	piece({ Name = "Stinger", Material = Enum.Material.Neon,
		Color = QUEEN_BLACK, Size = Vector3.new(0.8, 0.8, 3) * s }, CFrame.new(0, -0.5 * s, 10 * s))
	piece({ Name = "Thorax", Shape = Enum.PartType.Ball, Material = Enum.Material.SmoothPlastic,
		Color = QUEEN_BLACK, Size = Vector3.new(4.5, 4.5, 4.5) * s }, CFrame.new(0, 0.4 * s, 0))
	piece({ Name = "Head", Shape = Enum.PartType.Ball, Material = Enum.Material.SmoothPlastic,
		Color = QUEEN_YELLOW, Size = Vector3.new(4, 3.6, 3.6) * s }, CFrame.new(0, 0.8 * s, -3.5 * s))
	piece({ Name = "Crown", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon,
		Color = QUEEN_CROWN, Size = Vector3.new(1.2, 2.6, 2.6) * s }, CFrame.new(0, 3 * s, -3.5 * s) * CFrame.Angles(0, 0, math.rad(90)))
	piece({ Name = "WingL", Material = Enum.Material.Glass, Transparency = 0.35,
		Color = QUEEN_WING, Size = Vector3.new(9, 0.3, 4) * s }, CFrame.new(-5 * s, 3 * s, 1 * s) * CFrame.Angles(0, 0, math.rad(20)))
	piece({ Name = "WingR", Material = Enum.Material.Glass, Transparency = 0.35,
		Color = QUEEN_WING, Size = Vector3.new(9, 0.3, 4) * s }, CFrame.new(5 * s, 3 * s, 1 * s) * CFrame.Angles(0, 0, math.rad(-20)))

	model.WorldPivot = pose
	model.Parent = parent
	return model
end

--------------------------------------------------------------------------------
-- Der Handler
--------------------------------------------------------------------------------

function WaspQueenEvent.run(api: EventKit.Api, def: EventConfig.EventDef): EventKit.Session
	local cfg     = EventConfig.WASP_QUEEN
	local center  = api.center
	local running = true

	local folder = EventKit.newFolder("EventWaspQueen")
	local now0 = Workspace:GetServerTimeNow()
	local fightStart = now0 + cfg.ANNOUNCE_SECONDS

	-- Attribute fuer den Client: Bahn-Startzeit, Mitte, Kampfbeginn.
	folder:SetAttribute("StartTime", fightStart)
	folder:SetAttribute("Center", center)

	local queen = buildQueen(folder, EventMotion.queenPose(center, fightStart, fightStart, nil))

	-- Kampf-Zustand (nur im Speicher)
	local maxHp = 0
	local hp = 0
	local phase2At: number? = nil
	local victory = false
	local fighting = false
	local damage: { [Player]: number } = {}
	local stunUntil: { [Player]: number } = {}   -- os.clock()
	local dpsOf: { [string]: number } = {}       -- je baerchiUid
	-- HBB Paket 7: Potenzial (DPS x Zeit am Boss) und Aktivitaet je Spieler
	local potential: { [Player]: number } = {}
	local lastActive: { [Player]: number } = {}  -- os.clock()
	local lastPos: { [Player]: Vector3 } = {}
	local nextActivityCheck = 0

	local function publishHp()
		queen:SetAttribute("MaxHP", math.floor(maxHp))
		queen:SetAttribute("HP", math.max(0, math.floor(hp)))
	end

	local function measureDps(part: EventKit.Part): number
		local cached = dpsOf[part.baerchiUid]
		if cached then return cached end
		local stats = api.fightStats(part)
		local dps = if stats then BossBalance.dpsFromStats(stats) else 0
		dpsOf[part.baerchiUid] = dps
		return dps
	end

	local function inPit(position: Vector3): boolean
		return flatDist(position, center) <= api.radius
	end

	api.announce(Loc.msg("msg.boss.announce", { seconds = cfg.ANNOUNCE_SECONDS }), "big")

	----------------------------------------------------------------------------
	-- Attacken
	----------------------------------------------------------------------------

	-- Spieler-Charaktere, die gerade im Pit stehen (nur sie koennen getroffen werden).
	local function playersInPit(): { { player: Player, root: BasePart } }
		local list = {}
		for _, player in Players:GetPlayers() do
			local root = rootOfPlayer(player)
			if root and inPit(root.Position) then
				table.insert(list, { player = player, root = root })
			end
		end
		return list
	end

	local function randomPitPoint(): Vector3
		local angle = math.random() * math.pi * 2
		local r = api.radius * math.sqrt(math.random()) * 0.85
		return center + Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
	end

	local function onGround(p: Vector3): Vector3
		return Vector3.new(p.X, center.Y, p.Z)
	end

	-- Wer ist bei hitAt in der Flaeche? Treffer: Rueckstoss + Bremse beim
	-- Client, Schadenspause fuer seinen Baerchi.
	local function resolve(t: Types.HazardTelegraph)
		for _, entry in playersInPit() do
			local p = entry.root.Position
			local hit = false
			local pushFrom: Vector3 = center

			if t.kind == "ring" and t.center then
				local d = flatDist(p, t.center)
				hit = d >= (t.inner or 0) and d <= (t.outer or 0)
				pushFrom = t.center
			elseif t.kind == "circles" and t.points then
				for _, point in t.points do
					if flatDist(p, point) <= (t.radius or 0) then
						hit = true
						pushFrom = point
						break
					end
				end
			elseif t.kind == "lane" and t.from and t.to then
				hit = distToSegment(p, t.from, t.to) <= (t.width or 0) / 2
				if hit then
					-- seitlich aus der Bahn stossen
					local along = flatUnit(t.to - t.from)
					local side = Vector3.new(-along.Z, 0, along.X)
					local rel = Vector3.new(p.X - t.from.X, 0, p.Z - t.from.Z)
					pushFrom = p - (if rel:Dot(side) >= 0 then side else -side)
				end
			end

			if hit then
				stunUntil[entry.player] = os.clock() + cfg.HIT_STUN_SECONDS
				local hitInfo: Types.HazardHit = {
					push        = flatUnit(p - pushFrom) * cfg.KNOCKBACK_SPEED,
					slowFactor  = cfg.SLOW_FACTOR,
					slowSeconds = cfg.SLOW_SECONDS,
				}
				Remotes.EventHazardHit:FireClient(entry.player, hitInfo)
			end
		end
	end

	local attackIndex = 0
	local function launchAttack()
		attackIndex += 1
		local kind = ATTACK_ORDER[(attackIndex - 1) % #ATTACK_ORDER + 1]
		local serverNow = Workspace:GetServerTimeNow()
		local hitAt = serverNow + cfg.TELEGRAPH_SECONDS
		local targets = playersInPit()

		local telegraph: Types.HazardTelegraph
		if kind == "ring" then
			telegraph = {
				kind = "ring",
				center = EventMotion.queenGround(center, fightStart, hitAt, phase2At),
				inner = cfg.SHOCK_INNER, outer = cfg.SHOCK_OUTER,
				warnAt = serverNow, hitAt = hitAt,
			}
		elseif kind == "circles" then
			local count = if phase2At then cfg.STING_COUNT_PHASE2 else cfg.STING_COUNT
			local points: { Vector3 } = {}
			for i = 1, count do
				local target = targets[((i - 1) % math.max(1, #targets)) + 1]
				-- Erst auf Spieler zielen, dann um sie herum streuen.
				local base = if target and i <= #targets then onGround(target.root.Position) else randomPitPoint()
				table.insert(points, base)
			end
			telegraph = {
				kind = "circles", points = points, radius = cfg.STING_RADIUS,
				warnAt = serverNow, hitAt = hitAt,
			}
		else
			local target = if #targets > 0 then targets[math.random(1, #targets)] else nil
			local through = if target then onGround(target.root.Position) else randomPitPoint()
			local angle = math.random() * math.pi * 2
			local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
			telegraph = {
				kind = "lane",
				from = through - dir * SWARM_HALF_LENGTH, to = through + dir * SWARM_HALF_LENGTH,
				width = cfg.SWARM_WIDTH,
				warnAt = serverNow, hitAt = hitAt,
			}
		end

		Remotes.EventTelegraph:FireAllClients(telegraph)
		task.delay(cfg.TELEGRAPH_SECONDS, function()
			if running and fighting then
				local ok, err = pcall(resolve, telegraph)
				if not ok then
					warn("[WaspQueen] Treffer-Pruefung fehlgeschlagen:", err)
				end
			end
		end)
	end

	----------------------------------------------------------------------------
	-- Kampf-Takt
	----------------------------------------------------------------------------

	local nextAttack = 0
	local nextRain = 0

	local function startFight()
		local dpsList: { number } = {}
		for _, part in api.participants() do
			table.insert(dpsList, measureDps(part))
		end
		maxHp = BossBalance.bossHp(dpsList)
		hp = maxHp
		publishHp()
		fighting = true
		nextAttack = os.clock() + cfg.PHASE1_ATTACK_INTERVAL
		api.announce(Loc.msg("msg.boss.fight"), "big")
		print(string.format("[WaspQueen] Kampf beginnt | %d Baerchis | HP %d", #dpsList, maxHp))
	end

	local function fightTick()
		local now = os.clock()
		local elapsed = Workspace:GetServerTimeNow() - fightStart

		-- Wer erst jetzt dazukommt, macht den Kampf nicht kuerzer.
		local total = 0
		local checkActivity = now >= nextActivityCheck
		if checkActivity then
			nextActivityCheck = now + EventConfig.BOSS_TIERS.ACTIVE_CHECK_SECONDS
		end
		for _, part in api.participants() do
			local uid = part.baerchiUid
			if dpsOf[uid] == nil then
				local dps = measureDps(part)
				local extra = BossBalance.lateJoinHp(dps, elapsed)
				maxHp += extra
				hp += extra
			end

			local player = part.player

			-- HBB Paket 7: was der eigene Baerchi in dieser Zeit haette machen
			-- koennen (ohne Anfeuern, ohne Treffer) — Massstab der Stufe.
			potential[player] = (potential[player] or 0) + (dpsOf[uid] or 0) * cfg.TICK_SECONDS
			if checkActivity then
				local root = rootOfPlayer(player)
				if root then
					local before = lastPos[player]
					if before and (root.Position - before).Magnitude > EventConfig.BOSS_TIERS.ACTIVE_MOVE_STUDS then
						lastActive[player] = now
					end
					lastPos[player] = root.Position
				end
			end

			if now >= (stunUntil[player] or 0) then
				local root = rootOfPlayer(player)
				local cheer = if root and inPit(root.Position) then cfg.CHEER_FACTOR else 1
				local dmg = (dpsOf[uid] or 0) * cfg.TICK_SECONDS * cheer
				damage[player] = (damage[player] or 0) + dmg
				total += dmg
			end
		end
		hp -= total
		publishHp()

		-- Phase 2
		if not phase2At and hp <= maxHp * cfg.PHASE2_AT then
			phase2At = Workspace:GetServerTimeNow()
			queen:SetAttribute("Phase2At", phase2At)
			CombService.setTheme(cfg.RAIN_THEME)
			nextRain = now
			api.announce(Loc.msg("msg.boss.phase2"), "big")
		end
		if phase2At and now >= nextRain then
			CombService.launchCombs(cfg.RAIN_COUNT, nil)
			nextRain = now + cfg.RAIN_INTERVAL_SECONDS
		end

		-- Attacken
		if now >= nextAttack then
			launchAttack()
			nextAttack = now + (if phase2At then cfg.PHASE2_ATTACK_INTERVAL else cfg.PHASE1_ATTACK_INTERVAL)
		end

		-- Sieg
		if hp <= 0 then
			victory = true
			fighting = false
			api.announce(Loc.msg("msg.boss.victory"), "big")
			print(string.format("[WaspQueen] Besiegt nach %.0f s", elapsed))
			api.finishEarly()
		end
	end

	task.spawn(function()
		local untilFight = fightStart - Workspace:GetServerTimeNow()
		if untilFight > 0 then task.wait(untilFight) end
		if not running then return end

		local ok, err = pcall(startFight)
		if not ok then
			warn("[WaspQueen] Kampfbeginn fehlgeschlagen:", err)
			return
		end

		while running and fighting do
			task.wait(cfg.TICK_SECONDS)
			if not running or not fighting then break end
			local ok2, err2 = pcall(fightTick)
			if not ok2 then
				warn("[WaspQueen] Takt fehlgeschlagen:", err2)
			end
		end
	end)

	----------------------------------------------------------------------------
	-- Ende: Belohnung nach Schadensanteil
	----------------------------------------------------------------------------

	return {
		stop = function()
			running = false
			fighting = false

			if not victory and maxHp > 0 then
				api.announce(Loc.msg("msg.boss.fled"), "info")
			end

			local results: { [Player]: EventKit.Reward } = {}
			local payouts = BossBalance.payouts(damage, victory)
			for player, pay in payouts do
				if not pay.qualified then
					-- Mit Stufen bekommt auch er etwas (unten): keine "zu wenig"-Meldung.
					if FeatureFlags.isOn("BOSS_TIERS") then continue end
					api.notify(player, Loc.msg("msg.boss.too_little", { min = math.floor(cfg.MIN_DAMAGE_SHARE * 100) }), "info")
					continue
				end

				local reward: EventKit.Reward = {
					gummies   = pay.gummies,
					combUnits = pay.combUnits,
					notice    = Loc.msg("msg.boss.reward", {
						rank  = pay.rank,
						share = math.floor(pay.share * 100 + 0.5),
					}),
				}

				if pay.victoryEgg then
					if math.random() < cfg.JACKPOT_CHANCE then
						reward.egg = { kind = "eggs", eggType = EventConfig.UFO.JACKPOT_EGG, amount = 1 }
						api.announce(Loc.msg("msg.boss.jackpot", { player = player.DisplayName }), "big")
					else
						reward.egg = def.bonus
					end
				end
				if pay.top then
					reward.extraEgg = { kind = "eggs", eggPick = "jump", amount = 1 }
					reward.rarityUpFactor = cfg.RARITY_UP_FACTOR
				end
				results[player] = reward
			end

			-- HBB Paket 7: Stufen ZUSAETZLICH zur Anteils-Belohnung oben. Jeder
			-- mit Schaden >= 1 bekommt etwas, auch unter MIN_DAMAGE_SHARE.
			if FeatureFlags.isOn("BOSS_TIERS") then
				local tiersCfg = EventConfig.BOSS_TIERS
				local now = os.clock()
				for player, dmg in damage do
					local active = now - (lastActive[player] or -math.huge) <= tiersCfg.ACTIVE_WINDOW_SECONDS
					local tier = BossTiers.tierFor(dmg, potential[player] or 0, active, victory, tiersCfg)
					local pay = tiersCfg.REWARDS[tier]
					if tier <= 0 or not pay then continue end

					local reward: EventKit.Reward = results[player] or {}
					reward.gummies   = (reward.gummies or 0) + pay.gummies
					reward.combUnits = (reward.combUnits or 0) + pay.combUnits
					reward.bossTier  = tier
					if pay.mutationRoll then
						reward.tierBonus = { kind = "mutation", chance = tiersCfg.MUTATION_CHANCE }
					end
					-- Eier zahlt EventParticipationService mit dem Rest aus (gleiche
					-- Pruefung, ob der Baerchi noch am Event steht).
					reward.tierEggs = pay.basicEggs
					results[player] = reward
					print(string.format("[WaspQueen] %s | Stufe %d | Schaden %.0f / Potenzial %.0f | aktiv %s",
						player.Name, tier, dmg, potential[player] or 0, tostring(active)))
				end
			end

			-- Waben im Pit wieder normal (getragene behalten ihren Wert).
			CombService.clearTheme()
			folder:Destroy()
			return results
		end,
	}
end

return WaspQueenEvent
