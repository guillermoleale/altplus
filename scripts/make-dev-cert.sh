#!/bin/bash
# Crea un certificado autofirmado de firma de código para desarrollar AltPlus con identidad estable.
#
# macOS ata el permiso de Accesibilidad a la firma del binario. Con firma ad hoc cada compilación
# es "otra app" y el permiso se pierde. Firmando con este certificado, el permiso sobrevive.
#
#   scripts/make-dev-cert.sh            # crea "AltPlus Dev" en el llavero de inicio de sesión
#   ALTPLUS_SIGN_IDENTITY="AltPlus Dev" scripts/build-app.sh
#
# Ejecutarlo en una terminal propia: macOS puede pedir la contraseña del llavero y, en el primer
# codesign, mostrar un diálogo "codesign quiere acceder a la clave"; elegir "Permitir siempre".
#
# Guarda además una copia del certificado en ~/.config/altplus/ para cargarlo en los secrets de
# GitHub y que las releases se firmen con la misma identidad (el permiso de Accesibilidad sobrevive
# a las actualizaciones). El mismo certificado sirve para desarrollar y para publicar.
set -euo pipefail

NAME="${1:-AltPlus Dev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
STORE="$HOME/.config/altplus"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
  if [ -f "$STORE/signing.p12" ]; then
    echo "Ya existe la identidad \"$NAME\" y su copia en $STORE. Nada que hacer."
    exit 0
  fi
  # La identidad existe pero no hay copia para GitHub. `security export -t identities` exportaría
  # TODAS las identidades del llavero (claves privadas ajenas a AltPlus incluidas) y terminarían en los
  # secrets de GitHub, así que la copia de esta sola identidad se hace a mano.
  mkdir -p "$STORE" && chmod 700 "$STORE"
  cat >&2 <<MSG
La identidad "$NAME" ya existe, pero no hay copia en $STORE para los secrets de GitHub.

Expórtala sola desde Acceso a Llaveros: en "Mis certificados", clic derecho sobre "$NAME" › Exportar,
formato Intercambio de información personal (.p12), guárdala como $STORE/signing.p12 y escribe la
contraseña que elijas en $STORE/signing.password. Después:

  chmod 600 $STORE/signing.p12 $STORE/signing.password
  gh secret set SIGNING_P12_BASE64 --body "\$(base64 -i $STORE/signing.p12)"
  gh secret set SIGNING_P12_PASSWORD --body "\$(cat $STORE/signing.password)"
MSG
  exit 1
fi

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

openssl req -x509 -new -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.conf" >/dev/null 2>&1
P12_PASSWORD="$(openssl rand -hex 16)"
openssl pkcs12 -export -out "$TMP/dev.p12" -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
  -passout "pass:$P12_PASSWORD" -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1

mkdir -p "$STORE" && chmod 700 "$STORE"
cp "$TMP/dev.p12" "$STORE/signing.p12"
printf '%s\n' "$P12_PASSWORD" > "$STORE/signing.password"
chmod 600 "$STORE/signing.p12" "$STORE/signing.password"

security import "$TMP/dev.p12" -k "$KEYCHAIN" -P "$P12_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security >/dev/null
# Confiar en el certificado para firma de código (dominio del usuario; puede pedir autorización).
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"
# Permitir que codesign use esta clave (solo esta, por etiqueta) sin preguntar cada vez.
# `security` pide la contraseña del llavero de forma interactiva; no pasa por la línea de comandos.
echo "A continuación, la contraseña del llavero de inicio de sesión (la de tu usuario):"
security set-key-partition-list -S "apple-tool:,apple:,codesign:" -s -l "$NAME" "$KEYCHAIN" >/dev/null
echo
security find-identity -v -p codesigning | grep "\"$NAME\""
cat <<MSG

Listo. Compila con:  ALTPLUS_SIGN_IDENTITY="$NAME" scripts/build-app.sh

Para que GitHub Actions firme las releases con esta misma identidad, carga dos secrets en el repo
(Settings › Secrets and variables › Actions, o con gh):

  gh secret set SIGNING_P12_BASE64 --body "\$(base64 -i $STORE/signing.p12)"
  gh secret set SIGNING_P12_PASSWORD --body "\$(cat $STORE/signing.password)"

Guarda $STORE en un lugar seguro: si lo pierdes, las versiones futuras tendrán otra identidad
y los usuarios tendrán que volver a conceder el permiso de Accesibilidad una vez.
MSG
