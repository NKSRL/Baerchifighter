# Entwurf zur Freigabe – Paket 6.3: Ei-Kauf über freigeschaltete Rarities

Stand 05.10.2026 · **nicht gebaut** (laut Auftrag „eigener Entwurf zur Freigabe, bevor gebaut wird“).

## Idee (Auftraggeber)
Man schaltet einen besseren Ei-Typ zum Kaufen frei, wenn man bestimmte Rarities zieht. Das kaufbare Ei ist **nie das beste**, bei dem man schon ist.

## Vorschlag

1. **Freischalt-Tabelle** (`EggConfig.MERCHANT_UNLOCKS`): erste gezogene Rarity (aus `data.discovered`) → kaufbares Ei

   | Rarity einmal gezogen | Ei beim Händler | Preis (Gummies, ohne Rebirth-Mult.) |
   |---|---|---|
   | (Start) | Basis-Ei | 50 (wie heute) |
   | Rare | Zucker-Ei | 2.500 |
   | Epic | Goldenes **oder** Nebel-Ei (Pfad des höchsten freien) | 60.000 |
   | Legendary | Platin / Kristall / Void (eine Stufe unter dem besten freien Ei) | 1,5 Mio. |
   | Mythic | Sonnen / Prisma / Schatten | 40 Mio. |

2. **Nie das beste Ei:** Der Händler bietet das höchste so freigeschaltete Ei an, das **mindestens eine Stufe unter** `EggTree.highestUnlocked` liegt. Wer gerade Gold freigeschaltet hat, kann also Zucker kaufen, Gold aber erst, wenn Platin frei ist.
3. **Preise** steigen mit der Stufe (Faktor ~25 je Stufe) und haben eine **Tagesgrenze** (z. B. 10 Käufe je Ei-Typ und UTC-Tag), damit sich Gummy-Polster nicht unbegrenzt in Eier tauschen lassen. Das ist auch die zweite Geldsenke vor dem Rebirth (Entscheidung 11.5).
4. **Rebirth:** Die Freischaltung bleibt (sie hängt an `discovered` und am Ei-Baum, beides übersteht Rebirths).
5. **Presse:** Gekaufte Eier sind pressbar, außer dem Basis-Ei (wie heute, `PRESS_NO_BASIC_EGG`).

## Was vor dem Bau geprüft werden muss
* `egg_tree_sim.lua` mit Kauf-Strom: Die Freischalt-Tage der Knoten dürfen nicht kippen. Kauf-Eier zählen in `eggTree.hatched`; mit Tagesgrenze 10 und den Preisen oben schätze ich bis zu −20 % Spielzeit bis Gold/Kristall. Rebirth-Gates bremsen danach ohnehin.
* `progression_pacing.lua`: Gummy-Abfluss gegen Look-Zeiten.

## Offene Fragen an dich
1. Tabelle so (Rarity → Ei) oder lieber „N verschiedene Bärchis einer Rarity“?
2. Tagesgrenze ja (Vorschlag 10) oder nur über den Preis bremsen?
3. Ein Händler mit Auswahl oder je Stufe ein eigener Stand?
