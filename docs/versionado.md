# Versionado

Los repos TWA consumen `java-ci.yml` **por el SHA de un release**, con la versión en un comentario
(`java-ci.yml@<sha> # v0.1.0`, ver [uso](uso.md)): así cumplen su propio `WFL-01`. Un cambio acá llega a un repo cuando
ese repo sube la versión que usa (Renovate abre el PR, etapa 7).

## Tags

| Tag | Qué es | Quién lo usa |
|---|---|---|
| `vX.Y.Z` | Un release, fijo. Lo crea release-please | Su SHA es el que fijan los consumidores; también es el `standards-ref` de ese release |
| `vX.Y` | Móvil: apunta al último `vX.Y.Z` | Para ver cuál es el último release de una línea; un repo que acepte no fijar por SHA (apagando `WFL-01` con razón) |
| `vX` | Móvil: apunta al último `vX.Y.Z` | Ídem, desde `1.0.0` |

Los tags móviles los mueve `.github/workflows/release.yml` después de cada release.

### Tags inmutables

Los repos fijan `java-ci.yml` por SHA, pero los scripts y el catálogo salen del tag `vX.Y.Z` (`standards-ref`): si
alguien moviera ese tag, cambiaría el CI de todos los repos sin que cambie ningún SHA. Por eso los `vX.Y.Z` de este
repo no se pueden mover ni borrar. Se configura una vez, con permisos de administración:

* **Releases inmutables** (Settings → General → Releases → *Enable release immutability*): el tag de cada release
  publicado queda fijo. O, si no está disponible,
* **un ruleset de tags** que restringe actualizar y borrar `refs/tags/v*.*.*` (no alcanza a `vX` ni `vX.Y`, que
  `release.yml` mueve):

  ```bash
  gh api -X POST repos/andres-sacco/twa-engineering-standards/rulesets --input - <<'JSON'
  {"name": "Tags de release inmutables", "target": "tag", "enforcement": "active",
   "conditions": {"ref_name": {"include": ["refs/tags/v*.*.*"], "exclude": []}},
   "rules": [{"type": "update"}, {"type": "deletion"}]}
  JSON
  ```

El job `Config` de `java-ci.yml` resuelve el tag a un commit una vez por corrida y lo deja en `twa-results`
(`standardsSha`): todos los jobs corren lo mismo, y se puede ver qué commit corrió.

**Mientras la versión sea `0.x`** (hasta que termine el piloto de la etapa 9) un cambio incompatible sube el minor, no
el major (`bump-minor-pre-major`): un repo que siga un tag móvil usa `@v0.Y`, no `@v0`.

## Qué es un cambio incompatible

Hace subir el major (el minor en `0.x`) todo lo que puede hacer fallar un build que antes pasaba o que obliga a cambiar
el repo consumidor:

* Sacar o renombrar un workflow reutilizable, un input, un output o un secret; agregar un input o un secret obligatorio.
* Subir el default de un control de `warn` a `block` (ver la [política de severidades](politica-de-severidades.md)).
* Cambiar el formato de `.twa-standards.yml` de forma que un archivo válido deje de serlo (`version` sube a `2`).
* Subir la versión de Java por defecto.

Agregar un control nuevo en `warn`, un input opcional o una regla de una herramienta que solo avisa **no** es
incompatible.

## Cómo se publica un release

1. Los commits a `main` siguen Conventional Commits (`feat:`, `fix:`, `docs:`…; `feat!:` o `BREAKING CHANGE:` para un
   cambio incompatible). Los PR se mergean con squash, con el título del PR como mensaje.
2. release-please mantiene abierto un PR `chore: release X.Y.Z` con el `CHANGELOG.md` y la versión.
3. Al mergear ese PR se crean el tag `vX.Y.Z` y el release de GitHub, y se mueven `vX` y `vX.Y`. El PR de release
   también actualiza el default de `standards-ref` en `java-ci.yml` (la línea marcada con `x-release-please-version`),
   así el workflow de un release lee los scripts y el catálogo de ese mismo release.

### El token de release-please

release-please corre con el secret **`RELEASE_PLEASE_TOKEN`**, no con el `GITHUB_TOKEN`, por dos razones:

* El PR de release cambia `.github/workflows/java-ci.yml`, y el `GITHUB_TOKEN` no puede crear commits que toquen
  workflows (ese permiso no se le puede dar): falla con `Error adding to tree: <sha>`.
* Un PR abierto con el `GITHUB_TOKEN` no dispara el CI; con un token propio, el PR de release corre `Lint` y el
  servicio de prueba como cualquier otro.

Es un fine-grained token sobre **solo este repo** con Contents, Pull requests y Workflows en **Read and write**
(Metadata: read se agrega solo). Se guarda en Settings → Secrets and variables → Actions. Al vencer, el workflow
`Release` vuelve a fallar: se renueva y se corre de nuevo. Mover `vX` y `vX.Y` sigue con el `GITHUB_TOKEN` (solo
mueve tags).

## A validar

* Que la rama `main` tenga protección con el check `Lint` y `Sample service / twa-standards` requeridos.
* Que los tags `vX.Y.Z` estén protegidos ([arriba](#tags-inmutables)).
