#!/usr/bin/env bash
# GOV-01 y GOV-02: las excepciones a los controles (supresiones de hallazgos y severidades bajadas) quedan a la vista y
# con su razón (reglas 4 y 5 de docs/politica-de-severidades.md).
#   GOV-01: lista las excepciones que agregan o cambian los commits nuevos (los del PR o los del push): archivos de
#           supresión, violaciones de arquitectura congeladas, comentarios nosemgrep y hadolint ignore agregados, y
#           controles de .twa-standards.yml con menos severidad o con otros params. Un PR puede suprimir el hallazgo
#           que lo bloquea; este aviso es lo que hace que alguien lo mire.
#   GOV-02: cada supresión del repo tiene su razón y, si es una vulnerabilidad, fecha de vencimiento. Una severidad
#           bajada con `until` vencido también cuenta.
# Uso: check-suppressions.sh SEVERIDAD_GOV01 SEVERIDAD_GOV02 RANGO CONFIG (en la raíz del repo, con el historial).
#   RANGO: base..head (vacío: GOV-01 no tiene contra qué comparar). CONFIG: el .twa-standards.yml, relativo a la raíz.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

sev_changes="$1" sev_format="$2" range="${3:-}" config="${4:-.twa-standards.yml}"
config="${config#./}"

# Archivos que suprimen hallazgos, por nombre
SUPPRESSION_FILES='^(\.gitleaksignore|\.gitleaks\.toml|\.trivyignore|\.trivyignore\.yaml|\.semgrepignore|spotbugs-exclude\.xml)$'
# Dónde se buscan los comentarios que suprimen una línea
SOURCE_PATHS=('*.java' '*.kt' '*Dockerfile*')
INLINE='nosemgrep|hadolint ignore='

