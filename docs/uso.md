# Uso: cómo un repo adopta java-ci.yml

`java-ci.yml` es un solo workflow reutilizable para servicios y librerías Java. El tipo de repo, la versión de Java y
la severidad de cada control salen del `.twa-standards.yml` del repo; el workflow corre lo que le corresponde.

## 1. `.twa-standards.yml`

En la raíz del repo (o en `working-directory`). Lo mínimo:

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/andres-sacco/twa-engineering-standards/main/schema/twa-standards.schema.json
version: 1
type: service        # service | library
java: "25"           # default 25; las librerías declaran la suya ("11", "17")
architecture: layered  # solo servicios: layered (twa-layered-rules, el default) | hexagonal (twa-hexagonal-rules)
```

Solo se agregan los controles que cambian su default (`config/controls.yml`). Bajar una severidad necesita `reason`;
si la excepción es temporal, también `until` (`GOV-02` la marca cuando vence):

```yaml
controls:
  TST-01:
    params:
      minLineCoverage: 45   # el default es 60
  BLD-01:
    severity: "off"
    reason: La librería no tiene Spotless configurado (pendiente)
    until: 2027-02-28
```

Un PR que baja una severidad, cambia params o agrega una supresión queda marcado por `GOV-01` (⚠️ en el resumen):
quien lo revisa ve cada excepción nueva.

## 2. `.github/workflows/ci.yml`

Reemplaza el `ci.yml` actual del repo:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

permissions: {}

jobs:
  ci:
    permissions:
      contents: read
    uses: andres-sacco/twa-engineering-standards/.github/workflows/java-ci.yml@<sha> # v0.1.0
    secrets:
      PACKAGES_TOKEN: ${{ secrets.PACKAGES_TOKEN }}
```

* **Por SHA, con la versión en el comentario**, como cualquier action: así el repo cumple su propio `WFL-01` (zizmor
  marca como `unpinned-uses` una referencia por tag). Renovate actualiza el SHA y el comentario con el preset de
  [dependencias](dependencias.md) (grupo `twa-engineering-standards`, sin automerge). A mano: el SHA de un release es
  el del tag `vX.Y.Z` (`git ls-remote --tags` del repo).
* Un `renovate.json` que extiende el preset (`DEP-01`, ver [dependencias](dependencias.md)), y sin
  `.github/dependabot.yml`. En la configuración del repo, **Dependency graph** y **Dependabot alerts** activados: son
  las alertas de vulnerabilidades que Renovate convierte en PR (reemplazan al escaneo nocturno, ver
  [reportes](reportes.md)).
* El repo se agrega a `config/report.yml` de este repo, para que aparezca en el tablero.
* **El secret explícito**, no `secrets: inherit`: el workflow solo recibe lo que necesita.
* Una línea en el `openapi.feature` del `OpenApiIT` para que la spec quede en `target/openapi.json` (`API-01`, ver
  [openapi](openapi.md)).
