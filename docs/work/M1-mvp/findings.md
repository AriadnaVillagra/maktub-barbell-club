# M1-mvp — Hallazgos de la preparación

Relevado el 2026-11-07 sobre la rama `auth` (último commit `1bcd49f`). Este documento cuenta qué hay
hoy y qué falta. No trae diseño ni plan: el plan es el de
[docs/milestones/M1-mvp.md](../../milestones/M1-mvp.md) (en adelante, "M1"), y los números de tarea
que siguen son los suyos.

## Intención, tal como se dio

> "el m1"

Es decir, cumplir M1: que Andi y Ari entrenen un ciclo completo de 4 semanas solo con la app, con el
historial de la planilla migrado y verificado.

## Estado actual

### Etapa 0 — Cerrar F0

- **0.1 (PWA en GitHub Pages):** parcial. Existe `.github/workflows/pages.yml`. Corre en cada push a
  `main`, ejecuta los tests, compila con `--base-href /<repo>/` y `--no-web-resources-cdn` y publica
  `apps/frontend/build/web`, con `API_URL` apuntando a Cloud Run. El remoto ya existe
  (`github.com/AriadnaVillagra/maktub-barbell-club`). No se verificó que Pages esté activado ni que
  el origen esté cargado en `ORIGENES_PERMITIDOS`.
- **0.2 (abrir sin señal):** no hay service worker propio ni configuración de caché offline.
  Solo `apps/frontend/web/manifest.json`, `index.html` e íconos.
- **0.3 (backup):** nada. No hay job, script ni Dockerfile con `mongodump`.

### Etapa 1 — Acceso

- **1.1 hecha** (`eb26f6e`):
  - Modelos: `packages/maktub_core/lib/src/modelos/clubes.dart` (`Rol`, `TipoClub`, `Club`,
    `Membresia`, `Invitacion`, `Atleta`) y `usuario.dart` (`Usuario`, `MetodoIngreso`,
    `normalizarEmail`).
  - Matriz de permisos: `src/reglas/permisos.dart` (`Accion`, `puede`, `dejaSinCoach`).
  - Tests: `test/acceso_test.dart`.
- **1.2 hecha** (`1bcd49f`), en `apps/backend/lib/features/auth/`:
  - `tokens.dart`: access token HS256 de 15 min y refresh de 30 días, guardado como SHA-256.
  - Slices `start_session`, `refresh_session` (rotación y revocación por reuso) y `end_session`.
  - `authenticate.dart` (`requireUser`).
  - Rutas `routes/auth/refresh.dart` y `logout.dart`.
  - Tests: `test/features/auth/session_test.dart`.
  - Notas:
    - `StartSession` no tiene endpoint todavía; lo va a llamar 1.3.
    - `requireUser` no está montado en ningún `_middleware.dart`.
- **1.3 a 1.7:** nada.
  - Ninguna verificación de ID token de Google. El único rastro es el valor `MetodoIngreso.google`.
  - Ningún middleware de club ni de rol, ni un helper de test de aislamiento. `puede()` no se llama
    desde el backend.
  - Ningún script de alta.
  - En el frontend, `core/red/cliente_api.dart` solo tiene `get` y `put`, sin header de autorización
    ni renovación de token. `app/router.dart` no tiene ruta de login ni rutas según el rol.

### Etapa 2 — Catálogo

- Existe el modelo `Temporizador` (`modelos/temporizador.dart`: countdown, emom, tabata) con
  `fasesDe` en `reglas/fases.dart`.
- `Equipo` (`reglas/equipo.dart`) es la calculadora de barra y discos con el estándar en constantes,
  no el equipo del club en datos que pide 2.1.
- Ejercicio, categoría, endpoints, semilla y UI de catálogo: nada.

### Etapa 3 — Atletas y referencias

Nada. `Atleta` no tiene referencias; un comentario en `clubes.dart` dice que llegan con F3.

### Etapa 4 — Reglas de carga

Hay una base parcial en `maktub_core/lib/src/reglas/`:
- `porcentajes.dart`: `Porcentajes`, `normalizarPct`, `pctEfectivo`, `pesoPorPorcentaje` y
  `pctDesdePeso`.
