--!strict
-- EventFXController.luau
-- StarterPlayerScripts/Controllers/EventFXController.luau
--
-- Einzige Zustaendigkeit:
--   - Die bewegte Optik der lebendigen Events zeichnen: UFO-Patrouille,
--     fallende Abwurf-Kisten, Wespenkoenigin (samt HP-Leiste), Telegraphen der
--     Boss-Attacken, Himmel beim Boss — und Treffer am eigenen Charakter
--     ausfuehren und Event-Meldungen anzeigen.
--
-- Der Client rechnet und entscheidet nichts: Bahnen kommen aus
-- Modules/EventMotion (reine Funktionen der Serverzeit) und den Attributen,
-- die der Server einmal setzt (StartTime, Center, LandAt, Phase2At, HP).
-- Ob jemand getroffen ist, hat der Server entschieden (Remotes.EventHazardHit);
-- hier wird nur die Physik am EIGENEN Charakter ausgefuehrt, den der Client
-- besitzt.
--
-- PERFORMANCE: EIN RenderStepped fuer alles, ein PivotTo pro bewegtem Model
-- und Frame. Telegraphen sind wenige lokale Teile, die nach dem Treffer
-- verschwinden. Keine Lichter, keine Emitter.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")
local Lighting          = game:GetService("Lighting")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types       = require(ReplicatedStorage.Network.Types)
local Remotes     = require(ReplicatedStorage.Network.Remotes)
local EventMotion = require(ReplicatedStorage.Modules.EventMotion)
local Loc         = require(ReplicatedStorage.Localization.Loc)

local Theme = require(script.Parent.Parent.UI.Theme)
local Toast = require(script.Parent.Parent.UI.Toast)
-- HBB Paket 1: Meldungen nach FeedbackConfig verteilen (Icon/Moment/Toast)
local Notify   = require(script.Parent.Parent.UI.Notify)
local Feedback = require(script.Parent.Parent.UI.Feedback)
local Moment   = require(script.Parent.Parent.UI.Moment)

local EventFXController = {}

local localPlayer = Players.LocalPlayer

--------------------------------------------------------------------------------
-- Optik (keine Balance)
--------------------------------------------------------------------------------

local UFO_FOLDER   = "EventUfo"
local QUEEN_FOLDER = "EventWaspQueen"

local QUEEN_DESCENT_HEIGHT = 60          -- waehrend der Ankuendigung von so hoch herab
local QUEEN_SPIN_WINGS     = 18          -- Fluegelschlag (Grad)

local TELEGRAPH_COLOR      = Color3.fromRGB(255, 70, 50)
local TELEGRAPH_SAFE_COLOR = Color3.fromRGB(90, 230, 120)
local TELEGRAPH_FLASH      = 0.25        -- so lange blitzt die Flaeche beim Treffer
local TELEGRAPH_THICKNESS  = 0.3
local TELEGRAPH_LIFT       = 0.35

local HP_BAR_SIZE    = UDim2.fromOffset(260, 46)
local HP_BAR_OFFSET  = Vector3.new(0, 14, 0)
local HP_BAR_COLOR   = Color3.fromRGB(255, 190, 40)
local HP_BAR_BACK    = Color3.fromRGB(30, 26, 22)

local SKY_TINT       = Color3.fromRGB(255, 205, 170)
local SKY_BRIGHTNESS = -0.12
local SKY_SATURATION = -0.15
local SKY_TWEEN      = 3

local HIT_UPWARD     = 22               -- kleiner Hopser beim Rueckstoss

--------------------------------------------------------------------------------
-- Zustand
--------------------------------------------------------------------------------

type Crate = { model: Model, release: number, land: number, parts: { { part: BasePart, base: CFrame } }, canopy: BasePart?, landed: boolean }

local _ufo: { folder: Instance, model: Model?, start: number, center: Vector3 }? = nil
local _crates: { [Model]: Crate } = {}
local _queen: { folder: Instance, model: Model?, start: number, center: Vector3 }? = nil
local _telegraphs: { { parts: { BasePart }, hitAt: number, until_: number } } = {}
local _fxFolder: Folder? = nil

local function fxFolder(): Folder
	local folder = _fxFolder
	if folder and folder.Parent then
		return folder
	end
	local created = Instance.new("Folder")
	created.Name = "EventFX_Local"
	created.Parent = Workspace
	_fxFolder = created
	return created
