#!/usr/bin/env python3
"""
check_ui.py — Qualitaets-Tor fuer alles, was der Spieler LIEST oder ANTIPPT.

Warum es neben check_loc.py dieses Skript gibt: check_loc prueft die
Sprachdateien und raet mit Signalwoertern, wo noch deutscher Text im Code
steht. Das hat viel durchgelassen ("Battle Charms", "Fusion", jede
Skill-Beschreibung ohne "der/die/das", jeder Text, der aus einer Config kommt).
Dieses Skript zerlegt den Code in Tokens und weiss deshalb, WO ein String
landet. Jede Regel unten ist ein FEHLER (Exit-Code 1), keine Empfehlung.

  T1 FESTER TEXT      Ein String-Literal landet in einer Text-Senke (`.Text =`,
                      Theme.label/button/..., dialogHeader, Toast/Notify) und
                      enthaelt Woerter, die nicht sprachneutral sind.
                      → ueber Loc.t / Loc.bind / Loc.msg / Names.* gehen.
  T2 DEUTSCHER TEXT   Ein String mit deutschen Signalwoertern ausserhalb von
                      Log-Aufrufen (print/warn/error/assert), auch wenn er erst
                      ueber eine Variable in die Anzeige kommt.
  T3 CONFIG-TEXT      `.displayName` / `.description` / `.drawback` /
                      `.shortName` wird direkt gelesen statt ueber
                      `Localization/Names` (der einzige erlaubte Leser).
                      Ausnahme: reine Log-Aufrufe und DebugService.
  T4 SCHLUESSEL FEHLT Jeder Eintrag der Text-Configs (Baerchis, Eier, Skills,
                      Events, Gebaeude, Charm-Werte) braucht seine Loc-Schluessel
                      in de.luau (check_loc.py sorgt dann fuer en/fr/es).
  T5 PLATZHALTER      Ein Aufruf Loc.t/Loc.tn/Loc.msg/Loc.bind mit festem
                      Schluessel und Tabelle uebergibt nicht alle {platzhalter}
                      des deutschen Textes — der Spieler saehe "{n}".
  P1 PANEL-HUELLE     Jedes Modul in client/UI, das sich beim PanelManager
                      anmeldet, baut seine Huelle mit Theme.dialog — sonst
                      fehlen Groessen-Constraints, Kopfzeile und Schliessen-X.
  P2 SCROLLER         ScrollingFrames nur ueber Theme.scroller (Canvas waechst
                      automatisch mit, gleiche Scrollbar ueberall).
  P3 SCHLIESSEN-X     Schliessen-Knoepfe nur ueber Theme.closeButton (bzw.
                      Theme.dialogHeader): grosse Trefferflaeche fuers Handy.

Ausnahmen pro Zeile: ein Kommentar `-- ui-ok: <Grund>` am Ende der Zeile.
Ohne Grund zaehlt die Ausnahme nicht — sie soll im Review auffallen.

Aufruf:
    python3 tools/check_ui.py            # Exit-Code 1 bei Fehlern
    python3 tools/check_ui.py PFAD/ZU/src

Braucht nur Python 3, keine Pakete.
"""

import re
import sys
from pathlib import Path

# ------------------------------------------------------------------------------
# Einstellungen
# ------------------------------------------------------------------------------

# Dateien, die Entwickler-Oberflaeche sind (nie ein Spieler sieht sie).
SKIP_FILES = {"DebugService.luau", "DebugConfig.luau"}

# Der einzige Ort, der Config-Texte lesen darf (als Rueckfall hinter Loc).
NAMES_MODULE = "Names.luau"

