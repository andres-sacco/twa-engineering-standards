#!/usr/bin/env bash
# DKR-03: vulnerabilidades del sistema operativo de la imagen (los paquetes de la imagen base), con Trivy sobre la
# imagen construida. Cuenta solo las de severidad params.severities (default CRITICAL y HIGH) con versión corregida.
# Las dependencias Java del jar no se cuentan acá: son SEC-03, sobre el SBOM.
# El mismo escaneo busca secretos en todas las capas (trivy-image.json): los lee DKR-04.
# Una vulnerabilidad aceptada va en .trivyignore.yaml (como SEC-03), con statement y expired_at.
# Uso: check-image.sh SEVERIDAD PARAMS_JSON IMAGEN (en working-directory). Con SEVERIDAD off solo escanea.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

severity="$1"
params="$2"
image="$3"
reports="$(reports_dir)"
levels="$(jq -r '."DKR-03".severities // ["CRITICAL", "HIGH"] | join(",")' <<<"$params")"
ignore=()
for f in .trivyignore.yaml .trivyignore; do
  if [[ -f "$f" ]]; then
    ignore=(--ignorefile "/src/${f}")
    break
  fi
done

trivy() {
  docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v "${PWD}:/src:ro" -v "${reports}:/reports" \
    -v twa-trivy-cache:/root/.cache/trivy "aquasec/trivy:${TRIVY_VERSION}" "$@"
}

# Todas las severidades: el filtro de Trivy también se aplicaría a los secretos. Las vulnerabilidades se filtran abajo
if ! trivy image --quiet --scanners vuln,secret --pkg-types os --ignore-unfixed "${ignore[@]}" \
  --format json --output /reports/trivy-image.json "$image"; then
  set_output result fail
  [[ "$severity" == "off" ]] || report DKR-03 "$severity" fail "Trivy no pudo escanear la imagen: ver el log de este step"
  exit $?
fi
set_output result ok
trivy convert --quiet --format sarif --output /reports/trivy-image.sarif /reports/trivy-image.json || true
[[ "$severity" == "off" ]] && exit 0

findings="[.Results[]?.Vulnerabilities[]? | select(.Severity | IN($(jq -r '."DKR-03".severities // ["CRITICAL", "HIGH"] | map("\"\(.)\"") | join(",")' <<<"$params")))] | unique_by(.PkgName, .VulnerabilityID)"
count="$(jq "${findings} | length" "${reports}/trivy-image.json")"
os="$(jq -r '.Metadata.OS | "\(.Family) \(.Name)"' "${reports}/trivy-image.json")"
jq -r "${findings} | .[:20][] | [.Severity, .PkgName, .InstalledVersion, .FixedVersion, .VulnerabilityID] | @tsv" \
  "${reports}/trivy-image.json" |
  while IFS=$'\t' read -r level pkg installed fixed id; do
    annotate "$severity" "DKR-03 Trivy" "${id} (${level}) en ${pkg} ${installed} de la imagen base: corregida en ${fixed}"
  done

if ((count == 0)); then
  report DKR-03 "$severity" ok "Imagen ${os}: sin vulnerabilidades ${levels} con versión corregida"
else
  report DKR-03 "$severity" fail "Imagen ${os}: ${count} vulnerabilidades ${levels} con versión corregida ($(jq -r "${findings} | map(.PkgName) | unique | .[:5] | join(\", \")" "${reports}/trivy-image.json")): reconstruir con la imagen base actualizada (Renovate actualiza el digest)"
fi
