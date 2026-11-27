# twa-engineering-standards

Estándares de ingeniería de los repos TWA: workflows reutilizables de GitHub Actions que construyen y validan cada
servicio y cada librería (build, tests y cobertura, arquitectura, seguridad, OpenAPI, Docker y dependencias), con
herramientas open source.

La decisión está en
[ADR-0013](https://github.com/andres-sacco/twa-platform/blob/main/docs/adr/0013-estandares-de-ingenieria-centralizados.md)
de twa-platform. Las reglas de arquitectura **no** están acá: siguen en
[twa-layered-rules](https://github.com/andres-sacco/twa-layered-rules); este repo las ejecuta y reporta.

## Estado

Etapa 2 terminada: `java-ci.yml` corre build, tests, cobertura, enforcer, imagen y zizmor (controles `BLD-*`,
`TST-*`, `DKR-01` y `WFL-01`). Ningún repo lo usa todavía: el piloto con catalog es la etapa 9.

## Cómo se usa

Cada repo reemplaza su `ci.yml` por una llamada a `java-ci.yml` ([docs/uso.md](docs/uso.md)) y tiene un
`.twa-standards.yml` en la raíz con lo que cambia respecto de los defaults:

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/andres-sacco/twa-engineering-standards/main/schema/twa-standards.schema.json
version: 1
type: service        # service | library
java: "25"
controls:
  TST-01:
    params:
      minLineCoverage: 60
  DKR-02:
    severity: "off"
    reason: Explicación de por qué este repo lo apaga
```

## Comandos

```bash
make lint           # workflows (actionlint, zizmor), schema, catálogo de controles y scripts
make sample         # compila y testea el servicio de prueba
make sample-image   # construye su imagen
```

## Documentación

| Documento | Qué responde |
|---|---|
| [docs/uso.md](docs/uso.md) | Cómo un repo adopta `java-ci.yml`: su `ci.yml`, inputs, qué corre y qué cambia respecto del CI actual |
| [docs/plan.md](docs/plan.md) | Las etapas, qué entrega cada una y con qué herramientas |
| [docs/relevamiento.md](docs/relevamiento.md) | Cómo se construyen y validan hoy los repos TWA, y qué falta |
| [config/controls.yml](config/controls.yml) | El catálogo de controles: id, severidad por defecto, herramienta y etapa |
| [docs/versionado.md](docs/versionado.md) | Tags, qué es un cambio incompatible y cómo se publica un release |
| [docs/politica-de-severidades.md](docs/politica-de-severidades.md) | Qué significa `off`, `warn` y `block`, cuándo un control pasa a bloquear y el catálogo de controles con su id |
