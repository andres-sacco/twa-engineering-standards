#!/usr/bin/env bash
# Funciones comunes de los scripts que corren los controles. Se carga con `source`.
#
# Cada control termina con `report ID SEVERIDAD ok|fail "detalle"`: deja una fila en el resumen del job
# ($GITHUB_STEP_SUMMARY), una anotación si falló, y devuelve 1 solo si falló con severidad block.

# awk y printf con punto decimal, sea cual sea el locale
export LC_NUMERIC=C

# Versiones fijadas de las herramientas que se corren con uvx o pipx, npx o Docker (las usan los scripts que cargan este archivo)
# Renovate las actualiza por el comentario de la línea anterior (renovate/default.json, customManagers)
# shellcheck disable=SC2034
# renovate: datasource=pypi depName=check-jsonschema
CHECK_JSONSCHEMA_VERSION="0.39.0"
# shellcheck disable=SC2034
# renovate: datasource=pypi depName=zizmor
ZIZMOR_VERSION="1.33.1"
# shellcheck disable=SC2034
# renovate: datasource=pypi depName=semgrep
SEMGREP_VERSION="1.185.0"

# shellcheck disable=SC2034
# renovate: datasource=npm depName=@stoplight/spectral-cli
SPECTRAL_VERSION="6.17.1"

# Imágenes de las herramientas que se corren con Docker: versión y digest (el digest cambia si alguien reescribe el tag)
# shellcheck disable=SC2034
# renovate: datasource=docker depName=ghcr.io/gitleaks/gitleaks
GITLEAKS_VERSION="v8.30.1@sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f"
# shellcheck disable=SC2034
# renovate: datasource=docker depName=aquasec/trivy
TRIVY_VERSION="0.76.2@sha256:8f6bb947dbc528902e11f2f5be52f7b519f6a39d5d148f41166f2040499768fb"
# shellcheck disable=SC2034
# renovate: datasource=docker depName=tufin/oasdiff
OASDIFF_VERSION="v1.37.0@sha256:ff02af37a254b5199b9d72e7bba93dae5837a9119d59459168d1398893b47aea"

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

# Directorio de los reportes de seguridad (SARIF, JSON, SBOM) que el workflow sube como artifact
reports_dir() {
  local dir="${REPORTS_DIR:-${PWD}/target/twa-reports}"
  mkdir -p "$dir"
  echo "$dir"
}

# Anotación de un hallazgo en el PR (como máximo 20 por control, para no tapar el resto)
annotate() {
  local severity="$1" title="$2" message="$3" file="${4:-}" line="${5:-}" level=warning
  [[ "$severity" == "block" ]] && level=error
  if [[ -n "$file" ]]; then
    echo "::${level} title=${title},file=${file},line=${line:-1}::${message}"
  else
    echo "::${level} title=${title}::${message}"
  fi
}
