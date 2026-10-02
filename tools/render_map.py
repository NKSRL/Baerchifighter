#!/usr/bin/env python3
"""
render_map.py — zeichnet die Welt aus MapConfig von oben

Zweck: die Weltgeometrie ergibt sich aus rund zwei Dutzend Zahlen in
MapConfig, die miteinander zusammenhaengen. Ob ein Beet ueber seine Insel
ragt, ob ein Steg wirklich an der naechsten Insel ankommt, ob zwei Inseln
sich beruehren oder ob das Wasser bis hinter die Arenen reicht, sieht man
den Zahlen nicht an — dieser Grundriss schon.

Es sind dieselben Zusammenhaenge, die MapService.init beim Serverstart
nachrechnet und bewarnt. Der Unterschied: hier sieht man SOFORT, wie es
aussieht, ohne Studio zu starten.

Zwei Ansichten:
    1. die ganze Welt: Hauptinsel, acht Plot-Inseln, Stege, Arena-Inseln
    2. ein Plot in gross, mit Gebaeuden, Honig-Tropfen, Teich und Baerchi-Platz

Aufruf:
    python3 tools/render_map.py [ausgabe.html]
    python3 tools/render_map.py --svg <ordner>   # nur die nackten SVGs
"""

import math
import re
import sys
from pathlib import Path

MAP_CONFIG = Path(__file__).resolve().parent.parent / "src" / "shared" / "Config" / "MapConfig.luau"
SOURCE = MAP_CONFIG.read_text(encoding="utf-8")


# ---------------------------------------------------------------------------
# Config lesen
# ---------------------------------------------------------------------------

def read_config(source):
    """Die einfachen `local NAME = <zahl|Vector3|Color3>`-Zeilen."""
    cfg = {}

    for m in re.finditer(r"^local (\w+)\s*=\s*(-?[\d.]+)\s*(?:--.*)?$", source, re.MULTILINE):
        cfg[m.group(1)] = float(m.group(2))

    for m in re.finditer(r"^local (\w+)\s*=\s*Vector3\.new\(([-\d.,\s]+)\)", source, re.MULTILINE):
        cfg[m.group(1)] = tuple(float(v) for v in m.group(2).split(","))

    # Die Leerzeichen im Muster sind Absicht: in der Config stehen die
    # Farbwerte ausgerichtet, also `Color3.fromRGB( 58, 140,  62)`.
    for m in re.finditer(
        r"^local (\w+)\s*=\s*Color3\.fromRGB\(\s*(\d+),\s*(\d+),\s*(\d+)\s*\)", source, re.MULTILINE
    ):
        cfg[m.group(1)] = (int(m.group(2)), int(m.group(3)), int(m.group(4)))

    return cfg


def read_buildings(source):
    """BUILDING_OFFSETS: id -> {offset, size, displayName}."""
    start = source.find("local BUILDING_OFFSETS")
    block = source[start:source.find("\n}", start)]

    out = {}
    for m in re.finditer(r"^\t(\w+) = \{(.*?)^\t\},", block + "\n\t},", re.MULTILINE | re.DOTALL):
        body = m.group(2)
        vec = lambda key: tuple(float(v) for v in re.search(
            re.escape(key) + r"\s*=\s*Vector3\.new\(([-\d.,\s]+)\)", body).group(1).split(","))
        name = re.search(r'displayName\s*=\s*"([^"]+)"', body)
        out[m.group(1)] = {
            "offset": vec("offset"),
            "size": vec("size"),
            "name": name.group(1) if name else m.group(1),
        }
    return out


def read_number_list(source, name):
    m = re.search(rf"^local {name}[^=]*=\s*\{{([^}}]*)\}}", source, re.M)
    return [float(v) for v in re.findall(r"-?[\d.]+", m.group(1))] if m else []


def read_color_list(source, name):
    m = re.search(rf"^local {name}[^=]*=\s*\{{(.*?)^\}}", source, re.M | re.S)
    if not m:
        return []
    return [
        (int(r), int(g), int(b))
        for r, g, b in re.findall(r"fromRGB\(\s*(\d+),\s*(\d+),\s*(\d+)\s*\)", m.group(1))
    ]


def read_decor(source, name, cfg):
    """Eine DecorPiece-Liste: name, shape, size, offset, rotation, color.

    Die Farben stehen dort meist als benannte Konstante (WOOD, HONEY) statt als
    Color3 — die sind schon in `cfg`, also wird einfach nachgeschlagen.
    """
    m = re.search(rf"^local {name}[^=]*=\s*\{{(.*?)^\}}", source, re.M | re.S)
    if not m:
        return []

    out = []
    for entry in re.finditer(r'\{\s*name\s*=\s*"(\w+)"(.*?)\},', m.group(1), re.S):
        body = entry.group(2)

        def vec(key, default=(0.0, 0.0, 0.0)):
            v = re.search(re.escape(key) + r"\s*=\s*Vector3\.new\(([-\d.,\s]+)\)", body)
            return tuple(float(x) for x in v.group(1).split(",")) if v else default

        literal = re.search(r"color\s*=\s*Color3\.fromRGB\(\s*(\d+),\s*(\d+),\s*(\d+)\s*\)", body)
        named = re.search(r"color\s*=\s*([A-Z_][A-Z_0-9]*)\s*,", body)
        color = (
            tuple(int(literal.group(i)) for i in (1, 2, 3)) if literal
            else cfg.get(named.group(1)) if named
            else None
        )

        shape = re.search(r"shape\s*=\s*Enum\.PartType\.(\w+)", body)
        out.append({
            "name": entry.group(1),
            "shape": shape.group(1) if shape else "Block",
            "size": vec("size", (1.0, 1.0, 1.0)),
            "offset": vec("offset"),
            "rotation": vec("rotation"),
            "color": color,
        })
    return out


