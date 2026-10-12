-- driver.lua — baut die Client-UI in der Attrappe auf und gibt den Baum aus.
-- Wird von preview.py hinter shim.lua gehaengt; __ARGS kommt von dort:
--   { width, height, lang, scenario, pass, v2, panel, extra = { hud = bool } }

local A = __ARGS
local R = __rbxRequire

local FeatureFlags = R("ReplicatedStorage/Config/FeatureFlags")
FeatureFlags.FLAGS.TOWER_PANEL_V2 = A.v2
FeatureFlags.FLAGS.TOWER_TERMINAL = false
if A.passReady then
	R("ReplicatedStorage/Config/GamepassConfig").PASSES.SKIP_PASS.id = 123
end

local Loc = R("ReplicatedStorage/Localization/Loc")
Loc.setLanguage(A.lang)

local inset = 36
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RBL"
screenGui.AbsoluteSize = Vector2.new(A.width, A.height - inset)
screenGui.Parent = __playerGui

local UI = "StarterPlayerScripts/UI/"
local CT = "StarterPlayerScripts/Controllers/"
local UiScale = R(UI .. "UiScale")
UiScale.init(screenGui)
local ClientState = R(CT .. "ClientState")
ClientState.init()

local ok, err
if A.hud then
	for _, name in { "Hud", "MenuBar", "PetBar" } do
		ok, err = pcall(function() R(UI .. name).init(screenGui) end)
		if not ok then print("[driver] " .. name .. ": " .. tostring(err)) end
	end
end
ok, err = pcall(function() R(UI .. "CombatPanel").init(screenGui) end)
if not ok then print("[driver] CombatPanel: " .. tostring(err)) end
if A.v2 then
	ok, err = pcall(function() R(UI .. "TowerPanel").init(screenGui) end)
	if not ok then print("[driver] TowerPanel: " .. tostring(err)) end
end

-- Szenario-Daten
local function data(records, selected, unlocked, progress, gummies)
	return {
		gummies = gummies, goldGummies = 565, rebirthCount = A.rebirths or 0, rebirthMult = 1,
		rank = { tier = 1, name = "x", points = 0 },
		island = {
			buildings = { HoneyPond = { id = "HoneyPond", level = 12, honey = 3, lastProducedAt = 0 } },
			baerchis = { b1 = { uid = "b1", configId = "RedBaerchi", rarity = "Rare", level = 30, xp = 0, skillId = "x",
				isFusionResult = false, fusionBonus = 0, currentHp = 100, promotionLevel = 0,
				statLevels = { hp = 0, atk = 0, spd = 0, pwr = 0, egg = 0 }, charms = {} } },
			equippedUid = "b1",
			eggStock = { BasicEgg = 2 }, laidEggs = {}, lastEggAt = 0,
			recycler = { level = 3, queued = 0, progress = 0, lastProcessedAt = 0 },
			towerProgress = progress, pitRefund = 0,
		},
		discovered = {}, quests = { chainDone = 6, chainTotal = 12, daily = {}, dailyResetIn = 100 },
		eggTree = { unlocked = { BasicEgg = true }, hatched = {}, pressed = {}, blueprints = 0, bypass = {} },
		towers = { records = records, claimed = {}, highestTower = selected, selected = selected, unlocked = unlocked },
		daily = { day = 1, claimable = false, streak = 1, resetIn = 100 },
		stats = { totalEventsCompleted = 3 }, uiSeen = {},
	}
end

local scenarios = {
	only1 = function() return data({ I = 12 }, "I", { I = true }, { I = 12 }, 5953) end,
	new2  = function() return data({ I = 30 }, "I", { I = true, II = true }, { I = 30 }, 118548) end,
	mid   = function() return data({ I = 30, II = 23 }, "II", { I = true, II = true }, { II = 23 }, 2400000) end,
	all   = function() return data({ I = 30, II = 45, III = 60, Final = 100, Endless = 23 }, "III",
		{ I = true, II = true, III = true, Final = true, Endless = true }, { III = 40 }, 98000000) end,
	endless = function() return data({ I = 30, II = 45, III = 60, Final = 100, Endless = 23 }, "Endless",
		{ I = true, II = true, III = true, Final = true, Endless = true }, { Endless = 23 }, 98000000) end,
	poor  = function() return data({ I = 30, II = 23 }, "II", { I = true, II = true }, { II = 23 }, 1200) end,
}
local update = (scenarios[A.scenario] or scenarios.new2)()
if A.pass then __localPlayer:SetAttribute("Pass_SKIP_PASS", true) end
__remote("PlayerDataUpdated").OnClientEvent:Fire(update)
if A.running then __remote("PetModeChanged").OnClientEvent:Fire("InPit", nil, { stage = 7, tower = "II" }) end

local PanelManager = R(UI .. "PanelManager")
if A.panel then PanelManager.open("Combat") end

__flushTasks()
local rs = game:GetService("RunService")
for _ = 1, 3 do
	rs.RenderStepped:Fire(1 / 60)
	rs.Heartbeat:Fire(1 / 60)
	__flushTasks()
end

-- Leck-Test (Paket D6): 50x oeffnen/schliessen, Instanzen zaehlen
if A.leak then
	local Kit = R(UI .. "Kit")
	local function count() return #screenGui:GetDescendants() end
	PanelManager.close("Combat")
	__flushTasks()
	local before = count()
	for _ = 1, 50 do
		PanelManager.open("Combat")
		__flushTasks()
		rs.RenderStepped:Fire(1 / 60)
		PanelManager.close("Combat")
		__flushTasks()
	end
	print(string.format("@@LEAK@@ vorher=%d nachher=%d animationen=%d", before, count(), Kit.activeAnimations()))
	PanelManager.open("Combat")
	__flushTasks()
end

print("@@JSON@@" .. __dumpTree(screenGui))
