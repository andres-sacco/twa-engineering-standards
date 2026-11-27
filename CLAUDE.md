# twa-engineering-standards

Estándares de ingeniería de los repos TWA: workflows reutilizables de GitHub Actions, la configuración de cada
herramienta y el catálogo de controles con su severidad. La decisión es el ADR-0013 de `../twa-platform`. **Las reglas
de arquitectura no van acá**: están en `../twa-layered-rules` (y `../twa-hexagonal-rules`); este repo las ejecuta.

## Estructura

- `config/controls.yml`: **catálogo de controles**, fuente de verdad de los ids (`BLD-01`, `SEC-03`…), la severidad por
  defecto, la herramienta y la etapa. Un id no se reusa.
- `schema/twa-standards.schema.json`: el formato del `.twa-standards.yml` de cada repo. Casos de prueba en
  `schema/tests/valid` y `schema/tests/invalid` (cada inválido, con un comentario que dice por qué).
- `.github/workflows/java-ci.yml`: **el** workflow reutilizable (servicios y librerías). Un job por grupo de
  controles; cada job hace checkout de este repo en `standards-ref` y corre `scripts/`. No llama a otros reutilizables
  ni a composite actions de este repo (ver `docs/plan.md` § Decisiones de la etapa 2). `ci.yml`, `release.yml` y
  `renovate.yml` (Renovate self-hosted sobre los repos TWA) son de este repo; `ci.yml` corre `java-ci.yml` sobre el
  servicio de prueba.
- `renovate/default.json`: el preset de Renovate de todos los repos TWA (`docs/dependencias.md`). Este repo lo usa en
  su `renovate.json`.
- `scripts/`: `lib.sh` (`report`, versiones de herramientas), `read-config.sh`, `run-control.sh`, un script por control
  que no es un comando de Maven (`check-build-versions.sh`, `check-architecture.sh`, `check-architecture-version.sh`,
  `coverage.sh`, `check-workflows.sh`, `check-renovate.sh`, `check-secrets.sh`, `check-sast.sh`, `check-spotbugs.sh`,
  `sbom.sh`, `check-vulnerabilities.sh`, `check-licenses.sh`), `maven-settings.sh` y `lint.sh`.
- `examples/sample-service/`: servicio mínimo con la forma de los servicios TWA, para probar los workflows. No es una
  plantilla.
- `docs/`: `plan.md` (etapas y estado), `uso.md` (cómo un repo adopta `java-ci.yml`), `seguridad.md` (SEC-*), `dependencias.md` (Renovate),
  `relevamiento.md`, `politica-de-severidades.md`, `versionado.md`.

## Reglas de trabajo

- **Idioma:** español en documentación, comentarios, mensajes de salida y commits. Nombres de herramientas, inputs,
  outputs y claves de YAML en inglés.
- **Un control nuevo** se agrega en `config/controls.yml` y en la tabla de `docs/politica-de-severidades.md` con la
  misma severidad (`make lint` lo compara), entra en `warn` salvo lo que hoy ya bloquea, y termina con
  `report ID SEVERIDAD ok|fail "detalle"` (`scripts/lib.sh`), que es lo que decide si falla. Al terminar una etapa se
  agrega a `implementedStages`, y se actualizan `docs/uso.md` (qué corre) y `docs/plan.md`.
- **Plugins de Maven por línea de comandos** con versión fijada en `env:` de `java-ci.yml`: no se le pide a ningún
  repo que cambie su pom para un control. Las herramientas que corren con Docker (Gitleaks, Trivy) van con versión y
  digest en `scripts/lib.sh`, con su comentario `# renovate:`.
- **Actions fijadas por SHA** con la versión en un comentario (`uses: actions/checkout@<sha> # v7.0.1`),
  `permissions: {}` arriba y lo mínimo por job, con un comentario si es escritura, y `persist-credentials: false`.
  Nada de `${{ }}` dentro de `run:`: pasar por `env:`. zizmor lo verifica.
- **Versiones de herramientas fijadas** (`scripts/lib.sh`, `scripts/lint.sh` y `env:` de `java-ci.yml`), con un
  comentario `# renovate: datasource=… depName=…` en la línea anterior para que Renovate las actualice. Nunca `latest`.
- **Compatibilidad:** lo que hace fallar un build que antes pasaba es un cambio incompatible (`docs/versionado.md`).
- **Sin código de negocio** y sin reglas que pertenezcan a otro repo: las convenciones de las APIs están en
  `../twa-platform/docs/arquitectura.md`; acá solo se automatizan.
- Si cambia algo que afecta a la plataforma (un control que pasa a `block`, un workflow nuevo que adoptan los repos),
  se actualiza `../twa-platform` (README, `docs/pendientes.md`, ADR si cambia la decisión).
- No commitear ni pushear salvo pedido. Commits en Conventional Commits, en español: release-please arma el CHANGELOG
  con ellos.

## Comandos

```bash
make lint           # actionlint, zizmor, schema y sus casos, catálogo contra la política, shellcheck (Docker + uvx o pipx)
make sample         # mvn verify del servicio de prueba (Java 25)
make sample-image   # docker build del servicio de prueba
```

Un cambio está terminado cuando `make lint` pasa y, si toca un workflow o el sample, `make sample` y `make sample-image`
también.
