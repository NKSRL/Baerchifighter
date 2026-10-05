# Installiert Rojo 7.7.0 (passend zu aftman.toml) und das Rojo-Studio-Plugin.
# Einmalig in PowerShell ausfuehren:
#   powershell -ExecutionPolicy Bypass -File tools\setup_rojo.ps1
# Danach PowerShell neu oeffnen, damit "rojo" im PATH ist.

$ErrorActionPreference = "Stop"
$Version = "7.7.0"
$BinDir  = Join-Path $env:USERPROFILE ".rojo\bin"
$Url     = "https://github.com/rojo-rbx/rojo/releases/download/v$Version/rojo-$Version-windows-x86_64.zip"

# Git wird fuer den Abgleich mit GitHub gebraucht
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "Git fehlt - installiere ueber winget ..."
    winget install --id Git.Git -e --source winget
}

Write-Host "Lade Rojo $Version ..."
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
$Zip = Join-Path $env:TEMP "rojo-$Version.zip"
Invoke-WebRequest -Uri $Url -OutFile $Zip
Expand-Archive -Path $Zip -DestinationPath $BinDir -Force
Remove-Item $Zip

# Ordner dauerhaft in den Benutzer-PATH aufnehmen
$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($UserPath -notlike "*$BinDir*") {
    [Environment]::SetEnvironmentVariable("Path", "$UserPath;$BinDir", "User")
}
$env:Path += ";$BinDir"

& (Join-Path $BinDir "rojo.exe") --version
# Studio-Plugin installieren (Studio danach einmal neu starten)
& (Join-Path $BinDir "rojo.exe") plugin install
Write-Host "Fertig. PowerShell und Roblox Studio neu starten."
