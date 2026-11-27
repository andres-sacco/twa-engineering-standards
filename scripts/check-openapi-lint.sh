#!/usr/bin/env bash
# API-02: la spec cumple las convenciones de las APIs TWA, con Spectral y el ruleset de este repo
# (config/spectral/twa.yaml: las reglas twa-* y las recomendadas de Spectral para OpenAPI). Falla con los hallazgos de
# severidad error; los warn e info quedan como anotación y en el artifact.
# Un repo puede apagar una regla en params.disabledRules de API-02, con la razón en un comentario de su
# .twa-standards.yml.
# Uso: check-openapi-lint.sh SEVERIDAD PARAMS_JSON (las specs las dejó openapi-export.sh en <reportes>/specs)
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

join_details() {
  local IFS=";" joined
  joined="${details[*]}"
  echo "${joined//;/; }"
}

severity="$1"
params="$2"
[[ "$severity" == "off" ]] && exit 0

reports="$(reports_dir)"
ruleset="${reports}/spectral.yaml"
# Un ruleset que extiende el de este repo, con las reglas que el repo apaga
{
  echo "extends: [\"${STANDARDS_DIR}/config/spectral/twa.yaml\"]"
  echo "rules:"
  jq -r '."API-02".disabledRules // [] | .[] | "  \(.): \"off\""' <<<"$params"
} >"$ruleset"
grep -q '^  ' "$ruleset" || sed -i 's/^rules:$/rules: {}/' "$ruleset"

errors=0
warnings=0
details=()
for spec in "${reports}"/specs/*.json; do
  name="$(basename "$spec" .json)"
  # Sale con 1 si hay errores; el resultado se lee del JSON
  npx --yes --quiet --package "@stoplight/spectral-cli@${SPECTRAL_VERSION}" -- spectral lint "$spec" \
    --ruleset "$ruleset" --fail-severity error --quiet \
    -f json -o.json "${reports}/spectral-${name}.json" -f sarif -o.sarif "${reports}/spectral-${name}.sarif" || true
  if [[ ! -s "${reports}/spectral-${name}.json" ]]; then
    report API-02 "$severity" fail "Spectral no pudo correr sobre la spec de ${name}: ver el log de este step"
    exit $?
  fi
  e="$(jq '[.[] | select(.severity == 0)] | length' "${reports}/spectral-${name}.json")"
  w="$(jq '[.[] | select(.severity == 1)] | length' "${reports}/spectral-${name}.json")"
  errors=$((errors + e))
  warnings=$((warnings + w))
  ((e == 0)) || details+=("${name}: $(jq -r '[.[] | select(.severity == 0) | .code] | group_by(.) | map("\(.[0]) (\(length))") | join(", ")' "${reports}/spectral-${name}.json")")
  # Primero los errores; una anotación por regla y lugar
  jq -r '[.[] | select(.severity <= 1)] | sort_by(.severity) | .[:20][]
      | [.severity, .code, .message, (.path | join("."))] | @tsv' "${reports}/spectral-${name}.json" |
    while IFS=$'\t' read -r level code message path; do
      if ((level == 0)); then
        annotate "$severity" "API-02 ${code}" "${name}: ${message} (${path})"
      else
        annotate warn "API-02 ${code}" "${name}: ${message} (${path})"
      fi
    done
done

if ((errors == 0)); then
  report API-02 "$severity" ok "Sin errores de Spectral (${warnings} avisos: ver las anotaciones)"
else
  report API-02 "$severity" fail "${errors} errores de Spectral ($(join_details)): ver las anotaciones y docs/openapi.md"
fi
