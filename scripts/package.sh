#!/bin/bash
# Empaqueta build/AltPlus.app para distribuir: zip, dmg con enlace a Aplicaciones y sumas SHA-256.
# Deja todo en build/dist/. Primero hay que correr scripts/build-app.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/AltPlus.app"
[ -d "$APP" ] || { echo "No existe $APP. Corre primero scripts/build-app.sh" >&2; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
DIST="build/dist"
rm -rf "$DIST" && mkdir -p "$DIST"

# Zip: ditto conserva la firma y los atributos del bundle.
ditto -c -k --keepParent "$APP" "$DIST/AltPlus-$VERSION.zip"

# DMG: la app más un enlace a /Applications para arrastrar.
STAGE="build/dmg-stage"
rm -rf "$STAGE" && mkdir -p "$STAGE"
ditto "$APP" "$STAGE/AltPlus.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "AltPlus $VERSION" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DIST/AltPlus-$VERSION.dmg"
rm -rf "$STAGE"

(cd "$DIST" && shasum -a 256 "AltPlus-$VERSION.zip" "AltPlus-$VERSION.dmg" > SHA256SUMS.txt)
echo "Paquetes en $DIST:"
ls -la "$DIST"
