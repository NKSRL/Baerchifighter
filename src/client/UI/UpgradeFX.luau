--!strict
-- UpgradeFX.luau
-- StarterPlayerScripts/UI/UpgradeFX.luau
--
-- Einzige Zustaendigkeit:
--   - Der Erfolgs-Moment nach einem BESTAETIGTEN Ausbau (Paket G, 08.10.):
--     das Gebaeude springt kurz auf, Funken in seiner Farbe steigen auf,
--     "Level 7 ➜ 8" schwebt hoch, ein kurzer Klang, und der bezahlte Betrag
--     fliegt aus der Gummy-Pille zum Gebaeude (Feedback.spend). Beim
--     Look-Wechsel (Level 10/20/30/45/60) die grosse Variante.
--
-- Ausgeloest wird NUR aus dem Datenstand (ClientState): steigt das Level des
-- Honig-Brunnens bzw. eines Gebaeudes oder des Recyclers, hat der Server den
-- Kauf schon gebucht. Nie spekulativ beim Tastendruck — ein abgelehnter Kauf
-- (zu wenig Gummies) zeigt nur die Ablehnung (ActionFailed), keinen Effekt.
-- Egal ob ueber den Prompt (E) oder ein Menue ausgebaut wurde: es sieht
-- gleich aus.
--
-- Leistung: EINE Heartbeat-Schleife fuer alle laufenden Effekte, kein Thread
-- und kein Tween pro Effekt; je Effekt ein unsichtbarer Anker-Teil mit EINEM
-- Emitter und EINEM BillboardGui, nach <= 1,2 s wieder weg. Die Gebaeude-Teile
-- werden nur lokal skaliert und danach exakt auf ihren Stand zurueckgesetzt.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types            = require(ReplicatedStorage.Network.Types)
local Loc              = require(ReplicatedStorage.Localization.Loc)
local FeedbackConfig   = require(ReplicatedStorage.Config.FeedbackConfig)
local BuildingBehavior = require(ReplicatedStorage.Config.BuildingBehavior)
local CombConfig       = require(ReplicatedStorage.Config.CombConfig)
local MapConfig        = require(ReplicatedStorage.Config.MapConfig)

local Theme       = require(script.Parent.Theme)
local Kit         = require(script.Parent.Kit)
local Feedback    = require(script.Parent.Feedback)
local ClientState = require(script.Parent.Parent.Controllers.ClientState)

local UpgradeFX = {}

local FX = FeedbackConfig.UPGRADE_FX
local OWNER_ATTRIBUTE = "PlotOwner"
local RECYCLER_KEY = "Recycler"
local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

type PartState = { part: BasePart, cframe: CFrame, size: Vector3 }

type Job = {
	key      : string,       -- BuildingId oder "Recycler"
	from     : number,
	to       : number,
	big      : boolean,      -- Look-Wechsel
	t0       : number,       -- Start (os.clock); bis dahin wird auf den Neubau gewartet
	waitLook : number?,      -- Look, auf den gewartet wird (nil = sofort)
	started  : boolean,
	parts    : { PartState },
	origin   : CFrame,
	anchor   : BasePart?,
	label    : TextLabel?,
	gui      : BillboardGui?,
	popDone  : boolean,
}

local _jobs: { Job } = {}
local _last: { [string]: number }? = nil

--------------------------------------------------------------------------------
-- Welt
--------------------------------------------------------------------------------

local function ownPlot(): Instance?
	local userId = Players.LocalPlayer.UserId
	for _, child in Workspace:GetChildren() do
		if child:IsA("Model") and child:GetAttribute(OWNER_ATTRIBUTE) == userId then
			return child
		end
	end
	return nil
end

local function findBody(key: string): BasePart?
	local plot = ownPlot()
	if not plot then return nil end
	local name = if key == RECYCLER_KEY then CombConfig.RECYCLER_NAME else key
	local body = plot:FindFirstChild(name)
	return if body and body:IsA("BasePart") then body else nil
end

local function colorFor(key: string): Color3
	if key == RECYCLER_KEY then
		return Color3.fromRGB(120, 230, 140)
	end
	local def = MapConfig.BUILDING_OFFSETS[key]
	return if def then def.color else Theme.COLORS.goldGummy
end

--------------------------------------------------------------------------------
-- Effekt-Teile
--------------------------------------------------------------------------------

local function easeOut(t: number): number
	return 1 - (1 - t) * (1 - t)