end

local function localPart(props: { [string]: any }): BasePart
	local part: any = Instance.new("Part")
	part.Anchored   = true
	part.CanCollide = false
	part.CanQuery   = false
	part.CanTouch   = false
	part.CastShadow = false
	for key, value in props do
		part[key] = value
	end
	part.Parent = fxFolder()
	return part
end

--------------------------------------------------------------------------------
-- UFO und Kisten
--------------------------------------------------------------------------------

local function trackCrate(child: Instance)
	if not child:IsA("Model") or child.Name ~= "UfoDrop" then return end
	local release = child:GetAttribute("ReleaseAt")
	local land    = child:GetAttribute("LandAt")
	if typeof(release) ~= "number" or typeof(land) ~= "number" then return end

	-- Nur Kiste und Schirm fallen; Landekreis und Lichtsaeule stehen am Boden.
	local parts = {}
	for _, name in { "Crate", "Canopy" } do
		local part = child:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			table.insert(parts, { part = part, base = part.CFrame })
		end
	end
	local canopy = child:FindFirstChild("Canopy")
	_crates[child] = {
		model = child, release = release, land = land, parts = parts,
		canopy = if canopy and canopy:IsA("BasePart") then canopy else nil,
		landed = false,
	}
end

local function hookUfoFolder(folder: Instance)
	local start  = folder:GetAttribute("StartTime")
	local center = folder:GetAttribute("Center")
	if typeof(start) ~= "number" or typeof(center) ~= "Vector3" then
		-- Attribute kommen mit dem Ordner; ein Frame spaeter nochmal.
		task.defer(function()
			if folder.Parent and not _ufo then hookUfoFolder(folder) end
		end)
		return
	end
	local model = folder:FindFirstChild("Ufo")
	_ufo = { folder = folder, model = if model and model:IsA("Model") then model else nil, start = start, center = center }

	for _, child in folder:GetChildren() do
		trackCrate(child)
	end
	folder.ChildAdded:Connect(function(child)
		if child.Name == "Ufo" and child:IsA("Model") and _ufo and _ufo.folder == folder then
			_ufo.model = child
		end
		-- Kinder eines Models kommen evtl. nach dem Model an.
		task.defer(trackCrate, child)
	end)
	folder.ChildRemoved:Connect(function(child)
		if child:IsA("Model") then _crates[child] = nil end
	end)
end

local function animateUfo(now: number)
	local ufo = _ufo
	if not ufo then return end
	if not ufo.folder.Parent then
		_ufo = nil
		table.clear(_crates)
		return
	end
	local model = ufo.model
	if model and model.Parent then
		model:PivotTo(CFrame.new(EventMotion.ufoGround(ufo.center, ufo.start, now)))
	end

	for crateModel, crate in _crates do
		if not crateModel.Parent then
			_crates[crateModel] = nil
			continue
		end
		if crate.landed then continue end
		local height = if now < crate.release then EventMotion.DROP_FALL_HEIGHT else EventMotion.dropHeight(crate.release, crate.land, now)
		-- Vor dem Abwurf noch unsichtbar (unter dem UFO): ganz oben halten.
		for _, entry in crate.parts do
			entry.part.CFrame = entry.base + Vector3.new(0, height, 0)
		end
		if now >= crate.land then
			crate.landed = true
			local canopy = crate.canopy
			if canopy then canopy.Transparency = 1 end
		end
	end
end

--------------------------------------------------------------------------------
-- Wespenkoenigin
--------------------------------------------------------------------------------

local _hpFill: Frame? = nil
local _hpText: TextLabel? = nil

local function refreshHp(model: Model)
	local fill, text = _hpFill, _hpText
	if not fill or not text then return end
	local hp = model:GetAttribute("HP")
	local maxHp = model:GetAttribute("MaxHP")
	if typeof(hp) ~= "number" or typeof(maxHp) ~= "number" or maxHp <= 0 then
		fill.Size = UDim2.fromScale(1, 1)
		text.Text = Loc.t("ui.boss.name")
		return
	end
	fill.Size = UDim2.fromScale(math.clamp(hp / maxHp, 0, 1), 1)
	text.Text = Loc.t("ui.boss.hp", { hp = Loc.formatNumber(hp), max = Loc.formatNumber(maxHp) })
