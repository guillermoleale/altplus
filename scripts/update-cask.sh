#!/bin/bash
# Actualiza Casks/altplus.rb con la versión y el sha256 del zip publicado.
#   scripts/update-cask.sh 0.1.0 <sha256>
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?versión}"
SHA="${2:?sha256}"
sed -i '' \
  -e "s/^  version \".*\"/  version \"$VERSION\"/" \
  -e "s/^  sha256 .*/  sha256 \"$SHA\"/" \
  Casks/altplus.rb
grep -E "^  (version|sha256)" Casks/altplus.rb
