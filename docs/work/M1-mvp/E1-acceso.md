---
id: E1
nivel: epica
parent: docs/work/M1-mvp
orden: 1
---

# E1 — Acceso

## Qué entrega

El acceso de M1 de punta a punta: Andi y Ari entran con Google desde la app y cada pedido queda atado a un club y a un rol. Las tareas son 1.3 a 1.7 de M1 §5 (1.1 y 1.2 ya están hechas), con el alcance de design.md §3.2, §3.3, §3.4, §3.5 y §3.6 y las reglas de F1 §5. Lo que suma esta épica a lo que ya dicen esos documentos:

- Es la primera de la ruta crítica. E2 depende de su contexto de club.
- Los tres arreglos de la sesión (D5: reuso, rate limit, limpieza TTL) tienen que estar antes de que haya usuarios reales con sesión, o sea antes del merge de E1 (design.md §4.1, D2).
- El client ID de OAuth y el origen en `ORIGENES_PERMITIDOS` tienen que existir antes de 1.3 y 1.6.
- El test de aislamiento queda como pieza reutilizable: las épicas siguientes lo aplican a cada endpoint nuevo.
- Cubre el criterio 1 de M1 §7: entrar con Google desde el teléfono con la PWA instalada, y que un email desconocido no entre.

## Excluye

- Email y contraseña, verificación, recuperación, invitaciones, club personal desde la app, crear clubes, selector de club y planes por defecto: F1 (resto), según M1 §4. El script de alta crea los clubes personales sin interfaz (D6).
- El service worker y el modo sin señal: E0 y E7.
- Las colecciones y slices de dominio (catálogo, plan, asignación, sesión) y el canal en vivo: sus épicas.

## Contingencia

Supuesto de design.md §4.2 (M1 R2): Google acepta `https://ariadnavillagra.github.io` como origen autorizado del client de OAuth. Se prueba primero, al empezar, antes de construir la pantalla de ingreso. Si no lo acepta, cambia la forma del login (dominio propio u otro hosting) y esto afecta a 1.3, 1.6 y a todo lo que necesita un usuario logueado. Hay que frenar y rediseñar con el usuario.

## Terminada cuando

- Con el client ID real, el botón de Google funciona desde el origen de GitHub Pages y desde `http://localhost`.
- Un email dado de alta entra, y la app muestra lo que corresponde a sus clubes y roles según el endpoint de "quién soy".
- Un email desconocido recibe un mensaje claro con un código distinto de 401, y la app no intenta renovar el token.
- Usar un secreto que nunca fue válido no revoca la sesión de otro dispositivo; usar uno ya rotado sí la revoca.
- Pasado el límite de intentos, el login y la renovación responden con rechazo; las sesiones vencidas se borran solas.
- Un pedido a `/clubes/{clubId}/…` sin membresía activa o sin el rol necesario es rechazado, y con otro `clubId` no devuelve datos del club ajeno.
- El test de aislamiento se aplica a cualquier endpoint con una sola llamada.
- Correr el script de alta dos veces deja la base igual: club Maktub, usuarios, membresías coach + atleta, atletas y clubes personales, sin duplicados.
- En la app, el ingreso guarda los tokens, los pedidos llevan el header, las renovaciones simultáneas se hacen de a una y cerrar sesión revoca la sesión del dispositivo.
- Un usuario que es solo atleta no ve el editor de planificación.

## Bloqueos externos

- El client ID de OAuth con el origen `https://ariadnavillagra.github.io` (sin ruta) y `http://localhost`, creado por el usuario en la consola de GCP. Sin él no se puede probar la contingencia ni 1.3 ni 1.6.
- La carga de `https://ariadnavillagra.github.io` en `ORIGENES_PERMITIDOS` (E0).

## Issues

| # | Issue | Depende de |
|---|---|---|
| E1.1 | [Client ID de OAuth en GCP (manual)](E1.1-client-id-oauth.md) | — |
| E1.2 | [Reuso: solo cuenta un secreto ya rotado](E1.2-reuso-solo-secreto-rotado.md) | — |
| E1.3 | [Limpieza de sesiones vencidas (TTL)](E1.3-ttl-sesiones.md) | — |
| E1.4 | [Colecciones de acceso e índices únicos](E1.4-colecciones-acceso.md) | — |
| E1.5 | [Endpoint "quién soy"](E1.5-quien-soy.md) | E1.4 |
| E1.6 | [Verificar el ID token de Google](E1.6-verificar-id-token-google.md) | E1.1 |
| E1.7 | [Endpoint de ingreso con Google](E1.7-ingreso-google-backend.md) | E1.1, E1.2, E1.4, E1.6, E0.1 |
| E1.8 | [Límite de intentos en memoria](E1.8-limite-intentos.md) | E1.7 |
| E1.9 | [Script de alta idempotente](E1.9-script-alta.md) | E1.4 |
| E1.10 | [Contexto de club](E1.10-contexto-club.md) | E1.4, E1.5 |
| E1.11 | [Test de aislamiento reutilizable](E1.11-test-aislamiento.md) | E1.10 |
| E1.12 | [App: sesión](E1.12-app-sesion.md) | E1.7 |
| E1.13 | [App: ingreso con Google](E1.13-app-ingreso-google.md) | E1.1, E1.7, E1.9, E1.12, E0.1 |
| E1.14 | [App: planificación según el rol](E1.14-app-rol-planificacion.md) | E1.5, E1.10, E1.13 |

**En paralelo:**
- E1.1 (manual), E1.2, E1.3 y E1.4 arrancan juntos.
- Después de E1.4 se pueden tomar E1.5 y E1.9 a la vez. E1.6 sigue a E1.1.
- La rama del club (E1.10 → E1.11) es independiente de la del ingreso (E1.7 → E1.8 y E1.12).
- E1.13 y E1.14 cierran la épica.
- R2 se prueba sobre `github.io` al mergear E1 (D2).
