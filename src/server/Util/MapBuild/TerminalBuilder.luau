--!strict
-- TerminalBuilder.luau
-- ServerScriptService/Util/MapBuild/TerminalBuilder.luau
--
-- Einzige Zustaendigkeit:
--   - Das Tower-Terminal am Stegbeginn bauen (08.10., Paket B2) und seinen
--     Zustand als Attribute an das Model schreiben.
--
-- Gebaut wird EINMAL mit dem Plot, rein aus MapConfig.TOWER_TERMINAL (wie die
-- Gebaeude-Deko). Was der Bildschirm zeigt, steht nur in Attributen; den Text
-- in der Sprache des Betrachters, die Lampenfarbe, das Blinken, das "!" und
-- den Prompt macht der Client (Controllers/TerminalController). Kein Neubau
-- bei einer Aenderung, keine Emitter, keine Lichter.
--
-- Attribute am Model "TowerTerminal":
--   State     "locked" | "ready" | "normal" (TowerConfig.terminalState)
--   Tower     gewaehlter Tower (Id)
--   Record    Rekord im gewaehlten Tower
--   NextTower Tower, der als naechstes aufgeht ("" = keiner)
--   Progress  Rekord im Vorgaenger dieses Towers (Fortschritt "12/30")
--   Needed    noetige Stage im Vorgaenger
--
-- Teil von MapService: nur MapService benutzt dieses Modul. Es aendert keine
-- Spielerdaten.

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MapConfig = require(ReplicatedStorage.Config.MapConfig)
local MapParts  = require(ServerScriptService.Util.MapBuild.MapParts)

local TerminalBuilder = {}

TerminalBuilder.MODEL_NAME = "TowerTerminal"

export type TerminalView = {
	state     : string,
	tower     : string,
	record    : number,
	nextTower : string,
	progress  : number,
	needed    : number,
}

-- Boden-Ursprung des Terminals (plot-lokal versetzt und gedreht).
function TerminalBuilder.origin(slot: number): CFrame
	local cfg = MapConfig.TOWER_TERMINAL
	return MapParts.plotCFrame(slot)
		* CFrame.new(cfg.offset)
		* CFrame.Angles(0, math.rad(cfg.yaw), 0)
end

function TerminalBuilder.writeState(model: Model, view: TerminalView)
	model:SetAttribute("State", view.state)
	model:SetAttribute("Tower", view.tower)
	model:SetAttribute("Record", view.record)
	model:SetAttribute("NextTower", view.nextTower)
	model:SetAttribute("Progress", view.progress)
	model:SetAttribute("Needed", view.needed)
end

function TerminalBuilder.build(plotModel: Model, slot: number, view: TerminalView?): Model
	local old = plotModel:FindFirstChild(TerminalBuilder.MODEL_NAME)
	if old then old:Destroy() end

	local model = Instance.new("Model")
	model.Name = TerminalBuilder.MODEL_NAME
	local origin = TerminalBuilder.origin(slot)
	MapParts.buildDecor(model, origin, MapConfig.TOWER_TERMINAL.pieces)
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			part.CastShadow = part.Name == "Kopf" or part.Name == "Saeule" or part.Name == "Sockel"
		end
	end
	-- Pivot auf den Boden-Ursprung: der Client findet so "vorne" und "oben".
	model.WorldPivot = origin
	if view then
		TerminalBuilder.writeState(model, view)
	else
		TerminalBuilder.writeState(model, { state = "locked", tower = "I", record = 0, nextTower = "II", progress = 0, needed = 0 })
	end
	model.Parent = plotModel
	return model
end

return TerminalBuilder
