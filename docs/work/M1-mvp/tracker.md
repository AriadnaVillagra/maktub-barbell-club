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
| E0 | [Cerrar F0](E0-cerrar-f0.md) | pendiente | 0 / 6 | — |
| E1 | [Acceso](E1-acceso.md) | pendiente | 0 / 14 | E1.1 ← client ID de OAuth con el origen `github.io` (consola de GCP, acción manual del usuario) |
| E2 | [Catálogo](E2-catalogo.md) | pendiente | 0 / 10 | — |
| E3 | [Atletas y referencias](E3-atletas-referencias.md) | pendiente | 0 / 6 | — |
| E4 | [Reglas de carga](E4-reglas-de-carga.md) | pendiente | 0 / 6 | E4.6 ← CSV de la planilla (E8.1, lo exporta el usuario; adelantado por D12) |
| E5 | [Editor de plan](E5-editor-de-plan.md) | sin refinar | — | — |
| E6 | [Asignación y calendario](E6-asignacion-calendario.md) | sin refinar | — | — |
| E7 | [Sesión y registro en vivo](E7-sesion-en-vivo.md) | sin refinar | — | — |
| E8 | [Migración](E8-migracion.md) | sin refinar | — | ← CSV de las hojas de la planilla (lo exporta el usuario) |
| E9 | [Cierre](E9-cierre.md) | sin refinar | — | — |

Ya hecho antes de abrir el ítem: M1 1.1 y 1.2 (`eb26f6e`, `1bcd49f`), mergeados a `main` el
2026-11-07.

## Preguntas abiertas que vienen del diseño

- R4 (`diseno.md` no refleja el recorte de M1): no frena nada. Ver design.md §6.
