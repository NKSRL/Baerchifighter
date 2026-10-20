--!strict
-- HatchBorderShimmer.luau
-- ReplicatedStorage/VFX/HatchBorderShimmer.luau
--
-- Einzige Zustaendigkeit:
--   - Schimmer-Rahmen am Bildschirmrand waehrend der Ei-Schluepf-Animation (reine Client-Optik).
--     Phase 1: neutral, sanfte Pastell-Regenbogenfarben, Lichtkopf laeuft im Kreis.
--     Phase 2 (setRarity): blendet in die Rarity-Farbe, Staerke nach Rarity-Stufe.
--     Phase 3: bleibt auf voller Staerke, pulse() fuer den Reveal, stop() blendet aus.
--
-- Abgrenzung: kennt weder EggHatch noch Server. EggHatch ruft start/setRarity/pulse/stop auf.
-- Farben kommen aus BaerchiConfig.RARITY_COLORS, Reihenfolge aus BaerchiConfig.RARITY_ORDER.
--
-- Technik: EIN ScreenGui, drei verschachtelte Rahmen-Ebenen (UIStroke + UIGradient) fuer den
-- weichen Abfall, EINE RenderStepped-Schleife, keine Instanzen pro Frame. Es gibt nie mehr als
-- ein Overlay: start() raeumt ein altes sofort ab.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BaerchiConfig = require(ReplicatedStorage.Config.BaerchiConfig)

local HatchBorderShimmer = {}

--------------------------------------------------------------------------------
-- TUNING (hier drehen)
--------------------------------------------------------------------------------
-- Gemeinsame Werte
local GENERAL = {
	fadeIn        = 0.4,   -- Einblenden beim Start (s)
	fadeOut       = 0.4,   -- Ausblenden beim Stop (s)
	blendSeconds  = 0.4,   -- Farb-/Staerke-Uebergang beim Rarity-Hinweis (s)
	inset         = 4,     -- Abstand zum Bildschirmrand (px)
	cornerRadius  = 30,    -- Rundung der Ecken (px)
	neutralLap    = 3.2,   -- Sekunden pro Runde in Phase 1
	neutralAlpha  = 0.42,  -- Deckkraft in Phase 1
	neutralThick  = 8,     -- Dicke in Phase 1 (px)
	neutralColorSeconds = 7, -- ein voller Farbkreis in Phase 1 (s)
	maxPulseHz    = 1.5,   -- Sicherheitsgrenze (Lichtempfindlichkeit, max ca. 2 Hz)
	flareSeconds  = 0.9,   -- Dauer eines Eck-Flares
	flareEvery    = 2.4,   -- Abstand der Flares bei Top-Stufen (s)
}

-- Anker: unterste (Common) und oberste Rarity. Dazwischen wird nach Rarity-INDEX gemischt.
-- alpha = Deckkraft 0..1, thickness = px, lap = Sekunden pro Runde (kleiner = schneller),
-- pulse = Atem-Frequenz in Hz (0 = keiner)
local LOW  = { alpha = 0.28, thickness = 6,  lap = 4.2, pulse = 0 }
local HIGH = { alpha = 0.95, thickness = 14, lap = 2.0, pulse = 1.2 }
local DOUBLE_LAYER_FROM = 0.5   -- ab diesem Anteil (0..1) der Reihenfolge: zweite, breitere Glow-Ebene
local FLARE_FROM        = 0.7   -- ab diesem Anteil: Eck-Flares

-- Einzelne Rarity gezielt ueberschreiben (optional), z. B. Omega = { lap = 1.6 }
local OVERRIDES: { [string]: { alpha: number?, thickness: number?, lap: number?, pulse: number?, flare: boolean?, double: boolean? } } = {}

