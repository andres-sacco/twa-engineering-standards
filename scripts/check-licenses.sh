#!/usr/bin/env bash
# SEC-05: licencias de las dependencias que llegan al artefacto (el SBOM de sbom.sh, sin las de test) contra la lista
# permitida (params.allowedLicenses + extraAllowedLicenses). Una dependencia con varias licencias (doble licencia,
# como logback: EPL-2.0 o LGPL-2.1) pasa si al menos una está permitida. Los grupos propios (params.ownGroups) no se
# revisan. Una excepción puntual va en params.allowedComponents (group:artifact) del .twa-standards.yml, con la razón.
# Uso: check-licenses.sh SEVERIDAD PARAMS_JSON
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

severity="$1"
params="$2"
[[ "$severity" == "off" ]] && exit 0

bom="$(reports_dir)/bom.json"
# Una licencia sin id SPDX (solo el nombre del pom) se compara por nombre; la mayoría tiene id
rejected="$(jq -c --argjson p "$params" '
  ($p."SEC-05" // {}) as $c
  | (($c.allowedLicenses // []) + ($c.extraAllowedLicenses // [])) as $allowed
  | ($c.allowedComponents // []) as $components
  | ($c.ownGroups // []) as $own
  | [.components[]?
     | select(.type == "library" or .type == null)
     | (.group // "") as $g
     | .name as $n
     | select(any($own[]; $g == . or ($g | startswith(. + "."))) | not)
     | select(any($components[]; . == "\($g):\($n)") | not)
     | {id: "\($g):\($n):\(.version)",
        licenses: [.licenses[]? | .license.id // .license.name // .expression]}
     | select(.licenses as $l | any($l[]; . as $x | $allowed | index($x)) | not)]' "$bom")"
count="$(jq 'length' <<<"$rejected")"

jq -r '.[:20][] | [.id, (if (.licenses | length) == 0 then "sin licencia declarada" else (.licenses | join(" o ")) end)] | @tsv' \
  <<<"$rejected" |
  while IFS=$'\t' read -r component licenses; do
    annotate "$severity" "SEC-05 Licencias" "${component}: ${licenses}"
  done

if ((count == 0)); then
  report SEC-05 "$severity" ok "$(jq '.components | length' "$bom") componentes con licencia permitida"
else
  report SEC-05 "$severity" fail "${count} dependencias con una licencia fuera de la lista permitida o sin licencia ($(jq -r 'map(.id) | .[:5] | join(", ")' <<<"$rejected")): ver las anotaciones"
fi
