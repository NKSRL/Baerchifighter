"""make_modulkarte.py - erzeugt docs/ARCHITEKTUR.md (Modulkarte)

Eine Zeile je .luau-Datei unter src/: Pfad, Zeilenzahl, Zustaendigkeit. Die
Zustaendigkeit kommt aus dem Kopfkommentar ("Einzige Zustaendigkeit:" und der
erste Spiegelstrich danach; sonst die erste Satzzeile nach dem Pfad).
So muss eine Claude-Sitzung nicht 290 Dateien oeffnen, um die richtige zu finden.

Aufruf:  python tools/make_modulkarte.py          (schreibt docs/ARCHITEKTUR.md)
         python tools/make_modulkarte.py --check  (Exit 1, wenn die Datei veraltet ist)
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")
OUT = os.path.join(ROOT, "docs", "ARCHITEKTUR.md")

HEAD = """# Architektur und Modulkarte

Erzeugt von `tools/make_modulkarte.py` aus den Kopfkommentaren. Nicht von Hand
bearbeiten: Kopfkommentar der Datei aendern und das Werkzeug laufen lassen
(`check_all.py` meldet eine veraltete Karte).

## Datenfluss in zehn Zeilen

1. `src/shared` → ReplicatedStorage, `src/server` → ServerScriptService, `src/client` → StarterPlayerScripts.
2. Server-Start nur in `server/Core/GameManager.server.luau`: alle Services laden → `init()` → `start()`. DebugService nur in Studio.
3. Client-Start nur in `client/Main.client.luau`: Controller und UI-Module laden und verdrahten.
4. Client-Anfragen kommen nur über `RateLimiter.connect` (Remote-Name = Cooldown-Schlüssel in `NetworkConfig`).
5. Remote-Namen nur in `shared/Network/Remotes.luau`, Datenstrukturen nur in `shared/Network/Types.luau`.
6. Spielstand: `PlayerService` (einziger Spieler-DataStore), Migration in `server/Util/PlayerMigration.luau`.
7. Währungen schreibt nur `EconomyService`. Der Server ist autoritativ.
8. Client-Speicher: `client/Controllers/ClientState.luau` hört als einziger auf `PlayerDataUpdated`.
9. Werte in `shared/Config/*`, reine (testbare) Regeln in `shared/Modules/*`, Welt-Bau in `server/Util/MapBuild/*`.
10. Texte: `shared/Localization` (`Loc`, `Names` für Config-Namen, `WorldText` für Texte in der Welt), Schalter: `FeatureFlags.isOn`.

## Module
"""


def responsibility(text: str) -> str:
    lines = text.split("\n")[:80]
    comments = []
    for line in lines:
        s = line.strip()
        if s.startswith("--!"):
            continue
        if not s.startswith("--"):
            if s == "":
                continue
            break
        comments.append(s.lstrip("-").strip())
    for i, c in enumerate(comments):
        if re.match(r"(Einzige )?Zust(ae|ä)ndigkeit", c, re.I):
            rest = c.split(":", 1)[1].strip() if ":" in c else ""
            if rest:
                return rest
            parts = []
            for nxt in comments[i + 1:]:
                if nxt == "":
                    break
                if nxt.startswith("- ") and parts:
                    break
                parts.append(nxt.lstrip("- ").strip())
            if parts:
                return " ".join(parts)
    # Rueckfall: erste Satzzeile nach Dateiname und Pfad
    for c in comments:
        if not c or c.endswith(".luau") or "/" in c.split(" ")[0] or set(c) <= set("=-"):
            continue
        return c
    return "(kein Kopfkommentar)"


def build() -> str:
    rows = []
    for dirpath, dirs, files in os.walk(SRC):
        dirs.sort()
        for name in sorted(files):
            if not name.endswith(".luau") or "Strings" in dirpath.split(os.sep):
                continue
            path = os.path.join(dirpath, name)
            text = open(path, encoding="utf-8").read()
            rel = os.path.relpath(path, SRC).replace(os.sep, "/")
            resp = re.sub(r"\s+", " ", responsibility(text)).replace("|", "/")
            # Historie (Datum, Paket) gehoert nicht in die Karte
            resp = re.sub(r"\s*\([^()]*(\d{1,2}\.\d{1,2}\.|Paket|Schalter|Sammel)[^()]*\)", "", resp)
            resp = re.split(r"(?<=[a-z\)\"])\. ", resp, maxsplit=1)[0].rstrip(". ")
            if len(resp) > 110:
                resp = resp[:107].rstrip(" ,;:") + "..."
            rows.append((rel, text.count("\n") + 1, resp))
    out = [HEAD]
    current = None
    for rel, n, resp in rows:
        group = "/".join(rel.split("/")[:-1]) or "."
        if group != current:
            current = group
            out.append(f"\n### {group}\n")
        out.append(f"- `{rel.split('/')[-1]}` ({n}) – {resp}")
    out.append("\nSprachdateien `shared/Localization/Strings/{de,en,fr,es}.luau`: nur per Grep nach Schlüssel ansprechen.\n")
    return "\n".join(out)


def main() -> int:
    text = build()
    if "--check" in sys.argv:
        old = open(OUT, encoding="utf-8").read() if os.path.exists(OUT) else ""
        if old != text:
            print("docs/ARCHITEKTUR.md ist veraltet: python tools/make_modulkarte.py")
            return 1
        print("Modulkarte aktuell")
        return 0
    with open(OUT, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)
    print(f"docs/ARCHITEKTUR.md geschrieben ({text.count(chr(10))} Zeilen)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
