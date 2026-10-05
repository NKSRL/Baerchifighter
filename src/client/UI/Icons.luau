--!strict
-- Icons.luau
-- StarterPlayerScripts/UI/Icons.luau
--
-- Einzige Zustaendigkeit:
--   - Die Icon-Bilder des UI: Name → Roblox-Asset und ein Baustein, der ein
--     Icon in einen Container setzt.
--
-- Die PNGs liegen in assets/icons/ (Cartoon-Stil, dicker dunkler Rand). Sie
-- muessen EINMAL zu Roblox hochgeladen werden (Studio → Asset Manager →
-- Bulk Import, Typ "Image"); die entstandenen IDs kommen unten in IDS.
--
-- Solange eine ID leer ist, zeichnet make() stattdessen ein Text-Kuerzel —
-- das UI ist also auch ohne Upload bedienbar und nie leer.

local Icons = {}

-- Name → "rbxassetid://<id>". Leerer String = noch nicht hochgeladen.
local IDS: { [string]: string } = {
	egg       = "rbxassetid://136964848925363",
	bear      = "rbxassetid://122776209368174",
	tree      = "rbxassetid://129797544978321",
	trophy    = "rbxassetid://75245452219620",
	gift      = "rbxassetid://74340672915054",
	gummy     = "rbxassetid://119048609020329",
	goldgummy = "rbxassetid://84033098355972",
	crown     = "rbxassetid://133046204324660",
	rebirth   = "rbxassetid://107316929618805",
	globe     = "rbxassetid://104196408080735",
	ufo       = "rbxassetid://75799134348421",
	swords    = "rbxassetid://138272803014747",
	scroll    = "rbxassetid://82949036446757",
	check     = "rbxassetid://101607257834692",
	honey     = "rbxassetid://73136954746111",
	lock      = "rbxassetid://93949208631544",
}

function Icons.has(name: string): boolean
	local id = IDS[name]
	return id ~= nil and id ~= ""
end

-- Setzt Icon `name` als Kind von `parent` und gibt es zurueck. Position und
-- Groesse stellt der Aufrufer danach selbst ein.
--
-- `fallback` ist das Text-Kuerzel, falls es das Bild (noch) nicht gibt.
function Icons.make(parent: Instance, name: string, fallback: string?): GuiObject
	if Icons.has(name) then
		local image = Instance.new("ImageLabel")
		image.Name                   = "Icon"
		image.BackgroundTransparency = 1
		image.BorderSizePixel        = 0
		image.Image                  = IDS[name]
		image.ScaleType              = Enum.ScaleType.Fit
		image.Parent                 = parent
		return image
	end

	local label = Instance.new("TextLabel")
	label.Name                   = "Icon"
	label.BackgroundTransparency = 1
	label.Font                   = Enum.Font.FredokaOne
	label.Text                   = fallback or ""
	label.TextColor3             = Color3.new(1, 1, 1)
	label.TextStrokeColor3       = Color3.fromRGB(24, 20, 38)
	label.TextStrokeTransparency = 0
	label.TextScaled             = true
	label.Parent                 = parent
	return label
end

-- Faerbt ein Icon ein (z. B. grau bei gesperrten Knoepfen). Fuer das
-- Text-Kuerzel aendert es die Schriftfarbe, fuer das Bild die Bildfarbe.
function Icons.tint(icon: GuiObject, color: Color3)
	if icon:IsA("ImageLabel") then
		icon.ImageColor3 = color
	elseif icon:IsA("TextLabel") then
		icon.TextColor3 = color
	end
end

return Icons
