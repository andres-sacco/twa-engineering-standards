#!/usr/bin/env bash
# ARC-02: el servicio usa la librería de reglas de su arquitectura (twa-layered-rules o twa-hexagonal-rules) en una
# versión mayor o igual a la mínima (params.minVersions de ARC-02 en config/controls.yml). Lee el pom efectivo: no
# hace falta compilar.
# Uso: check-architecture-version.sh SEVERIDAD ARQUITECTURA PARAMS_JSON [args de Maven…] (en el directorio del pom)
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

severity="$1" architecture="$2" params="$3"
shift 3
[[ "$severity" == "off" ]] && exit 0

case "$architecture" in
  layered) library=twa-layered-rules ;;
  hexagonal) library=twa-hexagonal-rules ;;
  *) echo "::error::Arquitectura desconocida: ${architecture}"; exit 1 ;;
esac
min="$(jq -er --arg l "$library" '."ARC-02".minVersions[$l]' <<<"$params")" ||
  { echo "::error::Falta ARC-02.minVersions.${library} en los params"; exit 1; }

effective_pom="$(mktemp)"
trap 'rm -f "$effective_pom"' EXIT
if ! mvn -B -ntp -q help:effective-pom -Doutput="$effective_pom" "$@" >/dev/null 2>&1; then
  report ARC-02 "$severity" fail "No se pudo armar el pom efectivo (mvn help:effective-pom)"
  exit $?
fi

# La versión que sigue a cada <artifactId> de la librería (en un multi-módulo aparece una vez por módulo)
mapfile -t versions < <(grep -A1 "<artifactId>${library}</artifactId>" "$effective_pom" |
  grep -oE '<version>[^<]+' | sed 's/<version>//' | sort -uV)

if ((${#versions[@]} == 0)); then
  report ARC-02 "$severity" fail "El pom no declara ${library} (arquitectura ${architecture}): ver el README de la librería"
  exit $?
fi
lowest="${versions[0]}"
if [[ "$(printf '%s\n%s\n' "$min" "$lowest" | sort -V | head -1)" == "$min" ]]; then
  report ARC-02 "$severity" ok "${library} ${versions[*]} (mínima ${min})"
else
  report ARC-02 "$severity" fail "${library} ${lowest} es menor que la mínima ${min}: subí la versión en el pom"
fi
