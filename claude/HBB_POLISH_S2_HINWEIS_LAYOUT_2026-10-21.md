# Polish Schritt 2a: Hinweis am Kampf-Button (21.10.2026)

## Was
`GuideController`: Der Hinweis-Satz (GuideHint) sass bei Schritten mit Pfeil von oben (z. B. "tower") 25 px ueber dem Kampf-Button-Rahmen und ueberlappte ihn. Jetzt rueckt er ueber den hoechsten Punkt des wippenden Pfeils. Ohne Ziel oder bei Pfeil von links (Kachelleiste rechts) bleibt der alte Standardplatz (`HINT_DEFAULT_POS`).

## Warum
Aufraeumen des ersten Eindrucks (Polish-Check 21.10.): Hinweis, Pfeil und Kampf-Button sollen sich nicht verdecken.

## Umfang
- Nur `src/client/Controllers/GuideController.luau` (3 kleine Stellen), kein neues Flag (reine Layout-Korrektur, Rueckbau = Backup).
- Backup: `backup_vor_hinweis_layout_2026-10-21/GuideController.luau` und `ServerStorage.Backup_vor_Hinweis_Layout_2026-10-21`.
- Studio und Repo sind gleich (21617 Bytes).

## Geprueft
- `luau-compile --null`: OK. `check_locals.py`: OK (hoechster Wert 192, MapConfig).
- Play in Studio: keine Fehler in der Konsole, Hinweis wird gesetzt (sichtbar, Text vorhanden).

## Ungeprueft / offen
- Sichtprobe in 1080p-Fenster: im kleinen Studio-Viewport (467 px hoch) verdeckt das kurze Offline-Honig-Popup den Hinweis; auf kleinen Bildschirmen koennte er oben anstossen (kein Clamp, bewusst KISS).
- Hinweis und Pfeil bleiben bei offenem Panel sichtbar (Panel-Ueberlappung unveraendert).
- Weitere Punkte der Liste: Schwebetexte aufraeumen, Boden/Wege, Licht/Wasser, Buttons erst bei Freischaltung einblenden. Die schwarzen Quader sind die Bestenlisten (kein Fehler).
