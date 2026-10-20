--!strict
-- EpilogFinaleFX.luau
-- StarterPlayerScripts/UI/EpilogFinaleFX.luau
--
-- Einzige Zustaendigkeit (Prompt 6 von 7, Final-Epilog): die WELT-Effekte des Knopf-Finales,
-- alles nur lokal beim Spieler und rein visuell:
--   - Rakete aus dem Schacht in die Wolken fahren (Tween auf der Client-Kopie; Feuer und
--     Rauch schaltet der Server als Emitter)
--   - Shockwave-Ring ueber das Wasser (flacher Zylinder mit Ring aus SurfaceGui, oder Bild)
--   - Portal-Silhouette am Horizont (BillboardGui, Bild oder Frame-Silhouette)
--   - Himmel kurz in Welt-2-Violettrosa (ColorCorrection) und der Bloom-Stoss beim Start
--   - Kamera-Schuetteln ueber Humanoid.CameraOffset (0,3 -> 0,8 Studs, sinusfoermig)
-- Keine eigene Schleife: der EpilogController ruft `update(f, dt)` aus seiner einen
-- Kit.animate-Schleife. `destroy()` stellt ALLES wieder her (Bloom, Tint, CameraOffset,
-- lokale Teile) und ist immer sicher aufrufbar.

local Workspace         = game:GetService("Workspace")
local Lighting          = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EpilogConfig = require(ReplicatedStorage.Config.EpilogConfig)

local EpilogFinaleFX = {}
EpilogFinaleFX.__index = EpilogFinaleFX

local F = EpilogConfig.FINALE
local A = EpilogConfig.ASSETS

export type Info = {
	rocketBase : { number }?,
	island     : { number },
	dir        : { number },
}

export type Instance = typeof(setmetatable({} :: {
	info       : Info,
	humanoid   : Humanoid?,
	camOffset  : Vector3,
	rocket     : Model?,
	rocketHome : CFrame?,
	wave       : BasePart?,
	waveRing   : Frame?,
	portal     : BasePart?,
	portalGui  : GuiObject?,
	bloom      : BloomEffect?,
	tint       : ColorCorrectionEffect?,
	reduced    : boolean,
	waveStarted: boolean,
	destroyed  : boolean,
}, EpilogFinaleFX))

local function lerp(a: number, b: number, t: number): number return a + (b - a) * t end
local function clamp01(x: number): number return math.clamp(x, 0, 1) end

function EpilogFinaleFX.new(info: Info, humanoid: Humanoid?, reduced: boolean): Instance
	local self = setmetatable({
		info = info, humanoid = humanoid, camOffset = if humanoid then humanoid.CameraOffset else Vector3.zero,
		rocket = nil, rocketHome = nil, wave = nil, waveRing = nil,
		portal = nil, portalGui = nil, bloom = nil, tint = nil,
		reduced = reduced, waveStarted = false, destroyed = false,
	}, EpilogFinaleFX)

	local bloom = Instance.new("BloomEffect")
	bloom.Name = "EpilogFinaleBloom"
	bloom.Intensity = 0
	bloom.Size = 30
	bloom.Threshold = 1.0
	bloom.Parent = Lighting
	self.bloom = bloom
	local tint = Instance.new("ColorCorrectionEffect")
	tint.Name = "EpilogFinaleTint"
	tint.Parent = Lighting
	self.tint = tint
	return self
end

-- Rakete (Server-Teil) suchen: Modell "Rakete" mit Attribut EpilogRocketBase, darin Epilog_Rakete.
local function findRocket(): Model?
	for _, d in Workspace:GetDescendants() do
		if d.Name == "Epilog_Rakete" and d:IsA("Model") and d.Parent and d.Parent:GetAttribute("EpilogRocketBase") ~= nil then
			return d
		end
	end
	return nil
end

local function v3(a: { number }): Vector3 return Vector3.new(a[1], a[2], a[3]) end

