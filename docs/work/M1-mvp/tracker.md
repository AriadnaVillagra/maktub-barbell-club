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
| E6 | [Asignación y calendario](E6-asignacion-calendario.md) | hecho | 6 / 6 (mergeada a `main`; en producción; el día abre en 1 hasta E7.13) | — |
| E7 | [Sesión y registro en vivo](E7-sesion-en-vivo.md) | en curso | 8 / 13 (E7.1 a E7.5, E7.7, E7.8 y E7.13 hechos; sigue E7.6) | — |
| E8 | [Migración](E8-migracion.md) | en curso | 1 / 6 (E8.1 hecho) | — |
| E9 | [Cierre](E9-cierre.md) | pendiente | 0 / 8 | E9.3, E9.5, E9.7 ← disponibilidad de Andi y Ari (pasos manuales) |

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
- **Pings (E7.6 o E7.10):** E7.5 no configura `pingInterval`, y E7.1 midió con un eco cada 30 s. Hay que definirlos para detectar conexiones muertas y sostener una conexión sin tráfico.

## Para E6 (decidido el 2026-11-08)

Guardar deja un borrador, y publicar (E5.14) exige el plan completo. **E6.3 solo asigna un plan publicado.**
Editar un plan asignado no afecta a los atletas hasta volver a publicar: **E6 y E7 leen siempre la versión
publicada**, nunca el borrador.

## Para E8.2 (decidido el 2026-11-08)

Si un ejercicio de la planilla ya existe en el catálogo base con otra categoría (por ejemplo `Plancha`, accesorio
en la base y calentamiento en la planilla), el importador le suma la categoría de la planilla, sin duplicarlo.
Hasta correr E8.2, los 14 abdominales de calentamiento de la planilla no aparecen en la app.

## D16 aprobada (2026-11-08)

Se elimina "día sin primario". Cada bloque tiene categoría y cada ejercicio pertenece a la categoría de su
bloque. Al agregar un ejercicio (E5.7), los bloques de categoría `primario`, `secundario` y `accesorio`
traen las series por defecto de la referencia y sus descansos (`desc_180`, `desc_120`, `desc_90`); las
demás categorías no traen nada. Las series solo son obligatorias en esas tres categorías, como en la
referencia: E7 tiene que mostrar un ejercicio sin series (por ejemplo, un estiramiento). Excepción a D16
(2026-11-08): un bloque de categoría `wod` acepta ejercicios de cualquier categoría; es la forma de armar un EMOM.
Un bloque de `estiramiento` puede quedar sin ejercicios, con nota o sin ella, sin impedir la publicación. E7 tiene que mostrarlo.

## Pendientes que salieron de E3 (2026-11-08)

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
