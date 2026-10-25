--------------------------------------------------------------------------------
-- 25.10.2026 Pulsar-Nova (PulsarNova, Pulsar-Baerchi). Neue, bessere Fassung
-- des Blender-Prototyps "Pulsstoss" vom 22.10.: ein Lichtpunkt zeichnet einen
-- Ring um den Baerchi, er steigt mit dem Jetpack auf und dreht sich immer
-- schneller - Visier und Jetpack werfen zwei Lichtkegel wie ein Leuchtturm,
-- jeder Durchgang durch die Kamera blitzt. Dann kollabiert er zum
-- Neutronenstern und schlaegt als Komet ein: Impact-Frames, Feuerkuppel,
-- Weissblende. Doku in SkillFXConfig ("BAUSTEINE", Pulsar-Nova).
--------------------------------------------------------------------------------

local PULSAR_WHITE = Color3.fromRGB(232, 252, 255)
local NOVA_HOT     = Color3.fromRGB(255, 247, 224)   -- weissgluehend
local NOVA_YELLOW  = Color3.fromRGB(255, 204, 82)
local NOVA_RED     = Color3.fromRGB(230, 72, 38)
local NOVA_HOLE    = Color3.fromRGB(118, 20, 36)     -- dunkle Loecher in der Kuppel
local NOVA_PINK    = Color3.fromRGB(255, 92, 172)    -- Saum (Umriss) wie im Vorbild
local NOVA_ASH     = Color3.fromRGB(44, 30, 36)
local NOVA_INK     = Color3.fromRGB(28, 10, 34)      -- Silhouetten im invertierten Bild
local NOVA_PAPER   = Color3.fromRGB(255, 232, 246)   -- rosa-weisser Grund im invertierten Bild

type NovaRing = {
    anchor: BasePart,
    place: (CFrame, number, number) -> (),
    alpha: (number, number?) -> (),
    pattern: (number, { { number } }) -> (),
    destroy: () -> (),
}
type NovaVeil = { set: (Color3, number) -> (), destroy: () -> () }
type NovaTongue = { a0: Attachment, a1: Attachment, beam: Beam, th: number, seed: number }
type NovaFlames = {
    anchor: BasePart,
    place: (Vector3, number, number, number, number) -> (),
    destroy: () -> (),
}
type JetFlame = { p: BasePart, rel: CFrame, size: Vector3, axis: number, dir: Vector3,
    mat: Enum.Material, col: Color3, hot: boolean }
type PulsarJet = { set: (number, number, number) -> (), visor: () -> Vector3, pack: () -> Vector3 }
type SparkPill = { p: BasePart, v: Vector3, life: number, len: number }
type NovaBand = { ring: NovaRing, beta: number, w: number, spin: number, ph: number, tilt: CFrame }
type NovaHole = { p: BasePart, dir: Vector3, w: number, h: number, roll: number }

-- Deterministisches Flackern (0..1) aus zwei Zahlen: gleiche Eingabe = gleiches
-- Bild, deshalb auch in eingefrorenen Test-Buehnen stabil (freezeAt).
local function novaHash(a: number, b: number): number
    local x = math.sin(a * 127.1 + b * 311.7) * 43758.5453
    return x - math.floor(x)
end

-- quadratische Bezier-Kurve (Flugbahn des Neutronensterns)
local function novaBez(p0: Vector3, p1: Vector3, p2: Vector3, u: number): Vector3
    return p0 * ((1 - u) * (1 - u)) + p1 * (2 * u * (1 - u)) + p2 * (u * u)
end

-- Transparenz-Verlauf eines Flammenband-Viertels mit Luecken (gerissene
-- Flammenstreifen wie im Vorbild). Zeiten steigen streng, Ende genau 1.
local function novaGaps(rng: Random, tr: number): { { number } }
    local kps: { { number } } = { { 0, tr } }
    local x = rng:NextNumber(0.08, 0.3)
    while x < 0.82 and #kps < 16 do
        local g = rng:NextNumber(0.05, 0.12)
        table.insert(kps, { x, tr })
        table.insert(kps, { x + 0.025, 1 })
        table.insert(kps, { x + g, 1 })
        table.insert(kps, { x + g + 0.025, tr })
        x += g + rng:NextNumber(0.22, 0.42)
    end
    table.insert(kps, { 1, tr })
    return kps
end

-- Kreis aus 4 Bezier-Beams (Viertel, FaceCamera) an EINEM Anker - Trick aus
-- `worldglobe` (F31/F40): glatt, billig, von allen Seiten sichtbar. Der Kreis
-- liegt in der lokalen XZ-Ebene des Ankers (Normale = lokales Y), Start bei
-- lokal +X, gezeichnet Richtung lokal +Z. place(cf, Radius, Breite);
-- alpha(a, p): Sichtbarkeit 0..1 und gezeichneter Anteil p (0..1, rundherum);
-- pattern(i, kps): eigener Transparenz-Verlauf fuer Viertel i (Luecken);
-- color2 (optional): Farbverlauf color -> color2 je Viertel.
local function novaRing(color: Color3, emission: number, tr: number, segments: number?, color2: Color3?): NovaRing
    local anchor = newPart(Enum.PartType.Block, Vector3.one * 0.2, color, PARK, 1)
    anchor.Name = "NovaRing"
    local atts: { Attachment } = {}
    local beams: { Beam } = {}
    for i = 1, 4 do
        local a = Instance.new("Attachment")
        a.Parent = anchor
        atts[i] = a
    end
    for i = 1, 4 do
        local b = Instance.new("Beam")
        b.Attachment0 = atts[i]
        b.Attachment1 = atts[i % 4 + 1]
        b.FaceCamera = true
        b.Segments = segments or 12
        b.LightEmission = emission
        b.LightInfluence = 0
        b.Color = if color2 then ColorSequence.new(color, color2) else ColorSequence.new(color)
        b.Transparency = NumberSequence.new(1)
        b.Parent = anchor
        beams[i] = b
    end
    local pats: { [number]: { { number } } } = {}
    local lastR, lastW, lastA, lastP = -1, -1, -1, -1
    local ring: NovaRing = {
        anchor = anchor,
        place = function(cf: CFrame, r: number, w: number)
            anchor.CFrame = cf
            if math.abs(r - lastR) > 0.004 or math.abs(w - lastW) > 0.004 then
                lastR, lastW = r, w
                local rr = math.max(0.02, r)
                for i, a in atts do
                    local th = (i - 1) * math.pi / 2
                    local dir = Vector3.new(math.cos(th), 0, math.sin(th))
                    local tan = Vector3.new(-math.sin(th), 0, math.cos(th))
                    a.CFrame = CFrame.fromMatrix(dir * rr, tan, dir)
                end
                local cs = 0.5523 * rr
                for _, b in beams do
                    b.CurveSize0 = cs
                    b.CurveSize1 = cs
                    b.Width0 = w
                    b.Width1 = w
                end
            end
        end,
        alpha = function(a: number, p: number?)
            local pp = math.clamp(p or 1, 0, 1)
            if math.abs(a - lastA) < 0.008 and math.abs(pp - lastP) < 0.003 then return end
            lastA, lastP = a, pp
            for i, b in beams do
                local kps = pats[i]
                local q = math.clamp(pp * 4 - (i - 1), 0, 1)
                if a <= 0.01 or q <= 0.01 then
                    b.Transparency = NumberSequence.new(1)
                elseif kps then
                    local list: { NumberSequenceKeypoint } = {}
                    for _, k in kps do
                        table.insert(list, NumberSequenceKeypoint.new(k[1], 1 - (1 - k[2]) * a))
                    end
                    b.Transparency = NumberSequence.new(list)
                else
                    local v = 1 - (1 - tr) * a
                    if q >= 0.99 then
                        b.Transparency = NumberSequence.new(v)
                    else
                        -- harte Kante an der Zeichenspitze
                        b.Transparency = NumberSequence.new({
                            NumberSequenceKeypoint.new(0, v),
                            NumberSequenceKeypoint.new(math.max(0.002, q - 0.01), v),
                            NumberSequenceKeypoint.new(q, 1),
                            NumberSequenceKeypoint.new(1, 1),
                        })
                    end
                end
            end
        end,
        pattern = function(i: number, kps: { { number } })
            pats[i] = kps
            lastA = -1
        end,
        destroy = function()
            anchor:Destroy()
        end,
    }
    return ring
end

-- Bildschirm-Schleier nur fuer den Besitzer (eigene ScreenGui ueber dem Spiel,
-- unter dem Impact-Frame): Leuchtturm-Blitz, Puls der Kuppel, Weissblende.
-- Eigener Schleier statt `flash`, weil hier Farbe UND Deckkraft je Bild laufen.
local function novaVeil(ctx: Ctx): NovaVeil?
    if not ctx.isOwner then return nil end
    local gui = Instance.new("ScreenGui")
    gui.Name = "SkillFXNovaVeil"
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 49
    gui.ResetOnSpawn = false
    local f = Instance.new("Frame")
    f.Size = UDim2.fromScale(1, 1)
    f.BorderSizePixel = 0
    f.BackgroundColor3 = Color3.new(1, 1, 1)
    f.BackgroundTransparency = 1
    f.Parent = gui
    gui.Parent = player:WaitForChild("PlayerGui")
    local lastV = -1
    return {
        set = function(c: Color3, a: number)
            local v = 1 - math.clamp(a, 0, 1)
            if math.abs(v - lastV) > 0.004 or f.BackgroundColor3 ~= c then
                lastV = v
                f.BackgroundColor3 = c
                f.BackgroundTransparency = v
            end
        end,
        destroy = function()
            gui:Destroy()
        end,
    }
end