local function startWave(self: Instance)
	self.waveStarted = true
	local center = v3(self.info.island)
	local part = Instance.new("Part")
	part.Name = "Epilog_Shockwave"
	part.Shape = Enum.PartType.Cylinder
	part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery, part.CastShadow = true, false, false, false, false
	part.Material = Enum.Material.SmoothPlastic
	part.Transparency = 1
	part.Size = Vector3.new(F.shockwave.height, F.shockwave.startSize, F.shockwave.startSize)
	part.CFrame = CFrame.new(center + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90))
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Right   -- Zylinderachse X wird nach oben gedreht
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 8
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.Brightness = 2
	gui.Parent = part
	if A.shockwaveTex ~= "" then
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromScale(1, 1)
		img.Image = A.shockwaveTex
		img.ImageColor3 = Color3.fromRGB(255, 244, 214)
		img.Parent = gui
	else
		local ring = Instance.new("Frame")
		ring.BackgroundTransparency = 1
		ring.Size = UDim2.fromScale(1, 1)
		ring.BorderSizePixel = 0
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = ring
		local st = Instance.new("UIStroke")
		st.Color = Color3.fromRGB(255, 244, 214)
		st.Thickness = 14
		st.Parent = ring
		ring.Parent = gui
		self.waveRing = ring
	end
	part.Parent = Workspace
	self.wave = part
end

local function startPortal(self: Instance)
	local P = F.portal
	local pos = v3(self.info.island) + v3(self.info.dir) * P.distance + Vector3.new(0, P.height, 0)
	local part = Instance.new("Part")
	part.Name = "Epilog_Portal"
	part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery, part.CastShadow = true, false, false, false, false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	part.Position = pos
	local gui = Instance.new("BillboardGui")
	gui.StudsOffset = Vector3.zero
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.MaxDistance = 2000
	gui.Size = UDim2.fromScale(P.size, P.size)   -- BillboardGui: Scale = Studs
	gui.Parent = part
	local holder: GuiObject
	if A.portalTex ~= "" then
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromScale(1, 1)
		img.Image = A.portalTex
		img.ImageTransparency = 1
		img.Parent = gui
		holder = img
	else
		-- Ersatz: Torbogen aus Frame (oben rund) in Violett-Rosa mit Glut-Rand
		local arch = Instance.new("Frame")
		arch.AnchorPoint = Vector2.new(0.5, 1)
		arch.Position = UDim2.fromScale(0.5, 1)
		arch.Size = UDim2.fromScale(0.5, 0.8)
		arch.BackgroundColor3 = Color3.fromRGB(70, 20, 90)
		arch.BackgroundTransparency = 1
		arch.BorderSizePixel = 0
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = arch
		local st = Instance.new("UIStroke")
		st.Color = F.skyTint
		st.Thickness = 10
		st.Transparency = 1
		st.Parent = arch
		arch.Parent = gui
		holder = arch
	end
	part.Parent = Workspace
	self.portal = part
	self.portalGui = holder
end

local function setPortalAlpha(self: Instance, a: number)
	local g = self.portalGui
	if not g then return end
	if g:IsA("ImageLabel") then
		g.ImageTransparency = 1 - a
	else
		g.BackgroundTransparency = 1 - a * 0.92
		local st = g:FindFirstChildOfClass("UIStroke")
		if st then st.Transparency = 1 - a end
	end
end

