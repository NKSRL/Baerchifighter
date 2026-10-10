"""preview.py — Bildschirmfotos der Client-UI ohne Studio (08.10., Paket D)

Laesst die echten UI-Module (src/client, src/shared) in einer Roblox-Attrappe
laufen (shim.lua + driver.lua, luau-CLI), nimmt den entstandenen
Instanz-Baum als JSON und zeichnet ihn im Browser (render.js, Playwright/
Chromium) — mit Roblox-Layoutregeln (UDim2, AnchorPoint, UIListLayout,
UIPadding, UIScale, UICorner, UIStroke, UIGradient, TextScaled).

Das ist eine VORSCHAU, kein Ersatz fuer Studio: Schriftglaettung, Emoji und
Bilder (Icons aus assets/icons) sind angenaehert. Fuer Layout, Hierarchie,
Ueberlauf, Abstaende und Kontraste reicht es.

Aufruf (aus dem Repo):
  python tools/ui_preview/preview.py --out shots \\
      --sizes 1920x1080,1366x768,1024x768,812x375 --scenario new2 --lang de
  python tools/ui_preview/preview.py --old ...      (altes CombatPanel)
  python tools/ui_preview/preview.py --leak         (50x oeffnen/schliessen)
Braucht: luau (PATH oder $LUAU), python-playwright mit Chromium.
"""
import argparse, json, os, re, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
MAPS = {"src/shared": "ReplicatedStorage", "src/client": "StarterPlayerScripts"}


def long_string(text):
    level = 1
    while ("]" + "=" * level + "]") in text:
        level += 1
    eq = "=" * level
    return "[" + eq + "[\n" + text + "]" + eq + "]"


def lua_value(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if v is None:
        return "nil"
    return json.dumps(v)


def bundle(args):
    parts = ["local __SOURCES = {}"]
    for rel, root in MAPS.items():
        base = os.path.join(ROOT, rel)
        for dirpath, _, files in os.walk(base):
            for name in files:
                if not name.endswith(".luau"):
                    continue
                full = os.path.join(dirpath, name)
                inner = os.path.relpath(full, base).replace(os.sep, "/")
                for suffix in (".server.luau", ".client.luau", ".luau"):
                    if inner.endswith(suffix):
                        inner = inner[: -len(suffix)]
                        break
                parts.append("__SOURCES[%s] = %s" % (json.dumps(root + "/" + inner), long_string(open(full, encoding="utf-8").read())))
    lua_args = "__ARGS = {" + ", ".join("%s = %s" % (k, lua_value(v)) for k, v in args.items()) + "}"
    shim = open(os.path.join(HERE, "shim.lua"), encoding="utf-8").read()
    driver = open(os.path.join(HERE, "driver.lua"), encoding="utf-8").read()
    return "\n".join(parts) + "\n" + lua_args + "\n" + shim + "\n" + driver


def run_tree(args):
    code = bundle(args)
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as handle:
        handle.write(code)
        path = handle.name
    luau = os.environ.get("LUAU", "luau")
    proc = subprocess.run([luau, path], capture_output=True, text=True, encoding="utf-8")
    out = proc.stdout
    tree, logs = None, []
    for line in out.splitlines():
        if line.startswith("@@JSON@@"):
            tree = json.loads(line[len("@@JSON@@"):])
        else:
            logs.append(line)
    if proc.returncode != 0 or tree is None:
        sys.stderr.write(out[-4000:] + proc.stderr[-4000:])
        raise SystemExit("Luau-Lauf fehlgeschlagen")
    return tree, logs


def icon_map():
    """Icons.luau: Name -> rbxassetid; dazu die PNG aus assets/icons."""
    src = open(os.path.join(ROOT, "src/client/UI/Icons.luau"), encoding="utf-8").read()
    result = {}
    for name, aid in re.findall(r'^\s*(\w+)\s*=\s*"(rbxassetid://\d+)"', src, re.M):
        png = os.path.join(ROOT, "assets/icons", name + ".png")
        if os.path.exists(png):
            result[aid] = "file://" + png
    return result


def render(trees, out_dir, base_name):
    from playwright.sync_api import sync_playwright
    font = os.path.join(HERE, "fredoka-one.woff2")   # Fredoka One, SIL Open Font License
    html_tpl = open(os.path.join(HERE, "render.html"), encoding="utf-8").read()
    js = open(os.path.join(HERE, "render.js"), encoding="utf-8").read()
    os.makedirs(out_dir, exist_ok=True)
    paths = []
    with sync_playwright() as p:
        browser = p.chromium.launch()
        for (w, h, label), tree in trees:
            html = (html_tpl.replace("%%FONT%%", "file://" + font)
                    .replace("%%TREE%%", json.dumps(tree))
                    .replace("%%ICONS%%", json.dumps(icon_map()))
                    .replace("%%JS%%", js).replace("%%W%%", str(w)).replace("%%H%%", str(h)))
            page_path = os.path.join(out_dir, f"{base_name}_{label}.html")
            open(page_path, "w", encoding="utf-8").write(html)
            page = browser.new_page(viewport={"width": w, "height": h})
            page.goto("file://" + page_path)
            page.wait_for_function("window.__done === true", timeout=15000)
            png = os.path.join(out_dir, f"{base_name}_{label}.png")
            page.screenshot(path=png)
            report = page.evaluate("window.__report || null")
            if report:
                open(os.path.join(out_dir, f"{base_name}_{label}.json"), "w").write(json.dumps(report, indent=1))
            page.close()
            paths.append(png)
        browser.close()
    return paths


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(ROOT, "docs", "screens"))
    ap.add_argument("--sizes", default="1920x1080")
    ap.add_argument("--scenario", default="new2")
    ap.add_argument("--lang", default="de")
    ap.add_argument("--pass", dest="pass_", action="store_true")
    ap.add_argument("--pass-ready", action="store_true")
    ap.add_argument("--running", action="store_true")
    ap.add_argument("--old", action="store_true")
    ap.add_argument("--hud", action="store_true")
    ap.add_argument("--leak", action="store_true")
    ap.add_argument("--name", default=None)
    a = ap.parse_args()
    trees = []
    for size in a.sizes.split(","):
        w, h = (int(x) for x in size.lower().split("x"))
        args = {"width": w, "height": h, "lang": a.lang, "scenario": a.scenario, "pass": a.pass_,
                "passReady": a.pass_ready, "v2": not a.old, "panel": True, "hud": a.hud,
                "running": a.running, "leak": a.leak}
        tree, logs = run_tree(args)
        for line in logs:
            if line.strip() and ("Fehler" in line or "driver" in line or "warn" in line or "@@LEAK@@" in line):
                print(line)
        trees.append(((w, h, f"{w}x{h}"), tree))
    name = a.name or ("old" if a.old else "v2") + f"_{a.scenario}_{a.lang}" + ("_pass" if a.pass_ else "")
    for path in render(trees, a.out, name):
        print(path)


if __name__ == "__main__":
    main()
