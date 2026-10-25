--------------------------------------------------------------------------------
-- 25.10.2026 Shows der ersten Baerchis (Uncommon bis Legendary, Stufe 2/3, ohne
-- Kamerafahrt). Schub 1: Bauchrutscher (Eisbaer), Tigersprung (Tigerbaer),
-- Brennglas (Detektiv), Bass-Drop (Zucker-DJ). Gemeinsamer Baustein `moves`:
-- der Baerchi SELBST folgt Posen aus den DATEN (SkillFXConfig), so braucht nicht
-- jede Show eine eigene Tanz-Funktion. Alle Helfer dieser Shows liegen in EINER
-- Tabelle LOW (die Modul-Ebene hat nur noch ~60 freie lokale Namen, Roblox-
-- Grenze 200). Doku in SkillFXConfig ("BAUSTEINE", Erste Baerchis).
--------------------------------------------------------------------------------

local LOW: { [string]: any } = {}

LOW.WHITE = Color3.fromRGB(255, 250, 240)      -- warmes Weiss (Klon-Fuellung, F37)
LOW.ICE = Color3.fromRGB(178, 226, 255)        -- Eis
LOW.RIME = Color3.fromRGB(232, 247, 255)       -- Reif, fast weiss
LOW.EMBER = Color3.fromRGB(150, 38, 28)        -- schwelender Kratzer
LOW.HOT = Color3.fromRGB(255, 236, 160)        -- gluehend hell
LOW.GOLD = Color3.fromRGB(243, 218, 124)       -- Messing der Lupe
LOW.BRASS = Color3.fromRGB(160, 134, 97)       -- Griff
LOW.VINYL = Color3.fromRGB(38, 30, 48)         -- Schallplatte
LOW.DEEPICE = Color3.fromRGB(140, 200, 245)    -- Eisbahn (satter als der Block, F19)
LOW.RIMBLUE = Color3.fromRGB(90, 160, 235)     -- Reifkanten der Eisbahn (blau statt weiss)
LOW.DEEPPINK = Color3.fromRGB(255, 110, 190)   -- leuchtende Kopfhoerer-Muscheln (satt, kein Bloom, F17)

-- Easing nach Name ("inout" Standard; "in" beschleunigt, "out" bremst, "back"
-- federt ueber, "linear").
LOW.ease = function(name: string?, k: number): number
	k = math.clamp(k, 0, 1)
	if name == "linear" then return k end
	if name == "in" then return k * k end
	if name == "out" then return 1 - (1 - k) * (1 - k) end
	if name == "back" then return easeOutBack(k) end
	return 0.5 - 0.5 * math.cos(math.pi * k)
end

-- Bodenhoehe zwischen den Kaempfern an einem Punkt (Tower: beide Fuesse koennen
-- leicht verschieden hoch liegen).
LOW.groundY = function(ctx: Ctx, pos: Vector3): number
	local a, b = ctx.selfFeet, ctx.targetFeet
	local d = b - a
	local flat = Vector3.new(d.X, 0, d.Z)
	if flat.Magnitude < 0.01 then return a.Y end
	local u = math.clamp((pos - a):Dot(flat) / flat:Dot(flat), 0, 1)
	return lerpN(a.Y, b.Y, u)
end

-- Emitter-Anker mit Funken, Rauch und Schweif (wie in `ascend`), folgt dem Klon.
LOW.fxAnchor = function(ctx: Ctx, H: number, col: Color3, col2: Color3): (BasePart, ParticleEmitter, ParticleEmitter, Trail)
	local anchor = newPart(Enum.PartType.Block, Vector3.one * 0.2, col, PARK, 1)
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = SMOKE_TEX
	smoke.Rate = 0
	smoke.Speed = NumberRange.new(0.5, 2.5)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.Lifetime = NumberRange.new(0.45, 0.8)
	smoke.Drag = 2
	smoke.Acceleration = Vector3.new(0, 1.2, 0)
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, H * 0.22), NumberSequenceKeypoint.new(1, H * 0.55) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
	smoke.Color = ColorSequence.new(LOW.WHITE, col2)
	smoke.LightEmission = 0.3
	smoke.Rotation = NumberRange.new(0, 360)
	smoke.RotSpeed = NumberRange.new(-30, 30)
	smoke.Parent = anchor
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = SPARK_TEX
	sparks.Rate = 0
	sparks.Speed = NumberRange.new(4, 9)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Lifetime = NumberRange.new(0.3, 0.65)
	sparks.Drag = 2
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
	sparks.Color = ColorSequence.new(LOW.WHITE, col)
	sparks.LightEmission = 0.8
	sparks.Parent = anchor
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, H * 0.35, 0)
	a0.Parent = anchor
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -H * 0.35, 0)
	a1.Parent = anchor
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.25
	trail.LightEmission = 0.8
	trail.FaceCamera = true
	trail.Color = ColorSequence.new(LOW.WHITE, col)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	trail.Enabled = false
	trail.Parent = anchor
	return anchor, sparks, smoke, trail
end

