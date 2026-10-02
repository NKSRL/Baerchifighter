#!/usr/bin/env python3
"""
check_decor.py — prueft die Deko-Geometrie in MapConfig.luau

Warum es das gibt:
    Deko-Teile werden blind in Zahlen geschrieben und erst in Studio sichtbar.
    Ein um 0.3 Studs zu hoch gesetzter Deckel schwebt, ein zu breiter Ring
    ragt in den Nachbarn. Beides sieht man im Code nicht — hier schon.

Geprueft wird pro Deko-Liste:
    1. Kein Teil steckt im Boden (Unterkante < -0.05).
    2. Kein Teil schwebt: jedes Teil, dessen Unterkante ueber dem Boden liegt,
       muss sich senkrecht mit mindestens einem anderen Teil ueberlappen.
    3. Gebaeude-Deko bleibt im Grundriss der Koerper-Part (BUILDING_OFFSETS.size),
       damit zwei Gebaeude nicht ineinander wachsen.
    4. Gebaeude-Deko bleibt unter dem Schild (Koerperhoehe + 2).

Aufruf:  python3 tools/check_decor.py      (Exit-Code 1 wenn etwas nicht stimmt)
"""

import math
import re
import sys
from pathlib import Path

MAP_CONFIG = Path(__file__).resolve().parent.parent / "src" / "shared" / "Config" / "MapConfig.luau"

# Toleranz in Studs. Rundungsfehler in handgeschriebenen Zahlen sollen nicht
# als Fehler durchgehen, ein sichtbarer Spalt aber schon.
EPS = 0.05
FOOTPRINT_SLACK = 0.6   # so weit darf Deko ueber den Koerper hinausragen


# ---------------------------------------------------------------------------
# Lua-Tabellen einlesen (kein voller Parser — nur die Form die wir schreiben)
# ---------------------------------------------------------------------------

VEC = re.compile(r"Vector3\.new\(\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)\s*\)")
SHAPE = re.compile(r"Enum\.PartType\.(\w+)")


def _vec(text, key):
    """Liest `key = Vector3.new(x, y, z)` aus einer Zeile."""
    m = re.search(re.escape(key) + r"\s*=\s*" + VEC.pattern, text)
    if not m:
        return None
    return (float(m.group(1)), float(m.group(2)), float(m.group(3)))


def parse_pieces(block):
    """Ein `{ name = ..., ... },`-Eintrag pro Zeile — so schreiben wir sie."""
    pieces = []
    for line in block.splitlines():
        line = line.strip()
        if not line.startswith("{ name"):
            continue

        name = re.search(r'name\s*=\s*"([^"]+)"', line)
        size = _vec(line, "size")
        offset = _vec(line, "offset")
        shape = SHAPE.search(line)
        rotation = _vec(line, "rotation")
        if rotation is None and "rotation = UPRIGHT" in line:
            rotation = (0.0, 0.0, 90.0)

        if not (name and size and offset and shape):
            print(f"  ! Zeile nicht lesbar: {line[:70]}")
            continue

        pieces.append({
            "name": name.group(1),
            "shape": shape.group(1),
            "size": size,
            "offset": offset,
            "rotation": rotation or (0.0, 0.0, 0.0),
        })
    return pieces


def extract_table(source, varname):
    """Der Text zwischen `local <varname>... = {` und der Zeile `}` auf Spalte 0."""
    start = source.find(f"local {varname}")
    if start < 0:
        return None
    brace = source.find("{", start)
    end = source.find("\n}", brace)
    return source[brace:end]


def split_named_lists(block):
    """Teilt `Beehive = { ... },  HoneyPot = { ... },` in Einzelblöcke."""
    result = {}
    for m in re.finditer(r"^\t(\w+) = \{$", block, re.MULTILINE):
        key = m.group(1)
        end = block.find("\n\t},", m.end())
        result[key] = block[m.end():end]
    return result


# ---------------------------------------------------------------------------
# Geometrie
# ---------------------------------------------------------------------------

