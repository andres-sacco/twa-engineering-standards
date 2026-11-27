#!/usr/bin/env bash
# Funciones comunes de los scripts que corren los controles. Se carga con `source`.
#
# Cada control termina con `report ID SEVERIDAD ok|fail "detalle"`: deja una fila en el resumen del job
# ($GITHUB_STEP_SUMMARY), una anotación si falló, y devuelve 1 solo si falló con severidad block.

# awk y printf con punto decimal, sea cual sea el locale
export LC_NUMERIC=C

# Versiones fijadas de las herramientas que se corren con uvx o pipx (las usan los scripts que cargan este archivo)
# shellcheck disable=SC2034
CHECK_JSONSCHEMA_VERSION="0.39.0"
# shellcheck disable=SC2034
ZIZMOR_VERSION="1.33.1"

STANDARDS_DIR="${STANDARDS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CATALOG="${STANDARDS_DIR}/config/controls.yml"

# Corre una herramienta de Python con la versión fijada, con uvx o pipx
pytool() {
  local spec="$1"
  shift
  if command -v uvx >/dev/null 2>&1; then
    uvx --quiet --from "$spec" "$@"
  elif command -v pipx >/dev/null 2>&1; then
    pipx run --spec "$spec" "$@"
  else
    echo "Hace falta uvx o pipx para correr $spec" >&2
    return 127
  fi
}

control_name() {
  yq ".controls.\"$1\".name // \"\"" "$CATALOG"
}

summary() {
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    printf '%s\n' "$*" >>"$GITHUB_STEP_SUMMARY"
  fi
}

# Encabezado de la tabla del resumen, una vez por job
summary_header() {
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]] && ! grep -q '^| Control | Severidad | Resultado |' "$GITHUB_STEP_SUMMARY" 2>/dev/null; then
    summary ""
    summary "| Control | Severidad | Resultado | Detalle |"
    summary "|---|---|---|---|"
  fi
}

# report ID SEVERIDAD ok|fail|skip "detalle". skip: el control no se pudo evaluar por otra falla (no falla el step)
report() {
  local id="$1" severity="$2" result="$3" detail="$4" name icon
  name="$(control_name "$id")"
  summary_header
  if [[ "$result" == "ok" ]]; then
    icon="✅"
    echo "[$id] ${name}: OK. ${detail}"
  elif [[ "$result" == "skip" ]]; then
    icon="⏭️"
    echo "[$id] ${name}: sin evaluar. ${detail}"
  elif [[ "$severity" == "block" ]]; then
    icon="❌"
    echo "::error title=${id} ${name}::${detail}"
  else
    icon="⚠️"
    echo "::warning title=${id} ${name}::${detail}"
  fi
  summary "| \`${id}\` ${name} | ${severity} | ${icon} | ${detail} |"
  [[ "$result" != "fail" || "$severity" != "block" ]]
}

# Escribe una salida del step (en local, a la consola)
set_output() {
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf '%s=%s\n' "$1" "$2" >>"$GITHUB_OUTPUT"
  else
    printf '%s=%s\n' "$1" "$2"
  fi
}
