#!/usr/bin/env python3
"""
make_update_rbxmx.py — baut eine Update-Datei (.rbxmx) fuer Studio OHNE Rojo

Warum: Rojo loescht in Studio alles, was nur dort existiert (Modelle, das
BaerchiTemplate ...). Diese Datei bringt nur die GEAENDERTEN Skripte mit; der
Einspiel-Befehl (tools/einspielen.lua) verteilt sie an ihre Plaetze.

Aufruf:
    python3 tools/make_update_rbxmx.py <commit>            # alles seit <commit>
    python3 tools/make_update_rbxmx.py <commit> -o datei.rbxmx

Inhalt der Datei: ein Ordner "HBBUpdate" mit den Unterordnern
ReplicatedStorage / ServerScriptService / StarterPlayerScripts, darin die
Skripte in derselben Ordnerstruktur wie im Spiel (wie default.project.json):
    src/shared/X/Y.luau          -> ReplicatedStorage.X.Y        (ModuleScript)
    src/server/X/Y.server.luau   -> ServerScriptService.X.Y      (Script)
    src/client/X/Y.client.luau   -> StarterPlayerScripts.X.Y     (LocalScript)
Skripte und LocalScripts sind in der Datei deaktiviert (Disabled), damit
nichts im Workspace losläuft, bevor es an seinem Platz ist.

Geloeschte Dateien werden nur gemeldet (nichts loeschen ist Projektregel).

Schutz (10.10.2026): Enthaelt das Update WorldFXConfig oder SkillFXConfig,
muessen deren Asset-IDs (SOUNDS, TEXTURE_IDS, TEXTURES) gefuellt sein
(tools/check_asset_ids.py). Sonst wird KEINE Datei geschrieben — das Update
wuerde die in Studio eingetragenen IDs leeren. --allow-empty-ids nur, wenn
das wirklich gewollt ist.
"""
import argparse
import subprocess
import sys
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parent.parent
ROOTS = {
    "src/shared": "ReplicatedStorage",
    "src/server": "ServerScriptService",
    "src/client": "StarterPlayerScripts",
}


def changed_files(since: str):
    out = subprocess.check_output(
        ["git", "diff", "--name-status", since, "HEAD", "--", "src"], cwd=ROOT, text=True
    )
    files, deleted = [], []
    for line in out.splitlines():
        parts = line.split("\t")
        status, path = parts[0], parts[-1]
        if not path.endswith(".luau"):
            continue
        if status.startswith("D"):
            deleted.append(path)
        else:
            files.append(path)
    return sorted(set(files)), deleted


def classify(path: str):
    """(Dienst, [Ordner...], Name, Klasse) fuer einen Pfad unter src/."""
    for prefix, service in ROOTS.items():
        if path.startswith(prefix + "/"):
            rel = path[len(prefix) + 1:]
            break
    else:
        raise ValueError(path)
    parts = rel.split("/")
    name = parts[-1]
    if name.endswith(".server.luau"):
        name, cls = name[: -len(".server.luau")], "Script"
    elif name.endswith(".client.luau"):
        name, cls = name[: -len(".client.luau")], "LocalScript"
    else:
        name, cls = name[: -len(".luau")], "ModuleScript"
    return service, parts[:-1], name, cls


def cdata(text: str) -> str:
    # "]]>" darf in CDATA nicht vorkommen: an der Stelle aufteilen
    return "<![CDATA[" + text.replace("]]>", "]]]]><![CDATA[>") + "]]>"


class Node:
    def __init__(self, name, cls="Folder", source=None):
        self.name, self.cls, self.source, self.children = name, cls, source, {}


def build_tree(files):
    root = Node("HBBUpdate")
    for path in files:
        service, folders, name, cls = classify(path)
        node = root.children.setdefault(service, Node(service))
        for f in folders:
            node = node.children.setdefault(f, Node(f))
        source = (ROOT / path).read_text(encoding="utf-8")
        node.children[name] = Node(name, cls, source)
    return root


def write_item(node, out, counter):
    counter[0] += 1
    ref = f"RBX{counter[0]}"
    out.append(f'<Item class="{node.cls}" referent="{ref}"><Properties>')
    out.append(f'<string name="Name">{escape(node.name)}</string>')
    if node.source is not None:
        if node.cls in ("Script", "LocalScript"):
            out.append('<bool name="Disabled">true</bool>')
        out.append(f'<ProtectedString name="Source">{cdata(node.source)}</ProtectedString>')
    out.append("</Properties>")
    for child in sorted(node.children.values(), key=lambda n: n.name):
        write_item(child, out, counter)
    out.append("</Item>")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("since", help="Commit, seit dem die Aenderungen gelten")
    parser.add_argument("-o", "--out", default=None)
    parser.add_argument("--allow-empty-ids", action="store_true",
                        help="Update auch mit leeren Asset-IDs schreiben (leert sie in Studio!)")
    args = parser.parse_args()

    files, deleted = changed_files(args.since)
    if not files:
        print("Keine geaenderten .luau-Dateien.")
        return 1

    # Asset-IDs: kein Update, das in Studio gefuellte IDs wieder leert
    sys.path.insert(0, str(ROOT / "tools"))
    import check_asset_ids
    problems = []
    for path in files:
        name = Path(path).name[: -len(".luau")]
        if name in check_asset_ids.MINDESTENS:
            problems += check_asset_ids.check(name, (ROOT / path).read_text(encoding="utf-8"))
    if problems and not args.allow_empty_ids:
        print("ABBRUCH: Das Update wuerde Asset-IDs in Studio leeren. Erst die IDs aus Studio")
        print("ins Repo uebernehmen (tools/check_asset_ids.py muss gruen sein).")
        return 1
    tree = build_tree(files)
    out = [
        '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">'
    ]
    write_item(tree, out, [0])
    out.append("</roblox>")

    target = Path(args.out) if args.out else ROOT / "updates" / f"HBBUpdate_seit_{args.since[:7]}.rbxmx"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("\n".join(out), encoding="utf-8")

    print(f"{len(files)} Skripte -> {target.relative_to(ROOT) if target.is_relative_to(ROOT) else target}")
    for path in files:
        service, folders, name, cls = classify(path)
        print(f"  {cls:<12} {'.'.join([service] + folders + [name])}")
    if deleted:
        print("Im Repo geloescht (in Studio NICHT automatisch entfernt):")
        for path in deleted:
            print("  ", path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
