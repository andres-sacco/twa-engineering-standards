#!/usr/bin/env bash
# DKR-04: políticas TWA de la imagen.
#   * El Dockerfile, con Conftest y config/conftest/dockerfile.rego: JRE de eclipse-temurin como base final
#     (TWA-DOCKER-01), usuario sin privilegios (02), HEALTHCHECK (03), sin credenciales en ENV, ARG ni COPY (04).
#   * La imagen construida: sin secretos en ninguna capa (el escaneo de secretos de check-image.sh, trivy-image.json).
# Una política se exceptúa en params.exceptions de DKR-04 (ej. [TWA-DOCKER-03]), con la razón en un comentario del
# .twa-standards.yml. Un secreto en una capa no se exceptúa: se saca de la imagen y se rota.
# Uso: check-docker-policies.sh SEVERIDAD PARAMS_JSON DOCKERFILE (en working-directory)
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

severity="$1"
params="$2"
dockerfile="$3"
[[ "$severity" == "off" ]] && exit 0

reports="$(reports_dir)"
jq -c '{twa: {exceptions: (."DKR-04".exceptions // [])}}' <<<"$params" >"${reports}/conftest-data.json"
problems=()

if [[ ! -f "$dockerfile" ]]; then
  report DKR-04 "$severity" fail "No existe ${dockerfile}"
  exit $?
fi
docker run --rm -v "${PWD}:/project:ro" -v "${STANDARDS_DIR}/config/conftest:/policy:ro" -v "${reports}:/reports" \
  -w /project "openpolicyagent/conftest:${CONFTEST_VERSION}" test --policy /policy --data /reports/conftest-data.json \
  --parser dockerfile --no-fail --output json "$dockerfile" >"${reports}/conftest.json"
while IFS= read -r msg; do
  [[ -z "$msg" ]] && continue
  problems+=("${msg%%:*}")
  annotate "$severity" "DKR-04 ${msg%%:*}" "${msg#*: }" "$dockerfile" 1
done < <(jq -r '.[].failures[]?.msg' "${reports}/conftest.json")

secrets=0
if [[ -f "${reports}/trivy-image.json" ]]; then
  while IFS=$'\t' read -r target rule; do
    [[ -z "$target" ]] && continue
    secrets=$((secrets + 1))
    annotate "$severity" "DKR-04 secreto en la imagen" "${rule} en ${target}: sacarlo de la imagen (RUN --mount=type=secret) y rotarlo"
  done < <(jq -r '.Results[]? | select(.Class == "secret") | .Target as $t | .Secrets[]? | [$t, .RuleID] | @tsv' \
    "${reports}/trivy-image.json")
  ((secrets == 0)) || problems+=("${secrets} secretos en las capas")
  scope="el Dockerfile y las capas de la imagen"
else
  scope="el Dockerfile (la imagen no se construyó: sin escaneo de secretos)"
fi

if ((${#problems[@]} == 0)); then
  report DKR-04 "$severity" ok "Cumple las políticas TWA en ${scope}"
else
  report DKR-04 "$severity" fail "No cumple: $(printf '%s\n' "${problems[@]}" | sort -u | paste -sd, - | sed 's/,/, /g'). Ver las anotaciones"
fi
