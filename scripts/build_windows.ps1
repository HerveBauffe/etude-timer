# Build Windows release + version portable (zip) + taille mesurée.
# Usage :  powershell -ExecutionPolicy Bypass -File scripts\build_windows.ps1
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

flutter build windows --release --split-debug-info=build\debug-info

$rel = 'build\windows\x64\runner\Release'
if (-not (Test-Path $rel)) { Write-Error "Dossier de build introuvable : $rel" }

# Portable : un dossier EtudeTimerData à côté de l'exécutable => toutes les données restent dedans.
$stage = 'dist\EtudeTimer-portable'
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stage | Out-Null
Copy-Item "$rel\*" $stage -Recurse
New-Item -ItemType Directory -Force -Path "$stage\EtudeTimerData" | Out-Null
Set-Content -Path "$stage\EtudeTimerData\LISEZMOI.txt" -Value "Ce dossier contient les donnees de la version portable. Supprime-le pour utiliser %APPDATA%\etude-timer a la place."
Compress-Archive -Path "$stage\*" -DestinationPath 'dist\EtudeTimer-windows-portable.zip' -Force

function Mb($bytes) { '{0:N1} Mo' -f ($bytes / 1MB) }
$unpacked = (Get-ChildItem $rel -Recurse -File | Measure-Object Length -Sum).Sum
$zipped = (Get-Item 'dist\EtudeTimer-windows-portable.zip').Length
Write-Host ""
Write-Host "Dossier de build (decompresse) : $(Mb $unpacked)"
Write-Host "Zip portable                   : $(Mb $zipped)"
Write-Host ""
Write-Host "Installeur (optionnel) : ouvre installer\etude_timer.iss avec Inno Setup puis Compiler."
