# Plan por etapas

La decisión está en [ADR-0013](https://github.com/andres-sacco/twa-platform/blob/main/docs/adr/0013-estandares-de-ingenieria-centralizados.md)
de twa-platform. Los controles y su severidad, en la [política de severidades](politica-de-severidades.md).

| # | Etapa | Entrega | Herramientas (open source) | Estado |
|---|---|---|---|---|
| 0 | Decisión y relevamiento | ADR-0013, [relevamiento](relevamiento.md), [política de severidades](politica-de-severidades.md) | — | En curso |
| 1 | Base del repo | Estructura, JSON Schema de `.twa-standards.yml`, versionado semver con tag `v1`, CI propio, `examples/sample-service` | release-please, actionlint, zizmor, check-jsonschema, act | — |
| 2 | Build, estilo y tests | `build-test.yml` equivalente al `ci.yml` actual, composite action del `settings.xml`, cobertura | Maven Enforcer, Spotless, Surefire/Failsafe, JaCoCo, action-junit-report; PIT nocturno opcional | — |
| 3 | Arquitectura | `architecture.yml`: corre el perfil `architecture-rules` y exige la versión mínima de la librería. No define reglas | twa-layered-rules / twa-hexagonal-rules, Maven Enforcer | — |
| 4 | Seguridad | Secretos, SAST, vulnerabilidades, SBOM, licencias | Gitleaks (CLI), Semgrep CE, SpotBugs + FindSecBugs, Trivy, OSV-Scanner, CycloneDX | — |
| 5 | OpenAPI | Spec exportada en el build, lint con las convenciones de la plataforma, cambios incompatibles contra `main` | springdoc-openapi-maven-plugin, Spectral, oasdiff; Schemathesis más adelante | — |
| 6 | Docker | Lint del Dockerfile, escaneo de la imagen y políticas propias | Hadolint, Trivy, Dockle, Conftest; Cosign y Syft cuando se publiquen imágenes | — |
| 7 | Dependencias | Preset central de Renovate (grupos, actions por SHA, automerge de patch con CI verde) | Renovate | — |
| 8 | Reportes | Resumen por PR, SARIF, escaneo nocturno de todos los repos y tablero central | `$GITHUB_STEP_SUMMARY`, SARIF, Dependency-Track o DefectDojo | — |
| 9 | Despliegue | catalog como piloto; después exchange-rates, proveedores, search, reservations y las librerías. `warn` → `block` según la política | Branch protection, CODEOWNERS | — |

## Estructura objetivo

```
twa-engineering-standards/
├── .github/workflows/        # reutilizables (on: workflow_call): java-service.yml, java-library.yml,
│                             # build-test.yml, architecture.yml, openapi.yml, security.yml, docker.yml, report.yml
├── actions/                  # composite actions: maven-settings, setup-java, read-config
├── config/                   # configuración de cada herramienta: spectral, hadolint, trivy, semgrep, gitleaks, conftest
├── renovate/default.json     # preset compartido
├── schema/twa-standards.schema.json
├── examples/sample-service/  # servicio mínimo para probar los workflows
└── docs/                     # un documento por control, con su id
```

## A validar

* Visibilidad de los repos: si son privados, Code Scanning (SARIF) necesita GitHub Advanced Security.
* Renovate como GitHub App o self-hosted.
* Dónde va el tablero de la etapa 8: uno nuevo, `twa-data` o Grafana (`twa-observability`).
