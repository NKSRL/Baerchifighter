--------------------------------------------------------------------------------
-- 26.10.2026 Himmelsgericht (SeraphJudgment, Seraph-Baerchi, Divine, Stufe 4).
-- Der Seraph oeffnet seine sechs Fluegel Paar fuer Paar, steigt mit dem
-- Heiligenschein in die Hoehe, ueber der Arena oeffnet sich ein Himmelstor
-- (Ring aus Licht, Lichtschaefte), ein Speer aus Licht faellt ihm in die
-- Pfoten, eine Zielmarke schrumpft unter dem Gegner, Stille - Sturz - Einschlag
-- (Impact-Frames, Hitstop, Beben), dann die Lichtsaeule bis zum Tor, Druckwelle
-- bis zum Zaun, goldene Kuppel, die Ringe des Tors fallen als Kondensringe die
-- Saeule herab, Federn rieseln, ein schiefer kleiner Heiligenschein landet auf
-- dem Gegner (Pointe). Bewegung des Seraphs: `moves` (Daten in SkillFXConfig).
-- Alle Helfer dieser Show liegen in EINER Tabelle SER (Namensbudget, F51).
-- Doku in SkillFXConfig ("BAUSTEINE", Himmelsgericht). Beben ueber den vorhandenen
-- Baustein `quake` (26.10., Gletscherblick/Himmelsgelaeut), Impact-Frames ueber `impactframe`
-- mit dark/light/fill.
--------------------------------------------------------------------------------

local SER: { [string]: any } = {}

SER.GOLD = Color3.fromRGB(255, 214, 110)      -- Honiggold (Tor, Speer-Huelle, Kuppel)
SER.HONEY = Color3.fromRGB(230, 160, 40)      -- dunkles Honiggold (Risse, Umriss-Akzent)
SER.CREAM = Color3.fromRGB(255, 246, 225)     -- warmes Weiss (Kern, aeusserer Torring)
SER.HALO = Color3.fromRGB(255, 236, 160)      -- Heiligenschein (Neon-Akzent, klein)
SER.WINGLIGHT = Color3.fromRGB(255, 232, 170) -- Fluegel aus Licht (ForceField)
SER.SCORCH = Color3.fromRGB(72, 48, 24)       -- Brandfleck (dunkel-warm)
SER.INDIGO = Color3.fromRGB(70, 50, 160)      -- dunkle Impact-Frames (Tint)
SER.INDIGOFILL = Color3.fromRGB(40, 24, 110)  -- Silhouetten im dunklen Bild

-- Typen der Show (auf Modulebene, kein lokaler Name)
type SeraphWing = { p: BasePart, rel: CFrame, hinge: Vector3, side: number, pair: number, tip: Vector3,
	a0: Attachment, a1: Attachment, beam: Beam, trail: Trail, mat: Enum.Material, col: Color3 }
type SeraphHalo = { p: BasePart, rel: CFrame, mat: Enum.Material, col: Color3, size: Vector3 }
type SeraphGateRing = { ring: NovaRing, r0: number, w0: number, tr: number, spin: number, h: number, r1: number, order: number }

-- Teile eines Modells, deren Name ein Muster enthaelt (Kleinschreibung).
SER.partsLike = function(model: Model, pat: string): { BasePart }
	local out: { BasePart } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and string.find(string.lower(d.Name), pat, 1, true) then
			table.insert(out, d)
		end
	end
	return out
end

-- Unsichtbarer Anker mit einem Attachment (fuer Beams).
SER.anchorAt = function(pos: Vector3): (BasePart, Attachment)
	local p = newPart(Enum.PartType.Block, Vector3.one * 0.2, SER.CREAM, CFrame.new(pos), 1)
	p.Name = "SeraphAnchor"
	local a = Instance.new("Attachment")
	a.Parent = p
	return p, a
end

-- Beam zwischen zwei Attachments (FaceCamera, ohne Lichteinfluss).
SER.beam = function(a0: Attachment, a1: Attachment, w0: number, w1: number, col: Color3, emission: number, tr: number, texture: string?): Beam
	local b = Instance.new("Beam")
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.FaceCamera = true
	b.Segments = 1
	b.LightEmission = emission
	b.LightInfluence = 0
	b.Color = ColorSequence.new(col)
	b.Transparency = NumberSequence.new(tr)
	b.Width0 = w0
	b.Width1 = w1
	if texture then
		b.Texture = texture
		b.TextureMode = Enum.TextureMode.Stretch
	end
	b.Parent = a0.Parent
	return b
end

-- Zylinder-Stueck von a nach b (Laenge entlang X des Teils, Roehre statt
-- Quader, F31).
SER.rod = function(a: Vector3, b: Vector3, d: number, col: Color3, tr: number): BasePart
	local len = (b - a).Magnitude
	local p = newPart(Enum.PartType.Cylinder, Vector3.new(math.max(0.05, len), d, d), col,
		CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0), tr)
	return p
end

