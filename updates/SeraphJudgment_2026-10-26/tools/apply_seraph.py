# Fuegt die Himmelsgericht-Stuecke (pkg/) in Kopien der Studio-Quelltexte ein.
# Jeder Anker muss genau 1x vorkommen, jeder neue Name 0x (F52). Bei einem
# Fehler wird NICHTS geschrieben. Schreibt nach <out>/<Pfad>.luau und eine
# Anker-Tabelle (JSON) fuer den Studio-Befehl.
# Aufruf: python -I apply_seraph.py <studio_src> <pkg> <out>
import sys, os, json

SRC, PKG, OUT = sys.argv[1], sys.argv[2], sys.argv[3]

def rd(p):
    with open(p, encoding="utf-8") as f:
        return f.read()

def piece(name):
    return rd(os.path.join(PKG, name))

FILES = {
    "controller": "StarterPlayer/StarterPlayerScripts/Controllers/SkillFXController.luau",
    "fxconfig": "ReplicatedStorage/Config/SkillFXConfig.luau",
    "skillconfig": "ReplicatedStorage/Config/SkillConfig.luau",
    "baerchiconfig": "ReplicatedStorage/Config/BaerchiConfig.luau",
    "de": "ReplicatedStorage/Localization/Strings/de.luau",
    "en": "ReplicatedStorage/Localization/Strings/en.luau",
    "es": "ReplicatedStorage/Localization/Strings/es.luau",
    "fr": "ReplicatedStorage/Localization/Strings/fr.luau",
}

# (Datei, Name, Anker, Modus, Text)  Modus: before = vor dem Anker, after = hinter dem Anker, replace
EDITS = [
    ("controller", "Ctx-Felder", "\tstartedAt: number?, -- gemeinsame Uhr, nur opt-in in moves; angelbell nutzt sie\n}\n", "after_line1", piece("patch_ctx.luau")),
    ("controller", "Kamera seraphSide", "\tlocal chaseEye: Vector3? = nil\n", "after", "\tlocal seraphSide = 0   -- 26.10. (Himmelsgericht): Kamera-Seite, einmal beim Start\n"),
    ("controller", "Kamera-Stil seraph", "\t\telse\n\t\t\tlocal a = k * math.pi * 0.9\n", "before", piece("patch_cinematic.luau")),
    ("controller", "Bausteine", "\n-- Abspielen\n--------------------------------------------------------------------------------\n", "before", "\n" + piece("blocks_part1.luau") + piece("blocks_part2.luau")),
    ("fxconfig", "Doku", "--   Helfer (LOW): bridge (Bruecken-Punkt), tube (Zylinder-Stueck), shuriken (Vierstern).\n", "after", piece("fxdoc.txt")),
    ("fxconfig", "Texturen", "\t\tshockring = 94175665045126,  -- wie CometImpact.shockring (ring)\n\t},\n", "after", piece("textures.luau")),
    ("fxconfig", "Eintrag", "\n}\n\n-- Unbekannte Faehigkeit", "before", piece("fxentry.luau")),
    ("skillconfig", "Eintrag", "\n}\n\n-- ============================================================\n-- v15: AUFLADEN STATT COOLDOWN", "before", piece("skillentry.luau")),
    ("baerchiconfig", "defaultSkill", "\t\tdefaultSkill = \"SeraphGrace\", eggSource = {},\n", "replace", "\t\tdefaultSkill = \"SeraphJudgment\", eggSource = {}, -- 26.10.2026 Himmelsgericht (vorher SeraphGrace)\n"),
    ("de", "Texte", "\t[\"skill.SeraphGrace.name\"] = \"Seraphen-Segen\",\n", "after", piece("strings_de.txt")),
    ("en", "Texte", "\t[\"skill.SeraphGrace.name\"] = \"Seraph Blessing\",\n", "after", piece("strings_en.txt")),
    ("es", "Texte", "\t[\"skill.SeraphGrace.name\"] = \"Bendición Seráfica\",\n", "after", piece("strings_es.txt")),
    ("fr", "Texte", "\t[\"skill.SeraphGrace.name\"] = \"Bénédiction Séraphique\",\n", "after", piece("strings_fr.txt")),
]

# Neue Namen, die vorher NICHT vorkommen duerfen (je Datei)
NEW_NAMES = {
    "controller": ["local SER", "BLOCKS.seraphwings", "BLOCKS.seraphspear", "BLOCKS.halogate",
                   "BLOCKS.seraphmark", "BLOCKS.lightnuke", "seraphGate", "seraphHit", "seraphSide",
                   "style == \"seraph\"", "SeraphWing", "SeraphGateRing"],
    "fxconfig": ["SeraphJudgment"],
    "skillconfig": ["SeraphJudgment"],
    "baerchiconfig": ["SeraphJudgment"],
    "de": ["SeraphJudgment"], "en": ["SeraphJudgment"], "es": ["SeraphJudgment"], "fr": ["SeraphJudgment"],
}

sources = {k: rd(os.path.join(SRC, v)) for k, v in FILES.items()}
ok = True
report = []
for key, names in NEW_NAMES.items():
    for n in names:
        c = sources[key].count(n)
        if c != 0:
            ok = False
            report.append(f"DUP  {key}: '{n}' kommt schon {c}x vor")
for key, name, anchor, mode, text in EDITS:
    c = sources[key].count(anchor)
    if c != 1:
        ok = False
        report.append(f"MISS {key}/{name}: Anker {c}x (erwartet 1)")
if not ok:
    print("\n".join(report))
    print("ABBRUCH - nichts geschrieben")
    sys.exit(1)

anchor_table = []
for key, name, anchor, mode, text in EDITS:
    src = sources[key]
    i = src.index(anchor)
    if mode == "before":
        src = src[:i] + text + src[i:]
    elif mode == "after":
        src = src[:i + len(anchor)] + text + src[i + len(anchor):]
    elif mode == "after_line1":
        # hinter der ERSTEN Zeile des Ankers einfuegen
        nl = anchor.index("\n") + 1
        src = src[:i + nl] + text + src[i + nl:]
    elif mode == "replace":
        src = src[:i] + text + src[i + len(anchor):]
    sources[key] = src
    anchor_table.append({"datei": FILES[key], "stueck": name, "modus": mode, "anker": anchor, "bytes": len(text.encode("utf-8"))})
    report.append(f"ok   {key}/{name} ({mode}, +{len(text)} Zeichen)")

for key, path in FILES.items():
    out = os.path.join(OUT, path)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write(sources[key])
with open(os.path.join(OUT, "_anker.json"), "w", encoding="utf-8") as f:
    json.dump(anchor_table, f, ensure_ascii=False, indent=1)
print("\n".join(report))
print(f"geschrieben nach {OUT}")
