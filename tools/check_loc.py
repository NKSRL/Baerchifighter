#!/usr/bin/env python3
"""
check_loc.py — Prüft das Lokalisierungssystem (Localization/Loc + Strings/*.luau).

Findet drei Arten von Fehlern, bevor ein Spieler sie sieht:

  1. VOLLSTÄNDIGKEIT  — jede Sprache muss genau dieselben Schlüssel haben wie
                        Deutsch (die Ursprungssprache). Fehlt einer, sieht der
                        Spieler Englisch statt seiner Sprache.
  2. PLATZHALTER      — {name} muss in jeder Sprache für denselben Schlüssel
                        gleich heißen. Ein vertippter Platzhalter bleibt sonst
                        als "{hav}" im Text stehen. Mehrzahl-Schlüssel
                        (.one/.other) müssen als Paar vorhanden sein.
  3. VERWENDUNG       — jeder Schlüssel, der im Code als Literal auftaucht
                        (Loc.t / Loc.tn / Loc.msg / Loc.bind / Loc.name),
                        muss in Deutsch existieren. Dynamisch zusammengesetzte
                        Schlüssel ("baerchi." .. id .. ".name") kann das Skript
                        nicht prüfen und überspringt sie.

Zusätzlich (nur Information, kein Fehler):

  * UNBENUTZT         — Schlüssel, die im Code nirgends vorkommen.
  * OFFEN             — Zeilen mit festem deutschem Text im Code, die noch nicht
                        auf Loc umgestellt sind (Heuristik, siehe --todo).

Aufruf:

    python3 tools/check_loc.py            # Prüfung, Exit-Code 1 bei Fehlern
    python3 tools/check_loc.py --todo     # zusätzlich die offenen Textstellen
    python3 tools/check_loc.py PFAD/ZU/src

Braucht nur Python 3, keine Pakete.
"""

import re
import sys
from pathlib import Path

LANGS = ["de", "en", "fr", "es"]
BASE = "de"

ENTRY = re.compile(r'\["([^"]+)"\]\s*=\s*"((?:[^"\\]|\\.)*)"')
PLACEHOLDER = re.compile(r"\{([A-Za-z0-9_]+)(?::[A-Za-z0-9]+)?\}")

# Loc.t("key"...), Loc.tn("key"...), Loc.msg("key"...), Loc.name("key"...),
# Loc.has("key"), Loc.bind(x, "key"...)
# (?!\s*\.\.) — ein Literal, hinter dem ein ".." folgt, ist nur der ANFANG eines
# dynamisch zusammengesetzten Schluessels ("egg." .. id .. ".name") und wird
# deshalb nicht geprueft.
USE_SIMPLE = re.compile(r'Loc\.(t|tn|msg|name|has)\(\s*"([^"]+)"(?!\s*\.\.)')
USE_BIND = re.compile(r'Loc\.bind\(\s*[^,]+,\s*"([^"]+)"(?!\s*\.\.)')
ANY_LITERAL = re.compile(r'"([A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)+)"')

# Schlüssel, die der Code dynamisch zusammensetzt — hier stehen die Präfixe, die
# als "benutzt" gelten, damit sie nicht fälschlich als unbenutzt gemeldet werden.
DYNAMIC_PREFIXES = (
    "baerchi.", "rarity.", "mutation.", "egg.", "building.", "rank.", "skill.",
    "charm.", "event.",
)