-- seraphwings: die sechs Fluegel (Teile mit "acc_wing" im Namen) und der
-- Heiligenschein ("acc_halo") des `moves`-Klons (ctx.avatarModel). Zu Beginn
-- liegen die Fluegel angelegt; bei `snapAt[i]` schnappt Paar i (oben, Mitte,
-- unten) auf (Funken an den Spitzen, Lichtfedern = Beams mit Feder-Bild), danach
-- schlagen sie; ab `launchAt` schneller Flugschlag mit Nachbildern (ForceField-
-- Klone, F26), beim Schweben weit gespreizt und hochgewoelbt; ab `diveAt` nach
-- hinten angelegt (Sturzflug, Nachbilder); ab `landAt` gespreizt; ab `foldAt`
-- legen sie sich wieder an, die Lichtfedern vergehen. Heiligenschein: ab `haloAt`
-- Neon, dreht sich, pulst; bei `landAt` blitzt er. Laeuft bis `dur`.
--   snapAt {3}, haloAt, launchAt, diveAt, landAt, foldAt, dur, ghosts (Test: freezeAt)
BLOCKS.seraphwings = function(ctx, s)
	local snapAt: { number } = if type(s.snapAt) == "table" then s.snapAt else { 0.22, 0.44, 0.66 }
	local haloAt = s.haloAt or 0.8
	local launchAt = s.launchAt or 1.0
	local diveAt = s.diveAt or 3.02
	local landAt = s.landAt or 3.27
	local foldAt = s.foldAt or 4.2
	local dur = s.dur or 5.4
	local wantGhosts = if s.ghosts ~= nil then s.ghosts == true else extrasOn(ctx)
	local freezeAt: number? = s.freezeAt
	local feather = texOf(ctx, "feather")
	local wings: { SeraphWing } = {}
	local halo: SeraphHalo? = nil
	local model: Model? = nil
	local sc0 = 1
	local lastGhost = -1
	local ghostCount = 0
	local snapped = { false, false, false }
	local haloOn = false
	local haloFlash = false
	local phase = 0

	-- Paare nach Hoehe sortieren: oben = 1, Mitte = 2, unten = 3
	local function build(m: Model): boolean
		local pv = m:GetPivot()
		local raw = SER.partsLike(m, "acc_wing")
		if #raw < 2 then return false end
		local infos: { { p: BasePart, rel: CFrame } } = {}
		for _, p in raw do
			table.insert(infos, { p = p, rel = pv:ToObjectSpace(p.CFrame) })
		end
		table.sort(infos, function(a, b) return a.rel.Position.Y > b.rel.Position.Y end)
		local pairOf: { [BasePart]: number } = {}
		local pairIdx = 0
		local lastY = math.huge
		for _, w in infos do
			if lastY - w.rel.Position.Y > 0.2 then
				pairIdx = math.min(3, pairIdx + 1)
				lastY = w.rel.Position.Y
			end
			pairOf[w.p] = math.max(1, pairIdx)
		end
		for _, w in infos do
			local side = if w.rel.Position.X < 0 then -1 else 1
			local sz = w.p.Size
			-- Scharnier am Ruecken (Wirbelsaeule), Spitze = hinteres Ende des Blatts
			local hinge = Vector3.new(side * 0.25, w.rel.Position.Y, w.rel.Position.Z - sz.Z * 0.35)
			local tip = Vector3.new(0, sz.Y * 0.45, sz.Z * 0.5)
			local a0 = Instance.new("Attachment")
			a0.Position = Vector3.new(0, -sz.Y * 0.4, -sz.Z * 0.45)
			a0.Parent = w.p
			local a1 = Instance.new("Attachment")
			a1.Position = Vector3.new(side * 0.35, sz.Y * 0.55, sz.Z * 0.95)
			a1.Parent = w.p
			local beam = SER.beam(a0, a1, 0.9, 0.25, SER.GOLD, 0.35, 1, feather)
			beam.Segments = 4
			local t0a = Instance.new("Attachment")
			t0a.Position = Vector3.new(0, sz.Y * 0.45, sz.Z * 0.5)
			t0a.Parent = w.p
			local t1a = Instance.new("Attachment")
			t1a.Position = Vector3.new(0, -sz.Y * 0.1, sz.Z * 0.5)
			t1a.Parent = w.p
			local trail = Instance.new("Trail")
			trail.Attachment0 = t0a
			trail.Attachment1 = t1a
			trail.Lifetime = 0.22
			trail.LightEmission = 0.6
			trail.FaceCamera = true
			trail.Color = ColorSequence.new(SER.CREAM, SER.GOLD)
			trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
			trail.Enabled = false
			trail.Parent = w.p
			table.insert(wings, { p = w.p, rel = w.rel, hinge = hinge, side = side, pair = pairOf[w.p], tip = tip,
				a0 = a0, a1 = a1, beam = beam, trail = trail, mat = w.p.Material, col = w.p.Color })
		end
		local hp = SER.partsLike(m, "acc_halo")[1]
		if hp then
			halo = { p = hp, rel = pv:ToObjectSpace(hp.CFrame), mat = hp.Material, col = hp.Color, size = hp.Size }
		end
		sc0 = ctx.avatarScale or 1   -- Groesse des Klons beim Erfassen der Ruhelagen
		return true
	end

	local function restore()
		for _, w in wings do
			w.p.Material = w.mat
			w.p.Color = w.col
			w.trail.Enabled = false
		end
		if halo then
			halo.p.Material = halo.mat
			halo.p.Color = halo.col
		end
	end

	local function fanAngle(pairIdx: number): number
		-- Grundwinkel des Faechers (oben 28, Mitte 45, unten 60 Grad)
		return math.rad(if pairIdx == 1 then 28 elseif pairIdx == 2 then 45 else 60)
	end

	runLoop("seraphwings", function(tRaw, dt)
		if tRaw >= (if freezeAt then freezeAt + 150 else dur) then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		local m = ctx.avatarModel
		if not m or not m.Parent then
			if t > 0.6 and model == nil then return true end   -- kein Klon gekommen (fremdes Modell?)
			if model ~= nil then return true end               -- `moves` ist fertig
			return false
		end
		if model == nil then
			model = m
			if not build(m) then return true end
		end
		local pv = m:GetPivot()
		local sc = ctx.avatarScale or 1
		local k = sc / math.max(0.01, sc0)
		phase += dt * TAU * (if t < launchAt then 2.2 elseif t < launchAt + 0.7 then 7.5 elseif t < diveAt then 3.6 elseif t < landAt then 9 else 2.0)
		local parts: { BasePart } = {}
		local cfs: { CFrame } = {}
		for _, w in wings do
			local openK: number
			local snapT = snapAt[w.pair] or 0.5
			if t < snapT then
				openK = 0
			else
				local q = math.clamp((t - snapT) / 0.09, 0, 1)
				openK = easeOutBack(q)
				if not snapped[w.pair] then
					snapped[w.pair] = true
					burstAt(ctx, pv:PointToWorldSpace((w.rel.Position + w.tip) * k), 14, 7, SER.GOLD)
				end
			end
			if t >= foldAt then
				openK *= 1 - math.clamp((t - foldAt) / 0.5, 0, 1)
			end
			-- Schlag (Flattern) + Haltung je Phase: Schweben weit und hoch, Sturz angelegt
			local flap = math.sin(phase + w.pair * 0.6)
			local spread: number
			local liftRoll: number
			if t < launchAt then
				spread = 0.35 + 0.12 * flap
				liftRoll = 0.15 + 0.08 * flap
			elseif t < diveAt then
				local hoverK = math.clamp((t - launchAt) / 0.5, 0, 1)
				spread = 0.35 + 0.45 * hoverK + 0.22 * flap
				liftRoll = 0.15 + 0.55 * hoverK + 0.2 * flap
			elseif t < landAt then
				spread = -0.5 + 0.05 * flap          -- nach hinten angelegt
				liftRoll = -0.1
			else
				local landK = math.clamp((t - landAt) / 0.25, 0, 1)
				spread = -0.5 + 1.1 * easeOutBack(landK) + 0.1 * flap
				liftRoll = -0.1 + 0.6 * landK + 0.08 * flap
			end
			local yaw = w.side * (-fanAngle(w.pair) + (fanAngle(w.pair) + spread) * openK)
			local roll = w.side * liftRoll * openK
			local h = w.hinge * k
			local localCf = CFrame.new(h) * CFrame.Angles(0, yaw, roll) * CFrame.new(-h)
				* CFrame.new(w.rel.Position * k) * w.rel.Rotation
			table.insert(parts, w.p)
			table.insert(cfs, pv * localCf)
			-- Licht: Fluegel aus Licht sobald offen
			local lit = openK > 0.3
			local wantMat = if lit then Enum.Material.ForceField else w.mat
			if w.p.Material ~= wantMat then
				w.p.Material = wantMat
				w.p.Color = if lit then SER.WINGLIGHT else w.col
			end
			local beamA = math.clamp(openK * 1.2, 0, 1)
			w.beam.Transparency = NumberSequence.new(1 - 0.75 * beamA)
			w.trail.Enabled = (t >= launchAt and t < launchAt + 0.55) or (t >= diveAt and t < landAt + 0.05)
		end
		if halo then
			local hk = math.clamp((t - haloAt) / 0.3, 0, 1)
			if hk > 0 and not haloOn then
				haloOn = true
				halo.p.Material = Enum.Material.Neon
				halo.p.Color = SER.HALO
			end
			local pulse = 1 + 0.35 * math.sin(math.pi * hk) + 0.05 * math.sin(t * 9)
			if t >= landAt and t < landAt + 0.3 then
				pulse += 0.5 * (1 - (t - landAt) / 0.3)
				if not haloFlash then
					haloFlash = true
					burstAt(ctx, pv:PointToWorldSpace(halo.rel.Position * k), 18, 6, SER.HALO)
				end
			end
			local lift = 0.12 * hk + 0.06 * math.sin(t * 3)
			local hp = halo.rel.Position * k + Vector3.new(0, lift, 0)
			local tilt = if t >= diveAt and t < landAt then 0.35 else 0.08 * math.sin(t * 2.1)
			local localCf = CFrame.new(hp) * CFrame.Angles(tilt, t * 3.0 * hk, 0) * halo.rel.Rotation
			table.insert(parts, halo.p)
			table.insert(cfs, pv * localCf)
			local wantSize = halo.size * (if haloOn then pulse else 1)
			if (wantSize - halo.p.Size).Magnitude > 0.01 then halo.p.Size = wantSize end
		end
		if #parts > 0 then
			workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		end
		-- Nachbilder beim Start und im Sturz
		if wantGhosts and ((t >= launchAt and t < launchAt + 0.45) or (t >= diveAt and t < landAt)) then
			local every = if t < diveAt then 0.07 else 0.045
			if t - lastGhost >= every and ghostCount < 14 then
				lastGhost = t
				ghostCount += 1
				chronoGhost(m, SER.GOLD, 0.3, 0.26)
			end
		end
		return false
	end, function()
		restore()
		for _, w in wings do
			w.beam:Destroy()
			w.trail:Destroy()
			w.a0:Destroy()
			w.a1:Destroy()
		end
	end)
