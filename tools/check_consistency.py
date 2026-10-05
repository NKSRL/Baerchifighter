#!/usr/bin/env python3
"""
Konsistenz-Pruefung fuer das RBL-Projekt.

Prueft die Dinge, die Roblox erst beim Start bemerkt und die Luau selbst
nicht sieht, weil sie ueber mehrere Dateien verteilt sind:

  1. Gebaeude-IDs muessen in ALLEN neun Listen identisch sein.
  2. Bei RateLimiter.connect muessen Remote-Objekt und Cooldown-Schluessel
     denselben Namen tragen.
  3. Jedes verbundene Remote sollte einen eigenen Cooldown haben.
  4. Jedes Modul in der GameManager-Boot-Liste muss als Datei existieren.
  5. Jeder Service mit init() oder start() muss in der Boot-Liste stehen.
  6. Jede .luau-Datei unter src/ beginnt mit --!strict.

Aufruf:  python3 tools/check_consistency.py [pfad/zu/src]
"""
import re, sys
from pathlib import Path

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "src"

def strip_comments(text: str) -> str:
    out, i, n = [], 0, len(text)
    while i < n:
        if text.startswith("--[[", i):
            j = text.find("]]", i); i = n if j < 0 else j + 2
        elif text.startswith("--", i):
            j = text.find("\n", i); i = n if j < 0 else j
        else:
            out.append(text[i]); i += 1
    return "".join(out)

def read(rel: str) -> str:
    return strip_comments((ROOT / rel).read_text(encoding="utf-8", errors="replace"))

def block(src: str, pattern: str) -> str | None:
    m = re.search(pattern, src, re.S)
    return m.group(1) if m else None

issues: list[str] = []

# ---------- 1. Gebaeude-IDs ----------
types_src = read("shared/Network/Types.luau")
m = re.search(r"export type BuildingId\s*=(.*?)\n\s*\n", types_src, re.S)
canonical = set(re.findall(r'\|\s*"(\w+)"', m.group(1))) if m else set()
print(f"Kanonische Gebaeude-IDs (Types.BuildingId): {sorted(canonical)}\n")

def keys_of(body):
    """Nur die Schluessel der AEUSSERSTEN Ebene — verschachtelte Felder wie
    `offset` oder `color` gehoeren nicht dazu."""
    found, depth = set(), 0
    for m in re.finditer(r"[{}]|(\w+)\s*=", body):
        tok = m.group(0)
        if tok == "{":
            depth += 1
        elif tok == "}":
            depth -= 1
        elif depth == 0 and m.group(1):
            found.add(m.group(1))
    return found
def quoted(body):  return set(re.findall(r'"(\w+)"', body))
def ids_of(body):  return set(re.findall(r'id\s*=\s*"(\w+)"', body))

checks = [
    ("MapConfig.BUILDING_OFFSETS",   read("shared/Config/MapConfig.luau"),
     r"local BUILDING_OFFSETS[^=]*=\s*\{(.*?)\n\}", keys_of),
    ("MapConfig.BUILDING_ORDER",     read("shared/Config/MapConfig.luau"),
     r"local BUILDING_ORDER[^=]*=\s*\{(.*?)\}", quoted),
    # Die Ausbau-Tabellen sind mit v7 von EconomyConfig nach BuildingBehavior
    # gewandert: ihr Effekt-Text beschreibt die Mechanik des jeweiligen
    # Gebaeudes, und die kennt nur BuildingBehavior.
    ("BuildingBehavior.BUILDING_UPGRADES", read("shared/Config/BuildingBehavior.luau"),
     r"local BUILDING_UPGRADES[^=]*=\s*\{(.*?)\n\}", keys_of),
    ("BuildingBehavior.BEHAVIORS", read("shared/Config/BuildingBehavior.luau"),
     r"local BEHAVIORS[^=]*=\s*\{(.*?)\n\}", keys_of),
    ("Theme.BUILDING_COLORS", read("client/UI/Theme.luau"),
     r"local BUILDING_COLORS[^=]*=\s*\{(.*?)\n\}", keys_of),
    ("IslandService.VALID_BUILDINGS", read("server/Services/IslandService.luau"),
     r"local VALID_BUILDINGS[^=]*=\s*\{(.*?)\}", keys_of),
    ("WorldController.BUILDING_NAMES", read("client/Controllers/WorldController.luau"),
     r"local BUILDING_NAMES[^=]*=\s*\{(.*?)\}", keys_of),
    ("BuildingPanel.BUILDINGS",       read("client/UI/BuildingPanel.luau"),
     r"local BUILDINGS[^=]*=\s*\{(.*?)\n\}", ids_of),
    ("Types.createDefaultPlayerData", types_src,
     r"buildings = \{(.*?)\n\t\t\t\}", ids_of),
]

