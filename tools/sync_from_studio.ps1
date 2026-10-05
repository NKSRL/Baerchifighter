# Holt den aktuellen Stand aus Roblox Studio ins Repo und laedt ihn auf GitHub.
# Fuer den Fall, dass in Studio direkt gearbeitet wurde und GitHub veraltet ist.
#
# Vorher in Studio: Datei -> "Als Datei speichern unter..." -> RBL.rbxl
# in diesen Projektordner (wird von .gitignore ignoriert).
#
# Dann im Projektordner:
#   powershell -ExecutionPolicy Bypass -File tools\sync_from_studio.ps1
#
# Nur was default.project.json abbildet (ReplicatedStorage, ServerScriptService,
# StarterPlayerScripts) wird in src/ zurueckgeschrieben. Workspace-Bauten nicht.

param(
    [string]$Place = "RBL.rbxl",
    [string]$Message = "Stand aus Roblox Studio uebernommen"
)
$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

if (-not (Test-Path $Place)) { throw "$Place nicht gefunden. Erst in Studio als Datei speichern." }
if (git status --porcelain) { throw "Es gibt ungespeicherte Aenderungen im Repo. Erst committen oder verwerfen." }

git pull

# Sicherung von src (bleibt lokal, siehe .gitignore)
$Backup = "_backup_" + (Get-Date -Format "yyyy-MM-dd_HHmm")
Copy-Item -Recurse src $Backup
Write-Host "Sicherung: $Backup"

# Studio-Stand in die Dateien zurueckschreiben
rojo syncback default.project.json --input $Place --non-interactive

Write-Host "`nGeaenderte Dateien:"
git status --short
if (-not (git status --porcelain)) { Write-Host "Nichts geaendert - GitHub ist schon aktuell."; exit 0 }

$Answer = Read-Host "`nSo auf GitHub hochladen? (j/n)"
if ($Answer -ne "j") { Write-Host "Abgebrochen. Mit 'git checkout -- . ; git clean -fd src' zuruecksetzen."; exit 0 }

git add -A
git commit -m $Message
git push
Write-Host "GitHub ist jetzt auf dem Studio-Stand."
