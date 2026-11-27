# Plan por etapas

La decisión está en [ADR-0013](https://github.com/andres-sacco/twa-platform/blob/main/docs/adr/0013-estandares-de-ingenieria-centralizados.md)
de twa-platform. Los controles y su severidad, en la [política de severidades](politica-de-severidades.md).

| # | Etapa | Entrega | Herramientas (open source) | Estado |
|---|---|---|---|---|
| 0 | Decisión y relevamiento | ADR-0013, [relevamiento](relevamiento.md), [política de severidades](politica-de-severidades.md) | — | Hecha |
| 1 | Base del repo | Estructura, JSON Schema de `.twa-standards.yml`, versionado semver con tags móviles ([versionado](versionado.md)), CI propio, `examples/sample-service` | release-please, actionlint, zizmor, check-jsonschema, shellcheck | Hecha |
| 2 | Build, estilo y tests | `java-ci.yml` (un reutilizable para servicios y librerías) equivalente al `ci.yml` actual, más enforcer, cobertura y zizmor sobre los workflows del repo. Ver [uso](uso.md) | Maven Enforcer, Spotless, Surefire/Failsafe, JaCoCo, action-junit-report, zizmor. Sin PIT: mutation testing consume demasiados recursos para el CI | Hecha |
| 3 | Arquitectura | En `java-ci.yml`: ARC-01 lee de los reportes de los tests qué reglas corrieron y cuáles rompen (con su id); ARC-02 exige la versión mínima de la librería. No define reglas | twa-layered-rules / twa-hexagonal-rules, pom efectivo | Hecha |
| 4 | Seguridad | Secretos, SAST, vulnerabilidades, SBOM, licencias | Gitleaks (CLI), Semgrep CE, SpotBugs + FindSecBugs, Trivy, OSV-Scanner, CycloneDX | — |
| 5 | OpenAPI | Spec exportada en el build, lint con las convenciones de la plataforma, cambios incompatibles contra `main` | springdoc-openapi-maven-plugin, Spectral, oasdiff; Schemathesis más adelante | — |
| 6 | Docker | Lint del Dockerfile, escaneo de la imagen y políticas propias | Hadolint, Trivy, Dockle, Conftest; Cosign y Syft cuando se publiquen imágenes | — |
| 7 | Dependencias | Preset central de Renovate (grupos, actions por SHA, automerge de patch con CI verde) | Renovate | — |
| 8 | Reportes | Resumen por PR, SARIF, escaneo nocturno de todos los repos y tablero central | `$GITHUB_STEP_SUMMARY`, SARIF, Dependency-Track o DefectDojo | — |
| 9 | Despliegue | catalog como piloto; después exchange-rates, proveedores, search, reservations y las librerías. `warn` → `block` según la política | Branch protection, CODEOWNERS | — |

## Estructura objetivo

```
twa-engineering-standards/
├── .github/workflows/        # java-ci.yml (reutilizable: crece con un job por etapa), ci.yml y release.yml (propios)
├── scripts/                  # lo que corren los jobs: read-config, run-control, coverage, maven-settings…
├── config/                   # controls.yml (catálogo) y la configuración de cada herramienta: spectral, hadolint, trivy…
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

## A validar

* Visibilidad de los repos: si son privados, Code Scanning (SARIF) necesita GitHub Advanced Security.
* Renovate como GitHub App o self-hosted.
* Dónde va el tablero de la etapa 8: uno nuevo, `twa-data` o Grafana (`twa-observability`).
