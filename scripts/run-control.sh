#!/usr/bin/env bash
# Corre un comando como un control: run-control.sh ID SEVERIDAD "detalle si falla" -- comando...
# Con severidad off no corre. Si el comando falla, el step falla solo con severidad block. Deja `result=ok|fail` en
# las salidas del step para que los siguientes (subir reportes) sepan qué pasó.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

id="$1" severity="$2" failure_detail="$3"
shift 3
[[ "${1:-}" == "--" ]] && shift

if [[ "$severity" == "off" ]]; then
  echo "[$id] apagado en .twa-standards.yml"
  set_output result skipped
  exit 0
fi

if "$@"; then
  set_output result ok
  report "$id" "$severity" ok ""
else
  set_output result fail
  report "$id" "$severity" fail "$failure_detail"
fi