# Aufrufe, deren Strings nie beim Spieler landen.
LOG_CALLS = {
    "print", "warn", "error", "assert", "require", "debug.traceback",
}
# Aufrufe, deren Strings Bezeichner sind (Instanz-Namen, Attribute, Dienste).
IDENT_CALLS = {
    "GetService", "WaitForChild", "FindFirstChild", "FindFirstChildOfClass",
    "FindFirstChildWhichIsA", "FindFirstAncestor", "IsA", "Instance.new",
    "SetAttribute", "GetAttribute", "GetAttributeChangedSignal",
    "GetPropertyChangedSignal", "AddTag", "HasTag", "RemoveTag",
    "GetTagged", "GetInstanceAddedSignal", "GetInstanceRemovedSignal",
    "TweenInfo.new", "Enum", "typeof", "type", "string.rep",
}
# Loc-Aufrufe: das erste Argument ist ein Schluessel, kein Text.
LOC_CALL = re.compile(r"^(Loc|Names)\.")

# Text-Senken: Funktionsname → ab welchem Argument (1-basiert) Text kommt.
SINK_CALLS = {
    "Theme.label": 3, "Theme.bodyText": 3, "Theme.button": 3,
    "Theme.bigButton": 3, "Theme.sectionLabel": 3, "Theme.dialogHeader": 2,
    "Toast.show": 1, "Toast.success": 1, "Toast.info": 1, "Toast.error": 1,
    "Notify.show": 1, "Notify.push": 1,
    "Icons.make": 3,   # Rueckfall-Kuerzel, falls das Bild fehlt
}
SINK_PROPS = {"Text", "PlaceholderText", "ActionText", "ObjectText"}

# Woerter, die in jeder Sprache gleich sind (Spielbegriffe laut de.luau,
# Stat-Kuerzel, Einheiten). Vergleich ohne Gross-/Kleinschreibung.
NEUTRAL_WORDS = {
    "baerchi", "baerchis", "gummies", "goldgummies", "pit", "rebirth",
    "atk", "hp", "spd", "pwr", "xp", "lv", "lvl", "ko", "ok", "live", "vip",
    "omega", "ufo", "max", "min", "id", "uid", "s", "m", "h", "x", "r",
    "d", "f", "i", "q", "a", "b", "vs", "gg", "ii", "iii", "iv", "vi",
}

GERMAN_HINT = re.compile(
    r"\b(der|die|das|und|nicht|kein|keine|dein|deine|du|ist|sind|noch|jetzt|"
    r"zu|von|mit|für|fuer|auf|wird|kann|gerade|alle|dieser|dieses|bitte|"
    r"kostet|brauchst|hast|naechste|naechstes|stufe|honig|eier|ei|lager|"
    r"einsammeln|fuettern|wuerfeln|gekauft|geschafft|weg|ab|bis|oder)\b",
    re.IGNORECASE,
)

# Felder, in denen Configs ihren deutschen Rueckfall-Text tragen. Angezeigt
# werden sie nur ueber Names/Loc (T3), die Schluessel prueft T4.
TEXT_FIELDS = ("displayName", "description", "drawback", "shortName", "rewardText", "actionText")

# T4: Config-Datei → (Loc-Praefixe, Feld → Loc-Suffix). Die Eintraege werden
# ueber `id = "..."` erkannt. Mehrere Praefixe: einer muss passen (in der
# BaerchiConfig stehen auch die Mutationen). actionText wird nicht angezeigt.
CONFIG_KEYS = {
    "BaerchiConfig.luau": (("baerchi", "mutation"), {"displayName": "name", "description": "desc"}),
    "EggConfig.luau":     (("egg",),     {"displayName": "name", "description": "desc", "shortName": "short"}),
    "SkillConfig.luau":   (("skill",),   {"displayName": "name", "description": "desc", "drawback": "drawback"}),
    "EventConfig.luau":   (("event",),   {"displayName": "name", "rewardText": "reward"}),
    "CharmConfig.luau":   (("charm",),   {"displayName": "name"}),
}

# ------------------------------------------------------------------------------
# Tokenizer (genug Luau fuer diesen Zweck)
# ------------------------------------------------------------------------------

