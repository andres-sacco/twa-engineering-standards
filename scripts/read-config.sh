#!/usr/bin/env bash
# Lee el .twa-standards.yml del repo, lo valida contra el schema y lo combina con los defaults de config/controls.yml.
# Uso: read-config.sh [archivo] (por defecto .twa-standards.yml). Salidas del step:
#   type          service | library
#   architecture  layered | hexagonal (default layered; solo cuenta en servicios)
#   java          versión de Java (default 25)
#   severities  JSON {"BLD-01": "block", …} con todos los controles; off si no aplican al tipo de repo
#   params      JSON {"TST-01": {"minLineCoverage": 60}, …}: los params del catálogo con los del repo encima
# Falla si el archivo no cumple el schema o si baja la severidad de un control sin `reason`.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CONFIG="${1:-.twa-standards.yml}"
SCHEMA="${STANDARDS_DIR}/schema/twa-standards.schema.json"
DEFAULT_JAVA="25"

if [[ ! -f "$CONFIG" ]]; then
  echo "::error file=${CONFIG}::Falta ${CONFIG}: cada repo declara al menos 'version: 1' y 'type' (ver el README de twa-engineering-standards)"
  exit 1
fi
if ! pytool "check-jsonschema==${CHECK_JSONSCHEMA_VERSION}" check-jsonschema --schemafile "$SCHEMA" "$CONFIG"; then
  echo "::error file=${CONFIG}::${CONFIG} no cumple el schema de twa-engineering-standards"
  exit 1
fi

rank() {
  case "$1" in off) echo 0 ;; warn) echo 1 ;; block) echo 2 ;; esac
}

type="$(yq '.type' "$CONFIG")"
implemented_stage="$(yq '.implementedStage' "$CATALOG")"
java="$(yq ".java // \"${DEFAULT_JAVA}\"" "$CONFIG")"
architecture="$(yq '.architecture // "layered"' "$CONFIG")"
severities='{}'
errors=0

summary "### Configuración de twa-engineering-standards (\`${CONFIG}\`)"
summary ""
if [[ "$type" == "service" ]]; then
  summary "Tipo \`${type}\` (arquitectura \`${architecture}\`), Java ${java}."
else
  summary "Tipo \`${type}\`, Java ${java}."
fi
summary ""
summary "| Control | Default | Este repo | Razón |"
summary "|---|---|---|---|"

while read -r id; do
  default="$(yq ".controls.\"${id}\".severity" "$CATALOG")"
  if ! yq ".controls.\"${id}\".appliesTo[]" "$CATALOG" | grep -qx "$type"; then
    severities="$(jq -c --arg id "$id" '. + {($id): "off"}' <<<"$severities")"
    continue
  fi
  override="$(yq ".controls.\"${id}\".severity // \"\"" "$CONFIG")"
  reason="$(yq ".controls.\"${id}\".reason // \"\"" "$CONFIG")"
  effective="${override:-$default}"
  if [[ -n "$override" && "$(rank "$override")" -lt "$(rank "$default")" && -z "$reason" ]]; then
    echo "::error file=${CONFIG}::${id}: bajar la severidad de ${default} a ${override} necesita 'reason'"
    errors=$((errors + 1))
  fi
  severities="$(jq -c --arg id "$id" --arg s "$effective" '. + {($id): $s}' <<<"$severities")"
  name="$(control_name "$id")"
  if (($(yq ".controls.\"${id}\".stage" "$CATALOG") > implemented_stage)); then
    name="${name} _(todavía no corre)_"
  fi
  if [[ -n "$override" && "$override" != "$default" ]]; then
    summary "| \`${id}\` ${name} | ${default} | **${effective}** | ${reason} |"
  else
    summary "| \`${id}\` ${name} | ${default} | ${effective} | |"
  fi
done < <(yq '.controls | keys | .[]' "$CATALOG")

# Un id que no está en el catálogo es un error de tipeo o un control eliminado
while read -r id; do
  [[ -z "$id" ]] && continue
  if [[ "$(yq ".controls | has(\"${id}\")" "$CATALOG")" != "true" ]]; then
    echo "::error file=${CONFIG}::${id} no es un control del catálogo (config/controls.yml)"
    errors=$((errors + 1))
  fi
done < <(yq '.controls // {} | keys | .[]' "$CONFIG")

((errors == 0)) || exit 1

# Los params del catálogo, con los del repo combinados encima (un mapa se combina clave a clave)
defaults="$(yq -o=json -I=0 '.controls | map_values(.params // {})' "$CATALOG")"
overrides="$(yq -o=json -I=0 '.controls // {} | map_values(.params // {})' "$CONFIG")"
params="$(jq -cn --argjson d "$defaults" --argjson o "$overrides" '$d * $o')"
set_output type "$type"
set_output architecture "$architecture"
set_output java "$java"
set_output severities "$severities"
set_output params "$params"
