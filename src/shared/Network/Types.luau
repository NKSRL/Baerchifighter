--!strict
-- Types.luau
-- ReplicatedStorage/Network/Types.luau
--
-- Einzige Wahrheit fuer alle Datenstrukturen im Spiel.
-- Wird auf Server UND Client importiert.
-- Wenn sich ein Feld aendert, aendert es sich hier — nirgendwo sonst.

--------------------------------------------------------------------------------
-- Enums
--------------------------------------------------------------------------------

export type Rarity =
	| "Common"
	| "Uncommon"
	| "Rare"
	| "Epic"
	| "Legendary"
	| "Mythic"
	| "Divine"
	| "Cosmic"
	| "Secret"
	| "Godly"
	| "Eternal"
	| "Omega"

-- v14 (Mega Egg Tree): 20 Eier in einem Freischalt-Baum. Welches Ei zu
-- welchem Pfad gehoert und wie es frei wird, steht in EggConfig (TREE).
export type EggType =
	-- Stamm
	| "BasicEgg"
	| "SugarEgg"
	-- Gold-Pfad
	| "GoldenEgg"
	| "PlatinumEgg"
	| "SunEgg"
	| "ZenithEgg"
	-- Kristall-Pfad
	| "CrystalEgg"
	| "PrismEgg"
	| "AuroraEgg"
	-- Void-Pfad
	| "MistEgg"
	| "VoidEgg"
	| "ShadowEgg"
	| "AbyssEgg"
	-- Kosmos-Pfad
	| "CometEgg"
	| "NovaEgg"
	| "GalaxyEgg"
	-- Ascensions-Pfad (nur Rebirth)
	| "AscensionEgg"
	| "TranscendenceEgg"
	| "EternityEgg"
	| "OmegaEgg"

-- v14: die Pfade des Ei-Baums. Ein Pfad ist kein Upgrade, sondern ein
-- Spielziel (Gold = stark, Kristall = schnell, Void = selten, Kosmos =
-- Allrounder, Ascension = Rebirth). Siehe BaerchiConfig.PATHS.
export type PathId = "Stamm" | "Gold" | "Kristall" | "Void" | "Kosmos" | "Ascension"

