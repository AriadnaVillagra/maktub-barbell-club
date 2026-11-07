---
id: E4
nivel: epica
parent: docs/work/M1-mvp
orden: 4
---

# E4 — Reglas de carga

## Qué entrega

Las reglas que convierten lo que prescribe el plan en kilos concretos, puras y en `maktub_core`
(ver "Reglas de carga completas" en el diseño, §3.1). Es la etapa 4 (tarea 4.1) del plan de M1.

- **Objetivo de una serie:** RM × factor de trabajo × % del plan, redondeado al peso cargable más
  cercano según el equipo del club. El factor de trabajo es el de M1-D3, por atleta y ejercicio.
- **Kilaje fijo** para lo que no se calcula por RM, como los accesorios.
- **Barra vacía** para el % más chico de la rampa.
- **Ajuste del día en dos niveles**, aplicado por atleta.
- **Series tocadas:** el ajuste no pisa las editadas a mano.
- **% derivado de kg escritos a mano:** de un peso tipeado a su porcentaje.
- **Verificación contra `reference/`:** casos tomados de la app anterior, con los mismos RMs, que
  tienen que dar los mismos kilos. Con factor aplicado, el kilo cambia según el factor.

Se apoya en lo que ya existe en `reglas/` (`Porcentajes`, `Equipo`, `UbicacionEnCiclo`) y en los
modelos de E3 (tarea 3.1). Como no depende de la app, puede adelantarse. Sobre ella se construyen
E7 (pantalla de sesión) y E8 (verificación de la migración).

## Excluye

- Backend y pantallas: no hay endpoints ni UI en esta épica.
- Cualquier cambio a los modelos de E3; si falta un campo, se plantea ahí.
- Portar la referencia tal cual: se rescatan sus reglas y sus casos, no su código.

## Contingencia

El diseño vale solo si estas reglas reproducen los kilos de la referencia para los mismos RMs
(ver "El diseño vale solo si…", §4.2). Si no los reproducen, la sesión (7.4) y la verificación de
la migración (8.2) no se pueden dar por buenas, y tampoco el criterio de aceptación 5. Por eso
la comparación con `reference/` es parte de la épica y no un agregado posterior.

## Terminada cuando

- [ ] Todas las reglas listadas arriba están en `maktub_core`, sin dependencias de backend ni de
      Flutter, y con tests.
- [ ] Para los casos tomados de `reference/`, los kilos coinciden con los de la referencia con los
      mismos RMs.
- [ ] Con factor de trabajo, el kilo propuesto sale con el factor aplicado (criterio 5).
- [ ] El ajuste del día en dos niveles funciona por atleta y no pisa las series editadas a mano
      (criterio 6).
- [ ] Un % derivado de kg escritos a mano da el porcentaje esperado, y volver a calcular el kilo
      con ese % devuelve el peso tipeado, o el cargable más cercano si no es cargable.
- [ ] `dart test` y `dart analyze` pasan en `maktub_core`.

## Issues

| # | Issue | Depende de |
|---|---|---|
| E4.1 | [Factor de trabajo en el objetivo de una serie](E4.1-factor-de-trabajo.md) | E3.1 |
| E4.2 | [Ajuste del día en dos niveles y series tocadas](E4.2-ajuste-del-dia.md) | E4.1 |
| E4.3 | [Fuente de carga y kilaje fijo](E4.3-fuente-de-carga-y-kilaje-fijo.md) | E4.1, E3.1 |
| E4.4 | [Barra vacía en la rampa](E4.4-barra-vacia-en-rampa.md) | E4.1 |
| E4.5 | [% derivado de kilos escritos a mano](E4.5-pct-derivado-de-kg.md) | E4.1 |
| E4.6 | [Casos de verificación contra la referencia](E4.6-verificacion-contra-referencia.md) | E4.1–E4.5, E8.1 |

**En paralelo:**
- Después de E4.1 se pueden tomar a la vez E4.2, E4.3, E4.4 y E4.5.
- E4.6 necesita el CSV exportado (E8.1, adelantado por D12).
