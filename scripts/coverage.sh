#!/usr/bin/env bash
# TST-01 y TST-02: cobertura de líneas de todos los módulos (suma de los target/site/jacoco/jacoco.csv que deja
# `jacoco:report`, con los tests unitarios y de integración juntos).
# Uso: coverage.sh SEVERIDAD_TST01 SEVERIDAD_TST02 PARAMS_JSON BASELINE_JSON SALIDA_JSON (en el directorio del pom)
#   PARAMS_JSON: los params que deja read-config.sh, con los defaults del catálogo
#   ({"TST-01": {"minLineCoverage": 60}, "TST-02": {"maxDrop": 0.5}})
#   BASELINE_JSON: la cobertura de la rama principal (puede no existir); SALIDA_JSON: la de este build
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

sev_min="$1" sev_drop="$2" params="$3" baseline="$4" output="$5"
[[ "$sev_min" == "off" && "$sev_drop" == "off" ]] && exit 0

min="$(jq -er '."TST-01".minLineCoverage' <<<"$params")" || { echo "::error::Falta TST-01.minLineCoverage en los params"; exit 1; }
max_drop="$(jq -er '."TST-02".maxDrop' <<<"$params")" || { echo "::error::Falta TST-02.maxDrop en los params"; exit 1; }

mapfile -t reports < <(find . -path '*/target/site/jacoco/jacoco.csv' -not -path './.git/*' | sort)
if ((${#reports[@]} == 0)); then
  report TST-01 "$sev_min" fail "No hay reportes de JaCoCo (target/site/jacoco/jacoco.csv): ¿corrieron los tests?"
  exit $?
fi

# Columnas de jacoco.csv: … LINE_MISSED (8), LINE_COVERED (9) …
read -r missed covered < <(awk -F, 'FNR > 1 { m += $8; c += $9 } END { print m + 0, c + 0 }' "${reports[@]}")
total=$((missed + covered))
pct="$(awk -v c="$covered" -v t="$total" 'BEGIN { printf "%.2f", (t == 0 ? 0 : 100 * c / t) }')"

modules='[]'
for r in "${reports[@]}"; do
  read -r m c < <(awk -F, 'FNR > 1 { m += $8; c += $9 } END { print m + 0, c + 0 }' "$r")
  module="$(sed -E 's#^\./##; s#/?target/site/jacoco/jacoco.csv$##' <<<"$r")"
  modules="$(jq -c --arg n "${module:-$(basename "$PWD")}" --argjson m "$m" --argjson c "$c" '. + [{module: $n, missed: $m, covered: $c}]' <<<"$modules")"
done
jq -n --argjson pct "$pct" --argjson m "$missed" --argjson c "$covered" --argjson mods "$modules" \
  '{line: $pct, missed: $m, covered: $c, modules: $mods}' >"$output"
echo "Cobertura de líneas: ${pct}% (${covered}/${total})"

status=0
if [[ "$sev_min" != "off" ]]; then
  if awk -v p="$pct" -v m="$min" 'BEGIN { exit !(p >= m) }'; then
    report TST-01 "$sev_min" ok "${pct}% (mínimo ${min}%)" || status=1
  else
    report TST-01 "$sev_min" fail "${pct}% de líneas cubiertas, el mínimo es ${min}%" || status=1
  fi
fi

if [[ "$sev_drop" != "off" ]]; then
  if [[ ! -s "$baseline" ]]; then
    report TST-02 "$sev_drop" ok "Sin cobertura de la rama principal para comparar (se guarda al mergear)" || status=1
  else
    base="$(jq -r '.line' "$baseline")"
    drop="$(awk -v b="$base" -v p="$pct" 'BEGIN { printf "%.2f", b - p }')"
    if awk -v d="$drop" -v m="$max_drop" 'BEGIN { exit !(d <= m) }'; then
      report TST-02 "$sev_drop" ok "${pct}% contra ${base}% de la rama principal" || status=1
    else
      report TST-02 "$sev_drop" fail "Baja ${drop} puntos: ${pct}% contra ${base}% de la rama principal (tolerancia ${max_drop})" || status=1
    fi
  fi
fi
exit "$status"
