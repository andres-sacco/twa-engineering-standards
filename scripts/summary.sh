#!/usr/bin/env bash
# Resumen de una corrida de java-ci.yml (job twa-standards): junta los resultados que dejó cada job (una línea JSON
# por control, ver record en lib.sh) y escribe
#   * una tabla con todos los controles en el resumen del job: el lugar único donde mirar en un PR;
#   * twa-results.json, que el workflow sube como artifact twa-results y lee el tablero (scripts/report.sh).
# Un control que no dejó resultado aparece igual: apagado (off), o sin resultado (el job no corrió o falló antes).
# Uso: summary.sh DIRECTORIO_RESULTADOS SEVERIDADES_JSON SALIDA_JSON. Lee del entorno los datos de la corrida
# (GITHUB_REPOSITORY, GITHUB_SHA…) y WORKING_DIRECTORY y STANDARDS_REF.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

results_dir="$1"
severities="$2"
output="$3"

reported="$(cat "${results_dir}"/*.jsonl 2>/dev/null | jq -s '.' || echo '[]')"
catalog="$(yq -o=json -I=0 '.controls | to_entries | map({"id": .key, "name": .value.name})' "$CATALOG")"
run_url="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-local}/actions/runs/${GITHUB_RUN_ID:-0}"

# Un control puede reportar más de una vez (SEC-02: Semgrep y SpotBugs): cuenta el peor resultado
jq -n --argjson reported "$reported" --argjson severities "$severities" --argjson catalog "$catalog" \
  --arg repository "${GITHUB_REPOSITORY:-local}" --arg wd "${WORKING_DIRECTORY:-.}" --arg ref "${GITHUB_REF:-}" \
  --arg sha "${GITHUB_SHA:-}" --arg event "${GITHUB_EVENT_NAME:-}" --arg run "$run_url" \
  --arg standards "${STANDARDS_REF:-}" --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
  def rank: {"fail": 3, "skip": 2, "ok": 1}[.] // 0;
  {
    version: 1, repository: $repository, workingDirectory: $wd, ref: $ref, sha: $sha, event: $event,
    run: $run, standardsRef: $standards, createdAt: $date,
    controls: [
      $catalog[] | .id as $id | ($severities[$id] // "off") as $severity
      | [$reported[] | select(.id == $id)] as $r
      | {
          id: $id, name: .name, severity: $severity,
          result: (if ($r | length) > 0 then ($r | max_by(.result | rank) | .result)
                   elif $severity == "off" then "off" else "none" end),
          detail: ([$r[] | .detail | select(. != "")] | join(" · "))
        }
    ]
  }' >"$output"

summary "## twa-standards"
summary ""
counts="$(jq -r '.controls as $c
  | ([$c[] | select(.result == "ok")] | length) as $o
  | ([$c[] | select(.result == "fail" and .severity == "warn")] | length) as $w
  | ([$c[] | select(.result == "fail" and .severity == "block")] | length) as $b
  | "\($o) pasan, \($w) avisos (warn), \($b) fallan (block)"' "$output")"
summary "${counts}. Detalle de cada control en el resumen de su job y en las anotaciones."
summary ""
summary "| Control | Severidad | Resultado | Detalle |"
summary "|---|---|---|---|"
jq -r '.controls[] | select(.result != "off")
  | (if .result == "ok" then "✅" elif .result == "skip" then "⏭️ sin evaluar"
     elif .result == "none" then "— sin resultado"
     elif .severity == "block" then "❌" else "⚠️" end) as $icon
  | "| `\(.id)` \(.name) | \(.severity) | \($icon) | \(.detail | gsub("\\|"; "\\|") | gsub("\n"; " ")) |"' "$output" |
  while IFS= read -r line; do summary "$line"; done
off="$(jq -r '[.controls[] | select(.result == "off") | .id] | join(", ")' "$output")"
if [[ -n "$off" ]]; then
  summary ""
  summary "Apagados o que no aplican a este tipo de repo: ${off}."
fi
echo "$counts"
