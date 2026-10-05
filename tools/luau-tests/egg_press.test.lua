-- egg_press.test.lua — Playtest 05.10.: Basis-Eier sind nicht pressbar
-- python tools/luau-tests/run_local.py tools/luau-tests/egg_press.test.lua
--
-- Basis-Eier gibt es beim Haendler unbegrenzt. EggConfig.canPress ist die
-- einzige Regel fuer Server und Ei-Baum-Fenster.

local EggConfig    = rbxRequire("ReplicatedStorage/Config/EggConfig")
local FeatureFlags = rbxRequire("ReplicatedStorage/Config/FeatureFlags")

local failures = 0
local function check(name, ok)
	if ok then print("ok   " .. name) else failures += 1; print("FAIL " .. name) end
end

check("Schalter PRESS_NO_BASIC_EGG an", FeatureFlags.isOn("PRESS_NO_BASIC_EGG"))
check("Basis-Ei nicht pressbar", not EggConfig.canPress("BasicEgg"))
check("Zucker-Ei pressbar", EggConfig.canPress("SugarEgg"))
check("unbekanntes Ei nicht pressbar", not EggConfig.canPress("GibtsNicht" :: any))
for id, egg in EggConfig.data do
	if EggConfig.PRESS.blockedPaths[egg.path] then
		check(id .. " (gesperrter Pfad) nicht pressbar", not EggConfig.canPress(id))
	end
end

if failures > 0 then error(failures .. " Fehler", 0) end
print("egg_press: alle Tests gruen")
