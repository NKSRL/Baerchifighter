--!strict
-- PitBrawlService.luau
-- ServerScriptService/Services/PitBrawlService.luau
--
-- Einzige Zustaendigkeit:
--   - Kampf um die Mitte (Sammel-Update 05.10., Paket 5.2): waehrend eines
--     Events stossen freie Event-Baerchis Spieler-Charaktere, die KEIN
--     eigenes Baerchi im Event haben und ihnen im Pit zu nahe kommen.
--
-- "Erst kaempfen die Baerchis gegenseitig, dann greifen sie den Spieler an,
-- wenn kein Baerchi da ist. Damit kaempfen alle um die Mitte."
--
-- Regeln (Annahmen, Abschnitt 11.10, Zahlen in EventConfig.PIT_BRAWL):
--   * Nur waehrend eines laufenden Events, nur im Pit-Radius.
--   * Wer selbst ein Baerchi am Event hat, wird nie gestossen.
--   * Ein Baerchi, das gerade laeuft/kaempft (busy), greift nicht an — die
--     Duelle der Handler gehen vor.
--   * Kein Festhalten: Abklingzeit je Spieler und je Baerchi.
--   * Ein Stoss = Rueckstoss + kurze Verlangsamung (EventHazardHit wie beim
--     Boss) + kurze Waben-Pause (CombService.pausePickup). Kein Schaden.
--
-- Der Server entscheidet, der Client fuehrt den Stoss an seinem eigenen
-- Charakter aus. EIN Takt fuer alle (kein Thread pro Baerchi). Bei einem
-- Spieler allein passiert nichts (es gibt kein gegnerisches Baerchi).

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types        = require(ReplicatedStorage.Network.Types)
local Remotes      = require(ReplicatedStorage.Network.Remotes)
local EventConfig  = require(ReplicatedStorage.Config.EventConfig)
local FeatureFlags = require(ReplicatedStorage.Config.FeatureFlags)

local EventService              = require(ServerScriptService.Services.EventService)
local EventParticipationService = require(ServerScriptService.Services.EventParticipationService)
local MapService                = require(ServerScriptService.Services.MapService)
local CombService               = require(ServerScriptService.Services.CombService)
local FigureFX                  = require(ServerScriptService.Util.FigureFX)
local FigurePlacement           = require(ServerScriptService.Util.FigurePlacement)

local PitBrawlService = {}

local _playerCool: { [Player]: number } = {}
local _figureCool: { [Model]: number } = {}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function tick()
	if not EventService.getActive() then return end
	local cfg = EventConfig.PIT_BRAWL
	local participants = EventParticipationService.getParticipants()
	if #participants == 0 then return end

	local center = MapService.getEventPitPosition()
	local radius = MapService.getEventPitRadius()
	local now = os.clock()

	for _, player in Players:GetPlayers() do
		if EventParticipationService.isPresent(player) then continue end
		if now < (_playerCool[player] or 0) then continue end
		local character = player.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if not (root and root:IsA("BasePart")) then continue end
		if flat(root.Position - center).Magnitude > radius then continue end

		-- naechstes freies, fremdes Baerchi in Reichweite
		local best: { player: Player, figure: Model, busy: boolean }? = nil
		local bestDist = cfg.REACH
		for _, part in participants do
			if part.player ~= player and not part.busy and now >= (_figureCool[part.figure] or 0) then
				local foot = FigurePlacement.footOf(part.figure)
				local dist = flat(root.Position - foot).Magnitude
				if dist <= bestDist then
					best, bestDist = part, dist
				end
			end
		end
		if not best then continue end

		local foot = FigurePlacement.footOf(best.figure)
		local away = flat(root.Position - foot)
		local dir = if away.Magnitude > 0.1 then away.Unit else Vector3.new(1, 0, 0)

		_playerCool[player] = now + cfg.PLAYER_COOLDOWN
		_figureCool[best.figure] = now + cfg.BAERCHI_COOLDOWN

		pcall(FigureFX.attackLunge, best.figure, root.Position, cfg.LUNGE_DISTANCE, cfg.LUNGE_SECONDS)
		local hit: Types.HazardHit = {
			push        = dir * cfg.KNOCKBACK_SPEED,
			slowFactor  = cfg.SLOW_FACTOR,
			slowSeconds = cfg.SLOW_SECONDS,
			source      = "brawl",
		}
		Remotes.EventHazardHit:FireClient(player, hit)
		CombService.pausePickup(player, cfg.PICKUP_PAUSE_SECONDS)
	end
end

function PitBrawlService.init()
	Players.PlayerRemoving:Connect(function(player)
		_playerCool[player] = nil
	end)
end

function PitBrawlService.start()
	if not FeatureFlags.isOn("PIT_BRAWL") then return end
	task.spawn(function()
		while true do
			task.wait(EventConfig.PIT_BRAWL.TICK_SECONDS)
			local ok, err = pcall(tick)
			if not ok then
				warn("[PitBrawlService] Takt fehlgeschlagen:", err)
			end
			-- verschwundene Figuren vergessen
			for figure in _figureCool do
				if figure.Parent == nil then _figureCool[figure] = nil end
			end
		end
	end)
	print("[PitBrawlService] Gestartet | Reichweite", EventConfig.PIT_BRAWL.REACH)
end

return PitBrawlService
