--!strict
-- RecyclerBuilder.luau
-- ServerScriptService/Util/MapBuild/RecyclerBuilder.luau
--
-- Einzige Zustaendigkeit:
--   - Den Waben-Recycler auf dem Plot bauen und sein Schild/seine Lampe
--     beschriften.
--
-- Wie ein Gebaeude (siehe PlotBuilder.buildBuilding): ein unsichtbarer Koerper,
-- der Name, Attribute und Schild traegt, plus die deklarative Deko aus
-- CombConfig.RECYCLER_DECOR und (v15) den Zusaetzen seines Looks
-- (CombConfig.getDecor). Der Look steht als Attribut "Look" am Koerper. Der Koerper heisst "Recycler"; der Client
-- (CombController) haengt daran den Ausbau-Prompt, aber nur am eigenen Plot.
--
-- Teil von MapService: nur MapService benutzt dieses Modul. Es aendert keine
-- Spielerdaten.

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CombConfig = require(ReplicatedStorage.Config.CombConfig)
local FeatureFlags = require(ReplicatedStorage.Config.FeatureFlags)
local MapConfig  = require(ReplicatedStorage.Config.MapConfig)
local BuildingBehavior = require(ReplicatedStorage.Config.BuildingBehavior)
local Types      = require(ReplicatedStorage.Network.Types)
local Loc       = require(ReplicatedStorage.Localization.Loc)
local WorldText = require(ReplicatedStorage.Localization.WorldText)

local MapParts = require(ServerScriptService.Util.MapBuild.MapParts)

local RecyclerBuilder = {}

-- Die Insel-Wiese liegt auf PLATFORM_TOP_Y, also auf dem Plot-Ursprung — NICHT
-- auf der Beet-Hoehe (die ist PLOT_SIZE.Y darueber). Der Recycler steht auf dem
-- Gras vor dem Beet, deshalb Boden = Ursprung plus die Karo-Hoehe, damit nichts
-- in den hellen Feldern versinkt.
local function groundOffset(): number
	return MapConfig.GRASS_HEIGHT
end

-- Schreibt Level, Warteschlange und Lampe. Billig; laeuft bei jeder Aenderung
-- der Warteschlange (einmal pro Sekunde, solange gearbeitet wird).
-- Groesse des Recycler-Modells: Grundfaktor plus Wachstum mit dem Ausbau
-- (bis +25 % auf Level 60). Das Modell hat seinen Pivot am Boden, es waechst
-- also nach oben und zur Seite.
local RECYCLER_BASE_SCALE = 1.4
local RECYCLER_GROWTH     = 0.25

function RecyclerBuilder.modelScale(level: number): number
	local max = CombConfig.RECYCLER_MAX_LEVEL
	local progress = (math.clamp(level, 1, max) - 1) / math.max(1, max - 1)
	return RECYCLER_BASE_SCALE * (1 + RECYCLER_GROWTH * progress)
end

local function fitModel(body: BasePart, level: number)
	local mesh = body:FindFirstChild("RecyclerModel")
	if not mesh or not mesh:IsA("Model") then return end
	local target = RecyclerBuilder.modelScale(level)
	if math.abs(mesh:GetScale() - target) < 0.001 then return end
	mesh:ScaleTo(target)
	local sign = body:FindFirstChild("Sign")
	if sign and sign:IsA("BillboardGui") then
		local height = select(2, mesh:GetBoundingBox()).Y
		sign.StudsOffset = Vector3.new(0, height - body.Size.Y * 0.5 + 2, 0)
	end
end

