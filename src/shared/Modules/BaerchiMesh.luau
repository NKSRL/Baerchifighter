--!strict
-- BaerchiMesh.luau
-- ReplicatedStorage/Modules/BaerchiMesh.luau
--
-- Einzige Zustaendigkeit:
--   - Eine sichtbare Baerchi-Figur aus dem passenden importierten Pet-Mesh
--     klonen, ggf. einfaerben und im Raum positionieren.
--
-- Ersetzt das fruehere prozedurale BaerchiRig (Parts aus Konfig-Zahlen
-- zusammengesetzt) durch echte gemeshte Modelle (blockybearpet.glb,
-- gummybearpet.glb, ...). Jedes Modell liegt als .rbxm in
-- ReplicatedStorage/Assets — Rojo synct lose .rbxm/.rbxmx-Dateien in einem
-- $path-Ordner automatisch als Instanz, benannt nach dem Dateinamen.
--
-- MEHRERE MODELLE PRO RARITY (statt einem Modell fuer alle 6 Rarities):
--   - "BaerchiTemplate_<Rarity>" (z.B. "BaerchiTemplate_Uncommon") wird
--     genutzt wenn vorhanden — das ist ein bewusst fuer genau diese Rarity
--     gestaltetes Modell und bleibt in seiner ORIGINAL-Farbe (kein Tinting).
--   - Rarities OHNE eigenes Modell fallen auf das gemeinsame
--     "BaerchiTemplate" zurueck und werden mit der Rarity-Farbe eingefaerbt
--     (Platzhalter, bis ein eigenes Modell da ist).
--   - Ausnahme: Common selbst benutzt "BaerchiTemplate" (keine Rarity-
--     Endung noetig, das IST das Standardmodell) und bleibt IMMER in
--     Original-Farbe, nie eingefaerbt.
-- Ein neues Modell fuer eine weitere Rarity braucht also KEINE Code-
-- Aenderung: einfach "BaerchiTemplate_<Rarity>.rbxm" nach
-- src/shared/Assets/ legen (siehe Setup-Schritt unten) — ab dann wird diese
-- Rarity automatisch nicht mehr eingefaerbt.
--
-- Fell-Teile (im GLB mit den "fur"/"candy"-artigen Materialien) werden bei
-- Platzhalter-Rarities mit der Rarity-Farbe eingefaerbt. Schnauze, Nase,
-- Mund und Augen bleiben in JEDEM Modell unangetastet — das ist die
-- Wiedererkennung als eine Marke, nicht die Rarity-Farbe (gleiches Prinzip
-- wie zuvor bei BaerchiRig.SignatureColors).
--
-- ============================================================
-- EINMALIGER SETUP-SCHRITT IN STUDIO PRO MODELL (kann ich nicht
-- automatisieren, weil ich Studio nicht selbst bedienen kann):
--   1. Die .glb-Datei ueber den 3D-Importer in ein leeres Model laden.
--   2. Pruefen, dass die Teile so heissen wie unten in FUR_PART_NAMES:
--      head, ear_left, ear_right, snout, nose, mouth, eye_white_left,
--      eye_pupil_left, eye_white_right, eye_pupil_right, body, leg_left,
--      leg_right. Falls der Importer Namen aendert/dedupliziert (z.B.
--      "head_1"), hier in FUR_PART_NAMES nachziehen.
--   3. Das Model umbenennen:
--        Common     → "BaerchiTemplate"            (Standardmodell, kein Suffix)
--        Uncommon   → "BaerchiTemplate_Uncommon"
--        Rare       → "BaerchiTemplate_Rare"        (folgt bald)
--        usw.
--      und als .rbxm exportieren nach src/shared/Assets/<Name>.rbxm.
--   4. Rojo synct das automatisch als ReplicatedStorage.Assets.<Name>.
-- Fehlt fuer eine Rarity sowohl ihr eigenes Modell als auch das gemeinsame
-- "BaerchiTemplate": BaerchiMesh.build gibt nil zurueck und warnt einmal
-- pro Rarity, die Insel baut sich sonst normal (nur ohne diese Baerchis).
-- ============================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapConfig = require(ReplicatedStorage.Config.MapConfig)
local Types      = require(ReplicatedStorage.Network.Types)

