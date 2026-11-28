#!/usr/bin/env bash
# SEC-01: secretos (tokens, claves, contraseñas) con Gitleaks, en dos pasadas:
#   * los archivos del repo tal como están (gitleaks dir);
#   * los commits nuevos: los del PR (base..head) o los del push (before..sha). Un secreto que se agregó y se borró en
#     el mismo PR no está en los archivos pero sí en el historial, y mergeado ya no se puede sacar.
# Los secretos no se muestran (--redact). Un falso positivo se suprime en .gitleaksignore (su fingerprint, que está en
# el reporte) o con la configuración propia del repo en .gitleaks.toml.
# Uso: check-secrets.sh SEVERIDAD [RANGO] (en la raíz del repo). RANGO: base..head; vacío, solo los archivos.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

severity="$1"
range="${2:-}"
[[ "$severity" == "off" ]] && exit 0

reports="$(reports_dir)"
image="ghcr.io/gitleaks/gitleaks:${GITLEAKS_VERSION}"

# Un rango cuyo commit base no está en el clon (push de una rama nueva, historial reescrito) no se puede recorrer
if [[ -n "$range" ]] && ! git cat-file -e "${range%%..*}^{commit}" 2>/dev/null; then
  echo "[SEC-01] ${range%%..*} no está en el clon: solo se revisan los archivos"
  range=""
fi

gitleaks() {
  local report="$1"
  shift
  # Como root: la imagen marca todos los directorios como safe.directory para git solo para root
  docker run --rm -v "${PWD}:/repo" -v "${reports}:/reports" -w /repo "$image" "$@" \
    --redact --no-banner --exit-code 0 --report-format json --report-path "/reports/${report}.json"
}

# Si Gitleaks no corre (no se pudo bajar la imagen…), el control falla con su severidad: en block, el PR no pasa
# sin haber revisado los secretos
if ! gitleaks gitleaks-files dir .; then
  report SEC-01 "$severity" fail "Gitleaks no pudo correr sobre los archivos: ver el log de este step"
  exit $?
fi
found_files="$(jq 'length' "${reports}/gitleaks-files.json")"
found_commits=0
if [[ -n "$range" ]]; then
  if ! gitleaks gitleaks-commits git --log-opts="$range" .; then
    report SEC-01 "$severity" fail "Gitleaks no pudo correr sobre los commits ${range}: ver el log de este step"
    exit $?
  fi
  found_commits="$(jq 'length' "${reports}/gitleaks-commits.json")"
fi

# Las dos pasadas pueden encontrar el mismo secreto: se anota una vez por archivo y línea
jq -r -s 'add | unique_by(.File, .StartLine) | .[:20][] | [.RuleID, .File, .StartLine, (.Commit // "")[:8]] | @tsv' \
  "${reports}"/gitleaks-*.json |
  while IFS=$'\t' read -r rule file line commit; do
    annotate "$severity" "SEC-01 Gitleaks" "Posible secreto (${rule})${commit:+ en el commit ${commit}}" "$file" "$line"
  done

scope="los archivos"
[[ -n "$range" ]] && scope="los archivos y los commits ${range}"
if ((found_files + found_commits == 0)); then
  report SEC-01 "$severity" ok "Sin secretos en ${scope}"
else
  report SEC-01 "$severity" fail "Gitleaks encontró ${found_files} en los archivos y ${found_commits} en los commits: rotá el secreto (sacarlo del código no alcanza) y, si es un falso positivo, agregá su fingerprint a .gitleaksignore"
fi