# --- GOV-01 ------------------------------------------------------------------------------------------------------------
gov01() {
  local base head changes=() f
  base="${range%%..*}"
  head="${range##*..}"
  if [[ -z "$range" ]] || ! git cat-file -e "${base}^{commit}" 2>/dev/null || ! git cat-file -e "${head}^{commit}" 2>/dev/null; then
    report GOV-01 "$sev_changes" ok "Sin commits anteriores para comparar: solo se revisa el formato (GOV-02)"
    return
  fi

  # Tres puntos: lo que cambió desde el punto en que la rama salió de la base
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if [[ "$(basename "$f")" =~ $SUPPRESSION_FILES ]]; then
      changes+=("$f")
    elif [[ "$f" == */archunit_store/* && "$(basename "$f")" != stored.rules ]]; then
      changes+=("$f (violaciones de arquitectura congeladas)")
    fi
  done < <(git diff --name-only "${base}...${head}")

  # Comentarios agregados: "archivo:línea" de cada línea nueva con nosemgrep o hadolint ignore
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    changes+=("$f")
  done < <(git diff -U0 "${base}...${head}" -- "${SOURCE_PATHS[@]}" | awk -v re="$INLINE" '
    /^\+\+\+ / { file = substr($2, 3); next }
    /^@@/ { split($3, a, ","); line = substr(a[1], 2) + 0; next }
    /^\+/ { if ($0 ~ re) print file ":" line; line++ }')

  # .twa-standards.yml: controles con menos severidad que antes o con otros params
  if [[ -f "$config" ]] && ! git diff --quiet "${base}...${head}" -- "$config"; then
    local before after defaults
    before="$(git show "${base}:${config}" 2>/dev/null | yq -o=json -I=0 '.controls // {}' 2>/dev/null || true)"
    [[ -n "$before" ]] || before='{}'
    after="$(yq -o=json -I=0 '.controls // {}' "$config")"
    defaults="$(yq -o=json -I=0 '.controls | map_values(.severity)' "$CATALOG")"
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      changes+=("${config}: ${f}")
    done < <(jq -rn --argjson o "$before" --argjson n "$after" --argjson d "$defaults" '
      def rank: {"off": 0, "warn": 1, "block": 2}[.];
      ($o + $n | keys[]) as $k
      | ($o[$k].severity // $d[$k]) as $before | ($n[$k].severity // $d[$k]) as $after
      | (if $before != null and $after != null and (($after | rank) < ($before | rank))
         then "\($k) baja de \($before) a \($after)" else empty end),
        (if ($o[$k].params // {}) != ($n[$k].params // {}) then "\($k) cambia sus params" else empty end)')
  fi

  if ((${#changes[@]} == 0)); then
    report GOV-01 "$sev_changes" ok "Los commits nuevos no agregan ni cambian excepciones"
    return
  fi
  for f in "${changes[@]:0:20}"; do
    annotate "$sev_changes" "GOV-01 Excepción nueva" "Revisar la razón: ${f}"
  done
  report GOV-01 "$sev_changes" fail "Los commits nuevos agregan o cambian ${#changes[@]} excepciones ($(printf '%s\n' "${changes[@]:0:5}" | paste -sd';' - | sed 's/;/; /g')): revisar que cada una tenga su razón y que no tape un problema real"
}

# --- GOV-02 ------------------------------------------------------------------------------------------------------------
problems=()
problem() { # problem ARCHIVO LÍNEA "mensaje"
  problems+=("${1}:${2}")
  ((${#problems[@]} > 20)) || annotate "$sev_format" "GOV-02 Supresión sin razón" "$3" "$1" "$2"
}

# Cada línea que suprime algo (no vacía y no comentario) va después de una línea de comentario con la razón
needs_comment_above() { # needs_comment_above ARCHIVO
  awk '
    /^[[:space:]]*$/ { next }
    /^[[:space:]]*#/ { commented = 1; next }
    { if (!commented) print FNR; commented = 0 }' "$1"
}

gov02() {
  local f n id today
  today="$(date -u +%F)"
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    case "$(basename "$f")" in
      .gitleaksignore | .semgrepignore)
        while read -r n; do
          problem "$f" "$n" "Falta un comentario '# razón' en la línea anterior"
        done < <(needs_comment_above "$f")
        ;;
      .trivyignore)
        problem "$f" 1 "Usar .trivyignore.yaml, que lleva statement (la razón) y expired_at (el vencimiento)"
        ;;
      .trivyignore.yaml)
        while IFS= read -r id; do
          [[ -n "$id" ]] && problem "$f" 1 "${id}: falta statement o expired_at"
        done < <(yq '(.vulnerabilities // []) + (.misconfigurations // []) | .[]
          | select((has("statement") and has("expired_at")) | not) | .id' "$f")
        while IFS= read -r id; do
          [[ -n "$id" ]] && problem "$f" 1 "${id}: falta statement"
        done < <(yq '(.secrets // []) + (.licenses // []) | .[] | select(has("statement") | not) | .id' "$f")
        ;;
      spotbugs-exclude.xml)
        while read -r n; do
          problem "$f" "$n" "Falta un comentario <!-- razón --> antes del <Match>"
        done < <(awk '
          /<Match/ && prev !~ /-->/ && $0 !~ /<!--/ { print FNR }
          NF { prev = $0 }' "$f")
        ;;
    esac
  done < <(git ls-files | awk -F/ -v re="$SUPPRESSION_FILES" '$NF ~ re')

  # nosemgrep: <id> <razón> y hadolint ignore=<códigos> <razón>
  while IFS=: read -r f n _; do
    [[ -z "$f" ]] && continue
    problem "$f" "$n" "Falta el id de la regla o la razón: '// nosemgrep: <id> <razón>' o '# hadolint ignore=<código> <razón>'"
  done < <(git grep -nE "$INLINE" -- "${SOURCE_PATHS[@]}" |
    grep -vE 'nosemgrep:[[:space:]]*[^[:space:]]+[[:space:]]+[^[:space:]]|hadolint ignore=[^[:space:]]+[[:space:]]+[^[:space:]]' || true)

  # .twa-standards.yml: una severidad bajada con `until` vencido
  if [[ -f "$config" ]]; then
    while IFS=$'\t' read -r id until; do
      [[ -z "$id" ]] && continue
      [[ "$until" < "$today" ]] && problem "$config" 1 "${id}: la excepción venció el ${until}: volver al default o renovarla con su razón"
    done < <(yq -o=tsv '.controls // {} | to_entries | .[] | select(.value.until != null) | [.key, .value.until]' "$config")
  fi

  if ((${#problems[@]} == 0)); then
    report GOV-02 "$sev_format" ok "Las supresiones del repo tienen su razón y su vencimiento"
  else
    report GOV-02 "$sev_format" fail "${#problems[@]} supresiones sin razón, sin vencimiento o vencidas ($(printf '%s\n' "${problems[@]:0:5}" | paste -sd';' - | sed 's/;/; /g')): ver las anotaciones y docs/seguridad.md"
  fi
}

status=0
if [[ "$sev_changes" != "off" ]]; then gov01 || status=1; fi
if [[ "$sev_format" != "off" ]]; then gov02 || status=1; fi
exit "$status"
