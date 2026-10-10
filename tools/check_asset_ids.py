#!/usr/bin/env python3
"""
check_asset_ids.py — Waechter fuer die in Studio eingetragenen Asset-IDs

Seit 10.10.2026 stehen in Studio echte IDs in
    WorldFXConfig.SOUNDS        (9 Sounds der Klang-Kulisse + waspHum)
    WorldFXConfig.TEXTURE_IDS   (19 Welt-Texturen)
    SkillFXConfig TEXTURES      (29 Show-Texturen)
Ein Update mit einer leeren Fassung dieser Tabellen wuerde sie in Studio
wieder loeschen (der Einspiel-Befehl ersetzt die ganze Source). Dieses
Werkzeug zaehlt die gefuellten Eintraege.

Aufruf:
    python3 tools/check_asset_ids.py                 # Repo (src/shared/Config)
    python3 tools/check_asset_ids.py datei.rbxmx     # Update-Datei: nur die
                                                     # Configs, die sie enthaelt
Exit 1, wenn eine Tabelle weniger gefuellte Eintraege hat als MINDESTENS.
"""
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Datei -> [(Tabelle, Start-Muster, Mindestzahl gefuellter Eintraege)]
MINDESTENS = {
    "WorldFXConfig": [
        ("WorldFXConfig.SOUNDS", r"WorldFXConfig\.SOUNDS\s*=\s*\{", 9),
        ("WorldFXConfig.TEXTURE_IDS", r"WorldFXConfig\.TEXTURE_IDS\s*=\s*\{", 19),
    ],
    "SkillFXConfig": [
        ("SkillFXConfig.TEXTURES", r"local TEXTURES\b[^=]*=\s*\{", 29),
    ],
}


def block(source: str, start_pattern: str):
    """Text der Tabelle ab dem Start-Muster bis zur passenden schliessenden Klammer."""
    m = re.search(start_pattern, source)
    if not m:
        return None
    depth, i = 0, m.end() - 1
    while i < len(source):
        c = source[i]
        if c == "-" and source.startswith("--", i):
            i = source.find("\n", i)
            if i < 0:
                break
            continue
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return source[m.end():i]
        i += 1
    return None


def count_filled(text: str):
    """(gefuellt, gesamt): Strings mit Inhalt bzw. Zahlen > 0, Kommentare ignoriert."""
    filled = total = 0
    for line in text.splitlines():
        line = line.split("--", 1)[0]
        for value in re.findall(r"\w+\s*=\s*(\"[^\"]*\"|\d+)", line):
            total += 1
            if value.startswith('"'):
                filled += value != '""'
            else:
                filled += int(value) > 0
    return filled, total


def check(name: str, source: str):
    problems = []
    for table, pattern, minimum in MINDESTENS[name]:
        text = block(source, pattern)
        if text is None:
            problems.append(f"{table}: nicht gefunden")
            print(f"!!  {table:<28} nicht gefunden")
            continue
        filled, total = count_filled(text)
        ok = filled >= minimum
        print(f"{'OK ' if ok else '!! '} {table:<28} {filled:>2}/{total:<2} gefuellt (mindestens {minimum})")
        if not ok:
            problems.append(f"{table}: nur {filled} gefuellt, erwartet >= {minimum}")
    return problems


def sources_from_rbxmx(path: Path):
    """{Name: Source} der ModuleScripts aus MINDESTENS, die in der Datei stecken."""
    found = {}
    for item in ET.parse(path).getroot().iter("Item"):
        props = item.find("Properties")
        if props is None:
            continue
        name = source = None
        for p in props:
            if p.get("name") == "Name":
                name = p.text
            elif p.get("name") == "Source":
                source = "".join(p.itertext())
        if name in MINDESTENS and source is not None:
            found[name] = source
    return found


def main():
    problems = []
    if len(sys.argv) > 1:
        path = Path(sys.argv[1])
        found = sources_from_rbxmx(path)
        print(f"Update-Datei {path.name}: enthaelt {', '.join(sorted(found)) or 'keine der ID-Configs'}")
        for name, source in sorted(found.items()):
            problems += check(name, source)
    else:
        for name in MINDESTENS:
            source = (ROOT / "src/shared/Config" / f"{name}.luau").read_text(encoding="utf-8")
            problems += check(name, source)
    if problems:
        print(f"{len(problems)} Problem(e): diese IDs wuerden in Studio leer werden.")
        return 1
    print("Asset-IDs vollstaendig.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
