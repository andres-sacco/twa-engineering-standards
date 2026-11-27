#!/usr/bin/env bash
# ARC-01: las reglas de arquitectura de twa-layered-rules / twa-hexagonal-rules corrieron con los tests y pasaron. No
# las vuelve a correr: lee los reportes de Surefire y Failsafe que deja `mvn verify` (BLD-02). Cada caso de ArchUnit
# se llama "<Clase de reglas> > … > LAY_01": el id de la regla sale del nombre.
# Uso: check-architecture.sh SEVERIDAD RESULTADO_DE_BLD02 (en el directorio del pom)
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

severity="$1" verify_result="$2"
[[ "$severity" == "off" ]] && exit 0

mapfile -t reports < <(find . \( -path '*/target/surefire-reports/TEST-*.xml' -o -path '*/target/failsafe-reports/TEST-*.xml' \) \
  -not -path './.git/*' | sort)

# Una línea por regla que corrió: "ID ok|fail módulo"
rules="$(
  for r in "${reports[@]}"; do
    module="$(sed -E 's#^\./##; s#/?target/(surefire|failsafe)-reports/.*##' <<<"$r")"
    module="${module:-$(basename "$PWD")}"
    yq -p=xml -o=json -I=0 '[.testsuite.testcase] | flatten | .[]' "$r" 2>/dev/null |
      jq -r --arg m "$module" '
        select(."+@name" | test(" > .*[A-Z]{3}_[0-9]{2}$"))
        | [(."+@name" | capture("(?<id>[A-Z]{3}_[0-9]{2})$").id | sub("_"; "-")),
           (if (has("failure") or has("error")) then "fail" else "ok" end), $m] | join(" ")'
  done
)"

# Violaciones congeladas (FreezingArchRule): no fallan, pero son deuda
frozen=0
while read -r store; do
  [[ -z "$store" ]] && continue
  n="$(find "$store" -type f ! -name stored.rules -exec cat {} + 2>/dev/null | grep -c . || true)"
  frozen=$((frozen + n))
done < <(find . -type d -name archunit_store -path '*/src/test/resources/*' -not -path '*/target/*')
frozen_detail=""
((frozen > 0)) && frozen_detail=" ${frozen} violaciones congeladas en archunit_store."

if [[ -z "$rules" ]]; then
  if [[ "$verify_result" != "ok" ]]; then
    report ARC-01 "$severity" skip "El build falló antes de poder leer los resultados de las reglas (ver BLD-02)"
  else
    report ARC-01 "$severity" fail "No corrió ninguna regla de arquitectura: falta el ArchitectureTest, la dependencia de la librería o se salteó el perfil architecture-rules (-DskipArchitectureRules)"
  fi
  exit $?
fi

total="$(wc -l <<<"$rules")"
modules="$(awk '{print $3}' <<<"$rules" | sort -u | paste -sd, - | sed 's/,/, /g')"
failed="$(awk '$2 == "fail" {print $1 " (" $3 ")"}' <<<"$rules" | sort -u | paste -sd, - | sed 's/,/, /g')"
if [[ -z "$failed" ]]; then
  report ARC-01 "$severity" ok "${total} reglas en ${modules}.${frozen_detail}"
else
  report ARC-01 "$severity" fail "Rompen ${failed}: ver la regla en docs/architecture-rules.md de la librería.${frozen_detail}"
fi
