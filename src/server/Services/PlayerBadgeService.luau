--!strict
-- PlayerBadgeService.luau
-- ServerScriptService/Services/PlayerBadgeService.luau
--
-- Einzige Zustaendigkeit:
--   - Das Abzeichen ueber dem Kopf jedes Spielers (v15): Symbol des hoechsten
--     Towers + Rebirth-Zahl, ein BillboardGui pro Spieler.
--
-- Wird nur neu beschriftet, wenn sich der Text aendert (Signatur), und beim
-- (Re-)Spawn des Charakters neu angehaengt. Reine Anzeige, aendert keine Daten.

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types       = require(ReplicatedStorage.Network.Types)
local TowerConfig = require(ReplicatedStorage.Config.TowerConfig)

local PlayerService = require(ServerScriptService.Services.PlayerService)

local PlayerBadgeService = {}

local BADGE_NAME     = "TowerBadge"
local BADGE_OFFSET   = Vector3.new(0, 3.2, 0)
local BADGE_SIZE     = UDim2.fromScale(6, 1.2)
local BADGE_DISTANCE = 90

local _text: { [Player]: string } = {}

local function badgeOf(data: Types.PlayerData): (string, Color3)
	local towerId, record = TowerConfig.bestRecord(data.towers)
	local def = TowerConfig.get(towerId) or TowerConfig.TOWERS[1]
	local towerPart = if record > 0 then string.format("◆ %s %d", def.numeral, record) else "◆ —"
	return string.format("%s   ⟳ %d", towerPart, data.rebirthCount), def.color
end

local function apply(player: Player, data: Types.PlayerData, force: boolean)
	local text, color = badgeOf(data)
	if not force and _text[player] == text then return end
	_text[player] = text

	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then return end

	local gui = head:FindFirstChild(BADGE_NAME)
	if not gui then
		local billboard = Instance.new("BillboardGui")
		billboard.Name        = BADGE_NAME
		billboard.Size        = BADGE_SIZE
		billboard.StudsOffset = BADGE_OFFSET
		billboard.MaxDistance = BADGE_DISTANCE
		billboard.AlwaysOnTop = false
		billboard.Adornee     = head
		billboard.Parent      = head

		local label = Instance.new("TextLabel")
		label.Name                   = "Text"
		label.Size                   = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font                   = Enum.Font.FredokaOne
		label.TextScaled             = true
		label.TextStrokeTransparency = 0.3
		label.Parent                 = billboard
		gui = billboard
	end

	local label = (gui :: Instance):FindFirstChild("Text")
	if label and label:IsA("TextLabel") then
		label.Text       = text
		label.TextColor3 = color
	end
end

function PlayerBadgeService.init()
	PlayerService.onPlayerReady(function(player, data)
		apply(player, data, true)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("Head", 10)
			local current = PlayerService.getData(player)
			if current then apply(player, current, true) end
		end)
	end)

	PlayerService.onDataChanged(function(player, data)
		apply(player, data, false)
	end)

	Players.PlayerRemoving:Connect(function(player)
		_text[player] = nil
	end)

	print("[PlayerBadgeService] Initialisiert")
end

return PlayerBadgeService
