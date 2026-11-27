#!/usr/bin/env bash
# API-03: sin cambios incompatibles en la spec contra la de la rama principal (oasdiff breaking, nivel ERR: sacar un
# endpoint o un campo de la respuesta, volver obligatorio un parámetro, cambiar un tipo…). La spec de la rama principal
# la guarda java-ci.yml en la cache de Actions en cada push a esa rama, como la cobertura de TST-02.
# Un cambio incompatible a propósito se aprueba con la etiqueta `api-breaking-change` en el PR: el control pasa y lo
# informa. Los consumidores se avisan aparte (skill impact de twa-dev-flow).
# Uso: check-openapi-breaking.sh SEVERIDAD DIRECTORIO_BASE APROBADO(true|false)
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

join_details() {
  local IFS=";" joined
  joined="${details[*]}"
  echo "${joined//;/; }"
}

severity="$1"
baseline="$2"
approved="${3:-false}"
[[ "$severity" == "off" ]] && exit 0

reports="$(reports_dir)"
image="tufin/oasdiff:${OASDIFF_VERSION}"
total=0
compared=()
details=()
for spec in "${reports}"/specs/*.json; do
  name="$(basename "$spec" .json)"
  [[ -f "${baseline}/${name}.json" ]] || continue
  compared+=("$name")
  docker run --rm -v "${baseline}:/base:ro" -v "${reports}/specs:/revision:ro" "$image" \
    breaking "/base/${name}.json" "/revision/${name}.json" --format json >"${reports}/oasdiff-${name}.json"
  count="$(jq '[.[]? | select(.level == 3)] | length' "${reports}/oasdiff-${name}.json")"
  total=$((total + count))
  ((count == 0)) || details+=("${name}: $(jq -r '[.[] | select(.level == 3) | .id] | unique | join(", ")' "${reports}/oasdiff-${name}.json")")
  jq -r '[.[]? | select(.level == 3)] | .[:20][] | [.id, .text, .operation, .path] | @tsv' "${reports}/oasdiff-${name}.json" |
    while IFS=$'\t' read -r id text operation path; do
      if [[ "$approved" == "true" ]]; then
        annotate warn "API-03 ${id}" "${name} ${operation} ${path}: ${text} (aprobado)"
      else
        annotate "$severity" "API-03 ${id}" "${name} ${operation} ${path}: ${text}"
      fi
    done
done

if ((${#compared[@]} == 0)); then
  report API-03 "$severity" ok "Sin spec de la rama principal para comparar (se guarda en el primer push a esa rama)"
elif ((total == 0)); then
  report API-03 "$severity" ok "Sin cambios incompatibles contra la rama principal (${compared[*]})"
elif [[ "$approved" == "true" ]]; then
  report API-03 "$severity" ok "${total} cambios incompatibles aprobados con la etiqueta api-breaking-change: $(join_details)"
else
  report API-03 "$severity" fail "${total} cambios incompatibles contra la rama principal ($(join_details)): si son a propósito, etiqueta api-breaking-change en el PR y avisar a los consumidores"
fi
