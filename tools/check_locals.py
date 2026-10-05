#!/usr/bin/env python3
"""
check_locals.py — zaehlt die lokalen Namen auf oberster Ebene jeder .luau-Datei

Warum: Roblox (Studio und Live) erlaubt hoechstens 200 lokale Variablen pro
Funktion — der Haupt-Chunk eines Moduls ist auch eine Funktion. Der luau-CLI
aus dem Open-Source-Release meldet das NICHT (er kompiliert 210 klaglos),
Studio bricht das Modul beim Laden ab. Passiert am 05.10.2026 mit MapConfig
(210 lokale Konstanten), behoben durch Konstanten direkt in der
Rueckgabe-Tabelle.

Gezaehlt wird grob, aber sicher nach oben: jede Zeile in Spalte 0, die mit
`local` beginnt, zaehlt mit allen Namen vor dem `=` (`local a, b = ...` = 2,
`local function f` = 1).

Aufruf:  python3 tools/check_locals.py      (Exit-Code 1 ab LIMIT)
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "src"
LIMIT = 200   # Roblox
WARN = 180    # rechtzeitig umbauen

def count(path: Path) -> int:
    total = 0
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.startswith("local "):
            continue
        if line.startswith("local function "):
            total += 1
            continue
        names = line[len("local "):].split("=", 1)[0]
        names = re.sub(r":[^,]*", "", names)          # Typ-Annotationen weg
        total += len([n for n in names.split(",") if n.strip()])
    return total

def main() -> int:
    rows = sorted(((count(p), p.relative_to(ROOT)) for p in ROOT.rglob("*.luau")), reverse=True)
    failed = False
    for n, rel in rows:
        if n >= LIMIT:
            print(f"FEHLER {rel}: {n} lokale Namen auf oberster Ebene (Roblox-Grenze {LIMIT})")
            failed = True
        elif n >= WARN:
            print(f"WARNUNG {rel}: {n} lokale Namen (Grenze {LIMIT}) — Konstanten in eine Tabelle legen")
    print(f"Hoechster Wert: {rows[0][0]} ({rows[0][1]})")
    return 1 if failed else 0

if __name__ == "__main__":
    sys.exit(main())
