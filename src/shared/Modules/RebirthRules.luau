--!strict
-- RebirthRules.luau
-- ReplicatedStorage/Modules/RebirthRules.luau
--
-- Einzige Zustaendigkeit (Welt 1, Paket 5a, 20.10.2026):
--   - Darf der Spieler rebirthen, wenn Welt 2 noch nicht offen ist?
--     Neue Regel (Flag REBIRTH_NEEDS_WORLD2): Rebirth erst nach dem Raketenstart.
--     Bestandsschutz: wer schon rebirthCount >= 1 hat, darf weiter.
--   - Reine Funktionen, Server und Client nutzen dieselbe Regel.
-- Test: tools/luau-tests/rebirth_world2.test.lua

local FeatureFlags = require(script.Parent.Parent.Config.FeatureFlags)

local RebirthRules = {}

export type View = { rebirthCount: number?, epilog: { state: string? }? }

-- Welt 2 offen = Raketenknopf gedrueckt (epilog.state == "launched").
function RebirthRules.world2Open(view: View?): boolean
	if not view or typeof(view.epilog) ~= "table" then return false end
	return (view.epilog :: any).state == "launched"
end

-- Rein: Flag als Parameter (testbar ohne FeatureFlags).
function RebirthRules.allowedWith(flagOn: boolean, view: View?): boolean
	if not flagOn then return true end
	if view == nil then return false end
	if (view.rebirthCount or 0) >= 1 then return true end   -- Bestandsschutz
	return RebirthRules.world2Open(view)
end

function RebirthRules.allowed(view: View?): boolean
	return RebirthRules.allowedWith(FeatureFlags.isOn("REBIRTH_NEEDS_WORLD2"), view)
end

return RebirthRules
