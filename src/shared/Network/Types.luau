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

local HoneyPondMode = require(script.Parent.Parent.Modules.HoneyPondMode)
local FeatureFlags  = require(script.Parent.Parent.Config.FeatureFlags)

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
	-- Sonder-Eier ausserhalb des Baums (EggConfig: special = true)
	| "UfoJackpotEgg"

-- v14: die Pfade des Ei-Baums. Ein Pfad ist kein Upgrade, sondern ein
-- Spielziel (Gold = stark, Kristall = schnell, Void = selten, Kosmos =
-- Allrounder, Ascension = Rebirth). Siehe BaerchiConfig.PATHS.
export type PathId = "Stamm" | "Gold" | "Kristall" | "Void" | "Kosmos" | "Ascension"
	| "Event"   -- Sonder-Eier aus Events (nicht im Baum, nie freischaltbar)

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
-- Seit v15 (Gebaeude Option B) sind es noch ZWEI Honig-Gebaeude, und nur eine
-- Datei weiss, was sie koennen: Config/BuildingBehavior.luau. Kurz:
--   Beehive       Vorrat   — groesseres Lager, schnellere Produktion
--   HoneyRefiner  Veredeln — sein Level hebt Heilung UND XP jedes Honigs
--                            (verschmolzen aus Honigtopf und Honig-Presse;
--                            "Honig-Veredler" ist ein Platzhalter-Name)
-- Das dritte Gebaeude, der Waben-Recycler, liegt in island.recycler.
--
-- Level 1-60 (EconomyConfig.MAX_BUILDING_LEVEL), Look-Stufe aus dem Level
-- (BuildingBehavior.getLook).
--
-- Seit dem Honig-Teich (FeatureFlags.HONEY_POND_V2) ist es EIN Gebaeude:
--   HoneyPond     Honig-Teich — kann alles, was Stock und Veredler zusammen
--                 koennen; seine Looks wachsen bis zum Honig-Springbrunnen.
-- Die jeweils nicht aktiven liegen in IslandData.retiredBuildings
-- (Modules/HoneyPondMode).
export type BuildingId =
	| "Beehive"        -- Bienenstock
	| "HoneyRefiner"   -- Honig-Veredler (Platzhalter-Name)
	| "HoneyPond"      -- Honig-Teich (HONEY_POND_V2)
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
	endlessLevel   : number?,  -- Paket 9: Level ueber MAX_LEVEL (nil = 0), bleibt ueber Rebirths
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
	level : number,   -- 1 .. EconomyConfig.MAX_BUILDING_LEVEL (60)

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
-- Migration (Util/PlayerMigration) legt laufende Bruten alter Spielstaende zurueck
-- ins Lager.

-- v15: TOWER-SYSTEM (ersetzt das PIT-Level).
--
-- Vier Tower mit eigener Stage-Zahl und eigenem Gegner-Wachstum, Zahlen in
-- Config/TowerConfig. "I" Holz (30 Stages), "II" Stein (45), "III" Gold (60),
-- "Final" Kristall (100).
export type TowerId = "I" | "II" | "III" | "Final" | "Endless"   -- Endless: HBB Paket 9

-- Permanenter Tower-Fortschritt. Liegt bewusst AUSSERHALB von island (wie
-- eggTree): ein Rebirth setzt die Insel zurueck, Rekorde und abgeholte
-- Meilensteine bleiben.
--
--   records      beste geschaffte Stage je Tower (zaehlt nur bis zum Deckel
--                des jeweiligen Rebirths, siehe TowerConfig.getStageCap)
--   claimed      abgeholte Meilenstein-Stages je Tower. Die Stage steht als
--                TEXT-Schluessel ("5", "10"): eine Lua-Tabelle mit Luecken in
--                Zahlen-Schluesseln laesst sich nicht im DataStore ablegen
--                (derselbe Grund wie bei Baerchi.charms).
--   highestTower hoechster je erreichte Tower (Look des Turms, Abzeichen)
--   selected     der Tower, in den der Fight-Knopf schickt
export type TowerState = {
	records      : { [string]: number },
	claimed      : { [string]: { [string]: boolean } },
	highestTower : string,
	selected     : string,
	endlessWeek  : { week: number, best: number }?, -- Paket 9: beste Endless-Stage der Woche
}

