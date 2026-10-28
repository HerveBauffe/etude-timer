# Build Android release : un APK par architecture + tailles mesurées.
# Prerequis : Android SDK, JDK 17.   Option : -Aab  genere aussi le bundle .aab
#   powershell -ExecutionPolicy Bypass -File scripts\build_android.ps1 [-Aab]
param([switch]$Aab)
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

if (-not (Test-Path android)) { Write-Error "Dossier android/ absent : lance d'abord scripts\bootstrap.ps1" }

flutter build apk --release --split-per-abi --split-debug-info=build/debug-info
if ($LASTEXITCODE -ne 0) { Write-Error "Le build Android a echoue (voir les messages ci-dessus ; README > Depannage Android)." }
New-Item -ItemType Directory -Force dist | Out-Null
Copy-Item build\app\outputs\flutter-apk\app-*-release.apk dist\ -Force

if ($Aab) {
  flutter build appbundle --release --split-debug-info=build/debug-info
  if ($LASTEXITCODE -ne 0) { Write-Error "Le build du bundle a echoue." }
  Copy-Item build\app\outputs\bundle\release\app-release.aab dist\EtudeTimer.aab -Force
}

Write-Host ""
Write-Host "APK produits (taille reelle) :"
Get-ChildItem dist\app-*-release.apk | ForEach-Object { "  {0,-40} {1:N1} Mo" -f $_.Name, ($_.Length / 1MB) }
Write-Host ""
Write-Host "Appareils recents : app-arm64-v8a-release.apk.  Installation : adb install -r dist\app-arm64-v8a-release.apk"
Write-Host "Sans cle de signature perso (android\key.properties) l'APK est signe avec la cle de debug : usage personnel uniquement."
