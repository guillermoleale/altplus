#!/bin/bash
# Instala la última versión de AltPlus desde GitHub Releases en /Applications.
#
#   curl -fsSL https://raw.githubusercontent.com/guillermoleale/altplus/main/install.sh | bash
#
# Qué hace: descarga el zip de la última release, verifica su SHA-256, lo copia a /Applications
# (o a ~/Applications si no hay permiso), le quita la cuarentena para que Gatekeeper no lo bloquee
# y lo abre. No pide contraseña.
set -euo pipefail

REPO="${ALTPLUS_REPO:-guillermoleale/altplus}"
DEST="${ALTPLUS_DEST:-/Applications}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [ -n "${ALTPLUS_LOCAL_ZIP:-}" ]; then
  ZIP="$TMP/$(basename "$ALTPLUS_LOCAL_ZIP")"
  cp "$ALTPLUS_LOCAL_ZIP" "$ZIP"
else
  echo "Buscando la última versión de $REPO…"
  RELEASE="$(curl -fsSL -H "Accept: application/vnd.github+json" "https://api.github.com/repos/$REPO/releases/latest")"
  # `|| true`: con pipefail, un grep sin coincidencias cortaría el script sin ningún mensaje.
  URL="$(printf '%s' "$RELEASE" | grep -o '"browser_download_url": *"[^"]*/AltPlus-[^"/]*\.zip"' | head -1 | sed 's/.*"\(https[^"]*\)"$/\1/' || true)"
  SUMS_URL="$(printf '%s' "$RELEASE" | grep -o '"browser_download_url": *"[^"]*/SHA256SUMS\.txt"' | head -1 | sed 's/.*"\(https[^"]*\)"$/\1/' || true)"
  [ -n "$URL" ] || { echo "No encontré un AltPlus-*.zip en la última release de $REPO." >&2; exit 1; }
  ZIP="$TMP/$(basename "$URL")"
  echo "Descargando $(basename "$URL")…"
  curl -fL --progress-bar "$URL" -o "$ZIP"
  if [ -n "$SUMS_URL" ]; then
    curl -fsSL "$SUMS_URL" -o "$TMP/SHA256SUMS.txt"
    EXPECTED="$(grep " $(basename "$ZIP")\$" "$TMP/SHA256SUMS.txt" | cut -d' ' -f1 || true)"
    ACTUAL="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
    if [ -z "$EXPECTED" ]; then
      echo "Aviso: SHA256SUMS.txt no incluye $(basename "$ZIP"); no se pudo verificar la descarga." >&2
    elif [ "$EXPECTED" != "$ACTUAL" ]; then
      echo "La suma SHA-256 no coincide. Descarga corrupta o manipulada; no se instala." >&2
      exit 1
    else
      echo "SHA-256 verificada."
    fi
  else
    echo "Aviso: la release no publica SHA256SUMS.txt; no se pudo verificar la descarga." >&2
  fi
fi

ditto -x -k "$ZIP" "$TMP/unzipped"
[ -d "$TMP/unzipped/AltPlus.app" ] || { echo "El zip no contiene AltPlus.app." >&2; exit 1; }

if [ ! -w "$DEST" ]; then
  DEST="$HOME/Applications"
  mkdir -p "$DEST"
fi

if [ "${ALTPLUS_NO_LAUNCH:-0}" != "1" ]; then
  pkill -x AltPlus 2>/dev/null || true
  sleep 0.5
fi
rm -rf "$DEST/AltPlus.app"
ditto "$TMP/unzipped/AltPlus.app" "$DEST/AltPlus.app"
xattr -dr com.apple.quarantine "$DEST/AltPlus.app" 2>/dev/null || true
echo "AltPlus instalado en $DEST/AltPlus.app"

if [ "${ALTPLUS_NO_LAUNCH:-0}" != "1" ]; then
  open -a "$DEST/AltPlus.app"
  echo
  echo "Si es la primera vez: activa AltPlus en Ajustes del Sistema › Privacidad y seguridad › Accesibilidad."
  echo "Atajos: ⌥⇥ ventanas de este escritorio · ⌥⌃⇥ ventanas de todos los escritorios."
fi
