#!/bin/bash
# Publica una versión: actualiza Info.plist, commitea, etiqueta y empuja.
# GitHub Actions compila, empaqueta, crea la release y actualiza el cask de Homebrew.
#
#   scripts/release.sh 0.1.0
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?Uso: scripts/release.sh X.Y.Z}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Versión inválida: $VERSION" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "Hay cambios sin commitear. Commitea o descarta antes de publicar." >&2; exit 1; }
git rev-parse "v$VERSION" >/dev/null 2>&1 && { echo "La etiqueta v$VERSION ya existe." >&2; exit 1; }

PLIST=Resources/Info.plist
BUILD=$(( $(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST") + 1 ))
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$PLIST"

git add "$PLIST"
git commit -q -m "Versión $VERSION"
git tag -a "v$VERSION" -m "AltPlus $VERSION"
git push origin HEAD
git push origin "v$VERSION"
echo "Etiqueta v$VERSION enviada. Sigue el progreso en: gh run watch"
