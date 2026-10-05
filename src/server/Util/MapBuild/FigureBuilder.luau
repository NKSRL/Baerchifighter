--!strict
-- FigureBuilder.luau
-- ServerScriptService/Util/MapBuild/FigureBuilder.luau
--
-- Einzige Zustaendigkeit:
--   - Die sichtbare Figur des ausgeruesteten Baerchis bauen und ihren Zustand
--     (Namensschild, HP, erschoepft) anzeigen
--
-- Es gibt pro Plot nur EINE Figur: die des ausgeruesteten Baerchis. Alle
-- anderen Baerchis sind reine Inventar-Daten.
--
-- Teil von MapService: nur MapService (und die Builder untereinander)
-- benutzen dieses Modul. Es aendert keine Spielerdaten.

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MapConfig        = require(ReplicatedStorage.Config.MapConfig)
local MapLayout = require(ReplicatedStorage.Modules.MapLayout)
local BaerchiConfig    = require(ReplicatedStorage.Config.BaerchiConfig)
local BaerchiMesh      = require(ReplicatedStorage.Modules.BaerchiMesh)
local CombatCalculator = require(ReplicatedStorage.Modules.CombatCalculator)
local Types            = require(ReplicatedStorage.Network.Types)

local FigureFX         = require(ServerScriptService.Util.FigureFX)

local MapParts = require(ServerScriptService.Util.MapBuild.MapParts)

local FigureBuilder = {}

-- Beschriftung und Erschoepfungs-Zustand einer bereits stehenden Figur.
-- Getrennt vom Aufbau, weil sich HP staendig aendern und ein kompletter
-- Neuaufbau der Mesh-Figuren dafuer viel zu teuer waere.
function FigureBuilder.writeFigureState(model: Model, rawHp: number, maxHp: number)
	local hp        = math.clamp(rawHp, 0, maxHp)
	local exhausted = hp <= 0

	local label = model:FindFirstChild("Health", true)
	if label and label:IsA("TextLabel") then
		label.Text = if exhausted
			then "erschoepft"
			else string.format("%d / %d HP", hp, maxHp)

		label.TextColor3 = if exhausted
			then Color3.fromRGB(255, 120, 120)
			elseif hp < maxHp * 0.34 then Color3.fromRGB(255, 205, 110)
			else Color3.fromRGB(190, 245, 195)
	end

	-- Ein erschoepfter Baerchi wird matt. Bewusst nicht komplett durchsichtig:
	-- er ist ausser Gefecht, nicht weg.
	--
	-- Die urspruengliche Transparenz jedes Teils steht als Attribut daran
	-- (gesetzt beim Aufbau). Sie einfach auf 0 zurueckzusetzen wuerde sonst
	-- absichtliche Durchsichtigkeit im importierten Modell zerstoeren — der
	-- Gummy-Baer ist genau dafuer ein Beispiel.
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local stored = part:GetAttribute("BaseTransparency")
			local base   = if typeof(stored) == "number" then stored else 0

			part.Transparency = if exhausted
				then math.max(base, MapConfig.BAERCHI_EXHAUSTED_TRANSPARENCY)
				else base
		end
	end
end

-- Wie writeFigureState, aber respektiert einen laufenden PIT-Kampf.
--
-- Waehrend eines Laufs gehoert die Figur dem PitArenaService: der Kampf ist
-- serverseitig schon ausgerechnet und die HP stehen bereits auf dem Endwert,
-- waehrend die Wiedergabe in der Arena noch laeuft. Wuerde hier
-- dazwischengeschrieben, saehe der Baerchi ab der ersten Sekunde erschoepft
-- aus statt am Ende. PitArenaService zieht den Zustand selbst nach.
function FigureBuilder.writeBaerchiState(model: Model, baerchi: Types.Baerchi, maxHp: number)
	if model:GetAttribute("InArena") == true then
		return
	end

	FigureBuilder.writeFigureState(model, baerchi.currentHp, maxHp)
end

