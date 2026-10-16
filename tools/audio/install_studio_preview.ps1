# install_studio_preview.ps1 — kopiert die erzeugten WAVs in den Studio-Content-Ordner,
# damit Audio.luau sie im Studio per rbxasset://sounds/hbb/<datei>.wav abspielen kann
# (nur lokale Vorschau, kein Upload; im echten Spiel zaehlen nur die Ids in Audio.luau).
# Aufruf:  powershell -File tools/audio/install_studio_preview.ps1
$ErrorActionPreference = "Stop"
$out = Join-Path $PSScriptRoot "out"
if (-not (Test-Path $out)) { throw "Erst 'node tools/audio/synth.js' ausfuehren." }

$running = Get-Process RobloxStudioBeta -ErrorAction SilentlyContinue | Select-Object -First 1
if ($running) { $versions = @(Split-Path $running.Path) }
else { $versions = Get-ChildItem "$env:LOCALAPPDATA\Roblox\Versions" -Directory | Where-Object { Test-Path (Join-Path $_.FullName "RobloxStudioBeta.exe") } | ForEach-Object { $_.FullName } }

foreach ($v in $versions) {
    $dst = Join-Path $v "content\sounds\hbb"
    New-Item -ItemType Directory -Force $dst | Out-Null
    Get-ChildItem (Join-Path $out "music") -Filter *.wav | ForEach-Object { Copy-Item $_.FullName (Join-Path $dst ("music_" + $_.Name)) -Force }
    Get-ChildItem (Join-Path $out "sfx") -Filter *.wav | ForEach-Object { Copy-Item $_.FullName (Join-Path $dst ("sfx_" + $_.Name)) -Force }
    Write-Host "Kopiert nach $dst"
}