-- Streusel: kleine bunte Staebchen fliegen aus `pos` auseinander und fallen
-- (Rig, EINE Schleife), verblassen in `life` s.
LOW.sprinkles = function(ctx: Ctx, pos: Vector3, n: number, life: number?)
	local rig: { RigPart } = {}
	local rng = Random.new()
	local colors = { Color3.fromRGB(255, 160, 211), LOW.WHITE, Color3.fromRGB(218, 196, 255), Color3.fromRGB(255, 232, 130), Color3.fromRGB(180, 255, 225) }
	for i = 1, scaled(n, ctx.factor) do
		local p = newPart(Enum.PartType.Cylinder, Vector3.new(0.55, 0.16, 0.16), colors[(i - 1) % #colors + 1], CFrame.new(pos), 0)
		p.Material = Enum.Material.SmoothPlastic
		p.Name = "Sprinkle"
		rigPart(rig, p, CFrame.new(rng:NextNumber(-0.3, 0.3), rng:NextNumber(-0.3, 0.3), rng:NextNumber(-0.3, 0.3))
			* CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0), p.Size, 0, 0, true)
	end
	rigApply(rig, CFrame.new(pos), function() return 1 end, 1)
	rigShatter(rig, pos - Vector3.new(0, 0.5, 0), 7)
	local L = life or 0.8
	runLoop("sprinkles", function(t, dt)
		if t >= L then return true end
		rigFly(rig, dt, math.clamp(1 - (t - L * 0.6) / (L * 0.4), 0, 1))
		return false
	end, function()
		for _, r in rig do r.p:Destroy() end
	end)
end

-- moves: der Baerchi SELBST (echter Klon, Original lokal unsichtbar, F03) folgt
-- Posen aus den Daten; zwischen zwei Posen wird weich ueberblendet. Felder je
-- Pose (siehe SkillFXConfig): t, at, dx/dy/dz, u/h/from/to, pitch/yaw/roll (in
-- Umdrehungen), scale, ease, arc, trail, burst, smoke, hidden, tip. Drehung,
-- Groesse, Hut und Sichtbarkeit erben von der Pose davor, Ort und Versatz nicht.
-- Setzt ctx.avatarCf, avatarScale, avatarModel.
--   keys, hat, outline, hold, gap (Test: freezeAt)
BLOCKS.moves = function(ctx, s)
	local source = ctx.selfModel
	if not source or not source.Parent then return end
	local keys = s.keys
	if type(keys) ~= "table" or #keys == 0 then return end
	local clone = figureClone(source)
	if not clone then return end
	local H = ctx.selfSize.Y
	local home = CFrame.lookAt(ctx.selfFeet, ctx.selfFeet + ctx.fwd)
	local offset = home:ToObjectSpace(clone:GetPivot())
	local okScale, got = pcall(function() return clone:GetScale() end)
	local baseScale: number = if okScale and typeof(got) == "number" then got else 1
	local gap = (ctx.selfSize.Z + ctx.targetSize.Z) * 0.4 + (s.gap or 0.4)
	local side = sideOf(ctx)
	local up = Vector3.yAxis
	-- `dxc`: seitlicher Versatz relativ zur Kamera-Seite (+ = zur Kamera hin), einmal beim Start (F22)
	local camSide = if camFace((ctx.selfFeet + ctx.targetFeet) / 2, side):Dot(side) >= 0 then 1 else -1
	local anchors: { [string]: Vector3 } = {
		home = ctx.selfFeet,
		land = ctx.targetFeet - ctx.fwd * gap,
		target = ctx.targetFeet,
		arena = (ctx.selfFeet + ctx.targetFeet) / 2,
	}
	local freezeAt: number? = s.freezeAt
	local hold = s.hold or 0.1
	local col = ctx.fx.color

	-- Posen auffuellen
	local poses: { { [string]: any } } = {}
	local start: { [string]: any } = { t = 0, pos = ctx.selfFeet, pitch = 0, yaw = 0, roll = 0, scale = 1, tip = 0,
		atName = "home", hidden = false, arc = 0, trail = false, burst = 0, smoke = 0, done = true }
	local prev = start
	for _, k in keys do
		local atName = k.at or prev.atName
		local pos: Vector3
		if k.u ~= nil then
			local a = anchors[k.from or "home"] or ctx.selfFeet
			local b = anchors[k.to or "land"] or anchors.land
			local u = math.clamp(k.u, 0, 1)
			if k.curve then
				-- Bruecke (kubische Bezier wie `rainbow`, Schub 2)
				pos = LOW.bridge(a, b, ctx.fwd, k.curve, k.tilt or 0.35, u)
			else
				pos = a:Lerp(b, u) + up * ((k.h or 0) * 4 * u * (1 - u))
			end
		else
			pos = anchors[atName] or ctx.selfFeet
		end
		pos += side * ((k.dx or 0) + (k.dxc or 0) * camSide) + up * (k.dy or 0) + ctx.fwd * (k.dz or 0)
		local p = {
			t = k.t or prev.t, pos = pos, atName = atName,
			pitch = if k.pitch ~= nil then k.pitch * TAU else prev.pitch,
			yaw = if k.yaw ~= nil then k.yaw * TAU else prev.yaw,
			roll = if k.roll ~= nil then k.roll * TAU else prev.roll,
			scale = k.scale or prev.scale,
			tip = k.tip or prev.tip,
			hidden = if k.hidden ~= nil then k.hidden == true else prev.hidden,
			ease = k.ease, arc = k.arc or 0, trail = k.trail == true,
			burst = k.burst or 0, smoke = k.smoke or 0, done = false,
		}
		table.insert(poses, p)
		prev = p
	end
	local total = prev.t + hold

	-- Hut: Teile, deren Name eines der Muster in `hat` (kommagetrennt) enthaelt;
	-- Lage relativ zum Pivot bei Groesse 1, Drehpunkt = Mitte des Huts.
	local hatParts: { { p: BasePart, rel: CFrame } } = {}
	local hatMid = Vector3.zero
	if type(s.hat) == "string" then
		local pv = clone:GetPivot()
		for _, d in clone:GetDescendants() do
			if d:IsA("BasePart") then
				for pat in string.gmatch(s.hat, "[^,]+") do
					if d.Name:find(pat, 1, true) then
						local rel = pv:ToObjectSpace(d.CFrame)
						table.insert(hatParts, { p = d, rel = rel })
						hatMid += rel.Position
						break
					end
				end
			end
		end
		if #hatParts > 0 then hatMid /= #hatParts end
	end

	-- Leuchtumriss (helle Modelle: satter Umriss, warm-weisse Fuellung, F37)
	local hl = Instance.new("Highlight")
	hl.Adornee = clone
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.FillColor = LOW.WHITE
	hl.FillTransparency = 0.9
	hl.OutlineColor = if typeof(s.outline) == "Color3" then s.outline else col
	hl.OutlineTransparency = 0.05
	hl.Parent = clone

	local anchor, sparks, smoke, trail = LOW.fxAnchor(ctx, H, col, ctx.fx.color2)
	local hide = hideFigure(source)
	local lastScale = 1
	local function place(feet: CFrame, pitch: number, yaw: number, roll: number, sc: number, tip: number, hidden: boolean)
		if math.abs(sc - lastScale) > 0.008 then
			lastScale = sc
			pcall(function() clone:ScaleTo(baseScale * sc) end)
		end
		local half = H * sc * 0.5
		local pose = feet * CFrame.new(0, half, 0) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, roll) * CFrame.new(0, -half, 0)
		ctx.avatarCf = pose
		ctx.avatarScale = sc
		local pv = pose * CFrame.new(offset.Position * sc) * offset.Rotation
		if hidden then pv += Vector3.new(0, 1500, 0) end
		clone:PivotTo(pv)
		if tip > 0.001 and #hatParts > 0 then
			-- Hut lueften: anheben und seitlich kippen, um die Hutmitte
			local lift = CFrame.new(hatMid * sc) * CFrame.new(0, H * sc * 0.22 * tip, 0)
				* CFrame.Angles(0, 0, -0.5 * tip) * CFrame.new(-hatMid * sc)
			for _, h in hatParts do
				h.p.CFrame = pv * lift * CFrame.new(h.rel.Position * sc) * h.rel.Rotation
			end
		end
		anchor.CFrame = pose * CFrame.new(0, half, 0)
	end
	place(home, 0, 0, 0, 1, 0, false)
	ctx.avatarModel = clone
	clone.Parent = folder()
	hide(1)

	runLoop("moves", function(tRaw)
		if not clone.Parent then return true end
		if tRaw >= (if freezeAt then freezeAt + 150 else total) then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		-- Segment a -> b finden
		local a, b = start, poses[#poses]
		for i, p in poses do
			if t < p.t then
				b = p
				a = if i > 1 then poses[i - 1] else start
				break
			end
			a = p
		end
		local pos: Vector3, pitch: number, yaw: number, roll: number, sc: number, tip: number
		if t >= b.t then
			-- letzte Pose halten (leichtes Atmen)
			pos = b.pos + up * (0.03 * math.sin(t * 5))
			pitch, yaw, roll, sc, tip = b.pitch, b.yaw, b.roll, b.scale, b.tip
		else
			local k = (t - a.t) / math.max(0.001, b.t - a.t)
			local e = LOW.ease(b.ease, k)
			pos = a.pos:Lerp(b.pos, e) + up * (b.arc * 4 * k * (1 - k))
			if b.arc == 0 and (b.pos - a.pos).Magnitude < 0.01 and b.t - a.t > 0.25 then
				pos += up * (0.03 * math.sin(t * 5))
			end
			pitch = lerpN(a.pitch, b.pitch, e)
			yaw = lerpN(a.yaw, b.yaw, e)
			roll = lerpN(a.roll, b.roll, e)
			sc = lerpN(a.scale, b.scale, e)
			tip = lerpN(a.tip, b.tip, e)
		end
		trail.Enabled = (t < b.t) and b.trail and not a.hidden
		place(CFrame.lookAt(pos, pos + ctx.fwd), pitch, yaw, roll, sc, tip, a.hidden)
		-- Ereignisse beim Erreichen einer Pose (genau einmal)
		for _, p in poses do
			if not p.done and t >= p.t then
				p.done = true
				if p.burst > 0 then sparks:Emit(scaled(p.burst, ctx.factor)) end
				if p.smoke > 0 then smoke:Emit(scaled(p.smoke, ctx.factor)) end
			end
		end
		return false
	end, function()
		hide(0)
		ctx.avatarCf = nil
		ctx.avatarScale = nil
		ctx.avatarModel = nil
		clone:Destroy()
		trail.Enabled = false
		Debris:AddItem(anchor, 1)
	end)
end

-- icepath: eine Eisbahn gefriert in `draw` s von den eigenen Fuessen bis vor den
-- Gegner: Eisplatten (Material Ice) ploppen nacheinander auf, Reifkanten, kleine
-- Eiszacken an den Raendern (Rig), Frostglitzer an der Gefrierfront; zwischen
-- `slideAt` und `slideEnd` folgt eine Schneefahne dem Klon (ctx.avatarCf); ab
-- `meltAt` taut alles weg (Platten blass, Zacken sinken). Test: freezeAt.
--   draw, width, plates, spikes, over, slideAt, slideEnd, meltAt, dur
BLOCKS.icepath = function(ctx, s)
	local draw = s.draw or 0.5
	local width = s.width or 2.4
	local nPlates = math.max(2, s.plates or 6)
	local nSpikes = if (s.spikes or 8) > 0 then scaled(s.spikes or 8, ctx.factor) else 0
	local slideAt = s.slideAt or 0.75
	local slideEnd = s.slideEnd or 1.5
	local meltAt = s.meltAt or 2.2
	local dur = s.dur or 2.7
	local freezeAt: number? = s.freezeAt
	local gap = (ctx.selfSize.Z + ctx.targetSize.Z) * 0.4 + 0.4
	local a = ctx.selfFeet - ctx.fwd * 0.6
	local b = ctx.targetFeet - ctx.fwd * (gap - (s.over or 0.8))
	local len = (b - a).Magnitude
	local side = sideOf(ctx)
	local col = ctx.fx.color

	-- Platten + Reifkanten
	type Plate = { p: BasePart, l: BasePart, r: BasePart, t0: number, w: number, seg: number, mid: Vector3, k: number }
	local plates: { Plate } = {}
	local segLen = len / nPlates
	for i = 1, nPlates do
		local u0 = (i - 1) / nPlates
		local u1 = i / nPlates
		local mid = a:Lerp(b, (u0 + u1) / 2)
		mid = Vector3.new(mid.X, LOW.groundY(ctx, mid) + 0.07, mid.Z)
		local w = width * (0.8 + 0.35 * u1)
		local cf = CFrame.lookAt(mid, mid + ctx.fwd)
		local p = newPart(Enum.PartType.Block, Vector3.new(0.1, 0.14, 0.1), LOW.DEEPICE, cf, 1)
		p.Material = Enum.Material.Ice
		p.Name = "IcePlate"
		local l = newPart(Enum.PartType.Block, Vector3.new(0.1, 0.18, 0.1), LOW.RIMBLUE, cf, 1)
		local r = newPart(Enum.PartType.Block, Vector3.new(0.1, 0.18, 0.1), LOW.RIMBLUE, cf, 1)
		table.insert(plates, { p = p, l = l, r = r, t0 = draw * u0, w = w, seg = segLen + 0.04, mid = mid, k = -1 })
	end
	-- Eiszacken an den Raendern (abwechselnd links/rechts), Spitze nach aussen gekippt
	local rig: { RigPart } = {}
	local rng = Random.new(7)
	for i = 1, nSpikes do
		local u = (i - 0.5) / nSpikes
		local sideSign = if i % 2 == 0 then 1 else -1
		local pos = a:Lerp(b, u)
		local w = width * (0.8 + 0.35 * u) * 0.5
		pos = Vector3.new(pos.X, LOW.groundY(ctx, pos) + 0.12, pos.Z) + side * (sideSign * (w + 0.05))
		local h = 0.7 + rng:NextNumber(0, 0.6) + u * 0.5
		-- Klingenebene quer zur Bahn (Dicke entlang der Bahn), nach aussen gekippt
		local frame = CFrame.fromMatrix(pos, ctx.fwd, Vector3.yAxis) * CFrame.Angles(0.35 * sideSign, 0, 0)
		addBlade(rig, frame, 0.22, h, 0.3, LOW.ICE, Enum.Material.Ice, draw * u + 0.05)
	end
	-- Glitzer an der Gefrierfront, spaeter Schneefahne hinter dem Klon (EIN Emitter)
	local anchor = newPart(Enum.PartType.Block, Vector3.one * 0.2, col, CFrame.new(a), 1)
	local em = Instance.new("ParticleEmitter")
	em.Texture = SPARK_TEX
	em.Rate = 0
	em.Speed = NumberRange.new(1, 3)
	em.SpreadAngle = Vector2.new(180, 180)
	em.Lifetime = NumberRange.new(0.3, 0.6)
	em.Drag = 2
	em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	em.Color = ColorSequence.new(LOW.RIME, col)
	em.LightEmission = 0.6
	em.Parent = anchor
	local snow = false
	local extras = extrasOn(ctx)
	local melting = false
	runLoop("icepath", function(tRaw)
		if tRaw >= (if freezeAt then freezeAt + 150 else dur) then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		-- Platten ploppen auf (Groesse federt, dann sichtbar)
		for _, pl in plates do
			local k = math.clamp((t - pl.t0) / 0.16, 0, 1)
			if k ~= pl.k then
				pl.k = k
				local e = easeOutBack(k)
				local w = math.max(0.05, pl.w * e)
				local sg = math.max(0.05, pl.seg * e)
				local cf = CFrame.lookAt(pl.mid, pl.mid + ctx.fwd)
				pl.p.Size = Vector3.new(w, 0.14, sg)
				pl.p.CFrame = cf
				pl.p.Transparency = if k > 0 then 0.05 else 1
				pl.l.Size = Vector3.new(0.1, 0.18, sg)
				pl.r.Size = pl.l.Size
				pl.l.CFrame = cf * CFrame.new(-w / 2, 0.02, 0)
				pl.r.CFrame = cf * CFrame.new(w / 2, 0.02, 0)
				pl.l.Transparency = if k > 0 then 0.25 else 1
				pl.r.Transparency = pl.l.Transparency
			end
		end
		-- Zacken wachsen mit der Front, sinken beim Tauen
		local melt = math.clamp((t - meltAt) / 0.45, 0, 1)
		rigApply(rig, CFrame.identity, function(r)
			return math.clamp((t - r.delay) / 0.2, 0, 1) * (1 - melt)
		end, 1 - melt)
		if t < draw then
			-- Glitzer an der Gefrierfront
			local front = a:Lerp(b, t / draw)
			anchor.CFrame = CFrame.new(Vector3.new(front.X, LOW.groundY(ctx, front) + 0.3, front.Z))
			em.Rate = if extras then 60 * ctx.factor else 0
		elseif t >= slideAt and t < slideEnd and ctx.avatarCf then
			-- Schneefahne hinter dem rutschenden Klon
			if not snow then
				snow = true
				em.EmissionDirection = Enum.NormalId.Front
				em.Speed = NumberRange.new(5, 11)
				em.SpreadAngle = Vector2.new(35, 35)
				em.Lifetime = NumberRange.new(0.35, 0.7)
				em.Drag = 1.2
				em.Acceleration = Vector3.new(0, -14, 0)
				em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1.1) })
				em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
				em.Color = ColorSequence.new(LOW.RIME, LOW.WHITE)
				em.LightEmission = 0.2
			end
			local av = ctx.avatarCf :: CFrame
			local tail = av.Position - ctx.fwd * 0.9 + Vector3.new(0, 0.3, 0)
			anchor.CFrame = CFrame.lookAt(tail, tail - ctx.fwd * 2 + Vector3.new(0, 1.4, 0))
			em.Rate = 90 * ctx.factor
		else
			em.Rate = 0
		end
		-- Tauen: Platten und Kanten blass (einmal getweent)
		if t >= meltAt and not melting then
			melting = true
			for _, pl in plates do
				tween(pl.p, 0.45, { Transparency = 1 })
				tween(pl.l, 0.3, { Transparency = 1 })
				tween(pl.r, 0.3, { Transparency = 1 })
			end
		end
		return false
	end, function()
		for _, pl in plates do pl.p:Destroy() pl.l:Destroy() pl.r:Destroy() end
		for _, r in rig do r.p:Destroy() end
		em.Rate = 0
		Debris:AddItem(anchor, 1)
	end)
end

