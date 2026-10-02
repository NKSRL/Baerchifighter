#!/usr/bin/env python3
"""
render_decor.py — zeichnet die Deko aus MapConfig als massstabsgetreue Vorschau

Zweck: die Formen der Gebaeude stehen als Zahlen in der Config und sind sonst
erst in Studio zu sehen. Diese Vorschau beantwortet die Frage "sieht das
ueberhaupt nach einem Bienenstock aus?" ohne Studio zu starten.

Es ist bewusst eine schlichte Seitenansicht (Orthogonal, Blick von der
Plattform-Mitte auf das Gebaeude) — keine 3D-Simulation, nur Silhouette,
Groessenverhaeltnisse und Farben.

Aufruf:  python3 tools/render_decor.py [ausgabe.html]
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from check_decor import (  # noqa: E402
    MAP_CONFIG, extract_table, split_named_lists, parse_pieces, extents, _vec,
)

RGB = re.compile(r"Color3\.fromRGB\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)")

SCALE = 14      # Pixel pro Stud
MARGIN = 26


def named_colors(source):
    """Die Farb-Locals (WOOD, HONEY, ...) aus der Config."""
    found = {}
    for m in re.finditer(r"^local (\w+)\s*=\s*Color3\.fromRGB\((\d+),\s*(\d+),\s*(\d+)\)", source, re.MULTILINE):
        found[m.group(1)] = (int(m.group(2)), int(m.group(3)), int(m.group(4)))
    return found


def piece_colors(block, palette):
    """Farbe pro Teil, in der Reihenfolge der Zeilen."""
    colors = []
    for line in block.splitlines():
        line = line.strip()
        if not line.startswith("{ name"):
            continue

        m = re.search(r"color\s*=\s*Color3\.fromRGB\(\s*(\d+),\s*(\d+),\s*(\d+)\s*\)", line)
        if m:
            colors.append((int(m.group(1)), int(m.group(2)), int(m.group(3))))
            continue

        m = re.search(r"color\s*=\s*(\w+)", line)
        colors.append(palette.get(m.group(1), (200, 200, 200)) if m else (200, 200, 200))
    return colors


def svg_for(pieces, colors):
    """Seitenansicht: X waagerecht, Y senkrecht, Blick entlang +Z."""
    width_studs = max(abs(p["offset"][0]) + extents(p)[0] for p in pieces) * 2 + 2
    height_studs = max(p["offset"][1] + extents(p)[1] for p in pieces) + 1.5

    w = width_studs * SCALE + MARGIN * 2
    h = height_studs * SCALE + MARGIN * 2

    def sx(x):
        return MARGIN + (x + width_studs / 2) * SCALE

    def sy(y):
        return h - MARGIN - y * SCALE

    out = [f'<svg viewBox="0 0 {w:.0f} {h:.0f}" width="{w:.0f}" height="{h:.0f}">']
    out.append(f'<line x1="{MARGIN - 8}" y1="{sy(0):.1f}" x2="{w - MARGIN + 8}" y2="{sy(0):.1f}" '
               'stroke="currentColor" stroke-opacity="0.35" stroke-width="1.5"/>')

    # Hinten zuerst: groesseres z liegt weiter weg vom Betrachter
    order = sorted(range(len(pieces)), key=lambda i: -pieces[i]["offset"][2])

    for i in order:
        piece = pieces[i]
        ex, ey, _ = extents(piece)
        ox, oy, _ = piece["offset"]
        r, g, b = colors[i] if i < len(colors) else (200, 200, 200)
        fill = f"rgb({r},{g},{b})"

        if piece["shape"] == "Ball":
            # Ellipse, nicht Kreis: eine Ball-Part mit ungleichen Seiten ist in
            # Roblox ein Ellipsoid, und genau das nutzt der Honigtopf aus.
            out.append(f'<ellipse cx="{sx(ox):.1f}" cy="{sy(oy):.1f}" '
                       f'rx="{ex * SCALE:.1f}" ry="{ey * SCALE:.1f}" '
                       f'fill="{fill}" stroke="rgba(0,0,0,.28)"/>')
        else:
            rx = 3 if piece["shape"] == "Cylinder" else 1
            out.append(f'<rect x="{sx(ox - ex):.1f}" y="{sy(oy + ey):.1f}" '
                       f'width="{2 * ex * SCALE:.1f}" height="{2 * ey * SCALE:.1f}" '
                       f'rx="{rx}" fill="{fill}" stroke="rgba(0,0,0,.28)"/>')

    out.append("</svg>")
    return "".join(out)


def main():
    source = MAP_CONFIG.read_text(encoding="utf-8")
    palette = named_colors(source)

    sections = []
    decor_block = extract_table(source, "BUILDING_DECOR")
    offsets_block = extract_table(source, "BUILDING_OFFSETS")

    names = {}
    for key, body in split_named_lists(offsets_block or "").items():
        m = re.search(r'displayName\s*=\s*"([^"]+)"', body)
        names[key] = m.group(1) if m else key

    for key, block in split_named_lists(decor_block).items():
        pieces = parse_pieces(block)
        sections.append((names.get(key, key), key, svg_for(pieces, piece_colors(block, palette)), len(pieces)))

    center = extract_table(source, "CENTER_DECOR")
    center_pieces = parse_pieces(center)
    sections.append(("Honigmast", "CENTER_DECOR", svg_for(center_pieces, piece_colors(center, palette)),
                     len(center_pieces)))

    cards = "\n".join(
        f'<figure><h2>{title}</h2><div class="stage">{svg}</div>'
        f'<figcaption>{count} Teile · <code>{key}</code></figcaption></figure>'
        for title, key, svg, count in sections
    )

    html = f"""<!doctype html>
<html lang="de"><head><meta charset="utf-8">
<title>Deko-Vorschau</title>
<style>
  :root {{ color-scheme: light dark; --bg:#f4f1ea; --fg:#241c14; --card:#fff; --line:#0002; }}
  @media (prefers-color-scheme: dark) {{
    :root {{ --bg:#16130f; --fg:#efe7db; --card:#211c16; --line:#fff2; }}
  }}
  body {{ margin:0; padding:32px; background:var(--bg); color:var(--fg);
         font:15px/1.5 system-ui,-apple-system,"Segoe UI",sans-serif; }}
  h1 {{ font-size:22px; margin:0 0 4px; }}
  p.lead {{ margin:0 0 28px; opacity:.7; max-width:62ch; }}
  .grid {{ display:flex; flex-wrap:wrap; gap:20px; align-items:flex-end; }}
  figure {{ margin:0; background:var(--card); border:1px solid var(--line);
            border-radius:12px; padding:16px 18px 12px; }}
  h2 {{ font-size:15px; margin:0 0 10px; }}
  .stage {{ display:flex; justify-content:center; }}
  figcaption {{ margin-top:8px; font-size:12px; opacity:.6; }}
  code {{ font-size:11px; }}
</style></head>
<body>
<h1>Deko-Vorschau</h1>
<p class="lead">Seitenansicht der Gebaeude und des Honigmasts, massstabsgetreu aus
<code>MapConfig.BUILDING_DECOR</code> bzw. <code>CENTER_DECOR</code> gezeichnet.
Blickrichtung ist die, aus der ein Spieler von der Plattform-Mitte kommt. Die
graue Linie ist der Boden.</p>
<div class="grid">
{cards}
</div>
</body></html>
"""

    target = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("decor_preview.html")
    target.write_text(html, encoding="utf-8")
    print(f"Geschrieben: {target}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
