#!/usr/bin/env bash
# Génère les dossiers de plate-forme (windows/, linux/, android/) qui ne sont pas versionnés, adapte le projet
# Android (permission INTERNET, règles de sauvegarde), puis installe les dépendances.
# À lancer UNE fois après avoir récupéré le projet :  ./scripts/bootstrap.sh
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter est introuvable dans le PATH. Installe-le : https://docs.flutter.dev/get-started/install" >&2
  exit 1
fi

flutter create --platforms=windows,linux,android --project-name etude_timer --org be.etudetimer .
# `flutter create` ajoute un test d'exemple qui ne correspond pas à cette appli : on le retire.
rm -f test/widget_test.dart
flutter pub get
# Sans cette étape, l'APK « release » n'a pas la permission INTERNET (la synchro WebDAV échouerait).
dart tool/patch_android.dart .
echo
echo "Prêt. Pour lancer en développement :  flutter run -d linux   (ou -d windows, ou un appareil Android branché : flutter run)"
