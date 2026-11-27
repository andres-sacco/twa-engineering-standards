# OpenAPI (API-01 a API-03)

La etapa 5 revisa el contrato de cada servicio en `Build and test`, después de `mvn verify`:

| Control | Herramienta | Qué revisa |
|---|---|---|
| `API-01` | El `OpenApiIT` del servicio | La spec se exporta a `target/openapi.json` en el build |
| `API-02` | Spectral, con [config/spectral/twa.yaml](../config/spectral/twa.yaml) | La spec cumple las convenciones de las APIs TWA y las reglas recomendadas de Spectral |
| `API-03` | oasdiff | No hay cambios incompatibles contra la spec de la rama principal, salvo que el PR los apruebe |

Los tres entran en `warn` (política de severidades) y solo corren en servicios (`type: service`).

## API-01: exportar la spec

Los servicios generan la spec del código (springdoc): no hay un `openapi.yaml` en el repo. La forma más barata de
tenerla en el build es que la escriba el test de integración que ya la pide. Los seis servicios tienen un `OpenApiIT`
(Karate) que lee `/v3/api-docs`: alcanza con una línea en su `openapi.feature`, después de leer la respuesta:

```gherkin
  Background:
    * url baseUrl
    Given path '/v3/api-docs'
    When method get
    Then status 200
    * def api = response
    * karate.write(api, 'openapi.json')
```

`karate.write` escribe en `target/` del módulo. El servicio de prueba lo hace con JUnit
([OpenApiIT.java](../examples/sample-service/src/it/java/com/twa/sample/web/OpenApiIT.java)).

`java-ci.yml` busca `**/target/openapi.json`, una por módulo, y las sube en el artifact `openapi` junto con los
reportes de Spectral (JSON y SARIF) y de oasdiff.

Se descartaron `springdoc-openapi-maven-plugin` (levanta la app aparte, y la app necesita Mongo) y una spec versionada
en el repo (se desincroniza del código).

## API-02: las reglas de Spectral

El ruleset extiende `spectral:oas` (recomendado) y agrega las reglas `twa-*`, que traducen las "Convenciones comunes a
todas las APIs" de `docs/arquitectura.md` de twa-platform. Las de severidad `error` hacen fallar el control; `warn` e
`info` quedan como anotación.

| Regla | Severidad | Convención |
|---|---|---|
| `twa-servers`, `twa-base-path` | error | Hay un server y termina en `/api/flights/<servicio>` |
| `twa-paths-without-base-path` | error | Los paths no repiten el base path |
| `twa-relative-server` | info | El server es relativo (sin el host de quien generó la spec) |
| `twa-path-kebab-case` | warn | Segmentos en minúscula y kebab-case (`/ancillary-types/{code}`) |
| `twa-operation-summary` | error | Cada operación tiene `summary` |
| `twa-operation-id-generated` | error | El `operationId` no es uno generado por springdoc (`getById_1`) |
| `twa-client-id-header` | error | Cada operación declara el header `X-Client-Id` |
| `twa-json-media-types` | error | Las respuestas son `application/json` o `application/problem+json`, nunca `*/*` |
| `twa-error-problem-details` | error | Los 4xx y 5xx responden `application/problem+json` (RFC 9457) |
| `twa-error-code` | error | El schema del error tiene `code` (string) y `traceId` |
| `twa-error-examples` | warn | Cada error tiene ejemplos (uno por `code`) |
| `twa-response-examples`, `twa-request-examples` | warn | Las respuestas 2xx y los requests con cuerpo tienen ejemplo |
| `twa-amount-as-string` | error | Importes y tasas (`amount`, `price`, `total`, `taxes`, `rate`, `*Amount`, `*Price`…) como string decimal, nunca `number` |

De las recomendadas de Spectral, la validación de ejemplos contra su schema (`oas3-valid-media-example`,
`oas3-valid-schema-example`) baja a `warn`: es documentación, no contrato.

**Fuera de Spectral**, porque la spec no lo muestra: cifrado y enmascarado de datos personales, logs,
`Accept-Language`, y qué `POST` necesitan `Idempotency-Key` (depende de si tiene efecto en la aerolínea).

`make lint` corre el ruleset contra [tests/valida.yaml](../config/spectral/tests/valida.yaml) (cero hallazgos) y
[tests/invalida.yaml](../config/spectral/tests/invalida.yaml) (tiene que romper cada regla `twa-*` en `error`). Una
regla nueva entra con su caso en `invalida.yaml`.

### Apagar una regla en un repo

En el `.twa-standards.yml`, con la razón en un comentario:

```yaml
controls:
  API-02:
    params:
      # Los ejemplos de los errores se agregan en el próximo release (issue #42)
      disabledRules: [twa-error-examples]
```

## API-03: cambios incompatibles

En cada push a la rama principal la spec queda en la cache de Actions (`twa-openapi-<working-directory>-<rama>-<sha>`),
como la cobertura de TST-02. Un PR la restaura y corre `oasdiff breaking`; cuentan los cambios de nivel `ERR` (sacar un
endpoint o un campo de la respuesta, volver obligatorio un parámetro, cambiar un tipo…). Hasta el primer push con el
workflow nuevo no hay contra qué comparar y API-03 pasa.

**Un cambio incompatible a propósito** se aprueba con la etiqueta `api-breaking-change` en el PR: API-03 pasa e
informa los cambios. La etiqueta no avisa a nadie: antes se revisa a quién le pega (skill `impact` de twa-dev-flow) y
se coordina con los consumidores. Si la etiqueta se pone después de que corrió el CI, hay que volver a correrlo.

## Probarlo en local

En la raíz del servicio, después de `mvn verify` (con la línea de `karate.write`):

```bash
S=../twa-engineering-standards/scripts
export REPORTS_DIR="$PWD/target/twa-api"
$S/openapi-export.sh warn
$S/check-openapi-lint.sh warn '{}'
# API-03 contra una spec anterior: copiarla a target/api-base/<módulo>.json
$S/check-openapi-breaking.sh warn "$PWD/target/api-base" false
```

## Qué dio sobre los repos (2026-11-27)

Con la spec que sirve cada jar (`/v3/api-docs`):

| Servicio | Errores | Detalle |
|---|---|---|
| catalog | 1 | `oas3-schema`: `info.license` tiene `url` e `identifier` a la vez (OpenAPI 3.1 admite uno). Avisos: 238 ejemplos que no cumplen su schema (falta `names`; `instance` con `{id}`) |
| exchange-rates | 2 | `twa-amount-as-string`: `ConversionRequest.amount` y `ManualRateRequest.rate` son `number` |
| search | 0 | Avisos de ejemplos; el server tiene host (`info`) |
| reservations | 0 | Avisos: `X-Client-Id` duplicado en 5 operaciones, 3 sin `description`, 5 respuestas sin ejemplo |
| sample-service | 0 | Sin hallazgos |

Todos cumplen `X-Client-Id`, Problem Details con `code` y `traceId` y el base path. Los arreglos van en cada repo
cuando adopte el workflow (etapa 9).