-- Flammenzungen als Beams (FaceCamera, unten breit, oben spitz): von jeder
-- Seite eine Flamme, ein Anker fuer alle. place(center, r, h, t, a): Kranz um
-- `center` mit Radius r, Hoehe h (flackert in 2-Bild-Schritten wie im Anime),
-- a = Sichtbarkeit 0..1.
local function novaFlames(n: number, width: number, seed: number): NovaFlames
    local anchor = newPart(Enum.PartType.Block, Vector3.one * 0.2, NOVA_YELLOW, PARK, 1)
    anchor.Name = "NovaFlames"
    local rng = Random.new(seed)
    local list: { NovaTongue } = {}
    for j = 1, n do
        local a0 = Instance.new("Attachment")
        a0.Parent = anchor
        local a1 = Instance.new("Attachment")
        a1.Parent = anchor
        local b = Instance.new("Beam")
        b.Attachment0 = a0
        b.Attachment1 = a1
        b.FaceCamera = true
        b.Segments = 6
        b.Width0 = width * rng:NextNumber(0.75, 1.2)
        b.Width1 = width * 0.12
        b.LightEmission = 0.3
        b.LightInfluence = 0
        b.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, NOVA_HOT),
            ColorSequenceKeypoint.new(0.4, NOVA_YELLOW),
            ColorSequenceKeypoint.new(1, NOVA_RED),
        })
        b.Transparency = NumberSequence.new(1)
        b.Parent = anchor
        table.insert(list, { a0 = a0, a1 = a1, beam = b,
            th = (j - 0.5) / n * TAU + rng:NextNumber(-0.12, 0.12), seed = rng:NextNumber(0, 100) })
    end
    local lastA = -1
    return {
        anchor = anchor,
        place = function(center: Vector3, r: number, h: number, t: number, a: number)
            anchor.CFrame = CFrame.new(center)
            local step = math.floor(t * 15)
            for j, tg in list do
                local radial = Vector3.new(math.cos(tg.th), 0, math.sin(tg.th))
                local fl = 0.55 + 0.6 * novaHash(tg.seed, step)
                tg.a0.Position = radial * r
                tg.a1.Position = radial * (r * 1.06 + 0.25) + Vector3.new(0, h * fl, 0)
                tg.beam.CurveSize0 = 0.5 * math.sin(t * 17 + j)
            end
            if math.abs(a - lastA) > 0.01 then
                lastA = a
                local seq = if a <= 0.01 then NumberSequence.new(1) else NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 1 - 0.92 * a),
                    NumberSequenceKeypoint.new(0.7, 1 - 0.55 * a),
                    NumberSequenceKeypoint.new(1, 1),
                })
                for _, tg in list do tg.beam.Transparency = seq end
            end
        end,
        destroy = function()
            anchor:Destroy()
        end,
    }
end

-- Jetpack und Visier eines Modells (Teile "acc_flame", "acc_nozzle",
-- "acc_visor", "acc_jetpack", Bezug "..._body"). set(power, visor, t): die
-- Duesenflammen wachsen mit `power` (0 = Original) und flackern, Neon nur
-- solange sie brennen (F17); `visor` 0..1 laesst das Visier leuchten, ueber 1
-- blitzt es weiss. Nach jedem PivotTo aufrufen (Groesse ueber scaleOf, Teil-
-- groessen absolut aus Start x Scale x Faktor). visor()/pack() = Weltlage von
-- Visier bzw. Jetpack (Quellen der Lichtkegel). Ohne "_body": nil.
local function pulsarJet(model: Model, scaleOf: () -> number, col: Color3): PulsarJet?
    local body: BasePart? = nil
    local visorP: BasePart? = nil
    local packP: BasePart? = nil
    local flameParts: { BasePart } = {}
    local nozzles: { BasePart } = {}
    for _, d in model:GetDescendants() do
        if d:IsA("BasePart") then
            local n = string.lower(d.Name)
            if string.find(n, "_body", 1, true) then
                body = d
            elseif string.find(n, "acc_flame", 1, true) then
                table.insert(flameParts, d)
            elseif string.find(n, "acc_nozzle", 1, true) then
                table.insert(nozzles, d)
            elseif string.find(n, "acc_visor", 1, true) then
                visorP = d
            elseif string.find(n, "acc_jetpack", 1, true) then
                packP = d
            end
        end
    end
    if not body then return nil end
    local b = body :: BasePart
    local bcf = b.CFrame
    local flames: { JetFlame } = {}
    for _, fp in flameParts do
        local rel = bcf:ToObjectSpace(fp.CFrame)
        -- Spitzen-Richtung: von der naechsten Duese zur Flamme (sonst nach unten)
        local dir = Vector3.new(0, -1, 0)
        local best = math.huge
        for _, nz in nozzles do
            local v = rel.Position - bcf:PointToObjectSpace(nz.Position)
            if v.Magnitude < best and v.Magnitude > 0.01 then
                best = v.Magnitude
                dir = v.Unit
            end
        end
        -- Laengsachse = die lokale Achse der Flamme, die am besten zur Spitze passt
        local axes = { rel.RightVector, rel.UpVector, rel.LookVector }
        local axis, bestDot = 2, -1
        for i, ax in axes do
            local dd = math.abs(ax:Dot(dir))
            if dd > bestDot then
                bestDot = dd
                axis = i
            end
        end
        table.insert(flames, { p = fp, rel = rel, size = fp.Size, axis = axis, dir = dir,
            mat = fp.Material, col = fp.Color, hot = false })
    end
    local vRel: CFrame? = if visorP then bcf:ToObjectSpace(visorP.CFrame) else nil
    local vMat = if visorP then visorP.Material else Enum.Material.Plastic
    local vCol = if visorP then visorP.Color else col
    local vHot = false
    local pRel: CFrame = if packP then bcf:ToObjectSpace(packP.CFrame) else CFrame.new(0, 0, 1)
    local function lenOf(sz: Vector3, axis: number): number
        return if axis == 1 then sz.X elseif axis == 3 then sz.Z else sz.Y
    end
    local function along(sz: Vector3, axis: number, len: number, thick: number): Vector3
        if axis == 1 then return Vector3.new(len, sz.Y * thick, sz.Z * thick) end
        if axis == 3 then return Vector3.new(sz.X * thick, sz.Y * thick, len) end
        return Vector3.new(sz.X * thick, len, sz.Z * thick)
    end
    return {
        set = function(power: number, visor: number, t: number)
            local sc = scaleOf()
            local bc = b.CFrame
            for i, fl in flames do
                if power <= 0.01 then
                    if fl.hot then
                        fl.hot = false
                        fl.p.Material = fl.mat
                        fl.p.Color = fl.col
                    end
                    fl.p.Size = fl.size * sc
                    fl.p.CFrame = bc * CFrame.new(fl.rel.Position * sc) * fl.rel.Rotation
                else
                    if not fl.hot then
                        fl.hot = true
                        fl.p.Material = Enum.Material.Neon
                    end
                    local flick = 1 + 0.22 * math.sin(t * 46 + i * 2.1) + 0.12 * math.sin(t * 91 + i * 0.7)
                    local len0 = lenOf(fl.size, fl.axis) * sc
                    local len = len0 * (1 + power * 2.4 * flick)
                    fl.p.Size = along(fl.size * sc, fl.axis, len, 1 + 0.35 * power)
                    local top = fl.rel.Position * sc - fl.dir * (len0 * 0.5)
                    fl.p.CFrame = bc * CFrame.new(top + fl.dir * (len * 0.5)) * fl.rel.Rotation
                    fl.p.Color = col:Lerp(PULSAR_WHITE, math.clamp(0.25 + 0.3 * flick * power, 0, 1))
                end
            end
            local vp = visorP
            if vp then
                if visor > 0.02 then
                    if not vHot then
                        vHot = true
                        vp.Material = Enum.Material.Neon
                    end
                    vp.Color = col:Lerp(PULSAR_WHITE, 0.1 + 0.9 * math.clamp(visor - 1, 0, 1))
                elseif vHot then
                    vHot = false
                    vp.Material = vMat
                    vp.Color = vCol
                end
            end
        end,
        visor = function(): Vector3
            local sc = scaleOf()
            local vr = vRel
            if vr then
                return (b.CFrame * CFrame.new(vr.Position * sc)).Position
            end
            return (b.CFrame * CFrame.new(0, 0.5 * sc, -1.0 * sc)).Position
        end,
        pack = function(): Vector3
            return (b.CFrame * CFrame.new(pRel.Position * scaleOf())).Position
        end,
    }
end