def extents(piece):
    """Achsenparallele Ausdehnung (halbe Kantenlaengen) nach der Rotation.

    Fuer BELIEBIGE Winkel, nicht nur Vielfache von 90 Grad: seit der
    Honigloeffel schraeg im Teich lehnt, gibt es Deko, die weder liegt noch
    steht. Die Umhuellende eines gedrehten Quaders waechst pro Achse um
    |cos| * eine Halbkante + |sin| * die andere — fuer Zylinder und Kugeln ist
    das grosszuegig, also nie zu optimistisch.

    Die drei Drehungen werden in derselben Reihenfolge angewandt wie
    CFrame.Angles(x, y, z) sie zusammensetzt: erst Z, dann Y, dann X.
    """
    sx, sy, sz = (v * 0.5 for v in piece["size"])
    rx, ry, rz = piece["rotation"]

    def spread(a, b, degrees):
        c, s = abs(math.cos(math.radians(degrees))), abs(math.sin(math.radians(degrees)))
        return c * a + s * b, s * a + c * b

    sx, sy = spread(sx, sy, rz)   # Drehung um Z mischt X und Y
    sz, sx = spread(sz, sx, ry)   # Drehung um Y mischt Z und X
    sy, sz = spread(sy, sz, rx)   # Drehung um X mischt Y und Z

    return sx, sy, sz


def check_list(label, pieces, body_size=None, floating_ok=False):
    """`floating_ok` schaltet den Schwebe-Test ab.

    Gebraucht wird das nur vom Teich: seine Deko steht auf Becken, Sandkante
    und Steinen, und die baut MapService aus Zahlen statt aus dieser Liste —
    fuer dieses Werkzeug waere dort also nichts unter den Teilen, obwohl in der
    Welt ein ganzes Becken darunter liegt. Der Test "steckt im Boden" bleibt.
    """
    problems = []
    spans = []

    for piece in pieces:
        ex, ey, ez = extents(piece)
        ox, oy, oz = piece["offset"]
        spans.append((piece["name"], oy - ey, oy + ey))

        if oy - ey < -EPS:
            problems.append(f"{piece['name']}: steckt {ey - oy:.2f} Studs im Boden")

        if body_size is not None:
            half_x, half_z = body_size[0] * 0.5, body_size[2] * 0.5
            over_x = abs(ox) + ex - half_x
            over_z = abs(oz) + ez - half_z
            if over_x > FOOTPRINT_SLACK:
                problems.append(f"{piece['name']}: ragt {over_x:.2f} Studs seitlich (X) aus dem Koerper")
            if over_z > FOOTPRINT_SLACK:
                problems.append(f"{piece['name']}: ragt {over_z:.2f} Studs seitlich (Z) aus dem Koerper")

            sign_y = body_size[1] + 2.0
            if oy + ey > sign_y:
                problems.append(f"{piece['name']}: reicht bis {oy + ey:.2f}, das Schild haengt schon bei {sign_y:.2f}")

    # Schwebe-Test: jedes Teil ueber dem Boden braucht einen senkrechten Nachbarn
    for name, low, high in spans if not floating_ok else ():
        if low <= EPS:
            continue
        supported = any(
            other_name != name and other_low - EPS <= low <= other_high + EPS
            for other_name, other_low, other_high in spans
        )
        if not supported:
            problems.append(f"{name}: schwebt (Unterkante {low:.2f}, nichts darunter)")

    top = max((high for _, _, high in spans), default=0.0)
    status = "OK " if not problems else "!! "
    print(f"{status}{label:<14} {len(pieces):>2} Teile, Hoehe {top:.2f}")
    for problem in problems:
        print(f"     - {problem}")
    return problems


def main():
    source = MAP_CONFIG.read_text(encoding="utf-8")

    offsets_block = extract_table(source, "BUILDING_OFFSETS")
    decor_block = extract_table(source, "BUILDING_DECOR")
    center_block = extract_table(source, "CENTER_DECOR")
    pond_block = extract_table(source, "POND_DECOR")

    if decor_block is None or center_block is None or pond_block is None:
        print("BUILDING_DECOR, CENTER_DECOR oder POND_DECOR nicht gefunden — Config umgebaut?")
        return 1

    body_sizes = {}
    for key, body in split_named_lists(offsets_block or "").items():
        size = _vec(body, "size")
        if size:
            body_sizes[key] = size

    print("Deko-Geometrie")
    print("=" * 62)

    failures = []
    for key, block in split_named_lists(decor_block).items():
        failures += check_list(key, parse_pieces(block), body_sizes.get(key))

    failures += check_list("Honigmast", parse_pieces(center_block))
    failures += check_list("Honig-Teich", parse_pieces(pond_block), floating_ok=True)

    print("=" * 62)
    if failures:
        print(f"{len(failures)} Problem(e) gefunden.")
        return 1

    print("Alles sauber.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
