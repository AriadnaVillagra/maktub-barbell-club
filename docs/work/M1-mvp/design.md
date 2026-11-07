# M1-mvp: diseño

Escrito el 2026-11-07. Parte de [findings.md](findings.md) (estado actual) y de
[docs/milestones/M1-mvp.md](../../milestones/M1-mvp.md) (en adelante, "M1"). M1 ya fija el
objetivo, el alcance, las decisiones M1-D1 a M1-D5, las etapas con sus dependencias y los
criterios de aceptación. Este documento no repite eso. Agrega lo que la preparación y el diseño
decidieron encima de M1 y lo que hay que cambiar en cada parte del sistema.

## 1. Estado deseado

Es el de M1 §1: Andi y Ari entrenan solo con la app nueva, que hace lo mismo que la referencia sobre
el modelo de `docs/diseno.md`, con los defectos conocidos corregidos y sin funcionalidades nuevas.
El historial de la planilla está migrado, con octubre corregido. El alcance y lo que queda fuera son
los de M1 §2 a §4.

## 2. Decisiones de este diseño

Las decisiones que siguen valiendo después de M1 ya se pasaron a su lugar definitivo. Las de acceso
(D5 y D7, y la verificación del token de Google de 3.2) están en
[F1 §5](../../features/F1-clubes-usuarios-acceso.md). La del service worker propio (D8) está en la
sección de frontend de `CLAUDE.md`. El resto vale solo para M1.

| # | Decisión | Por qué |
|---|---|---|
| D1 | M1 es **un solo ítem**. Las etapas de M1 §5 son el primer nivel del breakdown y hay un solo tracker. | El plan ya está ordenado por etapas. Partirlo en ítems repetiría la preparación y el diseño sin ganar nada. |
| D2 | Lo que ya estaba en `auth` (1.1 y 1.2) se mergea a `main` el 2026-11-07 y la rama `auth` se borra. El resto va en la rama `m1-mvp`, que **se mergea a `main` al cerrar cada épica**. 9.2 es el último de esos merges y **va antes de 9.1** (prueba en el gimnasio), que es al revés que en M1. Cambiado en el breakdown; antes decía "todo en `auth` hasta 9.2". | El workflow de Pages solo publica desde `main`. Mergear por épica permite probar R2 sobre `github.io` al cerrar E1 y validar lo publicado sin esperar al final. La prueba en el gimnasio necesita la PWA nueva en los teléfonos. |
| D3 | Lo que solo se puede ver en la PWA publicada (abrir sin señal, instalación) se valida después del merge de la épica que lo entrega. | Es la consecuencia de D2. |
| D4 | No hay fecha objetivo. | Decisión del usuario. |
| D5 | Entran en M1 tres arreglos sobre la sesión ya hecha (1.2): la detección de reuso, un rate limit y la limpieza de sesiones vencidas. Ver 3.2. | La verificación encontró que hoy se puede cerrar la sesión de otro dispositivo, y F1 pide rate limit (criterio 12). |
| D6 | El script de alta (1.5) crea también los **clubes personales** de Andi y Ari, sin interfaz. | `Usuario.clubPersonalId` es obligatorio. Así el modelo no cambia y no hay nada que migrar cuando se complete F1. |
| D7 | El club activo viaja **en la ruta** (`/clubes/{clubId}/…`). | Queda explícito en cada endpoint, es fácil de auditar y de cubrir con el test de aislamiento, y no hay que tocar CORS. |
| D9 | E6 entrega el calendario: la asignación, qué toca hoy por fecha y la posibilidad de elegir otro día. **Marcar los días hechos y pendientes** lo completa E7, cuando existen las sesiones. Decidido en el breakdown (2026-11-07). | M1 6.2 pide días hechos, pero el dato sale de las sesiones de E7, que va después de E6. |
| D10 | Los **grupos musculares y patrones base** entran en M1 como datos: modelo en `maktub_core` y carga en la semilla del catálogo, en E2. Su interfaz sigue fuera (M1 §4). Decidido en el breakdown. | El ejercicio los referencia y la semilla los necesita, y ningún cambio los creaba. |
| D11 | La regla de **archivar en vez de borrar si está en uso** (E2) consulta el uso a través de una interfaz, probada con fakes. E5 (planes) y E7 (registros) suman sus consultas reales cuando existen. Decidido en el breakdown. | Planes y registros recién existen en E5 y E7, y E2 va antes. |
| D12 | **La exportación a CSV (8.1) se adelanta**: no depende de nada y se hace antes de E4, porque los casos de verificación de las reglas de carga salen de ahí. Sigue siendo parte de E8. Decidido en el breakdown. | El banco de pruebas de la referencia (`mock.js`) se perdió, así que los kilos esperados solo están en la planilla. |
| D13 | **Qué día abre la app**, como en la referencia (`reference/Index.html`, `primerDiaPendiente`): la fecha da el ciclo y la semana, y el día es el primero de esa semana sin series registradas, o el día 1 si están todos hechos. En M1 se mira la sesión del grupo, no a cada atleta. Hasta que existan sesiones (E7) se abre el día 1 y se elige a mano. Decidido en el breakdown. | Reproduce la referencia, y encaja con D9. |
| D14 | **El grupo de atletas lo crea el script de alta** (el de Andi y Ari); no hay pantalla de grupos en M1. Un grupo tiene **a lo sumo una asignación activa**. Decidido en el breakdown. | Hay un solo grupo, y es lo mínimo que reemplaza la estrella de "plan activo". |
| D15 | **Cada escritura que tiene que ser atómica toca un solo documento**, porque el driver `mongo_dart` (0.10.10) no tiene transacciones. Un plan se guarda entero como un solo documento. El reinicio del factor a 100 % cuando hay un RM nuevo no se escribe: se deriva por regla (un factor con fecha anterior al último RM de ese ejercicio no cuenta, y vale 100 %). Decidido en el breakdown; reemplaza la idea anterior de usar transacciones sobre un replica set local. | Verificado en el código del paquete: no expone `startTransaction`, `withTransaction` ni `commitTransaction`. |
| D16 | Cómo se traducen primario, secundario y accesorio de la referencia (series por defecto, validación de "día sin primario") al modelo de bloques con categoría **lo propone E5.1 leyendo `reference/`, y el usuario lo aprueba** antes de cerrarlo. Decidido en el breakdown. | El diseño no lo fija y depende del detalle de la referencia. |
| D8 | Sin señal tiene que abrir **la app y los datos del día** (sesión, plan y referencias), y se tiene que poder marcar series. | Es el criterio 8 de M1. Flutter 3.47 ya no trae un service worker útil (ver 3.4). |