-- v11: MUTATION-SYSTEM (ersetzt das binaere isInverted-Feld).
--
-- Acht Stufen statt einem einzigen Bonus — Namen und Werte (Multiplikator,
-- Farbe, Wuerfel-Gewicht) stehen NICHT hier, sondern in
-- Config/BaerchiConfig.MUTATIONS (dieselbe Trennung wie bei Rarity: Types
-- kennt nur die Werte-Menge, BaerchiConfig kennt die Bedeutung dahinter).
-- Aufsteigend sortiert nach Seltenheit/Staerke — BaerchiConfig.MUTATION_ORDER
-- haelt exakt diese Reihenfolge fuer Fusions-Vergleiche ("hoehere Stufe
-- gewinnt").
export type MutationId =
	| "Gold"
	| "Diamond"
	| "Bloodrot"
	| "Celestial"
	| "Candy"
	| "Lava"
	| "Galaxy"
	| "Rainbow"

-- Gebaeude sind seit v4 reine HONIG-Produzenten: jedes stellt regelmaessig
-- einen Honig her und lagert eine begrenzte Menge davon. Ein Honig an einen
-- Baerchi verfuettert heilt ihn und gibt XP — die einzige XP-Quelle im Spiel
-- (Kaempfe geben keine XP mehr).
--
-- Seit v7 hat jedes der drei eine EIGENE Rolle, und nur noch eine Datei weiss
-- welche: Config/BuildingBehavior.luau. Kurz:
--   Beehive     Vorrat    — groesseres Lager, schnellere Produktion
--   HoneyPot    Heilung   — SEIN Honig heilt mehr HP
--   HoneyPress  Wachstum  — hebt die XP JEDES Honigs, egal woher er kommt
--
-- Die Daten unten sind davon unberuehrt: was ein Gebaeude kann, ergibt sich
-- aus id + level. Deshalb brauchte v7 keine neuen Felder und keine Migration.
export type BuildingId =
	| "Beehive"      -- Bienenstock
	| "HoneyPot"     -- Honigtopf
	| "HoneyPress"   -- Honig-Presse
-- Fusion ist seit v3 kein Gebaeude mehr — sie laeuft rein ueber GUI
-- (FusionPanel/BaerchiInventory) und ist von Anfang an freigeschaltet.
-- Recycling ist seit v4 ebenfalls eine reine GUI-Funktion mit festem Wert
-- (EconomyConfig.RECYCLE_RETURN). Eier werden seit v12 sofort geoeffnet,
-- es gibt keine Brut-Slots mehr.

export type SkillId = string  -- "SugarRush", "GummySmash", "BearHug", etc.
                               -- String damit neue Skills nur Config-Eintraege sind

-- Rarity eines BATTLE-CHARMS. Bewusst eine eigene Kette, nicht Types.Rarity:
-- ein Charm hat andere Stufen als ein Baerchi ("Super Rare", "Ascended"), und
-- die Odds der einen duerfen sich nicht verschieben, wenn jemand die andere
-- erweitert. Zahlen und Farben stehen in Config/CharmConfig.
export type CharmRarity =
	| "Common"
	| "Uncommon"
	| "Rare"
	| "SuperRare"
	| "Legendary"
	| "Ascended"

-- Ein einzelner ausgeruesteter Battle-Charm.
--
-- Der Slot steht IM Eintrag statt als Tabellen-Schluessel: eine Lua-Tabelle mit
-- Luecken in den Zahlen-Schluesseln ({[1]=..., [5]=...}) laesst sich nicht in
-- einem DataStore ablegen. Baerchi.charms ist deshalb eine dichte Liste, in der
-- nur die tatsaechlich gewuerfelten Slots vorkommen — nach `slot` sortiert.
export type Charm = {
	slot   : number,        -- 1-8, siehe CharmConfig.SLOT_COUNT
	rarity : CharmRarity,   -- erster Wurf
	statId : string,        -- zweiter Wurf, Eintrag aus CharmConfig.STAT_POOL
	value  : number,        -- konkreter Bonus (Faktor bzw. flacher Wert, siehe STAT_POOL.mode)
	locked : boolean,       -- vom Spieler gegen erneutes Wuerfeln gesperrt
}

-- Fortschritt JEDES EINZELNEN Stats durch Event-Teilnahme, gedeckelt durch die
-- rarity-abhaengige Obergrenze (PromotionConfig.STAT_CAP). Voellig getrennt von
-- Baerchi.level, das ueber Honig/XP waechst — zwei unabhaengige Achsen.
--
-- Seit v10 sind alle fuenf echt: `egg` war lange ein Balken ohne Wirkung, weil
-- es das Ei-Legen noch nicht gab. Jetzt beschleunigt es das Legen (siehe
-- EggConfig.LAY_STAT_LEVEL_GAIN).
export type StatLevels = {
	hp  : number,
	atk : number,
	spd : number,   -- Angriffsgeschwindigkeit
	pwr : number,   -- Ability-Staerke (skaliert den Skill-Schaden)
	egg : number,   -- Lege-Tempo (siehe EggCalculator)
}

--------------------------------------------------------------------------------
-- Kern-Einheit: Baerchi
--------------------------------------------------------------------------------

export type Baerchi = {
	uid            : string,   -- eindeutige Instanz-ID ("b_1721abc...")
	configId       : string,   -- Schluessel in BaerchiConfig ("RedBaerchi", "GoldenGrizzly")
	rarity         : Rarity,
	level          : number,   -- 1 - BaerchiConfig.MAX_LEVEL
	xp             : number,   -- XP-Fortschritt zum naechsten Level
	skillId        : SkillId,  -- aktiver Skill (durch Fusion ueberschreibbar)
	isFusionResult : boolean,  -- fuer UI-Badge "FUSION"
	fusionBonus    : number,   -- 0.0 = kein Bonus, 0.25 = +25% HP/ATK
	                           -- wird beim Fusionieren gesetzt (EconomyConfig.FUSION_STAT_BONUS)
	                           -- und von CombatCalculator.getEffectiveStats angewendet
	currentHp      : number,   -- aktuelle Lebenspunkte, bleiben zwischen PIT-Laeufen
	                           -- stehen. 0 = erschoepft, der Baerchi kann erst
	                           -- wieder kaempfen wenn er mit Honig gefuettert wurde.
	                           -- Obergrenze ist maxHp aus getEffectiveStats.

	-- v8: die zweite Fortschrittsachse (siehe Config/PromotionConfig).
	promotionLevel : number,       -- 0 - PromotionConfig.MAX_PROMOTION, angezeigt als 5 Sterne
	statLevels     : StatLevels,   -- waechst durch Event-Teilnahme
	charms         : { Charm },    -- dichte Liste, nach slot sortiert (siehe Charm)

	-- v8: nur bei einem FUSIONS-Ergebnis gesetzt, sonst nil.
	--
	-- Basiswerte haengen sonst ausschliesslich am configId
	-- (BaerchiConfig.data[configId].baseStats). Seit der neuen Fusions-Regel
	-- ("pro Stat der bessere der beiden Eltern") kann ein Fusions-Ergebnis aber
	-- hoehere Basiswerte tragen, als sein eigener configId hergibt — genau
	-- dafuer ist dieses Feld da.
	--
	-- CombatCalculator.getEffectiveStats bevorzugt die hier gesetzten Werte.
	-- Fuer JEDEN nicht fusionierten Baerchi bleibt das Feld nil und das
	-- Verhalten unveraendert.
	baseStatOverride : {
		hp  : number?,
		atk : number?,
		spd : number?,
		pwr : number?,
	}?,

	-- v11: MUTATION (ersetzt das fruehere binaere isInverted-Feld aus v9).
	--
	-- Eine seltene Variante JEDES Baerchis (Wurf beim Schluepfen:
	-- BaerchiConfig.rollMutation()), diesmal GESTUFT statt binaer: acht
	-- Stufen mit steigendem Stat-Multiplikator, steigender Seltenheit und
	-- eigener Farbe/Leuchten (siehe BaerchiConfig.MUTATIONS). nil = keine
	-- Mutation, der weit ueberwiegende Normalfall.
	--
	-- Bewusst ein eigenes Feld und KEINE eigene Rarity: die Rarity steuert
	-- Gacha-Gewichte, Stat-Obergrenzen, Fusions-Kette und Farben. Mutation an
	-- sie zu haengen haette all das mitverbogen — derselbe Grund wie zuvor bei
	-- Inverted, nur jetzt mit mehr als zwei moeglichen Zustaenden.
	mutation : MutationId?,
}

--------------------------------------------------------------------------------
-- Insel-Daten
--------------------------------------------------------------------------------

export type Building = {
	id    : BuildingId,
	level : number,   -- 1-10, bestimmt die XP pro Honig aus diesem Gebaeude

	-- Eingelagerter Honig, 0 .. EconomyConfig.HONEY_CAPACITY.
	honey : number,

	-- os.time() des zuletzt ANGERECHNETEN Honigs. Die Produktion laeuft nicht
	-- ueber einen Timer sondern wird aus dieser Zeitmarke nachgerechnet
	-- (gleiches Prinzip wie HatchingEgg.readyAt) — dadurch produzieren die
	-- Gebaeude auch waehrend der Spieler offline ist, ohne Server-Loop.
	lastProducedAt : number,
}

-- v12: Brut-Slots (HatchingEgg, island.hatchingEggs) sind entfallen. Ein Ei
-- aus dem Lager wird per Klick sofort geoeffnet (EggService.openEgg). Die
-- Migration in PlayerService legt laufende Bruten alter Spielstaende zurueck
-- ins Lager.

-- v12: Stand des letzten PIT-Laufs fuer die Fortsetzungs-Frage.
--
-- reachedStage ist die letzte Stage, in die der Baerchi EINGETRETEN ist
-- (verloren oder beim Zurueckholen die gerade gespielte). Gilt nur fuer das
-- PIT-Level, auf dem der Lauf stattfand: auf einem anderen Level stehen
-- andere Gegner in denselben Stage-Nummern. Ein PIT-Ausbau oder Rebirth
-- loescht den Eintrag.
export type PitProgress = {
	pitLevel     : number,
	reachedStage : number,
}

-- Ein GELEGTES Ei: liegt sichtbar in der Welt und wartet darauf, angeklickt zu
-- werden. Erst beim Einsammeln wird daraus ein Eintrag in eggStock, der sich
-- ausbrueten laesst.
--
-- Die Position steht als drei Zahlen drin, nicht als Vector3: ein DataStore
-- kann nur einfache Werte speichern, ein Vector3 waere beim naechsten Laden
-- verschwunden.
--
-- Warum das Ei ueberhaupt eine Position hat: es wird dort abgelegt, wo der
-- Baerchi im Moment des Legens stand. Wer seinen Baerchi zum Honig-Teich und
-- zurueck laufen laesst, findet danach eine Spur aus Eiern — genau das ist
-- gewollt.
export type LaidEgg = {
	uid     : string,     -- eindeutig, wird zum Einsammeln benutzt
	eggType : EggType,
	laidAt  : number,     -- os.time(), nur fuer die Anzeige ("gerade eben")
	x       : number,
	y       : number,     -- Fusspunkt, das Ei sitzt mit seiner Unterkante darauf
	z       : number,
}

export type IslandData = {
	pitLevel     : number,                    -- Schichtanzahl der Kampfplattform
	buildings    : { [BuildingId]: Building },
	baerchis     : { [string]: Baerchi },     -- key = Baerchi.uid
	eggStock     : { [EggType]: number },     -- Eier im Lager (Legen, Events, Rebirth, Haendler)

	-- Der EINE Baerchi, der auf dem Plot steht: laeuft selbststaendig zum
	-- Honig-Teich, in den PIT und wieder zurueck. Alle anderen bleiben reiner
	-- Inventar-Datensatz und werden nicht in der Welt gebaut (MapService
	-- rendert ausschliesslich diesen). nil = noch keiner ausgeruestet (leerer
	-- Plot) — kommt nur direkt nach dem ersten Ei oder nach einem Rebirth vor,
	-- IslandService ruestet den ersten geschluepften Baerchi automatisch aus.
	equippedUid  : string?,

	-- v10: Eier, die der ausgeruestete Baerchi gelegt hat und die noch
	-- herumliegen. Gedeckelt durch EggConfig.MAX_UNCOLLECTED_EGGS.
	laidEggs : { LaidEgg },

	-- os.time() des zuletzt ANGERECHNETEN Eis. Genau wie
	-- Building.lastProducedAt: die Produktion laeuft nicht ueber einen Timer,
	-- sondern wird aus dieser Zeitmarke nachgerechnet — dadurch legt der
	-- Baerchi auch waehrend der Spieler offline ist weiter (langsamer, siehe
	-- EggConfig.OFFLINE_SLOWDOWN) und es braucht keinen Server-Loop dafuer.
	lastEggAt : number,

	-- v12: letzter PIT-Lauf (Fortsetzungs-Frage). nil = kein Lauf auf diesem
	-- PIT-Level gespeichert, der Dialog erscheint dann nicht.
	pitProgress : PitProgress?,
}

--------------------------------------------------------------------------------
-- Lokalisierte Nachrichten (Server → Client)
--------------------------------------------------------------------------------

-- Der Server formuliert nie einen Satz. Er schickt einen Schluessel plus Zahlen
-- bzw. Namen, der Client baut daraus den Text in der Sprache des Spielers
-- (siehe Localization/Loc). Ein Argument darf selbst wieder eine LocMsg sein,
-- damit z.B. ein Eiername in der Sprache des Spielers eingesetzt wird.
--
-- Konvention fuer Schluessel: "err.*" fuer abgelehnte Aktionen, "msg.*" fuer
-- Meldungen, "ui.*" fuer feste Beschriftungen. Die Texte stehen ausschliesslich
-- in Localization/Strings/<sprache>.luau.
export type LocArg = string | number | LocMsg
export type LocMsg = {
	k : string,                      -- Schluessel
	a : { [string]: LocArg }?,       -- Platzhalter-Werte
}

--------------------------------------------------------------------------------
-- Quests und Index (v13)
--------------------------------------------------------------------------------

-- Gespeicherter Quest-Stand. Gespeichert wird bewusst NUR, was sich nicht aus
-- den Spielzaehlern ableiten laesst: wie viele Kettenquests schon abgeholt
-- wurden, und der Tagesstand. Den Fortschritt selbst rechnet QuestProgress
-- jedes Mal frisch aus data.stats / island — so gibt es keine zweite Wahrheit,
-- die auseinanderlaufen kann, und kein anderer Service muss Quests kennen.
export type QuestBaseline = {
	hatched     : number,
	fightsWon   : number,
	gummies     : number,
}

export type QuestState = {
	chainClaimed : number,                    -- Kettenquests, die schon abgeholt sind
	day          : number,                    -- Tagesnummer (UTC), siehe QuestConfig.dayOf
	baseline     : QuestBaseline,             -- Zaehlerstand zu Tagesbeginn
	dailyClaimed : { [string]: boolean },     -- abgeholte Tages-Quests von `day`
}

-- Eine Zeile in der Quest-Anzeige (Server -> Client). Keine Texte: der Client
-- baut sie aus der id (Schluessel "quest.<id>.title").
export type QuestEntry = {
	id       : string,
	kind     : string,   -- "chain" | "daily"
	progress : number,   -- schon auf `target` gedeckelt
	target   : number,
	claimed  : boolean,
}

export type QuestView = {
	chain      : QuestEntry?,   -- aktuelle Kettenquest, nil = Kette komplett
	chainDone  : number,        -- wie viele der Kette erledigt sind
	chainTotal : number,
	daily      : { QuestEntry },
	dailyResetIn : number,      -- Sekunden bis zum naechsten Tageswechsel
}

-- Belohnungs-Meldung (Server -> Client), fuer den Toast.
export type QuestReward = {
	questId : string,
	gummies : number,
	eggType : EggType?,
}

--------------------------------------------------------------------------------
-- Ei-Baum (v14)
--------------------------------------------------------------------------------

-- Fortschritt im Ei-Baum. Liegt bewusst AUSSERHALB von island: ein Rebirth
-- setzt die Insel zurueck, den Baum aber nicht — er ist der lange Grind.
--
--   unlocked   Eier, deren Knoten frei ist (einmal frei, immer frei)
--   hatched    wie oft jedes Ei schon geoeffnet wurde (Freischalt-Bedingung)
--   pressed    wie oft jedes Ei in der Ei-Presse entstanden ist (Statistik)
--   blueprints Blaupausen aus Events, noch nicht eingesetzt
--   bypass     Knoten, deren Hatch- und Index-Bedingung eine Blaupause
--              ersetzt hat (das Rebirth-Gate gilt trotzdem)
export type EggTreeState = {
	unlocked   : { [string]: boolean },
	hatched    : { [string]: number },
	pressed    : { [string]: number },
	blueprints : number,
	bypass     : { [string]: boolean },
}

--------------------------------------------------------------------------------
-- Spieler-Rang
--------------------------------------------------------------------------------

export type Rank = {
	tier   : number,  -- 1, 2, 3 ...
	name   : string,  -- "Gummy Hatchling", "Sugar Brawler", "Golden Champion" ...
	points : number,  -- Rangpunkte (PvP Arena)
}

--------------------------------------------------------------------------------
-- PlayerData — alles was im DataStore landet
--------------------------------------------------------------------------------

export type PlayerData = {
	-- Schema
	version    : number,   -- fuer Migrationen beim Laden alter Daten
	createdAt  : number,   -- Unix-Timestamp
	lastSeenAt : number,   -- fuer Offline-Gummy-Farm-Berechnung

	-- Waehrungen
	gummies     : number,  -- aktiv: durch PIT-Kaempfe und Tower
	goldGummies : number,  -- Premium: PIT-Meilensteine, Events

	-- Progression
	rebirthCount : number,   -- Anzahl Rebirths
	rebirthMult  : number,   -- Earnings-Multiplikator (1.0 → 1.5 → 2.25 ...)
	rank         : Rank,

	-- Gewaehlte Sprache ("de" | "en" | "fr" | "es"). nil = der Spieler hat nie
	-- gewaehlt, es gilt die Roblox-Sprache seines Clients. Bewusst OHNE
	-- Versions-Sprung: ein fehlendes Feld liest sich in Lua ohnehin als nil
	-- und bedeutet genau "automatisch" (wie equippedUid in v6).
	language     : string?,

	-- Insel
	island : IslandData,

	-- Nur serverseitig relevant (wird nicht an Client gesendet)
	stats : {
		totalGummiesEarned  : number,
		totalFightsWon      : number,
		totalFightsLost     : number,
		totalFusions        : number,
		totalRebirths       : number,
		totalRecycled       : number,
		highestPitLevel     : number,
		highestTowerFloor   : number,
		totalHatched        : number,   -- v13: geoeffnete Eier (Quest-Zaehler)
	},

	-- v13: Index. Jede configId, die der Spieler je besessen hat (auch nach
	-- Recycling/Fusion/Rebirth). Wird nie geleert.
	discovered : { [string]: boolean },

	-- v13: Quest-Stand
	quests : QuestState,

	-- v14: Ei-Baum (ueberlebt Rebirths)
	eggTree : EggTreeState,
}

--------------------------------------------------------------------------------
-- Netzwerk-Typen (Server → Client Updates)
--------------------------------------------------------------------------------

-- Wird nach jeder relevanten Aenderung gefeuert.
-- Stats werden bewusst weggelassen (kein Leak sensibler Serverdaten).
export type PlayerDataUpdate = {
	gummies      : number,
	goldGummies  : number,
	rebirthCount : number,
	rebirthMult  : number,
	rank         : Rank,
	language     : string?,
	island       : IslandData,
	discovered   : { [string]: boolean },
	quests       : QuestView,
	eggTree      : EggTreeState,   -- v14
}

-- Eine einzelne Kampf-AKTION (v14: Runden-Log). Bleibt serverseitig in
-- CombatCalculator und wird NICHT komplett an den Client geschickt: ein
-- PIT-Lauf hat viele Stages, das ganze Protokoll waere ein Vielfaches der
-- Nutzlast. Der Client bekommt pro Stage nur die Zusammenfassung
-- (PitStageResult.skillUses / firstSkillRound) — genug fuer die SkillFX.
--
-- Seit v14 handelt jeder Kaempfer nach seiner SPD (siehe CombatCalculator),
-- ein Eintrag ist deshalb EINE Aktion von A oder B, nicht mehr eine
-- Doppelrunde.
export type RoundLogEntry = {
	roundNumber     : number,     -- wievielte Aktion von A (der Baerchi)
	actor           : string,     -- "A" | "B"
	-- v15: was in diesem Zug passiert ist: "hit" (Stoss), "skill"
	-- (Faehigkeit), "burst" (Feuerstoss nach Letzter Chance), "stunned"
	kind            : string,
	chargeA         : number,     -- v15: Ladestand von A nach dem Zug (0..1)
	skillUsed       : boolean,
	skillId         : string?,
	damage          : number,     -- wirklich abgezogene HP beim Ziel
	heal            : number,
	absorbed        : number,     -- vom Schild abgefangen
	effects         : { string }?, -- "stun", "slow", "dot", "burn:12", "laststand" ...
	attackerHpAfter : number,     -- HP von A nach der Aktion
	defenderHpAfter : number,     -- HP von B nach der Aktion
}

-- v15: ein Zug fuer die WIEDERGABE in der Arena (aus RoundLogEntry
-- verdichtet). Bleibt serverseitig: CombatService baut die Liste,
-- PitArenaService spielt sie ab (Stoesse, Faehigkeiten, Lebens- und
-- Ladeleisten). HP und Ladung als Anteil 0..1, damit die Leisten direkt
-- gesetzt werden koennen.
export type FightBeat = {
	actor   : string,    -- "A" = der Baerchi, "B" = der Gegner
	kind    : string,    -- "hit" | "skill" | "burst" | "stunned"
	selfHp  : number,    -- HP des Baerchis nach dem Zug (0..1)
	enemyHp : number,    -- HP des Gegners nach dem Zug (0..1)
	charge  : number,    -- Ladestand der Faehigkeit des Baerchis (0..1)
	skillId : string?,   -- bei "skill"/"burst"
}

-- Eine bestandene (oder verlorene) Stage innerhalb eines PIT-Laufs.
export type PitStageResult = {
	stage      : number,
	won        : boolean,
	rounds     : number,
	hpAfter    : number,   -- HP des Baerchis NACH dieser Stage
	gummiesWon : number,
	-- v14: fuer die Fähigkeiten-Animation (SkillFX)
	skillUses       : number?,   -- wie oft der Skill in dieser Stage kam
	firstSkillRound : number?,   -- erste Aktion mit Skill (nil = keiner)
}

-- Ergebnis eines kompletten PIT-Laufs.
--
-- Ein Lauf ist kein einzelner Kampf mehr: der Baerchi kaempft Stage fuer
-- Stage weiter, solange er ueberlebt. Seine HP werden zwischen den Stages
-- NICHT zurueckgesetzt — der Lauf endet erst wenn er verliert. Danach steht
-- er erschoepft (hpAfter, meist 0) auf dem Plot und muss mit Honig
-- hochgefuettert werden.
export type PitRunResult = {
	baerchiUid    : string,
	startStage    : number,           -- v12: erste gespielte Stage (1 = von vorn, sonst Fortsetzung)
	recalled      : boolean,          -- v12: true = vom Spieler nach einer Stage zurueckgeholt
	corrected     : boolean?,         -- v12: true = nachgeschicktes, gekuerztes Ergebnis nach dem Zurueckholen
	stagesCleared : number,           -- wie viele Stages gewonnen wurden
	stages        : { PitStageResult },
	gummiesWon    : number,           -- Summe ueber alle Stages, bereits mit rebirthMult
	goldGummiesWon: number,           -- Meilenstein-Belohnung (siehe EconomyConfig)
	hpBefore      : number,           -- HP mit denen der Lauf gestartet wurde
	hpAfter       : number,
	maxHp         : number,
}

-- Ergebnis einer Fuetterung: ein Honig heilt und gibt XP.
export type FeedResult = {
	baerchiUid : string,
	buildingId : BuildingId,   -- aus welchem Gebaeude der Honig kam
	hpGained   : number,
	xpGained   : number,
	leveledUp  : boolean,
	newLevel   : number,
	hpAfter    : number,
	maxHp      : number,
}

export type HatchResult = {
	eggType  : EggType,
	baerchi  : Baerchi,
	isNew    : boolean,   -- erstes Mal dieser configId → besondere Animation
}

-- Ergebnis eines Charm-Wurfs, eines Events oder einer Fusion enthaelt den
-- Baerchi selbst — `mutation` steht dort mit drin, ein eigener Typ dafuer
-- waere ueberfluessig.

export type FusionResult = {
	resultBaerchi : Baerchi,
	consumedUids  : { string },
}

export type RecycleResult = {
	consumedUid   : string,
	gummiesGained : number,
	goldGummiesGained : number,
}

-- Ergebnis einer Befoerderung (PromotionService).
export type PromotionResult = {
	baerchiUid       : string,
	newPromotion     : number,      -- 1 - PromotionConfig.MAX_PROMOTION
	consumedUids     : { string },  -- die verbrauchten Duplikate
	unlockedSlots    : { number },  -- Charm-Slots, die durch DIESE Stufe dazukamen
}

-- Ergebnis eines Charm-Wurf-Pakets (CharmService).
--
-- `rolls` ist die Anzahl der tatsaechlich durchgefuehrten Wuerfe: bei einem
-- Auto-Roll kann sie kleiner sein als angefragt, wenn zwischendurch die
-- GoldGummies ausgehen. Der Client zeigt genau diese Zahl an, nicht die
-- angefragte — sonst behauptet die Oberflaeche etwas, das nicht passiert ist.
export type CharmRollResult = {
	baerchiUid       : string,
	rolls            : number,
	goldGummiesSpent : number,
	charms           : { Charm },   -- Stand NACH allen Wuerfen
}

-- Ein gelegtes Ei wurde eingesammelt (fuer den Toast beim Spieler).
export type EggCollectResult = {
	eggUid   : string,
	eggType  : EggType,
	inStock  : number,   -- wie viele von dieser Sorte jetzt im Lager liegen
}

-- Beim Join nachgerechnete Eier aus der Abwesenheit. Wird zusammen mit dem
-- Honig-Bericht gezeigt (siehe OfflineReport) — aber als eigener Typ, weil
-- die beiden Systeme sonst aneinander haengen wuerden.
export type OfflineEggReport = {
	laid        : number,   -- wie viele Eier nachgelegt wurden
	skipped     : boolean,  -- true wenn die Obergrenze das Nachlegen gebremst hat
	secondsAway : number,
}

-- Was eine Event-Teilnahme gebracht hat (EventParticipationService).
--
-- Heisst weiterhin "StatGain", weil die Stat-Stufe der Kern der Belohnung ist —
-- seit dem Event-Katalog (EventConfig) kann aber zusaetzlich ein Bonus dazu
-- kommen, und in einem Fall NUR der Bonus.
export type EventStatGain = {
	baerchiUid : string,
	eventId    : string,

	-- Welcher Stat gestiegen ist ("hp" | "atk" | "spd" | "pwr" | "egg").
	--
	-- nil heisst: es gab KEINE Stat-Stufe, weil bereits jeder Stat dieses
	-- Baerchis an seiner Rarity-Obergrenze steht. Der Bonus unten wurde
	-- trotzdem vergeben — deshalb ist das kein Fehlerfall, und der Client muss
	-- diesen Fall anzeigen koennen statt ihn zu verwerfen.
	statKey    : string?,
	newLevel   : number,   -- 0, wenn statKey nil ist
	cap        : number,

	-- Der Zusatz-Ertrag dieses Events als fertiger Text ("+1x Goldenes Ei").
	-- nil = dieses Event hatte keinen Bonus, oder der Wurf ging daneben
	-- (Mutations-Sturm). Bewusst als Text und nicht als Zahlenfeld pro
	-- Bonus-Art: der Client zeigt ihn nur an, und die Formulierung soll an
	-- EINER Stelle stehen (EventConfig.describeBonus bzw. der Ausgabe-Text in
	-- EventParticipationService).
	bonusText  : string?,

	-- Gesetzt, wenn der Baerchi durch dieses Event eine (bessere) Mutation
	-- bekommen hat — der seltenste Ausgang im ganzen Event-System, deshalb als
	-- eigenes Feld statt nur im Text: der Client faerbt den Hinweis damit ein.
	mutation   : MutationId?,

	-- true: Zwischenmeldung WAEHREND eines Events (UFO-Kampf, Fund, Entfuehrung)
	-- statt Abschlussmeldung. Der Client zeigt dann nur `bonusText`.
	midEvent   : boolean?,

	-- Neue Rarity, falls das UFO den Baerchi aufsteigen liess.
	rarityUp   : string?,
}

export type RebirthResult = {
	newRebirthCount : number,
	newMultiplier   : number,
	ascensionEggs   : number,   -- Summe aller Meilenstein-Eier (0 = keine), fuer alte Anzeigen
	-- v14: Meilenstein-Eier nach Sorte (Ascension, Transzendenz, Ewigkeit, Omega)
	milestoneEggs   : { { eggType: EggType, count: number } }?,
}

-- v14: ein Knoten im Ei-Baum ist frei geworden (fuer den Toast).
export type EggUnlockResult = {
	eggType : EggType,
	reason  : string,    -- "tree" | "blueprint" | "rebirth" | "migration"
}

-- v14: Ergebnis der Ei-Presse.
export type EggPressResult = {
	fromEgg : EggType,
	toEgg   : EggType,
	used    : number,
}

-- Offline-Ertrag beim Join (Server → Client, direkt nach dem ersten Sync).
-- Seit v4 ist das der Honig, den die Gebaeude waehrend der Abwesenheit
-- produziert haben — gedeckelt durch EconomyConfig.HONEY_CAPACITY pro
-- Gebaeude, laenger weg bringt also nichts zusaetzlich.
export type OfflineReport = {
	secondsAway  : number,
	honeyGained  : number,
}

--------------------------------------------------------------------------------
-- Default-Fabrik (nur PlayerService darf dies aufrufen)
--------------------------------------------------------------------------------

local function createDefaultPlayerData(): PlayerData
	local now = os.time()

	return {
		-- v11: das binaere isInverted-Feld weicht dem gestuften Mutation-System
		-- (siehe Baerchi.mutation und BaerchiConfig.MUTATIONS). Die Migration in
		-- PlayerService bildet alte isInverted=true-Eintraege auf eine feste
		-- Mutation ab und entfernt das alte Feld — DAS ist der Grund, warum
		-- diese Zahl steigen MUSS: es wird wieder etwas ENTFERNT, nicht nur
		-- ein fehlendes Feld angelegt (dieselbe Konvention wie beim v9-Sprung).
		--
		-- v10: der ausgeruestete Baerchi legt Eier. Neu sind island.laidEggs
		-- und island.lastEggAt; die Migration legt beide an.
		--
		-- v9: DEF ist ersatzlos entfallen, PWR (Ability-Staerke) ist an seine
		-- Stelle getreten, und jeder Baerchi hat ein isInverted-Feld bekommen.
		-- Die Migration in PlayerService raeumt dafuer die alten def-Eintraege
		-- aus statLevels und baseStatOverride weg — DAS ist der Grund, warum
		-- diese Zahl steigen MUSS: die Migration entfernt etwas, statt nur ein
		-- fehlendes Feld anzulegen.
		--
		-- v8: jeder Baerchi hat drei neue Felder bekommen (promotionLevel,
		-- statLevels, charms) plus das optionale baseStatOverride. Die
		-- zugehoerige Migration in PlayerService legt sie auf bestehenden
		-- Baerchis an — sie erkennt fehlende Felder selbst und ist deshalb
		-- gefahrlos wiederholbar.
		--
		-- v7: eigene Rolle pro Gebaeude. KEIN neues Feld — die Zahl stieg
		-- trotzdem, weil die zugehoerige Migration in PlayerService einen Wert
		-- UMRECHNET (die Presse erbt einmalig das hoechste Gebaeude-Level) und
		-- deshalb genau einmal laufen darf.
		-- v13: Quests + Index. Neu: discovered, quests, stats.totalHatched. Die
		-- Migration seedet discovered aus den vorhandenen Baerchis und setzt
		-- totalHatched auf deren Anzahl, damit Veteranen nicht bei null starten.
		-- v12: Brut-Slots entfallen (Eier werden sofort geoeffnet), die
		-- Migration legt laufende Bruten zurueck ins Lager und ENTFERNT
		-- island.hatchingEggs. Neu: island.pitProgress (optional).
		version    = 14,  -- v14: Ei-Baum, v13: Quests + Index (discovered, quests, stats.totalHatched), v12: Sofort-Oeffnen + pitProgress, v11: Mutation-System (v10: Eier legen, v9: PWR statt DEF + Inverted, v8: Promotion/Charms/Stat-Level, v7: Gebaeude-Rollen, v6: equippedUid, v5: Ei-uid, v4: Honig-Gebaeude + currentHp)
		createdAt  = now,
		lastSeenAt = now,

		gummies     = 100,
		goldGummies = 0,

		rebirthCount = 0,
		rebirthMult  = 1.0,

		rank = {
			tier   = 1,
			name   = "Gummy Hatchling",
			points = 0,
		},

		island = {
			pitLevel  = 1,
			-- Alle drei Honig-Gebaeude stehen ab dem ersten Join auf dem Plot
			-- und fangen sofort an zu produzieren.
			buildings = {
				Beehive    = { id = "Beehive",    level = 1, honey = 0, lastProducedAt = now },
				HoneyPot   = { id = "HoneyPot",   level = 1, honey = 0, lastProducedAt = now },
				HoneyPress = { id = "HoneyPress", level = 1, honey = 0, lastProducedAt = now },
			},
			baerchis     = {},
			eggStock     = {
				BasicEgg = 3,  -- Starter-Eier fuer den ersten Join
			},
			equippedUid  = nil,   -- noch kein Baerchi da, der ausgeruestet sein koennte

			laidEggs  = {},
			lastEggAt = now,
		},

		stats = {
			totalGummiesEarned  = 0,
			totalFightsWon      = 0,
			totalFightsLost     = 0,
			totalFusions        = 0,
			totalRebirths       = 0,
			totalRecycled       = 0,
			highestPitLevel     = 1,
			highestTowerFloor   = 0,
			totalHatched        = 0,
		},

		discovered = {},

		eggTree = {
			unlocked   = { BasicEgg = true, SugarEgg = true },
			hatched    = {},
			pressed    = {},
			blueprints = 0,
			bypass     = {},
		},

		quests = {
			chainClaimed = 0,
			day          = 0,   -- 0 = noch nie gesetzt; QuestService setzt beim Join den Tag
			baseline     = { hatched = 0, fightsWon = 0, gummies = 0 },
			dailyClaimed = {},
		},
	}
end

return {
	createDefaultPlayerData = createDefaultPlayerData,
}