end

local function buildHpBar(model: Model)
	local head = model:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then return end

	local gui = Instance.new("BillboardGui")
	gui.Name        = "BossHp"
	gui.Size        = HP_BAR_SIZE
	gui.StudsOffset = HP_BAR_OFFSET
	gui.AlwaysOnTop = true
	gui.Adornee     = head
	gui.Parent      = model

	local back = Instance.new("Frame")
	back.Name = "Back"
	back.Size = UDim2.new(1, 0, 0, 18)
	back.Position = UDim2.new(0, 0, 1, -18)
	back.BackgroundColor3 = HP_BAR_BACK
	back.BorderSizePixel = 0
	back.Parent = gui
	Theme.corner(back, 6)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = HP_BAR_COLOR
	fill.BorderSizePixel = 0
	fill.Parent = back
	Theme.corner(fill, 6)

	local text = Theme.label("Name", gui, "")
	text.Size = UDim2.new(1, 0, 0, 24)
	text.TextXAlignment = Enum.TextXAlignment.Center
	text.TextColor3 = Theme.COLORS.goldGummy

	_hpFill, _hpText = fill, text
	refreshHp(model)
	model:GetAttributeChangedSignal("HP"):Connect(function() refreshHp(model) end)
	model:GetAttributeChangedSignal("MaxHP"):Connect(function() refreshHp(model) end)
end

local function hookQueenFolder(folder: Instance)
	local start  = folder:GetAttribute("StartTime")
	local center = folder:GetAttribute("Center")
	if typeof(start) ~= "number" or typeof(center) ~= "Vector3" then
		task.defer(function()
			if folder.Parent and not _queen then hookQueenFolder(folder) end
		end)
		return
	end
	_queen = { folder = folder, model = nil, start = start, center = center }

	local function adopt(child: Instance)
		if child.Name == "WaspQueen" and child:IsA("Model") and _queen and _queen.folder == folder then
			_queen.model = child
			task.defer(buildHpBar, child)
		end
	end
	for _, child in folder:GetChildren() do adopt(child) end
	folder.ChildAdded:Connect(adopt)
end

local function animateQueen(now: number)
	local queen = _queen
	if not queen then return end
	if not queen.folder.Parent then
		_queen = nil
		_hpFill, _hpText = nil, nil
		return
	end
	local model = queen.model
	if not model or not model.Parent then return end

	local phase2 = model:GetAttribute("Phase2At")
	local phase2At = if typeof(phase2) == "number" then phase2 else nil
	local pose: CFrame
	if now < queen.start then
		-- Ankuendigung: sinkt von oben herab auf ihre Bahn.
		local remaining = queen.start - now
		pose = EventMotion.queenPose(queen.center, queen.start, queen.start, nil)
			+ Vector3.new(0, QUEEN_DESCENT_HEIGHT * math.clamp(remaining / 20, 0, 1), 0)
	else
		pose = EventMotion.queenPose(queen.center, queen.start, now, phase2At)
	end
	model:PivotTo(pose)

	-- Fluegelschlag (lokal, rein optisch)
	local flap = math.rad(math.sin(now * 30) * QUEEN_SPIN_WINGS)
	for _, name in { "WingL", "WingR" } do
		local wing = model:FindFirstChild(name)
		if wing and wing:IsA("BasePart") then
			local sign = if name == "WingL" then 1 else -1
			wing.Transparency = 0.35 + 0.15 * math.abs(math.sin(now * 30))
			wing.CFrame = pose * CFrame.new(-5 * 1.6 * sign, 3 * 1.6, 1.6) * CFrame.Angles(0, 0, math.rad(20) * sign + flap * sign)
		end
	end
end

--------------------------------------------------------------------------------
-- Telegraphen
--------------------------------------------------------------------------------

local function disc(position: Vector3, radius: number, color: Color3, lift: number): BasePart
	return localPart({
		Name = "Telegraph", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon,
		Color = color, Transparency = 0.55,
		Size = Vector3.new(TELEGRAPH_THICKNESS, radius * 2, radius * 2),
		CFrame = CFrame.new(position + Vector3.new(0, lift, 0)) * CFrame.Angles(0, 0, math.rad(90)),
	})
