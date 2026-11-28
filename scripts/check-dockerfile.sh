#!/usr/bin/env bash
# DKR-02: buenas prácticas del Dockerfile con Hadolint (incluye shellcheck sobre los RUN). Cuentan los hallazgos de
# nivel error y warning; info y style quedan en el reporte.
# Un falso positivo se suprime en el Dockerfile, en la línea anterior a la instrucción, con la razón:
#   # hadolint ignore=DL3008 (la razón)
# Uso: check-dockerfile.sh SEVERIDAD DOCKERFILE (en working-directory)
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

severity="$1"
dockerfile="$2"
[[ "$severity" == "off" ]] && exit 0

reports="$(reports_dir)"
if [[ ! -f "$dockerfile" ]]; then
  report DKR-02 "$severity" fail "No existe ${dockerfile}: si el servicio no tiene imagen, apagar los DKR-* con la razón"
  exit $?
fi

hadolint() {
  docker run --rm -i "hadolint/hadolint:${HADOLINT_VERSION}" hadolint --no-fail "$@" - <"$dockerfile"
}
if ! hadolint -f json >"${reports}/hadolint.json"; then
  report DKR-02 "$severity" fail "Hadolint no pudo correr: ver el log de este step"
  exit $?
fi
hadolint -f sarif >"${reports}/hadolint.sarif" || true

findings='[.[] | select(.level == "error" or .level == "warning")]'
count="$(jq "${findings} | length" "${reports}/hadolint.json")"
jq -r "${findings} | .[:20][] | [.code, .line, .message] | @tsv" "${reports}/hadolint.json" |
  while IFS=$'\t' read -r code line message; do
    annotate "$severity" "DKR-02 ${code}" "${message} (https://github.com/hadolint/hadolint/wiki/${code})" "$dockerfile" "$line"
  done

if ((count == 0)); then
  report DKR-02 "$severity" ok "Hadolint: sin errores ni warnings ($(jq 'length' "${reports}/hadolint.json") info/style)"
else
  report DKR-02 "$severity" fail "Hadolint encontró ${count} ($(jq -r "${findings} | map(.code) | unique | join(\", \")" "${reports}/hadolint.json")): ver las anotaciones"
fi
