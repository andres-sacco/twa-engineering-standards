# Plan por etapas

La decisión está en [ADR-0013](https://github.com/andres-sacco/twa-platform/blob/main/docs/adr/0013-estandares-de-ingenieria-centralizados.md)
de twa-platform. Los controles y su severidad, en la [política de severidades](politica-de-severidades.md).

| # | Etapa | Entrega | Herramientas (open source) | Estado |
|---|---|---|---|---|
| 0 | Decisión y relevamiento | ADR-0013, [relevamiento](relevamiento.md), [política de severidades](politica-de-severidades.md) | — | Hecha |
| 1 | Base del repo | Estructura, JSON Schema de `.twa-standards.yml`, versionado semver con tags móviles ([versionado](versionado.md)), CI propio, `examples/sample-service` | release-please, actionlint, zizmor, check-jsonschema, shellcheck | Hecha |
| 2 | Build, estilo y tests | `java-ci.yml` (un reutilizable para servicios y librerías) equivalente al `ci.yml` actual, más enforcer, cobertura y zizmor sobre los workflows del repo. Ver [uso](uso.md) | Maven Enforcer, Spotless, Surefire/Failsafe, JaCoCo, action-junit-report, zizmor. Sin PIT: mutation testing consume demasiados recursos para el CI | Hecha |
| 3 | Arquitectura | En `java-ci.yml`: ARC-01 lee de los reportes de los tests qué reglas corrieron y cuáles rompen (con su id); ARC-02 exige la versión mínima de la librería. No define reglas | twa-layered-rules / twa-hexagonal-rules, pom efectivo | Hecha |
| 4 | Seguridad | Job `Security` en `java-ci.yml`: secretos en archivos y commits, SAST, SBOM, vulnerabilidades y licencias sobre el SBOM. Ver [seguridad](seguridad.md) | Gitleaks, Semgrep CE, SpotBugs + FindSecBugs, CycloneDX, Trivy. Sin OSV-Scanner ni SonarQube | Hecha |
| 5 | OpenAPI | En `java-ci.yml`: la spec que exporta el `OpenApiIT` de cada servicio, Spectral con las reglas `twa-*` y oasdiff contra la rama principal (se aprueba con la etiqueta `api-breaking-change`). Ver [openapi](openapi.md) | springdoc + OpenApiIT, Spectral, oasdiff; Schemathesis más adelante | Hecha |
| 6 | Docker | En el job `Docker image`: Hadolint, la imagen construida y cargada en el runner, Trivy sobre los paquetes del sistema operativo y los secretos de las capas, y las políticas TWA con Conftest. Ver [docker](docker.md) | Hadolint, Trivy, Conftest. Sin Dockle; Cosign y Syft cuando se publiquen imágenes | Hecha |
| 7 | Dependencias | Preset central de Renovate (grupos, 3 días de espera, actions e imágenes por digest, automerge de patch con CI verde), Renovate self-hosted en `renovate.yml` y DEP-01. Ver [dependencias](dependencias.md) | Renovate, renovate-config-validator | Hecha |
| 8 | Reportes | Una tabla con todos los controles en el job `twa-standards` y el artifact `twa-results`; tablero con el último push de cada repo (`make report`). Sin escaneo nocturno. Ver [reportes](reportes.md) | `$GITHUB_STEP_SUMMARY`, artifacts, jq | Hecha |
| 9 | Despliegue | catalog como piloto; después exchange-rates, proveedores, search, reservations y las librerías. `warn` → `block` según la política. Ver [despliegue](despliegue.md) | Branch protection (check `ci / twa-standards`). CODEOWNERS cuando haya más de un mantenedor | En curso: piloto con catalog |
| 10 | Gobernanza de excepciones | En el job `Repository`: GOV-01 avisa las supresiones y las severidades que agrega cada PR; GOV-02 verifica que tengan razón y vencimiento. `standards-ref` se resuelve a un commit una vez por corrida. Ver [seguridad](seguridad.md#suprimir-un-hallazgo) | git, yq | Hecha |

## Estructura objetivo

```
twa-engineering-standards/
├── .github/workflows/        # java-ci.yml (reutilizable: crece con un job por etapa), ci.yml y release.yml (propios)
├── scripts/                  # lo que corren los jobs: read-config, run-control, coverage, maven-settings…
├── config/                   # controls.yml (catálogo) y la configuración de cada herramienta: spectral, conftest, spotbugs…
├── renovate/default.json     # preset compartido
├── schema/twa-standards.schema.json
├── examples/sample-service/  # servicio mínimo para probar los workflows
└── docs/                     # plan, relevamiento, política, uso, versionado
```

## Decisiones de la etapa 2

* **Un solo workflow reutilizable** (`java-ci.yml`) en lugar de `java-service.yml` + `java-library.yml` + uno por
  tema: un reutilizable que llama a otro con `./` lo resuelve contra el repo que llama, no contra este. El tipo de repo
  sale de `.twa-standards.yml` y los controles que no aplican quedan en `off`.
* **Scripts en lugar de composite actions:** cada job hace checkout de este repo en `standards-ref` y corre
  `scripts/*.sh`. Una composite action referida desde un reutilizable necesitaría un `@ref` fijo, que no se puede
  probar en el PR que la cambia.
* **Los plugins se agregan por línea de comandos** (JaCoCo, enforcer): no hace falta tocar el pom de ningún repo.
* **Sin PIT**: el mutation testing quedó fuera por el consumo de recursos.

## Decisiones de la etapa 3

* **Las reglas no se corren dos veces:** ya corren en `mvn verify` (el `ArchitectureTest` de cada servicio, perfil
  `architecture-rules`). ARC-01 lee los reportes de Surefire: cada caso de ArchUnit se llama
  `TwaCoreRules > TwaLayerRules > LAY_01`, de ahí sale el id. Un repo sin reglas que corran (sin test, sin dependencia
  o con `-DskipArchitectureRules`) falla ARC-01 aunque los tests pasen.
* **ARC-01 no reemplaza a BLD-02:** una regla rota hace fallar `mvn verify`, así que BLD-02 falla igual. Para no
  bloquear por deuda existente se usa el mecanismo de la librería (`FreezingArchRule`), no la severidad; ARC-01 informa
  cuántas violaciones quedan congeladas en `archunit_store`.
* **La versión mínima vive en el catálogo** (`params.minVersions` de ARC-02), no en el pom de cada repo. Los params
  por defecto de todos los controles pasaron al catálogo: `read-config.sh` combina encima los del repo.
* **`architecture: layered | hexagonal`** en `.twa-standards.yml` (default `layered`, ADR-0001) elige la librería.
* El servicio de prueba usa `twa-layered-rules`: el CI de este repo necesita el secret `PACKAGES_TOKEN`.

## Decisiones de la etapa 4

* **SonarQube afuera.** La edición Community no analiza PRs ni ramas (no puede bloquear un PR), necesita un servidor
  propio, y lo que cubriría de esta etapa (SAST) ya lo hacen Semgrep y SpotBugs. Si hace falta un tablero, entra en la
  etapa 8 leyendo los SARIF.
* **El SBOM es la entrada de SEC-03 y SEC-05:** lo arma Maven con las versiones reales, incluidas las librerías TWA
  privadas. Trivy y la lista de licencias no vuelven a resolver el pom.
* **Sin OSV-Scanner:** sobre catalog encontró lo mismo que Trivy; los dos duplicaban los reportes.
* **Licencias con lista permitida propia** (`params.allowedLicenses` de SEC-05), no la clasificación de Trivy: una
  doble licencia pasa si una de las dos está permitida. Con Trivy, catalog tenía 6 falsos positivos.
* **SpotBugs en `Build and test`**, sobre lo que ya compiló `verify`; Semgrep, Gitleaks y el SBOM en un job
  `Security` en paralelo. Los dos reportan como `SEC-02`.
* **Gitleaks y Trivy con Docker, fijados por digest**; el `customManager` del preset ahora actualiza también el
  digest (`VERSION="x.y.z@sha256:…"`).

## Decisiones de la etapa 5

* **La spec la exporta el `OpenApiIT`** que ya tienen los seis servicios (una línea de `karate.write`), no
  `springdoc-openapi-maven-plugin`: el plugin levanta la app aparte y la app necesita Mongo. El IT ya la levanta con
  Testcontainers.
* **Un ruleset propio** (`config/spectral/twa.yaml`) que extiende el recomendado de Spectral: las reglas `twa-*` en
  `error` son las convenciones de `docs/arquitectura.md` de twa-platform que se ven en la spec. Lo que es
  comportamiento (cifrado, logs, idempotencia de cada operación) queda afuera.
* **Ejemplos inválidos en `warn`:** en catalog había 238, todos de documentación.
* **API-03 contra la cache**, como TST-02: la spec de la rama principal se guarda en cada push. Un cambio incompatible
  a propósito se aprueba con la etiqueta `api-breaking-change`.
* Un repo apaga una regla en `params.disabledRules` de API-02, con la razón; no con un ruleset propio.

## Decisiones de la etapa 6

* **Sin Dockle:** no tiene releases desde enero de 2025. Sus chequeos los cubren Conftest y el escaneo de secretos de
  Trivy sobre las capas.
* **DKR-03 solo mira el sistema operativo** (`--pkg-types os`): las dependencias Java son SEC-03, sobre el SBOM. Así
  una vulnerabilidad no se reporta dos veces.
* **Las políticas TWA miran el Dockerfile** (Conftest, `config/conftest/dockerfile.rego`): el mensaje dice qué
  instrucción cambiar y la política se prueba en `make lint` sin construir. Los secretos se buscan en la imagen.
* **La imagen se carga en el runner** (`load: true`) para escanearla; sigue sin publicarse.
* Un repo exceptúa una política en `params.exceptions` de DKR-04, con la razón.

## Decisiones de la etapa 8

* **Sin escaneo nocturno.** Las vulnerabilidades nuevas en repos que no cambian las cubren las alertas de Dependabot
  con el PR inmediato de Renovate, y las actualizaciones de la imagen base por digest. El tablero muestra el último
  push de cada repo.
* **Cada control deja su resultado en JSON** (`record` en `lib.sh`) y el job `twa-standards` los junta en una tabla y
  en el artifact `twa-results`: el resumen del PR y la fuente del tablero son lo mismo.
* **Sin Dependency-Track ni DefectDojo:** piden un servidor. El tablero es un script que lee los artifacts.
* **Nada se publica en este repo:** es público y el tablero tiene hallazgos de repos privados. Por lo mismo, el SARIF
  no va a Code Scanning (necesitaría GitHub Advanced Security en los privados).

## Decisiones de la etapa 7

* **Renovate self-hosted** en un workflow de este repo, no la GitHub App: todo open source y corriendo en Actions,
  como pide el ADR-0013. La App queda como alternativa (docs/dependencias.md).
* **Solo los repos con `renovate.json`** (`RENOVATE_REQUIRE_CONFIG=required`): la adopción es repo por repo en la
  etapa 9, no un PR de onboarding en cada `twa-*`.
* **3 días de espera** para versiones de terceros (cadena de suministro), salvo seguridad, librerías TWA e imágenes.
* **Automerge solo de patch de terceros e imágenes base**, y solo si la rama exige `ci / twa-standards`.
* Las versiones fijadas en scripts y workflows llevan un comentario `# renovate:` y las actualiza un `customManager`
  del preset: este repo se mantiene con su propio preset.
* Las etapas 4 a 6 seguían pendientes: `implementedStages` del catálogo reemplaza a un número de etapa.

## Decisiones de la etapa 10

Salen de una auditoría del pipeline (2026-11-28): con un solo mantenedor nadie revisa el PR que suprime un hallazgo o
baja una severidad, y el SHA que fija cada repo no fijaba los scripts.

* **GOV-01 avisa, no bloquea:** una supresión con razón es legítima. El aviso (⚠️ en el resumen y una anotación por
  excepción) es lo que hace que se mire. Cuenta los archivos de supresión, `archunit_store` (violaciones congeladas),
  los `nosemgrep` y `hadolint ignore` agregados y los controles de `.twa-standards.yml` con menos severidad o con otros
  params.
* **GOV-02 verifica el formato de la regla 4:** `statement` y `expired_at` en `.trivyignore.yaml`, un comentario antes
  de cada línea de `.gitleaksignore`, `.semgrepignore` y de cada `<Match>` de `spotbugs-exclude.xml`, la razón al lado
  de `nosemgrep` y `hadolint ignore`, y `until` sin vencer en `.twa-standards.yml`. `until` es opcional: hay excepciones
  permanentes (un servicio sin base de datos).
* **`standards-ref` se resuelve a un commit en el job `Config`** y los demás jobs usan ese commit: todos corren los
  mismos scripts aunque el tag se mueva a mitad de la corrida, y `twa-results` lo registra (`standardsSha`). Que el tag
  no se mueva lo garantiza GitHub (releases inmutables o un ruleset sobre `refs/tags/v*.*.*`, ver
  [versionado](versionado.md#tags-inmutables)), no el workflow: release-please no puede escribir el SHA del release en
  el PR que lo crea.
* **El automerge del preset se limita a las imágenes de los Dockerfile** (manager `dockerfile`), y este repo no
  mergea nada solo (`renovate.json`): una herramienta o una action nueva cambia el CI de todos los repos.

## A validar

* CODEOWNERS en cada repo cuando haya más de un mantenedor.

* Dónde se publica el tablero de la etapa 8 (`report.json`): un workflow en un repo privado, `twa-data`/Metabase o
  solo local.