-- Eine Baerchi-Figur: das geklonte Pet-Mesh aus BaerchiMesh.build. Welches
-- Modell das ist (eigenes fuer diese Rarity oder der gemeinsame Platzhalter)
-- und ob es eingefaerbt wird, entscheidet BaerchiMesh selbst.
--
-- JEDE BasePart der Figur traegt das Attribut "BaerchiUid" und einen eigenen
-- ClickDetector — bei einem Mesh aus mehreren Teilen waere ein einzelner
-- Hitbereich schwer zu treffen. Der Client (WorldController) liest das
-- Attribut beim Klick und schlaegt die Details in seinem eigenen Datenstand
-- nach — dafuer braucht es kein zusaetzliches Remote.
--
-- Fehlt das Mesh-Template noch, gibt BaerchiMesh.build nil zurueck — dann
-- wird diese eine Figur uebersprungen, der Rest des Plots baut sich normal.
function FigureBuilder.buildBaerchiFigure(parent: Instance, baerchi: Types.Baerchi, footPos: Vector3, facing: CFrame): Model?
	local color = BaerchiConfig.getRarityColor(baerchi.rarity)
	local def   = BaerchiConfig.getById(baerchi.configId)

	-- Ein MUTIERTER Baerchi (seit v11, ersetzt das fruehere binaere Inverted)
	-- bekommt die Farbe seiner Mutations-Stufe und leuchtet (siehe
	-- BaerchiMesh.build). Fuer alle anderen ist der vierte Parameter nil und
	-- es aendert sich nichts.
	local mutationColor = if baerchi.mutation
		then BaerchiConfig.getMutationColor(baerchi.mutation)
		else nil

	local model = BaerchiMesh.build(footPos, color, baerchi.rarity, mutationColor)
	if not model then
		return nil
	end
	model.Name = "Baerchi_" .. baerchi.uid

	-- BaerchiMesh stellt die Figur achsen-parallel hin. Hier wird sie noch in
	-- die Blickrichtung des Plots gedreht — und zwar um die senkrechte Achse
	-- DURCH footPos, nicht um den Modell-Pivot: wo der Pivot im importierten
	-- Mesh liegt, weiss dieses Modul nicht, eine Drehung darum wuerde die
	-- Figur seitlich wegschieben.
	local rotation = facing.Rotation
	local toOrigin = CFrame.new(-footPos)
	model:PivotTo(CFrame.new(footPos) * rotation * toOrigin * model:GetPivot())

	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part:SetAttribute("BaerchiUid", baerchi.uid)

			-- Ausgangs-Transparenz merken, damit der Erschoepfungs-Zustand
			-- sie spaeter nicht ueberschreibt (siehe writeBaerchiState).
			part:SetAttribute("BaseTransparency", part.Transparency)

			local click = Instance.new("ClickDetector")
			click.MaxActivationDistance = MapConfig.BAERCHI_CLICK_DISTANCE
			click.Parent = part
		end
	end

	-- Rarity-Aura: ab Rare ein dezentes Dauer-Glitzern, ab Epic zusaetzlich ein
	-- PointLight. Nutzt dieselbe Farbe wie die Koerpereinfaerbung
	-- (BaerchiConfig.getRarityColor) — Seltenheit soll auch aus der Distanz auf
	-- einen Blick erkennbar sein, nicht erst beim Ranschauen des Namensschilds.
	-- Siehe DESIGN_VORSCHLAG_TRENDANALYSE_2026-09-11.md Abschnitt 5.
	--
	-- Haengt an EINEM zentralen Part (nicht an jedem BasePart wie der
	-- ClickDetector oben): ein Glitzern pro Teilstueck des Mesh saehe wie ein
	-- Funkensturm aus, nicht wie eine Aura.
	local auraAnchor = (model.PrimaryPart :: BasePart?) or (model:FindFirstChildWhichIsA("BasePart", true) :: BasePart?)
	if auraAnchor then
		local rarityKey = baerchi.rarity :: string

		if MapConfig.RARITY_AURA_MIN_SPARKLE[rarityKey] then
			local sparkle = Instance.new("ParticleEmitter")
			sparkle.Name          = "RarityAura"
			sparkle.Texture       = "rbxasset://textures/particles/sparkles_main.dds"
			sparkle.Color         = ColorSequence.new(color)
			sparkle.Size          = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.35),
				NumberSequenceKeypoint.new(1, 0),
			})
			sparkle.Transparency  = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.3),
				NumberSequenceKeypoint.new(1, 1),
			})
			sparkle.Lifetime      = NumberRange.new(0.8, 1.4)
			sparkle.Speed         = NumberRange.new(1, 3)
			sparkle.SpreadAngle   = Vector2.new(180, 180)
			sparkle.Rate          = MapConfig.RARITY_AURA_PARTICLE_RATE
			sparkle.Parent        = auraAnchor
		end

		if MapConfig.RARITY_AURA_MIN_LIGHT[rarityKey] then
			local light = Instance.new("PointLight")
			light.Name       = "RarityAuraLight"
			light.Color      = color
			light.Range      = MapConfig.RARITY_AURA_LIGHT_RANGE
			light.Brightness = MapConfig.RARITY_AURA_LIGHT_BRIGHTNESS
			light.Parent     = auraAnchor
		end

		-- Mutations-Aura (seit v11): unabhaengig von der Rarity-Aura oben, weil
		-- eine Mutation auch einen Common treffen kann, der sonst nie eine Aura
		-- haette. JEDE Mutation bekommt zumindest ein Punktlicht in ihrer
		-- eigenen Farbe; ab Multiplikator 4x (Celestial/Candy/Lava/Galaxy/
		-- Rainbow — siehe BaerchiConfig.MUTATIONS) zusaetzlich ein dichteres
		-- Glitzern, damit die seltensten Baerchis im Spiel auch aus der
		-- Distanz sofort als etwas Besonderes auffallen.
		if baerchi.mutation then
			local mutColor = BaerchiConfig.getMutationColor(baerchi.mutation)

			local mutLight = Instance.new("PointLight")
			mutLight.Name       = "MutationAuraLight"
			mutLight.Color      = mutColor
			mutLight.Range      = MapConfig.RARITY_AURA_LIGHT_RANGE
			mutLight.Brightness = MapConfig.RARITY_AURA_LIGHT_BRIGHTNESS * 1.5
			mutLight.Parent     = auraAnchor

			if BaerchiConfig.getMutationMultiplier(baerchi.mutation) >= 4 then
				local mutSparkle = Instance.new("ParticleEmitter")
				mutSparkle.Name          = "MutationAura"
				mutSparkle.Texture       = "rbxasset://textures/particles/sparkles_main.dds"
				mutSparkle.Color         = ColorSequence.new(mutColor)
				mutSparkle.Size          = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.5),
					NumberSequenceKeypoint.new(1, 0),
				})
				mutSparkle.Transparency  = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.15),
					NumberSequenceKeypoint.new(1, 1),
				})
				mutSparkle.Lifetime      = NumberRange.new(1.0, 1.8)
				mutSparkle.Speed         = NumberRange.new(2, 5)
				mutSparkle.SpreadAngle   = Vector2.new(180, 180)
				mutSparkle.Rate          = MapConfig.RARITY_AURA_PARTICLE_RATE * 2
				mutSparkle.Parent        = auraAnchor
			end
		end
	end

	-- Namensschild ueber dem Kopf (faellt auf den Body zurueck, falls das
	-- Template keinen Part namens "head" hat). Rekursiv gesucht: der Importer
	-- packt die Teile in eine Zwischen-Gruppe.
	--
	-- Drei Zeilen statt zwei seit dem Ei-Legen: Name+Level, HP, und ganz unten
	-- der Ei-Timer. Der Ei-Timer-Text wird HIER nur als leeres Label angelegt —
	-- befuellt wird er rein clientseitig (EggTimerController), weil er
	-- sekuendlich weiterzaehlt und dafuer keine Serverlast noetig ist (siehe
	-- Kommentar-Kopf dort).
	local labelAnchor = (model:FindFirstChild("head", true) :: BasePart?) or model.PrimaryPart
	if labelAnchor then
		-- Sammel-Update 1.4 ("Naechstes Ei in: ist im Baerchi und braucht mehr
		-- Space"): breiter und hoeher (laengere Texte auf Franzoesisch/
		-- Spanisch), und der Abstand kommt aus der echten Oberkante der Figur
		-- (welt-ausgerichtet) statt aus der am body gedrehten Bounding-Box —
		-- das Schild sitzt damit immer UEBER dem Kopf, nie darin.
		local billboard = Instance.new("BillboardGui")
		billboard.Name        = "Label"
		billboard.Size        = UDim2.fromScale(MapConfig.FIGURE_LABEL.width, MapConfig.FIGURE_LABEL.height)
		local _, topY = BaerchiMesh.worldBoundsY(model)
		local anchorY = labelAnchor.Position.Y
		local aboveHead = if topY then math.max(0, (topY :: number) - anchorY) else BaerchiMesh.getHeight(model) * 0.55
		billboard.StudsOffset = Vector3.new(0, aboveHead + MapConfig.FIGURE_LABEL.height * 0.5 + MapConfig.FIGURE_LABEL.gap, 0)
		billboard.AlwaysOnTop = false
		billboard.MaxDistance = MapConfig.BAERCHI_CLICK_DISTANCE
		billboard.Adornee     = labelAnchor
		billboard.Parent      = labelAnchor

		local name = MapParts.newTextLabel("Name", billboard, UDim2.fromScale(1, 0.34), UDim2.fromScale(0, 0))
		name.Text = string.format(
			"%s%s  Lv.%d",
			-- Das Namensschild ist die zweite Stelle, an der eine Mutation
			-- auffaellt (die erste ist die leuchtende Mutations-Farbe der
			-- Figur selbst). Beides zusammen, weil die Farbe allein bei einer
			-- Rarity mit ungewohnter Palette nicht eindeutig genug waere —
			-- und weil ein Spieler lesen koennen soll, WELCHE der acht Stufen
			-- es genau ist (die Farbe allein verraet das nicht zuverlaessig).
			if baerchi.mutation then BaerchiConfig.getMutationBadge(baerchi.mutation) .. " " else "",
			def and def.displayName or baerchi.configId,
			baerchi.level
		)

		if baerchi.mutation then
			name.TextColor3 = BaerchiConfig.getMutationColor(baerchi.mutation)
		end

		MapParts.newTextLabel("Health", billboard, UDim2.fromScale(1, 0.28), UDim2.fromScale(0, 0.34))

		-- Ei-Timer bekommt die groesste Zeile: er ist der laengste Text.
		local eggTimer = MapParts.newTextLabel("EggTimer", billboard, UDim2.fromScale(1, 0.38), UDim2.fromScale(0, 0.62))
		eggTimer.TextColor3 = Color3.fromRGB(255, 224, 140)   -- Ei-Gold, passend zur HUD-Farbwelt
		eggTimer.Text        = ""   -- EggTimerController fuellt das im ersten Tick
	end

	model.Parent = parent
	return model
