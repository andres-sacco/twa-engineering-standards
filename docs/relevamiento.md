# Relevamiento: cómo se construyen y validan hoy los repos TWA

Punto de partida de la etapa 0, relevado el 2026-11-26 sobre la rama `main` de cada repo. Sirve para que la etapa 2
reemplace el `ci.yml` de cada repo **sin cambiar lo que ya valida**, y para medir lo que falta.

## Servicios

Los seis heredan de `spring-boot-starter-parent` 4.1.2, compilan con Java 25 (`maven:3.9-eclipse-temurin-25`) y usan
`twa-layered-rules` 0.1.0. Ninguno tiene Maven Wrapper (`mvnw`).

| Repo | Módulos | Tests unit / IT / `.feature` | `ArchitectureTest` | Enforcer | `settings.xml` en CI | Otros |
|---|---|---|---|---|---|---|
| catalog | `catalog-api`, `catalog-service`, `catalog-loader` | 21 / 17 / 22 | service y loader | **no** | `setup-java` (`server-username`) | Testcontainers Mongo |
| exchange-rates | `exchange-rates-api`, `-service`, `-loader` | 18 / 10 / 12 | service y loader | Maven | `setup-java` (`server-username`) | Testcontainers Mongo |
| provider-alpha | uno solo | 8 / 6 / 8 | sí | Maven, Java | `maven-settings.sh` | Microcks (Testcontainers), contract 0.5.0 |
| provider-beta | uno solo | 8 / 6 / 8 | sí | Maven, Java | `maven-settings.sh` | Microcks (Testcontainers), contract 0.5.0 |
| search | `search-api`, `search-service` | 16 / 5 / 10 | service | Maven | `maven-settings.sh` | Testcontainers Mongo, contract 0.5.0 |
| reservations | `reservations-api`, `reservations-service` | 21 / 8 / 14 | service | Maven, Java | `maven-settings.sh` | Testcontainers Mongo, contract 0.5.0 |

Tests unit: `*Test.java` (Surefire). IT: `*IT.java` en `src/it` (Failsafe, con Karate y Testcontainers). Los conteos
son de archivos, no de casos.

### CI de los servicios (`.github/workflows/ci.yml`)

Igual en los seis, salvo el armado del `settings.xml`:

| Job | Qué hace | Bloquea |
|---|---|---|
| `style` | `mvn spotless:check` | sí |
| `build` (después de `style`) | `mvn verify`: unit, IT y reglas de arquitectura (perfil `architecture-rules`). Sube los reportes si falla y el jar ejecutable | sí |
| `image` (después de `style`) | Construye la imagen con Buildx y cache de GHA, **sin publicarla**. El `settings.xml` entra como secret de build | sí |

* Dispara en `push` a `main` y en `pull_request`, con `concurrency` que cancela la corrida anterior.
* `permissions: contents: read`. Actions por tag (`checkout@v4`, `setup-java@v4`, `upload-artifact@v4`,
  `setup-buildx-action@v3`, `build-push-action@v6`), no por SHA.
* GitHub Packages necesita el secret `PACKAGES_TOKEN` (token clásico con `read:packages`): el `GITHUB_TOKEN` no lee
  paquetes de otro repo.

### Dockerfile

Igual en los seis: build multi-stage con `maven:3.9-eclipse-temurin-25`, el `settings.xml` como `--mount=type=secret`
(no queda en la imagen), jar separado en capas, runtime `eclipse-temurin:25-jre`, usuario `app` (uid 1001) sin
privilegios, `MaxRAMPercentage=75` y `HEALTHCHECK` contra el liveness de Actuator por `/dev/tcp`. El build salta tests,
reglas de arquitectura y Spotless (ya corren en el job `build`).

## Librerías

| Repo | Java (`release`) | CI | Release | Dependabot |
|---|---|---|---|---|
| twa-flights-provider-contract | 17 | `verify` | `release.yml` | no |
| twa-layered-rules | 11 | `verify` | `release.yml` manual (`workflow_dispatch` con la versión): tag, GitHub Packages y release | Maven y Actions, semanal |
| twa-hexagonal-rules | 11 | `verify` | igual que layered-rules | Maven y Actions, semanal |

Usan actions más nuevas que los servicios (`checkout@v7`, `setup-java@v6`, `upload-artifact@v7`); provider-contract
mezcla `@v4` y `@v7`.

## Qué no se valida hoy en ningún repo

| Tema | Situación |
|---|---|
| Cobertura | Sin JaCoCo: no se mide |
| Secretos | Sin escaneo |
| Vulnerabilidades de dependencias | Sin escaneo; sin SBOM |
| Licencias de dependencias | Sin control |
| Código (SAST) | Sin análisis |
| Contrato OpenAPI | springdoc lo genera en tiempo de ejecución; no hay spec versionada, ni lint, ni detección de cambios incompatibles |
| Dockerfile e imagen | Se construye; no se analiza el Dockerfile ni las vulnerabilidades de la imagen |
| Actualización de dependencias | Solo los dos repos de reglas (Dependabot); los servicios y provider-contract, no |
| Workflows | Sin actionlint ni análisis de seguridad; actions sin fijar por SHA |

## Divergencias para resolver en la etapa 2

1. Dos formas de armar el `settings.xml` (`setup-java` en catalog y exchange-rates, `maven-settings.sh` en el resto):
   pasa a una composite action.
2. catalog no tiene `maven-enforcer-plugin`; el resto exige Maven y, algunos, Java: pasa a ser el control `BLD-03`.
3. Versiones de las actions distintas entre servicios y librerías: se unifican y se fijan por SHA (`WFL-01`).

## Medición con `java-ci.yml` (etapa 2)

Los pasos del job `Build and test` corridos en local sobre `main` de catalog, con un `.twa-standards.yml` mínimo
(2026-11-27):

| Control | Resultado |
|---|---|
| `BLD-01` Spotless | ✅ |
| `BLD-02` build y tests | ✅ 81 tests unitarios y 9 IT del loader, más los del service |
| `BLD-03` versiones exigidas | ⚠️ sin `maven-enforcer-plugin` (requireJavaVersion, requireMavenVersion) |
| `BLD-04` convergencia | ✅ |
| `TST-01` cobertura de líneas | ✅ **84,98 %** (catalog-service 81,7 %, catalog-loader 90,3 %) |

zizmor (`WFL-01`) sobre el CI actual: catalog y search tienen 9 actions sin fijar por SHA y 3 checkouts con
credenciales persistidas; twa-layered-rules, 5 y 2. Se resuelve al reemplazar el `ci.yml` por la llamada a
`java-ci.yml`, salvo los `release.yml` de las librerías.
