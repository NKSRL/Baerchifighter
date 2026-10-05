--!strict
-- DebugConfig.luau
-- ReplicatedStorage/Config/DebugConfig.luau
--
-- Einzige Zustaendigkeit:
--   - Schalter fuer Diagnose-Ausgaben, die im normalen Spiel stoeren
--
-- Manche Vorgaenge passieren laufend von selbst (der Autopilot fuettert alle
-- paar Sekunden). Eine Log-Zeile pro Vorgang fuellt die Konsole mit Hunderten
-- Zeilen und verdeckt Warnungen. Solche Ausgaben laufen nur, wenn der Schalter
-- hier an ist. Seltene Spieler-Aktionen (Ei oeffnen, Fusion, Rebirth) loggen
-- weiter immer.

return {
	-- true = eine Zeile pro Fuetterung (HoneyService). Zum Nachrechnen von
	-- XP/HP beim Balancing.
	VERBOSE_LOG = false,

	-- true = FunnelService schreibt jeden Trichter-Schritt und jedes
	-- UI-Ereignis ins Output. In Studio gehen keine echten Analytics-Events
	-- raus (Roblox nimmt sie nur im veroeffentlichten Spiel an) — das Log ist
	-- dort der einzige Nachweis, dass ein Schritt ausgeloest wurde.
	FUNNEL_LOG = true,
}
