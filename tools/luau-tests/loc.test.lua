-- Tests fuer Localization/Loc (laufen mit: node run.mjs loc.test.lua)
local Loc = require(RS.Localization.Loc)
local function check(name, got, want)
  if got ~= want then
    __log("FAIL", name, "got=[" .. tostring(got) .. "] want=[" .. tostring(want) .. "]")
  else
    __log("ok  ", name)
  end
end
-- Standardsprache (en) ohne setLanguage
check("default en", Loc.t("ui.menu.eggs"), "Eggs")
Loc.setLanguage("de")
check("de simple", Loc.t("ui.menu.eggs"), "Eier")
check("de args+number", Loc.t("err.not_enough_gummies", {have = 1234567, need = 50}), "Nicht genug Gummies (du hast 1.234.567, du brauchst 50)")
Loc.setLanguage("en")
check("en number", Loc.t("err.not_enough_gummies", {have = 1234567, need = 50}), "Not enough Gummies (you have 1,234,567, you need 50)")
Loc.setLanguage("fr")
check("fr nbsp", Loc.formatNumber(1234567), "1\u{00A0}234\u{00A0}567")
check("fr 1000", Loc.formatNumber(1000), "1\u{00A0}000")
check("neg", Loc.formatNumber(-12345), "-12\u{00A0}345")
check("100000", Loc.formatNumber(100000), "100\u{00A0}000")
check("fr plural 0", Loc.tn("ui.rebirth.reward_eggs", 0, {mult="1,50"}), "Ensuite : Multiplicateur x1,50  —  +0 Oeuf d'Ascension")
check("fr plural 2", Loc.tn("ui.rebirth.reward_eggs", 2, {mult="1,50"}), "Ensuite : Multiplicateur x1,50  —  +2 Oeufs d'Ascension")
Loc.setLanguage("es")
check("es plural 1", Loc.tn("msg.rebirth_done_eggs", 1, {count=3, mult="2,25"}), "Rebirth 3 conseguido: Multiplicador x2,25 y 1 Huevo de Ascensión")
-- verschachtelte Nachricht
local m = Loc.msg("err.egg_not_buyable", { egg = Loc.msg("egg.AscensionEgg.name") })
check("nested", Loc.resolve(m), "No hay Huevo de Ascensión en el almacén (no se puede comprar)")
check("legacy string", Loc.resolve("Fertiger Text"), "Fertiger Text")
check("garbage", Loc.resolve(nil), "nil")
-- fehlender Schluessel
check("missing", Loc.t("gibt.es.nicht"), "[gibt.es.nicht]")
check("name fallback", Loc.name("gibt.es.nicht", "Fallback"), "Fallback")
-- decimal
Loc.setLanguage("de"); check("dec de", Loc.formatDecimal(1.5, 2), "1,50")
Loc.setLanguage("en"); check("dec en", Loc.formatDecimal(1.5, 2), "1.50")
-- bind + Sprachwechsel
local label = { Text = "" }
setmetatable(label, nil)
Loc.bind(label, "ui.menu.fight")
check("bind en", label.Text, "Fight")
Loc.setLanguage("fr")
check("bind fr", label.Text, "Combat")
-- Listener
local seen = nil
local off = Loc.onChanged(function(l) seen = l end)
Loc.setLanguage("de")
check("listener", seen, "de")
off(); seen = nil
Loc.setLanguage("es")
check("unlisten", seen, nil)
-- fromLocaleId
check("locale de-de", Loc.fromLocaleId("de-de"), "de")
check("locale es-mx", Loc.fromLocaleId("es-mx"), "es")
check("locale pt-br", Loc.fromLocaleId("pt-br"), nil)
check("unsupported set", Loc.setLanguage("xx"), false)
Loc.setLanguage("fr")
check("fr num in args", Loc.t("ui.rebirth.cost", {cost=1500, have=999}), "Coûte 1\u{00A0}500 Gummies  (tu as 999)")
Loc.setLanguage("de")
check("dur hm", Loc.formatDuration(3725), "1h 02m")
check("dur ms", Loc.formatDuration(125), "2m 05s")
check("dur s", Loc.formatDuration(45), "45s")
Loc.setLanguage("fr")
check("dur fr", Loc.formatDuration(125), "2 min 05 s")
check("dur in text", Loc.t("err.egg_wait", {seconds = 3725}), "Encore 1 h 02 min avant que l'oeuf soit prêt")
check("dec spec", Loc.t("ui.rebirth.status", {count = 2, mult = 2.25}), "Rebirth 2  —  Multiplicateur x2,25")
