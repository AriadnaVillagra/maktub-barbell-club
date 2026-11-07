---
id: E8
nivel: epica
parent: docs/work/M1-mvp
orden: 8
---

# E8 — Migración de la planilla a la app

## Qué entrega

La app nueva con los datos de la planilla vieja adentro, verificados contra ella. Es la etapa 8 de
M1 (F14), menos el corte. Tiene tres partes: la exportación, el importador y la verificación
(design, "Importador y verificación").

- **Exportación (8.1).** Las hojas de la planilla en CSV, bajadas por el usuario. Tienen que estar
  todas las hojas de `reference/Esquema.gs`.
- **Importador (8.2).** Carga catálogo, RMs, kilajes, planes e historial. El test de febrero 2026
  entra como referencias *testeadas*. Las variantes pasan a modelos de semana y los bloques fijos a
  bloques. Corrige el plan de octubre, que tiene 85 % donde va 80 % (M1-D4). Es idempotente: se
  puede volver a correr en el corte.
- **Verificación (8.3).** Cantidades por hoja, el invariante `rm × pct ≈ kg` y una muestra
  revisada a mano. No puede quedar ninguna diferencia sin explicar.

Además, el importador sirve para probar las etapas 5 a 7 con datos reales (M1 §6). Puede empezar
apenas existan 5.2 y 7.2. Necesita 8.1, la semilla del catálogo de E2 (2.4), 3.2, 5.2 y 7.2, y
alimenta a E9.

## Excluye

El corte (el 8.4 original: congelar la planilla, importar lo último y pasar a la app). La
selección de tareas lo movió a E9, porque el diseño lo ubica después del deploy y las pruebas. Acá
solo queda el importador listo para correrse de nuevo en ese momento.

## Contingencia

El diseño vale solo si el CSV exportado cubre todas las hojas de `reference/Esquema.gs`. Si no las
cubre, la migración queda incompleta y 8.2, 8.3 y el criterio 10 no se pueden dar por buenos.

## Terminada cuando

- Están exportadas todas las hojas de `reference/Esquema.gs`.
- El importador carga catálogo, RMs, kilajes, planes e historial, y correrlo dos veces no duplica
  nada.
- Octubre queda con 80 %, no 85 %.
- La verificación da las mismas cantidades que la planilla en cada hoja, cumple `rm × pct ≈ kg` y
  la muestra revisada a mano coincide.
- No hay diferencias sin explicar (criterio 10: el historial migrado coincide con la planilla, con
  octubre corregido).

## Bloqueos externos

- La exportación a CSV de las hojas la hace el usuario. Bloquea 8.2 y 8.3.
- La planilla no se edita durante la migración (M1 R3), porque es la única fuente del historial.

## Issues

Se completa al derivar los issues de esta épica.
