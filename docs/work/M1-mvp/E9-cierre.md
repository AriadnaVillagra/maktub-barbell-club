---
id: E9
nivel: epica
parent: docs/work/M1-mvp
orden: 9
---

# E9 — Cierre

## Qué entrega

El paso de M1 de "construido y mergeado por épica" a "usado de verdad en producción". Es la última
épica y depende de todas las demás (E0 a E8). Sigue el orden de "Aceptación y cierre del ítem" del
diseño, que invierte M1 §5 al poner 9.2 antes de 9.1 (D2):

- **Último merge y despliegue (9.2).** Lo que quede en `m1-mvp` entra a `main` (D2: cada épica ya
  se mergeó al cerrarse). Pages publica la PWA desde `main` y el backend se despliega con
  `scripts/desplegar-backend.sh`.
- **Validación de punta a punta de lo publicado.** Cada épica ya validó lo suyo al mergear (D3).
  Acá se prueba todo junto, sobre la PWA publicada.
- **Prueba en el gimnasio (9.1).** Una semana con dos teléfonos y la sesión en vivo. Los problemas
  que aparezcan se corrigen dentro de esta épica.
- **Prueba manual del usuario** sobre la PWA de producción.
- **Corte (8.4, que pasa de E8 a esta épica).** Se congela la planilla (solo lectura), se importa lo
  último con el importador de E8 y se pasa a la app. Se respeta M1 R3: la planilla no se edita
  durante la migración.
- **Ciclo completo (criterio 11 de M1).** Cuatro semanas entrenadas solo con la app.

## Excluye

- Fecha objetivo: no hay (D4).
- Construir o cambiar funcionalidad nueva: solo se corrigen los problemas que salgan de las pruebas.
- El importador, su verificación y el CSV (E8): acá solo se vuelve a correr en el corte.
- Editar `docs/diseno.md` o el resto de lo que M1 deja para la sesión que lo mantiene.

## Terminada cuando

- [ ] `main` tiene todo lo de M1 y está desplegado: PWA en Pages y backend en Cloud Run.
- [ ] Abrir sin señal e instalar la PWA se validaron sobre la PWA publicada.
- [ ] Pasó una semana en el gimnasio con dos teléfonos y la sesión en vivo, y la lista de problemas
  está corregida.
- [ ] El usuario hizo su prueba manual sobre la PWA de producción y la aceptó.
- [ ] La planilla quedó solo de lectura, lo último está importado con el importador de E8 y se
  entrena con la app.
- [ ] Un ciclo completo de 4 semanas se entrenó solo con la app.
- [ ] Con esto se cumplen los 11 criterios de M1 §7 y el ítem queda cerrado.

## Issues

Se completa al derivar los issues de esta épica.
