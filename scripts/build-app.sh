#!/bin/bash
# Compila AltPlus y arma build/AltPlus.app listo para abrir.
#
#   scripts/build-app.sh                                   # release, arquitectura nativa, firma ad hoc
#   ALTPLUS_UNIVERSAL=1 scripts/build-app.sh               # binario universal (arm64 + x86_64)
#   ALTPLUS_SIGN_IDENTITY="AltPlus Dev" scripts/build-app.sh
#
# Sobre la firma: macOS ata el permiso de Accesibilidad a la firma del binario. Con firma ad hoc ("-")
# cada compilación es "otra app" y hay que volver a conceder el permiso. Para desarrollar cómodo,
# crea una vez un certificado autofirmado con scripts/make-dev-cert.sh y pásalo en ALTPLUS_SIGN_IDENTITY.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${ALTPLUS_CONFIG:-release}"
IDENTITY="${ALTPLUS_SIGN_IDENTITY:--}"
APP="build/AltPlus.app"
mkdir -p build

if [ "${ALTPLUS_UNIVERSAL:-0}" = "1" ]; then
  # Dos compilaciones por triple y lipo: funciona con Command Line Tools, sin Xcode.
  swift build -c "$CONFIG" --triple arm64-apple-macosx
  swift build -c "$CONFIG" --triple x86_64-apple-macosx
  lipo -create -output build/AltPlus-universal \
    ".build/arm64-apple-macosx/$CONFIG/AltPlus" ".build/x86_64-apple-macosx/$CONFIG/AltPlus"
  BIN=build/AltPlus-universal
else
  swift build -c "$CONFIG"
  BIN=".build/$CONFIG/AltPlus"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/AltPlus"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ícono: se genera una vez y se cachea en build/.
if [ ! -f build/AppIcon.icns ]; then
  if swift scripts/make-icon.swift build/AppIcon.png >/dev/null 2>&1; then
    rm -rf build/AppIcon.iconset && mkdir -p build/AppIcon.iconset
    for s in 16 32 128 256 512; do
      sips -z $s $s build/AppIcon.png --out "build/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
      d=$((s * 2))
      sips -z $d $d build/AppIcon.png --out "build/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
    rm -rf build/AppIcon.iconset
  else
    echo "Aviso: no se pudo generar el ícono; la app sale sin ícono." >&2
  fi
fi
[ -f build/AppIcon.icns ] && cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign "$IDENTITY" --identifier org.altplus.AltPlus "$APP"
echo "Listo: $APP (firma: $IDENTITY, arquitecturas: $(lipo -archs "$APP/Contents/MacOS/AltPlus"))"
