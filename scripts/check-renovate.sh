#!/usr/bin/env bash
# DEP-01: el repo tiene la configuración de Renovate y extiende el preset de este repo (renovate/default.json), y no
# tiene Dependabot para los mismos ecosistemas (abriría PRs duplicados).
# Uso: check-renovate.sh SEVERIDAD (en la raíz del repo)
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PRESET="github>andres-sacco/twa-engineering-standards//renovate/default"
severity="$1"
[[ "$severity" == "off" ]] && exit 0

config=""
for f in renovate.json renovate.json5 .github/renovate.json .github/renovate.json5 .renovaterc .renovaterc.json .renovaterc.json5; do
  if [[ -f "$f" ]]; then
    config="$f"
    break
  fi
done

problems=()
if [[ -z "$config" ]]; then
  problems+=("no hay renovate.json")
elif ! grep -qF "\"${PRESET}" "$config"; then
  problems+=("${config} no extiende ${PRESET}")
fi
for f in .github/dependabot.yml .github/dependabot.yaml; do
  if [[ -f "$f" ]] && grep -qE 'package-ecosystem:\s*"?(maven|github-actions|docker)' "$f"; then
    problems+=("${f} actualiza los mismos ecosistemas que Renovate: sacalo")
  fi
done

if ((${#problems[@]} == 0)); then
  report DEP-01 "$severity" ok "${config}"
else
  detail="$(printf '%s; ' "${problems[@]}")"
  report DEP-01 "$severity" fail "${detail%; } (ver docs/dependencias.md de twa-engineering-standards)"
fi
