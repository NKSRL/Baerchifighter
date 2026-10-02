--!strict
-- BaerchiFactory.luau
-- ReplicatedStorage/Modules/BaerchiFactory.luau
--
-- Einzige Stelle an der eine Baerchi-Instanz entsteht.
-- Wichtig weil Types.Baerchi waechst: ein neues Pflichtfeld muss genau
-- hier gesetzt werden, nicht in jedem Service der Baerchis erzeugt
-- (EggService beim Hatchen, FusionService beim Fusionieren, spaeter Events).
--
-- Zustandslos bis auf den uid-Zaehler — kein Service, kein init().

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types            = require(ReplicatedStorage.Network.Types)
local BaerchiConfig    = require(ReplicatedStorage.Config.BaerchiConfig)
local PromotionConfig  = require(ReplicatedStorage.Config.PromotionConfig)
local CombatCalculator = require(ReplicatedStorage.Modules.CombatCalculator)

local BaerchiFactory = {}

-- Laufender Zaehler damit zwei Baerchis in derselben Sekunde nicht
-- dieselbe uid bekommen koennen (os.time() allein reicht dafuer nicht).
local _counter = 0

function BaerchiFactory.newUid(): string
	_counter += 1
	return string.format("b_%d_%d_%d", os.time(), _counter, math.random(1000, 9999))
end

export type CreateOptions = {
	level          : number?,   -- Standard: 1
	xp             : number?,   -- Standard: 0
	skillId        : string?,   -- Standard: defaultSkill aus BaerchiConfig
	isFusionResult : boolean?,  -- Standard: false
	fusionBonus    : number?,   -- Standard: 0

	-- Nur die Fusion setzt diese beiden (siehe FusionService, Regel 1 und 2).
	-- Ueberall sonst startet ein neuer Baerchi bei Null bzw. ohne Override.
	--
	-- promotionLevel und charms sind bewusst NICHT als Option vorgesehen: ein
	-- frisch entstandener Baerchi faengt bei Promotion 0 ohne Charms an, auch
	-- als Fusions-Ergebnis (bestaetigte Entscheidung, siehe FusionService).
	statLevels       : Types.StatLevels?,
	baseStatOverride : { hp: number?, atk: number?, spd: number?, pwr: number? }?,

	-- Welche Mutation dieser Baerchi hat (seit v11, ersetzt das fruehere
	-- isInverted: boolean).
	--
	-- Bewusst eine ausdrueckliche Angabe und KEIN Wurf hier drin: diese Fabrik
	-- wird auch von der Fusion und vom Debug-Service benutzt, und ein
	-- versteckter Wuerfelwurf mitten in einer Konstruktor-Funktion waere genau
	-- die Art Ueberraschung, die man beim Testen nie findet. Wer einen Wurf
	-- will, ruft BaerchiConfig.rollMutation() selbst auf — das tut derzeit
	-- genau eine Stelle: EggService beim Schluepfen.
	mutation         : Types.MutationId?,
}

-- Erstellt eine neue Baerchi-Instanz aus einem configId.
-- Gibt nil zurueck wenn der configId unbekannt ist — der Aufrufer entscheidet
-- ob das ein Fehler ist (Gacha-Roll) oder still ignoriert wird.
function BaerchiFactory.create(configId: string, options: CreateOptions?): Types.Baerchi?
	local def = BaerchiConfig.getById(configId)
	if not def then
		warn("[BaerchiFactory] Unbekannter configId:", configId)
		return nil
	end

	local opts: CreateOptions = options or {}

	local baerchi: Types.Baerchi = {
		uid            = BaerchiFactory.newUid(),
		configId       = configId,
		rarity         = def.rarity,
		level          = math.clamp(opts.level or 1, 1, BaerchiConfig.MAX_LEVEL),
		xp             = opts.xp or 0,
		skillId        = opts.skillId or def.defaultSkill,
		isFusionResult = opts.isFusionResult or false,
		fusionBonus    = opts.fusionBonus or 0,
		currentHp      = 0,   -- gleich unten auf volle HP gesetzt

		-- v8: zweite Fortschrittsachse. Promotion und Charms fangen IMMER bei
		-- Null an — auch bei einem Fusions-Ergebnis, damit gut gewuerfelte
		-- Charms sich nicht ueber Fusionen vervielfaeltigen lassen.
		promotionLevel = 0,
		statLevels     = opts.statLevels or PromotionConfig.newStatLevels(),
		charms         = {},

		baseStatOverride = opts.baseStatOverride,

		-- v11: Mutation. Standard nil (keine Mutation) — siehe CreateOptions,
		-- warum hier nicht gewuerfelt wird.
		mutation = opts.mutation,
	}

	-- Ein frischer Baerchi startet mit vollen HP. Der Wert wird bewusst ueber
	-- CombatCalculator geholt statt hier nachgerechnet: es gibt genau eine
	-- Formel fuer maxHp, und die steht dort.
	baerchi.currentHp = CombatCalculator.getEffectiveStats(baerchi, def.baseStats).maxHp

	return baerchi
end

return BaerchiFactory
