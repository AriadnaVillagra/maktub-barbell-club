---
id: E7
nivel: epica
parent: docs/work/M1-mvp
orden: 7
---

# E7 — Sesión y registro en vivo

## Qué entrega

Es la etapa 7 del plan de M1 (F8 + F9 + F12 recortados): el día de entrenamiento corre en la app
con dos teléfonos sincronizados. Los modelos, el canal en vivo, el modo sin señal (D8) y las
pantallas están en el diseño (secciones 3.1, 3.3 y 3.4); acá queda solo lo que ese texto no dice.

- **Cierra M1-D2.** Cada serie se registra al marcarla, es idempotente y se difunde a los demás
  dispositivos de la sesión. Recargar o cortar la conexión no pierde marcas, y un dispositivo no pisa
  al otro.
- **Alcance recortado de F8, F9 y F12.** Sesión y registro por serie con todos los campos de 3.6;
  abrir o retomar la sesión del día; pantalla de sesión; canal en vivo; borrador local y cola de
  reintentos; temporizadores y WoD en la sesión. De F12 entra solo el registro por serie.
- **El modo sin señal de esta etapa** es el de los datos del día, la cola y la reconexión. El service
  worker que guarda la app es de E0.
- **Modo guiado "Entrenar"** (design.md D19 y D20), como en `reference/Guia.html`. Se recorre el día
  de a un paso por tarjeta, con simultáneo, por turnos, circuito y cambio de modo en vivo. Al
  terminar se ve el resumen con los tiempos y las diferencias con el plan. Trae a M1 esa parte de F10
  y el registro de la duración de cada bloque. La lista de la sesión queda como vista general.
- **Completa el calendario de E6** (design.md, D9): con las sesiones registradas, el calendario
  marca los días hechos y pendientes.
- **Orden:** va después de E5 (sesión y modelos, necesita 5.1), E3 (3.1), E6 (7.2 necesita 6.1, 7.4
  necesita 6.2) y E4 (7.4 necesita 4.1). El canal en vivo se empieza apenas existe la escritura por
  serie (7.2), sin esperar a la pantalla.
- **Lo que habilita:** el importador de E8 depende de la escritura de la sesión (7.2) y la prueba
  en el gimnasio (9.1) depende de los temporizadores (7.6) y del modo guiado (E7.20, E7.21).

## Excluye

- De F10: reordenar pasos y el modo `timed` en el editor. El motor de pasos, el circuito, los turnos
  y el cambio de modo en vivo **entran** (D19).
- AMRAP, for time, intervalos y resultados de bloques por tiempo: F11.
- RPE o RIR numérico por serie: resto de F12. La nota del plan sigue siendo texto libre.
- El service worker propio que guarda la app: E0.

## Contingencia

Descarga R1 (`docs/milestones/M1-mvp.md`, sección Riesgos; `design.md`, sección 4.2). El diseño vale
solo si Cloud Run sostiene el WebSocket con una sola instancia y reconexión como máximo cada
60 minutos. Si no, hay que repensar el canal en vivo; por eso se arranca temprano. El borrador local
cubre los cortes mientras tanto. Que Cloud Run sostenga la conexión se comprueba en esta épica, no
se da por supuesto.

## Terminada cuando

1. Repetir una escritura de serie no la duplica y dos dispositivos no se pisan.
2. Con dos teléfonos en la misma sesión, una serie marcada en uno aparece en el otro al instante;
   cortar la conexión y reconectar, o recargar, no pierde marcas (criterio 7).
3. La app abre en el día que toca por fecha, con ciclo y semana correctos, y permite elegir otro
   (criterio 4); los kilos coinciden con los de la referencia, con el factor cuando lo hay
   (criterio 5).
4. El ajuste del día funciona por atleta y no pisa las series editadas a mano (criterio 6).
5. Con el modo avión se sigue marcando y al volver la señal se sincroniza (criterio 8).
6. Countdown, EMOM y tabata suenan, vibran y mantienen la pantalla encendida en la PWA instalada, y
   si el dispositivo no lo permite nada falla (criterio 9).
7. La sesión hace todo lo que hacía la pantalla de seguimiento de la referencia, y el calendario
   marca los días hechos y pendientes, como las pills de la referencia.
8. El modo guiado recorre el día bloque por bloque y paso por paso, en simultáneo, por turnos y en
   circuito, y permite cambiar el modo a mitad del bloque sin tocar lo hecho. Cada paso terminado
   queda registrado y se ve en el otro teléfono.
9. Al terminar el modo guiado quedan registrados los tiempos de cada bloque, y el resumen muestra
   los tiempos y las diferencias con el plan.
10. Está comprobado si Cloud Run sostiene el WebSocket en una instancia con reconexión cada 60
   minutos como máximo, o se decidió cómo repensar el canal.

## Issues

