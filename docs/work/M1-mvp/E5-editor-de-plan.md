---
id: E5
nivel: epica
parent: docs/work/M1-mvp
orden: 5
---

# E5 — Editor de plan

## Qué entrega

Las tareas 5.1 a 5.4 de M1 §5 (Etapa 5), con el alcance de design.md §3.1 (modelos del plan), §3.3 (slice de plan) y §3.4 (pantalla del editor de plan). Es F5 más la parte de F6 que M1 conserva, recortadas (M1 §4, fila "F6 (resto)").

Lo que esas secciones no dicen:

- El editor tiene que poder armar la forma de la referencia: modelos de semana `A, B, B, A`, 3 días y 5 bloques (M1 §3, filas de mes modelo y de día fijo). Los bloques son los mismos de la referencia (estiramiento, calentamiento, principal, final, WoD), pero ahora son bloques con nombre y categoría que se eligen a mano.
- Estiramiento y calentamiento se eligen en el editor. En la sesión no se rellena nada: un bloque vacío queda vacío (M1 §3; `diseno.md`, "Modo planificación").
- Los modelos llevan los modos de ejecución completos, pero M1 solo usa el secuencial.
- Guardar un plan es atómico: se guarda entero o no se guarda. Las validaciones de la referencia corren en el modelo (5.1). Al guardar no frenan un plan sin terminar, para no perder el progreso: se exigen al asignarlo (E6).
- Solo el coach crea, lee de forma completa y guarda planes; el contexto de club viene de la E1.
- El ejercicio de cada bloque se elige con el selector filtrado por categoría que entrega la E2 (2.6).

Orden: después de la E2 (5.1 necesita 2.1; 5.4 necesita 2.6) y de la E1 (5.2 necesita el contexto de club, 1.4). La E6 depende de 5.2.

## Excluye

- Atajos del editor (duplicar día, bloque o modelo; generar rampa; copiar series): F6 (resto), fuera de M1.
- Sugerencias de ejercicios y análisis del plan mientras se arma: fuera de M1 (M1 §4).
- Modos de ejecución no secuenciales y el motor de pasos: F10.
- AMRAP, for time, intervalos y resultados de bloques por tiempo: F11.
- Asignar el plan a un grupo y el calendario: E6.
- Importar los planes de la referencia: E8 (tarea 8.2).

## Terminada cuando

- Los modelos del plan existen en `maktub_core` con todos los campos que define `diseno.md` y las validaciones de la referencia, con tests.
- El backend crea, lee, lista y guarda un plan entero; guardar es atómico, solo el coach puede, y un fallo a mitad no deja un plan a medias.
- Un plan de otro club no se ve ni se guarda (aislamiento por `clubId`).
- Desde la app, el coach arma un plan con la forma de la referencia: modelos `A, B, B, A`, 3 días, 5 bloques con nombre y categoría (criterio 3 de M1 §7, en su parte de armado).
- Desde la app, el coach carga en cada bloque ejercicios filtrados por categoría, series una por una (reps, %, kg), con series por defecto al agregar como la referencia, más nota y temporizador.
- Un plan sin terminar se guarda igual y la app muestra lo que le falta; solo un plan sin nombre o con modelos de semana repetidos no se guarda (decidido el 2026-11-08).
- Con la app se puede reescribir a mano el plan de octubre.

## Issues

| # | Issue | Depende de |
|---|---|---|
| E5.1 | [Modelos del plan y validaciones en maktub_core](E5.1-modelos-del-plan.md) | E2.1 |
| E5.2 | [Backend: crear, leer y listar planes](E5.2-backend-crear-leer-listar-plan.md) | E5.1, E1.10, E1.11 |
| E5.3 | [Backend: guardar un plan entero, atómico y validado](E5.3-backend-guardar-plan-atomico.md) | E5.1, E5.2 |
| E5.4 | [Los planes cuentan como uso real de ejercicios y temporizadores](E5.4-planes-como-uso-real.md) | E5.3, E2.4 |
| E5.5 | [App: lista de planes y editor de estructura (modelos de semana, asignación y días)](E5.5-app-estructura-del-plan.md) | E5.1, E5.2, E1.12, E1.14 |
| E5.6 | [App: bloques de cada día con nombre, categoría y temporizador](E5.6-app-bloques-del-dia.md) | E5.5, E2.1, E2.2 |
| E5.7 | [App: agregar prescripciones con ejercicio y series por defecto](E5.7-app-prescripciones-con-series-por-defecto.md) | E5.6, E2.10 |
| E5.8 | [App: editar series una por una, nota y temporizador propio](E5.8-app-series-una-por-una.md) | E5.7 |
| E5.9 | [App: guardar el plan con validación visible](E5.9-app-guardar-plan.md) | E5.3, E5.8 |
| E5.10 | [Modelo del WoD de biblioteca y nota del bloque](E5.10-modelo-wod.md) | E5.1 |
| E5.11 | [Backend: biblioteca de WoDs del club](E5.11-backend-wods.md) | E5.10, E1.10, E1.11 |
| E5.12 | [App: sección WoDs en Preferencias](E5.12-app-wods-preferencias.md) | E5.11, E5.8 |
| E5.13 | [App: agregar un WoD de la biblioteca a un bloque](E5.13-app-agregar-wod-a-bloque.md) | E5.12 |

E5.10 a E5.13 se agregaron el 2026-11-08, tras la prueba del editor: el coach arma WoDs reutilizables en Preferencias. Van en orden.

**En paralelo:**
- La cadena del backend (E5.2 → E5.3 → E5.4) y la de la app (E5.5 → E5.6 → E5.7 → E5.8) avanzan en paralelo una vez que existe E5.2.
- E5.9 une las dos.
- E5.1 depende solo de E2.1 y se puede adelantar.
