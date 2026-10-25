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
-- 14.10. UI_HONEY_SKIN: die Waehrungs-Icons "gummy"/"goldgummy" sind jetzt Paw Coin und
-- Honey Crystal (ueberall, wo Icons.make(..., "gummy") benutzt wird).
do
	local ok, flags = pcall(function() return require(game:GetService("ReplicatedStorage").Config.FeatureFlags) end)
	if ok and flags.isOn("UI_HONEY_SKIN") then
		IDS.gummy     = "rbxassetid://105188312461511"
		IDS.goldgummy = "rbxassetid://121338605294333"
	end
end

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
	["eggs/AuroraEgg"]              = "rbxassetid://128624067596954",
	["eggs/BasicEgg"]               = "rbxassetid://139462456858860",
	["eggs/CometEgg"]               = "rbxassetid://72343604946191",
	["eggs/CrystalEgg"]             = "rbxassetid://131259197241502",
	["eggs/EternityEgg"]            = "",
	["eggs/GalaxyEgg"]              = "rbxassetid://75049781906047",
	["eggs/GoldenEgg"]              = "",
	["eggs/MistEgg"]                = "rbxassetid://135149596067002",
	["eggs/NovaEgg"]                = "",
	["eggs/OmegaEgg"]               = "rbxassetid://110123007289870",
	["eggs/PlatinumEgg"]            = "rbxassetid://109207973135325",
	["eggs/PrismEgg"]               = "rbxassetid://94860329458860",
	["eggs/ShadowEgg"]              = "",
	["eggs/SugarEgg"]               = "rbxassetid://99106612485972",
	["eggs/SunEgg"]                 = "rbxassetid://95896852084747",
	["eggs/TranscendenceEgg"]       = "rbxassetid://132274722580858",
	["eggs/UfoJackpotEgg"]          = "",
	["eggs/AnimeEgg"]               = "",
	["eggs/VoidEgg"]                = "rbxassetid://136294845645416",
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
	-- 14.10.: neues Honig-UI (eigene Bilder des Spielers, hochgeladen als Image).
	-- Schalter: FeatureFlags.UI_HONEY_SKIN. Das sind die IMAGE-IDs (die Decal-IDs aus dem
	-- Asset Manager laden in ImageLabels nicht; ermittelt mit InsertService:LoadAsset).
	["honey/settings"]             = "rbxassetid://88362500381367",
	["honey/bears_btn"]            = "rbxassetid://94596135405106",
	["honey/quest_window"]         = "rbxassetid://92667718010617",
	["honey/daily_btn"]            = "rbxassetid://86275653412102",
	["honey/eggs_btn"]             = "rbxassetid://71465614737750",
	["honey/egg_tree_btn"]         = "rbxassetid://122080043663661",
	["honey/quest_bar"]            = "rbxassetid://128679896638321",
	["honey/close_btn"]            = "rbxassetid://135204722524839",
	["honey/leaderboard_btn"]      = "rbxassetid://103332845663800",
	["honey/bear_bar"]             = "rbxassetid://76294073929970",
	["honey/equip_btn"]            = "rbxassetid://73444030548408",   -- 19.10.: Ausruesten-Knopf (freigestellt)
	-- 14.10. Teil 2: Fenster und Knoepfe (freigestellt hochgeladen)
	["honey/scroll_btn"]           = "rbxassetid://107670656548028",   -- Quest-Knopf
	["honey/shop_btn"]             = "rbxassetid://109627337837940",   -- Shop-Knopf
	["honey/shop_window"]          = "rbxassetid://74659327479306",    -- helles leeres Fenster
	["honey/tower_window"]         = "rbxassetid://116415152657312",   -- Fenster mit Tabs + 3 Knoepfen
	["honey/daily_window"]         = "rbxassetid://114468054048359",   -- dunkles leeres Fenster
	["honey/res_bar_pink"]         = "rbxassetid://110712317541270",   -- noch ungenutzt
	["honey/res_bar_gold"]         = "rbxassetid://99522410174928",    -- noch ungenutzt
	["honey/stat_bar"]             = "rbxassetid://108905481958929",   -- noch ungenutzt
	["honey/fight_btn"]            = "rbxassetid://94321728397377",
	["honey/fight_btn_active"]     = "rbxassetid://140171600981000",
	["honey/event_btn"]            = "rbxassetid://90767211639472",
	["honey/event_btn_active"]     = "rbxassetid://117450611491746",
	["honey/daily_pillar"]         = "rbxassetid://131391375507995",   -- noch ungenutzt
	-- 14.10. Waehrungen: Paw Coins (ersetzt Gummies) und Honey Crystals (ersetzt GoldGummies)
	["honey/paw_coin"]             = "rbxassetid://105188312461511",
	["honey/honey_crystal"]        = "rbxassetid://121338605294333",
	["honey/paw_coin_bar"]         = "rbxassetid://132619601355899",   -- 1503x346, Muenze links, Feld, gruenes +
	["honey/honey_crystal_bar"]    = "rbxassetid://93339411213607",    -- 1503x362
	["honey/currency_panel"]       = "rbxassetid://106838880505504",   -- Fenster mit Uhr + Honigglas (noch ungenutzt)
	-- 14.10. Teil 5 (freigestellt): Einstellungen, Baerchi-Details, zwei leere Standard-Knoepfe
	-- (Image-IDs; Decal-IDs: 138896368236897, 87774764018554, 98413107137742, 131774308051872)
	["honey/settings_window"]      = "rbxassetid://127242721875649",   -- 1023x682, Titel "Settings" im Bild
	["honey/pet_stats_window"]     = "rbxassetid://109853001690872",   -- 1023x682, Bild-Slots fuer Baerchi-Details
	["honey/btn_dark"]             = "rbxassetid://74690205069992",    -- 1024x512, leerer dunkler Standard-Knopf
	["honey/btn_light"]            = "rbxassetid://130269595911666",   -- 1024x512, leerer heller (Honig) Standard-Knopf
	-- 14.10. Charm-Fenster (Decal 91542574113706)
	["honey/charm_window"]         = "rbxassetid://118679865686270",   -- 683x1024 (Original 1024x1536), 8 Kacheln + 8 Zeilen + 2 Knoepfe
	["honey/incubator_window"]     = "rbxassetid://73327976420840",   -- 1506x937 (Roblox: 1024x637), Inkubator-Fenster, ID nach Upload eintragen
}

