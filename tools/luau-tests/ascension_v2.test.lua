-- ascension_v2.test.lua — Welt 1, Paket 5d (20.10.2026)
-- python tools/luau-tests/run_local.py tools/luau-tests/ascension_v2.test.lua
local EggConfig = require(RS.Config.EggConfig)
local BC = require(RS.Config.BaerchiConfig)
local EggTree = require(RS.Modules.EggTree)
local FF = require(RS.Config.FeatureFlags)

local failures = 0
local function check(name, ok, d) if ok then print("ok   " .. name) else failures += 1; print("FAIL " .. name .. (d ~= nil and (" -> " .. tostring(d)) or "")) end end

local pet = BC.getById("AscendantBaerchi")
check("Hoffnungs-Pet existiert (Godly, Pfad Ascension)", pet ~= nil and pet.rarity == "Godly" and pet.path == "Ascension")
check("Hoffnungs-Pet legt Transzendenz-Eier (21.10.)", pet.eggTable[1].eggType == "TranscendenceEgg")
local count = 0 for _ in BC.data do count += 1 end
check("33 Pets (29 + 4 Anime-Pets, 21.10.)", count == 33, count)

local h = EggConfig.data.AscensionEgg.hatchTable
check("Ascension-Ei: Hoffnungs-Pet genau 1 %", math.abs((h.AscendantBaerchi or 0) - 1) < 1e-9, h.AscendantBaerchi)
local sum = 0 for _, v in h do sum += v end
check("Ascension-Ei Summe 100 %", math.abs(sum - 100) < 1e-6, sum)
local leak = false
for id, egg in EggConfig.data do if id ~= "AscensionEgg" and egg.hatchTable.AscendantBaerchi then leak = true end end
check("Hoffnungs-Pet faellt aus keinem anderen Ei", not leak)

-- Schleifen-Pruefung: erwartete Hoffnungs-Pets pro Stunde aus Eigenlegen
local perHour = 3600 / pet.layIntervalSeconds * 0.01
check(("Selbst-Vervielfachung klein (%.3f Pets/h bei Dauerlauf)"):format(perHour), perHour < 0.15, perHour)

-- Baum: Gates
local discovered = {}
local function input(launched, disc, rebirths) return { eggTree = EggTree.newState(), discovered = disc, rebirthCount = rebirths, epilog = { state = launched and "launched" or "seen" } } end
local p1 = EggTree.getProgress(input(false, { NebulaBaerchi = true }, 99), "AscensionEgg")
check("Ascension: ohne Welt 2 gesperrt, auch mit Rebirths und Schluessel-Pet", not p1.ready)
local p2 = EggTree.getProgress(input(true, { NebulaBaerchi = true }, 0), "AscensionEgg")
check("Ascension: Welt 2 + Schluessel-Pet = bereit, ohne Rebirth", p2.ready)
local p3 = EggTree.getProgress(input(true, {}, 0), "AscensionEgg")
check("Ascension: ohne Schluessel-Pet nicht bereit", not p3.ready)
local p4 = EggTree.getProgress(input(false, { AscendantBaerchi = true }, 0), "TranscendenceEgg")
check("Transzendenz: Hoffnungs-Pet = bereit (kein Rebirth)", p4.ready)
local p5 = EggTree.getProgress(input(false, { TitanBaerchi = true }, 0), "EternityEgg")
check("Ewigkeit: Titan = bereit", p5.ready)
local p6 = EggTree.getProgress(input(false, { InfinityBaerchi = true }, 0), "OmegaEgg")
check("Omega: Infinity = bereit", p6.ready)
-- Bestand: bereits freigeschaltet bleibt frei
local st = input(false, {}, 0); st.eggTree.unlocked.AscensionEgg = true
check("Bereits freigeschaltet bleibt frei", EggTree.isUnlocked(st.eggTree, "AscensionEgg"))

-- Schalter aus = altes Verhalten
FF.FLAGS.ASCENSION_V2 = false
EggConfig.setDropRatesV2(false)
local old = EggConfig.data.AscensionEgg.hatchTable
check("Aus: kein Hoffnungs-Pet im Ei", old.AscendantBaerchi == nil)
local q = EggTree.getProgress(input(false, { NebulaBaerchi = true }, 0), "AscensionEgg")
check("Aus: Rebirth-Gate gilt wieder (R0 -> gesperrt)", not q.ready)
local q2 = EggTree.getProgress(input(false, {}, 1), "AscensionEgg")
check("Aus: R1 reicht", q2.ready)
FF.FLAGS.ASCENSION_V2 = true
EggConfig.setDropRatesV2(false)

if failures > 0 then error(failures .. " Fehler") end
print("alle ok")