| # | Issue | Depende de |
|---|---|---|
| E7.1 | [Verificar que Cloud Run sostiene el WebSocket](E7.1-verificar-websocket-cloud-run.md) | — |
| E7.2 | [Modelos de sesión y registro en `maktub_core`](E7.2-modelos-sesion-y-registro.md) | E3.1, E4.1, E4.5, E5.1 |
| E7.3 | [Backend: abrir o retomar la sesión del día y registrar por serie](E7.3-sesion-del-dia-y-upsert-por-serie.md) | E7.2, E6.3, E6.4, E1.10, E1.11 |
| E7.4 | [Consulta real de uso de registros para la regla de archivar](E7.4-uso-de-registros-para-archivar.md) | E7.3, E2.4 |
| E7.5 | [Canal en vivo: ticket de un solo uso y WebSocket por sesión](E7.5-ticket-y-websocket-por-sesion.md) | E7.1, E7.3 |
| E7.6 | [Canal en vivo: número de secuencia, resincronización y difusión en memoria](E7.6-secuencia-resync-y-difusion.md) | E7.5 |
| E7.7 | [Pantalla de la sesión: día, presentes, atleta y kilos calculados](E7.7-pantalla-sesion-dia-y-kilos.md) | E7.3, E4.1, E4.2, E6.4, E6.6 |
| E7.8 | [Pantalla de la sesión: marcar series, editar kilos y reps, nota y restaurar](E7.8-pantalla-sesion-marcar-y-editar.md) | E7.7, E7.3, E4.5 |
| E7.9 | [Borrador local y cola de reintentos](E7.9-borrador-local-y-cola.md) | E7.8, E0.2 |
| E7.10 | [Cliente del canal en vivo y reconexión](E7.10-cliente-canal-en-vivo.md) | E7.6, E7.8, E7.9 |
| E7.11 | [Temporizadores en la sesión](E7.11-temporizadores-en-sesion.md) | E7.8, E2.2 |
| E7.12 | [WoD en la sesión: nota y temporizador](E7.12-wod-en-sesion.md) | E7.8, E7.11 |
| E7.13 | [Calendario: días hechos y pendientes desde las sesiones](E7.13-calendario-hechos-y-pendientes.md) | E6.6, E7.3 |
| E7.14 | [Backend: kilos propuestos por asignación y fecha, sin sesión abierta](E7.14-kilos-propuestos-sin-sesion.md) | E7.7 |
| E7.15 | [App: datos del día sin señal (precarga y copia local)](E7.15-datos-del-dia-sin-senal.md) | E7.14, E7.9, E6.6 |
| E7.16 | [App: abrir la sesión del día sin señal](E7.16-abrir-sesion-sin-senal.md) | E7.15, E7.10 |
| E7.17 | [Regla de pasos en `maktub_core`](E7.17-regla-de-pasos.md) | E7.2 |
| E7.18 | [Editor de plan: modo de ejecución y modo de atletas del bloque](E7.18-editor-modo-del-bloque.md) | E5.6 |
| E7.19 | [Tiempos de bloque: modelo y backend](E7.19-tiempos-de-bloque.md) | E7.3 |
| E7.20 | [Modo guiado: atletas, bloques y pasos](E7.20-modo-guiado-bloques-y-pasos.md) | E7.17, E7.8, E7.9, E7.11, E7.12 |
| E7.21 | [Modo guiado: tiempos de bloque y resumen del día](E7.21-modo-guiado-resumen-y-tiempos.md) | E7.20, E7.19 |
| E7.22 | [Modo guiado: elegir secuencial o circuito al entrenar](E7.22-modo-guiado-orden-en-vivo.md) | E7.20, E7.21 |
| E7.23 | [Modo guiado: seguir desde lo pendiente o hacer todo de nuevo](E7.23-modo-guiado-seguir-o-empezar-de-cero.md) | E7.21 |
| E7.24 | [Una sola pantalla para el calendario y la sesión del día](E7.24-unificar-calendario-y-sesion.md) | E7.13, E7.20 |
| E7.25 | [Calendario como tablero, con vistas a elección](E7.25-calendario-tablero-con-vistas.md) | E7.24 |

**En paralelo:**
- E7.1 (verificación de R1) no depende de nada y va primero (M1 §6).
- La cadena del canal (E7.5 → E7.6) avanza en paralelo con la de la pantalla (E7.7 → E7.8). E7.4 y E7.13 se pueden tomar apenas existe E7.3.
- Después de E7.8 se pueden tomar a la vez E7.9 y E7.11. E7.10 une el canal con el borrador.
- Modo guiado (agregado el 2026-11-14): E7.17, E7.18 y E7.19 no dependen entre sí y se pueden tomar ya.
  E7.20 espera a E7.12 por el bloque de WoD, después E7.21. E7.22, E7.23 y E7.24 salieron de la prueba en local: E7.22 y E7.23 van juntos (mismos archivos) y E7.24 en paralelo.
- E7.14 a E7.16 (agregados el 2026-11-14) cubren D8 completo: abrir plan, calendario y sesión sin señal. E7.14 se puede tomar ya, en paralelo con E7.10 y E7.12. E7.15 sigue a E7.14, y E7.16 va al final porque une la copia local con la cola y el canal.
