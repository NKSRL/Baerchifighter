--!strict
-- ActivityLock.luau
-- ServerScriptService/Util/ActivityLock.luau
--
-- Einzige Zustaendigkeit:
--   - Verhindern, dass die sichtbare Figur eines Spielers gleichzeitig zwei
--     Dinge tut, die beide ihre Position steuern (in den PIT laufen UND
--     selbststaendig zum Honig-Teich laufen).
--
-- Ein einfaches Schloss pro Spieler, das den NAMEN seines Halters traegt statt
-- nur eines Bools. Damit kann ein Service beim Freigeben pruefen, ob er
-- selbst noch der Halter ist — sonst koennte er versehentlich das Schloss
-- eines inzwischen neueren Halters wegreissen (z.B. wenn PitArenaService dem
-- Autopilot das Schloss per forceAcquire abgenommen hat, der Autopilot seine
-- Ess-Sequenz aber trotzdem noch zu Ende raeumt).

local Players = game:GetService("Players")

local ActivityLock = {}

local _owner: { [Player]: string } = {}

function ActivityLock.isFree(player: Player): boolean
	return _owner[player] == nil
end

function ActivityLock.owner(player: Player): string?
	return _owner[player]
end

-- Versucht das Schloss zu bekommen. true = gehoert ab jetzt `holder`.
-- false = ein anderer haelt es bereits — nichts wurde veraendert.
function ActivityLock.tryAcquire(player: Player, holder: string): boolean
	if _owner[player] ~= nil then
		return false
	end
	_owner[player] = holder
	return true
end

-- Nimmt das Schloss auf jeden Fall, auch wenn es schon jemand haelt. Nur fuer
-- Aktionen, die immer Vorrang haben (aktuell: ein vom Spieler ausgeloester
-- Kampf gegenueber dem automatischen Weg zum Honig-Teich).
function ActivityLock.forceAcquire(player: Player, holder: string)
	_owner[player] = holder
end

-- Gibt das Schloss frei — aber nur wenn `holder` es tatsaechlich noch haelt.
function ActivityLock.release(player: Player, holder: string)
	if _owner[player] == holder then
		_owner[player] = nil
	end
end

Players.PlayerRemoving:Connect(function(player)
	_owner[player] = nil
end)

return ActivityLock