end

local function showTelegraph(t: Types.HazardTelegraph)
	local parts: { BasePart } = {}
	if t.kind == "ring" and t.center then
		table.insert(parts, disc(t.center, t.outer or 0, TELEGRAPH_COLOR, TELEGRAPH_LIFT))
		-- Innen ist sicher: gruene Scheibe knapp darueber.
		table.insert(parts, disc(t.center, t.inner or 0, TELEGRAPH_SAFE_COLOR, TELEGRAPH_LIFT + 0.05))
	elseif t.kind == "circles" and t.points then
		for _, point in t.points do
			table.insert(parts, disc(point, t.radius or 0, TELEGRAPH_COLOR, TELEGRAPH_LIFT))
		end
	elseif t.kind == "lane" and t.from and t.to then
		local from, to = t.from, t.to
		local mid = (from + to) / 2
		local length = (Vector3.new(to.X - from.X, 0, to.Z - from.Z)).Magnitude
		table.insert(parts, localPart({
			Name = "Telegraph", Material = Enum.Material.Neon, Color = TELEGRAPH_COLOR, Transparency = 0.55,
			Size = Vector3.new(t.width or 0, TELEGRAPH_THICKNESS, length),
			CFrame = CFrame.lookAt(mid + Vector3.new(0, TELEGRAPH_LIFT, 0), Vector3.new(to.X, mid.Y + TELEGRAPH_LIFT, to.Z)),
		}))
	end
	table.insert(_telegraphs, { parts = parts, hitAt = t.hitAt, until_ = t.hitAt + TELEGRAPH_FLASH })
end

local function animateTelegraphs(now: number)
	for i = #_telegraphs, 1, -1 do
		local t = _telegraphs[i]
		if now >= t.until_ then
			for _, part in t.parts do part:Destroy() end
			table.remove(_telegraphs, i)
		elseif now >= t.hitAt then
			for _, part in t.parts do part.Transparency = 0.05 end
		else
			-- pulsiert schneller, je naeher der Treffer
			local left = t.hitAt - now
			local pulse = 0.45 + 0.2 * math.sin(now * (8 + 12 / math.max(0.2, left)))
			for _, part in t.parts do
				if part.Color ~= TELEGRAPH_SAFE_COLOR then
					part.Transparency = pulse
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Treffer am eigenen Charakter
--------------------------------------------------------------------------------

local _slowToken = 0

local function onHit(info: any)
	if typeof(info) ~= "table" or typeof(info.push) ~= "Vector3" then return end
	local character = localPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not root or not root:IsA("BasePart") or not humanoid then return end

	root.AssemblyLinearVelocity = info.push + Vector3.new(0, HIT_UPWARD, 0)

	local factor  = if typeof(info.slowFactor) == "number" then info.slowFactor else 1
	local seconds = if typeof(info.slowSeconds) == "number" then info.slowSeconds else 0
	if factor < 1 and seconds > 0 then
		_slowToken += 1
		local token = _slowToken
		local before = humanoid.WalkSpeed
		local slowed = before * factor
		humanoid.WalkSpeed = slowed
		task.delay(seconds, function()
			-- Nur zuruecksetzen, wenn niemand sonst (CombService) inzwischen
			-- einen anderen Wert gesetzt hat.
			if token == _slowToken and humanoid.Parent and humanoid.WalkSpeed == slowed then
				humanoid.WalkSpeed = before
			end
		end)
	end
	Notify.emit("boss_hit", function()
		Toast.show(Loc.t("ui.boss.hit"), Theme.COLORS.bad)
	end)
end

--------------------------------------------------------------------------------
-- Himmel beim Boss
--------------------------------------------------------------------------------

local _sky: ColorCorrectionEffect? = nil

local function setBossSky(active: boolean)
	local sky = _sky
	if not sky then
		local created = Instance.new("ColorCorrectionEffect")
		created.Name = "BossSky_Local"
		created.Parent = Lighting
		sky = created
		_sky = created
	end
	local effect = sky :: ColorCorrectionEffect
	TweenService:Create(effect, TweenInfo.new(SKY_TWEEN), {
		TintColor  = if active then SKY_TINT else Color3.new(1, 1, 1),
		Brightness = if active then SKY_BRIGHTNESS else 0,
		Saturation = if active then SKY_SATURATION else 0,
	}):Play()