end

-- Maximale HP eines Baerchis. Liegt hier statt inline, weil sowohl der Aufbau
-- als auch die In-Place-Aktualisierung sie brauchen.
function FigureBuilder.maxHpOf(baerchi: Types.Baerchi): number
	local def = BaerchiConfig.getById(baerchi.configId)
	if not def then return 1 end

	return CombatCalculator.getEffectiveStats(baerchi, def.baseStats).maxHp
end

-- Baut die sichtbare Baerchi-Figur eines Plots neu: seit dem Equip-System
-- steht dort hoechstens EINE — der ausgeruestete Baerchi. Alle anderen sind
-- reiner Inventar-Datensatz und werden nicht in die Welt gebaut. Ist keiner
-- ausgeruestet (leerer Plot, z.B. direkt nach einem Rebirth), bleibt der
-- Ordner einfach leer.
function FigureBuilder.renderBaerchis(plotModel: Model, slot: number, islandData: Types.IslandData)
	local old = plotModel:FindFirstChild("Baerchis")
	if old then old:Destroy() end

	local folder = Instance.new("Folder")
	folder.Name   = "Baerchis"
	folder.Parent = plotModel

	local equippedUid = islandData.equippedUid
	local equipped = if equippedUid then islandData.baerchis[equippedUid] else nil
	if not equipped then
		return
	end

	local plotCFrame = MapParts.plotCFrame(slot)
	local home       = MapLayout.baerchiHomeOffset()   -- HONEY_POND_V2: am Becken
	local footPos    = (plotCFrame * CFrame.new(home.X, MapParts.plotSurfaceOffset() + home.Y, home.Z)).Position

	local figure = FigureBuilder.buildBaerchiFigure(folder, equipped, footPos, plotCFrame)
	if figure then
		FigureBuilder.writeBaerchiState(figure, equipped, FigureBuilder.maxHpOf(equipped))

		-- Eine frisch gebaute Figur steht — also atmet sie. Wer sie danach
		-- selbst bewegt (PitArenaService, BaerchiAutopilotService), meldet sie
		-- vorher ab und danach wieder an. Die alte Figur ist eine Zeile weiter
		-- oben zerstoert worden; ihr Registry-Eintrag raeumt sich beim
		-- naechsten Durchlauf des Idle-Loops selbst weg.
		FigureFX.idleBob(figure, {
			height = MapConfig.IDLE_BOB_HEIGHT,
			rate   = MapConfig.IDLE_BOB_RATE,
		})
	end
end

return FigureBuilder
