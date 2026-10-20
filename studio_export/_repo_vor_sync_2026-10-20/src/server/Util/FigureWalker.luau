--!strict
-- FigureWalker.luau
-- ServerScriptService/Util/FigureWalker.luau
--
-- Einzige Zustaendigkeit:
--   - Ein Model prozedural von einem Fusspunkt zu einem anderen "laufen"
--     lassen — Bewegung plus einfache Lauf-Animation (Huepfen + Vorlehnung),
--     ohne dass dafuer eine echte Skelett-Animation gebraucht wird.
--
-- Die importierten Baerchi-Meshes sind keine gerigten Humanoid-Modelle
-- (siehe BaerchiMesh.luau): es sind lose zusammengesetzte Parts ohne
-- Motor6D-Gelenke, an denen eine klassische Lauf-Animation ansetzen koennte.
-- Eine Animation dafuer zu FORDERN waere Buerokratie um etwas, das es fuer
-- dieses Mesh gar nicht geben kann (dafuer muesste jedes Baerchi-Modell in
-- Studio neu gerigt werden). Stattdessen bewegt dieses Modul das GANZE Model
-- per Heartbeat-Schleife und legt ein Huepfen plus eine leichte Vorlehnung in
-- Laufrichtung darueber — der uebliche Trick fuer nicht gerigte Pet-Figuren
-- in diesem Genre (auch bei "Grow a ..."-artigen Spielen ueblich).
--
-- Der Fusspunkt bleibt waehrend der ganzen Bewegung exakt auf dem Boden: JEDEN
-- Frame wird zuerst gedreht und dann anhand der Bounding-Box neu auf den
-- Fusspunkt (plus Huepf-Offset) gestellt. Das Hinstellen selbst macht
-- FigurePlacement — dieselbe Funktion, die auch PitArenaService benutzt, um
-- seine Kaempfer aufzustellen. Warum das so laufen muss (erst drehen, dann
-- messen) steht im Kopf von FigurePlacement.luau, nicht mehr hier.

local RunService          = game:GetService("RunService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MapConfig       = require(ReplicatedStorage.Config.MapConfig)
local FigurePlacement = require(ServerScriptService.Util.FigurePlacement)

local FigureWalker = {}

-- Die Vorgaben fuer das Huepfen kommen aus MapConfig und stehen bewusst NICHT
-- mehr hier: an ihnen dreht man beim Ausprobieren, und die Begruendung fuer die
-- Werte (wenige hohe Spruenge statt vieler flacher) gehoert neben die Zahl.
-- FigurePlacement bleibt davon unberuehrt — das ist reine Geometrie ohne
-- Geschmacksfrage.
export type WalkOptions = {
	speed       : number,          -- Studs pro Sekunde
	bobHeight   : number?,         -- Studs, Standard MapConfig.WALK_BOB_HEIGHT
	bobPerStud  : number?,         -- Spruenge pro Stud, Standard MapConfig.WALK_BOB_PER_STUD
	leanDegrees : number?,         -- Vorlehnung, Standard MapConfig.WALK_LEAN_DEGREES
	isCancelled : (() -> boolean)?,
}

-- Laeuft von `fromFoot` nach `toFoot` (beide Fusspunkte — es wird angenommen,
-- dass beide auf demselben Niveau liegen, z.B. Plot- oder Plattform-Hoehe;
-- die Y-Koordinate von `fromFoot` gilt fuer die ganze Bewegung). Kehrt erst
-- zurueck wenn die Bewegung fertig ist oder abgebrochen wurde — wer nebenher
-- weiterlaufen will, startet das selbst in einem eigenen task.spawn.
--
-- Endet IMMER exakt auf toFoot, auch nach einem Abbruch ueber isCancelled:
-- ein Model, das mitten in der Luft oder auf halbem Weg haengen bleibt, waere
-- schlimmer als der fehlende letzte Teil der Animation.
function FigureWalker.walk(model: Model, fromFoot: Vector3, toFoot: Vector3, options: WalkOptions)
	local flatFrom = Vector3.new(fromFoot.X, fromFoot.Y, fromFoot.Z)
	local flatTo   = Vector3.new(toFoot.X, fromFoot.Y, toFoot.Z)

	local delta    = flatTo - flatFrom
	local distance = delta.Magnitude

	if distance < 1e-2 then
		FigurePlacement.place(model, flatTo, model:GetPivot().Rotation)
		return
	end

	local direction = delta.Unit
	local facing    = CFrame.lookAt(Vector3.new(), direction)

	local speed       = math.max(options.speed, 1)
	local bobHeight   = options.bobHeight or MapConfig.WALK_BOB_HEIGHT
	local bobPerStud  = math.max(options.bobPerStud or MapConfig.WALK_BOB_PER_STUD, 1e-3)
	local leanRad     = math.rad(options.leanDegrees or MapConfig.WALK_LEAN_DEGREES)
	local isCancelled = options.isCancelled

	local duration = distance / speed
	local elapsed  = 0

	while elapsed < duration do
		if isCancelled and isCancelled() then
			break
		end

		local dt = RunService.Heartbeat:Wait()
		elapsed += dt

		local t        = math.clamp(elapsed / duration, 0, 1)
		local traveled = distance * t

		-- |sin| ist die Flugbahn eines huepfenden Balls: ein sauberer Bogen nach
		-- oben und ein harter Aufsetzpunkt unten. Genau dieser Knick macht den
		-- Unterschied zwischen "huepft" und "schwebt".
		--
		-- Das Argument ist absichtlich `traveled * bobPerStud * pi`, nicht
		-- `* 2 * pi`: |sin| hat die halbe Periode von sin, damit kommt auf
		-- 1 / bobPerStud Studs genau EIN Sprung. bobPerStud ist also woertlich
		-- "Spruenge pro Stud" — vorher stand dort ein Wert, der in Wahrheit die
		-- doppelte Frequenz bedeutete, und genau das war die Zitter-Falle.
		local bob = math.abs(math.sin(traveled * bobPerStud * math.pi)) * bobHeight

		FigurePlacement.place(
			model,
			flatFrom:Lerp(flatTo, t) + Vector3.new(0, bob, 0),
			facing * CFrame.Angles(leanRad, 0, 0)
		)
	end

	FigurePlacement.place(model, flatTo, facing)
end

return FigureWalker
