#!/usr/bin/env bash
# make lint: valida los workflows, el schema de .twa-standards.yml y el catálogo de controles. Corre igual en local y
# en CI. Necesita Docker (actionlint), yq (mikefarah, viene en los runners de GitHub) y uvx o pipx (zizmor,
# check-jsonschema, shellcheck) y npx (renovate-config-validator), con las versiones fijadas acá.
set -euo pipefail

# renovate: datasource=docker depName=rhysd/actionlint
ACTIONLINT_VERSION="1.7.12"
# renovate: datasource=pypi depName=shellcheck-py
SHELLCHECK_VERSION="0.11.0.1"
# renovate: datasource=npm depName=renovate
RENOVATE_VERSION="44.236.5"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
# shellcheck source=scripts/lib.sh
source scripts/lib.sh

SCHEMA="schema/twa-standards.schema.json"
CATALOG="config/controls.yml"
POLICY="docs/politica-de-severidades.md"
ID_PATTERN='^(BLD|TST|ARC|SEC|API|DKR|DEP|WFL)-[0-9]{2}$'

errors=0
section() { printf '==> %s\n' "$1"; }
ok() { printf '  ✔ %s\n' "$1"; }
fail() { printf '  ✘ %s\n' "$1"; errors=$((errors + 1)); }

section "Workflows: actionlint ${ACTIONLINT_VERSION}"
if docker run --rm -v "$ROOT:/repo" -w /repo "rhysd/actionlint:${ACTIONLINT_VERSION}" -color; then
  ok "sin problemas"
else
  fail "actionlint encontró problemas"
fi

section "Workflows: zizmor ${ZIZMOR_VERSION} (WFL-01)"
if pytool "zizmor==${ZIZMOR_VERSION}" zizmor --offline --no-progress .github/workflows; then
  ok "sin problemas"
else
  fail "zizmor encontró problemas"
fi

section "Schema de .twa-standards.yml"
jsonschema() { pytool "check-jsonschema==${CHECK_JSONSCHEMA_VERSION}" check-jsonschema "$@"; }
if jsonschema --check-metaschema "$SCHEMA" >/dev/null; then
  ok "el schema es válido (JSON Schema 2020-12)"
else
  fail "el schema no cumple el metaschema"
fi
mapfile -t valid_files < <(find schema/tests/valid examples -name '*.yml' -path '*/valid/*' -o -name '.twa-standards.yml' | sort)
for f in "${valid_files[@]}"; do
  if jsonschema --schemafile "$SCHEMA" "$f" >/dev/null; then ok "válido: $f"; else fail "debería ser válido: $f"; fi
