import re, os, sys, json
from pathlib import Path

import sys
ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "src"
files = sorted(ROOT.rglob("*.luau"))

def strip_comments(text):
    out = []
    i = 0
    n = len(text)
    while i < n:
        if text.startswith("--[[", i):
            j = text.find("]]", i)
            i = n if j < 0 else j + 2
        elif text.startswith("--", i):
            j = text.find("\n", i)
            i = n if j < 0 else j
        elif text[i] in "\"'":
            q = text[i]; i += 1
            while i < n and text[i] != q:
                if text[i] == "\\": i += 1
                i += 1
            i += 1
        else:
            out.append(text[i]); i += 1
    return "".join(out)

# ---- 1. Fuer jedes Modul: welche Felder bietet es an? -------------------------
exports = {}   # modulname -> set(felder)

for f in files:
    src = strip_comments(f.read_text(encoding="utf-8", errors="replace"))
    name = f.stem.replace(".server", "").replace(".client", "")
    keys = set()

    # a0) exportierte Typen: Types.PlayerData ist eine Typ-Referenz,
    #     kein Laufzeit-Feld — zaehlt aber als gueltiger Zugriff.
    for m in re.finditer(r"\bexport\s+type\s+(\w+)", src):
        keys.add(m.group(1))

    # a) function Mod.foo(...)  /  Mod.foo = ...
    for m in re.finditer(r"\bfunction\s+([A-Za-z_]\w*)[.:](\w+)\s*\(", src):
        keys.add(m.group(2))
    for m in re.finditer(r"^\s*([A-Za-z_]\w*)\.(\w+)\s*=", src, re.M):
        keys.add(m.group(2))

    # b) letztes "return { ... }" auf Modulebene
    idx = src.rfind("\nreturn {")
    if idx == -1 and src.startswith("return {"):
        idx = 0
    if idx != -1:
        block = src[idx:]
        depth = 0
        end = len(block)
        for i, ch in enumerate(block):
            if ch == "{": depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    end = i; break
        body = block[:end]
        # nur die aeussersten Schluessel: Tiefe 1
        depth = 0
        for m in re.finditer(r"[{}]|(\b[A-Za-z_]\w*)\s*=", body):
            if m.group(0) == "{": depth += 1
            elif m.group(0) == "}": depth -= 1
            elif depth == 1 and m.group(1):
                keys.add(m.group(1))
    exports[name] = keys

# ---- 2. Wer benutzt was? -----------------------------------------------------
problems = []
for f in files:
    raw = f.read_text(encoding="utf-8", errors="replace")
    src = strip_comments(raw)

    # local Alias = require(... .Modul)
    aliases = {}
    for m in re.finditer(r"local\s+([A-Za-z_]\w*)\s*=\s*require\s*\(([^)]*)\)", src):
        alias, path = m.group(1), m.group(2)
        mod = path.strip().rstrip(")").split(".")[-1].strip()
        if mod in exports:
            aliases[alias] = mod

    for alias, mod in aliases.items():
        for m in re.finditer(r"\b" + re.escape(alias) + r"\.(\w+)", src):
            field = m.group(1)
            if field not in exports[mod]:
                line = src[:m.start()].count("\n") + 1
                problems.append((str(f.relative_to(ROOT)), line, f"{alias}.{field}", mod))

if problems:
    print(f"{len(problems)} verdaechtige Zugriffe:\n")
    for path, line, expr, mod in problems:
        print(f"  {path}:{line}\n      {expr}   -> {mod} bietet dieses Feld nicht an")
else:
    print("Keine unbekannten Modul-Felder gefunden.")