-- iceblock: der Gegner steckt in einem Eisblock: Eis-Quader um die Figur (Ice-
-- Material) mit vier Reif-Stegen an den Kanten, hellblauer Leuchtumriss am
-- Original, Frosthauch; folgt der Figur (Server-Rueckstoss, Hopser). Bei
-- `breakAt` zerspringt der Block in Eissplitter (Rig), sonst verschwindet er
-- bei `dur`. Test: freezeAt.
--   at, appear, breakAt, dur, pad, small
BLOCKS.iceblock = function(ctx, s)
	local where = s.at or "target"
	local model = if where == "target" then ctx.targetModel else ctx.selfModel
	local size = sizeAt(ctx, where)
	local pad = s.pad or 0.5
	local full = Vector3.new(size.X + pad, size.Y + pad * 0.5, size.Z + pad)
	if s.small then full *= 0.75 end
	local appear = math.max(0.03, s.appear or 0.1)
	local breakAt: number? = s.breakAt
	local dur = s.dur or 1
	local freezeAt: number? = s.freezeAt
	local fallback = at(ctx, where)
	local block = newPart(Enum.PartType.Block, Vector3.one * 0.1, LOW.ICE, CFrame.new(fallback), 0.12)
	block.Material = Enum.Material.Ice
	block.Name = "IceBlock"
	local edges: { BasePart } = {}
	for _ = 1, 4 do
		table.insert(edges, newPart(Enum.PartType.Block, Vector3.new(0.12, 0.1, 0.12), LOW.RIME, CFrame.new(fallback), 0.3))
	end
	local hl: Highlight? = nil
	if model and model.Parent then
		local h = Instance.new("Highlight")
		h.Adornee = model
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.FillColor = Color3.fromRGB(205, 238, 255)
		h.FillTransparency = 0.55
		h.OutlineColor = LOW.RIME
		h.OutlineTransparency = 0.1
		h.Parent = folder()
		hl = h
	end
	-- Frosthauch (EIN Emitter)
	local anchor = newPart(Enum.PartType.Block, Vector3.one * 0.2, LOW.RIME, CFrame.new(fallback), 1)
	local em = Instance.new("ParticleEmitter")
	em.Texture = SMOKE_TEX
	em.Rate = if extrasOn(ctx) then 6 * ctx.factor else 0
	em.Speed = NumberRange.new(0.3, 0.8)
	em.SpreadAngle = Vector2.new(180, 180)
	em.Lifetime = NumberRange.new(0.6, 1.0)
	em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1.4) })
	em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
	em.Color = ColorSequence.new(LOW.RIME, LOW.ICE)
	em.LightEmission = 0.2
	em.Parent = anchor
	local side = sideOf(ctx)
	local rig: { RigPart } = {}
	local broken = false
	local brokenAt = 0
	local lastK = -1
	runLoop("iceblock", function(tRaw, dt)
		if tRaw >= (if freezeAt then freezeAt + 150 else dur) then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		if broken then
			-- Splitter fliegen und verblassen
			local k = math.clamp((t - brokenAt) / 0.5, 0, 1)
			if not freezeAt or tRaw < freezeAt then rigFly(rig, dt, 1 - k) end
			return false
		end
		local c = centerOf(model) or fallback
		local k = easeOutBack(math.clamp(t / appear, 0, 1))
		local sz = full * math.max(0.05, k)
		local cf = CFrame.fromMatrix(c, side, Vector3.yAxis)
		if k ~= lastK then
			lastK = k
			block.Size = sz
			for _, e in edges do e.Size = Vector3.new(0.12, sz.Y + 0.04, 0.12) end
		end
		block.CFrame = cf
		edges[1].CFrame = cf * CFrame.new(sz.X / 2, 0, sz.Z / 2)
		edges[2].CFrame = cf * CFrame.new(-sz.X / 2, 0, sz.Z / 2)
		edges[3].CFrame = cf * CFrame.new(sz.X / 2, 0, -sz.Z / 2)
		edges[4].CFrame = cf * CFrame.new(-sz.X / 2, 0, -sz.Z / 2)
		anchor.CFrame = cf
		if breakAt and t >= breakAt then
			-- zerspringen: Block weg, Eissplitter fliegen auseinander
			broken = true
			brokenAt = t
			block:Destroy()
			for _, e in edges do e:Destroy() end
			if hl then hl:Destroy() hl = nil end
			em.Rate = 0
			local rng = Random.new()
			for _ = 1, scaled(12, ctx.factor) do
				local sh = Vector3.new(0.25 + rng:NextNumber(0, 0.35), 0.3 + rng:NextNumber(0, 0.45), 0.2 + rng:NextNumber(0, 0.25))
				local p = newPart(Enum.PartType.Block, sh, LOW.ICE, cf, 0.1)
				p.Material = Enum.Material.Ice
				p.Name = "IceShard"
				local off = Vector3.new(rng:NextNumber(-0.5, 0.5) * sz.X, rng:NextNumber(-0.5, 0.5) * sz.Y, rng:NextNumber(-0.5, 0.5) * sz.Z)
				rigPart(rig, p, CFrame.new(off) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0), sh, 0, 0.1, true)
			end
			rigApply(rig, cf, function() return 1 end, 1)
			rigShatter(rig, c, 9)
			burstAt(ctx, c, 14, 7, LOW.RIME, true)
			burstAt(ctx, c, 18, 10, LOW.ICE)
		end
		return false
	end, function()
		if block.Parent then block:Destroy() end
		for _, e in edges do if e.Parent then e:Destroy() end end
		for _, r in rig do r.p:Destroy() end
		if hl then hl:Destroy() end
		em.Rate = 0
		Debris:AddItem(anchor, 1.2)
	end)
end

