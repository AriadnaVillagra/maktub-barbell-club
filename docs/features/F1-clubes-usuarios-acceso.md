# F1 — Clubes, usuarios y acceso

Estado: listo para desarrollar, con los supuestos de la sección 8 por confirmar. 2026-11-07.
Contexto: [diseño general](../diseno.md), §3.1 y decisiones P1, P1b, A1–A6.

## 1. Objetivo

Que cada persona entre con su cuenta, use la app sola o dentro de uno o varios clubes, y que el
backend sepa en cada pedido **quién es, en qué club está actuando y con qué rol**. Todo lo demás
(planes, sesiones, registro) se apoya en esto.

## 2. Alcance

- Registro e inicio de sesión con **Google** o con **email y contraseña**, unificados por email.
- Verificación de email y recuperación de contraseña.
- **Club personal** creado automáticamente con cada usuario.
- **Crear un club**: quien lo crea queda como coach.
- **Invitaciones** del coach (link o código) con roles, vencimiento y revocación.
- **Membresías** con roles `coach` y/o `atleta`; salir de un club y quitar miembros.
- **Administrador de plataforma** como marca en el usuario.
- **Selector de club** en la app: el club personal más los clubes de los que es miembro.
- Autorización en el backend: autenticación, contexto de club, rol y filtrado por `clubId` en todo
  endpoint.

## 3. Fuera de alcance

- Buscar clubes públicos o pedir unirse sin invitación.
- Otros proveedores de login (Apple, Facebook).
- Facturación o planes pagos.
- Borrado de cuenta y exportación de datos personales (ver 8).
- Biblioteca de planes por defecto: el club personal la consume, pero se construye con el editor
  (F5/F6) y la asignación (F7).

## 4. Modelo

| Entidad | Campos principales | Notas |
|---|---|---|
| **Usuario** | id, email (único, normalizado), nombre, email verificado, credenciales (Google sub, hash de contraseña; una o ambas), es administrador de plataforma, club personal | Sin `clubId`: es la única entidad global junto con las de plataforma. |
| **Club** | id, nombre, tipo (`personal` \| `club`), creado por | El club personal tiene un único miembro. |
| **Membresía** | clubId, usuarioId, roles (`coach`, `atleta`), estado (`activa` \| `terminada`), desde, hasta | Única por club y usuario. Terminarla no borra nada. |
| **Invitación** | clubId, código, roles a otorgar, creada por, vence, usos máximos, usos, revocada | El link contiene el código. |
| **Sesión de login** | usuarioId, refresh token (guardado como hash), dispositivo, vence, revocada | Una por dispositivo. |
| **Atleta** | clubId, usuarioId, nombre visible | Se crea al obtener el rol `atleta` en un club. Los datos de carga llegan en F3. |

Todos los documentos con `clubId` llevan además la auditoría que ya existe en `maktub_core`.

## 5. Reglas

**Identidad**

- Un email identifica a un usuario. Si una persona entra con Google y ya existe una cuenta con
  contraseña con ese email (o al revés), **se vincula a la misma cuenta**, siempre que el email esté
  verificado (Google ya lo trae verificado).
- Las contraseñas se guardan con un hash lento (argon2 o bcrypt) y nunca viajan de vuelta.
- El backend verifica el token de Google o la contraseña y **emite su propia sesión**: un token de
  acceso de vida corta y un refresh token que rota en cada uso. Cerrar sesión revoca el refresh
  token de ese dispositivo.
- **Los tokens viajan en un header, no en cookies.** La app (`github.io`) y la API (`run.app`)
  están en sitios distintos, y los navegadores bloquean las cookies entre sitios (Safari en
  especial). Por eso el refresh token no puede ir en una cookie httpOnly: la app lo guarda y lo
  manda en un header al renovar. Como queda al alcance del JavaScript de la app, la rotación en cada
  uso y la detección de reuso (si se usa un refresh token ya rotado, se revoca toda la sesión de ese
  dispositivo) son obligatorias, no opcionales. Con un dominio propio común (`app.` y `api.`) se
  podría volver a cookies httpOnly.
- **Solo un secreto ya rotado cuenta como reuso.** Un secreto que nunca fue válido se rechaza sin
  revocar nada: el id de la sesión se lee en el token de acceso, y si cualquier secreto erróneo
  revocara la sesión, quien tenga ese token podría cerrar la sesión de otro dispositivo.
  (Decidido en M1, 2026-11-07.)