-- f = Finale-Sekunden, dt = Frame-Zeit.
function EpilogFinaleFX.update(self: Instance, f: number, dt: number)
	if self.destroyed then return end

	-- Kamera-Schuetteln: wird ab dem Countdown staerker, nach dem Start abklingend
	local hum = self.humanoid
	if hum and hum.Parent then
		local S = F.shake
		local amp = 0
		if f >= F.countTimes[1] and f < F.launchAt then
			amp = lerp(S.from, S.to, clamp01((f - F.countTimes[1]) / (F.launchAt - F.countTimes[1])))
		elseif f >= F.launchAt and f < F.launchEnd + 1 then
			amp = lerp(S.to, 0, clamp01((f - F.launchAt) / (F.launchEnd + 1 - F.launchAt)))
		end
		if self.reduced then amp *= 0.5 end
		local w = f * S.hz * 2 * math.pi
		hum.CameraOffset = self.camOffset + Vector3.new(math.sin(w) * amp, math.sin(w * 1.31 + 1) * amp * 0.6, 0)
	end

	-- Bloom: 1,5 beim Start, in 2 s auf 0,8, dann sanft aus
	local bloom = self.bloom
	if bloom then
		local v: number
		if f < F.launchAt then
			v = lerp(0, 0.9, clamp01((f - F.countTimes[1]) / (F.launchAt - F.countTimes[1])))
		elseif f < F.launchAt + F.bloomSeconds then
			v = lerp(F.bloomPeak, F.bloomRest, clamp01((f - F.launchAt) / F.bloomSeconds))
		else
			v = lerp(F.bloomRest, 0, clamp01((f - (F.returnAt)) / 1.5))
		end
		bloom.Intensity = v
	end

	-- Rakete
	if f >= F.launchAt - 0.01 and not self.rocket then
		self.rocket = findRocket()
		if self.rocket then self.rocketHome = self.rocket:GetPivot() end
	end
	local rocket, home = self.rocket, self.rocketHome
	if rocket and rocket.Parent and home then
		local u = clamp01((f - F.launchAt) / (F.launchEnd - F.launchAt))
		local rise = F.rocket.rise * u * u            -- Quad: zuerst traege, dann davon
		local wobble = math.sin(f * 21) * 0.05 * u
		rocket:PivotTo(home * CFrame.new(wobble, rise, 0))
	end

	-- Shockwave
	if f >= F.launchAt and not self.waveStarted then startWave(self) end
	local wave = self.wave
	if wave and wave.Parent then
		local W = F.shockwave
		local u = clamp01((f - F.launchAt) / W.seconds)
		local d = lerp(W.startSize, W.endSize, 1 - (1 - u) * (1 - u))
		wave.Size = Vector3.new(W.height, d, d)
		local a = 1 - u
		if self.waveRing then
			local st = self.waveRing:FindFirstChildOfClass("UIStroke")
			if st then st.Transparency = 1 - a; st.Thickness = lerp(16, 3, u) end
		else
			local gui = wave:FindFirstChildOfClass("SurfaceGui")
			local img = if gui then gui:FindFirstChildOfClass("ImageLabel") else nil
			if img then img.ImageTransparency = 1 - a end
		end
		if u >= 1 then wave.Parent = nil end
	end

	-- Himmel: Violett-Rosa kurz einblenden, halten, ausblenden; Portal-Silhouette dazu
	local tint = self.tint
	if tint then
		local inA = clamp01((f - F.celebrateAt) / F.skyTintSeconds)
		local outA = clamp01((f - (F.celebrateAt + F.skyTintSeconds + F.skyHoldSeconds)) / 1.2)
		local k = inA * (1 - outA)
		tint.TintColor = Color3.new(1, 1, 1):Lerp(F.skyTint, 0.55 * k)
		tint.Saturation = 0.2 * k
	end
	if f >= F.celebrateAt and not self.portal then startPortal(self) end
	if self.portal then
		local P = F.portal
		local inA = clamp01((f - F.celebrateAt) / 1.0)
		local outA = clamp01((f - (F.celebrateAt + P.seconds)) / 1.0)
		setPortalAlpha(self, inA * (1 - outA) * (if self.reduced then 0.8 else 1))
	end
end

-- Stellt alles wieder her und entfernt alle lokalen Teile. Mehrfachaufruf harmlos.
function EpilogFinaleFX.destroy(self: Instance)
	if self.destroyed then return end
	self.destroyed = true
	local hum = self.humanoid
	if hum and hum.Parent then hum.CameraOffset = self.camOffset end
	if self.bloom then self.bloom:Destroy() end
	if self.tint then self.tint:Destroy() end
	if self.wave then self.wave:Destroy() end
	if self.portal then self.portal:Destroy() end
	-- Die Raketen-Kopie liegt in einem Server-Modell; es wird serverseitig zerstoert.
	local rocket, home = self.rocket, self.rocketHome
	if rocket and rocket.Parent and home then rocket:PivotTo(home) end
end

-- Zaehler fuer `epilog audit`.
function EpilogFinaleFX.audit(): { [string]: any }
	local n = 0
	for _, c in Lighting:GetChildren() do
		if string.sub(c.Name, 1, 12) == "EpilogFinale" then n += 1 end
	end
	return {
		lichtEffekte = n,
		welle = Workspace:FindFirstChild("Epilog_Shockwave") ~= nil,
		portal = Workspace:FindFirstChild("Epilog_Portal") ~= nil,
	}
end

return EpilogFinaleFX