end

--------------------------------------------------------------------------------
-- Belohnungs-Momente (Icon-Weg von "event_notice_good")
--------------------------------------------------------------------------------

-- HBB Paket 7: Truhenfarbe je Boss-Stufe 1..4 (Bronze, Silber, Gold, Lila)
local BOSS_TIER_COLORS = {
	Color3.fromRGB(205, 127, 50), Color3.fromRGB(200, 210, 225),
	Color3.fromRGB(255, 200, 40), Color3.fromRGB(190, 110, 255),
}

-- Zeigt zu einer bekannten Belohnungsnotiz das passende Bild ohne Text.
-- Rueckgabe false = Notiz unbekannt, der Aufrufer faellt auf den Toast zurueck.
local function playRewardMoment(key: any, args: any): boolean
	if key == "msg.boss.tier" then
		-- Truhe in der Stufenfarbe; die Inhalte fliegen danach ueber den
		-- Datenstand in die Pillen.
		local tier = if typeof(args) == "table" and typeof(args.tier) == "number" then args.tier else 1
		Moment.show("chest", BOSS_TIER_COLORS[math.clamp(tier, 1, 4)], nil)
	elseif key == "msg.event.rarity_up" then
		local to = if typeof(args) == "table" and Loc.isMsg(args.to) then args.to.k else nil
		local rarity = if typeof(to) == "string" then string.gsub(to, "^rarity%.", "") else nil
		Moment.show("rarity", if rarity then Theme.rarityColor(rarity :: any) else Theme.COLORS.goldGummy, "ui.moment.rarity")
	elseif key == "msg.event.combs" then
		local n = if typeof(args) == "table" and typeof(args.n) == "number" then args.n else 1
		Feedback.gain("comb", n)
	elseif key == "msg.event.gummies" or key == "msg.ufo.drop_picked" then
		-- schon ueber den Datenstand sichtbar
	else
		return false
	end
	return true
end

--------------------------------------------------------------------------------
-- Initialisierung
--------------------------------------------------------------------------------

function EventFXController.init()
	local function onWorkspaceChild(child: Instance)
		if child.Name == UFO_FOLDER then
			hookUfoFolder(child)
		elseif child.Name == QUEEN_FOLDER then
			hookQueenFolder(child)
		end
	end
	for _, child in Workspace:GetChildren() do
		onWorkspaceChild(child)
	end
	Workspace.ChildAdded:Connect(onWorkspaceChild)

	Remotes.EventTelegraph.OnClientEvent:Connect(function(t: any)
		if typeof(t) ~= "table" or typeof(t.hitAt) ~= "number" then return end
		showTelegraph(t :: Types.HazardTelegraph)
	end)

	Remotes.EventHazardHit.OnClientEvent:Connect(onHit)

	Remotes.EventNotice.OnClientEvent:Connect(function(msg: any, style: any)
		if not Loc.isMsg(msg) and typeof(msg) ~= "string" then return end
		if style == "big" then
			Notify.emit("event_notice_big", function()
				Toast.show(msg, Theme.COLORS.goldGummy)
			end)
		elseif style == "good" then
			Notify.emit("event_notice_good", function()
				Toast.success(msg)
			end, function()
				-- Gummies und Eier fliegen schon ueber den Datenstand
				-- (UI/Feedback). Hier nur, was dort nicht sichtbar wird.
				if not (Loc.isMsg(msg) and playRewardMoment((msg :: any).k, (msg :: any).a)) then
					-- Unbekannte Belohnungsnotiz: lieber lesen als verlieren
					Toast.success(msg)
				end
			end)
		else
			Notify.emit("event_notice_info", function()
				Toast.info(msg)
			end)
		end
	end)

	Remotes.EventPhaseChanged.OnClientEvent:Connect(function(eventId: any)
		setBossSky(eventId == "WaspQueen")
	end)

	RunService.RenderStepped:Connect(function()
		local now = Workspace:GetServerTimeNow()
		animateUfo(now)
		animateQueen(now)
		animateTelegraphs(now)
	end)

	print("[EventFXController] Initialisiert")
end

return EventFXController