end

-- seraphspear: der Speer aus Licht. Bei `formAt` entsteht er klein am Himmelstor
-- (ctx.seraphGate) und sinkt in `form` s zu dem schwebenden Klon; ab `grabAt`
-- in den Pfoten (folgt ctx.avatarCf), richtet sich in 0,3 s auf die Fuesse des
-- Gegners aus (zielt); im Sturz voraus; bei `plantAt` steckt er im Boden an
-- den Fuessen des Gegners (Spitze unten, Schaft zum Seraph geneigt) und blitzt
-- - setzt ctx.seraphHit; bei `pullAt` hebt er sich und zerfaellt in Federn
-- und Funken. Kern Neon (schmal, F17), Huelle ForceField, Klinge aus zwei
-- Keilen, goldene Parierscheibe, zwei Feder-Troddeln (Beams).
--   formAt, form, grabAt, plantAt, pullAt, length, dur (Test: freezeAt)
BLOCKS.seraphspear = function(ctx, s)
	local formAt = s.formAt or 0
	local form = s.form or 0.35
	local grabAt = s.grabAt or 0.45
	local plantAt = s.plantAt or 1.38
	local pullAt = s.pullAt or 2.45
	local L = s.length or 8
	local dur = s.dur or 2.7
	local freezeAt: number? = s.freezeAt
	local feather = texOf(ctx, "feather")
	local H = ctx.selfSize.Y

	-- Teile: lokale Achse = +Y (Spitze bei +L/2)
	local rig: { { p: BasePart, rel: CFrame, tr: number } } = {}
	local function add(p: BasePart, rel: CFrame, tr: number)
		p.Transparency = 1
		table.insert(rig, { p = p, rel = rel, tr = tr })
	end
	local shaftLen = L * 0.78
	local core = newPart(Enum.PartType.Cylinder, Vector3.new(shaftLen, 0.18, 0.18), SER.CREAM, PARK, 1)
	core.Name = "SeraphSpearCore"
	add(core, CFrame.new(0, -L * 0.08, 0) * CFrame.Angles(0, 0, math.rad(90)), 0)
	local shell = newPart(Enum.PartType.Cylinder, Vector3.new(shaftLen, 0.44, 0.44), SER.GOLD, PARK, 1)
	shell.Material = Enum.Material.ForceField
	add(shell, CFrame.new(0, -L * 0.08, 0) * CFrame.Angles(0, 0, math.rad(90)), 0.15)
	local guard = newPart(Enum.PartType.Cylinder, Vector3.new(0.14, 0.9, 0.9), SER.HONEY, PARK, 1)
	guard.Material = Enum.Material.SmoothPlastic
	add(guard, CFrame.new(0, L * 0.31, 0) * CFrame.Angles(0, 0, math.rad(90)), 0)
	local bladeLen = L * 0.2
	for side = -1, 1, 2 do
		local w = Instance.new("WedgePart")
		prepPart(w, SER.CREAM, PARK, 1)
		w.Material = Enum.Material.Neon
		w.Size = Vector3.new(0.12, bladeLen, 0.42)
		-- Keil: senkrechte Flaeche hinten (+Z), Spitze oben (F16); zwei Keile Ruecken an Ruecken
		add(w, CFrame.new(0, L * 0.31 + bladeLen / 2, side * 0.21) * (if side > 0 then CFrame.Angles(0, math.pi, 0) else CFrame.identity), 0)
	end
	local bladeGlow = newPart(Enum.PartType.Ball, Vector3.new(0.7, bladeLen * 1.1, 0.7), SER.GOLD, PARK, 1)
	bladeGlow.Material = Enum.Material.ForceField
	add(bladeGlow, CFrame.new(0, L * 0.31 + bladeLen / 2, 0), 0.35)
	local pommel = newPart(Enum.PartType.Ball, Vector3.one * 0.36, SER.HONEY, PARK, 1)
	pommel.Material = Enum.Material.SmoothPlastic
	add(pommel, CFrame.new(0, -L * 0.47, 0), 0)
	-- Troddeln: zwei Feder-Beams vom Rand der Parierscheibe nach unten-aussen
	-- (Scheibe ist um 90 Grad gedreht: lokal +X = zur Spitze, Y/Z = Scheibenebene)
	local tassels: { Beam } = {}
	for side = -1, 1, 2 do
		local a0 = Instance.new("Attachment")
		a0.Parent = guard
		a0.Position = Vector3.new(0, side * 0.42, 0)
		local a1 = Instance.new("Attachment")
		a1.Parent = guard
		a1.Position = Vector3.new(-1.1, side * 0.8, 0)
		local b = SER.beam(a0, a1, 0.45, 0.12, SER.CREAM, 0.3, 1, feather)
		b.Segments = 3
		b.CurveSize0 = 0.4
		b.CurveSize1 = -0.4
		table.insert(tassels, b)
	end
	local light = Instance.new("PointLight")
	light.Color = SER.GOLD
	light.Brightness = 0
	light.Range = 9
	light.Parent = core

	local gateC: Vector3 = ctx.seraphGate or (ctx.selfFeet + Vector3.new(0, 24, 0))
	local hit: Vector3 = ctx.targetFeet
	local planted = false
	local pulled = false
	local alpha = 0
	local lastAlpha = -1
	local function setAlpha(a: number)
		if math.abs(a - lastAlpha) < 0.01 then return end
		lastAlpha = a
		for _, r in rig do
			r.p.Transparency = 1 - (1 - r.tr) * a
		end
		local seq = NumberSequence.new(1 - 0.8 * a)
		for _, b in tassels do b.Transparency = seq end
		light.Brightness = 1.4 * a
	end
	local function place(cf: CFrame)
		local parts: { BasePart } = table.create(#rig)
		local cfs: { CFrame } = table.create(#rig)
		for i, r in rig do
			parts[i] = r.p
			cfs[i] = cf * r.rel
		end
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end
	-- Speer-Lage aus Mitte und Richtung (Spitze zeigt nach `dir`)
	local function frameOf(center: Vector3, dir: Vector3, roll: number): CFrame
		local d = if dir.Magnitude > 0.01 then dir.Unit else Vector3.yAxis
		local ref = if math.abs(d:Dot(Vector3.yAxis)) > 0.95 then ctx.fwd else Vector3.yAxis
		local right = d:Cross(ref).Unit
		-- lokale Y-Achse = d (Z ergibt sich als X x Y)
		return CFrame.fromMatrix(center, right, d) * CFrame.Angles(0, roll, 0)
	end
	local restCenter = ctx.selfFeet + Vector3.new(0, H * 0.7, 0)
	local lastCf = CFrame.new(gateC)

	runLoop("seraphspear", function(tRaw)
		if tRaw >= (if freezeAt then freezeAt + 150 else dur) then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		local av = ctx.avatarCf
		local sc = ctx.avatarScale or 1
		local cf: CFrame = lastCf
		if t < formAt then
			setAlpha(0)
			return false
		elseif t < grabAt then
			-- Entstehen: vom Tor herab in die Naehe der Pfoten, erst klein (F43)
			local q = math.clamp((t - formAt) / form, 0, 1)
			local e = easeOutCubic(q)
			local hover = if av then av.Position + Vector3.new(0, H * sc * 0.75, 0) + av.LookVector * (H * sc * 0.3) else restCenter
			local pos = gateC:Lerp(hover + Vector3.new(0, 1.6, 0), e)
			local spin = (1 - e) * 4
			cf = frameOf(pos, Vector3.new(0, 1, 0), spin)
			setAlpha(0.25 + 0.75 * e)
		elseif t < plantAt then
			if not av then
				cf = frameOf(restCenter + Vector3.new(0, 1.6, 0), Vector3.yAxis, 0)
			else
				local body = av.Position + Vector3.new(0, H * sc * 0.5, 0)
				-- in den Pfoten: rechts-vorn vor der Brust
				local grip = body + av.RightVector * (0.35 * sc) + av.LookVector * (H * sc * 0.45) - av.UpVector * (H * sc * 0.05)
				local aimK = math.clamp((t - grabAt) / 0.3, 0, 1)
				local toHit = (hit + Vector3.new(0, 0.3, 0)) - grip
				local upDir = av.UpVector
				local dir = upDir:Lerp(toHit.Unit, easeInOutSine(aimK))
				local roll = t * 0.8
				cf = frameOf(grip + dir.Unit * (L * 0.1), dir, roll)
			end
			setAlpha(1)
		else
			if not planted then
				planted = true
				ctx.seraphHit = hit
				burstAt(ctx, hit + Vector3.new(0, 0.6, 0), 26, 11, SER.CREAM)
			end
			if t < pullAt then
				-- steckt im Boden: Spitze bei `hit`, Schaft zum Seraph geneigt (20 Grad)
				local back = -ctx.fwd
				local axis = (Vector3.yAxis * math.cos(math.rad(20)) + back * math.sin(math.rad(20))).Unit
				local center = hit + axis * (L * 0.5 - L * 0.35)   -- Spitze 35 % eingegraben
				local wob = 0.03 * math.sin((t - plantAt) * 28) * math.max(0, 1 - (t - plantAt) * 2)
				cf = frameOf(center, -axis, 0) * CFrame.Angles(wob, 0, 0)
				setAlpha(1)
			else
				local q = math.clamp((t - pullAt) / 0.25, 0, 1)
				if not pulled then
					pulled = true
					burstAt(ctx, hit + Vector3.new(0, 1.2, 0), 30, 9, SER.GOLD)
					-- Federn
					local a = newPart(Enum.PartType.Block, Vector3.one * 0.3, SER.CREAM, CFrame.new(hit + Vector3.new(0, 1.5, 0)), 1)
					local em = Instance.new("ParticleEmitter")
					em.Texture = feather or SPARK_TEX
					em.Rate = 0
					em.Speed = NumberRange.new(2, 6)
					em.SpreadAngle = Vector2.new(180, 180)
					em.Lifetime = NumberRange.new(0.8, 1.4)
					em.Drag = 2
					em.Acceleration = Vector3.new(0, -1.5, 0)
					em.Size = NumberSequence.new(0.5)
					em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
					em.Color = ColorSequence.new(SER.CREAM, SER.GOLD)
					em.LightEmission = 0.5
					em.Rotation = NumberRange.new(0, 360)
					em.RotSpeed = NumberRange.new(-60, 60)
					em.Parent = a
					em:Emit(scaled(18, ctx.factor))
					Debris:AddItem(a, 1.8)
				end
				local back = -ctx.fwd
				local axis = (Vector3.yAxis * math.cos(math.rad(20)) + back * math.sin(math.rad(20))).Unit
				local center = hit + axis * (L * 0.15) + Vector3.new(0, 1.2 * easeOutCubic(q), 0)
				cf = frameOf(center, -axis, q * 3)
				setAlpha(1 - q)
			end
		end
		lastCf = cf
		place(cf)
		return false
	end, function()
		for _, r in rig do r.p:Destroy() end
	end)
end

-- halogate: das Himmelstor ueber der Arena (`at` + `lift`): drei Ringe aus je
-- 4 Bezier-Beams (novaRing, FaceCamera - von unten, schraeg und von innen
-- sichtbar, F40): aussen warm-weiss breit, innen Gold schmal (gestrichelt,
-- dreht sich), dazwischen ein duenner Honigring. Oeffnet sich bei 0: erst
-- klein, dann in `open` s auf `radius` (F43). Ab `raysAt` Lichtschaefte vom
-- Ring herab zur Arena (Beams, oben schmal, unten breit, drehen langsam);
-- bei jedem `ticks` pulsen Ringe und Schaefte; bei `offAt` reissen die
-- Schaefte ab (Einschlag). Bei `fallAt` stuerzen die drei Ringe in `fallFor` s
-- zur Lichtsaeule am Einschlagpunkt (ctx.seraphHit) und werden dort zu
-- Kondensringen (dehnen sich, verblassen); ein vierter kleiner Ring (Krone)
-- sinkt langsamer und landet schief ueber dem Kopf des Gegners (Pointe), bei
-- `popAt` zerplatzt er zu Funken. Setzt ctx.seraphGate und ctx.seraphGateR.
--   at, lift, radius, open, raysAt, ticks {}, offAt, fallAt, fallFor, popAt, dur
--   (Test: freezeAt)
BLOCKS.halogate = function(ctx, s)
	local lift = s.lift or 24
	local R = s.radius or 16
	local open = s.open or 0.55
	local raysAt = s.raysAt or 0.35
	local ticks: { number } = if type(s.ticks) == "table" then s.ticks else {}
	local offAt = s.offAt or 2.18
	local fallAt = s.fallAt or 2.7
	local fallFor = s.fallFor or 0.55
	local popAt = s.popAt or 4.55
	local dur = s.dur or 4.6
	local freezeAt: number? = s.freezeAt
	local center = at(ctx, s.at or "arena") + Vector3.new(0, lift, 0)
	ctx.seraphGate = center
	ctx.seraphGateR = R
	local flat = CFrame.new(center)   -- lokale XZ-Ebene = waagerecht
	local rings: { SeraphGateRing } = {
		{ ring = novaRing(SER.CREAM, 0.6, 0.12, 14), r0 = 1.0, w0 = 1.3, tr = 0.12, spin = 0.0, h = 14, r1 = 7.0, order = 1 },
		{ ring = novaRing(SER.HONEY, 0.3, 0.25, 14), r0 = 0.84, w0 = 0.28, tr = 0.25, spin = 0.35, h = 9.5, r1 = 5.0, order = 2 },
		{ ring = novaRing(SER.GOLD, 0.35, 0.2, 14), r0 = 0.72, w0 = 0.55, tr = 0.2, spin = -0.6, h = 5.0, r1 = 3.4, order = 3 },
	}
	-- gestrichelter Innenring (4 Striche je Viertel; NumberSequence erlaubt 20 Stuetzen)
	local dashed: { { number } } = {}
	for i = 0, 3 do
		local a = i / 4
		table.insert(dashed, { a, 0.2 })
		table.insert(dashed, { a + 0.16, 0.2 })
		table.insert(dashed, { a + 0.17, 1 })
		table.insert(dashed, { a + 0.245, 1 })
	end
	table.insert(dashed, { 1, 0.2 })
	for i = 1, 4 do rings[3].ring.pattern(i, dashed) end
	-- Krone (Pointe)
	local crown = novaRing(SER.HALO, 0.5, 0.1, 10)
	local crownR = 0.9
	-- Lichtschaefte: ein Anker in der Tormitte, Attachments lokal (drehen mit dem Anker)
	local nRays = if extrasOn(ctx) then 8 else 5
	local rayAnchor = newPart(Enum.PartType.Block, Vector3.one * 0.2, SER.CREAM, flat, 1)
	rayAnchor.Name = "SeraphRays"
	local rays: { Beam } = {}
	for i = 1, nRays do
		local a = (i - 1) / nRays * TAU
		local top = Instance.new("Attachment")
		top.Parent = rayAnchor
		top.Position = Vector3.new(math.cos(a) * R * 0.8, 0, math.sin(a) * R * 0.8)
		local low = Instance.new("Attachment")
		low.Parent = rayAnchor
		low.Position = Vector3.new(math.cos(a + 0.25) * R * 0.45, -lift + 0.3, math.sin(a + 0.25) * R * 0.45)
		local b = SER.beam(top, low, 1.4, 4.6, Color3.fromRGB(255, 236, 190), 0.3, 1)
		b.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 1) })
		table.insert(rays, b)
	end
	local hitP: Vector3? = nil
	local fellSound = false
	local popped = false
	local lastRayA = -1
	local function raysAlpha(a: number)
		if math.abs(a - lastRayA) < 0.01 then return end
		lastRayA = a
		local seq = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1 - 0.45 * a), NumberSequenceKeypoint.new(1, 1 - 0.15 * a) })
		for _, b in rays do b.Transparency = seq end
	end
	local function pulseAt(t: number): number
		-- Puls (0..1) kurz nach jedem Tick
		local best = 0
		for _, tk in ticks do
			local q = t - tk
			if q >= 0 and q < 0.22 then best = math.max(best, 1 - q / 0.22) end
		end
		return best
	end

	runLoop("halogate", function(tRaw)
		if tRaw >= (if freezeAt then freezeAt + 150 else dur) then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		local pulse = pulseAt(t)
		local openK = easeOutCubic(math.clamp(t / open, 0, 1))
		local pop = easeOutBack(math.clamp(t / 0.1, 0, 1))
		local scaleR = (0.06 + 0.94 * openK) * (0.9 + 0.1 * pop)
		local fading = math.clamp((t - (dur - 0.5)) / 0.4, 0, 1)
		if t < fallAt then
			for _, g in rings do
				local r = R * g.r0 * scaleR
				local w = g.w0 * math.min(1, t / 0.12) * (1 + 0.35 * pulse)
				g.ring.place(flat * CFrame.Angles(0, t * g.spin, 0), r, w)
				g.ring.alpha(math.clamp(openK * 1.5, 0, 1) * (1 - fading))
			end
			local rk = math.clamp((t - raysAt) / 0.4, 0, 1)
			local off = if t >= offAt then math.clamp(1 - (t - offAt) / 0.06, 0, 1) else 1
			raysAlpha(rk * off * (0.75 + 0.25 * pulse))
			rayAnchor.CFrame = flat * CFrame.Angles(0, t * 0.12, 0)
			crown.place(flat, 0.01, 0.01)
			crown.alpha(0)
		else
			raysAlpha(0)
			if not hitP then
				hitP = ctx.seraphHit or ctx.targetFeet
			end
			local hp = hitP :: Vector3
			local q = math.clamp((t - fallAt) / fallFor, 0, 1)
			local e = q * q * q   -- Fall beschleunigt
			for _, g in rings do
				local land = Vector3.new(hp.X, hp.Y + g.h, hp.Z)
				local pos = center:Lerp(land, e)
				local r = lerpN(R * g.r0, g.r1, e)
				local w = g.w0
				local a = 1
				if q >= 1 then
					-- Kondensring: dehnt sich, verblasst in 1 s (gestaffelt)
					local q2 = math.clamp((t - fallAt - fallFor - (g.order - 1) * 0.12) / 1.0, 0, 1)
					r = g.r1 + 2.6 * easeOutCubic(q2)
					w = g.w0 * (1 - 0.5 * q2)
					a = 1 - q2
				end
				g.ring.place(CFrame.new(pos) * CFrame.Angles(0, t * g.spin, 0), r, w)
				g.ring.alpha(a * (1 - fading))
			end
			if not fellSound and q >= 1 then
				fellSound = true
				burstAt(ctx, hp + Vector3.new(0, 1, 0), 20, 8, SER.GOLD)
			end
			-- Krone: langsamer, landet schief ueber dem Kopf des Gegners
			local headY = ctx.targetFeet.Y + ctx.targetSize.Y + 0.5
			local head = Vector3.new(ctx.targetFeet.X, headY, ctx.targetFeet.Z)
			local qc = math.clamp((t - fallAt) / (fallFor + 0.7), 0, 1)
			local ec = easeInOutSine(qc)
			local cpos = center:Lerp(head, ec)
			local tilt = math.rad(22) * ec
			local wob = if qc >= 1 then math.sin((t - fallAt) * 6) * 0.08 else 0
			local cr = lerpN(R * 0.5, crownR, ec)
			crown.place(CFrame.new(cpos) * CFrame.Angles(tilt + wob, t * 1.5, 0), cr, lerpN(0.6, 0.18, ec))
			if t >= popAt then
				if not popped then
					popped = true
					burstAt(ctx, cpos, 16, 6, SER.HALO)
				end
				crown.alpha(math.clamp(1 - (t - popAt) / 0.05, 0, 1))
			else
				crown.alpha(math.clamp((t - fallAt) / 0.3, 0, 1))
			end
		end
		return false
	end, function()
		for _, g in rings do g.ring.destroy() end
		crown.destroy()
		rayAnchor:Destroy()
	end)