* `.github/maven-settings.sh` se borra: el `settings.xml` lo arma `scripts/maven-settings.sh` de este repo.
* El check que se exige en la protección de `main` es **`ci / twa-standards`**: resume a todos los jobs y falla solo
  si falló un control en `block`. El resto de la configuración del repo (secrets, alertas, etiqueta
  `api-breaking-change`) está en [despliegue](despliegue.md#qué-hace-falta-en-cada-repo).

### Inputs

| Input | Default | Para qué |
|---|---|---|
| `working-directory` | `.` | Directorio del pom raíz |
| `config-file` | `.twa-standards.yml` | Relativo a `working-directory` |
| `maven-args` | — | Argumentos extra para Maven en BLD-02 y BLD-04 (ej. `-pl search-service -am`) |
| `artifact-name` / `artifact-path` | — | Sube el jar como artifact (glob relativo a `working-directory`), por un día. Solo si algo lo baja: un jar de servicio pesa ~60 MB y la cuota de artifacts es de la cuenta ([reportes](reportes.md#artifacts-y-cuota)) |
| `docker-context` / `dockerfile` | `.` / `Dockerfile` | Relativos a `working-directory` |
| `standards-ref` | la versión del release | **No se toca.** De esa versión de este repo salen los scripts y el catálogo. |

Secret: `PACKAGES_TOKEN`, token clásico con `read:packages` para las librerías TWA de GitHub Packages. Sin él, el
build solo baja dependencias públicas (sirve para un repo sin librerías TWA).

## Qué corre

| Job | Controles | Qué hace |
|---|---|---|
| `Config` | — | Valida `.twa-standards.yml` contra el schema, lo combina con los defaults y deja la tabla en el resumen |
| `Code style` | `BLD-01` | `mvn spotless:check` |
| `Build and test` | `BLD-03`, `ARC-02`, `BLD-04`, `BLD-02`, `ARC-01`, `TST-01`, `TST-02`, `SEC-02`, `API-01`, `API-02`, `API-03` | Versiones de Java y Maven exigidas por el enforcer del pom; versión mínima de la librería de reglas; convergencia de dependencias; `mvn verify` (unit e IT, con las reglas de arquitectura del perfil `architecture-rules`) con JaCoCo agregado por línea de comandos; qué reglas corrieron y cuáles rompen; cobertura de líneas contra el mínimo y contra la rama principal; al final, SpotBugs + FindSecBugs sobre lo compilado (`SEC-02`) y el contrato: la spec de `target/openapi.json` (`API-01`), Spectral (`API-02`) y oasdiff contra la rama principal (`API-03`, ver [openapi](openapi.md)). Sube los reportes si fallan los tests, el reporte de cobertura y el jar |
| `Security` | `SEC-01` a `SEC-05` | Gitleaks sobre los archivos y los commits del PR; Semgrep; SBOM CycloneDX y, sobre el SBOM, vulnerabilidades con Trivy y licencias contra la lista permitida. Sube `security-reports` y `sbom`. Detalle y supresiones en [seguridad](seguridad.md) |
| `Docker image` | `DKR-01` a `DKR-04` | Hadolint sobre el Dockerfile; construye la imagen con el `settings.xml` como secret y la carga en el runner (no la publica); Trivy sobre los paquetes del sistema operativo y los secretos de las capas; políticas TWA con Conftest. Sube `docker-reports`. Detalle en [docker](docker.md) |
| `Repository` | `WFL-01`, `DEP-01`, `GOV-01`, `GOV-02` | zizmor sobre `.github/workflows`; `renovate.json` con el preset y sin Dependabot; las excepciones que agregan los commits nuevos y el formato de todas las supresiones del repo ([seguridad](seguridad.md#suprimir-un-hallazgo)) |
| `twa-standards` | — | Una tabla con todos los controles en su resumen y el artifact `twa-results` (ver [reportes](reportes.md)); falla si falló algún job (un control en `block`) o si un control en `block` quedó sin evaluar |

Cada job deja en su resumen una tabla con el resultado de cada control, y los que fallan en `warn` quedan como
anotación (⚠️) sin fallar el check. Si una herramienta no puede correr (no se baja su imagen, se cae), el control
informa la falla con su severidad: en `warn` avisa, en `block` falla. Cada job tiene `timeout-minutes` (45 el build y
la imagen, 30 `Security`, 15 o menos el resto).

### Diferencias con el `ci.yml` actual de los servicios

| Antes | Ahora |
|---|---|
| Sin revisión del contrato fuera de los tests | Spectral con las convenciones de la plataforma y oasdiff contra la rama principal |
| Sin controles de seguridad | Secretos (bloquea desde el primer día), SAST, SBOM, vulnerabilidades y licencias en `warn` |
| `style` bloquea y `build` espera a `style` | `Code style` y `Build and test` corren en paralelo. El build salta Spotless (`-Dspotless.check.skip=true`): el formato se reporta una vez |
| Sin cobertura | JaCoCo 0.8.16 sin tocar el pom (`prepare-agent` + `report` por línea de comandos), unit e IT juntos |
| El enforcer del pom (si está) | Además, `BLD-03` exige que esté y `BLD-04` corre convergencia de dependencias |
| Actions por tag | Por SHA (y `WFL-01` lo verifica en el repo) |
| Dos formas de armar el `settings.xml` | Una sola, con los tres servers de GitHub Packages |

## Reglas de arquitectura (ARC-01, ARC-02)

Las reglas son las de [twa-layered-rules](https://github.com/andres-sacco/twa-layered-rules) (o twa-hexagonal-rules):
este repo no define ninguna. Cada servicio las corre en su `ArchitectureTest`, dentro de `mvn verify`, y
`java-ci.yml` lee el resultado:

* **ARC-01** lista los ids de las reglas que rompen (`LAY-06 (catalog-service)`) y falla si no corrió ninguna. Una
  regla rota también hace fallar `mvn verify` (BLD-02): bajar la severidad de ARC-01 no evita eso. Para la deuda que
  ya existe se congela la regla con `FreezingArchRule` (README de la librería, § Congelar la deuda); ARC-01 informa
  cuántas violaciones quedan congeladas.
* **ARC-02** exige la versión mínima de la librería (`params.minVersions` de ARC-02 en `config/controls.yml`, hoy
  0.1.0). La mínima sube cuando una major de la librería vuelve obligatoria una regla.

## Cobertura contra la rama principal (TST-02)

En cada push a la rama principal se guarda la cobertura en la cache de Actions
(`twa-coverage-<working-directory>-<rama>-<sha>`); un PR la restaura y compara. La tolerancia es `maxDrop` (default
0,5 puntos). Hasta el primer push a la rama principal con el workflow nuevo no hay contra qué comparar y TST-02 pasa.

El mínimo de TST-01 (default **60 %**) es provisorio: se ajusta con lo que midan los repos en `warn`
(`docs/politica-de-severidades.md`).

## Limitaciones

* PRs desde forks: el workflow hace checkout de este repo en `standards-ref`, que existe; los secrets no llegan, así que
  las librerías de GitHub Packages no se pueden bajar (como hoy).
* `standards-ref` es un input y no la versión con la que se llamó al workflow porque GitHub no expone, dentro de un
  workflow reutilizable, el commit desde el que corre. release-please actualiza su default en cada release. El job
  `Config` lo resuelve a un commit y los demás jobs usan ese commit (`standardsSha` en `twa-results`); que el tag no se
  mueva depende de la protección de tags de este repo ([versionado](versionado.md#tags-inmutables)).