-- Sichtbarer Ausschnitt (Bildpixel der von Roblox verkleinerten Bilder: Offset, Groesse), damit
-- der durchsichtige Rand nicht mitzaehlt. Seitenverhaeltnis: Fenster ~1,60 / ~1,69, Knoepfe ~3,85.
local CROPS: { [string]: { Vector2 } } = {
	["honey/settings_window"]  = { Vector2.new(12, 19), Vector2.new(1004, 595) },
	["honey/pet_stats_window"] = { Vector2.new(4, 18),  Vector2.new(1018, 638) },
	["honey/charm_window"]      = { Vector2.new(7, 0),   Vector2.new(670, 993) },   -- Roblox verkleinert 1024x1536 auf 683x1024
	["honey/btn_dark"]         = { Vector2.new(4, 116), Vector2.new(1011, 262) },
	["honey/btn_light"]        = { Vector2.new(8, 116), Vector2.new(1008, 265) },
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

-- Honig-UI (14.10.): ein Knopf bekommt ein fertiges Bild als ganzes Aussehen.
-- Position, Groesse und Klick-Verbindungen bleiben; nur die bisherige Optik
-- (Hintergrund, Rand, Verlauf, Text, Glanz) verschwindet.
function Icons.skinButton(button: GuiButton, name: string): boolean
	local FeatureFlags = require(game:GetService("ReplicatedStorage").Config.FeatureFlags)
	if not FeatureFlags.isOn("UI_HONEY_SKIN") then return false end
	local id = Icons.ui(name)
	if not id then return false end
	if button:FindFirstChild("HoneySkin") then return true end

	button.BackgroundTransparency = 1
	if button:IsA("TextButton") then button.Text = "" end
	for _, child in button:GetChildren() do
		if child:IsA("UIStroke") or child:IsA("UIGradient") or child:IsA("UICorner") then
			child:Destroy()
		elseif child:IsA("GuiObject") and child.Name ~= "CloseHit" and child.Name ~= "Hit" then
			child.Visible = false
		end
	end

	local image = Instance.new("ImageLabel")
	image.Name                   = "HoneySkin"
	image.BackgroundTransparency = 1
	image.BorderSizePixel        = 0
	image.Image                  = id
	image.ScaleType              = Enum.ScaleType.Fit
	image.AnchorPoint            = Vector2.new(0.5, 0.5)
	image.Position               = UDim2.fromScale(0.5, 0.5)
	image.Size                   = UDim2.fromScale(1, 1)
	image.ZIndex                 = button.ZIndex + 1
	image.Active                 = false
	image.Parent                 = button
	return true
end

-- Honig-UI (14.10.): Bild als dehnbarer Rahmen (9-Slice). `slice` in Bildpixeln
-- (links, oben, rechts, unten), `sliceScale` macht die festen Raender kleiner,
-- `cropOffset`/`cropSize` schneiden durchsichtigen Rand ab. nil ohne Schalter/ID.
function Icons.honeyImage(parent: Instance, name: string, slice: Rect?, sliceScale: number?, cropOffset: Vector2?, cropSize: Vector2?): ImageLabel?
	local FeatureFlags = require(game:GetService("ReplicatedStorage").Config.FeatureFlags)
	if not FeatureFlags.isOn("UI_HONEY_SKIN") then return nil end
	local id = Icons.ui(name)
	if not id then return nil end
	local image = Instance.new("ImageLabel")
	image.Name                   = "HoneySkin"
	image.BackgroundTransparency = 1
	image.BorderSizePixel        = 0
	image.Image                  = id
	image.Size                   = UDim2.fromScale(1, 1)
	image.Active                 = false
	if cropOffset and cropSize then
		image.ImageRectOffset = cropOffset
		image.ImageRectSize   = cropSize
	end
	if slice then
		image.ScaleType   = Enum.ScaleType.Slice
		image.SliceCenter = slice
		image.SliceScale  = sliceScale or 1
	else
		image.ScaleType = Enum.ScaleType.Stretch
	end
	image.Parent = parent
	return image
end

-- Honig-UI (14.10.): Dialog (Theme.dialog) wird zu einem festen Bild-Fenster der Groesse
-- w x h (Seitenverhaeltnis des Bildes, nie verzerrt). Alter Rahmen verschwindet. Gibt das Bild
-- zurueck oder nil (Schalter aus / keine ID): dann bleibt alles wie es war.
function Icons.honeyWindow(root: GuiObject, name: string, w: number, h: number): ImageLabel?
	-- Bilder mit Eintrag in CROPS werden auf ihren sichtbaren Ausschnitt zugeschnitten (w x h
	-- muss dann dessen Seitenverhaeltnis haben).
	local FeatureFlags = require(game:GetService("ReplicatedStorage").Config.FeatureFlags)
	if not FeatureFlags.isOn("UI_HONEY_SKIN") or not Icons.ui(name) then return nil end
	root.BackgroundTransparency = 1
	for _, child in root:GetChildren() do
		if child:IsA("UIStroke") or child:IsA("UIGradient") or child:IsA("UICorner") then
			child:Destroy()
		elseif child:IsA("UISizeConstraint") then
			child.MinSize = Vector2.new(w, h)
			child.MaxSize = Vector2.new(w, h)
		elseif child:IsA("GuiObject") then
			child.Visible = false
		end
	end
	root.Size = UDim2.fromOffset(w, h)
	local crop = CROPS[name]
	local image = if crop then Icons.honeyImage(root, name, nil, nil, crop[1], crop[2]) else Icons.honeyImage(root, name)
	if image then image.ZIndex = 0 end
	return image
end

-- Honig-UI (14.10.): leerer Standard-Knopf als Bild ("honey/btn_dark" oder "honey/btn_light"), auf
-- den Ausschnitt zugeschnitten und mit festem Seitenverhaeltnis (Fit). Beschriftung legt der
-- Aufrufer als eigenes Label darueber. nil ohne Schalter/ID.
function Icons.honeyStdButton(parent: Instance, name: string): ImageLabel?
	local crop = CROPS[name]
	local image = Icons.honeyImage(parent, name, nil, nil, if crop then crop[1] else nil, if crop then crop[2] else nil)
	if image then
		image.Name = "StdButton"
		image.ScaleType = Enum.ScaleType.Fit
	end
	return image
end

-- Honig-UI: nach Theme.dialogHeader. Titel in die Titelleiste des Bildes (x, y, w, h in
-- Fenster-Einheiten), das Kreuz unsichtbar auf das Kreuz-Bild (Mitte cx, cy, Groesse).
function Icons.honeyHeader(root: GuiObject, bar: Rect, cx: number, cy: number, closeSize: number)
	local band = root:FindFirstChild("TitleBand")
	if band and band:IsA("GuiObject") then band.Visible = false end
	local header = root:FindFirstChild("Header")
	if header and header:IsA("GuiObject") then
		header.Position = UDim2.fromOffset(bar.Min.X, bar.Min.Y)
		header.Size     = UDim2.fromOffset(bar.Width, bar.Height)
		local title = header:FindFirstChild("Title")
		if title and title:IsA("TextLabel") then
			title.Size = UDim2.fromScale(1, 1)
			title.TextXAlignment = Enum.TextXAlignment.Center
		end
		local close = header:FindFirstChild("Close")
		if close and close:IsA("GuiObject") then
			close.Parent      = root
			close.AnchorPoint = Vector2.new(0.5, 0.5)
			close.Position    = UDim2.fromOffset(cx, cy)
			close.Size        = UDim2.fromOffset(closeSize, closeSize)
			close.ZIndex      = 30
			local skin = close:FindFirstChild("HoneySkin")
			if skin and skin:IsA("GuiObject") then skin.Visible = false end
		end
	end
end

-- Honig-UI (14.10.): ein Bild als ganzer Knopf MIT Beschriftung. Das Bild (Leiste mit Baer
-- links und dunklem Feld) bekommt die Knopfgroesse, das Wort liegt ein eigenes Label darauf
-- (Rueckgabe: das Label, damit der Aufrufer es an Loc binden kann; nil = Schalter aus/keine ID).
function Icons.skinLabelButton(button: GuiButton, name: string, text: string): (TextLabel?, ImageLabel?)
	local FeatureFlags = require(game:GetService("ReplicatedStorage").Config.FeatureFlags)
	if not FeatureFlags.isOn("UI_HONEY_SKIN") then return nil, nil end
	local id = Icons.ui(name)
	if not id then return nil, nil end
	button.BackgroundTransparency = 1
	if button:IsA("TextButton") then button.TextTransparency = 1 end
	for _, child in button:GetChildren() do
		if child:IsA("UIStroke") or child:IsA("UIGradient") or child:IsA("UICorner") or child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local art = Instance.new("ImageLabel")
	art.Name = "HoneySkin"
	art.BackgroundTransparency = 1
	art.BorderSizePixel = 0
	art.Image = id
	art.ScaleType = Enum.ScaleType.Stretch   -- Knopfgroesse hat das Seitenverhaeltnis des Bildes
	art.Size = UDim2.fromScale(1, 1)
	art.ZIndex = button.ZIndex + 1
	art.Active = false
	art.Parent = button
	local word = Instance.new("TextLabel")
	word.Name = "Word"
	word.BackgroundTransparency = 1
	word.AnchorPoint = Vector2.new(0, 0.5)
	word.Position = UDim2.fromScale(0.2, 0.5)
	word.Size = UDim2.fromScale(0.72, 0.52)
	word.Font = Enum.Font.FredokaOne
	word.Text = text
	word.TextScaled = true
	word.TextColor3 = Color3.new(1, 1, 1)
	word.TextStrokeColor3 = Color3.fromRGB(60, 30, 10)
	word.TextStrokeTransparency = 0
	word.ZIndex = button.ZIndex + 2
	word.Parent = button
	return word, art
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

-- 19.10. Vorladen: alle UI-Bilder werden beim Start geladen (der Ladebildschirm wartet
-- darauf), nicht erst beim ersten Klick auf ein Fenster. Fehler und Zeitueberschreitungen
-- blockieren nie: der Ladebildschirm hat eine eigene Obergrenze.
Icons.preloadState = { total = 0, done = 0, finished = false }

function Icons.preloadAll()
	local state = Icons.preloadState
	if state.total > 0 then return end
	local seen: { [string]: boolean } = {}
	local list: { string } = {}
	local function add(id: string)
		if id ~= "" and not seen[id] then
			seen[id] = true
			table.insert(list, id)
		end
	end
	for _, id in IDS do add(id) end
	for _, id in UI_IDS do add(id) end
	state.total = #list
	local player = game:GetService("Players").LocalPlayer
	local provider = game:GetService("ContentProvider")
	player:SetAttribute("UiPreloadTotal", #list)
	local index = 1
	while index <= #list do
		local chunk = table.move(list, index, math.min(index + 11, #list), 1, {})
		pcall(function() provider:PreloadAsync(chunk) end)
		state.done += #chunk
		player:SetAttribute("UiPreloadDone", state.done)
		index += 12
	end
	state.finished = true
	player:SetAttribute("UiPreloaded", true)
end
task.spawn(Icons.preloadAll)

return Icons
