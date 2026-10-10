--!strict
-- IslandStage.luau
-- ReplicatedStorage/Modules/IslandStage.luau
--
-- Einzige Zustaendigkeit:
--   - Aus dem Fortschritt eines Spielers die Stufe seiner Insel-Deko
--     berechnen (Paket D, "Welt aufwerten"): 1 = Start, 2 = Blumen,
--     3 = + Pilze, 4 = + Bienenhaus und leuchtender Bernstein-Stein
--
-- Reine Rechnung, keine Instanzen. Der Server (PlotDisplayService) schreibt
-- das Ergebnis als Attribut "IslandStage" an das Plot-Model, der Client
-- (PlotLifeController) baut daraus die Deko. Grundlage ist dasselbe, was
-- PlotDisplayService schon fuer den Tower-Turm kennt (Tower-Rekorde), dazu
-- die Rebirth-Zahl — es zaehlt, was weiter ist.

local Config = script.Parent.Parent.Config
local TowerConfig   = require(Config.TowerConfig)
local WorldFXConfig = require(Config.WorldFXConfig)

local IslandStage = {}

IslandStage.MAX = 4

-- Wie viele Tower (I, II, III, …) vollstaendig geschafft sind.
function IslandStage.towersCleared(records: { [string]: number }?): number
	local cleared = 0
	for _, def in TowerConfig.TOWERS do
		if def.id ~= "Endless" then
			local record = if records then records[def.id] or 0 else 0
			if record >= def.stages then
				cleared += 1
			else
				break   -- Tower bauen aufeinander auf
			end
		end
	end
	return cleared
end

-- Stufe 1..MAX aus Tower-Rekorden und Rebirth-Zahl.
function IslandStage.compute(records: { [string]: number }?, rebirths: number): number
	local cfg = WorldFXConfig.ISLAND_STAGE
	local stage = 1
	local cleared = IslandStage.towersCleared(records)
	for s = 2, IslandStage.MAX do
		if cleared >= cfg.TOWERS_FOR[s] or rebirths >= cfg.REBIRTHS_FOR[s] then
			stage = s
		end
	end
	return stage
end

return IslandStage