TOKEN = re.compile(r"""
    (?P<ws>[ \t\r]+)
  | (?P<nl>\n)
  | (?P<lcomment>--\[(?P<leq>=*)\[)
  | (?P<comment>--[^\n]*)
  | (?P<lstr>\[(?P<seq>=*)\[)
  | (?P<str>"(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*')
  | (?P<bstr>`(?:[^`\\]|\\.)*`)
  | (?P<num>0[xX][0-9a-fA-F_]+|\d[\d_]*(?:\.\d*)?(?:[eE][+-]?\d+)?|\.\d+)
  | (?P<name>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<op>\.\.\.|\.\.=?|==|~=|<=|>=|::|->|[+\-*/%^#]=?|[=<>(){}\[\];:,.]|.)
""", re.VERBOSE | re.DOTALL)


class Tok:
    __slots__ = ("kind", "text", "line", "value")

    def __init__(self, kind, text, line, value=None):
        self.kind, self.text, self.line, self.value = kind, text, line, value


def unquote(s):
    body = re.sub(r"\\u\{[0-9A-Fa-f]+\}", "\u2022", s[1:-1])   # \u{25BC} → Symbol
    return re.sub(r"\\(.)", lambda m: {"n": "\n", "t": "\t"}.get(m.group(1), m.group(1)), body)


def tokenize(src):
    toks, comments = [], {}
    pos, line = 0, 1
    while pos < len(src):
        m = TOKEN.match(src, pos)
        kind = m.lastgroup
        text = m.group(0)
        if kind == "lcomment":
            end = src.find("]" + m.group("leq") + "]", m.end())
            end = len(src) if end < 0 else end + len(m.group("leq")) + 2
            text = src[pos:end]
            kind = "comment"
        elif kind == "lstr":
            end = src.find("]" + m.group("seq") + "]", m.end())
            end = len(src) if end < 0 else end + len(m.group("seq")) + 2
            text = src[pos:end]
            toks.append(Tok("str", text, line, text[2 + len(m.group("seq")):-(2 + len(m.group("seq")))]))
            kind = None
        elif kind in ("str", "bstr"):
            toks.append(Tok("str", text, line, unquote(text)))
            kind = None
        if kind == "comment":
            comments.setdefault(line, []).append(text)
        elif kind == "nl":
            toks.append(Tok("nl", text, line))
        elif kind in ("name", "num", "op"):
            toks.append(Tok(kind, text, line))
        line += text.count("\n")
        pos += len(text)
    return toks, comments


# ------------------------------------------------------------------------------
# Analyse
# ------------------------------------------------------------------------------

def ok_marker(comments, line):
    for c in comments.get(line, []):
        m = re.search(r"ui-ok:\s*(\S.*)", c)
        if m:
            return True
    return False


def has_words(text):
    """Enthaelt der Text Woerter, die uebersetzt werden muessten?"""
    plain = re.sub(r"%[-+ #0]*\d*(?:\.\d+)?[a-zA-Z%]", " ", text)   # %d, %.2f, %%
    plain = re.sub(r"\{[A-Za-z0-9_:]+\}", " ", plain)                 # {name}
    words = re.findall(r"[A-Za-zÄÖÜäöüßéèàçñ]+", plain)
    return [w for w in words if len(w) > 1 and w.lower() not in NEUTRAL_WORDS]


def is_identifier(text):
    return re.fullmatch(r"[A-Za-z0-9_./:\-]*", text) is not None


def dotted_name_before(toks, i):
    """Name des Aufrufs, dessen '(' bei toks[i] steht (z.B. 'Theme.label')."""
    parts = []
    j = i - 1
    while j >= 0 and toks[j].kind == "nl":
        j -= 1
    while j >= 0 and toks[j].kind == "name":
        parts.append(toks[j].text)
        if j >= 1 and toks[j - 1].text in (".", ":"):
            j -= 2
        else:
            break
    return ".".join(reversed(parts))


CONTINUE_OPS = {"..", "+", "-", "*", "/", "(", ",", "=", "and", "or", "then", "else", "{", "if", "not"}

# Aufrufe, durch die ein Text unveraendert in die Anzeige laeuft.
PASS_THROUGH = {"string.format", "format", "string.upper", "upper", "string.lower",
                "lower", "table.concat", "tostring", "string.rep"}

