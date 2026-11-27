# Docker (DKR-01 a DKR-04)

El job `Docker image` de `java-ci.yml` revisa el Dockerfile, construye la imagen (sin publicarla) y la escanea:

| Control | Severidad | Herramienta | Qué revisa |
|---|---|---|---|
| `DKR-01` | block | Docker Buildx | La imagen construye (ya bloqueaba) |
| `DKR-02` | warn | Hadolint | Buenas prácticas del Dockerfile, con shellcheck sobre los `RUN`. Cuentan `error` y `warning` |
| `DKR-03` | warn | Trivy (imagen) | Vulnerabilidades CRITICAL y HIGH **con versión corregida** en los paquetes del sistema operativo (la imagen base) |
| `DKR-04` | warn | Conftest + Trivy | Políticas TWA del Dockerfile y secretos en las capas de la imagen |

La imagen se carga en el Docker del runner (`twa-ci/image:<sha>`) para escanearla; no sale del runner. Los reportes
(JSON y SARIF de Hadolint, Trivy y Conftest) quedan en el artifact `docker-reports`.

## DKR-03: solo el sistema operativo

Las dependencias Java del jar ya las revisa `SEC-03` sobre el SBOM. `DKR-03` mira solo los paquetes de la imagen base
(`--pkg-types os`): lo que se arregla reconstruyendo con la base actualizada. Renovate fija la imagen base por digest
y mergea solo los cambios de digest y patch (grupo `imágenes base`, ver [dependencias](dependencias.md)).

## DKR-04: las políticas TWA

Están en [config/conftest/dockerfile.rego](../config/conftest/dockerfile.rego) y miran la etapa final del Dockerfile,
que es la imagen que se publica:

| Id | Política | Por qué |
|---|---|---|
| `TWA-DOCKER-01` | La base final es el JRE de eclipse-temurin (`eclipse-temurin:<versión>-jre`, con o sin digest) | Una sola familia de imágenes base para todos los servicios, sin JDK ni herramientas de build en producción |
| `TWA-DOCKER-02` | Hay `USER` y no es `root` ni `0` | El proceso no corre como root |
| `TWA-DOCKER-03` | Hay `HEALTHCHECK` y no es `NONE` | Docker y el orquestador saben si el servicio responde |
| `TWA-DOCKER-04` | Ningún `ENV` ni `ARG` con nombre de credencial (`*TOKEN*`, `*PASSWORD*`, `*SECRET*`…) ni `COPY`/`ADD` de archivos de credenciales (`settings.xml`, `.npmrc`, `id_rsa`, `*.pem`…) | Quedan en la imagen. Un secreto del build entra con `RUN --mount=type=secret`, como el `settings.xml` de Maven |

Además, Trivy busca secretos en todas las capas de la imagen construida: un token que se copió sin querer aparece
aunque el Dockerfile no lo nombre.

Los seis servicios y el de prueba cumplen las cuatro políticas: `DKR-04` es candidato a pasar a `block` apenas corra
en `warn` (política de severidades).

### Exceptuar una política

En el `.twa-standards.yml`, con la razón en un comentario. Un secreto en una capa no se exceptúa: se saca de la
imagen y se rota.

```yaml
controls:
  DKR-04:
    params:
      # El proxy de prueba no expone un endpoint de salud (pendiente)
      exceptions: [TWA-DOCKER-03]
```

`make lint` corre las políticas contra el Dockerfile del servicio de prueba (las cumple) y contra
[config/conftest/tests](../config/conftest/tests) (entre los dos Dockerfile rompen las cuatro). Una política nueva va
con su caso.

## Suprimir un hallazgo

| Control | Dónde | Cómo |
|---|---|---|
| `DKR-02` | El Dockerfile | `# hadolint ignore=DL3008` en la línea anterior a la instrucción, con la razón |
| `DKR-03` | `.trivyignore.yaml` en `working-directory` | Como `SEC-03`: el id en `vulnerabilities`, con `statement` y `expired_at` |
| `DKR-04` | `.twa-standards.yml` | `params.exceptions` (arriba) |

## Por qué así

* **Sin Dockle.** El plan lo incluía para los chequeos CIS de la imagen, pero no tiene releases desde enero de 2025.
  Lo que aportaba lo cubren Conftest (usuario, `HEALTHCHECK`, credenciales en `ENV`) y el escaneo de secretos de
  Trivy sobre las capas.
* **Conftest sobre el Dockerfile, no sobre la imagen:** el mensaje apunta a la instrucción que hay que cambiar, y la
  política se prueba sin construir nada.
* **Un solo escaneo de Trivy** para `DKR-03` y los secretos de `DKR-04`, con todas las severidades: el filtro de
  severidad de Trivy también se aplicaría a los secretos. Las vulnerabilidades se filtran después.
* Cosign y Syft (firmar la imagen y publicar su SBOM) quedan para cuando las imágenes se publiquen.

## Probarlo en local

En la raíz del servicio, con la imagen construida (`docker build -t mi-servicio:local .`):

```bash
S=../twa-engineering-standards/scripts
export REPORTS_DIR="$PWD/target/twa-docker"
$S/check-dockerfile.sh warn Dockerfile
$S/check-image.sh warn '{}' mi-servicio:local
$S/check-docker-policies.sh warn '{}' Dockerfile
```

## Qué dio sobre los repos (2026-11-27)

| Repo | DKR-02 | DKR-03 | DKR-04 |
|---|---|---|---|
| catalog, exchange-rates, search, reservations, provider-alpha, provider-beta | Sin errores ni warnings (un `info` DL3066 por `USER app` no numérico) | — (imagen no construida en esta prueba) | Cumplen las cuatro políticas |
| sample-service | Ídem | Ubuntu 26.04 de `eclipse-temurin:25-jre`: sin CRITICAL/HIGH con fix | Cumple; sin secretos en las capas |

Casos negativos probados: un Dockerfile con JDK como base, sin `USER` ni `HEALTHCHECK`, con `ARG GITHUB_TOKEN`,
`ENV DB_PASSWORD` y `COPY settings.xml` (DKR-02 marca DL3064 y DL3045; DKR-04 las cuatro políticas), y una imagen
con un `settings.xml` con token en una capa (DKR-04 lo encuentra, oculto).