done
for f in schema/tests/invalid/*.yml; do
  if jsonschema --schemafile "$SCHEMA" "$f" >/dev/null 2>&1; then fail "debería ser inválido: $f"; else ok "inválido: $f"; fi
done

section "Renovate ${RENOVATE_VERSION}: preset y renovate.json"
if npx --yes --quiet --package "renovate@${RENOVATE_VERSION}" -- renovate-config-validator --strict --no-global \
  renovate/default.json renovate.json >/dev/null 2>&1; then
  ok "válidos como configuración de repo"
else
  fail "renovate-config-validator encontró problemas (correrlo a mano para ver el detalle)"
fi
if [[ "$(grep -oE 'renovate-version: \S+' .github/workflows/renovate.yml | cut -d' ' -f2)" != "$RENOVATE_VERSION" ]]; then
  fail "renovate.yml y lint.sh usan versiones distintas de Renovate"
fi

section "Spectral ${SPECTRAL_VERSION}: config/spectral/twa.yaml contra config/spectral/tests"
spectral_codes() {
  local out
  out="$(mktemp)"
  npx --yes --quiet --package "@stoplight/spectral-cli@${SPECTRAL_VERSION}" -- spectral lint "$1" \
    --ruleset config/spectral/twa.yaml --fail-severity error --quiet -f json -o.json "$out" >/dev/null 2>&1 || true
  jq -r --argjson max "$2" '.[] | select(.severity <= $max) | .code' "$out" 2>/dev/null | sort -u
  rm -f "$out"
}
found="$(spectral_codes config/spectral/tests/valida.yaml 1)"
if [[ -z "$found" ]]; then
  ok "valida.yaml: sin errores ni avisos"
else
  fail "valida.yaml tiene hallazgos: $(tr '\n' ' ' <<<"$found")"
fi
# Cada regla twa-* en error tiene que aparecer en invalida.yaml (salvo twa-servers: esa spec sí tiene servers)
found="$(spectral_codes config/spectral/tests/invalida.yaml 0)"
missing=()
if ! rules="$(yq '.rules | to_entries | .[] | select(.key | test("^twa-")) | select(.value.severity == "error") | .key' \
  config/spectral/twa.yaml)" || [[ -z "$rules" ]]; then
  fail "no se pudieron leer las reglas twa-* de config/spectral/twa.yaml (YAML inválido)"
fi
while read -r rule; do
  [[ -z "$rule" || "$rule" == "twa-servers" ]] && continue
  grep -qx "$rule" <<<"$found" || missing+=("$rule")
done <<<"$rules"
if ((${#missing[@]} == 0)); then
  ok "invalida.yaml rompe todas las reglas twa-* en error"
else
  fail "invalida.yaml no rompe: ${missing[*]}"
fi

section "Conftest ${CONFTEST_VERSION%@*}: config/conftest/dockerfile.rego"
conftest_ids() {
  docker run --rm -v "$ROOT:/project:ro" -w /project "openpolicyagent/conftest:${CONFTEST_VERSION}" test \
    --policy config/conftest --parser dockerfile --no-fail --output json "$@" 2>/dev/null |
    jq -r '.[].failures[]?.msg | split(":")[0]' | sort -u
}
found="$(conftest_ids examples/sample-service/Dockerfile)"
if [[ -z "$found" ]]; then
  ok "examples/sample-service/Dockerfile cumple las políticas"
else
  fail "examples/sample-service/Dockerfile no cumple: $(tr '\n' ' ' <<<"$found")"
fi
# Cada política (TWA-DOCKER-NN) tiene que fallar en algún Dockerfile de config/conftest/tests
found="$(conftest_ids config/conftest/tests/*.Dockerfile)"
missing=()
while read -r id; do
  grep -qx "$id" <<<"$found" || missing+=("$id")
done < <(grep -oE 'TWA-DOCKER-[0-9]{2}' config/conftest/dockerfile.rego | sort -u)
if [[ -n "$found" && ${#missing[@]} -eq 0 ]]; then
  ok "config/conftest/tests rompe todas las políticas"
else
  fail "config/conftest/tests no rompe: ${missing[*]:-ninguna (¿conftest no corrió?)}"
fi

section "Catálogo de controles (${CATALOG})"
mapfile -t ids < <(yq '.controls | keys | .[]' "$CATALOG")
for id in "${ids[@]}"; do
  [[ "$id" =~ $ID_PATTERN ]] || fail "$id: no cumple ${ID_PATTERN}"
  severity="$(yq ".controls.\"$id\".severity" "$CATALOG")"
  [[ "$severity" =~ ^(off|warn|block)$ ]] || fail "$id: severity '$severity' no es off, warn ni block"
  for field in name tool stage appliesTo; do
    [[ "$(yq ".controls.\"$id\" | has(\"$field\")" "$CATALOG")" == "true" ]] || fail "$id: falta '$field'"
  done
  if yq ".controls.\"$id\".appliesTo[]" "$CATALOG" | grep -qvE '^(service|library)$'; then
    fail "$id: appliesTo solo admite service y library"
  fi
done
[[ "$(yq '.implementedStages | type' "$CATALOG")" == "!!seq" ]] || fail "implementedStages tiene que ser una lista de etapas"
ok "${#ids[@]} controles"

section "Política de severidades contra el catálogo"
# Filas de la tabla: | `ID` | Control | Herramienta | Severidad inicial | Etapa |. Los backticks son literales
# shellcheck disable=SC2016
mapfile -t policy_rows < <(grep -E '^\| `[A-Z]{3}-[0-9]{2}` \|' "$POLICY")
declare -A policy_severity=()
for row in "${policy_rows[@]}"; do
  # shellcheck disable=SC2016
  id="$(sed -E 's/^\| `([A-Z]{3}-[0-9]{2})`.*/\1/' <<<"$row")"
  severity="$(awk -F'|' '{print $5}' <<<"$row" | grep -oE 'off|warn|block' | head -1)"
  policy_severity["$id"]="$severity"
done
for id in "${ids[@]}"; do
  if [[ -z "${policy_severity[$id]:-}" ]]; then
    fail "$id está en el catálogo y no en ${POLICY}"
  elif [[ "${policy_severity[$id]}" != "$(yq ".controls.\"$id\".severity" "$CATALOG")" ]]; then
    fail "$id: la severidad de ${POLICY} no coincide con el catálogo"
  fi
done
for id in "${!policy_severity[@]}"; do
  printf '%s\n' "${ids[@]}" | grep -qx "$id" || fail "$id está en ${POLICY} y no en el catálogo"
done
ok "${#policy_rows[@]} filas revisadas"

section "Ids usados en las configuraciones"
for f in "${valid_files[@]}"; do
  while read -r id; do
    [[ -z "$id" ]] && continue
    printf '%s\n' "${ids[@]}" | grep -qx "$id" || fail "$f: el control $id no está en el catálogo"
  done < <(yq '.controls // {} | keys | .[]' "$f")
done
ok "${#valid_files[@]} archivos revisados"

section "Scripts"
# El default de standards-ref lo actualiza release-please: tiene que tener la marca
if ! grep -qE 'default: v[0-9]+\.[0-9]+\.[0-9]+ # x-release-please-version' .github/workflows/java-ci.yml; then
  fail "java-ci.yml: el default de standards-ref perdió la marca x-release-please-version"
fi
for f in scripts/*.sh; do
  bash -n "$f" || fail "sintaxis: $f"
done
if pytool "shellcheck-py==${SHELLCHECK_VERSION}" shellcheck scripts/*.sh; then
  ok "shellcheck"
else
  fail "shellcheck encontró problemas"
fi

if ((errors > 0)); then
  printf '✘ %d problemas\n' "$errors"
  exit 1
fi
printf '✔ Todo en orden\n'
