--!strict
-- FigureFX.luau
-- ServerScriptService/Util/FigureFX.luau
--
-- Einzige Zustaendigkeit:
--   - Kleine, rein kosmetische Bewegungen an einem Model abspielen:
--     Ausfallschritt, Treffer-Blitz, Umkippen, Vorbeugen, Ruhe-Atmen.
--
-- Dieses Modul kennt WEDER Spielerdaten NOCH Remotes NOCH Gebaeude oder
-- Kaempfe — nur Model, CFrame und Zahlen. Es entscheidet WIE eine Bewegung
-- aussieht; WANN sie passiert, entscheidet der aufrufende Service
-- (PitArenaService, BaerchiAutopilotService, MapService). Genau diese Trennung
-- ist der Grund, warum es eine eigene Datei ist und nicht in PitArenaService
-- steht.
--
-- ============================================================
-- KEIN RIG, KEIN ANIMATOR
-- ============================================================
-- Die importierten Baerchi-Meshes haben keine Motor6D-Gelenke (siehe
-- BaerchiMesh.luau / FigureWalker.luau) — eine klassische Skelett-Animation
-- kann daran nicht ansetzen. Alles hier bewegt deshalb das GANZE Model per
-- PivotTo, genau wie FigureWalker. Der Fusspunkt bleibt dabei ueberall auf dem
-- Boden: entweder ueber FigurePlacement (Ausfallschritt) oder ueber eine
-- Drehung um eine Achse, die DURCH den Fusspunkt geht (Vorbeugen, Umkippen).
-- Ein Motor6D oder AnimationController wird hier bewusst NICHT eingefuehrt.
--
-- ============================================================
-- WER WELCHE ZAHL BESTIMMT
-- ============================================================
-- Dauer, Distanz und Farbe kommen als Argument herein — die stehen in
-- MapConfig, weil sie Balance/Optik des Spiels sind. Was hier unten als
-- Konstante steht, ist die FORM der Bewegung (wie hoch der Hopser im
-- Verhaeltnis zur Ausfall-Distanz ist, wie lange die Figur beim Fressen unten
-- bleibt). Die gehoert zur Bewegung selbst, nicht zum Spiel — genauso wie
-- FigureWalker seine Huepf-Vorgaben selbst mitbringt.

local RunService          = game:GetService("RunService")
local TweenService        = game:GetService("TweenService")
local Debris              = game:GetService("Debris")
local ServerScriptService = game:GetService("ServerScriptService")

local FigurePlacement = require(ServerScriptService.Util.FigurePlacement)

local FigureFX = {}

--------------------------------------------------------------------------------
-- Form-Konstanten (siehe Kopf: das WIE, nicht das WIEVIEL)
--------------------------------------------------------------------------------

-- Huepf-Hoehe des Ausfallschritts als Anteil seiner Distanz. Ein Ausfall ohne
-- jede Hoehe sieht aus wie Schlittern.
local LUNGE_HOP_SHARE = 0.35

-- Wie weit eine besiegte Figur nach HINTEN wegkippt, und wie weit sie dabei
-- absackt (als Anteil ihrer eigenen Hoehe, damit es bei jedem Mesh passt).
local COLLAPSE_DEGREES    = 74
local COLLAPSE_SINK_SHARE = 0.18

-- Anteil der Fress-Dauer, den die Figur unten bleibt. Der Rest teilt sich auf
-- Runterbeugen und Wiederaufrichten auf.
local LEAN_HOLD_SHARE = 0.40

-- Deckkraft des Treffer-Blitzes. Voll deckend waere ein Farbklecks statt eines
-- Aufleuchtens.
local FLASH_FILL_TRANSPARENCY = 0.45

-- Ruhe-Atmen: Vorgaben, falls der Aufrufer keine mitgibt.
local IDLE_DEFAULT_HEIGHT = 0.16   -- Studs
local IDLE_DEFAULT_RATE   = 1.5    -- Schwingungen pro Sekunde

-- Feier-Momente (celebrate/burstAt) — siehe Abschnitt weiter unten.
-- Die Zahlen hier sind FORM (wie ein Partikel-Stoss aussieht), nicht Balance
-- — deshalb hier und nicht in MapConfig, genau wie beim Rest dieser Datei.
local CELEBRATE_PARTICLE_COUNT   = 24
local CELEBRATE_HOP_HEIGHT_SHARE = 0.45   -- Anteil der Modellhoehe
local CELEBRATE_FLASH_SECONDS    = 0.35
local CELEBRATE_DEFAULT_SECONDS  = 0.6