-- pulsar: der Pulsar-Baerchi SELBST (echter Klon, Original lokal unsichtbar,
-- F03). Bodenblitz, ein Lichtpunkt zeichnet in `draw` s einen Ring (Radius
-- `ring`, 12 Tick-Striche) um ihn; er duckt sich (`crouchAt`), das Jetpack
-- zuendet, er steigt mit Drehung auf (`height`, `spins`, `grow`) - der Ring
-- hebt mit ab und wird sein Orbit-Ring. Ab `beamAt` Leuchtturm: Lichtkegel
-- aus Visier (vorn) und Jetpack (hinten), Laenge `beamLen`, zur Hoehe der
-- Kamera geneigt; er dreht sich immer schneller, so dass der Visier-Kegel
-- genau zu den Zeiten in `ticks` durch die Kamera DIESES Clients fegt
-- (Richtung beim Start fest, F22) - jeder Durchgang blitzt groesser (Besitzer:
-- Bildschirm-Schleier). Bei `collapseAt` stuerzen Kegel und Ring in ihn: er
-- wird zum weissgluehenden Neutronenstern (Anime-Sternbruch: flackernde
-- Zacken, Funken im Bogen), pulst bei jedem `pulseAt`, holt ab `windAt`
-- Schwung und schiesst bei `launchAt` in `fly` s als Komet in den Gegner
-- (Landung = Einschlag; Schweif, Nachbilder). Ab `emergeAt` rollt er sich aus
-- dem Krater auf, Rueckwaerts-Salto heim (`back`), Landung, der Ring blitzt
-- noch einmal um seine Fuesse (`settle`). Setzt avatarCf, pulsarHover,
-- pulsarCam (Kamera "pulsar"). Laeuft auch ohne Jetpack (fremde Modelle).
--   ring, draw, crouchAt, crouch, rise, height, spins, grow, beamAt, beamLen,
--   ticks, collapseAt, pulseAt, windAt, launchAt, fly, emergeAt, emerge,
--   back, settle (Test: freezeAt, trailLife)
BLOCKS.pulsar = function(ctx, s)
    local source = ctx.selfModel
    if not source or not source.Parent then return end
    local clone = figureClone(source)
    if not clone then return end
    local H = ctx.selfSize.Y
    local home = CFrame.lookAt(ctx.selfFeet, ctx.selfFeet + ctx.fwd)
    local offset = home:ToObjectSpace(clone:GetPivot())
    local okScale, got = pcall(function() return clone:GetScale() end)
    local baseScale: number = if okScale and typeof(got) == "number" then got else 1
    local col = ctx.fx.color
    local col2 = ctx.fx.color2
    local f = ctx.factor
    local rich = extrasOn(ctx)
    local ringR = s.ring or 3.6
    local draw = math.max(0.1, s.draw or 0.35)
    local crouchAt = s.crouchAt or 0.38
    local crouch = math.max(0.05, s.crouch or 0.24)
    local rise = math.max(0.2, s.rise or 0.48)
    local height = s.height or 5.5
    local spins = s.spins or 1
    local grow = s.grow or 1.15
    local beamAt = s.beamAt or 1.05
    local beamLen = s.beamLen or 34
    local ticks: { number } = s.ticks or { 1.2, 1.48, 1.7, 1.86, 2.01 }
    local collapseAt = s.collapseAt or 2.05
    local pulseAt: { number } = s.pulseAt or { 2.15, 2.3 }
    local windAt = s.windAt or 2.33
    local launchAt = math.max(collapseAt + 0.1, s.launchAt or 2.45)
    local fly = math.max(0.1, s.fly or 0.43)
    local emergeAt = s.emergeAt or 4.42
    local emerge = math.max(0.05, s.emerge or 0.16)
    local back = math.max(0.2, s.back or 0.72)
    local settle = math.max(0.1, s.settle or 0.35)
    local freezeAt: number? = s.freezeAt
    local trailLife = s.trailLife or 0.16
    local riseAt = crouchAt + crouch
    local hangAt = riseAt + rise
    local landAt = launchAt + fly
    local backAt = emergeAt + emerge
    local homeAt = backAt + back
    local total = homeAt + settle
    local hide = hideFigure(source)
    local hideClone = hideFigure(clone)
    local rng = Random.new(41)

    -- Schwebepunkt und Kamera-Seite (waagerecht + Hoehenwinkel) zur Kamera
    -- DIESES Clients, einmal beim Start (F22): danach richten sich der Tick-
    -- Fahrplan, die Neigung der Kegel und die Kamerafahrt.
    local hoverFeet = ctx.selfFeet + ctx.fwd * 1.2 + Vector3.new(0, height, 0)
    local hoverC = hoverFeet + Vector3.new(0, H * grow * 0.5, 0)
    local camDir = sideOf(ctx)
    local camPitch = 0.12
    local cam = workspace.CurrentCamera
    if cam then
        local v = cam.CFrame.Position - hoverC
        local flat = Vector3.new(v.X, 0, v.Z)
        if flat.Magnitude > 1 then
            camDir = flat.Unit
            camPitch = math.clamp(math.atan2(v.Y, flat.Magnitude), -0.35, 0.45)
        end
    end
    ctx.pulsarHover = hoverC
    ctx.pulsarCam = camDir
    local camN = if cam then cam.CFrame.Position - hoverC else camDir
    camN = if camN.Magnitude > 0.1 then camN.Unit else camDir
    local upP = Vector3.yAxis - camN * Vector3.yAxis:Dot(camN)
    upP = if upP.Magnitude > 0.1 then upP.Unit else perpOf(camN)
    local rgtP = upP:Cross(camN).Unit

    -- Gier-Fahrplan: nach dem Aufstieg blickt er zum Gegner (spins * TAU); der
    -- Visier-Kegel zeigt zur Kamera, wenn yaw = yawCam (mod TAU). Zwischen den
    -- Ticks je eine volle Drehung - die Abstaende werden kuerzer, er dreht
    -- immer schneller.
    local lc = CFrame.lookAt(Vector3.zero, ctx.fwd):VectorToObjectSpace(camDir)
    local yawCam = math.atan2(-lc.X, -lc.Z)
    local yaw0 = spins * TAU
    local tickYaw: { number } = {}
    do
        local y = yawCam
        while y < yaw0 + math.pi * 0.6 do y += TAU end
        for i = 1, #ticks do
            tickYaw[i] = y + (i - 1) * TAU
        end
    end
    local function yawAt(t: number): number
        if t <= hangAt or #ticks == 0 then return yaw0 end
        local t1 = ticks[1]
        if t < t1 then
            local k = (t - hangAt) / math.max(0.05, t1 - hangAt)
            return yaw0 + (tickYaw[1] - yaw0) * k * k
        end
        for i = 1, #ticks - 1 do
            if t < ticks[i + 1] then
                local k = (t - ticks[i]) / math.max(0.02, ticks[i + 1] - ticks[i])
                return tickYaw[i] + TAU * k
            end
        end
        local n = #ticks
        local lastDt = if n >= 2 then math.max(0.02, ticks[n] - ticks[n - 1]) else 0.2
        return tickYaw[n] + TAU * (t - ticks[n]) / lastDt
    end

    -- Klon: warmes Weiss + cyan Umriss, damit er vor jedem Himmel klar bleibt (F37)
    local hl = Instance.new("Highlight")
    hl.Adornee = clone
    hl.DepthMode = Enum.HighlightDepthMode.Occluded
    hl.FillColor = Color3.fromRGB(255, 252, 240)
    hl.FillTransparency = 0.88
    hl.OutlineColor = col
    hl.OutlineTransparency = 0.1
    hl.Parent = clone

    -- Funken und Staub (EIN Anker an der Koerpermitte)
    local anchor = newPart(Enum.PartType.Block, Vector3.one * 0.2, col, home, 1)
    local sparks = Instance.new("ParticleEmitter")
    sparks.Texture = SPARK_TEX
    sparks.Rate = 0
    sparks.Speed = NumberRange.new(5, 12)
    sparks.SpreadAngle = Vector2.new(180, 180)
    sparks.Lifetime = NumberRange.new(0.3, 0.7)
    sparks.Drag = 2
    sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.34), NumberSequenceKeypoint.new(1, 0) })
    sparks.Color = ColorSequence.new(PULSAR_WHITE, col)
    sparks.LightEmission = 0.6
    sparks.Parent = anchor
    local dust = Instance.new("ParticleEmitter")
    dust.Texture = SMOKE_TEX
    dust.Rate = 0
    dust.Speed = NumberRange.new(3, 8)
    dust.SpreadAngle = Vector2.new(180, 20)
    dust.Lifetime = NumberRange.new(0.5, 0.9)
    dust.Drag = 3
    dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, H * 0.3), NumberSequenceKeypoint.new(1, H * 0.8) })
    dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
    dust.Color = ColorSequence.new(PULSAR_WHITE, col)
    dust.LightEmission = 0.2
    dust.Rotation = NumberRange.new(0, 360)
    dust.Parent = anchor

    -- Ring am Boden: Lichtpunkt zeichnet ihn (Start auf der Kamera-Seite),
    -- 12 Tick-Striche wie ein Zifferblatt ("tickt wie eine Uhr")
    local startAng = math.atan2(-camDir.Z, camDir.X)
    local groundC = ctx.selfFeet + Vector3.new(0, 0.12, 0)
    local ringFrame0 = CFrame.new(groundC) * CFrame.Angles(0, startAng, 0)
    local ring = novaRing(col, 0.4, 0.12, 14)
    local tickParts: { BasePart } = {}
    for j = 0, 11 do
        local th = j / 12 * TAU
        local radial = ringFrame0:VectorToWorldSpace(Vector3.new(math.cos(th), 0, math.sin(th)))
        local pos = groundC + radial * (ringR + 0.5) - Vector3.new(0, 0.06, 0)
        local p = newPart(Enum.PartType.Block, Vector3.new(0.62, 0.08, 0.26), PULSAR_WHITE,
            CFrame.fromMatrix(pos, radial, Vector3.yAxis), 1)
        p.Name = "PulsarTick"
        tickParts[j + 1] = p
    end
    local head = newPart(Enum.PartType.Ball, Vector3.one * 0.55, PULSAR_WHITE, PARK, 1)
    head.Name = "PulsarHead"
    local flashDisc = newPart(Enum.PartType.Cylinder, Vector3.new(0.06, ringR * 0.8, ringR * 0.8),
        col:Lerp(PULSAR_WHITE, 0.5), CFrame.new(ctx.selfFeet + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90)), 0.3)
    flashDisc.Name = "PulsarFlash"
    tween(flashDisc, 0.24, { Size = Vector3.new(0.06, ringR * 2.7, ringR * 2.7), Transparency = 1 })
    Debris:AddItem(flashDisc, 0.3)

    -- Lichtkegel: Kern (weiss -> cyan) + breiter Schein, je vorn und hinten
    local beamAnchor = newPart(Enum.PartType.Block, Vector3.one * 0.2, col, PARK, 1)
    beamAnchor.Name = "PulsarBeams"
    local function mkAtt(): Attachment
        local a = Instance.new("Attachment")
        a.Parent = beamAnchor
        return a
    end
    local vA0, vA1, jA0, jA1 = mkAtt(), mkAtt(), mkAtt(), mkAtt()
    local function mkBeam(a0: Attachment, a1: Attachment, w0: number, w1: number, c0: Color3, c1: Color3,
        tr0: number, emission: number): Beam
        local bm = Instance.new("Beam")
        bm.Attachment0 = a0
        bm.Attachment1 = a1
        bm.FaceCamera = true
        bm.Segments = 12
        bm.Width0 = w0
        bm.Width1 = w1
        bm.LightEmission = emission
        bm.LightInfluence = 0
        bm.Color = ColorSequence.new(c0, c1)
        bm.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, tr0),
            NumberSequenceKeypoint.new(0.45, tr0 + (1 - tr0) * 0.45),
            NumberSequenceKeypoint.new(1, 1),
        })
        bm.Enabled = false
        bm.Parent = beamAnchor
        return bm
    end
    local beams: { Beam } = {
        mkBeam(vA0, vA1, 0.35, 2.6, PULSAR_WHITE, col, 0.05, 0.5),
        mkBeam(vA0, vA1, 1.2, 8.0, col, col, 0.55, 0.35),
        mkBeam(jA0, jA1, 0.4, 2.8, PULSAR_WHITE, col, 0.08, 0.5),
        mkBeam(jA0, jA1, 1.3, 8.5, col, col, 0.6, 0.35),
    }
    local beamsOn = false

    -- Leuchtturm-Blitz an der Quelle, die gerade zur Kamera zeigt
    local glowTex = texOf(ctx, "glow")
    local flareP = newPart(Enum.PartType.Block, Vector3.one * 0.2, col, PARK, 1)
    flareP.Name = "PulsarFlare"
    local flareGui: BillboardGui? = nil
    local flareImg: ImageLabel? = nil
    local flareBall: BasePart? = nil
    if glowTex then
        local g = Instance.new("BillboardGui")
        g.Size = UDim2.fromScale(2, 2)
        g.LightInfluence = 0
        g.Brightness = 2
        g.Adornee = flareP
        g.Parent = flareP
        local img = Instance.new("ImageLabel")
        img.BackgroundTransparency = 1
        img.Image = glowTex
        img.ImageColor3 = col:Lerp(PULSAR_WHITE, 0.45)
        img.ImageTransparency = 1
        img.Size = UDim2.fromScale(1, 1)
        img.Parent = g
        flareGui, flareImg = g, img
    end
    -- Neon-Kern zusaetzlich zum Bild: das Schein-Bild allein verschwindet vor
    -- hellem Himmel (Test 25.10.); sichtbar nur nahe der Kamera-Richtung
    local ball = newPart(Enum.PartType.Ball, Vector3.one, col:Lerp(PULSAR_WHITE, 0.6), PARK, 1)
    ball.Name = "PulsarFlareBall"
    flareBall = ball
    local veil = novaVeil(ctx)

    -- Neutronenstern: Kern, Kraftfeld-Huelle, Schein, Schweif (an der Huelle,
    -- die sich nicht dreht)
    local orbCore = newPart(Enum.PartType.Ball, Vector3.one * 1.5, PULSAR_WHITE, PARK, 1)
    orbCore.Name = "PulsarOrb"
    local orbShell = newPart(Enum.PartType.Ball, Vector3.one * 2.8, col, PARK, 1)
    orbShell.Material = Enum.Material.ForceField
    orbShell.Name = "PulsarOrbShell"
    local orbTex = texOf(ctx, "orb")
    local orbGui: BillboardGui? = nil
    local orbImg: ImageLabel? = nil
    if orbTex then
        local g = Instance.new("BillboardGui")
        g.Size = UDim2.fromScale(6, 6)
        g.LightInfluence = 0
        g.Brightness = 1.6
        g.Adornee = orbShell
        g.Parent = orbShell
        local img = Instance.new("ImageLabel")
        img.BackgroundTransparency = 1
        img.Image = orbTex
        img.ImageColor3 = col
        img.ImageTransparency = 1
        img.Size = UDim2.fromScale(1, 1)
        img.Parent = g
        orbGui, orbImg = g, img
    end
    local ta0 = Instance.new("Attachment")
    ta0.Position = Vector3.new(0, 0.7, 0)
    ta0.Parent = orbShell
    local ta1 = Instance.new("Attachment")
    ta1.Position = Vector3.new(0, -0.7, 0)
    ta1.Parent = orbShell
    local trail = Instance.new("Trail")
    trail.Attachment0 = ta0
    trail.Attachment1 = ta1
    trail.Lifetime = 0.2
    trail.MinLength = 0.05
    trail.FaceCamera = true
    trail.LightEmission = 0.5
    trail.LightInfluence = 0
    trail.Color = ColorSequence.new(PULSAR_WHITE, col2)
    trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
    trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.15) })
    local tailTex = texOf(ctx, "tail")
    if tailTex then
        trail.Texture = tailTex
        trail.TextureMode = Enum.TextureMode.Stretch
    end
    trail.Enabled = false
    trail.Parent = orbShell

    -- Sternbruch: zwei Zacken-Saetze (Klingen in der Ebene zur Kamera), im
    -- Wechsel sichtbar (2-Bild-Schritte wie im Anime), dazu Funken-Pillen
    local starRig: { RigPart } = {}
    local starSet: { [RigPart]: number } = {}
    local starBlade: { [RigPart]: number } = {}
    local nSpk = if rich then 12 else 8
    local bladeNo = 0
    for set = 1, 2 do
        for j = 1, nSpk do
            bladeNo += 1
            local a = (j - 1 + (set - 1) * 0.5 + rng:NextNumber(-0.25, 0.25)) / nSpk * TAU
            local d = upP * math.cos(a) + rgtP * math.sin(a)
            local frame = CFrame.fromMatrix(Vector3.zero, camN, d)
            local hgt = rng:NextNumber(1.6, 3.6) * (if set == 1 then 1 else 0.8)
            local before = #starRig
            addBlade(starRig, frame, 0.08, hgt, rng:NextNumber(0.13, 0.21),
                if set == 1 then PULSAR_WHITE else col, Enum.Material.Neon, 0)
            for k = before + 1, #starRig do
                starSet[starRig[k]] = set
                starBlade[starRig[k]] = bladeNo
            end
        end
    end
    local pills: { SparkPill } = {}
    for _ = 1, (if rich then 16 else 9) do
        local a = rng:NextNumber(0, TAU)
        local dirP = (upP * math.cos(a) + rgtP * math.sin(a) + camN * rng:NextNumber(-0.35, 0.35)).Unit
        local p = newPart(Enum.PartType.Block, Vector3.new(0.26, 0.26, 1.0), PULSAR_WHITE, PARK, 1)
        p.Name = "PulsarSpark"
        table.insert(pills, { p = p, v = dirP * rng:NextNumber(11, 22) + Vector3.new(0, 4, 0),
            life = rng:NextNumber(0.32, 0.58), len = rng:NextNumber(0.8, 1.5) })
    end
    local pulseRings: { NovaRing } = {}
    for _ = 1, #pulseAt do
        table.insert(pulseRings, novaRing(col:Lerp(PULSAR_WHITE, 0.3), 0.5, 0.05, 14))
    end

    local lastScale = 1
    -- Pose: Fuesse `feet`, gedreht um die Koerpermitte (wie `ascend`)
    local function place(feet: CFrame, pitch: number, yaw: number, roll: number, sc: number)
        if math.abs(sc - lastScale) > 0.008 then
            lastScale = sc
            pcall(function() clone:ScaleTo(baseScale * sc) end)
        end
        local half = H * sc * 0.5
        local pose = feet * CFrame.new(0, half, 0) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, roll) * CFrame.new(0, -half, 0)
        ctx.avatarCf = pose
        ctx.avatarScale = sc
        clone:PivotTo(pose * CFrame.new(offset.Position * sc) * offset.Rotation)
        anchor.CFrame = pose * CFrame.new(0, half, 0)
    end
    local function face(pos: Vector3): CFrame
        return CFrame.lookAt(pos, pos + ctx.fwd)
    end
    place(home, 0, 0, 0, 1)
    clone.Parent = folder()
    hide(1)
    -- ohne Jetpack (fremdes Modell): Quellen der Kegel vorn/hinten am Koerper
    local jet: PulsarJet = pulsarJet(clone, function() return lastScale end, col) or {
        set = function(_p: number, _v: number, _t: number) end,
        visor = function(): Vector3
            local pose = ctx.avatarCf or home
            return (pose * CFrame.new(0, H * lastScale * 0.6, -0.9 * lastScale)).Position
        end,
        pack = function(): Vector3
            local pose = ctx.avatarCf or home
            return (pose * CFrame.new(0, H * lastScale * 0.45, 0.9 * lastScale)).Position
        end,
    }

    -- Flugbahn des Neutronensterns: holt Schwung (zurueck, hoch), dann Bogen
    -- in den Gegner, beschleunigt (k^2, F32)
    local hitPos = ctx.targetPos - ctx.fwd * (ctx.targetSize.Z * 0.3)
    local windP = hoverC - ctx.fwd * 0.9 + Vector3.new(0, 0.5, 0)
    local ctrlP = windP:Lerp(hitPos, 0.45) + Vector3.new(0, 3.2, 0)
    local landGap = (ctx.selfSize.Z + ctx.targetSize.Z) * 0.4 + 0.4
    local emergeFeet = ctx.targetFeet - ctx.fwd * (landGap + 1.2)
    local function orbPos(t: number): Vector3
        if t < windAt then
            return hoverC
        elseif t < launchAt then
            return hoverC:Lerp(windP, easeOutCubic((t - windAt) / math.max(0.02, launchAt - windAt)))
        end
        local k = math.clamp((t - launchAt) / fly, 0, 1)
        return novaBez(windP, ctrlP, hitPos, k * k)
    end

    local fired: { [string]: boolean } = {}
    local function once(key: string): boolean
        if fired[key] then return false end
        fired[key] = true
        return true
    end
    local tickDone: { boolean } = {}
    local pulseDone: { boolean } = {}
    local lastT = -1
    local ghostT = 0
    local starShown = false
    runLoop("pulsar", function(tRaw)
        if not clone.Parent then return true end
        if tRaw >= (if freezeAt then freezeAt + 150 else total) then return true end
        local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
        local dtE = if lastT < 0 then 0 else math.max(0, t - lastT)
        lastT = t
        local power, visorGlow = 0, 0
        local inOrb = t >= collapseAt + 0.05 and t < emergeAt

        -- 1. der Baerchi
        if t < crouchAt then
            -- schaut sich den Ring an, das Visier geht an
            local k = math.clamp(t / crouchAt, 0, 1)
            place(home, -0.06 * math.sin(math.pi * k), 0, 0, 1)
            visorGlow = math.min(1, t / 0.25)
        elseif t < riseAt then
            -- ausholen: zuruecklehnen, kleiner; am Ende zuenden die Duesen
            local e = math.sin(((t - crouchAt) / crouch) * math.pi * 0.5)
            place(home, 0.26 * e, 0, 0, 1 - 0.08 * e)
            visorGlow = 1
            power = math.clamp((t - (riseAt - 0.1)) / 0.1, 0, 1) * 0.5
        elseif t < hangAt then
            -- Aufstieg mit Drehung (Jetpack), waechst
            if once("rise") then
                sparks:Emit(scaled(24, f))
                dust:Emit(scaled(16, f))
            end
            local k = (t - riseAt) / rise
            local e = easeOutCubic(k)
            local pos = home.Position:Lerp(hoverFeet, e) + Vector3.new(0, math.sin(math.pi * k) * 1.0, 0)
            place(face(pos), 0.26 * (1 - e), spins * TAU * e, 0, lerpN(0.92, grow, e))
            power = lerpN(0.6, 1, e)
            visorGlow = 1
        elseif t < collapseAt + 0.05 then
            -- Leuchtturm: kreist immer schneller, wippt; zieht sich zum Kollaps zusammen
            local h = t - hangAt
            local pos = hoverFeet + Vector3.new(0, math.sin(h * 5.5) * 0.12, 0)
            local shrink = math.clamp((t - (collapseAt - 0.1)) / 0.15, 0, 1)
            place(face(pos), 0.05 * math.sin(h * 3), yawAt(t), 0.04 * math.sin(h * 4.3),
                lerpN(grow, grow * 0.45, shrink * shrink))
            power = 1
            visorGlow = 1
            for i, tt in ticks do
                if t >= tt and t < tt + 0.07 then
                    visorGlow = 2
                end
                if t >= tt and not tickDone[i] then
                    tickDone[i] = true
                    twinkle(jet.visor() + camN * 0.6, 2.4 + 0.8 * i, PULSAR_WHITE, 0.45)
                    sparks:Emit(scaled(6 + 3 * i, f))
                end
            end
        elseif t >= emergeAt and t < backAt then
            -- rollt sich aus dem Krater auf (halbe Rolle, waechst federnd)
            if once("emerge") then
                hideClone(0)
                hl.Enabled = true
                twinkle(emergeFeet + Vector3.new(0, H * 0.6, 0), 3, PULSAR_WHITE, 0.3)
                sparks:Emit(scaled(18, f))
            end
            local k = (t - emergeAt) / emerge
            local pos = ctx.targetFeet:Lerp(emergeFeet, easeOutCubic(k))
            place(face(pos), -math.pi * (1 - k), 0, 0, lerpN(0.5, 1, easeOutBack(k)))
            power = 0.4
            visorGlow = 1
        elseif t >= backAt and t < homeAt then
            -- Rueckwaerts-Salto heim
            local k = (t - backAt) / back
            local e = easeInOutSine(k)
            local pos = emergeFeet:Lerp(home.Position, e) + Vector3.new(0, math.sin(math.pi * k) * 4.5, 0)
            place(face(pos), TAU * e, 0, 0, 1)
            power = 0.2 + 0.7 * math.sin(math.pi * k)
            visorGlow = 1
        elseif t >= homeAt then
            -- Landung, die Duesen gehen aus
            if once("land") then
                dust:Emit(scaled(18, f))
                sparks:Emit(scaled(12, f))
            end
            local k = math.clamp((t - homeAt) / settle, 0, 1)
            place(home, 0, 0, 0, 1 - 0.1 * math.exp(-k * 6) * math.sin(k * 9))
            power = math.max(0, 0.5 * (1 - k * 2))
            visorGlow = math.max(0, 1 - k * 1.5)
        end
        if not inOrb then
            jet.set(power, visorGlow, t)
        end

        -- 2. Ring: am Boden zeichnen, mit ihm aufsteigen (Orbit-Ring), beim
        -- Kollaps in ihn stuerzen; zu Hause blitzt er noch einmal auf
        local drawn = math.clamp(t / draw, 0, 1)
        local rA, rP, rR, rW = 0, 1, ringR, 0.32
        local rCf = ringFrame0
        if t < riseAt then
            rA, rP = 1, drawn
        elseif t < collapseAt + 0.09 then
            local kr = math.clamp((t - riseAt) / rise, 0, 1)
            local ks = math.clamp((t - hangAt) / math.max(0.1, collapseAt - hangAt), 0, 1)
            local feetNow = if t < hangAt then (ctx.avatarCf or home).Position else hoverFeet
            local waist = feetNow + Vector3.new(0, H * lastScale * 0.42, 0)
            rR = lerpN(ringR, 2.7, easeOutCubic(kr)) - 0.7 * ks
            if t >= collapseAt then
                rR *= (1 - math.min(1, (t - collapseAt) / 0.09)) ^ 2
            end
            rW = lerpN(0.32, 0.26, ks)
            rCf = CFrame.new(groundC:Lerp(waist, easeOutCubic(kr))) * CFrame.Angles(0, startAng + yawAt(t) * 0.5, 0)
            rA = 1
        elseif t >= homeAt then
            rR, rW = 2.8, 0.28
            rCf = ringFrame0
            rP = math.clamp((t - homeAt) / 0.16, 0, 1)
            rA = 1 - math.clamp((t - homeAt - 0.16) / math.max(0.05, settle - 0.16), 0, 1)
        end
        ring.place(rCf, math.max(0.05, rR), rW)
        ring.alpha(rA, rP)
        -- Zeichenkopf und Tick-Striche (bleiben am Boden, verblassen beim Abheben)
        if drawn < 1 then
            local th = drawn * TAU
            head.CFrame = CFrame.new(groundC + ringFrame0:VectorToWorldSpace(Vector3.new(math.cos(th), 0, math.sin(th))) * ringR)
            head.Transparency = 0
        elseif once("drawn") then
            head.Transparency = 1
            twinkle(head.Position, 2.2, PULSAR_WHITE, 0.3)
        end
        local tickA = if t < riseAt then 1 else 1 - math.clamp((t - riseAt) / 0.3, 0, 1)
        for j, p in tickParts do
            local v = if drawn >= (j - 1) / 12 + 0.004 then 1 - 0.9 * tickA else 1
            if math.abs(p.Transparency - v) > 0.01 then p.Transparency = v end
        end

        -- 3. Lichtkegel + Blitz zur Kamera (Besitzer: Bildschirm-Schleier)
        local beamK = 0
        if t >= beamAt and t < collapseAt then
            beamK = easeOutCubic(math.min(1, (t - beamAt) / 0.14))
        elseif t >= collapseAt and t < collapseAt + 0.08 then
            beamK = 1 - (t - collapseAt) / 0.08
        end
        local glowA = 0
        if beamK > 0.01 then
            if not beamsOn then
                beamsOn = true
                for _, bm in beams do bm.Enabled = true end
            end
            local pose = ctx.avatarCf or home
            local look = pose.LookVector
            local flatLook = Vector3.new(look.X, 0, look.Z)
            flatLook = if flatLook.Magnitude > 0.05 then flatLook.Unit else ctx.fwd
            local dir = (flatLook * math.cos(camPitch) + Vector3.yAxis * math.sin(camPitch)).Unit
            local vSrc = jet.visor()
            local jSrc = jet.pack()
            local L = beamLen * beamK
            beamAnchor.CFrame = CFrame.new(vSrc)
            vA0.Position = Vector3.zero
            vA1.Position = dir * L
            jA0.Position = jSrc - vSrc
            jA1.Position = jSrc - vSrc - dir * L
            -- Ausrichtung zur ECHTEN Kamera (F22): Blitz an der Quelle, die zur Kamera zeigt
            local c2 = workspace.CurrentCamera
            if c2 then
                local cp = c2.CFrame.Position
                local aV = math.max(0, dir:Dot((cp - vSrc).Unit))
                local aJ = math.max(0, (-dir):Dot((cp - jSrc).Unit)) * 0.7
                local a = math.max(aV, aJ)
                local boost = 0
                for i, tt in ticks do
                    if t >= tt - 0.05 and t < tt + 0.12 then boost = 0.15 * i end
                end
                local inten = (a ^ 10) * beamK * (1 + boost)
                glowA = math.clamp((a ^ 14) * beamK * (0.35 + boost * 0.6), 0, 0.9)
                flareP.CFrame = CFrame.new(if aV >= aJ then vSrc else jSrc)
                local sz = 1.5 + 11 * inten
                local fg, fi, fb = flareGui, flareImg, flareBall
                if fg and fi then
                    fg.Size = UDim2.fromScale(sz, sz)
                    fi.ImageTransparency = 1 - math.clamp(0.2 + inten, 0, 0.95)
                end
                if fb then
                    -- Kern hoechstens ~3,7 Studs, Transparenz >= 0,3 (F36)
                    fb.CFrame = flareP.CFrame
                    fb.Size = Vector3.one * (0.6 + 2.4 * math.min(inten, 1.3))
                    fb.Transparency = 1 - math.clamp(inten * 0.7, 0, 0.7)
                end
            end
        elseif beamsOn then
            beamsOn = false
            for _, bm in beams do bm.Enabled = false end
            local fi, fb = flareImg, flareBall
            if fi then fi.ImageTransparency = 1 end
            if fb then fb.Transparency = 1 end
        end
        if veil then
            veil.set(PULSAR_WHITE, glowA)
        end

        -- 4. Kollaps: Neutronenstern, Sternbruch, Pulse, Flug
        if t >= collapseAt and t < landAt then
            if once("collapse") then
                sparks:Emit(scaled(30, f))
                twinkle(hoverC + camN * 0.5, 5, PULSAR_WHITE, 0.35)
            end
            if t >= collapseAt + 0.05 and once("orb") then
                hideClone(1)
                hl.Enabled = false
                jet.set(0, 0, t)
            end
            local shown = t >= collapseAt + 0.05
            local p = orbPos(t)
            local pop = easeOutBack(math.clamp((t - collapseAt - 0.03) / 0.12, 0, 1))
            local pulse = 0
            for i, pt in pulseAt do
                if t >= pt then
                    local q = t - pt
                    pulse = math.max(pulse, math.exp(-q * 14) * math.min(1, q / 0.03))
                    if not pulseDone[i] then
                        pulseDone[i] = true
                        sparks:Emit(scaled(12, f))
                    end
                end
            end
            local flyK = if t >= launchAt then math.clamp((t - launchAt) / fly, 0, 1) else 0
            local heat = flyK * flyK
            local szC = math.max(0.05, 1.5 * pop * (1 + 0.35 * pulse) * (1 - 0.25 * heat))
            orbCore.Size = Vector3.one * szC
            orbShell.Size = Vector3.one * szC * 1.9
            orbCore.Transparency = if shown then 0 else 1
            orbShell.Transparency = if shown then 0.15 else 1
            orbCore.Color = PULSAR_WHITE:Lerp(NOVA_HOT, heat)
            orbShell.Color = col:Lerp(col2, heat)
            orbCore.CFrame = CFrame.new(p)
            orbShell.CFrame = CFrame.new(p)
            anchor.CFrame = CFrame.new(p)
            ctx.avatarCf = CFrame.new(p)
            local og, oi = orbGui, orbImg
            if og and oi then
                og.Size = UDim2.fromScale(szC * 4.2, szC * 4.2)
                oi.ImageTransparency = if shown then 0.2 else 1
                oi.ImageColor3 = col:Lerp(col2, heat)
            end
            if t >= launchAt then
                if once("launch") then
                    trail.Enabled = true
                    sparks:Emit(scaled(20, f))
                end
                ghostT += dtE
                if ghostT >= 0.045 then
                    ghostT = 0
                    local g = newPart(Enum.PartType.Ball, Vector3.one * szC * 1.3, col:Lerp(col2, heat), CFrame.new(p), 0.35)
                    g.Name = "PulsarGhost"
                    tween(g, trailLife, { Transparency = 1, Size = Vector3.one * szC * 0.5 })
                    Debris:AddItem(g, trailLife + 0.1)
                end
            end
        elseif t >= landAt and once("landed") then
            -- Einschlag: der Stern verschwindet in der Kuppel (`firedome`)
            orbCore.Transparency = 1
            orbShell.Transparency = 1
            trail.Enabled = false
            local oi = orbImg
            if oi then oi.ImageTransparency = 1 end
            ctx.avatarCf = CFrame.new(hitPos)
            burstAt(ctx, hitPos, 26, 18, col)
        end

        -- Sternbruch (collapseAt .. +0,42): Zacken flackern, Funken fliegen
        local sb = t - collapseAt
        if sb >= 0 and sb < 0.42 then
            starShown = true
            local step = math.floor(sb * 15)
            local fadeK = 1 - math.clamp((sb - 0.26) / 0.16, 0, 1)
            local big = if step == 0 then 1.35 else 1
            rigApply(starRig, CFrame.new(hoverC), function(r: RigPart): number
                local on = (step % 2 == 0) == (starSet[r] == 1)
                return if on then (0.55 + 0.7 * novaHash(starBlade[r] or 0, step)) * big else 0
            end, fadeK)
            local parts: { BasePart } = table.create(#pills)
            local cfs: { CFrame } = table.create(#pills)
            for i, pl in pills do
                local dt = sb
                local tr = 1
                local pos = hoverC
                local vel = pl.v
                if dt < pl.life then
                    vel = pl.v + Vector3.new(0, -30 * dt, 0)
                    pos = hoverC + pl.v * dt + Vector3.new(0, -15 * dt * dt, 0)
                    tr = dt / pl.life
                end
                local ln = pl.len * (1 - 0.6 * math.min(1, dt / pl.life))
                if math.abs(pl.p.Size.Z - ln) > 0.02 then
                    pl.p.Size = Vector3.new(0.26, 0.26, math.max(0.1, ln))
                end
                if math.abs(pl.p.Transparency - tr) > 0.01 then pl.p.Transparency = tr end
                parts[i] = pl.p
                cfs[i] = CFrame.lookAt(pos, pos + (if vel.Magnitude > 0.1 then vel.Unit else Vector3.yAxis))
            end
            workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
        elseif starShown then
            starShown = false
            rigApply(starRig, CFrame.new(hoverC), function(_r: RigPart): number return 0 end, 0)
            for _, pl in pills do pl.p.Transparency = 1 end
        end

        -- Puls-Ringe des Neutronensterns (zur Kamera)
        for i, rg in pulseRings do
            local pt = pulseAt[i]
            local q = (t - pt) / 0.28
            if q >= 0 and q < 1 then
                rg.place(planeCf(orbPos(t), camN), lerpN(0.9, 4.8, easeOutCubic(q)), lerpN(0.32, 0.08, q))
                rg.alpha(1 - q)
            else
                rg.alpha(0)
            end
        end
        return false
    end, function()
        hide(0)
        ctx.avatarCf = nil
        ctx.avatarScale = nil
        ctx.pulsarHover = nil
        ctx.pulsarCam = nil
        clone:Destroy()
        ring.destroy()
        for _, rg in pulseRings do rg.destroy() end
        beamAnchor:Destroy()
        flareP:Destroy()
        local fb = flareBall
        if fb then fb:Destroy() end
        if veil then veil.destroy() end
        head:Destroy()
        for _, p in tickParts do p:Destroy() end
        for _, r in starRig do r.p:Destroy() end
        for _, pl in pills do pl.p:Destroy() end
        orbCore:Destroy()
        orbShell:Destroy()
        Debris:AddItem(anchor, 1.2)
    end)
end

-- Silhouette fuer den invertierten Impact-Frame: Klon einer Figur oder eines
-- Effekt-Teils, alles tintenschwarz (ViewportFrame ohne Licht).
local function novaInk(src: Instance, parent: Instance)
    local c: Instance? = nil
    if src:IsA("Model") then
        c = figureClone(src)
    else
        local ok, cc = pcall(function() return src:Clone() end)
        if ok then c = cc end
    end
    local inst = c
    if not inst then return end
    local function ink(p: BasePart)
        p.Material = Enum.Material.SmoothPlastic
        p.Color = NOVA_INK
        p.Transparency = 0
        p.Reflectance = 0
        if p:IsA("MeshPart") then
            pcall(function() (p :: MeshPart).TextureID = "" end)
        end
    end
    if inst:IsA("BasePart") then ink(inst) end
    for _, d in inst:GetDescendants() do
        if d:IsA("BasePart") then
            ink(d)
        elseif d:IsA("SpecialMesh") then
            d.TextureId = ""
        elseif d:IsA("Decal") or d:IsA("Texture") or d:IsA("SurfaceAppearance") or d:IsA("Highlight")
            or d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") or d:IsA("BillboardGui")
            or d:IsA("SurfaceGui") or d:IsA("Light") then
            d:Destroy()
        end
    end
    inst.Parent = parent
end

-- novaframe: Impact-Frames (nur Besitzer, F14). Bild 1: invertiert - rosa-
-- weisser Grund, tintenschwarze Silhouetten (ViewportFrame mit Klonen des
-- Gegners und aller Effekt-Teile, deren Name mit "IFrame" beginnt, z. B. die
-- kleine Kuppel) und Speedlines, die auf den Einschlag zulaufen; danach Weiss,
-- dann blendet das Weiss aus. Jedes Bild steht mindestens EIN gerendertes
-- Bild lang (Zaehlen ueber RenderStepped, nicht ueber Wartezeiten).
--   invert, white, fade, lines
BLOCKS.novaframe = function(ctx, s)
    if not ctx.isOwner then return end
    local cam = workspace.CurrentCamera
    if not cam then return end
    local inv = s.invert or 0.045
    local wht = s.white or 0.08
    local fade = math.max(0.05, s.fade or 0.16)
    local vs = cam.ViewportSize
    local W, Hs = math.max(1, vs.X), math.max(1, vs.Y)
    local gui = Instance.new("ScreenGui")
    gui.Name = "SkillFXImpactFrame"
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 52
    gui.ResetOnSpawn = false
    local paper = Instance.new("Frame")
    paper.Size = UDim2.fromScale(1, 1)
    paper.BorderSizePixel = 0
    paper.BackgroundColor3 = NOVA_PAPER
    paper.ZIndex = 1
    paper.Parent = gui
    local vp = Instance.new("ViewportFrame")
    vp.Size = UDim2.fromScale(1, 1)
    vp.BackgroundTransparency = 1
    vp.Ambient = Color3.new(0, 0, 0)
    vp.LightColor = Color3.new(0, 0, 0)
    vp.ZIndex = 2
    vp.Parent = gui
    local vcam = Instance.new("Camera")
    vcam.CFrame = cam.CFrame
    vcam.FieldOfView = cam.FieldOfView
    vcam.Parent = vp
    vp.CurrentCamera = vcam
    if ctx.targetModel and ctx.targetModel.Parent then
        novaInk(ctx.targetModel, vp)
    end
    for _, fo in workspace:GetChildren() do
        if fo.Name == "SkillFXLocal" then
            for _, d in fo:GetChildren() do
                if d:IsA("BasePart") and string.sub(d.Name, 1, 6) == "IFrame" then
                    novaInk(d, vp)
                end
            end
        end
    end
    -- Speedlines laufen auf den Einschlag zu (Bildpunkt ueber dem Gegner)
    local sp, _ = cam:WorldToViewportPoint(ctx.targetFeet + Vector3.new(0, 2, 0))
    local cx = math.clamp(sp.X, W * 0.2, W * 0.8)
    local cy = math.clamp(sp.Y, Hs * 0.2, Hs * 0.8)
    local lines = Instance.new("Frame")
    lines.Size = UDim2.fromScale(1, 1)
    lines.BackgroundTransparency = 1
    lines.ZIndex = 3
    lines.Parent = gui
    local rng = Random.new()
    local n = math.max(12, s.lines or 46)
    local diag = math.sqrt(W * W + Hs * Hs)
    for i = 1, n do
        local a = (i - 1) / n * TAU + rng:NextNumber(-0.05, 0.05)
        local r0 = rng:NextNumber(0.16, 0.42) * Hs
        local len = diag
        local w = if rng:NextNumber() < 0.2 then rng:NextNumber(0.022, 0.034) * Hs else rng:NextNumber(0.004, 0.016) * Hs
        local fr = Instance.new("Frame")
        fr.AnchorPoint = Vector2.new(0.5, 0.5)
        fr.Size = UDim2.fromOffset(len, w)
        fr.Position = UDim2.fromOffset(cx + math.cos(a) * (r0 + len / 2), cy + math.sin(a) * (r0 + len / 2))
        fr.Rotation = math.deg(a)
        fr.BorderSizePixel = 0
        fr.BackgroundColor3 = NOVA_INK
        fr.ZIndex = 3
        local g = Instance.new("UIGradient")
        g.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.18, 0.25),
            NumberSequenceKeypoint.new(1, 0),
        })
        g.Parent = fr
        fr.Parent = lines
    end
    local white = Instance.new("Frame")
    white.Size = UDim2.fromScale(1, 1)
    white.BorderSizePixel = 0
    white.BackgroundColor3 = Color3.new(1, 1, 1)
    white.BackgroundTransparency = 1
    white.ZIndex = 4
    white.Parent = gui
    gui.Parent = player:WaitForChild("PlayerGui")
    local stage, frames, tStage = 0, 0, 0
    runLoop("novaframe", function(t)
        frames += 1
        if stage == 0 then
            if t >= inv and frames >= 2 then
                stage, frames, tStage = 1, 0, t
                paper.Visible = false
                vp.Visible = false
                lines.Visible = false
                white.BackgroundTransparency = 0
            end
        elseif stage == 1 then
            if t - tStage >= wht and frames >= 2 then
                stage, tStage = 2, t
            end
        else
            local k = (t - tStage) / fade
            white.BackgroundTransparency = math.min(1, k)
            if k >= 1 then return true end
        end
        return false
    end, function()
        gui:Destroy()
    end)
