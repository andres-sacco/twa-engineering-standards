# Reportes

La etapa 8 junta lo que cada control reporta en dos lugares: el resumen de cada PR y un tablero con el estado de
todos los repos. **No hay escaneo nocturno**: los controles corren en cada PR y en cada push a la rama principal, y el
tablero muestra ese último resultado.

## El resumen del PR

El job `twa-standards` (el check que se exige en la protección de la rama) deja en su resumen **una tabla con todos
los controles**: severidad, resultado (✅, ⚠️ en warn, ❌ en block, ⏭️ sin evaluar, — sin resultado) y el detalle. Los
apagados o que no aplican al tipo de repo van en una línea aparte. Es el único lugar donde mirar; el detalle de cada
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
    {"id": "TST-01", "name": "Cobertura de líneas mínima", "severity": "warn", "result": "fail", "detail": "55% (mínimo 60%)"}
  ]
}
```

`result` es `ok`, `fail`, `skip` (no se pudo evaluar por otra falla), `none` (no dejó resultado: el job no corrió) u
`off` (apagado o no aplica).

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

## SARIF

Cada herramienta deja su SARIF en los artifacts (`security-reports`, `openapi`, `docker-reports`). No se suben a Code
Scanning: en un repo privado necesita GitHub Advanced Security, y los servicios son privados. Si eso cambia, se agrega
un paso con `github/codeql-action/upload-sarif` y `security-events: write` (a validar).
