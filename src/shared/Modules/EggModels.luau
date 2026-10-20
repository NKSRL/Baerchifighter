--!strict
-- EggModels.luau
-- ReplicatedStorage/Modules/EggModels.luau
--
-- Einzige Zustaendigkeit:
--   - Welches fertige Ei-Modell (ReplicatedStorage.Assets.Eggs, aus den GLB-
--     Dateien importiert) zu welchem EggType gehoert, und wie eine Kopie davon
--     auf einen Ei-Koerper in der Welt gesetzt wird.
--
-- Die Modelle sind fertig gefaerbt (Textur auf dem Koerper, Gold/Edelsteine/
-- Konturen als Teilfarben, Leucht-Teile als Neon). Sie haben mehrere MeshParts
-- (7 bis 50; Ascension 35), deshalb setzt NUR DER CLIENT sie ein (LaidEggMeshController):
-- der Server baut weiter einen einzelnen unsichtbaren Koerper je Ei und bleibt
-- im Teile-Budget (<= 250 je Insel).
--
-- Eier ohne Modell behalten den alten Look (EggMesh + Gurte/Steine). Seit R2 haben
-- alle 21 Eier ein Modell (Nova, UFO-Jackpot aus den Teilen der anderen Eier + eigener Textur).
-- Schalter: FeatureFlags.EGG_MODELS_V1 (aus = alter Look fuer alle Eier).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FeatureFlags = require(ReplicatedStorage.Config.FeatureFlags)

local EggModels = {}

-- Modell-Name je EggType. Neue Eier: Modell nach Assets.Eggs legen und hier eintragen.
local TEMPLATE_NAME: { [string]: string } = {
	BasicEgg         = "Egg_Basic",
	SugarEgg         = "Egg_PinkBow",
	PlatinumEgg      = "Egg_Platinum",
	SunEgg           = "Egg_Blaze",
	CrystalEgg       = "Egg_Crystal",
	PrismEgg         = "Egg_Frost",
	AuroraEgg        = "Egg_Aurora",
	MistEgg          = "Egg_Mist",
	VoidEgg          = "Egg_Void",
	CometEgg         = "Egg_Comet",
	GalaxyEgg        = "Egg_Galaxy",
	TranscendenceEgg = "Egg_Transcendence",
	OmegaEgg         = "Egg_Omega",
	GoldenEgg        = "Egg_Goldenes",
	ZenithEgg        = "Egg_Zenit",
	ShadowEgg        = "Egg_Schatten",
	AbyssEgg         = "Egg_Abyss",
	EternityEgg      = "Egg_Ewigkeit",
	AscensionEgg     = "Egg_Ascension",
	NovaEgg          = "Egg_Nova",          -- R2 (16.10.)
	UfoJackpotEgg    = "Egg_UfoJackpot",    -- R2 (16.10.)
}

-- Wie gross das Modell gegenueber dem Koerper-Hoehe des gelegten Eis ist.
-- 1.1 = die Eier sind (mit Kontur und Zubehoer) etwas besser zu sehen, bleiben
-- aber klar kleiner als der Baerchi (2,7 Studs).
local MODEL_SCALE = 1.1

function EggModels.isEnabled(): boolean
	return FeatureFlags.isOn("EGG_MODELS_V1")
end

-- Hat dieser EggType ein Modell (und ist der Schalter an)?
function EggModels.has(eggId: string): boolean
	return TEMPLATE_NAME[eggId] ~= nil and EggModels.isEnabled()
end

-- Die Vorlage oder nil (Schalter aus, kein Modell, Assets noch nicht da).
function EggModels.getTemplate(eggId: string): Model?
	if not EggModels.has(eggId) then return nil end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Eggs")
	local template = folder and folder:FindFirstChild(TEMPLATE_NAME[eggId])
	if template and template:IsA("Model") and template.PrimaryPart then
		return template
	end
	return nil
end

-- Setzt `model` (Kopie einer Vorlage) so auf den Ei-Koerper `body`, dass der
-- Fuss am Boden bleibt und die Drehung des Koerpers uebernommen wird.
-- `factor` skaliert zusaetzlich (Pop-Animation, 1 = fertig).
-- Das Modell wird ueber seine Vorlage skaliert; `baseHeight` ist die Hoehe des
-- Ei-Koerpers (PrimaryPart) der UNskalierten Vorlage.
function EggModels.place(model: Model, baseHeight: number, body: BasePart, factor: number)
	local target   = body.Size.Y * MODEL_SCALE
	local scale    = target / baseHeight * factor
	model:ScaleTo(scale)
	local half     = baseHeight * scale * 0.5
	model:PivotTo(body.CFrame * CFrame.new(0, -body.Size.Y * 0.5 + half, 0))
end

return EggModels
