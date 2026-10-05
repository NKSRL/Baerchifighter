"""check_feedback.py - HBB Paket 1

Prueft, dass
  1. jeder Schluessel aus Notify.emit("...") in FeedbackConfig.CLASSES steht,
  2. kein Toast.show/success/info im Client ausserhalb eines Notify.emit-
     Aufrufs steht (ausser in Toast.luau selbst und als Rueckfall in
     Notify-Rueckrufen fuer unbekannte Event-Notizen),
  3. hoechstens 20 % der Klassen TOAST sind.

Aufruf: python tools/check_feedback.py   (aus dem Repo-Wurzelordner)
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CLIENT = os.path.join(ROOT, "src", "client")
CONFIG = os.path.join(ROOT, "src", "shared", "Config", "FeedbackConfig.luau")

cfg = open(CONFIG, encoding="utf-8").read()
classes = dict(re.findall(r'^\s*([a-z_]+)\s*=\s*"(ICON|MOMENT|TOAST|NONE)"', cfg, re.M))

errors = []
used = set()
for dirpath, _, files in os.walk(CLIENT):
    for name in files:
        if not name.endswith(".luau"):
            continue
        path = os.path.join(dirpath, name)
        rel = os.path.relpath(path, ROOT)
        lines = open(path, encoding="utf-8").read().split("\n")
        for i, line in enumerate(lines):
            if line.strip().startswith("--"):
                continue
            for key in re.findall(r'Notify\.emit\("([a-z_]+)"', line):
                used.add(key)
                if key not in classes:
                    errors.append(f"{rel}:{i+1}: Schluessel '{key}' fehlt in FeedbackConfig")
            if name in ("Toast.luau",):
                continue
            if re.search(r'\bToast\.(show|success|info)\(', line):
                window = "\n".join(lines[max(0, i - 25):i])
                if "Notify.emit(" not in window:
                    errors.append(f"{rel}:{i+1}: Toast ohne Notify.emit")

unused = sorted(set(classes) - used)
toast_share = sum(1 for c in classes.values() if c == "TOAST") / max(1, len(classes))

print(f"Klassen: {len(classes)} | benutzt: {len(used)} | TOAST-Anteil: {toast_share:.0%}")
if unused:
    print("Klassifiziert, aber nicht benutzt:", ", ".join(unused))
if toast_share > 0.20:
    errors.append(f"TOAST-Anteil {toast_share:.0%} > 20 %")
for e in errors:
    print("FEHLER", e)
sys.exit(1 if errors else 0)
