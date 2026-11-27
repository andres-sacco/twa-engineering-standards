#!/usr/bin/env bash
# SEC-04: SBOM CycloneDX (JSON) de las dependencias que llegan al artefacto (sin las de test), con el plugin de
# CycloneDX agregado por línea de comandos. Maven resuelve las versiones reales, también las de las librerías TWA de
# GitHub Packages: SEC-03 y SEC-05 leen este SBOM en lugar de volver a resolver el pom.
# Deja el SBOM en el directorio de reportes (bom.json) y `result=ok|fail` en las salidas del step.
# Uso: sbom.sh SEVERIDAD [argumentos de Maven…] (en working-directory). Usa CYCLONEDX_VERSION del entorno.
# Con SEVERIDAD off el SBOM se genera igual si lo necesitan SEC-03 o SEC-05, pero no se reporta.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

severity="$1"
shift
reports="$(reports_dir)"

if mvn -B -ntp "org.cyclonedx:cyclonedx-maven-plugin:${CYCLONEDX_VERSION}:makeAggregateBom" \
  -DoutputFormat=json -DoutputName=bom -DincludeTestScope=false "$@" && [[ -f target/bom.json ]]; then
  cp target/bom.json "${reports}/bom.json"
  set_output result ok
  if [[ "$severity" != "off" ]]; then
    report SEC-04 "$severity" ok "$(jq '.components | length' target/bom.json) componentes: artifact sbom"
  fi
else
  set_output result fail
  if [[ "$severity" != "off" ]]; then
    report SEC-04 "$severity" fail "No se pudo generar el SBOM: ver el log de este step"
  fi
fi