- `ciclo.dart`: `UbicacionEnCiclo`.
- `fechas.dart`.

Faltan para 4.1:
- el factor de trabajo;
- el kilaje fijo;
- la barra vacía en la rampa;
- el ajuste del día por atleta en dos niveles;
- las series tocadas que no se pisan;
- la verificación contra los casos de `reference/`.

### Etapas 5 a 7 — Editor, asignación, sesión y vivo

No existen los modelos de plan, modelo de semana, día, bloque, prescripción, serie, grupo,
asignación, sesión ni registro. Tampoco hay WebSocket ni canal en vivo.

Lo único que hay es el temporizador del frontend, en `apps/frontend/lib/features/temporizador/`:
`Crono`, `CronoController`, `BarraCrono`, `elegirTemporizador` y su test `crono_test.dart`.

### Etapa 8 — Migración

Nada: no hay importador ni CSV.

## Brecha

De las 40 tareas de M1 están hechas 2 (1.1 y 1.2), más algunas bases en las reglas de carga y en el
temporizador. Falta casi todo:
- cerrar F0 (caché offline, backup y, si falta, publicar la PWA);
- el resto del acceso;
- catálogo, referencias, reglas de carga completas, editor de plan y asignación;
- la sesión con sincronización en vivo;
- la migración y el cierre.

## Lo que encontraron los barridos

- **Trabajo propuesto o activo:** no había ninguna ubicación de trabajo antes de esta. No hay
  ítems que solapen, que sean prerrequisito ni que queden bloqueados.
- **Registro de deuda técnica:** el proyecto no tiene uno.
- **Choque con la intención de diseño:** M1 recorta F1 a F12 y saca F10 (motor de pasos), pero el
  "Camino crítico" y la tabla de "Features" de `docs/diseno.md` siguen sin reflejarlo. Es el riesgo
  R4 de M1. Lo tiene que resolver la sesión que mantiene `diseno.md`; desde acá no se edita.
- **Documentación desactualizada:**
  - La sección "Status" de `CLAUDE.md` dice que el repo de GitHub no está creado, pero el remoto y
    el workflow de Pages ya existen.
  - `docs/milestones/` está sin trackear en git.

## Bloqueos externos al ítem

- **Client ID de Google OAuth autorizado para el origen de GitHub Pages** (M1 R2, F1 S7). Bloquea
  1.3, y con eso 1.6, 1.7 y todo lo que depende de un usuario logueado. Se resuelve en la consola de
  GCP; no está en el repo. Entra en este trabajo.
- **Exportación a CSV de las hojas de la planilla** (M1 8.1). La hace el usuario. Bloquea 8.2 a 8.4.
  Entra en este trabajo.
- **No hay documento de política de trabajo.** La magnitud y esta estructura de carpeta son
  improvisadas. Si después se define una política, este ítem se tiene que ajustar a ella.

## E7.1: WebSocket en Cloud Run (R1), medido el 2026-11-08

Se abrió un WebSocket contra la API real (`europe-north1`, una sola instancia, `--timeout 3600`), con un eco
cada 30 s durante 66 minutos.

- La primera conexión duró **3601 s** y respondió los 120 mensajes. Eco más lento: 67 ms.
- El único corte fue en el tope de 3600 s de Cloud Run, con **código 1006** y sin mensaje de cierre.
- La reconexión abrió en unos 2 s, y siguió hasta el final de la prueba sin más cortes.

R1 se cumple: hace falta reconectar una vez cada 60 minutos. **Para E7.10:** el cierre llega como 1006, igual
que una caída de red, así que el cliente tiene que reconectar y resincronizar por número de secuencia sin
mostrarlo como error. La prueba fue desde una conexión de escritorio estable; un teléfono en el gimnasio va a
cortarse más seguido por la red, y eso lo cubre la misma reconexión.

## Nota sobre la investigación

La ubicación del código la hizo un agente de búsqueda. El juicio sobre si lo que existe tiene la
forma correcta se hizo con una verificación puntual en la conversación principal, no con una
revisión profunda. Antes de construir sobre 1.1 y 1.2 conviene confirmar que siguen la sección
"Modelo del dominio" de `docs/diseno.md`.