local BaerchiMesh = {}

-- Eigene Baerchis sind etwas groesser als das Template, damit sie neben den
-- gelegten Eiern (EGG_SCALE im LaidEggBuilder) klar die Hauptfigur bleiben.
local BAERCHI_SCALE = 1.15

-- Namen der Parts/MeshParts die die Fellfarbe bekommen (nur bei Platzhalter-
-- Rarities relevant, siehe Kommentar-Kopf). Muss mit den Node-Namen in
-- JEDEM importierten GLB uebereinstimmen (siehe Setup-Schritt oben) —
-- bisher bei blockybearpet.glb und gummybearpet.glb identisch.
local FUR_PART_NAMES: { [string]: boolean } = {
	head      = true,
	ear_left  = true,
	ear_right = true,
	body      = true,
	leg_left  = true,
	leg_right = true,
}

type Resolved = { model: Model, isDedicated: boolean }
local _resolved: { [string]: Resolved } = {}
local _warnedMissing: { [string]: boolean } = {}

-- Findet das Template fuer eine Rarity und ob es ihr EIGENES ist (dann keine
-- Faerbung) oder der gemeinsame Platzhalter (dann Faerbung mit Rarity-Farbe).
local function resolveTemplate(rarity: Types.Rarity): (Model?, boolean)
	local cached = _resolved[rarity]
	if cached then
		return cached.model, cached.isDedicated
	end

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		return nil, false
	end

	local dedicated = assets:FindFirstChild("BaerchiTemplate_" .. rarity)
	if dedicated and dedicated:IsA("Model") then
		_resolved[rarity] = { model = dedicated, isDedicated = true }
		return dedicated, true
	end

	local fallback = assets:FindFirstChild("BaerchiTemplate")
	if fallback and fallback:IsA("Model") then
		-- Common IST das Standardmodell (kein eigenes "_Common"-Asset noetig)
		-- und bleibt deshalb immer unveraendert. Alle anderen Rarities ohne
		-- eigenes Modell sind hier nur Platzhalter → Faerbung.
		local isDedicated = (rarity == "Common")
		_resolved[rarity] = { model = fallback, isDedicated = isDedicated }
		return fallback, isDedicated
	end

	return nil, false
end

-- Klont ein Template, richtet die Teile her und faerbt optional das Fell.
-- Gemeinsamer Kern von build() und buildEnemy() — der Unterschied zwischen
-- den beiden ist nur, WELCHES Template genommen und OB eingefaerbt wird.
local function cloneAndPrepare(template: Model, furColor: Color3?): Model
	local model = template:Clone()
	model.Name  = "BaerchiMesh"

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true

			-- Bewusst solide (nicht CanCollide=false wie z.B. Deko-Teile):
			-- der Spieler soll sich auf seinen Baerchi draufstellen koennen,
			-- statt durch ihn hindurchzulaufen. Anchored+CanCollide blockiert
			-- zwar Spieler-Charaktere, stoesst aber selbst nichts an — zwei
			-- solide Baerchi-Figuren (z.B. eigener Baerchi und PIT-Gegner)
			-- koennen sich deshalb trotzdem ueberlappend positionieren, ohne
			-- dass sich beide gegenseitig wegschieben.
			descendant.CanCollide = true

			if furColor and FUR_PART_NAMES[descendant.Name] then
				descendant.Color = furColor
			end
		end
	end

	-- Rekursiv suchen: der Importer packt die eigentlichen Teile oft in eine
	-- zusaetzliche Zwischen-Gruppe (z.B. "blocky_bear_pet"), "body" ist also
	-- meist kein direktes Kind des Root-Models.
	if not model.PrimaryPart then
		local body = model:FindFirstChild("body", true)
		if body and body:IsA("BasePart") then
			model.PrimaryPart = body
		end
	end

	-- Blickrichtung (10.10.2026): Alle Lauf- und Kampf-Bewegungen drehen die
	-- Figur ueber ihren Pivot (FigurePlacement/FigureWalker: -Z = vorwaerts).
	-- Liegt die Schnauze eines importierten Modells hinter dem Pivot (+Z),
	-- liefe jede Figur rueckwaerts. Dann den Pivot um 180 Grad drehen —
	-- die Teile selbst bleiben, wo sie sind.
	local face = model:FindFirstChild("snout", true) or model:FindFirstChild("nose", true)
	local primary = model.PrimaryPart
	if face and face:IsA("BasePart") and primary then
		if model:GetPivot():PointToObjectSpace(face.Position).Z > 0 then
			primary.PivotOffset = primary.PivotOffset * CFrame.Angles(0, math.pi, 0)
		end
	end

	return model