end

-- Skalierung ueber die Zeit: schnell auf `peak`, dann gedaempft zurueck
-- (kurzes Unterschwingen wie eine Feder).
local function popScale(t: number, peak: number): number
	if t <= 0 then return 1 end
	if t >= 1 then return 1 end
	if t < 0.35 then
		return 1 + (peak - 1) * easeOut(t / 0.35)
	end
	local u = (t - 0.35) / 0.65
	return 1 + (peak - 1) * math.cos(u * math.pi * 1.5) * (1 - u)
end

local function startJob(job: Job, body: BasePart)
	job.started = true
	job.t0 = os.clock()

	-- Teile merken (nur die Deko, nicht der unsichtbare Koerper)
	local top = body.Position.Y
	for _, child in body:GetDescendants() do
		if child:IsA("BasePart") then
			table.insert(job.parts, { part = child, cframe = child.CFrame, size = child.Size })
			top = math.max(top, child.Position.Y + child.Size.Y * 0.5)
		end
	end
	job.origin = body.CFrame * CFrame.new(0, -body.Size.Y * 0.5, 0)

	-- Anker oben auf dem Gebaeude: Funken + Zahl
	local anchor = Instance.new("Part")
	anchor.Name         = "UpgradeFxAnchor"
	anchor.Anchored     = true
	anchor.CanCollide   = false
	anchor.CanQuery     = false
	anchor.CanTouch     = false
	anchor.CastShadow   = false
	anchor.Transparency = 1
	anchor.Size         = Vector3.new(1, 1, 1)
	anchor.CFrame       = CFrame.new(body.Position.X, top + 0.5, body.Position.Z)
	anchor.Parent       = Workspace.CurrentCamera or Workspace
	job.anchor = anchor

	local color = colorFor(job.key)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture       = SPARK_TEXTURE
	emitter.Color         = ColorSequence.new(Theme.shade(color, 0.35), color)
	emitter.LightEmission = 1
	emitter.Size          = NumberSequence.new({
		NumberSequenceKeypoint.new(0, if job.big then 1.4 else 1.0),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency  = NumberSequence.new(0.1, 1)
	emitter.Lifetime      = NumberRange.new(FX.SPARK_LIFETIME * 0.6, FX.SPARK_LIFETIME)
	emitter.Speed         = NumberRange.new(8, if job.big then 22 else 15)
	emitter.SpreadAngle   = Vector2.new(55, 55)
	emitter.Acceleration  = Vector3.new(0, 6, 0)
	emitter.Drag          = 3
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Rate          = 0
	emitter.Parent        = anchor
	emitter:Emit(if job.big then FX.SPARKS_BIG else FX.SPARKS)

	local size = if job.big then FX.NUMBER_SIZE_BIG else FX.NUMBER_SIZE
	local gui = Instance.new("BillboardGui")
	gui.Name           = "UpgradeFxNumber"
	gui.Size           = UDim2.fromOffset(size.X, size.Y)
	gui.AlwaysOnTop    = true
	gui.LightInfluence = 0
	gui.StudsOffset    = Vector3.new(0, 1, 0)
	gui.Adornee        = anchor
	gui.Parent         = anchor
	job.gui = gui

	local label = Theme.label("Text", gui, "")
	label.Size = UDim2.fromScale(1, 1)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextColor3 = if job.big then Theme.COLORS.goldGummy else Color3.new(1, 1, 1)
	local text = Loc.t("ui.upgrade.fx_level", { from = job.from, to = job.to })
	if job.big then
		text = text .. "\n" .. Loc.t("ui.upgrade.fx_look")
		label.TextWrapped = true
		local limit = label:FindFirstChildOfClass("UITextSizeConstraint")
		if limit then limit.MaxTextSize = 44 end
	end
	label.Text = text
	Theme.outlineText(label, 3)
	job.label = label

	Kit.playSound(if job.big then "lookUp" else "upgrade")

	-- Bezahlter Betrag fliegt aus der Pille zum Gebaeude (Mechanik aus Paket 1)
	local cost = 0
	if job.key == RECYCLER_KEY then
		local def = CombConfig.getUpgradeCost(job.to)
		cost = if def then def.gummies else 0
	else
		local def = BuildingBehavior.getUpgrade(job.key :: any, job.to)
		cost = if def then def.costGummies else 0
	end
	if cost > 0 then
		Feedback.spend("gummies", cost, anchor.Position)
	end
end

local function finishJob(job: Job)
	for _, state in job.parts do
		if state.part.Parent then
			state.part.Size   = state.size
			state.part.CFrame = state.cframe
		end
	end
	table.clear(job.parts)
	if job.anchor then
		job.anchor:Destroy()
		job.anchor = nil
	end
end

local function step()
	if #_jobs == 0 then return end
	local now = os.clock()
	for i = #_jobs, 1, -1 do
		local job = _jobs[i]
		if not job.started then
			-- Look-Wechsel: der Server baut das Gebaeude neu. Erst auf den
			-- neuen Koerper warten, sonst springt der alte, gleich verschwindende.
			local body = findBody(job.key)
			local ready = body ~= nil and (job.waitLook == nil or body:GetAttribute("Look") == job.waitLook)
			local late = now - job.t0 > FX.LOOK_WAIT
			if body and (ready or late) then
				startJob(job, body)
			elseif late then
				table.remove(_jobs, i)
			end
			continue
		end

		local t = now - job.t0

		-- 1. Aufspringen und zurueckfedern
		if not job.popDone then
			local tp = math.clamp(t / FX.POP_SECONDS, 0, 1)
			local s = popScale(tp, if job.big then FX.POP_SCALE_BIG else FX.POP_SCALE)
			for _, state in job.parts do
				if state.part.Parent then
					local rel = job.origin:ToObjectSpace(state.cframe)
					state.part.Size   = state.size * s
					state.part.CFrame = job.origin * CFrame.new(rel.Position * s) * rel.Rotation
				end
			end
			if tp >= 1 then
				job.popDone = true
				for _, state in job.parts do
					if state.part.Parent then
						state.part.Size   = state.size
						state.part.CFrame = state.cframe
					end
				end
			end
		end

		-- 2. Zahl steigt auf und blendet aus
		local tn = math.clamp(t / FX.NUMBER_SECONDS, 0, 1)
		local gui, label = job.gui, job.label
		if gui and label then
			gui.StudsOffset = Vector3.new(0, 1 + FX.NUMBER_RISE * easeOut(tn), 0)
			local fade = math.max(0, (tn - 0.6) / 0.4)
			label.TextTransparency = fade
			local stroke = label:FindFirstChildOfClass("UIStroke")
			if stroke then stroke.Transparency = fade end
			label.TextStrokeTransparency = fade
		end

		if tn >= 1 and job.popDone then
			finishJob(job)
			table.remove(_jobs, i)
		end
	end
end

--------------------------------------------------------------------------------
-- Ausloesen
--------------------------------------------------------------------------------

-- Oeffentlich (auch fuer Tests/Debug): Effekt fuer `key` von Level `from` auf `to`.
function UpgradeFX.play(key: string, from: number, to: number)
	local big = BuildingBehavior.getLook(to) > BuildingBehavior.getLook(from)
	-- Ein laufender Effekt am selben Gebaeude wird beendet (schnelles
	-- Doppelt-Ausbauen ueber das Menue): nie zwei Skalierungen uebereinander.
	for i = #_jobs, 1, -1 do
		if _jobs[i].key == key then
			finishJob(_jobs[i])
			table.remove(_jobs, i)
		end
	end
	table.insert(_jobs, {
		key = key, from = from, to = to, big = big,
		t0 = os.clock(), waitLook = if big then BuildingBehavior.getLook(to) else nil,
		started = false, parts = {}, origin = CFrame.identity, popDone = false,
	})
end

local function levelsOf(data: Types.PlayerDataUpdate): { [string]: number }
	local levels: { [string]: number } = {}
	for id, building in data.island.buildings do
		levels[id :: string] = building.level
	end
	levels[RECYCLER_KEY] = data.island.recycler.level
	return levels
end

local function onData(data: Types.PlayerDataUpdate)
	local now = levelsOf(data)
	local last = _last
	_last = now
	if not last then return end   -- erster Stand nach dem Join
	for key, level in now do
		local before = last[key]
		-- Nur ein echter Ausbau: genau +1 (ein Rebirth senkt, ein
		-- Debug-Sprung um viele Level ist keiner).
		if before and level == before + 1 then
			UpgradeFX.play(key, before, level)
		end
	end
end

function UpgradeFX.init()
	ClientState.onChanged(onData)
	RunService.Heartbeat:Connect(step)
	print("[UpgradeFX] Initialisiert")
end

return UpgradeFX
