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
| E1 | [Acceso](E1-acceso.md) | en curso | 12 / 14 (hechos: E1.1–E1.12) | — |
| E2 | [Catálogo](E2-catalogo.md) | pendiente | 0 / 10 | — |
| E3 | [Atletas y referencias](E3-atletas-referencias.md) | pendiente | 0 / 6 | — |
| E4 | [Reglas de carga](E4-reglas-de-carga.md) | pendiente | 0 / 6 | — |
| E5 | [Editor de plan](E5-editor-de-plan.md) | pendiente | 0 / 9 | — |
| E6 | [Asignación y calendario](E6-asignacion-calendario.md) | pendiente | 0 / 6 | — |
| E7 | [Sesión y registro en vivo](E7-sesion-en-vivo.md) | pendiente | 0 / 13 | — |
| E8 | [Migración](E8-migracion.md) | en curso | 1 / 6 (E8.1 hecho) | — |
| E9 | [Cierre](E9-cierre.md) | pendiente | 0 / 8 | E9.3, E9.5, E9.7 ← disponibilidad de Andi y Ari (pasos manuales) |

Ya hecho antes de abrir el ítem: M1 1.1 y 1.2 (`eb26f6e`, `1bcd49f`), mergeados a `main` el
2026-11-07.

## Preguntas abiertas que vienen del diseño

- R4 (`diseno.md` no refleja el recorte de M1): no frena nada. Ver design.md §6.
