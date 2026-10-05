# HBB Paket 10 – Shop umgesetzt – 05.10.2026

Schalter: `FeatureFlags.SHOP_V1 = true`. Auf `false`: keine Kachel, kein Gratis-Griff, Tages-Quests wieder 100 Gold.

## Inhalt
| Teil | Umsetzung |
| --- | --- |
| Kachel | Menüleiste „Shop“ (Icon GoldGummy, „!“ wenn der Gratis-Griff offen ist). Sichtbar **ab der 2. Sitzung** (`stats.sessions`, PlayerService zählt pro Join; Veteranen gelten beim ersten Laden als Sitzung 1, sehen den Shop also sofort). |
| Gratis-Griff | einmal pro UTC-Tag **+75 GoldGummies** (`ShopConfig.FREE_GRAB_GOLD`), Remote `RequestClaimFreeGrab` (Cooldown 1 s), Server entscheidet. Fenster zeigt, wofür Gold da ist (Charm-Würfe) und dass Tages-Quests mehr geben. |
| Gold-Budget | weiter **12 Charm-Würfe/Tag**: 3 Tages-Quests × 75 + Gratis-Griff 75 = 300 Gold (Test prüft die Summe). |
| Robux-Pakete | 150 / 400 / 900 Gold als Developer Products. **Noch aus**: `productId = 0` → nicht sichtbar, nicht auszahlbar. Preis-Vorschlag ~25/60/120 R$; angezeigt wird der Preis aus dem Dashboard. |
| Kauf-Sicherheit | `ShopService.processReceipt`: bekannte Kauf-ID → nur bestätigen; sonst merken + auszahlen + **sofort speichern** (`PlayerService.saveConfirmed`); scheitert das Speichern → zurücknehmen und `NotProcessedYet` (Roblox fragt erneut). Spieler nicht da/nicht geladen → `NotProcessedYet`. Die letzten 100 Kauf-IDs bleiben im Spielstand (`data.shop.receipts`). |

Neue Dateien: `Config/ShopConfig`, `Modules/ShopRules` (rein), `Services/ShopService`, `UI/ShopPanel`, Test `tools/luau-tests/shop.test.lua`.
Spielstand: `data.shop = { freeGrabDay, receipts }`, `stats.sessions` (Migration legt beides an bzw. repariert).

## Entscheidung offen: Robux-Pakete einschalten?
Gold kauft Charm-Würfe und damit Kampfkraft (Pay-to-Win-Gefahr bei Kindern/Eltern). Die Pakete sind deshalb klein (≤ 3 Tage Gratis-Gold). Einschalten = Developer Products im Creator Dashboard anlegen und die IDs in `ShopConfig.PRODUCTS` eintragen. Alternativen ohne Kampfkraft (Kosmetik, 2× Honig-Gamepass) wären ein eigenes Paket.

## Prüfungen
`shop.test.lua` (Gratis-Griff inkl. 00:00 UTC, Kauf genau einmal, Rücknahme, begrenzte Liste, Budget 300, Kachel ab Sitzung 2 und nur mit Schalter, Migration Veteran/Neu/kaputt), `unlock_rules`, `gold_rules`, `migration_hbb`, alle anderen Tests/Sims/Checks grün.

## Studio-Testschritte
1. Neues Konto: keine Shop-Kachel. Rejoin (≥ 10 min später oder `stats.sessions` per Debug ≥ 2): Kachel mit „!“.
2. Shop öffnen → „Gratis holen!“ → +75 Gold fliegt in die Pille; Knopf „Heute abgeholt“, Zeit bis Mitternacht UTC.
3. Zweiter Klick → Meldung „Heute schon abgeholt“.
4. Tages-Quest abholen: +75 GoldGummies.
5. (Wenn Pakete eingerichtet) Kauf in Studio (Testkauf) → Gold kommt einmal; Output `[ShopService] … Kauf`.