end

-- Stellt ein Modell so hin, dass die Unterkante seiner Bounding-Box auf
-- footPos steht. Die Fusshoehe kommt damit aus dem echten Mesh und nicht aus
-- einer Konfig-Zahl — das funktioniert unabhaengig davon wie gross oder klein
-- das exportierte Modell tatsaechlich ist.
--
-- Sammel-Update 1.2 ("kleine Figuren stecken in den Tower-Platten"):
-- Model:GetBoundingBox() ist nach dem PrimaryPart (body) ausgerichtet, nicht
-- nach der Welt. Ist der body eines importierten Modells gekippt (bei den
-- Rarity-eigenen Modellen unterschiedlich), ist size.Y gar nicht die Hoehe —
-- die berechnete Unterkante liegt dann zu hoch oder zu tief, und kleine
-- Figuren verschwinden in der Platte. Die Unterkante kommt deshalb aus den
-- WELT-ausgerichteten Grenzen jedes sichtbaren Teils (worldBottomY).
function BaerchiMesh.worldBoundsY(model: Model): (number?, number?)
	local bottom: number? = nil
	local top: number? = nil
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local cf, sz = d.CFrame, d.Size
			local halfY = 0.5 * (
				math.abs(cf.RightVector.Y) * sz.X
				+ math.abs(cf.UpVector.Y) * sz.Y
				+ math.abs(cf.LookVector.Y) * sz.Z
			)
			local lo, hi = cf.Position.Y - halfY, cf.Position.Y + halfY
			if bottom == nil or lo < (bottom :: number) then bottom = lo end
			if top == nil or hi > (top :: number) then top = hi end
		end
	end
	return bottom, top
end

function BaerchiMesh.worldBottomY(model: Model): number?
	local bottom = BaerchiMesh.worldBoundsY(model)
	return bottom
end

local function standOn(model: Model, footPos: Vector3)
	local boundingCFrame, size = model:GetBoundingBox()
	local bottomY = BaerchiMesh.worldBottomY(model) or (boundingCFrame.Position.Y - size.Y * 0.5)
	local offset  = footPos - Vector3.new(boundingCFrame.Position.X, bottomY, boundingCFrame.Position.Z)
	model:PivotTo(model:GetPivot() + offset)
end

-- Macht eine Figur als MUTIERT erkennbar (seit v11 — ersetzt das fruehere
-- binaere "Inverted", derselbe visuelle Mechanismus, jetzt mit der Farbe der
-- getroffenen Mutations-Stufe statt der festen Komplementaerfarbe).
--
-- Zwei Dinge zusammen, weil eines allein nicht reicht:
--   1. Fell auf die Farbe der Mutations-Stufe (BaerchiConfig.getMutationColor).
--   2. Material auf Neon — die Figur leuchtet.
--
-- Warum die Faerbung hier nochmal passiert, obwohl cloneAndPrepare das schon
-- kann: fuer eine Rarity MIT eigenem Modell faerbt cloneAndPrepare bewusst
-- gar nicht (isDedicated). Ein mutierter Legendary saehe damit exakt aus wie
-- ein normaler — die eine Sache, die auf keinen Fall passieren darf, wenn ein
-- Baerchi eine der seltenen Mutations-Stufen trifft. Deshalb setzt sich eine
-- Mutation auch ueber ein eigenes Modell hinweg.
local function markMutation(model: Model, mutationColor: Color3)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and FUR_PART_NAMES[descendant.Name] then
			descendant.Color    = mutationColor
			descendant.Material = Enum.Material.Neon
		end
	end
