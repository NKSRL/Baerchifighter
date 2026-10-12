--!strict
-- EggMerchantService.luau
-- ServerScriptService/Services/EggMerchantService.luau
--
-- Einzige Zustaendigkeit:
--   - Den versteckten Basis-Ei-Haendler in der Welt aufstellen und Kaeufe
--     dort entgegennehmen (inklusive Entfernungspruefung).
--
-- Seit v12 ist das die EINZIGE Stelle, an der man ein Ei kaufen kann. Kein
-- Menue-Eintrag, kein HUD-Hinweis, kein Marker — wer den Stand findet, kann
-- hier fuer Gummies ein Basis-Ei holen. Lage und Preis stehen in
-- EggConfig.MERCHANT.
--
-- Warum ein serverseitiger ProximityPrompt statt eines eigenen Remotes:
-- Triggered feuert direkt auf dem Server mit dem ausloesenden Spieler. Es
-- gibt also keinen Remote, den ein Skript von ueberall aufrufen koennte, und
-- die Entfernung wird hier trotzdem noch einmal selbst geprueft (Roblox'
-- eigene Pruefung ist nicht dokumentiert genug, um sich allein darauf zu
-- verlassen).

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local EggConfig = require(ReplicatedStorage.Config.EggConfig)
local MapConfig = require(ReplicatedStorage.Config.MapConfig)
local Remotes   = require(ReplicatedStorage.Network.Remotes)
local FeatureFlags = require(ReplicatedStorage.Config.FeatureFlags)  -- HBB Paket 5
local Loc       = require(ReplicatedStorage.Localization.Loc)

local EggService = require(ServerScriptService.Services.EggService)

local EggMerchantService = {}

local MODEL_NAME = "EggMerchant"

-- Gegen Doppel-Ausloesen (zwei schnelle E-Druecke): ein Kauf pro Spieler und
-- so vielen Sekunden. Kein Balancing-Wert, nur Entprellung.
local BUY_COOLDOWN = 0.5
local _lastBuy: { [Player]: number } = {}

local WOOD      = Color3.fromRGB(150, 105, 62)
local WOOD_DARK = Color3.fromRGB(112, 76, 44)
local CLOTH_A   = Color3.fromRGB(235, 228, 205)
local CLOTH_B   = Color3.fromRGB(196, 92, 82)

local _counter: BasePart? = nil

