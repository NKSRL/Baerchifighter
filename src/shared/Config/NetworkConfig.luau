--!strict
-- NetworkConfig.luau
-- ReplicatedStorage/Config/NetworkConfig.luau
--
-- Alle Netzwerk-bezogenen Zahlen an einer Stelle.
-- Aktuell: Cooldowns pro Remote (Spam-/Exploit-Schutz).
--
-- Der Server erzwingt diese Werte (siehe ServerScriptService/Util/RateLimiter).
-- Der Client darf sie lesen um Buttons zu entprellen — das ist Komfort,
-- keine Sicherheit. Autoritativ ist immer der Server.

-- Sekunden die zwischen zwei Aufrufen desselben Remotes vom selben
-- Spieler mindestens vergehen muessen.
local REMOTE_COOLDOWNS: { [string]: number } = {
	-- Seit v12 oeffnet das sofort ein Ei. Kurz genug fuer mehrere Eier
	-- hintereinander (die Animation stellt sie in eine Warteschlange).
	RequestHatchEgg        = 0.35,

	-- v12: Pet-Leiste (Event/Fight). Startet sichtbare Laufwege, deshalb wie
	-- SendToEvent nicht im Sekundentakt.
	RequestPetMode         = 0.60,

	-- v13: Quest-Belohnung abholen. Zahlt aus, deshalb nicht im Sekundentakt.
	RequestClaimQuest      = 0.50,
	RequestUpgradeBuilding = 0.50,
	-- v15: Tower waehlen (reines Umschalten) und Login-Bonus (zahlt aus).
	RequestSelectTower     = 0.30,
	RequestClaimDailyBonus = 1.00,
	RequestUpgradeRecycler = 0.50,   -- v15: Waben-Recycler
	RequestFuseBaerchis    = 1.00,
	RequestRecycleBaerchi  = 0.25,
	-- Fuettern ist die haeufigste Aktion im Spiel (ein Klick pro Honig) —
	-- deshalb bewusst kurz, aber nicht null.
	RequestFeedHoney       = 0.15,
	RequestEquipBaerchi    = 0.50,
	RequestRebirth         = 3.00,

	-- Befoerdern verbraucht Duplikate unwiderruflich — bewusst traege, damit
	-- ein Doppelklick nicht zwei Stufen auf einmal zieht.
	RequestPromoteBaerchi  = 1.00,

	-- Ein Wurf kostet GoldGummies. Ein Auto-Roll ist EIN Aufruf mit mehreren
	-- Wuerfen darin (siehe CharmConfig.AUTO_ROLL_COUNT), deshalb reicht hier
	-- derselbe Abstand wie bei der Fusion.
	RequestRollCharms      = 1.00,

	-- Reines Umschalten eines Schlosses, kostet nichts — darf schnell gehen.
	RequestToggleCharmLock = 0.15,


	-- Eier einsammeln ist die haeufigste Weltaktion ueberhaupt: bis zu zwoelf
	-- liegen gleichzeitig herum, und man klickt sie nacheinander weg. Deshalb
	-- so kurz wie das Fuettern.
	RequestCollectEgg      = 0.15,

	-- Alle auf einmal: eine Anfrage statt zwoelf, darf entsprechend traeger sein.
	RequestCollectAllEggs  = 0.50,
	RequestPressEggs       = 0.40,   -- v14
	RequestUseBlueprint    = 1.00,   -- v14

	-- Reines Umschalten einer Einstellung. Kein Spam-Risiko fuer Spielwerte,
	-- aber jeder Wechsel stoesst ein Daten-Update an — daher nicht null.
	RequestSetLanguage     = 1.00,

	GetPlayerData          = 1.00,

	-- HBB Paket 0: Statistik-Ereignisse. Kurz, weil "Panel auf" und "Panel
	-- schnell zu" direkt nacheinander kommen koennen; die Menge deckelt
	-- FunnelConfig.MAX_UI_EVENTS_PER_SESSION.
	RequestLogUiEvent      = 0.20,
	-- HBB Paket 3: "gesehen"-Markierung. Nimmt mehrere Ids pro Aufruf an,
	-- deshalb reicht ein ruhiger Abstand.
	RequestMarkUiSeen      = 0.30,
	-- HBB Paket 5: Heim-Knopf. Teleport — nicht im Sekundentakt.
	RequestGoHome          = 3.00,
	RequestClaimFreeGrab   = 1.00,   -- HBB Paket 10

	-- Sammel-Update 05.10.
	RequestPitSpeed          = 0.25,   -- 4.3: nur ein Schalter, keine Spielwerte
	RequestClaimIndexReward  = 0.50,   -- 7: Auszahlung, einmalig je Belohnung
	RequestIncubatorStart    = 0.30,   -- 8: Baerchi einsetzen (mehrere schnell hintereinander)
	RequestIncubatorCollect  = 0.30,
	RequestIncubatorRemove   = 0.30,   -- Umbau 05.10.: Baerchi herausnehmen
	RequestUpgradeIncubator  = 0.50,   -- kostet Gummies (wie Recycler)

	-- v15: Bestenliste und Inspektor. Der Server antwortet aus dem Cache bzw.
	-- aus dem Speicher; die Bremse schuetzt nur vor Spam.
	GetLeaderboard         = 1.00,
	GetPlayerProfile       = 1.00,
}

-- Fuer Remotes die (noch) keinen eigenen Eintrag haben
local DEFAULT_COOLDOWN = 0.50

-- Wie viele Verstoesse geloggt werden bevor der Server aufhoert zu warnen.
-- Verhindert dass ein Exploiter das Server-Log flutet.
local MAX_WARNINGS_PER_PLAYER = 5

local function getCooldown(remoteName: string): number
	return REMOTE_COOLDOWNS[remoteName] or DEFAULT_COOLDOWN
end

return {
	REMOTE_COOLDOWNS        = REMOTE_COOLDOWNS,
	DEFAULT_COOLDOWN        = DEFAULT_COOLDOWN,
	MAX_WARNINGS_PER_PLAYER = MAX_WARNINGS_PER_PLAYER,

	getCooldown = getCooldown,
}