def find_src(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    if args:
        return Path(args[0])
    here = Path(__file__).resolve().parent.parent
    return here / "src"


def load_strings(src):
    folder = src / "shared" / "Localization" / "Strings"
    result = {}
    for lang in LANGS:
        path = folder / f"{lang}.luau"
        if not path.exists():
            print(f"FEHLER: {path} fehlt")
            sys.exit(2)
        text = path.read_text(encoding="utf-8")
        entries = {}
        for key, value in ENTRY.findall(text):
            if key in entries:
                print(f"FEHLER [{lang}] Schlüssel doppelt: {key}")
                entries[key] = None  # Marker
            entries[key] = value
        result[lang] = entries
    return result


def check_completeness(strings):
    errors = 0
    base = set(strings[BASE])
    for lang in LANGS:
        if lang == BASE:
            continue
        keys = set(strings[lang])
        for key in sorted(base - keys):
            print(f"FEHLT   [{lang}] {key}")
            errors += 1
        for key in sorted(keys - base):
            print(f"ÜBRIG   [{lang}] {key}   (steht nicht in {BASE}.luau)")
            errors += 1
    return errors


def check_placeholders(strings):
    errors = 0
    for key, base_value in strings[BASE].items():
        want = set(PLACEHOLDER.findall(base_value))
        for lang in LANGS:
            if lang == BASE or key not in strings[lang]:
                continue
            got = set(PLACEHOLDER.findall(strings[lang][key]))
            if got != want:
                print(
                    f"PLATZHALTER [{lang}] {key}: "
                    f"erwartet {sorted(want)}, gefunden {sorted(got)}"
                )
                errors += 1

    # Mehrzahl-Paare
    for lang in LANGS:
        keys = set(strings[lang])
        for key in keys:
            if key.endswith(".one") and key[:-4] + ".other" not in keys:
                print(f"PAAR    [{lang}] {key} hat kein .other")
                errors += 1
            if key.endswith(".other") and key[:-6] + ".one" not in keys:
                print(f"PAAR    [{lang}] {key} hat kein .one")
                errors += 1
    return errors


def lua_files(src):
    for path in sorted(src.rglob("*.luau")):
        if "Localization" in path.parts and "Strings" in path.parts:
            continue
        yield path


def strip_comment(line):
    # Grobe Heuristik: ab "--" ist Kommentar, sofern es nicht in einem String steht.
    in_str = None
    i = 0
    while i < len(line):
        c = line[i]
        if in_str:
            if c == "\\":
                i += 2
                continue
            if c == in_str:
                in_str = None
        else:
            if c in "\"'":
                in_str = c
            elif line.startswith("--", i):
                return line[:i]
        i += 1
    return line


def check_usage(src, strings):
    errors = 0
    used = set()
    base = strings[BASE]

    for path in lua_files(src):
        rel = path.relative_to(src)
        for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            line = strip_comment(raw)
            for kind, key in USE_SIMPLE.findall(line):
                if kind == "tn":
                    candidates = [key + ".one", key + ".other"]
                else:
                    candidates = [key]
                for candidate in candidates:
                    used.add(candidate)
                    if candidate not in base:
                        # Loc.name(key, fallback) darf bewusst auf einen noch
                        # nicht übersetzten Schlüssel zeigen.
                        if kind == "name" and "," in line.split(key, 1)[1].split(")")[0]:
                            continue
                        print(f"UNBEKANNT {rel}:{number}  {candidate}")
                        errors += 1
            for key in USE_BIND.findall(line):
                used.add(key)
                if key not in base:
                    print(f"UNBEKANNT {rel}:{number}  {key}")
                    errors += 1
            # Schluessel, die ueber eine Variable oder ein if-Ausdruck laufen
            # (Loc.msg(if x then "a.b" else "c.d")): jedes Literal, das EXAKT ein
            # bekannter Schluessel ist, zaehlt als benutzt.
            for literal in ANY_LITERAL.findall(line):
                if literal in base:
                    used.add(literal)
    return errors, used


# --- OFFEN: feste deutsche Texte im Code (Heuristik) --------------------------

GERMAN_HINT = re.compile(
    r"\b(der|die|das|und|nicht|kein|keine|dein|deine|du|ist|sind|noch|jetzt|"
    r"zu|von|mit|für|fuer|auf|wird|kann|gerade|alle|dieser|dieses|bitte|"
    r"kostet|brauchst|hast|Baerchi|Gummies)\b",
    re.IGNORECASE,
)
STRING = re.compile(r'"((?:[^"\\]|\\.){3,})"')
# Zeilen, in denen ein String SICHER beim Spieler landet (UI-Aufrufe): hier zaehlt
# jedes Literal mit Leerzeichen oder grossem Anfangsbuchstaben, auch ohne
# deutsche Signalwoerter.
UI_CALL = re.compile(r"Theme\.(label|button|bigButton|bodyText|sectionLabel|dialogHeader|outlineText)\(|\.Text\s*=|Toast\.(show|success|info)\(")
SKIP_LINE = re.compile(r"\b(print|warn|error|assert)\s*\(|require\(|GetService|WaitForChild|FindFirstChild")


def find_open_texts(src):
    result = {}
    for path in lua_files(src):
        rel = str(path.relative_to(src))
        # Tools-/Debug-Dateien sind Entwickler-Oberfläche, nicht Spieler-Text
        if rel.endswith("DebugService.luau"):
            continue
        hits = []
        for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            line = strip_comment(raw)
            if not line.strip() or SKIP_LINE.search(line):
                continue
            is_ui = bool(UI_CALL.search(line))
            for text in STRING.findall(line):
                if is_ui and re.search(r"[A-Za-zÄÖÜäöüß]{3,}", text) and not re.fullmatch(r"[A-Za-z0-9_.:]+", text):
                    hits.append((number, text))
                    break
                if " " not in text.strip():
                    continue
                if GERMAN_HINT.search(text):
                    hits.append((number, text))
                    break
        if hits:
            result[rel] = hits
    return result


def main():
    src = find_src(sys.argv)
    show_todo = "--todo" in sys.argv

    strings = load_strings(src)
    print(f"Sprachen: {', '.join(f'{l} ({len(strings[l])} Schlüssel)' for l in LANGS)}")

    errors = 0
    errors += check_completeness(strings)
    errors += check_placeholders(strings)
    usage_errors, used = check_usage(src, strings)
    errors += usage_errors

    unused = [
        k for k in strings[BASE]
        if k not in used and not k.startswith(DYNAMIC_PREFIXES)
        and not (k.endswith(".one") or k.endswith(".other"))
    ]
    if unused:
        print(f"\nINFO: {len(unused)} Schlüssel werden im Code (noch) nicht verwendet:")
        for key in unused[:40]:
            print(f"  {key}")
        if len(unused) > 40:
            print(f"  ... und {len(unused) - 40} weitere")

    open_texts = find_open_texts(src)
    total_open = sum(len(v) for v in open_texts.values())
    print(f"\nINFO: {total_open} Zeilen mit festem deutschem Text in {len(open_texts)} Dateien (noch nicht auf Loc umgestellt)")
    if show_todo:
        for rel, hits in sorted(open_texts.items(), key=lambda kv: -len(kv[1])):
            print(f"\n  {rel}  ({len(hits)})")
            for number, text in hits:
                shown = text if len(text) <= 78 else text[:75] + "..."
                print(f"    {number:>5}: {shown}")
    else:
        for rel, hits in sorted(open_texts.items(), key=lambda kv: -len(kv[1]))[:12]:
            print(f"  {len(hits):>4}  {rel}")
        print("  (alle Stellen: python3 tools/check_loc.py --todo)")

    print()
    if errors:
        print(f"{errors} Fehler")
        sys.exit(1)
    print("Lokalisierung konsistent")


if __name__ == "__main__":
    main()