-- clawmarks: Krallenhiebe am Gegner. Je Hieb `claws` parallele Streifen
-- (Zylinder, F31) ziehen in `draw` s schraeg ueber die Vorderseite der Figur
-- (abwechselnd \ und /), Funken; sie gluehen hell und werden in `fade` s zu
-- schwelenden Kratzern (dunkelrot, pulsierend, Glutpartikel), die bis `dur` an
-- der Figur bleiben (folgen ihr). Test: freezeAt.
--   at, count, every, claws, len, draw, fade, dur
BLOCKS.clawmarks = function(ctx, s)
	local where = s.at or "target"
	local model = if where == "target" then ctx.targetModel else ctx.selfModel
	local size = sizeAt(ctx, where)
	local count = s.count or 3
	local every = s.every or 0.14
	local claws = s.claws or 3
	local len = s.len or 2.4
	local draw = math.max(0.03, s.draw or 0.07)
	local fade = s.fade or 0.3
	local dur = s.dur or 1.5
	local freezeAt: number? = s.freezeAt
	local col = ctx.fx.color
	local fallback = at(ctx, where)
	-- Ebene der Marken: Normale = Winkelhalbierende zwischen Richtung zum Angreifer
	-- und Richtung zur Kamera (einmal beim Start, F22) - so sieht der Spieler sie
	-- auch, wenn der Angreifer davor steht (F44)
	local toCam = camFace(fallback, -ctx.fwd)
	local nrm = (-ctx.fwd + toCam)
	nrm = if nrm.Magnitude > 0.1 then nrm.Unit else -ctx.fwd
	local side = Vector3.yAxis:Cross(nrm)
	side = if side.Magnitude > 0.1 then side.Unit else sideOf(ctx)
	local d = 0.17
	type Mark = { p: BasePart, start: Vector3, dir: Vector3, ang: number, t0: number, i: number }
	local marks: { Mark } = {}
	for i = 1, count do
		local ang = (if i % 2 == 1 then -1 else 1) * math.rad(50 + (i - 1) * 5)
		local dir = Vector3.new(math.cos(ang), math.sin(ang), 0)
		local shift = Vector3.new((i - (count + 1) / 2) * 0.3, (i - (count + 1) / 2) * -0.18, 0)
		local depth = size.Z * 0.5 + 0.12
		for c = 1, claws do
			local perp = Vector3.new(-dir.Y, dir.X, 0) * ((c - (claws + 1) / 2) * 0.3)
			local base = Vector3.new(0, size.Y * 0.05, depth) + shift + perp
			local p = newPart(Enum.PartType.Cylinder, Vector3.new(0.05, d, d), LOW.HOT, PARK, 1)
			p.Name = "ClawMark"
			table.insert(marks, { p = p, start = base - dir * (len / 2), dir = dir, ang = ang, t0 = (i - 1) * every, i = i })
		end
	end
	-- Glut (EIN Emitter), schwebt langsam hoch
	local anchor = newPart(Enum.PartType.Block, Vector3.one * 0.2, col, CFrame.new(fallback), 1)
	local em = Instance.new("ParticleEmitter")
	em.Texture = SPARK_TEX
	em.Rate = 0
	em.Speed = NumberRange.new(0.5, 1.5)
	em.SpreadAngle = Vector2.new(40, 40)
	em.Lifetime = NumberRange.new(0.5, 0.9)
	em.Acceleration = Vector3.new(0, 1.5, 0)
	em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.22), NumberSequenceKeypoint.new(1, 0) })
	em.Color = ColorSequence.new(col, LOW.EMBER)
	em.LightEmission = 0.7
	em.Parent = anchor
	local emberRate = if extrasOn(ctx) then 14 * ctx.factor else 0
	local parts: { BasePart } = table.create(#marks)
	local cfs: { CFrame } = table.create(#marks)
	local sparked: { [number]: boolean } = {}
	local fading = false
	runLoop("clawmarks", function(tRaw)
		if tRaw >= (if freezeAt then freezeAt + 150 else dur) then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		local c = centerOf(model) or fallback
		-- lokales System: X seitlich, Y hoch, +Z zum Angreifer (Vorderseite)
		local F = CFrame.fromMatrix(c, side, Vector3.yAxis, nrm)
		anchor.CFrame = F * CFrame.new(0, 0, size.Z * 0.5)
		for n, m in marks do
			local k = math.clamp((t - m.t0) / draw, 0, 1)
			local L = math.max(0.05, len * k)
			local center = m.start + m.dir * (L / 2)
			parts[n] = m.p
			cfs[n] = F * CFrame.new(center) * CFrame.Angles(0, 0, m.ang)
			if k > 0 then
				if not sparked[m.i] then
					sparked[m.i] = true
					burstAt(ctx, F:PointToWorldSpace(m.start + m.dir * (len / 2)), 14, 9, col)
				end
				local g = math.clamp(1 - (t - m.t0 - draw) / fade, 0, 1)
				m.p.Size = Vector3.new(L, d, d)
				m.p.Transparency = 0
				if g > 0.15 then
					m.p.Material = Enum.Material.Neon
					local warm = LOW.EMBER:Lerp(col, math.min(1, g * 2))
					m.p.Color = warm:Lerp(LOW.HOT, math.max(0, g * 2 - 1))
				else
					-- schwelender Kratzer: dunkelrot, pulsiert leicht
					m.p.Material = Enum.Material.SmoothPlastic
					m.p.Color = LOW.EMBER:Lerp(Color3.fromRGB(235, 90, 40), 0.3 + 0.3 * math.sin(t * 9 + m.i))
				end
			end
		end
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		em.Rate = if t > draw + 0.1 and t < dur - 0.35 then emberRate else 0
		if t >= dur - 0.3 and not fading then
			fading = true
			for _, m in marks do tween(m.p, 0.28, { Transparency = 1 }) end
		end
		return false
	end, function()
		for _, m in marks do m.p:Destroy() end
		em.Rate = 0
		Debris:AddItem(anchor, 1)
	end)
end

-- pawprints: leuchtende Pfotenspuren (Ballen + drei Zehen) fuehren im leichten
-- Zickzack von den eigenen Fuessen zum Platz vor dem Gegner, eine nach der
-- anderen (`every`, federnd); bei `pulseAt` blitzen alle weiss, ab `dur` - 0,4
-- verblassen sie. Test: freezeAt.
--   count, every, sway, pulseAt, dur
BLOCKS.pawprints = function(ctx, s)
	local count = s.count or 7
	local every = s.every or 0.09
	local sway = s.sway or 0.38
	local pulseAt: number? = s.pulseAt
	local dur = s.dur or 2.8
	local freezeAt: number? = s.freezeAt
	local col = ctx.fx.color
	local side = sideOf(ctx)
	local gap = (ctx.selfSize.Z + ctx.targetSize.Z) * 0.4 + (s.gap or 0.4)
	local a = ctx.selfFeet + ctx.fwd * 1.0
	local b = ctx.targetFeet - ctx.fwd * (gap + 0.3)
	type Print = { parts: { BasePart }, rel: { CFrame }, base: CFrame, t0: number, k: number }
	local prints: { Print } = {}
	for i = 1, count do
		local u = i / count
		local pos = a:Lerp(b, u) + side * (if i % 2 == 0 then sway else -sway)
		pos = Vector3.new(pos.X, LOW.groundY(ctx, pos) + 0.04, pos.Z)
		local base = CFrame.fromMatrix(pos, side, Vector3.yAxis) * CFrame.Angles(0, (if i % 2 == 0 then -0.12 else 0.12), 0)
		local parts: { BasePart } = {}
		local rel: { CFrame } = {}
		-- Ballen (flache Ellipse) + 3 Zehen vorn (vorn = lokal -Z)
		local pad = newPart(Enum.PartType.Cylinder, Vector3.new(0.05, 0.48, 0.4), col, PARK, 1)
		pad.Name = "PawPad"
		table.insert(parts, pad)
		table.insert(rel, CFrame.new(0, 0, 0.1) * CFrame.Angles(0, 0, math.rad(90)))
		for z = -1, 1 do
			local toe = newPart(Enum.PartType.Cylinder, Vector3.new(0.05, 0.17, 0.15), col, PARK, 1)
			toe.Name = "PawToe"
			table.insert(parts, toe)
			table.insert(rel, CFrame.new(z * 0.17, 0, -0.25 - (if z == 0 then 0.05 else 0)) * CFrame.Angles(0, 0, math.rad(90)))
		end
		table.insert(prints, { parts = parts, rel = rel, base = base, t0 = (i - 1) * every, k = -1 })
	end
	runLoop("pawprints", function(tRaw)
		if tRaw >= (if freezeAt then freezeAt + 150 else dur) then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		local flash = if pulseAt and t >= pulseAt then math.clamp(1 - (t - pulseAt) / 0.25, 0, 1) else 0
		local fade = math.clamp((t - (dur - 0.4)) / 0.4, 0, 1)
		for _, pr in prints do
			local k = math.clamp((t - pr.t0) / 0.14, 0, 1)
			if k ~= pr.k or flash > 0 or fade > 0 then
				pr.k = k
				local sc = math.max(0.05, easeOutBack(k))
				for n, p in pr.parts do
					local r = pr.rel[n]
					p.Size = Vector3.new(0.05, (if n == 1 then 0.48 else 0.17) * sc, (if n == 1 then 0.4 else 0.15) * sc)
					p.CFrame = pr.base * CFrame.new(r.Position * sc) * r.Rotation
					p.Transparency = if k > 0 then 0.25 * (1 - flash) + fade * 0.75 else 1
					p.Color = col:Lerp(LOW.WHITE, flash)
				end
			end
		end
		return false
	end, function()
		for _, pr in prints do for _, p in pr.parts do p:Destroy() end end
	end)
end

-- lensbeam: Brennglas. Eine grosse Lupe (Messingring aus 12 Zylinder-Stuecken,
-- Glas, Griff, Knauf) waechst in `appear` s aus der Pfote des Klons (seine
-- kleine Lupe - Teile mit "acc_lupe" im Namen - verschwindet so lange) vor
-- seinen Kopf; ab `beamAt` faellt eine weiche Lichtsaeule von oben in die Linse,
-- der gebuendelte Kegel trifft als Brennpunkt die Vorderseite des Gegners: der
-- Punkt wandert suchend, Rauch steigt, er wird weiss; bei `burnAt` Flammenstoss
-- (Funken, Feuerball, Glanz auf dem Glas), Strahlen aus; dann kehrt die Lupe
-- in `away` s in die Pfote zurueck. Ohne Klon: Lupe vor der eigenen Figur
-- (Echo, `small`). Test: freezeAt.
--   lens, appear, beamAt, burnAt, away, dur, small
BLOCKS.lensbeam = function(ctx, s)
	local lens = s.lens or 1.1
	local appear = math.max(0.03, s.appear or 0.25)
	local beamAt = s.beamAt or appear
	local burnAt = s.burnAt or 1.0
	local away = math.max(0.05, s.away or 0.25)
	local dur = s.dur or (burnAt + away + 0.15)
	local freezeAt: number? = s.freezeAt
	local col2 = ctx.fx.color2
	local up = Vector3.yAxis
	local H = ctx.selfSize.Y
	local targetModel = ctx.targetModel
	local tSize = ctx.targetSize

	-- Lupe: lokale Lagen (Linsenmitte = Ursprung, Z = Normale, Griff nach -Y)
	type Piece = { p: BasePart, rel: CFrame, size: Vector3 }
	local pieces: { Piece } = {}
	local d = 0.15 * lens
	local n = 12
	for i = 1, n do
		local a0 = (i - 1) / n * TAU
		local a1 = i / n * TAU
		local p0 = Vector3.new(math.cos(a0), math.sin(a0), 0) * lens
		local p1 = Vector3.new(math.cos(a1), math.sin(a1), 0) * lens
		local mid = (p0 + p1) / 2
		local segLen = (p1 - p0).Magnitude + 0.5 * d
		local p = newPart(Enum.PartType.Cylinder, Vector3.new(segLen, d, d), LOW.GOLD, PARK, 1)
		p.Material = Enum.Material.SmoothPlastic
		p.Reflectance = 0.15
		p.Name = "LensRing"
		table.insert(pieces, { p = p, rel = CFrame.lookAt(mid, p1, Vector3.zAxis) * CFrame.Angles(0, math.rad(90), 0), size = p.Size })
	end
	local glass = newPart(Enum.PartType.Cylinder, Vector3.new(0.06, lens * 1.9, lens * 1.9), Color3.fromRGB(205, 240, 255), PARK, 1)
	glass.Material = Enum.Material.Glass
	glass.Reflectance = 0.1
	glass.Name = "LensGlass"
	table.insert(pieces, { p = glass, rel = CFrame.Angles(0, math.rad(90), 0), size = glass.Size })
	local grip = newPart(Enum.PartType.Cylinder, Vector3.new(lens * 1.25, d * 1.3, d * 1.3), LOW.BRASS, PARK, 1)
	grip.Material = Enum.Material.SmoothPlastic
	grip.Name = "LensGrip"
	table.insert(pieces, { p = grip, rel = CFrame.new(0, -(lens + lens * 0.62), 0) * CFrame.Angles(0, 0, math.rad(90)), size = grip.Size })
	local knob = newPart(Enum.PartType.Ball, Vector3.one * d * 2, LOW.BRASS, PARK, 1)
	knob.Material = Enum.Material.SmoothPlastic
	knob.Name = "LensKnob"
	table.insert(pieces, { p = knob, rel = CFrame.new(0, -(lens + lens * 1.25), 0), size = knob.Size })
	local parts: { BasePart } = table.create(#pieces)
	local cfs: { CFrame } = table.create(#pieces)

	-- kleine Lupe des Klons ausblenden, solange die grosse da ist
	local smallParts: { { p: BasePart, tr: number } } = {}
	local smallGlass: BasePart? = nil
	local function findSmall()
		local m = ctx.avatarModel
		if not m or #smallParts > 0 then return end
		for _, p in m:GetDescendants() do
			if p:IsA("BasePart") and p.Name:find("acc_lupe", 1, true) then
				table.insert(smallParts, { p = p, tr = p.Transparency })
				if p.Name:find("glas", 1, true) then smallGlass = p end
			end
		end
	end
	local function smallShown(v: boolean)
		for _, e in smallParts do
			if e.p.Parent then e.p.Transparency = if v then e.tr else 1 end
		end
	end
	local function pawPos(): Vector3
		if smallGlass and smallGlass.Parent then return smallGlass.Position end
		local av = ctx.avatarCf or CFrame.lookAt(ctx.selfFeet, ctx.selfFeet + ctx.fwd)
		return (av * CFrame.new(-0.5, H * 0.45, -0.6)).Position
	end
	local function hoverPos(): Vector3
		local av = ctx.avatarCf or CFrame.lookAt(ctx.selfFeet, ctx.selfFeet + ctx.fwd)
		return (av * CFrame.new(0.3, H * 1.0, -H * 0.55)).Position
	end
	local function spotBase(): Vector3
		local c = centerOf(targetModel) or ctx.targetPos
		return c - ctx.fwd * (tSize.Z * 0.5 + 0.05) + up * (tSize.Y * 0.1)
	end

	-- Strahlen (Beams an einem Anker), Brennpunkt, Rauch
	local beamAnchor = newPart(Enum.PartType.Block, Vector3.one * 0.2, LOW.HOT, PARK, 1)
	local function att(): Attachment
		local a = Instance.new("Attachment")
		a.Parent = beamAnchor
		return a
	end
	local sunA, sunB, focA, focB = att(), att(), att(), att()
	local function beam(a: Attachment, b: Attachment, w0: number, w1: number, t0: number, t1: number, emission: number): Beam
		local bm = Instance.new("Beam")
		bm.Attachment0 = a
		bm.Attachment1 = b
		bm.Width0 = w0
		bm.Width1 = w1
		bm.FaceCamera = true
		bm.Segments = 1
		bm.LightEmission = emission
		bm.LightInfluence = 0
		bm.Color = ColorSequence.new(Color3.fromRGB(255, 246, 210), LOW.HOT)
		bm.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, t0), NumberSequenceKeypoint.new(1, t1) })
		bm.Enabled = false
		bm.Parent = beamAnchor
		return bm
	end
	local sun = beam(sunA, sunB, 2.4 * lens, 1.9 * lens, 0.82, 0.6, 0.35)
	local focus = beam(focA, focB, 1.75 * lens, 0.14, 0.45, 0.1, 0.55)
	local spot = newPart(Enum.PartType.Ball, Vector3.one * 0.2, LOW.HOT, PARK, 1)
	spot.Name = "LensSpot"
	local glow = newPart(Enum.PartType.Ball, Vector3.one * 0.6, col2, PARK, 1)
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = SMOKE_TEX
	smoke.Rate = 0
	smoke.Speed = NumberRange.new(0.8, 1.6)
	smoke.SpreadAngle = Vector2.new(25, 25)
	smoke.Lifetime = NumberRange.new(0.6, 1.1)
	smoke.Acceleration = Vector3.new(0, 1.5, 0)
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1.1) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
	smoke.Color = ColorSequence.new(Color3.fromRGB(120, 110, 100), Color3.fromRGB(70, 60, 60))
	smoke.LightEmission = 0
	smoke.Parent = spot

	local burned = false
	local gone = false
	local lastSc = -1
	runLoop("lensbeam", function(tRaw)
		if tRaw >= (if freezeAt then freezeAt + 150 else dur) then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		if gone then return false end
		findSmall()
		-- Lage und Groesse der Lupe
		local sc: number
		local lensPos: Vector3
		if t < appear then
			local k = easeOutBack(t / appear)
			sc = lerpN(0.3, 1, k)
			lensPos = pawPos():Lerp(hoverPos(), k)
			smallShown(false)
		elseif t < burnAt + 0.1 then
			sc = 1
			lensPos = hoverPos()
		else
			local k = easeInOutSine(math.clamp((t - burnAt - 0.1) / away, 0, 1))
			sc = lerpN(1, 0.3, k)
			lensPos = hoverPos():Lerp(pawPos(), k)
			if k >= 1 then
				gone = true
				smallShown(true)
				for _, pc in pieces do pc.p.Transparency = 1 end
				return false
			end
		end
		local spotPos = spotBase()
		local toSpot = spotPos - lensPos
		local nrm = (up + (if toSpot.Magnitude > 0.1 then toSpot.Unit else ctx.fwd)).Unit
		local L = CFrame.lookAt(lensPos, lensPos + nrm)
		if sc ~= lastSc then
			lastSc = sc
			for _, pc in pieces do pc.p.Size = pc.size * sc end
		end
		for i, pc in pieces do
			parts[i] = pc.p
			cfs[i] = L * CFrame.new(pc.rel.Position * sc) * pc.rel.Rotation
			if pc.p.Transparency > 0.99 and t > 0 then
				pc.p.Transparency = if pc.p == glass then 0.4 else 0
			end
		end
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		-- Strahlen und Brennpunkt
		if t >= beamAt and t < burnAt then
			local g = math.clamp((t - beamAt) / math.max(0.05, burnAt - beamAt), 0, 1)
			local w = math.clamp((burnAt - t) / 0.3, 0, 1)
			local wander = sideOf(ctx) * (0.3 * math.sin(t * 5.3) * w) + up * (0.25 * math.cos(t * 3.9) * w)
			local sp = spotPos + wander
			sun.Enabled = true
			focus.Enabled = true
			sunA.WorldPosition = lensPos + up * 14
			sunB.WorldPosition = lensPos
			focA.WorldPosition = lensPos
			focB.WorldPosition = sp
			spot.CFrame = CFrame.new(sp)
			spot.Size = Vector3.one * (0.2 + 0.3 * g)
			spot.Transparency = 0
			spot.Color = col2:Lerp(LOW.WHITE, g)
			glow.CFrame = CFrame.new(sp)
			glow.Size = Vector3.one * (0.5 + 0.9 * g)
			glow.Transparency = 0.85 - 0.25 * g
			smoke.Rate = if extrasOn(ctx) then (6 + 16 * g) * ctx.factor else 0
		elseif t >= burnAt and not burned then
			-- Flammenstoss: Funken, Feuerball, Rauchpuff, Glanz auf dem Glas
			burned = true
			sun.Enabled = false
			focus.Enabled = false
			spot.Transparency = 1
			glow.Transparency = 1
			smoke.Rate = 0
			burstAt(ctx, spotPos, 26, 10, col2)
			burstAt(ctx, spotPos + up * 0.3, 10, 3, Color3.fromRGB(90, 80, 80), true)
			local fire = newPart(Enum.PartType.Ball, Vector3.one * 0.5, col2:Lerp(LOW.WHITE, 0.45), CFrame.new(spotPos), 0.3)
			fire.Name = "LensFire"
			tween(fire, 0.22, { Size = Vector3.one * 1.9, Transparency = 1 }, Enum.EasingStyle.Quad)
			Debris:AddItem(fire, 0.3)
			twinkle(lensPos + up * (lens * 0.7), lens * 1.1, LOW.WHITE, 0.3)
			glass.Color = LOW.WHITE
			glass.Transparency = 0.1
			tween(glass, 0.25, { Color = Color3.fromRGB(205, 240, 255), Transparency = 0.4 })
		end
		return false
	end, function()
		smallShown(true)
		for _, pc in pieces do pc.p:Destroy() end
		spot:Destroy()
		glow:Destroy()
		beamAnchor:Destroy()
	end)
