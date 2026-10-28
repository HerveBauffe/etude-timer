# Génère les dossiers de plate-forme (windows/, linux/, android/), adapte le projet Android puis installe les dépendances.
# À lancer UNE fois :  powershell -ExecutionPolicy Bypass -File scripts\bootstrap.ps1
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  Write-Error "Flutter est introuvable dans le PATH. Installe-le : https://docs.flutter.dev/get-started/install"
}

flutter create --platforms=windows,linux,android --project-name etude_timer --org be.etudetimer .
if ($LASTEXITCODE -ne 0) { Write-Error "flutter create a echoue." }
# `flutter create` ajoute un test d'exemple qui ne correspond pas a cette appli : on le retire.
Remove-Item -Force -ErrorAction SilentlyContinue test\widget_test.dart
flutter pub get
if ($LASTEXITCODE -ne 0) { Write-Error "flutter pub get a echoue." }
# Sans cette etape, l'APK release n'a pas la permission INTERNET (la synchro WebDAV echouerait).
dart tool/patch_android.dart . @args
if ($LASTEXITCODE -ne 0) { Write-Error "patch_android a echoue." }
Write-Host ""
Write-Host "Pret. Pour lancer en developpement :  flutter run -d windows"
