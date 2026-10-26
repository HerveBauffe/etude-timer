#!/usr/bin/env bash
# Build Linux release + archive tar.gz + taille mesurée.
# Prérequis (Debian/Ubuntu) : sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev
set -euo pipefail
cd "$(dirname "$0")/.."

flutter build linux --release --split-debug-info=build/debug-info

REL=build/linux/x64/release/bundle
[ -d "$REL" ] || { echo "Dossier de build introuvable : $REL" >&2; exit 1; }

mkdir -p dist
tar -C "$REL" -czf dist/EtudeTimer-linux-x64.tar.gz .

echo
echo "Dossier de build (décompressé) : $(du -sh "$REL" | cut -f1)"
echo "Archive tar.gz                 : $(du -h dist/EtudeTimer-linux-x64.tar.gz | cut -f1)"
echo
echo "Mode portable : crée un dossier « EtudeTimerData » à côté de l'exécutable 'etude_timer'."
