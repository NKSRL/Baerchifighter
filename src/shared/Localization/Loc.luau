--!strict
-- Loc.luau
-- ReplicatedStorage/Localization/Loc.luau
--
-- Einzige Zustaendigkeit:
--   - Schluessel + Argumente → Text in der aktiven Sprache
--   - Die aktive Sprache halten und Beobachter bei einem Wechsel benachrichtigen
--
-- Laeuft auf Server UND Client. Der Server benutzt nur `Loc.msg` (er baut
-- Nachrichten aus Schluessel + Zahlen, ohne je einen Satz zu formulieren), der
-- Client loest sie mit `Loc.t` / `Loc.resolve` in den Text der Spielersprache
-- auf. Dieses Modul fasst bewusst KEINEN Roblox-Dienst an (kein
-- LocalizationService, keine Players): welche Sprache gilt, entscheidet der
-- LanguageController im Client und ruft dann `Loc.setLanguage`.
--
-- ============================================================
-- WARUM DAS SO GEBAUT IST (Effizienz: das Spiel darf nie laggen)
-- ============================================================
-- * Nur die AKTIVE Sprache und die Rueckfall-Sprache liegen im Speicher. Die
--   anderen werden erst geladen, wenn jemand sie waehlt (lazy require).
-- * Ein Nachschlagen ist EIN Tabellenzugriff. Ohne Argumente entsteht gar
--   kein neues Objekt; mit Argumenten genau ein gsub.
-- * Es gibt keine Heartbeat-Schleife und keinen Polling-Mechanismus. Beim
--   Sprachwechsel (selten: ein Klick des Spielers) werden gebundene Labels
--   einmal neu beschriftet.
-- * REGEL fuer Aufrufer: Texte, die jeden Frame aktualisiert werden (Timer),
--   werden NICHT jeden Frame neu aus dem Schluessel gebaut, sondern nur wenn
--   sich der Wert aendert (z.B. volle Sekunde). Das ist dieselbe Regel wie fuer
--   jede String-Arbeit in Luau.
--
-- ============================================================
-- SCHLUESSEL UND PLATZHALTER
-- ============================================================
-- Schluessel sind flache Strings mit Punkten ("err.not_enough_gummies").
-- Platzhalter heissen `{name}` und kommen aus dem Args-Table.
-- Zahlen im Args-Table werden automatisch mit Tausendertrennzeichen der
-- Sprache formatiert (1234567 → "1.234.567" / "1,234,567"). Dezimalzahlen
-- und alles, was anders aussehen soll, formatiert der Aufrufer vorher selbst
-- und uebergibt es als String.
-- Ein Args-Wert darf selbst eine Nachricht sein ({ k = ..., a = ... }); sie
-- wird rekursiv aufgeloest. So kann "Kein {egg} im Lager" den Eiernamen in
-- der Spielersprache einsetzen, obwohl der Server ihn nie ausgeschrieben hat.
--
-- Mehrzahl: Schluessel `foo.one` / `foo.other` und `Loc.tn("foo", n)`.
--
-- ============================================================
-- RUECKFALL
-- ============================================================
-- aktive Sprache → Englisch → Deutsch → der Schluessel selbst (in Klammern, damit
-- ein fehlender Eintrag im Spiel sofort auffaellt statt still leer zu bleiben).
-- Jeder fehlende Schluessel wird pro Sitzung genau einmal gewarnt.

local Types = require(script.Parent.Parent.Network.Types)

export type Lang = "de" | "en" | "fr" | "es"
export type LocMsg = Types.LocMsg

local Loc = {}

--------------------------------------------------------------------------------
-- Sprachen
--------------------------------------------------------------------------------

-- Reihenfolge = Reihenfolge in der Sprachauswahl.
-- `native` ist der Name der Sprache in ihr selbst: wer die Oberflaeche nicht
-- versteht, muss seine Sprache trotzdem finden.
Loc.LANGUAGES = {
	{ code = "de" :: Lang, native = "Deutsch"  },
	{ code = "en" :: Lang, native = "English"  },
	{ code = "fr" :: Lang, native = "Français" },
	{ code = "es" :: Lang, native = "Español"  },
}

-- Sprache, die gilt wenn weder Spieler noch Roblox-Einstellung etwas
-- Brauchbares liefern. Englisch: die meisten Spieler lesen es.
Loc.DEFAULT_LANGUAGE = "en" :: Lang

