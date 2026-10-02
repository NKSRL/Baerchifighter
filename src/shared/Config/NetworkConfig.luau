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
	RequestHatchEgg        = 0.50,
	RequestClaimEgg        = 0.25,
	RequestStartCombat     = 1.00,
	RequestUpgradeBuilding = 0.50,
	RequestUpgradePit      = 0.50,
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

	-- Beides startet eine sichtbare Laufbewegung quer ueber die Karte. Kurz
	-- genug, dass ein versehentlicher Klick korrigierbar ist, lang genug, dass
	-- niemand die Figur im Sekundentakt hin und her schickt.
	RequestSendToEvent     = 1.00,
	RequestRecallFromEvent = 1.00,

	-- Eier einsammeln ist die haeufigste Weltaktion ueberhaupt: bis zu zwoelf
	-- liegen gleichzeitig herum, und man klickt sie nacheinander weg. Deshalb
	-- so kurz wie das Fuettern.
	RequestCollectEgg      = 0.15,

	-- Alle auf einmal: eine Anfrage statt zwoelf, darf entsprechend traeger sein.
	RequestCollectAllEggs  = 0.50,

	-- Reines Umschalten einer Einstellung. Kein Spam-Risiko fuer Spielwerte,
	-- aber jeder Wechsel stoesst ein Daten-Update an — daher nicht null.
	RequestSetLanguage     = 1.00,

	GetPlayerData          = 1.00,
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
