# TWA Engineering Standards

[![CI](https://github.com/andres-sacco/twa-engineering-standards/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/andres-sacco/twa-engineering-standards/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

El CI común de los repos TWA: un workflow reutilizable de GitHub Actions (`java-ci.yml`) que construye, testea y revisa
cada servicio y cada librería con 22 controles, todos con herramientas open source. Cada repo declara en un archivo
qué cambia respecto de los defaults; el resto es igual para todos.

La decisión está en
[ADR-0013](https://github.com/andres-sacco/twa-platform/blob/main/docs/adr/0013-estandares-de-ingenieria-centralizados.md)
de twa-platform. Las reglas de arquitectura **no** están acá: siguen en
[twa-layered-rules](https://github.com/andres-sacco/twa-layered-rules); este repo las ejecuta y reporta.

**Estado:** etapas 0 a 8 terminadas ([plan](docs/plan.md)). Ningún repo lo usa todavía: el piloto con catalog es la
etapa 9.

## Qué revisa

Cada control tiene un id estable y una severidad: `block` hace fallar el check, `warn` lo informa sin fallar, `off`
no corre ([política de severidades](docs/politica-de-severidades.md)). Un control nuevo entra en `warn`, salvo lo que
ya bloqueaba antes.

| Área | Controles | Herramientas | Default | Detalle |
|---|---|---|---|---|
| Build y estilo | `BLD-01` a `BLD-04` | Maven, Spotless, Maven Enforcer | `BLD-01`, `BLD-02` block; el resto warn | [uso](docs/uso.md) |
| Tests | `TST-01`, `TST-02` | JaCoCo (cobertura mínima y contra la rama principal) | warn | [uso](docs/uso.md#cobertura-contra-la-rama-principal-tst-02) |
| Arquitectura | `ARC-01`, `ARC-02` | twa-layered-rules / twa-hexagonal-rules (ArchUnit) | `ARC-01` block; `ARC-02` warn | [uso](docs/uso.md#reglas-de-arquitectura-arc-01-arc-02) |
| Seguridad | `SEC-01` a `SEC-05` | Gitleaks, Semgrep, SpotBugs + FindSecBugs, CycloneDX, Trivy | `SEC-01` (secretos) block; el resto warn | [seguridad](docs/seguridad.md) |
| OpenAPI | `API-01` a `API-03` | Spectral (reglas `twa-*`), oasdiff | warn | [openapi](docs/openapi.md) |
| Docker | `DKR-01` a `DKR-04` | Buildx, Hadolint, Trivy, Conftest (políticas TWA) | `DKR-01` block; el resto warn | [docker](docs/docker.md) |
| Repositorio | `DEP-01`, `WFL-01` | Renovate, zizmor | warn | [dependencias](docs/dependencias.md) |

La lista completa, con la herramienta y los parámetros de cada uno, está en [config/controls.yml](config/controls.yml).

### Cómo corre

```
config ─┬─ style       BLD-01
        ├─ build       BLD-02..04, TST-*, ARC-*, SEC-02 (SpotBugs), API-*
        ├─ security    SEC-01..05
        ├─ image       DKR-*
        └─ repository  DEP-01, WFL-01
                 └──→ twa-standards   una tabla con todos los controles; falla si falló uno en block
```

`twa-standards` es el check que se exige en la protección de la rama principal. Además deja el artifact
`twa-results`, del que sale el tablero de todos los repos (`make report`, ver [reportes](docs/reportes.md)).

## Cómo lo adopta un repo

1. Un `.twa-standards.yml` en la raíz, con lo que cambia respecto de los defaults (lo valida un
   [JSON Schema](schema/twa-standards.schema.json)):

   ```yaml
   # yaml-language-server: $schema=https://raw.githubusercontent.com/andres-sacco/twa-engineering-standards/main/schema/twa-standards.schema.json
   version: 1
   type: service        # service | library
   java: "25"
   controls:
     TST-01:
       params:
         minLineCoverage: 45   # el default es 60
     DKR-03:
       severity: "off"
       reason: Explicación de por qué este repo lo apaga
   ```

2. Su `.github/workflows/ci.yml` llama a `java-ci.yml`, fijado por SHA con la versión en el comentario:

   ```yaml
   name: CI
   on:
     push:
       branches: [main]
     pull_request:
   permissions: {}
   jobs:
     ci:
       permissions:
         contents: read
       uses: andres-sacco/twa-engineering-standards/.github/workflows/java-ci.yml@<sha> # v0.1.0
       secrets:
         PACKAGES_TOKEN: ${{ secrets.PACKAGES_TOKEN }}
   ```

3. Lo demás:
   * un `renovate.json` que extiende el preset, y sin Dependabot para las versiones ([dependencias](docs/dependencias.md));
   * una línea de `karate.write` en su `OpenApiIT` para exportar la spec ([openapi](docs/openapi.md#api-01-exportar-la-spec));
   * Dependency graph y Dependabot alerts activados en la configuración del repo;
   * el check `ci / twa-standards` requerido en la protección de `main`;
   * el repo agregado a [config/report.yml](config/report.yml), para que aparezca en el tablero.

Inputs, diferencias con el CI actual y limitaciones: [docs/uso.md](docs/uso.md).

## Secrets

| Secret | Dónde | Para qué |
|---|---|---|
| `PACKAGES_TOKEN` | Cada repo que adopta `java-ci.yml` (y este) | Token clásico con `read:packages`: las librerías TWA de GitHub Packages |
| `RENOVATE_TOKEN` | Este repo | Renovate self-hosted: ramas, PRs e issues en los repos `twa-*` ([dependencias](docs/dependencias.md#renovate-self-hosted)) |
| `TWA_REPORT_TOKEN` | Local (variable de entorno) | `make report`: lectura de Actions en los repos del tablero ([reportes](docs/reportes.md#el-tablero)) |

## Comandos

```bash
make help           # lista los comandos
make lint           # workflows (actionlint, zizmor), schema, catálogo, reglas de Spectral y Conftest, scripts
make sample         # compila y testea el servicio de prueba (Java 25)
make sample-image   # construye su imagen
make report         # tablero con el último resultado de cada repo (TWA_REPORT_TOKEN)
```

## Documentación

| Documento | Qué responde |
|---|---|
| **Adoptarlo** | |
| [docs/uso.md](docs/uso.md) | Cómo un repo adopta `java-ci.yml`: su `ci.yml`, inputs, qué corre y qué cambia respecto del CI actual |
| **Qué revisa cada área** | |
| [docs/seguridad.md](docs/seguridad.md) | Secretos, SAST, SBOM, vulnerabilidades y licencias: herramientas, reportes, cómo suprimir un hallazgo |
| [docs/openapi.md](docs/openapi.md) | El contrato OpenAPI: cómo se exporta la spec, las reglas de Spectral, los cambios incompatibles y cómo aprobarlos |
| [docs/docker.md](docs/docker.md) | La imagen: Hadolint, vulnerabilidades de la base, las políticas TWA de Conftest y cómo exceptuarlas |
| [docs/dependencias.md](docs/dependencias.md) | El preset de Renovate: cómo lo adopta un repo, grupos, automerge, Renovate self-hosted y sus secrets |
| **Operación** | |
| [docs/reportes.md](docs/reportes.md) | El resumen de cada PR, el artifact `twa-results`, el tablero y por qué no hay escaneo nocturno |
| [docs/politica-de-severidades.md](docs/politica-de-severidades.md) | Qué significa `off`, `warn` y `block`, cuándo un control pasa a bloquear y el catálogo de controles |
| [docs/versionado.md](docs/versionado.md) | Tags, qué es un cambio incompatible y cómo se publica un release |
| **Contexto** | |
| [docs/plan.md](docs/plan.md) | Las etapas, qué entrega cada una, con qué herramientas y las decisiones de cada una |
| [docs/relevamiento.md](docs/relevamiento.md) | Cómo se construían y validaban los repos TWA antes de este repo, y qué faltaba |

## Cómo se cambia

* **Un control nuevo** va en [config/controls.yml](config/controls.yml) y en la tabla de la
  [política de severidades](docs/politica-de-severidades.md) con la misma severidad, entra en `warn` y termina con
  `report ID SEVERIDAD ok|fail "detalle"` (`scripts/lib.sh`): así aparece en el resumen y en el tablero.
* **Una regla de Spectral o una política de Conftest** va con su caso en `config/spectral/tests/` o
  `config/conftest/tests/`.
* **Las versiones** de las herramientas están fijadas (por SHA o digest) con un comentario `# renovate:`, y las
  actualiza el mismo preset de Renovate.
* Todo cambio pasa `make lint`. Los commits van en español con Conventional Commits: release-please arma la versión y
  el changelog ([versionado](docs/versionado.md)). El detalle, en [CLAUDE.md](CLAUDE.md).

## Licencia

[MIT](LICENSE).