-- Kuerzeste sinnvolle Dauer — schuetzt vor Division durch Null bei 0.
local MIN_SECONDS = 0.05

local EPSILON = 1e-3

--------------------------------------------------------------------------------
-- Interne Hilfen
--------------------------------------------------------------------------------

-- Fusspunkt eines Models: Mitte der Unterkante seiner Bounding-Box. Dieselbe
-- Groesse, mit der FigurePlacement und FigureWalker rechnen.
local function footOf(model: Model): Vector3
	local box, size = model:GetBoundingBox()
	return Vector3.new(box.Position.X, box.Position.Y - size.Y * 0.5, box.Position.Z)
end

local function heightOf(model: Model): number
	local _, size = model:GetBoundingBox()
	return size.Y
end

-- Laeuft `seconds` lang und ruft `step(t)` jeden Frame mit t von 0 bis 1.
-- Bricht ab, sobald das Model aus der Welt verschwindet (Plot neu gebaut,
-- Gegner weggeraeumt, Spieler weg) — dieselbe defensive Pruefung, die auch
-- FigureWalker und PitArenaService machen.
--
-- Gibt zurueck, ob die Bewegung ganz durchgelaufen ist.
local function animate(model: Model, seconds: number, step: (t: number) -> ()): boolean
	local duration = math.max(seconds, MIN_SECONDS)
	local elapsed  = 0

	while elapsed < duration do
		local dt = RunService.Heartbeat:Wait()
		elapsed += dt

		if model.Parent == nil then
			return false
		end

		step(math.clamp(elapsed / duration, 0, 1))
	end

	return true
end

-- Die waagerechte Achse, um die eine Figur nach vorne oder hinten kippt:
-- quer zu ihrer Blickrichtung.
local function tiltAxis(pivot: CFrame): Vector3
	local right = Vector3.new(pivot.RightVector.X, 0, pivot.RightVector.Z)
	if right.Magnitude < EPSILON then
		return Vector3.xAxis
	end
	return right.Unit
end

-- Kippt `basePivot` um `radians` um eine Achse, die DURCH `foot` geht — die
-- Fuesse bleiben also stehen, nur der Koerper neigt sich. Zusaetzlich sackt
-- die Figur um `sink` Studs ab.
--
-- Vorzeichen: positive Radiant kippen nach HINTEN (Rechte-Hand-Regel um den
-- RightVector schwenkt den UpVector Richtung +Z, und Blickrichtung ist -Z).
-- Wer nach vorne will, uebergibt einen negativen Wert.
local function tilted(basePivot: CFrame, foot: Vector3, radians: number, sink: number): CFrame
	local hinge = CFrame.new(foot)
	local turn  = CFrame.fromAxisAngle(tiltAxis(basePivot), radians)

	return (hinge * turn * hinge:Inverse() * basePivot) + Vector3.new(0, -sink, 0)
end

--------------------------------------------------------------------------------
-- Ruhe-Atmen: EIN Loop fuer ALLE Figuren
--------------------------------------------------------------------------------
--
-- Pro Figur eine eigene RunService-Verbindung waere bei 8 Spielern plus deren
-- Arena-Gegnern ein gutes Dutzend paralleler Schleifen fuer eine Bewegung, die
-- sich in einem einzigen Callback genauso rechnen laesst. Deshalb: eine
-- Registry, ein Heartbeat.
--
-- Die Verbindung entsteht erst mit der ersten Figur und loest sich wieder,
-- sobald keine mehr registriert ist — ein leerer Server laesst also gar nichts
-- mitlaufen.

export type IdleOptions = {
	height : number?,   -- Studs Hub, Standard IDLE_DEFAULT_HEIGHT
	rate   : number?,   -- Schwingungen pro Sekunde, Standard IDLE_DEFAULT_RATE
}

type IdleEntry = {
	basePivot : CFrame,        -- Ruhelage, auf die jederzeit zurueckgesetzt wird
	options   : IdleOptions,   -- gemerkt, um nach einer Bewegung gleich weiterzumachen
	height    : number,
	rate      : number,
	phase     : number,        -- damit nicht alle Figuren im Gleichschritt wippen
}

local _idle: { [Model]: IdleEntry } = {}
local _idleConnection: RBXScriptConnection? = nil
local _idleClock = 0

