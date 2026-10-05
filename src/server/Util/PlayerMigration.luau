--!strict
-- PlayerMigration.luau
-- ServerScriptService/Util/PlayerMigration.luau
--
-- Einzige Zustaendigkeit:
--   - Einen geladenen Spielstand beliebiger frueherer Version auf die aktuelle
--     Struktur (Types.PlayerData) bringen
--
-- Gehoert fachlich zu PlayerService und wird nur von dort aufgerufen. Es ist
-- ein eigenes Modul, weil es eine reine Funktion ist (Tabelle rein, Tabelle
-- raus, kein DataStore, kein Spieler-Objekt) und deshalb ohne Studio getestet
-- werden kann: tools/luau-tests/migration.test.lua schickt alte Spielstaende
-- hindurch und prueft das Ergebnis gegen Types.createDefaultPlayerData.
--
-- Regel fuer neue Felder: jedes Feld, das in Types.PlayerData dazukommt, wird
-- hier nachgeruestet (oder ausdruecklich begruendet, warum nil reicht). Eine
-- Migration, die Werte UMRECHNET statt Fehlendes anzulegen, haengt an
-- data.version und darf nur einmal laufen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types            = require(ReplicatedStorage.Network.Types)
local BaerchiConfig    = require(ReplicatedStorage.Config.BaerchiConfig)
local PromotionConfig  = require(ReplicatedStorage.Config.PromotionConfig)
local CharmConfig      = require(ReplicatedStorage.Config.CharmConfig)
local EggConfig        = require(ReplicatedStorage.Config.EggConfig)
local CombatCalculator = require(ReplicatedStorage.Modules.CombatCalculator)
local EggTree          = require(ReplicatedStorage.Modules.EggTree)
local TowerConfig      = require(ReplicatedStorage.Config.TowerConfig)
local EconomyConfig    = require(ReplicatedStorage.Config.EconomyConfig)
local BuildingBehavior = require(ReplicatedStorage.Config.BuildingBehavior)
local FeatureFlags     = require(ReplicatedStorage.Config.FeatureFlags)
local HoneyPondMode    = require(ReplicatedStorage.Modules.HoneyPondMode)

local PlayerMigration = {}