- Las sesiones vencidas se borran solas (índice TTL).
- **El ID token de Google se verifica en el backend sin SDK de Google**: firma RS256 contra las
  claves públicas que publica Google, más `aud` (el client ID), `iss`, `exp` y `email_verified`.
  Se guarda el `sub` de Google en el primer ingreso. En web, la app obtiene el token con el botón
  que dibuja Google: `google_sign_in` no permite iniciar sesión por código. (M1, 2026-11-07.)
- Un email sin cuenta que entra con Google recibe un rechazo claro con un código que no es 401,
  porque la app trata 401 como "renovar el token".
- El login, el registro y la recuperación tienen límite de intentos, y también la renovación del
  token. Mientras el backend corra en una sola instancia, el límite se lleva en memoria.

**Clubes y membresías**

- Al registrarse, se crea el **club personal** del usuario, con una membresía con roles
  `coach` + `atleta` pero con capacidades recortadas (ver la matriz): en el club personal no se
  planifica.
- Crear un club da al creador los roles `coach` + `atleta`. Puede quitarse `atleta` si no entrena.
- **Un club siempre tiene al menos un coach activo.** No se puede quitar ni hacer salir al último.
- Aceptar una invitación exige estar logueado. Crea la membresía con los roles de la invitación y,
  si incluye `atleta`, el perfil de atleta. Si ya era miembro, suma los roles que falten.
- Terminar una membresía corta el acceso al club. Los registros que el usuario escribió y su
  historial como atleta **se conservan**: el historial no miente.

**Contexto de cada pedido**

- Todo pedido autenticado indica en qué club actúa. El backend verifica que haya una membresía
  activa, que el rol alcance para la acción y **filtra cada consulta por ese `clubId`**.
- **El club viaja en la ruta**: `/clubes/{clubId}/…`. Queda explícito en cada endpoint, es fácil
  de auditar y de cubrir con el test de aislamiento, y no hace falta tocar CORS. Las rutas sin club
  son solo las de la sesión (`/auth/…`) y la de "quién soy", que devuelve el usuario, sus clubes y
  sus roles en cada uno. (Decidido en M1, 2026-11-07.)
- Los recursos de plataforma (catálogo base, biblioteca de planes) se leen desde cualquier club y
  solo los escribe el administrador de plataforma.

**Matriz de permisos**

| Acción | Atleta | Coach | Club personal | Admin plataforma |
|---|---|---|---|---|
| Ver catálogo, planes asignados, sus sesiones | ✓ | ✓ | ✓ | — |
| Registrar lo suyo y lo de compañeros de su sesión | ✓ | ✓ | ✓ (solo él) | — |
| Ver reportes propios | ✓ | ✓ | ✓ | — |
| Editar sus referencias (RMs, marcas) | — | ✓ (de todos) | ✓ | — |
| Planificar, asignar, editar catálogo del club | — | ✓ | — | — |
| Seguir un plan por defecto | — | — | ✓ | — |
| Invitar, quitar miembros, cambiar roles | — | ✓ | — | — |
| Ver reportes de todos | — | ✓ | — | — |
| Editar catálogo base y biblioteca de planes | — | — | — | ✓ |

## 6. Interfaz

**Recursos del backend** (nivel de diseño; las rutas exactas se definen al implementar):

- autenticación: registrarse con email, verificar email, iniciar sesión con email, iniciar sesión
  con Google, renovar sesión, cerrar sesión, pedir y confirmar cambio de contraseña;
- yo: datos del usuario y la lista de sus clubes con roles;
- clubes: crear, ver y renombrar;
- miembros: listar, cambiar roles, quitar, salir;
- invitaciones: crear, listar, revocar, ver los datos públicos de un código, aceptar.

**Pantallas**:

- ingreso: "Continuar con Google" + email y contraseña, registro, recuperación;
- selector de club (en la barra o el menú), recordando el último usado;
- crear club;
- miembros del club: lista con roles, invitar (genera link y código para compartir), invitaciones
  pendientes;
- aceptar invitación: al abrir el link, ver nombre del club y roles; si no hay sesión, ingresar y
  volver.

## 7. Criterios de aceptación