local function stepIdle(dt: number)
	_idleClock += dt

	for model, entry in _idle do
		if model.Parent == nil then
			-- Figur ist aus der Welt verschwunden (Plot neu gebaut, Gegner
			-- weggeraeumt). Kein Aufrufer muss daran denken, sich abzumelden.
			_idle[model] = nil
			continue
		end

		-- (1 - cos) laeuft von 0 sanft nach oben und zurueck auf 0 — die Figur
		-- geht also nie UNTER ihre Ruhelage und damit nie in den Boden.
		local swing = (1 - math.cos(_idleClock * entry.rate * math.pi * 2 + entry.phase)) * 0.5
		model:PivotTo(entry.basePivot + Vector3.new(0, swing * entry.height, 0))
	end

	if next(_idle) == nil and _idleConnection then
		_idleConnection:Disconnect()
		_idleConnection = nil
	end
end

local function ensureIdleLoop()
	if _idleConnection then return end
	_idleConnection = RunService.Heartbeat:Connect(stepIdle)
end

-- Meldet eine STEHENDE Figur zum Ruhe-Atmen an und gibt die Stopp-Funktion
-- zurueck. Wer die Figur selbst bewegen will, muss vorher abmelden — sonst
-- ueberschreiben sich Idle-Loop und Bewegung gegenseitig.
--
-- Nochmal fuer dieselbe Figur aufgerufen: die alte Anmeldung wird sauber
-- beendet (Ruhelage wiederhergestellt) und die aktuelle Lage als neue Ruhelage
-- genommen. Ohne das wuerde sich der Hub bei jedem Neuanmelden aufaddieren.
function FigureFX.idleBob(model: Model, options: IdleOptions?): () -> ()
	FigureFX.stopIdle(model)

	local opts: IdleOptions = options or {}

	_idle[model] = {
		basePivot = model:GetPivot(),
		options   = opts,
		height    = opts.height or IDLE_DEFAULT_HEIGHT,
		rate      = opts.rate or IDLE_DEFAULT_RATE,
		phase     = math.random() * math.pi * 2,
	}

	ensureIdleLoop()

	return function()
		FigureFX.stopIdle(model)
	end
end

-- Meldet eine Figur ab und stellt ihre Ruhelage wieder her. Ohne das
-- Zuruecksetzen bliebe sie um den halben Hub in der Luft stehen — und genau
-- dieser Versatz wuerde in PitArenaService._home als "Heimatposition"
-- gespeichert.
--
-- Fuer eine nicht angemeldete Figur passiert nichts.
function FigureFX.stopIdle(model: Model)
	local entry = _idle[model]
	if not entry then return end

	_idle[model] = nil

	if model.Parent ~= nil then
		model:PivotTo(entry.basePivot)
	end
end

-- Nimmt einer Figur das Ruhe-Atmen fuer die Dauer einer eigenen Bewegung weg.
-- Gibt eine Funktion zurueck, die es an der DANN aktuellen Stelle wieder
-- aufnimmt — oder nil, wenn die Figur gar nicht geatmet hat.
local function takeOver(model: Model): (() -> ())?
	local entry = _idle[model]
	if not entry then return nil end

	FigureFX.stopIdle(model)

	return function()
		if model.Parent ~= nil then
			FigureFX.idleBob(model, entry.options)
		end
	end
end

--------------------------------------------------------------------------------
-- Kampf- und Fress-Bausteine
--------------------------------------------------------------------------------

-- Kurzer Ausfallschritt in Richtung `towardPosition` und zurueck: die Figur
-- setzt nach vorne, hebt dabei leicht ab und landet wieder exakt auf ihrem
-- Ausgangs-Fusspunkt. Die Ausrichtung bleibt unveraendert — sie schaut den
-- Gegner ja schon an.
--
-- Blockiert bis die Bewegung durch ist (wie FigureWalker.walk), damit der
-- Aufrufer die Reihenfolge im Kampf bestimmen kann.
function FigureFX.attackLunge(model: Model, towardPosition: Vector3, distance: number, duration: number)
	local resume = takeOver(model)

	local facing = model:GetPivot().Rotation
	local foot   = footOf(model)

	local flat  = Vector3.new(towardPosition.X, foot.Y, towardPosition.Z)
	local delta = flat - foot

	-- Steht der Gegner praktisch auf demselben Punkt, gibt es keine Richtung —
	-- dann bleibt der Ausfall aus, statt in eine zufaellige Richtung zu gehen.
	if delta.Magnitude > EPSILON then
		local direction = delta.Unit
		local hop       = distance * LUNGE_HOP_SHARE

		animate(model, duration, function(t)
			-- sin(pi*t): 0 → 1 → 0, also hin und wieder zurueck in einem Zug.
			local swing = math.sin(t * math.pi)
			FigurePlacement.place(
				model,
				foot + direction * (distance * swing) + Vector3.new(0, hop * swing, 0),
				facing
			)
		end)

		-- Immer sauber auf dem Ausgangspunkt enden, auch nach einem Abbruch.
		if model.Parent ~= nil then
			FigurePlacement.place(model, foot, facing)
		end
	end

	if resume then resume() end