def rgb(color, fallback="#999"):
    return f"rgb({color[0]},{color[1]},{color[2]})" if color else fallback


# ---------------------------------------------------------------------------
# Bausteine, die in beiden Ansichten gebraucht werden
# ---------------------------------------------------------------------------

def checker_cells_disc(cfg, cx, cz, radius):
    """Die hellen Karo-Felder auf einer runden Insel.

    Wortgleich zu MapService.buildCheckerDisc: Welt-Raster mit Ursprung im
    Weltmittelpunkt, ein Feld nur dann, wenn alle VIER Ecken in der Scheibe
    liegen. Weicht die Zeichnung hier von der Welt ab, ist genau das der
    Grund, warum die Vorschau nichts wert waere.
    """
    tile = cfg["GRASS_TILE"]
    half = tile / 2

    out = []
    for i in range(math.floor((cx - radius) / tile), math.ceil((cx + radius) / tile) + 1):
        for j in range(math.floor((cz - radius) / tile), math.ceil((cz + radius) / tile) + 1):
            if (i + j) % 2 != 0:
                continue
            x = (i + 0.5) * tile
            z = (j + 0.5) * tile
            if all(
                (x + dx - cx) ** 2 + (z + dz - cz) ** 2 <= radius * radius
                for dx in (-half, half)
                for dz in (-half, half)
            ):
                out.append((x, z, tile, tile))
    return out


