# Despliegue (etapa 9)

Cómo los repos TWA pasan de su `ci.yml` propio a `java-ci.yml`: catalog como piloto y después el resto, de a un repo
por vez. Los controles nuevos entran en `warn`; pasan a `block` en cada repo según la
[política de severidades](politica-de-severidades.md#reglas).

## Orden

| # | Repo | Tipo | Estado | Notas |
|---|---|---|---|---|
| 1 | twa-flights-catalog | service | **Piloto: cambios listos, sin mergear** | Ver [el piloto](#el-piloto-catalog) |
| 2 | twa-flights-exchange-rates | service | — | `amount` y `rate` como `number` en la spec: API-02 lo marca (`twa-amount-as-string`) |
| 3 | twa-flights-provider-alpha / -beta | service | — | Implementan `twa-flights-provider-contract`: misma configuración en los dos |
| 4 | twa-flights-search | service | — | |
| 5 | twa-flights-reservations | service | — | `X-Client-Id` duplicado y operaciones sin descripción en la spec |
| 6 | twa-flights-provider-contract, twa-layered-rules, twa-hexagonal-rules | library | — | Sin imagen ni spec: `DKR-*` y `API-*` no aplican |

Un repo empieza cuando el anterior tuvo al menos un push a `main` con el workflow nuevo y su `twa-standards` en verde.

## Qué hace falta en cada repo

En un PR del repo:

1. `.github/workflows/ci.yml` que llama a `java-ci.yml` ([uso](uso.md#2-githubworkflowsciyml)), con
   `artifact-name`/`artifact-path` si sube el jar y `maven-args` si es multi-módulo.
2. `.twa-standards.yml` con lo que cambia respecto de los defaults. Con la cobertura medida, `TST-01.minLineCoverage`
   unos puntos abajo de lo que mide (así avisa si baja), nunca abajo del default.
3. `renovate.json` con el preset y sin `.github/dependabot.yml` ([dependencias](dependencias.md)).
4. La línea de `karate.write` en su `openapi.feature` ([openapi](openapi.md#api-01-exportar-la-spec)).
5. Lo que los controles encuentren y sea barato de arreglar en el mismo PR; el resto queda en `warn` y se anota en la
   tabla de arriba.
6. README y `CLAUDE.md` del repo: qué corre el CI y qué check mirar.

En la configuración del repo (la hace quien administra el repo, no un PR):

* **Secrets:** `PACKAGES_TOKEN` (ya está en los servicios). `RENOVATE_TOKEN` es de este repo y tiene que tener acceso
  al repo nuevo.
* **Code security:** Dependency graph y Dependabot alerts activados (no las version updates).
* **Branch protection de `main`** (o un ruleset): requerir el check **`ci / twa-standards`**, PR antes de mergear y la
  rama al día. Si exigía los checks del `ci.yml` viejo (`Code style`, `Build and test`), se sacan: dejan de existir
  con ese nombre y el PR quedaría esperando para siempre. Se cambia **después** del primer PR verde con el workflow
  nuevo, para ver el nombre exacto del check.
* Etiqueta `api-breaking-change` creada (la usa API-03 para aprobar un cambio incompatible).

En este repo: agregar el repo a [config/report.yml](../config/report.yml) si no está, y actualizar la tabla de
arriba.

CODEOWNERS no se agrega todavía: con un solo mantenedor, exigir la revisión del dueño impide mergear los PRs propios.
Cuando haya más de una persona, `.twa-standards.yml` y `.github/workflows/` pasan a tener dueño en cada repo, para que
bajar una severidad lo revise alguien más (**a validar**).

## Antes del primer release

Mientras este repo no tenga un release (`v0.1.0`), un repo no puede usar el default de `standards-ref` (`v0.0.0`,
que no existe). El piloto fija el workflow **y** `standards-ref` al mismo commit de `main`:

```yaml
    uses: andres-sacco/twa-engineering-standards/.github/workflows/java-ci.yml@<sha de main> # main
    with:
      standards-ref: <el mismo sha>
```

Con el primer release, el `uses:` pasa al SHA del tag `v0.1.0` (comentario `# v0.1.0`) y se saca `standards-ref`.
Desde ahí lo actualiza Renovate.

El workflow `Release` falla hoy en `release-please` con `Error adding to tree`: el `GITHUB_TOKEN` no puede escribir
aunque el job pida `contents: write`, porque la configuración del repo lo limita a lectura. Se arregla en
**Settings → Actions → General → Workflow permissions**: "Read and write permissions" y "Allow GitHub Actions to
create and approve pull requests" (release-please abre el PR de release). Después, el próximo push a `main` abre el
PR de `v0.1.0`.

## El piloto: catalog

Medido en local el 2026-11-27, con los scripts de este repo sobre la rama del piloto (los de seguridad y Docker, en
las etapas 4 y 6):

| Control | Resultado | Qué se hizo |
|---|---|---|
| `BLD-01`, `BLD-02` | ✅ | — |
| `BLD-03` | ⚠️ → ✅ | No tenía enforcer: se agregó `requireJavaVersion` (`[${java.version},)`) y `requireMavenVersion` (`[3.9,)`) |
| `BLD-04` | ✅ | — |
| `TST-01` | ✅ 84,98 % | `minLineCoverage: 80` en `.twa-standards.yml` |
| `TST-02` | ✅ | Sin línea de base hasta el primer push a `main` |
| `ARC-01`, `ARC-02` | ✅ 76 reglas | — |
| `SEC-01` a `SEC-05` | ✅ | Ver [seguridad](seguridad.md#qué-dio-sobre-los-repos-2026-11-27) |
| `API-01` | ✅ | `karate.write` en `openapi.feature` |
| `API-02` | ⚠️ → ✅ | `info.license` tenía `url` e `identifier` (en OpenAPI 3.1 se excluyen): se sacó `identifier`. Quedan 238 avisos de ejemplos (`instance` sin formato `uri-reference`, entre otros) |
| `API-03` | ✅ | Sin línea de base hasta el primer push a `main` |
| `DKR-01` a `DKR-04` | ✅ | Ver [docker](docker.md) |
| `DEP-01` | ✅ | `renovate.json` |
| `WFL-01` | ✅ | `ci.yml` pasa actionlint y zizmor sin hallazgos |

Falta: el PR en catalog con el workflow corriendo en GitHub, la configuración del repo de arriba y dos semanas (o 10
PRs) en `warn` antes de proponer qué pasa a `block`.
