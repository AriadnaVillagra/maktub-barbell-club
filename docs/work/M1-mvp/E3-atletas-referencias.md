---
id: E3
nivel: epica
parent: docs/work/M1-mvp
orden: 3
---

# E3 — Atletas y referencias

## Qué entrega

El coach puede ver y editar, desde la ficha de cada atleta, lo que necesita el cálculo de kilos: sus RMs con historial, el factor de trabajo por ejercicio y los kilajes fijos. Es el F3 recortado, y reemplaza las hojas `RMs` y `PesosAccesorios` de la planilla (M1-D3).

Lo que el diseño no dice y esta épica fija:

- **Un RM nuevo no pisa nada.** Se agrega al historial y el factor de ese ejercicio vuelve a 100 %, en el mismo paso. El coach puede volver a bajarlo después.
- **La vigencia es por fecha**, no por orden de carga. Cargar un RM con fecha pasada no cambia lo que rigió para fechas anteriores a él.
- **El factor también tiene historial**; no se sobrescribe el valor anterior.
- **Permisos**: solo el coach escribe. El atleta ve solamente lo suyo (sus RMs, su factor, sus kilajes), nunca los de otro atleta.
- **Orden**: va después de E2 (los modelos dependen del catálogo) y de E1 (los endpoints necesitan el contexto de club). E4 (reglas de carga) necesita los modelos y la vigencia; E6 (asignación y calendario) necesita el backend de factores y kilajes.

Para modelos, slices y rutas, ver `design.md`, secciones "`maktub_core`" y "Backend: contexto de club y dominio".

## Excluye

- Marcas, ritmos y FC máxima/zonas: los tipos existen en el modelo, pero la app no los carga ni los muestra en M1. Quedan para cuando se haga cardio.
- Referencias *testeadas* creadas por un plan de test: dependen de los planes de test, fuera de M1. En M1 el test de febrero 2026 entra por migración (E8).
- Aplicar el factor y el kilaje fijo al calcular kilos: es E4.
- Alta de atletas y membresías: es E1 (por script en M1).
- Progresión de fuerza y RM estimado: no entran en M1.
- Datos corporales del atleta (altura, peso y su seguimiento): van después de M1 y todavía no tienen diseño.
- Lectura de perfiles por parte de los administradores: sin definir. La regla es un nivel hacia abajo y nunca hacia arriba: el coach ve a los atletas y el atleta solo lo suyo.

## Terminada cuando

- La referencia vigente para una fecha es la última con `fecha ≤` esa fecha, con tests.
- El coach registra un RM nuevo desde la app y se suma al historial; el factor de ese ejercicio queda en 100 %.
- El coach edita factores y kilajes fijos por atleta y ejercicio, y los factores conservan su historial.
- Un atleta que lee sus datos ve lo suyo; si intenta escribir, o leer los de otro atleta, la API lo rechaza.
- Un coach de otro club no ve ni toca estos datos (test de aislamiento por `clubId`).
- Con esto se cumple el criterio 2 de M1 para RMs, factores y kilajes: se editan desde la app sin tocar la base, y las hojas `RMs` y `PesosAccesorios` dejan de hacer falta.

## Issues

| # | Issue | Depende de |
|---|---|---|
| E3.1 | [Modelos de referencia, factor y kilaje, con vigencia](E3.1-modelos-y-vigencia.md) | E2.1 |
| E3.2 | [Backend: registrar un RM nuevo (el factor vuelve a 100 % por regla)](E3.2-registrar-rm.md) | E3.1, E1.10 |
| E3.3 | [Backend: factores con historial y kilajes fijos](E3.3-factores-y-kilajes-api.md) | E3.1, E1.10 |
| E3.4 | [Backend: leer la ficha con permisos por rol](E3.4-lectura-ficha-api.md) | E3.2, E3.3, E1.10, E1.11 |
| E3.5 | [App: ficha del atleta en solo lectura](E3.5-ficha-atleta-lectura.md) | E3.4, E3.7, E1.12 |
| E3.6 | [App: cargar RMs, factores y kilajes](E3.6-ficha-atleta-edicion.md) | E3.2, E3.3, E3.5 |
| E3.7 | [Backend: listar los atletas del club y conocer el id propio](E3.7-listar-atletas-e-id-propio.md) | E3.4, E1.10, E1.11 |
| E3.8 | [App: pestaña Perfil del atleta, en solo lectura](E3.8-app-perfil-del-atleta.md) | E3.7, E3.5 |

Orden de lo que queda: E3.7, E3.5, E3.6, E3.8. E3.7 y E3.8 se agregaron el 2026-11-08, cuando E3.5 no tenía de dónde sacar el id del atleta.

**En paralelo:**
- E3.2 y E3.3 se pueden tomar a la vez.
- E3.1 depende solo de E2.1, así que se puede adelantar, y con él E4.
- E3.6 y E3.8 tocan `features/atletas`: van en orden.
