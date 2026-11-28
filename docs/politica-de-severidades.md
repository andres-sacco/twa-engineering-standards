# Política de severidades

Cada control tiene un id (`BLD-01`, `SEC-03`…) que aparece en el mensaje cuando falla, y una severidad por repo en
`.twa-standards.yml`.

| Severidad | Qué pasa cuando el control encuentra algo |
|---|---|
| `off` | No corre. Solo con una razón escrita en `.twa-standards.yml` (ej. un repo sin Dockerfile) |
| `warn` | Corre, lo reporta en el resumen del PR y en los artifacts, y **no** falla el check |
| `block` | Falla el check `twa-standards`, que es requerido para mergear en `main` |

## Reglas

1. **Lo que hoy ya bloquea sigue bloqueando** desde el primer día (Spotless, build, tests, reglas de arquitectura, que
   la imagen construya). La migración no puede aflojar nada.
2. **Un control nuevo entra en `warn`.** Pasa a `block` en un repo cuando se cumplen las tres condiciones:
   * corrió en `warn` al menos **dos semanas** (o 10 PR) en ese repo;
   * `main` no tiene hallazgos abiertos de ese control (corregidos o suprimidos según la regla 4);
   * no hubo falsos positivos sin resolver en ese tiempo.
3. **Excepción: secretos (`SEC-01`) bloquea desde el primer día.** Un secreto en el historial no se arregla después.
4. **Suprimir un hallazgo, no el control.** Una supresión va en el archivo de la herramienta (`.gitleaksignore`,
   `.trivyignore.yaml`, comentario `nosemgrep`…) con la razón y, si es una vulnerabilidad, una fecha de vencimiento. Al
   vencer, el hallazgo vuelve a aparecer. `GOV-02` verifica que cada supresión tenga su razón y su vencimiento, y
   `GOV-01` avisa en el PR cada supresión nueva: el mismo PR puede suprimir el hallazgo que lo bloquea.
5. **El default lo define este repo**; un repo puede subir la severidad pero solo bajarla con una razón escrita en su
   `.twa-standards.yml`, que se revisa en el PR (`GOV-01` lo marca). Una excepción temporal lleva `until`: vencida,
   `GOV-02` la marca.
6. Subir un default de `warn` a `block` en este repo es un **cambio mayor** (`v2`), salvo que todos los repos ya lo
   tengan en `block`.

## Catálogo inicial de controles

Los ids son estables: un control que se elimina no reusa su id. La fuente de verdad es [config/controls.yml](../config/controls.yml); `make lint` verifica que esta tabla coincida. La etapa en que se implementa está en el
[plan](plan.md).

| Id | Control | Herramienta | Severidad inicial | Etapa |
|---|---|---|---|---|
| `BLD-01` | Formato del código | Spotless | block (ya bloquea) | 2 |
| `BLD-02` | Compila y pasan los tests unitarios y de integración | Maven, Surefire, Failsafe | block (ya bloquea) | 2 |
| `BLD-03` | Versiones de Java y Maven exigidas | maven-enforcer-plugin | warn | 2 |
| `BLD-04` | Convergencia de dependencias y dependencias prohibidas | maven-enforcer-plugin | warn | 2 |
| `TST-01` | Cobertura de líneas mínima (umbral a definir con lo que mida JaCoCo en `warn`) | JaCoCo | warn | 2 |
| `TST-02` | La cobertura no baja respecto de `main` | JaCoCo | warn | 2 |
| `ARC-01` | Corren y pasan las reglas de arquitectura de `twa-layered-rules` / `twa-hexagonal-rules` | ArchUnit (librería existente) | block (ya bloquea) | 3 |
| `ARC-02` | Versión mínima de la librería de reglas | Maven (pom efectivo) | warn | 3 |
| `SEC-01` | Secretos en el código y en el historial del PR | Gitleaks | **block** | 4 |
| `SEC-02` | Análisis estático de seguridad | Semgrep CE, SpotBugs + FindSecBugs | warn | 4 |
| `SEC-03` | Vulnerabilidades CRITICAL/HIGH con versión corregida en dependencias | Trivy (sobre el SBOM) | warn | 4 |
| `SEC-04` | SBOM generado y publicado como artifact | CycloneDX Maven plugin | warn | 4 |
| `SEC-05` | Licencias de dependencias fuera de la lista permitida | SBOM (CycloneDX) contra la lista permitida | warn | 4 |
| `API-01` | La spec OpenAPI se exporta en el build | springdoc + OpenApiIT (target/openapi.json) | warn | 5 |
| `API-02` | La spec cumple las convenciones de la plataforma (base path, Problem Details, `code` de error) | Spectral | warn | 5 |
| `API-03` | Sin cambios incompatibles contra `main` sin aprobación explícita | oasdiff | warn | 5 |
| `DKR-01` | La imagen construye | Docker Buildx | block (ya bloquea) | 2 |
| `DKR-02` | Buenas prácticas del Dockerfile | Hadolint | warn | 6 |
| `DKR-03` | Vulnerabilidades CRITICAL/HIGH con fix en la imagen | Trivy (image, paquetes del sistema operativo) | warn | 6 |
| `DKR-04` | Políticas TWA: usuario sin privilegios, `HEALTHCHECK`, base `eclipse-temurin`, sin secretos en capas | Conftest (OPA), Trivy (secretos en las capas) | warn | 6 |
| `DEP-01` | El repo usa el preset de Renovate y no Dependabot | Renovate | warn | 7 |
| `WFL-01` | Actions fijadas por SHA y `permissions` mínimos | zizmor | warn | 2 |
| `GOV-01` | Las excepciones nuevas (supresiones, reglas congeladas, severidades bajadas) quedan a la vista en el PR | git diff | warn | 10 |
| `GOV-02` | Las supresiones tienen razón y, las de vulnerabilidades, vencimiento; ninguna excepción con `until` vencido | Archivos de supresión de cada herramienta | warn | 10 |

Los seis servicios ya cumplen `DKR-04`: es candidato a pasar a `block` apenas se implemente.
