#!/usr/bin/env bash
# BLD-03: el build compila para la versión de Java del .twa-standards.yml y exige versiones de Java y Maven con
# maven-enforcer-plugin (requireJavaVersion y requireMavenVersion en el pom efectivo).
# Uso: check-build-versions.sh SEVERIDAD JAVA (en el directorio del pom)
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

severity="$1" java="$2"
[[ "$severity" == "off" ]] && exit 0

problems=()
release="$(mvn -B -ntp -q help:evaluate -Dexpression=maven.compiler.release -DforceStdout 2>/dev/null || true)"
if [[ "$release" != "$java" ]]; then
  problems+=("compila para Java '${release:-sin maven.compiler.release}' y .twa-standards.yml dice ${java}")
fi
effective_pom="$(mktemp)"
mvn -B -ntp -q help:effective-pom -Doutput="$effective_pom" >/dev/null 2>&1 || true
for rule in requireJavaVersion requireMavenVersion; do
  grep -q "<${rule}>" "$effective_pom" || problems+=("maven-enforcer-plugin no tiene ${rule}")
done
rm -f "$effective_pom"

if ((${#problems[@]} == 0)); then
  report BLD-03 "$severity" ok "Java ${java}"
else
  detail="$(printf '%s; ' "${problems[@]}")"
  detail="${detail%; }"
  report BLD-03 "$severity" fail "$detail"
fi