export type Entry = { alpha: number, thickness: number, speed: number, pulse: number, flare: boolean, double: boolean }
-- RARITY_SHIMMER[rarity] = { alpha, thickness, speed (Sek./Runde), pulse (Hz), flare, double }
-- Wird aus RARITY_ORDER erzeugt; neue Raritys bekommen automatisch eine Stufe.
local RARITY_SHIMMER: { [string]: Entry } = {}
HatchBorderShimmer.RARITY_SHIMMER = RARITY_SHIMMER

do
	local order = BaerchiConfig.RARITY_ORDER :: { string }
	local n = #order
	for i, name in order do
		local u = if n > 1 then (i - 1) / (n - 1) else 0
		local function mix(a: number, b: number): number return a + (b - a) * u end
		local e: Entry = {
			alpha = mix(LOW.alpha, HIGH.alpha),
			thickness = mix(LOW.thickness, HIGH.thickness),
			speed = mix(LOW.lap, HIGH.lap),
			pulse = mix(LOW.pulse, HIGH.pulse),
			flare = u >= FLARE_FROM,
			double = u >= DOUBLE_LAYER_FROM,
		}
		local o = OVERRIDES[name]
		if o then
			if o.alpha then e.alpha = o.alpha end
			if o.thickness then e.thickness = o.thickness end
			if o.lap then e.speed = o.lap end
			if o.pulse then e.pulse = o.pulse end
			if o.flare ~= nil then e.flare = o.flare end
			if o.double ~= nil then e.double = o.double end
		end
		RARITY_SHIMMER[name] = e
	end
end

--------------------------------------------------------------------------------
-- Hilfen
--------------------------------------------------------------------------------
local function clamp01(x: number): number return math.clamp(x, 0, 1) end

-- Dunkle Rarity-Farben (z. B. Secret) wuerden auf dem abgedunkelten Spiel verschwinden:
-- Helligkeit anheben, Farbton bleibt.
local function visible(c: Color3): Color3
	local h, s, v = c:ToHSV()
	if v < 0.65 then v = 0.65 end
	return Color3.fromHSV(h, s, v)
end

-- Lichtkopf: unten durchsichtig, zum Ende hell (die Drehung des Verlaufs laesst ihn kreisen)
local HEAD_TRANSPARENCY = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.5, 0.9),
	NumberSequenceKeypoint.new(0.8, 0.45),
	NumberSequenceKeypoint.new(1, 0),
})

type Layer = {
	frame: Frame, stroke: UIStroke, corner: UICorner, gradient: UIGradient?,
	mulThick: number, mulAlpha: number, pad: number,
}

export type Shimmer = {
	setRarity: (self: Shimmer, rarity: string) -> (),
	pulse: (self: Shimmer) -> (),
	stop: (self: Shimmer, immediate: boolean?) -> (),
	alive: boolean,
}

local current: Shimmer? = nil