1. Un usuario se registra con email, recibe el email de verificación, lo confirma e inicia sesión.
2. Un usuario recupera su contraseña desde el email recibido.
3. Un usuario que se registró con email y después entra con Google con el mismo email llega a la
   **misma cuenta**, con sus mismos clubes y datos.
4. Un usuario recién registrado aterriza en su club personal y puede elegir un plan por defecto.
   No ve el editor de planes.
5. Un usuario crea un club y queda como coach y atleta.
6. El coach genera una invitación de atleta. Otro usuario abre el link, inicia sesión y aparece en
   la lista de atletas del club. Una invitación vencida, revocada o sin usos disponibles se rechaza
   con un mensaje claro.
7. Un atleta que llama a una acción de coach recibe un rechazo por permisos.
8. **Aislamiento**: un usuario del club A no puede leer ni escribir nada del club B, aunque conozca
   los ids. Esto se prueba en cada endpoint con datos del club, no solo en los de F1.
9. No se puede quitar ni hacer salir al último coach de un club.
10. Un miembro que sale de un club pierde el acceso, y su historial sigue visible para el coach.
11. El token de acceso vencido se renueva solo, también en Safari con la app en `github.io` y la API
    en otro dominio. Cerrar sesión en un dispositivo no cierra los demás. Reusar un refresh token ya
    rotado revoca la sesión de ese dispositivo.
12. Muchos intentos fallidos de login seguidos se frenan.

## 8. Supuestos a confirmar

| # | Supuesto | Por qué importa |
|---|---|---|
| S1 | Quien crea un club recibe `coach` + `atleta` por defecto. | Ari y Andi planifican y entrenan. |
| S2 | Un club puede tener **varios coaches**, todos con los mismos permisos. | Simplifica; no hay "dueño" del club. |
| S3 | El email de verificación y recuperación se envía por **SMTP de Gmail con contraseña de aplicación**, detrás de una interfaz de envío. Sin dominio propio no se pueden cargar los registros DNS que piden SES y servicios similares; se pasa a uno de ellos cuando haya dominio. Gmail tiene límites diarios de envío, que alcanzan para el grupo chico. | El login con email no funciona sin un servicio de email. Propuesto por la sesión del setup tras el cambio de P10b. |
| S7 | Google Sign-In funciona con el origen `https://<usuario>.github.io` usando scopes básicos y sin verificar dominio. | Si no, el login con Google queda frenado hasta tener dominio. Confirmar al empezar la tarea 4. |
| S4 | Borrar la cuenta queda fuera por ahora. Cuando se haga, el historial se anonimiza en vez de borrarse. | Choca con "el historial no miente". |
| S5 | **Migración**: como no hay atletas sin usuario, los usuarios de Andi y Ari se crean por script con su email antes de migrar. Al entrar con Google con ese email, toman la cuenta. | F14 depende de esto. |
| S6 | El club personal no aparece en los reportes del coach de otros clubes; lo que alguien entrena solo es privado. | Privacidad entre contextos. |

## 9. Tareas

En orden. Cada una termina con tests.

1. **Modelos en `maktub_core`**: Usuario, Club, Membresía, Invitación, Atleta (identidad), roles y
   la matriz de permisos como función pura (`puede(rol, acción, tipoDeClub)`).
2. **Backend: sesión propia**: emisión y rotación de tokens, colección de sesiones de login,
   middleware que resuelve el usuario.
3. **Backend: email y contraseña**: registro, hash, verificación, recuperación, límite de intentos,
   envío detrás de una interfaz: SMTP de Gmail en producción y un emisor falso en desarrollo.
4. **Backend: Google**: verificación del ID token y vinculación por email.
5. **Backend: contexto de club**: middleware de club + rol, y filtro obligatorio por `clubId` en el
   acceso a Mongo, con un test de aislamiento reutilizable por cualquier endpoint.
6. **Backend: clubes, membresías e invitaciones**, incluido el club personal al registrarse y la
   regla del último coach.
7. **Administrador de plataforma**: marca en el usuario, asignable solo por script.
8. **Frontend: ingreso**: pantallas de login/registro/recuperación, Google Identity Services,
   guardado de los tokens en la app (no en cookies), envío por header y renovación automática.
9. **Frontend: clubes**: selector de club, crear club, miembros, invitar, aceptar invitación por link.
10. **Frontend: gating por rol**: navegación y acciones según la matriz (por ejemplo, el club
    personal no muestra el editor).
