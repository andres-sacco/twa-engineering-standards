#!/usr/bin/env bash
# settings.xml con las credenciales de GitHub Packages para las librerías TWA, a partir de PACKAGES_USER y
# PACKAGES_TOKEN. Los ids son los de los <repository> de los poms. Sin token, un settings.xml vacío: el build solo
# puede bajar dependencias públicas.
set -euo pipefail

SERVERS=(github-twa-layered-rules github-twa-hexagonal-rules github-twa-flights-provider-contract)

echo "<settings>"
if [[ -n "${PACKAGES_TOKEN:-}" ]]; then
  echo "  <servers>"
  for id in "${SERVERS[@]}"; do
    cat <<XML
    <server>
      <id>${id}</id>
      <username>${PACKAGES_USER:?falta PACKAGES_USER}</username>
      <password>${PACKAGES_TOKEN}</password>
    </server>
XML
  done
  echo "  </servers>"
else
  echo "::warning::Sin PACKAGES_TOKEN: no se pueden bajar las librerías TWA de GitHub Packages" >&2
fi
echo "</settings>"
