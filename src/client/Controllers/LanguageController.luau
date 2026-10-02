--!strict
-- LanguageController.luau
-- StarterPlayerScripts/Controllers/LanguageController.luau
--
-- Einzige Zustaendigkeit:
--   - Entscheiden, in welcher Sprache der Client gerade laeuft, und das Loc
--     mitteilen
--   - Die Wahl des Spielers an den Server schicken (damit sie gespeichert wird)
--
-- ============================================================
-- WELCHE SPRACHE GILT — in dieser Reihenfolge
-- ============================================================
--   1. Die gespeicherte Wahl des Spielers (data.language vom Server).
--   2. Die Roblox-Sprache seines Kontos/Clients (Player.LocaleId, zum Beispiel
--      "de-de" → Deutsch). Das ist der Normalfall fuer jeden, der nie im Menue
--      war — er sieht das Spiel sofort in seiner Sprache.
--   3. Englisch, wenn Roblox eine Sprache meldet, die wir nicht uebersetzt haben.
--
-- Der Client wertet die Roblox-Sprache SOFORT aus, noch bevor der erste
-- Server-Sync da ist. Sonst waere der allererste Toast (und alles, was
-- vorher beschriftet wird) einen Moment lang in der falschen Sprache.
--
-- ============================================================
-- WARUM DIE WAHL OPTIMISTISCH GILT
-- ============================================================
-- Klickt der Spieler eine Sprache an, wechselt die Oberflaeche sofort — nicht
-- erst, wenn der Server bestaetigt hat. Das ist eine reine Darstellungs-
-- Einstellung (kein Spielwert), der Server prueft sie nur und legt sie ab.
-- Damit ein PlayerDataUpdated, das noch den ALTEN Wert traegt (weil es vor
-- dem Klick gesendet wurde), die Wahl nicht kurz zurueckdreht, wird die eigene
-- Wahl fuer PENDING_SECONDS bevorzugt, bis der Server denselben Wert meldet.

local Players             = game:GetService("Players")
local LocalizationService = game:GetService("LocalizationService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")

local Types   = require(ReplicatedStorage.Network.Types)
local Remotes = require(ReplicatedStorage.Network.Remotes)
local Loc     = require(ReplicatedStorage.Localization.Loc)

local ClientState = require(script.Parent.ClientState)

local LanguageController = {}

-- So lange gewinnt die eigene Wahl gegen einen (moeglicherweise veralteten)
-- Server-Wert. Deutlich laenger als der Rate-Limit-Abstand des Remotes.
local PENDING_SECONDS = 5

-- nil = "automatisch" (Roblox-Sprache)
local _choice: string? = nil
local _pendingUntil = 0

-- Letzter vom Server gemeldeter Wert, damit nicht bei JEDEM PlayerDataUpdated
-- (das ist haeufig) neu verglichen werden muss, ob sich die Sprache aendert.
local _lastServerValue: string? = nil
local _seenServerValue = false

--------------------------------------------------------------------------------
-- Roblox-Sprache
--------------------------------------------------------------------------------

local function detectRobloxLanguage(): Loc.Lang
	local fromPlayer = Loc.fromLocaleId(Players.LocalPlayer.LocaleId)
	if fromPlayer then return fromPlayer end

	local fromService = Loc.fromLocaleId(LocalizationService.RobloxLocaleId)
	if fromService then return fromService end

	return Loc.DEFAULT_LANGUAGE
end

local function applyChoice()
	local code = _choice
	if code == nil or not Loc.isSupported(code) then
		code = detectRobloxLanguage()
	end
	Loc.setLanguage(code :: string)
end

--------------------------------------------------------------------------------
-- Oeffentliche API
--------------------------------------------------------------------------------

-- Die gewaehlte Sprache; nil bedeutet "automatisch". NICHT die gerade
-- aktive Sprache — die liefert Loc.getLanguage().
function LanguageController.getChoice(): string?
	return _choice
end

-- `code` = "de" | "en" | "fr" | "es", oder nil fuer "automatisch".
function LanguageController.choose(code: string?)
	if code ~= nil and not Loc.isSupported(code) then return end
	if code == _choice then return end

	_choice       = code
	_pendingUntil = os.clock() + PENDING_SECONDS
	applyChoice()

	Remotes.RequestSetLanguage:FireServer(code)
end

--------------------------------------------------------------------------------
-- Server-Stand
--------------------------------------------------------------------------------

local function onData(update: Types.PlayerDataUpdate)
	local serverValue = update.language

	-- Die gespeicherte Sprache aendert sich nur durch den Spieler selbst —
	-- fast jedes Update traegt denselben Wert wie das letzte. Dann gibt es
	-- nichts zu tun.
	if _seenServerValue and serverValue == _lastServerValue then
		return
	end
	_seenServerValue  = true
	_lastServerValue  = serverValue

	-- Eigene, noch nicht bestaetigte Wahl hat Vorrang
	if os.clock() < _pendingUntil then
		if serverValue == _choice then
			_pendingUntil = 0   -- bestaetigt
		end
		return
	end

	if serverValue ~= _choice then
		_choice = serverValue
		applyChoice()
	end
end

--------------------------------------------------------------------------------
-- Initialisierung
--------------------------------------------------------------------------------

function LanguageController.init()
	-- Sofort: Roblox-Sprache, noch vor dem ersten Server-Sync
	applyChoice()

	ClientState.onChanged(onData)

	print("[LanguageController] Initialisiert |", Loc.getLanguage())
end

return LanguageController