-- Fehlende Felder aus Default auffuellen (einfache Migration fuer neue Felder).
-- Muss jedes Feld abdecken das seit dem ersten Release in Types.luau
-- dazugekommen ist — sonst crasht alter Save-Stand beim ersten Zugriff.
function PlayerMigration.applyDefaults(data: Types.PlayerData): Types.PlayerData
	local default = Types.createDefaultPlayerData()

	-- Neue Top-Level-Felder
	if data.gummies      == nil then data.gummies      = default.gummies      end
	if data.goldGummies  == nil then data.goldGummies  = default.goldGummies  end
	if data.rebirthCount == nil then data.rebirthCount = default.rebirthCount end
	if data.rebirthMult  == nil then data.rebirthMult  = default.rebirthMult  end
	if data.rank         == nil then data.rank         = default.rank         end
	if data.island       == nil then data.island       = default.island       end
	if data.stats        == nil then data.stats        = default.stats        end
	if data.createdAt    == nil then data.createdAt    = default.createdAt    end
	if data.lastSeenAt   == nil then data.lastSeenAt   = default.lastSeenAt   end

	-- Neue Stats-Felder (dynamischer Key → bewusst ueber any, sonst meckert --!strict)
	local stats     = data.stats    :: any
	local defStats  = default.stats :: any

	-- HBB Paket 10: Sitzungszaehler. Ein Konto, das schon aelter als 10 min
	-- ist, war mindestens einmal da — es zaehlt als 1, damit Veteranen den
	-- Shop schon bei diesem Join (= Sitzung 2, PlayerService zaehlt hoch) sehen.
	if stats.sessions == nil then
		stats.sessions = if os.time() - (data.createdAt or os.time()) >= 600 then 1 else 0
	end
	for key, value in defStats do
		if stats[key] == nil then
			stats[key] = value
		end
	end

	-- highestTowerFloor gehoerte zu einem Tower-Modus, den es nicht gibt. Das
	-- Feld wird entfernt, damit es nicht bei jedem Speichern wieder im
	-- DataStore landet. Am Feld erkennbar und deshalb ohne Versions-Sprung
	-- wiederholbar; ein Wert geht nicht verloren, er war immer 0.
	stats.highestTowerFloor = nil

	-- Neue Island-Felder
	local island = data.island
	if island.baerchis  == nil then island.baerchis  = {} end
	if island.eggStock  == nil then island.eggStock  = { BasicEgg = 3 } end

	-- language: kein Nachruesten noetig — nil bedeutet "automatisch" (die
	-- Roblox-Sprache des Clients), und genau das soll ein alter Spielstand
	-- bekommen. Kein Versions-Sprung. Siehe SettingsService.
	--
	-- v6: equippedUid. Kein Nachruesten noetig — ein fehlendes Feld liest
	-- sich in Lua ohnehin als nil, und IslandService.autoEquipIfNone laeuft
	-- bei jedem Join (onDataLoaded) und ruestet automatisch den ersten
	-- vorhandenen Baerchi aus, falls noch/wieder keiner steht.

	-- ============================================================
	-- ============================================================
	-- v13: QUESTS + INDEX
	-- ============================================================
	-- Neue Felder: discovered, quests, stats.totalHatched (das Stats-Feld legt
	-- die Schleife oben schon mit 0 an). Fuer Spielstaende VOR v13 wird
	-- discovered aus den vorhandenen Baerchis gesaeet und totalHatched auf
	-- deren Anzahl gesetzt, damit Veteranen nicht bei null anfangen.
	if data.discovered == nil then
		data.discovered = {}
		for _, baerchi in data.island.baerchis do
			data.discovered[baerchi.configId] = true
		end
	end

	if (data.version or 0) < 13 then
		local owned = 0
		for _ in data.island.baerchis do owned += 1 end
		data.stats.totalHatched = math.max(data.stats.totalHatched or 0, owned)
	end

	-- HBB Paket 3: uiSeen. Leer nachruesten; UiStateService markiert beim
	-- ersten Laden eines Stands mit Fortschritt alles Sichtbare als gesehen
	-- (keine Badge-Flut fuer Veteranen). Kein Versions-Sprung.
	if data.uiSeen == nil then
		data.uiSeen = {}
	end

	-- HBB Paket 10: Shop-Teil. Leer nachruesten, kaputte Felder reparieren.
	local shop = (data :: any).shop
	if typeof(shop) ~= "table" then
		(data :: any).shop = default.shop
	else
		if typeof(shop.freeGrabDay) ~= "number" then shop.freeGrabDay = -1 end
		if typeof(shop.receipts) ~= "table" then shop.receipts = {} end
	end

	if data.quests == nil then
		data.quests = default.quests
	end

	-- ============================================================
	-- v14: EI-BAUM (Mega Egg Tree)
	-- ============================================================
	-- Neues Top-Level-Feld eggTree (ausserhalb der Insel, damit ein Rebirth
	-- es nicht loescht). Bestandsspieler bekommen die Knoten der Eier frei,
	-- die sie schon im Lager haben oder die auf ihrem Plot liegen — wer ein
	-- Goldenes Ei besitzt, soll es nicht ploetzlich "gesperrt" sehen. Die
	-- Rebirth-Knoten (Ascensions-Pfad) schaltet evaluate unten frei.
	--
	-- Gefahrlos wiederholbar: sanitize ergaenzt nur Fehlendes, und die
	-- Lager-Freischaltung laeuft nur fuer Spielstaende vor v14.
	local hadTree = data.eggTree ~= nil
	data.eggTree = EggTree.sanitize(data.eggTree)
	if not hadTree and (data.version or 0) < 14 then
		for eggType, count in island.eggStock do
			if (count or 0) > 0 and EggConfig.data[eggType] then
				data.eggTree.unlocked[eggType] = true
			end
		end
		for _, egg in (island.laidEggs or {}) do
			if EggConfig.data[egg.eggType] then
				data.eggTree.unlocked[egg.eggType] = true
			end
		end
	end
	-- Unbekannte Ei-Typen im Lager (alte Config) werden zum Basis-Ei.
	local stockAny = island.eggStock :: any
	for eggType, count in stockAny do
		if not EggConfig.data[eggType] then
			stockAny.BasicEgg = (stockAny.BasicEgg or 0) + (tonumber(count) or 0)
			stockAny[eggType] = nil
		end
	end
	EggTree.evaluate(data)

	-- v12: BRUT-SLOTS ENTFALLEN (Eier werden sofort geoeffnet)
	-- ============================================================
	-- Alte Spielstaende koennen noch laufende oder fertige Bruten in
	-- island.hatchingEggs haben. Die gehen NICHT verloren: jedes Ei wandert
	-- als ungeoeffnetes Ei zurueck ins Lager, danach wird das Feld entfernt.
	-- Ein Ei-Typ, den es nicht mehr gibt, wird zum Basis-Ei (dieselbe Regel,
	-- die frueher beim Abholen galt).
	--
	-- Gefahrlos wiederholbar: beim zweiten Durchlauf ist das Feld schon nil.
	-- Ueber `any`, weil Types.IslandData das Feld seit v12 nicht mehr kennt.
	local legacyIsland = island :: any
	if legacyIsland.hatchingEggs ~= nil then
		if typeof(legacyIsland.hatchingEggs) == "table" then
			for _, egg in legacyIsland.hatchingEggs do
				local eggType = if typeof(egg) == "table" then egg.eggType else nil
				if typeof(eggType) ~= "string" or not EggConfig.data[eggType :: Types.EggType] then
					eggType = "BasicEgg"
				end
				local stock = island.eggStock :: any
				stock[eggType] = (stock[eggType] or 0) + 1
			end
		end
		legacyIsland.hatchingEggs = nil
	end

	-- v12: pitProgress muss nur gueltig sein, wenn es da ist (nil = kein
	-- gespeicherter Lauf). Ein halber Eintrag wird verworfen statt geraten.
	local progress = legacyIsland.pitProgress
	if progress ~= nil and (typeof(progress) ~= "table"
		or typeof(progress.pitLevel) ~= "number"
		or typeof(progress.reachedStage) ~= "number")
	then
		legacyIsland.pitProgress = nil
	end

	-- v10: gelegte Eier.
	--
	-- lastEggAt bewusst auf JETZT statt auf createdAt: ein Spielstand, der vor
	-- diesem Feature entstanden ist, hat keine Ei-Zeit — wuerde man hier
	-- createdAt einsetzen, bekaeme er beim ersten Join nach dem Update die
	-- Obergrenze auf einen Schlag geschenkt, fuer eine Zeit, in der es das
	-- Legen noch gar nicht gab.
	if island.laidEggs == nil then
		island.laidEggs = {}
	else
		-- Nur vollstaendige Eintraege behalten. Ein Ei ohne uid liesse sich nie
		-- einsammeln und laege bis in alle Ewigkeit auf dem Plot herum.
		local cleaned: { Types.LaidEgg } = {}
		for _, egg in island.laidEggs do
			if typeof(egg.uid) == "string" and #egg.uid > 0
				and typeof(egg.eggType) == "string"
				and typeof(egg.x) == "number"
				and typeof(egg.y) == "number"
				and typeof(egg.z) == "number"
			then
				table.insert(cleaned, egg)
			end
		end
		island.laidEggs = cleaned
	end

	if island.lastEggAt == nil then
		island.lastEggAt = os.time()
	end

	-- v15: Waben-Recycler. Feldweise nachgeruestet (wie lastEggAt), deshalb
	-- gefahrlos wiederholbar und ohne Versionssprung.
	local recycler = (island :: any).recycler
	if typeof(recycler) ~= "table" then
		(island :: any).recycler = { level = 1, queued = 0, progress = 0, lastProcessedAt = os.time() }
	else
		if typeof(recycler.level) ~= "number" then recycler.level = 1 end
		if typeof(recycler.queued) ~= "number" then recycler.queued = 0 end
		if typeof(recycler.progress) ~= "number" then recycler.progress = 0 end
		if typeof(recycler.lastProcessedAt) ~= "number" then recycler.lastProcessedAt = os.time() end
	end

	-- (v5 hatte hier die uid-Nachruestung der Brut-Eier — seit v12 gibt es
	-- keine Brut-Eier mehr, siehe oben.)

	-- v4: die Gebaeude sind komplett ausgetauscht. Frueher gab es Hatchery,
	-- GummyFarm, Recycler (und davor FusionLab) mit je eigener Funktion —
	-- jetzt reine Honig-Produzenten. Alte Eintraege werden entfernt und
	-- die neuen angelegt; das Level laesst sich nicht sinnvoll uebertragen,
	-- weil die Gebaeude etwas voellig anderes tun.
	--
	-- (Honigtopf und Honig-Presse bleiben hier noch stehen: die v7- und die
	-- v15-Migration weiter unten brauchen ihre Level. Entfernt werden sie erst
	-- in der v15-Zusammenlegung.)
	local OBSOLETE_BUILDINGS = { "Hatchery", "GummyFarm", "Recycler", "FusionLab" }

	if island.buildings == nil then
		island.buildings = default.island.buildings
	else
		local buildings = island.buildings :: any

		for _, obsolete in OBSOLETE_BUILDINGS do
			buildings[obsolete] = nil
		end

		for buildingId, building in default.island.buildings do
			local existing = buildings[buildingId]
			if existing == nil then
				buildings[buildingId] = {
					id             = building.id,
					level          = building.level,
					honey          = building.honey,
					lastProducedAt = building.lastProducedAt,
				}
			else
				-- v4: Honig-Felder auf bereits vorhandenen Gebaeuden nachruesten
				if existing.honey == nil then
					existing.honey = 0
				end
				if existing.lastProducedAt == nil then
					existing.lastProducedAt = os.time()
				end
			end
		end
	end

	-- v7: die drei Gebaeude haben eigene Rollen bekommen (siehe
	-- Config/BuildingBehavior). Die XP pro Honig haengen seitdem allein am Level
	-- der Honig-Presse — vorher am Level des Gebaeudes, aus dem der Honig kam,
	-- also an allen dreien.
	--
	-- Ohne Ausgleich wuerde ein laufender Spielstand dabei XP VERLIEREN: wer
	-- seinen Bienenstock auf Level 5 stehen hat und die Presse auf Level 1,
	-- bekaeme ploetzlich 30 statt 135 XP pro Honig. Deshalb erbt die Presse
	-- einmalig das hoechste Level, das dieser Spielstand bei irgendeinem
	-- Gebaeude erreicht hatte. Danach ist die XP-Ausbeute mindestens so gut wie
	-- vorher, und niemand muss etwas nachkaufen.
	--
	-- DAS IST DIE ERSTE MIGRATION, DIE AN DER VERSIONSNUMMER HAENGEN MUSS
	-- (siehe den Kommentar bei data.version am Ende dieser Funktion): sie
	-- rechnet einen Wert um, statt ein fehlendes Feld anzulegen. Liefe sie bei
	-- jedem Join erneut, wuerde die Presse jedes Mal wieder auf das Maximum
	-- hochgezogen — der Spieler koennte die anderen beiden nie ueberholen.
	if (data.version or 0) < 7 then
		local press = (island.buildings :: any).HoneyPress

		if press then
			local highest = press.level or 1

			for _, building in island.buildings do
				highest = math.max(highest, building.level or 1)
			end

			press.level = highest
		end
	end

	-- ============================================================
	-- v15: GEBAEUDE OPTION B — Honigtopf + Honig-Presse -> Honig-Veredler
	-- ============================================================
	-- Niemand verliert etwas: der Veredler bekommt das HOEHERE der beiden alten
	-- Level (er kann beides: XP wie die Presse, Heilung wie der Topf), und der
	-- eingelagerte Honig beider wird zusammengelegt (gedeckelt auf sein Lager).
	-- Haengt an der Version, weil es UMRECHNET; danach sind Topf und Presse weg.
	-- Ueber `any`, weil Types.BuildingId die alten Ids nicht mehr kennt.
	do
		local buildings = island.buildings :: any
		if (data.version or 0) < 15 then
			local pot     = buildings.HoneyPot
			local press   = buildings.HoneyPress
			local refiner = buildings.HoneyRefiner
			-- Mit HONEY_POND_V2 legt der Standard keinen Veredler mehr an; fuer
			-- die Zusammenlegung (und danach den Teich) wird er hier angelegt.
			if refiner == nil and (pot or press) then
				refiner = { id = "HoneyRefiner", level = 1, honey = 0, lastProducedAt = os.time() }
				buildings.HoneyRefiner = refiner
			end
			if refiner and (pot or press) then
				local level = math.max(refiner.level or 1,
					if pot then pot.level or 1 else 1,
					if press then press.level or 1 else 1)
				refiner.level = math.clamp(level, 1, EconomyConfig.MAX_BUILDING_LEVEL)

				local honey = (if pot then pot.honey or 0 else 0) + (if press then press.honey or 0 else 0)
				refiner.honey = math.clamp(honey, 0, BuildingBehavior.getCapacity("HoneyRefiner", refiner.level))
			end
		end

		-- Honig-Teich (HONEY_POND_V2) bzw. zurueck zu Stock + Veredler. MUSS vor
		-- dem Aufraeumen unten laufen: sonst waeren die gerade nicht geltenden
		-- Gebaeude schon geloescht statt im Ruhestand (island.retiredBuildings).
		HoneyPondMode.apply(island, FeatureFlags.isOn("HONEY_POND_V2"), os.time())
		local pond = buildings[HoneyPondMode.POND]
		if pond then
			pond.level = EconomyConfig.clampBuildingLevel(pond.level or 1)
			pond.honey = math.clamp(pond.honey or 0, 0, BuildingBehavior.getCapacity("HoneyPond", pond.level))
		end

		-- Alles, was es nicht (mehr) gibt, verschwindet — auch Topf und Presse
		-- nach der Zusammenlegung. Am Feld erkennbar, deshalb wiederholbar.
		for buildingId in buildings do
			if default.island.buildings[buildingId] == nil then
				buildings[buildingId] = nil
			end
		end

		-- Level auf den gueltigen Bereich (1-60) klemmen.
		for _, building in buildings do
			building.level = EconomyConfig.clampBuildingLevel(building.level or 1)
		end
	end

	-- ============================================================
	-- v15: TOWER STATT PIT-LEVEL
	-- ============================================================
	-- 1. Erstattung: die Summe der bezahlten PIT-Ausbaukosten landet in
	--    island.pitRefund. Die Migration fasst KEINE Waehrung an —
	--    TowerService zahlt den Betrag beim Join ueber EconomyService aus.
	-- 2. Rekord: der alte letzte Lauf (pitProgress) wird in die gleich starke
	--    Tower-Stage umgerechnet (TowerConfig.legacyPitToTower) und als
	--    permanenter Rekord eingetragen. Die zugehoerigen Meilensteine vergibt
	--    TowerService beim Join rueckwirkend.
	-- 3. pitLevel, pitProgress und stats.highestPitLevel werden entfernt.
	--
	-- Gilt reachedStage als "geschafft"? reachedStage ist die letzte Stage, in
	-- die der Baerchi eingetreten ist — gewonnen oder verloren. Bewusst
	-- grosszuegig als Rekord gezaehlt: niemand soll durch die Umstellung weniger
	-- haben (ANNAHME, im Bericht).
	data.towers = (data :: any).towers
	if typeof(data.towers) ~= "table" then
		data.towers = {
			records      = {},
			claimed      = {},
			highestTower = TowerConfig.FIRST_TOWER,
			selected     = TowerConfig.FIRST_TOWER,
		}
	end
	local towers = data.towers :: any
	if typeof(towers.records) ~= "table" then towers.records = {} end
	if typeof(towers.claimed) ~= "table" then towers.claimed = {} end

	if (data.version or 0) < 15 then
		local legacyLevel = tonumber(legacyIsland.pitLevel) or 1
		local refund = TowerConfig.legacyPitRefund(legacyLevel)
		legacyIsland.pitRefund = (tonumber(legacyIsland.pitRefund) or 0) + refund

		local legacyProgress = legacyIsland.pitProgress
		if typeof(legacyProgress) == "table" then
			local towerId, stage = TowerConfig.legacyPitToTower(
				tonumber(legacyProgress.pitLevel) or legacyLevel,
				tonumber(legacyProgress.reachedStage) or 0
			)
			if towerId and stage > 0 then
				towers.records[towerId] = math.max(tonumber(towers.records[towerId]) or 0, stage)
			end
		end
	end
	legacyIsland.pitLevel    = nil
	legacyIsland.pitProgress = nil
	stats.highestPitLevel    = nil

	-- Rekorde: nur gueltige Tower, nur Zahlen, nur bis zur Stage-Zahl.
	for towerId, record in towers.records do
		local def = TowerConfig.get(towerId)
		local value = tonumber(record)
		if not def or not value or value <= 0 then
			towers.records[towerId] = nil
		else
			towers.records[towerId] = math.clamp(math.floor(value), 0, def.stages)
		end
	end
	-- Meilensteine: Tabelle je Tower mit TEXT-Schluesseln (siehe Types).
	for towerId, claimed in towers.claimed do
		if not TowerConfig.get(towerId) or typeof(claimed) ~= "table" then
			towers.claimed[towerId] = nil
		else
			local cleaned: { [string]: boolean } = {}
			for stage, flag in claimed do
				if flag == true and tonumber(stage) then
					cleaned[tostring(math.floor(tonumber(stage) :: number))] = true
				end
			end
			towers.claimed[towerId] = cleaned
		end
	end
	-- Hoechster Tower = der hoechste mit Rekord (nie niedriger als gespeichert).
	local highest = if TowerConfig.isValidId(towers.highestTower) then towers.highestTower else TowerConfig.FIRST_TOWER
	for towerId in towers.records do
		if TowerConfig.getIndex(towerId) > TowerConfig.getIndex(highest) then
			highest = towerId
		end
	end
	towers.highestTower = highest
	if not TowerConfig.isValidId(towers.selected) then
		towers.selected = TowerConfig.FIRST_TOWER
	end

	-- Fortsetzen pro Tower (ersetzt pitProgress) und Erstattungs-Feld.
	if typeof(legacyIsland.towerProgress) ~= "table" then
		legacyIsland.towerProgress = {}
	else
		for towerId, stage in legacyIsland.towerProgress do
			if not TowerConfig.get(towerId) or typeof(stage) ~= "number" or stage < 1 then
				legacyIsland.towerProgress[towerId] = nil
			end
		end
	end
	if typeof(legacyIsland.pitRefund) ~= "number" or legacyIsland.pitRefund < 0 then
		legacyIsland.pitRefund = 0
	end

	-- v15: Login-Bonus. Feldweise, wiederholbar.
	local daily = (data :: any).daily
	if typeof(daily) ~= "table" then
		(data :: any).daily = { lastClaimDay = 0, streak = 0 }
	else
		if typeof(daily.lastClaimDay) ~= "number" then daily.lastClaimDay = 0 end
		if typeof(daily.streak) ~= "number" then daily.streak = 0 end
	end

	-- v8: die zweite Fortschrittsachse (Promotion, Stat-Level, Charms).
	--
	-- Steht bewusst VOR der currentHp-Migration weiter unten: die rechnet mit
	-- CombatCalculator.getEffectiveStats, und das liest inzwischen genau diese
	-- Felder. Es kaeme auch ohne zurecht (es faengt fehlende Felder mit 0 ab),
	-- aber ein Spielstand soll die Migration nicht in halb fertigem Zustand
	-- durchlaufen — das ist die Art Reihenfolge-Abhaengigkeit, die man erst
	-- Monate spaeter bemerkt.
	--
	-- Erkennt fehlende Felder einzeln statt an der Versionsnummer und ist
	-- deshalb gefahrlos wiederholbar (dieselbe Konvention wie v2/v4/v5).
	for _, baerchi in island.baerchis do
		if baerchi.promotionLevel == nil then
			baerchi.promotionLevel = 0
		end

		if baerchi.statLevels == nil then
			baerchi.statLevels = PromotionConfig.newStatLevels()
		else
			-- Einzelne Stat-Schluessel nachruesten: `egg` kam als letzter dazu,
			-- und ein kuenftiger fuenfter Stat soll hier ebenfalls landen, ohne
			-- dass die ganze Tabelle ersetzt (und damit der Fortschritt
			-- geloescht) wird.
			local levels = baerchi.statLevels :: any
			for _, key in PromotionConfig.ALL_STATS do
				if levels[key] == nil then
					levels[key] = 0
				end
			end
		end

		if baerchi.charms == nil then
			baerchi.charms = {}
		else
			-- Nur gueltige Eintraege behalten. Ein Charm ohne Slot oder mit
			-- einem Stat-Typ, den es nicht mehr gibt (Pool-Aenderung), waere
			-- sonst ein stiller Rechenfehler in getEffectiveStats.
			local cleaned: { Types.Charm } = {}
			for _, charm in baerchi.charms do
				local slotOk = typeof(charm.slot) == "number"
					and charm.slot >= 1
					and charm.slot <= CharmConfig.SLOT_COUNT

				if slotOk and CharmConfig.getStatDef(charm.statId) then
					if charm.locked == nil then
						charm.locked = false
					end
					table.insert(cleaned, charm)
				end
			end
			table.sort(cleaned, function(a, b)
				return a.slot < b.slot
			end)
			baerchi.charms = cleaned
		end

		-- baseStatOverride bleibt absichtlich ungesetzt: nil heisst "Basiswerte
		-- kommen wie immer aus BaerchiConfig", und genau das gilt fuer jeden
		-- Baerchi, der vor dieser Version entstanden ist — auch fuer die
		-- damaligen Fusions-Ergebnisse (die haben ihren Vorteil ueber
		-- fusionBonus, nicht ueber die Basiswerte).

		-- ============================================================
		-- v9: DEF ist weg, PWR ist da, Inverted ist neu
		-- ============================================================
		-- Anders als alles darueber RAEUMT diese Migration etwas WEG. Ein
		-- statLevels.def oder ein baseStatOverride.def aus v8 zeigt auf einen
		-- Stat, den es nicht mehr gibt — stehen bleiben duerfte er trotzdem
		-- nicht: er landete beim naechsten Speichern wieder im DataStore und
		-- waere in einem Jahr ein Feld, das niemand mehr einordnen kann.
		--
		-- Der alte def-WERT wird NICHT in pwr uebertragen. Die beiden haben
		-- nichts miteinander zu tun (Schadensreduktion gegen Ability-Staerke),
		-- und ein Baerchi mit acht DEF-Stufen haette sonst still acht Stufen
		-- eines voellig anderen Stats geschenkt bekommen. pwr faengt bei 0 an.
		local statLevels = baerchi.statLevels :: any
		if statLevels.def ~= nil then
			statLevels.def = nil
		end
		if statLevels.pwr == nil then
			statLevels.pwr = 0
		end

		local override = baerchi.baseStatOverride :: any
		if override ~= nil then
			override.def = nil

			-- Ein Fusions-Ergebnis aus v8 hat einen gemischten Basiswert fuer
			-- hp/atk/spd, aber keinen fuer pwr (den Stat gab es noch nicht).
			-- nil ist hier genau richtig: getEffectiveStats faellt dann auf den
			-- pwr-Wert seines configId zurueck.
		end

		-- ============================================================
		-- v11: MUTATION-SYSTEM ERSETZT INVERTED
		-- ============================================================
		-- Das binaere isInverted-Feld weicht dem gestuften Mutation-System
		-- (siehe BaerchiConfig.MUTATIONS). Alte Spielstaende kannten hoechstens
		-- isInverted = true.
		--
		-- ANNAHME, nicht vom Projektinhaber vorgegeben: ein zuvor invertierter
		-- Baerchi wird auf die Mutation "Diamond" abgebildet (0.3% Wurf-Chance,
		-- damit nahe an der alten INVERTED_CHANCE von 0.5% — eine exakte
		-- Entsprechung gibt es nicht, weil das alte System nur eine einzige
		-- Stufe kannte). Wer eine andere Zuordnung will, ist das hier die
		-- einzige Stelle, die es aendern muss.
		--
		-- Erkennt das alte Feld selbst (ueber `any`, weil Types.Baerchi es seit
		-- v11 nicht mehr kennt) und ist deshalb gefahrlos wiederholbar: beim
		-- ersten Durchlauf wird das alte Feld entfernt, jeder weitere Durchlauf
		-- findet es dann bereits als nil vor und tut nichts mehr.
		local legacy = baerchi :: any
		if legacy.isInverted == true and baerchi.mutation == nil then
			baerchi.mutation = "Diamond"
		end
		legacy.isInverted = nil
	end

	-- v2: fusionBonus auf allen bestehenden Baerchis
	for _, baerchi in island.baerchis do
		if baerchi.fusionBonus == nil then
			baerchi.fusionBonus = 0
		end
		if baerchi.isFusionResult == nil then
			baerchi.isFusionResult = false
		end
	end

	-- v4: currentHp auf allen bestehenden Baerchis.
	-- Sie haben unter dem neuen System noch nicht gekaempft, starten also mit
	-- vollen HP. CombatCalculator wird dafuer bewusst hier requiret: es ist
	-- ein reines Rechenmodul ohne Zustand, und maxHp soll es nur EINE Formel
	-- im ganzen Projekt geben.
	for _, baerchi in island.baerchis do
		if baerchi.currentHp == nil then
			local baerchiDef = BaerchiConfig.getById(baerchi.configId)

			if baerchiDef then
				-- In pcall: getEffectiveStats rechnet mit level und
				-- fusionBonus. Fehlt einem uralten Eintrag eines davon, waere
				-- der Fehler sonst mitten im Join — und ein einziger kaputter
				-- Baerchi wuerde den ganzen Spielstand unbrauchbar machen.
				local ok, maxHp = pcall(function()
					return CombatCalculator.getEffectiveStats(baerchi, baerchiDef.baseStats).maxHp
				end)

				baerchi.currentHp = if ok then maxHp else 0
				if not ok then
					warn("[PlayerService] Kaputter Baerchi-Eintrag migriert:", baerchi.configId, maxHp)
				end
			else
				-- Unbekannter configId (Config-Eintrag entfernt): nicht raten,
				-- lieber erschoepft starten als mit erfundenen Werten.
				baerchi.currentHp = 0
			end
		end
	end

	-- Zum Schluss die Versionsnummer nachziehen. Sie steuert heute keine der
	-- Migrationen oben — die pruefen alle einzeln auf fehlende Felder und
	-- laufen deshalb harmlos bei jedem Laden. Sie ist trotzdem wichtig: sobald
	-- eine kuenftige Migration NICHT mehr am Feld erkennbar ist (weil sie zum
	-- Beispiel Werte umrechnet statt welche anzulegen), ist diese Zahl der
	-- einzige Weg, sie nicht bei jedem Join erneut auszufuehren. Wer
	-- Types.createDefaultPlayerData um ein Feld erweitert, erhoeht sie dort.
	data.version = default.version
	return data
end

return PlayerMigration
