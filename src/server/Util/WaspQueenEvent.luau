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
-- Optik (keine Balance): Suesse, kinderfreundliche Chibi-Wespenkoenigin
--------------------------------------------------------------------------------

local QUEEN_YELLOW   = Color3.fromRGB(255, 204,  58)
local QUEEN_PLUM     = Color3.fromRGB( 56,  42,  76)
local QUEEN_GOLD     = Color3.fromRGB(246, 196,  62)
local QUEEN_CREAM    = Color3.fromRGB(250, 242, 224)
local QUEEN_WING     = Color3.fromRGB(212, 240, 255)
local QUEEN_CROWN    = Color3.fromRGB(255, 222,  82)
local QUEEN_EYE_DARK = Color3.fromRGB( 24,  16,  38)
local QUEEN_SHINE    = Color3.fromRGB(255, 255, 255)
local QUEEN_BLUSH    = Color3.fromRGB(255, 128, 152)
local QUEEN_CUSHION  = Color3.fromRGB(245,  96, 132)
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
-- Suesse, kinderfreundliche Chibi-Wespenkoenigin (grosse Kulleraugen mit
-- Glanzlichtern, rosa Pausbaeckchen, flauschiger Koenigskragen, Kroenchen mit
-- Perlen & Kissen, kurze Stummelpfoten mit Goldschuhen und runde Feenfluegel).
local function buildQueen(parent: Instance, pose: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "WaspQueen"

	local s = QUEEN_SCALE
	local function piece(props: { [string]: any }, offset: CFrame): BasePart
		props.CFrame = pose * offset
		return EventKit.fxPart(props, model)
	end

	-- 1. Optionaler FBX-Mesh-Pfad (falls Wespenkoenigin_Boss.fbx in ReplicatedStorage.Assets importiert wurde)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local bossFolder = assets and (assets:FindFirstChild("Boss") or assets:FindFirstChild("Map"))
	local meshChitin = bossFolder and bossFolder:FindFirstChild("WaspQueen_ChitinSchwarz", true)
	if meshChitin and meshChitin:IsA("BasePart") then
		local meshSpecs = {
			{ name = "WaspQueen_ChitinSchwarz", color = QUEEN_PLUM,    mat = Enum.Material.SmoothPlastic, trans = 0 },
			{ name = "WaspQueen_PanzerGelb",    color = QUEEN_YELLOW,  mat = Enum.Material.SmoothPlastic, trans = 0 },
			{ name = "WaspQueen_KroneGold",     color = QUEEN_GOLD,    mat = Enum.Material.Metal,         trans = 0 },
			{ name = "WaspQueen_AugenGlut",     color = QUEEN_SHINE,   mat = Enum.Material.Neon,          trans = 0 },
			{ name = "WaspQueen_GiftNeon",      color = QUEEN_CUSHION, mat = Enum.Material.SmoothPlastic, trans = 0 },
			{ name = "WaspQueen_KoenigsGlut",   color = QUEEN_CROWN,   mat = Enum.Material.Neon,          trans = 0 },
			{ name = "WingL",                   color = QUEEN_WING,    mat = Enum.Material.Glass,         trans = 0.35 },
			{ name = "WingR",                   color = QUEEN_WING,    mat = Enum.Material.Glass,         trans = 0.35 },
			{ name = "WingBackL",               color = QUEEN_WING,    mat = Enum.Material.Glass,         trans = 0.42 },
			{ name = "WingBackR",               color = QUEEN_WING,    mat = Enum.Material.Glass,         trans = 0.42 },
		}
		local refPos = meshChitin.Position
		for _, spec in meshSpecs do
			local src = bossFolder:FindFirstChild(spec.name, true)
			if src and src:IsA("BasePart") then
				local clone = src:Clone()
				clone.Name         = spec.name
				clone.Color        = spec.color
				clone.Material     = spec.mat
				clone.Transparency = spec.trans
				clone.Anchored     = true
				clone.CanCollide   = false
				clone.CanQuery     = false
				clone.CanTouch     = false
				clone.CastShadow   = false
				local rel = src.Position - refPos
				clone.CFrame = pose * CFrame.new(rel.X, rel.Y, rel.Z) * src.CFrame.Rotation
				clone.Parent = model
			end
		end
		piece({ Name = "Head", Transparency = 1, Size = Vector3.new(2, 2, 2) * s }, CFrame.new(0, 1.2 * s, -3.45 * s))
		model.WorldPivot = pose
		model.Parent = parent
		return model
	end

	local function limb(name: string, p0: Vector3, p1: Vector3, radius: number, color: Color3, mat: Enum.Material)
		local v0 = p0 * s
		local v1 = p1 * s
		local mid = (v0 + v1) * 0.5
		local len = (v1 - v0).Magnitude
		if len < 1e-3 then return end
		local look = CFrame.lookAt(mid, v1) * CFrame.Angles(0, math.rad(90), 0)
		piece({
			Name = name,
			Shape = Enum.PartType.Cylinder,
			Material = mat,
			Color = color,
			Size = Vector3.new(len, radius * 2 * s, radius * 2 * s),
		}, look)
	end

	-- 2. KUSCHELIGER CHIBI-THORAX, FLAUSCHIGER KOENIGSKRAGEN & HERZ-BROSCHE
	piece({ Name = "Thorax", Shape = Enum.PartType.Ball, Material = Enum.Material.SmoothPlastic,
		Color = QUEEN_PLUM, Size = Vector3.new(5.1, 4.9, 5.5) * s }, CFrame.new(0, 0.45 * s, 0))
	piece({ Name = "ThoraxGoldBelt", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Metal,
		Color = QUEEN_GOLD, Size = Vector3.new(0.42, 4.1, 4.1) * s },
		CFrame.new(0, 0.28 * s, 1.95 * s) * CFrame.Angles(0, math.rad(90), 0))

	-- Flauschiger Creme-Koenigskragen aus runden Pluesch-Bommeln rund um den Hals
	for i = 0, 9 do
		local ra = i * (math.pi * 2 / 10)
		local px = math.cos(ra) * 2.15
		local py = 0.72 + math.sin(ra) * 2.05
		local pz = -1.95 + math.sin(ra) * 0.25
		piece({ Name = "NeckFluff" .. i, Shape = Enum.PartType.Ball, Material = Enum.Material.SmoothPlastic,
			Color = QUEEN_CREAM, Size = Vector3.new(1.55, 1.55, 1.35) * s }, CFrame.new(px * s, py * s, pz * s))
	end

	-- Goldene Koenigs-Brosche vorne am Kragen
	piece({ Name = "BroochGold", Shape = Enum.PartType.Ball, Material = Enum.Material.Metal,
		Color = QUEEN_GOLD, Size = Vector3.new(1.35, 1.35, 0.70) * s }, CFrame.new(0, -0.85 * s, -2.65 * s))
	piece({ Name = "BroochGem", Shape = Enum.PartType.Ball, Material = Enum.Material.Neon,
		Color = QUEEN_CUSHION, Size = Vector3.new(0.88, 0.88, 0.50) * s }, CFrame.new(0, -0.92 * s, -2.85 * s))

	-- 3. KUGELIGER HUMMEL-BAUCH (Abdomen) & SUESSER RUNDER MINI-STACHEL
	piece({ Name = "Abdomen", Shape = Enum.PartType.Ball, Material = Enum.Material.SmoothPlastic,
		Color = QUEEN_YELLOW, Size = Vector3.new(7.1, 6.9, 8.9) * s },
		CFrame.new(0, 0.10 * s, 5.85 * s) * CFrame.Angles(math.rad(-6), 0, 0))

	local tummyRings = {
		{ name = "Stripe1",   z = 3.85, y = 0.28,  d = 6.2, w = 1.05, col = QUEEN_PLUM, mat = Enum.Material.SmoothPlastic },
		{ name = "GoldBand1", z = 4.48, y = 0.22,  d = 6.6, w = 0.32, col = QUEEN_GOLD, mat = Enum.Material.Metal },
		{ name = "Stripe2",   z = 5.85, y = 0.10,  d = 7.2, w = 1.15, col = QUEEN_PLUM, mat = Enum.Material.SmoothPlastic },
		{ name = "GoldBand2", z = 6.55, y = 0.02,  d = 6.9, w = 0.32, col = QUEEN_GOLD, mat = Enum.Material.Metal },
		{ name = "Stripe3",   z = 7.85, y = -0.12, d = 6.0, w = 1.05, col = QUEEN_PLUM, mat = Enum.Material.SmoothPlastic },
		{ name = "GoldBand3", z = 8.48, y = -0.18, d = 5.0, w = 0.30, col = QUEEN_GOLD, mat = Enum.Material.Metal },
	}
	for _, r in tummyRings do
		piece({ Name = r.name, Shape = Enum.PartType.Cylinder, Material = r.mat,
			Color = r.col, Size = Vector3.new(r.w, r.d, r.d) * s },
			CFrame.new(0, r.y * s, r.z * s) * CFrame.Angles(math.rad(-6), math.rad(90), 0))
	end

	-- Harmloser, runder goldener Stachel-Knopf am Po
	piece({ Name = "StingerButton", Shape = Enum.PartType.Ball, Material = Enum.Material.Metal,
		Color = QUEEN_GOLD, Size = Vector3.new(1.9, 1.9, 1.5) * s }, CFrame.new(0, -0.35 * s, 10.15 * s))
	limb("Stinger", Vector3.new(0, -0.38, 10.45), Vector3.new(0, -0.52, 11.55), 0.38, QUEEN_CROWN, Enum.Material.Neon)
	piece({ Name = "StingerBall", Shape = Enum.PartType.Ball, Material = Enum.Material.Neon,
		Color = QUEEN_CROWN, Size = Vector3.new(0.55, 0.55, 0.55) * s }, CFrame.new(0, -0.53 * s, 11.62 * s))

	-- 4. GROSSER RUNDER CHIBI-KOPF (Head), KULLERAUGEN, PAUSBAECKCHEN & BOMMEL-FUEHLER
	piece({ Name = "Head", Shape = Enum.PartType.Ball, Material = Enum.Material.SmoothPlastic,
		Color = QUEEN_YELLOW, Size = Vector3.new(5.1, 4.7, 4.5) * s }, CFrame.new(0, 0.95 * s, -3.45 * s))

	for _, side in { -1, 1 } do
		local tag = if side < 0 then "L" else "R"
		-- Grosse dunkle Kulleraugen
		piece({ Name = "Eye" .. tag, Shape = Enum.PartType.Ball, Material = Enum.Material.SmoothPlastic,
			Color = QUEEN_EYE_DARK, Size = Vector3.new(1.36, 1.64, 0.70) * s },
			CFrame.new(side * 1.15 * s, 1.08 * s, -5.32 * s) * CFrame.Angles(math.rad(8), math.rad(side * -16), math.rad(side * -12)))
		-- Zwei weisse Glanzlichter pro Auge (macht den Blick sofort lieb & lebendig)
		piece({ Name = "EyeShineBig" .. tag, Shape = Enum.PartType.Ball, Material = Enum.Material.Neon,
			Color = QUEEN_SHINE, Size = Vector3.new(0.44, 0.48, 0.24) * s },
			CFrame.new(side * 0.98 * s, 1.38 * s, -5.62 * s))
		piece({ Name = "EyeShineSmall" .. tag, Shape = Enum.PartType.Ball, Material = Enum.Material.Neon,
			Color = QUEEN_SHINE, Size = Vector3.new(0.22, 0.22, 0.16) * s },
			CFrame.new(side * 1.32 * s, 0.82 * s, -5.58 * s))

		-- Sanfte Augenbrauen
		limb("Brow" .. tag, Vector3.new(side * 0.65, 2.02, -5.42), Vector3.new(side * 1.55, 1.92, -5.12), 0.12, QUEEN_PLUM, Enum.Material.SmoothPlastic)

		-- Rosa Pausbaeckchen
		piece({ Name = "Blush" .. tag, Shape = Enum.PartType.Ball, Material = Enum.Material.SmoothPlastic,
			Color = QUEEN_BLUSH, Size = Vector3.new(0.96, 0.60, 0.44) * s },
			CFrame.new(side * 1.62 * s, 0.38 * s, -5.05 * s) * CFrame.Angles(0, math.rad(side * -24), 0))

		-- Kleines freundliches Laecheln (:3)
		limb("Smile" .. tag, Vector3.new(0, 0.38, -5.62), Vector3.new(side * 0.38, 0.50, -5.55), 0.08, QUEEN_PLUM, Enum.Material.SmoothPlastic)

		-- Runde Bommelfuehler
		local a0 = Vector3.new(side * 0.75, 2.85, -4.25)
		local a1 = Vector3.new(side * 1.35, 3.85, -4.65)
		local a2 = Vector3.new(side * 1.95, 4.45, -4.45)
		limb("Antenna1" .. tag, a0, a1, 0.15, QUEEN_PLUM, Enum.Material.SmoothPlastic)
		limb("Antenna2" .. tag, a1, a2, 0.13, QUEEN_PLUM, Enum.Material.SmoothPlastic)
		piece({ Name = "AntennaPom" .. tag, Shape = Enum.PartType.Ball, Material = Enum.Material.Neon,
			Color = QUEEN_CROWN, Size = Vector3.new(0.84, 0.84, 0.84) * s }, CFrame.new(a2 * s))
	end

	-- 5. SUESSES KOENIGSKROENCHEN MIT SAMTKISSEN & LEUCHTPERLEN
	local cz, cy = -3.35, 3.15
	piece({ Name = "Crown", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Metal,
		Color = QUEEN_GOLD, Size = Vector3.new(0.75, 2.95, 2.95) * s },
		CFrame.new(0, (cy + 0.18) * s, cz * s) * CFrame.Angles(0, 0, math.rad(90)))
	piece({ Name = "CrownCushion", Shape = Enum.PartType.Ball, Material = Enum.Material.SmoothPlastic,
		Color = QUEEN_CUSHION, Size = Vector3.new(2.35, 1.30, 2.35) * s },
		CFrame.new(0, (cy + 0.45) * s, cz * s))
	piece({ Name = "CrownTopGem", Shape = Enum.PartType.Ball, Material = Enum.Material.Neon,
		Color = QUEEN_CROWN, Size = Vector3.new(0.76, 0.90, 0.76) * s },
		CFrame.new(0, (cy + 1.15) * s, cz * s))

	for i = 0, 5 do
		local ca = i * (math.pi / 3)
		local sx0, sz0 = math.sin(ca) * 1.42, cz - math.cos(ca) * 1.42
		local sx1, sz1 = math.sin(ca) * 1.62, cz - math.cos(ca) * 1.62
		local sh = if i % 2 == 0 then 0.85 else 0.62
		limb("CrownPoint" .. i, Vector3.new(sx0, cy + 0.42, sz0), Vector3.new(sx1, cy + 0.42 + sh, sz1), 0.18, QUEEN_GOLD, Enum.Material.Metal)
		piece({ Name = "CrownPearl" .. i, Shape = Enum.PartType.Ball, Material = Enum.Material.Neon,
			Color = if i % 2 == 1 then QUEEN_SHINE else QUEEN_CROWN,
			Size = Vector3.new(0.44, 0.44, 0.44) * s }, CFrame.new(sx1 * s, (cy + 0.48 + sh) * s, sz1 * s))
	end

	-- 6. VIER SUESSE KURZE STUMMELPFOTEN MIT GOLDSCHUHEN
	for _, paw in { { tag = "F", x = 1.55, z = -0.85, y = -1.75 }, { tag = "B", x = 1.65, z = 1.05, y = -1.85 } } do
		for _, side in { -1, 1 } do
			local nameTag = paw.tag .. (if side < 0 then "L" else "R")
			local hip  = Vector3.new(side * paw.x * 0.82, paw.y + 0.85, paw.z)
			local foot = Vector3.new(side * paw.x,        paw.y,        paw.z)
			limb("PawLeg" .. nameTag, hip, foot, 0.44, QUEEN_PLUM, Enum.Material.SmoothPlastic)
			piece({ Name = "PawShoe" .. nameTag, Shape = Enum.PartType.Ball, Material = Enum.Material.Metal,
				Color = QUEEN_GOLD, Size = Vector3.new(1.04, 0.84, 1.30) * s },
				CFrame.new(side * paw.x * s, (paw.y - 0.15) * s, (paw.z - 0.15) * s))
		end
	end

	-- 7. RUNDE FEEN-/HONIGFLUEGEL (WingL/WingR & WingBackL/WingBackR)
	piece({ Name = "WingL", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Glass, Transparency = 0.35,
		Color = QUEEN_WING, Size = Vector3.new(0.22, 7.8, 7.8) * s },
		CFrame.new(-5.0 * s, 3.0 * s, 0.6 * s) * CFrame.Angles(0, math.rad(-14), math.rad(20)))
	piece({ Name = "WingR", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Glass, Transparency = 0.35,
		Color = QUEEN_WING, Size = Vector3.new(0.22, 7.8, 7.8) * s },
		CFrame.new(5.0 * s, 3.0 * s, 0.6 * s) * CFrame.Angles(0, math.rad(14), math.rad(-20)))

	piece({ Name = "WingBackL", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Glass, Transparency = 0.42,
		Color = QUEEN_WING, Size = Vector3.new(0.18, 5.4, 5.4) * s },
		CFrame.new(-3.8 * s, 2.1 * s, 2.2 * s) * CFrame.Angles(0, math.rad(-24), math.rad(12)))
	piece({ Name = "WingBackR", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Glass, Transparency = 0.42,
		Color = QUEEN_WING, Size = Vector3.new(0.18, 5.4, 5.4) * s },
		CFrame.new(3.8 * s, 2.1 * s, 2.2 * s) * CFrame.Angles(0, math.rad(24), math.rad(-12)))

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

				-- Sammel-Update 05.10. (Paket 6.2): Boss-Sieg merken (besonderer
				-- Meilenstein, Zaehler stats.bossVictories).
				reward.bossVictory = victory
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
