--!strict
-- WorldText.luau
-- ReplicatedStorage/Localization/WorldText.luau
--
-- Einzige Zustaendigkeit:
--   - Texte, die der SERVER in die Welt schreibt (Tafeln, Schilder, Labels
--     ueber Figuren, ProximityPrompts), fuer jeden Spieler in SEINER Sprache
--     anzeigen
--
-- Das Problem: eine BillboardGui ueber der Arena gibt es einmal fuer alle.
-- Schreibt der Server `Text = "Keine Stage geschafft"`, liest das auch der
-- Spieler aus Frankreich. Der Server kennt die Sprache der Spieler nicht und
-- soll sie auch nicht kennen (siehe Loc: "Der Server formuliert nie einen Satz").
--
-- Die Loesung: der Server haengt die NACHRICHT (LocMsg, Schluessel + Werte)
-- als Attribut an die Instanz und markiert sie mit dem Tag "LocText". Jeder
-- Client loest das Attribut selbst auf — beim Erscheinen, bei jeder Aenderung
-- und bei jedem Sprachwechsel (WorldText.startClient, aufgerufen in Main).
--
-- Den sichtbaren Text setzt der Server nur beim ERSTEN Mal (in seiner Sprache,
-- als Platzhalter bis der Client uebernimmt). Danach aendert er nur noch das
-- Attribut — sonst wuerde ein Countdown jede Sekunde kurz in der falschen
-- Sprache aufblitzen, bevor der Client ihn wieder umschreibt.
--
-- Mehrere Eigenschaften pro Instanz gehen (ProximityPrompt: ActionText und
-- ObjectText): das Attribut heisst "Loc_<Eigenschaft>".

local CollectionService = game:GetService("CollectionService")
local HttpService       = game:GetService("HttpService")

local Types = require(script.Parent.Parent.Network.Types)
local Loc   = require(script.Parent.Loc)

local WorldText = {}

WorldText.TAG = "LocText"

local PROPERTIES = { "Text", "ActionText", "ObjectText" }

local function attributeName(property: string): string
	return "Loc_" .. property
end

--------------------------------------------------------------------------------
-- Server
--------------------------------------------------------------------------------

-- Beschriftet `instance.<property>` mit einem Text oder einer Nachricht.
-- Ein fertiger String (z.B. reine Zahlen "12 / 40") wird direkt gesetzt und
-- loescht eine fruehere Nachricht.
function WorldText.set(instance: Instance, value: string | Types.LocMsg, property: string?)
	local prop = property or "Text"
	local attr = attributeName(prop)
	local target: any = instance

	if typeof(value) == "string" then
		instance:SetAttribute(attr, nil)
		target[prop] = value
		return
	end

	local encoded = HttpService:JSONEncode(value)
	local first = instance:GetAttribute(attr) == nil
	if instance:GetAttribute(attr) ~= encoded then
		instance:SetAttribute(attr, encoded)
	end
	if first then
		target[prop] = Loc.resolve(value)
	end
	if not CollectionService:HasTag(instance, WorldText.TAG) then
		CollectionService:AddTag(instance, WorldText.TAG)
	end
end

--------------------------------------------------------------------------------
-- Client
--------------------------------------------------------------------------------

local function resolve(instance: Instance)
	for _, prop in PROPERTIES do
		local raw = instance:GetAttribute(attributeName(prop))
		if typeof(raw) == "string" then
			local ok, msg = pcall(HttpService.JSONDecode, HttpService, raw)
			if ok then
				local target: any = instance
				pcall(function()
					target[prop] = Loc.resolve(msg)
				end)
			end
		end
	end
end

local function watch(instance: Instance)
	resolve(instance)
	for _, prop in PROPERTIES do
		instance:GetAttributeChangedSignal(attributeName(prop)):Connect(function()
			resolve(instance)
		end)
	end
end

-- Einmal beim Client-Start (Main). Danach laeuft alles ueber Signale —
-- keine Schleife pro Frame.
function WorldText.startClient()
	for _, instance in CollectionService:GetTagged(WorldText.TAG) do
		watch(instance)
	end
	CollectionService:GetInstanceAddedSignal(WorldText.TAG):Connect(watch)

	Loc.onChanged(function()
		for _, instance in CollectionService:GetTagged(WorldText.TAG) do
			resolve(instance)
		end
	end)
end

return WorldText
