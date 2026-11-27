#!/usr/bin/env bash
# WFL-01: los workflows del repo (.github/workflows) pasan zizmor: actions fijadas por SHA, permissions mínimos, sin
# inyección de expresiones en run, sin credenciales persistidas en el checkout…
# Uso: check-workflows.sh SEVERIDAD (en la raíz del repo)
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

severity="$1"
[[ "$severity" == "off" ]] && exit 0

if [[ ! -d .github/workflows ]]; then
  report WFL-01 "$severity" ok "Sin workflows"
  exit 0
fi
if pytool "zizmor==${ZIZMOR_VERSION}" zizmor --offline --no-progress --format=github .github/workflows; then
  report WFL-01 "$severity" ok ""
else
  report WFL-01 "$severity" fail "zizmor encontró problemas en .github/workflows: ver las anotaciones y https://docs.zizmor.sh/audits/"
fi
