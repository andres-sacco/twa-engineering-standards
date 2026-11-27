# Actualización de dependencias (DEP-01)

Un solo preset de Renovate ([renovate/default.json](../renovate/default.json)) define cómo se actualizan las
dependencias de todos los repos TWA, y un workflow de este repo ([renovate.yml](../.github/workflows/renovate.yml)) corre
Renovate self-hosted (open source, sin servicio externo) sobre los repos que lo adoptaron.

## Cómo lo adopta un repo

1. Un `renovate.json` en la raíz:

   ```json
   {
     "$schema": "https://docs.renovatebot.com/renovate-schema.json",
     "extends": ["github>andres-sacco/twa-engineering-standards//renovate/default"]
   }
   ```

   Lo propio del repo va abajo del `extends` (una regla más, un paquete ignorado), no una copia del preset.
2. Se borra `.github/dependabot.yml` si actualiza Maven, Actions o Docker: abriría los mismos PRs dos veces.
3. El token de Renovate (`RENOVATE_TOKEN`) tiene que llegar al repo (ver abajo).

`DEP-01` (en el job `Repository` de `java-ci.yml`) verifica los dos primeros puntos. Renovate solo procesa los repos
que tienen su `renovate.json` (`RENOVATE_REQUIRE_CONFIG=required`): no abre PRs de onboarding en todos los `twa-*`.

## Qué hace el preset

| Qué | Cómo |
|---|---|
| Cuándo | Los lunes antes de las 7 (hora de Buenos Aires), como máximo 8 PRs abiertos y 4 por hora. Los arreglos de seguridad (alertas de vulnerabilidad de GitHub) salen enseguida, con etiqueta `security` |
| Antigüedad mínima | Una versión nueva de terceros espera **3 días** antes del PR: protege de un release malicioso o retirado. Sin espera: las librerías TWA, twa-engineering-standards, los arreglos de seguridad y las imágenes de Docker (no informan la fecha) |
| Grupos | `Spring Boot`; `plugins de Maven`; `dependencias de test`; `librerías TWA` (twa-layered-rules, twa-hexagonal-rules, provider-contract); `twa-engineering-standards`; `GitHub Actions` (una vez por mes); `imágenes base` |
| Versiones mayores | Necesitan aprobación en el Dependency Dashboard (un issue que Renovate mantiene en cada repo). Java 26 en las imágenes base es una decisión de arquitectura (ADR-0003) |
| Automerge | Solo **patch de terceros** e **imágenes base** (digest y patch), cuando el check requerido de la rama pasa. Nunca las librerías TWA ni `java-ci.yml`: pueden cambiar el resultado del CI a propósito |
| Fijado | Las actions y las imágenes de Docker se fijan por digest (`helpers:pinGitHubActionDigests`, `docker:pinDigests`), con la versión en el comentario |
| Versiones en scripts | Una línea `# renovate: datasource=… depName=…` antes de `VAR="x.y.z"` o `var: x.y.z` hace que Renovate la actualice (así se actualizan las herramientas de este repo: zizmor, actionlint, JaCoCo, el enforcer, Renovate) |
| Commits | `chore(deps): actualiza <dependencia> a <versión>` |

El automerge depende de que la rama principal **exija** el check `ci / twa-standards`: sin protección de rama, un
patch se mergearía aunque el CI falle.

## Renovate self-hosted

`renovate.yml` corre cada 6 horas (y a mano desde Actions) con la versión de Renovate fijada, y recorre los
`andres-sacco/twa-*` a los que llega el token. Necesita dos secrets en **este** repo:

| Secret | Qué es |
|---|---|
| `RENOVATE_TOKEN` | Token que puede leer y escribir en los repos TWA: crear ramas, abrir PRs e issues, leer las alertas de vulnerabilidad. Un fine-grained PAT con Contents, Pull requests, Issues, Workflows y Commit statuses (el check `renovate/stability-days` de la espera de 3 días) en lectura y escritura, y Dependabot alerts en lectura, sobre los repos `twa-*`; mejor, el token de una GitHub App propia |
| `PACKAGES_TOKEN` | El mismo que usa el CI: para que Renovate vea las versiones nuevas de las librerías TWA en GitHub Packages |

Alternativa sin workflow: la GitHub App de Renovate (Mend), gratis. Usa el mismo preset; las librerías de GitHub
Packages necesitan un secret cifrado en el `renovate.json` (**a validar** si se prefiere a self-hosted).

## Probarlo sin abrir PRs

En la raíz de un repo, con el preset local y sin tocar GitHub:

```bash
LOG_LEVEL=debug LOG_FORMAT=json RENOVATE_CONFIG_FILE=<ruta a renovate/default.json> \
  npx --package renovate@44.236.5 -- renovate --platform=local --dry-run=lookup --require-config=ignored --onboarding=false
```

Sobre catalog (2026-11-27) agrupó `spring-boot` (4.1.2 → 4.2.0), `plugins-de-maven` (Spotless, build-helper),
`imagenes-base` (fijar los digest), MapStruct y springdoc, y dejó Mongo 7 → 9 (major, en `docker-compose-local.yml`)
esperando aprobación.

## A validar

* La zona horaria (`America/Argentina/Buenos_Aires`) y el horario de los lunes.
* GitHub App propia o PAT para `RENOVATE_TOKEN`.
