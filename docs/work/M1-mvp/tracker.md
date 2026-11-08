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
| E3 | [Atletas y referencias](E3-atletas-referencias.md) | en curso | 8 / 8 (probada y revisada; falta mergear a `main`) | — |
| E4 | [Reglas de carga](E4-reglas-de-carga.md) | en curso | 6 / 6 (revisada; falta mergear a `main`) | — |
| E5 | [Editor de plan](E5-editor-de-plan.md) | en curso | 13 / 13 (probada en local; falta mergear a `main`) | — |
| E6 | [Asignación y calendario](E6-asignacion-calendario.md) | pendiente | 0 / 6 | — |
| E7 | [Sesión y registro en vivo](E7-sesion-en-vivo.md) | pendiente | 0 / 13 | — |
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
- **Semilla:** `Cronómetro` es nuevo en la lista base; en producción hay que volver a correr `tool/semilla.dart` (no pisa lo existente).

## Para E6 (decidido el 2026-11-08)

Un plan sin terminar se puede guardar. Por eso **E6.3 tiene que rechazar la asignación de un plan con
problemas de `validatePlan`**, y definir qué pasa si se edita un plan ya asignado y queda incompleto.

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