end

-- djset: Bass-Drop. Unter dem DJ dreht sich eine Schallplatte (dunkle Scheibe,
-- rosa Rillen und Label als SurfaceGui), rund um die Arena stehen `bars`
-- Equalizer-Balken (Neon, rosa/weiss/violett, Luecke zur Kamera, F44), die bei
-- jedem Eintrag in `beats` hochzucken (Bodenring, Kopfhoerer-Muscheln des Klons
-- leuchten kurz); ab `buildAt` steigen alle Balken zitternd an, die Platte rast;
-- bei `dropAt` der Drop: Label blitzt, Balken schlagen voll aus, Schockwelle
-- (`wave` + Bodenring bis zum Zaun), Streusel am Gegner; danach sinken die
-- Balken, die Platte bremst und verblasst. Test: freezeAt.
--   beats, buildAt, dropAt, dur, bars, radius, disc
BLOCKS.djset = function(ctx, s)
	local beats: { number } = s.beats or { 0.5, 1.0, 1.5 }
	local buildAt = s.buildAt or 1.55
	local dropAt = s.dropAt or 2.0
	local dur = s.dur or 2.9
	local nBars = scaled(s.bars or 14, ctx.factor)
	local R = radiusOf(s.radius, 7.5)
	local D = s.disc or 4.6
	local freezeAt: number? = s.freezeAt
	local col = ctx.fx.color
	local col2 = ctx.fx.color2
	local feet = ctx.selfFeet
	local center = Vector3.new(feet.X, feet.Y + 0.07, feet.Z)
	local arena = groundAt(ctx, "arena")

	-- Schallplatte: Scheibe + unsichtbare Platte mit SurfaceGui (Rillen, Label)
	local disc = newPart(Enum.PartType.Cylinder, Vector3.new(0.14, 0.2, 0.2), LOW.VINYL, CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)), 0)
	disc.Material = Enum.Material.SmoothPlastic
	disc.Reflectance = 0.08
	disc.Name = "DjDisc"
	local plate = newPart(Enum.PartType.Block, Vector3.new(0.2, 0.05, 0.2), col, CFrame.new(center + Vector3.new(0, 0.08, 0)), 1)
	plate.Name = "DjLabel"
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 32
	gui.LightInfluence = 0
	gui.Brightness = 1.25
	gui.Adornee = plate
	gui.Parent = plate
	local function roundFrame(parent: Instance, scale: number, color: Color3?, stroke: number?): Frame
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(0.5, 0.5)
		f.Size = UDim2.fromScale(scale, scale)
		f.BorderSizePixel = 0
		f.BackgroundTransparency = if color then 0.05 else 1
		if color then f.BackgroundColor3 = color end
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = f
		if stroke then
			local st = Instance.new("UIStroke")
			st.Color = col
			st.Thickness = stroke
			st.Transparency = 0.15
			st.Parent = f
		end
		f.Parent = parent
		return f
	end
	roundFrame(gui, 0.9, nil, 4)
	roundFrame(gui, 0.76, nil, 3)
	roundFrame(gui, 0.62, nil, 3)
	roundFrame(gui, 0.5, nil, 2)
	local label = roundFrame(gui, 0.34, col, nil)
	for _, rot in { 45, 135 } do
		local b = Instance.new("Frame")
		b.AnchorPoint = Vector2.new(0.5, 0.5)
		b.Position = UDim2.fromScale(0.5, 0.5)
		b.Size = UDim2.fromScale(0.7, 0.12)
		b.Rotation = rot
		b.BackgroundColor3 = LOW.WHITE
		b.BackgroundTransparency = 0.2
		b.BorderSizePixel = 0
		b.Parent = label
	end
	roundFrame(gui, 0.07, LOW.VINYL, nil)

	-- Equalizer-Balken rund um die Arena, Luecke zur Kamera (F44)
	local camDir = camFace(arena, -ctx.fwd)
	local baseAng = math.atan2(camDir.Z, camDir.X)
	local gapHalf = math.rad(38)
	local span = TAU - 2 * gapHalf
	type Bar = { p: BasePart, pos: Vector3, h: number, goal: number, seed: number }
	local bars: { Bar } = {}
	local palette = { col, LOW.WHITE, col2 }
	for i = 1, nBars do
		local ang = baseAng + gapHalf + span * (i - 0.5) / nBars
		local pos = Vector3.new(arena.X + math.cos(ang) * R, arena.Y, arena.Z + math.sin(ang) * R)
		local p = newPart(Enum.PartType.Block, Vector3.new(0.55, 0.3, 0.3), palette[(i - 1) % 3 + 1], CFrame.new(pos), 0.3)
		p.Name = "DjBar"
		table.insert(bars, { p = p, pos = pos, h = 0.3, goal = 0.3, seed = i * 0.37 })
	end
	local function hash(a: number, b: number): number
		local x = math.sin(a * 12.9898 + b * 78.233) * 43758.5453
		return x - math.floor(x)
	end
	-- Kopfhoerer-Muscheln des Klons (Teile mit "cup" oder "kopfhoerer" im Namen)
	local cups: { { p: BasePart, mat: Enum.Material, col: Color3 } } = {}
	local function findCups()
		if #cups > 0 then return end
		local m = ctx.avatarModel
		if m then
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") and (d.Name:find("cup", 1, true) or d.Name:find("kopfhoerer", 1, true)) then
					table.insert(cups, { p = d, mat = d.Material, col = d.Color })
				end
			end
		end
	end
	local cupUntil = -1
	local function pulseCups(t: number)
		findCups()
		cupUntil = t + 0.14
		for _, c in cups do
			if c.p.Parent then c.p.Material = Enum.Material.Neon c.p.Color = LOW.DEEPPINK end
		end
	end
	local function restoreCups()
		for _, c in cups do
			if c.p.Parent then c.p.Material = c.mat c.p.Color = c.col end
		end
	end

	local spin = 0
	local dropped = false
	local lastBeatCount = 0
	local labelFlash = 0
	runLoop("djset", function(tRaw, dt)
		if tRaw >= (if freezeAt then freezeAt + 150 else dur) then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		local step = if freezeAt and tRaw >= freezeAt then 0 else dt
		-- Platte: dreht (33 rpm), rast im Build-up, bremst nach dem Drop
		local rps = 0.6
		if t >= buildAt and t < dropAt then
			rps = 0.6 + 2.2 * (t - buildAt) / math.max(0.1, dropAt - buildAt)
		elseif t >= dropAt then
			rps = math.max(0, 2.8 - (t - dropAt) * 4)
		end
		spin += TAU * rps * step
		local grow = easeOutBack(math.clamp(t / 0.25, 0, 1))
		disc.Size = Vector3.new(0.14, math.max(0.1, D * grow), math.max(0.1, D * grow))
		disc.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)) * CFrame.Angles(spin, 0, 0)
		plate.Size = Vector3.new(math.max(0.1, D * grow), 0.05, math.max(0.1, D * grow))
		plate.CFrame = CFrame.new(center + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, spin, 0)
		-- Beats: Balken-Ziele neu wuerfeln, Bodenring, Muscheln
		local nBeat = 0
		for i, bt in beats do if t >= bt then nBeat = i end end
		if nBeat > lastBeatCount then
			lastBeatCount = nBeat
			for i, b in bars do b.goal = 1.0 + 3.0 * hash(i, nBeat) end
			BLOCKS.ring(ctx, { at = "self", ground = true, radius = D * 0.5 + 2.5 + nBeat * 0.6, dur = 0.4 })
			pulseCups(t)
		end
		if cupUntil >= 0 and t > cupUntil then
			cupUntil = -1
			restoreCups()
		end
		-- Build-up: alle Balken steigen zitternd
		if t >= buildAt and t < dropAt then
			local k = (t - buildAt) / math.max(0.1, dropAt - buildAt)
			for _, b in bars do b.goal = 1.5 + 2.7 * k + 0.3 * math.sin(t * 40 + b.seed) end
		end
		if t >= dropAt and not dropped then
			dropped = true
			for _, b in bars do b.goal = 5.2 b.h = 5.2 end
			labelFlash = 1
			BLOCKS.wave(ctx, { at = "self", radius = 12, dur = 0.5 })
			BLOCKS.ring(ctx, { at = "self", ground = true, toArena = true, radius = "fence", dur = 0.55 })
			LOW.sprinkles(ctx, ctx.targetPos + Vector3.new(0, ctx.targetSize.Y * 0.4, 0), 40, 0.8)
			pulseCups(t)
		end
		if t >= dropAt + 0.12 then
			for _, b in bars do b.goal = 0.3 end
		end
		-- Balken federn zu ihrem Ziel; nach dem Drop verblassen sie
		local alpha = if t >= dropAt + 0.3 then math.clamp(1 - (t - dropAt - 0.3) / 0.5, 0, 1) else 1
		local appear = math.clamp(t / 0.3, 0, 1)
		for _, b in bars do
			b.h += (b.goal - b.h) * math.min(1, step * 14)
			local h = math.max(0.15, b.h * appear)
			b.p.Size = Vector3.new(0.55, h, 0.3)
			local mid = b.pos + Vector3.new(0, h / 2, 0)
			b.p.CFrame = CFrame.lookAt(mid, Vector3.new(arena.X, mid.Y, arena.Z))
			b.p.Transparency = 0.3 + 0.7 * (1 - alpha)
		end
		-- Label-Blitz beim Drop, Platte verblasst am Ende
		if labelFlash > 0 then
			labelFlash = math.max(0, labelFlash - step * 5)
			label.BackgroundColor3 = col:Lerp(LOW.WHITE, labelFlash)
		end
		if t >= dur - 0.4 then
			local f = (t - (dur - 0.4)) / 0.4
			disc.Transparency = f
			gui.Enabled = f < 0.5
		end
		return false
	end, function()
		restoreCups()
		disc:Destroy()
		plate:Destroy()
		for _, b in bars do b.p:Destroy() end
	end)
end

-- ---------------------------------------------------------------------------
-- Schub 2 (25.10.2026): Muenzregen (Grizzly), Shuriken-Sturm (Ninja),
-- Wurzelwall (Uralter), Regenbogenbruecke (Regenbogen) - Stufe 3, ohne
-- Kamerafahrt. Helfer wieder in LOW.
-- ---------------------------------------------------------------------------

LOW.BARK = Color3.fromRGB(96, 64, 40)          -- Wurzelrinde
LOW.MOSS = Color3.fromRGB(124, 196, 108)       -- Moos, Blaetter (wie die Blattkrone)
LOW.STEEL = Color3.fromRGB(225, 227, 234)      -- Shuriken, Klinge
LOW.NINJARED = Color3.fromRGB(231, 63, 75)     -- Stirnband
LOW.INK = Color3.fromRGB(34, 28, 62)           -- Schattenklone
LOW.DARKGOLD = Color3.fromRGB(190, 150, 60)    -- dunklere Muenzen
LOW.COINGOLD = Color3.fromRGB(255, 200, 60)    -- Muenzen (satt, wenig Reflexion - sonst blass vor dem Himmel)

-- Punkt auf der Bruecke von a nach b (kubische Bezier wie ein Beam mit
-- CurveSize `c`: Tangenten am Anfang hoch-vorwaerts, am Ende runter-vorwaerts;
-- `tilt` = Vorwaertsanteil der Tangenten). `moves` (Pose mit `curve`) und
-- `rainbow` nutzen dieselbe Formel - der Baerchi laeuft genau auf den Baendern.
LOW.bridge = function(a: Vector3, b: Vector3, fwd: Vector3, c: number, tilt: number, u: number): Vector3
	local up = Vector3.yAxis
	local t0 = (fwd * tilt + up).Unit
	local t1 = (fwd * tilt - up).Unit
	local p1 = a + t0 * c
	local p2 = b - t1 * c
	local v = 1 - u
	return a * (v * v * v) + p1 * (3 * v * v * u) + p2 * (3 * v * u * u) + b * (u * u * u)
end