end

-- seraphmark: Zielmarke unter dem Gegner: ein goldener Heiligenschein (Decal-
-- Platte, Bild `halo`) schrumpft von `radius` auf `shrinkTo`, bei jedem
-- `ticks` blitzt er (twinkle) - ein Lichtfaden vom Himmelstor (ctx.seraphGate)
-- laeuft beim ersten Tick herab in die Marke. Der Gegner (echter Klon, Original
-- lokal unsichtbar, F03) schaut hoch, zittert immer schneller, hopst bei den
-- Ticks; bei `releaseAt` (kurz vor impactAt) verschwindet der Klon, das
-- Original zeigt den Server-Rueckstoss (F15).
--   at, radius, shrinkTo, ticks {}, releaseAt, dur (Test: freezeAt)
BLOCKS.seraphmark = function(ctx, s)
	local r0 = s.radius or 5.5
	local r1 = s.shrinkTo or 1.6
	local ticks: { number } = if type(s.ticks) == "table" then s.ticks else {}
	local releaseAt = s.releaseAt or 0.96
	local dur = s.dur or 1.0
	local freezeAt: number? = s.freezeAt
	local g = groundAt(ctx, s.at or "target") + Vector3.new(0, 0.08, 0)
	local halo = texOf(ctx, "halo")
	local plate = newPart(Enum.PartType.Block, Vector3.new(r0 * 2, 0.05, r0 * 2), SER.GOLD, CFrame.new(g), 1)
	plate.Name = "SeraphMark"
	local decal: Decal? = nil
	local ringBeam: NovaRing? = nil
	if halo then
		local d0 = addDecal(plate, halo, Enum.NormalId.Top, SER.GOLD)
		d0.Transparency = 0.15
		decal = d0
	else
		ringBeam = novaRing(SER.GOLD, 0.4, 0.2, 12)
	end
	-- Lichtfaden vom Tor
	local gate = ctx.seraphGate or (g + Vector3.new(0, 24, 0))
	local topP, topA = SER.anchorAt(gate)
	local lowP, lowA = SER.anchorAt(gate)
	local thread = SER.beam(topA, lowA, 0.32, 0.14, SER.CREAM, 0.5, 1)
	local threadOn = false
	-- Gegner-Klon
	local source = ctx.targetModel
	local clone: Model? = if source and source.Parent then figureClone(source) else nil
	local hide: ((number) -> ())? = nil
	local tOff: CFrame = CFrame.identity
	local Ht = ctx.targetSize.Y
	local tHome = CFrame.lookAt(ctx.targetFeet, ctx.targetFeet - ctx.fwd)
	if clone and source then
		tOff = tHome:ToObjectSpace(clone:GetPivot())
		local hl = Instance.new("Highlight")
		hl.Adornee = clone
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.FillColor = SER.CREAM
		hl.FillTransparency = 0.9
		hl.OutlineColor = SER.HONEY
		hl.OutlineTransparency = 0.1
		hl.Parent = clone
		clone.Parent = folder()
		hide = hideFigure(source)
		;(hide :: (number) -> ())(1)
	end
	local released = false
	local function release()
		if released then return end
		released = true
		if hide then hide(0) end
		if clone then clone:Destroy() end
	end
	local tickDone: { boolean } = {}
	local hop = 0

	runLoop("seraphmark", function(tRaw, dt)
		if tRaw >= (if freezeAt then freezeAt + 150 else dur) then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		local q = math.clamp(t / (dur * 0.92), 0, 1)
		local r = lerpN(r0, r1, easeInOutSine(q))
		local pulse = 0
		for i, tk in ticks do
			local d = t - tk
			if d >= 0 and d < 0.2 then pulse = math.max(pulse, 1 - d / 0.2) end
			if d >= 0 and not tickDone[i] then
				tickDone[i] = true
				twinkle(g + Vector3.new(0, 0.6, 0), 1.6 + 0.4 * i, SER.CREAM, 0.3)
				hop = 0.25 + 0.1 * i
				if i == 1 then
					threadOn = true
					tween(lowP, 0.25, { CFrame = CFrame.new(g + Vector3.new(0, 0.3, 0)) }, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
				end
			end
		end
		plate.Size = Vector3.new(r * 2, 0.05, r * 2)
		plate.CFrame = CFrame.new(g) * CFrame.Angles(0, t * 0.6, 0)
		local appear = math.clamp(t / 0.15, 0, 1)
		if decal then
			(decal :: Decal).Transparency = 1 - (0.85 + 0.15 * pulse) * appear
		elseif ringBeam then
			(ringBeam :: NovaRing).place(CFrame.new(g + Vector3.new(0, 0.1, 0)), r, 0.4)
			;(ringBeam :: NovaRing).alpha(appear)
		end
		if threadOn then
			thread.Transparency = NumberSequence.new(1 - (0.55 + 0.45 * pulse))
			thread.Width0 = 0.32 + 0.3 * pulse
			thread.Width1 = 0.14 + 0.2 * pulse
		end
		-- Gegner: schaut hoch, zittert schneller, hopst bei den Ticks
		if clone and clone.Parent and not released then
			hop = math.max(0, hop - dt * 1.6)
			local look = math.clamp(t / 0.35, 0, 1)
			local f = 18 + 50 * q
			local tremble = (0.012 + 0.025 * q) * math.sin(t * f)
			local pitch = 0.22 * easeInOutSine(look)
			local y = 4 * hop * (1 - hop) * 0.5
			local half = Ht * 0.5
			local pose = tHome * CFrame.new(0, half + y, 0) * CFrame.Angles(pitch, 0, tremble) * CFrame.new(0, -half, 0)
			clone:PivotTo(pose * CFrame.new(tOff.Position) * tOff.Rotation)
		end
		if t >= releaseAt then release() end
		return false
	end, function()
		release()
		plate:Destroy()
		if ringBeam then (ringBeam :: NovaRing).destroy() end
		topP:Destroy()
		lowP:Destroy()
	end)
end

-- lightnuke: das Ende als Nuke in himmlischer Haut (2.5): bei 0 ein kleiner
-- goldener Kern (F36); ab `columnAt` eine Lichtsaeule (zwei Beams mit dem
-- Bild `column`: Kern warm-weiss, Huelle Gold) schiesst vom Einschlag
-- (ctx.seraphHit, sonst `at`) `height` Studs hoch (durch das Himmelstor), ab
-- `waveAt` die Druckwelle: eine Wand aus Licht (hellRing, heller Rand) rast bis
-- zum Zaun, eine zweite schmale dahinter; Brandfleck (dunkle Scheibe, Bild
-- `halo` als goldenes Siegel, sechs goldene Risse) bleibt bis `dur`; ab
-- `domeAt` drueckt die Saeule eine goldene Kuppel hoch (ForceField, zwei
-- Schalen, Radius `dome` in `domeFor` s), die Kuppel verblasst, Glut steigt.
-- Weit entfernte Zuschauer (ctx.far) sehen nur Kern und Saeule (`global`).
--   at, core, columnAt, height, waveAt, domeAt, dome, domeFor, scorch, dur
--   (Test: freezeAt)
BLOCKS.lightnuke = function(ctx, s)
	local hit: Vector3 = ctx.seraphHit or groundAt(ctx, s.at or "target")
	local coreFor = s.core or 0.2
	local columnAt = s.columnAt or 0.12
	local height = s.height or 160
	local waveAt = s.waveAt or 0.15
	local domeAt = s.domeAt or 0.6
	local domeR = s.dome or 11
	local domeFor = s.domeFor or 0.7
	local scorchR = s.scorch or 3.6
	local dur = s.dur or 2.5
	local freezeAt: number? = s.freezeAt
	local fenceR = radiusOf("fence", 24.6)
	local column = texOf(ctx, "column")
	local haloTex = texOf(ctx, "halo")
	local bodyR = math.max(ctx.targetSize.X, ctx.targetSize.Z) * 0.5

	-- Kern
	local core = newPart(Enum.PartType.Ball, Vector3.one * 0.6, SER.GOLD:Lerp(Color3.new(1, 1, 1), 0.55), CFrame.new(hit + Vector3.new(0, 1.2, 0)), 0.25)
	core.Name = "SeraphCore"
	-- Saeule
	local baseP, baseA = SER.anchorAt(hit + Vector3.new(0, 0.2, 0))
	local topP, topA = SER.anchorAt(hit + Vector3.new(0, 2, 0))
	local colCore = SER.beam(topA, baseA, 2.6, 2.6, SER.CREAM, 0.6, 1, column)
	local colShell = SER.beam(topA, baseA, 7.0, 6.0, SER.GOLD, 0.35, 1, column)
	local colLight = Instance.new("PointLight")
	colLight.Color = SER.GOLD
	colLight.Brightness = 0
	colLight.Range = 40
	colLight.Parent = baseP
	-- Druckwelle (zwei Lichtwaende)
	local waveP = newPart(Enum.PartType.Block, Vector3.one * 0.2, SER.CREAM, CFrame.new(hit), 1)
	waveP.Name = "SeraphWave"
	local wave1: HellRing? = nil
	local wave2: HellRing? = nil
	-- Brandfleck
	local scorchP: BasePart? = nil
	local sigil: Decal? = nil
	local cracksDone = false
	-- Kuppel
	local domeOuter: BasePart? = nil
	local domeInner: BasePart? = nil
	local embers: ParticleEmitter? = nil
	local emberP: BasePart? = nil
	local far = ctx.far

	runLoop("lightnuke", function(tRaw)
		if tRaw >= (if freezeAt then freezeAt + 150 else dur) then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		-- Kern: klein, kurz, getoent
		if t < coreFor then
			local q = t / coreFor
			local rr = lerpN(0.3, 3.2 * bodyR, easeOutCubic(q))
			core.Size = Vector3.one * rr * 2
			core.Transparency = 0.25 + 0.75 * q
		elseif core.Transparency < 1 then
			core.Transparency = 1
		end
		-- Saeule
		if t >= columnAt then
			local q = math.clamp((t - columnAt) / 0.18, 0, 1)
			local h = lerpN(2, height, easeOutCubic(q))
			topP.CFrame = CFrame.new(hit + Vector3.new(0, h, 0))
			local fadeQ = math.clamp((t - (columnAt + 1.6)) / 0.5, 0, 1)
			local wCore = 2.6 * (1 - 0.8 * fadeQ) * (1 + 0.15 * math.sin(t * 14))
			local wShell = 7.0 * (1 - 0.8 * fadeQ)
			colCore.Width0 = wCore
			colCore.Width1 = wCore
			colShell.Width0 = wShell
			colShell.Width1 = wShell * 0.85
			colCore.Transparency = NumberSequence.new(0.15 + 0.85 * fadeQ)
			colShell.Transparency = NumberSequence.new(0.55 + 0.45 * fadeQ)
			colLight.Brightness = 2.5 * (1 - fadeQ)
		end
		if far then return false end
		-- Druckwelle: Wand aus Licht bis zum Zaun
		if t >= waveAt then
			if not wave1 then
				wave1 = hellRing(waveP, 1, 1.0, 2.6, SER.CREAM, 0.5, 0.15)
				wave2 = hellRing(waveP, 1, 0.6, 1.2, SER.GOLD, 0.35, 0.25)
			end
			local q = math.clamp((t - waveAt) / 0.45, 0, 1)
			local e = easeOutCubic(q)
			local r = lerpN(1, fenceR, e)
			local w = lerpN(2.6, 1.0, e)
			;(wave1 :: HellRing).set(r, w * 0.5 + 0.2, w)
			hellFade((wave1 :: HellRing).beams, 0.15, 1 - q)
			local q2 = math.clamp((t - waveAt - 0.1) / 0.5, 0, 1)
			local r2 = lerpN(1, fenceR, easeOutCubic(q2))
			;(wave2 :: HellRing).set(r2, 0.6, 1.2 * (1 - 0.5 * q2))
			hellFade((wave2 :: HellRing).beams, 0.25, if t >= waveAt + 0.1 then 1 - q2 else 0)
		end
		-- Brandfleck + Risse (bleiben bis dur)
		if t >= columnAt and not scorchP then
			local sp = newPart(Enum.PartType.Cylinder, Vector3.new(0.08, scorchR * 2, scorchR * 2), SER.SCORCH,
				CFrame.new(hit + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.rad(90)), 0.1)
			sp.Material = Enum.Material.SmoothPlastic
			sp.Name = "SeraphScorch"
			scorchP = sp
			if haloTex then
				local plate = newPart(Enum.PartType.Block, Vector3.new(scorchR * 1.9, 0.05, scorchR * 1.9), SER.GOLD, CFrame.new(hit + Vector3.new(0, 0.12, 0)), 1)
				plate.Name = "SeraphSigil"
				sigil = addDecal(plate, haloTex, Enum.NormalId.Top, SER.GOLD)
				Debris:AddItem(plate, dur + 0.1)
			end
		end
		if t >= columnAt + 0.05 and not cracksDone then
			cracksDone = true
			for i = 1, 6 do
				local a = (i - 1) / 6 * TAU + 0.3
				local dir = Vector3.new(math.cos(a), 0, math.sin(a))
				local len = scorchR + 1.2 + math.random() * 1.8
				groundStroke(ctx, hit + dir * 0.6 + Vector3.new(0, 0.1, 0), hit + dir * len + Vector3.new(0, 0.1, 0),
					0.28, SER.HONEY, 0, 0.18, dur - 0.55)
			end
		end
		if sigil then
			local pulse = 0.5 + 0.5 * math.sin(t * 4)
			local fadeQ = math.clamp((t - (dur - 0.45)) / 0.4, 0, 1)
			;(sigil :: Decal).Transparency = (0.08 + 0.25 * pulse) + (1 - (0.08 + 0.25 * pulse)) * fadeQ
		end
		if scorchP then
			local fadeQ = math.clamp((t - (dur - 0.45)) / 0.4, 0, 1)
			;(scorchP :: BasePart).Transparency = 0.1 + 0.9 * fadeQ
		end
		-- Kuppel
		if t >= domeAt then
			if not domeOuter then
				local o = newPart(Enum.PartType.Ball, Vector3.one, SER.GOLD, CFrame.new(hit + Vector3.new(0, 0.4, 0)), 0.3)
				o.Material = Enum.Material.ForceField
				o.Name = "SeraphDome"
				domeOuter = o
				local inn = newPart(Enum.PartType.Ball, Vector3.one, SER.CREAM, CFrame.new(hit + Vector3.new(0, 0.4, 0)), 0.55)
				inn.Material = Enum.Material.ForceField
				inn.Name = "SeraphDomeInner"
				domeInner = inn
				local ep = newPart(Enum.PartType.Block, Vector3.new(domeR, 0.3, domeR), SER.GOLD, CFrame.new(hit + Vector3.new(0, 0.5, 0)), 1)
				emberP = ep
				local em = Instance.new("ParticleEmitter")
				em.Texture = SPARK_TEX
				em.Shape = Enum.ParticleEmitterShape.Box
				em.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
				em.Rate = 0
				em.Speed = NumberRange.new(3, 7)
				em.SpreadAngle = Vector2.new(20, 20)
				em.Lifetime = NumberRange.new(0.8, 1.5)
				em.Drag = 1
				em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
				em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
				em.Color = ColorSequence.new(SER.CREAM, SER.GOLD)
				em.LightEmission = 0.6
				em.Parent = ep
				embers = em
				em:Emit(scaled(36, ctx.factor))
			end
			local q = math.clamp((t - domeAt) / domeFor, 0, 1)
			local rr = lerpN(2, domeR, easeOutCubic(q))
			local holdEnd = domeAt + domeFor + 0.45
			local fadeQ = math.clamp((t - holdEnd) / 0.6, 0, 1)
			local o = domeOuter :: BasePart
			local inn = domeInner :: BasePart
			o.Size = Vector3.one * rr * 2
			inn.Size = Vector3.one * rr * 1.7
			o.Transparency = 0.3 + 0.7 * fadeQ
			inn.Transparency = 0.55 + 0.45 * fadeQ
		end
		return false
	end, function()
		core:Destroy()
		baseP:Destroy()
		topP:Destroy()
		waveP:Destroy()
		if scorchP then (scorchP :: BasePart):Destroy() end
		if domeOuter then (domeOuter :: BasePart):Destroy() end
		if domeInner then (domeInner :: BasePart):Destroy() end
		if emberP then Debris:AddItem(emberP :: BasePart, 1.6) end
	end)
end