def checker_cells_plate(cfg, size_x, size_z):
    """Die hellen Karo-Felder auf dem quadratischen Beet (plot-lokal).

    Wortgleich zu MapService.buildCheckerPlate.
    """
    tile = cfg["PLOT_GRASS_TILE"]
    count_x = max(1, int(size_x // tile))
    count_z = max(1, int(size_z // tile))
    step_x = size_x / count_x
    step_z = size_z / count_z

    out = []
    for i in range(count_x):
        for j in range(count_z):
            if (i + j) % 2 == 0:
                out.append((
                    (i - (count_x - 1) / 2) * step_x,
                    (j - (count_z - 1) / 2) * step_z,
                    step_x,
                    step_z,
                ))
    return out


def pond_stand(cfg):
    """Abstand des Baerchi-Standplatzes zur Teichmitte — wie MapService."""
    return cfg["POND_RADIUS"] + cfg["POND_STAND_GAP"]


def pond_fill_radius(cfg, ratio):
    """Radius der Honigflaeche bei diesem Fuellstand — wie writePondFill."""
    scale = cfg["POND_FILL_MIN_SCALE"] + (1 - cfg["POND_FILL_MIN_SCALE"]) * max(0.0, min(1.0, ratio))
    return (cfg["POND_RADIUS"] - cfg["POND_FILL_INSET"]) * scale


def pond_stones(cfg):
    """Die Steine des Kranzes als (x, z, radius, farbe) — wie buildPondStones.

    Winkel 0 ist teich-lokales +Z, die Luecke liegt bei pi (also auf -Z, zum
    Baerchi-Platz hin).
    """
    sizes = read_number_list(SOURCE, "POND_STONE_SIZES") or [3.0]
    colors = read_color_list(SOURCE, "POND_STONE_COLORS") or [(160, 160, 160)]

    ring = cfg["POND_RADIUS"] + cfg["POND_RIM_WIDTH"] / 2
    gap = math.radians(cfg["POND_STONE_GAP_DEGREES"])
    count = int(cfg["POND_STONE_COUNT"])

    out = []
    for i in range(count):
        angle = i * (2 * math.pi / count)
        delta = abs(((angle - math.pi + math.pi) % (2 * math.pi)) - math.pi)
        if delta > gap:
            size = sizes[i % len(sizes)]
            out.append((
                math.sin(angle) * ring,
                math.cos(angle) * ring,
                size / 2,
                colors[i % len(colors)],
            ))
    return out


def pit_distance(cfg):
    """Abstand der Arena-Mitte zur Weltmitte — wie MapService.pitCenter."""
    return (
        cfg["PLOT_RING_RADIUS"]
        + cfg["PLOT_ISLAND_RADIUS"]
        + cfg["ISLAND_GAP"]
        + cfg["PIT_BASE_RADIUS"]
    )


# ---------------------------------------------------------------------------
# Ansicht 1: die ganze Welt
# ---------------------------------------------------------------------------

def render_world(cfg, size_px=820):
    reach = pit_distance(cfg) + cfg["PIT_BASE_RADIUS"] + cfg["SHORE_WIDTH"] + 24
    scale = size_px / (2 * reach)

    def sx(x):
        return size_px / 2 + x * scale

    def sy(z):
        return size_px / 2 + z * scale

    def disc(cx, cz, r, fill, extra=""):
        return (f'<circle cx="{sx(cx):.1f}" cy="{sy(cz):.1f}" r="{r * scale:.1f}" '
                f'fill="{fill}" {extra}/>')

    def island(cx, cz, r, color):
        return (disc(cx, cz, r + cfg["SHORE_WIDTH"], rgb(cfg.get("SHORE_COLOR")))
                + disc(cx, cz, r, rgb(color), 'stroke="rgba(0,0,0,.12)"'))

    def span(ux, uz, from_r, to_r):
        a = from_r - cfg["BRIDGE_OVERLAP"]
        b = to_r + cfg["BRIDGE_OVERLAP"]
        return (f'<line x1="{sx(ux * a):.1f}" y1="{sy(uz * a):.1f}" '
                f'x2="{sx(ux * b):.1f}" y2="{sy(uz * b):.1f}" '
                f'stroke="{rgb(cfg.get("BRIDGE_COLOR"))}" '
                f'stroke-width="{cfg["BRIDGE_WIDTH"] * scale:.1f}"/>')

    light = rgb(cfg.get("GRASS_LIGHT"))
    out = [f'<svg viewBox="0 0 {size_px} {size_px}" width="{size_px}" height="{size_px}">']

    # Wasser
    out.append(disc(0, 0, cfg["WATER_RADIUS"], rgb(cfg.get("WATER_COLOR"))))

    # Hauptinsel mit Karo
    out.append(island(0, 0, cfg["PLATFORM_RADIUS"], cfg.get("GRASS_DARK")))
    for x, z, w, d in checker_cells_disc(cfg, 0, 0, cfg["PLATFORM_RADIUS"]):
        out.append(f'<rect x="{sx(x - w / 2):.1f}" y="{sy(z - d / 2):.1f}" '
                   f'width="{w * scale:.1f}" height="{d * scale:.1f}" fill="{light}"/>')

    plot_w, plot_d = cfg["PLOT_SIZE"][0], cfg["PLOT_SIZE"][2]
    count = int(cfg["PLOT_COUNT"])
    ring = cfg["PLOT_RING_RADIUS"]
    island_r = cfg["PLOT_ISLAND_RADIUS"]
    pit_dist = pit_distance(cfg)

    for slot in range(count):
        deg = slot * (360 / count)
        rad = math.radians(deg)
        ux, uz = math.cos(rad), math.sin(rad)
        cx, cz = ux * ring, uz * ring

        # Stege: Hauptinsel -> Plot-Insel -> Arena-Insel
        out.append(span(ux, uz, cfg["PLATFORM_RADIUS"], ring - island_r))
        out.append(span(ux, uz, ring + island_r, ring + island_r + cfg["ISLAND_GAP"]))

        # Plot-Insel
        out.append(island(cx, cz, island_r, cfg.get("PLOT_ISLAND_COLOR")))

        # Beet, gedreht wie das Plot-CFrame.
        #
        # Das Plot-CFrame kommt aus CFrame.lookAt(...zur Mitte), sein lokales
        # +Z zeigt also nach AUSSEN. In SVG bildet rotate(a) die lokale Y-Achse
        # (hier: Z) auf (-sin a, cos a) ab — gleichgesetzt mit der
        # Aussenrichtung (cos θ, sin θ) ergibt das a = θ - 90.
        tiles = "".join(
            f'<rect x="{(x - w / 2) * scale:.1f}" y="{(z - d / 2) * scale:.1f}" '
            f'width="{w * scale:.1f}" height="{d * scale:.1f}" fill="{light}"/>'
            for x, z, w, d in checker_cells_plate(cfg, plot_w, plot_d)
        )
        out.append(
            f'<g transform="translate({sx(cx):.1f},{sy(cz):.1f}) rotate({deg - 90:.1f})">'
            f'<rect x="{-plot_w / 2 * scale:.1f}" y="{-plot_d / 2 * scale:.1f}" '
            f'width="{plot_w * scale:.1f}" height="{plot_d * scale:.1f}" '
            f'fill="{rgb(cfg.get("GRASS_DARK"))}" stroke="rgba(0,0,0,.3)"/>{tiles}</g>'
        )
        # Beschriftung bewusst UNGEDREHT, sonst steht die Haelfte auf dem Kopf
        out.append(f'<text x="{sx(cx):.1f}" y="{sy(cz) + 4:.1f}" text-anchor="middle" '
                   f'font-size="12" fill="#fff" opacity=".9">{slot + 1}</text>')

        # Arena-Insel: Sandkante, Leuchtring, Sockel, goldene Kampfflaeche
        px, pz = ux * pit_dist, uz * pit_dist
        out.append(disc(px, pz, cfg["PIT_BASE_RADIUS"] + cfg["SHORE_WIDTH"], rgb(cfg.get("SHORE_COLOR"))))
        out.append(disc(px, pz, cfg["PIT_BASE_RADIUS"] + cfg["PIT_RING_OVERHANG"], rgb(cfg.get("PIT_RING_COLOR"))))
        out.append(disc(px, pz, cfg["PIT_BASE_RADIUS"], rgb(cfg.get("PIT_BASE_COLOR"))))
        out.append(disc(px, pz, cfg["PIT_RADIUS"], rgb(cfg.get("PIT_FLOOR_COLOR")), 'stroke="rgba(0,0,0,.2)"'))

        # Zaunpfosten, mit der Luecke zum Steg hin (wie MapService.buildPit)
        post_r = cfg["PIT_BASE_RADIUS"] - cfg["PIT_FENCE_INSET"]
        inward = math.atan2(-uz, -ux)
        gap = math.radians(cfg["PIT_FENCE_GAP_DEGREES"])
        for i in range(int(cfg["PIT_FENCE_COUNT"])):
            a = i * (2 * math.pi / cfg["PIT_FENCE_COUNT"])
            delta = abs(((a - inward + math.pi) % (2 * math.pi)) - math.pi)
            if delta > gap:
                out.append(f'<circle cx="{sx(px + post_r * math.cos(a)):.1f}" '
                           f'cy="{sy(pz + post_r * math.sin(a)):.1f}" '
                           f'r="{max(1.2, 0.4 * scale * cfg["PIT_FENCE_SIZE"][0]):.1f}" '
                           f'fill="{rgb(cfg.get("PIT_FENCE_COLOR"))}"/>')

    spawn = cfg["SPAWN_SIZE"][0]
    out.append(f'<rect x="{sx(-spawn / 2):.1f}" y="{sy(-spawn / 2):.1f}" '
               f'width="{spawn * scale:.1f}" height="{spawn * scale:.1f}" '
               f'fill="{rgb(cfg.get("SPAWN_COLOR"))}" stroke="rgba(0,0,0,.3)"/>')
    out.append(disc(0, 0, 3, "#c8a05a"))

    out.append("</svg>")
    return "".join(out), scale


# ---------------------------------------------------------------------------
# Ansicht 2: ein Plot in gross (plot-lokal, -Z oben = Richtung Weltmitte)
# ---------------------------------------------------------------------------

def render_plot(cfg, buildings, size_px=560):
    island_r = cfg["PLOT_ISLAND_RADIUS"]
    outer = island_r + cfg["SHORE_WIDTH"]
    margin = 14
    scale = (size_px - 2 * margin) / (2 * outer)

    def sx(x):
        return size_px / 2 + x * scale

    def sy(z):
        return size_px / 2 + z * scale   # -Z oben = Richtung Weltmitte

    out = [f'<svg viewBox="0 0 {size_px} {size_px}" width="{size_px}" height="{size_px}">']

    # Wasser, Sandkante, Insel
    out.append(f'<rect x="0" y="0" width="{size_px}" height="{size_px}" '
               f'fill="{rgb(cfg.get("WATER_COLOR"))}"/>')
    out.append(f'<circle cx="{sx(0):.1f}" cy="{sy(0):.1f}" r="{outer * scale:.1f}" '
               f'fill="{rgb(cfg.get("SHORE_COLOR"))}"/>')
    out.append(f'<circle cx="{sx(0):.1f}" cy="{sy(0):.1f}" r="{island_r * scale:.1f}" '
               f'fill="{rgb(cfg.get("PLOT_ISLAND_COLOR"))}"/>')

    # Beet mit Karo
    half_x = cfg["PLOT_SIZE"][0] / 2
    half_z = cfg["PLOT_SIZE"][2] / 2
    out.append(f'<rect x="{sx(-half_x):.1f}" y="{sy(-half_z):.1f}" '
               f'width="{2 * half_x * scale:.1f}" height="{2 * half_z * scale:.1f}" '
               f'fill="{rgb(cfg.get("GRASS_DARK"))}" stroke="rgba(0,0,0,.3)"/>')
    for x, z, w, d in checker_cells_plate(cfg, cfg["PLOT_SIZE"][0], cfg["PLOT_SIZE"][2]):
        out.append(f'<rect x="{sx(x - w / 2):.1f}" y="{sy(z - d / 2):.1f}" '
                   f'width="{w * scale:.1f}" height="{d * scale:.1f}" '
                   f'fill="{rgb(cfg.get("GRASS_LIGHT"))}"/>')

    # Zaun an den beiden Seiten (lokales +X und -X)
    for side in (-1, 1):
        out.append(f'<line x1="{sx(side * half_x):.1f}" y1="{sy(-half_z):.1f}" '
                   f'x2="{sx(side * half_x):.1f}" y2="{sy(half_z):.1f}" '
                   f'stroke="{rgb(cfg.get("FENCE_COLOR"))}" stroke-width="3"/>')

    # Gebaeude mit Honig-Tropfen.
    # Zwei der drei Gebaeude haben 5 Plaetze, der Bienenstock waechst weiter
    # (BuildingBehavior). Die Vorschau zeichnet den Normalfall — sie soll nur
    # zeigen, ob die Tropfen ins Bild passen, nicht den Spielstand abbilden.
    #
    # Der Bogen entsteht wie in MapService: fester Winkelabstand, gedeckelt.
    dots = 5
    arc = min(
        math.radians(cfg.get("HONEY_DOT_ARC", 200)),
        math.radians(cfg.get("HONEY_DOT_SPACING", 37.5)) * max(1, dots - 1),
    )

    for info in buildings.values():
        ox, _, oz = info["offset"]
        w, _, d = info["size"]
        out.append(f'<rect x="{sx(ox - w / 2):.1f}" y="{sy(oz - d / 2):.1f}" '
                   f'width="{w * scale:.1f}" height="{d * scale:.1f}" rx="3" '
                   f'fill="rgba(0,0,0,.18)" stroke="rgba(0,0,0,.45)" stroke-dasharray="3 3"/>')
        out.append(f'<text x="{sx(ox):.1f}" y="{sy(oz) + 4:.1f}" text-anchor="middle" '
                   f'font-size="10" fill="#fff">{info["name"]}</text>')

        for i in range(dots):
            t = (i / (dots - 1) - 0.5) if dots > 1 else 0
            angle = t * arc
            dx = ox + math.sin(angle) * cfg["HONEY_DOT_RADIUS"]
            dz = oz - math.cos(angle) * cfg["HONEY_DOT_RADIUS"]
            out.append(f'<circle cx="{sx(dx):.1f}" cy="{sy(dz):.1f}" '
                       f'r="{cfg["HONEY_DOT_SIZE"] / 2 * scale:.1f}" '
                       f'fill="{rgb(cfg.get("HONEY_DOT_COLOR"))}" stroke="rgba(0,0,0,.3)"/>')

    # Honig-Teich.
    #
    # Er ist gedreht: sein lokales -Z zeigt zum Baerchi-Platz (siehe
    # MapService.pondGround), damit Steinluecke und Bohlen immer auf der Seite
    # liegen, von der der Baerchi kommt. Dieselbe Umrechnung von Richtung nach
    # SVG-Winkel wie bei den Plots in der Weltansicht: rotate(a) bildet die
    # lokale +Z-Achse auf (-sin a, cos a) ab.
    px, _, pz = cfg["POND_OFFSET"]
    bx, _, bz = cfg["BAERCHI_HOME_OFFSET"]
    away = (px - bx, pz - bz)                     # +Z des Teichs zeigt VOM Baerchi weg
    norm = math.hypot(*away) or 1.0
    pond_deg = math.degrees(math.atan2(-away[0] / norm, away[1] / norm))

    stand = pond_stand(cfg)
    pond_parts = [
        f'<circle cx="0" cy="0" r="{(cfg["POND_RADIUS"] + cfg["POND_RIM_WIDTH"]) * scale:.1f}" '
        f'fill="{rgb(cfg.get("POND_RIM_COLOR"))}"/>',
        f'<circle cx="0" cy="0" r="{cfg["POND_RADIUS"] * scale:.1f}" '
        f'fill="{rgb(cfg.get("POND_FLOOR_COLOR"))}"/>',
        f'<circle cx="0" cy="0" r="{pond_fill_radius(cfg, 0.7) * scale:.1f}" '
        f'fill="{rgb(cfg.get("POND_FILL_COLOR"))}"/>',
        f'<rect x="{-cfg["POND_PLANK_SIZE"][0] / 2 * scale:.1f}" '
        f'y="{(-stand - cfg["POND_PLANK_SIZE"][2]) * scale:.1f}" '
        f'width="{cfg["POND_PLANK_SIZE"][0] * scale:.1f}" '
        f'height="{cfg["POND_PLANK_SIZE"][2] * 2 * scale:.1f}" '
        f'fill="{rgb(cfg.get("BRIDGE_COLOR"))}"/>',
    ]
    for stone_x, stone_z, stone_r, stone_c in pond_stones(cfg):
        pond_parts.append(f'<circle cx="{stone_x * scale:.1f}" cy="{stone_z * scale:.1f}" '
                          f'r="{stone_r * scale:.1f}" fill="{rgb(stone_c)}"/>')

    out.append(f'<g transform="translate({sx(px):.1f},{sy(pz):.1f}) rotate({pond_deg:.1f})">'
               + "".join(pond_parts) + "</g>")

    # Der Platz des ausgeruesteten Baerchi — seit dem Equip-System genau EINER
    # statt des frueheren 25er-Rasters.
    out.append(f'<circle cx="{sx(bx):.1f}" cy="{sy(bz):.1f}" r="{2.2 * scale:.1f}" '
               f'fill="rgba(255,255,255,.75)" stroke="rgba(0,0,0,.35)"/>')
    out.append(f'<text x="{sx(bx):.1f}" y="{sy(bz) - 3 * scale:.1f}" text-anchor="middle" '
               f'font-size="10" fill="#fff">Baerchi</text>')

    # Schild zur Mitte hin, Steg nach aussen
    out.append(f'<rect x="{sx(-cfg["SIGN_BOARD_SIZE"][0] / 2):.1f}" y="{sy(-half_z) - 6:.1f}" '
               f'width="{cfg["SIGN_BOARD_SIZE"][0] * scale:.1f}" height="6" '
               f'fill="{rgb(cfg.get("SIGN_COLOR"))}" stroke="rgba(0,0,0,.3)"/>')
    out.append(f'<rect x="{sx(-cfg["BRIDGE_WIDTH"] / 2):.1f}" y="{sy(island_r):.1f}" '
               f'width="{cfg["BRIDGE_WIDTH"] * scale:.1f}" height="{10 * scale:.1f}" '
               f'fill="{rgb(cfg.get("BRIDGE_COLOR"))}"/>')
    out.append(f'<rect x="{sx(-cfg["BRIDGE_WIDTH"] / 2):.1f}" y="{sy(-island_r - 10):.1f}" '
               f'width="{cfg["BRIDGE_WIDTH"] * scale:.1f}" height="{10 * scale:.1f}" '
               f'fill="{rgb(cfg.get("BRIDGE_COLOR"))}"/>')

    out.append(f'<text x="{size_px / 2:.0f}" y="11" text-anchor="middle" font-size="11" '
               f'fill="#fff" opacity=".85">oben = Steg zur Hauptinsel (-Z)</text>')
    out.append(f'<text x="{size_px / 2:.0f}" y="{size_px - 4:.0f}" text-anchor="middle" '
               f'font-size="11" fill="#fff" opacity=".85">unten = Steg zur Arena (+Z)</text>')
    out.append("</svg>")
    return "".join(out)


# ---------------------------------------------------------------------------
# Der Honig-Teich von oben (teich-lokal, -Z oben = zum Baerchi-Platz)
# ---------------------------------------------------------------------------

def render_pond(cfg, decor, ratio, size_px=320, detail=True, caption=None):
    """Der Teich bei einem bestimmten Fuellstand.

    Der Sinn dieser Ansicht ist der Fuellstand selbst: der alte Teich hat den
    Vorrat gemessen und dann NICHTS davon gezeigt (die Fuellung steckte
    vollstaendig im Beckenklotz). Vier dieser Bilder nebeneinander beantworten
    die Frage, ob man den Stand jetzt wirklich ablesen kann.
    """
    reach = pond_stand(cfg) + cfg["POND_PLANK_SIZE"][2] + cfg["POND_PLANK_GAP"] + 2
    scale = (size_px - 8) / (2 * reach)

    def sx(x):
        return size_px / 2 + x * scale

    def sy(z):
        return size_px / 2 + z * scale   # -Z oben = zum Baerchi-Platz

    def disc(x, z, r, fill, extra=""):
        return (f'<circle cx="{sx(x):.1f}" cy="{sy(z):.1f}" r="{r * scale:.1f}" '
                f'fill="{fill}" {extra}/>')

    out = [f'<svg viewBox="0 0 {size_px} {size_px}" width="{size_px}" height="{size_px}">']
    out.append(f'<rect x="0" y="0" width="{size_px}" height="{size_px}" '
               f'fill="{rgb(cfg.get("GRASS_DARK"))}"/>')

    # Bohlen, bevor die Steine darueber kommen
    if detail:
        stand = pond_stand(cfg)
        pw, _, pd = cfg["POND_PLANK_SIZE"]
        step = (pd + cfg["POND_PLANK_GAP"]) / 2
        plank_colors = read_color_list(SOURCE, "POND_PLANK_COLORS") or [(160, 110, 65)]
        for i, off in enumerate((-step, step)):
            out.append(f'<rect x="{sx(-pw / 2):.1f}" y="{sy(-stand + off - pd / 2):.1f}" '
                       f'width="{pw * scale:.1f}" height="{pd * scale:.1f}" '
                       f'fill="{rgb(plank_colors[i % len(plank_colors)])}"/>')
        for side in (-1, 1):
            out.append(disc(side * cfg["POND_PEG_SPREAD"], -stand,
                            cfg["POND_PEG_SIZE"][1] / 2, rgb(plank_colors[-1])))

    out.append(disc(0, 0, cfg["POND_RADIUS"] + cfg["POND_RIM_WIDTH"], rgb(cfg.get("POND_RIM_COLOR"))))
    out.append(disc(0, 0, cfg["POND_RADIUS"], rgb(cfg.get("POND_FLOOR_COLOR"))))

    fill_r = pond_fill_radius(cfg, ratio)
    if ratio > 0:
        out.append(disc(0, 0, fill_r, rgb(cfg.get("POND_FILL_COLOR")),
                        'stroke="rgba(255,255,255,.35)"'))

    for x, z, r, color in pond_stones(cfg):
        out.append(disc(x, z, r, rgb(color), 'stroke="rgba(0,0,0,.25)"'))

    if detail:
        for piece in decor:
            ox, _, oz = piece["offset"]
            w, _, d = piece["size"]
            if piece["shape"] == "Ball":
                out.append(disc(ox, oz, w / 2, rgb(piece["color"]), 'stroke="rgba(0,0,0,.3)"'))
            else:
                # Der Loeffelstiel: ein liegender Zylinder, von oben ein
                # Balken. Die Neigung steckt in rotation.Z und verkuerzt ihn
                # im Grundriss — genau das soll man hier sehen.
                lean = math.cos(math.radians(piece["rotation"][2]))
                length = w * abs(lean)
                out.append(f'<rect x="{sx(ox - length / 2):.1f}" y="{sy(oz - d / 2):.1f}" '
                           f'width="{length * scale:.1f}" height="{d * scale:.1f}" rx="2" '
                           f'fill="{rgb(piece["color"])}" stroke="rgba(0,0,0,.3)"/>')

    label = caption if caption is not None else f"{ratio * 100:.0f} % Vorrat"
    out.append(f'<text x="{size_px / 2:.0f}" y="{size_px - 6:.0f}" text-anchor="middle" '
               f'font-size="12" fill="#fff" opacity=".9">{label}</text>')
    out.append("</svg>")
    return "".join(out)


# ---------------------------------------------------------------------------
# Ansicht 3: Schnitt durch die Welt (Weltmitte -> Arena)
# ---------------------------------------------------------------------------

def render_section(cfg, width_px=820, height_px=210):
    """Senkrechter Schnitt entlang der Aussenrichtung eines Plots.

    Das ist die Ansicht, die der Grundriss NICHT zeigen kann: ob der Steg
    ueber dem Wasser liegt statt darin, ob die Sandkante wirklich zwischen
    Wiese und Wasser sitzt und ob die Stufen niedrig genug sind, dass man aus
    dem Wasser wieder an Land kommt. Genau dort verstecken sich Fehler, die
    von oben tadellos aussehen.
    """
    far = pit_distance(cfg) + cfg["PIT_BASE_RADIUS"] + cfg["SHORE_WIDTH"] + 20
    scale = width_px / far
    top_y = 3.0                       # Studs ueber der Wiese, oberer Bildrand
    deep = cfg["ISLAND_HEIGHT"] + 3   # Studs unter der Wiese, unterer Bildrand
    vscale = height_px / (top_y + deep)

    def sx(x):
        return x * scale

    def sy(y):
        return (top_y - y) * vscale

    def box(x0, x1, y_top, y_bottom, fill, extra=""):
        return (f'<rect x="{sx(x0):.1f}" y="{sy(y_top):.1f}" '
                f'width="{sx(x1 - x0):.1f}" height="{(y_top - y_bottom) * vscale:.1f}" '
                f'fill="{fill}" {extra}/>')

    out = [f'<svg viewBox="0 0 {width_px} {height_px}" width="{width_px}" height="{height_px}">']

    # Himmel und Wasser
    out.append(f'<rect x="0" y="0" width="{width_px}" height="{height_px}" fill="#bfe4f5"/>')
    out.append(box(0, far, -cfg["WATER_DROP"], -cfg["WATER_DROP"] - cfg["WATER_HEIGHT"],
                   rgb(cfg.get("WATER_COLOR")), 'opacity=".85"'))

    islands = [
        (0, cfg["PLATFORM_RADIUS"], cfg.get("GRASS_DARK"), 0.0),
        (cfg["PLOT_RING_RADIUS"], cfg["PLOT_ISLAND_RADIUS"], cfg.get("PLOT_ISLAND_COLOR"), 0.0),
        (pit_distance(cfg), cfg["PIT_BASE_RADIUS"], cfg.get("PIT_BASE_COLOR"), cfg["PIT_RIM_DROP"]),
    ]
    for center, radius, color, drop in islands:
        shore = radius + cfg["SHORE_WIDTH"]
        out.append(box(max(0, center - shore), center + shore,
                       -drop - cfg["SHORE_DROP"], -cfg["ISLAND_HEIGHT"], rgb(cfg.get("SHORE_COLOR"))))
        out.append(box(max(0, center - radius), center + radius,
                       -drop, -cfg["ISLAND_HEIGHT"], rgb(color)))

    # Leuchtring am Arena-Sockel
    pit_c = pit_distance(cfg)
    ring_r = cfg["PIT_BASE_RADIUS"] + cfg["PIT_RING_OVERHANG"]
    ring_top = -cfg["PIT_RIM_DROP"] - cfg["PIT_RING_HEIGHT"]
    out.append(box(pit_c - ring_r, pit_c + ring_r,
                   ring_top, ring_top - cfg["PIT_RING_HEIGHT"], rgb(cfg.get("PIT_RING_COLOR"))))

    # Beet auf der Plot-Insel
    ring = cfg["PLOT_RING_RADIUS"]
    out.append(box(ring - cfg["PLOT_SIZE"][2] / 2, ring + cfg["PLOT_SIZE"][2] / 2,
                   cfg["PLOT_SIZE"][1], 0, rgb(cfg.get("GRASS_DARK")), 'stroke="rgba(0,0,0,.3)"'))

    # Goldene Kampfflaeche
    pit = pit_distance(cfg)
    out.append(box(pit - cfg["PIT_RADIUS"], pit + cfg["PIT_RADIUS"],
                   0, -cfg["PIT_FLOOR_HEIGHT"], rgb(cfg.get("PIT_FLOOR_COLOR"))))

    # Die beiden Stege
    deck_top = -cfg["BRIDGE_SINK"]
    deck_bottom = deck_top - cfg["BRIDGE_HEIGHT"]
    for a, b in (
        (cfg["PLATFORM_RADIUS"], ring - cfg["PLOT_ISLAND_RADIUS"]),
        (ring + cfg["PLOT_ISLAND_RADIUS"], ring + cfg["PLOT_ISLAND_RADIUS"] + cfg["ISLAND_GAP"]),
    ):
        # Die Gelaender stehen LINKS UND RECHTS des Decks; dieser Schnitt geht
        # durch die Mitte, wo keins steht. Sie werden trotzdem angedeutet,
        # damit ihre Hoehe im Bild ablesbar bleibt.
        out.append(box(a - cfg["BRIDGE_OVERLAP"], b + cfg["BRIDGE_OVERLAP"],
                       deck_top + cfg["BRIDGE_RAIL_HEIGHT"], deck_bottom,
                       rgb(cfg.get("BRIDGE_RAIL_COLOR")), 'opacity=".35"'))
        out.append(box(a - cfg["BRIDGE_OVERLAP"], b + cfg["BRIDGE_OVERLAP"],
                       deck_top, deck_bottom, rgb(cfg.get("BRIDGE_COLOR"))))

    # Hoehenlinien mit Beschriftung
    for y, label in (
        (0, "Wiese 0"),
        (-cfg["SHORE_DROP"], f'Sand -{cfg["SHORE_DROP"]:.1f}'),
        (-cfg["WATER_DROP"], f'Wasser -{cfg["WATER_DROP"]:.1f}'),
    ):
        out.append(f'<line x1="0" y1="{sy(y):.1f}" x2="{width_px}" y2="{sy(y):.1f}" '
                   f'stroke="rgba(0,0,0,.35)" stroke-dasharray="2 3"/>')
        out.append(f'<text x="4" y="{sy(y) - 3:.1f}" font-size="10" fill="#123">{label}</text>')

    out.append("</svg>")
    return "".join(out)


# ---------------------------------------------------------------------------

def facts(cfg):
    """Dieselben Zusammenhaenge, die MapService.init beim Start nachrechnet."""
    pit_dist = pit_distance(cfg)
    plate_corner = math.hypot(cfg["PLOT_SIZE"][0] / 2, cfg["PLOT_SIZE"][2] / 2)
    expected_ring = cfg["PLATFORM_RADIUS"] + cfg["ISLAND_GAP"] + cfg["PLOT_ISLAND_RADIUS"]
    shore_r = cfg["PLOT_ISLAND_RADIUS"] + cfg["SHORE_WIDTH"]
    neighbour = 2 * cfg["PLOT_RING_RADIUS"] * math.sin(math.pi / cfg["PLOT_COUNT"]) - 2 * shore_r
    world_edge = pit_dist + cfg["PIT_BASE_RADIUS"] + cfg["SHORE_WIDTH"]

    def verdict(ok, good, bad):
        return good if ok else bad

    return [
        ("Hauptinsel", f'Radius {cfg["PLATFORM_RADIUS"]:.0f}'),
        ("Plot-Inseln", f'{int(cfg["PLOT_COUNT"])} x Radius {cfg["PLOT_ISLAND_RADIUS"]:.0f} '
                        f'auf Ring {cfg["PLOT_RING_RADIUS"]:.0f}'),
        ("Arena-Mitte", f"{pit_dist:.0f} Studs von der Weltmitte"),
        ("Steglaenge", f'{cfg["ISLAND_GAP"]:.0f} Studs, 16 Stege'),
        ("Beet auf der Insel",
         verdict(plate_corner <= cfg["PLOT_ISLAND_RADIUS"],
                 f'{cfg["PLOT_ISLAND_RADIUS"] - plate_corner:.1f} Studs Rand',
                 f"RAGT {plate_corner - cfg['PLOT_ISLAND_RADIUS']:.1f} ueber!")),
        ("Ring passt zur Luecke",
         verdict(abs(cfg["PLOT_RING_RADIUS"] - expected_ring) <= 0.5,
                 "ja", f"nein, sollte {expected_ring:.0f} sein")),
        ("Wasser zwischen zwei Plot-Inseln",
         verdict(neighbour > 0, f"{neighbour:.0f} Studs", "UEBERLAPPEN!")),
        ("Wasser reicht bis",
         verdict(world_edge <= cfg["WATER_RADIUS"],
                 f'{cfg["WATER_RADIUS"] - world_edge:.0f} Studs hinter die Arenen',
                 f"ZU KLEIN, Weltrand {world_edge:.0f}")),
        ("Weg Baerchi-Platz → Arena",
         f'rund {pit_dist - cfg["PLOT_RING_RADIUS"] - cfg["BAERCHI_HOME_OFFSET"][2]:.0f} Studs'),
    ]


def main():
    source = SOURCE
    cfg = read_config(source)
    buildings = read_buildings(source)
    pond_decor = read_decor(source, "POND_DECOR", cfg)

    world, _ = render_world(cfg)
    plot = render_plot(cfg, buildings)
    section = render_section(cfg)
    pond = render_pond(cfg, pond_decor, 0.7, 330, caption="70 % Vorrat")
    levels = "".join(
        render_pond(cfg, pond_decor, r, 158, detail=False) for r in (0.0, 0.25, 0.6, 1.0)
    )

    if len(sys.argv) > 2 and sys.argv[1] == "--svg":
        target = Path(sys.argv[2])
        target.mkdir(parents=True, exist_ok=True)
        for name, svg in (("world", world), ("plot", plot), ("section", section), ("pond", pond)):
            (target / f"{name}.svg").write_text(svg, encoding="utf-8")
        for i, r in enumerate((0.0, 0.25, 0.6, 1.0)):
            (target / f"pond_{i}.svg").write_text(
                render_pond(cfg, pond_decor, r, 200, detail=False), encoding="utf-8")
        print(f"Geschrieben: {target}/world.svg, plot.svg, section.svg, pond.svg, pond_0..3.svg")
        return 0

    fact_rows = "".join(f"<tr><td>{k}</td><td>{v}</td></tr>" for k, v in facts(cfg))

    html = f"""<!doctype html>
<html lang="de"><head><meta charset="utf-8">
<title>Map-Grundriss</title>
<style>
  :root {{ color-scheme: light dark; --bg:#f4f1ea; --fg:#241c14; --card:#fff; --line:#0002; }}
  @media (prefers-color-scheme: dark) {{
    :root {{ --bg:#16130f; --fg:#efe7db; --card:#211c16; --line:#fff2; }}
  }}
  body {{ margin:0; padding:32px; background:var(--bg); color:var(--fg);
         font:15px/1.5 system-ui,-apple-system,"Segoe UI",sans-serif; }}
  h1 {{ font-size:22px; margin:0 0 4px; }}
  p.lead {{ margin:0 0 24px; opacity:.7; max-width:66ch; }}
  .grid {{ display:flex; flex-wrap:wrap; gap:20px; align-items:flex-start; }}
  figure {{ margin:0; background:var(--card); border:1px solid var(--line);
            border-radius:12px; padding:16px 18px 12px; }}
  h2 {{ font-size:15px; margin:0 0 10px; }}
  figcaption {{ margin-top:8px; font-size:12px; opacity:.6; max-width:50ch; }}
  table {{ border-collapse:collapse; font-size:13px; }}
  td {{ padding:4px 14px 4px 0; border-bottom:1px solid var(--line); }}
  td:last-child {{ font-variant-numeric:tabular-nums; opacity:.8; }}
</style></head>
<body>
<h1>Map-Grundriss</h1>
<p class="lead">Direkt aus <code>MapConfig.luau</code> gezeichnet, massstabsgetreu.
Die Weltgeometrie haengt an einem guten Dutzend Zahlen, die voneinander abhaengen —
ob ein Beet ueber seine Insel ragt oder ein Steg die naechste Insel verfehlt, sieht
man den Zahlen nicht an, diesem Bild schon. Die Tabelle rechnet dieselben Zusammen&shy;haenge
nach, die auch <code>MapService.init</code> beim Serverstart prueft.</p>
<div class="grid">
  <figure><h2>Die Welt von oben</h2>{world}
    <figcaption>Hauptinsel mit Spawn und Honigmast, davon abgehend acht Stege auf
    die Plot-Inseln und von dort je ein weiterer auf die eigene, goldene
    Arena-Insel.</figcaption></figure>
  <figure><h2>Eine Plot-Insel</h2>{plot}
    <figcaption>Gestrichelt: die unsichtbaren Gebaeude-Koerper (Trefferflaeche
    fuer den Prompt). Gelbe Punkte: die Honig-Tropfen, einer pro eingelagertem
    Honig. Der grosse Kreis rechts unten ist der Honig-Teich, der weisse Punkt
    der Platz des ausgeruesteten Baerchi.</figcaption></figure>
  <figure><h2>Zahlen</h2><table>{fact_rows}</table></figure>
  <figure><h2>Der Honig-Teich</h2>{pond}
    <figcaption>Von oben, mit dem Baerchi-Platz nach oben. Sandkante, Steinkranz
    mit Luecke, abgesenkter Beckenboden, Honig darin — davor die zwei Bohlen, auf
    denen der Baerchi beim Fressen steht.</figcaption></figure>
  <figure><h2>Fuellstand ablesbar?</h2><div style="display:flex;gap:6px">{levels}</div>
    <figcaption>Die Honigflaeche waechst in Breite UND Hoehe mit dem Vorrat. Der
    alte Teich hat den Vorrat zwar gemessen, die Fuellung steckte aber
    vollstaendig im Beckenklotz — sichtbar war davon bei keinem Stand
    etwas.</figcaption></figure>
  <figure><h2>Schnitt: Weltmitte → Arena</h2>{section}
    <figcaption>Die Ansicht, die der Grundriss nicht zeigen kann. Hier sieht man,
    ob der Steg ueber dem Wasser liegt statt darin, ob die Sandkante zwischen
    Wiese und Wasser sitzt und ob die Stufen niedrig genug sind, dass man aus
    dem Wasser wieder an Land kommt.</figcaption></figure>
</div>
</body></html>
"""

    target = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("map_preview.html")
    target.write_text(html, encoding="utf-8")
    print(f"Geschrieben: {target}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