# Tabellenfelder, die in client/ erfahrungsgemaess angezeigt werden
# (`{ headline = "...", label = "..." }`). Ein Schluessel mit Punkt ist erlaubt.
TEXT_TABLE_FIELDS = {"label", "headline", "detail", "title", "hint", "text", "subtitle", "message"}

SINK_PATTERNS = [
    r"\.(?:Text|ActionText|ObjectText|PlaceholderText)\s*=\s*{p}\b",
    r"Theme\.(?:label|bodyText|button|bigButton|sectionLabel)\(\s*[^,()]+,\s*[^,()]+,\s*{p}\b",
    r"Theme\.dialogHeader\(\s*[^,()]+,\s*{p}\b",
    r"(?:Toast|Notify)\.\w+\(\s*{p}\b",
    r"WorldText\.set\(\s*[^,()]+,\s*{p}\b",
    r"bonusText\s*=\s*{p}\b",
]


def parse_functions(src, module):
    """(name, parameter, rumpf) fuer `local function f(..)` und
    `function Modul.f(..)` (dann unter dem Namen "Modul.f")."""
    clean = re.sub(r"--[^\n]*", "", src)
    funcs = []
    for m in re.finditer(r"^([ \t]*)(local )?function ([\w.:]+)\s*(?:<[^>]*>)?\(((?:[^()]|\([^()]*\))*)\)", clean, re.M):
        indent, is_local, name, params = m.group(1), m.group(2), m.group(3), m.group(4)
        if not is_local:
            parts = re.split(r"[.:]", name)
            if len(parts) != 2:
                continue
            name = module + "." + parts[1]
            if ":" in m.group(3):
                params = "self," + params
        stop = re.search(r"^" + re.escape(indent) + r"end\b", clean[m.end():], re.M)
        body = clean[m.end(): m.end() + (stop.start() if stop else 0)]
        params = re.sub(r"\([^()]*\)", "", params)          # Typen wie (string | LocMsg)?
        names = [re.split(r"[:\s]", x.strip())[0] for x in params.split(",") if x.strip()]
        funcs.append((name, names, body))
    return funcs


def helper_sinks(src, module="", known=None):
    """Funktionen, deren Parameter in einer Text-Senke landen
    (`local function section(text) ... Theme.sectionLabel(.., .., text)`).
    Liefert {name: {argument-index (0-basiert)}}. `known` sind die schon
    bekannten Senken anderer Module ("EventKit.setLabel"). Zwei Durchlaeufe,
    damit auch Helfer erkannt werden, die einen anderen Helfer aufrufen."""
    funcs = parse_functions(src, module)
    sinks = {k: set(v) for k, v in (known or {}).items()}
    for _ in range(2):
        for name, params, body in funcs:
            for index, param in enumerate(params):
                if not re.fullmatch(r"\w+", param):
                    continue
                pats = [x.replace("{p}", re.escape(param)) for x in SINK_PATTERNS]
                for helper, idxs in sinks.items():
                    for k in idxs:
                        pats.append(re.escape(helper) + r"\(" + r"[^,()]*(?:\([^()]*\))?[^,()]*," * k + r"\s*" + re.escape(param) + r"\b")
                if any(re.search(pat, body) for pat in pats):
                    sinks.setdefault(name, set()).add(index)
    # Aliase: `local setLabel = EventKit.setLabel`
    for m in re.finditer(r"^\s*local (\w+)\s*=\s*([\w]+\.[\w]+)\s*$", src, re.M):
        if m.group(2) in sinks:
            sinks[m.group(1)] = sinks[m.group(2)]
    return sinks


def global_sinks(src_root):
    """Senken-Funktionen aller Module ("MapService.setPitBanner": {1, 2})."""
    known = {}
    files = [(p.stem.replace(".server", "").replace(".client", ""), p.read_text(encoding="utf-8"))
             for p in sorted(src_root.rglob("*.luau")) if "/Strings/" not in p.as_posix()]
    for _ in range(2):
        for module, text in files:
            found = helper_sinks(text, module, known)
            for name, idxs in found.items():
                if "." in name and name.split(".")[0] == module:
                    known.setdefault(name, set()).update(idxs)
    return known


