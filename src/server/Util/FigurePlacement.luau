--!strict
-- FigurePlacement.luau
-- ServerScriptService/Util/FigurePlacement.luau
--
-- Einzige Zustaendigkeit:
--   - Ein Model so hinstellen, dass die Unterkante seiner Bounding-Box exakt
--     auf einem Fusspunkt liegt — in einer vorgegebenen Blickrichtung.
--
-- Warum es diese Datei gibt:
-- Genau das stand vorher zweimal fast identisch im Projekt — als
-- FigureWalker.placeFoot (laeuft jeden Frame waehrend einer Bewegung) und als
-- PitArenaService.placeModel (stellt die Kaempfer in der Arena auf). Beide
-- taten dasselbe und unterschieden sich nur darin, WORAUF sie ausrichten:
-- eine fertige facing-CFrame gegenueber "schau zu diesem Punkt". Hier steht
-- jetzt die eine Implementierung; das "schau zu X" ist eine duenne Schicht
-- darueber (placeLookingAt).
--
-- Eigenes Util statt einer Funktion in FigureWalker: Hinstellen ist keine
-- Lauf-Animation. PitArenaService stellt Gegner auf, die nie einen Schritt
-- machen, und muesste sonst einen "Walker" requiren, nur um ein Model
-- hinzustellen.
--
-- ============================================================
-- ZWEI SCHRITTE — UND DIE REIHENFOLGE IST WICHTIG
-- ============================================================
-- Erst drehen, dann messen und verschieben. Andersherum wuerde die Drehung das
-- Model wieder von seinem Standpunkt wegschieben, weil sich die
-- achsenparallele Bounding-Box beim Drehen aendert. Aus demselben Grund wird
-- JEDES Mal neu gemessen statt den Pivot einmalig zu verschieben: bei jeder
-- neuen Drehung laege eine gemerkte Verschiebung leicht daneben.
--
-- Die Ausrichtung wird ABSOLUT gesetzt, nicht auf die bestehende
-- draufgerechnet. Wer die aktuelle Drehung behalten will, uebergibt
-- `model:GetPivot().Rotation`. Das setzt voraus, dass der Pivot des
-- importierten Mesh selbst ungedreht ist — waere er das nicht, staenden schon
-- die Figuren auf dem Plot schief.

local FigurePlacement = {}

-- Ab welchem Abstand ein Blickziel ueberhaupt eine Richtung ergibt. Darunter
-- waere CFrame.lookAt nicht definiert (Ziel == Standpunkt).
local LOOK_EPSILON = 1e-3

-- Dreht `model` auf die Drehung von `facing` und stellt es danach so hin, dass
-- die Unterkante seiner Bounding-Box auf `footPos` liegt.
function FigurePlacement.place(model: Model, footPos: Vector3, facing: CFrame)
	model:PivotTo(CFrame.new(model:GetPivot().Position) * facing.Rotation)

	local boxCFrame, size = model:GetBoundingBox()
	local bottomCenter = Vector3.new(
		boxCFrame.Position.X,
		boxCFrame.Position.Y - size.Y * 0.5,
		boxCFrame.Position.Z
	)

	model:PivotTo(model:GetPivot() + (footPos - bottomCenter))
end

-- Wie place(), aber die Blickrichtung ergibt sich aus einem Zielpunkt: das
-- Model schaut von `footPos` zu `lookTarget`, nur um die senkrechte Achse
-- (die Hoehe des Ziels wird bewusst ignoriert — sonst wuerde die Figur sich
-- nach vorne oder hinten neigen).
--
-- Liegt das Ziel praktisch auf dem Fusspunkt, bleibt die aktuelle Drehung
-- stehen, statt sie auf eine undefinierte Richtung zu setzen.
function FigurePlacement.placeLookingAt(model: Model, footPos: Vector3, lookTarget: Vector3)
	local flatTarget = Vector3.new(lookTarget.X, footPos.Y, lookTarget.Z)

	local facing = if (flatTarget - footPos).Magnitude > LOOK_EPSILON
		then CFrame.lookAt(footPos, flatTarget)
		else model:GetPivot()

	FigurePlacement.place(model, footPos, facing)
end

return FigurePlacement