for label, src, pattern, extract in checks:
    body = block(src, pattern)
    if body is None:
        issues.append(f"{label}: Block nicht gefunden — Pruefung nicht moeglich")
        continue
    found = extract(body)
    if found != canonical:
        issues.append(
            f"Gebaeude-IDs weichen ab in {label}:\n"
            f"      gefunden: {sorted(found)}\n"
            f"      erwartet: {sorted(canonical)}"
        )

# ---------- 2./3. Remotes ----------
connected = set()
for f in sorted(ROOT.rglob("*.luau")):
    src = strip_comments(f.read_text(encoding="utf-8", errors="replace"))
    for mm in re.finditer(r'RateLimiter\.connect(?:Function)?\(\s*Remotes\.(\w+)\s*,\s*"(\w+)"', src):
        connected.add(mm.group(1))
        if mm.group(1) != mm.group(2):
            issues.append(
                f'RateLimiter-Schluessel passt nicht zum Remote:\n'
                f'      {f.relative_to(ROOT)}: Remotes.{mm.group(1)} mit "{mm.group(2)}"'
            )

cooldowns = set(re.findall(r"^\s*(\w+)\s*=\s*[\d.]+", read("shared/Config/NetworkConfig.luau"), re.M))
missing = connected - cooldowns
if missing:
    issues.append(f"Remotes ohne eigenen Cooldown (nutzen den Default): {sorted(missing)}")

# ---------- 4./5. Boot-Liste ----------
gm = read("server/Core/GameManager.server.luau")
listed = set()
for mm in re.finditer(r"module\s*=\s*ServerScriptService\.(\w+)\.(\w+)", gm):
    folder, name = mm.group(1), mm.group(2)
    listed.add(name)
    if not (ROOT / "server" / folder / f"{name}.luau").exists():
        issues.append(f"GameManager verweist auf fehlendes Modul: server/{folder}/{name}.luau")

for f in sorted((ROOT / "server" / "Services").glob("*.luau")):
    src = strip_comments(f.read_text(encoding="utf-8", errors="replace"))
    for phase in ("init", "start"):
        if re.search(rf"function \w+\.{phase}\(", src) and f.stem not in listed:
            issues.append(f"Service hat {phase}(), steht aber nicht in der Boot-Liste: {f.stem}")

# ---------- 6. --!strict ----------
# Die Typpruefung ist nur so gut wie ihre schwaechste Datei: ein Modul ohne
# strict liefert anderen Modulen ungeprueft `any` zurueck.
for f in sorted(ROOT.rglob("*.luau")):
    first = f.read_text(encoding="utf-8", errors="replace").lstrip("\ufeff").split("\n", 1)[0].strip()
    if first != "--!strict":
        issues.append(f"Datei beginnt nicht mit --!strict: {f.relative_to(ROOT)} (erste Zeile: {first[:40]!r})")

# ---------- 7. Tower-IDs (v15) ----------
# Types.TowerId muss genau die Tower aus TowerConfig.TOWERS nennen, und jeder
# Tower braucht seinen Namen in den Strings (tower.<id>.name).
tm = re.search(r"export type TowerId\s*=([^\n]*)", types_src)
tower_types = set(re.findall(r'"(\w+)"', tm.group(1))) if tm else set()
tower_cfg = set(re.findall(r'id\s*=\s*"(\w+)",\s*index\s*=', read("shared/Config/TowerConfig.luau")))
if not tower_types or tower_types != tower_cfg:
    issues.append(f"Tower-IDs weichen ab: Types.TowerId {sorted(tower_types)} / TowerConfig {sorted(tower_cfg)}")
de_strings = read("shared/Localization/Strings/de.luau")
for tid in sorted(tower_cfg):
    if f'["tower.{tid}.name"]' not in de_strings:
        issues.append(f"Tower {tid} hat keinen Namen in Strings/de (tower.{tid}.name)")

# ---------- 8. DataStore-Regel (v15) ----------
# Spieler-DataStore NUR in PlayerService, OrderedDataStores NUR in
# LeaderboardService. Sonst konkurrieren zwei Module um dasselbe Budget.
for f in sorted(ROOT.rglob("*.luau")):
    src = strip_comments(f.read_text(encoding="utf-8", errors="replace"))
    if ":GetDataStore(" in src and f.stem != "PlayerService":
        issues.append(f"GetDataStore ausserhalb von PlayerService: {f.relative_to(ROOT)}")
    if ":GetOrderedDataStore(" in src and f.stem != "LeaderboardService":
        issues.append(f"GetOrderedDataStore ausserhalb von LeaderboardService: {f.relative_to(ROOT)}")

print("=" * 62)
if issues:
    print(f"{len(issues)} Befund(e):\n")
    for i in issues:
        print("  - " + i + "\n")
    sys.exit(1)
print("Alles konsistent.")
