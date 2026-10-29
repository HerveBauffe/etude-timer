#!/usr/bin/env bash
# Build Android release : un APK par architecture (le plus léger) + tailles mesurées.
# Prérequis : Android SDK (Android Studio ou « flutter doctor --android-licenses »), JDK 17.
# Option :  ./scripts/build_android.sh --aab   → génère aussi le bundle .aab (Google Play).
set -euo pipefail
cd "$(dirname "$0")/.."

[ -d android ] || { echo "Dossier android/ absent : lance d'abord ./scripts/bootstrap.sh" >&2; exit 1; }

# Idempotent : applique le patch Android (notifications, service, alarme…) même si android/ date d'une ancienne version.
dart tool/patch_android.dart .

flutter build apk --release --split-per-abi --split-debug-info=build/debug-info
mkdir -p dist
cp build/app/outputs/flutter-apk/app-*-release.apk dist/

if [ "${1:-}" = "--aab" ]; then
  flutter build appbundle --release --split-debug-info=build/debug-info
  cp build/app/outputs/bundle/release/app-release.aab dist/EtudeTimer.aab
fi

echo
echo "APK produits (taille réelle) :"
for f in dist/app-*-release.apk; do
  [ -f "$f" ] && printf '  %-40s %s\n' "$f" "$(du -h "$f" | cut -f1)"
done
echo
echo "Téléphone/tablette récents : app-arm64-v8a-release.apk. Installation : adb install -r dist/app-arm64-v8a-release.apk"
echo "(ou copie le fichier sur l'appareil et ouvre-le ; autorise « sources inconnues » si demandé)."
echo "Remarque : sans clé de signature perso (android/key.properties), l'APK est signé avec la clé de debug —"
echo "suffisant pour un usage personnel, pas pour une publication."