end

-- Kurzes Aufleuchten als Treffer-Rueckmeldung. Kehrt sofort zurueck; das
-- Ausblenden laeuft nebenher.
--
-- Bewusst ein Highlight statt eines Farbpulses auf allen BaseParts: die
-- eigenen Farben und Transparenzen der Figur sind bereits belegt (Rarity-
-- Einfaerbung in BaerchiMesh, Erschoepfungs-Transparenz in MapService, die
-- Ausgangswerte liegen als Attribute an den Parts). Ein Highlight legt sich
-- darueber, ohne einen dieser Werte anzufassen — es kann also auch nichts
-- falsch wiederherstellen, wenn zwei Treffer kurz hintereinander kommen.
--
-- Occluded statt AlwaysOnTop: sonst leuchtete der Treffer quer ueber die
-- Plattform durch die Landschaft hindurch.
function FigureFX.hitFlash(model: Model, color: Color3, duration: number)
	local seconds = math.max(duration, MIN_SECONDS)

	local previous = model:FindFirstChild("HitFlash")
	if previous then
		previous:Destroy()
	end

	local highlight = Instance.new("Highlight")
	highlight.Name                = "HitFlash"
	highlight.FillColor           = color
	highlight.FillTransparency    = FLASH_FILL_TRANSPARENCY
	highlight.OutlineTransparency = 1
	highlight.DepthMode           = Enum.HighlightDepthMode.Occluded
	highlight.Adornee             = model
	highlight.Parent              = model

	TweenService:Create(
		highlight,
		TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ FillTransparency = 1 }
	):Play()

	task.delay(seconds, function()
		if highlight.Parent ~= nil then
			highlight:Destroy()
		end
	end)
end

-- Die Figur kippt nach hinten weg und sackt dabei etwas ab, statt einfach zu
-- verschwinden. Gedacht fuer den Moment VOR dem Aufraeumen — das Entfernen
-- selbst bleibt Sache des Aufrufers.
--
-- Meldet die Figur vom Ruhe-Atmen ab und nimmt es bewusst NICHT wieder auf:
-- eine umgekippte Figur soll liegen bleiben, nicht weiteratmen.
--
-- Blockiert bis die Bewegung durch ist.
function FigureFX.defeatCollapse(model: Model, duration: number)
	FigureFX.stopIdle(model)

	local basePivot = model:GetPivot()
	local foot      = footOf(model)
	local radians   = math.rad(COLLAPSE_DEGREES)
	local sink      = heightOf(model) * COLLAPSE_SINK_SHARE

	animate(model, duration, function(t)
		-- Quadratisch statt linear: erst langsam wegkippen, dann fallen.
		local fall = t * t
		model:PivotTo(tilted(basePivot, foot, radians * fall, sink * fall))
	end)
end

-- Die Figur beugt sich nach vorne, bleibt kurz unten und richtet sich wieder
-- auf — die "ich fresse gerade"-Bewegung am Honig-Teich.
--
-- `duration` ist die GESAMTE Dauer inklusive Verharren, damit der Aufrufer
-- einfach seine bisherige Wartezeit durchreichen kann, statt sie aufzuteilen.
-- Blockiert genau so lange.
function FigureFX.leanForward(model: Model, degrees: number, duration: number)
	local resume = takeOver(model)

	local basePivot = model:GetPivot()
	local foot      = footOf(model)

	-- Negativ = nach vorne (siehe tilted).
	local radians = -math.rad(degrees)
	local move    = (1 - LEAN_HOLD_SHARE) * 0.5   -- Anteil fuer Runter bzw. Hoch

	animate(model, duration, function(t)
		local amount: number
		if t < move then
			amount = t / move                      -- runterbeugen
		elseif t < move + LEAN_HOLD_SHARE then
			amount = 1                             -- unten bleiben
		else
			amount = (1 - t) / move                -- wieder aufrichten
		end

		model:PivotTo(tilted(basePivot, foot, radians * math.clamp(amount, 0, 1), 0))
	end)

	-- Sauber aufgerichtet enden, auch nach einem Abbruch.
	if model.Parent ~= nil then
		model:PivotTo(basePivot)
	end

	if resume then resume() end