end

-- Klont das passende Template fuer diese Rarity, faerbt es falls es nur ein
-- Platzhalter ist, und stellt es bei footPos auf den Boden (Y = Fusshoehe,
-- XZ = Mitte der Standflaeche). Gibt nil zurueck wenn kein Template
-- existiert — MapService faengt das ab.
--
-- `mutationColor` ist gesetzt, wenn dieser Baerchi eine Mutation hat (der
-- Aufrufer holt die Farbe aus BaerchiConfig.getMutationColor). nil = normaler,
-- unmutierter Baerchi.
function BaerchiMesh.build(
	footPos: Vector3,
	rarityColor: Color3,
	rarity: Types.Rarity,
	mutationColor: Color3?
): Model?
	local template, isDedicated = resolveTemplate(rarity)
	if not template then
		if not _warnedMissing[rarity] then
			warn(
				"[BaerchiMesh] Kein Template fuer Rarity " .. rarity .. " gefunden",
				"(weder ReplicatedStorage.Assets.BaerchiTemplate_" .. rarity .. " noch .BaerchiTemplate) —",
				"Baerchis dieser Rarity werden nicht gebaut. Siehe Kommentar-Kopf in BaerchiMesh.luau."
			)
			_warnedMissing[rarity] = true
		end
		return nil
	end

	local model = cloneAndPrepare(template, if isDedicated then nil else rarityColor)
	model:ScaleTo(model:GetScale() * BAERCHI_SCALE)   -- relativ: das Template traegt schon einen eigenen Massstab

	if mutationColor then
		markMutation(model, mutationColor)
	end

	standOn(model, footPos)

	return model
end

-- Baut eine GEGNER-Figur fuer die PIT-Arena: immer das Standard-Modell,
-- immer eingefaerbt.
--
-- Bewusst getrennt von build(): ein Gegner hat keine Rarity, und er soll sich
-- auf den ersten Blick vom eigenen Baerchi unterscheiden — deshalb nie ein
-- Rarity-eigenes Modell, egal welches gerade importiert ist.
function BaerchiMesh.buildEnemy(footPos: Vector3, color: Color3): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local template = assets and assets:FindFirstChild("BaerchiTemplate")

	if not template or not template:IsA("Model") then
		-- Eigene Warnung noetig: build() warnt nur wenn fuer eine Rarity
		-- WEDER ein eigenes NOCH das Standard-Modell existiert. Haben alle
		-- Baerchis eines Spielers ein Rarity-eigenes Modell, faellt das
		-- fehlende Standard-Modell dort gar nicht auf — und der PIT-Kampf
		-- liefe dann ohne jeden Gegner ab, ohne Hinweis irgendwo.
		if not _warnedMissing["__enemy"] then
			warn(
				"[BaerchiMesh] ReplicatedStorage.Assets.BaerchiTemplate fehlt —",
				"die PIT-Gegner werden nicht gebaut. Das Standard-Modell wird",
				"auch dann gebraucht wenn jede Rarity ein eigenes hat."
			)
			_warnedMissing["__enemy"] = true
		end
		return nil
	end

	local model = cloneAndPrepare(template, color)
	model.Name  = "Enemy"
	standOn(model, footPos)

	return model
end

-- Hoehe der Figur (fuer den Billboard-Offset des Namensschilds). Nutzt die
-- echte Bounding-Box statt einer Konfig-Zahl. Faellt auf
-- MapConfig.BAERCHI_FALLBACK_HEIGHT zurueck, falls das Template kaputt/leer
-- importiert wurde (Bounding-Box-Hoehe 0) — sonst wuerde das Namensschild
-- im Boden des Baerchis stecken.
function BaerchiMesh.getHeight(model: Model): number
	local _, size = model:GetBoundingBox()
	if size.Y <= 0 then
		return MapConfig.BAERCHI_FALLBACK_HEIGHT
	end
	return size.Y
end

return BaerchiMesh
