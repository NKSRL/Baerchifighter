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

--------------------------------------------------------------------------------
-- Bilder fuer Ei-Menue, Ei-Baum und MenuBar (assets/ui/, gezeichnet in Blender
-- mit tools/art/render_eggs.py und tools/art/render_ui.py)
--------------------------------------------------------------------------------
--
-- Schluessel = Pfad unter assets/ui/ ohne ".png". Nach dem Hochladen kommt
-- die ID als "rbxassetid://<id>" hinter den Schluessel. Leer = noch nicht
-- hochgeladen: dann zeichnen EggIcon, Theme und EggTreePanel ihren
-- einfachen Rueckfall (Frames, Farben, Text) — das UI bleibt bedienbar.
-- Anleitung: docs/HBB_COWORK_EI_UI_PROMPT.md
local UI_IDS: { [string]: string } = {
	["eggs/AbyssEgg"]               = "",
	["eggs/AscensionEgg"]           = "",
	["eggs/AuroraEgg"]              = "",
	["eggs/BasicEgg"]               = "",
	["eggs/CometEgg"]               = "",
	["eggs/CrystalEgg"]             = "",
	["eggs/EternityEgg"]            = "",
	["eggs/GalaxyEgg"]              = "",
	["eggs/GoldenEgg"]              = "",
	["eggs/MistEgg"]                = "",
	["eggs/NovaEgg"]                = "",
	["eggs/OmegaEgg"]               = "",
	["eggs/PlatinumEgg"]            = "",
	["eggs/PrismEgg"]               = "",
	["eggs/ShadowEgg"]              = "",
	["eggs/SugarEgg"]               = "",
	["eggs/SunEgg"]                 = "",
	["eggs/TranscendenceEgg"]       = "",
	["eggs/UfoJackpotEgg"]          = "",
	["eggs/VoidEgg"]                = "",
	["eggs/ZenithEgg"]              = "",
	["eggs/egg_mask"]               = "",
	["tree/branch_ascension"]       = "",
	["tree/branch_glow"]            = "",
	["tree/branch_gold"]            = "",
	["tree/branch_kosmos"]          = "",
	["tree/branch_kristall"]        = "",
	["tree/branch_stamm"]           = "",
	["tree/branch_void"]            = "",
	["tree/cup_locked_back"]        = "",
	["tree/cup_locked_front"]       = "",
	["tree/cup_open_back"]          = "",
	["tree/cup_open_front"]         = "",
	["tree/cup_ready_back"]         = "",
	["tree/cup_ready_front"]        = "",
	["tree/lock"]                   = "",
	["tree/tree_bg"]                = "",
	["tree/trunk"]                  = "",
	["fx/honeylight"]               = "",
	["fx/pollen"]                   = "",
	["fx/ring_rays"]                = "",
	["fx/ring_soft"]                = "",
	["fx/sparkle"]                  = "",
	["frames/frame_card"]           = "",
	["frames/frame_panel"]          = "",
	["frames/frame_tile"]           = "",
	["frames/pedestal"]             = "",
	["frames/seal"]                 = "",
}

-- 9-Slice-Rahmen: SliceCenter in Bildpixeln {links, oben, rechts, unten}.
-- Fest, weil die Bilder fest sind (render_ui.py: frame()/render_seal()).
local SLICES: { [string]: { number } } = {
	["frames/frame_panel"] = { 72, 72, 184, 184 },   -- 256 × 256
	["frames/frame_card"]  = { 64, 64, 192, 192 },   -- 256 × 256
	["frames/frame_tile"]  = { 76, 76, 180, 180 },   -- 256 × 256, Mitte durchsichtig
	["frames/seal"]        = { 76, 44, 180, 84 },    -- 256 × 128
}

-- ID eines UI-Bildes oder nil, wenn es (noch) keine gibt.
function Icons.ui(name: string): string?
	local id = UI_IDS[name]
	if id == nil or id == "" then return nil end
	return id
end

function Icons.hasUi(name: string): boolean
	return Icons.ui(name) ~= nil
end

-- Alle Schluessel (fuer Tests und den Upload-Abgleich).
function Icons.uiNames(): { string }
	local list = {}
	for name in UI_IDS do table.insert(list, name) end
	table.sort(list)
	return list
end

-- Bild als ImageLabel in `parent`, oder nil ohne ID (der Aufrufer baut dann
-- seinen Rueckfall). 9-Slice-Rahmen bekommen SliceCenter automatisch;
-- `sliceScale` macht den Rand auf kleinen Flaechen schmaler.
function Icons.uiImage(parent: Instance, name: string, sliceScale: number?): ImageLabel?
	local id = Icons.ui(name)
	if not id then return nil end
	local image = Instance.new("ImageLabel")
	image.Name                   = string.match(name, "[^/]+$") or name
	image.BackgroundTransparency = 1
	image.BorderSizePixel        = 0
	image.Image                  = id
	image.Active                 = false
	local slice = SLICES[name]
	if slice then
		image.ScaleType   = Enum.ScaleType.Slice
		image.SliceCenter = Rect.new(slice[1], slice[2], slice[3], slice[4])
		image.SliceScale  = sliceScale or 1
	else
		image.ScaleType = Enum.ScaleType.Stretch
	end
	image.Parent = parent
	return image
end

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