end

--------------------------------------------------------------------------------
-- Feier-Momente: Partikel-Stoss + Huepfer + Aufleuchten
--------------------------------------------------------------------------------
-- Fuer Ereignisse, die vorher nur als Toast-Text sichtbar waren (Level-Up,
-- Promotion, Rebirth, Ei einsammeln) — siehe
-- DESIGN_VORSCHLAG_TRENDANALYSE_2026-09-11.md, Abschnitt 4. WICHTIG: das
-- passiert in der geteilten Welt, alle 8 Spieler sehen es mit, nicht nur der
-- Besitzer — genau das macht den Unterschied zu einem reinen UI-Toast.

-- Ein einmaliger Partikel-Stoss an einer Attachment/BasePart. Feuert sofort
-- `count` Partikel und raeumt sich selbst ab (Debris) — kein Dauer-Emitter,
-- der irgendwo vergessen werden koennte.
local function burstParticles(parent: Instance, color: Color3, count: number)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture      = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color        = ColorSequence.new(color)
	emitter.Size          = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency  = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime      = NumberRange.new(0.5, 0.9)
	emitter.Speed         = NumberRange.new(6, 12)
	emitter.SpreadAngle   = Vector2.new(180, 180)
	emitter.Rate          = 0   -- kein Dauerstrom, nur der Emit()-Stoss unten
	emitter.Parent        = parent

	emitter:Emit(count)

	Debris:AddItem(emitter, 1.2)
end

-- Feier-Moment an einer FIGUR: ein kurzer Freuden-Huepfer (rein vertikal,
-- Fusspunkt bleibt stehen), ein Partikel-Stoss in `color`, und ein kurzes
-- Aufleuchten (wiederverwendet hitFlash — dieselbe Technik, andere Bedeutung).
--
-- Blockiert NICHT: laeuft als eigene Coroutine, damit der aufrufende Service
-- (der gerade PlayerService.markDirty/saveNow aufrufen will) nicht auf eine
-- Zierbewegung warten muss.
function FigureFX.celebrate(model: Model, color: Color3, duration: number?)
	local seconds = math.max(duration or CELEBRATE_DEFAULT_SECONDS, MIN_SECONDS)

	local anchor = (model.PrimaryPart :: BasePart?) or (model:FindFirstChildWhichIsA("BasePart", true) :: BasePart?)
	if anchor then
		local attachment = Instance.new("Attachment")
		attachment.Name   = "CelebrateBurst"
		attachment.Parent = anchor

		burstParticles(attachment, color, CELEBRATE_PARTICLE_COUNT)
		Debris:AddItem(attachment, 1.3)
	end

	FigureFX.hitFlash(model, color, CELEBRATE_FLASH_SECONDS)

	task.spawn(function()
		local resume = takeOver(model)

		local basePivot = model:GetPivot()
		local hop        = heightOf(model) * CELEBRATE_HOP_HEIGHT_SHARE

		animate(model, seconds, function(t)
			-- sin(pi*t): hoch und wieder runter in einem Zug, wie ein einzelner
			-- Freudensprung — dieselbe Kurve wie beim Ausfallschritt.
			local swing = math.sin(t * math.pi)
			model:PivotTo(basePivot + Vector3.new(0, hop * swing, 0))
		end)

		if model.Parent ~= nil then
			model:PivotTo(basePivot)
		end

		if resume then resume() end
	end)
end

-- Feier-Moment an einer FESTEN WELTPOSITION, ohne Model — fuer Momente wie
-- das Einsammeln eines Eis, wo es keine Figur gibt, an die der Effekt haengen
-- koennte. Baut einen unsichtbaren, nicht-kollidierenden Anker-Part, feuert
-- den Partikel-Stoss, und raeumt beides selbst wieder ab.
function FigureFX.burstAt(position: Vector3, color: Color3, parent: Instance, count: number?)
	local anchor = Instance.new("Part")
	anchor.Name         = "FXAnchor"
	anchor.Anchored     = true
	anchor.CanCollide   = false
	anchor.CanTouch     = false
	anchor.CanQuery     = false
	anchor.Transparency = 1
	anchor.Size         = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame       = CFrame.new(position)
	anchor.Parent       = parent

	burstParticles(anchor, color, count or CELEBRATE_PARTICLE_COUNT)

	Debris:AddItem(anchor, 1.3)
end

return FigureFX