-- Wird der Schluessel in der aktiven Sprache nicht gefunden, springt der Text
-- hierher. Deutsch ist die Ursprungssprache des Projekts und deshalb immer
-- vollstaendig.
local FALLBACK_CHAIN: { Lang } = { "en", "de" }

local SEPARATORS: { [string]: string } = {
	de = ".",
	en = ",",
	fr = "\u{00A0}",   -- geschuetztes Leerzeichen: bricht nicht mitten in der Zahl um
	es = ".",
}

-- Dezimaltrenner. Englisch benutzt den Punkt, die anderen drei das Komma.
local DECIMALS: { [string]: string } = {
	de = ",",
	en = ".",
	fr = ",",
	es = ",",
}

-- Lazy Lader. Der Ordner `Strings` neben diesem Modul enthaelt pro Sprache ein
-- ModuleScript, das eine flache Tabelle { [schluessel] = text } zurueckgibt.
-- (Neben und nicht unter dem Modul: Rojo haengt Kinder nur an ein Modul mit
-- init-Datei, und die ist an anderer Stelle im Projekt bewusst verboten.)
local Strings = script.Parent.Strings

local LOADERS: { [string]: () -> { [string]: string } } = {
	de = function() return require(Strings.de) end,
	en = function() return require(Strings.en) end,
	fr = function() return require(Strings.fr) end,
	es = function() return require(Strings.es) end,
}

--------------------------------------------------------------------------------
-- Zustand
--------------------------------------------------------------------------------

local _loaded: { [string]: { [string]: string } } = {}
local _lang: Lang = Loc.DEFAULT_LANGUAGE
local _active: { [string]: string } = {}
local _separator: string = SEPARATORS[_lang]
local _decimal: string = DECIMALS[_lang]
local _initialized = false
local _warned: { [string]: boolean } = {}
local _listeners: { (Lang) -> () } = {}

-- Gebundene Beschriftungen. Schwache Schluessel: wird ein Label zerstoert und
-- vom Garbage Collector eingesammelt, verschwindet sein Eintrag von selbst.
type Binding = { key: string, args: { [string]: any }? }
local _bound: { [Instance]: Binding } = setmetatable({}, { __mode = "k" }) :: any

local function load(lang: string): { [string]: string }
	local cached = _loaded[lang]
	if cached then return cached end

	local loader = LOADERS[lang]
	if not loader then return {} end

	local ok, result = pcall(loader)
	if not ok then
		warn("[Loc] Sprachdatei konnte nicht geladen werden:", lang, result)
		result = {}
	end

	_loaded[lang] = result
	return result
end

--------------------------------------------------------------------------------
-- Sprache waehlen
--------------------------------------------------------------------------------

function Loc.isSupported(code: any): boolean
	return typeof(code) == "string" and LOADERS[code] ~= nil
end

-- "de-de" → "de", "es-mx" → "es", "pt-br" → nil (nicht unterstuetzt).
-- Eingabe ist die LocaleId von Roblox (immer kleingeschrieben, Bindestrich).
function Loc.fromLocaleId(localeId: string?): Lang?
	if typeof(localeId) ~= "string" then return nil end
	local prefix = string.lower(string.sub(localeId, 1, 2))
	if LOADERS[prefix] then
		return prefix :: Lang
	end
	return nil
end

function Loc.getLanguage(): Lang
	return _lang
end

function Loc.setLanguage(code: string): boolean
	if not LOADERS[code] then
		warn("[Loc] Unbekannte Sprache:", code)
		return false
	end
	if code == _lang and _initialized then
		return true
	end

	_initialized = true
	_lang        = code :: Lang
	_active      = load(code)
	_separator  = SEPARATORS[code] or ","
	_decimal    = DECIMALS[code] or "."

	-- Rueckfall-Sprachen vorladen, damit ein fehlender Schluessel spaeter nicht
	-- mitten im Spiel einen require ausloest.
	for _, fallback in FALLBACK_CHAIN do
		load(fallback)
	end

	-- Gebundene Labels neu beschriften. pcall pro Eintrag: ein zerstoertes oder
	-- seltsames Label darf den Wechsel nicht abbrechen.
	for instance, binding in _bound do
		pcall(function()
			(instance :: any).Text = Loc.t(binding.key, binding.args)
		end)
	end

	for _, callback in _listeners do
		local ok, err = pcall(callback, _lang)
		if not ok then
			warn("[Loc] Beobachter fehlgeschlagen:", err)
		end
	end

	return true
end

