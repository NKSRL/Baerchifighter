# UI-Vorschau ohne Studio (08.10.2026)

Laesst die echten Client-UI-Module (`src/client`, `src/shared`) in einer
Roblox-Attrappe laufen (`shim.lua` + `driver.lua`, luau-CLI), nimmt den
entstandenen Instanz-Baum als JSON und zeichnet ihn im Browser (`render.js`,
Playwright/Chromium) nach Roblox-Layoutregeln: UDim2, AnchorPoint,
UIListLayout, UIPadding, AutomaticSize, UIScale, UICorner, UIStroke,
UIGradient, TextScaled mit UITextSizeConstraint, ZIndex unter Geschwistern.

Eine VORSCHAU, kein Ersatz fuer Studio (Schriftglaettung, Emoji, Bilder
angenaehert; 3D gibt es nicht). Fuer Layout, Hierarchie, Ueberlauf, Abstaende
und Kontraste reicht es — das alte CombatPanel sieht darin aus wie im
Playtest-Screenshot.

    python tools/ui_preview/preview.py --sizes 1920x1080,1366x768,1024x768,812x375 --scenario new2 --hud
    python tools/ui_preview/preview.py --old ...          # altes CombatPanel (vorher)
    python tools/ui_preview/preview.py --lang fr|es|en    # Sprache
    python tools/ui_preview/preview.py --pass             # Gamepass besessen
    python tools/ui_preview/preview.py --pass-ready       # Pass-Id gesetzt (kaufbar)
    python tools/ui_preview/preview.py --running          # Baerchi kaempft gerade
    python tools/ui_preview/preview.py --leak             # 50x oeffnen/schliessen, Instanzen zaehlen

Szenarien (`driver.lua`): `only1` (nur Tower I, 12/30), `new2` (Tower II gerade
frei), `mid` (Tower II gewaehlt, 23/45), `all` (alles offen), `endless`, `poor`.
Ausgabe: PNG + HTML + JSON-Bericht (kleinste Schrift in px, Texte, die nicht
passen) je Groesse im `--out`-Ordner (Standard `docs/screens`).

Braucht: `luau` (PATH oder `$LUAU`), `pip install playwright` + Chromium,
Schrift `fredoka-one.woff2` (Fredoka One, SIL Open Font License) liegt bei.
