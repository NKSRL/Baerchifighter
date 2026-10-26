"""check_all.py - alle Pruefungen in einem Lauf (vor jedem Commit)

Syntax aller .luau (luau-compile), check_locals, alle check_*.py, Modulkarte,
alle Luau-Tests und die Pruef-Sims. Standard: nur rote und bekannte Zeilen
plus Summe (spart Tokens), rote mit ihren letzten Ausgabezeilen. Exit 1,
sobald eine Pruefung rot ist, die nicht in BEKANNT_ROT steht.

Aufruf:  python tools/check_all.py            (alles, ca. 80 s; check_ui braucht ~70 s)
         python tools/check_all.py --schnell  (ohne check_ui)
         python tools/check_all.py -v         (auch die gruenen Zeilen zeigen)
Luau-CLI: luau-bin/ im Repo (SessionStart-Hook) oder LUAU / luau im PATH.
"""
import concurrent.futures as futures
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXE = ".exe" if os.name == "nt" else ""

# Pruefung -> Grund. Bleibt sichtbar ("bekannt"), bricht den Lauf aber nicht ab.
# Jeder Eintrag steht auch in docs/STATUS.md unter "Offen".
BEKANNT_ROT = {
    "test rebirth_rules": "Balance v3: Rebirth-Bedingung R6 ist schwaecher als R5 (Entscheidung offen)",
}

# Sims mit Pruefzielen (Exit 1 bei FAIL). Reine Tabellen/Erkundungen (power_sweep,
# pit_balance, egg_tree_sim, pacing_v2_vorschlag, power_*) laufen nicht mit.
SIMS = [
    "progression_pacing", "tower_calibration", "egg_tree_check", "path_balance",
    "fight_timeline", "boss_balance", "fortschritt_w1", "drop_rates_v2", "comb_respawn",
]


def tool(name: str) -> str:
    local = os.path.join(ROOT, "luau-bin", name + EXE)
    if os.path.exists(local):
        return local
    if name == "luau" and os.environ.get("LUAU"):
        return os.environ["LUAU"]
    return name


LUAU = tool("luau")
COMPILE = tool("luau-compile")
PY = sys.executable


def run(cmd, timeout=300):
    env = dict(os.environ, LUAU=LUAU, PYTHONIOENCODING="utf-8")
    try:
        p = subprocess.run(cmd, cwd=ROOT, env=env, capture_output=True, text=True,
                           encoding="utf-8", errors="replace", timeout=timeout)
        return p.returncode, (p.stdout + p.stderr)
    except FileNotFoundError as e:
        return 127, f"Programm fehlt: {e.filename} (Luau-CLI nach luau-bin/ legen, siehe CLAUDE.md)"
    except subprocess.TimeoutExpired:
        return 124, f"Zeitlimit {timeout} s ueberschritten"


def syntax():
    bad = []
    files = []
    for d, _, names in os.walk(os.path.join(ROOT, "src")):
        files += [os.path.join(d, n) for n in names if n.endswith(".luau")]
    for f in sorted(files):
        code, out = run([COMPILE, "--null", f], timeout=60)
        if code == 127:
            return code, out
        if code != 0:
            bad.append(out.strip())
    return (1 if bad else 0), "\n".join(bad) if bad else f"{len(files)} Dateien"


def members():
    code, out = run([PY, "tools/check_members.py"])
    # check_members endet auch bei Funden mit 0
    if code == 0 and "Keine unbekannten Modul-Felder" not in out:
        code = 1
    return code, out


def jobs(fast: bool):
    j = {"syntax": syntax, "check_members": members}
    for name in ["check_locals", "check_feedback", "check_consistency", "check_loc", "check_ui", "check_decor"]:
        if fast and name == "check_ui":
            continue
        j[name] = (lambda n=name: run([PY, f"tools/{n}.py"]))
    j["modulkarte"] = lambda: run([PY, "tools/make_modulkarte.py", "--check"])
    tdir = os.path.join(ROOT, "tools", "luau-tests")
    for name in sorted(os.listdir(tdir)):
        if not name.endswith(".test.lua"):
            continue
        path = os.path.join("tools", "luau-tests", name)
        src = open(os.path.join(ROOT, path), encoding="utf-8").read()
        direct = 'require("../../' in src   # reine Luau-Tests ohne Roblox-Buendel
        cmd = [LUAU, path] if direct else [PY, "tools/luau-tests/run_local.py", path]
        j["test " + name[:-9]] = (lambda c=cmd: run(c))
    for sim in SIMS:
        j["sim " + sim] = (lambda s=sim: run([PY, "tools/luau-tests/run_local.py", f"tools/sim/{s}.lua"]))
    return j


def main() -> int:
    fast = "--schnell" in sys.argv
    verbose = "-v" in sys.argv
    start = time.time()
    todo = jobs(fast)
    results = {}
    with futures.ThreadPoolExecutor(max_workers=max(2, os.cpu_count() or 2)) as pool:
        running = {pool.submit(lambda f=f: (time.time(), f(), time.time())): n for n, f in todo.items()}
        for fut in futures.as_completed(running):
            t0, (code, out), t1 = fut.result()
            results[running[fut]] = (code, out, t1 - t0)
    red, known = [], []
    for name in todo:
        code, out, dt = results[name]
        if code == 0:
            if verbose:
                print(f"ok    {name}  ({dt:.0f} s)" if dt >= 5 else f"ok    {name}")
            continue
        elif name in BEKANNT_ROT:
            known.append(name)
            print(f"BEKANNT {name}: {BEKANNT_ROT[name]}")
        else:
            red.append(name)
            print(f"FEHL  {name}  (Exit {code})")
            tail = [l for l in out.strip().split("\n") if l.strip() and not l.startswith("ok")][-12:]
            for line in tail:
                print("      " + line[:200])
    print(f"--- {len(todo) - len(red) - len(known)} ok, {len(known)} bekannt rot, {len(red)} rot, {time.time() - start:.0f} s"
          + ("  (ohne check_ui)" if fast else ""))
    return 1 if red else 0


if __name__ == "__main__":
    sys.exit(main())
