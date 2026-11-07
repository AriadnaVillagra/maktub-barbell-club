---
id: E0
nivel: epica
parent: docs/work/M1-mvp
orden: 0
---

# E0 — Cerrar F0

## Qué entrega

Las tres tareas de la Etapa 0 de M1 §5, con el alcance de design.md §3.4 ("Sin señal") y §3.6 (CORS, backup):

- La PWA publicada en GitHub Pages llega a la API: el origen `https://ariadnavillagra.github.io` queda cargado en `ORIGENES_PERMITIDOS` (hoy la API no devuelve `Access-Control-Allow-Origin` para él).
- La app instalada abre sin señal y muestra lo último que tenía, con un service worker propio que guarda la app (el generado por Flutter 3.47 se desregistra solo).
- Hay un backup diario de la base en Cloud Storage y se probó restaurarlo en local.

E0 corre en paralelo con el resto de las épicas. Lo que solo se ve en la PWA publicada (abrir sin señal, instalación) se valida después de mergear E0 a `main` (D2, D3).

## Excluye

- El almacenamiento local de los datos del día y la cola de reintentos: van en E7 (D8 pide que sin señal abran también los datos del día y que se pueda marcar; eso es de E7, no de acá).
- El cliente del canal en vivo con reconexión: E7.
- El client ID de OAuth y el login con Google: E1.

## Contingencia

Supuesto de design.md §4.2: un service worker propio funciona en la PWA instalada, dentro del scope `/maktub-barbell-club/`. Si falla, no hay modo sin señal tal como está diseñado, y eso alcanza a 0.2, 7.5 y al criterio 8 de M1 §7. Hay que frenar y rediseñar esa parte con el usuario antes de seguir con 7.5.

## Terminada cuando

- Desde `https://ariadnavillagra.github.io/maktub-barbell-club/` la app abre y llega a `/health` de la API, sin error de CORS.
- Con la app instalada en el teléfono y el modo avión puesto, abre y muestra lo último que tenía; el service worker sigue registrado, no se desregistra.
- Existe un backup diario en Cloud Storage, corre solo, y se restauró uno en una base local y los datos coinciden.
- Los chequeos de la PWA publicada se hicieron después de mergear E0 a `main`.

## Issues

| # | Issue | Depende de |
|---|---|---|
| E0.1 | [Cargar el origen de Pages en la API](E0.1-origen-pages-en-api.md) | — |
| E0.2 | [Service worker propio que guarda el shell](E0.2-sw-propio-shell.md) | — |
| E0.3 | [Bucket y cuenta de escritura para el backup](E0.3-bucket-backup.md) | — |
| E0.4 | [Job de `mongodump` programado cada día](E0.4-job-backup-diario.md) | E0.3 |
| E0.5 | [Probar la restauración en local](E0.5-prueba-restauracion.md) | E0.4 |
| E0.6 | [Validar la PWA publicada](E0.6-validar-pwa-publicada.md) | E0.1, E0.2 |

**En paralelo:**
- E0.1, E0.2 y E0.3 arrancan juntos.
- La cadena del backup (E0.3 → E0.4 → E0.5) es independiente de la cadena de Pages (E0.1 y E0.2 → E0.6).
- E0.6 corre después de mergear E0.1 y E0.2 a `main` (D3).
