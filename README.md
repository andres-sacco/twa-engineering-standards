# twa-engineering-standards

Estándares de ingeniería de los repos TWA: workflows reutilizables de GitHub Actions que construyen y validan cada
servicio y cada librería (build, tests y cobertura, arquitectura, seguridad, OpenAPI, Docker y dependencias), con
herramientas open source.

La decisión está en
[ADR-0013](https://github.com/andres-sacco/twa-platform/blob/main/docs/adr/0013-estandares-de-ingenieria-centralizados.md)
de twa-platform. Las reglas de arquitectura **no** están acá: siguen en
[twa-layered-rules](https://github.com/andres-sacco/twa-layered-rules); este repo las ejecuta y reporta.

## Estado

Etapa 0: decisión y relevamiento. Todavía no hay workflows para consumir.

## Documentación

| Documento | Qué responde |
|---|---|
| [docs/plan.md](docs/plan.md) | Las etapas, qué entrega cada una y con qué herramientas |
| [docs/relevamiento.md](docs/relevamiento.md) | Cómo se construyen y validan hoy los repos TWA, y qué falta |
| [docs/politica-de-severidades.md](docs/politica-de-severidades.md) | Qué significa `off`, `warn` y `block`, cuándo un control pasa a bloquear y el catálogo de controles con su id |
