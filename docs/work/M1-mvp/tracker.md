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
| E2 | [Catálogo](E2-catalogo.md) | en curso | 10 / 10 (lista para revisión y merge; la semilla se corre en producción después del merge) | — |
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

## Pendientes que salieron de E1

- **Aviso de versión nueva.** El service worker de E0.2 no activa una versión nueva hasta que se
  cierran todas las pestañas y la PWA; recargar no alcanza. Al publicar E1 hubo que desinstalar la
  PWA y limpiar la caché en el teléfono. Hace falta un "Hay una versión nueva, tocá para actualizar".
  Candidato para E7 (modo sin señal), o antes como issue chico.
- **Límite de intentos y `X-Forwarded-For` (E1.8).** Confirmar en los logs de Cloud Run que la última
  dirección es la del cliente y no la de un balanceador de Google; si no, todos comparten el cupo.
- **Renovación simultánea en dos pestañas (E1.12).** Arreglado el caso común (`f7be008`); solo dos
  renovaciones en el mismo instante pueden revocar la sesión. Bloquearlo del todo requiere Web Locks.