def analyse(path, rel, src, known=None):
    toks, comments = tokenize(src)
    findings = []
    is_client = rel.startswith("client/")
    module = path.stem.replace(".server", "").replace(".client", "")
    helpers = helper_sinks(src, module, known)

    # Stapel offener Klammern: [art, aufrufname, argument-index]
    stack = []
    sink_depth = None          # Klammertiefe, in der eine `.Text =`-Zuweisung laeuft
    sink_ifexpr = False        # `.Text = if a then "x" else "y"` ueber mehrere Zeilen
    prev = None

    def in_call(names):
        return any(f[1] in names or f[1].split(".")[-1] in names for f in stack if f[1])

    def in_loc():
        return any(f[1] and LOC_CALL.match(f[1]) for f in stack)

    def in_sink():
        """Der innerste echte Aufruf entscheidet: steckt der String in einem
        anderen Aufruf (z.B. getPathColor("Kosmos")), ist er kein Anzeige-Text."""
        floor = sink_depth if sink_depth is not None else 0
        for depth in range(len(stack) - 1, -1, -1):
            f = stack[depth]
            name = f[1]
            if depth < floor:
                break
            if not name or name in PASS_THROUGH:
                continue
            start = SINK_CALLS.get(name)
            if start:
                return f[2] + 1 >= start
            if name in helpers:
                return f[2] in helpers[name]
            return False
        return sink_depth is not None

    for i, t in enumerate(toks):
        if t.kind == "nl":
            # `.Text = a ..` geht in der naechsten Zeile weiter
            if sink_depth is not None and len(stack) <= sink_depth:
                if prev is None or prev.text not in CONTINUE_OPS:
                    nxt = next((x for x in toks[i + 1:] if x.kind != "nl"), None)
                    cont = ("..", "or", "and") + (("then", "else", "elseif") if sink_ifexpr else ())
                    if nxt is None or nxt.text not in cont:
                        sink_depth = None
            continue

        if t.kind == "op" and t.text in "({[":
            name = dotted_name_before(toks, i) if t.text == "(" else None
            stack.append([t.text, name, 0])
        elif t.kind == "op" and t.text in ")}]":
            if stack:
                stack.pop()
            if sink_depth is not None and len(stack) < sink_depth:
                sink_depth = None
        elif t.kind == "op" and t.text == "," and stack:
            stack[-1][2] += 1
            if sink_depth is not None and len(stack) == sink_depth:
                sink_depth = None
        elif t.kind == "op" and t.text == "=":
            # `x.Text = ...`
            if prev is not None and prev.kind == "name" and prev.text in SINK_PROPS \
                    and i >= 2 and toks[i - 2].text == ".":
                sink_depth = len(stack)
                nxt = next((x for x in toks[i + 1:] if x.kind != "nl"), None)
                sink_ifexpr = nxt is not None and nxt.text == "if"

        # T3: direkter Zugriff auf Config-Texte (Lesen, kein Aufruf, keine Definition)
        if t.kind == "name" and t.text in TEXT_FIELDS and prev is not None and prev.text == "." \
                and rel.split("/")[0] in ("client", "server") and path.name != NAMES_MODULE:
            nxt = toks[i + 1] if i + 1 < len(toks) else None
            is_write = nxt is not None and nxt.text == "="
            is_call = nxt is not None and nxt.text == "("
            is_def = i >= 3 and toks[i - 3].text == "function"
            if not (is_write or is_call or is_def) and not in_call(LOG_CALLS) and not ok_marker(comments, t.line):
                findings.append(("T3", t.line, f".{t.text} direkt gelesen — Names.* benutzen"))

        if t.kind == "str":
            text = t.value or ""
            skip = in_call(LOG_CALLS) or in_call(IDENT_CALLS) or in_loc() or ok_marker(comments, t.line)
            # Schluessel einer Tabelle (`["x"] =`) oder Vergleich (`== "x"`)
            nxt = toks[i + 1] if i + 1 < len(toks) else None
            if (prev is not None and prev.text in ("==", "~=")) or (nxt is not None and nxt.text in ("==", "~=")):
                skip = True
            if prev is not None and prev.text == "[" and nxt is not None and nxt.text == "]":
                skip = True
            if not skip and text.strip():
                field = toks[i - 2].text if i >= 2 and prev is not None and prev.text == "=" else None
                in_table = bool(stack) and stack[-1][0] == "{"
                words = has_words(text)
                if in_sink():
                    if words and not (is_identifier(text) and "." in text):
                        findings.append(("T1", t.line, f"fester Text in Anzeige: \"{text[:60]}\""))
                elif is_client and in_table and field in TEXT_TABLE_FIELDS and words and not (is_identifier(text) and "." in text):
                    findings.append(("T1", t.line, f"fester Text im Feld '{field}': \"{text[:60]}\""))
                elif is_config_text_field(toks, i):
                    pass
                elif is_client and " " in text.strip() and words and not is_identifier(text):
                    findings.append(("T2", t.line, f"Text ohne Loc: \"{text[:60]}\""))
                elif " " in text.strip() and GERMAN_HINT.search(text):
                    findings.append(("T2", t.line, f"deutscher Text: \"{text[:60]}\""))
        prev = t

    # P1 / P2 nur fuer client/UI
    # 08.10.: UI/Kit ist die Huelle des neuen Looks (Kit.window passt sich
    # wie Theme.dialog an den Bildschirm an, Kit.scroller wie Theme.scroller).
    if rel.startswith("client/UI/") and path.name not in ("Theme.luau", "PanelManager.luau", "Kit.luau"):
        stripped = re.sub(r"--[^\n]*", "", src)
        if "PanelManager.register(" in stripped and "Theme.dialog(" not in stripped and "Kit.window(" not in stripped:
            line = stripped[:stripped.find("PanelManager.register(")].count("\n") + 1
            if not ok_marker(comments, line):
                findings.append(("P1", line, "Panel ohne Theme.dialog-Huelle"))
        for m in re.finditer(r'Theme\.(?:big)?[bB]utton\(\s*[^,]+,\s*[^,]+,\s*"[Xx✕×]"', stripped):
            line = stripped[:m.start()].count("\n") + 1
            if not ok_marker(comments, line):
                findings.append(("P3", line, "Schliessen-Knopf ohne Theme.closeButton"))
        for m in re.finditer(r'Instance\.new\(\s*"ScrollingFrame"', stripped):
            line = stripped[:m.start()].count("\n") + 1
            if not ok_marker(comments, line):
                findings.append(("P2", line, "ScrollingFrame ohne Theme.scroller"))

    return findings