function RecyclerBuilder.writeState(body: BasePart, recycler: Types.RecyclerData)
	-- Attribute: der Client rechnet daraus Prompt-Text und Kosten selbst.
	body:SetAttribute("RecyclerLevel", recycler.level)
	fitModel(body, recycler.level)
	body:SetAttribute("RecyclerQueued", recycler.queued)

	local lamp = body:FindFirstChild("Lampe")
	if lamp and lamp:IsA("BasePart") then
		lamp.Color = if recycler.queued > 0 then CombConfig.LAMP_ACTIVE_COLOR else CombConfig.LAMP_IDLE_COLOR
	end

	local sign = body:FindFirstChild("Sign")
	if not sign or not sign:IsA("BillboardGui") then return end

	-- 12.10. (Playtest): das Schild zeigt IMMER nur den Geld-Multiplikator
	-- ("×12", sprachneutral) — sonst nichts. Ausgezahlt wird sofort, eine
	-- Warteschlange gibt es nicht mehr (CombConfig.INSTANT_PAYOUT).
	local title = sign:FindFirstChild("Title")
	local stock = sign:FindFirstChild("Stock")
	if CombConfig.INSTANT_PAYOUT then
		if title and title:IsA("TextLabel") then
			WorldText.set(title, CombConfig.formatMultiplier(recycler.level))
			title.TextColor3 = CombConfig.LAMP_ACTIVE_COLOR
			title.Size = UDim2.fromScale(1, 1)   -- die ganze Schildflaeche
		end
		if stock and stock:IsA("TextLabel") then
			stock.Visible = false
		end
		return
	end

	if title and title:IsA("TextLabel") then
		WorldText.set(title, Loc.msg("ui.world.sign_level", {
			name = Loc.msg("ui.recycler.name"), level = recycler.level,
		}))
	end

	if stock and stock:IsA("TextLabel") then
		if recycler.queued > 0 then
			stock.Text = string.format("⬡ %d", recycler.queued)   -- sprachneutral (2.4)
			stock.TextColor3 = CombConfig.LAMP_ACTIVE_COLOR
		else
			-- Sammel-Update 3.6: sprachneutral "⬡ = 12 G" (eine Wabe bringt so viel)
			stock.Text = string.format("⬡ = %d G", CombConfig.getPayPerUnit(recycler.level))
			stock.TextColor3 = Color3.fromRGB(235, 235, 235)
		end
	end
end

-- Baut den Recycler in das Plot-Model.
function RecyclerBuilder.build(plotModel: Model, slot: number, recycler: Types.RecyclerData)
	local plotCFrame = MapParts.plotCFrame(slot)
	local offset = CombConfig.RECYCLER_OFFSET
	local size   = CombConfig.RECYCLER_BODY_SIZE

	local ground = plotCFrame * CFrame.new(offset.X, groundOffset() + offset.Y, offset.Z)

	local body = MapParts.newPart(
		CombConfig.RECYCLER_NAME,
		size,
		ground * CFrame.new(0, size.Y * 0.5, 0),
		Color3.fromRGB(84, 178, 96),
		Enum.Material.SmoothPlastic
	)
	body.Transparency = 1
	body.CanCollide   = false
	body.Parent       = plotModel

	local look  = BuildingBehavior.getLook(recycler.level)
	local decor = CombConfig.getDecor(look)
	-- NEW_MODELS_V3: Mesh-Recycler aus ReplicatedStorage.Assets.Recyclers
	-- (Look 1..6 -> Stage 0..4). Haengt unter dem Koerper, wird mit ihm
	-- zerstoert; Aus oder Vorlage fehlt = alte Deko aus CombConfig.
	local newTop: number? = nil
	if FeatureFlags.isOn("NEW_MODELS_V3") then
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		local folder = assets and assets:FindFirstChild("Recyclers")
		local tpl = folder and folder:FindFirstChild("Recycler_Stage" .. math.clamp(look - 1, 0, 4))
		if tpl and tpl:IsA("Model") then
			local mesh = tpl:Clone()
			mesh.Name = "RecyclerModel"
			mesh:ScaleTo(RecyclerBuilder.modelScale(recycler.level))
			mesh:PivotTo(ground)
			mesh.Parent = body
			newTop = select(2, mesh:GetBoundingBox()).Y
		end
	end
	if not newTop then
		MapParts.buildDecor(body, ground, decor)
	end
	body:SetAttribute("Look", look)

	-- Schild ueber dem Trichter, auf die Hoehe der hoechsten Deko gesetzt (wie
	-- bei den Gebaeuden: so haengt es nach einer Formaenderung nicht falsch).
	local top = newTop or math.max(MapParts.decorHeight(decor), size.Y)

	local sign = Instance.new("BillboardGui")
	sign.Name        = "Sign"
	sign.Size        = UDim2.fromScale(9, 2.6)
	sign.StudsOffset = Vector3.new(0, top - size.Y * 0.5 + 2, 0)
	sign.AlwaysOnTop = true
	sign.MaxDistance = MapConfig.BUILDING_SIGN_DISTANCE
	sign.Adornee     = body
	sign.Parent      = body

	MapParts.newTextLabel("Title", sign, UDim2.fromScale(1, 0.5), UDim2.fromScale(0, 0))
	MapParts.newTextLabel("Stock", sign, UDim2.fromScale(1, 0.5), UDim2.fromScale(0, 0.5))

	RecyclerBuilder.writeState(body, recycler)
end

return RecyclerBuilder