--------------------------------------------------------------------------------
-- start / setRarity / pulse / stop
--------------------------------------------------------------------------------
-- start(parent): parent = der ScreenGui der Szene (nur fuer DisplayOrder). Gibt das Objekt zurueck.
function HatchBorderShimmer.start(parent: Instance?): Shimmer
	if current then current:stop(true) end

	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
	local baseGui = if parent then (if parent:IsA("ScreenGui") then parent else parent:FindFirstAncestorWhichIsA("ScreenGui")) else nil

	local gui = Instance.new("ScreenGui")
	gui.Name = "HatchBorderShimmer"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = (if baseGui then (baseGui :: ScreenGui).DisplayOrder else 0) + 1
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	-- Drei Ebenen: Aussen (breit, blass) -> Mitte -> Kern (schmal, hell). Weicher Abfall nach innen.
	local layers: { Layer } = {}
	local function makeLayer(name: string, mulThick: number, mulAlpha: number, withGradient: boolean): Layer
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.BackgroundTransparency = 1
		frame.Active = false
		frame.Parent = gui
		local corner = Instance.new("UICorner")
		corner.Parent = frame
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Transparency = 1
		stroke.Parent = frame
		local gradient: UIGradient? = nil
		if withGradient then
			local g = Instance.new("UIGradient")
			g.Transparency = HEAD_TRANSPARENCY
			g.Parent = stroke
			gradient = g
		end
		local l: Layer = { frame = frame, stroke = stroke, corner = corner, gradient = gradient, mulThick = mulThick, mulAlpha = mulAlpha, pad = 0 }
		table.insert(layers, l)
		return l
	end
	local glow = makeLayer("Glow", 1.6, 0.22, true)
	local mid  = makeLayer("Mid",  1.1, 0.45, true)
	local core = makeLayer("Core", 0.55, 1.0,  true)
	-- Dauerhafter, blasser Grundring (ohne Kopf), damit der ganze Rand immer sichtbar ist
	local base = makeLayer("Base", 0.8, 0.28, false)

	-- Eck-Flares: vier kleine Kreise, nur bei Top-Stufen sichtbar
	local flares: { { frame: Frame, stroke: UIStroke } } = {}
	for i = 1, 4 do
		local f = Instance.new("Frame")
		f.Name = "Flare" .. i
		f.BackgroundTransparency = 1
		f.Active = false
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.new(if i % 2 == 1 then 0 else 1, if i % 2 == 1 then 14 else -14, if i <= 2 then 0 else 1, if i <= 2 then 14 else -14)
		f.Size = UDim2.fromOffset(0, 0)
		f.Visible = false
		f.Parent = gui
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0.5, 0); c.Parent = f
		local s = Instance.new("UIStroke"); s.Thickness = 5; s.Transparency = 1; s.Parent = f
		table.insert(flares, { frame = f, stroke = s })
	end

	-- Zustand (alles wird in der einen Schleife geglaettet)
	local alive = true
	local fadingOut = false
	local master = 0                 -- 0..1 Ein-/Ausblenden
	local elapsed = 0
	local angle = 0                  -- Lichtkopf-Winkel (Grad)
	local rarityMode = false
	local rarityEntry: Entry? = nil
	local color = Color3.fromHSV(0, 0.4, 1)
	local targetColor = color
	local alpha, thickness, lap, pulseHz = GENERAL.neutralAlpha, GENERAL.neutralThick, GENERAL.neutralLap, 0
	local doubleMix = 0              -- 0..1 Sichtbarkeit der Glow-Ebene
	local extraPulse = 0             -- klingt ab
	local nextFlare = math.huge
	local flareT = -1
	local conn: RBXScriptConnection? = nil

	local self: Shimmer = nil :: any

	local function destroy()
		if not alive then return end
		alive = false
		if conn then conn:Disconnect() conn = nil end
		gui:Destroy()
		if current == self then current = nil end
	end

	local function apply(breath: number)
		local screen = gui.AbsoluteSize
		for _, l in layers do
			local visibleLayer = true
			if l == glow then visibleLayer = doubleMix > 0.01 end
			l.frame.Visible = visibleLayer
			if visibleLayer then
				local th = math.max(1, thickness * l.mulThick)
				local off = GENERAL.inset + th   -- Border-Strich liegt aussen: Rahmen nach innen ruecken
				l.frame.Position = UDim2.fromOffset(off, off)
				l.frame.Size = UDim2.fromOffset(math.max(screen.X - 2 * off, 2), math.max(screen.Y - 2 * off, 2))
				l.corner.CornerRadius = UDim.new(0, math.max(GENERAL.cornerRadius - th * 0.3, 4))
				l.stroke.Thickness = th
				l.stroke.Color = color
				local a = clamp01(alpha * l.mulAlpha * breath * master * (if l == glow then doubleMix else 1))
				l.stroke.Transparency = 1 - a
				if l.gradient then l.gradient.Rotation = angle end
			end
		end
	end

	conn = RunService.RenderStepped:Connect(function(dt: number)
		if not alive then return end
		elapsed += dt

		-- Ein-/Ausblenden
		if fadingOut then
			master -= dt / math.max(GENERAL.fadeOut, 0.05)
			if master <= 0 then destroy() return end
		else
			master = math.min(1, master + dt / math.max(GENERAL.fadeIn, 0.05))
		end

		-- Glaettung Richtung Ziel (ca. blendSeconds)
		local k = 1 - math.exp(-dt * 3 / math.max(GENERAL.blendSeconds, 0.05))
		if rarityMode then
			color = color:Lerp(targetColor, k)
		else
			color = Color3.fromHSV((elapsed / GENERAL.neutralColorSeconds) % 1, 0.42, 1)
		end
		local e = rarityEntry
		local tAlpha = if e then e.alpha else GENERAL.neutralAlpha
		local tThick = if e then e.thickness else GENERAL.neutralThick
		local tLap   = if e then e.speed else GENERAL.neutralLap
		local tPulse = if e then math.min(e.pulse, GENERAL.maxPulseHz) else 0
		local tDouble = if e and e.double then 1 else 0
		alpha += (tAlpha - alpha) * k
		thickness += (tThick - thickness) * k
		lap += (tLap - lap) * k
		pulseHz += (tPulse - pulseHz) * k
		doubleMix += (tDouble - doubleMix) * k

		-- Lichtkopf im Uhrzeigersinn
		angle = (angle + 360 * dt / math.max(lap, 0.5)) % 360

		-- Atmen (max. maxPulseHz) + einmaliger Extra-Puls (klingt ab)
		extraPulse = math.max(0, extraPulse - dt / 0.9)
		local breath = 1
		if pulseHz > 0.01 then
			breath = 0.82 + 0.18 * math.sin(elapsed * math.pi * 2 * math.min(pulseHz, GENERAL.maxPulseHz))
		end
		breath = math.min(1.15, breath + 0.25 * math.sin(math.pi * (1 - extraPulse)) * (if extraPulse > 0 then 1 else 0))

		-- Eck-Flares (nur Top-Stufen)
		if e and e.flare and not fadingOut then
			if elapsed >= nextFlare then
				flareT = 0
				nextFlare = elapsed + GENERAL.flareEvery
			end
		end
		if flareT >= 0 then
			flareT += dt
			local u = flareT / GENERAL.flareSeconds
			for _, f in flares do
				if u >= 1 then
					f.frame.Visible = false
				else
					local s = 30 + 150 * (1 - (1 - u) ^ 2)
					f.frame.Visible = true
					f.frame.Size = UDim2.fromOffset(s, s)
					f.stroke.Color = color
					f.stroke.Transparency = 1 - 0.55 * (1 - u) * master
				end
			end
			if u >= 1 then flareT = -1 end
		end

		apply(breath)
	end)

	self = {
		alive = true,
		setRarity = function(_, rarity: string)
			if not alive or fadingOut then return end
			local entry = RARITY_SHIMMER[rarity]
			if not entry then return end
			if rarityMode then return end   -- nur der erste Hinweis zaehlt
			rarityMode = true
			rarityEntry = entry
			targetColor = visible(BaerchiConfig.RARITY_COLORS[rarity] or Color3.new(1, 1, 1))
			color = color  -- Start der Mischung: aktuelle Farbe
			if entry.flare then nextFlare = elapsed + GENERAL.blendSeconds end
		end,
		pulse = function(_)
			if not alive or fadingOut or not rarityEntry then return end
			if rarityEntry.double then extraPulse = 1 end
		end,
		stop = function(_, immediate: boolean?)
			if not alive then return end
			self.alive = false
			if immediate then destroy() return end
			fadingOut = true
		end,
	} :: any

	current = self
	return self
end

-- Bequeme Aufrufe auf das aktuelle Overlay (API: start() / setRarity() / stop())
function HatchBorderShimmer.setRarity(rarity: string)
	if current then current:setRarity(rarity) end
end

function HatchBorderShimmer.pulse()
	if current then current:pulse() end
end

function HatchBorderShimmer.stop(immediate: boolean?)
	if current then current:stop(immediate) end
end

return HatchBorderShimmer
