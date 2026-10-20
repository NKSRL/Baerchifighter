--!strict
-- PetCapacity.luau
-- ReplicatedStorage/Modules/PetCapacity.luau
--
-- Einzige Zustaendigkeit:
--   - Die Rechenregeln des Pet-Limits als reine Funktionen ueber den Spielstand:
--     Limit, Anzahl, freier Platz, Zustand (ok / warn / full / over)
--
-- Keine Roblox-Dienste ausser den Schaltern. Der Server (EggService) setzt die
-- Regel durch, der Client (Zaehler, ausgegraute Oeffnen-Knoepfe) rechnet mit
-- denselben Funktionen — der Client entscheidet aber nie.
--
-- Was zaehlt: ALLE Baerchis in island.baerchis (auch das ausgeruestete und das
-- im Inkubator). Was nicht zaehlt: Eier und der Index.
--
-- Schalter aus (PET_LIMIT_V1 = false): es gibt kein Limit, getFree liefert
-- unendlich viel Platz — das Spiel verhaelt sich wie vor dem Paket.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FeatureFlags   = require(ReplicatedStorage.Config.FeatureFlags)
local PetLimitConfig = require(ReplicatedStorage.Config.PetLimitConfig)

local PetCapacity = {}

export type State = "ok" | "warn" | "full" | "over"

function PetCapacity.isActive(): boolean
	return FeatureFlags.isOn("PET_LIMIT_V1")
end

-- Das Limit dieses Spielers. HAKEN fuer spaeter: hier kommen Rebirth-, Gamepass-
-- und Upgrade-Boni drauf (data.rebirthCount, data.gamepasses, ...). Heute nur
-- der Basiswert.
function PetCapacity.getPetLimit(_data: any): number
	return PetLimitConfig.BASE_LIMIT
end

-- Anzahl aller Baerchis im Besitz.
function PetCapacity.count(data: any): number
	local n = 0
	for _ in data.island.baerchis do
		n += 1
	end
	return n
end

-- Freier Platz (>= 0). Mit ausgeschaltetem Schalter: math.huge.
function PetCapacity.getFree(data: any): number
	if not PetCapacity.isActive() then return math.huge end
	return math.max(0, PetCapacity.getPetLimit(data) - PetCapacity.count(data))
end

-- Passen `n` weitere Baerchis hinein?
function PetCapacity.canAdd(data: any, n: number): boolean
	return PetCapacity.getFree(data) >= n
end

function PetCapacity.isFull(data: any): boolean
	return PetCapacity.getFree(data) <= 0
end

-- Zustand fuer die Anzeige. "over" = ein Bestandsspieler mit mehr Baerchis als
-- das Limit: nichts wird geloescht, aber es kommt nichts Neues dazu.
function PetCapacity.state(data: any): State
	local limit = PetCapacity.getPetLimit(data)
	local count = PetCapacity.count(data)
	if count > limit then return "over" end
	if count >= limit then return "full" end
	if count >= limit * PetLimitConfig.WARN_FRACTION then return "warn" end
	return "ok"
end

return PetCapacity