end

-- firedome: die Feuerkuppel am Einschlag (wie im Vorbild). Erst steht `miniFor`
-- s eine kleine gleissende Kuppel (Radius `mini`, Name "IFrameDome": auch
-- Silhouette im invertierten Impact-Frame), dann waechst die grosse Kuppel
-- (Radius `radius`) mit Ueberschwingen (`grow`): flach weissgluehender Kern
-- (SmoothPlastic, nur schwache Highlight-Fuellung - sie liegt ueber den
-- Baendern, F45; kein Neon - kein Bloom, F17/F36),
-- pinker Umriss, schwacher Neon-Schein (0,9, F05), laufende Flammenbaender
-- (Bezier-Beams mit Luecken, LightEmission 0: vor Weiss sonst unsichtbar),
-- dunkle Loecher, Flammenkranz am Fuss (Beams, flackern), Truemmer, Glut,
-- Brandfleck. Bei jedem `pulseAt` gleisst sie auf und schwillt kurz an
-- (Besitzer: rosa Schleier), bei `flareAt` flammt sie weiss auf (Besitzer:
-- Weissblende -> Rosa) und vergeht in `fade` s; danach zuengeln `burn` s
-- kleine Flammen am Gegner (Brand). Setzt novaT0/novaCenter/novaRadius
-- (Kamera "pulsar" faehrt zurueck).
--   at, radius, mini, miniFor, grow, pulseAt, flareAt, fade, burn,
--   holes, skirt, chunks (Test: freezeAt)
BLOCKS.firedome = function(ctx, s)
    local feet = groundAt(ctx, s.at or "target")
    local R = radiusOf(s.radius, 8)
    local miniR = s.mini or 3.2
    local miniFor = math.max(0.02, s.miniFor or 0.07)
    local grow = math.max(0.05, s.grow or 0.12)
    local pulseAt: { number } = s.pulseAt or { 0.55, 1.05 }
    local flareAt = s.flareAt or 1.45
    local fade = math.max(0.1, s.fade or 0.3)
    local burn = math.max(0, s.burn or 0.75)
    local freezeAt: number? = s.freezeAt
    local goneAt = flareAt + 0.12 + fade
    local total = goneAt + burn
    local col2 = ctx.fx.color2
    local f = ctx.factor
    local rich = extrasOn(ctx)
    local rng = Random.new(77)
    local settleAt = miniFor + grow + 0.15

    -- 1. kleine Kuppel (Impact-Frame 1)
    local mini = newPart(Enum.PartType.Ball, Vector3.one * miniR * 2, NOVA_HOT, CFrame.new(feet), 0)
    mini.Material = Enum.Material.SmoothPlastic
    mini.Name = "IFrameDome"
    local mh = Instance.new("Highlight")
    mh.Adornee = mini
    mh.DepthMode = Enum.HighlightDepthMode.Occluded
    mh.FillColor = NOVA_HOT
    mh.FillTransparency = 0
    mh.OutlineColor = NOVA_YELLOW
    mh.OutlineTransparency = 0
    mh.Parent = mini

    -- 2. die grosse Kuppel
    local core = newPart(Enum.PartType.Ball, Vector3.one * 0.4, NOVA_HOT, CFrame.new(feet), 1)
    core.Material = Enum.Material.SmoothPlastic
    core.Name = "NovaDome"
    local hl = Instance.new("Highlight")
    hl.Adornee = core
    hl.DepthMode = Enum.HighlightDepthMode.Occluded
    hl.FillColor = NOVA_HOT
    hl.FillTransparency = 1
    hl.OutlineColor = NOVA_PINK
    hl.OutlineTransparency = 1
    hl.Parent = core
    local aura = newPart(Enum.PartType.Ball, Vector3.one * 0.4, Color3.fromRGB(255, 128, 96), CFrame.new(feet), 1)
    aura.Name = "NovaDomeAura"
    local embers = Instance.new("ParticleEmitter")
    embers.Texture = SPARK_TEX
    embers.Rate = 0
    embers.Shape = Enum.ParticleEmitterShape.Sphere
    embers.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
    embers.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
    embers.Speed = NumberRange.new(5, 13)
    embers.Lifetime = NumberRange.new(0.5, 1.1)
    embers.Acceleration = Vector3.new(0, 5, 0)
    embers.Drag = 1.5
    embers.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0) })
    embers.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, NOVA_HOT),
        ColorSequenceKeypoint.new(0.45, NOVA_YELLOW),
        ColorSequenceKeypoint.new(1, NOVA_RED),
    })
    embers.LightEmission = 0.6
    embers.Parent = core

    -- Flammenbaender (Breitengrade, leicht gekippt), drehen sich verschieden
    -- schnell; je Viertel ein Verlauf zum Rot wie ein Flammenschweif. Test
    -- 25.10.: 7 breite waagerechte Baender sahen aus wie ein Wasserball, ein
    -- kleiner Ring ganz oben stand von der Seite als roter Balken ab.
    local bands: { NovaBand } = {}
    local lats: { number } = if rich then { 9, 22, 35, 48 } else { 14, 38 }
    local bandCols = { NOVA_YELLOW, col2, NOVA_YELLOW:Lerp(col2, 0.5), col2 }
    for i, deg in lats do
        local rg = novaRing(bandCols[(i - 1) % #bandCols + 1], 0, 0.1, 16, NOVA_RED)
        for q = 1, 4 do rg.pattern(q, novaGaps(rng, 0.1)) end
        table.insert(bands, { ring = rg, beta = math.rad(deg), w = rng:NextNumber(0.045, 0.075),
            spin = (if i % 2 == 0 then -1 else 1) * rng:NextNumber(0.9, 2.2), ph = rng:NextNumber(0, TAU),
            tilt = CFrame.Angles(rng:NextNumber(-0.2, 0.2), 0, rng:NextNumber(-0.2, 0.2)) })
    end
    -- dunkle Loecher auf der Oberflaeche
    local holes: { NovaHole } = {}
    for _ = 1, (if rich then (s.holes or 6) else 3) do
        local th = rng:NextNumber(0, TAU)
        local el = rng:NextNumber(0.25, 1.05)
        local p, mesh = ellipsoid(NOVA_HOLE, Vector3.one, PARK, 1, Enum.Material.SmoothPlastic)
        mesh.Scale = Vector3.one
        p.Name = "NovaHole"
        table.insert(holes, { p = p, dir = Vector3.new(math.cos(el) * math.cos(th), math.sin(el), math.cos(el) * math.sin(th)),
            w = rng:NextNumber(0.2, 0.32), h = rng:NextNumber(0.11, 0.19), roll = rng:NextNumber(0, TAU) })
    end
    local skirt = novaFlames(if rich then (s.skirt or 18) else 10, R * 0.2, 5)
    local burnFl = novaFlames(8, 1.1, 9)
    -- Truemmer (Rig, frei gebaut: fixed, g = 1)
    local rubble: { RigPart } = {}
    for _ = 1, scaled(s.chunks or 10, f) do
        local sz = Vector3.new(rng:NextNumber(0.45, 1.0), rng:NextNumber(0.35, 0.8), rng:NextNumber(0.45, 1.0))
        local p = newPart(Enum.PartType.Block, sz, NOVA_ASH, PARK, 1)
        p.Material = Enum.Material.SmoothPlastic
        p.Name = "NovaRubble"
        local a = rng:NextNumber(0, TAU)
        local rel = CFrame.new(math.cos(a) * rng:NextNumber(0.5, 2.2), 0.4, math.sin(a) * rng:NextNumber(0.5, 2.2))
            * CFrame.Angles(rng:NextNumber(0, TAU), rng:NextNumber(0, TAU), 0)
        table.insert(rubble, { p = p, frame = rel, size = sz, delay = 0, tr = 0, g = 1, fixed = true, lt = 1 })
    end
    -- Brandfleck (unter der Kuppel, sichtbar wenn sie vergeht)
    local scorch = newPart(Enum.PartType.Cylinder, Vector3.new(0.05, R * 1.9, R * 1.9), Color3.fromRGB(28, 18, 30),
        CFrame.new(feet + Vector3.new(0, 0.04, 0)) * CFrame.Angles(0, 0, math.rad(90)), 1)
    scorch.Material = Enum.Material.SmoothPlastic
    scorch.Name = "NovaScorch"
    local craterTex = texOf(ctx, "crater")
    local plate: BasePart? = nil
    local decal: Decal? = nil
    if craterTex then
        local pl = newPart(Enum.PartType.Block, Vector3.new(R * 2.3, 0.05, R * 2.3), NOVA_YELLOW, CFrame.new(feet + Vector3.new(0, 0.07, 0)), 1)
        pl.Name = "NovaCrater"
        decal = addDecal(pl, craterTex, Enum.NormalId.Top, NOVA_YELLOW)
        plate = pl
    end
    local veil = novaVeil(ctx)

    local fired: { [string]: boolean } = {}
    local function once(key: string): boolean
        if fired[key] then return false end
        fired[key] = true
        return true
    end
    local pulseDone: { boolean } = {}
    local lastT = -1
    runLoop("firedome", function(tRaw)
        if tRaw >= (if freezeAt then freezeAt + 150 else total) then return true end
        local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
        local dtE = if lastT < 0 then 0 else math.max(0, t - lastT)
        lastT = t
        -- kleine Kuppel weg, die grosse beginnt
        if t >= miniFor and once("big") then
            mini:Destroy()
            ctx.novaT0 = os.clock()
            ctx.novaCenter = feet + Vector3.new(0, R * 0.4, 0)
            ctx.novaRadius = R
            embers:Emit(scaled(40, f))
            rigApply(rubble, CFrame.new(feet), function(_r: RigPart): number return 1 end, 1)
            rigShatter(rubble, feet - Vector3.new(0, 1, 0), 22)
            burstAt(ctx, feet + Vector3.new(0, 1.5, 0), 20, 10, NOVA_ASH, true)
        end
        if t < miniFor then return false end
        local tb = t - miniFor
        -- Groesse: Ueberschwingen, langsames Wachsen, Pulse, Aufflammen
        local S: number
        if tb < grow then
            S = 0.15 + 0.97 * easeOutCubic(tb / grow)
        elseif t < settleAt then
            S = lerpN(1.12, 1.0, easeInOutSine((t - miniFor - grow) / 0.15))
        else
            S = 1 + 0.1 * math.clamp((t - settleAt) / math.max(0.1, flareAt - settleAt), 0, 1)
        end
        local spike = 0
        for i, pt in pulseAt do
            if t >= pt then
                local q = t - pt
                spike = math.max(spike, math.exp(-q * 10) * math.min(1, q / 0.04))
                if not pulseDone[i] then
                    pulseDone[i] = true
                    embers:Emit(scaled(28, f))
                end
            end
        end
        local flareK = if t >= flareAt then easeOutCubic(math.min(1, (t - flareAt) / 0.12)) else 0
        if t >= flareAt and once("flare") then
            embers:Emit(scaled(60, f))
        end
        S = S + 0.08 * spike + 0.14 * flareK
        local alpha = 1 - math.clamp((t - flareAt - 0.1) / fade, 0, 1)
        local Rn = R * S
        if alpha > 0.001 then
            core.Size = Vector3.one * Rn * 2
            aura.Size = Vector3.one * Rn * 2.14
        end
        core.Transparency = if alpha > 0.02 then 1 - alpha else 1
        aura.Transparency = 1 - (1 - 0.9) * alpha * (1 + spike + flareK)
        local hot = math.max(spike, flareK)
        hl.FillColor = NOVA_HOT:Lerp(Color3.new(1, 1, 1), flareK)
        -- Fuellung nur schwach: sie liegt UEBER den Baendern (Beams schreiben
        -- keine Tiefe, F45); Pulse und Aufflammen gleissen ueber die Fuellung
        hl.FillTransparency = 1 - (1 - lerpN(0.82, 0, hot)) * alpha
        hl.OutlineColor = NOVA_PINK:Lerp(Color3.new(1, 1, 1), math.max(spike * 0.6, flareK))
        hl.OutlineTransparency = 1 - alpha
        -- Baender: auf der Oberflaeche, verschwinden im Aufflammen
        local bA = alpha * (1 - flareK) * math.clamp(tb / 0.06, 0, 1)
        for _, bd in bands do
            local rr = Rn * math.cos(bd.beta) * 1.012
            bd.ring.place(CFrame.new(feet) * bd.tilt * CFrame.new(0, Rn * math.sin(bd.beta) * 1.012, 0)
                * CFrame.Angles(0, bd.ph + bd.spin * t, 0), rr, math.max(0.25, bd.w * Rn))
            bd.ring.alpha(bA)
        end
        -- Loecher drehen langsam mit
        local spinCf = CFrame.Angles(0, 0.35 * t, 0)
        local hParts: { BasePart } = table.create(#holes)
        local hCfs: { CFrame } = table.create(#holes)
        for i, ho in holes do
            local d = spinCf:VectorToWorldSpace(ho.dir)
            local pos = feet + d * Rn * 1.006
            ho.p.Size = Vector3.new(ho.w * Rn, ho.h * Rn, 0.06)
            local v = 1 - (1 - 0.08) * bA
            if math.abs(ho.p.Transparency - v) > 0.01 then ho.p.Transparency = v end
            hParts[i] = ho.p
            hCfs[i] = CFrame.lookAt(pos, pos + d, perpOf(d)) * CFrame.Angles(0, 0, ho.roll)
        end
        workspace:BulkMoveTo(hParts, hCfs, Enum.BulkMoveMode.FireCFrameChanged)
        -- Flammenkranz am Fuss
        skirt.place(feet, Rn * 0.97, R * (0.32 + 0.2 * spike) * (1 - 0.5 * flareK), t, alpha * math.clamp(tb / 0.05, 0, 1))
        -- Truemmer fliegen (eingefroren: dt = 0)
        if #rubble > 0 then
            rigFly(rubble, dtE, 1 - math.clamp((tb - 0.6) / 0.4, 0, 1))
        end
        -- Brandfleck und Glut: erst heiss, kuehlt ab, verblasst am Ende
        local cool = math.clamp((t - flareAt) / 1.0, 0, 1)
        local endA = 1 - math.clamp((t - (total - 0.35)) / 0.35, 0, 1)
        scorch.Transparency = 1 - 0.7 * endA
        local dc = decal
        if dc then
            dc.Color3 = NOVA_YELLOW:Lerp(NOVA_RED, math.min(1, cool * 1.6)):Lerp(NOVA_ASH, math.max(0, cool * 1.6 - 0.6))
            dc.Transparency = 1 - endA
        end
        -- Brand: kleine Flammen am Gegner, folgen ihm (Server-Rueckstoss)
        if t >= goneAt - 0.15 and burn > 0 then
            local c = centerOf(ctx.targetModel) or ctx.targetPos
            local tf = c - Vector3.new(0, ctx.targetSize.Y / 2, 0)
            local bk = math.clamp((t - (goneAt - 0.15)) / 0.15, 0, 1) * endA
            -- bis ueber den Kopf (Test 25.10.: 1,5 Studs hohe Flammen gingen
            -- hinter dem Gegner unter)
            burnFl.place(tf, math.max(0.7, ctx.targetSize.X * 0.5), math.max(1.8, ctx.targetSize.Y * 1.1), t, bk)
        end
        -- Besitzer: rosa Schleier bei den Pulsen, Weissblende -> Rosa beim Aufflammen
        if veil then
            local wA = 0
            local wC = Color3.fromRGB(255, 160, 205)
            if t >= flareAt then
                local q = t - flareAt
                if q < 0.36 then
                    wA = math.min(1, q / 0.05)
                    wC = Color3.new(1, 1, 1)
                else
                    local k = math.clamp((q - 0.36) / 0.75, 0, 1)
                    wA = 1 - k
                    wC = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(255, 196, 226), math.min(1, k * 2.2))
                end
            else
                wA = 0.42 * spike
            end
            veil.set(wC, wA)
        end
        return false
    end, function()
        if mini.Parent then mini:Destroy() end
        ctx.novaT0 = nil
        ctx.novaCenter = nil
        ctx.novaRadius = nil
        core:Destroy()
        aura:Destroy()
        for _, bd in bands do bd.ring.destroy() end
        for _, ho in holes do ho.p:Destroy() end
        skirt.destroy()
        burnFl.destroy()
        for _, r in rubble do r.p:Destroy() end
        scorch:Destroy()
        local pl = plate
        if pl then pl:Destroy() end
        if veil then veil.destroy() end
    end)
end

-- novabolt: Echo. Ein kleiner Neutronenstern blitzt am Angreifer auf, schiesst
-- in `fly` s (k^2) in den Gegner (Treffer), dort ploppt eine kleine Feuer-
-- kuppel (Radius `radius`) auf und vergeht in `life` s.
--   at, fly, radius, life, size (Test: freezeAt)
BLOCKS.novabolt = function(ctx, s)
    local fly = math.max(0.05, s.fly or 0.25)
    local R = s.radius or 2.6
    local life = math.max(0.1, s.life or 0.34)
    local size = s.size or 0.7
    local freezeAt: number? = s.freezeAt
    local col = ctx.fx.color
    local col2 = ctx.fx.color2
    local from = ctx.selfPos + ctx.fwd * (ctx.selfSize.Z * 0.5 + 0.4) + Vector3.new(0, 0.2, 0)
    local hitFeet = groundAt(ctx, s.at or "target")
    local to = ctx.targetPos - ctx.fwd * (ctx.targetSize.Z * 0.35)
    twinkle(from, 2.4, PULSAR_WHITE, 0.25)
    local core = newPart(Enum.PartType.Ball, Vector3.one * size, PULSAR_WHITE, CFrame.new(from), 0)
    core.Name = "PulsarBolt"
    local shell = newPart(Enum.PartType.Ball, Vector3.one * size * 1.8, col, CFrame.new(from), 0.15)
    shell.Material = Enum.Material.ForceField
    local a0 = Instance.new("Attachment")
    a0.Position = Vector3.new(0, size * 0.8, 0)
    a0.Parent = shell
    local a1 = Instance.new("Attachment")
    a1.Position = Vector3.new(0, -size * 0.8, 0)
    a1.Parent = shell
    local trail = Instance.new("Trail")
    trail.Attachment0 = a0
    trail.Attachment1 = a1
    trail.Lifetime = 0.2
    trail.FaceCamera = true
    trail.LightEmission = 0.5
    trail.LightInfluence = 0
    trail.Color = ColorSequence.new(PULSAR_WHITE, col2)
    trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
    trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) })
    trail.Parent = shell
    local dome = newPart(Enum.PartType.Ball, Vector3.one * 0.3, NOVA_YELLOW, CFrame.new(hitFeet), 1)
    dome.Material = Enum.Material.SmoothPlastic
    dome.Name = "NovaBoltDome"
    local hl = Instance.new("Highlight")
    hl.Adornee = dome
    hl.DepthMode = Enum.HighlightDepthMode.Occluded
    hl.FillColor = NOVA_HOT
    hl.FillTransparency = 1
    hl.OutlineColor = NOVA_PINK
    hl.OutlineTransparency = 1
    hl.Parent = dome
    local flames = novaFlames(6, 0.8, 13)
    local hit = false
    runLoop("novabolt", function(tRaw)
        if tRaw >= (if freezeAt then freezeAt + 150 else fly + life) then return true end
        local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
        if t < fly then
            local k = t / fly
            local e = k * k
            local p = from:Lerp(to, e) + Vector3.new(0, math.sin(math.pi * k) * 1.2, 0)
            core.CFrame = CFrame.new(p)
            shell.CFrame = CFrame.new(p)
            shell.Color = col:Lerp(col2, e)
            return false
        end
        if not hit then
            hit = true
            core.Transparency = 1
            shell.Transparency = 1
            trail.Enabled = false
            burstAt(ctx, to, 18, 14, col2)
        end
        local q = (t - fly) / life
        local S = if q < 0.25 then 1.12 * easeOutCubic(q / 0.25) else lerpN(1.12, 1.0, math.min(1, (q - 0.25) / 0.2))
        dome.Size = Vector3.one * 2 * R * math.max(0.1, S)
        local a = 1 - math.clamp((q - 0.45) / 0.55, 0, 1)
        dome.Transparency = if a > 0.02 then 1 - a else 1
        hl.FillTransparency = 1 - 0.9 * a
        hl.OutlineTransparency = 1 - a
        flames.place(hitFeet, R * math.max(0.1, S) * 0.95, R * 0.5, t, a)
        return false
    end, function()
        core:Destroy()
        shell:Destroy()
        dome:Destroy()
        flames.destroy()
    end)
end
