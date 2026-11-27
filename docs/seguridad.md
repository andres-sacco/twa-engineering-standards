# Seguridad (SEC-01 a SEC-05)

La etapa 4 agrega a `java-ci.yml` un job `Security` y un paso al final de `Build and test`. Todo es open source y
corre dentro del runner: no hay servidor ni servicio externo (SonarQube quedó afuera, ver el
[plan](plan.md#decisiones-de-la-etapa-4)).

| Control | Severidad | Herramienta | Qué revisa | Dónde corre |
|---|---|---|---|---|
| `SEC-01` | **block** | Gitleaks | Secretos en los archivos del repo y en los commits nuevos (los del PR, o los del push) | `Security`, en la raíz del repo |
| `SEC-02` | warn | Semgrep CE | Código fuente con las reglas `p/java` (sin `src/test`) | `Security` |
| `SEC-02` | warn | SpotBugs + FindSecBugs | Bytecode compilado, solo la categoría SECURITY | `Build and test`, después de `mvn verify` |
| `SEC-04` | warn | CycloneDX Maven plugin | SBOM de las dependencias que llegan al artefacto (sin las de test) | `Security` |
| `SEC-03` | warn | Trivy | Vulnerabilidades CRITICAL y HIGH **con versión corregida**, sobre el SBOM | `Security` |
| `SEC-05` | warn | El SBOM y la lista permitida | Licencias fuera de la lista permitida o sin licencia | `Security` |

Ningún repo tiene que tocar su pom: SpotBugs, FindSecBugs y CycloneDX se agregan por línea de comandos, como JaCoCo.
Gitleaks y Trivy corren con Docker, fijados por versión y digest (`scripts/lib.sh`); Semgrep con `pipx`/`uvx`.

## Reportes

* El resumen de cada job tiene una fila por control; cada hallazgo es una anotación en el PR (como máximo 20 por
  control).
* Artifact `security-reports`: el JSON y el SARIF de cada herramienta (Gitleaks con los secretos ocultos).
  `security-reports-spotbugs`: un SARIF por módulo. Se guardan 7 días.
* Artifact `sbom` (`bom.json`, CycloneDX): 30 días. Es lo que se consulta cuando sale una vulnerabilidad nueva.
* El SARIF no se sube a Code Scanning: los servicios son privados y necesitaría GitHub Advanced Security (ver
  [reportes](reportes.md#sarif)).

## Por qué así

* **SEC-03 y SEC-05 leen el SBOM, no el pom.** Maven ya resolvió las versiones reales, incluidas las de las
  librerías TWA de GitHub Packages, que un escáner externo no puede bajar. Si SEC-04 está en `off`, el SBOM se genera
  igual cuando SEC-03 o SEC-05 lo necesitan.
* **Solo Trivy para vulnerabilidades.** Sobre el SBOM de catalog, OSV-Scanner y Trivy encontraron lo mismo (una
  vulnerabilidad MEDIUM de OpenTelemetry): correr los dos duplicaba los reportes.
* **Las licencias se comparan contra una lista permitida**, no con la clasificación de Trivy. Trivy marca cada
  licencia por separado, y en catalog daba 6 falsos positivos: dependencias con doble licencia (logback, EPL-2.0 o
  LGPL-2.1) o GPL con la excepción de classpath (las APIs de Jakarta). Con la regla "pasa si al menos una de sus
  licencias está permitida", catalog no tiene ninguna.
* **Gitleaks también revisa los commits**: un secreto que se agrega y se borra dentro del PR no queda en los archivos
  pero sí en el historial de `main` después del merge. Un push de una rama nueva (sin commit anterior) revisa solo los
  archivos.

## Suprimir un hallazgo

La regla 4 de la [política de severidades](politica-de-severidades.md): se suprime el hallazgo, no el control, con la
razón al lado.

| Control | Dónde | Cómo |
|---|---|---|
| `SEC-01` | `.gitleaksignore` en la raíz del repo | Una línea con el `Fingerprint` del hallazgo (está en `gitleaks-*.json` del artifact) y un comentario `#` con la razón. **Un secreto real no se suprime: se rota.** Reglas propias, en `.gitleaks.toml` |
| `SEC-02` Semgrep | La línea del código | `// nosemgrep: <id de la regla> <razón>` |
| `SEC-02` SpotBugs | `spotbugs-exclude.xml` en `working-directory` | Un `<Match>` de [FindBugsFilter](https://spotbugs.readthedocs.io/en/latest/filter.html) con la clase y el `<Bug pattern="…"/>`, y un comentario con la razón |
| `SEC-03` | `.trivyignore.yaml` en `working-directory` | El id en `vulnerabilities`, con `statement` (la razón) y `expired_at` (al vencer vuelve a aparecer) |
| `SEC-05` | `.twa-standards.yml` | `params.allowedComponents` (`group:artifact`) o `params.extraAllowedLicenses` (id SPDX) de `SEC-05`, con la razón en un comentario |

Ejemplo de `.trivyignore.yaml`:

```yaml
vulnerabilities:
  - id: CVE-2026-12345
    paths: []
    statement: No se usa el parser afectado; se actualiza con Spring Boot 4.2
    expired_at: 2027-01-31
```

## Probarlo en local

Con Docker, Java 25, Maven, `jq`, `yq` y `uvx`, en la raíz del repo que se quiere revisar (los reportes quedan en
`target/twa-reports`):

```bash
S=../twa-engineering-standards/scripts
PARAMS="$(yq -o=json -I=0 '.controls | map_values(.params // {})' ../twa-engineering-standards/config/controls.yml)"
export SPOTBUGS_VERSION=4.10.5.0 FINDSECBUGS_VERSION=1.14.0 DEPENDENCY_VERSION=3.11.0 CYCLONEDX_VERSION=2.9.3
$S/check-secrets.sh block "origin/main..HEAD"
$S/check-sast.sh warn "$PARAMS"
mvn -q verify && $S/check-spotbugs.sh warn
$S/sbom.sh warn -q && $S/check-vulnerabilities.sh warn "$PARAMS" && $S/check-licenses.sh warn "$PARAMS"
```

Las versiones de los plugins son las del `env:` de `java-ci.yml`.

## Qué dio sobre los repos (2026-11-27)

| Repo | SEC-01 | SEC-02 | SEC-03 | SEC-04 | SEC-05 |
|---|---|---|---|---|---|
| catalog | sin secretos (archivos y últimos 10 commits) | sin hallazgos (Semgrep y SpotBugs, 189 clases) | sin CRITICAL/HIGH (una MEDIUM con fix) | 191 componentes | todas permitidas |
| sample-service | sin secretos | sin hallazgos | sin CRITICAL/HIGH | 49 componentes | todas permitidas |

Casos negativos probados: un token de GitHub en un commit (SEC-01 lo marca en el archivo y en el commit, oculto), una
clase con MD5 y `Runtime.exec` (Semgrep marca el MD5, SpotBugs los dos), MEDIUM incluida en las severidades (SEC-03
falla con la de OpenTelemetry) y una lista permitida recortada (SEC-05 marca 14 dependencias).
