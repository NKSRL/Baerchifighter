# P3 – Tower in den Fokus: "Reise" (20.10.2026)

Schalter `ONBOARDING_V2` (setzt `UI_V2_GUIDE` voraus; aus = heutige Fuehrung). **Erweitert**, nicht ersetzt: `GuideSteps`/`GuideController` bleiben unveraendert.

## Etappen (alle aus dem echten Spielstand, `Modules/OnboardingRules`)
| # | ID | erfuellt wenn | Belohnung (Gold-Gummies) |
|---|---|---|---|
| 1 | hatch | `stats.totalHatched >= 1` oder Baerchi vorhanden | 3 |
| 2 | equip | Baerchi ausgeruestet oder Tower I schon betreten | 3 |
| 3 | tower1_enter | `records.I >= 1` | 5 |
| 4 | tower1_clear | `records.I >= 30` (Balken x/30) | 10 |
| 5 | tower3_open | `towers.unlocked.III` | 15 |
| 6 | final_open | `towers.unlocked.Final` | 20 |
| 7 | final_clear | `records.Final >= 100` (Balken x/100) | 30 |

Summe 86 Gold-Gummies. Die Belohnung ist klein und im Config (`OnboardingConfig`) einstellbar (offene Entscheidung 4).

## Gebaut
- `Config/OnboardingConfig`, `Modules/OnboardingRules` (rein, getestet), `Services/JourneyService` (Server zahlt genau einmal: erst "abgeholt" setzen, dann auszahlen), `UI/JourneyPanel` (einklappbar, Quad 0,3 s, "Spaeter", Ausblenden ueber Schliessen-Knopf), Remote `RequestJourney` (claim/skip/hide/show, Rate-Limit 0,4 s).
- Spielstand: `journey = { claimed, skipped, hidden }`, **Datenversion 19**. Migration: Bestandsspieler bekommen alle schon erfuellten Etappen als abgeholt, **ohne Nachzahlung** (Begruendung: stabile Waehrung, kein Abholen-Spam beim ersten Login; sie landen automatisch bei der passenden Etappe). Neue Spieler starten leer.
- Texte in 4 Sprachen (`ui.journey.*`, alle <= 12 Woerter).
- Debug: `D:Invoke("journey", "state" | "set", n | "reset")`.
- Tests: `onboarding_rules.test.lua` (neu, gruen), `migration_hbb.test.lua` (+3 Pruefungen, Versionsmarken auf 19), `guide_steps` gruen.

## Anti-Spoof
Der Client nennt nur eine ID; `OnboardingRules.canClaim` prueft ID-Typ, Bekanntheit, Erfuellung aus dem Server-Spielstand und "noch nicht abgeholt". Doppel-Claim, Fremd-IDs und Nicht-Strings werden abgelehnt (Regel-Test). Ein echter Remote-Spoof-Test in Studio steht aus.

## Nicht umgesetzt / offen
- **Spotlight (abgedunkelter Hintergrund mit Loch), Coach-Bubble mit Maskottchen, Tower-Eingang-Markierung, Reise-Anzeige im Kampf-UI, Moment nach Tower-Etappen, Konfetti, Belohnungs-Sound:** nicht gebaut. Das bestehende Beam/Timed-Hint-System bleibt unveraendert.
- **Eigene Bilder** (`Journey_Panel.png`, 7 Etappen-Icons, `Journey_Spot.png`): nicht gebaut; das Panel nutzt vorhandene Icons (egg, bear, swords, trophy, crown, globe).
- **Einstellungen:** wer die Leiste ausblendet, bekommt sie nur ueber `RequestJourney("show")` zurueck; ein Schalter im Einstellungsfenster fehlt noch.
- Panel-Position (links Mitte) ist ungeprueft gegen das Hud; Studio-Screenshots (de/en) stehen aus.
- Etappe 7 "Insel entdeckt" (P4) ist noch nicht verdrahtet.
- `check_ui`/`check_feedback`/`check_members`/`check_consistency`: nur Alt-Funde, keine aus P3.
- `migration_hbb` C4 war schon vorher rot (17 statt 20).