## 3. Cambios por parte del sistema

### 3.1 `maktub_core`

- **Modelos nuevos**, con todos los campos que define `diseno.md` aunque M1 no los use, como pide
  `CLAUDE.md`: catálogo (ejercicio, categoría, equipo del club en datos, temporizador con ámbito),
  referencias con historial y vigencia, factor de trabajo, kilaje fijo, plan (modelo de semana,
  asignación de las 4 semanas, día, bloque con modos, prescripción, serie), grupo, asignación,
  sesión y registro por serie.
- **Reglas de carga completas** (4.1), sobre lo que ya hay en `reglas/`: factor de trabajo, kilaje
  fijo, barra vacía en la rampa, ajuste del día por atleta en dos niveles, series tocadas que no se
  pisan, y `%` derivado de kg escritos a mano. Se verifican contra los casos de `reference/`.
- `Usuario` y los modelos de acceso no cambian (D6).

### 3.2 Backend: acceso

- **Login con Google**, que hoy no existe. El backend verifica el ID token sin SDK de Google:
  firma RS256 contra el JWKS publicado por Google, más `aud` (el client ID), `iss`, `exp` y
  `email_verified`. Después busca al usuario por email normalizado y abre la sesión con lo que ya
  existe de 1.2. Guarda el `sub` de Google en el primer ingreso.
- **Rechazo de emails no dados de alta** con un mensaje claro y un código que no sea 401, porque la
  app trata un 401 como "renovar token".
- **Detección de reuso, corregida** (D5). Hoy cualquier secreto erróneo con un id de sesión válido
  revoca la sesión, y el id se lee en el payload del access token. Tiene que contar como reuso solo
  un secreto que ya fue válido y se rotó.
- **Rate limit** en memoria (D5), al menos para el login y la renovación. La memoria alcanza porque
  el backend corre en una sola instancia.
- **Limpieza de sesiones vencidas** con un índice TTL (D5).
- **Endpoint de "quién soy"**, con el usuario, sus clubes, sus roles en cada uno y si es
  administrador de plataforma. La app lo necesita para saber qué mostrar.

### 3.3 Backend: contexto de club y dominio

- **Contexto de club** (1.4), en la ruta (D7). Verifica que haya una membresía activa y el rol que
  pide cada acción, según la matriz que ya existe en `maktub_core`.
- **Filtro obligatorio por `clubId`**, con la regla de lectura de `diseno.md`: plataforma + club
  actual.
- **Test de aislamiento reutilizable** que se pueda aplicar a cualquier endpoint.
- **Colecciones nuevas** de acceso y de dominio, con índices únicos donde la unicidad es una regla:
  email del usuario, membresía y atleta por club y usuario, código de invitación. El script de alta
  depende de esos índices para ser idempotente.
- **Slices de dominio**, como cortes verticales: catálogo, referencias, plan, asignación, y sesión
  con upsert idempotente por serie.
