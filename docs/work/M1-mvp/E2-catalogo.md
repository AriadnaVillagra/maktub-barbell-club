---
id: E2
nivel: epica
parent: docs/work/M1-mvp
orden: 2
---

# E2 — Catálogo

## Qué entrega

Las tareas 2.1 a 2.6 de M1 §5 (Etapa 2), con el alcance de design.md §3.1 (modelos del catálogo), §3.3 (slice de catálogo y filtro por `clubId` con la regla de lectura plataforma + club) y §3.5 (semilla del catálogo base).

Lo que esas secciones no dicen:

- Un ejercicio lleva categorías y métricas explícitas: de ahí sale que un ejercicio sin referencia sea accesorio (M1 §3, "Sin referencia = accesorio"). Los WoDs se siembran como bloques de categoría `wod`, no como un modelo aparte.
- El equipo del club pasa de constantes a datos, con el estándar como valor por defecto. Parte de lo que ya existe en `Equipo` y en `Temporizador`/`fasesDe`.
- Archivar en vez de borrar: un ejercicio usado deja de ofrecerse, pero los registros viejos lo siguen resolviendo.
- Corregir un ejercicio base se refleja en todos los clubes, historial incluido (M1-D5).
- La lista de la semilla la aprueba el usuario antes de cargarla. Es un paso de revisión, no un bloqueo.
- El selector de ejercicios por categoría es un componente reutilizable; esta épica lo entrega, la E5 lo usa.

Orden: después de la E1 (necesita el contexto de club, 1.4). La E3 y la E5 dependen de esta.

## Excluye

- UI de grupos musculares, patrones, sugerencias y relaciones, set general del catálogo base y edición del catálogo base desde la app: F2 (resto), fuera de M1 (M1 §4).
- Referencias, factores y kilajes (RMs): E3.
- Reglas de carga que usan el equipo: E4.
- El editor de plan que consume el selector: E5.
- La ejecución de los temporizadores en sesión (sonido, vibración, pantalla encendida): E7.
- El script de alta de usuarios y clubes: E1.

## Terminada cuando

- Los modelos de ejercicio (con todos los campos de `diseno.md` 3.2), categoría, equipo y temporizador con ámbito viajan ida y vuelta por JSON, y sus validaciones puras tienen tests.
- La lectura devuelve los ejercicios base y los del club, filtrables por categoría, y nunca los de otro club (con el test de aislamiento).
- El coach crea, edita y archiva ejercicios, categorías, temporizadores y equipo desde la app, sin tocar la base (criterio 2 de M1 §7).
- Un ejercicio usado se archiva en vez de borrarse y los registros viejos lo siguen resolviendo.
- La semilla corre dos veces sin duplicar y se cargó solo con la lista aprobada por el usuario.
- El selector de ejercicios filtrado por categoría funciona y queda listo para el editor.

## Issues

| # | Issue | Depende de |
|---|---|---|
| E2.1 | [Modelos de ejercicio, categoría, grupo muscular y patrón](E2.1-modelos-ejercicio-categoria.md) | — |
| E2.2 | [Equipo y temporizador como datos](E2.2-equipo-y-temporizador-como-datos.md) | E2.1 |
| E2.3 | [Lectura del catálogo visible](E2.3-lectura-del-catalogo.md) | E1.10, E1.11, E2.1, E2.2 |
| E2.4 | [Escritura: ejercicios y categorías](E2.4-escritura-ejercicios-y-categorias.md) | E1.10, E2.3 |
| E2.5 | [Escritura: temporizadores y equipo](E2.5-escritura-temporizadores-y-equipo.md) | E1.10, E2.2 |
| E2.6 | [Lista propuesta del catálogo base](E2.6-lista-semilla-base.md) | E2.1, E2.2 |
| E2.7 | [Script idempotente de la semilla](E2.7-script-semilla.md) | E2.1, E2.2, E2.6 |
| E2.8 | [App: catálogo y ficha de ejercicio](E2.8-app-catalogo-y-ficha.md) | E1.12, E2.3, E2.4 |
| E2.9 | [App: categorías, temporizadores y equipo](E2.9-app-categorias-temporizadores-equipo.md) | E1.12, E2.4, E2.5 |
| E2.10 | [Selector de ejercicios por categoría](E2.10-selector-de-ejercicios.md) | E1.12, E2.3 |

**En paralelo:**
- E2.1 y E2.2 son la base y no dependen de E1, así que pueden adelantarse mientras avanza E1.
- Después de E2.2 se pueden tomar a la vez E2.3, E2.5 y E2.6.
- E2.7 espera tu aprobación de la lista (E2.6).
- E2.8, E2.9 y E2.10 se pueden tomar a la vez una vez que existen sus escrituras o su lectura.