-- Zylinder-Stueck von p nach q (F31: Laenge + 0,5 d, Achse X entlang der Strecke)
LOW.tube = function(p: BasePart, a: Vector3, b: Vector3, d: number, f: number)
	local dir = b - a
	local L = math.max(0.05, dir.Magnitude * f)
	local u = if dir.Magnitude > 0.01 then dir.Unit else Vector3.yAxis
	p.Size = Vector3.new(L + 0.5 * d, d, d)
	p.CFrame = CFrame.lookAt(a + u * (L / 2), a + u * (L / 2 + 1), if math.abs(u.Y) > 0.9 then Vector3.xAxis else Vector3.yAxis) * CFrame.Angles(0, math.rad(90), 0)
end

-- Ein Vierstern-Shuriken (zwei gekreuzte Klingen + roter Kern) als Modell;
-- `set(cf)` setzt ihn (lokale Ebene XY, Normale Z).
LOW.shuriken = function(size: number): (Model, (CFrame) -> ())
	local m = Instance.new("Model")
	m.Name = "Shuriken"
	local parts: { BasePart } = {}
	local rels: { CFrame } = {}
	for _, ang in { 0, 90 } do
		local blade = Instance.new("Part")
		prepPart(blade, LOW.STEEL, PARK, 0)
		blade.Material = Enum.Material.SmoothPlastic
		blade.Reflectance = 0.2
		blade.Size = Vector3.new(size, size * 0.2, 0.06)
		blade.Parent = m
		table.insert(parts, blade)
		table.insert(rels, CFrame.Angles(0, 0, math.rad(ang)))
	end
	local core = Instance.new("Part")
	core.Shape = Enum.PartType.Ball
	prepPart(core, LOW.NINJARED, PARK, 0)
	core.Size = Vector3.one * size * 0.22
	core.Parent = m
	table.insert(parts, core)
	table.insert(rels, CFrame.identity)
	m.Parent = folder()
	local cfs: { CFrame } = table.create(#parts)
	return m, function(cf: CFrame)
		for i, p in parts do cfs[i] = cf * rels[i] end
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- coinshower: Muenzregen. Bei `burstAt` spritzen `count` Goldmuenzen (flache
-- Zylinder, drehen sich) aus den Fuessen des Gegners nach oben (Funken), fliegen
-- dann nacheinander im Bogen zum Angreifer und tuermen sich dort zu einem
-- Haufen (Goldhuegel + liegende Muenzen); Glitzer am Haufen, Medaille und Rubin
-- des Klons (acc_medal, acc_ruby) blitzen bei jeder dritten Muenze; am Ende
-- sinkt der Haufen weg. `small`: Echo. Test: freezeAt.
--   count, burstAt, rise, fly, every, dur, small
BLOCKS.coinshower = function(ctx, s)
	local count = scaled(s.count or 18, ctx.factor)
	local eruptAt = s.burstAt or 0
	local rise = s.rise or 0.3
	local fly = s.fly or 0.55
	local every = s.every or 0.045
	local dur = s.dur or 2.0
	local small = s.small == true
	local freezeAt: number? = s.freezeAt
	local up = Vector3.yAxis
	local targetModel = ctx.targetModel
	local selfFeet = ctx.selfFeet
	local pileScale = if small then 0.5 else 1
	type Coin = { p: BasePart, t0: number, v: Vector3, axis: Vector3, start: Vector3?, done: boolean, dx: number, dz: number }
	local coins: { Coin } = {}
	local rng = Random.new(3)
	for i = 1, count do
		local p = newPart(Enum.PartType.Cylinder, Vector3.new(0.12, 0.75, 0.75), if i % 3 == 0 then LOW.DARKGOLD else LOW.COINGOLD, PARK, 1)
		p.Material = Enum.Material.SmoothPlastic
		p.Reflectance = 0.08
		p.Name = "Coin"
		local a = rng:NextNumber(-1.2, 1.2)
		local spread = rng:NextNumber(1.5, 3.5)
		-- Startgeschwindigkeit: steil hoch, leicht zum Angreifer hin (nicht im Gegner bleiben)
		table.insert(coins, {
			p = p, t0 = eruptAt + (i - 1) * every,
			v = (-ctx.fwd) * (math.cos(a) * spread) + sideOf(ctx) * (math.sin(a) * spread) + up * rng:NextNumber(9, 12),
			axis = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)).Unit,
			start = nil, done = false, dx = rng:NextNumber(-0.5, 0.5), dz = rng:NextNumber(-0.4, 0.4),
		})
	end
	-- Goldhaufen (Ellipsoid) + liegende Muenzen obenauf
	local pile = newPart(Enum.PartType.Block, Vector3.one * 0.1, LOW.GOLD, CFrame.new(selfFeet), 1)
	pile.Material = Enum.Material.SmoothPlastic
	pile.Reflectance = 0.2
	pile.Name = "CoinPile"
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = pile
	local resting: { BasePart } = {}
	local restCf: { CFrame } = {}
	for i = 1, 6 do
		local p = newPart(Enum.PartType.Cylinder, Vector3.new(0.12, 0.75, 0.75), if i % 2 == 0 then LOW.DARKGOLD else LOW.COINGOLD, PARK, 1)
		p.Material = Enum.Material.SmoothPlastic
		p.Reflectance = 0.08
		p.Name = "CoinRest"
		table.insert(resting, p)
		local a = i / 6 * TAU
		table.insert(restCf, CFrame.new(math.cos(a) * 0.8 * pileScale, 0, math.sin(a) * 0.7 * pileScale) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, TAU), math.rad(90) + rng:NextNumber(-0.3, 0.3)))
	end
	-- Glitzer am Haufen (EIN Emitter)
	local glitAnchor = newPart(Enum.PartType.Block, Vector3.one * 0.2, LOW.GOLD, CFrame.new(selfFeet + up * 0.5), 1)
	local glit = Instance.new("ParticleEmitter")
	glit.Texture = SPARK_TEX
	glit.Rate = 0
	glit.Speed = NumberRange.new(1, 3)
	glit.SpreadAngle = Vector2.new(70, 70)
	glit.Lifetime = NumberRange.new(0.4, 0.8)
	glit.Drag = 2
	glit.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	glit.Color = ColorSequence.new(LOW.WHITE, LOW.GOLD)
	glit.LightEmission = 0.7
	glit.Parent = glitAnchor
	-- Medaille/Rubin des Klons
	local medals: { BasePart } = {}
	local function findMedals()
		local m = ctx.avatarModel
		if not m or #medals > 0 then return end
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") and (d.Name:find("acc_medal", 1, true) or d.Name:find("acc_ruby", 1, true)) then table.insert(medals, d) end
		end
	end
	local parts: { BasePart } = table.create(count)
	local cfs: { CFrame } = table.create(count)
	local arrived = 0
	local burstDone = false
	local lastPile = -1
	runLoop("coinshower", function(tRaw)
		if tRaw >= (if freezeAt then freezeAt + 150 else dur) then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		local tFeet = (centerOf(targetModel) or ctx.targetPos) - up * (ctx.targetSize.Y * 0.5)
		local pileTop = selfFeet + up * (0.35 * pileScale)
		if t >= eruptAt and not burstDone then
			burstDone = true
			burstAt(ctx, tFeet + up * 0.4, 20, 8, LOW.GOLD)
		end
		local n = 0
		for _, c in coins do
			local tau = t - c.t0
			local cf: CFrame
			if tau < 0 or c.done then
				cf = PARK
			elseif tau < rise then
				-- 1. nach oben spritzen (ballistisch)
				if not c.start then c.start = tFeet + up * 0.3 - ctx.fwd * (ctx.targetSize.Z * 0.45) + Vector3.new(c.dx, 0, c.dz) end
				local pos = (c.start :: Vector3) + c.v * tau + up * (-18 * tau * tau)
				cf = CFrame.new(pos) * CFrame.fromAxisAngle(c.axis, tau * 14)
				c.p.Transparency = 0
			else
				-- 2. im Bogen zum Angreifer, dann im Haufen verschwinden
				local k = math.clamp((tau - rise) / fly, 0, 1)
				local from = (c.start :: Vector3) + c.v * rise + up * (-18 * rise * rise)
				local to = pileTop + Vector3.new(c.dx * 0.8, 0, c.dz * 0.8)
				local ctrl = (from + to) / 2 + up * 3.5
				local pos = bez2(from, ctrl, to, k)
				cf = CFrame.new(pos) * CFrame.fromAxisAngle(c.axis, tau * 14)
				if k >= 1 then
					c.done = true
					c.p.Transparency = 1
					arrived += 1
					if not freezeAt or tRaw < freezeAt then
						glit:Emit(scaled(4, ctx.factor))
						if arrived % 3 == 0 then
							findMedals()
							for _, md in medals do twinkle(md.Position - ctx.fwd * 0.15, 0.9, LOW.WHITE, 0.3) end
						end
					end
					cf = PARK
				end
			end
			n += 1
			parts[n] = c.p
			cfs[n] = cf
		end
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		-- Haufen waechst mit den angekommenen Muenzen, sinkt am Ende
		local k = arrived / math.max(1, count)
		local sinkLen = if small then 0.12 else 0.6
		if t >= dur - sinkLen then k *= 1 - math.clamp((t - (dur - sinkLen)) / sinkLen, 0, 1) end
		if math.abs(k - lastPile) > 0.002 then
			lastPile = k
			local sc = math.max(0.02, k) * pileScale
			pile.Size = Vector3.new(2.6 * sc, 0.9 * sc, 2.2 * sc)
			pile.CFrame = CFrame.new(selfFeet + up * (0.3 * sc))
			pile.Transparency = if k > 0.01 then 0 else 1
			for i, p in resting do
				local show = k > i / 7
				p.Transparency = if show then 0 else 1
				if show then p.CFrame = CFrame.new(selfFeet + up * (0.72 * sc)) * restCf[i] end
			end
		end
		glit.Rate = if arrived > 0 and arrived < count then 10 * ctx.factor else 0
		return false
	end, function()
		for _, c in coins do c.p:Destroy() end
		for _, p in resting do p:Destroy() end
		pile:Destroy()
		glit.Rate = 0
		Debris:AddItem(glitAnchor, 1)
	end)
end