-- Meldet sich bei jedem Sprachwechsel. Gibt eine Funktion zurueck, die die
-- Anmeldung wieder aufhebt (fuer UI die zerstoert wird).
function Loc.onChanged(callback: (Lang) -> ()): () -> ()
	table.insert(_listeners, callback)
	return function()
		local index = table.find(_listeners, callback)
		if index then
			table.remove(_listeners, index)
		end
	end
end

--------------------------------------------------------------------------------
-- Zahlen
--------------------------------------------------------------------------------

-- 1234567 → "1.234.567" (de/es), "1,234,567" (en), "1 234 567" (fr)
function Loc.formatNumber(value: number): string
	local rounded = math.floor(value)
	-- Schneller Pfad: die allermeisten Zahlen im UI sind kleiner als 1000
	if rounded > -1000 and rounded < 1000 then
		return tostring(rounded)
	end

	-- "%.0f" statt tostring: tostring schreibt grosse Zahlen (ab 1e15) in
	-- Exponentenschreibweise, die ein Zaehler nie zeigen soll.
	local text  = string.format("%.0f", math.abs(rounded))
	local len   = #text
	local first = len % 3
	local parts: { string } = {}

	if first > 0 then
		parts[1] = string.sub(text, 1, first)
	end
	for i = first + 1, len, 3 do
		parts[#parts + 1] = string.sub(text, i, i + 2)
	end

	local out = table.concat(parts, _separator)
	if rounded < 0 then
		out = "-" .. out
	end
	return out
end

-- Dezimalzahl mit dem Trenner der Sprache: (1.5, 2) → "1.50" bzw. "1,50".
-- Fuer Multiplikatoren ("x1,50") und Prozentwerte.
function Loc.formatDecimal(value: number, digits: number): string
	local text = string.format("%." .. digits .. "f", value)
	if _decimal == "." then
		return text
	end
	return (string.gsub(text, "%.", _decimal))
end

--------------------------------------------------------------------------------
-- Nachschlagen
--------------------------------------------------------------------------------

local function lookup(key: string): string?
	-- Erster Zugriff vor jedem setLanguage (z.B. ein Toast, der vor dem
	-- LanguageController kommt): die Standardsprache laden statt "[key]" zu
	-- zeigen. Der Server ruft nie lookup auf und laedt deshalb nie Text.
	if not _initialized then
		_initialized = true
		_active = load(_lang)
		for _, fallback in FALLBACK_CHAIN do
			load(fallback)
		end
	end

	local text = _active[key]
	if text ~= nil then return text end

	for _, fallback in FALLBACK_CHAIN do
		if fallback ~= _lang then
			local table_ = _loaded[fallback]
			if table_ then
				text = table_[key]
				if text ~= nil then return text end
			end
		end
	end
	return nil
end

local resolveArg: (any) -> string

-- Formatiert EINEN Platzhalter-Wert. `spec` ist der Teil nach dem Doppelpunkt:
--   {n}        automatisch: Ganzzahlen mit Tausendertrenner, sonst tostring
--   {n:raw}    Zahl unveraendert (Level, Jahreszahlen ... nie ein Trenner)
--   {n:dur}    Sekunden als Dauer ("2m 05s", "1h 12m")
--   {n:d2}     Dezimalzahl mit 2 Nachkommastellen und Trenner der Sprache
-- Das Format steht damit im TEXT und nicht im Code: eine Sprache kann es
-- anders haben wollen, ohne dass irgendein Aufrufer etwas davon weiss.
local function formatArg(value: any, spec: string): string
	if spec ~= "" and typeof(value) == "number" then
		if spec == "raw" then
			return tostring(value)
		elseif spec == "dur" then
			return Loc.formatDuration(value)
		else
			local digits = tonumber(string.sub(spec, 2))
			if string.sub(spec, 1, 1) == "d" and digits then
				return Loc.formatDecimal(value, digits)
			end
		end
	end
	return resolveArg(value)
end

-- Setzt {name}- und {name:format}-Platzhalter ein. Unbekannte Platzhalter
-- bleiben stehen, damit ein Tippfehler im Text sichtbar ist statt still zu
-- verschwinden.
local function interpolate(template: string, args: { [string]: any }): string
	local result = string.gsub(template, "{([%w_]+):?(%w*)}", function(name: string, spec: string): string?
		local value = args[name]
		if value == nil then return nil end
		return formatArg(value, spec)
	end)
	return result
end

function resolveArg(value: any): string
	local kind = typeof(value)
	if kind == "string" then
		return value
	elseif kind == "number" then
		if value == math.floor(value) then
			return Loc.formatNumber(value)
		end
		return tostring(value)
	elseif kind == "table" then
		return Loc.resolve(value)
	end
	return tostring(value)
end

-- Haupt-Funktion. Ohne `args` wird kein neues Objekt erzeugt.
function Loc.t(key: string, args: { [string]: any }?): string
	local template = lookup(key)
	if template == nil then
		if not _warned[key] then
			_warned[key] = true
			warn("[Loc] Schluessel fehlt:", key)
		end
		return "[" .. key .. "]"
	end

	if args == nil then
		return template
	end
	return interpolate(template, args)
end

-- Mehrzahl. Franzoesisch zaehlt 0 und 1 als Einzahl, die anderen drei Sprachen
-- nur genau 1. Die Zahl steht automatisch als {n} zur Verfuegung.
function Loc.tn(key: string, n: number, args: { [string]: any }?): string
	local singular = if _lang == "fr" then (n >= 0 and n < 2) else (n == 1)
	local suffix = if singular then ".one" else ".other"

	local merged: { [string]: any } = { n = n }
	if args then
		for k, v in args do
			merged[k] = v
		end
	end
	return Loc.t(key .. suffix, merged)
end

-- Fuer Anzeigenamen von Konfigurationseintraegen ("baerchi.RedBaerchi.name").
-- Faellt auf `fallback` zurueck, WENN der Schluessel noch nicht uebersetzt ist,
-- ohne eine Warnung zu erzeugen — so koennen Config-Eintraege schrittweise
-- umgestellt werden.
function Loc.name(key: string, fallback: string?): string
	local template = lookup(key)
	if template ~= nil then return template end
	if fallback ~= nil then return fallback end
	return Loc.t(key)
end

function Loc.has(key: string): boolean
	return lookup(key) ~= nil
end

-- Restzeiten: "45s", "2m 05s", "1h 12m" (Einheiten kommen aus time.* der Sprache).
function Loc.formatDuration(seconds: number): string
	local total = math.max(0, math.floor(seconds))

	if total >= 3600 then
		return Loc.t("time.hm", {
			h = string.format("%d", total // 3600),
			m = string.format("%02d", (total % 3600) // 60),
		})
	end
	if total >= 60 then
		return Loc.t("time.ms", {
			m = string.format("%d", total // 60),
			s = string.format("%02d", total % 60),
		})
	end
	return Loc.t("time.s", { s = string.format("%d", total) })
end

--------------------------------------------------------------------------------
-- Nachrichten ueber das Netzwerk
--------------------------------------------------------------------------------

-- Baut eine Nachricht, die der Server an den Client schicken kann. Mehr ist es
-- nicht: eine Tabelle { k, a }. Der Server formuliert nie einen Satz.
function Loc.msg(key: string, args: { [string]: any }?): LocMsg
	return { k = key, a = args }
end

-- Sammel-Update 2.4: zwei Meldungen zu einer ("A  •  B"). Der Server haengt
-- so Teil-Ertraege aneinander, ohne selbst einen Satz zu bauen — der Trenner
-- steht im Text (Schluessel "msg.join") und damit bei der Sprache.
function Loc.join(a: any, b: any): LocMsg
	return { k = "msg.join", a = { a = a, b = b } }
end

function Loc.isMsg(value: any): boolean
	return typeof(value) == "table" and typeof((value :: any).k) == "string"
end

-- Nimmt alles an, was ein Server schicken kann: eine Nachricht, einen
-- (aelteren) fertigen Text oder etwas Unerwartetes — und liefert immer einen
-- anzeigbaren String.
function Loc.resolve(value: any): string
	if typeof(value) == "string" then
		return value
	end
	if Loc.isMsg(value) then
		local msg = value :: LocMsg
		return Loc.t(msg.k, msg.a)
	end
	return tostring(value)
end

--------------------------------------------------------------------------------
-- Beschriftungen binden
--------------------------------------------------------------------------------

-- Beschriftet ein Label/Button jetzt UND bei jedem kuenftigen Sprachwechsel.
-- Fuer statische Texte ("Abbrechen", Panel-Titel). Texte, die sich aus
-- Spielzustand ergeben, bleiben in der refresh-Funktion ihres Moduls und
-- haengen sich stattdessen mit Loc.onChanged an.
function Loc.bind(instance: Instance, key: string, args: { [string]: any }?)
	_bound[instance] = { key = key, args = args }
	;(instance :: any).Text = Loc.t(key, args)
end

return Loc
