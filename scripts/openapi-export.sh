#!/usr/bin/env bash
# API-01: la spec OpenAPI se exporta en el build. Los servicios la generan del código (springdoc) y su OpenApiIT la
# escribe en target/openapi.json del módulo, dentro de mvn verify (docs/openapi.md). Este script la busca y la deja en
# <reportes>/specs/<módulo>.json para API-02 y API-03.
# Deja `result=ok|fail` en las salidas del step: API-02 y API-03 corren solo si hay spec.
# Uso: openapi-export.sh SEVERIDAD (en working-directory, después de mvn verify)
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

severity="$1"
specs="$(reports_dir)/specs"
mkdir -p "$specs"

found=()
invalid=()
while IFS= read -r spec; do
  module="$(basename "$(cd "$(dirname "$spec")/.." && pwd)")"
  if jq -e '.openapi | strings' "$spec" >/dev/null 2>&1; then
    cp "$spec" "${specs}/${module}.json"
    found+=("$module")
  else
    invalid+=("$spec")
  fi
done < <(find . -path '*/target/openapi.json' -not -path '*/node_modules/*' | sort)

if ((${#found[@]} > 0)); then
  set_output result ok
  detail="Spec de ${found[*]}"
  ((${#invalid[@]} == 0)) || detail="${detail}; no son una spec OpenAPI: ${invalid[*]}"
  [[ "$severity" == "off" ]] || report API-01 "$severity" ok "$detail"
else
  set_output result fail
  if ((${#invalid[@]} > 0)); then
    detail="${invalid[*]} no es una spec OpenAPI (falta el campo openapi)"
  else
    detail="Ningún módulo dejó target/openapi.json: el OpenApiIT tiene que escribir la respuesta de /v3/api-docs (docs/openapi.md)"
  fi
  [[ "$severity" == "off" ]] || report API-01 "$severity" fail "$detail"
fi