-- ninjaclones: Schattenklone + Shuriken-Sturm. Ab `appearAt` (+ i * `every`)
-- erscheinen `count` dunkle Klone des Angreifers (inkBear, Stirnband rot) in
-- Rauch-Puffs auf einem Ring (`radius`) um den Gegner - hinten und seitlich,
-- nie zwischen Kamera und Gegner (F44); ab `throwAt` (+ i * `every`) wirft
-- jeder einen Shuriken (Vierstern, dreht sich), der im Bogen um den Gegner
-- fliegt und sich rund um ihn in den Boden bohrt (Funken); bei `dashAt`
-- stuermen alle gleichzeitig durch den Gegner (Lichtstreifen) und vergehen in
-- Puffs; bei `flashAt` blitzen die Shuriken und sinken ein. `single`: Echo -
-- ein Shuriken fliegt von self in den Boden vor dem Gegner. Test: freezeAt.
--   count, radius, appearAt, every, throwAt, flight, dashAt, dash, flashAt, dur, single
BLOCKS.ninjaclones = function(ctx, s)
	local count = s.count or 3
	local R = s.radius or 4.5
	local appearAt = s.appearAt or 0
	local every = s.every or 0.2
	local throwAt = s.throwAt or 0.7
	local flight = s.flight or 0.35
	local dashAt = s.dashAt or 1.5
	local dash = s.dash or 0.2
	local flashAt = s.flashAt or 1.8
	local dur = s.dur or 2.5
	local single = s.single == true
	local freezeAt: number? = s.freezeAt
	local up = Vector3.yAxis
	local tFeet = ctx.targetFeet
	local side = sideOf(ctx)
	local puff = smokeAt(ctx, nil, dur)
	-- Klone auf dem Ring: Winkel ab der Angreifer-Richtung (-fwd = 0 Grad),
	-- 110 / 250 / 180 Grad: hinten und seitlich, nicht vor der Kamera (F44)
	type Clone = { m: Model, off: CFrame, feet: Vector3, fwd: Vector3, t0: number, shown: boolean, gone: boolean, streak: BasePart? }
	local clones: { Clone } = {}
	-- Ring relativ zur Kamera-Richtung (0 Grad = zur Kamera), alle Klone auf der
	-- abgewandten Seite (F44); einmal beim Start (F22)
	local camDir = camFace(tFeet, -ctx.fwd)
	local camSide = up:Cross(camDir)
	camSide = if camSide.Magnitude > 0.01 then camSide.Unit else side
	local function ringPoint(deg: number): Vector3
		local a = math.rad(deg)
		local dir = camDir * math.cos(a) + camSide * math.sin(a)
		return tFeet + dir * R
	end
	if not single then
		local angles = { 180, 125, 235, 150, 210 }
		for i = 1, count do
			local spot = ringPoint(angles[(i - 1) % #angles + 1])
			local look = Vector3.new(tFeet.X - spot.X, 0, tFeet.Z - spot.Z)
			local fwd = if look.Magnitude > 0.1 then look.Unit else ctx.fwd
			local m, off = inkBear(ctx.selfModel, ctx.selfSize, LOW.INK, 0.1, spot, fwd, nil)
			m.Name = "SkillFXNinja"
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") and (d.Name:find("band", 1, true) or d.Name:find("knot", 1, true)) then d.Color = LOW.NINJARED end
			end
			m:PivotTo(PARK)
			table.insert(clones, { m = m, off = off, feet = spot, fwd = fwd, t0 = appearAt + (i - 1) * every, shown = false, gone = false, streak = nil })
		end
	end
	-- Shuriken: Start (Pfote des Klons bzw. self), Scheitel, Ziel (Boden um den Gegner)
	type Star = { m: Model, set: (CFrame) -> (), t0: number, from: Vector3, ctrl: Vector3, to: Vector3, stuck: boolean }
	local stars: { Star } = {}
	local nStars = if single then 1 else count
	for i = 1, nStars do
		local m, set = LOW.shuriken(if single then 0.9 else 1.1)
		local c = clones[i]
		local from = if c then c.feet + c.fwd * 0.6 + up * (ctx.selfSize.Y * 0.55) else ctx.selfFeet + ctx.fwd * 0.8 + up * (ctx.selfSize.Y * 0.5)
		local a = math.rad(if single then 0 else (30 + (i - 1) * 120))
		local toDir = (-ctx.fwd) * math.cos(a) + side * math.sin(a)
		local to = tFeet + toDir * (if single then 1.3 else 2.3) + up * 0.1
		local sideways = side * (if i % 2 == 0 then 1 else -1) * 2.5
		local ctrl = (from + to) / 2 + up * 2.2 + (if single then Vector3.zero else sideways)
		table.insert(stars, { m = m, set = set, t0 = throwAt + (i - 1) * every, from = from, ctrl = ctrl, to = to, stuck = false })
	end
	local flashed = false
	runLoop("ninjaclones", function(tRaw)
		if tRaw >= (if freezeAt then freezeAt + 150 else dur) then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		local live = not freezeAt or tRaw < freezeAt
		-- Klone erscheinen (Puff), ducken sich beim Wurf, stuermen bei dashAt
		for i, c in clones do
			if c.gone then continue end
			if t >= c.t0 and not c.shown then
				c.shown = true
				if live then puff(c.feet + up * 1, 10) end
			end
			if c.shown then
				local pitch = 0
				local st = stars[i]
				if st then
					local w = t - st.t0
					if w > -0.15 and w < 0.2 then pitch = -0.25 * math.sin(math.clamp((w + 0.15) / 0.35, 0, 1) * math.pi) end
				end
				local pos = c.feet
				if t >= dashAt then
					-- Sturm: durch den Gegner hindurch zur Gegenseite
					local k = math.clamp((t - dashAt) / dash, 0, 1)
					local mirror = tFeet + (tFeet - c.feet)
					pos = c.feet:Lerp(mirror, k)
					pitch = -0.2
					if not c.streak then
						local len = (mirror - c.feet).Magnitude
						local st2 = newPart(Enum.PartType.Block, Vector3.new(0.5, 0.5, len), LOW.STEEL, CFrame.lookAt((c.feet + mirror) / 2 + up * 1.2, mirror + up * 1.2), 0.45)
						st2.Name = "NinjaStreak"
						c.streak = st2
						tween(st2, dash + 0.25, { Transparency = 1, Size = Vector3.new(0.1, 0.1, len) })
						Debris:AddItem(st2, dash + 0.35)
					end
					if k >= 1 then
						c.gone = true
						c.m:PivotTo(PARK)
						if live then puff(mirror + up * 1, 8) end
						continue
					end
				end
				local half = ctx.selfSize.Y * 0.5
				local pose = CFrame.lookAt(pos, pos + c.fwd) * CFrame.new(0, half, 0) * CFrame.Angles(pitch, 0, 0) * CFrame.new(0, -half, 0)
				c.m:PivotTo(pose * c.off)
			end
		end
		-- Shuriken fliegen, bohren sich ein, blitzen
		for _, st in stars do
			local w = t - st.t0
			if w < 0 then
				st.set(PARK)
			elseif w < flight then
				local k = w / flight
				local pos = bez2(st.from, st.ctrl, st.to, k)
				local ahead = bez2(st.from, st.ctrl, st.to, math.min(1, k + 0.02))
				local dir = ahead - pos
				dir = if dir.Magnitude > 0.001 then dir.Unit else ctx.fwd
				-- Ebene waagerecht, dreht sich um die Hochachse
				st.set(CFrame.lookAt(pos, pos + dir) * CFrame.Angles(math.rad(90), 0, 0) * CFrame.Angles(0, 0, w * 40))
			else
				if not st.stuck then
					st.stuck = true
					if live then burstAt(ctx, st.to + up * 0.2, 10, 6, LOW.STEEL) end
				end
				-- eingebohrt: Ebene senkrecht (enthaelt die Richtung zum Gegner), 35 Grad geneigt
				local radial = (st.to - tFeet) * Vector3.new(1, 0, 1)
				radial = if radial.Magnitude > 0.01 then radial.Unit else -ctx.fwd
				local tilt = CFrame.lookAt(st.to, st.to + radial:Cross(up)) * CFrame.Angles(math.rad(35), 0, 0)
				local sink = if t >= flashAt + 0.25 then math.clamp((t - flashAt - 0.25) / 0.4, 0, 1) else 0
				st.set(tilt * CFrame.new(0, 0.35 - 0.9 * sink, 0))
				if t >= flashAt and not flashed then
					for _, d in st.m:GetChildren() do
						if d:IsA("BasePart") and d.Shape ~= Enum.PartType.Ball then
							d.Material = Enum.Material.Neon
						end
					end
				end
			end
		end
		if t >= flashAt and not flashed then
			flashed = true
			task.delay(0.2, function()
				for _, st in stars do
					for _, d in st.m:GetChildren() do
						if d:IsA("BasePart") then d.Material = Enum.Material.SmoothPlastic end
					end
				end
			end)
		end
		return false
	end, function()
		for _, c in clones do c.m:Destroy() end
		for _, st in stars do st.m:Destroy() end
	end)
end

-- katana: ein sichelfoermiger Lichtschnitt (7 Neon-Stuecke, F31) fegt in
-- `draw` s ueber den Oberkoerper des Gegners, zur Kamera gedreht (F04), und
-- verblasst in `fade` s zu Stahl; Funken. Test: freezeAt.
--   at, radius, draw, fade, lift
BLOCKS.katana = function(ctx, s)
	local R = s.radius or 1.9
	local draw = math.max(0.03, s.draw or 0.08)
	local fade = s.fade or 0.3
	local lift = s.lift or 0.15
	local freezeAt: number? = s.freezeAt
	local up = Vector3.yAxis
	local c = (centerOf(ctx.targetModel) or at(ctx, s.at or "target")) + up * (ctx.targetSize.Y * lift)
	local face = camFace(c, -ctx.fwd)
	local right = up:Cross(face)
	right = if right.Magnitude > 0.01 then right.Unit else sideOf(ctx)
	local n = 7
	local segs: { BasePart } = {}
	local pts: { Vector3 } = {}
	for i = 0, n do
		local a = math.rad(-150 + 120 * i / n)
		table.insert(pts, c + right * (math.cos(a) * R) + up * (math.sin(a) * R * 0.75))
	end
	for _ = 1, n do
		local p = newPart(Enum.PartType.Cylinder, Vector3.new(0.1, 0.22, 0.22), LOW.WHITE, PARK, 1)
		p.Name = "KatanaCut"
		table.insert(segs, p)
	end
	local sparked = false
	runLoop("katana", function(tRaw)
		if tRaw >= (if freezeAt then freezeAt + 150 else draw + fade) then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		local k = math.clamp(t / draw, 0, 1)
		for i, p in segs do
			local f = math.clamp(k * n - (i - 1), 0, 1)
			if f > 0 then
				LOW.tube(p, pts[i], pts[i + 1], 0.22, f)
				local age = math.clamp((t - draw) / fade, 0, 1)
				p.Transparency = age
				p.Color = LOW.WHITE:Lerp(LOW.STEEL, age)
			end
		end
		if k >= 1 and not sparked then
			sparked = true
			if not freezeAt or tRaw < freezeAt then burstAt(ctx, c, 22, 10, LOW.WHITE) end
		end
		return false
	end, function()
		for _, p in segs do p:Destroy() end
	end)
end

-- roots: Wurzelwall. `count` dicke Wurzeln brechen rund um die eigene Figur
-- aus dem Boden (Ring `radius`), winden sich als Bogen hoch und nach innen ueber
-- den Kopf (Hoehe `height` x Figurenhoehe) und flechten sich zu einem Kaefig:
-- Stueck fuer Stueck (`segs` Zylinder, verjuengt, Rinde + leuchtende Moosknoten),
-- gestaffelt (`stagger`); bei `closeAt` treffen sich die Spitzen (Puls, Blaetter
-- spriessen, Gluehwuermchen), die Blattkrone des Klons (acc_leaf*) leuchtet; ab
-- `sinkAt` ziehen sich die Wurzeln zurueck, die Blaetter stieben. Test: freezeAt.
--   count, segs, radius, height, grow, stagger, closeAt, sinkAt, dur
BLOCKS.roots = function(ctx, s)
	local count = scaled(s.count or 8, ctx.factor)
	local segs = s.segs or 7
	local R = s.radius or 2.3
	local H = ctx.selfSize.Y
	local height = (s.height or 1.45) * H
	local grow = s.grow or 0.9
	local stagger = s.stagger or 0.06
	local closeAt = s.closeAt or 1.4
	local sinkAt = s.sinkAt or 3.0
	local dur = s.dur or 3.6
	local freezeAt: number? = s.freezeAt
	local up = Vector3.yAxis
	local feet = ctx.selfFeet
	local center = feet + up * height
	type Root = { parts: { BasePart }, pts: { Vector3 }, ds: { number }, t0: number, moss: { { p: BasePart, j: number } }, leaf: BasePart }
	local roots: { Root } = {}
	local rng = Random.new(5)
	for i = 1, count do
		local ang = (i - 0.5) / count * TAU
		local out = Vector3.new(math.cos(ang), 0, math.sin(ang))
		local tang = Vector3.new(-math.sin(ang), 0, math.cos(ang))
		local p0 = feet + out * R - up * 0.35
		local p1 = feet + out * (R * 1.3) + up * (height * 0.95) + tang * rng:NextNumber(-0.7, 0.7)
		local p2 = center + out * 0.4 + tang * rng:NextNumber(-0.35, 0.35)
		local pts: { Vector3 } = {}
		for j = 0, segs do table.insert(pts, bez2(p0, p1, p2, j / segs)) end
		local parts: { BasePart } = {}
		local ds: { number } = {}
		for j = 1, segs do
			local d = lerpN(0.48, 0.2, (j - 1) / math.max(1, segs - 1))
			local p = newPart(Enum.PartType.Cylinder, Vector3.new(0.1, d, d), LOW.BARK, PARK, 1)
			p.Material = Enum.Material.Wood
			p.Name = "Root"
			table.insert(parts, p)
			table.insert(ds, d)
		end
		local moss = {}
		for j = 2, segs do
			local mp = newPart(Enum.PartType.Ball, Vector3.one * 0.3, LOW.MOSS, PARK, 1)
			mp.Name = "RootMoss"
			table.insert(moss, { p = mp, j = j })
		end
		local leaf = newPart(Enum.PartType.Block, Vector3.new(0.85, 0.05, 0.5), LOW.MOSS, PARK, 1)
		leaf.Material = Enum.Material.SmoothPlastic
		leaf.Name = "RootLeaf"
		table.insert(roots, { parts = parts, pts = pts, ds = ds, t0 = (i - 1) * stagger, moss = moss, leaf = leaf })
	end
	-- Gluehwuermchen (EIN Emitter) um den Kaefig
	local fireAnchor = newPart(Enum.PartType.Block, Vector3.one * 0.2, LOW.MOSS, CFrame.new(feet + up * (height * 0.55)), 1)
	local fire = Instance.new("ParticleEmitter")
	fire.Texture = SPARK_TEX
	fire.Rate = 0
	fire.Speed = NumberRange.new(0.3, 1.2)
	fire.SpreadAngle = Vector2.new(180, 180)
	fire.Lifetime = NumberRange.new(1.0, 1.8)
	fire.Drag = 1
	fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(0.5, 0.35), NumberSequenceKeypoint.new(1, 0) })
	fire.Color = ColorSequence.new(Color3.fromRGB(200, 255, 170), LOW.MOSS)
	fire.LightEmission = 0.6
	fire.Parent = fireAnchor
	-- Blattkrone des Klons
	local crown: { { p: BasePart, mat: Enum.Material } } = {}
	local crownOn = false
	local function findCrown()
		local m = ctx.avatarModel
		if not m or #crown > 0 then return end
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") and d.Name:find("acc_leaf", 1, true) then table.insert(crown, { p = d, mat = d.Material }) end
		end
	end
	local function crownGlow(on: boolean)
		if on == crownOn then return end
		crownOn = on
		findCrown()
		for _, c in crown do
			if c.p.Parent then c.p.Material = if on then Enum.Material.Neon else c.mat end
		end
	end
	local closed = false
	local sunk = false
	local lastG: { number } = {}
	runLoop("roots", function(tRaw)
		if tRaw >= (if freezeAt then freezeAt + 150 else dur) then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		local live = not freezeAt or tRaw < freezeAt
		local sink = math.clamp((t - sinkAt) / 0.5, 0, 1)
		local pulse = if t >= closeAt then math.clamp(1 - (t - closeAt) / 0.35, 0, 1) else 0
		for i, r in roots do
			local g = math.clamp((t - r.t0) / grow, 0, 1) * (1 - sink)
			if lastG[i] ~= g then
				lastG[i] = g
				for j, p in r.parts do
					local f = math.clamp(g * segs - (j - 1), 0, 1)
					if f > 0 then
						LOW.tube(p, r.pts[j], r.pts[j + 1], r.ds[j], f)
						p.Transparency = 0
					else
						p.Transparency = 1
					end
				end
				for _, mo in r.moss do
					local f = math.clamp(g * segs - (mo.j - 1), 0, 1)
					mo.p.Transparency = if f >= 1 then 0 else 1
					if f >= 1 then mo.p.CFrame = CFrame.new(r.pts[mo.j + 1]) end
				end
			end
			for _, mo in r.moss do
				mo.p.Color = LOW.MOSS:Lerp(LOW.WHITE, pulse)
			end
			-- Blatt an der Spitze ab closeAt (federnd), beim Sinken weg
			local lf = if t >= closeAt then easeOutBack(math.clamp((t - closeAt) / 0.25, 0, 1)) * (1 - sink) else 0
			if lf > 0.02 then
				local tip = r.pts[segs + 1]
				local dir = (tip - r.pts[segs])
				dir = if dir.Magnitude > 0.01 then dir.Unit else up
				r.leaf.Size = Vector3.new(0.85 * lf, 0.05, 0.5 * lf)
				r.leaf.CFrame = CFrame.lookAt(tip + dir * (0.3 * lf), tip + dir * 2, up) * CFrame.Angles(0.6, 0, 0)
				r.leaf.Transparency = 0
			else
				r.leaf.Transparency = 1
			end
		end
		if t >= closeAt and not closed then
			closed = true
			if live then
				burstAt(ctx, center, 24, 6, LOW.MOSS)
				fire.Rate = if extrasOn(ctx) then 10 * ctx.factor else 0
			end
		end
		crownGlow(t >= closeAt and t < sinkAt)
		if t >= sinkAt then
			fire.Rate = 0
			if not sunk then
				sunk = true
				if live then burstAt(ctx, center, 30, 9, LOW.MOSS) end
			end
		end
		return false
	end, function()
		crownGlow(false)
		for _, r in roots do
			for _, p in r.parts do p:Destroy() end
			for _, mo in r.moss do mo.p:Destroy() end
			r.leaf:Destroy()
		end
		fire.Rate = 0
		Debris:AddItem(fireAnchor, 2)
	end)
