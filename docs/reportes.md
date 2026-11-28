# Reportes

La etapa 8 junta lo que cada control reporta en dos lugares: el resumen de cada PR y un tablero con el estado de
todos los repos. **No hay escaneo nocturno**: los controles corren en cada PR y en cada push a la rama principal, y el
tablero muestra ese último resultado.

## El resumen del PR

El job `twa-standards` (el check que se exige en la protección de la rama) deja en su resumen **una tabla con todos
los controles**: severidad, resultado (✅, ⚠️ en warn, ❌ en block, ⏭️ sin evaluar, — sin resultado) y el detalle. Los
apagados o que no aplican al tipo de repo van en una línea aparte. Un control en `block` que quedó sin evaluar porque
un paso anterior en `warn` falló y lo salteó (API-02 sin la spec de API-01, SEC-03 sin el SBOM, DKR-03 sin la imagen)
sale como **❌ sin evaluar (block)** y hace fallar el check. Si su job no dejó ningún resultado (no pudo subir el
artifact por la cuota) no se puede saber, y no cuenta: el job que falló ya hace fallar el check por su cuenta. Es el único lugar donde mirar; el detalle de cada
hallazgo sigue en las anotaciones y en el resumen del job que lo encontró.

Cómo se arma:

1. Cada `report ID SEVERIDAD ok|fail|skip "detalle"` (`scripts/lib.sh`) además escribe una línea JSON en
   `$TWA_RESULTS_FILE`, y cada job la sube como artifact `twa-results-<job>`.
2. `twa-standards` los baja, corre `scripts/summary.sh` y sube **`twa-results`** (`twa-results.json`, 30 días): el
   repo, el commit, la corrida, la versión de twa-engineering-standards y el resultado de cada control. Si un control
   reporta más de una vez (SEC-02: Semgrep y SpotBugs), cuenta el peor resultado.

`twa-results.json`:

```json
{
  "version": 1,
  "repository": "andres-sacco/twa-flights-catalog",
  "workingDirectory": ".",
  "ref": "refs/heads/main",
  "sha": "…",
  "event": "push",
  "run": "https://github.com/andres-sacco/twa-flights-catalog/actions/runs/…",
  "standardsRef": "v0.2.0",
  "createdAt": "2026-11-27T18:43:07Z",
  "controls": [
    {"id": "TST-01", "name": "Cobertura de líneas mínima", "severity": "warn", "result": "fail", "detail": "55% (mínimo 60%)", "unevaluated": false}
  ]
}
```

`result` es `ok`, `fail`, `skip` (no se pudo evaluar por otra falla), `none` (no dejó resultado: el job no corrió) u
`off` (apagado o no aplica). `unevaluated` es `true` para un control en `block` con `skip` o `none` cuyo job sí dejó
resultados (los jobs de cada control están en `jobs` de `config/controls.yml`).

## El tablero

`make report` (`scripts/report.sh`) baja el `twa-results` del **último push a la rama principal** de cada repo de
[config/report.yml](../config/report.yml) y arma `report/index.md` (una fila por repo, una columna por control, y la
lista de lo que falla) y `report/report.json`. No escanea nada: solo lee artifacts.

```bash
read -rs TWA_REPORT_TOKEN && export TWA_REPORT_TOKEN   # pide el token sin mostrarlo
make report
```

`TWA_REPORT_TOKEN` es un fine-grained token con **Actions: read** (y Metadata: read, que se agrega solo) sobre los
repos de `config/report.yml`. No se llama `GITHUB_TOKEN` porque GitHub no admite secrets con ese prefijo, y el mismo
nombre sirve como secret si el tablero pasa a correr en un workflow.

* `report/` está en `.gitignore`: tiene hallazgos de repos privados. **No se publica en este repo**, que es público
  (su Pages y sus Actions también lo son).
* Un repo entra en `config/report.yml` cuando adopta `java-ci.yml` (etapa 9). Si no tiene un push a la rama principal
  en los últimos 30 días, el artifact venció y aparece en "Sin resultados".
* Dónde se publica el tablero (un workflow en un repo privado, `twa-data`/Metabase leyendo `report.json`, o solo
  local) queda **a validar**.

## Por qué no hay escaneo nocturno

Lo único que aportaría es ver una vulnerabilidad nueva en un repo que no cambió. Eso ya lo cubren:

* **Dependencias Java:** las alertas de Dependabot de GitHub (Dependency graph + Dependabot alerts, que se activan en
  cada repo en la etapa 9; no son las actualizaciones de versión de Dependabot) avisan apenas sale el CVE, y el preset
  de Renovate (`vulnerabilityAlerts`) abre el PR del arreglo enseguida. Ese PR corre todos los controles.
* **Imagen base:** Renovate actualiza el digest de `eclipse-temurin` y lo mergea solo: cada imagen nueva de Temurin
  (con los parches del sistema operativo) llega como un PR que reconstruye y escanea la imagen.
* **Una consulta puntual:** el SBOM de cada build queda 30 días como artifact (`sbom`).

Lo que se pierde: el tablero muestra el estado al último push, no el de hoy, y una vulnerabilidad sin versión
corregida no aparece hasta que alguien toca el repo (tampoco cuenta para SEC-03 ni DKR-03).

## Artifacts y cuota

Los artifacts de los repos privados comparten **una cuota de almacenamiento de la cuenta** (500 MB en el plan
gratuito), que GitHub recalcula cada 6 a 12 horas. Si se llena, ningún repo puede subir artifacts hasta que venzan o
se borren los viejos. Por eso:

| Artifact | Días | Peso aproximado |
|---|---|---|
| `twa-results-<job>` (intermedios) | 1 | < 10 KB |
| `twa-results` (lo lee el tablero) | 30 | < 10 KB |
| `sbom` | 30 | ~200 KB |
| `test-reports` (solo si fallan los tests), `coverage-report`, `security-reports*`, `openapi`, `docker-reports` | 3 | 1 a 10 MB |
| el jar (`artifact-name`, opcional) | 1 | ~60 MB por servicio |

Cada subida tiene `continue-on-error`: sin cuota, el step queda en rojo pero el job sigue y el PR no se bloquea por
eso. Lo que se pierde es lo que no se subió: si falta un `twa-results-<job>`, sus controles aparecen como "— sin
resultado" en el resumen. Las líneas de base de TST-02 y API-03 usan la cache de Actions, que tiene su propio límite
por repo.

Si la cuota se llena: borrar los artifacts viejos (los jars primero) en Actions de cada repo privado y esperar el
recálculo.

## SARIF

Cada herramienta deja su SARIF en los artifacts (`security-reports`, `openapi`, `docker-reports`). No se suben a Code
Scanning: en un repo privado necesita GitHub Advanced Security, y los servicios son privados. Si eso cambia, se agrega
un paso con `github/codeql-action/upload-sarif` y `security-events: write` (a validar).
