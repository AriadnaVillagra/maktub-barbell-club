# M1-mvp: tracker

Ítem: [item.md](item.md) · Diseño: [design.md](design.md) · Hallazgos: [findings.md](findings.md)

Rama: `m1-mvp`. Se mergea a `main` al cerrar cada épica (design.md D2).

## Cómo se lee

- **Escalera:** ítem → épica (`E<n>`) → issue (`E<n>.<m>`). Las dependencias de cada issue y qué se
  puede tomar en paralelo están en la sección "Issues" de su épica.
- **Estados:**
  - `sin refinar`: la entrada todavía no tiene hijos.
  - `pendiente`, `en curso`, `hecho`.
  - `bloqueado`: algo fuera del ítem frena la entrada. La causa se anota con ← y apunta a lo que
    falta.
- Que un issue espere a otro issue del ítem no lo bloquea: es el siguiente, no está bloqueado.
- Solo se edita desde la conversación principal.

## Épicas

| # | Épica | Estado | Issues | Bloqueos |
|---|---|---|---|---|
| E0 | [Cerrar F0](E0-cerrar-f0.md) | hecho | 6 / 6 (mergeada a `main`) | — |
| E1 | [Acceso](E1-acceso.md) | hecho | 14 / 14 (mergeada a `main`; ingreso probado en localhost:5000 y en Pages, R2 ok) | — |
| E2 | [Catálogo](E2-catalogo.md) | hecho | 10 / 10 (mergeada a `main` y semilla cargada; prueba en producción ok) | — |
| E3 | [Atletas y referencias](E3-atletas-referencias.md) | hecho | 8 / 8 (mergeada a `main`; en producción) | — |
| E4 | [Reglas de carga](E4-reglas-de-carga.md) | hecho | 6 / 6 (mergeada a `main`; en producción) | — |
| E5 | [Editor de plan](E5-editor-de-plan.md) | hecho | 15 / 15 (mergeada a `main`; en producción) | — |
| E6 | [Asignación y calendario](E6-asignacion-calendario.md) | hecho | 7 / 7 (mergeada a `main`; en producción; el día abre en 1 hasta E7.13; E6.7 en `m1-mvp`) | — |
| E7 | [Sesión y registro en vivo](E7-sesion-en-vivo.md) | hecho | 27 / 27 (mergeada a `main`, PR #11; la prueba real con dos teléfonos y modo avión queda en E9.2 y E9.3) | — |
| E8 | [Migración](E8-migracion.md) | hecho | 10 / 10 (mergeada a `main`, PR #11; migración cerrada el 2026-11-19. Lo que falta de Octubre 2026 y Levantamiento lo hace Ari a mano en la app, ver E8.6) | — |
| E9 | [Cierre](E9-cierre.md) | en curso | 1 / 8 (E9.1 hecho: PR #11 y versión 1.6.0+7 desplegada) | E9.3, E9.5, E9.7 ← disponibilidad de Andi y Ari (pasos manuales) |

Ya hecho antes de abrir el ítem: M1 1.1 y 1.2 (`eb26f6e`, `1bcd49f`), mergeados a `main` el
2026-11-07.

## Preguntas abiertas que vienen del diseño

- R4 (`diseno.md` no refleja el recorte de M1): no frena nada. Ver design.md §6.

## Ajustes tras la prueba de E2 (2026-11-08)

Hechos en `m1-mvp`: etiquetas Default/Custom, rol `admin_club` y alta de miembros,
pestaña Preferencias, inventario de equipo con barra por ejercicio, cinco modos de temporizador.

- **Antes de usarlo en producción:** desplegar la API y la PWA juntas, y correr `tool/ajustes_e2.dart`
  con `ADMIN_PLATAFORMA`. Sin ese paso, los coaches actuales pierden la edición del catálogo.
- **`diseno.md` quedó atrás** en C1 (ejercicios base) y en Equipo (S3 de F2). Se actualiza desde su sesión.
- **E5 (editor de plan):** la barra se indica por ejercicio, y la prescripción la puede pisar con una barra opcional (decidido el 2026-11-08). El control va en el editor (E5.7 o E5.8), y E4/E7 tienen que usar esa barra al calcular.
- **E7.11 (ejecución):** for time sin tope y Death By tienen fases sin fin fijo que `Crono` todavía no maneja. El temporizador base `Cronómetro` (for time sin tope, agregado el 2026-11-08) depende de esto: tiene que contar hacia arriba y dejar registrado el tiempo final del WoD.
- **Datos en producción (2026-11-08):** ya están el grupo de Andi y Ari, el temporizador `Cronómetro` y los roles de E2.

## Para E7 (salió de E7.3, 2026-11-08)

- **Kilos propuestos (E7.7):** el servidor los entrega en un endpoint nuevo, por atleta y sesión. El atleta no recibe su factor, así que la app no los puede calcular sola.
- **Nota (E7.8, decidido el 2026-11-09):** hay una por ejercicio, en `SetRecord.note` de la primera serie, y una por sesión, en `Session.note` (`PUT .../sesiones/{id}/nota`). Un ejercicio sin series no tiene dónde guardarla, así que no ofrece nota. `diseno.md` todavía no tiene estos dos campos.
- **Restaurar (E7.8, decidido el 2026-11-09):** "Volver a lo planificado" es por ejercicio. Devuelve kilos y reps a lo propuesto y deja las series marcadas como estaban; distinto de la referencia, que las desmarcaba.
- **Sin probar en real (E7.8):** marcar, editar, notas y restaurar solo pasaron tests. Los stores corrieron contra MongoDB, pero la pantalla no se abrió en un navegador contra la API.
- **Republicar a mitad de sesión:** la sesión no guarda copia del plan y los registros se ubican por posición, así que pueden quedar apuntando a otro ejercicio. Decidido: no se cubre en M1, no republicar con una sesión a medias.
- **Pendiente:** `presentes` solo acumula, no hay forma de quitar a alguien. `AthleteDay` todavía no se escribe, y E7.13 deriva hecho o pendiente de las sesiones y sus series.
- **Sin probar en real (E7.7):** la pantalla de sesión solo pasó tests, no se abrió en un navegador contra la API. `MongoProposedLoadsStore` no corrió contra MongoDB.
- **Nombres de compañeros (sin decidir):** `GET /atletas` es solo para coach, así que un atleta sin ese rol ve "Yo" y "Atleta N". No afecta a Andi y Ari.
- **Pings (E7.6, hecho):** el servidor manda un ping cada 30 s, como midió E7.1. Falta comprobarlo en Cloud Run con una conexión sin tráfico.
- **Canal en vivo (E7.6, para E7.10):** el contador va en la sesión. Cada mensaje es un `SessionChange` con el estado completo de un registro o de la sesión (nota y presentes). El cliente se conecta primero y después pide `GET .../cambios?desde=N`, y recuerda el número más alto visto: los números pueden saltear, así que un salto no indica pérdida. El dispositivo que escribe también recibe su propio cambio.
- **Dos réplicas (E7.6):** repetir una escritura ya no toca nada, tampoco la auditoría. Las escrituras de una sesión se hacen en fila dentro del proceso, lo que solo vale con una instancia. Si algún día hay más, esa fila también hay que reemplazarla, no solo la difusión.
- **Sin probar en real (E7.6):** los stores corrieron contra MongoDB y el WebSocket contra un servidor local en los tests, con el store falso. No se probó en Cloud Run ni con dos teléfonos; eso queda para E7.10.
- **`diseno.md` (E7.6):** tampoco tiene `secuencia` en sesión y registro ni `secuenciaSesion` en sesión.
- **Borrador y cola (E7.9, hecho):** el borrador va en `shared_preferences` (`localStorage` en la PWA). Con señal, la pantalla sigue esperando la respuesta del servidor; solo muestra la marca antes si la escritura queda en cola. La cola reintenta cada 15 s, y un 4xx la saca de la cola. Para E7.10: `SetSyncQueue.pending`, `changes` y `flush()` al reconectar. Una escritura que sale en segundo plano no trae los kilos calculados del servidor hasta reabrir la sesión, o hasta que llegue el cambio por el canal de E7.10.
- **D8 completo (decidido el 2026-11-14):** abrir plan, calendario y sesión sin señal entra en M1. Se agregan E7.14 (kilos propuestos sin sesión, en el servidor), E7.15 (precarga de hoy y los próximos 7 días, más lo último visto) y E7.16 (la sesión se abre en el teléfono y la apertura va a la cola, adelante de las series).
- **Temporizadores (E7.11, hecho):** `TimerPlatform` (sonido, vibración, pantalla encendida) traga los errores. `Crono` se extendió con fases abiertas: for time sin tope cuenta hacia arriba y Death By se puede terminar con "Terminar". El tiempo final queda en `cronoResultsProvider` y no se envía al backend; eso es de E7.12. Un for time con tope dentro de un `mix` no muestra "Terminar", porque `Fase` no sabe el tipo de bloque. El botón "Terminar" de `BarraCrono` no tiene test de widget.
- **Sin probar en real (E7.9, E7.11):** sin red con la PWA instalada (modo avión), y sonido, vibración y pantalla encendida en el teléfono, quedan para después del merge de E7 (D3).

## Modo guiado sumado a E7 (2026-11-14)

- `reference/` se actualizó a la versión viva (`9dc1691`), que tiene el modo guiado en `Guia.html` (design.md D18, D19).
- Entran E7.17 a E7.21. Los tiempos de bloque se registran (D20, reemplaza D17).
- **Para E8.4:** los accesorios con el mismo `grupo` en un día de la referencia son una biserie: se importan
  como un bloque en circuito (E7.18).
- **Temporizadores siempre disponibles (2026-11-14, pedido por Ari):** como el ⏱ de cada cabecera de la referencia. Cada temporizador activo de la sección Temporizadores tiene un botón para iniciarlo. El shell suma "Temporizador" como último ítem de la barra y del riel, que abre el selector sin navegar. Con una sola sección, la barra queda con Entrenamiento y Temporizador.
- **E7.21 (hecho):** los tiempos de bloque van por la cola de E7.9, con su id creado una vez, y salen después de las series. Están indexados por `sessionId`, así que E7.16 solo tiene que reemplazar ese id en las series y tiempos de la cola. Los kg del resumen usan `formatKg` ("77.5", no "77,5"). Un tiempo rechazado con 4xx sale de la cola sin avisar.
- **Prueba en local de Ari (2026-11-14):** pidió elegir secuencial o circuito al entrenar (E7.22), preguntar al empezar si seguir o empezar de cero (E7.23; la rampa de la sentadilla ya estaba marcada desde la lista) y unificar calendario y sesión (E7.24). **Para E7.15 y E7.16:** después de E7.24 el calendario es la pantalla de la sesión.
- **E7.22 a E7.24 (hechos):**
  - E7.22: cada pasada de bloque guarda su propio orden, sin cambiar el plan.
  - E7.23: "Hacer todo de nuevo" nunca desmarca. Una serie rehecha se escribe con lo propuesto y pisa la anterior. "Terminar bloque" de un bloque sin pasos reescribe sus series con el plan.
  - E7.24: `CalendarPage` se borró. La sesión tiene el selector "Sesión del día / Calendario", y `/entrenamiento/calendario` abre la vista Calendario. El estado de los días es de todo el ciclo (`cycleDayStatesProvider`) y se refresca al escribir una serie.
- **E7.25 (hecho):** el calendario tiene tres vistas (Compacta, Tarjetas y Detallada), y la elegida se guarda en el dispositivo (`maktub.calendarLayout`). Los ejercicios "principales" son los de bloques de categoría `primario`; si no hay, los del primer bloque con ejercicios. El día de D13 dice "Toca hoy". En el celular, el detalle es un panel abajo y no un modal. Componente nuevo `DayCard` en `maktub_ui`; los goldens del muestrario se regeneraron por la sección nueva de la galería.
- **E7.20 (hecho), decisiones para revisar con Ari:** (1) elegir en el modo guiado a un atleta que no está presente reabre la sesión sumándolo a presentes, porque el backend solo acepta series de presentes; (2) "Terminar bloque" en un bloque por tiempo con series (WoD o EMOM con ejercicios) registra como hechas, con los valores del plan, las series que faltaban, para que el día cuente como hecho; (3) los kg y reps editados quedan en el teléfono hasta "Terminar serie"; (4) el modo guiado avanza sin esperar la escritura, y si una falla muestra el error y el paso queda pasado; (5) un bloque con todas sus series ya registradas se cierra como hecho al tocar "Iniciar bloque". Se entra desde la sesión con "Entrenar" (`/entrenamiento/sesion/entrenar`); la posición se pierde al salir.
- **E7.19 (hecho):** `PUT .../sesiones/{id}/tiempos/{tiempoId}` exige que los atletas estén presentes en la sesión (422 si no). Un id de cliente repetido en otro club da 500 por clave duplicada; se aceptó porque los ids son UUID. Para E8.5: la hoja Tiempos trae nombres de atletas, no ids.
- **`diseno.md`:** no tiene `BlockTime` ni que el modo guiado y parte de F10 entran en M1. Se avisa a su sesión.
- **Revisar el resto de la versión nueva de `reference/`:** tiene más que la versión con la que se planificó M1,
  como menú de entrada, resumen global del plan, editar el día en ejecución, días salteados, rampa
  configurable, medida del ejercicio y ejercicios inactivos. Falta ver si a M1 le falta algo de eso.

## Cierre de E7: canal en vivo y sin señal (2026-11-14)

- **E7.10:** la app pide el ticket, abre el WebSocket y resincroniza con `cambios?desde=N`. Ante un corte reconecta sola (esperas de 0,5 s a 30 s) y muestra "Conectando…". Deja de reintentar con 403/404. Al abrir el canal manda la cola. Un cambio de una serie que todavía está en la cola de este dispositivo se retiene hasta que la escritura sale. Gana el número más alto. El canal se corta al cambiar de día o salir de la pantalla. "Conectando…" no aparece en el modo guiado.
- **E7.14:** `GET .../asignaciones/{id}/kilos-propuestos?desde&hasta` (31 días como máximo, todos los días de la semana de cada fecha). El cálculo del día pasó a `maktub_core` (`set_load.dart`) y lo comparten los dos endpoints. No tiene parámetro `semana`: si alguien elige otra semana, esa semana no queda precargada.
- **E7.15:** la copia local está en `shared_preferences` (`maktub.copy.*`). Se precargan hoy y los 7 días siguientes al iniciar sesión, y se borra lo que tiene más de 14 días. Un 4xx a propósito no usa la copia; sin conexión, un 5xx, un 408 y un 429 sí. Sin señal, el ajuste del día no se recalcula: solo sirven el 100 % o un ajuste ya visto.
- **E7.16:** una sesión abierta sin señal tiene un id `local-…`. La apertura va en la cola adelante de todo, y cuando sale, la cola reemplaza el id por el del servidor en las series, los tiempos y el borrador. El backend no cambió. Si el servidor rechaza la apertura con un 4xx, se descartan también las marcas de esa sesión. Timeouts del cliente: 8 s en lecturas y al abrir, 30 s en escrituras.
- **E7.26 (hecho, salió de la prueba en local):** la sesión tiene `pasadaGuiada` (opcional; sin ella no hay pasada). Se escribe con `POST .../sesiones/{id}/pasada` con una acción (`comenzar`, `iniciar_bloque`, `saltar_bloque`, `terminar_bloque`, `pasar_series`, `dejar`, `terminar`, etc.). La regla `applyGuidedAction` está en `maktub_core`, y la usan el servidor y el teléfono. No se rechazan escrituras por versión: cada acción se aplica sobre el estado actual, y si ya no tiene sentido no cambia nada. Dos "Comenzar" a la vez quedan en una sola pasada. La pasada guarda también las series pasadas y los ejercicios dejados de cada bloque. El id de un tiempo de bloque es `{pasadaId}-{bloque}`. "Terminar el día" con un bloque en curso lo cierra como interrumpido. En la cola, la pasada va después de las series y antes de los tiempos. **`diseno.md`** no tiene `pasadaGuiada`: avisar a su sesión.
- **E7.27 (hecho, salió de la prueba en local del 2026-11-15):** la sesión del día ya no tiene "Abrir sesión" ni "Presentes". Muestra pestañas por atleta del grupo (`TabBar`, en el orden del grupo) y la sesión se crea con la primera escritura (serie, valor, ajuste, nota o "Comenzar"), sumando a presentes al atleta que escribe. Antes de que exista, `GET .../sesiones?asignacionId&fecha&semana&dia` (slice `find_session`, 200 o 204) la busca sin crear nada, se consulta cada 15 s, y los kilos salen de los kilos por fecha con ajuste neutro (los de un día de otra semana usan el primer día de esa semana). Un ajuste que no cambia nada no crea la sesión; si la apertura falla, el ajuste vuelve atrás. El guiado funciona sin sesión hasta "Comenzar" (sin vista previa de bloques antes). Se arregló `SetSyncQueue.submit`, que perdía el rechazo cuando otro flush mandaba la escritura primero. Volver de segundo plano no consulta en el momento: espera la consulta de 15 s. **`diseno.md`** 3.6 y 5.3 todavía dicen que los presentes se eligen al abrir: avisar a su sesión.
- **Sin probar en real:** todo E7.10 a E7.16 y E7.26 pasó solo con fakes (sin WebSocket real, sin modo avión, sin dos teléfonos). Va en la prueba después del merge (D3).

## Para E6 (decidido el 2026-11-08)

Guardar deja un borrador, y publicar (E5.14) exige el plan completo. **E6.3 solo asigna un plan publicado.**
Editar un plan asignado no afecta a los atletas hasta volver a publicar: **E6 y E7 leen siempre la versión
publicada**, nunca el borrador.

## E8.5: decisiones (2026-11-15, aprobadas por Ari)

- Las filas "historico" de Registro (3976) entran en un plan "Histórico" por mes que arma y publica el importador.
- Octubre y Levantamiento: Ari completa los % que faltan y después se publican. No se inventan valores.
- El importador crea las asignaciones ya terminadas (respeta D14): Octubre para "Andi y Ari", Levantamiento solo para Ari.
- Aprobadas las decisiones de la primera parte (`6282bfb`):
  - `OpenSession` con `history: true` acepta asignaciones terminadas o pausadas.
  - Las series históricas quedan como kilos escritos a mano, y la hora de la planilla se toma como Europe/Berlin.
  - Una fila sin reps queda con las reps del plan, y se avisa.
  - "Bloque accesorios" va al primer bloque de accesorios; "Bloque principal" y "Bloque secundario" van al Secundario.
  - La nota del ejercicio va en la primera serie.
- Segunda parte (`9017aa1`):
  - El paso `asignaciones` crea asignaciones terminadas desde `plans.assignments`.
  - `plans.pctFills` tiene en `ajustes.json` las 37 series sin % (26 de Octubre y 11 de Levantamiento), con `pct: null`; Ari los completa.
  - El importador vuelve a guardar y publica sus propios borradores cuando quedan completos.
- Los planes "Histórico" no traen %. Se publican con un modo historial que acepta series sin %, solo desde el importador.
- Tercera parte (`f0fb3f8`): 14 planes "Histórico 2025-05" a "Histórico 2026-10", publicados en modo historial, con asignaciones terminadas para "Andi y Ari". Corrida local: 155 sesiones y 3974 series (2 filas repetidas en Registro); una segunda corrida no cambia nada. Para revisar:
  - Cada mes queda en el ciclo 1, aunque la planilla diga ciclo 2 a 4.
  - En marzo 2026, las semanas 3 y 4 repiten la 2.
  - Se pierden 23 notas de prescripción en atletas que no hicieron la serie 1.
- **Editor del plan, tras probar E8.5 (2026-11-15, pedido por Ari):** los bloques de un día se reordenan arrastrando su manija (≡), sin flechas; cada día tiene "Duplicar día en otro modelo": elegís el modelo de semana y el día se agrega al final de ese modelo, con sus bloques (hasta 7 días).
- **Planes "Histórico" en el editor (2026-11-15, pedido por Ari):** al guardar mostraban un cartel enorme de % faltantes y pedían asignarlos. Se suma un tipo de plan "histórico": el editor no muestra esos avisos ni pide asignar, y se puede publicar sin %. Lo está haciendo un subagente.
- **Filtro en la lista de planes (2026-11-15, pedido por Ari):** "Activos" y "Pasados". Cada plan tiene el campo `pasado` (`Plan.past`), que Ari elige en el editor con el selector Activo / Pasado y se guarda con Guardar. Un plan histórico siempre es pasado y no tiene selector. Reemplaza el criterio por asignaciones que se había elegido antes.
- **Copiar como plan nuevo (2026-11-15, pedido por Ari):** el editor tiene "Copiar como plan nuevo", que crea un plan regular en borrador y activo con los modelos de semana y la asignación del plan guardado, y abre su editor. Sirve para repetir un plan histórico: antes de publicar hay que completar los % que falten.
- **Abril a julio 2026 (pedido por Ari):**
  - En Registro no hay series de esos meses, pero se entrenó con la planificación de abril, repetida.
  - Se importa el plan de abril desde la grilla `ABR_2026` de la planilla de planificación. Se le cargan series de abril a julio con los kilos que propone la app (RM × %), marcadas como estimadas, y Ari corrige lo que haga falta.
  - La grilla de abril no tiene kilos, pero sí los %. Los kilos salen de las RMs ya importadas (E8.3) con las reglas de E4: factor de trabajo y peso cargable más cercano.
  - Es un cambio aparte de E8.5, todavía sin issue. Falta decidir cómo se marca una serie estimada en el modelo de E7.
- **E8.7 (hecho, `9683539` y `1d51587`):**
  - La serie registrada tiene `estimada`. Solo el importador la pone, y cualquier escritura desde la app la saca.
  - El paso `abril` arma "Abril 2026" (histórico) desde la grilla y lo asigna terminado del 1/4 al 31/7.
  - Corrida en una copia: 48 sesiones y 851 series estimadas (395 con kilos y 456 solo con reps). Una segunda corrida no cambia nada, y una serie corregida a mano no se pisa.
  - No entran 1149 series de ejercicios con carga sin kilos en la grilla: sentadilla frontal, peso muerto y bench con "barra de…", sit ups con disco, TGU, etc. Tampoco "windmill", que no está en el catálogo.
  - **Deploy:** desplegar el backend antes de correr el paso contra producción.
  - **`diseno.md`** no tiene `estimada`: avisar a su sesión.
- **E8.8 (hecho, `788e3a5`, `d630ab2`, `b78e3a6` y `9bc9b15`):** una asignación es de un grupo o de un atleta (`grupoId` o `atletaId`), y el plan propio convive con el del grupo. D14 se aplica por dueño, con un índice único para cada tipo: `asegurarIndices` recrea `club_grupo_activa_unica` la primera vez que arranca. Si hay dos planes en el día, la sesión muestra uno por plan para elegir. Levantamiento se asigna a Ari, terminado: en la corrida de prueba entraron 10 series (no 14) y 3 tiempos. **Deploy:** primero el backend y después la PWA. **`diseno.md`** no tiene la asignación por atleta: avisar a su sesión.
- **E8.9 (hecho, 2026-11-16, pedido por Ari):** "Eliminar plan" en el editor, para coach y `admin_club` (acción nueva `Accion.deletePlan`). Borra el plan y sus asignaciones; sesiones, series y tiempos de bloque quedan para los informes. Las lecturas de sesión ya devuelven 404 o vacío sin asignación. Volver a correr el importador recrea un plan importado que se haya eliminado. **Deploy:** primero el backend y después la PWA. **`diseno.md`** no dice que un plan se pueda eliminar: avisar a su sesión.
- **E5.16 (hecho, 2026-11-18, pedido por Ari):** al planificar, una serie por % se escribe en % o en kg, y cada atleta de la asignación con RM queda con su % y sus kg congelados (`PlanSet.porAtleta`). La sesión propone esos kg con el ajuste del día. Se calcula con el factor de trabajo, como en E4. **Deploy:** primero el backend y después la PWA. **`diseno.md`** no tiene `porAtleta`: avisar a su sesión.
- **E6.7 (hecho, 2026-11-18, pedido por Ari):** una asignación guarda su lista de atletas con desde-hasta, y el coach suma o saca atletas sin terminar el plan (`PUT .../asignaciones/{id}/atletas`). Quien sale conserva sus días anteriores. Un atleta puede estar en varias asignaciones activas: **se elimina D14** y sus dos índices únicos. Al arrancar, `asegurarIndices` copia a `atletas` los miembros del grupo (o el atleta) de cada asignación vieja, una sola vez. **Deploy:** primero el backend (corre la migración) y después la PWA. **`diseno.md`** no tiene asignación por lista de atletas ni la baja de D14: avisar a su sesión.
- **Planes por persona y plantillas (pedido por Ari el 2026-11-18, sin issue):** va a haber planes de un grupo, de una sola persona y plantillas con planes listos. Hoy "para quién" sale de la asignación, o de la elección en Detalles, que no se guarda en el plan. Falta decidir si un plan guarda para quién es antes de asignarlo, qué es una plantilla (un plan sin atletas que se copia, como "Copiar como plan nuevo") y si los valores congelados de E5.16 se recalculan al copiarla o asignarla a otra persona.
- **Datos corporales del atleta** (altura, peso y su seguimiento, cargados por el atleta): van después de
  M1. No tienen diseño. Definir qué datos, si guardan historial, quién los ve y cómo se protegen.
- **Marcas que no son en kilos** (repeticiones máximas en Dominadas; tiempo, velocidad y km máximos en
  Bicicleta): van después de M1, junto con cardio. `diseno.md` solo define marcas de cardio por tiempo o
  distancia. Definir qué marcas tiene cada métrica, en qué unidad y si guardan historial.
- **Factor y kilaje fijo son del coach.** La API de la ficha no se los manda a un atleta. E7 (sesión)
  tiene que resolver desde el servidor los kilos del atleta, sin depender de ese endpoint.
- **Quién lee perfiles.** Decidido: un nivel hacia abajo y nunca hacia arriba; el coach ve a los atletas
  y el atleta solo lo suyo. Falta diseñar qué ven los administradores. Andi y Ari son admin de plataforma,
  y hoy esa marca no da permisos dentro de un club (`permisos.dart`). Como también son coach y atleta en
  Maktub, esto no frena M1.

## Pendientes que salieron de E1

- **Aviso de versión nueva.** El service worker de E0.2 no activa una versión nueva hasta que se
  cierran todas las pestañas y la PWA; recargar no alcanza. Al publicar E1 hubo que desinstalar la
  PWA y limpiar la caché en el teléfono. Hace falta un "Hay una versión nueva, tocá para actualizar".
  Candidato para E7 (modo sin señal), o antes como issue chico.
- **Límite de intentos y `X-Forwarded-For` (E1.8).** Confirmar en los logs de Cloud Run que la última
  dirección es la del cliente y no la de un balanceador de Google; si no, todos comparten el cupo.
- **Renovación simultánea en dos pestañas (E1.12).** Arreglado el caso común (`f7be008`); solo dos
  renovaciones en el mismo instante pueden revocar la sesión. Bloquearlo del todo requiere Web Locks.

## Pedidos sueltos

- **Visibilidad de un plan para otros coaches** (pedido por Ari el 2026-11-19): pasó a ser
  [E8.10](E8.10-visibilidad-del-plan.md), hecho. Falta sumarlo a `docs/diseno.md` desde la otra sesión.
- **Ver lo que se hizo en un día pasado** (salió de la revisión de E8.6, 2026-11-19). Hoy el calendario muestra
  solo el ciclo del plan activo, y el editor de un plan histórico muestra lo planificado, sin kilos. Estado:
  `sin refinar`, fuera de M1.
- **Insignias de las tarjetas en la sesión del día** (pedido por Ari el 2026-11-19). Una tarjeta dice "Hecho"
  apenas se tilda un ejercicio, aunque falte el resto del día. Tiene que reflejar cuánto se hizo de verdad.
  Estado: `en curso` (estado del día por atleta, con progreso: decidido por Ari el 2026-11-21, reemplaza D13).
- **Días marcados como hechos sin hacerlos** (bug, Ari, 2026-11-21). El estado del día es de toda la asignación:
  con una serie de Andi, el día figura hecho también para Ari. Se arregla con el estado por atleta. Estado: `en curso`.
- **Calendario compacto solo con los ejercicios** (Ari, 2026-11-21), sin series ni repeticiones. Estado: `pendiente`.
- **El temporizador saca del modo guiado** (bug, Ari, 2026-11-21). El modo guiado se abre con `push`, y al abrir un
  temporizador `CronoConAtras` hace `go(?crono=1)`, que reemplaza la pila. Estado: `en curso`.
- **Series del modo guiado sin marcar en la sesión del día** (bug, Ari, 2026-11-21). El día figura como hecho, pero
  las viñetas de la sesión del día no se marcan, ni siquiera al recargar. Estado: `en curso`.
- **Tarjetas colapsables en la sesión del día** (Ari, 2026-11-21), para ver todo compacto. Estado: `en curso`.
- **Alta de un club nuevo** (Ari, 2026-11-21). Hoy no existe: los clubes solo se crean con `tool/alta.dart`, y
  `admin_club` da de alta miembros en un club existente. Falta diseño. Estado: `sin refinar`.
