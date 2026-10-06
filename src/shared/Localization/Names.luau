--!strict
-- Names.luau
-- ReplicatedStorage/Localization/Names.luau
--
-- Einzige Zustaendigkeit:
--   - Anzeigenamen und Beschreibungen von Config-Eintraegen in der
--     Spielersprache liefern (Baerchis, Eier, Skills, Events, Gebaeude,
--     Mutationen, Charm-Werte)
--
-- Warum es dieses Modul gibt: die Configs tragen ihre Texte auf Deutsch
-- (`displayName`, `description`, ...). Jede Stelle, die diese Felder direkt
-- anzeigte, war ein Text, der nie uebersetzt wurde — und davon gab es ueber
-- dreissig. Jetzt ist das hier der EINZIGE Leser dieser Felder;
-- `tools/check_ui.py` (Regel T3) meldet jeden anderen. Das deutsche Feld
-- bleibt als Rueckfall stehen, falls ein Schluessel fehlt (T4 verhindert das).
--
-- Zwei Formen:
--   * Names.baerchi(id) usw.  → fertiger Text (Client, aktive Sprache)
--   * Names.msg.baerchi(id)   → LocMsg (Server: der Client loest sie auf,
--                               jeder Spieler in seiner Sprache)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types         = require(ReplicatedStorage.Network.Types)
local BaerchiConfig = require(ReplicatedStorage.Config.BaerchiConfig)
local EggConfig     = require(ReplicatedStorage.Config.EggConfig)
local SkillConfig   = require(ReplicatedStorage.Config.SkillConfig)
local EventConfig   = require(ReplicatedStorage.Config.EventConfig)
local CharmConfig   = require(ReplicatedStorage.Config.CharmConfig)
local MapConfig     = require(ReplicatedStorage.Config.MapConfig)
local Loc           = require(script.Parent.Loc)

local Names = {}

-- Ein Schluessel mit deutschem Rueckfall aus der Config; ohne beides die id.
local function lookup(key: string, fallback: string?, id: string): string
	return Loc.name(key, fallback or id)
end

--------------------------------------------------------------------------------
-- Baerchis
--------------------------------------------------------------------------------

function Names.baerchi(configId: string): string
	local def = BaerchiConfig.getById(configId)
	return lookup("baerchi." .. configId .. ".name", def and def.displayName, configId)
end

function Names.baerchiDesc(configId: string): string
	local def = BaerchiConfig.getById(configId)
	return lookup("baerchi." .. configId .. ".desc", def and def.description, "")
end

function Names.rarity(rarity: string): string
	return Loc.name("rarity." .. rarity, rarity)
end

function Names.mutation(mutation: Types.MutationId): string
	local ok, fallback = pcall(BaerchiConfig.getMutationDisplayName, mutation)
	return lookup("mutation." .. tostring(mutation) .. ".name", if ok then fallback else nil, tostring(mutation))
end

--------------------------------------------------------------------------------
-- Eier
--------------------------------------------------------------------------------

function Names.egg(eggType: string): string
	local def = EggConfig.data[eggType :: any]
	return lookup("egg." .. eggType .. ".name", def and def.displayName, eggType)
end

function Names.eggDesc(eggType: string): string
	local def = EggConfig.data[eggType :: any]
	return lookup("egg." .. eggType .. ".desc", def and def.description, "")
end

function Names.eggShort(eggType: string): string
	local def = EggConfig.data[eggType :: any]
	return lookup("egg." .. eggType .. ".short", def and def.shortName, eggType)
end

--------------------------------------------------------------------------------
-- Skills
--------------------------------------------------------------------------------

function Names.skill(skillId: string): string
	local def = SkillConfig.getById(skillId)
	return lookup("skill." .. skillId .. ".name", def and def.displayName, skillId)
end

function Names.skillDesc(skillId: string): string
	local def = SkillConfig.getById(skillId)
	return lookup("skill." .. skillId .. ".desc", def and def.description, "")
end

function Names.skillDrawback(skillId: string): string
	local def = SkillConfig.getById(skillId)
	return lookup("skill." .. skillId .. ".drawback", def and def.drawback, "")
end

--------------------------------------------------------------------------------
-- Events, Gebaeude, Charms
--------------------------------------------------------------------------------

function Names.event(eventId: string): string
	local def = EventConfig.getById(eventId)
	return lookup("event." .. eventId .. ".name", def and def.displayName, eventId)
end

function Names.building(buildingId: string): string
	local def = MapConfig.BUILDING_OFFSETS[buildingId]
	return lookup("building." .. buildingId .. ".name", def and def.displayName, buildingId)
end

function Names.buildingShort(buildingId: string): string
	local def = MapConfig.BUILDING_OFFSETS[buildingId]
	return lookup("building." .. buildingId .. ".short", def and def.shortName, buildingId)
end

function Names.charmStat(statId: string): string
	local def = CharmConfig.getStatDef(statId)
	return lookup("charm." .. statId .. ".name", def and def.displayName, statId)
end

--------------------------------------------------------------------------------
-- Dieselben Namen als Nachricht (fuer den Server)
--------------------------------------------------------------------------------
-- Der Server kennt die Sprache des Spielers nicht. Er schickt deshalb nur den
-- Schluessel; Loc.resolve beim Client setzt den Namen ein — auch verschachtelt
-- als Argument einer anderen Nachricht ("+{n}x {egg}").

Names.msg = {
	baerchi  = function(configId: string): Types.LocMsg return Loc.msg("baerchi." .. configId .. ".name") end,
	egg      = function(eggType: string): Types.LocMsg return Loc.msg("egg." .. eggType .. ".name") end,
	eggShort = function(eggType: string): Types.LocMsg return Loc.msg("egg." .. eggType .. ".short") end,
	event    = function(eventId: string): Types.LocMsg return Loc.msg("event." .. eventId .. ".name") end,
	building = function(buildingId: string): Types.LocMsg return Loc.msg("building." .. buildingId .. ".name") end,
	mutation = function(mutation: string): Types.LocMsg return Loc.msg("mutation." .. mutation .. ".name") end,
}

return Names