- **Canal en vivo** (7.3): ticket de un solo uso, WebSocket por sesión, número de secuencia,
  resincronización al reconectar y difusión en memoria detrás de una interfaz.

### 3.4 Frontend

- **Ingreso con el botón de Google.** En web, `google_sign_in` no permite iniciar sesión por código:
  hay que usar el botón que dibuja la librería de Google y mandar el ID token al backend apenas
  llega.
- **Sesión en la app:** tokens guardados, header de autorización, renovación de a una, cierre de
  sesión. Lo que se muestra depende del rol.
- **Pantallas:** catálogo, ficha de atleta, editor de plan, asignación y calendario, sesión del día.
- **Sin señal** (D8):
  - un **service worker propio** que guarde la app. El que genera Flutter 3.47
    (`flutter_service_worker.js`) es un stub que se desregistra solo, verificado en
    `apps/frontend/build/web`;
  - almacenamiento local de los datos del día;
  - la cola de reintentos;
  - el cliente del canal en vivo con reconexión.

### 3.5 Scripts

- **Alta** (1.5): club Maktub, usuarios, membresías coach + atleta, atletas y clubes personales (D6).
  Idempotente.
- **Semilla del catálogo base** (2.4), con una lista que el usuario aprueba antes de cargarla.
- **Importador y verificación de la migración** (8.2, 8.3).
- **Backup** con `mongodump` (0.3).

### 3.6 Infraestructura externa

Nada de esto está en el repo.

- **Client ID de OAuth** en el proyecto de GCP, con el origen `https://ariadnavillagra.github.io`
  (sin ruta) y `http://localhost` para desarrollo. La pantalla de consentimiento puede quedar en
  modo prueba con los dos usuarios.
- **CORS:** cargar ese origen en `ORIGENES_PERMITIDOS`. Hoy la API no devuelve
  `Access-Control-Allow-Origin` para él (verificado), así que la PWA publicada no llega a la API.
- **Backup:** un bucket de Cloud Storage y un job programado de Cloud Run.
- **GitHub Pages:** ya publica desde `main` (verificado). No cambia.

## 4. Relaciones

### 4.1 Lo que tiene que existir antes

Son las dependencias de M1 §5 ("Depende de") y el gráfico de M1 §6, con un solo cambio: 9.2 va
antes de 9.1 (D2). Además:

- El client ID de OAuth y la carga del origen en CORS van antes de 1.3 y 1.6.
- El CSV de la planilla (8.1) va antes de 8.2.
- La corrección de la detección de reuso va antes de que haya usuarios reales con sesión, o sea
  antes del merge de E1 (D2).
- El CSV (8.1) va antes de los casos de verificación de E4 (D12).

### 4.2 El diseño vale solo si…

| Supuesto | Qué depende de él | Si falla |
|---|---|---|
| Google acepta `https://ariadnavillagra.github.io` como origen del client de OAuth (M1 R2) | 1.3, 1.6 y todo lo que necesita un usuario logueado | Cambia la forma del login (dominio propio u otro hosting). Mientras se construye, se prueba con `localhost`; sobre `github.io` se prueba al mergear E1 (D2). |
| Cloud Run sostiene el WebSocket con una sola instancia, con reconexión cada 60 min como máximo (M1 R1) | 7.3, 7.5 y el criterio 7 | Hay que repensar el canal en vivo. Por eso 7.3 arranca apenas existe 7.2. |
| 4.1 reproduce los kilos de la referencia para los mismos RM | 7.4, la migración (8.2) y el criterio 5 | La sesión y la verificación de la migración no se pueden dar por buenas. |
| Un service worker propio funciona en la PWA instalada, dentro del scope `/maktub-barbell-club/` | 0.2, 7.5 y el criterio 8 | No hay modo sin señal tal como está diseñado. |
| El CSV exportado cubre todas las hojas de `reference/Esquema.gs` | 8.2 a 8.4 y el criterio 10 | La migración queda incompleta. |

## 5. Aceptación y cierre del ítem

Se aceptan los 11 criterios de M1 §7. El ítem se cierra cuando se cumple, en este orden:

1. `main` desplegado con todo lo de M1 (9.2).
2. La prueba en el gimnasio: una semana con dos teléfonos y la sesión en vivo (9.1), con los
   problemas encontrados corregidos.
3. La prueba manual del usuario sobre la PWA de producción.
4. El corte: la planilla congelada, lo último importado y el paso a la app (8.4).
5. Un ciclo completo de 4 semanas entrenado solo con la app (criterio 11).

## 6. Preguntas abiertas

| Pregunta | Qué frena |
|---|---|
| R4 de M1: `diseno.md` no refleja el recorte de M1. Su camino crítico todavía incluye F10 (motor de pasos) y describe F1 a F12 completas. Lo tiene que resolver la sesión que mantiene `diseno.md`. | Nada. Se decidió avanzar igual. |