end

-- rainbow: Regenbogenbruecke aus `bands` Baendern (Bezier-Beams, FaceCamera,
-- F31/F35) von den eigenen Fuessen bis zum Landeplatz vor dem Gegner - derselbe
-- Bogen wie die Posen von `moves` mit `curve`/`tilt` (LOW.bridge), gestapelt
-- (rot oben); zeichnet sich in `draw` s vom Baerchi weg (Glitzer an der
-- Spitze), ab `dissolveAt` loest sie sich vom Anfang her in Glitzer auf.
-- `echo`: kurz bis zum Gegner. Test: freezeAt.
--   bands, width, curve, tilt, lift, draw, dissolveAt, dur, gap, echo
BLOCKS.rainbow = function(ctx, s)
	local bands = s.bands or 6
	local width = s.width or 0.5
	local curve = s.curve or 8.5
	local tilt = s.tilt or 0.35
	local lift = s.lift or 0.3
	local draw = math.max(0.05, s.draw or 0.6)
	local dissolveAt = s.dissolveAt or 2.6
	local dur = s.dur or 3.6
	local freezeAt: number? = s.freezeAt
	local up = Vector3.yAxis
	local gap = (ctx.selfSize.Z + ctx.targetSize.Z) * 0.4 + (s.gap or 0.4)
	local a = ctx.selfFeet + up * lift
	local b = (if s.echo then ctx.targetFeet else ctx.targetFeet - ctx.fwd * gap) + up * lift
	local side = sideOf(ctx)
	local T0 = (ctx.fwd * tilt + up).Unit
	local T1 = (ctx.fwd * tilt - up).Unit
	local anchor = newPart(Enum.PartType.Block, Vector3.one * 0.2, ctx.fx.color, PARK, 1)
	anchor.Name = "RainbowAnchor"
	local beams: { Beam } = {}
	for i = 1, bands do
		local off = up * ((bands - i) * width * 0.9)
		-- erst einhaengen, dann WorldCFrame setzen (sonst gilt der Wert relativ zu PARK)
		local a0 = Instance.new("Attachment")
		a0.Parent = anchor
		a0.WorldCFrame = CFrame.fromMatrix(a + off, T0, T0:Cross(side).Unit)
		local a1 = Instance.new("Attachment")
		a1.Parent = anchor
		a1.WorldCFrame = CFrame.fromMatrix(b + off, T1, T1:Cross(side).Unit)
		local bm = Instance.new("Beam")
		bm.Attachment0 = a0
		bm.Attachment1 = a1
		bm.CurveSize0 = curve
		bm.CurveSize1 = curve
		bm.Width0 = width
		bm.Width1 = width
		bm.Segments = 24
		bm.FaceCamera = true
		bm.LightEmission = 0.35
		bm.LightInfluence = 0
		bm.Color = ColorSequence.new(RAINBOW[(i - 1) % #RAINBOW + 1])
		bm.Transparency = NumberSequence.new(1)
		bm.Parent = anchor
		table.insert(beams, bm)
	end
	-- sichtbarer Abschnitt k0..k1 als Transparenz-Verlauf (Zeiten streng steigend)
	local function seq(k0: number, k1: number, tr: number): NumberSequence
		local e = 0.004
		k0 = math.clamp(k0, 0, 1)
		k1 = math.clamp(k1, 0, 1)
		if k1 - k0 < 3 * e then return NumberSequence.new(1) end
		local kps: { NumberSequenceKeypoint } = {}
		if k0 > e then
			table.insert(kps, NumberSequenceKeypoint.new(0, 1))
			table.insert(kps, NumberSequenceKeypoint.new(k0 - e, 1))
			table.insert(kps, NumberSequenceKeypoint.new(k0, tr))
		else
			table.insert(kps, NumberSequenceKeypoint.new(0, tr))
		end
		if k1 < 1 - e then
			table.insert(kps, NumberSequenceKeypoint.new(k1, tr))
			table.insert(kps, NumberSequenceKeypoint.new(k1 + e, 1))
			table.insert(kps, NumberSequenceKeypoint.new(1, 1))
		else
			table.insert(kps, NumberSequenceKeypoint.new(1, tr))
		end
		return NumberSequence.new(kps)
	end
	-- Glitzer an der Zeichen- bzw. Aufloese-Front (EIN Emitter)
	local glitAnchor = newPart(Enum.PartType.Block, Vector3.one * 0.2, LOW.WHITE, CFrame.new(a), 1)
	local glit = Instance.new("ParticleEmitter")
	glit.Texture = SPARK_TEX
	glit.Rate = 0
	glit.Speed = NumberRange.new(1, 3)
	glit.SpreadAngle = Vector2.new(180, 180)
	glit.Lifetime = NumberRange.new(0.35, 0.7)
	glit.Drag = 2
	glit.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) })
	glit.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, LOW.WHITE), ColorSequenceKeypoint.new(0.5, ctx.fx.color), ColorSequenceKeypoint.new(1, ctx.fx.color2) })
	glit.LightEmission = 0.6
	glit.Parent = glitAnchor
	local lastK0, lastK1 = -1, -1
	runLoop("rainbow", function(tRaw)
		if tRaw >= (if freezeAt then freezeAt + 150 else dur) then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		local k0, k1 = 0, 0
		if t < dissolveAt then
			k1 = easeOutCubic(math.clamp(t / draw, 0, 1))
		else
			k1 = 1
			k0 = math.clamp((t - dissolveAt) / math.max(0.1, dur - dissolveAt - 0.1), 0, 1)
		end
		if math.abs(k0 - lastK0) > 0.003 or math.abs(k1 - lastK1) > 0.003 then
			lastK0, lastK1 = k0, k1
			local sq = seq(k0, k1, 0.15)
			for _, bm in beams do bm.Transparency = sq end
		end
		local front = if t < dissolveAt then k1 else k0
		local p = LOW.bridge(a, b, ctx.fwd, curve, tilt, front) + up * (bands * width * 0.45)
		glitAnchor.CFrame = CFrame.new(p)
		glit.Rate = if (t < draw) or (t >= dissolveAt and k0 < 1) then 50 * ctx.factor else 0
		return false
	end, function()
		anchor:Destroy()
		glit.Rate = 0
		Debris:AddItem(glitAnchor, 1)
	end)
end

-- paintsplash: Farbkleckse in Regenbogenfarben spritzen bei `at` rund um die
-- Figur auf den Boden (flache Ellipsen, federn auf, zufaellig gedreht),
-- verblassen ab `dur` - 0,4. Test: freezeAt.
--   at, count, radius, dur
BLOCKS.paintsplash = function(ctx, s)
	local count = scaled(s.count or 7, ctx.factor)
	local R = s.radius or 2.0
	local dur = s.dur or 1.4
	local freezeAt: number? = s.freezeAt
	local feet = groundAt(ctx, s.at or "target")
	local rng = Random.new(11)
	type Splat = { p: BasePart, cf: CFrame, w: number, l: number, t0: number }
	local splats: { Splat } = {}
	for i = 1, count do
		local ang = (i - 0.5) / count * TAU + rng:NextNumber(-0.3, 0.3)
		local r = R * rng:NextNumber(0.45, 1)
		local pos = feet + Vector3.new(math.cos(ang) * r, 0.05 + i * 0.004, math.sin(ang) * r)
		local w = rng:NextNumber(1.3, 2.2)
		local p = newPart(Enum.PartType.Cylinder, Vector3.new(0.05, 0.05, 0.05), RAINBOW[(i - 1) % #RAINBOW + 1], PARK, 1)
		p.Material = Enum.Material.SmoothPlastic
		p.Name = "PaintSplat"
		local cf = CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0) * CFrame.Angles(0, 0, math.rad(90))
		table.insert(splats, { p = p, cf = cf, w = w, l = w * rng:NextNumber(0.6, 0.9), t0 = rng:NextNumber(0, 0.08) })
	end
	runLoop("paintsplash", function(tRaw)
		if tRaw >= (if freezeAt then freezeAt + 150 else dur) then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		local fade = math.clamp((t - (dur - 0.4)) / 0.4, 0, 1)
		for _, sp in splats do
			local k = math.clamp((t - sp.t0) / 0.22, 0, 1)
			local e = math.max(0.02, easeOutBack(k))
			sp.p.Size = Vector3.new(0.05, sp.w * e, sp.l * e)
			sp.p.CFrame = sp.cf
			sp.p.Transparency = if k > 0 then fade else 1
		end
		return false
	end, function()
		for _, sp in splats do sp.p:Destroy() end
	end)
end


