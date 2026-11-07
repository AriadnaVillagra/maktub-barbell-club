---
id: E6
nivel: epica
parent: docs/work/M1-mvp
orden: 6
---

# E6 — Asignación y calendario

## Qué entrega

El coach asigna un plan al grupo de atletas con una fecha de inicio, y la app muestra qué toca hoy
según esa fecha. Es F7 recortado (etapa 6, tareas 6.1 y 6.2 del plan de M1). Los modelos de grupo y
asignación y su slice de backend están descriptos en el diseño ("`maktub_core`" y "Backend: contexto
de club y dominio"); acá se fija lo que no dicen:

- Una asignación es plan × grupo × fecha de inicio y está **activa o terminada**. Reemplaza la
  estrella de "plan activo" global de la referencia: puede haber asignaciones terminadas, pero
  qué toca hoy sale de la activa.
- La ubicación por fecha (ciclo, semana, día) usa la `UbicacionEnCiclo` que ya existe en
  `maktub_core` (hallazgos, "Etapa 4"); no se reescribe, se conecta con la asignación.
- En la app, la pantalla de asignación y calendario sigue la lógica de las pills de semana y día de
  la referencia: abre en el día que toca por fecha, con ciclo y semana correctos, y deja elegir otro
  día. Los días hechos y pendientes no se marcan acá: dependen de las sesiones, que llegan con E7
  (design.md, D9).
- Orden: arranca después de E5 (6.1 necesita 5.2) y E3 (6.1 necesita 3.2). E7 depende de 6.1 y 6.2.

## Excluye

- Los estados recuperado y falta, y la decisión del coach sobre ellos (F7, resto).
- Pausar asignaciones (F7, resto).
- Cualquier cosa de la sesión y el registro en vivo (E7), incluido marcar días hechos y pendientes
  en el calendario (D9).

## Terminada cuando

- Existen los modelos de grupo y asignación en `maktub_core`, con todos los campos del doc de
  diseño, y su slice de backend filtra por `clubId`.
- El coach puede asignar un plan al grupo con una fecha de inicio, y la asignación queda activa o
  terminada.
- Dada una fecha, el backend devuelve ciclo, semana y día de la asignación activa, con tests.
- Criterio 3 de M1: el coach arma un plan y lo asigna al grupo con una fecha de inicio.
- Criterio 4 de M1: la app abre en el día que toca por fecha, con ciclo y semana correctos, y
  permite elegir otro día.

## Issues

Se completa al derivar los issues de esta épica.
