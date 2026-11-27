#!/usr/bin/env bash
# SEC-02 (Semgrep CE): análisis estático de seguridad del código fuente con las reglas de params.semgrepConfigs
# (default p/java, del registry de Semgrep). No mira los tests (src/test). Cuenta los hallazgos de severidad media o
# más (ERROR/WARNING, o HIGH/MEDIUM en las versiones nuevas); los informativos no cuentan.
# Un falso positivo se suprime con un comentario `// nosemgrep: <id de la regla>` en la línea, con la razón al lado.
# Uso: check-sast.sh SEVERIDAD PARAMS_JSON (en working-directory)
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

severity="$1"
params="$2"
[[ "$severity" == "off" ]] && exit 0

reports="$(reports_dir)"
mapfile -t configs < <(jq -r '."SEC-02".semgrepConfigs // ["p/java"] | .[]' <<<"$params")
args=()
for c in "${configs[@]}"; do
  args+=(--config "$c")
done

if ! pytool "semgrep==${SEMGREP_VERSION}" semgrep scan "${args[@]}" --metrics=off --quiet \
  --exclude '**/src/test/**' --json-output "${reports}/semgrep.json" --sarif-output "${reports}/semgrep.sarif" .; then
  report SEC-02 "$severity" fail "Semgrep no pudo correr: ver el log de este step"
  exit $?
fi

findings='[.results[] | select(.extra.severity | IN("INFO", "LOW") | not)]'
count="$(jq "${findings} | length" "${reports}/semgrep.json")"
jq -r "${findings} | .[:20][] | [.check_id, .path, .start.line, (.extra.message | gsub(\"[\\r\\n]+\"; \" \"))] | @tsv" \
  "${reports}/semgrep.json" |
  while IFS=$'\t' read -r rule file line message; do
    annotate "$severity" "SEC-02 Semgrep" "${rule##*.}: ${message}" "$file" "$line"
  done

if ((count == 0)); then
  report SEC-02 "$severity" ok "Semgrep (${configs[*]}): sin hallazgos"
else
  rules="$(jq -r "${findings} | map(.check_id | split(\".\") | last) | unique | join(\", \")" "${reports}/semgrep.json")"
  report SEC-02 "$severity" fail "Semgrep encontró ${count} (${rules}): ver las anotaciones y el artifact security-reports"
fi
