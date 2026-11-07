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
- Guardar un plan es atómico: se guarda entero o no se guarda. Las validaciones de la referencia corren en el modelo (5.1) y se repiten al guardar desde la app (5.4).
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
- Un plan inválido no se guarda y la app muestra por qué.
- Con la app se puede reescribir a mano el plan de octubre.

## Issues

Se completa al derivar los issues de esta épica.