-- v15: Taeglicher Login-Bonus (Config/LoginBonusConfig). Tage zaehlen nach
-- UTC (os.time() // 86400). streak = wie viele Tage des 7-Tage-Zyklus schon
-- abgeholt sind (0-7); lastClaimDay = UTC-Tag der letzten Abholung (0 = nie).
export type DailyState = {
	lastClaimDay : number,
	streak       : number,
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

-- v15: der Waben-Recycler vor der Basis (siehe Config/CombConfig). Er nimmt die
-- Waben, die der Spieler im Event-Pit gesammelt hat, in eine Warteschlange und
-- verwandelt sie nach und nach in Gummies. Wie Building.lastProducedAt laeuft
-- das ueber eine Zeitmarke und nicht ueber einen Timer, damit er auch offline
-- weiterarbeitet.
export type RecyclerData = {
	level           : number,   -- 1 .. CombConfig.RECYCLER_MAX_LEVEL
	queued          : number,   -- Wabeneinheiten, die noch verarbeitet werden muessen
	progress        : number,   -- angefangene Einheit (0 .. <1), damit keine Bruchteile verloren gehen
	lastProcessedAt : number,   -- os.time() der letzten Verrechnung
}

export type IslandData = {
	buildings    : { [BuildingId]: Building },
	-- HONEY_POND_V2: Gebaeude, die im aktuellen Modus nicht gelten (Teich
	-- bzw. Stock + Veredler). Bleiben erhalten, kommen beim Zurueckschalten
	-- wieder (Modules/HoneyPondMode). nil = keine.
	retiredBuildings : { [BuildingId]: Building }?,
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

	-- v15: Waben-Recycler (Level 1-60 + Warteschlange).
	recycler : RecyclerData,

	-- v15: letzte erreichte Stage je Tower fuer die Fortsetzungs-Frage
	-- (ersetzt pitProgress). Schluessel = TowerId. Gehoert zur Insel, weil ein
	-- Rebirth den Baerchi auf Level 1 setzt und ein alter Einstieg dann
	-- sinnlos waere.
	towerProgress : { [string]: number },

	-- v15: Erstattung fuer gekaufte PIT-Level (Migration v14 -> v15). Die
	-- Migration schreibt den Betrag, TowerService zahlt ihn beim Join ueber
	-- EconomyService aus und setzt das Feld auf 0.
	pitRefund : number,

	-- v16 (Sammel-Update, Paket 4.1): beste geschaffte Stage je Tower in
	-- DIESEM Leben (seit dem letzten Rebirth). Die Rebirth-Bedingung
	-- (TowerConfig.getRebirthRequirement) prueft dagegen — nicht gegen die
	-- dauerhaften Rekorde, sonst koennte ein Veteran mehrere Rebirths am Stueck
	-- machen. Liegt in der Insel, damit ein Rebirth es von selbst leert.
	stageBest : { [string]: number },

	-- v16 (Sammel-Update, Paket 8): der Inkubator auf dem Plot.
	incubator : IncubatorData,
}

-- v16 (Paket 8): ein belegter Brut-Platz. Zeitmarken statt Timer (wie
-- Honig und Recycler): fertig ist das Ei, sobald os.time() >= finishAt —
-- auch wenn der Spieler dazwischen offline war. `slot` steht IM Eintrag
-- (dichte Liste, derselbe DataStore-Grund wie bei Baerchi.charms).
export type IncubatorSlot = {
	slot      : number,    -- 1 .. IncubatorConfig.MAX_SLOTS
	eggType   : EggType,
	startedAt : number,
	finishAt  : number,
}

-- v16 (Paket 8): Level (Ausbau mit Gummies, Geldsenke vor dem Rebirth) und
-- die belegten Plaetze. Ein Rebirth setzt das Level zurueck, die Eier in den
-- Plaetzen bleiben (wie das Ei-Lager).
export type IncubatorData = {
	level : number,
	slots : { IncubatorSlot },
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
	goldGummies : number?,   -- GOLD_CHARMS_ONLY: Tages-Quests
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
-- Sitzungs-Sperre
--------------------------------------------------------------------------------

-- jobId ist game.JobId des haltenden Servers, lockedAt sein os.time() beim
-- letzten Laden oder Speichern.
export type SessionLock = {
	jobId    : string,
	lockedAt : number,
}

--------------------------------------------------------------------------------
-- PlayerData — alles was im DataStore landet
--------------------------------------------------------------------------------

-- HBB Paket 10: Shop-Teil des Spielstands (Regeln: Modules/ShopRules)
export type ShopState = {
	freeGrabDay : number,     -- UTC-Tag des letzten Gratis-Griffs, -1 = nie
	receipts    : { string }, -- zuletzt ausgezahlte Robux-Kauf-IDs
}

-- HBB Paket 10: was der Client fuer das Shop-Fenster braucht
export type ShopView = {
	freeReady  : boolean,
	nextFreeIn : number,      -- Sekunden bis zum naechsten UTC-Tag
	freeGold   : number,
}

export type PlayerData = {
	-- Schema
	version    : number,   -- fuer Migrationen beim Laden alter Daten
	createdAt  : number,   -- Unix-Timestamp
	lastSeenAt : number,   -- fuer Offline-Gummy-Farm-Berechnung

	-- Waehrungen
	gummies     : number,  -- aktiv: PIT-Kaempfe, Quests, Recycling
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
		totalHatched        : number,   -- v13: geoeffnete Eier (Quest-Zaehler)
		-- HBB Paket 2: Events, an deren Ende der Baerchi belohnt wurde
		-- (Fuehrung: "erstes Event geschafft"). Alte Staende starten bei 0.
		totalEventsCompleted : number,
		-- Sammel-Update 05.10. (Paket 6.2): Boss-Siege mit eigenem Schaden
		-- (besonderer Meilenstein "erster Boss-Sieg"). Alte Staende starten bei 0.
		bossVictories : number,
		-- Sammel-Update 05.10. (Paket 3.5): im Recycler abgegebene Waben
		-- (Einfuehrung "Waben abgeben"). Alte Staende starten bei 0.
		totalCombsDelivered : number,
	},

	-- v13: Index. Jede configId, die der Spieler je besessen hat (auch nach
	-- Recycling/Fusion/Rebirth). Wird nie geleert.
	discovered : { [string]: boolean },

	-- HBB Paket 3: welche Bedienelemente der Spieler schon gesehen hat
	-- (Badge "!" nur fuer neue). Rein kosmetisch, gesetzt nur von
	-- UiStateService; Ids siehe Modules/UnlockRules.ELEMENTS.
	uiSeen : { [string]: boolean },

	-- HBB Paket 10: Shop (Gratis-Griff, gemerkte Robux-Kaeufe)
	shop : ShopState,

	-- v13: Quest-Stand
	quests : QuestState,

	-- v14: Ei-Baum (ueberlebt Rebirths)
	eggTree : EggTreeState,

	-- v15: Tower-Rekorde und Meilensteine (ueberleben Rebirths)
	towers : TowerState,

	-- v15: taeglicher Login-Bonus
	daily : DailyState,

	-- v16 (Sammel-Update, Paket 7): abgeholte Index-Belohnungen
	-- (Schluessel = IndexRewardConfig-Id, z.B. "egg:BasicEgg", "path:Gold").
	indexClaimed : { [string]: boolean },

	-- v16 (Sammel-Update, Paket 6.2): ausgezahlte besondere Meilensteine
	-- (EconomyConfig.SPECIAL_MILESTONES, einmalig pro Konto, auch rueckwirkend).
	specialClaimed : { [string]: boolean },

	-- Welcher Server den Spielstand gerade haelt (siehe Util/SessionLock).
	-- Nur serverseitig, geht nie an den Client. nil = niemand; das ist der
	-- Stand nach einem sauberen Verlassen und bei jedem alten Spielstand,
	-- deshalb ohne Versions-Sprung.
	session : SessionLock?,
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
	towers       : TowerState,     -- v15
	daily        : DailyView,      -- v15
	-- HBB Paket 2: fuer Fuehrung und Freischaltung (rein lesend im Client)
	stats        : { [string]: number }?,
	createdAt    : number?,
	uiSeen       : { [string]: boolean }?,   -- HBB Paket 3
	shop         : ShopView?,                -- HBB Paket 10
	indexClaimed : { [string]: boolean }?,   -- v16: Paket 7
}

-- v15: was der Client fuer das Login-Bonus-Fenster braucht (fertig
-- ausgewertet vom Server, siehe LoginBonusService.buildView).
--   day        welcher Tag des Zyklus heute dran ist (1-7)
--   claimable  heute noch nicht abgeholt
--   streak     schon abgeholte Tage im laufenden Zyklus
--   resetIn    Sekunden bis zum naechsten UTC-Tag
export type DailyView = {
	day       : number,
	claimable : boolean,
	streak    : number,
	resetIn   : number,
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
	towerId       : string?,          -- v15: in welchem Tower der Lauf war
	capStage      : number?,          -- v15: Deckel des Rebirths in diesem Tower (Belohnung/Rekord nur bis hier)
	capReached    : boolean?,         -- v15: der Lauf hat den Deckel erreicht (Rebirth-Hinweis)
	newRecord     : number?,          -- v15: neuer Tower-Rekord (nil = keiner)
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
	bonusText  : (string | LocMsg)?,   -- Sammel-Update 2.4: meist LocMsg

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

-- Telegraph einer Boss-Attacke (Server → alle Clients, Remotes.EventTelegraph).
-- Die Wahrheit (wer getroffen wird) rechnet der Server zum Zeitpunkt hitAt;
-- der Client zeichnet nur die Warnflaeche von jetzt bis hitAt.
--   kind = "ring"    Kreisring um `center` zwischen `inner` und `outer`
--   kind = "circles" Kreise mit Radius `radius` um jeden Punkt in `points`
--   kind = "lane"    Bahn von `from` nach `to`, Breite `width`
-- warnAt/hitAt sind Serverzeiten (workspace:GetServerTimeNow()).
export type HazardTelegraph = {
	kind   : "ring" | "circles" | "lane",
	center : Vector3?,
	inner  : number?,
	outer  : number?,
	points : { Vector3 }?,
	radius : number?,
	from   : Vector3?,
	to     : Vector3?,
	width  : number?,
	warnAt : number,
	hitAt  : number,
}

-- Treffer einer Boss-Attacke am eigenen Charakter (Server → ein Client,
-- Remotes.EventHazardHit). Der Server hat entschieden; der Client fuehrt nur
-- die Physik an seinem eigenen Charakter aus (er besitzt ihn).
export type HazardHit = {
	push        : Vector3,   -- Rueckstoss (Studs/s, waagerecht)
	slowFactor  : number,    -- WalkSpeed-Faktor fuer slowSeconds
	slowSeconds : number,
	-- Sammel-Update 05.10. (Paket 5.2): "boss" (Standard) oder "brawl"
	-- (gegnerischer Event-Baerchi) — nur fuer die Meldung beim Client.
	source      : string?,
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

-- v15: ein Tower-Meilenstein wurde ausgezahlt (Toast).
export type TowerMilestoneReward = {
	towerId     : string,
	stage       : number,
	gummies     : number,   -- ohne Rebirth-Multiplikator
	goldGummies : number,
	eggType     : EggType?,
	eggs        : number,
	blueprints  : number,
	endlessLevels : number?, -- Paket 9: +Endless-Level fuer den ausgeruesteten Baerchi
}

-- v15: eine Zeile einer Bestenliste (Server → Client).
export type LeaderboardEntry = {
	rank   : number,
	userId : number,
	name   : string,
	value  : number,
}

-- v15: eine Bestenliste. listId = "Tower" | "Rebirths" | "Collection".
-- ownRank = Rang des Anfragenden (nil = nicht in den Top N).
export type LeaderboardView = {
	listId    : string,
	entries   : { LeaderboardEntry },
	ownRank   : number?,
	ownValue  : number,
	updatedAt : number,
}

-- v15: die Profilkarte eines anderen Spielers (Inspektor). Der Server baut sie
-- aus den Daten im Speicher — rohe PlayerData gehen nie an fremde Clients.
export type ProfileBaerchi = {
	configId  : string,
	rarity    : Rarity,
	mutation  : MutationId?,
	level     : number,
	promotion : number,
	power     : number,   -- grobe Staerke (fuer die Top-3-Sortierung)
}

export type PlayerProfileCard = {
	userId       : number,
	name         : string,
	equipped     : ProfileBaerchi?,
	highestTower : string,
	towerRecord  : number,
	rebirths     : number,
	indexCount   : number,
	indexTotal   : number,
	top          : { ProfileBaerchi },
}

-- v16 (Sammel-Update, Paket 6.2): ein besonderer Meilenstein wurde
-- ausgezahlt (Toast). id = Schluessel in EconomyConfig.SPECIAL_MILESTONES.
export type SpecialMilestoneResult = {
	id   : string,
	eggs : { { eggType: EggType, count: number } },
}

-- v16 (Sammel-Update, Paket 7): eine Index-Belohnung wurde abgeholt (Toast).
export type IndexRewardResult = {
	rewardId       : string,
	gummies        : number,
	goldGummies    : number,
	eggType        : EggType?,
	eggs           : number,
	blueprints     : number,
	incubatorSlots : number,
}

-- v15: Ergebnis des Login-Bonus (Toast).
export type DailyBonusResult = {
	day         : number,
	gummies     : number,
	goldGummies : number,
	eggType     : EggType?,
	eggs        : number,
	blueprint   : boolean,
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

	local data: PlayerData = {
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
		-- Die Migration (Util/PlayerMigration) raeumt dafuer die alten def-Eintraege
		-- aus statLevels und baseStatOverride weg — DAS ist der Grund, warum
		-- diese Zahl steigen MUSS: die Migration entfernt etwas, statt nur ein
		-- fehlendes Feld anzulegen.
		--
		-- v8: jeder Baerchi hat drei neue Felder bekommen (promotionLevel,
		-- statLevels, charms) plus das optionale baseStatOverride. Die
		-- zugehoerige Migration (Util/PlayerMigration) legt sie auf bestehenden
		-- Baerchis an — sie erkennt fehlende Felder selbst und ist deshalb
		-- gefahrlos wiederholbar.
		--
		-- v7: eigene Rolle pro Gebaeude. KEIN neues Feld — die Zahl stieg
		-- trotzdem, weil die zugehoerige Migration (Util/PlayerMigration) einen Wert
		-- UMRECHNET (die Presse erbt einmalig das hoechste Gebaeude-Level) und
		-- deshalb genau einmal laufen darf.
		-- v13: Quests + Index. Neu: discovered, quests, stats.totalHatched. Die
		-- Migration seedet discovered aus den vorhandenen Baerchis und setzt
		-- totalHatched auf deren Anzahl, damit Veteranen nicht bei null starten.
		-- v12: Brut-Slots entfallen (Eier werden sofort geoeffnet), die
		-- Migration legt laufende Bruten zurueck ins Lager und ENTFERNT
		-- island.hatchingEggs. Neu: island.pitProgress (optional).
		-- v15: Gebaeude Option B (Honigtopf + Honig-Presse -> HoneyRefiner),
		-- Level 1-60, Tower statt PIT-Level (towers, island.towerProgress,
		-- island.pitRefund), Login-Bonus (daily). Die Migration RECHNET um
		-- (Veredler-Level, PIT-Erstattung, alter Rekord) — deshalb Sprung.
		-- v16 (Sammel-Update 05.10.): island.stageBest (Rebirth nach Stage),
		-- island.incubator (Inkubator), indexClaimed (Index-Belohnungen),
		-- specialClaimed (besondere Meilensteine). EINE gemeinsame Migration;
		-- sie legt nur an und saeet stageBest aus towerProgress, fasst keine
		-- Waehrung an.
		version    = 16,  -- v16: Sammel-Update, v15: Tower + Gebaeude B + Login-Bonus, v14: Ei-Baum, v13: Quests + Index (discovered, quests, stats.totalHatched), v12: Sofort-Oeffnen + pitProgress, v11: Mutation-System (v10: Eier legen, v9: PWR statt DEF + Inverted, v8: Promotion/Charms/Stat-Level, v7: Gebaeude-Rollen, v6: equippedUid, v5: Ei-uid, v4: Honig-Gebaeude + currentHp)
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
			-- Beide Honig-Gebaeude stehen ab dem ersten Join auf dem Plot und
			-- fangen sofort an zu produzieren.
			buildings = {
				Beehive      = { id = "Beehive",      level = 1, honey = 0, lastProducedAt = now },
				HoneyRefiner = { id = "HoneyRefiner", level = 1, honey = 0, lastProducedAt = now },
				HoneyPond    = { id = "HoneyPond",    level = 1, honey = 0, lastProducedAt = now },
			},
			baerchis     = {},
			eggStock     = {
				-- Sammel-Update 05.10. (Paket 6.4, "mehr Eier am Anfang"): 3 -> 6.
				-- Die ersten Minuten sollen mehrere Schluepf-Momente haben, bevor das
				-- Legen uebernimmt. Ein Rebirth setzt das Lager NICHT zurueck (siehe
				-- RebirthService), Veteranen bekommen also nichts doppelt.
				BasicEgg = 6,  -- Starter-Eier fuer den ersten Join
			},
			equippedUid  = nil,   -- noch kein Baerchi da, der ausgeruestet sein koennte

			laidEggs  = {},
			lastEggAt = now,

			recycler = { level = 1, queued = 0, progress = 0, lastProcessedAt = now },

			towerProgress = {},
			pitRefund     = 0,

			stageBest = {},                       -- v16: Paket 4.1
			incubator = { level = 1, slots = {} },  -- v16: Paket 8
		},

		stats = {
			totalGummiesEarned  = 0,
			totalFightsWon      = 0,
			totalFightsLost     = 0,
			totalFusions        = 0,
			totalRebirths       = 0,
			totalRecycled       = 0,
			totalHatched        = 0,
			totalEventsCompleted = 0,
			bossVictories        = 0,   -- v16: Paket 6.2
			totalCombsDelivered  = 0,   -- v16: Paket 3.5
			sessions             = 0,   -- HBB Paket 10: Sitzungen (Shop ab der 2.)
		},

		-- HBB Paket 10: Shop (Modules/ShopRules). freeGrabDay = UTC-Tag des
		-- letzten Gratis-Griffs (-1 = nie), receipts = gemerkte Robux-Kauf-IDs.
		shop = { freeGrabDay = -1, receipts = {} },

		discovered = {},
		uiSeen     = {},

		eggTree = {
			unlocked   = { BasicEgg = true, SugarEgg = true },
			hatched    = {},
			pressed    = {},
			blueprints = 0,
			bypass     = {},
		},

		towers = {
			records      = {},
			claimed      = {},
			highestTower = "I",
			selected     = "I",
		},

		daily = {
			lastClaimDay = 0,
			streak       = 0,
		},

		indexClaimed   = {},   -- v16: Paket 7
		specialClaimed = {},   -- v16: Paket 6.2

		quests = {
			chainClaimed = 0,
			day          = 0,   -- 0 = noch nie gesetzt; QuestService setzt beim Join den Tag
			baseline     = { hatched = 0, fightsWon = 0, gummies = 0 },
			dailyClaimed = {},
		},
	}

	-- Honig-Teich oder Stock + Veredler, je nach Schalter (neue Spieler und
	-- Rebirth gehen beide hierueber).
	HoneyPondMode.apply(data.island, FeatureFlags.isOn("HONEY_POND_V2"), now)
	return data
end

return {
	createDefaultPlayerData = createDefaultPlayerData,
}