def is_config_text_field(toks, i):
    """`description = "..."` in einer Config: das deckt T4 ab, nicht T2."""
    return i >= 2 and toks[i - 1].text == "=" and toks[i - 2].text in TEXT_FIELDS


# ------------------------------------------------------------------------------
# T4: Loc-Schluessel fuer Config-Eintraege
# ------------------------------------------------------------------------------

ENTRY = re.compile(r'\["([^"]+)"\]\s*=')


def config_entries(text, fields):
    """Liefert (id, feld) fuer jedes Text-Feld eines Config-Eintrags."""
    text = re.sub(r"--[^\n]*", "", text)
    out = []
    current = None
    for line in text.splitlines():
        m = re.search(r'\bid\s*=\s*"([^"]+)"', line)
        if m:
            current = m.group(1)
        for field in fields:
            if re.search(r"\b" + field + r'\s*=\s*"', line) and current:
                out.append((current, field))
    return out


def check_config_keys(src):
    de = (src / "shared/Localization/Strings/de.luau").read_text(encoding="utf-8")
    keys = set(ENTRY.findall(de))
    findings = []
    for fname, (prefix, fields) in CONFIG_KEYS.items():
        path = src / "shared/Config" / fname
        if not path.exists():
            continue
        for entry_id, field in config_entries(path.read_text(encoding="utf-8"), fields):
            candidates = [f"{p}.{entry_id}.{fields[field]}" for p in prefix]
            key = candidates[0]
            if not any(c in keys for c in candidates):
                findings.append((f"shared/Config/{fname}", "T4", 0, f"Schluessel fehlt in de.luau: {key}"))
    return findings


