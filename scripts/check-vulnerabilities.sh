#!/usr/bin/env bash
# SEC-03: vulnerabilidades conocidas en las dependencias, con Trivy sobre el SBOM (bom.json de sbom.sh). Cuenta solo
# las de severidad params.severities (default CRITICAL y HIGH) que ya tienen una versión corregida: son las que se
# arreglan actualizando.
# Una vulnerabilidad aceptada va en .trivyignore.yaml (o .trivyignore) en working-directory, con la razón (statement) y
# la fecha de vencimiento (expired_at): al vencer vuelve a aparecer.
# Uso: check-vulnerabilities.sh SEVERIDAD PARAMS_JSON (en working-directory)
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

severity="$1"
params="$2"
[[ "$severity" == "off" ]] && exit 0

reports="$(reports_dir)"
levels="$(jq -r '."SEC-03".severities // ["CRITICAL", "HIGH"] | join(",")' <<<"$params")"
ignore=()
for f in .trivyignore.yaml .trivyignore; do
  if [[ -f "$f" ]]; then
    ignore=(--ignorefile "/src/${f}")
    break
  fi
done

trivy() {
  # La base de vulnerabilidades queda en un volumen de Docker: en local no se baja en cada corrida
  docker run --rm -v "${PWD}:/src:ro" -v "${reports}:/reports" -v twa-trivy-cache:/root/.cache/trivy \
    "aquasec/trivy:${TRIVY_VERSION}" "$@"
}

if ! trivy sbom --quiet --scanners vuln --severity "$levels" --ignore-unfixed "${ignore[@]}" \
  --format json --output /reports/trivy.json /reports/bom.json; then
  report SEC-03 "$severity" fail "Trivy no pudo correr: ver el log de este step"
  exit $?
fi
trivy convert --quiet --format sarif --output /reports/trivy.sarif /reports/trivy.json || true

findings='[.Results[]?.Vulnerabilities[]?] | unique_by(.PkgName, .VulnerabilityID)'
count="$(jq "${findings} | length" "${reports}/trivy.json")"
jq -r "${findings} | .[:20][] | [.Severity, .PkgName, .InstalledVersion, .FixedVersion, .VulnerabilityID] | @tsv" \
  "${reports}/trivy.json" |
  while IFS=$'\t' read -r level pkg installed fixed id; do
    annotate "$severity" "SEC-03 Trivy" "${id} (${level}) en ${pkg} ${installed}: corregida en ${fixed}"
  done

if ((count == 0)); then
  report SEC-03 "$severity" ok "Sin vulnerabilidades ${levels} con versión corregida"
else
  pkgs="$(jq -r "${findings} | map(\"\(.PkgName) \(.InstalledVersion)\") | unique | .[:5] | join(\", \")" "${reports}/trivy.json")"
  report SEC-03 "$severity" fail "${count} vulnerabilidades ${levels} con versión corregida (${pkgs}): actualizá la dependencia o el BOM que la trae"
fi