local function newPart(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name       = name
	part.Size       = size
	part.CFrame     = cframe
	part.Color      = color
	part.Material   = Enum.Material.Wood
	part.Anchored   = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent     = parent
	return part
end

-- Wo der Stand steht: auf dem Ring um die Weltmitte, mit der Theke zur Mitte.
local function standCFrame(): CFrame
	local merchant = EggConfig.MERCHANT
	-- HBB Paket 5: sichtbarer Platz am Weg zum Event-Pit
	local place = if FeatureFlags.isOn("MAP_V2_MERCHANT") then EggConfig.MERCHANT_V2 else merchant
	local angle    = math.rad(place.angleDegrees)
	local position = Vector3.new(
		MapConfig.CENTER.X + place.radius * math.cos(angle),
		MapConfig.PLATFORM_TOP_Y,
		MapConfig.CENTER.Z + place.radius * math.sin(angle)
	)
	return CFrame.lookAt(position, Vector3.new(MapConfig.CENTER.X, position.Y, MapConfig.CENTER.Z))
end

-- Ein kleiner Marktstand: Theke, zwei Pfosten, gestreiftes Dach, ein Ei auf
-- der Theke. Bewusst klein und unscheinbar (gleiche Holzfarben wie Zaeune und
-- Stege), damit er zwischen den Blumen am Inselrand nicht auffaellt.
local function buildStand(): BasePart
	local existing = workspace:FindFirstChild(MODEL_NAME)
	if existing then existing:Destroy() end

	local model = Instance.new("Model")
	model.Name = MODEL_NAME

	local base = standCFrame()
	local function at(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x, y, z)
	end

	local counter = newPart("Counter", Vector3.new(6, 2.6, 2.4), at(0, 1.3, 0), WOOD, model)
	newPart("CounterTop", Vector3.new(6.4, 0.3, 2.8), at(0, 2.75, 0), WOOD_DARK, model)

	newPart("PostL", Vector3.new(0.4, 6.2, 0.4), at(-2.9, 3.1, 1.0), WOOD_DARK, model)
	newPart("PostR", Vector3.new(0.4, 6.2, 0.4), at( 2.9, 3.1, 1.0), WOOD_DARK, model)

	-- Gestreiftes Dach aus vier Bahnen, leicht nach vorn geneigt
	for index = 0, 3 do
		local stripe = newPart(
			"Awning" .. index,
			Vector3.new(1.6, 0.2, 3.4),
			at(-2.4 + index * 1.6, 6.1, 0.2) * CFrame.Angles(math.rad(-12), 0, 0),
			if index % 2 == 0 then CLOTH_A else CLOTH_B,
			model
		)
		stripe.Material = Enum.Material.Fabric
	end

	-- Das Ei auf der Theke, in der Farbe des Basis-Eis
	local egg = newPart("Egg", Vector3.new(1.4, 1.9, 1.4), at(0, 3.85, -0.2), EggConfig.data[EggConfig.MERCHANT.eggType].color, model)
	egg.Shape    = Enum.PartType.Ball
	egg.Material = Enum.Material.SmoothPlastic
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale    = Vector3.new(1, 1, 1)
	mesh.Parent   = egg
	egg.CanCollide = false

	-- HBB Paket 5: Ei-Schild ueber dem Stand (Billboard mit Bild, kein Text),
	-- damit man den Haendler von weitem erkennt. Keine Teile, kein Licht.
	if FeatureFlags.isOn("MAP_V2_MERCHANT") then
		local sign = EggConfig.MERCHANT_V2
		local board = Instance.new("BillboardGui")
		board.Name = "EggSign"
		board.Size = UDim2.new(sign.signSize, 0, sign.signSize, 0)
		board.StudsOffset = Vector3.new(0, sign.signHeight - 1.3, 0)
		board.LightInfluence = 0
		board.MaxDistance = 400
		board.Adornee = counter
		board.Parent = counter
		local image = Instance.new("ImageLabel")
		image.BackgroundTransparency = 1
		image.Size = UDim2.fromScale(1, 1)
		image.Image = sign.signImage
		image.ScaleType = Enum.ScaleType.Fit
		image.Parent = board
	end

	model.PrimaryPart = counter
	model.Parent = workspace

	return counter
end

local function onTriggered(player: Player)
	local counter = _counter
	if not counter then return end

	local now = os.clock()
	if now - (_lastBuy[player] or 0) < BUY_COOLDOWN then
		return
	end
	_lastBuy[player] = now

	-- Eigene Entfernungspruefung: nur wer wirklich am Stand steht, kauft.
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then return end

	if (root.Position - counter.Position).Magnitude > EggConfig.MERCHANT.maxBuyDistance then
		Remotes.ActionFailed:FireClient(player, "BuyBasicEgg", Loc.msg("err.merchant_far"))
		return
	end

	if EggService.buyFromMerchant(player) then
		-- Sammel-Update 2.3 ("Animation groesser, wenn man Ei kauft"): das
		-- gekaufte Ei wird sofort geoeffnet — der Client spielt dafuer die
		-- grosse Schluepf-Animation (HatchResultReceived ohne offene Anfrage
		-- startet sie direkt, siehe HatchAnimation.deliver). Klappt das
		-- Oeffnen nicht, liegt das Ei im Lager und es gibt den alten Toast.
		if EggService.openEgg(player, EggConfig.MERCHANT.eggType) then
			return
		end
		-- Kurze Bestaetigung ueber den bestehenden Ei-Eingang (Toast "+1 Basis-Ei")
		Remotes.EggCollectedReceived:FireClient(player, {
			eggUid  = "merchant",
			eggType = EggConfig.MERCHANT.eggType,
			inStock = -1,   -- -1 = Anzeige ohne Lagerzahl
		})
	end
end

function EggMerchantService.init()
	local counter = buildStand()
	_counter = counter

	local merchant = EggConfig.MERCHANT
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name                  = "BuyPrompt"
	-- Sammel-Update 2.4: der Prompt ist fuer alle gleich (Server-Objekt) —
	-- deshalb sprachneutral: Ei + Preis.
	prompt.ActionText            = string.format("🥚 +1  (%d G)", merchant.priceGummies)
	prompt.ObjectText            = "🥚"
	prompt.MaxActivationDistance = merchant.promptDistance
	prompt.RequiresLineOfSight   = false
	prompt.HoldDuration          = 0
	prompt.Parent                = counter

	prompt.Triggered:Connect(onTriggered)

	Players.PlayerRemoving:Connect(function(player)
		_lastBuy[player] = nil
	end)

	print("[EggMerchantService] Initialisiert | Stand bei", counter.Position)
end

return EggMerchantService