# ------------------------------------------------------------------------------
# T5: Platzhalter, die ein Aufruf nicht uebergibt
# ------------------------------------------------------------------------------

PLACEHOLDER = re.compile(r"\{([A-Za-z0-9_]+)(?::[A-Za-z0-9]+)?\}")
LOC_CALL_ARGS = re.compile(r'Loc\.(t|tn|msg|bind)\(\s*(?:[\w.]+\s*,\s*)?"([a-z][\w.]*)"\s*(,)?')


def balanced(text, start):
    """Inhalt der Tabelle ab text[start] == "{" (ohne die Klammern)."""
    depth = 0
    for i in range(start, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[start + 1:i]
    return None


def check_placeholders(src):
    de_text = (src / "shared/Localization/Strings/de.luau").read_text(encoding="utf-8")
    templates = dict(re.findall(r'\["([^"]+)"\]\s*=\s*"((?:[^"\\]|\\.)*)"', de_text))
    findings = []
    for path in sorted(src.rglob("*.luau")):
        rel = path.relative_to(src).as_posix()
        if "/Strings/" in rel:
            continue
        text = re.sub(r"--[^\n]*", "", path.read_text(encoding="utf-8"))
        for m in LOC_CALL_ARGS.finditer(text):
            kind, key = m.group(1), m.group(2)
            if kind == "bind" and not text[m.start():m.end()].startswith("Loc.bind("):
                continue
            keys = [key + ".one", key + ".other"] if kind == "tn" else [key]
            needed = set()
            for k in keys:
                needed |= set(PLACEHOLDER.findall(templates.get(k, "")))
            if kind == "tn":
                needed.discard("n")
            if not needed:
                continue
            given = set()
            if m.group(3):
                rest = text[m.end():]
                brace = re.match(r"\s*\{", rest)
                if not brace:
                    continue   # Tabelle kommt aus einer Variablen: nicht pruefbar
                body = balanced(rest, brace.end() - 1) or ""
                # nur die oberste Ebene: verschachtelte Tabellen ausblenden
                flat = re.sub(r"\{[^{}]*\}", "", body)
                flat = re.sub(r"\{[^{}]*\}", "", flat)
                given = set(re.findall(r"(?:^|[,{\s])(\w+)\s*=", flat))
            missing = sorted(needed - given)
            if missing:
                line = text[:m.start()].count("\n") + 1
                findings.append((rel, "T5", line, f"{key}: Platzhalter fehlen im Aufruf: {', '.join(missing)}"))
    return findings


# ------------------------------------------------------------------------------

def main():
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    src = Path(args[0]) if args else Path(__file__).resolve().parent.parent / "src"

    all_findings = []
    known = global_sinks(src)
    for path in sorted(src.rglob("*.luau")):
        rel = path.relative_to(src).as_posix()
        if path.name in SKIP_FILES or "/Strings/" in "/" + rel:
            continue
        for rule, line, msg in analyse(path, rel, path.read_text(encoding="utf-8"), known):
            all_findings.append((rel, rule, line, msg))
    all_findings += check_config_keys(src)
    all_findings += check_placeholders(src)

    if not all_findings:
        print("UI-Pruefung: keine Funde")
        return 0

    by_rule = {}
    for rel, rule, line, msg in all_findings:
        by_rule[rule] = by_rule.get(rule, 0) + 1
        loc = f"{rel}:{line}" if line else rel
        print(f"{rule}  {loc}  {msg}")
    print()
    print("FEHLER: " + ", ".join(f"{r} {n}" for r, n in sorted(by_rule.items()))
          + f"  (gesamt {len(all_findings)})")
    return 1


if __name__ == "__main__":
    sys.exit(main())
