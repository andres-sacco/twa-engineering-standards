#!/usr/bin/env bash
# Tablero de twa-engineering-standards: el estado de cada control en cada repo, según el último push a su rama
# principal. No escanea nada: lee el artifact twa-results que deja java-ci.yml (job twa-standards) en cada corrida.
# Un repo que no cambió muestra su último resultado (no hay escaneo nocturno: docs/reportes.md).
#
# Uso:
#   report.sh fetch [DIRECTORIO]   baja el twa-results de cada repo de config/report.yml (necesita TWA_REPORT_TOKEN con
#                                  lectura de Actions en esos repos)
#   report.sh render [DIRECTORIO]  arma DIRECTORIO/index.md y DIRECTORIO/report.json con lo bajado
# DIRECTORIO: report/ por defecto (está en .gitignore: tiene hallazgos de repos privados).
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

command="${1:-}"
out="${2:-report}"
API="${GITHUB_API_URL:-https://api.github.com}"
REPOS_FILE="${STANDARDS_DIR}/config/report.yml"

gh_api() {
  local auth=()
  [[ -n "${TWA_REPORT_TOKEN:-}" ]] && auth=(-H "Authorization: Bearer ${TWA_REPORT_TOKEN}")
  curl -fsSL "${auth[@]}" -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" "$@"
}

fetch() {
  mkdir -p "${out}/results"
  while IFS= read -r repo; do
    [[ -z "$repo" ]] && continue
    name="${repo##*/}"
    rm -f "${out}/results/${name}.json" "${out}/results/${name}.missing"
    if ! branch="$(gh_api "${API}/repos/${repo}" | jq -r '.default_branch')"; then
      echo "${repo}: no se pudo leer (¿el token tiene acceso?)" | tee "${out}/results/${name}.missing"
      continue
    fi
    # El artifact más reciente de la rama principal (los de un PR tienen como head_branch la rama del PR)
    artifact="$(gh_api "${API}/repos/${repo}/actions/artifacts?name=twa-results&per_page=100" |
      jq -c --arg b "$branch" '[.artifacts[] | select(.expired | not) | select(.workflow_run.head_branch == $b)]
        | sort_by(.created_at) | last // empty')"
    if [[ -z "$artifact" ]]; then
      echo "${repo}: sin twa-results en ${branch} (¿adoptó java-ci.yml? ¿el último push tiene más de 30 días?)" |
        tee "${out}/results/${name}.missing"
      continue
    fi
    tmp="$(mktemp -d)"
    gh_api -o "${tmp}/a.zip" "$(jq -r '.archive_download_url' <<<"$artifact")"
    unzip -qo "${tmp}/a.zip" -d "$tmp"
    cp "${tmp}/twa-results.json" "${out}/results/${name}.json"
    rm -rf "$tmp"
    echo "${repo}: $(jq -r '"\(.sha[:7]) del \(.createdAt)"' "${out}/results/${name}.json")"
  done < <(yq '.repos[]' "$REPOS_FILE")
}

render() {
  local results=("${out}"/results/*.json)
  if [[ ! -e "${results[0]}" ]]; then
    echo "No hay resultados en ${out}/results: correr primero report.sh fetch" >&2
    exit 1
  fi
  jq -s --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{createdAt: $date, repos: .}' "${results[@]}" >"${out}/report.json"
  local ids
  ids="$(yq -o=json -I=0 '.controls | keys' "$CATALOG")"
  {
    echo "# Tablero de twa-engineering-standards"
    echo
    echo "Generado el $(date -u '+%Y-%m-%d %H:%M') UTC con el último push a la rama principal de cada repo. ✅ pasa ·"
    echo "⚠️ falla en warn · ❌ falla en block · ⏭️ sin evaluar · — sin resultado · vacío: apagado o no aplica."
    echo
    jq -r --argjson ids "$ids" '
      def icon: if .result == "ok" then "✅" elif .result == "skip" then "⏭️" elif .result == "none" then "—"
        elif .result == "off" then "" elif .severity == "block" then "❌" else "⚠️" end;
      "| Repo | Último push | " + ($ids | join(" | ")) + " |",
      "|---|---|" + ($ids | map("---") | join("|")) + "|",
      (.repos | sort_by(.repository)[] | . as $r
        | "| \($r.repository | split("/") | last) | [\($r.sha[:7])](\($r.run)) \($r.createdAt[:10]) | "
          + ($ids | map(. as $id | ($r.controls[] | select(.id == $id) | icon) // "") | join(" | ")) + " |")
    ' "${out}/report.json"
    echo
    echo "## Lo que falla"
    echo
    jq -r '[.repos | sort_by(.repository)[] | .repository as $repo | .controls[]
        | select(.result == "fail") | {repo: ($repo | split("/") | last), id, name, severity, detail}]
      | if length == 0 then "Nada: todos los controles que corren pasan."
        else (.[] | "* **\(.repo)** `\(.id)` \(.name) (\(.severity)): \(.detail)") end' "${out}/report.json"
    local missing=("${out}"/results/*.missing)
    if [[ -e "${missing[0]}" ]]; then
      echo
      echo "## Sin resultados"
      echo
      cat "${missing[@]}" | sed 's/^/* /'
    fi
  } >"${out}/index.md"
  echo "Tablero en ${out}/index.md ($(jq '.repos | length' "${out}/report.json") repos)"
}

case "$command" in
  fetch) fetch ;;
  render) render ;;
  *)
    echo "Uso: report.sh fetch|render [DIRECTORIO]" >&2
    exit 2
    ;;
esac
