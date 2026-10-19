#!/bin/bash
# Prepara la firma de las releases que compila GitHub Actions. Se ejecuta una sola vez.
#
#   scripts/setup-release-signing.sh
#
# Crea un certificado autofirmado de firma de código llamado "AltPlus Release",
# y lo carga como secrets del repositorio con gh. No toca el llavero ni pide contraseñas.
# Con una identidad fija, quien actualiza AltPlus no tiene que volver a conceder los permisos.
#
# El certificado queda en ~/.config/altplus/release/. Guárdalo en un lugar seguro: si se pierde,
# la siguiente versión tendrá otra identidad y los usuarios deberán conceder los permisos una vez más.
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="${ALTPLUS_RELEASE_IDENTITY:-AltPlus Release}"
STORE="${ALTPLUS_RELEASE_STORE:-$HOME/.config/altplus/release}"
REPO="${ALTPLUS_REPO:-}"

if [ -f "$STORE/signing.p12" ] && [ -f "$STORE/signing.password" ]; then
  echo "Ya existe un certificado de releases en $STORE; se reutiliza."
else
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  cat > "$TMP/cert.conf" <<CONF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:FALSE
subjectKeyIdentifier = hash
CONF
  /usr/bin/openssl req -x509 -new -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.conf" >/dev/null 2>&1
  PASSWORD="$(/usr/bin/openssl rand -hex 16)"
  # Cifrado clásico (3DES): es el que `security import` de macOS lee sin problemas.
  /usr/bin/openssl pkcs12 -export -out "$TMP/signing.p12" -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$NAME" -passout "pass:$PASSWORD" -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES
  mkdir -p "$STORE" && chmod 700 "$STORE"
  cp "$TMP/signing.p12" "$STORE/signing.p12"
  printf '%s' "$PASSWORD" > "$STORE/signing.password"
  chmod 600 "$STORE/signing.p12" "$STORE/signing.password"
  echo "Certificado \"$NAME\" creado en $STORE."
fi

if [ "${ALTPLUS_NO_UPLOAD:-0}" = "1" ]; then
  echo "ALTPLUS_NO_UPLOAD=1: no se cargan los secrets."
  exit 0
fi

[ -n "$REPO" ] || REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
# Los valores van por la entrada estándar: no quedan en la línea de comandos ni en el historial.
base64 -i "$STORE/signing.p12" | gh secret set SIGNING_P12_BASE64 --repo "$REPO"
gh secret set SIGNING_P12_PASSWORD --repo "$REPO" < "$STORE/signing.password"
printf '%s' "$NAME" | gh secret set SIGNING_IDENTITY --repo "$REPO"
echo "Secrets cargados en $REPO. Las próximas releases se firman como \"$NAME\"."
echo "Haz una copia de seguridad de $STORE."
