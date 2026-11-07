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
- **Completa el calendario de E6** (design.md, D9): con las sesiones registradas, el calendario
  marca los días hechos y pendientes.
- **Orden:** va después de E5 (sesión y modelos, necesita 5.1), E3 (3.1), E6 (7.2 necesita 6.1, 7.4
  necesita 6.2) y E4 (7.4 necesita 4.1). El canal en vivo se empieza apenas existe la escritura por
  serie (7.2), sin esperar a la pantalla.
- **Lo que habilita:** el importador de E8 depende de la escritura de la sesión (7.2) y la prueba
  en el gimnasio (9.1) depende de los temporizadores (7.6).

## Excluye

- Motor de pasos, modo circuito, modo por turnos y cambio de modo en vivo: F10.
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
8. Está comprobado si Cloud Run sostiene el WebSocket en una instancia con reconexión cada 60
   minutos como máximo, o se decidió cómo repensar el canal.

## Issues

Se completa al derivar los issues de esta épica.
