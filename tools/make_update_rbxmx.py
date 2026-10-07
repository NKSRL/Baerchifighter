#!/usr/bin/env python3
"""
make_update_rbxmx.py — Update-Datei fuer Studio OHNE Rojo.

Warum: Rojo macht ReplicatedStorage, ServerScriptService und
StarterPlayerScripts exakt zum Repo-Stand und LOESCHT dabei alles, was nur in
Studio existiert (Modelle, Studio-Skripte, neuere Staende vom Heim-PC).
Diese Datei dagegen ersetzt nur den Quelltext der Skripte, die sich geaendert
haben, legt neue an und loescht NICHTS.

Aufruf (aus dem Projektordner):
    python tools/make_update_rbxmx.py                  # Aenderungen seit 52f75c1
    python tools/make_update_rbxmx.py <commit>         # Aenderungen seit <commit>
    python tools/make_update_rbxmx.py --all            # alle Skripte

Ergebnis: updates/HBBUpdate.rbxmx und updates/HBBUpdate_Befehl.lua

In Studio:
  1. Datei → Aus Datei importieren (bzw. Rechtsklick Workspace → "Insert from
     File...") → updates/HBBUpdate.rbxmx. Es erscheint ein Ordner
     "HBBUpdate" im Workspace.
  2. Inhalt von updates/HBBUpdate_Befehl.lua in die Befehlsleiste (Ansicht →
     Befehlsleiste) kopieren, Enter. Im Ausgabe-Fenster steht, was ersetzt
     und was neu angelegt wurde. Der Ordner "HBBUpdate" verschwindet danach.
  3. Strg+Z macht den ganzen Einspiel-Schritt rueckgaengig (ein Wegpunkt).
"""

import subprocess
import sys
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_BASE = "52f75c1"   # Stand vor UI-Qualitaet Schritt 1

# Ordner im Repo → Pfad in Studio (wie default.project.json)
MAPPING = {
    "src/shared": "ReplicatedStorage",
    "src/server": "ServerScriptService",
    "src/client": "StarterPlayerScripts",
}


def changed_files(base):
    out = subprocess.run(
        ["git", "diff", "--name-only", "--diff-filter=AMR", base, "HEAD", "--", "src"],
        cwd=ROOT, capture_output=True, text=True, check=True,
    ).stdout.split()
    return [p for p in out if p.endswith(".luau")]


def all_files():
    return [p.relative_to(ROOT).as_posix() for p in sorted((ROOT / "src").rglob("*.luau"))]


def classify(name):
    if name.endswith(".server.luau"):
        return "Script", name[: -len(".server.luau")]
    if name.endswith(".client.luau"):
        return "LocalScript", name[: -len(".client.luau")]
    return "ModuleScript", name[: -len(".luau")]


def cdata(text):
    return "<![CDATA[" + text.replace("]]>", "]]]]><![CDATA[>") + "]]>"


def main():
    args = sys.argv[1:]
    if "--all" in args:
        files = all_files()
    else:
        files = changed_files(args[0] if args else DEFAULT_BASE)
    if not files:
        print("Keine geaenderten Skripte.")
        return 0

    # Baum aufbauen: Dienst → Ordner → ... → Skript
    tree = {}
    for rel in files:
        for prefix, service in MAPPING.items():
            if rel.startswith(prefix + "/"):
                parts = [service] + rel[len(prefix) + 1:].split("/")
                node = tree
                for folder in parts[:-1]:
                    node = node.setdefault(folder, {})
                node[parts[-1]] = rel
                break

    ref = [0]

    def item(cls, name, inner):
        ref[0] += 1
        return (f'<Item class="{cls}" referent="RBX{ref[0]}"><Properties>'
                f'<string name="Name">{escape(name)}</string>{inner}</Properties>')

    def emit(name, node):
        if isinstance(node, str):
            cls, script_name = classify(name)
            source = (ROOT / node).read_text(encoding="utf-8")
            return item(cls, script_name, f'<ProtectedString name="Source">{cdata(source)}</ProtectedString>') + "</Item>"
        children = "".join(emit(k, v) for k, v in sorted(node.items()))
        return item("Folder", name, "") + children + "</Item>"

    body = emit("HBBUpdate", tree)
    xml = '<roblox version="4">' + body + "</roblox>\n"

    out_dir = ROOT / "updates"
    out_dir.mkdir(exist_ok=True)
    (out_dir / "HBBUpdate.rbxmx").write_text(xml, encoding="utf-8")
    (out_dir / "HBBUpdate_Befehl.lua").write_text(COMMAND, encoding="utf-8")
    print(f"{len(files)} Skripte → updates/HBBUpdate.rbxmx (+ HBBUpdate_Befehl.lua)")
    return 0


# Einspiel-Befehl fuer die Studio-Befehlsleiste. Ersetzt nur Source, legt
# Fehlendes an, loescht nichts ausser dem importierten Hilfsordner.
COMMAND = """local CHS = game:GetService("ChangeHistoryService") CHS:SetWaypoint("vor HBBUpdate") local root = workspace:FindFirstChild("HBBUpdate") if not root then warn("HBBUpdate: Ordner 'HBBUpdate' nicht im Workspace - erst die .rbxmx importieren") return end local targets = { ReplicatedStorage = game:GetService("ReplicatedStorage"), ServerScriptService = game:GetService("ServerScriptService"), StarterPlayerScripts = game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts") } local replaced, created = 0, 0 local function walk(src, dst, path) for _, child in src:GetChildren() do local here = path .. "/" .. child.Name if child:IsA("LuaSourceContainer") then local existing = dst:FindFirstChild(child.Name) if existing and existing:IsA("LuaSourceContainer") then if existing.ClassName ~= child.ClassName then warn("HBBUpdate: andere Skript-Art in Studio, nur Quelltext ersetzt:", here, existing.ClassName, "->", child.ClassName) end existing.Source = child.Source replaced += 1 else child:Clone().Parent = dst created += 1 print("HBBUpdate: neu angelegt", here) end elseif child:IsA("Folder") then local folder = dst:FindFirstChild(child.Name) if not folder then folder = Instance.new("Folder") folder.Name = child.Name folder.Parent = dst print("HBBUpdate: Ordner angelegt", here) end walk(child, folder, here) end end end for name, service in targets do local part = root:FindFirstChild(name) if part then walk(part, service, name) end end root:Destroy() CHS:SetWaypoint("HBBUpdate eingespielt") print(("HBBUpdate: %d Skripte ersetzt, %d neu angelegt, nichts geloescht"):format(replaced, created))
"""

if __name__ == "__main__":
    sys.exit(main())
