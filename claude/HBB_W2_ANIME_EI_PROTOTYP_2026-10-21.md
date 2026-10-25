# Welt 2: Anime-Ei, Prototyp der 4 Basis-Bärchis + Import der 4 offenen Welt-1-Pets (21.10.2026)

## Was
1. **Import in Studio:** `Pet_Genesis`, `Pet_Infinity`, `Pet_Shade`, `Pet_Ascendant` (FBX lagen fertig in `Export/`) nach `ReplicatedStorage.Assets.BaerchiModels`, Farben mit dem Inhalt von `tools/pets/studio_recolor_w1.lua` gesetzt (alle Teile gefärbt, Neon für Leuchtteile). `MODEL_BY_ID` hatte die Einträge schon. Test: `BaerchiMesh.buildFor` baut alle vier ohne Fehler (22 / 20 / 20 / 21 Teile, PrimaryPart `_body`). Damit haben alle 29 Pets ein eigenes Modell.
2. **Blender-Prototyp Anime-Ei (Basis-Satz, 4 Bärchis):** `assets/pets/Anime_Pets.blend`, Skripte `tools/pets/build_w2_anime.py` (Bau) und `render_w2_anime.py` (Vorschau). Gleicher Körper und gleiche Konventionen wie die Welt-1-Pets (Omega-Körper, je Teil ein flaches Material, Endungen `_body/_ears/_feet/_cute_tail`, Gesicht -Y, ≤ 30 Teile). Vorschau: `assets/pets/_preview_w2_front.png`, `_back.png`, `_34.png`.

## Die 4 Charaktere (Archetyp, eigenes Design, eigene Namen)
| Modell | Arbeitsname | Erkennbar an | Bewusst anders als das Original | Teile |
|---|---|---|---|---|
| `Anime_Pirat` | Gummi-Pirat | Strohhut, Gummi-Arm mit Faust, Schärpe | Hutband türkis statt rot, gelbe Schärpe statt Weste, keine Narbe | 23 |
| `Anime_Ninja` | Orange-Ninja | Orange, Stirnband mit Metallplatte, Schnurrhaar-Wangen, Schriftrolle | blaues Band, eigenes Wirbel-Symbol (kein Blatt), cremefarbener Schal statt Overall | 25 |
| `Anime_Krieger` | Sternenkrieger | schwarzes Stachelhaar, oranger Kampfanzug, blaue Schärpe | Farben rot-orange/blau, keine Kanji, kein Symbol, Haar nur 1 Teil | 20 |
| `Anime_Jaeger` | Karo-Jäger | grün/schwarzer Karo-Umhang, Schwert auf dem Rücken, Stirnmal | Mal als roter Strich, Umhang als Rückenplatte, keine Ohrringe, keine Maske | 24 |

## Rechtliche Linie (gilt für alle weiteren Anime-Eier)
Wiedererkennung nur über **Typ und Silhouette** (Hut, Haar, Umhang-Muster), nie über Originalkostüm als Ganzes, Logos, Symbole, Schriftzeichen, Zitate oder Originalnamen. Keine Namen wie Ruffy/Naruto/Goku/Tanjiro oder Titel (One Piece, Naruto, Dragon Ball, Demon Slayer) im Spiel, in Beschreibungen, Asset-Namen auf Roblox, Thumbnails oder Marketing. Das senkt das Risiko, schließt es aber nicht aus: Roblox kann Inhalte auch ohne Strike entfernen, und wir sind keine Rechtsberatung. Je näher spätere Formen (Gear-5-Typ, Super-Form) kommen, desto mehr eigene Merkmale braucht es (eigene Farben, eigene Form, eigener Name).

## Technik-Notizen
- Der Körper ist ein Block mit Füßen, ohne Hals. Kleidung ist deshalb als rechteckiges Band **unter** dem Maul (z -0.76) gebaut, Stirnband/Hut oberhalb der Augen. Bänder: `solidify` plus `recalc_face_normals`, sonst culled Roblox die Außenwände.
- Haare und Karo-Muster je als **ein** zusammengeführtes Mesh (Teile-Budget).
- Farben der Studio-Nachfärbung stehen als Hex in `build_w2_anime.py` (`PETS` und `acc(...)`-Aufrufe), analog zu `studio_recolor_w1.lua`.

## Offen / nächster Schritt
- **Abstimmung:** Vorschau ansehen, Änderungswünsche nennen (z. B. Gum-Arm kräftiger, Ninja-Schal, Haarform).
- Nach OK: FBX-Export (`export_all()` im Skript), Import nach `ReplicatedStorage.Assets.BaerchiModels`, `studio_recolor_w2_anime.lua` analog W1, Einträge in `BaerchiModels.MODEL_BY_ID`.
- Danach Verdrahtung (eigenes Paket): Anime-Ei (`EggConfig`, ab Welt 2 frei über `worlds.unlocked.World2`), `BaerchiConfig`-Einträge (4 Pets), Namen/Texte über `Localization/Names` (de/en/fr/es), Ei-Modell in Blender, Balance gegen `progression_pacing.lua`. Weitere Anime-Eier: je 4–5 Charaktere plus spätere „Super-Formen“ als höhere Seltenheit.
- Nicht verifiziert: Sichtprüfung der 4 importierten Welt-1-Pets im Spiel (Größe, Namensschild), Playtest.
- **Du:** in Studio *Datei → Auf Roblox speichern* (4 neue Modelle sind nur lokal), die neuen Dateien im Repo committen. Modelle zusätzlich als `.rbxm` nach `src/shared/Assets` exportieren.
