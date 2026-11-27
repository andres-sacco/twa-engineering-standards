#!/usr/bin/env bash
# SEC-02 (SpotBugs + FindSecBugs): análisis de seguridad del bytecode ya compilado (corre después de mvn verify).
# Solo la categoría SECURITY (config/spotbugs-security.xml). Los plugins se agregan por línea de comandos, como JaCoCo:
# el pom del repo no los declara.
# Un falso positivo se suprime en spotbugs-exclude.xml en working-directory (formato FindBugsFilter), con la razón en
# un comentario.
# Uso: check-spotbugs.sh SEVERIDAD [argumentos de Maven…] (en working-directory). Usa SPOTBUGS_VERSION,
# FINDSECBUGS_VERSION y DEPENDENCY_VERSION del entorno.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

severity="$1"
shift
[[ "$severity" == "off" ]] && exit 0

reports="$(reports_dir)"
plugins="${RUNNER_TEMP:-${PWD}/target}/spotbugs-plugins"
mvn -B -ntp -q "org.apache.maven.plugins:maven-dependency-plugin:${DEPENDENCY_VERSION}:copy" \
  "-Dartifact=com.h3xstream.findsecbugs:findsecbugs-plugin:${FINDSECBUGS_VERSION}" \
  "-DoutputDirectory=${plugins}" -Dmdep.stripVersion=true

args=(
  "-Dspotbugs.pluginList=${plugins}/findsecbugs-plugin.jar"
  "-Dspotbugs.includeFilterFile=${STANDARDS_DIR}/config/spotbugs-security.xml"
  -Dspotbugs.xmlOutput=true
  -Dspotbugs.sarifOutput=true
)
[[ -f spotbugs-exclude.xml ]] && args+=("-Dspotbugs.excludeFilterFile=${PWD}/spotbugs-exclude.xml")

if ! mvn -B -ntp "com.github.spotbugs:spotbugs-maven-plugin:${SPOTBUGS_VERSION}:spotbugs" "${args[@]}" "$@"; then
  report SEC-02 "$severity" fail "SpotBugs no pudo correr: ver el log de este step"
  exit $?
fi

# Un reporte por módulo: se juntan los hallazgos y se copian los SARIF
count=0
details=()
while IFS= read -r xml; do
  module="$(dirname "$(dirname "$xml")")"
  [[ -f "${module}/target/spotbugsSarif.json" ]] &&
    cp "${module}/target/spotbugsSarif.json" "${reports}/spotbugs-$(basename "$(cd "$module" && pwd)").sarif"
  while IFS=$'\t' read -r type class line; do
    [[ -z "$type" ]] && continue
    count=$((count + 1))
    details+=("$type")
    if ((count <= 20)); then
      annotate "$severity" "SEC-02 SpotBugs" "${type} en ${class}:${line} (https://find-sec-bugs.github.io/bugs.htm#${type})"
    fi
  done < <(yq -p xml -o tsv '[.BugCollection.BugInstance] | flatten | .[] | select(. != null)
    | [."+@type", .Class."+@classname", ([.SourceLine] | flatten | .[0]."+@start" // "")]' "$xml" 2>/dev/null || true)
done < <(find . -path '*/target/spotbugsXml.xml' -not -path '*/node_modules/*' | sort)

if ((count == 0)); then
  report SEC-02 "$severity" ok "SpotBugs + FindSecBugs: sin hallazgos de seguridad"
else
  types="$(printf '%s\n' "${details[@]}" | sort -u | paste -sd, - | sed 's/,/, /g')"
  report SEC-02 "$severity" fail "SpotBugs encontró ${count} (${types}): ver las anotaciones y el artifact security-reports"
fi
